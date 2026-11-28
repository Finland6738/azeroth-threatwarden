-- The heatmap (M8.3, SPEC-07 §3, §6; ui-style §3.8; ADR 0021; SPEC-09 Q29): the heat step of a monitor row for every
-- state and mode, the tank, the holder that is not a tank, the hysteresis of the borders, at most one change a second
-- but DANGER at once, never heat on UNKNOWN; the overlay over the game's raid frames on the mock's frames
-- (Tests/mock/55_raidframes.lua), whose log of every forbidden touch must stay empty: positions copied only out of
-- combat, marks only for WARNING, DANGER and the aggro of a non-tank, all hidden after a roster change in combat, no
-- frames, secret or failing frames, the mouse never taken, the demo, and with the switch or the settings off nothing
-- made or registered.

local ON = { monitor = true, multitarget = false, heatmap = true }
before_boot(function(M) M.features = ON end)

local function ns() return Mock.ns end
local function H() return Mock.ns.Heatmap end
local function O() return Mock.ns.RaidOverlay end
local function V() return Mock.ns.ThreatList.view end
local function C() return Mock.ns.Config end
local function set(key, value) truthy(C():Set("account.settings.heatmap." .. key, value), key) end

local function forbidden() return Mock.raidFrames.log end

local function newPull(def)
	def = def or {}
	return Fight.new{
		player = def.player or { class = "MAGE", role = "DAMAGER", ranged = true },
		party = def.party or {
			{ key = "tank", role = "TANK", name = "Bram" },
			{ key = "healer", class = "PRIEST", role = "HEALER", name = "Sela" },
			{ key = "rogue", class = "ROGUE", role = "DAMAGER", name = "Kor" },
		},
		raid = def.raid,
		mobs = { { key = "boss", tokens = { "target" }, classification = "worldboss", name = "Gorrak" } },
	}
end

-- The tank holds the boss; the player, the rogue and the healer at fixed scaled percentages.
local function partyPull(me, rogue, healer, outcome)
	local pull = newPull()
	if outcome then pull:outcome(outcome) end
	pull:at(0):start():threat("boss", "tank", 1000)
		:threat("boss", "player", { raw = 500, scaled = me or 40 })
		:threat("boss", "rogue", { raw = 300, scaled = rogue or 20 })
		:threat("boss", "healer", { raw = 100, scaled = healer or 8 })
	return pull
end

local function widget(token)
	for _, w in ipairs(V().widgets) do
		if w:IsShown() and w.data and w.data.record.unitToken == token then return w end
	end
end

-- The alpha a row's heat ends at (the fades finished).
local function heat(token)
	Mock.FinishAnimations()
	local w = widget(token)
	if not w.heat then return nil end
	return w.heat:GetAlpha()
end

-- A row of Data/ThreatModel.lua as Heatmap.Step reads it.
local function row(state, mode, p, extra)
	local r = { state = state, record = { mode = mode or "values", scaledPercent = p, unitKey = "u1" } }
	for k, v in pairs(extra or {}) do r[k] = v end
	return r
end

