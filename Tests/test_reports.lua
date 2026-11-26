-- UI/Reports.lua (SPEC-05 §3.6, §7 M4.5; ADR 0003): the Reports tab. The list (newest first, badges, the player's worst
-- state), the selection and the report with a category marker and a reason for every metric, the empty list with each
-- reason, deletion with a second click that survives a /reload, read-only data, combat, and nothing with the switch off.

local function ALL() return { monitor = true, alerts = true, coach = true, recording = true, reports = true } end

before_boot(function(M) M.features = ALL() end)

local function R() return Mock.ns.Reports end
local function W() return AzerothThreatwarden.Window end
local function L() return Mock.ns.L end
local function St() return Mock.ns.Storage end
local function S() return Mock.ns.Session end
local function Config() return Mock.ns.Config end
local function bus() return Mock.ns.Bus end
local function sessions() return AzerothThreatwardenDB.sessions end

local counter = 0

-- A recording added to the store: spec.dur, started, state, ended, trunc, after, zone, mob (name), player states.
local function add(spec)
	spec = spec or {}
	counter = counter + 1
	local s = S().New{ id = spec.id or ("r-" .. counter), started = spec.started or (1767225600 + counter * 100),
		group = "party", zone = spec.zone, rec = { hz = 2, warning = 80, danger = 95 }, after = spec.after }
	S().AddUnit(s, { name = "Testchar", role = "DAMAGER", token = "player", me = true }, 0)
	S().AddUnit(s, { name = "Bram", class = "WARRIOR", role = "TANK", token = "party1" }, 0)
	S().AddMob(s, { name = spec.mob or "Gorrak", class = "elite", npc = 448 }, 0)
	local events = spec.events or {
		{ 0, "C", 0, 0, 0, "1" }, { 0, "M", 0, 0, 0, "v" }, { 0, "T", 1 }, { 0, "A", 1, 2, 0, "1" },
		{ 0, "S", 1, 1, 0, "S", "-" }, { 100, "S", 1, 1, 0, "W", "S" }, { 300, "S", 1, 1, 0, "S", "W" },
		{ 400, "c" },
	}
	for _, e in ipairs(events) do S().AddEvent(s, e[1], e[2], e[3], e[4], e[5], e[6], e[7], e[8], e[9]) end
	local rows = spec.rows or {
		{ 10, 1, 1, 400, "0" }, { 10, 1, 2, 1000, "3" }, { 100, 1, 1, 820, "0" }, { 200, 1, 1, 850, "0" },
		{ 300, 1, 1, 500, "0" }, { 300, 1, 2, 1000, "3" },
	}
	for _, r in ipairs(rows) do S().AddRow(s, r[1], r[2], r[3], r[4], r[5]) end
	for i, v in ipairs({ 80, 80 }) do s.q.v[i] = v end
	S().Join(s)
	s.state, s.ended = spec.state or "complete", spec.ended or "combat"
	s.dur, s.fight, s.trunc = spec.dur or 400, spec.dur or 400, spec.trunc
	truthy(St().Add(s))
	St().Closed(s, true)
	return s
end

local function openTab()
	W():Open()
	truthy(W():SelectTab("reports"))
	return W():Frame().pages.reports.view
end

