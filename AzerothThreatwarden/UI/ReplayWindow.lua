-- ReplayWindow: the window of the Threat Replay (SPEC-05 §5.5, SPEC-02 §3.9, ui-style 3.5; ADR 0003, 0017; SPEC-09
-- Q18, Q19). Lua 5.1; no game API is named here (ARC-02): CreateFrame, the methods of its own frames, and
-- Core/Compat.lua. Behind the `replay` and `timeline` switches (ADR 0014): with either off nothing is listened to and no
-- frame is made. Threatwarden's own.
--
-- A frame of its own, AzerothThreatwardenReplay, apart from the main window: title bar with the recording (date, zone,
-- enemy, length, badge), the chart with its lanes (UI/Timeline.lua), the controls and the speed, the event list and the
-- detail at the cursor (under NARROW points one panel with a selector). It shows what Data/Replay.lua says and nothing
-- else; every value carries its category in a tooltip, estimates in the `warn` colour and unknowns in `text-3`.
--
--   ReplayWindow.Open(id, t)       the recording `id` at time `t` (nil: the first combat); false with a switch off
--   ReplayWindow.Close()
--   ReplayWindow.frame             nil until the first opening; .rows, .detail (pools), .mode
--
-- Modes: "building", "ready", and the messages "damaged", "recording" (it opens when the fight ends), "unknown"
-- (deleted), "failed". Position, size and speed per character (`char.ui.replay`), the scale of `char.ui.scale`.
-- Keys (Replay.KEYS) only out of combat and with the pointer over the window; every other key goes to the game. The
-- keyboard is switched off during combat, so nothing is propagated or taken then; Esc closes it also in combat
-- (UISpecialFrames). Nothing here is protected.
--
-- Bus (registered at PLAYER_LOGIN with the switches on): REPLAY_REQUESTED(id, t), COMBAT_STARTED, COMBAT_ENDED,
-- CONFIG_LOADED, CONFIG_CHANGED (the scale and its own keys), DISPLAY_CHANGED, SESSIONS_CHANGED, SESSION_ENDED.
local ADDON_NAME, ns = ...
ns = ns or {}
ns.modules = ns.modules or {}

local ReplayWindow = {}
ns.ReplayWindow, ns.modules.ReplayWindow = ReplayWindow, ReplayWindow

local L, Widgets, Theme, Assets, Compat = ns.L, ns.Widgets, ns.Theme, ns.Assets, ns.Compat
local type, ipairs, pcall, floor, max, min, concat = type, ipairs, pcall, math.floor, math.max, math.min, table.concat

ReplayWindow.NAME = "AzerothThreatwardenReplay"
ReplayWindow.DEFAULT_SIZE = { w = 820, h = 520 }
ReplayWindow.NARROW = 760        -- narrower: one panel below, with the selector Events / Details
ReplayWindow.PAD, ReplayWindow.GAP = 12, 8
ReplayWindow.ROW = 20            -- an event row
ReplayWindow.CHART_SHARE = 0.55  -- of what is under the title bar
ReplayWindow.MIN_PANEL = 92      -- the lower part is never smaller than this
ReplayWindow.BUTTON = 28
ReplayWindow.HEADER = 32         -- of a panel and of the selector row
ReplayWindow.SCROLL_HOLD = 3     -- seconds the event list stays where the player scrolled it
ReplayWindow.WHEEL_ROWS = 3
ReplayWindow.GRIP = 14

local POS_PATH, SIZE_PATH = "char.ui.replay.pos", "char.ui.replay.size"

local MESSAGES = {
	building = "TIMELINE_BUILDING", damaged = "REPLAY_MSG_DAMAGED", recording = "REPLAY_MSG_RECORDING",
	unknown = "REPLAY_MSG_DELETED", failed = "TIMELINE_FAILED",
}
local STATE_BADGE = { S = "safe", W = "warning", D = "danger" }
local CATEGORY_KEYS = { detected = "CAT_DETECTED", calculated = "CAT_CALCULATED", estimated = "CAT_ESTIMATED",
	predicted = "CAT_PREDICTED", unknown = "CAT_UNKNOWN" }
local CATEGORY_TOKEN = { estimated = "warn", unknown = "text-3" }
local ENDED_KEYS = { reload = "REPORT_ENDED_RELOAD", login = "REPORT_ENDED_LOGIN" }

-- The controls, left to right: id (of Replay.Do), icons and the key of the tooltip.
local CONTROLS = {
	{ id = "start", icons = { "skip-back" }, tip = "REPLAY_CTL_START" },
	{ id = "prevEvent", icons = { "step-back", "step-back" }, tip = "REPLAY_CTL_PREV_EVENT" },
	{ id = "back", icons = { "step-back" }, tip = "REPLAY_CTL_BACK", jump = true },
	{ id = "toggle", icons = { "play" }, tip = "REPLAY_CTL_PLAY" },
	{ id = "forward", icons = { "step-forward" }, tip = "REPLAY_CTL_FORWARD", jump = true },
	{ id = "nextEvent", icons = { "step-forward", "step-forward" }, tip = "REPLAY_CTL_NEXT_EVENT" },
	{ id = "finish", icons = { "skip-forward" }, tip = "REPLAY_CTL_END" },
}
-- The icon of a marker that the timeline draws as a line or a band (the list gives every row one).
local ROW_ICONS = { c = "flag", T = "refresh", M = "eye", G = "clock", Z = "warn" }

local function replay() return ns.Replay end
local function config() return ns.Config end
local function get(path) return config() and config():Get(path) end

local function on()
	local F = ns.Features
	return F ~= nil and F.On("replay") and F.On("timeline")
end

local function categoryName(category) return L[CATEGORY_KEYS[category] or "CAT_UNKNOWN"] end
local function tagged(text, category) return L.TIP_TAGGED:format(text, categoryName(category)) end

local function inCombat()
	if ns.addon and ns.addon.inCombat then return true end
	if Compat.InCombatLockdown() then return true end
	return Compat.Unit.AffectingCombat("player") == true
end

---------------------------------------------------------------------------------------------------------------------
-- Place and size (the geometry of UI/Window.lua)
---------------------------------------------------------------------------------------------------------------------
local function screenSize(f)
	local parent = Compat.UIParent()
	if not parent then return nil end
	local w, h, scale = parent:GetWidth(), parent:GetHeight(), f:GetScale()
	if not w or not h or w <= 0 or h <= 0 then return nil end
	if not scale or scale <= 0 then scale = 1 end
	return w / scale, h / scale
end

local function currentPos(f)
	local point, _, rel, x, y = f:GetPoint(1)
	if type(point) ~= "string" or type(x) ~= "number" or type(y) ~= "number" then return nil end
	return { point = point, relativePoint = type(rel) == "string" and rel or point, x = x, y = y }
end

