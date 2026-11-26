-- What a comparison of twenty fights may cost (run_tests.py --long, SPEC-06 §2.4, M6.3): twenty sessions of the same
-- enemy at the row limit (30 000 rows: 40 units for 750 recording ticks), compared with Compare.Build. The queue builds
-- one session at a time with Metrics.Build in slices; every frame of it is measured against the worst frame of the
-- report built in slices on the same kind of session (Report.Build: the report's budget, SPEC-05 §3.4), and the memory
-- after the comparison must not grow past what the cache of the metrics holds. Offline numbers on the mock client: the
-- cost in the game is the probe's P10.
--
-- Work is counted in Lua VM instructions (T.instructions), the same on every machine.

local UNITS, TICKS, STEP, FIGHTS = 40, 750, 5, 20

-- A frame of the queue may cost at most this much more than the report's worst frame: the metrics' passes over the
-- events and the rows do a little more per row than the report's. M6.3 measured 1.00: the worst frame of both is the
-- first one, Storage.Decode of the session and a first slice of the report's own pass.
local FRAME_FACTOR = 1.5
-- What a second comparison of the same twenty fights (all from the cache) may leave in memory.
local REPEAT_KB = 256

before_boot(function(M)
	M.features = { monitor = true, alerts = true, coach = true, recording = true, reports = true, timeline = true,
		analytics = true }
end)

local function fullSession(k)
	local S = Mock.ns.Session
	local s = S.New{ id = "compare-" .. k, started = 4000 + k, group = "raid", diff = 3,
		rec = { hz = 2, warning = 80, danger = 95, mode = "values" } }
	for u = 1, UNITS do
		S.AddUnit(s, { name = "Raider" .. u, token = "raid" .. u, me = u == 1 or nil,
			role = u <= 2 and "TANK" or "DAMAGER" }, 0)
	end
	S.AddMob(s, { name = "Boss", class = "worldboss", npc = 9001 }, 0)
	S.AddEvent(s, 0, "C", 0, 0, 0, "1")
	S.AddEvent(s, 0, "M", 0, 0, 0, "v")
	S.AddEvent(s, 0, "T", 1)
	S.AddEvent(s, 0, "A", 1, 2, 0, "1")
	for u = 1, UNITS do S.AddEvent(s, 0, "S", 1, u, 0, "S", "-") end
	for tick = 1, TICKS do
		local t = tick * STEP
		for u = 1, UNITS do
			local p = u == 2 and 1000 or ((tick * 7 + u * 13 + k) % 1100)
			S.AddRow(s, t, 1, u, p, p >= 1000 and "3" or "0")
		end
		if tick % 50 == 0 then
			local u = 3 + tick % 30
			S.AddEvent(s, t, "S", 1, u, 0, "W", "S")
			S.AddEvent(s, t + 1, "S", 1, u, 0, "S", "W")
		end
	end
	for u = 1, UNITS do s.q.v[u] = TICKS end
	S.AddEvent(s, TICKS * STEP + 5, "c")
	S.Join(s)
	s.state, s.ended, s.dur, s.fight = "complete", "combat", TICKS * STEP + 5, TICKS * STEP + 5
	eq(s.n, S.LIMITS.rows)
	truthy(Mock.ns.Storage.Add(s))
	truthy(Mock.ns.Storage.Closed(s, true))
	return s
end

-- Runs the frames of Compat.After one by one, each measured; returns the worst frame and the count.
local function pump(start)
	local Compat = Mock.ns.Compat
	local queue, after = {}, Compat.After
	Compat.After = function(_, fn) queue[#queue + 1] = fn return true end
	local worst, count = T.instructions(start, 1000), 1
	while #queue > 0 do
		local fn = table.remove(queue, 1)
		local work = T.instructions(fn, 1000)
		count = count + 1
		if work > worst then worst = work end
	end
	Compat.After = after
	return worst, count
end

local function kb()
	collectgarbage("collect")
	collectgarbage("collect")
	return collectgarbage("count")
end

describe("the cost of a comparison of twenty fights at the row limit (SPEC-06 §2.4)", function()
	it("keeps every frame within the report's budget and the memory within the cache", function()
		local Compare, Metrics, Report = Mock.ns.Compare, Mock.ns.Metrics, Mock.ns.Report
		-- twenty full raid sessions need more than the default 2 MB of recordings (about 250 KB each)
		truthy(Mock.ns.Config:Set("account.settings.recording.maxKB", Mock.ns.Config.RECORDING.maxKB.max))
		local sessions = {}
		for k = 1, FIGHTS do sessions[k] = fullSession(k) end
		eq(#Compare.Set("npc:9001").fights, FIGHTS)

		local report
		local reportWorst, reportFrames = pump(function() Report.Build(sessions[1].id, function(r) report = r end) end)
		notNil(report)
		T.log(("report: worst frame %d instructions over %d frames"):format(reportWorst, reportFrames))

		-- a cache smaller than the set first: every session built, the memory held at the cache
		local CACHE = Metrics.CACHE
		Metrics.CACHE = 5
		local before = kb()
		local small
		local worst, count = pump(function() Compare.Build("npc:9001", nil, nil, function(r) small = r end) end)
		notNil(small)
		eq(#small.rows, FIGHTS)
		eq(small.counted, FIGHTS)
		eq(small.aggregates.warningCross.n, FIGHTS)
		eq(small.aggregates.closest.n, FIGHTS)
		eq(Metrics.CacheSize(), 5)
		T.log(("comparison: worst frame %d instructions over %d frames (%.2f of the report's)"):format(worst, count,
			worst / reportWorst))
		truthy(worst <= reportWorst * FRAME_FACTOR, ("worst frame %d, report %d"):format(worst, reportWorst))
		truthy(count >= FIGHTS, "one session at a time")
		small = nil
		Compare.Cancel()
		local afterSmall = kb()
		T.log(("with a cache of 5: %.0f KB kept"):format(afterSmall - before))

		-- the default cache holds all twenty; the same comparison again comes from it and keeps nothing more
		Metrics.CACHE = CACHE
		local result
		pump(function() Compare.Build("npc:9001", nil, nil, function(r) result = r end) end)
		notNil(result)
		eq(#result.rows, FIGHTS)
		eq(Metrics.CacheSize(), FIGHTS)
		local first = kb()
		T.log(("with the default cache: %.0f KB kept"):format(first - before))
		local again
		local worst2, count2 = pump(function() Compare.Build("npc:9001", nil, nil, function(r) again = r end) end)
		notNil(again)
		local second = kb()
		T.log(("again from the cache: worst frame %d over %d frames; %.0f KB more"):format(worst2, count2,
			second - first))
		truthy(second - first <= REPEAT_KB, ("grew %.0f KB"):format(second - first))
		eq(count2, 1, "all from memory, in one frame")
		truthy((afterSmall - before) * 2 < first - before, "the memory follows the cache, not the set")
		eq(#Mock.errors, 0)
	end)
end)
