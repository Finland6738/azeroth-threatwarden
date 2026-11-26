-- UI/ReplayWindow.lua (SPEC-05 §5.5, §10 M5.5; SPEC-02 §3.9; ui-style 3.5; ADR 0003; SPEC-09 Q18, Q19): the window
-- opened from the report's button, from its timeline card, from /atw replay and from REPLAY_REQUESTED; the wide and the
-- single-panel layout; every state of the table of §5.5; the keys only out of combat and over the window, every other
-- key left to the game; Esc; position, size and speed per character across a /reload; read-only data; the theme; the
-- event list and the detail; nothing with a switch off.

local function ALL()
	return { monitor = true, alerts = true, coach = true, recording = true, reports = true, timeline = true,
		replay = true }
end

before_boot(function(M) M.features = ALL() end)

local function RW() return Mock.ns.ReplayWindow end
local function Rp() return Mock.ns.Replay end
local function L() return Mock.ns.L end
local function S() return Mock.ns.Session end
local function St() return Mock.ns.Storage end
local function Config() return Mock.ns.Config end
local function W() return AzerothThreatwarden.Window end
local function bus() return Mock.ns.Bus end
local function frame() return RW().frame end

local counter = 0

local ME = { name = "Testchar", role = "DAMAGER", token = "player", me = true }
local TANK = { name = "Bram", class = "WARRIOR", role = "TANK", token = "party1" }
local KOR = { name = "Kor", class = "ROGUE", role = "DAMAGER", token = "party2" }
local BOSS = { name = "Gorrak", class = "elite", npc = 448 }

local function sorted(rows)
	table.sort(rows, function(a, b) if a[1] ~= b[1] then return a[1] < b[1] end return a[3] < b[3] end)
	return rows
end

-- A session built with the Session API and stored (spec.open: left open, as while it records).
local function build(spec)
	counter = counter + 1
	local s = S().New{ id = spec.id or ("rw-" .. counter), started = spec.started or (1767225600 + counter * 100),
		group = "party", zone = spec.zone or "Gloomhold", rec = { hz = 2, warning = 80, danger = 95, mode = "values" },
		after = spec.after }
	for _, u in ipairs(spec.units or { ME, TANK, KOR }) do S().AddUnit(s, u, 0) end
	for _, m in ipairs(spec.mobs or { BOSS }) do S().AddMob(s, m, 0) end
	for _, e in ipairs(spec.events or {}) do S().AddEvent(s, e[1], e[2], e[3], e[4], e[5], e[6], e[7], e[8], e[9]) end
	for _, r in ipairs(spec.rows or {}) do S().AddRow(s, r[1], r[2], r[3], r[4], r[5]) end
	S().Join(s)
	if spec.open then
		truthy(St().Add(s))
		Mock.ns.Recorder.current = s       -- the recorder's open session
		return s
	end
	s.state, s.ended = spec.state or "complete", spec.ended or "combat"
	s.dur, s.fight, s.trunc = spec.dur or 0, spec.dur or 0, spec.trunc
	truthy(St().Add(s))
	truthy(St().Closed(s, true))
	return s
end