describe("the heat step of a row (SPEC-07 §3.2)", function()
	it("has the five alphas and the constants of the specification", function()
		deepEq({ H().ALPHA[0], H().ALPHA[1], H().ALPHA[2], H().ALPHA[3], H().ALPHA[4] }, { 0, 0.06, 0.10, 0.14, 0.18 })
		eq(H().HYSTERESIS, 2)
		eq(H().HOLD, 1)
		eq(H().SAFE_FROM, 50)
	end)

	it("in values: SAFE below and from 50 %, WARNING below and from the middle of the thresholds, DANGER", function()
		local warning, danger = ns().ThreatState.Thresholds()
		eq(warning, 82) eq(danger, 91)
		eq(H().Step(row("SAFE", "values", 10)), 0)
		eq(H().Step(row("SAFE", "values", 49.9)), 0)
		eq(H().Step(row("SAFE", "values", 50)), 1)
		eq(H().Step(row("SAFE", "values", 81)), 1)
		eq(H().Step(row("WARNING", "values", 82)), 2)
		eq(H().Step(row("WARNING", "values", 86.4)), 2)
		eq(H().Step(row("WARNING", "values", 86.5)), 3, "the middle of 82 and 91")
		eq(H().Step(row("WARNING", "values", 90)), 3)
		eq(H().Step(row("WARNING", "values", 70, { stateReason = "predicted" })), 2, "a predicted WARNING")
		eq(H().Step(row("WARNING", "values", nil)), 2, "WARNING without a value")
		eq(H().Step(row("SAFE", "values", nil)), 0, "SAFE without a value")
		eq(H().Step(row("DANGER", "values", 95)), 4)
	end)

	it("in state only: SAFE none, WARNING 2, DANGER 4, whatever the numbers", function()
		eq(H().Step(row("SAFE", "state", 70)), 0)
		eq(H().Step(row("WARNING", "state")), 2)
		eq(H().Step(row("DANGER", "state")), 4)
	end)

	it("never heats UNKNOWN or a row off the list, in any mode", function()
		for _, mode in ipairs({ "values", "state", "none" }) do
			eq(H().Step(row("UNKNOWN", mode, 99)), 0, mode)
			eq(H().Step(row(nil, mode, 99)), 0, mode)
		end
		eq(H().Step(row("UNKNOWN", "values", 99, { isHolder = true, isTank = false })), 0, "not even a holder")
	end)

	it("the tank holding the mob compares the second, s = 100 - margin", function()
		local tank = { isHolder = true, isTank = true }
		eq(H().Step(row("SAFE", "values", 100, { isHolder = true, isTank = true, margin = 60 })), 0, "s = 40")
		eq(H().Step(row("SAFE", "values", 100, { isHolder = true, isTank = true, margin = 45 })), 1, "s = 55")
		eq(H().Step(row("WARNING", "values", 100, { isHolder = true, isTank = true, margin = 16 })), 2, "s = 84")
		eq(H().Step(row("WARNING", "values", 100, { isHolder = true, isTank = true, margin = 12 })), 3, "s = 88")
		eq(H().Step(row("SAFE", "values", 100, tank)), 0, "alone: no second")
	end)

	it("the unit that holds the mob without being a tank has the full heat", function()
		eq(H().Step(row("DANGER", "values", 100, { isHolder = true, isTank = false, stateReason = "aggro" })), 4)
		eq(H().Step(row("WARNING", "state", nil, { isHolder = true, isTank = false })), 4)
	end)

	it("keeps a higher step 2 points below its border inside one state", function()
		eq(H().Step(row("SAFE", "values", 48.5), 1), 1)
		eq(H().Step(row("SAFE", "values", 48), 1), 1)
		eq(H().Step(row("SAFE", "values", 47.9), 1), 0)
		eq(H().Step(row("SAFE", "values", 49), 0), 0, "rising needs the border itself")
		eq(H().Step(row("WARNING", "values", 85), 3), 3)
		eq(H().Step(row("WARNING", "values", 84.4), 3), 2)
		eq(H().Step(row("WARNING", "values", 86), 2), 2)
	end)
end)

describe("the heat over time (Heatmap.For)", function()
	it("changes step at most once a second inside a state", function()
		local r = row("SAFE", "values", 40)
		eq(H().For(r, 10), 0)
		r.record.scaledPercent = 60
		eq(H().For(r, 10.5), 0, "held")
		eq(H().For(r, 11), 1, "a second later")
		r.record.scaledPercent = 30
		eq(H().For(r, 11.2), 1, "held again")
		eq(H().For(r, 12.1), 0)
	end)

	it("follows a change of state at once: DANGER and UNKNOWN are never late", function()
		local r = row("SAFE", "values", 60)
		eq(H().For(r, 10), 1)
		r.state, r.record.scaledPercent = "DANGER", 95
		eq(H().For(r, 10.1), 4, "DANGER at once")
		r.state = "UNKNOWN"
		eq(H().For(r, 10.2), 0, "UNKNOWN at once")
		r.state, r.record.scaledPercent = "WARNING", 88
		eq(H().For(r, 10.3), 3)
	end)

	it("starts again for another unit in the same place", function()
		local r = row("WARNING", "values", 88)
		eq(H().For(r, 10), 3)
		r.record.unitKey, r.record.scaledPercent = "u2", 83
		eq(H().For(r, 10.1), 2)
	end)
end)

