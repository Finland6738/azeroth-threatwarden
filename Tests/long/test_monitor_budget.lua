-- What one tick of the threat monitor may cost (run_tests.py --long, SPEC-01 §5, SPEC-09 Q14, M2.7): a full tick of
-- the pipeline (40 reads, model and calculator, states, the list with its window) in a raid of 40, at 2, 5 and 10 Hz,
-- on one mob and with a new target every few ticks; and, since M4.6, with a recording open (its own tick at the
-- recording rate, 2 Hz) and what that recording tick alone may cost. A regression fails here. These are offline
-- numbers on the mock client: the cost in the game is the probe's P10, and the default rate stays provisional until
-- then.
--
-- Three measures, each made to give the same answer from run to run:
--   work         Lua VM instructions per tick (T.instructions): the same on every machine, the tight bound
--   allocation   growth of the Lua state per tick with the collector stopped, the smallest of three batches after a
--                full collection and a warm-up
--   time         os.clock per tick, as a ratio of a fixed reference loop run in turn with it, the median of seven
--                batches: a slower or busier machine slows both
-- The mock's widgets allocate a table in several setters and in Show and Hide; during the measures those write into
-- place, so that what grows is the addon's. The game functions are constant answers (Tests/lib/raid.lua and below).
--
-- The budgets are about 1.3 times (work), twice (allocation) and twice or more (time) what M2.7 measured. When a change
-- needs more on purpose, measure, say why in the pull request and move the numbers here and in SPEC-01 §5.

local WARMUP = 600          -- ticks before any measure: rows, widgets, rings and strings made
local INSTRUCTION_TICKS = 200
local ALLOC_TICKS, ALLOC_BATCHES = 400, 3
local TIME_TICKS, TIME_BATCHES = 100, 7

-- Measured by M2.7 over the six cases: 156 000 to 168 000 instructions, 14 to 27 bytes and 9 to 14 reference units per
-- tick. The same budget for every rate and case. One table made per tick (some 60 bytes) already breaks `bytes`.
local BUDGET = {
	instructions = 220000,   -- per tick
	bytes = 48,              -- allocated per tick
	time = 30,               -- per tick, in runs of the reference loop
}

-- Three sets of switches: the monitor alone (the M2.7 measure), the one shipped since v0.3.0, with the alerts and the
-- Coach, and the one shipped since v0.4.0, recording too. M3.R measured 39 to 113 bytes per tick with the alerts and the Coach
-- (the strip writes new texts as its numbers change, at most once a second, so fewer reads per second cost more per
-- tick); work and time stayed as for the monitor alone. M4.6 measured with a recording open, its tick among the
-- monitor's: 162 000 to 181 000 instructions (the budget of work stays), 9 to 11 reference units, and 110 to 610 bytes
-- per tick (the rows kept, 8 bytes each, and the joining of 256 of them): the budget is twice the most.
local CONFIGS = {
	{ name = "the monitor alone", alerts = false, coach = false, bytes = BUDGET.bytes },
	{ name = "with the alerts and the Coach", alerts = true, coach = true, bytes = 160 },
	{ name = "with recording too", alerts = true, coach = true, recording = true, bytes = 1200 },
}

-- One recording tick (M4.6, SPEC-05 §1.8, SPEC-01 §5.1) with 40 units, measured alone. M4.6 measured, in values,
-- state only and nothing readable: 27 000 / 13 600 / 13 200 instructions on average and at most 67 000 (a tick that
-- packs 256 rows), 370 to 515 / at most 7 / 0 bytes (in values the pieces of the 38 rows, 8 bytes each, and the
-- buffers of their joining; it was 8 600 before M4.6 made the packing reuse one table). The budgets are about 1.3
-- times (work) and twice or more (allocation) that. At 2 Hz it is under a tenth of what
-- the monitor does in a second at 5 Hz.
local RECORD = { instructions = 36000, worst = 90000, bytes = { values = 1024, state = 48, none = 48 } }
local RECORD_TICKS = 400