local function shownRows(view)
	local out = {}
	for _, row in ipairs(view.rows) do if row:IsShown() then out[#out + 1] = row end end
	return out
end

local function pillTexts(row)
	local out = {}
	for _, p in ipairs(row.pills) do if p:IsShown() then out[#out + 1] = p.label:GetText() end end
	return table.concat(out, "|")
end

local function metrics(card)
	local out = {}
	for _, row in ipairs(card.rows) do if row:IsShown() then out[row.cell.key] = row end end
	return out
end

local function tooltip(widget)
	Mock.RunScript(widget, "OnEnter")
	local lines = table.concat(Mock.ns.Widgets.Tooltip.Lines(), "\n")
	Mock.RunScript(widget, "OnLeave")
	return lines
end

describe("the list", function()
	it("shows the recordings newest first, with the use of the store as an estimate", function()
		add{ zone = "Gloomhold", mob = "Gorrak" }
		add{ zone = "Frostpeak", mob = "Pup", dur = 1020 }
		local view = openTab()
		local rows = shownRows(view)
		eq(#rows, 2)
		contains(rows[1].title:GetText(), "Frostpeak")
		contains(rows[1].title:GetText(), "2026-01-01")
		eq(rows[1].mob:GetText(), "Pup")
		eq(rows[1].duration:GetText(), "1:42")
		eq(rows[2].mob:GetText(), "Gorrak")
		eq(rows[1].badge:GetState(), "warning")
		matches(view.usage:GetText(), "^2 recordings · about %d+ KB of 2 MB$")
		eq(view.usageMarker.label:GetText(), L().CAT_ESTIMATED)
		contains(tooltip(view.usageHit), L().REPORTS_USAGE_NOTE)
		falsy(view.empty:IsShown())
		falsy(view.report:IsShown(), "no report until one is clicked")
		eq(#Mock.errors, 0)
	end)

	it("marks an interrupted, a truncated and a continuing recording, with at least for the length", function()
		add{ id = "old", state = "interrupted", ended = "reload", dur = 400 }
		add{ id = "cut", trunc = 300 }
		add{ id = "next", after = "old" }
		local rows = shownRows(openTab())
		eq(pillTexts(rows[1]), L().REPORTS_BADGE_CONTINUES)
		eq(pillTexts(rows[2]), L().REPORTS_BADGE_LIMIT)
		eq(pillTexts(rows[3]), L().REPORTS_BADGE_INTERRUPTED)
		eq(rows[3].duration:GetText(), "at least 0:40")
	end)

	it("gives every value of a row with its category and reason in the tooltip", function()
		add{}
		local tip = tooltip(shownRows(openTab())[1])
		contains(tip, "Duration: 0:40 (" .. L().CAT_DETECTED .. ")")
		contains(tip, "Main enemy: Gorrak (" .. L().CAT_DETECTED .. ")")
		contains(tip, "Your worst state: " .. L().STATE_WARNING .. " (" .. L().CAT_CALCULATED .. ")")
	end)

	it("says Unknown, with the reason, when no state of the player was recorded", function()
		add{ events = { { 0, "C", 0, 0, 0, "1" }, { 400, "c" } }, rows = { { 10, 1, 2, 1000, "3" } } }
		local row = shownRows(openTab())[1]
		eq(row.badge:GetState(), "unknown")
		contains(tooltip(row), L().REPORTS_NO_WORST)
	end)

	it("follows the store while it is open", function()
		add{}
		local view = openTab()
		eq(#shownRows(view), 1)
		add{}
		eq(#shownRows(view), 2)
		St().DeleteAll()
		eq(#shownRows(view), 0)
		truthy(view.empty:IsShown())
	end)
end)

describe("the report", function()
	it("opens under the list with every metric, its category marker and its tooltip", function()
		local s = add{ zone = "Gloomhold" }
		local view = openTab()
		shownRows(view)[1]:Click()
		eq(view.selected, s.id)
		notNil(view.data)
		truthy(view.report:IsShown())
		contains(view.head.title:GetText(), "Gorrak")
		contains(view.head.meta:GetText(), "Gloomhold")
		falsy(view.head.message:IsShown())
		local fight = metrics(view.fight)
		for _, key in ipairs(Mock.ns.Report.SESSION_ROWS) do
			local row = fight[key]
			notNil(row, key)
			truthy(row.marker.label:GetText() ~= "", key .. " has a marker")
			contains(tooltip(row), L().REPORTS_TIP_CATEGORY:format(row.marker.label:GetText()))
		end
		eq(fight.duration.marker.label:GetText(), L().CAT_DETECTED)
		eq(fight.quality.marker.label:GetText(), L().CAT_CALCULATED)
		local me = view.units[1]
		eq(me.name:GetText(), L().UNIT_YOU)
		local mine = metrics(me)
		for _, key in ipairs(Mock.ns.Report.UNIT_CELLS) do notNil(mine[key], key) end
		eq(mine.warningTime.value:GetText(), "20.0 s")
		contains(tooltip(mine.warningTime), "Warning from 80 %, Danger from 95 %")
		eq(view.units[2].name:GetText(), "Bram")
		eq(#Mock.errors, 0)
	end)

	it("says why a value is not there, with an unknown marker", function()
		add{ events = { { 0, "C", 0, 0, 0, "1" }, { 0, "M", 0, 0, 0, "n", "S" }, { 400, "c" } },
			rows = { { 10, 1, 1, nil, "S" } } }
		Mock.Reload()
		local s = sessions()[1]
		s.q.v = { 0, 0 }
		s.q.x = { 80, 80 }
		local view = openTab()
		view:Select(s.id)
		local fight = metrics(view.fight)
		eq(fight.tanks.marker.label:GetText(), L().CAT_UNKNOWN)
		eq(fight.tanks.value:GetText(), L().REPORT_NA_TANKS)
		contains(tooltip(fight.tanks), L().REPORT_WHY_SECRET)
		local me = view.units[1]
		truthy(me.note:IsShown())
		contains(me.note:GetText(), L().REPORT_NA)
	end)

	it("shows Building report while the slices run, in combat too", function()
		local rows = {}
		for i = 1, 40 do rows[i] = { i * 10, 1, 1, 500, "0" } end
		local s = add{ rows = rows }
		Mock.ns.Report.SLICE = 5
		local view = openTab()
		AzerothThreatwarden.inCombat = true
		view:Select(s.id)
		truthy(view.head.message:IsShown())
		eq(view.head.message:GetText(), "Building report…")
		isNil(view.data)
		Mock.Advance(5)
		notNil(view.data)
		falsy(view.head.message:IsShown())
		eq(#Mock.errors, 0)
	end)

	it("lets a later selection win over a build still running", function()
		local rows = {}
		for i = 1, 40 do rows[i] = { i * 10, 1, 1, 500, "0" } end
		local slow = add{ rows = rows }
		local quick = add{ mob = "Pup", rows = { { 10, 1, 1, 500, "0" } } }
		Mock.ns.Report.SLICE = 30
		local view = openTab()
		view:Select(slow.id)
		view:Select(quick.id)
		Mock.Advance(5)
		eq(view.data.id, quick.id)
	end)

	it("shows that a recording is damaged", function()
		local s = add{}
		s.mobs = { { name = "x" } }
		s.cols.m = string.rep("z", #s.cols.m)
		local view = openTab()
		view:Select(s.id)
		eq(view.head.message:GetText(), L().REPORT_DAMAGED)
		truthy(view.report:IsShown())
	end)

	it("does not build the recording still open", function()
		local pull = Fight.new{ player = { class = "MAGE" }, mobs = { { key = "boss", tokens = { "target" } } },
			party = { { key = "tank", role = "TANK" } } }
		pull:at(0):start():threat("boss", "tank", 1000):threat("boss", "player", 10)
		pull:to(2)
		eq(#sessions(), 1)
		local view = openTab()
		local row = shownRows(view)[1]
		contains(pillTexts(row), L().REPORTS_BADGE_RECORDING)
		eq(row.duration:GetText(), L().REPORTS_RECORDING_NOW)
		row:Click()
		eq(view.head.message:GetText(), L().REPORTS_RECORDING)
		falsy(view.head.delete:IsEnabled())
		pull:at(6):stop()
		pull:finish()
		Mock.Advance(7)
		notNil(view.data, "built once it ended")
	end)

	it("closes with Close report and opens from REPORT_REQUESTED", function()
		local s = add{}
		local view = openTab()
		bus().Emit("REPORT_REQUESTED", s.id)
		eq(view.selected, s.id)
		view.head.close:Click()
		isNil(view.selected)
		falsy(view.report:IsShown())
		bus().Emit("REPORT_REQUESTED", "not-there")
		isNil(view.selected)
		eq(#Mock.errors, 0)
	end)
end)

describe("deleting", function()
	it("needs a second click, deletes only that one, and it stays deleted after a /reload", function()
		local first = add{}
		local second = add{}
		local view = openTab()
		view:Select(first.id)
		view.head.delete:Click()
		eq(view.head.delete:GetLabel(), L().REPORTS_DELETE_CONFIRM)
		eq(#sessions(), 2)
		view.head.delete:Click()
		eq(#sessions(), 1)
		eq(sessions()[1].id, second.id)
		isNil(view.selected)
		eq(#shownRows(view), 1)
		Mock.Reload()
		eq(#sessions(), 1)
		eq(sessions()[1].id, second.id)
	end)

	it("forgets the first click after 8 s, on another selection and when the tab is hidden", function()
		local a, b = add{}, add{}
		local view = openTab()
		view:Select(a.id)
		view.head.delete:Click()
		Mock.Advance(9)
		eq(view.head.delete:GetLabel(), L().REPORTS_DELETE)
		view.head.delete:Click()
		view:Select(b.id)
		eq(view.head.delete:GetLabel(), L().REPORTS_DELETE)
		view.head.delete:Click()
		W():SelectTab("monitor")
		W():SelectTab("reports")
		eq(view.head.delete:GetLabel(), L().REPORTS_DELETE)
		eq(#sessions(), 2)
	end)
end)

describe("an empty list", function()
	local function reason(setup)
		if setup then setup() end
		local view = openTab()
		truthy(view.empty:IsShown())
		eq(view.empty:GetText(), "No recordings yet")
		falsy(view.list:IsShown())
		return view.emptyReason:GetText()
	end
	local function set(path, value) truthy(Config():Set("account.settings.recording." .. path, value)) end

	it("says recording only in a group or an instance (the default)", function()
		eq(reason(), "Recording only in a group or an instance.")
	end)
	it("says recording only in an instance", function()
		eq(reason(function() set("when", "instance") end), "Recording only in an instance.")
	end)
	it("says recording is off", function()
		eq(reason(function() set("enabled", false) end), "Recording is off.")
	end)
	it("says that the next recorded fight appears here when nothing stops it", function()
		eq(reason(function() set("when", "always") end), L().REPORTS_EMPTY_NEXT)
	end)
	it("follows the setting while open", function()
		local view = openTab()
		set("enabled", false)
		eq(view.emptyReason:GetText(), "Recording is off.")
	end)
	it("says recording is off with the recording switch off", function()
		T.boot(function(M) M.features = { monitor = true, recording = false, reports = true } end)
		eq(reason(), "Recording is off.")
	end)
end)

describe("read-only data", function()
	it("shows the recordings, says they are read-only and changes nothing", function()
		add{}
		local saved = sessions()[1]
		T.boot(function(M)
			M.features = ALL()
			M.saved = { AzerothThreatwardenDB = { schema = 99, sessions = { saved } } }
		end)
		local view = openTab()
		eq(#shownRows(view), 1)
		truthy(view.notice:IsShown())
		contains(view.notice:GetText(), L().REPORTS_READ_ONLY_NEWER)
		view:Select(saved.id)
		notNil(view.data)
		falsy(view.head.delete:IsEnabled())
		view.head.delete:Click()
		view.head.delete:Click()
		eq(#sessions(), 1)
	end)

	it("says why an empty list stays empty", function()
		T.boot(function(M)
			M.features = ALL()
			M.saved = { AzerothThreatwardenDB = { schema = 99, sessions = {} } }
		end)
		local view = openTab()
		eq(view.emptyReason:GetText(), L().REPORTS_EMPTY_READ_ONLY)
	end)
end)

describe("the layouts", function()
	it("fit the smallest and the default window, with the list above the report", function()
		for i = 1, 8 do add{} end
		local view = openTab()
		view:Select(sessions()[1].id)
		for _, size in ipairs({ { 440, 300 }, { 520, 400 } }) do
			view:Layout(size[1], size[2])
			truthy(view.list:GetHeight() <= 3 * (R().ROW_HEIGHT + R().ROW_GAP), "three rows over the report")
			truthy(view.report:GetHeight() >= 40)
		end
		view:Select(nil)
		truthy(view.list:GetHeight() > 3 * (R().ROW_HEIGHT + R().ROW_GAP))
	end)
end)

describe("in Italian", function()
	before_boot(function(M) M.features = ALL() M.player.locale = "itIT" end)
	it("writes the tab, the report and the date in Italian", function()
		add{}
		local view = openTab()
		contains(shownRows(view)[1].title:GetText(), "01/01/2026")
		view:Select(sessions()[1].id)
		eq(view.head.delete:GetLabel(), "Elimina registrazione")
		eq(metrics(view.fight).duration.marker.label:GetText(), "rilevato")
		eq(#Mock.errors, 0)
	end)
end)

describe("with the `reports` switch off", function()
	before_boot(function(M) M.features = { monitor = true, recording = true, reports = false } end)
	it("has no tab, no view and no listener", function()
		W():Open()
		falsy(W():SelectTab("reports"))
		isNil(W():Frame().pages.reports.view)
		isNil(R().view)
	end)
end)

describe("the Timeline card (SPEC-05 §4.8, M5.3)", function()
	before_boot(function(M)
		local on = ALL()
		on.timeline = true
		M.features = on
	end)

	local function replayAsked()
		local asked = {}
		bus().On("REPLAY_REQUESTED", function(id, t) asked[#asked + 1] = { id, t } end)
		return asked
	end

	local function click(chart, t)
		Mock.cursor.x = Mock.ns.Timeline.X(t, chart.a, chart.b, chart.plot.width)
		Mock.RunScript(chart.hit, "OnEnter")
		Mock.RunScript(chart.hit, "OnMouseDown", "LeftButton")
		Mock.RunScript(chart.hit, "OnMouseUp", "LeftButton")
		Mock.RunScript(chart.hit, "OnLeave")
	end

	it("follows the head card with the whole fight, the holder lane and the events, without a legend", function()
		local s = add{}
		local view = openTab()
		isNil(view.timeline, "no card before a recording is opened")
		view:Select(s.id)
		local card = view.timeline
		truthy(card:IsShown())
		eq(view.report.cards[1], view.head)
		eq(view.report.cards[2], card)
		eq(view.report.cards[3], view.fight)
		falsy(card.message:IsShown())
		truthy(card.chart:IsShown())
		eq(card.chart.model.id, s.id)
		deepEq({ card.chart:View() }, { 0, 400 })
		eq(card.chart:GetHeight(), Mock.ns.Timeline.CARD_HEIGHT)
		local kinds = {}
		for i = 1, card.chart.textures.used do kinds[card.chart.textures.list[i].kind] = true end
		truthy(kinds.holder and kinds.marker and kinds.grid)
		falsy(kinds["legend-mark"] or kinds.lane)
		falsy(card.chart.hit:IsMouseWheelEnabled(), "the wheel scrolls the report")
		truthy(card:GetHeight() > Mock.ns.Timeline.CARD_HEIGHT)
		eq(#Mock.errors, 0)
	end)

	it("is built after the report, in slices, and says so meanwhile", function()
		local rows = {}
		for i = 1, 40 do rows[i] = { i * 10, 1, 1, 500, "0" } end
		local s = add{ rows = rows }
		Mock.ns.Timeline.SLICE = 10
		local view = openTab()
		view:Select(s.id)
		notNil(view.data, "the report first")
		isNil(view.model)
		eq(view.timeline.message:GetText(), L().TIMELINE_BUILDING)
		falsy(view.timeline.chart:IsShown())
		Mock.Advance(5)
		eq(view.model.id, s.id)
		truthy(view.timeline.chart:IsShown())
		falsy(view.timeline.message:IsShown())
	end)

	it("lets a later selection win, and closes with the report", function()
		local rows = {}
		for i = 1, 40 do rows[i] = { i * 10, 1, 1, 500, "0" } end
		local slow = add{ rows = rows }
		local quick = add{ mob = "Pup", rows = { { 10, 1, 1, 500, "0" } } }
		Mock.ns.Timeline.SLICE = 10
		local view = openTab()
		view:Select(slow.id)
		view:Select(quick.id)
		Mock.Advance(5)
		eq(view.model.id, quick.id)
		eq(view.timeline.chart.model.id, quick.id)
		view:Select(nil)
		falsy(view.report:IsShown())
		view:Select(slow.id)
		Mock.Advance(5)
		eq(view.timeline.chart.model.id, slow.id)
		eq(#Mock.errors, 0)
	end)

	it("says when the timeline cannot be built", function()
		local s = add{}
		Mock.ns.Timeline.Compute = function() error("boom") end
		local view = openTab()
		view:Select(s.id)
		eq(view.timeline.message:GetText(), L().TIMELINE_FAILED)
		falsy(view.timeline.chart:IsShown())
		notNil(view.data, "the report stays")
	end)

	it("is not shown for a damaged or an open recording", function()
		local s = add{}
		s.mobs = { { name = "x" } }
		s.cols.m = string.rep("z", #s.cols.m)
		local view = openTab()
		view:Select(s.id)
		falsy(view.timeline and view.timeline:IsShown())
		eq(#view.report.cards, 1)
	end)

	it("asks for nothing on a click while the replay is off", function()
		local s = add{}
		local view = openTab()
		view:Select(s.id)
		local asked = replayAsked()
		click(view.timeline.chart, 200)
		eq(#asked, 0)
		falsy(view.timeline.hint:IsShown())
	end)

	it("asks for the replay at that time on a click, with the `replay` switch", function()
		T.boot(function(M)
			local on = ALL()
			on.timeline, on.replay = true, true
			M.features = on
		end)
		local s = add{}
		local view = openTab()
		view:Select(s.id)
		local asked = replayAsked()
		eq(view.timeline.hint:GetText(), L().TIMELINE_CARD_HINT)
		truthy(view.timeline.hint:IsShown())
		click(view.timeline.chart, 200)
		deepEq(asked, { { s.id, 200 } })
	end)

	it("has no card with the switch off", function()
		T.boot(function(M) M.features = ALL() end)
		local s = add{}
		local view = openTab()
		view:Select(s.id)
		isNil(view.timeline)
		eq(view.report.cards[2], view.fight)
		eq(Mock.ns.Timeline.regions.textures, 0)
		isNil(Mock.ns.Timeline.Cached())
	end)
end)
