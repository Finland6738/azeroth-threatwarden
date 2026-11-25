-- What one tick of the threat monitor may cost (run_tests.py --long, SPEC-01 §5, SPEC-09 Q14, M2.7): a full tick of
-- the pipeline (40 reads, model and calculator, states, the list with its window) in a raid of 40, at 2, 5 and 10 Hz,
-- on one mob and with a new target every few ticks. A regression fails here. These are offline numbers on the mock
-- client: the cost in the game is the probe's P10, and the default rate stays provisional until then.
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

before_boot(function(M) M.features = { monitor = true } end)

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

local function noop() end

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
local function setup(rate, switching)
	local ns = Mock.ns
	local raid = Raid.new()
	truthy(ns.Config:Set("account.settings.monitor.show", "manual"))
	truthy(ns.Config:Set("account.settings.monitor.rate", rate))
	ns.Window:Open()
	ns.Window:SelectTab("monitor")
	ns.ThreatList.view:Layout(560, 760)
	raid:advance(1)
	ns.Scheduler.Stop("threat")   -- the ticks are made here
	local guids = {}
	for i = 1, 5 do guids[i] = "Creature-0-1-0-1-100-000000000" .. i end
	local guid, ticks = guids[1], 0
	UnitExists = function() return true end
	UnitIsDead = function() return false end
	UnitGUID = function(unit) if unit == "target" then return guid end return nil end
	quietWidgets()
	local Scan, dt = ns.ThreatScanner.Scan, 1 / rate
	local function tick()
		ticks = ticks + 1
		if switching and ticks % 25 == 0 then
			local m = ticks / 25 % 5 + 1
			guid, raid.mob = guids[m], m
		end
		raid:step(dt)
		Mock.StepClock(dt)
		Scan()
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

describe("the budget of one tick in a raid of 40", function()
	for _, case in ipairs({ { id = "one", name = "on one mob" }, { id = "switching", name = "with new targets" } }) do
		for _, rate in ipairs({ 2, 5, 10 }) do
			it(("stays inside its budget at %d Hz %s"):format(rate, case.name), function()
				local tick = setup(rate, case.id == "switching")
				local ns = Mock.ns
				local scans, changes = ns.ThreatScanner.scans, ns.ThreatState.changes
				local targets = 0
				ns.Bus.On("TARGET_CHANGED", function() targets = targets + 1 end)
				local instructions, bytes, time, ms = measure(tick)
				local ticks = INSTRUCTION_TICKS + ALLOC_TICKS * ALLOC_BATCHES + TIME_TICKS * TIME_BATCHES
				-- what was measured really ran: every tick scanned 40 units, the rows changed, the list was drawn
				truthy(ns.ThreatScanner.scans - scans >= ticks)
				eq(ns.ThreatModel.count, 40)
				truthy(ns.ThreatState.changes > changes, "states changed")
				truthy(ns.ThreatList.view.shownRows >= 20, "rows drawn: " .. ns.ThreatList.view.shownRows)
				if case.id == "switching" then truthy(targets >= ticks / 25 - 2, "targets: " .. targets) end
				eq(#Mock.errors, 0)
				eq(ns.Bus.errorCount, 0)
				T.log(("%d Hz %s: %.2f ms/tick (%.1f ms per second, time %.2f), %.0f instructions, %.1f B/tick"):format(
					rate, case.name, ms, ms * rate, time, instructions, bytes))
				truthy(instructions <= BUDGET.instructions,
					("work: %.0f instructions per tick, budget %d"):format(instructions, BUDGET.instructions))
				truthy(bytes <= BUDGET.bytes, ("allocation: %.1f B per tick, budget %d"):format(bytes, BUDGET.bytes))
				truthy(time <= BUDGET.time, ("time: %.1f reference units per tick, budget %d"):format(time, BUDGET.time))
			end)
		end
	end
end)
