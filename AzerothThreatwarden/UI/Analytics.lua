-- Analytics: the *Analytics* page of the Reports tab and the *Analytics* card of a report (SPEC-06 §3; ui-style §3.6;
-- ADR 0003, 0018). Lua 5.1; no game API (ARC-02): CreateFrame, and the data modules for the rest. Behind the
-- `analytics` switch (ADR 0014): while it is off nothing is built and no listener is registered. Threatwarden's own.
--
-- The page is a view over Data/Compare.lua (the overview by enemy from the headers only, the comparison built one fight
-- at a time, paused in combat) and the card a view over Data/Metrics.lua. Every value carries its category (the pill of
-- the card, a letter beside the value in the table, the word in the tooltip) with the reason and the basis; *Not
-- available*, *Insufficient data* and *Not comparable* are words in text-3, never a number. No ranking and no trend
-- (ANA-01): the enemies and the fights go from the most recent to the oldest.
--
-- With the `export` switch the compare card has an *Export* button that opens UI/ExportBox.lua on that comparison.
--
--   Analytics.Build(parent) -> page    built by UI/Reports.lua the first time the page shows; page:Layout(w, h),
--                                      page:Refresh(), page:Choose(key or false)
--   Analytics.Show(key)                opens the page on the comparison of `key` (the card's *Compare with…*)
--   Analytics.Card(view) -> card       the report's card; Analytics.PaintCard(card, { id, metrics, problem })
--
-- The choices (enemy, filters) stay in memory until the next /reload. Bus: the card emits REPLAY_REQUESTED(id, t) on
-- an unstable interval, only with the `replay` switch. SESSIONS_CHANGED and combat reach the page through
-- UI/Reports.lua and Data/Compare.lua. Rows and cells are pooled: nothing new is made for a comparison already shown.
local ADDON_NAME, ns = ...
ns = ns or {}
ns.modules = ns.modules or {}

local Analytics = {}
ns.Analytics, ns.modules.Analytics = Analytics, Analytics

local L, Widgets, Theme = ns.L, ns.Widgets, ns.Theme
local ipairs, pairs, type, max, min, floor, concat = ipairs, pairs, type, math.max, math.min, math.floor, table.concat

Analytics.ENEMY_HEIGHT = 32
Analytics.ENEMY_ROWS = 5          -- enemies on screen before the list scrolls
Analytics.ROW_HEIGHT = 22
Analytics.CELL_GAP = 10
Analytics.CARD_INTERVALS = 3      -- unstable intervals listed in the report's card
Analytics.TIP_LINES = 32          -- a tooltip of the table says more than the default (a line per measure and its why)

Analytics.key = nil               -- the enemy chosen: a key, false for the unknown enemies, nil for none
Analytics.filters = { group = true, diff = true, role = true }

-- The columns of the comparison, by priority (the last ones go first when the page is narrow, SPEC-06 §3.2). The
-- first measure is the one the cell shows (two for the crossings and the unstable intervals); the others are in its
-- tooltip.
Analytics.COLUMNS = {
	{ id = "date", key = "ANALYTICS_COL_DATE", measures = {} },
	{ id = "length", key = "ANALYTICS_COL_LENGTH", measures = { "fight", "deaths" } },
	{ id = "readable", key = "ANALYTICS_COL_READABLE", measures = { "valid", "validValues" } },
	{ id = "crossings", key = "ANALYTICS_COL_CROSSINGS", measures = { "warningCross", "dangerCross" }, pair = " / " },
	{ id = "danger", key = "ANALYTICS_COL_DANGER", measures = { "dangerAny", "warningAny" } },
	{ id = "holders", key = "ANALYTICS_COL_HOLDERS", measures = { "holders", "aggroTaken" } },
	{ id = "unstable", key = "ANALYTICS_COL_UNSTABLE", measures = { "unstable", "unstableTime" }, pair = " · " },
	{ id = "risk", key = "ANALYTICS_COL_RISK", measures = { "risk" } },
	{ id = "highest", key = "ANALYTICS_COL_HIGHEST",
		measures = { "myMaxPct", "myWarningCross", "myDangerCross", "myWarningTime", "myDangerTime", "myAggro" } },
	{ id = "closest", key = "ANALYTICS_COL_CLOSEST", measures = { "closest" } },
}

local STATUS_WORD = { na = "REPORT_NA", insufficient = "REPORT_INSUFFICIENT",
	["not-comparable"] = "ANALYTICS_NOT_COMPARABLE" }
local MARK = {
	detected = { key = "ANALYTICS_MARK_DETECTED", token = "text-2" },
	calculated = { key = "ANALYTICS_MARK_CALCULATED", token = "text-2" },
	estimated = { key = "ANALYTICS_MARK_ESTIMATED", token = "warn" },
}
local CATEGORY_KEY = { detected = "CAT_DETECTED", calculated = "CAT_CALCULATED", estimated = "CAT_ESTIMATED" }
local GROUP_KEY = { solo = "ANALYTICS_GROUP_SOLO", party = "ANALYTICS_GROUP_PARTY", raid = "ANALYTICS_GROUP_RAID" }
local ROLE_KEY = { TANK = "ROLE_TANK", HEALER = "ROLE_HEALER", DAMAGER = "ROLE_DAMAGER" }
local CLASS_KEY = { elite = "MON_CLASS_ELITE", rare = "MON_CLASS_RARE", rareelite = "MON_CLASS_RAREELITE",
	worldboss = "MON_CLASS_BOSS" }
local SESSION_CELLS = { "valid", "crossings", "stateTime", "holders", "aggroTaken", "unstable", "risk",
	"maxNotHolding" }
local WITH_BASIS = { crossings = true, stateTime = true, unstable = true, risk = true }

local function featureOn(name) return ns.Features ~= nil and ns.Features.On(name) end
local function exportOn() return ns.ExportBox ~= nil and ns.Export ~= nil and ns.Export.On() end

function Analytics.On() return featureOn("analytics") end

local function atLeast(text, lower)
	if lower then return L.REPORT_AT_LEAST:format(text) end
	return text
end

local function tagged(label, value) return L.REPORTS_TIP_LINE:format(label, value) end

local function enemyTitle(name, class)
	if CLASS_KEY[class or ""] then return L.ANALYTICS_ENEMY_CLASS:format(name, L[CLASS_KEY[class]]) end
	return name
end

local function fightsText(n)
	if n == 1 then return L.ANALYTICS_FIGHTS_ONE end
	return L.ANALYTICS_FIGHTS:format(n)
end

local function groupText(row)
	local count, only = 0, nil
	for g in pairs(row.groups or {}) do count, only = count + 1, g end
	if count > 1 then return L.ANALYTICS_GROUP_MIXED end
	return L[GROUP_KEY[only or ""] or "ANALYTICS_GROUP_UNKNOWN"]
end

local function readableText(row)
	if not row.validMin then return L.ANALYTICS_READABLE_UNKNOWN end
	if row.validMin == row.validMax then return L.ANALYTICS_READABLE_ONE:format(row.validMin) end
	return L.ANALYTICS_READABLE_RANGE:format(row.validMin, row.validMax)
end

---------------------------------------------------------------------------------------------------------------------
-- The words of the comparison table
---------------------------------------------------------------------------------------------------------------------
local function measure(id) return ns.Compare.MEASURE[id] end
local function label(id) return L[ns.Compare.MEASURE_KEYS[id]] end

local function addOnce(lines, seen, text)
	if text and not seen[text] then
		seen[text] = true
		lines[#lines + 1] = text
	end
end

-- One measure of one fight: its value with the category, or the word and the reason; then the basis, the valid
-- samples, the coverage and why it is a lower bound (each said once in a tooltip).
local function fightLines(lines, seen, row, id)
	local Compare, Metrics = ns.Compare, ns.Metrics
	local ms = measure(id)
	local v = Compare.Value(row, ms)
	if v.status == "ok" then
		local cat = CATEGORY_KEY[v.category]
		local text = Compare.CellText(ms, v)
		lines[#lines + 1] = tagged(label(id), cat and L.TIP_TAGGED:format(text, L[cat]) or text)
	else
		lines[#lines + 1] = tagged(label(id), L[STATUS_WORD[v.status] or "REPORT_UNKNOWN"])
		if v.status == "not-comparable" then
			addOnce(lines, seen, Compare.NotComparableText(v.nc))
		elseif v.reason == "no-player" then
			addOnce(lines, seen, L.ANALYTICS_WHY_NO_PLAYER)
		else
			addOnce(lines, seen, Metrics.ReasonText({ reason = v.reason, valid = v.valid, coverage = v.coverage }))
		end
	end
	if ms.group == "state" and row.basis then
		addOnce(lines, seen, L.ANALYTICS_TIP_BASIS:format(Compare.BasisText(row.basis)))
	end
	if v.status == "ok" then
		if v.valid then addOnce(lines, seen, L.ANALYTICS_TIP_VALID:format(v.valid)) end
		if v.coverage then addOnce(lines, seen, L.ANALYTICS_COVERAGE:format(v.coverage)) end
		if v.lower then
			for _, text in ipairs(Metrics.LowerLines(v.lowerBy)) do addOnce(lines, seen, text) end
			if row.interrupted then addOnce(lines, seen, L.ANALYTICS_LOWER_INTERRUPTED) end
		end
	end
end

-- One measure over all fights: median, total, lowest and highest (with their fight), the category and how many.
local function aggregateLines(lines, seen, result, id)
	local Compare = ns.Compare
	local agg = result.aggregates[id]
	local ms = measure(id)
	if agg.status ~= "ok" then
		lines[#lines + 1] = tagged(label(id), L.REPORT_INSUFFICIENT)
		addOnce(lines, seen, Compare.AggregateText(agg))
		addOnce(lines, seen, Compare.CountText(agg))
		return
	end
	local parts = {}
	local function part(which, text)
		parts[#parts + 1] = L.ANALYTICS_AGG_PART:format(L[Compare.AGGREGATE_KEYS[which]], text)
	end
	part("median", Compare.AggregateText(agg, "median"))
	if agg.total then part("total", Compare.AggregateText(agg, "total")) end
	for _, which in ipairs({ "min", "max" }) do
		part(which, L.ANALYTICS_AGG_DATED:format(Compare.AggregateText(agg, which),
			ns.Reports.DateText(agg[which].started)))
	end
	if ms.kind == "rate" and agg.rate then part("rate", Compare.NumberText(ms, agg.rate, agg.lower)) end
	lines[#lines + 1] = tagged(label(id), concat(parts, " · "))
	lines[#lines + 1] = L.ANALYTICS_AGG_CATEGORY:format(L[CATEGORY_KEY[agg.category]], Compare.CountText(agg))
	if ms.group == "state" and result.basis then
		addOnce(lines, seen, L.ANALYTICS_TIP_BASIS:format(Compare.BasisText(result.basis)))
	end
	if agg.lower then addOnce(lines, seen, L.ANALYTICS_LOWER_IN_SET) end
	if agg.hz then addOnce(lines, seen, L.ANALYTICS_HZ_DIFFERS) end
end

-- The text and the category of a fight's cell in `column`: a word (no category) when it has no number.
local function fightCell(row, column)
	local Compare = ns.Compare
	local first = Compare.Value(row, measure(column.measures[1]))
	if first.status ~= "ok" then return L[STATUS_WORD[first.status] or "REPORT_UNKNOWN"] end
	local text, category = Compare.CellText(measure(column.measures[1]), first), first.category
	if column.pair then
		local ms = measure(column.measures[2])
		local second = Compare.Value(row, ms)
		if second.status ~= "ok" then return L[STATUS_WORD[second.status] or "REPORT_UNKNOWN"] end
		-- no interval: "0", not "0 · 0:00"
		if not (column.id == "unstable" and first.value == 0) then
			text = text .. column.pair .. Compare.CellText(ms, second)
		end
		if second.category == "estimated" then category = "estimated" end
	end
	return text, category
end

-- The cell of the *All fights* row: the median (the rate over all fights for the risk).
local function allCell(result, column)
	local Compare = ns.Compare
	local id = column.measures[1]
	local agg, ms = result.aggregates[id], measure(id)
	if agg.status ~= "ok" then return L.REPORT_INSUFFICIENT end
	if ms.kind == "rate" then
		if not agg.rate then return L.REPORT_NA end
		return Compare.NumberText(ms, agg.rate, agg.lower), agg.category
	end
	local text, category = Compare.AggregateText(agg, "median"), agg.category
	if column.pair then
		local other = result.aggregates[column.measures[2]]
		if other.status ~= "ok" then return L.REPORT_INSUFFICIENT end
		if not (column.id == "unstable" and agg.median == 0) then
			text = text .. column.pair .. Compare.AggregateText(other, "median")
		end
		if other.category == "estimated" then category = "estimated" end
	end
	return text, category
end

local function cellTip(result, line, column)
	local lines, seen = { L[column.key], maxLines = Analytics.TIP_LINES }, {}
	for _, id in ipairs(column.measures) do
		if line.kind == "all" then aggregateLines(lines, seen, result, id)
		else fightLines(lines, seen, line.row, id) end
	end
	return lines
end

-- The tooltip of a row: the fight, its notes, and the columns that did not fit (SPEC-06 §3.2).
local function rowTip(result, line, shown)
	local Compare = ns.Compare
	local lines, seen = { maxLines = Analytics.TIP_LINES }, {}
	if line.kind == "all" then
		lines[1] = L.ANALYTICS_ALL_FIGHTS
	else
		lines[1] = ns.Reports.DateText(line.row.started)
		for _, note in ipairs(Compare.RowNotes(line.row)) do addOnce(lines, seen, note) end
	end
	if line.kind == "all" or line.row.status == "ok" then
		for i = shown + 1, #Analytics.COLUMNS do
			local column = Analytics.COLUMNS[i]
			local text, category
			if line.kind == "all" then text, category = allCell(result, column)
			else text, category = fightCell(line.row, column) end
			if category then text = L.TIP_TAGGED:format(text, L[CATEGORY_KEY[category]]) end
			lines[#lines + 1] = tagged(L[column.key], text)
		end
	end
	if line.kind == "fight" then lines[#lines + 1] = L.ANALYTICS_OPEN_REPORT end
	return lines
end

---------------------------------------------------------------------------------------------------------------------
-- The table
---------------------------------------------------------------------------------------------------------------------
local function openReport(id)
	local view = ns.Reports.view
	if not view then return end
	view:SetPage("recordings")
	view:Select(id)
end

local function cellFrame(row)
	local cell = CreateFrame("Button", nil, row)
	cell:SetHeight(Analytics.ROW_HEIGHT)
	cell.text = Widgets.Text(cell, "MonoSmall", "text-1", "RIGHT")
	cell.text:SetPoint("RIGHT", cell, "RIGHT", 0, 0)
	cell.mark = Widgets.Text(cell, "Small", "text-2", "RIGHT")
	cell.mark:SetPoint("RIGHT", cell.text, "LEFT", -3, 0)
	cell:SetScript("OnClick", function() if row.fight then openReport(row.fight) end end)
	cell:HookScript("OnEnter", function() Theme.Fill(row.hover, "surface-2", 1) end)
	cell:HookScript("OnLeave", function() Theme.Fill(row.hover, "surface-2", row.isAll and 1 or 0) end)
	Widgets.Tooltip.Attach(cell, function(self) return self.tip end, "TOP")
	return cell
end

local function tableRow(t)
	local row = CreateFrame("Button", nil, t)
	row:SetHeight(Analytics.ROW_HEIGHT)
	Widgets.RowHover(row)
	row.cells = {}
	row.span = Widgets.Text(row, "Small", "text-3", "LEFT")
	row:SetScript("OnClick", function(self) if self.fight then openReport(self.fight) end end)
	row:HookScript("OnLeave", function(self) Theme.Fill(self.hover, "surface-2", self.isAll and 1 or 0) end)
	Widgets.Tooltip.Attach(row, function(self) return self.tip end, "TOP")
	return row
end

local function comparisonTable(card)
	local t = CreateFrame("Frame", nil, card)
	t:SetHeight(Analytics.ROW_HEIGHT)
	t.rows, t.heads, t.shownColumns = {}, {}, 0
	t.measure = Widgets.Text(t, "MonoSmall", "text-1", "LEFT")
	t.measure:Hide()
	t.headMeasure = Widgets.Text(t, "Th", "text-3", "LEFT")
	t.headMeasure:Hide()
	for i, column in ipairs(Analytics.COLUMNS) do
		local fs = Widgets.Text(t, "Th", "text-3", i == 1 and "LEFT" or "RIGHT")
		fs:SetText(L[column.key])
		t.heads[i] = fs
	end

	local function widthOf(fs, text)
		fs:SetText(text)
		return fs:GetStringWidth() or 0
	end

	function t:Reflow(width)
		local result = self.result
		if not result then self:SetHeight(1) return end
		local lines = { { kind = "all" } }
		for _, r in ipairs(result.rows) do lines[#lines + 1] = { kind = "fight", row = r } end
		local alone = result.counted <= 1
		-- the texts of every cell and the widths they need
		local widths = {}
		for i, column in ipairs(Analytics.COLUMNS) do widths[i] = widthOf(self.headMeasure, L[column.key]) end
		for _, line in ipairs(lines) do
			line.cells = {}
			if line.kind == "all" then
				line.date = L.ANALYTICS_ALL_FIGHTS
				if alone then line.span = result.counted == 1 and L.ANALYTICS_ONE_FIGHT or L.ANALYTICS_NO_FIGHT end
			else
				line.date = ns.Reports.DateText(line.row.started)
				if line.row.status ~= "ok" then line.span = L.ANALYTICS_DAMAGED_ROW end
			end
			widths[1] = max(widths[1], widthOf(self.measure, line.date))
			if not line.span then
				for i = 2, #Analytics.COLUMNS do
					local column = Analytics.COLUMNS[i]
					local text, category
					if line.kind == "all" then text, category = allCell(result, column)
					else text, category = fightCell(line.row, column) end
					local w = widthOf(self.measure, text)
					local mark = category and MARK[category]
					if mark then w = w + 3 + widthOf(self.measure, L[mark.key]) end
					widths[i] = max(widths[i], w)
					line.cells[i] = { text = text, category = category }
				end
			end
		end
		local n, total = #Analytics.COLUMNS, 0
		for i = 1, n do
			widths[i] = widths[i] + Analytics.CELL_GAP
			total = total + widths[i]
		end
		while total > width and n > 2 do
			total = total - widths[n]
			n = n - 1
		end
		local extra = max(0, floor((width - total) / n))
		for i = 1, n do widths[i] = widths[i] + extra end
		self.shownColumns, self.widths = n, widths

		local x = 0
		for i, fs in ipairs(self.heads) do
			fs:SetShown(i <= n)
			if i <= n then
				fs:ClearAllPoints()
				fs:SetPoint("TOPLEFT", self, "TOPLEFT", x, -4)
				fs:SetWidth(widths[i] - (i == 1 and 0 or 2))
				x = x + widths[i]
			end
		end
		for index, line in ipairs(lines) do
			local row = self.rows[index]
			if not row then row = tableRow(self) self.rows[index] = row end
			row.fight = line.kind == "fight" and line.row.id or nil
			row.isAll = line.kind == "all"
			row.line = line
			row.tip = rowTip(result, line, n)
			Theme.Fill(row.hover, "surface-2", row.isAll and 1 or 0)
			row:ClearAllPoints()
			row:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -index * Analytics.ROW_HEIGHT)
			row:SetWidth(width)
			local at = 0
			for i = 1, #Analytics.COLUMNS do
				local column = Analytics.COLUMNS[i]
				local cell = row.cells[i]
				if not cell then cell = cellFrame(row) row.cells[i] = cell end
				local data = i == 1 and { text = line.date } or line.cells[i]
				local visible = i <= n and data ~= nil
				cell:SetShown(visible)
				if visible then
					cell:ClearAllPoints()
					cell:SetPoint("TOPLEFT", row, "TOPLEFT", at, 0)
					cell:SetWidth(widths[i])
					cell.text:ClearAllPoints()
					cell.text:SetPoint(i == 1 and "LEFT" or "RIGHT", cell, i == 1 and "LEFT" or "RIGHT", i == 1 and 4 or -2, 0)
					cell.text:SetText(data.text)
					local mark = data.category and MARK[data.category]
					local ink = "text-1"
					if i > 1 and not mark then ink = "text-3"
					elseif data.category == "estimated" then ink = "warn" end
					Theme.Text(cell.text, ink)
					cell.mark:SetShown(mark ~= nil)
					cell.mark:SetText(mark and L[mark.key] or "")
					if mark then Theme.Text(cell.mark, mark.token) end
					cell.column, cell.category = column.id, data.category
					cell.tip = i == 1 and row.tip or cellTip(result, line, column)
				end
				if i <= n then at = at + widths[i] end
			end
			row.span:SetShown(line.span ~= nil)
			row.span:SetText(line.span or "")
			row.span:ClearAllPoints()
			row.span:SetPoint("LEFT", row, "LEFT", widths[1] + 4, 0)
			row.span:SetPoint("RIGHT", row, "RIGHT", -2, 0)
			row:Show()
		end
		for i = #lines + 1, #self.rows do self.rows[i]:Hide() end
		self.lines = #lines
		self:SetHeight((#lines + 1) * Analytics.ROW_HEIGHT)
	end

	return t
end

---------------------------------------------------------------------------------------------------------------------
-- The page
---------------------------------------------------------------------------------------------------------------------
local function enemyRow(page)
	local row = CreateFrame("Button", nil, page.enemies.list.child)
	row:SetHeight(Analytics.ENEMY_HEIGHT)
	Widgets.RowHover(row)
	row.selected = row:CreateTexture(nil, "BACKGROUND")
	Theme.Fill(row.selected, "surface-2", 0)
	row.selected:SetAllPoints(row)
	row.accent = row:CreateTexture(nil, "ARTWORK")
	Theme.Fill(row.accent, "accent", 0)
	row.accent:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
	row.accent:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
	row.accent:SetWidth(2)
	row.name = Widgets.Text(row, "Body", "text-1", "LEFT")
	row.name:SetPoint("TOPLEFT", row, "TOPLEFT", 8, -2)
	row.group = Widgets.Text(row, "Small", "text-2", "RIGHT")
	row.group:SetPoint("TOPRIGHT", row, "TOPRIGHT", -8, -3)
	row.name:SetPoint("RIGHT", row.group, "LEFT", -8, 0)
	row.numbers = Widgets.Text(row, "MonoSmall", "text-2", "LEFT")
	row.numbers:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 8, 3)
	row.numbers:SetPoint("RIGHT", row, "RIGHT", -8, 0)
	row:SetScript("OnClick", function(self) page:Choose(self.key) end)
	Widgets.Tooltip.Attach(row, function(self) return self.tip end, "TOP")
	return row
end

local function paintEnemy(row, data)
	local Compare = ns.Compare
	local key = data.key
	if data.unknown then key = false end
	row.key, row.data = key, data
	local name = Compare.OverviewName(data)
	row.name:SetText(data.unknown and name or enemyTitle(name, data.class))
	Theme.Text(row.name, data.unknown and "text-2" or "text-1")
	row.group:SetText(data.unknown and "" or groupText(data))
	local parts = { fightsText(data.count) }
	local tip = { name }
	tip[#tip + 1] = L.TIP_TAGGED:format(fightsText(data.count), L.CAT_DETECTED)
	if not data.unknown then
		local combat = L.ANALYTICS_IN_COMBAT:format(atLeast(ns.Report.Time(data.fight), data.fightLower))
		local readable = readableText(data)
		parts[#parts + 1] = combat
		parts[#parts + 1] = ns.Reports.DateText(data.last)
		parts[#parts + 1] = readable
		tip[#tip + 1] = groupText(data)
		tip[#tip + 1] = L.TIP_TAGGED:format(combat, L[data.fightLower and "CAT_ESTIMATED" or "CAT_CALCULATED"])
		tip[#tip + 1] = tagged(L.ANALYTICS_LAST, ns.Reports.DateText(data.last))
		tip[#tip + 1] = data.validMin and L.TIP_TAGGED:format(readable, L.CAT_CALCULATED) or readable
		if data.validUnknown > 0 and data.validMin then
			tip[#tip + 1] = L.ANALYTICS_READABLE_SOME_UNKNOWN:format(data.validUnknown)
		end
	else
		tip[#tip + 1] = L.ANALYTICS_UNKNOWN_ENEMY
	end
	row.numbers:SetText(concat(parts, " · "))
	row.tip = tip
	local chosen = Analytics.key == key
	Theme.Fill(row.selected, "surface-2", chosen and 1 or 0)
	Theme.Fill(row.accent, "accent", chosen and 1 or 0)
	row.chosen = chosen
	row:Show()
end

local function filtersRow(page, card)
	local f = CreateFrame("Frame", nil, card)
	f.items = {}
	for _, name in ipairs({ "group", "diff", "role" }) do
		local item = CreateFrame("Frame", nil, f)
		item:SetHeight(20)
		item.switch = Widgets.Switch(item, { small = true, on = Analytics.filters[name], onChange = function(v)
			Analytics.filters[name] = v
			page:Refresh()
		end })
		item.switch:SetPoint("LEFT", item, "LEFT", 0, 0)
		item.label = Widgets.Text(item, "Small", "text-2", "LEFT")
		item.label:SetPoint("LEFT", item.switch, "RIGHT", 6, 0)
		item.label:SetText(L[ns.Compare.FILTER_KEYS[name]])
		f.items[name] = item
	end
	function f:Reflow(width)
		local x, y = 0, 0
		for _, name in ipairs({ "group", "diff", "role" }) do
			local item = self.items[name]
			local w = 32 + 6 + (item.label:GetStringWidth() or 0)
			if x > 0 and x + w > width then x, y = 0, y + 22 end
			item:SetWidth(w)
			item:ClearAllPoints()
			item:SetPoint("TOPLEFT", self, "TOPLEFT", x, -y)
			x = x + w + 16
		end
		self:SetHeight(y + 20)
	end
	return f
end

-- True when `result` is the comparison of the key chosen with the filters chosen.
local function matches(result, key, filters)
	if not result or result.key ~= key then return false end
	for name, value in pairs(filters) do
		if result.filters[name] ~= value then return false end
	end
	return true
end

local function copyFilters()
	local out = {}
	for name, value in pairs(Analytics.filters) do out[name] = value end
	return out
end

-- The context line of a comparison: "5 fights · median 1:42 · readable 62–100 %".
local function contextText(result)
	local Compare = ns.Compare
	local parts = { fightsText(result.counted) }
	local length = result.aggregates.fight
	if length.status == "ok" then
		parts[#parts + 1] = L.ANALYTICS_CONTEXT_MEDIAN:format(Compare.AggregateText(length, "median"))
	end
	local valid = result.aggregates.valid
	if valid.status == "ok" then
		parts[#parts + 1] = L.ANALYTICS_READABLE_RANGE:format(floor(valid.min.value + 0.5), floor(valid.max.value + 0.5))
	end
	return concat(parts, " · ")
end

function Analytics.Build(parent)
	local holder = CreateFrame("Frame", nil, parent)
	local column = ns.Settings.Column(holder)
	local page = holder
	page.column, page.token, page.rows = column, 0, {}

	local enemies = ns.Settings.StackCard(column.frame)
	ns.Settings.CardText(enemies, "H2", "text-1", L.ANALYTICS_ENEMIES, 0)
	enemies.list = ns.Reports.ScrollPane(enemies)
	enemies:Add(enemies.list, 8, { stretch = true })
	page.enemies = enemies

	local compare = ns.Settings.StackCard(column.frame)
	compare.title = ns.Settings.CardText(compare, "H2", "text-1", L.ANALYTICS_COMPARE, 0)
	compare.message = ns.Settings.CardText(compare, "BodyMedium", "text-2", "", 8)
	compare.filters = compare:Add(filtersRow(page, compare), 8, { stretch = true })
	compare.context = ns.Settings.CardText(compare, "Body", "text-2", "", 8)
	compare.notes = ns.Settings.CardText(compare, "Small", "warn", "", 6)
	local buttons = CreateFrame("Frame", nil, compare)
	buttons:SetHeight(28)
	buttons.refresh = Widgets.Button(buttons, { text = L.ANALYTICS_REFRESH, style = "secondary", height = 28,
		onClick = function() page:Start() page:Paint() end })
	buttons.refresh:SetPoint("LEFT", buttons, "LEFT", 0, 0)
	-- the export of the comparison shown (SPEC-06 §4)
	if exportOn() then
		buttons.export = Widgets.Button(buttons, { text = L.EXPORT_BUTTON, style = "secondary", height = 28,
			onClick = function() ns.ExportBox.Open("compare", ns.Compare.Current()) end })
		Widgets.Tooltip.Attach(buttons.export, L.EXPORT_COMPARE_TIP, "TOP")
	end
	compare.buttons = compare:Add(buttons, 6, { stretch = true })
	compare.table = compare:Add(comparisonTable(compare), 10, { stretch = true })
	compare.legend = ns.Settings.CardText(compare, "Small", "text-3", L.ANALYTICS_LEGEND, 6)
	page.compare = compare
	column.cards[1], column.cards[2] = enemies, compare

	-- Starts building the comparison of the key and filters chosen (a build still running is cancelled).
	function page:Start()
		local key = Analytics.key
		if not key then return end
		self.token = self.token + 1
		local mine = self.token
		self.job = { key = key, filters = copyFilters() }
		self.progress = nil
		ns.Compare.Build(key, copyFilters(), function(i, n, paused)
			if mine ~= self.token then return end
			self.progress = { i, n, paused }
			if self:IsVisible() then self:Paint() end
		end, function(result)
			if mine ~= self.token then return end
			self.job, self.progress = nil, nil
			if result and self:IsVisible() then self:Paint() end
		end)
	end

	function page:Paint()
		local Compare = ns.Compare
		local key = Analytics.key
		local chosen
		for i, data in ipairs(self.overview or {}) do
			local row = self.rows[i]
			if row then paintEnemy(row, data) end
			if row and row.key == key then chosen = data end
		end
		local title, message = L.ANALYTICS_COMPARE, nil
		local result
		if key == nil then
			message = L.ANALYTICS_CHOOSE
		elseif key == false then
			message = L.ANALYTICS_UNKNOWN_ENEMY
		else
			title = L.ANALYTICS_COMPARE_OF:format(chosen and Compare.OverviewName(chosen) or L.MON_UNKNOWN_MOB)
			if self.job then
				local p = self.progress
				message = p and Compare.ProgressText(p[1], p[2], p[3]) or nil
			else
				local current = Compare.Current()
				if matches(current, key, Analytics.filters) then result = current end
			end
		end
		compare.title:SetText(title)
		compare.message:SetText(message or "")
		compare.message:SetShown(message ~= nil)
		compare.filters:SetShown(key ~= nil and key ~= false)
		for name, item in pairs(compare.filters.items) do
			item.switch:SetOn(Analytics.filters[name], true)
			local text = L[Compare.FILTER_KEYS[name]]
			if name == "role" and result and ROLE_KEY[result.ref.role or ""] then
				text = L.ANALYTICS_FILTER_ROLE_NAMED:format(L[ROLE_KEY[result.ref.role]])
			end
			item.label:SetText(text)
		end
		compare.context:SetShown(result ~= nil)
		compare.context:SetText(result and contextText(result) or "")
		local notes = result and Compare.NoteLines(result) or {}
		compare.notes:SetText(concat(notes, "\n"))
		compare.notes:SetShown(#notes > 0)
		local fresh = result ~= nil and (result.newFights or 0) > 0
		local rows = result ~= nil and #result.rows > 0
		local export = compare.buttons.export
		if export then
			compare.buttons.refresh:SetShown(fresh)
			export:SetShown(rows)
			export:ClearAllPoints()
			if fresh then export:SetPoint("LEFT", compare.buttons.refresh, "RIGHT", 8, 0)
			else export:SetPoint("LEFT", compare.buttons, "LEFT", 0, 0) end
		end
		compare.buttons:SetShown(fresh or (export ~= nil and rows))
		compare.table.result = rows and result or nil
		compare.table:SetShown(rows)
		compare.legend:SetShown(rows)
		if result and not rows then
			compare.message:SetText(L.ANALYTICS_NO_FIGHT)
			compare.message:Show()
		end
		self:Relayout()
	end

	function page:Relayout()
		local width = self.width_
		if not width or width <= 0 then width = self:GetWidth() end
		if not width or width <= 0 then return end
		local count = self.overview and #self.overview or 0
		enemies.list:SetHeight(max(1, min(count, Analytics.ENEMY_ROWS)) * Analytics.ENEMY_HEIGHT)
		local inner = width - 2 * ns.Settings.CARD_PAD
		for i = 1, count do
			local row = self.rows[i]
			row:ClearAllPoints()
			row:SetPoint("TOPLEFT", enemies.list.child, "TOPLEFT", 0, -(i - 1) * Analytics.ENEMY_HEIGHT)
			row:SetWidth(inner)
		end
		enemies.list:SetContent(inner, count * Analytics.ENEMY_HEIGHT)
		column:Layout(width)
	end

	-- Places the page: `width` x `height` (kept from the last call when not given).
	function page:Layout(width, height)
		self.width_, self.height_ = width or self.width_, height or self.height_
		if self.width_ and self.height_ then self:SetSize(self.width_, self.height_) end
		self:Relayout()
	end

	function page:Refresh()
		self.overview = ns.Compare.Overview()
		local found = Analytics.key == nil
		for i, data in ipairs(self.overview) do
			if not self.rows[i] then self.rows[i] = enemyRow(self) end
			self.rows[i]:Show()
			local key = data.key
			if data.unknown then key = false end
			if key == Analytics.key then found = true end
		end
		for i = #self.overview + 1, #self.rows do self.rows[i]:Hide() end
		if not found then Analytics.key = nil end   -- every recording of that enemy is gone
		local key = Analytics.key
		if key then
			local running = self.job and self.job.key == key
			if running then
				for name, value in pairs(Analytics.filters) do
					if self.job.filters[name] ~= value then running = false end
				end
			end
			if not running then
				if matches(ns.Compare.Current(), key, Analytics.filters) then
					self.job, self.progress = nil, nil
				else
					self:Start()
				end
			end
		elseif self.job then
			self.token, self.job, self.progress = self.token + 1, nil, nil
			ns.Compare.Cancel()
		end
		self:Paint()
	end

	-- The enemy of a row of the overview (false: the unknown ones).
	function page:Choose(key)
		Analytics.key = key
		self:Refresh()
	end

	ns.Compare.OnChange(function() if page:IsVisible() then page:Paint() end end)
	Analytics.page = page
	return page
end

-- Opens the *Analytics* page on the comparison of `key`.
function Analytics.Show(key)
	if not Analytics.On() then return end
	Analytics.key = key
	local view = ns.Reports.view
	if view then view:SetPage("analytics") end
end

---------------------------------------------------------------------------------------------------------------------
-- The card of the report (SPEC-06 §3.3)
---------------------------------------------------------------------------------------------------------------------
-- A line that can be clicked: an unstable interval, or *Compare with…*. :Set(text, token, onClick or nil)
local function linkRow(card)
	local row = CreateFrame("Button", nil, card)
	row.text = Widgets.Text(row, "Small", "text-2", "LEFT")
	row.text:SetWordWrap(true)
	row.text:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -1)
	row:SetScript("OnClick", function(self) if self.onClick then self.onClick() end end)
	function row:Set(text, token, onClick)
		self.text:SetText(text)
		Theme.Text(self.text, token)
		self.onClick = onClick
		self:EnableMouse(onClick ~= nil)
		self:Show()
	end
	function row:Reflow(width)
		self.text:SetWidth(width)
		self:SetHeight((self.text:GetStringHeight() or 14) + 2)
	end
	return row
end

function Analytics.Card(view)
	local card = ns.Settings.StackCard(view.report.child)
	ns.Settings.CardText(card, "H2", "text-1", L.ANALYTICS_PAGE, 0)
	card.message = ns.Settings.CardText(card, "BodyMedium", "text-2", "", 8)
	card.rows, card.intervals = {}, {}
	for _, key in ipairs(SESSION_CELLS) do
		card.rows[key] = card:Add(ns.Reports.MetricRow(card), 10, { stretch = true })
		if key == "unstable" then
			for i = 1, Analytics.CARD_INTERVALS do
				card.intervals[i] = card:Add(linkRow(card), i == 1 and 4 or 2, { stretch = true })
			end
			card.more = ns.Settings.CardText(card, "Small", "text-3", "", 2)
			card.hint = ns.Settings.CardText(card, "Small", "text-3", L.ANALYTICS_REPLAY_HINT, 2)
		end
	end
	card.nothing = ns.Settings.CardText(card, "Body", "text-3", L.ANALYTICS_CARD_NOTHING, 10)
	card.compare = card:Add(linkRow(card), 10, { stretch = true })
	return card
end

local function paintCardMetric(row, metrics, c)
	local info = ns.Reports.CATEGORY[c.category] or ns.Reports.CATEGORY.unknown
	row.cell = c
	row.label:SetText(L[ns.Metrics.METRIC_KEYS[c.key]])
	row.marker:Set(L[info.key], info.token)
	local text = ns.Metrics.Text(metrics, c)
	if c.status ~= "ok" then
		local reason = ns.Metrics.ReasonText(c)
		if reason then text = text .. " · " .. reason end
	elseif WITH_BASIS[c.key] then
		local basis = ns.Report.BasisText(metrics, c.basis)
		if basis then text = text .. "\n" .. basis end
	end
	row.value:SetText(text)
	Theme.Text(row.value, c.status == "ok" and "text-2" or "text-3")
	local tip = { L[ns.Metrics.METRIC_KEYS[c.key]] }
	for _, line in ipairs(ns.Metrics.Tooltip(metrics, c)) do tip[#tip + 1] = line end
	row.tip = tip
	row:Show()
end

-- The other closed recordings against the same enemy.
local function others(key, id)
	local count = 0
	for _, h in ipairs(ns.Storage.List()) do
		if h.id ~= id and not h.open and h.state ~= "open" and ns.Compare.HeaderKey(h) == key then count = count + 1 end
	end
	return count
end

-- state = { id, metrics (nil while building), problem (nil, "damaged" or why Metrics.Build failed) }
function Analytics.PaintCard(card, state)
	local metrics, problem = state.metrics, state.problem
	local message
	if problem == "damaged" then message = L.ANALYTICS_CARD_DAMAGED
	elseif problem then message = L.ANALYTICS_CARD_FAILED
	elseif not metrics then message = L.ANALYTICS_CARD_BUILDING end
	card.message:SetText(message or "")
	card.message:SetShown(message ~= nil)
	local nothing = metrics ~= nil and metrics.outcome == "none"
	for _, key in ipairs(SESSION_CELLS) do
		local row = card.rows[key]
		if metrics and (key == "valid" or not nothing) then paintCardMetric(row, metrics, metrics.cells[key])
		else row:Hide() end
	end
	card.nothing:SetShown(nothing)

	local unstable = metrics and not nothing and metrics.cells.unstable
	local list = unstable and unstable.status == "ok" and unstable.value.list or {}
	local replay = featureOn("replay")
	local shown = min(#list, Analytics.CARD_INTERVALS)
	for i = 1, Analytics.CARD_INTERVALS do
		local row = card.intervals[i]
		if i <= shown then
			local from, id = list[i].from, state.id
			row:Set(ns.Metrics.IntervalText(list[i]), replay and "accent-text" or "text-2", replay and function()
				if ns.Bus then ns.Bus.Emit("REPLAY_REQUESTED", id, from) end
			end or nil)
		else
			row:Hide()
		end
	end
	local rest = shown > 0 and unstable.value.count - shown or 0
	card.more:SetShown(rest > 0)
	card.more:SetText(rest == 1 and L.ANALYTICS_MORE_ONE or rest > 1 and L.ANALYTICS_MORE:format(rest) or "")
	card.hint:SetShown(shown > 0 and replay)

	local key = metrics and metrics.key
	local count = key and not nothing and others(key, state.id) or 0
	if count > 0 then
		local entry = metrics.mobs[metrics.mob or 0]
		local name = entry and entry.name or L.MON_UNKNOWN_MOB
		card.compare:Set(count == 1 and L.ANALYTICS_COMPARE_WITH_ONE:format(name)
			or L.ANALYTICS_COMPARE_WITH:format(count, name), "accent-text", function() Analytics.Show(key) end)
	else
		card.compare:Hide()
	end
	card:Show()
end

if ns.addon then ns.addon.Analytics = Analytics end
