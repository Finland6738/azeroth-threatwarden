-- RaidOverlay: marks over the game's own party and raid frames (M8.3, SPEC-07 §3.3, §3.5; ui-style §3.8; ADR 0021;
-- SPEC-09 Q29, R14). Threatwarden's own. Lua 5.1; ordinary unprotected frames of the addon only.
--
-- The game's Compact Raid Frames are secure code and are NEVER touched: no hook, no anchor, no parent, no field, no
-- texture, no method call. Core/Compat.lua (Compat.RaidFrames.Collect) finds them by name and reads their unit and
-- rectangle, out of combat only; this file only copies those rectangles into its own detached overlay:
--   * `AzerothThreatwardenRaidOverlay`, a frame of the addon on UIParent covering it, never protected, never taking the
--     mouse, with a pool of up to 40 marks made the first time they are needed, each placed at absolute coordinates of
--     the overlay (never relative to a frame of the game);
--   * a mark is a 2 px border in the state's token (alpha 0.9) around the copied rectangle and the small state badge
--     (icon and word) at the middle of its top edge: only for WARNING, DANGER and the unit that holds the mob without
--     being a tank; SAFE and UNKNOWN show nothing; nothing in the demo (invented states on real frames would be false).
--     Each mark has a border per state, painted once; a mark appears and goes at once, without a fade;
--   * the positions are copied at COMBAT_ENDED, GROUP_CHANGED and GROUP_ROSTER_UPDATE out of combat,
--     COMPACT_UNIT_FRAME_PROFILES_LOADED, DISPLAY_CHANGED, ENTERING_WORLD, when the setting is turned on, and every
--     REFRESH seconds out of combat while the player is in a group (a tick of Core/Scheduler.lua at 1 Hz);
--   * in combat the positions stay; only the colour, the word and whether a mark shows change, after THREAT_UPDATED and
--     only for the marks that change. A roster change (GROUP_ROSTER_UPDATE) or a change of the screen in combat may
--     have moved the frames: every mark hides until the fight ends, and /atw debug counts it.
-- A mark is chosen from the unit token of its frame and the rows of the monitor (Data/ThreatModel.lua, Data/ThreatState.lua):
-- a frame whose unit is not on the list has none. The player's own raid frame (raidN of Compat.Group.RaidIndex) is the
-- row "player".
--
-- Active only while the `heatmap` switch (Core/Features.lua) and `account.settings.heatmap.raidFrames` are both on:
-- otherwise no game event is registered, no frame is made, the blocked and forbidden actions are not counted
-- (Core/Diagnostics.lua) and the tick does not run. The debug section *Heatmap* exists with the switch on.
-- Bus: emits RAID_FRAMES_READ(count, state) when a copy finds a different number of frames or capability state.
local ADDON_NAME, ns = ...
ns = ns or {}
ns.modules = ns.modules or {}

local RaidOverlay = {}
ns.RaidOverlay, ns.modules.RaidOverlay = RaidOverlay, RaidOverlay

local Compat, Theme, Widgets = ns.Compat, ns.Theme, ns.Widgets
local type, pairs, max = type, pairs, math.max

RaidOverlay.NAME = "AzerothThreatwardenRaidOverlay"
RaidOverlay.REFRESH = 2          -- seconds between two copies of the positions out of combat, in a group
RaidOverlay.TICK = "raidoverlay" -- the name of its tick in Core/Scheduler.lua (1 Hz, out of combat only)
RaidOverlay.BORDER = 2           -- points of the border of a mark
RaidOverlay.BORDER_ALPHA = 0.9
RaidOverlay.MAX = Compat.RaidFrames.MAX
local RAID_PATH = "account.settings.heatmap.raidFrames"

RaidOverlay.enabled = false      -- the switch was on at login
RaidOverlay.active = false       -- switch and setting on: events registered
RaidOverlay.suspended = false    -- marks hidden after a roster change in combat, until it ends
RaidOverlay.suspensions = 0      -- how many times since the addon was loaded
RaidOverlay.copies = 0
RaidOverlay.copiedAt = nil       -- Compat.Now() of the last copy
RaidOverlay.count, RaidOverlay.state = 0, nil   -- frames shown by the game at the last copy, and the capability
RaidOverlay.shown = 0            -- marks on screen

local places = { count = 0 }     -- Compat.RaidFrames.Collect's output, reused
local placeOf = {}               -- row unit token -> index of its place
local placeUnit = {}             -- index -> the row unit token of that place
local wanted = {}                -- index -> "warning" | "danger" | nil, reused by Paint
local marks = {}                 -- the pool
local overlay

local function switchOn() return ns.Features ~= nil and ns.Features.On("heatmap") end
local function settingOn()
	local v = ns.Config and ns.Config.db and ns.Config:Get(RAID_PATH)
	if type(v) ~= "boolean" then v = ns.Config.HEATMAP_DEFAULTS.raidFrames end
	return v == true
