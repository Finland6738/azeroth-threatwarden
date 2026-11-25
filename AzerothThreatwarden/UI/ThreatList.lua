-- ThreatList: the Monitor tab (SPEC-03 §1.5–§1.6, §2.6, §3, §4.2; docs/specs/ui-style.md 3.2, 3.3, 4.2). Threatwarden's
-- own. The header of the monitored mob (name, classification, the player's own state, the tank, the margin), a list
-- header with the sort order and "pin me on top", one row per unit on the threat list, the message of an empty or
-- unreadable view, and the data quality in the footer. Lua 5.1; ordinary unprotected frames.
--
-- It reads the Data modules only (TargetTracker, ThreatScanner, ThreatModel, ThreatState): no game API is named here
-- (ARC-02); the class colour comes through Core/Compat.lua. Nothing is invented (ADR 0003): a state is always an icon
-- and a word (ST-02); a value that is not known is "?" or "—" with its reason in a tooltip; trends and predictions carry
-- "~" and their category.
--
-- Redraws are bounded: one per THREAT_UPDATED while the view is visible (STATE_CHANGED only asks for a new order),
-- plus settings, theme, size and showing; a hidden view only remembers that it is out of date. A text is written only
-- when it differs from what is there. Row widgets are made once per visible place and reused.
--
-- Order (SPEC-03 §3): "relative" (default), "absolute", "risk", "change"; UNKNOWN rows last, ties in roster order, the
-- player first with "pin me on top"; computed at most once a second and at once when a row enters DANGER (MON-13). The
-- order and the pin are `account.settings.monitor.sort` and `.pinSelf`; on read-only data they last for the session.
-- During the demo (Core/Demo.lua) the data modules it reads are the invented ones and the footer says so.
local ADDON_NAME, ns = ...
ns = ns or {}
ns.modules = ns.modules or {}

local ThreatList = {}
ns.ThreatList, ns.modules.ThreatList = ThreatList, ThreatList

local L, Widgets, Theme, Assets, Compat = ns.L, ns.Widgets, ns.Theme, ns.Assets, ns.Compat
local type, pairs, ipairs, tostring = type, pairs, ipairs, tostring
local floor, max, min, sort = math.floor, math.max, math.min, table.sort

ThreatList.ROW_HEIGHT, ThreatList.HEADER_HEIGHT, ThreatList.NOTICE_HEIGHT = 20, 34, 12
ThreatList.LISTHEAD_HEIGHT, ThreatList.FOOTER_HEIGHT = 14, 16
ThreatList.PAD_X, ThreatList.PAD_TOP = 8, 4
ThreatList.RESORT = 1                -- seconds between two automatic orderings (MON-13)
ThreatList.TREND_WIDTH = 28          -- the trend cell: an arrow, or "~4 s" for a predicted overtake
ThreatList.SORTS = ns.Config.SORTS
ThreatList.DEFAULTS = { sort = ns.Config.MONITOR_DEFAULTS.sort, pinSelf = ns.Config.MONITOR_DEFAULTS.pinSelf }
local SORT_PATH, PIN_PATH = "account.settings.monitor.sort", "account.settings.monitor.pinSelf"
local MONITOR_PREFIX = "account.settings.monitor."

local SORT_LABEL = {
	relative = "SORT_RELATIVE", absolute = "SORT_ABSOLUTE", risk = "SORT_RISK", change = "SORT_CHANGE",
}
local STATE_ID = { SAFE = "safe", WARNING = "warning", DANGER = "danger", UNKNOWN = "unknown" }
local STATE_RISK = { DANGER = 3, WARNING = 2, SAFE = 1, UNKNOWN = 0 }
local ROLE_ICON = { TANK = "role-tank", HEALER = "role-healer", DAMAGER = "role-dps" }
local ROLE_LABEL = { TANK = "ROLE_TANK", HEALER = "ROLE_HEALER", DAMAGER = "ROLE_DAMAGER" }
local CLASSIFICATION = {
	elite = "MON_CLASS_ELITE", rare = "MON_CLASS_RARE", rareelite = "MON_CLASS_RAREELITE",
	worldboss = "MON_CLASS_BOSS",
}
local CATEGORY_LABEL = {
	detected = "CAT_DETECTED", calculated = "CAT_CALCULATED", estimated = "CAT_ESTIMATED", predicted = "CAT_PREDICTED",
}
local CONFIDENCE_LABEL = { high = "CONF_HIGH", medium = "CONF_MEDIUM", low = "CONF_LOW" }
local WHY = {
	secret = "WHY_SECRET", missing = "WHY_MISSING", error = "WHY_ERROR", ["no-unit"] = "WHY_NO_UNIT",
	stale = "WHY_STALE_SHORT", insufficient = "WHY_INSUFFICIENT", ["state-only"] = "WHY_STATE_ONLY",
	["not-rising"] = "WHY_NOT_RISING", ["low-confidence"] = "WHY_LOW_CONFIDENCE", beyond = "WHY_BEYOND",
	["has-aggro"] = "WHY_HAS_AGGRO", holder = "WHY_HOLDER", ["not-holder"] = "WHY_NOT_HOLDER",
	alone = "TIP_ALONE", ["nil"] = "WHY_NOT_ON_LIST",
}
local MODE_LABEL = { values = "MODULE_LIVE", state = "MODULE_STATE", none = "MODULE_UNAVAILABLE" }
local LEAD_BAND = { [0] = "MON_LEAD_COMFORTABLE", "MON_LEAD_CLOSE", "MON_LEAD_VERYCLOSE", "MON_LEAD_VERYCLOSE" }

-- The text of a reason of Data/ThreatModel.lua (SPEC-03 §1.6): never empty.
function ThreatList.Why(reason) return L[WHY[reason or ""] or "WHY_UNKNOWN"] end
local why = ThreatList.Why

---------------------------------------------------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------------------------------------------------
local function setting(path)
	return ns.Config and ns.Config.Get and ns.Config:Get(path)
end

local override = {}   -- path -> value kept for the session when the saved data cannot hold it
local current = {}    -- the values in use, read when they change (Config:Get allocates: never per redraw)

local function isSort(v) return SORT_LABEL[v] ~= nil end

local function readSettings()
	local v = override[SORT_PATH]
	if v == nil then v = setting(SORT_PATH) end
	current.sort = isSort(v) and v or ThreatList.DEFAULTS.sort
	local pin = override[PIN_PATH]
	if pin == nil then pin = setting(PIN_PATH) end
	if type(pin) ~= "boolean" then pin = ThreatList.DEFAULTS.pinSelf end
	current.pin = pin
end

function ThreatList.Sort()
	if current.sort == nil then readSettings() end
	return current.sort
end

function ThreatList.PinSelf()
	if current.sort == nil then readSettings() end
	return current.pin
end

local function store(path, value)
	local ok = ns.Config and ns.Config.Set and ns.Config:Set(path, value)
	if ok then override[path] = nil else override[path] = value end
	readSettings()
	local view = ThreatList.view
	if view then
		view.forceSort = true
		view:Redraw()
	end
end

function ThreatList.SetSort(id)
	if not isSort(id) then return false end
	store(SORT_PATH, id)
	return true
end

-- The next order of the list header (a click).
function ThreatList.NextSort()
	local current = ThreatList.Sort()
	for i, id in ipairs(ThreatList.SORTS) do
		if id == current then return ThreatList.SetSort(ThreatList.SORTS[i % #ThreatList.SORTS + 1]) end
	end
end

function ThreatList.SetPinSelf(on) store(PIN_PATH, on == true) return true end

---------------------------------------------------------------------------------------------------------------------
-- Names
---------------------------------------------------------------------------------------------------------------------
-- The name of a record, or the label of its token when the name is secret or unknown: never empty (SPEC-03 §1.6).
function ThreatList.UnitLabel(rec)
	if rec.unitName then return rec.unitName end
	local token = rec.unitToken or ""
	if token == "player" then return L.UNIT_YOU end
	if token == "pet" then return L.UNIT_PET end
	local n = token:match("^party(%d+)$")
	if n then return L.UNIT_PARTY:format(n) end
	n = token:match("^raid(%d+)$")
	if n then return L.UNIT_RAID:format(n) end
	return L.UNIT_OTHER
end
local unitLabel = ThreatList.UnitLabel

local function round(v) return floor(v + 0.5) end
local function signed(v)
	local r = round(v)
	if r > 0 then return "+" .. r end
	return tostring(r)
end

---------------------------------------------------------------------------------------------------------------------
-- Tooltips
---------------------------------------------------------------------------------------------------------------------
local function tagged(value, category)
	return L.TIP_TAGGED:format(value, L[CATEGORY_LABEL[category]])
end

-- "Label: value (category)", or "Label: the reason" (nothing is left out, ADR 0003).
local function valueLine(lines, label, row, field, text)
	local Model = ns.ThreatModel
	local rec = row.record
	local reason
	if row.stale then reason = "stale"
	elseif rec.mode == "none" then reason = row.reason or "missing" end
	if not reason and Model.Category(row, field) ~= "unknown" then
		lines[#lines + 1] = L[label]:format(tagged(text(row), Model.Category(row, field)))
	else
		lines[#lines + 1] = L[label]:format(why(reason or Model.Reason(row, field) or "missing"))
	end
end

-- The first lines after the state: why the state is what it is (SPEC-03 §2.6).
local function stateLines(lines, row, now)
	local rec = row.record
	local reason, state = row.stateReason, row.state
	if state == "UNKNOWN" then
		if reason == "stale" or row.stale then
			lines[#lines + 1] = L.WHY_STALE:format(max(now - (rec.observedAt or now), 0))
		else
			lines[#lines + 1] = why(reason or row.reason)
		end
		return
	end
	if reason == "predicted" and row.predictedIn then
		local _, danger = ns.ThreatState.Thresholds()
		lines[#lines + 1] = L.TIP_PREDICTED_WARNING:format(danger, math.ceil(row.predictedIn))
	elseif reason == "aggro" then
		lines[#lines + 1] = rec.unitToken == "player" and L.TIP_YOU_AGGRO or L.TIP_AGGRO
	elseif reason == "lost-aggro" then
		lines[#lines + 1] = L.TIP_LOST_AGGRO
	elseif reason == "behind" then
		lines[#lines + 1] = L.TIP_BEHIND
	elseif reason == "alone" then
		lines[#lines + 1] = L.TIP_ALONE
	elseif reason == "margin-unknown" then
		lines[#lines + 1] = L.TIP_MARGIN_UNKNOWN
	end
	if rec.mode == "state" then
		lines[#lines + 1] = L.TIP_STATE_ONLY
		lines[#lines + 1] = L.TIP_GAME_STATE
	end
end

local function scaledText(row) return ("%d %%"):format(round(row.record.scaledPercent)) end
local function rawText(row) return ("%d %%"):format(round(row.record.rawPercent)) end
local function threatText(row) return tostring(round(row.record.rawThreat)) end
local function marginText(row) return signed(row.margin) end
local function leadText(row) return tostring(round(row.record.leadPercent)) end
local function trendText(row)
	return L.TIP_TREND_VALUE:format(row.trend, L[CONFIDENCE_LABEL[row.trendConfidence] or "CONF_LOW"], row.trendSamples)
end
local function overtakeText(row) return L.TIP_PREDICTED_AGGRO:format(row.overtakeIn) end

-- The tooltip of a row (SPEC-03 §1.6): every value with its category, everything missing with its reason.
function ThreatList.RowTooltip(row, now)
	local rec = row.record
	if not rec then return nil end
	now = now or Compat.Now()
	local lines = { unitLabel(rec) }
	if ns.Demo and ns.Demo.IsActive() then lines[#lines + 1] = L.MON_DEMO_TIP end
	local def = Theme.State(STATE_ID[row.state or "UNKNOWN"])
	local category = (rec.mode == "state") and "detected" or "calculated"
	if row.state == "UNKNOWN" or not row.state then
		lines[#lines + 1] = L.TIP_STATE_UNKNOWN:format(L[def.labelKey])
	else
		lines[#lines + 1] = L.TIP_STATE:format(L[def.labelKey], L[CATEGORY_LABEL[category]])
	end
	stateLines(lines, row, now)
	if row.isHolder then lines[#lines + 1] = L.TIP_HOLDS end
	if rec.role then lines[#lines + 1] = L.TIP_ROLE:format(L[ROLE_LABEL[rec.role]]) end
	valueLine(lines, "TIP_SCALED", row, "scaledPercent", scaledText)
	valueLine(lines, "TIP_RAW", row, "rawPercent", rawText)
	valueLine(lines, "TIP_THREAT", row, "rawThreat", threatText)
	valueLine(lines, "TIP_MARGIN", row, "margin", marginText)
	if row.isHolder then valueLine(lines, "TIP_LEAD", row, "leadPercent", leadText) end
	if not row.isHolder then
		valueLine(lines, "TIP_TREND", row, "trend", trendText)
		valueLine(lines, "TIP_PREDICTION", row, "overtakeIn", overtakeText)
	end
	if (rec.observedAt or 0) > 0 then lines[#lines + 1] = L.TIP_READ:format(max(now - rec.observedAt, 0)) end
	lines[#lines + 1] = L.TIP_MODE:format(L[MODE_LABEL[rec.mode] or "MODULE_UNAVAILABLE"])
	return lines
end

---------------------------------------------------------------------------------------------------------------------
-- Situation and order
---------------------------------------------------------------------------------------------------------------------
-- What the view shows (SPEC-03 §2.6): "none", "died", "lost" (no mob), "idle" (out of combat), "ended" (the last rows of
-- the fight), "unavailable" (nothing readable), "empty" (nobody on the list yet), "list".
function ThreatList.Situation()
	local Tracker, Scanner, Model, State = ns.TargetTracker, ns.ThreatScanner, ns.ThreatModel, ns.ThreatState
	if not Tracker.mobKey then
		local status = Tracker.status
		if status == "died" or status == "lost" then return status end
		return "none"
	end
	local present = 0
	if Model.mobKey == Tracker.mobKey then
		for i = 1, Model.count do
			if Model.rows[i].present and Model.rows[i].state then present = present + 1 end
		end
	end
	if not Scanner.inCombat then
		return present > 0 and "ended" or "idle"
	end
	local reason = State.modeReason
	if State.mode == "none" and reason and reason ~= "nil" then return "unavailable" end
	return present > 0 and "list" or "empty"
end

local keyUnknown, keySelf, key1, key2, rawKnown = {}, {}, {}, {}, false
local pinned = false

local function less(a, b)
	if pinned and keySelf[a] ~= keySelf[b] then return keySelf[a] end
	if keyUnknown[a] ~= keyUnknown[b] then return keyUnknown[b] end
	if key1[a] ~= key1[b] then return key1[a] > key1[b] end
	if key2[a] ~= key2[b] then return key2[a] > key2[b] end
	return a < b                 -- the roster order, never a name (SPEC-03 §3)
end

-- The key of the default order: the holder first, then the scaled %, then (state only) the game's situation.
local function relative(row)
	local rec = row.record
	if row.isHolder then return 3000 end
	if rec.mode == "values" and type(rec.scaledPercent) == "number" then return 2000 + rec.scaledPercent end
	if type(rec.situation) == "number" then return 1000 + rec.situation end
	return 0
end

-- Sorts `order` (row indices) by the order `by`.
local function sortRows(rows, order, by)
	pinned = ThreatList.PinSelf()
	rawKnown = false
	for _, i in ipairs(order) do
		if not rows[i].stale and type(rows[i].record.rawThreat) == "number" then rawKnown = true end
	end
	if by == "absolute" and not rawKnown then by = "relative" end
	for _, i in ipairs(order) do
		local row = rows[i]
		local base = relative(row)
		keySelf[i] = row.record.unitToken == "player"
		keyUnknown[i] = row.state == "UNKNOWN"
		if by == "absolute" then
			local raw = not row.stale and row.record.rawThreat
			if type(raw) == "number" then key1[i], key2[i] = 1, raw else key1[i], key2[i] = 0, base end
		elseif by == "risk" then
			key1[i], key2[i] = STATE_RISK[row.state] or 0, base
		elseif by == "change" then
			if row.trend ~= nil then key1[i], key2[i] = 1, row.trend else key1[i], key2[i] = 0, base end
		else
			key1[i], key2[i] = base, 0
		end
	end
	sort(order, less)
end

---------------------------------------------------------------------------------------------------------------------
-- Widgets
---------------------------------------------------------------------------------------------------------------------
local View = {}

-- Writes a text only when it differs.
local function setText(self, fs, text)
	if fs.shownText ~= text then
		fs.shownText = text
		fs:SetText(text)
		self.writes = self.writes + 1
	end
end

local function ink(fs, token)
	if fs.token ~= token then
		fs.token = token
		Theme.Text(fs, token)
	end
end

local function show(region, shown)
	if region:IsShown() ~= shown then region:SetShown(shown) end
end

local function line(parent, font, token, justify)
	local fs = Theme.NewText(parent, font, token)
	fs.token = token
	fs:SetJustifyH(justify or "LEFT")
	if fs.SetWordWrap then fs:SetWordWrap(false) end
	return fs
end

local function iconTexture(parent, name, size, token)
	local tex = parent:CreateTexture(nil, "ARTWORK")
	tex:SetTexture(Assets.textures.icons.path)
	tex:SetSize(size, size)
	tex:SetTexCoord(Assets.IconCoords(name))
	tex.name = name
	Theme.Tint(tex, token)
	return tex
end

local function setIcon(tex, name)
	if tex.name ~= name then
		tex.name = name
		tex:SetTexCoord(Assets.IconCoords(name))
	end
end

-- The width every state badge of a row gets: the widest of the four words in the language on screen.
local function badgeColumn(view)
	local badge = view.measure
	local width = 0
	for _, id in ipairs(Theme.STATE_ORDER) do
		badge:SetState(id)
		width = max(width, badge:GetWidth())
	end
	return width
end

local function newRowWidget(view, i)
	local w = CreateFrame("Frame", nil, view.list)
	w:SetHeight(ThreatList.ROW_HEIGHT)
	w.ring = Theme.Slice(w, "rr_ring_4", "accent", "BORDER")
	w.ring:SetAllPoints(w)
	w.ring:Hide()
	w.stripe = Widgets.StateStripe(w)
	w.classMark = w:CreateTexture(nil, "ARTWORK")   -- on the light theme the name is text-1: this carries the colour
	w.classMark:SetSize(2, 10)
	w.classMark:SetPoint("LEFT", w, "LEFT", 4, 0)
	w.classMark:Hide()
	local function paintMark(region)
		local c = w.classColor
		if c then region:SetColorTexture(c[1], c[2], c[3], 1) end   -- theme-ok: the class colour of the game
		region:SetShown(c ~= nil and not Theme.IsDark())
	end
	w.paintMark = paintMark
	Theme.Call(w.classMark, paintMark)                   -- once: repainted on a theme change
	w.role = iconTexture(w, "role-dps", 10, "text-3")
	w.tank = iconTexture(w, "tank", 10, "text-2")
	w.name = line(w, "Row", "text-1")
	w.bar = Widgets.ThreatBar(w, { width = 80, numberWidth = 36 })
	w.bar:EnableMouse(false)                          -- the row has the tooltip
	w.dash = line(w, "RowMono", "text-2", "RIGHT")
	w.margin = line(w, "RowMono", "text-3", "RIGHT")
	w.trend = iconTexture(w, "trend-flat", 10, "text-2")
	w.time = line(w, "MonoSmall", "text-2", "CENTER")
	w.badge = Widgets.StateBadge(w)
	w.badge:SetPoint("RIGHT", w, "RIGHT", -2, 0)
	w:SetPoint("TOPLEFT", view.list, "TOPLEFT", 0, -(i - 1) * ThreatList.ROW_HEIGHT)
	w:SetPoint("TOPRIGHT", view.list, "TOPRIGHT", 0, -(i - 1) * ThreatList.ROW_HEIGHT)
	w:EnableMouse(true)
	Widgets.Tooltip.Attach(w, function(self) return self.data and ThreatList.RowTooltip(self.data) end, "TOP")
	view:LayoutRow(w)
	return w
end

-- Places the parts of a row for the width of the view: a narrow row loses the role icon, the trend and the track of
-- the bar before the name; the state keeps its icon and word (ST-02).
function View:LayoutRow(w)
	local c = self.columns
	if not c or w.layoutVersion == self.layoutVersion then return end
	w.layoutVersion = self.layoutVersion
	local function at(region, x, width)
		region:ClearAllPoints()
		region:SetPoint("LEFT", w, "LEFT", x, 0)
		if width then region:SetWidth(width) end
	end
	w.badge:SetWidth(c.badge)
	at(w.role, c.roleX)
	at(w.tank, c.tankX)
	at(w.name, c.nameX, c.name)
	at(w.bar, c.barX, c.bar)
	w.bar:SetTrackShown(c.track)
	at(w.dash, c.barX, c.bar)
	at(w.margin, c.marginX, 30)
	at(w.trend, c.trendX + 9)
	at(w.time, c.trendX, ThreatList.TREND_WIDTH)
end

-- Columns of a row for a content width.
function View:Columns(width)
	local badge = self.badgeWidth
	local c = { badge = badge, showRole = width >= 250, showTrend = width >= 230, showMargin = width >= 370 }
	local x = 8
	c.roleX = x
	if c.showRole then x = x + 12 end
	c.tankX = x
	x = x + 12
	c.nameX = x
	local right = badge + 4
	if c.showTrend then right = right + ThreatList.TREND_WIDTH + 2 end
	if c.showMargin then right = right + 34 end
	local rest = width - x - right - 4
	c.track = rest >= 110
	if c.track then
		c.bar = min(max(70, floor(rest * 0.5)), rest - 40)
	else
		c.bar = 50
	end
	c.name = max(20, rest - c.bar)
	c.barX = x + c.name + 4
	c.marginX = c.barX + c.bar + 2
	c.trendX = width - badge - 4 - ThreatList.TREND_WIDTH - 2
	return c
end

function View:Layout(width, height)
	width = width - 2 * ThreatList.PAD_X
	height = height - ThreatList.PAD_TOP - 2
	if width == self.contentWidth and height == self.contentHeight then return end
	self.contentWidth, self.contentHeight = width, height
	self.columns = self:Columns(width)
	self.layoutVersion = self.layoutVersion + 1
	for _, w in ipairs(self.widgets) do self:LayoutRow(w) end
	self.mobMax = max(40, width - self.badge:GetWidth() - 62)   -- room for the kind and the badge
	self.mobLayout = nil
	self.tank:SetWidth(max(40, width - 100))
	self.notice:SetWidth(width)
	self.message:SetWidth(width - 8)
	self.reason:SetWidth(width - 8)
	self.quality:SetWidth(width - 16)
	self:Redraw()
end

---------------------------------------------------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------------------------------------------------
local function fillRow(view, w, row)
	local rec = row.record
	local state = row.state or "UNKNOWN"
	local id = STATE_ID[state]
	local c = view.columns
	w.data = row
	w.stripe:SetState(id)
	if w.badge:GetState() ~= id then
		w.badge:SetState(id)
		w.badge:SetWidth(c.badge)
	end
	setText(view, w.name, unitLabel(rec))
	if w.classFile ~= rec.classFile then
		w.classFile = rec.classFile
		local r, g, b = Compat.ClassColor(rec.classFile)
		if r then
			w.classColor = { r, g, b }
			Theme.ClassText(w.name, r, g, b)
		else
			w.classColor = nil
			Theme.Text(w.name, "text-1")
		end
		w.paintMark(w.classMark)
	end
	show(w.ring, rec.unitToken == "player")
	local roleIcon = rec.role and ROLE_ICON[rec.role]
	if roleIcon then setIcon(w.role, roleIcon) end
	show(w.role, c.showRole and roleIcon ~= nil)
	show(w.tank, row.isHolder == true)

	local unknown = state == "UNKNOWN"
	local stateOnly = not unknown and rec.mode == "state"
	show(w.bar, not stateOnly)
	show(w.dash, stateOnly)
	if stateOnly then
		setText(view, w.dash, L.MON_DASH)
	else
		local percent = not unknown and rec.mode == "values" and rec.scaledPercent or nil
		local predicted = percent ~= nil and (row.stateReason == "predicted" or row.overtakeIn ~= nil)
		local warning, danger = ns.ThreatState.Thresholds()
		if w.warningAt ~= warning or w.dangerAt ~= danger then
			w.warningAt, w.dangerAt = warning, danger
			w.bar:SetThresholds(warning, danger)
		end
		w.bar:Set(percent, id, false, predicted)
	end

	show(w.margin, c.showMargin)
	if c.showMargin then
		local known = not unknown and rec.mode == "values" and row.margin ~= nil
		setText(view, w.margin, known and signed(row.margin) or L.MON_DASH)
	end

	-- the trend cell: "stale" for old data, "~4 s" for a predicted overtake, else the arrow (SPEC-03 §2.5–§2.6)
	local arrow, eta = nil, nil
	if unknown then
		if row.stale or row.stateReason == "stale" then arrow = "stale" end
	elseif rec.mode == "values" and not row.isHolder then
		if row.overtakeIn then
			eta = L.MON_TIME:format(row.overtakeIn)
		elseif row.trend then
			local Calc = ns.ThreatCalc
			if row.trend > Calc.ARROW then arrow = "trend-up"
			elseif row.trend < -Calc.ARROW then arrow = "trend-down"
			else arrow = "trend-flat" end
		end
	end
	if arrow then
		setIcon(w.trend, arrow)
		local token = (arrow ~= "stale" and row.trendConfidence == "low") and "text-3" or "text-2"
		if w.trend.token ~= token then
			w.trend.token = token
			Theme.Tint(w.trend, token)
		end
	end
	show(w.trend, c.showTrend and arrow ~= nil)
	show(w.time, c.showTrend and eta ~= nil)
	if eta then setText(view, w.time, eta) end

	if Widgets.Tooltip.Owner() == w then
		Widgets.Tooltip.Show(w, ThreatList.RowTooltip(row), "TOP")
	end
end

-- The tank line: the holder's name, the name of an unwatched holder, or "Unknown tank".
local function tankText()
	local State = ns.ThreatState
	if State.tank then return L.MON_TANK:format(unitLabel(State.tank.record)), nil end
	if State.tankReason == "not-watched" then
		local name = ns.TargetTracker.HolderName() or L.MON_UNWATCHED
		return L.MON_TANK:format(L.MON_TANK_OUTSIDE:format(name)), "WHY_TANK_UNWATCHED"
	end
	return L.MON_TANK_UNKNOWN, "WHY_TANK_UNKNOWN"
end

-- The player's margin: a number in values, the game's band for a tank in state only, else "—" and why.
local function ownMargin(row)
	local rec = row.record
	if row.stale then return L.MON_DASH, "stale" end
	if rec.mode == "values" and row.margin ~= nil then return signed(row.margin), nil end
	if rec.mode == "state" then
		local band = row.isHolder and row.isTank and type(rec.leadSituation) == "number" and LEAD_BAND[rec.leadSituation]
		if band then return L[band], nil end
		return L.MON_DASH, "state-only"
	end
	return L.MON_DASH, row.marginReason or row.reason or "missing"
end

-- The mob's name and classification, read once per mob (again while the name is not known yet).
local function mobInfo(view)
	local Tracker = ns.TargetTracker
	if view.infoKey ~= Tracker.mobKey or (Tracker.mobKey and view.infoName == nil) then
		view.infoKey = Tracker.mobKey
		view.infoName, view.infoClass = Tracker.MobName(), Tracker.MobClassification()
	end
	if Tracker.mobKey then return view.infoName or L.MON_UNKNOWN_MOB, view.infoClass end
	return nil, nil
end

local function drawHeader(view, situation)
	local State = ns.ThreatState
	local mobName, classification = mobInfo(view)
	local title, class = mobName, nil
	if situation == "none" then title = L.MON_NO_TARGET
	elseif situation == "died" then title = L.MON_DIED
	elseif situation == "lost" then title = L.MON_LOST
	elseif situation == "ended" then title = L.MON_COMBAT_ENDED
	else
		local key = CLASSIFICATION[classification or ""]
		class = key and L[key]
	end
	title = title or L.MON_NO_TARGET
	if view.mob.shownText ~= title or view.mobLayout ~= view.layoutVersion then
		setText(view, view.mob, title)
		-- as wide as its text (the kind sits right after it), cut when it does not fit
		view.mobLayout = view.layoutVersion
		view.mob:SetWidth(0)
		view.mob:SetWidth(min(view.mob:GetStringWidth() + 1, view.mobMax))
	end
	show(view.class, class ~= nil)
	if class then setText(view, view.class, class) end

	local fight = situation == "list" or situation == "unavailable"
	local own = situation == "list" and State.self or nil
	local badge = nil
	if situation == "unavailable" then badge = "unknown"
	elseif own then badge = STATE_ID[own.state] end
	show(view.badge, badge ~= nil)
	if badge then view.badge:SetState(badge) end

	local tank, tankWhy = nil, nil
	if fight then tank, tankWhy = tankText()
	elseif situation == "ended" then tank = mobName end
	view.tankWhy = fight and tankWhy or nil
	show(view.tank, tank ~= nil)
	show(view.tankIcon, fight and State.tank ~= nil)
	if tank then setText(view, view.tank, tank) end

	local margin, marginWhy = nil, nil
	if own then margin, marginWhy = ownMargin(own) end
	view.marginWhy = marginWhy
	show(view.margin, margin ~= nil)
	if margin then setText(view, view.margin, L.MON_MARGIN:format(margin)) end

	local notice = situation == "list" and own == nil
	show(view.notice, notice)
	if notice then setText(view, view.notice, L.MON_NOT_ON_LIST) end
	local height = ThreatList.HEADER_HEIGHT + (notice and ThreatList.NOTICE_HEIGHT or 0)
	if view.headerHeight ~= height then
		view.headerHeight = height
		view.header:SetHeight(height)
	end
	view.title = title
end

-- The tooltip of the header: the state, the tank and the margin, each with its reason when unknown.
function View:HeaderTooltip()
	local situation = self.situation
	if situation ~= "list" and situation ~= "unavailable" then return nil end
	local State = ns.ThreatState
	local lines = { self.title }
	local own = situation == "list" and State.self or nil
	if situation == "unavailable" then
		lines[#lines + 1] = L.TIP_STATE_UNKNOWN:format(L.STATE_UNKNOWN)
		lines[#lines + 1] = why(State.modeReason)
	elseif own then
		lines[#lines + 1] = L.TIP_STATE_OWN:format(L[Theme.State(STATE_ID[own.state]).labelKey])
		stateLines(lines, own, Compat.Now())
	else
		lines[#lines + 1] = L.MON_NOT_ON_LIST
	end
	local tank = tankText()
	lines[#lines + 1] = tank
	if self.tankWhy then lines[#lines + 1] = L[self.tankWhy] end
	if own then
		local margin, marginWhy = ownMargin(own)
		lines[#lines + 1] = L.TIP_MARGIN:format(marginWhy and why(marginWhy) or margin)
	end
	return lines
end

local function drawFooter(view, situation)
	local Scanner, State = ns.ThreatScanner, ns.ThreatState
	local text, token, valid = "", "text-3", nil
	if ns.Demo and ns.Demo.IsActive() then
		text, token = L.MON_DEMO, "warn"
	elseif situation == "idle" or situation == "ended" then
		text = L.MON_NOT_IN_COMBAT
	elseif situation == "list" or situation == "unavailable" or situation == "empty" then
		local now = Compat.Now()
		local age = max(now - Scanner.lastScanAt, 0)
		if Scanner.scans == 0 then age = 0 end
		valid = Scanner.Quality(now)
		local stateOnly = State.mode == "state"
		if valid then text = L[stateOnly and "MON_QUALITY_STATE" or "MON_QUALITY"]:format(age, floor(valid))
		else text = L[stateOnly and "MON_QUALITY_STATE_NONE" or "MON_QUALITY_NONE"]:format(age) end
		if (valid and valid < 50) or age > 2 / Scanner.Rate() then token = "warn" end
	end
	view.valid = valid
	setText(view, view.quality, text)
	ink(view.quality, token)
end

local function listMessage(view, situation)
	if situation == "none" then return L.MON_NO_TARGET_HINT end
	if situation == "idle" then return L.MON_NOT_IN_COMBAT end
	if situation == "empty" then return L.MON_EMPTY end
	if situation == "unavailable" then return L.MON_UNAVAILABLE, why(ns.ThreatState.modeReason) end
	return nil
end

-- Brings the order up to date (MON-13): at once when asked (a new mob, an order, DANGER), else once a second; in between
-- the rows keep their places, the ones that left go and the new ones join at the end.
function View:Order(now)
	local Model = ns.ThreatModel
	local rows, order, member = Model.rows, self.order, self.member
	for k in pairs(member) do member[k] = nil end
	local resort = self.forceSort or Model.mobKey ~= self.mobKey or now - self.sortedAt >= ThreatList.RESORT - 1e-6
	local kept = 0
	for i = 1, #order do
		local index = order[i]
		local row = rows[index]
		if index <= Model.count and row.present and row.state then
			if row.record.unitKey ~= self.keys[index] then resort = true end
			kept = kept + 1
			order[kept] = index
			member[index] = true
		end
	end
	for i = #order, kept + 1, -1 do order[i] = nil end
	if kept == 0 then resort = true end
	for i = 1, Model.count do
		local row = rows[i]
		if row.present and row.state and not member[i] then order[#order + 1] = i end
		self.keys[i] = row.record.unitKey
	end
	if resort then
		sortRows(rows, order, ThreatList.Sort())
		self.sortedAt, self.forceSort, self.mobKey = now, false, Model.mobKey
		self.sorts = self.sorts + 1
	end
	return order
end

local function drawRows(view, situation)
	local Model = ns.ThreatModel
	local height = (view.contentHeight or 0) - view.headerHeight - ThreatList.LISTHEAD_HEIGHT - ThreatList.FOOTER_HEIGHT
	local places = max(1, floor(height / ThreatList.ROW_HEIGHT))
	local total, used = 0, 0
	local order
	if situation == "list" or situation == "ended" then
		order = view:Order(Compat.Now())
		total = #order
	end
	if total > 0 then
		used = min(total, places)
		local hidden = 0
		if total > places and places > 1 then
			used = places - 1
			hidden = total - used
		elseif total > places then
			hidden = total - used
		end
		-- the player's row is always visible: it takes the last visible place when it would fall below
		local own
		for i = used + 1, total do
			if Model.rows[order[i]].record.unitToken == "player" then own = order[i] end
		end
		for i = 1, used do
			local w = view.widgets[i]
			if not w then
				w = newRowWidget(view, i)
				view.widgets[i] = w
			end
			local index = (own and i == used) and own or order[i]
			view:LayoutRow(w)
			fillRow(view, w, Model.rows[index])
			show(w, true)
		end
		local more = hidden > 0 and places > 1
		show(view.more, more)
		if more then
			setText(view, view.more, L.MON_MORE:format(hidden))
			if view.moreAt ~= used then
				view.moreAt = used
				view.more:ClearAllPoints()
				view.more:SetPoint("TOPLEFT", view.list, "TOPLEFT", 8, -used * ThreatList.ROW_HEIGHT - 4)
			end
		end
	else
		show(view.more, false)
	end
	for i = used + 1, #view.widgets do
		local w = view.widgets[i]
		w.data = nil
		show(w, false)
	end
	view.shownRows = used

	show(view.listHead, total > 0)
	if total > 0 then
		local by = ThreatList.Sort()
		local label = L[SORT_LABEL[by]]
		setText(view, view.sortButton.label, L.MON_SORT:format(label))
		view.sortButton:SetWidth(view.sortButton.label:GetStringWidth() + 16)
		local pin = ThreatList.PinSelf()
		setText(view, view.pinButton.label, pin and L.MON_PIN_ON or L.MON_PIN_OFF)
		view.pinButton:SetWidth(view.pinButton.label:GetStringWidth() + 16)
		ink(view.pinButton.label, pin and "accent-text" or "text-3")
		setIcon(view.pinButton.icon, pin and "check" or "minus")
	end
	local message, reason = listMessage(view, situation)
	show(view.message, message ~= nil)
	show(view.reason, reason ~= nil)
	if message then setText(view, view.message, message) end
	if reason then setText(view, view.reason, reason) end
end

-- Draws the view from the Data modules. A hidden view only notes that it is out of date.
function View:Redraw()
	if not (ns.Features and ns.Features.On("monitor")) or not self.columns then return end
	if not self:IsVisible() then
		self.dirty = true
		return
	end
	self.dirty = false
	self.redraws = self.redraws + 1
	local situation = ThreatList.Situation()
	self.situation = situation
	drawHeader(self, situation)
	drawRows(self, situation)
	drawFooter(self, situation)
end

-- The tooltip of the list header's order button.
local function sortTip()
	local lines = { L[SORT_LABEL[ThreatList.Sort()]], L.MON_SORT_TIP }
	if ThreatList.Sort() == "absolute" then
		local Model, known = ns.ThreatModel, false
		for i = 1, Model.count do
			local row = Model.rows[i]
			if row.present and not row.stale and type(row.record.rawThreat) == "number" then known = true end
		end
		if not known then lines[#lines + 1] = L.MON_SORT_NEEDS_VALUES end
	end
	return lines
end

local function textButton(parent, withIcon)
	local b = CreateFrame("Button", nil, parent)
	b:SetHeight(ThreatList.LISTHEAD_HEIGHT)
	if withIcon then
		b.icon = iconTexture(b, "minus", 10, "text-3")
		b.icon:SetPoint("LEFT", b, "LEFT", 2, 0)
	end
	b.label = line(b, "Th", "text-3")
	b.label:SetPoint("LEFT", b, "LEFT", withIcon and 14 or 8, 0)
	return b
end

-- Builds the view in `page` (the Monitor tab). The caller gives it its size with :Layout(width, height).
function ThreatList.Build(page)
	local view = CreateFrame("Frame", nil, page)
	view:SetPoint("TOPLEFT", page, "TOPLEFT", ThreatList.PAD_X, -ThreatList.PAD_TOP)
	view:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -ThreatList.PAD_X, 2)
	for name, fn in pairs(View) do view[name] = fn end
	view.redraws, view.writes, view.sorts, view.layoutVersion = 0, 0, 0, 0
	view.widgets, view.order, view.member, view.keys = {}, {}, {}, {}
	view.sortedAt, view.forceSort, view.mobKey = -math.huge, true, nil
	view.headerHeight, view.shownRows = ThreatList.HEADER_HEIGHT, 0
	view.measure = Widgets.StateBadge(view)
	view.measure:Hide()
	view.badgeWidth = badgeColumn(view)

	local header = CreateFrame("Frame", nil, view)
	header:SetHeight(ThreatList.HEADER_HEIGHT)
	header:SetPoint("TOPLEFT", view, "TOPLEFT", 0, 0)
	header:SetPoint("TOPRIGHT", view, "TOPRIGHT", 0, 0)
	header:EnableMouse(true)
	view.header = header
	view.mob = line(header, "BodyMedium", "text-1")
	view.mob:SetPoint("TOPLEFT", header, "TOPLEFT", 0, -1)
	view.badge = Widgets.StateBadge(header, { large = true, state = "unknown" })
	view.badge:SetPoint("TOPRIGHT", header, "TOPRIGHT", 0, 0)
	view.class = line(header, "Small", "text-3")
	view.class:SetPoint("LEFT", view.mob, "RIGHT", 4, 0)
	view.tankIcon = iconTexture(header, "tank", 10, "text-2")
	view.tankIcon:SetPoint("TOPLEFT", header, "TOPLEFT", 0, -21)
	view.tank = line(header, "Row", "text-2")
	view.tank:SetPoint("TOPLEFT", header, "TOPLEFT", 14, -20)
	view.margin = line(header, "RowMono", "text-2", "RIGHT")
	view.margin:SetPoint("TOPRIGHT", header, "TOPRIGHT", 0, -20)
	view.notice = line(header, "Small", "text-2")
	view.notice:SetPoint("TOPLEFT", header, "TOPLEFT", 0, -33)
	Widgets.Tooltip.Attach(header, function() return view:HeaderTooltip() end, "BOTTOM")

	view.listHead = CreateFrame("Frame", nil, view)
	view.listHead:SetHeight(ThreatList.LISTHEAD_HEIGHT)
	view.listHead:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, 0)
	view.listHead:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", 0, 0)
	view.sortButton = textButton(view.listHead, false)
	view.sortButton:SetPoint("LEFT", view.listHead, "LEFT", 0, 0)
	view.sortButton:SetScript("OnClick", function() ThreatList.NextSort() end)
	Widgets.Tooltip.Attach(view.sortButton, sortTip, "TOP")
	view.pinButton = textButton(view.listHead, true)
	view.pinButton:SetPoint("RIGHT", view.listHead, "RIGHT", 0, 0)
	view.pinButton:SetScript("OnClick", function() ThreatList.SetPinSelf(not ThreatList.PinSelf()) end)
	Widgets.Tooltip.Attach(view.pinButton, L.MON_PIN_TIP, "TOP")

	view.list = CreateFrame("Frame", nil, view)
	view.list:SetPoint("TOPLEFT", view.listHead, "BOTTOMLEFT", 0, 0)
	view.list:SetPoint("BOTTOMRIGHT", view, "BOTTOMRIGHT", 0, ThreatList.FOOTER_HEIGHT)
	view.more = line(view.list, "Row", "text-3")
	view.more:Hide()
	view.message = line(view.list, "BodyMedium", "text-2", "CENTER")
	if view.message.SetWordWrap then view.message:SetWordWrap(true) end
	view.message:SetPoint("CENTER", view.list, "CENTER", 0, 8)
	view.reason = line(view.list, "Small", "text-3", "CENTER")
	view.reason:SetPoint("TOP", view.message, "BOTTOM", 0, -4)

	local footer = CreateFrame("Frame", nil, view)
	footer:SetHeight(ThreatList.FOOTER_HEIGHT)
	footer:SetPoint("BOTTOMLEFT", view, "BOTTOMLEFT", 0, 0)
	footer:SetPoint("BOTTOMRIGHT", view, "BOTTOMRIGHT", 0, 0)
	footer:EnableMouse(true)
	view.footer = footer
	view.quality = line(footer, "RowMono", "text-3")
	view.quality:SetPoint("LEFT", footer, "LEFT", 0, 0)
	Widgets.Tooltip.Attach(footer, function()
		if ns.Demo and ns.Demo.IsActive() then return L.MON_DEMO_TIP end
		if view.valid == nil and (view.situation == "list" or view.situation == "unavailable") then
			return L.WHY_NO_READS
		end
		return nil
	end, "TOP")

	view:SetScript("OnShow", function(self) self:Redraw() end)
	ThreatList.view = view
	return view
end

---------------------------------------------------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------------------------------------------------
local function redraw()
	local view = ThreatList.view
	if view then view:Redraw() end
end

if ns.Bus then
	local Bus = ns.Bus
	-- the model and the states have run already (they registered first, TOC order)
	Bus.On("THREAT_UPDATED", redraw)
	Bus.On("TARGET_STATUS", redraw)
	Bus.On("THEME_CHANGED", redraw)
	Bus.On("DEMO_CHANGED", function()
		local view = ThreatList.view
		if view then
			view.forceSort, view.infoKey = true, nil
			view:Redraw()
		end
	end)
	Bus.On("CONFIG_LOADED", readSettings)
	Bus.On("STATE_CHANGED", function(_, _, _, new)
		local view = ThreatList.view
		if view and new == "DANGER" then view.forceSort = true end
	end)
	Bus.On("CONFIG_CHANGED", function(path)
		if type(path) ~= "string" or path:sub(1, #MONITOR_PREFIX) ~= MONITOR_PREFIX then return end
		override[path] = nil
		readSettings()
		local view = ThreatList.view
		if view then
			view.forceSort = true
			view:Redraw()
		end
	end)
end

if ns.addon then ns.addon.ThreatList = ThreatList end