-- 60 s in values: me read every 0.5 s with a secret row at 21.0, the tank holds the enemy, two deaths of the Coach and
-- of the alerts for the list.
local function fight(over)
	local rows = {}
	for t = 10, 200, 5 do rows[#rows + 1] = { t, 1, 1, 400 + t, "0" } end
	rows[#rows + 1] = { 210, 1, 1, -1, "S" }
	for t = 240, 595, 5 do rows[#rows + 1] = { t, 1, 1, 500, "0" } end
	for t = 10, 595, 5 do rows[#rows + 1] = { t, 1, 2, 1000, "3" } end
	local spec = { dur = 600, rows = sorted(rows), events = {
		{ 0, "C", 0, 0, 0, "1" }, { 0, "M", 0, 0, 0, "v" }, { 0, "T", 1 }, { 0, "A", 1, 2, 0, "1" },
		{ 0, "S", 1, 2, 0, "S", "-" }, { 0, "S", 1, 1, 0, "S", "-" }, { 100, "S", 1, 1, 0, "W", "S" },
		{ 150, "S", 1, 1, 0, "S", "W" }, { 200, "L", 1, 1, 0, "w", "1", "0", "ch" }, { 205, "H", 0, 1, 0, "1", "d", "h" },
		{ 300, "S", 1, 1, 0, "D", "S" }, { 600, "c" },
	} }
	for k, v in pairs(over or {}) do spec[k] = v end
	return build(spec)
end

-- Opens the window on `s` and lets the model be built.
local function open(s, t)
	truthy(RW().Open(s.id, t))
	Mock.Advance(0.5, 0.05)
	return frame()
end

local function ready(s, t)
	local f = open(s, t)
	eq(RW().mode, "ready", "mode")
	eq(#Mock.errors, 0)
	return f
end

local function shownRows(f)
	local out = {}
	for _, row in ipairs(f.rows) do if row:IsShown() then out[#out + 1] = row end end
	return out
end

local function detailText(f)
	local out = {}
	for i = 1, f.detail.lines.used do out[#out + 1] = f.detail.lines.list[i].text:GetText() end
	for i = 1, f.detail.units.used do
		local w = f.detail.units.list[i]
		out[#out + 1] = w.name:GetText() .. " " .. w.badge.label:GetText() .. " " .. w.reading:GetText()
	end
	return table.concat(out, "\n")
end

local function unitWidget(f, u)
	for i = 1, f.detail.units.used do
		local w = f.detail.units.list[i]
		if w.unit == u then return w end
	end
	return nil
end

local function tooltip(widget)
	Mock.RunScript(widget, "OnEnter")
	local lines = table.concat(Mock.ns.Widgets.Tooltip.Lines(), "\n")
	Mock.RunScript(widget, "OnLeave")
	return lines
end

local function resize(f, w, h)
	f:SetSize(w, h)
	Mock.RunScript(f, "OnSizeChanged", w, h)
end

local function openReport(s)
	W():Open()
	truthy(W():SelectTab("reports"))
	local view = W():Frame().pages.reports.view
	view:Select(s.id)
	Mock.Advance(0.5, 0.05)
	return view
end

local function run(line)
	Mock.ClearOutput()
	truthy(Mock.Slash(line))
	Mock.Advance(0.5, 0.05)
	eq(#Mock.errors, 0, line)
	return Mock.PlainOutput()
end

describe("opening the replay (SPEC-05 §5.5)", function()
	it("makes no frame until it is asked for, and listens from the login", function()
		isNil(frame())
		isNil(rawget(_G, "AzerothThreatwardenReplay"))
		truthy(RW().Listening())
	end)

	it("opens its own named frame on REPLAY_REQUESTED, at the time asked, apart from the main window", function()
		local s = fight()
		bus().Emit("REPLAY_REQUESTED", s.id, 150)
		Mock.Advance(0.5, 0.05)
		local f = frame()
		truthy(f:IsShown())
		eq(f:GetName(), "AzerothThreatwardenReplay")
		eq(AzerothThreatwardenReplay, f)
		eq(f:GetFrameStrata(), "MEDIUM")
		eq(f:GetWidth(), 820)
		eq(f:GetHeight(), 520)
		eq(RW().mode, "ready")
		eq(Rp().state.id, s.id)
		eq(Rp().state.cursor, 150)
		eq(f.chart.model, Rp().state.model)
		eq(f.chart.cursorAt, 150)
		eq(#Mock.errors, 0)
	end)

	it("titles it with the date, the zone, the enemy and the length", function()
		local f = ready(fight{ zone = "Frostpeak" })
		eq(f.bar.title:GetText(), L().REPLAY_TITLE)
		local sub = f.bar.subtitle:GetText()
		contains(sub, "2026-01-01")
		contains(sub, "Frostpeak")
		contains(sub, "Gorrak")
		contains(sub, "1:00")
		falsy(f.badge:IsShown())
	end)

	it("opens from the report's Replay button, off with its reason for an open or damaged recording", function()
		local s = fight()
		local view = openReport(s)
		local button = view.head.replay
		truthy(button:IsShown())
		eq(button:GetLabel(), L().REPORTS_REPLAY)
		truthy(button:IsEnabled())
		contains(tooltip(button), L().REPORTS_REPLAY_TIP)
		button:Click()
		Mock.Advance(0.5, 0.05)
		eq(RW().mode, "ready")
		eq(Rp().state.id, s.id)

		local live = build{ open = true, id = "live" }
		view = openReport(live)
		falsy(view.head.replay:IsEnabled())
		contains(tooltip(view.head.replay), L().REPORTS_REPLAY_RECORDING)
		Mock.ns.Recorder.current = nil

		local bad = fight()
		bad.cols.s = string.rep("?", bad.n)
		view = openReport(bad)
		falsy(view.head.replay:IsEnabled())
		contains(tooltip(view.head.replay), L().REPORTS_REPLAY_DAMAGED)
		eq(#Mock.errors, 0)
	end)

	it("opens from the report's timeline card at that time", function()
		local s = fight()
		local view = openReport(s)
		view.timeline.chart.opts.onSeek(200)
		Mock.Advance(0.5, 0.05)
		eq(RW().mode, "ready")
		eq(Rp().state.cursor, 200)
		-- the same recording again only moves the cursor
		local token = RW().token
		view.timeline.chart.opts.onSeek(300)
		eq(RW().token, token)
		eq(Rp().state.cursor, 300)
		eq(#Mock.errors, 0)
	end)

	it("opens with /atw replay on the newest closed recording, and /atw replay n on the n-th", function()
		local old = fight()
		local newest = fight()
		eq(run("/atw replay"), "")
		eq(Rp().state.id, newest.id)
		run("/atw replay 2")
		eq(Rp().state.id, old.id)
		run("/atw replay 1")
		eq(Rp().state.id, newest.id)
		contains(run("/atw help"), "/atw replay - " .. L().HELP_REPLAY)
	end)

	it("skips the recording in progress without a number, and says when there is nothing to open", function()
		contains(run("/atw replay"), L().CMD_REPLAY_NONE)
		contains(run("/atw replay 1"), L().CMD_REPLAY_NONE)
		build{ open = true, id = "live", started = 1767999999 }
		contains(run("/atw replay"), L().CMD_REPLAY_RECORDING)
		isNil(frame())
		local s = fight()
		run("/atw replay")
		eq(Rp().state.id, s.id)
		run("/atw replay 1")
		eq(RW().mode, "recording")
		for _, bad in ipairs({ "0", "3", "x", "1.5" }) do
			contains(run("/atw replay " .. bad), L().CMD_REPLAY_UNKNOWN:format(bad, 2))
		end
	end)
end)

describe("the layout (SPEC-05 §5.5)", function()
	it("shows the chart with its lanes, the controls, the event list and the detail", function()
		local f = ready(fight())
		truthy(f.chart:IsShown())
		truthy(f.chart.opts.lanes)
		truthy(f.chart.opts.legend)
		truthy(f.controls:IsShown())
		truthy(f.events:IsShown())
		truthy(f.detail:IsShown())
		falsy(f.switch:IsShown(), "two panels side by side at 820")
		falsy(f.message:IsShown())
		truthy(f.events.title:IsShown())
		truthy(#shownRows(f) >= 3)
		eq(f.speed:Active(), 1)
		contains(f.time:GetText(), "1:00")
		truthy(f.chartHeight + f.controlsHeight + f.panelHeight <= 520 - 52 - 8 - 12 - 16 + 1)
	end)

	it("becomes one panel with the selector under 760 points", function()
		local f = ready(fight())
		resize(f, 759, 520)
		truthy(f.switch:IsShown())
		truthy(f.events:IsShown())
		falsy(f.detail:IsShown())
		f.switch.buttons.details:Click()
		falsy(f.events:IsShown())
		truthy(f.detail:IsShown())
		falsy(f.filter:IsShown(), "the filter goes with the list")
		truthy(f.detail.lines.used > 0)
		f.switch.buttons.events:Click()
		truthy(f.events:IsShown())
		resize(f, 760, 520)
		falsy(f.switch:IsShown())
		truthy(f.events:IsShown())
		truthy(f.detail:IsShown())
		eq(#Mock.errors, 0)
	end)

	it("fits the smallest window with at least two event rows", function()
		local f = ready(fight())
		resize(f, 640, 420)
		truthy(f.panelHeight >= RW().HEADER + 2 * RW().ROW, "panel " .. f.panelHeight)
		truthy(#shownRows(f) >= 2)
		truthy(f.chartHeight + f.controlsHeight + f.panelHeight <= 420 - 52 - 8 - 12 - 16 + 1)
		eq(f.zoomMode, "icons")
		truthy(f.zoomIcon:IsShown())
		falsy(f.zoom:IsShown())
		resize(f, 1400, 1000)
		eq(f.zoomMode, "text")
		truthy(f.zoom:IsShown())
		falsy(f.wholeIcon:IsShown())
		eq(#Mock.errors, 0)
	end)

	it("is redrawn in every theme", function()
		local f = ready(fight())
		for _, theme in ipairs({ "aurora", "warden", "nebula" }) do
			truthy(Config():Set("account.settings.theme", theme))
			Mock.ns.Theme.Apply(theme)
			eq(#Mock.errors, 0, theme)
			truthy(f:IsShown())
		end
	end)
end)

describe("the states of the window (SPEC-05 §5.5)", function()
	it("building: says so, with the controls off, then opens", function()
		local s = fight()
		Mock.ns.Timeline.SLICE = 5
		RW().Open(s.id)
		local f = frame()
		eq(RW().mode, "building")
		eq(f.message:GetText(), L().TIMELINE_BUILDING)
		truthy(f.message:IsShown())
		falsy(f.chart:IsShown())
		falsy(f.events:IsShown())
		falsy(f.detail:IsShown())
		for _, b in pairs(f.buttons) do falsy(b:IsEnabled()) end
		falsy(f.whole:IsEnabled())
		for _ = 1, 200 do Mock.Advance(0.05) end
		eq(RW().mode, "ready")
		falsy(f.message:IsShown())
		for _, b in pairs(f.buttons) do truthy(b:IsEnabled()) end
		eq(#Mock.errors, 0)
	end)

	it("damaged: the recording was set aside", function()
		local s = fight()
		s.cols.s = string.rep("?", s.n)
		local f = open(s)
		eq(RW().mode, "damaged")
		eq(f.message:GetText(), L().REPLAY_MSG_DAMAGED)
		falsy(f.chart:IsShown())
		eq(#Mock.errors, 0)
	end)

	it("recording: says so and opens when the fight ends", function()
		local s = build{ open = true, id = "live", events = { { 0, "C", 0, 0, 0, "1" } } }
		local f = open(s)
		eq(RW().mode, "recording")
		eq(f.message:GetText(), L().REPLAY_MSG_RECORDING)
		contains(f.bar.subtitle:GetText(), L().REPORTS_RECORDING_NOW)
		s.state, s.ended, s.dur, s.fight = "complete", "combat", 100, 100
		Mock.ns.Recorder.current = nil
		St().Closed(s, true)
		bus().Emit("SESSION_ENDED", s.id, "complete")
		Mock.Advance(1, 0.05)
		eq(RW().mode, "ready")
		eq(Rp().state.id, "live")
		eq(#Mock.errors, 0)
	end)

	it("deleted: before and while it is open", function()
		local f
		truthy(RW().Open("nothing"))
		Mock.Advance(0.5, 0.05)
		f = frame()
		eq(RW().mode, "unknown")
		eq(f.message:GetText(), L().REPLAY_MSG_DELETED)
		local s = fight()
		ready(s)
		Rp().Do("toggle")
		truthy(St().Delete(s.id))
		eq(RW().mode, "unknown")
		eq(f.message:GetText(), L().REPLAY_MSG_DELETED)
		falsy(f.chart:IsShown())
		isNil(f.chart.model)
		isNil(Rp().state)
		eq(Mock.ns.Scheduler.IsRunning("replay"), false)
		eq(#Mock.errors, 0)
	end)

	it("state only: the note of the chart, the lanes and the states in the detail", function()
		local rows = {}
		for t = 10, 100, 5 do rows[#rows + 1] = { t, 1, 1, -1, "b" } end
		local s = build{ dur = 100, rows = rows, units = { ME }, events = { { 0, "C", 0, 0, 0, "1" },
			{ 0, "M", 0, 0, 0, "s", "s" }, { 0, "T", 1 }, { 0, "S", 1, 1, 0, "W", "-" }, { 100, "c" } } }
		local f = ready(s, 50)
		eq(f.chart.model.outcome, "state")
		contains(f.chart.note:GetText(), L().TIMELINE_OUTCOME_STATE)
		falsy(f.chart.plan.chart)
		truthy(#f.chart.plan.lanes > 0)
		local text = detailText(f)
		contains(text, L().REPLAY_MODE_STATE)
		contains(text, L().STATE_WARNING)
		contains(text, L().REPLAY_SITUATION_1)
	end)

	it("nothing readable: the note, the events and the detail with the mode and its reason", function()
		local s = build{ dur = 100, units = { ME }, events = { { 0, "C", 0, 0, 0, "1" },
			{ 0, "M", 0, 0, 0, "n", "S" }, { 0, "T", 1 }, { 40, "D", 0, 1 }, { 100, "c" } } }
		local f = ready(s, 50)
		eq(f.chart.model.outcome, "none")
		contains(f.chart.note:GetText(), "Nothing was readable")
		truthy(#shownRows(f) >= 1)
		contains(detailText(f), L().REPLAY_MODE_NONE:format(L().TIMELINE_WHY_SECRET))
	end)

	it("interrupted: the badge, the interruption and the links between the two sessions", function()
		local first = fight{ id = "first", state = "interrupted", ended = "reload" }
		local second = fight{ id = "second", after = "first" }
		local f = ready(first)
		truthy(f.badge:IsShown())
		eq(f.badge.label:GetText(), L().REPORT_INTERRUPTED:format(L().REPORT_ENDED_RELOAD))
		contains(f.bar.subtitle:GetText(), L().REPORT_AT_LEAST:format("1:00"))
		falsy(f.before:IsShown())
		truthy(f.later:IsShown())
		contains(f.later:GetLabel(), "Continues in")
		f.later:Click()
		Mock.Advance(0.5, 0.05)
		eq(Rp().state.id, second.id)
		falsy(f.badge:IsShown())
		truthy(f.before:IsShown())
		falsy(f.later:IsShown())
		contains(f.before:GetLabel(), "Continued from")
		f.before:Click()
		Mock.Advance(0.5, 0.05)
		eq(Rp().state.id, first.id)
		eq(#Mock.errors, 0)
	end)

	it("truncated: the detail says where the samples stopped", function()
		local s = build{ dur = 600, trunc = 300, units = { ME }, rows = { { 10, 1, 1, 500, "0" } },
			events = { { 0, "C", 0, 0, 0, "1" }, { 0, "M", 0, 0, 0, "v" }, { 0, "T", 1 }, { 300, "Z", 0, 0, 0, "r" },
				{ 600, "c" } } }
		local f = ready(s, 500)
		contains(detailText(f), L().REPLAY_MISSING_LIMIT:format("0:30.0"))
	end)

	it("read-only data: the same replay, nothing written", function()
		local s = fight()
		local saved = { AzerothThreatwardenDB = AzerothThreatwardenDB, AzerothThreatwardenCharDB =
			{ schema = 99, ui = { replay = { speed = 4 } } } }
		boot(function(M) M.features = ALL(); M.saved = saved end)
		truthy(Config():IsReadOnly("char"))
		local list = St().List()
		eq(#list, 1)
		local f = ready(St().Get(list[1].id))
		eq(f.speed:Active(), 4)
		f.speed.buttons[8]:Click()
		eq(Rp().state.speed, 8)
		eq(AzerothThreatwardenCharDB.ui.replay.speed, 4)
		f.bar.GetScript(f.bar, "OnDragStart")(f.bar)
		f.bar.GetScript(f.bar, "OnDragStop")(f.bar)
		isNil(AzerothThreatwardenCharDB.ui.replay.pos)
		eq(#Mock.errors, 0)
		truthy(s)
	end)

	it("in combat: playback paused, Play off with its tooltip, seeking and reading go on", function()
		local f = ready(fight())
		f.buttons.toggle:Click()
		truthy(Rp().state.playing)
		eq(f.buttons.toggle.icon, "pause")
		Mock.combat.Enter()
		eq(Rp().state.playing, false)
		eq(f.buttons.toggle.icon, "play")
		falsy(f.buttons.toggle:IsEnabled())
		contains(tooltip(f.buttons.toggle), L().REPLAY_PLAY_COMBAT)
		truthy(f.buttons.forward:IsEnabled())
		f.buttons.forward:Click()
		truthy(Rp().state.cursor > 0)
		f.buttons.nextEvent:Click()
		truthy(Rp().state.focus ~= nil)
		truthy(f:IsShown(), "never closed or opened by the combat")
		Mock.combat.Leave()
		truthy(f.buttons.toggle:IsEnabled())
		eq(#Mock.errors, 0)
	end)

	for _, off in ipairs({ "replay", "timeline" }) do
		it("with the " .. off .. " switch off nothing is built or listened to", function()
			boot(function(M) local x = ALL(); x[off] = false; M.features = x end)
			local s = fight()
			falsy(RW().Listening())
			bus().Emit("REPLAY_REQUESTED", s.id)
			falsy(RW().Open(s.id))
			Mock.Advance(0.5, 0.05)
			isNil(frame())
			isNil(rawget(_G, "AzerothThreatwardenReplay"))
			local view = openReport(s)
			isNil(view.head.replay)
			contains(run("/atw replay"), L().CMD_LATER:format("v0.5.0"))
			falsy(run("/atw help"):find("/atw replay", 1, true))
			eq(#Mock.errors, 0)
		end)
	end
end)

describe("the controls (SPEC-05 §5.5)", function()
	it("move the cursor, play and set the speed, each with its key in the tooltip", function()
		local f = ready(fight())
		f.buttons.finish:Click()
		eq(Rp().state.cursor, 600)
		f.buttons.start:Click()
		eq(Rp().state.cursor, 0)
		f.buttons.forward:Click()
		eq(Rp().state.cursor, 10)
		f.buttons.back:Click()
		eq(Rp().state.cursor, 0)
		f.buttons.nextEvent:Click()
		notNil(Rp().state.focus)
		f.buttons.prevEvent:Click()
		f.speed.buttons[4]:Click()
		eq(Rp().state.speed, 4)
		eq(AzerothThreatwardenCharDB.ui.replay.speed, 4)
		for _, pair in ipairs({ { "start", "REPLAY_CTL_START" }, { "prevEvent", "REPLAY_CTL_PREV_EVENT" },
			{ "back", "REPLAY_CTL_BACK" }, { "toggle", "REPLAY_CTL_PLAY" }, { "forward", "REPLAY_CTL_FORWARD" },
			{ "nextEvent", "REPLAY_CTL_NEXT_EVENT" }, { "finish", "REPLAY_CTL_END" } }) do
			local tip = tooltip(f.buttons[pair[1]])
			contains(tip, L()[pair[2]], pair[1])
			contains(tip, L().REPLAY_KEYS_HINT)
		end
		contains(tooltip(f.speed.buttons[8]), L().REPLAY_CTL_SPEED:format(8, 4))
		eq(#Mock.errors, 0)
	end)

	it("play moves the chart's cursor and the time, and updates the age of an estimate", function()
		local f = ready(fight())
		Rp().Seek(200)
		local cursor = f.chart.cursorAt
		f.buttons.toggle:Click()
		Mock.Advance(1.05, 0.05)
		truthy(f.chart.cursorAt > cursor)
		eq(f.chart.cursorAt, Rp().state.cursor)
		contains(f.time:GetText(), Mock.ns.Timeline.TimeText(Rp().state.cursor))
		eq(#Mock.errors, 0)
	end)

	it("zoom to a selection made on the chart, and back to the whole fight", function()
		local f = ready(fight())
		falsy(f.zoom:IsEnabled())
		falsy(f.whole:IsEnabled())
		f.chart.opts.onSelect(100, 300)
		deepEq(Rp().state.selection, { 100, 300 })
		truthy(f.zoom:IsEnabled())
		resize(f, 1400, 1000)
		f.zoom:Click()
		deepEq(Rp().state.view, { 100, 300 })
		deepEq({ f.chart:View() }, { 100, 300 })
		truthy(f.whole:IsEnabled())
		f.whole:Click()
		deepEq({ f.chart:View() }, { 0, 600 })
		f.chart.opts.onSelect(nil, nil)
		isNil(Rp().state.selection)
		falsy(f.zoom:IsEnabled())
		f.chart.opts.onSeek(250)
		eq(Rp().state.cursor, 250)
		f.chart.opts.onView(0, 200)
		deepEq(Rp().state.view, { 0, 200 })
		eq(#Mock.errors, 0)
	end)
end)

describe("the keys (Q19)", function()
	local function over(f) Mock.mouseOver = f end

	it("work out of combat with the pointer over the window, and every other key goes to the game", function()
		local f = ready(fight())
		truthy(f:IsKeyboardEnabled())
		over(f)
		falsy(Mock.PressKey(f, "END"))
		eq(Rp().state.cursor, 600)
		falsy(Mock.PressKey(f, "HOME"))
		eq(Rp().state.cursor, 0)
		falsy(Mock.PressKey(f, "RIGHT"))
		eq(Rp().state.cursor, 10)
		falsy(Mock.PressKey(f, "LEFT"))
		eq(Rp().state.cursor, 0)
		Mock.modifiers.shift = true
		falsy(Mock.PressKey(f, "RIGHT"))
		eq(Rp().state.cursor, 50)
		falsy(Mock.PressKey(f, "LEFT"))
		eq(Rp().state.cursor, 0)
		truthy(Mock.PressKey(f, "SPACE"), "Shift+Space is the game's")
		Mock.modifiers.shift = nil
		falsy(Mock.PressKey(f, "DOWN"))
		notNil(Rp().state.focus)
		falsy(Mock.PressKey(f, "UP"))
		falsy(Mock.PressKey(f, "SPACE"))
		truthy(Rp().state.playing)
		falsy(Mock.PressKey(f, "SPACE"))
		falsy(Rp().state.playing)
		for i, speed in ipairs({ 1, 2, 4, 8 }) do
			falsy(Mock.PressKey(f, tostring(i)))
			eq(Rp().state.speed, speed)
		end
		for _, key in ipairs({ "W", "5", "ENTER", "ESCAPE", "F1", "TAB" }) do truthy(Mock.PressKey(f, key), key) end
		for _, mod in ipairs({ "ctrl", "alt" }) do
			Mock.modifiers[mod] = true
			truthy(Mock.PressKey(f, "SPACE"), mod)
			truthy(Mock.PressKey(f, "1"), mod)
			Mock.modifiers[mod] = nil
		end
		eq(#Mock.errors, 0)
	end)

	it("leave every key to the game when the pointer is not over the window", function()
		local f = ready(fight())
		over(nil)
		for _, key in ipairs({ "SPACE", "LEFT", "END", "1" }) do truthy(Mock.PressKey(f, key), key) end
		eq(Rp().state.cursor, 0)
		falsy(Rp().state.playing)
		-- after a taken key the next one is not swallowed
		over(f)
		falsy(Mock.PressKey(f, "END"))
		over(nil)
		truthy(Mock.PressKey(f, "W"))
	end)

	it("leave every key to the game while there is nothing to replay", function()
		local s = fight()
		s.cols.s = string.rep("?", s.n)
		local f = open(s)
		over(f)
		for _, key in ipairs({ "SPACE", "LEFT", "END" }) do truthy(Mock.PressKey(f, key), key) end
		eq(#Mock.errors, 0)
	end)

	it("take nothing in combat, never call the keyboard functions in lockdown, and come back after it", function()
		local f = ready(fight())
		over(f)
		Mock.combat.Enter()
		falsy(f:IsKeyboardEnabled())
		for _, key in ipairs({ "SPACE", "LEFT", "END" }) do truthy(Mock.PressKey(f, key), key) end
		eq(Rp().state.cursor, 0)
		Rp().Seek(10)
		f:Hide()
		-- opened during the fight: still no keys
		RW().Open(Mock.ns.Storage.List()[1].id)
		Mock.Advance(0.5, 0.05)
		falsy(f:IsKeyboardEnabled())
		truthy(f:IsShown())
		eq(Mock.blocked, 0)
		Mock.combat.Leave()
		truthy(f:IsKeyboardEnabled())
		falsy(Mock.PressKey(f, "END"))
		eq(Rp().state.cursor, 600)
		eq(Mock.blocked, 0)
		eq(#Mock.errors, 0)
	end)

	it("never listens on a client without SetPropagateKeyboardInput", function()
		boot(function(M)
			M.features = ALL()
			M.OnFilesLoaded(function() getmetatable(UIParent).__index.SetPropagateKeyboardInput = nil end)
		end)
		local f = ready(fight())
		falsy(f:IsKeyboardEnabled())
		eq(#Mock.errors, 0)
	end)

	it("closes with Esc, also in combat (UISpecialFrames)", function()
		local f = ready(fight())
		contains(UISpecialFrames, "AzerothThreatwardenReplay")
		Mock.combat.Enter()
		f:Hide()          -- what the game does on Esc
		falsy(f:IsShown())
		isNil(Rp().state)
		eq(#Mock.errors, 0)
	end)
end)

describe("closing", function()
	it("with the cross closes the replay and drops the model; the next opening builds again", function()
		local s = fight()
		local f = ready(s)
		Rp().Do("toggle")
		f.bar.close:Click()
		falsy(f:IsShown())
		isNil(Rp().state)
		isNil(f.chart.model)
		falsy(f:IsKeyboardEnabled())
		eq(Mock.ns.Scheduler.IsRunning("replay"), false)
		ready(s)
		eq(frame(), f)
		eq(#Mock.errors, 0)
	end)

	it("hidden with the whole interface it keeps its replay, paused", function()
		local f = ready(fight())
		Rp().Do("toggle")
		UIParent:Hide()
		eq(Rp().state.playing, false)
		notNil(Rp().state)
		UIParent:Show()
		truthy(f:IsShown())
		eq(RW().mode, "ready")
		truthy(f:IsKeyboardEnabled())
		eq(#Mock.errors, 0)
	end)

	it("a build overtaken by a close or another recording leaves nothing behind", function()
		local a, b = fight(), fight()
		Mock.ns.Timeline.SLICE = 5
		RW().Open(a.id)
		RW().Open(b.id)
		for _ = 1, 400 do Mock.Advance(0.05) end
		eq(RW().mode, "ready")
		eq(Rp().state.id, b.id)
		RW().Open(a.id)
		RW().Close()
		for _ = 1, 400 do Mock.Advance(0.05) end
		isNil(Rp().state)
		falsy(frame():IsShown())
		eq(#Mock.errors, 0)
	end)
end)

describe("position, size, speed and scale (SPEC-02 §3.9)", function()
	local function place(f)
		f.bar:GetScript("OnDragStart")(f.bar)
		f:ClearAllPoints()
		f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", 100, 900)
		f.bar:GetScript("OnDragStop")(f.bar)
	end

	it("are saved on release and come back after a /reload", function()
		local s = fight()
		local f = ready(s)
		local p = { f:GetPoint(1) }
		eq(p[1], "CENTER", "in the centre until moved")
		place(f)
		deepEq(AzerothThreatwardenCharDB.ui.replay.pos, { point = "TOPLEFT", relativePoint = "BOTTOMLEFT", x = 100, y = 900 })
		f.grip:GetScript("OnMouseDown")(f.grip)
		f:SetSize(900, 600)
		f.grip:GetScript("OnMouseUp")(f.grip)
		deepEq(AzerothThreatwardenCharDB.ui.replay.size, { w = 900, h = 600 })
		f.speed.buttons[2]:Click()
		Mock.Reload()
		eq(AzerothThreatwardenCharDB.ui.replay.speed, 2)
		f = ready(St().Get(s.id))
		eq(f:GetWidth(), 900)
		eq(f:GetHeight(), 600)
		p = { f:GetPoint(1) }
		eq(p[1], "TOPLEFT")
		eq(p[4], 100)
		eq(p[5], 900)
		eq(f.speed:Active(), 2)
		eq(Rp().state.speed, 2)
		eq(#Mock.errors, 0)
	end)

	it("keeps the size within 640 x 420 and 1400 x 1000", function()
		local f = ready(fight())
		f.grip:GetScript("OnMouseDown")(f.grip)
		f:SetSize(100, 4000)
		f.grip:GetScript("OnMouseUp")(f.grip)
		eq(f:GetWidth(), 640)
		eq(f:GetHeight(), 1000)
	end)

	it("follows the scale, staying where it is, and comes back onto the screen", function()
		local f = ready(fight())
		place(f)
		truthy(Config():Set("char.ui.scale", 0.5))
		eq(f:GetScale(), 0.5)
		eq(AzerothThreatwardenCharDB.ui.replay.pos.x, 200)
		truthy(Config():Set("char.ui.scale", 1))
		Config():Set("char.ui.replay.pos", { point = "TOPLEFT", relativePoint = "BOTTOMLEFT", x = 5000, y = 900 })
		local p = { f:GetPoint(1) }
		truthy(p[4] <= 1920 - 820, "x " .. p[4])
		bus().Emit("DISPLAY_CHANGED")
		eq(#Mock.errors, 0)
	end)
end)

describe("the event list (SPEC-05 §5.4)", function()
	-- more events than rows
	local function long(n)
		local events = { { 0, "C", 0, 0, 0, "1" }, { 0, "M", 0, 0, 0, "v" }, { 0, "T", 1 } }
		for i = 1, n do events[#events + 1] = { i * 5, "D", 0, 1 } end
		events[#events + 1] = { n * 5 + 5, "c" }
		return build{ dur = n * 5 + 5, units = { ME }, events = events }
	end

	it("has only the rows that show, however long the list", function()
		local f = ready(long(300))
		local rows = #f.rows
		truthy(rows <= 20, "rows " .. rows)
		local area = f.events.areaHeight
		truthy(#shownRows(f) <= math.floor(area / RW().ROW) + 2)
		for _ = 1, 60 do Mock.RunScript(f.events.area, "OnMouseWheel", -1) end
		eq(#f.rows, rows)
		contains(shownRows(f)[1].text:GetText(), "")
		truthy(f.offset > 0)
		for _ = 1, 400 do Mock.RunScript(f.events.area, "OnMouseWheel", 1) end
		eq(f.offset, 0)
		eq(#Mock.errors, 0)
	end)

	it("gives every row its time, icon, text and category marker, and a tooltip", function()
		local f = ready(fight())
		local rows = shownRows(f)
		eq(rows[1].time:GetText(), "0:00.0")
		truthy(rows[1].text:GetText() ~= "")
		eq(rows[1].pill.label:GetText(), L().CAT_DETECTED)
		contains(tooltip(rows[1]), L().REPORTS_TIP_CATEGORY:format(L().CAT_DETECTED))
		f.filter.buttons.alerts:Click()
		eq(Rp().state.filter, "alerts")
		rows = shownRows(f)
		eq(#rows, 2)
		contains(tooltip(rows[1]), L().REPLAY_CONFIDENCE:format(""):gsub("%s+$", ""))
		f.filter.buttons.all:Click()
		truthy(#shownRows(f) > 2)
	end)

	it("focuses the clicked event: cursor, window, and the missing data of it", function()
		local f = ready(fight())
		local rows = shownRows(f)
		local target = rows[#rows]
		target:Click()
		eq(Rp().state.focus, target.index)
		eq(Rp().state.cursor, Rp().state.model.events[target.index].t)
		truthy(target.focused or shownRows(f)[1].focused ~= nil)
		local text = detailText(f)
		contains(text, L().REPLAY_SELECTED_EVENT)
		contains(text, L().REPLAY_MISSING_TITLE)
		eq(#Mock.errors, 0)
	end)

	it("says when there is no missing data in the window", function()
		local rows = {}
		for t = 0, 200, 5 do rows[#rows + 1] = { t, 1, 1, 500, "0" } end
		local s = build{ dur = 200, units = { ME }, rows = rows, events = { { 0, "C", 0, 0, 0, "1" },
			{ 0, "M", 0, 0, 0, "v" }, { 0, "T", 1 }, { 100, "D", 0, 1 }, { 200, "c" } } }
		local f = ready(s)
		for i, mk in ipairs(Rp().state.model.events) do
			if mk.k == "D" then Rp().Focus(i) end
		end
		contains(detailText(f), L().REPLAY_MISSING_NONE)
	end)

	it("switches to the details on a click in the narrow layout", function()
		local f = ready(fight())
		resize(f, 700, 520)
		shownRows(f)[2]:Click()
		truthy(f.detail:IsShown())
		falsy(f.events:IsShown())
		eq(f.switch:Active(), "details")
		contains(detailText(f), L().REPLAY_SELECTED_EVENT)
	end)

	it("keeps the last event passed in view while playing, except just after a scroll", function()
		local f = ready(long(300))
		f.speed.buttons[8]:Click()
		f.buttons.toggle:Click()
		Mock.Advance(5, 0.05)
		local last = Rp().LastRow()
		truthy(last > f.offset and last <= f.offset + f.rowsShown, "row " .. last .. " at " .. f.offset)
		local lit
		for _, row in ipairs(shownRows(f)) do if row.last then lit = row end end
		notNil(lit)
		Mock.RunScript(f.events.area, "OnMouseWheel", 1)
		local held = f.offset
		Mock.Advance(1, 0.05)
		eq(f.offset, held, "held for 3 s")
		Mock.Advance(4, 0.05)
		truthy(f.offset ~= held)
		eq(#Mock.errors, 0)
	end)

	it("says when only the start and the end of combat were recorded, and when a filter is empty", function()
		local s = build{ dur = 100, units = { ME }, events = { { 0, "C", 0, 0, 0, "1" }, { 100, "c" } } }
		local f = ready(s)
		truthy(f.events.note:IsShown())
		eq(f.events.note:GetText(), L().REPLAY_ONLY_COMBAT)
		f.filter.buttons.alerts:Click()
		eq(f.events.note:GetText(), L().REPLAY_NO_EVENTS)
		eq(#shownRows(f), 0)
	end)
end)

describe("the detail (SPEC-05 §5.3)", function()
	it("gives each value its category, estimates in warn and unknowns in text-3", function()
		local f = ready(fight(), 100)
		local me = unitWidget(f, 1)
		notNil(me)
		contains(me.reading:GetText(), "50.0 %")
		eq(me.badge:GetState(), "warning")
		local tip = tooltip(me)
		contains(tip, L().REPLAY_STATE_TIP:format(L().TIMELINE_STATE_WARNING, L().CAT_CALCULATED))
		contains(tip, "(" .. L().CAT_DETECTED .. ")")
		contains(tip, L().REPLAY_UNIT_TIP)
		Rp().Seek(218)
		me = unitWidget(f, 1)
		contains(me.reading:GetText(), "No reading since")
		eq(me.reading.token, nil)
		contains(detailText(f), L().REPLAY_HOLDS_TANK:format("Bram"))
		contains(detailText(f), "Gorrak")
		eq(#Mock.errors, 0)
	end)

	it("recomputes the age of an estimate as the cursor moves", function()
		local rows = { { 10, 1, 1, 500, "0" }, { 60, 1, 1, 600, "0" } }
		local s = build{ dur = 200, units = { ME }, rows = rows, events = { { 0, "C", 0, 0, 0, "1" },
			{ 0, "M", 0, 0, 0, "v" }, { 0, "T", 1 }, { 0, "S", 1, 1, 0, "S", "-" }, { 200, "c" } } }
		local f = ready(s, 30)
		local before = unitWidget(f, 1).reading:GetText()
		contains(before, "~50.0 %")
		Rp().Seek(36)
		local after = unitWidget(f, 1).reading:GetText()
		contains(after, "~50.0 %")
		truthy(before ~= after, before .. " / " .. after)
		eq(f.detail.estimates[1], unitWidget(f, 1))
		contains(tooltip(unitWidget(f, 1)), "Estimate: the last reading")
	end)

	it("shows or hides a unit on the chart with a click on its name", function()
		local f = ready(fight(), 100)
		local me = unitWidget(f, 1)
		truthy(me.series ~= nil)
		me:Click()
		local found = false
		for _, u in ipairs(Rp().state.series) do if u == 1 then found = true end end
		falsy(found)
		for _, u in ipairs(f.chart.shown) do ne(u, 1) end
		unitWidget(f, 1):Click()
		found = false
		for _, u in ipairs(f.chart.shown) do if u == 1 then found = true end end
		truthy(found)
		eq(#Mock.errors, 0)
	end)

	it("shows nothing read out of combat", function()
		local s = build{ dur = 200, units = { ME }, events = { { 0, "C", 0, 0, 0, "1" }, { 100, "c" },
			{ 150, "C", 0, 0, 0, "2" }, { 200, "c" } } }
		local f = ready(s, 120)
		contains(detailText(f), L().REPLAY_OUT_OF_COMBAT)
		eq(f.detail.units.used, 0)
	end)

	it("keeps its pools while the cursor goes through the whole fight, again and again", function()
		local f = ready(fight())
		for t = 0, 600, 7 do Rp().Seek(t) end
		local lines, units, rows = #f.detail.lines.list, #f.detail.units.list, #f.rows
		for _ = 1, 3 do
			for t = 0, 600, 7 do Rp().Seek(t) end
			for i = 1, #Rp().state.model.events do Rp().Focus(i) end
		end
		truthy(#f.detail.lines.list <= lines + 8, "lines " .. #f.detail.lines.list)
		eq(#f.detail.units.list, units)
		eq(#f.rows, rows)
		eq(#Mock.errors, 0)
	end)
end)

describe("Italian", function()
	before_boot(function(M) M.features = ALL(); M.player.locale = "itIT" end)
	it("shows the window in Italian", function()
		local f = ready(fight(), 100)
		eq(f.bar.title:GetText(), L().REPLAY_TITLE)
		eq(f.events.title:GetText(), "Eventi")
		contains(detailText(f), "In combattimento")
		eq(f.speed.buttons[2].label:GetText(), "2×")
	end)
end)