describe("the heat of the monitor rows", function()
	it("paints each row in its state's colour at the alpha of its step", function()
		partyPull(84, 97, 60):to(1)
		eq(heat("player"), 0.10, "WARNING below the middle")
		eq(heat("party3"), 0.18, "DANGER")
		eq(heat("party1"), 0.18, "the tank, DANGER on its margin of 3")
		eq(heat("party2"), 0.06, "SAFE from 50 %")
		local tex = widget("party3").heat
		local r, g, b = Mock.ns.Theme.Color("state-danger")
		local c = tex:GetTexture()
		near(c[1], r, 1e-6) near(c[2], g, 1e-6) near(c[3], b, 1e-6)
		eq(c[4], 1, "the alpha is the region's, not the colour's")
		eq(tex._layer, "BACKGROUND", "under the text, the bar and the badge")
		truthy(widget("player").badge:IsShown(), "the badge stays")
		eq(widget("player").badge:GetState(), "warning")
	end)

	it("puts nothing on UNKNOWN rows", function()
		local pull = partyPull(84, 97, 60, "none")
		pull:to(1)
		for _, token in ipairs({ "player", "party1", "party2", "party3" }) do
			local w = widget(token)
			if w then
				eq(w.data.state, "UNKNOWN", token)
				eq(w.heat and w.heat:GetAlpha() or 0, 0, token)
			end
		end
	end)

	it("in state only gives SAFE nothing, WARNING the second step and DANGER the full heat", function()
		local pull = partyPull(84, 97, 8, "state")
		pull:at(0.5):aggro("boss", "rogue")
		pull:to(1.5)
		local seen = {}
		for _, token in ipairs({ "player", "party1", "party2", "party3" }) do
			local w = widget(token)
			local expected = ({ SAFE = 0, WARNING = 0.10, DANGER = 0.18 })[w.data.state]
			eq(heat(token), expected, token .. " " .. w.data.state)
			seen[w.data.state] = true
		end
		local kinds = 0
		for _ in pairs(seen) do kinds = kinds + 1 end
		truthy(kinds >= 2, "more than one state on screen")
	end)

	it("fades between steps of the same unit and never flashes", function()
		local pull = partyPull(60, 20, 8)
		pull:to(1)
		eq(heat("player"), 0.06)
		pull:at(2):threat("boss", "player", { raw = 900, scaled = 95 })
		pull:to(2.5)
		local w = widget("player")
		eq(w.heatAlpha, 0.18)
		local fading = false
		for _, g in ipairs(Mock.animGroups) do if g._parent == w.heat and g:IsPlaying() then fading = true end end
		truthy(fading, "a fade of 120 ms is playing")
		eq(heat("player"), 0.18)
	end)

	it("follows the setting without /reload, and is not made with the setting off", function()
		partyPull(84, 97, 60):to(1)
		set("rows", false)
		eq(heat("player"), 0)
		falsy(H().RowsOn())
		set("rows", true)
		truthy(H().RowsOn())
		eq(heat("player"), 0.10)
		boot(function(M)
			M.features = ON
			M.saved = { AzerothThreatwardenDB = nil }
		end)
		set("rows", false)
		partyPull(84, 97, 60):to(1)
		isNil(widget("player").heat, "no texture made")
	end)

	it("is shown in the demo", function()
		Mock.Slash("/atw demo")
		local any = false
		for _ = 1, 40 do
			Mock.Advance(0.5)
			for _, w in ipairs(V().widgets) do
				if w:IsShown() and w.heat and w.heatAlpha > 0 then any = true end
			end
			if any then break end
		end
		truthy(any, "the invented rows have heat")
		Mock.Slash("/atw demo")
	end)
end)

describe("with the heatmap switch off", function()
	before_boot(function(M)
		M.features = { monitor = true, multitarget = false, heatmap = false }
		M.raidFrames.Party({ "player", "party1", "party2", "party3" })
	end)

	it("makes no heat and no overlay, registers nothing and has no debug section, even with the settings on", function()
		falsy(H().RowsOn())
		set("raidFrames", true)
		partyPull(84, 97, 60):to(1)
		isNil(widget("player").heat)
		falsy(O().Enabled())
		falsy(O().Active())
		isNil(rawget(_G, "AzerothThreatwardenRaidOverlay"))
		isNil(O().Frame())
		eq(Mock.Listeners("COMPACT_UNIT_FRAME_PROFILES_LOADED"), 0)
		eq(Mock.Listeners("ADDON_ACTION_BLOCKED"), 0)
		eq(Mock.Listeners("ADDON_ACTION_FORBIDDEN"), 0)
		falsy(Mock.ns.Scheduler.IsRunning(O().TICK))
		eq(Mock.ns.Compat.RaidFrames.stats.collects, 0, "the game's frames were not read")
		local titles = {}
		for _, s in ipairs(Mock.ns.addon.debugSections) do titles[s.title] = true end
		isNil(titles.Heatmap)
		deepEq(forbidden(), {})
	end)
end)

