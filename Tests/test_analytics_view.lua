-- UI/Analytics.lua and the changes of UI/Reports.lua (SPEC-06 §3, §6 M6.4; ADR 0003, 0013, 0014; ui-style §3.6): the
-- *Recordings · Analytics* selector, the overview by enemy (nothing decoded), the comparison with its filters, the
-- *All fights* row, Not comparable, Insufficient data and Not available (never a number), the columns dropped under a
-- width, a click opening the report, the report's Analytics card in every outcome, the unstable intervals with and
-- without the `replay` switch, *Compare with…*, every state of the table of §3.4, read-only data and the switch off.

local function features(extra)
	local on = { monitor = true, alerts = true, coach = true, recording = true, reports = true, timeline = true,
		replay = true, analytics = true, export = false }
	for k, v in pairs(extra or {}) do on[k] = v end
	return on
end

before_boot(function(M) M.features = features() end)

local function A() return Mock.ns.Analytics end
local function R() return Mock.ns.Reports end
local function C() return Mock.ns.Compare end
local function W() return AzerothThreatwarden.Window end
local function L() return Mock.ns.L end
local function S() return Mock.ns.Session end
local function St() return Mock.ns.Storage end
local function bus() return Mock.ns.Bus end
local function sessions() return AzerothThreatwardenDB.sessions end

local counter = 0

local function ordered(list)
	local out = {}
	for i, e in ipairs(list) do out[i] = { e = e, i = i } end
	table.sort(out, function(a, b)
		if a.e[1] ~= b.e[1] then return a.e[1] < b.e[1] end
		return a.i < b.i
	end)
	for i, x in ipairs(out) do out[i] = x.e end
	return out
end

local BOSS = { name = "Gorrak", class = "elite", npc = 448 }
local NAMELESS = { class = "normal" }