end
local function inCombat() return (ns.addon ~= nil and ns.addon.inCombat == true) or Compat.InCombatLockdown() end
local function inDemo() return ns.Demo ~= nil and ns.Demo.IsActive ~= nil and ns.Demo.IsActive() == true end
local function emit(event, ...) if ns.Bus then ns.Bus.Emit(event, ...) end end

function RaidOverlay.Enabled() return RaidOverlay.enabled end
function RaidOverlay.Active() return RaidOverlay.active end
function RaidOverlay.Frame() return overlay end
function RaidOverlay.Marks() return marks end

---------------------------------------------------------------------------------------------------------------------
-- The frames of the addon
---------------------------------------------------------------------------------------------------------------------
local function edge(holder, a, b, horizontal, token)
	local tex = holder:CreateTexture(nil, "OVERLAY")
	tex:SetPoint(a, holder, a, 0, 0)
	tex:SetPoint(b, holder, b, 0, 0)
	if horizontal then tex:SetHeight(RaidOverlay.BORDER) else tex:SetWidth(RaidOverlay.BORDER) end
	Theme.Crisp(tex)
	Theme.Fill(tex, token, RaidOverlay.BORDER_ALPHA)
	return tex
end

-- The border of one state: four edges of 2 px in its token, on a frame of the mark that covers it. Each mark has one
-- per state it can show, painted once (a change of state shows the other one: nothing is recoloured in combat).
local function border(mark, state)
	local holder = CreateFrame("Frame", nil, mark)
	holder:SetAllPoints(mark)
	holder:EnableMouse(false)
	local token = Theme.State(state).token
	holder.edges = {
		edge(holder, "TOPLEFT", "TOPRIGHT", true, token), edge(holder, "BOTTOMLEFT", "BOTTOMRIGHT", true, token),
		edge(holder, "TOPLEFT", "BOTTOMLEFT", false, token), edge(holder, "TOPRIGHT", "BOTTOMRIGHT", false, token),
	}
	holder:Hide()
	return holder
end

local function ensureOverlay()
	if overlay then return overlay end
	local parent = Compat.UIParent()
	overlay = CreateFrame("Frame", RaidOverlay.NAME, parent)
	overlay:SetAllPoints(parent)
	overlay:SetFrameStrata("MEDIUM")
	overlay:EnableMouse(false)
	return overlay
end

local function newMark(i)
	local mark = CreateFrame("Frame", nil, ensureOverlay())
	mark:EnableMouse(false)
	mark.borders = { warning = border(mark, "warning"), danger = border(mark, "danger") }
	mark.badge = Widgets.StateBadge(mark, { small = true, state = "warning" })
	mark.badge:EnableMouse(false)
	mark.badge:SetPoint("CENTER", mark, "TOP", 0, 0)
	mark.index = i
	mark:Hide()
	marks[i] = mark
	return mark
end

local function paintMark(mark, state)
	if mark.state == state then return false end
	local was = mark.state
	mark.state = state
	if not state then
		mark.borders[was]:Hide()
		mark:Hide()
		RaidOverlay.shown = RaidOverlay.shown - 1
		return true
	end
	if was then mark.borders[was]:Hide() end
	mark.borders[state]:Show()
	mark.badge:SetState(state)
	if not was then   -- at once, without a fade: nothing moves over the game's frames (and nothing is allocated)
		RaidOverlay.shown = RaidOverlay.shown + 1
		mark:Show()
	end
	return true
end

-- Hides every mark (the overlay stays, empty).
function RaidOverlay.HideAll()
	for i = 1, #marks do paintMark(marks[i], nil) end
	RaidOverlay.shown = 0
end

---------------------------------------------------------------------------------------------------------------------
-- Marks
---------------------------------------------------------------------------------------------------------------------
-- What a row asks for on its frame: "danger", "warning" or nil (SAFE, UNKNOWN, not on the list).
function RaidOverlay.MarkOf(row)
	if not row or not row.present then return nil end
	local state = row.state
	if state == nil or state == "UNKNOWN" then return nil end
	if state == "DANGER" or (row.isHolder and not row.isTank) then return "danger" end
	if state == "WARNING" then return "warning" end
	return nil
end
local markOf = RaidOverlay.MarkOf

-- Brings the marks up to date with the rows of the monitor; only the marks that change are touched. Allocation-free.
function RaidOverlay.Paint()
	if not RaidOverlay.active or not overlay then return 0 end
	local count = places.count
	if RaidOverlay.suspended or inDemo() then
		if RaidOverlay.shown > 0 then RaidOverlay.HideAll() end
		return 0
	end
	for i = 1, count do wanted[i] = nil end
	local Model = ns.ThreatModel
	if Model and ns.TargetTracker and Model.mobKey ~= nil and Model.mobKey == ns.TargetTracker.mobKey then
		local rows = Model.rows
		for r = 1, Model.count do
			local row = rows[r]
			local i = placeOf[row.record.unitToken or ""]
			if i then wanted[i] = markOf(row) end
		end
	end
	local changed = 0
	for i = 1, count do
		local mark = marks[i]
		local state = wanted[i]
		if mark and paintMark(mark, state) then changed = changed + 1 end
	end
	return changed