local function noop() end

-- Keeps the function of the recording tick when the recorder starts it, so that the tests call it themselves.
local function catchRecordTick()
	local ns, found = Mock.ns, {}
	local start = ns.Scheduler.Start
	ns.Scheduler.Start = function(name, hz, fn, opts)
		if name == ns.Recorder.TICK then found.fn, found.hz = fn, hz end
		return start(name, hz, fn, opts)
	end
	return found
end

-- No limit of a session is reached during a measure (30 000 rows are some 800 ticks of 38 rows): a recorder that
-- stopped writing would cost nothing.
local function unlimited()
	local L = Mock.ns.Session.LIMITS
	L.rows, L.events = 1e7, 1e7
end

-- The setters of the mock widgets the pipeline calls on a tick, writing into place instead of making a table.
local function quietWidgets()
	local widget = getmetatable(Mock.ns.ThreatList.view).__index
	local function colour(field)
		return function(self, r, g, b, a)
			local c = rawget(self, field)
			if not c then
				c = {}
				self[field] = c
			end
			c[1], c[2], c[3], c[4] = r, g, b, a or 1
		end
	end
	widget.SetVertexColor, widget.SetColorTexture, widget.SetTextColor =
		colour("_vertex"), colour("_texture"), colour("_textColor")
	widget.SetTexCoord, widget.SetPoint, widget.ClearAllPoints = noop, noop, noop
	-- the mock runs the show and hide scripts of a frame and its children through tables of arguments
	widget.Show = function(self) self._shown = true end
	widget.Hide = function(self) self._shown = false end
	-- the mock's animations make a closure and a table at every call of a setter (the fades of the heat, M8.3): the
	-- same calls, written into place
	local anim = UIParent:CreateAnimationGroup():CreateAnimation("Alpha")
	local meta, made = getmetatable(anim), {}
	meta.__index = function(_, key)
		local fn = made[key]
		if not fn then
			local field = key:sub(4)
			if key:sub(1, 3) == "Set" then
				fn = function(me, v)
					local t = me._set[field]
					if not t then
						t = {}
						me._set[field] = t
					end
					t[1] = v
					return me
				end
			elseif key:sub(1, 3) == "Get" then
				fn = function(me) local t = me._set[field]; if t then return t[1] end end
			else
				fn = function(me) return me end
			end
			made[key] = fn
		end
		return fn
	end
end

-- A fixed piece of plain Lua of the kind the pipeline does (calls under pcall, table reads and writes, arithmetic): the
-- unit of the time budget.
local ref = {}
for i = 1, 64 do ref[i] = i end
local function reference()
	local floor, total = math.floor, 0
	for _ = 1, 20 do
		for i = 1, 64 do
			local _, v = pcall(floor, ref[i] * 1.5)
			ref[i] = i
			total = total + v
		end
	end
	return total
end

-- Builds the raid, the window and the tick. `switching`: a new target every 25 ticks (a new creature behind the target
-- token, as TargetTracker.Check sees it at a scan: no event of the mock, which would allocate).
local function setup(rate, switching, recording)
	local ns = Mock.ns
	local record = recording and catchRecordTick()
	if recording then unlimited() end
	local raid = Raid.new()
	truthy(ns.Config:Set("account.settings.monitor.show", "manual"))
	truthy(ns.Config:Set("account.settings.monitor.rate", rate))
	ns.Window:Open()
	ns.Window:SelectTab("monitor")
	ns.ThreatList.view:Layout(560, 760)
	raid:advance(1)
	ns.Scheduler.Stop("threat")   -- the ticks are made here
	if recording then
		truthy(record.fn and ns.Recorder.current, "a recording is open")
		ns.Scheduler.Stop(ns.Recorder.TICK)
	end
	local guids = {}
	for i = 1, 5 do guids[i] = "Creature-0-1-0-1-100-000000000" .. i end
	local guid, ticks = guids[1], 0
	UnitExists = function() return true end
	UnitIsDead = function() return false end
	UnitGUID = function(unit) if unit == "target" then return guid end return nil end
	quietWidgets()
	local Scan, dt = ns.ThreatScanner.Scan, 1 / rate
	local owed = 0                -- seconds since the last recording tick
	local function tick()
		ticks = ticks + 1
		if switching and ticks % 25 == 0 then
			local m = ticks / 25 % 5 + 1
			guid, raid.mob = guids[m], m
		end
		raid:step(dt)
		Mock.StepClock(dt)
		Scan()
		if recording then
			owed = owed + dt
			if owed >= 1 / record.hz - 1e-9 then
				owed = owed - 1 / record.hz
				record.fn()
			end
		end
	end
	for _ = 1, WARMUP do tick() end
	return tick
