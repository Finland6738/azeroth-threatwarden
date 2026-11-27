-- Reports: the *Reports* tab of the window (SPEC-05 §3.6, SPEC-03 §4.4; ADR 0003, 0013, 0014). Lua 5.1; no game API is
-- named here (ARC-02): CreateFrame and Core/Compat.lua. Behind the `reports` switch. Threatwarden's own.
--
-- A header with the use of the store (an estimate), the list of the recordings (newest first, with badges and the
-- player's worst state), and under it the report of the recording clicked, built in slices by Data/Report.lua: every
-- metric with its category marker and, in its tooltip, the category and the reason. With the `timeline` switch a
-- *Timeline* card follows the head card (UI/Timeline.lua, SPEC-05 §4.8): built after the report, in slices; with the
-- `replay` switch too, a click on it asks for the replay at that time. Delete asks twice and is for
-- closed recordings. Empty: *No recordings yet* and why recording is off or would not start. Read-only data are shown
-- and never changed. Nothing here is protected, so the tab works in combat too. With the `analytics` switch a
-- *Recordings · Analytics* selector sits at the top (the page is UI/Analytics.lua, remembered in memory until a
-- /reload) and the report has an *Analytics* card after the timeline's, built after it, in slices (SPEC-06 §3).
--
--   Reports.Build(parent) -> view     built by UI/Window.lua the first time the tab shows; view:Layout(width, height),
--                                     view:Refresh(), view:Select(id) (nil closes the report), view:Rebuild(),
--                                     view:SetPage("recordings" | "analytics")
--   Reports.ShowPage(page)            the page the tab shows next (and now, when built)
--   Reports.UsageText(usage)          "12 recordings · about 640 KB of 2 MB" (also the Recording card of Settings)
--   Reports.EmptyReason()             why the list is empty, nil when recording is on and would start
--
-- Bus (registered when the view is built): SESSIONS_CHANGED, SESSION_STARTED, SESSION_ENDED, REPORT_REQUESTED,
-- CONFIG_CHANGED, COMBAT_ENDED; it emits REPLAY_REQUESTED(id, t). Rows and cards are pooled: nothing new is made for a recording already shown.
local ADDON_NAME, ns = ...
ns = ns or {}
ns.modules = ns.modules or {}

local Reports = {}
ns.Reports, ns.modules.Reports = Reports, Reports

local L, Widgets, Theme, Compat = ns.L, ns.Widgets, ns.Theme, ns.Compat
local ipairs, type, max, min, floor, concat = ipairs, type, math.max, math.min, math.floor, table.concat

Reports.ROW_HEIGHT = 44
Reports.ROW_GAP = 2
Reports.ROWS_WITH_REPORT = 3     -- rows of the list that stay on screen above an open report
Reports.HEADER_HEIGHT = 20
Reports.CONFIRM_SECONDS = 8      -- how long "Click again to delete" waits (as Reset settings)
Reports.CARD_WIDTH = 520
Reports.BADGE_HEIGHT = 16

local STATE_BADGE = { S = "safe", W = "warning", D = "danger", U = "unknown" }
local STATE_WORD = { S = "STATE_SAFE", W = "STATE_WARNING", D = "STATE_DANGER", U = "STATE_UNKNOWN" }
local CATEGORY = {
	detected = { key = "CAT_DETECTED", note = "REPORTS_NOTE_DETECTED", token = "text-2" },
	calculated = { key = "CAT_CALCULATED", note = "REPORTS_NOTE_CALCULATED", token = "text-2" },
	estimated = { key = "CAT_ESTIMATED", note = "REPORTS_NOTE_ESTIMATED", token = "warn" },
	unknown = { key = "CAT_UNKNOWN", note = "REPORTS_NOTE_UNKNOWN", token = "text-3" },
}
local BUILD_ERROR = {
	damaged = "REPORT_DAMAGED", recording = "REPORTS_RECORDING", unknown = "REPORTS_GONE",
	error = "REPORTS_FAILED", off = "REPORTS_FAILED",
}
local ROLE_KEY = { TANK = "ROLE_TANK", HEALER = "ROLE_HEALER", DAMAGER = "ROLE_DAMAGER" }

local function storage() return ns.Storage end
local function config() return ns.Config end
local function readOnly() return config() ~= nil and config():IsReadOnly("account") end
local function recordingOn() return ns.Features ~= nil and ns.Features.On("recording") end
local function timelineOn() return ns.Features ~= nil and ns.Features.On("timeline") end
local function replayOn() return ns.Features ~= nil and ns.Features.On("replay") end
local function analyticsOn() return ns.Analytics ~= nil and ns.Analytics.On() end

Reports.page = "recordings"      -- kept in memory until a /reload (SPEC-06 §3.1)
function Reports.ShowPage(page)
	if not analyticsOn() then return end
	Reports.page = page
	if Reports.view then Reports.view:SetPage(page) end
end

---------------------------------------------------------------------------------------------------------------------
-- Words
---------------------------------------------------------------------------------------------------------------------
-- "640 KB", "2 MB", "1.5 MB"
function Reports.SizeText(kb)
	if kb >= 1024 then
		local mb = kb / 1024
		if mb == floor(mb) then return L.REPORTS_MB_WHOLE:format(mb) end
		return L.REPORTS_MB:format(mb)
	end
	return L.REPORTS_KB:format(floor(kb + 0.5))
end

function Reports.UsageText(usage)
	local count = usage.count == 1 and L.REPORTS_COUNT_ONE or L.REPORTS_COUNT:format(usage.count)
	return L.REPORTS_USAGE:format(count, Reports.SizeText(usage.bytes / 1024), Reports.SizeText(usage.maxKB))
end

-- Why the list is empty: the data are read-only, recording is off, or it only starts in a group or an instance.
function Reports.EmptyReason()
	if readOnly() then return L.REPORTS_EMPTY_READ_ONLY end
	if not recordingOn() or config():Get("account.settings.recording.enabled") ~= true then return L.REPORTS_EMPTY_OFF end
	if ns.addon and ns.addon.isForever == false then return L.REPORTS_EMPTY_CLIENT end
	local when = config():Get("account.settings.recording.when")
	if when == "group" then return L.REPORTS_EMPTY_GROUP end
	if when == "instance" then return L.REPORTS_EMPTY_INSTANCE end
	return nil
end

local function readOnlyText()
	local why = config() and config().readOnly.account
	if not why then return nil end
	return L[why == "newer" and "REPORTS_READ_ONLY_NEWER" or "REPORTS_READ_ONLY_MIGRATION"]
end

local function dateText(started)
	-- the locale writes the strftime fields as {Y}, {m}...: a % there would be a placeholder (ADR 0009)
	local pattern = L.REPORTS_DATE_FORMAT:gsub("{(%a)}", "%%%1")
	return Compat.DateText(pattern, started) or L.REPORTS_DATE_UNKNOWN
end

Reports.DateText = dateText     -- also the title of the replay window

local function zoneText(zone)
	if type(zone) == "string" and zone ~= "" then return zone end
	return L.REPORTS_ZONE_UNKNOWN
end
Reports.ZoneText = zoneText

local function categoryName(category) return L[(CATEGORY[category] or CATEGORY.unknown).key] end

-- "Label: value (category)" or "Label: reason"
local function tagged(label, value, category)
	return L.REPORTS_TIP_LINE:format(label, L.TIP_TAGGED:format(value, categoryName(category)))
end

-- The values of a list row: { name = { text, category, reason } }, from the header and its summary (SPEC-02 §4.1).
local function rowValues(h)
	local session = storage().Get(h.id)
	local sum = type(h.sum) == "table" and h.sum or nil
	local interrupted = h.state == "interrupted"
	local out = {}

	local length = type(h.dur) == "number" and ns.Report.Time(h.dur) or nil
	if h.open then
		out.duration = { text = L.REPORTS_RECORDING_NOW, category = "unknown", reason = L.REPORTS_RECORDING }
	elseif not length then
		out.duration = { text = L.REPORT_UNKNOWN, category = "unknown" }
	else
		out.duration = { text = interrupted and L.REPORT_AT_LEAST:format(length) or length, category = "detected" }
	end

	local entry = sum and sum.mob and session and session.mobs[sum.mob]
	if entry and type(entry.name) == "string" and entry.name ~= "" then
		out.mob = { text = entry.name, category = "detected" }
	elseif entry then
		out.mob = { text = L.MON_UNKNOWN_MOB, category = "unknown", reason = L.REPORT_WHY_NAME }
	else
		out.mob = { text = L.MON_UNKNOWN_MOB, category = "unknown",
			reason = (not sum) and L.REPORTS_NO_SUMMARY or L.REPORT_WHY_NO_MOB }
	end

	local worst = sum and sum.worst
	if STATE_BADGE[worst or ""] and worst ~= "U" then
		out.worst = { text = L[STATE_WORD[worst]], state = STATE_BADGE[worst], category = "calculated" }
	else
		out.worst = { text = L.STATE_UNKNOWN, state = "unknown", category = "unknown",
			reason = (not sum) and L.REPORTS_NO_SUMMARY or L.REPORTS_NO_WORST }
	end
	return out
end

local function badgesOf(h)
	local list = {}
	if h.open then list[#list + 1] = { key = "REPORTS_BADGE_RECORDING", token = "accent-text" } end
	if h.state == "interrupted" then list[#list + 1] = { key = "REPORTS_BADGE_INTERRUPTED", token = "warn" } end
	if h.trunc then list[#list + 1] = { key = "REPORTS_BADGE_LIMIT", token = "warn" } end
	if h.after then list[#list + 1] = { key = "REPORTS_BADGE_CONTINUES", token = "text-2" } end
	return list
end

function Reports.RowTooltip(h, values)
	local lines = { dateText(h.started) .. " · " .. zoneText(h.zone) }
	local function add(label, v)
		lines[#lines + 1] = tagged(L[label], v.text, v.category)
		if v.reason then lines[#lines + 1] = v.reason end
	end
	add("REPORT_METRIC_DURATION", values.duration)
	add("REPORT_METRIC_MOB", values.mob)
	add("REPORTS_WORST", values.worst)
	for _, b in ipairs(badgesOf(h)) do lines[#lines + 1] = L[b.key .. "_TIP"] end
	return lines
end

-- The tooltip of a metric of the report: the category and what it means, then why, and the limits of the value.
function Reports.CellTooltip(report, c)
	local info = CATEGORY[c.category] or CATEGORY.unknown
	local lines = { L[ns.Report.METRIC_KEYS[c.key]], L.REPORTS_TIP_CATEGORY:format(L[info.key]), L[info.note] }
	if c.status ~= "ok" then lines[#lines + 1] = ns.Report.CellText(report, c) end
	local reason = ns.Report.ReasonText(c.reason)
	if reason then lines[#lines + 1] = reason end
	if c.lower then lines[#lines + 1] = L.REPORTS_TIP_LOWER end
	local basis = ns.Report.BasisText(report, c.basis)
	if basis then lines[#lines + 1] = basis end
	if c.timeCategory then lines[#lines + 1] = L.REPORTS_TIP_TIME:format(categoryName(c.timeCategory)) end
	if c.truncated then lines[#lines + 1] = L.REPORTS_TIP_TRUNCATED end
	return lines
end

---------------------------------------------------------------------------------------------------------------------
-- Small widgets
---------------------------------------------------------------------------------------------------------------------
-- A small pill with a word in `token`. :Set(text, token)
local function pill(parent)
	local f = CreateFrame("Frame", nil, parent)
	f:SetHeight(Reports.BADGE_HEIGHT)
	f.fill = Theme.Slice(f, "rr_fill_8", "text-2", "BACKGROUND", 0.16)
	f.fill:SetAllPoints(f)
	f.label = Theme.NewText(f, "Badge", "text-2")
	f.label:SetPoint("CENTER", f, "CENTER", 0, 0)
	function f:Set(text, token)
		Theme.Tint(self.fill, token, 0.16)
		Theme.Text(self.label, token)
		self.label:SetText(text)
		self.token = token
		self:SetWidth(max(24, self.label:GetStringWidth() + 12))
	end
	return f
end

Reports.Pill, Reports.CATEGORY = pill, CATEGORY     -- the category markers of the replay window and of Analytics

local function scrollPane(parent)
	local scroll = CreateFrame("ScrollFrame", nil, parent)
	local child = CreateFrame("Frame", nil, scroll)
	child:SetSize(100, 10)
	scroll:SetScrollChild(child)
	scroll:EnableMouseWheel(true)
	scroll.child, scroll.height = child, 0
	scroll:SetScript("OnMouseWheel", function(self, delta)
		local range = max(0, self.height - (self:GetHeight() or 0))
		local step = ns.Settings.WHEEL_STEP
		self:SetVerticalScroll(min(range, max(0, (self:GetVerticalScroll() or 0) - delta * step)))
	end)
	function scroll:SetContent(width, height)
		self.height = height
		self.child:SetSize(width, max(1, height))
		local range = max(0, height - (self:GetHeight() or 0))
		if (self:GetVerticalScroll() or 0) > range then self:SetVerticalScroll(range) end
	end
	return scroll
end

Reports.ScrollPane = scrollPane

---------------------------------------------------------------------------------------------------------------------
-- The list
---------------------------------------------------------------------------------------------------------------------
local function listRow(view)
	local row = CreateFrame("Button", nil, view.list.child)
	row:SetHeight(Reports.ROW_HEIGHT)
	row.selected = row:CreateTexture(nil, "BACKGROUND")
	Theme.Fill(row.selected, "raised", 0)
	row.selected:SetAllPoints(row)
	Widgets.RowHover(row)
	row.title = Widgets.Text(row, "BodyMedium", "text-1", "LEFT")
	row.title:SetPoint("TOPLEFT", row, "TOPLEFT", 8, -5)
	row.duration = Widgets.Text(row, "Mono", "text-1", "RIGHT")
	row.duration:SetPoint("TOPRIGHT", row, "TOPRIGHT", -8, -5)
	row.title:SetPoint("RIGHT", row.duration, "LEFT", -8, 0)
	row.badge = Widgets.StateBadge(row, {})
	row.badge:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -8, 6)
	row.pills = {}
	row.mob = Widgets.Text(row, "Small", "text-2", "LEFT")
	row.mob:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 8, 7)
	row:SetScript("OnClick", function(self) view:Select(self.id) end)
	Widgets.Tooltip.Attach(row, function(self) return self.tip end, "TOP")
	return row
end

local function paintRow(view, row, h)
	local values = rowValues(h)
	row.id = h.id
	row.values = values
	row.tip = Reports.RowTooltip(h, values)
	row.title:SetText(dateText(h.started) .. " · " .. zoneText(h.zone))
	row.duration:SetText(values.duration.text)
	row.badge:SetState(values.worst.state)
	local right = row.badge
	local badges = badgesOf(h)
	for i, b in ipairs(badges) do
		local p = row.pills[i]
		if not p then p = pill(row) row.pills[i] = p end
		p:Set(L[b.key], b.token)
		p:ClearAllPoints()
		p:SetPoint("RIGHT", right, "LEFT", -4, 0)
		p:Show()
		right = p
	end
	for i = #badges + 1, #row.pills do row.pills[i]:Hide() end
	row.mob:SetPoint("RIGHT", right, "LEFT", -8, 0)
	row.mob:SetText(values.mob.text)
	Theme.Fill(row.selected, "raised", view.selected == h.id and 1 or 0)
end

---------------------------------------------------------------------------------------------------------------------
-- The report: cards of metric rows
---------------------------------------------------------------------------------------------------------------------
-- A metric: its name, the category marker at the right, the value under them (wrapping).
local function metricRow(card)
	local row = CreateFrame("Frame", nil, card)
	row:EnableMouse(true)
	row.marker = pill(row)
	row.marker:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, 0)
	row.label = Widgets.Text(row, "BodyMedium", "text-1", "LEFT")
	row.label:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -1)
	row.label:SetPoint("RIGHT", row.marker, "LEFT", -8, 0)
	row.value = Widgets.Text(row, "Body", "text-2", "LEFT")
	row.value:SetWordWrap(true)
	row.value:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -(Reports.BADGE_HEIGHT + 3))
	function row:Reflow(width)
		self.value:SetWidth(width)
		self:SetHeight(Reports.BADGE_HEIGHT + 3 + (self.value:GetStringHeight() or 14))
	end
	Widgets.Tooltip.Attach(row, function(self) return self.tip end, "TOP")
	return row
end

Reports.MetricRow = metricRow

local function paintMetric(row, report, c)
	row.cell = c
	local info = CATEGORY[c.category] or CATEGORY.unknown
	row.label:SetText(L[ns.Report.METRIC_KEYS[c.key]])
	row.marker:Set(L[info.key], info.token)
	row.value:SetText(ns.Report.CellText(report, c))
	Theme.Text(row.value, c.status == "ok" and "text-2" or "text-3")
	row.tip = Reports.CellTooltip(report, c)
	row:Show()
end

local function sessionCard(view)
	local card = ns.Settings.StackCard(view.report.child)
	ns.Settings.CardText(card, "H2", "text-1", L.REPORTS_SECTION_FIGHT, 0)
	card.rows = {}
	for i = 1, #ns.Report.SESSION_ROWS do
		card.rows[i] = card:Add(metricRow(card), 10, { stretch = true })
	end
	return card
end

local function unitCard(view)
	local card = ns.Settings.StackCard(view.report.child)
	card.name = ns.Settings.CardText(card, "H2", "text-1", "", 0)
	card.sub = ns.Settings.CardText(card, "Small", "text-3", "", 2)
	card.note = ns.Settings.CardText(card, "Body", "text-3", "", 8)
	card.rows = {}
	for i = 1, #ns.Report.UNIT_CELLS do
		card.rows[i] = card:Add(metricRow(card), 10, { stretch = true })
	end
	return card
end

local function paintUnit(card, report, u)
	local name = u.me and L.UNIT_YOU or ns.Report.UnitName(report, u.index)
	card.unit = u
	card.name:SetText(name)
	local sub = {}
	if u.me then sub[#sub + 1] = ns.Report.UnitName(report, u.index) end
	if ROLE_KEY[u.role or ""] then sub[#sub + 1] = L[ROLE_KEY[u.role]] end
	if u.pet then sub[#sub + 1] = L.REPORTS_PET end
	card.sub:SetText(concat(sub, " · "))
	card.sub:SetShown(#sub > 0)
	local whole = u.status ~= "ok"
	card.note:SetShown(whole)
	if whole then
		local text = L[u.status == "na" and "REPORT_NA" or "REPORT_INSUFFICIENT"]
		local reason = ns.Report.ReasonText(u.reason)
		if reason then text = text .. " · " .. reason end
		card.note:SetText(text)
	end
	for i, key in ipairs(ns.Report.UNIT_CELLS) do
		local c = u.cells[key]
		-- a unit with too little data keeps its note and its data quality only
		if c and (not whole or key == "quality") then paintMetric(card.rows[i], report, c)
		else card.rows[i]:Hide() end
	end
	card:Show()
end

---------------------------------------------------------------------------------------------------------------------
-- The view
---------------------------------------------------------------------------------------------------------------------
local function disarm(view)
	view.armToken = view.armToken + 1
	view.armed = false
	view.head.delete:SetLabel(L.REPORTS_DELETE)
end

local function say(view, text, token)
	view.head.status:SetText(text or "")
	Theme.Text(view.head.status, token or "warn")
	view.head.status:SetShown((text or "") ~= "")
end

local function deleteClicked(view)
	local id = view.selected
	if not id then return end
	if not view.armed then
		disarm(view)
		view.armed = true
		view.head.delete:SetLabel(L.REPORTS_DELETE_CONFIRM)
		local mine = view.armToken
		Compat.After(Reports.CONFIRM_SECONDS, function() if mine == view.armToken then disarm(view) end end)
		return
	end
	disarm(view)
	local ok, why = storage().Delete(id)
	if ok then return end   -- SESSIONS_CHANGED closed the report
	say(view, L[why == "read-only" and "CMD_READ_ONLY" or why == "recording" and "REPORTS_RECORDING"
		or "REPORTS_GONE"])
	view:Layout()
end

local function headCard(view)
	local card = ns.Settings.StackCard(view.report.child)
	card.title = ns.Settings.CardText(card, "H2", "text-1", "", 0)
	card.meta = ns.Settings.CardText(card, "Small", "text-3", "", 2)
	card.headlines = ns.Settings.CardText(card, "Body", "warn", "", 8)
	card.message = ns.Settings.CardText(card, "BodyMedium", "text-2", "", 8)
	local buttons = CreateFrame("Frame", nil, card)
	buttons:SetHeight(32)
	card.delete = Widgets.Button(buttons, { text = L.REPORTS_DELETE, style = "secondary", width = 220,
		onClick = function() deleteClicked(view) end })
	card.delete:SetPoint("LEFT", buttons, "LEFT", 0, 0)
	card.close = Widgets.Button(buttons, { text = L.REPORTS_CLOSE, style = "ghost",
		onClick = function() view:Select(nil) end })
	card.close:SetPoint("LEFT", card.delete, "RIGHT", 8, 0)
	-- the replay (SPEC-05 §5.5): off with its reason for a recording that is open or damaged
	if replayOn() and timelineOn() then
		card.replay = Widgets.Button(buttons, { text = L.REPORTS_REPLAY, style = "primary", onClick = function()
			if view.selected and ns.Bus then ns.Bus.Emit("REPLAY_REQUESTED", view.selected, nil) end
		end })
		card.replay:SetPoint("LEFT", card.delete, "RIGHT", 8, 0)
		card.close:SetPoint("LEFT", card.replay, "RIGHT", 8, 0)
		if card.replay.SetMotionScriptsWhileDisabled then card.replay:SetMotionScriptsWhileDisabled(true) end
		Widgets.Tooltip.Attach(card.replay, function(self) return self.tip end, "TOP")
	end
	card:Add(buttons, 10, { stretch = true })
	card.status = ns.Settings.CardText(card, "Small", "warn", "", 8)
	card.status:Hide()
	return card
end

-- The *Timeline* card: the chart of the whole recording with the default series, the holder lane and the events.
local function timelineCard(view)
	local card = ns.Settings.StackCard(view.report.child)
	ns.Settings.CardText(card, "H2", "text-1", L.TIMELINE_TITLE, 0)
	card.message = ns.Settings.CardText(card, "BodyMedium", "text-2", "", 8)
	card.chart = ns.Timeline.Widget(card, { zoom = false, onSeek = function(t)
		if replayOn() and view.selected and ns.Bus then ns.Bus.Emit("REPLAY_REQUESTED", view.selected, t) end
	end })
	card:Add(card.chart, 8, { stretch = true })
	card.hint = ns.Settings.CardText(card, "Small", "text-3", L.TIMELINE_CARD_HINT, 6)
	return card
end

local function paintTimeline(view)
	local card = view.timeline
	local model = view.model
	local message = view.modelProblem and L.TIMELINE_FAILED or (not model and L.TIMELINE_BUILDING) or nil
	card.message:SetText(message or "")
	card.message:SetShown(message ~= nil)
	if card.chart.model ~= model then card.chart:SetModel(model) end
	card.chart:SetShown(model ~= nil)
	card.hint:SetShown(model ~= nil and replayOn())
	card:Show()
end

local function headerOf(view, id)
	for _, h in ipairs(view.headers) do
		if h.id == id then return h end
	end
	return nil
end

-- The report pane for the selected recording: the head card, the fight card and one card per unit.
local function paintReport(view)
	local head = view.head
	local report = view.data
	local h = headerOf(view, view.selected)
	local mob = report and report.rows.mob
	head.title:SetText(mob and ns.Report.CellText(report, mob) or h and rowValues(h).mob.text or L.REPORT_UNKNOWN)
	local started, zone = report and report.started, report and report.zone
	if not report and h then started, zone = h.started, h.zone end
	head.meta:SetText(dateText(started) .. " · " .. zoneText(zone))
	local lines = report and ns.Report.Headlines(report) or {}
	head.headlines:SetText(concat(lines, "\n"))
	head.headlines:SetShown(#lines > 0)
	local message = view.problem and L[BUILD_ERROR[view.problem] or "REPORTS_FAILED"]
		or (not report and L.REPORT_BUILDING) or nil
	head.message:SetText(message or "")
	head.message:SetShown(message ~= nil)
	head.delete:SetEnabled(h ~= nil and not h.open and not readOnly())
	if head.replay then
		local why = (h and h.open and "REPORTS_REPLAY_RECORDING")
			or (view.problem == "damaged" and "REPORTS_REPLAY_DAMAGED") or (not h and "REPORTS_GONE") or nil
		head.replay:SetEnabled(why == nil)
		head.replay.tip = L[why or "REPORTS_REPLAY_TIP"]
	end

	local cards = view.report.cards
	for i = #cards, 1, -1 do cards[i] = nil end
	cards[1] = head
	if report and timelineOn() then
		if not view.timeline then view.timeline = timelineCard(view) end
		paintTimeline(view)
		cards[#cards + 1] = view.timeline
	elseif view.timeline then
		view.timeline:Hide()
	end
	if analyticsOn() and (report or view.problem == "damaged") then
		if not view.analytics then view.analytics = ns.Analytics.Card(view) end
		ns.Analytics.PaintCard(view.analytics, { id = view.selected, metrics = view.metrics,
			problem = view.problem == "damaged" and "damaged" or view.metricsProblem })
		cards[#cards + 1] = view.analytics
	elseif view.analytics then
		view.analytics:Hide()
	end
	view.fight:SetShown(report ~= nil)
	if report then
		cards[#cards + 1] = view.fight
		for i, row in ipairs(view.fight.rows) do
			local c = report.rows[ns.Report.SESSION_ROWS[i]]
			if c then paintMetric(row, report, c) else row:Hide() end
		end
		for i, u in ipairs(report.units) do
			local card = view.units[i]
			if not card then card = unitCard(view) view.units[i] = card end
			paintUnit(card, report, u)
			cards[#cards + 1] = card
		end
	end
	for i = (report and #report.units or 0) + 1, #view.units do view.units[i]:Hide() end
end

local function layoutReport(view, width, height)
	view.report:SetSize(width, height)
	local cardWidth = min(Reports.CARD_WIDTH, width)
	local y = 0
	for _, card in ipairs(view.report.cards) do
		card:Layout(cardWidth)
		card:ClearAllPoints()
		card:SetPoint("TOPLEFT", view.report.child, "TOPLEFT", 0, -y)
		y = y + card:GetHeight() + ns.Settings.CARD_GAP
	end
	view.report:SetContent(cardWidth, y - ns.Settings.CARD_GAP)
end

function Reports.Build(parent)
	local view = CreateFrame("Frame", nil, parent)
	view:SetAllPoints(parent)
	view.rows, view.units, view.headers = {}, {}, {}
	view.armToken, view.armed, view.buildToken = 0, false, 0

	view.usage = Widgets.Text(view, "BodyMedium", "text-1", "LEFT")
	view.usage:SetPoint("TOPLEFT", view, "TOPLEFT", 0, -2)
	view.usageHit = CreateFrame("Frame", nil, view)
	view.usageHit:EnableMouse(true)
	view.usageHit:SetPoint("TOPLEFT", view, "TOPLEFT", 0, 0)
	view.usageMarker = pill(view.usageHit)
	view.usageMarker:SetPoint("LEFT", view.usage, "RIGHT", 8, 0)
	view.usageMarker:Set(L.CAT_ESTIMATED, "warn")
	Widgets.Tooltip.Attach(view.usageHit, { L.REPORTS_USAGE_TITLE, L.REPORTS_TIP_CATEGORY:format(L.CAT_ESTIMATED),
		L.REPORTS_USAGE_NOTE }, "BOTTOM")

	view.notice = Widgets.Text(view, "Small", "warn", "LEFT")
	view.notice:SetWordWrap(true)

	view.empty = Widgets.Text(view, "H2", "text-1", "CENTER")
	view.empty:SetText(L.REPORTS_EMPTY)
	view.emptyReason = Widgets.Text(view, "Body", "text-2", "CENTER")
	view.emptyReason:SetWordWrap(true)

	view.list = scrollPane(view)
	view.report = scrollPane(view)
	view.report.cards = {}
	view.head = headCard(view)
	view.fight = sessionCard(view)

	if analyticsOn() then
		view.segmented = Widgets.Segmented(view, {
			{ id = "recordings", text = L.ANALYTICS_PAGE_RECORDINGS }, { id = "analytics", text = L.ANALYTICS_PAGE },
		}, function(id)
			Reports.page = id
			if view.ready then
				disarm(view)
				view:Refresh()
			end
		end)
		view.segmented:SetPoint("TOPLEFT", view, "TOPLEFT", 0, 0)
	end

	function view:Page()
		return self.segmented and Reports.page == "analytics" and "analytics" or "recordings"
	end

	function view:SetPage(page)
		if not self.segmented then return end
		if self.segmented:Active() == page then self:Refresh() else self.segmented:Select(page) end
	end

	-- Places the parts for `width` x `height` (kept from the last call when not given).
	function view:Layout(width, height)
		self.width, self.height_ = width or self.width, height or self.height_
		local w = self.width
		if not w or w <= 0 then w = self:GetWidth() end
		if not w or w <= 0 then w = Reports.CARD_WIDTH end
		local total = self.height_
		if not total or total <= 0 then total = self:GetHeight() end
		if not total or total <= 0 then total = 400 end
		local y = Reports.HEADER_HEIGHT + 6
		if self.segmented then
			-- the selector, with the use of the store beside it, or under it in a narrow window
			local left = self.segmented:GetWidth() + 12
			local need = (self.usage:GetStringWidth() or 0) + 8 + (self.usageMarker:GetWidth() or 0)
			local x, top = left, 6
			y = max(32, Reports.HEADER_HEIGHT) + 6
			if left + need > w then
				x, top = 0, 36
				y = top + Reports.HEADER_HEIGHT + 6
			end
			self.usage:ClearAllPoints()
			self.usage:SetPoint("TOPLEFT", self, "TOPLEFT", x, -(top + 2))
			self.usageHit:ClearAllPoints()
			self.usageHit:SetPoint("TOPLEFT", self, "TOPLEFT", x, -top)
			self.usageHit:SetSize(max(1, w - x), Reports.HEADER_HEIGHT)
		else
			self.usageHit:SetSize(w, Reports.HEADER_HEIGHT)
		end
		if self.notice:IsShown() then
			self.notice:ClearAllPoints()
			self.notice:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -y)
			self.notice:SetWidth(w)
			y = y + (self.notice:GetStringHeight() or 14) + 6
		end
		self.empty:ClearAllPoints()
		self.empty:SetPoint("TOP", self, "TOP", 0, -(y + 40))
		self.empty:SetWidth(w)
		self.emptyReason:ClearAllPoints()
		self.emptyReason:SetPoint("TOP", self.empty, "BOTTOM", 0, -8)
		self.emptyReason:SetWidth(w)

		if self.analyticsPage and self:Page() == "analytics" then
			self.analyticsPage:ClearAllPoints()
			self.analyticsPage:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -y)
			self.analyticsPage:Layout(w, max(40, total - y))
		end

		local step = Reports.ROW_HEIGHT + Reports.ROW_GAP
		local count = #self.headers
		local free = max(step, total - y)
		local listHeight = free
		if self.selected then listHeight = min(free, step * max(1, min(Reports.ROWS_WITH_REPORT, count))) end
		self.list:ClearAllPoints()
		self.list:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -y)
		self.list:SetSize(w, listHeight)
		for i = 1, count do
			local row = self.rows[i]
			row:ClearAllPoints()
			row:SetPoint("TOPLEFT", self.list.child, "TOPLEFT", 0, -(i - 1) * step)
			row:SetWidth(w)
		end
		self.list:SetContent(w, count * step)
		if self.selected then
			local top = y + listHeight + 8
			self.report:ClearAllPoints()
			self.report:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -top)
			layoutReport(self, w, max(40, total - top))
		end
	end

	function view:Refresh()
		local Storage = storage()
		self.headers = Storage.List()
		local usage = Storage.Usage()
		local count = #self.headers
		local analytics = self:Page() == "analytics"
		self.usage:SetText(Reports.UsageText(usage))
		local notes = {}
		local ro = readOnlyText()
		if ro then notes[#notes + 1] = ro end
		if usage.damaged > 0 then notes[#notes + 1] = L.REPORTS_DAMAGED_COUNT:format(usage.damaged) end
		self.notice:SetText(concat(notes, "\n"))
		self.notice:SetShown(#notes > 0)
		-- a recording that went away closes its report; a damaged one keeps the message
		if self.selected and not headerOf(self, self.selected) and self.problem ~= "damaged"
			and self.building ~= self.selected then
			self.selected, self.data, self.problem = nil, nil, nil
			self.model, self.modelProblem = nil, nil
			self.metrics, self.metricsProblem = nil, nil
			disarm(self)
		end
		for i, h in ipairs(self.headers) do
			local row = self.rows[i]
			if not row then row = listRow(self) self.rows[i] = row end
			paintRow(self, row, h)
			row:Show()
		end
		for i = count + 1, #self.rows do self.rows[i]:Hide() end
		local empty = count == 0 and (analytics or not self.selected)
		local why = empty and Reports.EmptyReason() or nil
		self.empty:SetShown(empty)
		self.emptyReason:SetShown(empty)
		self.emptyReason:SetText(empty and (why or L.REPORTS_EMPTY_NEXT) or "")
		self.usage:SetShown(not empty)
		self.usageHit:SetShown(not empty)
		self.list:SetShown(not empty and not analytics)
		self.report:SetShown(self.selected ~= nil and not analytics)
		if self.selected and not analytics then paintReport(self) end
		if analytics and not empty then
			if not self.analyticsPage then self.analyticsPage = ns.Analytics.Build(self) end
			self.analyticsPage:Show()
			local enemies = ns.Compare.Overview()
			local known = 0
			for _, row in ipairs(enemies) do
				if not row.unknown then known = known + 1 end
			end
			local recordings = count == 1 and L.REPORTS_COUNT_ONE or L.REPORTS_COUNT:format(count)
			self.usage:SetText(L.ANALYTICS_HEADER:format(recordings,
				known == 1 and L.ANALYTICS_ENEMIES_ONE or L.ANALYTICS_ENEMIES_COUNT:format(known)))
			self.usageMarker:Hide()
			self.usageHit:Hide()   -- its tooltip is about the size, which this line no longer says
		else
			self.usageMarker:Show()
			if self.analyticsPage then self.analyticsPage:Hide() end
		end
		-- a recording that ended while its report was open can be built now
		if self.selected and self.problem == "recording" then
			local h = headerOf(self, self.selected)
			if h and not h.open then self:Rebuild() return end
		end
		self:Layout()
		if analytics and not empty then self.analyticsPage:Refresh() end
	end

	function view:Rebuild()
		local id = self.selected
		self.buildToken = self.buildToken + 1
		local mine = self.buildToken
		self.data, self.problem, self.building = nil, nil, id
		self.model, self.modelProblem = nil, nil
		self.metrics, self.metricsProblem = nil, nil
		paintReport(self)
		self:Layout()
		ns.Report.Build(id, function(report, why)
			if mine ~= self.buildToken or self.selected ~= id then return end
			self.building = nil
			self.data, self.problem = report, why
			if why == "unknown" then self.selected, self.problem = nil, nil end   -- deleted while building
			if report and timelineOn() then self:BuildTimeline(id, mine)           -- after the report
			elseif report and analyticsOn() then self:BuildAnalytics(id, mine) end
			if self:IsVisible() then self:Refresh() end
		end)
	end

	-- The model of the timeline, built in slices by Data/Timeline.lua; a later selection wins.
	function view:BuildTimeline(id, mine)
		local waiting = false
		ns.Timeline.Build(id, function(model, why)
			if mine ~= self.buildToken or self.selected ~= id then return end
			self.model, self.modelProblem = model, why
			if analyticsOn() then self:BuildAnalytics(id, mine) end                -- after the timeline
			if waiting and self:IsVisible() then self:Refresh() end
		end)
		waiting = true
	end

	-- The metrics of the report's Analytics card, built in slices by Data/Metrics.lua; a later selection wins.
	function view:BuildAnalytics(id, mine)
		local waiting = false
		ns.Metrics.Build(id, function(metrics, why)
			if mine ~= self.buildToken or self.selected ~= id then return end
			self.metrics, self.metricsProblem = metrics, why
			if waiting and self:IsVisible() then self:Refresh() end
		end)
		waiting = true
	end

	-- Opens the report of `id` under the list (nil closes it).
	function view:Select(id)
		disarm(self)
		say(self, "")
		if id ~= nil and id == self.selected and (self.data or self.building == id) then
			self:Refresh()
			return
		end
		self.selected, self.data, self.problem, self.building = id, nil, nil, nil
		self.model, self.modelProblem = nil, nil
		self.metrics, self.metricsProblem = nil, nil
		self.buildToken = self.buildToken + 1
		self.report:SetVerticalScroll(0)
		self:Refresh()
		if id and self.selected == id then      -- an id that is not in the list opens nothing
			self:Rebuild()
			self:Refresh()
		end
	end

	view:SetScript("OnHide", function(self) disarm(self) end)

	local Bus = ns.Bus
	if Bus then
		local function changed()
			if view:IsVisible() then view:Refresh() end
		end
		Bus.On("SESSIONS_CHANGED", changed)
		Bus.On("SESSION_STARTED", changed)
		Bus.On("SESSION_ENDED", changed)
		Bus.On("CONFIG_CHANGED", function(path)
			if type(path) == "string" and path:find("^account%.settings") then changed() end
		end)
		-- the summaries are computed at the end of a fight, after the listeners of this one
		Bus.On("COMBAT_ENDED", function() Compat.After(0, changed) end)
		Bus.On("REPORT_REQUESTED", function(id)
			view:SetPage("recordings")
			view:Select(id)
		end)
	end
	Reports.view = view
	view.ready = true
	if view.segmented then view.segmented:Select(Reports.page) end
	return view
end

if ns.addon then ns.addon.Reports = Reports end