local function anchor(f, pos)
	local parent = Compat.UIParent()
	f:ClearAllPoints()
	if pos then f:SetPoint(pos.point, parent, pos.relativePoint, pos.x, pos.y)
	else f:SetPoint("CENTER", parent, "CENTER", 0, 0) end
end

-- Writes without answering our own CONFIG_CHANGED.
local function save(path, value)
	if not config() then return end
	ReplayWindow.saving = true
	config():Set(path, value)
	ReplayWindow.saving = false
end

local function keepOnScreen(f)
	local sw, sh = screenSize(f)
	if not sw or not ns.Window then return end
	local w, h = f:GetWidth(), f:GetHeight()
	local left, top = ns.Window.Rect(currentPos(f), w, h, sw, sh)
	local l, t = ns.Window.Clamp(left, top, w, h, sw, sh)
	if math.abs(l - left) < 0.5 and math.abs(t - top) < 0.5 then return end
	anchor(f, { point = "TOPLEFT", relativePoint = "BOTTOMLEFT", x = l, y = t })
end

local function savedSize()
	local size = get(SIZE_PATH) or ReplayWindow.DEFAULT_SIZE
	return size.w, size.h
end

-- Scale, size and position from `char.ui`.
local function place(f)
	f.scale = get("char.ui.scale") or 1
	f:SetScale(f.scale)
	local lim = ns.Config.SIZES.replay
	if f.SetResizeBounds then f:SetResizeBounds(lim.minW, lim.minH, lim.maxW, lim.maxH) end
	f:SetSize(savedSize())
	anchor(f, get(POS_PATH))
	keepOnScreen(f)
end

local function stopMoving(f)
	if not f.moving then return end
	f.moving = false
	f:StopMovingOrSizing()
	local pos = currentPos(f)
	if pos then save(POS_PATH, pos) end
end

local function stopSizing(f)
	if not f.sizing then return end
	f.sizing = false
	f:StopMovingOrSizing()
	local pos = currentPos(f)
	save(SIZE_PATH, { w = f:GetWidth(), h = f:GetHeight() })
	-- Config brings the size within the limits; a read-only character keeps the size just given
	local saved = get(SIZE_PATH)
	if saved and not (config() and config():IsReadOnly("char")) then f:SetSize(saved.w, saved.h) end
	if pos then save(POS_PATH, pos) end
end

---------------------------------------------------------------------------------------------------------------------
-- The keyboard (Q19): taken only out of combat, and only the keys of the replay while the pointer is over the window
---------------------------------------------------------------------------------------------------------------------
-- Out of combat the frame listens and propagates every key it does not take; in combat it hears nothing. Without
-- SetPropagateKeyboardInput it never listens (it would swallow every key).
local function setKeyboard(f, want)
	f.keys = false
	if want and f.SetPropagateKeyboardInput and not inCombat() then
		if pcall(f.SetPropagateKeyboardInput, f, true) then f.keys = true end
	end
	f:EnableKeyboard(f.keys)
end

local function onKeyDown(f, key)
	if not f.keys then return end
	if inCombat() then setKeyboard(f, false) return end
	local action
	if ReplayWindow.mode == "ready" and f:IsMouseOver() then
		action = replay().KeyAction(key, Compat.ModifierDown("shift"), Compat.ModifierDown("ctrl"),
			Compat.ModifierDown("alt"))
	end
	f:SetPropagateKeyboardInput(action == nil)
	if action then replay().Do(action) end
end