end

---------------------------------------------------------------------------------------------------------------------
-- Copying the positions (out of combat only)
---------------------------------------------------------------------------------------------------------------------
-- The row token of a frame's unit: the player's own raidN is "player".
local function rowToken(unit, me)
	if me and unit == me then return "player" end
	return unit
end

-- Copies the rectangles of the game's frames into the marks. Returns true when it copied (false in combat).
function RaidOverlay.Copy()
	if not RaidOverlay.active then return false end
	if inCombat() then return false end
	local count, state = Compat.RaidFrames.Collect(places)
	if state == "combat" then return false end
	RaidOverlay.copies = RaidOverlay.copies + 1
	RaidOverlay.copiedAt = Compat.Now()
	local resumed = RaidOverlay.suspended
	RaidOverlay.suspended = false
	local index = Compat.Group.RaidIndex()
	local me = index and ("raid" .. index) or nil
	for unit in pairs(placeOf) do placeOf[unit] = nil end
	ensureOverlay()
	overlay:Show()
	for i = 1, count do
		local place = places[i]
		local mark = marks[i] or newMark(i)
		local token = rowToken(place.unit, me)
		placeUnit[i] = token
		if placeOf[token] == nil then placeOf[token] = i end
		mark:ClearAllPoints()
		mark:SetPoint("BOTTOMLEFT", overlay, "BOTTOMLEFT", place.left, place.bottom)
		mark:SetSize(place.width, place.height)
	end
	for i = count + 1, #marks do
		placeUnit[i] = nil
		paintMark(marks[i], nil)
	end
	if resumed or count ~= RaidOverlay.count or state ~= RaidOverlay.state then
		RaidOverlay.count, RaidOverlay.state = count, state
		emit("RAID_FRAMES_READ", count, state)
	end
	RaidOverlay.Paint()
	return true
end

-- A roster or screen change in combat: the frames may have moved, so every mark hides until the fight ends.
function RaidOverlay.Suspend()
	if not RaidOverlay.active then return false end
	if not RaidOverlay.suspended then
		RaidOverlay.suspended = true
		RaidOverlay.suspensions = RaidOverlay.suspensions + 1
		emit("RAID_FRAMES_READ", RaidOverlay.count, RaidOverlay.state)
	end
	RaidOverlay.HideAll()
	return true
end

-- A change that moves frames: copied again out of combat, hidden in combat.
local function moved()
	if not RaidOverlay.active then return end
	if inCombat() then RaidOverlay.Suspend() else RaidOverlay.Copy() end
end

---------------------------------------------------------------------------------------------------------------------
-- The tick and the switch
---------------------------------------------------------------------------------------------------------------------
local function tick()
	if not RaidOverlay.active or inCombat() then return end
	local now = Compat.Now()
	if RaidOverlay.copiedAt == nil or now - RaidOverlay.copiedAt >= RaidOverlay.REFRESH - 1e-6 then RaidOverlay.Copy() end
end

-- Runs the tick while active, out of combat and in a group; stops it otherwise.
local function schedule()
	local Scheduler = ns.Scheduler
	if not Scheduler then return end
	local want = RaidOverlay.active and not (ns.addon and ns.addon.inCombat) and Compat.Group.InGroup()
	if want then
		if not Scheduler.IsRunning(RaidOverlay.TICK) then Scheduler.Start(RaidOverlay.TICK, 1, tick) end
	elseif Scheduler.IsRunning(RaidOverlay.TICK) then
		Scheduler.Stop(RaidOverlay.TICK)
	end
end

local events = {}
function events.GROUP_ROSTER_UPDATE() moved(); schedule() end
function events.COMPACT_UNIT_FRAME_PROFILES_LOADED() moved() end
local function onEvent(event, ...)
	local handler = events[event]
	if handler then handler(event, ...) end
end

local function activate()
	local AceEvent = LibStub and LibStub("AceEvent-3.0", true)
	if not AceEvent then return false end
	if not RaidOverlay.embedded then
		AceEvent:Embed(RaidOverlay)
		RaidOverlay.embedded = true
	end
	RaidOverlay:RegisterEvent("GROUP_ROSTER_UPDATE", onEvent)                 -- PartyInfo in the dump
	RaidOverlay:RegisterEvent("COMPACT_UNIT_FRAME_PROFILES_LOADED", onEvent)  -- CompactUnitFrames in the dump
	if ns.Diagnostics then ns.Diagnostics.WatchActions(true) end
	RaidOverlay.active = true
	RaidOverlay.Copy()
	schedule()
	return true