---------------------------------------------------------------------------------------------------------------------
-- The overlay
---------------------------------------------------------------------------------------------------------------------
local PARTY = { "player", "party1", "party2", "party3" }

local function mark(i) return O().Marks()[i] end
local function shown()
	local out = {}
	for i, m in ipairs(O().Marks()) do
		if m:IsShown() then out[#out + 1] = i .. ":" .. tostring(m.state) end
	end
	return table.concat(out, " ")
end

describe("the overlay over the game's raid frames (SPEC-07 §3.3)", function()
	before_boot(function(M)
		M.features = ON
		M.raidFrames.Party(PARTY)
	end)

	it("is off by default: nothing made, nothing registered, the frames not read", function()
		eq(C().HEATMAP_DEFAULTS.raidFrames, false)
		truthy(O().Enabled())
		falsy(O().Active())
		partyPull(84, 97, 60):to(1)
		isNil(O().Frame())
		isNil(rawget(_G, "AzerothThreatwardenRaidOverlay"))
		eq(Mock.Listeners("COMPACT_UNIT_FRAME_PROFILES_LOADED"), 0)
		eq(Mock.Listeners("ADDON_ACTION_BLOCKED"), 0)
		eq(Mock.ns.Compat.RaidFrames.stats.collects, 0)
		deepEq(forbidden(), {})
	end)

	it("copies the frames' rectangles into a detached frame of the addon on UIParent", function()
		set("raidFrames", true)
		truthy(O().Active())
		local frame = O().Frame()
		eq(frame, rawget(_G, "AzerothThreatwardenRaidOverlay"))
		eq(frame:GetParent(), UIParent)
		falsy(frame:IsMouseEnabled())
		eq(O().count, 4)
		eq(O().state, "available")
		eq(Mock.ns.Compat.Capability("raidFrames"), "available")
		for i = 1, 4 do
			local m = mark(i)
			eq(m:GetParent(), frame)
			local point, rel, relPoint, x, y = m:GetPoint(1)
			eq(point, "BOTTOMLEFT") eq(rel, frame) eq(relPoint, "BOTTOMLEFT")
			eq(x, 20) eq(y, 600 - (i - 1) * 36)
			deepEq({ m:GetSize() }, { 72, 36 })
			falsy(m:IsMouseEnabled())
			falsy(m.badge:IsMouseEnabled())
			falsy(m:IsShown(), "nothing to say out of combat")
		end
		eq(Mock.Listeners("COMPACT_UNIT_FRAME_PROFILES_LOADED"), 1)
		eq(Mock.Listeners("ADDON_ACTION_BLOCKED"), 1)
		eq(Mock.Listeners("ADDON_ACTION_FORBIDDEN"), 1)
		deepEq(forbidden(), {})
	end)

	it("marks only WARNING, DANGER and the aggro of a non-tank, with the state's colour, icon and word", function()
		set("raidFrames", true)
		partyPull(84, 97, 60):to(1)
		-- places: 1 player (WARNING), 2 party1 the tank (DANGER on its margin), 3 party2 (SAFE), 4 party3 (DANGER)
		eq(shown(), "1:warning 2:danger 4:danger")
		eq(mark(1).badge:GetState(), "warning")
		eq(mark(1).badge.label:GetText(), "WARNING")
		eq(mark(1).badge:GetHeight(), 12)
		local r, g, b = Mock.ns.Theme.Color("state-danger")
		truthy(mark(4).borders.danger:IsShown())
		falsy(mark(4).borders.warning:IsShown())
		truthy(mark(1).borders.warning:IsShown())
		falsy(mark(4).borders.danger:IsMouseEnabled())
		local c = mark(4).borders.danger.edges[1]:GetTexture()
		near(c[1], r, 1e-6) near(c[2], g, 1e-6) near(c[3], b, 1e-6) near(c[4], 0.9, 1e-6)
		eq(O().shown, 3)
		deepEq(forbidden(), {})
	end)

	it("gives a mark to a damage dealer who holds the mob", function()
		set("raidFrames", true)
		local pull = partyPull(40, 20, 8)
		pull:to(1)
		eq(shown(), "")
		pull:at(2):aggro("boss", "rogue")
		pull:to(3)
		eq(mark(4).state, "danger")
		deepEq(forbidden(), {})
	end)

	it("never copies in combat; in combat only the marks change, and a roster change hides them all", function()
		set("raidFrames", true)
		local stats = Mock.ns.Compat.RaidFrames.stats
		local pull = partyPull(84, 97, 60)
		pull:to(1)
		local copies = O().copies
		Mock.raidFrames.Get("CompactPartyFrameMember1").left = 300
		-- the tick in combat: nothing is read
		Mock.Advance(5)
		eq(O().copies, copies)
		eq(select(2, Mock.ns.Compat.RaidFrames.Collect({})), "combat", "Compat refuses in combat too")
		truthy(stats.refused >= 1)
		eq(select(4, mark(1):GetPoint(1)), 20, "the old place stays")
		eq(shown(), "1:warning 2:danger 4:danger")
		-- a state that changes in combat changes its mark only
		pull:at(6):threat("boss", "player", { raw = 900, scaled = 95 })
		pull:to(7)
		eq(mark(1).state, "danger")
		-- the roster changes in combat
		Mock.Fire("GROUP_ROSTER_UPDATE")
		truthy(O().suspended)
		eq(shown(), "")
		eq(O().suspensions, 1)
		Mock.Fire("COMPACT_UNIT_FRAME_PROFILES_LOADED")   -- the frames laid out again: still hidden, nothing read
		eq(O().suspensions, 1)
		eq(O().copies, copies)
		pull:to(8)
		eq(shown(), "", "they stay hidden until the fight ends")
		pull:at(9):stop()
		pull:to(10)
		falsy(O().suspended)
		eq(O().copies, copies + 1)
		eq(select(4, mark(1):GetPoint(1)), 300, "copied again after the fight")
		deepEq(forbidden(), {})
	end)

	it("copies every 2 s out of combat in a group, and stops the tick in combat", function()
		set("raidFrames", true)
		newPull()   -- a group, out of combat
		Mock.Advance(0.1)
		truthy(Mock.ns.Scheduler.IsRunning(O().TICK))
		local copies = O().copies
		Mock.raidFrames.Get("CompactPartyFrameMember2").bottom = 111
		Mock.Advance(2.5)
		truthy(O().copies > copies)
		eq(select(5, mark(2):GetPoint(1)), 111)
		Mock.combat.Enter()
		falsy(Mock.ns.Scheduler.IsRunning(O().TICK))
		Mock.combat.Leave()
		truthy(Mock.ns.Scheduler.IsRunning(O().TICK))
		deepEq(forbidden(), {})
	end)

	it("copies again at the events that move frames, out of combat", function()
		set("raidFrames", true)
		local copies = O().copies
		Mock.Fire("COMPACT_UNIT_FRAME_PROFILES_LOADED")
		eq(O().copies, copies + 1)
		Mock.Fire("DISPLAY_SIZE_CHANGED")
		eq(O().copies, copies + 2)
		Mock.Fire("GROUP_ROSTER_UPDATE")
		truthy(O().copies >= copies + 3)
		deepEq(forbidden(), {})
	end)

	it("shows nothing in the demo", function()
		set("raidFrames", true)
		Mock.Slash("/atw demo")
		Mock.Advance(2)
		eq(shown(), "")
		Mock.Slash("/atw demo")
		deepEq(forbidden(), {})
	end)

	it("hides everything and registers nothing more when the setting is turned off", function()
		set("raidFrames", true)
		partyPull(84, 97, 60):to(1)
		truthy(O().shown > 0)
		set("raidFrames", false)
		falsy(O().Active())
		eq(O().shown, 0)
		falsy(O().Frame():IsShown())
		eq(Mock.Listeners("COMPACT_UNIT_FRAME_PROFILES_LOADED"), 0)
		eq(Mock.Listeners("ADDON_ACTION_BLOCKED"), 0)
		falsy(Mock.ns.Scheduler.IsRunning(O().TICK))
		deepEq(forbidden(), {})
	end)

	it("follows a frame's scale and leaves out hidden frames and frames without a unit", function()
		UIParent:SetScale(1.25)
		local d = Mock.raidFrames.Get("CompactPartyFrameMember1")
		d.scale, d.left, d.bottom, d.width, d.height = 1, 100, 200, 80, 40
		Mock.raidFrames.Get("CompactPartyFrameMember3").visible = false
		Mock.raidFrames.SetUnit("CompactPartyFrameMember4", nil)
		set("raidFrames", true)
		eq(O().count, 2)
		local _, _, _, x, y = mark(1):GetPoint(1)
		near(x, 80, 1e-9) near(y, 160, 1e-9)
		deepEq({ mark(1):GetSize() }, { 64, 32 })
		UIParent:SetScale(1)
		deepEq(forbidden(), {})
	end)
end)

describe("the overlay in a raid", function()
	before_boot(function(M) M.features = ON end)

	it("finds the player's own raid frame by the raid index and the grouped frames", function()
		local pull = newPull{ raid = true }
		local units = {}
		for i = 1, 4 do units[i] = "raid" .. i end
		Mock.raidFrames.Raid(units, true)
		local me = Mock.ns.Compat.Group.RaidIndex()
		notNil(me)
		set("raidFrames", true)
		eq(O().count, 4)
		eq(Mock.ns.Compat.RaidFrames.stats.group, 4)
		pull:at(0):start():threat("boss", "tank", 1000):threat("boss", "player", { raw = 500, scaled = 84 })
		pull:to(1)
		eq(mark(me).state, "warning", "raid" .. me .. " is the player")
		deepEq(forbidden(), {})
	end)
end)

describe("the overlay without readable frames", function()
	before_boot(function(M) M.features = ON end)

	it("with no frame of these names says not shown, capability missing", function()
		set("raidFrames", true)
		eq(O().count, 0)
		eq(O().state, "missing")
		eq(Mock.ns.Compat.Capability("raidFrames"), "missing")
		eq(O().Status(), "HEATMAP_RAID_NOT_SHOWN")
		partyPull(84, 97, 60):to(1)
		eq(O().shown, 0)
	end)

	it("with secret answers draws nothing: capability restricted", function()
		Mock.raidFrames.Party(PARTY)
		for i = 1, 4 do Mock.raidFrames.Get("CompactPartyFrameMember" .. i).mode = "secret" end
		set("raidFrames", true)
		eq(O().count, 0)
		eq(O().state, "restricted")
		eq(Mock.ns.Compat.Capability("raidFrames"), "restricted")
		eq(O().Status(), "HEATMAP_RAID_RESTRICTED")
		eq(Mock.ns.Compat.RaidFrames.stats.failed, 4)
		deepEq(forbidden(), {})
	end)

	it("with failing reads draws nothing and raises nothing", function()
		Mock.raidFrames.Party(PARTY)
		for i = 1, 4 do Mock.raidFrames.Get("CompactPartyFrameMember" .. i).mode = "error" end
		set("raidFrames", true)
		eq(O().state, "restricted")
		eq(#Mock.errors, 0)
		deepEq(forbidden(), {})
	end)

	it("a frame that is not shown is still read: available, not shown", function()
		Mock.raidFrames.Party(PARTY)
		for i = 1, 4 do Mock.raidFrames.Get("CompactPartyFrameMember" .. i).visible = false end
		set("raidFrames", true)
		eq(O().state, "available")
		eq(O().count, 0)
		eq(O().Status(), "HEATMAP_RAID_NOT_SHOWN")
	end)
end)

describe("the mock's log of forbidden touches", function()
	it("catches every kind of touch, so an empty log means something", function()
		Mock.raidFrames.Add("CompactRaidFrame1", { unit = "raid1" })
		local f = rawget(_G, "CompactRaidFrame1")
		local _ = f.healthBar
		f:SetAlpha(0.5)
		f.marked = true
		hooksecurefunc("CompactUnitFrame_UpdateAll", function() end)
		CompactUnitFrame_UpdateAll(f)
		local mine = CreateFrame("Frame")
		mine:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
		mine:SetParent(f)
		local log = table.concat(forbidden(), "\n")
		contains(log, "CompactRaidFrame1: read healthBar")
		contains(log, "CompactRaidFrame1: call SetAlpha")
		contains(log, "CompactRaidFrame1: write marked")
		contains(log, "CompactUnitFrame_UpdateAll: hooksecurefunc")
		contains(log, "CompactUnitFrame_UpdateAll: called")
		contains(log, "CompactRaidFrame1: anchored to")
		contains(log, "CompactRaidFrame1: parented to")
		Mock.raidFrames.ClearLog()
		eq(#forbidden(), 0)
	end)
end)