end

local function run(tick, n)
	for _ = 1, n do tick() end
end

local function median(list)
	table.sort(list)
	return list[math.floor((#list + 1) / 2)]
end

local function measure(tick)
	local instructions = T.instructions(function() run(tick, INSTRUCTION_TICKS) end) / INSTRUCTION_TICKS

	local grown = math.huge
	for _ = 1, ALLOC_BATCHES do
		collectgarbage("collect")
		collectgarbage("collect")
		collectgarbage("stop")
		local before = collectgarbage("count")
		run(tick, ALLOC_TICKS)
		grown = math.min(grown, collectgarbage("count") - before)
		collectgarbage("restart")
	end
	local bytes = grown * 1024 / ALLOC_TICKS

	local ratios, ms = {}, {}
	for b = 1, TIME_BATCHES do
		collectgarbage("collect")
		local t0 = Mock.RealClock()
		run(reference, TIME_TICKS)
		local t1 = Mock.RealClock()
		run(tick, TIME_TICKS)
		local t2 = Mock.RealClock()
		run(reference, TIME_TICKS)
		local t3 = Mock.RealClock()
		local unit = ((t1 - t0) + (t3 - t2)) / (2 * TIME_TICKS)
		ratios[b] = (t2 - t1) / TIME_TICKS / math.max(unit, 1e-9)
		ms[b] = (t2 - t1) * 1000 / TIME_TICKS
	end
	return instructions, bytes, median(ratios), median(ms)
end

for _, config in ipairs(CONFIGS) do
describe("the budget of one tick in a raid of 40, " .. config.name, function()
	before_boot(function(M)
		M.features = { monitor = true, alerts = config.alerts, coach = config.coach, recording = config.recording == true,
			reports = config.recording == true }
	end)

	for _, case in ipairs({ { id = "one", name = "on one mob" }, { id = "switching", name = "with new targets" } }) do
		for _, rate in ipairs({ 2, 5, 10 }) do
			it(("stays inside its budget at %d Hz %s"):format(rate, case.name), function()
				local tick = setup(rate, case.id == "switching", config.recording)
				local ns = Mock.ns
				local scans, changes = ns.ThreatScanner.scans, ns.ThreatState.changes
				local targets = 0
				ns.Bus.On("TARGET_CHANGED", function() targets = targets + 1 end)
				local session = ns.Recorder and ns.Recorder.current
				local rows = session and session.n
				local instructions, bytes, time, ms = measure(tick)
				local ticks = INSTRUCTION_TICKS + ALLOC_TICKS * ALLOC_BATCHES + TIME_TICKS * TIME_BATCHES
				-- what was measured really ran: every tick scanned 40 units, the rows changed, the list was drawn
				truthy(ns.ThreatScanner.scans - scans >= ticks)
				eq(ns.ThreatModel.count, 40)
				truthy(ns.ThreatState.changes > changes, "states changed")
				truthy(ns.ThreatList.view.shownRows >= 20, "rows drawn: " .. ns.ThreatList.view.shownRows)
				if case.id == "switching" then truthy(targets >= ticks / 25 - 2, "targets: " .. targets) end
				if config.recording then
					-- the recording tick ran at 2 Hz and wrote a row for most units each time
					eq(ns.Recorder.current, session)
					isNil(session.trunc)
					local written = session.n - rows
					truthy(written > ticks / rate * 2 * 20, "rows recorded: " .. written)
				end
				eq(#Mock.errors, 0)
				eq(ns.Bus.errorCount, 0)
				T.log(("%d Hz %s: %.2f ms/tick (%.1f ms per second, time %.2f), %.0f instructions, %.1f B/tick"):format(
					rate, case.name, ms, ms * rate, time, instructions, bytes))
				truthy(instructions <= BUDGET.instructions,
					("work: %.0f instructions per tick, budget %d"):format(instructions, BUDGET.instructions))
				truthy(bytes <= config.bytes, ("allocation: %.1f B per tick, budget %d"):format(bytes, config.bytes))
				truthy(time <= BUDGET.time, ("time: %.1f reference units per tick, budget %d"):format(time, BUDGET.time))
			end)
		end
	end
end)
end

describe("the budget of one recording tick in a raid of 40", function()
	before_boot(function(M)
		M.features = { monitor = true, alerts = true, coach = true, recording = true, reports = true }
	end)

	for _, outcome in ipairs(Fight.OUTCOMES) do
		it("stays inside its budget in " .. outcome, function()
			local ns = Mock.ns
			local record = catchRecordTick()
			unlimited()
			local raid = Raid.new()
			raid:outcome(outcome)
			truthy(ns.Config:Set("account.settings.monitor.show", "manual"))   -- the window stays closed
			raid:advance(1)
			local s = ns.Recorder.current
			truthy(record.fn and s, "a recording is open")
			ns.Scheduler.Stop(ns.Recorder.TICK)
			ns.Scheduler.Stop("threat")
			local Scan, tick = ns.ThreatScanner.Scan, record.fn
			local function read()                   -- what the scanner does between two recording ticks
				raid:step(0.5)
				Mock.StepClock(0.5)
				Scan()
			end
			for _ = 1, 100 do read() tick() end

			local total, worst, rows = 0, 0, s.n
			for _ = 1, RECORD_TICKS do
				read()
				local instructions = T.instructions(tick, 10)
				total = total + instructions
				if instructions > worst then worst = instructions end
			end
			local average, written = total / RECORD_TICKS, (s.n - rows) / RECORD_TICKS

			local grown = math.huge
			for _ = 1, ALLOC_BATCHES do
				collectgarbage("collect")
				collectgarbage("collect")
				collectgarbage("stop")
				local sum = 0
				for _ = 1, RECORD_TICKS do
					read()
					local before = collectgarbage("count")
					tick()
					sum = sum + collectgarbage("count") - before
				end
				collectgarbage("restart")
				grown = math.min(grown, sum)
			end
			local bytes = grown * 1024 / RECORD_TICKS

			eq(ns.ThreatModel.count, 40)
			eq(ns.Recorder.current, s)
			isNil(s.trunc)
			-- what was measured really ran: with values every unit on the list gives a row each time
			if outcome == "values" then truthy(written > 30, "rows per tick: " .. written) end
			local counted = 0
			for i = 1, #s.units do counted = counted + s.q.v[i] + s.q.s[i] + s.q.x[i] end
			truthy(counted > 30 * RECORD_TICKS, "units counted: " .. counted)
			eq(#Mock.errors, 0)
			eq(ns.Bus.errorCount, 0)
			T.log(("recording tick, %s: %.0f instructions (at most %.0f), %.1f B, %.1f rows"):format(outcome, average, worst,
				bytes, written))
			truthy(average <= RECORD.instructions,
				("work: %.0f instructions per tick, budget %d"):format(average, RECORD.instructions))
			truthy(worst <= RECORD.worst, ("work: %.0f instructions in one tick, budget %d"):format(worst, RECORD.worst))
			truthy(bytes <= RECORD.bytes[outcome],
				("allocation: %.1f B per tick, budget %d"):format(bytes, RECORD.bytes[outcome]))
		end)
	end
end)

-- The heat of the rows and the overlay on the game's raid frames (M8.3, SPEC-08 §8, SPEC-07 §3.1 HM-06): the same tick
-- of the monitor alone at 5 Hz, measured without the heatmap, with the heat of the rows, and with the overlay too (40
-- frames of the game, Tests/mock/55_raidframes.lua, copied before the fight). The same budgets as the monitor alone;
-- the heat may add at most HEAT instructions per tick and the overlay at most OVERLAY more, and neither any byte after
-- the warm-up (within the noise of the measure, NOISE bytes).
local HEAT, OVERLAY, NOISE = 8000, 15000, 4
local heatMeasures = {}

describe("the budget of one tick in a raid of 40 with the heatmap (M8.3)", function()
	before_boot(function(M)
		M.features = { monitor = true, alerts = false, coach = false, recording = false, reports = false,
			heatmap = true, multitarget = false }
		local units = {}
		for i = 1, 40 do units[i] = "raid" .. i end
		M.raidFrames.Raid(units, true)
	end)

	for _, case in ipairs({ { id = "off", rows = false, raid = false }, { id = "rows", rows = true, raid = false },
		{ id = "overlay", rows = true, raid = true } }) do
		it("measures the tick at 5 Hz: " .. case.id, function()
			local ns = Mock.ns
			truthy(ns.Config:Set("account.settings.heatmap.rows", case.rows))
			truthy(ns.Config:Set("account.settings.heatmap.raidFrames", case.raid))
			local tick = setup(5, false, false)
			if case.raid then
				truthy(ns.RaidOverlay.Active())
				eq(ns.RaidOverlay.count, 40)
				truthy(ns.RaidOverlay.shown > 0, "marks shown in the fight: " .. ns.RaidOverlay.shown)
			end
			local instructions, bytes, time, ms = measure(tick)
			heatMeasures[case.id] = { instructions = instructions, bytes = bytes }
			eq(#Mock.errors, 0)
			eq(ns.Bus.errorCount, 0)
			deepEq(Mock.raidFrames.log, {}, "no forbidden touch of the game's frames")
			T.log(("heatmap %s: %.2f ms/tick (time %.2f), %.0f instructions, %.1f B/tick"):format(case.id, ms, time,
				instructions, bytes))
			truthy(instructions <= BUDGET.instructions,
				("work: %.0f instructions per tick, budget %d"):format(instructions, BUDGET.instructions))
			truthy(bytes <= BUDGET.bytes, ("allocation: %.1f B per tick, budget %d"):format(bytes, BUDGET.bytes))
			truthy(time <= BUDGET.time, ("time: %.1f reference units per tick, budget %d"):format(time, BUDGET.time))
		end)
	end

	it("adds at most 8 000 instructions for the heat and 15 000 for the overlay, and no allocation", function()
		local off, rows, overlay = heatMeasures.off, heatMeasures.rows, heatMeasures.overlay
		truthy(off and rows and overlay, "the three measures ran")
		local heat, marks = rows.instructions - off.instructions, overlay.instructions - rows.instructions
		T.log(("heat of the rows: %+.0f instructions, %+.1f B; overlay: %+.0f instructions, %+.1f B per tick"):format(heat,
			rows.bytes - off.bytes, marks, overlay.bytes - rows.bytes))
		truthy(heat <= HEAT, ("heat: %.0f instructions per tick, budget %d"):format(heat, HEAT))
		truthy(marks <= OVERLAY, ("overlay: %.0f instructions per tick, budget %d"):format(marks, OVERLAY))
		truthy(rows.bytes - off.bytes <= NOISE, ("heat: %.1f B per tick more"):format(rows.bytes - off.bytes))
		truthy(overlay.bytes - rows.bytes <= NOISE, ("overlay: %.1f B per tick more"):format(overlay.bytes - rows.bytes))
	end)
end)