end

local function deactivate()
	if RaidOverlay.embedded then
		RaidOverlay:UnregisterEvent("GROUP_ROSTER_UPDATE")
		RaidOverlay:UnregisterEvent("COMPACT_UNIT_FRAME_PROFILES_LOADED")
	end
	if ns.Diagnostics then ns.Diagnostics.WatchActions(false) end
	RaidOverlay.active = false
	schedule()
	RaidOverlay.HideAll()
	if overlay then overlay:Hide() end
	for unit in pairs(placeOf) do placeOf[unit] = nil end
	places.count = 0
end

-- Turns the overlay on or off to match the switch and the setting. Returns whether it is active.
function RaidOverlay.Refresh()
	local want = RaidOverlay.enabled and switchOn() and settingOn()
	if want and not RaidOverlay.active then activate()
	elseif not want and RaidOverlay.active then deactivate() end
	return RaidOverlay.active
end

-- PLAYER_LOGIN (Core/Init.lua). Nothing with the switch off.
function RaidOverlay.Enable()
	if RaidOverlay.enabled or not switchOn() then return false end
	RaidOverlay.enabled = true
	if ns.addon and ns.addon.AddDebugSection then ns.addon:AddDebugSection("Heatmap", RaidOverlay.DebugLines) end
	RaidOverlay.Refresh()
	return true
end

-- What the *Heatmap* card says under the raid frame switch: nil (nothing to say), or a key of Locales/ and a number.
function RaidOverlay.Status()
	if not RaidOverlay.active or RaidOverlay.state == nil then return nil end
	if RaidOverlay.state == "restricted" then return "HEATMAP_RAID_RESTRICTED" end
	if RaidOverlay.state == "missing" or RaidOverlay.count == 0 then return "HEATMAP_RAID_NOT_SHOWN" end
	return "HEATMAP_RAID_FOUND", RaidOverlay.count
end

if ns.Bus then
	local Bus = ns.Bus
	Bus.On("THREAT_UPDATED", function() if RaidOverlay.active then RaidOverlay.Paint() end end)
	Bus.On("DEMO_CHANGED", function() if RaidOverlay.active then RaidOverlay.Paint() end end)
	Bus.On("COMBAT_STARTED", function() if RaidOverlay.active then schedule() end end)
	Bus.On("COMBAT_ENDED", function()
		if not RaidOverlay.active then return end
		RaidOverlay.Copy()
		schedule()
	end)
	Bus.On("GROUP_CHANGED", function() if RaidOverlay.active then moved(); schedule() end end)
	Bus.On("DISPLAY_CHANGED", moved)
	Bus.On("ENTERING_WORLD", moved)
	Bus.On("CONFIG_LOADED", function() if RaidOverlay.enabled then RaidOverlay.Refresh() end end)
	Bus.On("CONFIG_CHANGED", function(path)
		if RaidOverlay.enabled and (path == RAID_PATH or path == "account.settings") then RaidOverlay.Refresh() end
	end)
end
if ns.OnEnable then ns.OnEnable(RaidOverlay.Enable) end

-- /atw debug, section *Heatmap* (English, numbers and fixed words; never a name).
function RaidOverlay.DebugLines()
	local s = Compat.RaidFrames.stats
	local Heatmap = ns.Heatmap
	local age = RaidOverlay.copiedAt and ("%.1f s ago"):format(max(Compat.Now() - RaidOverlay.copiedAt, 0)) or "never"
	local lines = {
		"switch: " .. (switchOn() and "on" or "off"),
		("monitor rows: %s; raid frame marks: %s (%s)"):format(Heatmap and Heatmap.RowsOn() and "on" or "off",
			settingOn() and "on" or "off", RaidOverlay.active and "active" or "inactive"),
		"capability raidFrames: " .. tostring((Compat.Capability("raidFrames"))),
		("frames found by name: party %d, raid %d, group %d; shown %d; failed reads %d"):format(s.party, s.raid,
			s.group, s.visible, s.failed),
		("positions copied %d times, last %s; refused in combat %d"):format(RaidOverlay.copies, age, s.refused),
		("marks shown: %d (%d made)"):format(RaidOverlay.shown, #marks),
		("marks hidden for a roster change in combat: %s (%d times)"):format(RaidOverlay.suspended and "yes" or "no",
			RaidOverlay.suspensions),
	}
	local actions = ns.Diagnostics and ns.Diagnostics.ActionLines and ns.Diagnostics.ActionLines() or {}
	for i = 1, #actions do lines[#lines + 1] = actions[i] end
	return lines
end

if ns.addon then ns.addon.RaidOverlay = RaidOverlay end