---------------------------------------------------------------------------------------------------------------------
-- Small widgets
---------------------------------------------------------------------------------------------------------------------
-- A square button with one or two icons of the sheet. :SetIcon(name), :SetUsable(bool). Its tooltip shows while it is
-- off too.
local function iconButton(parent, icons, tip, onClick)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(ReplayWindow.BUTTON, ReplayWindow.BUTTON)
	b.fill = Theme.Slice(b, "rr_fill_8", "surface-3", "BACKGROUND")
	b.fill:SetAllPoints(b)
	b.ring = Theme.Slice(b, "rr_ring_8", "border", "BORDER")
	b.ring:SetAllPoints(b)
	b.icons = {}
	local size = #icons > 1 and 10 or 14
	for i, name in ipairs(icons) do
		local t = b:CreateTexture(nil, "OVERLAY")
		t:SetTexture(Assets.textures.icons.path)
		t:SetTexCoord(Assets.IconCoords(name))
		t:SetSize(size, size)
		t:SetPoint("CENTER", b, "CENTER", (i - (#icons + 1) / 2) * (size - 2), 0)
		Theme.Tint(t, "text-1")
		b.icons[i] = t
	end
	b.icon = icons[1]
	function b:SetIcon(name)
		self.icon = name
		self.icons[1]:SetTexCoord(Assets.IconCoords(name))
	end
	function b:SetUsable(usable)
		self:SetEnabled(usable and true or false)
		self:SetAlpha(usable and 1 or 0.45)
	end
	if b.SetMotionScriptsWhileDisabled then b:SetMotionScriptsWhileDisabled(true) end
	b:SetScript("OnEnter", function(self) Theme.Tint(self.ring, "border-strong") end)
	b:SetScript("OnLeave", function(self) Theme.Tint(self.ring, "border") end)
	if onClick then b:SetScript("OnClick", onClick) end
	Widgets.Tooltip.Attach(b, tip, "TOP")
	return b
end

-- A panel of the lower part.
local function panel(parent)
	local p = CreateFrame("Frame", nil, parent)
	p.parts = Theme.Panel(p, { radius = 8, fill = "surface-1", border = "border-subtle" })
	return p
end

---------------------------------------------------------------------------------------------------------------------
-- The title bar
---------------------------------------------------------------------------------------------------------------------
local function sessionOf(id) return id and ns.Storage.Get(id) or nil end

local function mobOf(s, model)
	local sum = type(s.sum) == "table" and s.sum or nil
	local entry = sum and sum.mob and s.mobs[sum.mob]
	if entry and type(entry.name) == "string" and entry.name ~= "" then return entry.name end
	if model and model.mobs[1] then return ns.Timeline.MobName(model, model.mobs[1][3]) end
	return L.MON_UNKNOWN_MOB
end

local function paintTitle()
	local f = ReplayWindow.frame
	local s = sessionOf(ReplayWindow.id)
	local st = replay().state
	local model = st and st.id == ReplayWindow.id and st.model or nil
	local parts = {}
	local badge
	if s then
		local Report = ns.Report
		local length
		if s.state == "open" then
			length = L.REPORTS_RECORDING_NOW
		elseif type(s.dur) == "number" then
			length = Report.Time(s.dur)
			if s.state == "interrupted" then length = L.REPORT_AT_LEAST:format(length) end
		else
			length = L.REPORT_UNKNOWN
		end
		parts = { ns.Reports.DateText(s.started), ns.Reports.ZoneText(s.zone), mobOf(s, model), length }
		if s.state == "interrupted" then
			badge = L.REPORT_INTERRUPTED:format(L[ENDED_KEYS[s.ended or ""] or "REPORT_ENDED_UNKNOWN"])
		end
	end
	f.bar.subtitle:SetText(concat(parts, " · "))
	if badge then
		f.badge:Set(badge, "warn")
		f.badge:Show()
	else
		f.badge:Hide()
	end
end

-- *Continued from...* and *Continues in...*: the sessions linked by `after`.
local function paintLinks()
	local f = ReplayWindow.frame
	local s = ReplayWindow.mode == "ready" and sessionOf(ReplayWindow.id) or nil
	local before = s and s.after and sessionOf(s.after) or nil
	local later
	if s then
		for _, h in ipairs(ns.Storage.List()) do
			if h.after == s.id then later = h break end
		end
	end
	local function set(button, target, key)
		button.target = target and target.id or nil
		if target then
			button:SetLabel(L[key]:format(ns.Reports.DateText(target.started)))
			button:Show()
		else
			button:Hide()
		end
	end
	set(f.before, before, "REPLAY_CONTINUED_FROM")
	set(f.later, later, "REPLAY_CONTINUES_IN")
end

---------------------------------------------------------------------------------------------------------------------
-- The controls
---------------------------------------------------------------------------------------------------------------------
local function timeLabel()
	local st = replay().state
	local f = ReplayWindow.frame
	if st and ReplayWindow.mode == "ready" then
		f.time:SetText(L.REPLAY_TIME:format(ns.Timeline.TimeText(st.cursor), ns.Report.Time(st.model.dur)))
	else
		f.time:SetText("")
	end
end

local function paintControls()
	local f = ReplayWindow.frame
	local ready = ReplayWindow.mode == "ready" and replay().state ~= nil
	local st = ready and replay().state or nil
	for _, c in ipairs(CONTROLS) do
		local b = f.buttons[c.id]
		if c.id == "toggle" then
			local playing = st ~= nil and st.playing
			b:SetIcon(playing and "pause" or "play")
			b:SetUsable(ready and (playing or replay().CanPlay()))
		else
			b:SetUsable(ready)
		end
	end
	f.speed:SetEnabled(ready)
	ReplayWindow.painting = true
	f.speed:Select(st and st.speed or replay().Speed())
	ReplayWindow.painting = false
	local zoom = st ~= nil and st.selection ~= nil
	local whole = st ~= nil and (st.view[1] > 0 or st.view[2] < st.model.dur)
	f.zoom:SetUsableState(zoom)
	f.zoomIcon:SetUsableState(zoom)
	f.whole:SetUsableState(whole)
	f.wholeIcon:SetUsableState(whole)
	timeLabel()
end

-- The controls in `width` points: one row (the zoom buttons as text, or as icons when the text does not fit), else two.
-- Returns the height.
local function layoutControls(f, width)
	local size, gap = ReplayWindow.BUTTON, 4
	local x = 0
	for _, c in ipairs(CONTROLS) do
		local b = f.buttons[c.id]
		b:ClearAllPoints()
		b:SetPoint("TOPLEFT", f.controls, "TOPLEFT", x, 0)
		x = x + size + gap
	end
	x = x - gap + 12
	f.speed:ClearAllPoints()
	f.speed:SetPoint("TOPLEFT", f.controls, "TOPLEFT", x, 2)
	x = x + f.speed:GetWidth() + 12
	f.time:ClearAllPoints()
	f.time:SetPoint("LEFT", f.controls, "TOPLEFT", x, -size / 2)
	-- room for the longest time of this recording
	local st = replay().state
	local longest = st and ns.Timeline.TimeText(st.model.dur) .. " / " .. ns.Report.Time(st.model.dur) or "0:00.0 / 0:00"
	x = x + #longest * 7 + 12

	local text = f.zoom:GetWidth() + gap * 2 + f.whole:GetWidth()
	local icons = size * 2 + gap
	local mode = (x + text <= width) and "text" or (x + icons <= width) and "icons" or "wrap"
	local height = size
	f.zoomMode = mode
	f.zoom:SetShown(mode ~= "icons")
	f.whole:SetShown(mode ~= "icons")
	f.zoomIcon:SetShown(mode == "icons")
	f.wholeIcon:SetShown(mode == "icons")
	local first, second = f.zoom, f.whole
	if mode == "icons" then first, second = f.zoomIcon, f.wholeIcon end
	first:ClearAllPoints()
	second:ClearAllPoints()
	if mode == "wrap" then
		first:SetPoint("TOPLEFT", f.controls, "TOPLEFT", 0, -(size + gap))
		second:SetPoint("LEFT", first, "RIGHT", gap * 2, 0)
		height = size * 2 + gap
	else
		second:SetPoint("TOPRIGHT", f.controls, "TOPRIGHT", 0, 0)
		first:SetPoint("RIGHT", second, "LEFT", mode == "icons" and -gap or -gap * 2, 0)
	end
	f.controls:SetSize(width, height)
	return height
end

---------------------------------------------------------------------------------------------------------------------
-- The event list (§5.4): only the rows that show, over a list of any length
---------------------------------------------------------------------------------------------------------------------
local paintList, paintDetail

local function eventRow(f, i)
	local row = CreateFrame("Button", nil, f.events.area)
	row:SetHeight(ReplayWindow.ROW)
	row.back = row:CreateTexture(nil, "BACKGROUND")
	Theme.Fill(row.back, "raised", 0)
	row.back:SetAllPoints(row)
	row.mark = row:CreateTexture(nil, "ARTWORK")
	Theme.Fill(row.mark, "accent", 0)
	row.mark:SetSize(2, ReplayWindow.ROW)
	row.mark:SetPoint("LEFT", row, "LEFT", 0, 0)
	row.time = Widgets.Text(row, "MonoSmall", "text-3", "LEFT")
	row.time:SetPoint("LEFT", row, "LEFT", 6, 0)
	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetTexture(Assets.textures.icons.path)
	row.icon:SetSize(10, 10)
	row.icon:SetPoint("LEFT", row, "LEFT", 50, 0)
	row.pill = ns.Reports.Pill(row)
	row.pill:SetPoint("RIGHT", row, "RIGHT", -4, 0)
	row.text = Widgets.Text(row, "Small", "text-1", "LEFT")
	row.text:SetWordWrap(false)
	row.text:SetPoint("LEFT", row, "LEFT", 66, 0)
	row.text:SetPoint("RIGHT", row.pill, "LEFT", -4, 0)
	row:SetScript("OnClick", function(self)
		if not self.index then return end
		if ReplayWindow.narrow then
			ReplayWindow.panel = "details"
			ReplayWindow.frame.switch:Select("details")
		end
		replay().Focus(self.index)
	end)
	Widgets.Tooltip.Attach(row, function(self) return self.tip end, "TOP")
	f.rows[i] = row
	return row
end

local function rowTip(model, mk)
	local lines = { ns.Timeline.MarkerText(model, mk), L.REPORTS_TIP_CATEGORY:format(categoryName(mk.category)),
		L.REPLAY_AT:format(ns.Timeline.TimeText(mk.t)) }
	local confidence = replay().ConfidenceText(mk)
	if confidence then lines[#lines + 1] = confidence end
	return lines
end

local function fillRow(row, model, index)
	local mk = model.events[index]
	if row.index == index and row.model == model then return end
	row.index, row.model = index, model
	row.time:SetText(ns.Timeline.TimeText(mk.t))
	local name, token = ns.Timeline.Icon(mk)
	if not name then
		name, token = ROW_ICONS[mk.k] or "dot", "text-2"
		if mk.k == "S" then
			if mk.state == "S" then name, token = "state-safe", "state-safe"
			elseif mk.state == "U" then name, token = "state-unknown", "state-unknown" end
		end
	end
	row.icon:SetTexCoord(Assets.IconCoords(name))
	Theme.Tint(row.icon, token)
	row.text:SetText(ns.Timeline.MarkerText(model, mk))
	local info = ns.Reports.CATEGORY[mk.category] or ns.Reports.CATEGORY.unknown
	row.pill:Set(L[info.key], info.token)
	row.tip = rowTip(model, mk)
end

-- The highlight of the rows: the focused event raised with the accent bar, the last one passed a shade lighter.
local function paintHighlight(f)
	local st = replay().state
	if not st then return end
	local last = replay().LastRow()
	local list = replay().Events()
	for i = 1, f.rowsShown or 0 do
		local row = f.rows[i]
		if row and row:IsShown() then
			local at = f.offset + i
			local focused = st.focus ~= nil and list[at] == st.focus
			row.focused, row.last = focused, at == last
			Theme.Fill(row.back, focused and "raised" or "surface-2", (focused or row.last) and 1 or 0)
			Theme.Fill(row.mark, "accent", focused and 1 or 0)
		end
	end
end

paintList = function()
	local f = ReplayWindow.frame
	local st = replay().state
	if ReplayWindow.mode ~= "ready" or not st then
		for _, row in ipairs(f.rows) do row:Hide() end
		return
	end
	local list = replay().Events()
	local note = replay().ListNote(list)
	local area = f.events.areaHeight or ReplayWindow.ROW
	local used = 0
	f.events.note:SetShown(note ~= nil)
	if note then
		f.events.note:SetText(note)
		used = (f.events.note:GetStringHeight() or 14) + 8
	end
	local rows = max(1, floor((area - used) / ReplayWindow.ROW))
	f.rowsShown = rows
	f.offset = min(max(f.offset, 0), max(#list - rows, 0))
	for i = 1, rows do
		local row = f.rows[i] or eventRow(f, i)
		local index = list[f.offset + i]
		if index then
			row:ClearAllPoints()
			row:SetPoint("TOPLEFT", f.events.area, "TOPLEFT", 0, -(used + (i - 1) * ReplayWindow.ROW))
			row:SetWidth(f.events.areaWidth or 200)
			fillRow(row, st.model, index)
			row:Show()
		else
			row.index = nil
			row:Hide()
		end
	end
	for i = rows + 1, #f.rows do
		f.rows[i].index = nil
		f.rows[i]:Hide()
	end
	paintHighlight(f)
end

-- Scrolls the list so that position `at` (in the list in force) shows, unless the player scrolled it just now.
local function follow(f, at)
	if not at or at < 1 then paintHighlight(f) return end
	if f.scrolled and Compat.Now() - f.scrolled < ReplayWindow.SCROLL_HOLD then paintHighlight(f) return end
	local rows = f.rowsShown or 1
	if at > f.offset and at <= f.offset + rows then paintHighlight(f) return end
	f.offset = at - floor(rows / 2) - 1
	paintList()
end

local function focusPosition()
	local st = replay().state
	if not st or not st.focus then return nil end
	for at, index in ipairs(replay().Events()) do
		if index == st.focus then return at end
	end
	return nil
end

---------------------------------------------------------------------------------------------------------------------
-- The detail (§5.3): lines and unit rows from pools
---------------------------------------------------------------------------------------------------------------------
local function textLine(f)
	local pool = f.detail.lines
	pool.used = pool.used + 1
	local line = pool.list[pool.used]
	if not line then
		line = CreateFrame("Frame", nil, f.detail.scroll.child)
		line:EnableMouse(true)
		line.text = Widgets.Text(line, "Small", "text-2", "LEFT")
		line.text:SetWordWrap(true)
		line.text:SetPoint("TOPLEFT", line, "TOPLEFT", 0, 0)
		Widgets.Tooltip.Attach(line, function(self) return self.tip end, "TOP")
		pool.list[pool.used] = line
	end
	return line
end

local function unitLine(f)
	local pool = f.detail.units
	pool.used = pool.used + 1
	local row = pool.list[pool.used]
	if not row then
		row = CreateFrame("Button", nil, f.detail.scroll.child)
		Widgets.RowHover(row)
		row.dash = row:CreateTexture(nil, "ARTWORK")
		row.dash:SetSize(12, 2)
		row.dash:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -7)
		row.name = Widgets.Text(row, "BodyMedium", "text-1", "LEFT")
		row.name:SetWordWrap(false)
		row.badge = Widgets.StateBadge(row, {})
		row.badge:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, -1)
		row.name:SetPoint("TOPLEFT", row, "TOPLEFT", 18, 0)
		row.name:SetPoint("RIGHT", row.badge, "LEFT", -8, 0)
		row.reading = Widgets.Text(row, "MonoSmall", "text-2", "LEFT")
		row.reading:SetWordWrap(true)
		row.reading:SetPoint("TOPLEFT", row, "TOPLEFT", 18, -18)
		row:SetScript("OnClick", function(self) if self.unit then replay().ToggleSeries(self.unit) end end)
		Widgets.Tooltip.Attach(row, function(self) return self.tip end, "TOP")
		pool.list[pool.used] = row
	end
	return row
end

-- Writes one text line under what is there; returns the line.
local function say(f, text, token, tip, font, gap)
	local detail = f.detail
	local line = textLine(f)
	detail.y = detail.y + (gap or 2)
	line.text:SetFontObject(Theme.Font(font or "Small"))
	Theme.Text(line.text, token or "text-2")
	line.token = token or "text-2"
	line.text:SetWidth(detail.width)
	line.text:SetText(text)
	line.tip = tip
	local height = line.text:GetStringHeight() or 14
	line:SetSize(detail.width, height)
	line:ClearAllPoints()
	line:SetPoint("TOPLEFT", detail.scroll.child, "TOPLEFT", 0, -detail.y)
	line:Show()
	detail.y = detail.y + height
	return line
end

local function categorized(f, text, category, font, gap)
	return say(f, text, CATEGORY_TOKEN[category] or "text-2", tagged(text, category), font, gap)
end

local function unitTip(model, row)
	local R = replay()
	local lines = { ns.Timeline.UnitName(model, row.u) }
	local state = R.StateText(row) or L.STATE_UNKNOWN
	lines[#lines + 1] = L.REPLAY_STATE_TIP:format(state, categoryName(row.stateCategory))
	lines[#lines + 1] = L.REPLAY_READING_TIP:format(R.ReadingText(row), categoryName(row.category))
	if row.lower then lines[#lines + 1] = L.REPORTS_TIP_LOWER end
	lines[#lines + 1] = R.ReadingTip(row)
	lines[#lines + 1] = L.REPLAY_UNIT_TIP
	return lines
end

local function unitRowAt(f, model, row, tokens)
	local detail = f.detail
	local w = unitLine(f)
	w.unit, w.data = row.u, row
	w.name:SetText(ns.Timeline.UnitName(model, row.u))
	local token = tokens[row.u]
	w.dash:SetShown(token ~= nil)
	w.series = token
	if token then Theme.Fill(w.dash, token) end
	w.badge:SetState(STATE_BADGE[row.state or ""] or "unknown")
	w.reading:SetWidth(max(20, detail.width - 18))
	w.reading:SetText(replay().ReadingText(row))
	Theme.Text(w.reading, CATEGORY_TOKEN[row.category] or "text-1")
	w.tip = unitTip(model, row)
	local height = 18 + (w.reading:GetStringHeight() or 14) + 2
	w:SetSize(detail.width, height)
	detail.y = detail.y + 4
	w:ClearAllPoints()
	w:SetPoint("TOPLEFT", detail.scroll.child, "TOPLEFT", 0, -detail.y)
	w:Show()
	detail.y = detail.y + height
	if row.kind == "estimate" then detail.estimates[#detail.estimates + 1] = w end
end

local function eventSection(f, st)
	local R, model, T = replay(), st.model, ns.Timeline
	f.detail.event = R.EventDetail(st.focus, f.detail.event)
	local d = f.detail.event
	say(f, L.REPLAY_SELECTED_EVENT, "text-1", nil, "BodyMedium", 0)
	categorized(f, T.MarkerText(model, d.event), d.category)
	say(f, L.REPLAY_AT:format(T.TimeText(d.t)), "text-3")
	local confidence = R.ConfidenceText(d)
	if confidence then say(f, confidence, "text-3") end
	if #d.units > 0 then
		say(f, L.REPLAY_AROUND:format(T.TimeText(d.a), T.TimeText(d.b)), "text-1", nil, "BodyMedium", 8)
		for _, r in ipairs(d.units) do
			categorized(f, R.EventReadingText(model, r), r.count == 0 and "unknown" or "detected")
		end
	end
	say(f, L.REPLAY_MISSING_TITLE, "text-1", nil, "BodyMedium", 8)
	local lines = R.MissingLines(model, d.missing)
	for _, line in ipairs(lines) do
		categorized(f, line, #d.missing > 0 and "unknown" or "detected")
	end
end

local function momentSection(f, st)
	local R, model, T, detail = replay(), st.model, ns.Timeline, f.detail
	detail.snap = R.Snapshot(st.cursor, detail.snap)
	local snap = detail.snap
	detail.atLine = say(f, L.REPLAY_AT:format(T.TimeText(st.cursor)), "text-1", nil, "BodyMedium",
		st.focus and 14 or 0)

	local parts, tips = {}, {}
	local function part(text, category)
		if not text then return end
		parts[#parts + 1] = text
		tips[#tips + 1] = tagged(text, category)
	end
	part(R.MobText(model, snap), snap.mobCategory)
	part(R.ModeText(snap), snap.modeCategory)
	part(R.CombatText(snap), snap.combatCategory)
	local unsure = snap.combat and (snap.mobCategory == "unknown" or snap.modeCategory == "unknown")
	say(f, concat(parts, " · "), unsure and "text-3" or "text-2", tips)

	for i = 1, snap.ngaps do
		local g = snap.gaps[i]
		if g[3] == "limit" then
			categorized(f, R.MissingText(model, { kind = "limit", from = g[1], to = g[2], start = g[1] }), "unknown")
		elseif g[3] == "tick" then
			categorized(f, T.GapText(g), "unknown")
		end
	end
	local holder = R.HolderText(model, snap)
	if holder then categorized(f, holder, snap.holderCategory) end

	-- the colours of the series on the chart
	local tokens = {}
	for j, u in ipairs(f.chart.shown or {}) do tokens[u] = f.chart.tokens and f.chart.tokens[j] end
	for i = 1, snap.nunits do unitRowAt(f, model, snap.units[i], tokens) end
	if snap.more > 0 then say(f, L.REPLAY_MORE_UNITS:format(snap.more), "text-3") end
end

paintDetail = function()
	local f = ReplayWindow.frame
	local detail = f.detail
	local st = replay().state
	detail.lines.used, detail.units.used, detail.y = 0, 0, 0
	for i = #detail.estimates, 1, -1 do detail.estimates[i] = nil end
	detail.atLine = nil
	if ReplayWindow.mode == "ready" and st and detail.width then
		if st.focus then eventSection(f, st) end
		momentSection(f, st)
		ReplayWindow.moment = st.moment
		detail.focus = st.focus
	end
	for _, pool in ipairs({ detail.lines, detail.units }) do
		for i = pool.used + 1, #pool.list do pool.list[i]:Hide() end
	end
	detail.scroll:SetContent(detail.width or 100, detail.y)
end

-- Only what changes with the time alone: the header and the age of the estimates.
local function tickDetail(f, st)
	local detail = f.detail
	if detail.atLine then detail.atLine.text:SetText(L.REPLAY_AT:format(ns.Timeline.TimeText(st.cursor))) end
	for _, w in ipairs(detail.estimates) do
		local row = w.data
		row.age = st.cursor - row.readingT
		w.reading:SetText(replay().ReadingText(row))
		w.tip = unitTip(st.model, row)
	end
end

---------------------------------------------------------------------------------------------------------------------
-- Layout (§5.5)
---------------------------------------------------------------------------------------------------------------------
local function layoutPanels(f, y, width, height)
	local pad, gap, header = ReplayWindow.PAD, ReplayWindow.GAP, ReplayWindow.HEADER
	local narrow = width + 2 * pad < ReplayWindow.NARROW
	ReplayWindow.narrow = narrow
	local ready = ReplayWindow.mode == "ready"
	local which = ReplayWindow.panel
	f.switch:SetShown(ready and narrow)
	f.events:SetShown(ready and (not narrow or which == "events"))
	f.detail:SetShown(ready and (not narrow or which == "details"))
	f.filter:SetShown(ready and f.events:IsShown())

	local top, h = y, height
	if narrow then
		f.switch:ClearAllPoints()
		f.switch:SetPoint("TOPLEFT", f, "TOPLEFT", pad, -y)
		top, h = y + header + 4, height - header - 4
	end
	local eventsWidth = narrow and width or floor((width - gap) / 2)
	local detailWidth = narrow and width or width - gap - eventsWidth

	f.events:ClearAllPoints()
	f.events:SetPoint("TOPLEFT", f, "TOPLEFT", pad, -top)
	f.events:SetSize(eventsWidth, h)
	local inside = narrow and 6 or header + 4
	-- the filter: beside the selector in the narrow layout, else on the panel's header, with its title when it fits
	f.filter:ClearAllPoints()
	if narrow then
		f.filter:SetPoint("TOPRIGHT", f, "TOPRIGHT", -pad, -y)
		f.events.title:Hide()
	else
		f.filter:SetPoint("TOPRIGHT", f.events, "TOPRIGHT", -4, -4)
		f.events.title:SetShown(f.events.title:GetStringWidth() + f.filter:GetWidth() + 24 <= eventsWidth)
	end
	f.events.area:ClearAllPoints()
	f.events.area:SetPoint("TOPLEFT", f.events, "TOPLEFT", 4, -inside)
	f.events.areaWidth, f.events.areaHeight = eventsWidth - 8, max(ReplayWindow.ROW, h - inside - 4)
	f.events.area:SetSize(f.events.areaWidth, f.events.areaHeight)
	f.events.note:SetWidth(f.events.areaWidth - 8)

	f.detail:ClearAllPoints()
	f.detail:SetPoint("TOPLEFT", f, "TOPLEFT", narrow and pad or pad + eventsWidth + gap, -top)
	f.detail:SetSize(detailWidth, h)
	f.detail.width = detailWidth - 20
	f.detail.scroll:SetSize(detailWidth - 20, max(20, h - 16))
end

local function layout()
	local f = ReplayWindow.frame
	if not f then return end
	local pad, gap = ReplayWindow.PAD, ReplayWindow.GAP
	local width, height = f:GetWidth(), f:GetHeight()
	if not width or width <= 0 then width, height = savedSize() end
	local inner = width - 2 * pad
	-- the title gives way to the badge
	local badge = f.badge:IsShown() and f.badge:GetWidth() + 8 or 0
	f.bar.subtitle:SetWidth(max(60, width - 56 - 56 - badge))

	local y = Widgets.TITLE_HEIGHT + gap
	if f.before:IsShown() or f.later:IsShown() then
		local x = pad
		for _, button in ipairs({ f.before, f.later }) do
			if button:IsShown() then
				button:ClearAllPoints()
				button:SetPoint("TOPLEFT", f, "TOPLEFT", x, -y)
				x = x + button:GetWidth() + gap
			end
		end
		y = y + 24 + 4
	end
	local body = height - y - pad
	f.message:ClearAllPoints()
	f.message:SetPoint("CENTER", f, "CENTER", 0, 0)
	f.message:SetWidth(inner)

	local ready = ReplayWindow.mode == "ready"
	f.chart:SetShown(ready)
	if not ready then
		local controls = layoutControls(f, inner)
		f.controls:ClearAllPoints()
		f.controls:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", pad, pad + 8)
		f.controlsHeight = controls
		layoutPanels(f, y, inner, ReplayWindow.MIN_PANEL)
		return
	end
	f.chart:ClearAllPoints()
	f.chart:SetPoint("TOPLEFT", f, "TOPLEFT", pad, -y)
	local wanted = floor(body * ReplayWindow.CHART_SHARE)
	local used = f.chart:Layout(inner, wanted)
	local controls = layoutControls(f, inner)
	local rest = height - pad - (y + used + gap + controls + gap)
	if rest < ReplayWindow.MIN_PANEL then
		used = f.chart:Layout(inner, max(0, wanted - (ReplayWindow.MIN_PANEL - rest)))
		rest = height - pad - (y + used + gap + controls + gap)
	end
	f.controls:ClearAllPoints()
	f.controls:SetPoint("TOPLEFT", f, "TOPLEFT", pad, -(y + used + gap))
	f.chartHeight, f.controlsHeight, f.panelHeight = used, controls, rest
	layoutPanels(f, y + used + gap + controls + gap, inner, max(ReplayWindow.HEADER + ReplayWindow.ROW, rest))
end

-- Everything again: the title, the message of the mode, the layout, the controls, the list and the detail.
local function paint()
	local f = ReplayWindow.frame
	if not f then return end
	local key = MESSAGES[ReplayWindow.mode]
	f.message:SetText(key and L[key] or "")
	f.message:SetShown(key ~= nil)
	paintTitle()
	paintLinks()
	layout()
	paintControls()
	paintList()
	paintDetail()
end

---------------------------------------------------------------------------------------------------------------------
-- The controller's changes (Replay.OnChange)
---------------------------------------------------------------------------------------------------------------------
local function setMode(mode)
	local f = ReplayWindow.frame
	ReplayWindow.mode = mode
	if mode ~= "ready" then
		f.chart:SetModel(nil)
		f.detail.snap, f.detail.event = nil, nil
		for _, row in ipairs(f.rows) do row.index, row.model, row.tip = nil, nil, nil end
		for _, w in ipairs(f.detail.units.list) do w.data, w.unit, w.tip = nil, nil, nil end
	end
	paint()
end

local function onChange(what, why)
	local f = ReplayWindow.frame
	if not f or not f:IsShown() then return end
	if what == "closed" then
		if why == "unknown" then setMode("unknown") end
		return
	end
	local st = replay().state
	if not st or ReplayWindow.mode ~= "ready" or st.id ~= ReplayWindow.id then return end
	if what == "cursor" then
		f.chart:SetCursor(st.cursor)
		timeLabel()
		if st.moment ~= ReplayWindow.moment or st.focus ~= f.detail.focus then
			paintDetail()
			follow(f, replay().LastRow())
		else
			tickDetail(f, st)
		end
	elseif what == "play" then
		paintControls()
	elseif what == "view" then
		f.chart:SetView(st.view[1], st.view[2])
		paintControls()
	elseif what == "focus" then
		f.chart:SetSelection(st.selection and st.selection[1], st.selection and st.selection[2])
		paintDetail()
		paintControls()
		local at = focusPosition()
		if at then
			f.scrolled = nil
			follow(f, at)
		else
			paintHighlight(f)
		end
	elseif what == "series" then
		f.chart:SetSeries(st.series)
		layout()
		paintList()
		paintDetail()
	elseif what == "filter" then
		ReplayWindow.painting = true
		f.filter:Select(st.filter)
		ReplayWindow.painting = false
		f.offset, f.scrolled = 0, nil
		paintList()
		follow(f, replay().LastRow())
	end
end

-- The model is built: the chart takes it and the whole window shows it.
local function ready()
	local f = ReplayWindow.frame
	local st = replay().state
	ReplayWindow.mode, ReplayWindow.moment = "ready", nil
	f.offset, f.scrolled = 0, nil
	f.chart:SetModel(st.model)
	f.chart:SetSeries(st.series)
	f.chart:SetView(st.view[1], st.view[2])
	f.chart:SetCursor(st.cursor)
	ReplayWindow.painting = true
	f.filter:Select(st.filter)
	ReplayWindow.painting = false
	f.detail.scroll:SetVerticalScroll(0)
	paint()
	follow(f, replay().LastRow())
end

---------------------------------------------------------------------------------------------------------------------
-- Building
---------------------------------------------------------------------------------------------------------------------
local function buildControls(f)
	f.controls = CreateFrame("Frame", nil, f)
	f.buttons = {}
	for _, c in ipairs(CONTROLS) do
		f.buttons[c.id] = iconButton(f.controls, c.icons, function(self)
			local lines = { L[c.tip] }
			if c.id == "toggle" then
				local playing = replay().state and replay().state.playing
				lines[1] = L[playing and "REPLAY_CTL_PAUSE" or "REPLAY_CTL_PLAY"]
				local ok, why = replay().CanPlay()
				if not ok and why == "combat" then lines[1] = L.REPLAY_PLAY_COMBAT end
			end
			if c.jump then lines[#lines + 1] = L.REPLAY_CTL_JUMP_HINT end
			lines[#lines + 1] = L.REPLAY_KEYS_HINT
			return lines
		end, function() replay().Do(c.id) end)
	end

	local items = {}
	for _, x in ipairs(replay().SPEEDS) do items[#items + 1] = { id = x, text = L.REPLAY_SPEED_ITEM:format(x) } end
	f.speed = Widgets.Segmented(f.controls, items, function(x)
		if not ReplayWindow.painting then replay().SetSpeed(x) end
	end)
	for i, x in ipairs(replay().SPEEDS) do
		Widgets.Tooltip.Attach(f.speed.buttons[x], { L.REPLAY_CTL_SPEED:format(x, i), L.REPLAY_KEYS_HINT }, "TOP")
	end
	f.time = Widgets.Text(f.controls, "Mono", "text-1", "LEFT")

	local function zoom()
		local st = replay().state
		if st and st.selection then replay().SetView(st.selection[1], st.selection[2]) end
	end
	local function whole() replay().WholeFight() end
	local zoomTip = { L.REPLAY_ZOOM_SELECTION, L.REPLAY_ZOOM_TIP }
	local function textButton(key, tip, fn)
		local b = Widgets.Button(f.controls, { text = L[key], height = ReplayWindow.BUTTON, onClick = fn })
		if b.SetMotionScriptsWhileDisabled then b:SetMotionScriptsWhileDisabled(true) end
		Widgets.Tooltip.Attach(b, tip, "TOP")
		b.SetUsableState = b.SetEnabled
		return b
	end
	f.zoom = textButton("REPLAY_ZOOM_SELECTION", zoomTip, zoom)
	f.whole = textButton("REPLAY_WHOLE", L.REPLAY_WHOLE, whole)
	f.zoomIcon = iconButton(f.controls, { "search" }, zoomTip, zoom)
	f.wholeIcon = iconButton(f.controls, { "refresh" }, L.REPLAY_WHOLE, whole)
	f.zoomIcon.SetUsableState, f.wholeIcon.SetUsableState = f.zoomIcon.SetUsable, f.wholeIcon.SetUsable
end

local function buildPanels(f)
	f.switch = Widgets.Segmented(f, { { id = "events", text = L.REPLAY_EVENTS },
		{ id = "details", text = L.REPLAY_DETAILS } }, function(id)
		ReplayWindow.panel = id
		layout()
		paintList()
		paintDetail()
	end)

	f.events = panel(f)
	f.events.title = Widgets.Text(f.events, "H2", "text-1", "LEFT")
	f.events.title:SetPoint("TOPLEFT", f.events, "TOPLEFT", 10, -10)
	f.events.title:SetText(L.REPLAY_EVENTS)
	f.events.area = CreateFrame("Frame", nil, f.events)
	f.events.area:EnableMouse(true)
	f.events.area:EnableMouseWheel(true)
	f.events.area:SetScript("OnMouseWheel", function(_, delta)
		f.offset = f.offset - delta * ReplayWindow.WHEEL_ROWS
		f.scrolled = Compat.Now()
		paintList()
	end)
	f.events.note = Widgets.Text(f.events.area, "Small", "text-3", "LEFT")
	f.events.note:SetWordWrap(true)
	f.events.note:SetPoint("TOPLEFT", f.events.area, "TOPLEFT", 4, -4)

	local items = {}
	for _, id in ipairs(replay().FILTERS) do items[#items + 1] = { id = id, text = L[replay().FILTER_KEYS[id]] } end
	f.filter = Widgets.Segmented(f, items, function(id)
		if not ReplayWindow.painting then replay().SetFilter(id) end
	end)
	f.filter:SetFrameLevel((f.events:GetFrameLevel() or 1) + 5)

	f.detail = panel(f)
	f.detail.scroll = ns.Reports.ScrollPane(f.detail)
	f.detail.scroll:SetPoint("TOPLEFT", f.detail, "TOPLEFT", 10, -8)
	f.detail.lines, f.detail.units = { list = {}, used = 0 }, { list = {}, used = 0 }
	f.detail.estimates, f.detail.y = {}, 0
	f.rows, f.offset = {}, 0
end

local function build()
	local f = CreateFrame("Frame", ReplayWindow.NAME, Compat.UIParent())
	f:Hide()
	f:SetFrameStrata("MEDIUM")
	f:SetToplevel(true)
	f:SetClampedToScreen(true)
	f:SetMovable(true)
	f:SetResizable(true)
	if f.SetDontSavePosition then f:SetDontSavePosition(true) end   -- the place is kept in char.ui, not by the client
	f:EnableMouse(true)
	f.parts = Theme.Panel(f, { radius = 12, fill = "bg", border = "border", shadow = true, shadowAlpha = 0.6,
		highlight = true })

	f.bar = Widgets.TitleBar(f, { title = L.REPLAY_TITLE, closeLabel = L.WINDOW_CLOSE,
		onClose = function() ReplayWindow.Close() end })
	f.bar:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
	f.bar:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
	f.bar:EnableMouse(true)
	f.bar:RegisterForDrag("LeftButton")
	f.bar:SetScript("OnDragStart", function()
		f.moving = true
		f:StartMoving()
	end)
	f.bar:SetScript("OnDragStop", function() stopMoving(f) end)
	f.bar.subtitle:SetWordWrap(false)
	f.badge = ns.Reports.Pill(f.bar)
	f.badge:SetPoint("RIGHT", f.bar.close, "LEFT", -8, 0)
	f.badge:Hide()

	local function link()
		local b = Widgets.Button(f, { text = "", style = "ghost", height = 24 })
		b:SetScript("OnClick", function(self) if self.target then ReplayWindow.Open(self.target) end end)
		b:Hide()
		return b
	end
	f.before, f.later = link(), link()

	f.message = Widgets.Text(f, "BodyMedium", "text-2", "CENTER")
	f.message:SetWordWrap(true)
	f.chart = ns.Timeline.Widget(f, { legend = true, lanes = true,
		onSeek = function(t) replay().Seek(t) end,
		onSelect = function(a, b) replay().SetSelection(a, b) end,
		onView = function(a, b) replay().SetView(a, b) end })

	ReplayWindow.frame = f
	buildControls(f)
	buildPanels(f)
	ReplayWindow.panel = "events"
	f.switch:Select("events")

	f.grip = CreateFrame("Button", nil, f)
	f.grip:SetSize(ReplayWindow.GRIP, ReplayWindow.GRIP)
	f.grip:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -3, 3)
	f.grip:SetFrameLevel((f:GetFrameLevel() or 1) + 30)
	f.grip.icon = f.grip:CreateTexture(nil, "OVERLAY")
	f.grip.icon:SetTexture(Assets.textures.icons.path)
	f.grip.icon:SetTexCoord(Assets.IconCoords("dashed"))
	f.grip.icon:SetAllPoints(f.grip)
	Theme.Tint(f.grip.icon, "text-3")
	f.grip:SetScript("OnEnter", function(self) Theme.Tint(self.icon, "accent-text") end)
	f.grip:SetScript("OnLeave", function(self) Theme.Tint(self.icon, "text-3") end)
	Widgets.Tooltip.Attach(f.grip, L.WINDOW_RESIZE, "TOP")
	f.grip:SetScript("OnMouseDown", function()
		f.sizing = true
		f:StartSizing("BOTTOMRIGHT")
	end)
	f.grip:SetScript("OnMouseUp", function() stopSizing(f) end)

	Widgets.CloseOnEscape(ReplayWindow.NAME)
	f:SetScript("OnKeyDown", onKeyDown)
	f:SetScript("OnSizeChanged", function()
		if ReplayWindow.mode then
			layout()
			paintList()
			paintDetail()
		end
	end)
	f:SetScript("OnShow", function(self) setKeyboard(self, true) end)
	f:SetScript("OnHide", function(self)
		stopMoving(self)
		stopSizing(self)
		setKeyboard(self, false)
		if self:IsShown() then
			replay().Pause()          -- hidden with the whole interface (Alt+Z, a cinematic): nothing plays unseen
			return
		end
		ReplayWindow.token = (ReplayWindow.token or 0) + 1
		replay().Close()
		ReplayWindow.id = nil
		setMode("building")           -- lets go of the model; the next opening builds again
	end)
	replay().OnChange(onChange)
	place(f)
	return f
end

---------------------------------------------------------------------------------------------------------------------
-- Opening and closing
---------------------------------------------------------------------------------------------------------------------
function ReplayWindow.IsShown() return ReplayWindow.frame ~= nil and ReplayWindow.frame:IsShown() end

function ReplayWindow.Open(id, t)
	if not on() or type(id) ~= "string" then return false end
	local f = ReplayWindow.frame or build()
	local st = replay().state
	if f:IsShown() and ReplayWindow.id == id and ReplayWindow.mode == "ready" and st and st.id == id then
		if t then replay().Seek(t) end
		if f.Raise then f:Raise() end
		return true
	end
	ReplayWindow.token = (ReplayWindow.token or 0) + 1
	local mine = ReplayWindow.token
	ReplayWindow.id = id
	if not f:IsShown() then
		f:Show()
		keepOnScreen(f)
	end
	if f.Raise then f:Raise() end
	setMode("building")
	replay().Open(id, t, function(ok, why)
		if mine ~= ReplayWindow.token or not f:IsShown() then return end
		if ok then
			ready()
		elseif why ~= "replaced" and why ~= "closed" then
			setMode(MESSAGES[why or ""] and why ~= "building" and why or "failed")
		end
	end)
	return true
end

function ReplayWindow.Close()
	if ReplayWindow.IsShown() then ReplayWindow.frame:Hide() end
end

---------------------------------------------------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------------------------------------------------
-- The store changed: a recording that ended opens, a deleted one says so, the links follow.
local function onSessions()
	if not ReplayWindow.IsShown() then return end
	local id, mode = ReplayWindow.id, ReplayWindow.mode
	if mode == "recording" then
		local s = sessionOf(id)
		if not s then
			setMode("unknown")
		elseif s.state ~= "open" then
			local mine = ReplayWindow.token
			Compat.After(0, function()
				if mine == ReplayWindow.token and ReplayWindow.IsShown() and ReplayWindow.mode == "recording" then
					ReplayWindow.Open(id)
				end
			end)
		end
	elseif mode == "ready" and sessionOf(id) then
		paintTitle()
		paintLinks()
		layout()
		paintList()
		paintDetail()
	end
end

local listening = false
local function listen()
	if listening or not ns.Bus then return end
	listening = true
	local Bus = ns.Bus
	Bus.On("REPLAY_REQUESTED", function(id, t) ReplayWindow.Open(id, t) end)
	Bus.On("COMBAT_STARTED", function()
		local f = ReplayWindow.frame
		if not f then return end
		setKeyboard(f, false)
		if f:IsShown() then paintControls() end
	end)
	Bus.On("COMBAT_ENDED", function()
		local f = ReplayWindow.frame
		if not f or not f:IsShown() then return end
		setKeyboard(f, true)
		paintControls()
	end)
	Bus.On("CONFIG_LOADED", function() if ReplayWindow.frame then place(ReplayWindow.frame) end end)
	Bus.On("CONFIG_CHANGED", function(path)
		local f = ReplayWindow.frame
		if not f or ReplayWindow.saving or type(path) ~= "string" then return end
		if path == "char.ui.scale" then
			-- the saved offsets are in the units of the window: converted, so that the window stays where it is
			local old, new = f.scale or 1, get("char.ui.scale") or 1
			local pos = get(POS_PATH)
			if pos then
				save(POS_PATH, { point = pos.point, relativePoint = pos.relativePoint, x = pos.x * old / new,
					y = pos.y * old / new })
			end
			place(f)
		elseif path == POS_PATH or path == SIZE_PATH then
			place(f)
		end
	end)
	Bus.On("DISPLAY_CHANGED", function() if ReplayWindow.frame then keepOnScreen(ReplayWindow.frame) end end)
	Bus.On("SESSIONS_CHANGED", onSessions)
	Bus.On("SESSION_ENDED", onSessions)
end

function ReplayWindow.Listening() return listening end

if ns.OnEnable then
	ns.OnEnable(function() if on() then listen() end end)
end

if ns.addon then ns.addon.ReplayWindow = ReplayWindow end