-- A recorded fight, stored and summarized. o: started, group, mode ("values", "state" or "none"), rec, mob, dur, warn,
-- danger (times the player rises), taken (times Kor takes the enemy), unknown (unreadable samples per unit),
-- interrupted.
local function session(o)
	o = o or {}
	counter = counter + 1
	local mode = o.mode or "values"
	local s = S().New{ id = "av-" .. counter, started = o.started or (1767225600 + counter * 100),
		group = o.group or "party", diff = 1, rec = o.rec or { hz = 2, warning = 80, danger = 95, mode = mode } }
	S().AddUnit(s, { name = "Testchar", role = "DAMAGER", token = "player", me = true }, 0)
	S().AddUnit(s, { name = "Bram", class = "WARRIOR", role = "TANK", token = "party1" }, 0)
	S().AddUnit(s, { name = "Kor", class = "ROGUE", role = "DAMAGER", token = "party2" }, 0)
	S().AddMob(s, o.mob or BOSS, 0)
	local dur = o.dur or 1000
	local events = { { 0, "C", 0, 0, 0, "1" },
		{ 0, "M", 0, 0, 0, mode == "state" and "s" or mode == "none" and "n" or "v", mode == "none" and "S" or nil },
		{ 0, "T", 1 }, { 0, "A", 1, 2, 0, "1" }, { 0, "S", 1, 1, 0, "S", "-" }, { 0, "S", 1, 2, 0, "S", "-" },
		{ 0, "S", 1, 3, 0, "S", "-" } }
	for _, t in ipairs(o.warn or {}) do
		events[#events + 1] = { t, "S", 1, 1, 0, "W", "S" }
		events[#events + 1] = { t + 1, "S", 1, 1, 0, "S", "W" }
	end
	for _, t in ipairs(o.danger or {}) do
		events[#events + 1] = { t, "S", 1, 1, 0, "D", "S" }
		events[#events + 1] = { t + 1, "S", 1, 1, 0, "S", "D" }
	end
	for _, t in ipairs(o.taken or {}) do
		events[#events + 1] = { t, "A", 1, 3, 2, "0", "1" }
		events[#events + 1] = { t + 5, "A", 1, 2, 3, "1", "0" }
	end
	events[#events + 1] = { dur, o.interrupted and "X" or "c" }
	for _, e in ipairs(ordered(events)) do
		truthy(S().AddEvent(s, e[1], e[2], e[3], e[4], e[5], e[6], e[7], e[8], e[9]), "event at " .. e[1])
	end
	for i, t in ipairs({ 50, 150, 250 }) do
		if mode == "state" then
			S().AddRow(s, t, 1, 1, -1, "a")
			S().AddRow(s, t, 1, 2, -1, "d")
			S().AddRow(s, t, 1, 3, -1, "b")
		elseif mode == "none" then
			for u = 1, 3 do S().AddRow(s, t, 1, u, -1, "S") end
		else
			S().AddRow(s, t, 1, 1, 400 + i * 10, "0")
			S().AddRow(s, t, 1, 2, 1000, "3")
			S().AddRow(s, t, 1, 3, 300 + i, "0")
		end
	end
	for i = 1, 3 do
		if mode == "state" then s.q.s[i] = 100
		elseif mode == "none" then s.q.x[i] = 100
		else s.q.v[i] = 100 - (o.unknown or 0) s.q.x[i] = o.unknown or 0 end
	end
	S().Join(s)
	s.state, s.ended = o.interrupted and "interrupted" or "complete", o.interrupted and "reload" or "combat"
	s.dur, s.fight = dur, o.interrupted and 0 or dur
	truthy(St().Add(s))
	truthy(St().Closed(s, true))
	return s
end

local function frames() for _ = 1, 100 do Mock.Advance(0.05) end end

local function openTab()
	W():Open()
	truthy(W():SelectTab("reports"))
	local view = W():Frame().pages.reports.view
	view:Layout(900, 600)
	return view
end

local function analytics()
	local view = openTab()
	view.segmented.buttons.analytics:Click()
	frames()
	return view, view.analyticsPage
end

local function enemy(page, key)
	for _, row in ipairs(page.rows) do
		if row:IsShown() and row.key == key then return row end
	end
end

-- Chooses the enemy of `key` and waits for its comparison.
local function choose(page, key)
	local row = enemy(page, key)
	notNil(row, "a row for " .. tostring(key))
	row:Click()
	frames()
	return page.compare.table
end

local function tableRows(t)
	local out = {}
	for _, row in ipairs(t.rows) do if row:IsShown() then out[#out + 1] = row end end
	return out
end

local function cellOf(row, id)
	for _, cell in ipairs(row.cells) do
		if cell:IsShown() and cell.column == id then return cell end
	end
end

local function tooltip(widget)
	Mock.RunScript(widget, "OnEnter")
	local lines = table.concat(Mock.ns.Widgets.Tooltip.Lines(), "\n")
	Mock.RunScript(widget, "OnLeave")
	return lines
end

local function report(view, s)
	view:Select(s.id)
	frames()
	return view.analytics
end

describe("the selector (SPEC-06 §3.1)", function()
	it("shows Recordings as before and Analytics on a click, with the recordings and enemies in the header", function()
		session()
		session{ mob = { name = "Pup", class = "normal", npc = 7 } }
		local view = openTab()
		eq(view.segmented:Active(), "recordings")
		truthy(view.list:IsShown())
		matches(view.usage:GetText(), "^2 recordings · about ")
		view.segmented.buttons.analytics:Click()
		frames()
		falsy(view.list:IsShown())
		falsy(view.report:IsShown())
		truthy(view.analyticsPage:IsShown())
		eq(view.usage:GetText(), "2 recordings · 2 enemies")
		falsy(view.usageMarker:IsShown())
		view.segmented.buttons.recordings:Click()
		truthy(view.list:IsShown())
		falsy(view.analyticsPage:IsShown())
		truthy(view.usageMarker:IsShown())
		eq(#Mock.errors, 0)
	end)

	it("remembers the page until a /reload, and /atw reports opens Recordings", function()
		session()
		local view = analytics()
		W():SelectTab("monitor")
		W():SelectTab("reports")
		eq(view.segmented:Active(), "analytics")
		truthy(Mock.Slash("/atw reports"))
		eq(view.segmented:Active(), "recordings")
		view.segmented.buttons.analytics:Click()
		Mock.Reload()
		eq(openTab().segmented:Active(), "recordings")
	end)

	it("keeps the open report when coming back, and REPORT_REQUESTED opens Recordings", function()
		local s = session()
		local view = openTab()
		view:Select(s.id)
		view.segmented.buttons.analytics:Click()
		falsy(view.report:IsShown())
		view.segmented.buttons.recordings:Click()
		eq(view.selected, s.id)
		truthy(view.report:IsShown())
		view.segmented.buttons.analytics:Click()
		bus().Emit("REPORT_REQUESTED", s.id)
		eq(view.segmented:Active(), "recordings")
		truthy(view.report:IsShown())
	end)

	it("says No recordings yet on an empty list", function()
		local view = analytics()
		truthy(view.empty:IsShown())
		eq(view.empty:GetText(), L().REPORTS_EMPTY)
		falsy(view.analyticsPage and view.analyticsPage:IsShown())
		eq(#Mock.errors, 0)
	end)

	it("keeps the selector and the page in the smallest window", function()
		session()
		local view = analytics()
		view:Layout(440, 300)
		truthy(view.analyticsPage:GetHeight() >= 40)
		view:Layout(300, 300)
		eq(#Mock.errors, 0)
	end)
end)

describe("the overview (SPEC-06 §2.3, §3.2)", function()
	it("lists the enemies newest first with their numbers and categories, decoding nothing", function()
		session{ mob = { name = "Pup", class = "normal", npc = 7 } }
		session{ mob = NAMELESS }
		session()
		session{ dur = 500 }
		St().Decode = function() error("the overview decodes nothing") end
		local _, page = analytics()
		local shown = {}
		for _, row in ipairs(page.rows) do if row:IsShown() then shown[#shown + 1] = row end end
		eq(#shown, 3)
		eq(shown[1].name:GetText(), "Gorrak (Elite)")
		eq(shown[2].name:GetText(), "Pup")
		eq(shown[3].name:GetText(), L().ANALYTICS_UNKNOWN_ENEMIES)
		eq(shown[1].group:GetText(), L().ANALYTICS_GROUP_PARTY)
		contains(shown[1].numbers:GetText(), "2 fights · 2:30 in combat · 2026-01-01")
		contains(shown[1].numbers:GetText(), "readable 100 %")
		local tip = tooltip(shown[1])
		contains(tip, "2 fights (" .. L().CAT_DETECTED .. ")")
		contains(tip, "in combat (" .. L().CAT_CALCULATED .. ")")
		eq(shown[1]:GetHeight(), A().ENEMY_HEIGHT)
		eq(page.compare.message:GetText(), L().ANALYTICS_CHOOSE)
		falsy(page.compare.filters:IsShown())
		falsy(page.compare.table:IsShown())
		eq(#Mock.errors, 0)
	end)

	it("says that unknown enemies cannot be compared", function()
		session{ mob = NAMELESS }
		local _, page = analytics()
		choose(page, false)
		eq(page.compare.message:GetText(), L().ANALYTICS_UNKNOWN_ENEMY)
		falsy(page.compare.table:IsShown())
		falsy(page.compare.filters:IsShown())
	end)

	it("highlights the chosen enemy and makes no new row the second time", function()
		session()
		session()
		local _, page = analytics()
		local t = choose(page, "npc:448")
		truthy(enemy(page, "npc:448").chosen)
		local made = #t.rows
		choose(page, "npc:448")
		eq(#t.rows, made)
	end)
end)

describe("the comparison (SPEC-06 §3.2)", function()
	it("shows All fights first, then the fights newest first, each value with its category letter", function()
		local old = session{ dur = 1000, warn = { 100, 300 } }
		local new = session{ dur = 2000, warn = { 100 }, danger = { 300 } }
		local _, page = analytics()
		local t = choose(page, "npc:448")
		contains(page.compare.title:GetText(), "Gorrak")
		contains(page.compare.context:GetText(), "2 fights · median 2:30 · readable 100–100 %")
		local rows = tableRows(t)
		eq(#rows, 3)
		eq(cellOf(rows[1], "date").text:GetText(), L().ANALYTICS_ALL_FIGHTS)
		eq(cellOf(rows[2], "date").text:GetText(), R().DateText(new.started))
		eq(cellOf(rows[3], "date").text:GetText(), R().DateText(old.started))
		eq(cellOf(rows[2], "length").text:GetText(), "3:20")
		eq(cellOf(rows[2], "length").mark:GetText(), L().ANALYTICS_MARK_DETECTED)
		eq(cellOf(rows[3], "crossings").text:GetText(), "2 / 0")
		eq(cellOf(rows[2], "crossings").text:GetText(), "1 / 1")
		eq(cellOf(rows[2], "crossings").mark:GetText(), L().ANALYTICS_MARK_CALCULATED)
		eq(cellOf(rows[1], "crossings").text:GetText(), "1.5 / 0.5")
		eq(page.compare.legend:GetText(), L().ANALYTICS_LEGEND)
		eq(#Mock.errors, 0)
	end)

	it("gives every aggregate with its category, count, basis and fight in the tooltips", function()
		session{ danger = { 300 } }
		session{ danger = { 300, 500 } }
		local _, page = analytics()
		local rows = tableRows(choose(page, "npc:448"))
		local tip = tooltip(cellOf(rows[1], "crossings"))
		contains(tip, L().ANALYTICS_M_DANGER_CROSS .. ": Median 1.5 · Total 3 · Lowest 1 (")
		contains(tip, "Highest 2 (")
		contains(tip, "Category: " .. L().CAT_CALCULATED .. " · 2 of 2 fights")
		contains(tip, "Basis: thresholds 80 / 95")
		contains(tooltip(cellOf(rows[1], "risk")), L().ANALYTICS_AGG_RATE)
		-- every measure has a cell that tells it
		local told = {}
		for _, column in ipairs(A().COLUMNS) do
			for _, id in ipairs(column.measures) do told[id] = true end
		end
		for _, ms in ipairs(C().MEASURES) do truthy(told[ms.id], ms.id) end
	end)

	it("tells a fight's value, category, basis and reason in the cell tooltip", function()
		session{ danger = { 300 } }
		session{ danger = { 300 }, interrupted = true }
		local _, page = analytics()
		local rows = tableRows(choose(page, "npc:448"))
		local cell = cellOf(rows[2], "crossings")
		eq(cell.mark:GetText(), L().ANALYTICS_MARK_ESTIMATED)
		contains(cell.text:GetText(), "at least")
		local tip = tooltip(cell)
		contains(tip, L().ANALYTICS_M_DANGER_CROSS .. ": at least 1 (" .. L().CAT_ESTIMATED .. ")")
		contains(tip, "Basis: thresholds 80 / 95")
		contains(tip, L().ANALYTICS_LOWER_INTERRUPTED)
		contains(tooltip(cellOf(rows[2], "date")), L().ANALYTICS_LOWER_INTERRUPTED)
	end)

	it("says Not comparable for other thresholds, with the reason, and never a number", function()
		session{ rec = { hz = 2, warning = 70, danger = 90, mode = "values" } }
		session()
		local _, page = analytics()
		local rows = tableRows(choose(page, "npc:448"))
		local cell = cellOf(rows[3], "crossings")
		eq(cell.text:GetText(), L().ANALYTICS_NOT_COMPARABLE)
		falsy(cell.mark:IsShown())
		contains(tooltip(cell), "Not comparable: thresholds 70 / 90 and 80 / 95")
		eq(cellOf(rows[1], "crossings").text:GetText(), L().REPORT_INSUFFICIENT)
		contains(tooltip(cellOf(rows[1], "crossings")), L().ANALYTICS_ONE_FIGHT)
	end)

	it("says Insufficient data under half the samples, with the percentage", function()
		session{ unknown = 80 }
		session()
		local _, page = analytics()
		local rows = tableRows(choose(page, "npc:448"))
		local cell = cellOf(rows[3], "crossings")
		eq(cell.text:GetText(), L().REPORT_INSUFFICIENT)
		falsy(cell.mark:IsShown())
		contains(tooltip(cell), "Fewer than half the samples readable: 20 %")
	end)

	it("says Not available for the percentages of a fight with states only", function()
		session{ mode = "state" }
		session{ mode = "state" }
		local _, page = analytics()
		local rows = tableRows(choose(page, "npc:448"))
		for i = 2, 3 do
			eq(cellOf(rows[i], "closest").text:GetText(), L().REPORT_NA)
			falsy(cellOf(rows[i], "closest").mark:IsShown())
			eq(cellOf(rows[i], "highest").text:GetText(), L().REPORT_NA)
		end
		eq(cellOf(rows[1], "closest").text:GetText(), L().REPORT_INSUFFICIENT)
		contains(tooltip(cellOf(rows[2], "crossings")), L().ANALYTICS_BASIS_GAME)
	end)

	it("says Only one comparable fight with one fight", function()
		session()
		local _, page = analytics()
		local rows = tableRows(choose(page, "npc:448"))
		eq(#rows, 2)
		eq(rows[1].span:GetText(), L().ANALYTICS_ONE_FIGHT)
		falsy(cellOf(rows[1], "length"))
		notNil(cellOf(rows[2], "length"))
	end)

	it("shows a damaged recording as a row that does not count", function()
		local bad = session()
		session()
		session()
		bad.cols.m = string.rep("z", #bad.cols.m)
		local _, page = analytics()
		local rows = tableRows(choose(page, "npc:448"))
		eq(#rows, 4)
		eq(rows[4].span:GetText(), L().ANALYTICS_DAMAGED_ROW)
		truthy(rows[4].span:IsShown())
		contains(page.compare.context:GetText(), "2 fights")
		contains(page.compare.notes:GetText(), "1 damaged recording not counted")
		eq(#Mock.errors, 0)
	end)

	it("drops the last columns under a width and keeps them in the row tooltip", function()
		session()
		session()
		local view, page = analytics()
		local t = choose(page, "npc:448")
		view:Layout(1400, 600)
		eq(t.shownColumns, #A().COLUMNS)
		view:Layout(440, 400)
		truthy(t.shownColumns < #A().COLUMNS)
		truthy(t.shownColumns >= 2)
		local rows = tableRows(t)
		falsy(cellOf(rows[2], "closest"))
		local total = 0
		for i = 1, t.shownColumns do total = total + t.widths[i] end
		truthy(total <= 440 - 2 * Mock.ns.Settings.CARD_PAD or t.shownColumns == 2, "no text cut: " .. total)
		local tip = tooltip(rows[2])
		contains(tip, L().ANALYTICS_COL_CLOSEST .. ": ")
		contains(tip, L().CAT_DETECTED)
		contains(tip, L().ANALYTICS_OPEN_REPORT)
		eq(#Mock.errors, 0)
	end)

	it("filters by group size and switches the filter off", function()
		session{ group = "raid" }
		session()
		session()
		local _, page = analytics()
		local t = choose(page, "npc:448")
		eq(#tableRows(t), 3)
		contains(page.compare.notes:GetText(), "1 fight left out by the filters")
		local item = page.compare.filters.items.group
		truthy(item.switch:IsOn())
		item.switch:Click()
		frames()
		eq(#tableRows(t), 4)
		falsy(A().filters.group)
		eq(page.compare.filters.items.role.label:GetText(), "Same role (Damage)")
	end)

	it("opens the report of a fight on a click on its row or on a value", function()
		local s = session()
		session()
		local view, page = analytics()
		local rows = tableRows(choose(page, "npc:448"))
		cellOf(rows[3], "length"):Click()
		eq(view.segmented:Active(), "recordings")
		eq(view.selected, s.id)
		view.segmented.buttons.analytics:Click()
		rows = tableRows(page.compare.table)
		rows[2]:Click()
		eq(view.selected, sessions()[#sessions()].id)
		view.segmented.buttons.analytics:Click()
		page.compare.table.rows[1]:Click()
		eq(view.segmented:Active(), "analytics", "All fights opens nothing")
	end)

	it("says Building and pauses in combat, then goes on", function()
		for _ = 1, 4 do session() end
		local _, page = analytics()
		AzerothThreatwarden.inCombat = true
		enemy(page, "npc:448"):Click()
		eq(page.compare.message:GetText(), L().ANALYTICS_PAUSED)
		falsy(page.compare.table:IsShown())
		frames()
		eq(page.compare.message:GetText(), L().ANALYTICS_PAUSED)
		AzerothThreatwarden.inCombat = false
		Mock.ns.Metrics.SLICE = 5
		bus().Emit("COMBAT_ENDED")
		matches(page.compare.message:GetText(), "^Building %d of 4")
		frames()
		falsy(page.compare.message:IsShown())
		eq(#tableRows(page.compare.table), 5)
		eq(#Mock.errors, 0)
	end)

	it("takes a deleted fight out and offers Refresh for a new one", function()
		local a = session()
		session()
		session()
		local _, page = analytics()
		local t = choose(page, "npc:448")
		eq(#tableRows(t), 4)
		truthy(St().Delete(a.id))
		eq(#tableRows(t), 3)
		contains(page.compare.notes:GetText(), "1 deleted fight left out")
		falsy(page.compare.buttons:IsShown())
		session()
		bus().Emit("SESSIONS_CHANGED")
		truthy(page.compare.buttons:IsShown())
		contains(page.compare.notes:GetText(), "1 new fight: Refresh")
		page.compare.buttons.refresh:Click()
		frames()
		eq(#tableRows(t), 4)
		falsy(page.compare.buttons:IsShown())
	end)

	it("forgets an enemy whose recordings are all gone", function()
		local only = session()
		session{ mob = { name = "Pup", class = "normal", npc = 7 } }
		local _, page = analytics()
		choose(page, "npc:448")
		truthy(St().Delete(only.id))
		isNil(A().key)
		eq(page.compare.message:GetText(), L().ANALYTICS_CHOOSE)
		falsy(page.compare.table:IsShown())
		eq(#Mock.errors, 0)
	end)

	it("never holds the open recording", function()
		local pull = Fight.new{ player = { class = "MAGE" }, mobs = { { key = "boss", tokens = { "target" } } },
			party = { { key = "tank", role = "TANK" } } }
		pull:at(0):start():threat("boss", "tank", 1000):threat("boss", "player", 10)
		pull:to(2)
		eq(#sessions(), 1)
		local _, page = analytics()
		for _, row in ipairs(page.rows) do falsy(row:IsShown()) end
	end)
end)

describe("the Analytics card of a report (SPEC-06 §3.3)", function()
	it("follows the Timeline card with every metric, its marker, tooltip and basis", function()
		local s = session{ danger = { 300 }, taken = { 500 } }
		local view = openTab()
		local card = report(view, s)
		truthy(card:IsShown())
		eq(view.report.cards[2], view.timeline)
		eq(view.report.cards[3], card)
		eq(view.report.cards[4], view.fight)
		falsy(card.message:IsShown())
		for _, key in ipairs({ "valid", "crossings", "stateTime", "holders", "aggroTaken", "unstable", "risk",
			"maxNotHolding" }) do
			local row = card.rows[key]
			truthy(row:IsShown(), key)
			truthy(row.marker.label:GetText() ~= "", key)
			contains(tooltip(row), L()[Mock.ns.Metrics.METRIC_KEYS[key]])
		end
		contains(card.rows.crossings.value:GetText(), "0 Warning · 1 Danger")
		contains(card.rows.crossings.value:GetText(), "Warning from 80 %, Danger from 95 %")
		contains(card.rows.valid.value:GetText(), "enemy monitored")
		falsy(card.nothing:IsShown())
		eq(#Mock.errors, 0)
	end)

	it("follows the head card with the timeline switched off", function()
		T.boot(function(M) M.features = features{ timeline = false, replay = false } end)
		local s = session()
		local view = openTab()
		local card = report(view, s)
		eq(view.report.cards[2], card)
		notNil(view.metrics)
	end)

	it("says Building analytics while it is built, after the report, in combat too", function()
		local s = session()
		Mock.ns.Metrics.SLICE = 2
		AzerothThreatwarden.inCombat = true
		local view = openTab()
		view:Select(s.id)
		for _ = 1, 400 do
			if view.data and view.analytics and view.analytics.message:IsShown() then break end
			Mock.Advance(0.01)
		end
		eq(view.analytics.message:GetText(), L().ANALYTICS_CARD_BUILDING)
		for _ = 1, 4 do frames() end
		notNil(view.metrics)
		falsy(view.analytics.message:IsShown())
	end)

	it("shows state-only metrics with Not available where values are needed", function()
		local s = session{ mode = "state" }
		local card = report(openTab(), s)
		local row = card.rows.maxNotHolding
		contains(row.value:GetText(), L().REPORT_NA)
		eq(row.marker.label:GetText(), L().CAT_UNKNOWN)
		contains(card.rows.crossings.value:GetText(), L().REPORT_BASIS_GAME)
	end)

	it("says Insufficient data with the reason beside it", function()
		local s = session{ unknown = 80 }
		local card = report(openTab(), s)
		eq(card.rows.crossings.value:GetText(),
			L().REPORT_INSUFFICIENT .. " · Fewer than half the samples readable: 20 %")
		eq(card.rows.crossings.marker.label:GetText(), L().CAT_UNKNOWN)
	end)

	it("keeps only the readable samples row and a note with nothing readable", function()
		local s = session{ mode = "none" }
		local card = report(openTab(), s)
		truthy(card.rows.valid:IsShown())
		for _, key in ipairs({ "crossings", "holders", "unstable", "risk", "maxNotHolding" }) do
			falsy(card.rows[key]:IsShown(), key)
		end
		truthy(card.nothing:IsShown())
		falsy(card.compare:IsShown())
	end)

	local function unstableSession()
		return session{ warn = { 100, 120, 140, 400, 420, 440, 600, 620, 640, 800, 820, 840 } }
	end

	it("lists the first three unstable intervals and replays one on a click", function()
		local s = unstableSession()
		local asked = {}
		bus().On("REPLAY_REQUESTED", function(id, t) asked[#asked + 1] = { id, t } end)
		local card = report(openTab(), s)
		for i = 1, 3 do truthy(card.intervals[i]:IsShown()) end
		contains(card.intervals[1].text:GetText(), "0:10")
		contains(card.more:GetText(), "1 more interval")
		truthy(card.hint:IsShown())
		card.intervals[2]:Click()
		eq(#asked, 1)
		deepEq(asked[1], { s.id, 400 })
	end)

	it("lists them without a click with the replay switched off", function()
		T.boot(function(M) M.features = features{ replay = false } end)
		local s = unstableSession()
		local asked = {}
		bus().On("REPLAY_REQUESTED", function(id, t) asked[#asked + 1] = { id, t } end)
		local card = report(openTab(), s)
		truthy(card.intervals[1]:IsShown())
		falsy(card.hint:IsShown())
		card.intervals[1]:Click()
		eq(#asked, 0)
	end)

	it("offers Compare with the other fights and opens the page on that enemy", function()
		local s = session()
		session()
		session{ mob = { name = "Pup", class = "normal", npc = 7 } }
		local view = openTab()
		local card = report(view, s)
		eq(card.compare.text:GetText(), "Compare with 1 other fight against Gorrak")
		card.compare:Click()
		frames()
		eq(view.segmented:Active(), "analytics")
		eq(A().key, "npc:448")
		eq(#tableRows(view.analyticsPage.compare.table), 3)
		eq(#Mock.errors, 0)
	end)

	it("has no Compare line for the only fight against an enemy", function()
		local card = report(openTab(), session())
		falsy(card.compare:IsShown())
	end)

	it("says a damaged recording was set aside", function()
		local s = session()
		s.cols.m = string.rep("z", #s.cols.m)
		local view = openTab()
		view:Select(s.id)
		frames()
		eq(view.analytics.message:GetText(), L().ANALYTICS_CARD_DAMAGED)
		falsy(view.analytics.rows.valid:IsShown())
	end)

	it("says when the analytics cannot be built", function()
		local s = session()
		Mock.ns.Metrics.Compute = function() error("boom") end
		local card = report(openTab(), s)
		eq(card.message:GetText(), L().ANALYTICS_CARD_FAILED)
		falsy(card.rows.crossings:IsShown())
	end)

	it("closes with the report and a later selection wins", function()
		local a, b = session(), session{ mob = { name = "Pup", class = "normal", npc = 7 } }
		Mock.ns.Metrics.SLICE = 5
		local view = openTab()
		view:Select(a.id)
		view:Select(b.id)
		frames()
		eq(view.metrics.id, b.id)
		view:Select(nil)
		falsy(view.report:IsShown())
		truthy(St().Delete(b.id))
		eq(#Mock.errors, 0)
	end)
end)

describe("read-only data", function()
	it("are analysed the same and never changed", function()
		session()
		session()
		local saved = { sessions()[1], sessions()[2] }
		T.boot(function(M)
			M.features = features()
			M.saved = { AzerothThreatwardenDB = { schema = 99, sessions = saved } }
		end)
		local view, page = analytics()
		eq(#tableRows(choose(page, "npc:448")), 3)
		view.segmented.buttons.recordings:Click()
		notNil(report(view, saved[1]))
		eq(#sessions(), 2)
		eq(#Mock.errors, 0)
	end)
end)

describe("in Italian", function()
	before_boot(function(M) M.features = features() M.player.locale = "itIT" end)
	it("writes the page and the card in Italian", function()
		local s = session{ unknown = 80 }
		session()
		local view, page = analytics()
		local rows = tableRows(choose(page, "npc:448"))
		eq(cellOf(rows[2], "length").mark:GetText(), "R")
		eq(cellOf(rows[3], "crossings").text:GetText(), "Dati insufficienti")
		contains(view.usage:GetText(), "1 nemico")
		report(view, s)
		view.segmented.buttons.recordings:Click()
		contains(view.analytics.rows.crossings.value:GetText(), "Dati insufficienti")
		eq(#Mock.errors, 0)
	end)
end)

describe("with the `analytics` switch off", function()
	before_boot(function(M) M.features = features{ analytics = false } end)
	it("shows no selector, no card, no page and listens to nothing", function()
		local s = session()
		local view = openTab()
		isNil(view.segmented)
		view:Select(s.id)
		frames()
		isNil(view.analytics)
		isNil(view.analyticsPage)
		eq(view.report.cards[3], view.fight)
		view:SetPage("analytics")
		A().Show("npc:448")
		R().ShowPage("analytics")
		truthy(view.list:IsShown())
		falsy(Mock.ns.Metrics.Listening())
		falsy(C().Listening())
		eq(#Mock.errors, 0)
	end)
end)
