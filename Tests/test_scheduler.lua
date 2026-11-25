-- Core/Scheduler.lua (SPEC-01 §5, ARC-05, ARC-06, ARC-09): one ticker per name, rate limits, stop at COMBAT_ENDED, an
-- error stops its tick, the cost is measured, nothing runs unless asked, a tick allocates nothing.

local function S() return Mock.ns.Scheduler end

describe("starting and stopping", function()
	it("runs nothing at login (no tick in M1)", function()
		deepEq(S().Active(), {})
		eq(Mock.PendingTimers(), 0)
		deepEq(S().DebugLines(), { "no tick running" })
	end)

	it("runs a named tick at its rate until it is stopped", function()
		local n = 0
		truthy(S().Start("test", 5, function() n = n + 1 end))
		truthy(S().IsRunning("test"))
		eq(S().Rate("test"), 5)
		Mock.Advance(2)
		eq(n, 10)
		truthy(S().Stop("test"))
		falsy(S().Stop("test"))
		Mock.Advance(2)
		eq(n, 10)
		eq(Mock.PendingTimers(), 0)
		falsy(S().IsRunning("test"))
		isNil(S().Rate("test"))
	end)

	it("keeps one client ticker per name: a second Start replaces the first", function()
		local first, second = 0, 0
		S().Start("test", 10, function() first = first + 1 end)
		S().Start("test", 2, function() second = second + 1 end)
		eq(Mock.PendingTimers(), 1)
		Mock.Advance(1)
		eq(first, 0)
		eq(second, 2)
		deepEq(S().Active(), { "test" })
	end)

	it("keeps the rate between 1 and 10 Hz", function()
		local n = 0
		S().Start("fast", 60, function() n = n + 1 end)
		eq(S().Rate("fast"), 10)
		Mock.Advance(1)
		eq(n, 10)
		S().Start("slow", 0.1, function() end)
		eq(S().Rate("slow"), 1)
	end)

	it("refuses a bad name, rate or function", function()
		falsy(S().Start("", 5, function() end))
		falsy(S().Start(nil, 5, function() end))
		falsy(S().Start("test", "fast", function() end))
		falsy(S().Start("test", 0 / 0, function() end))
		falsy(S().Start("test", 5, nil))
		deepEq(S().Active(), {})
	end)

	it("answers false, without an error, on a client without timers", function()
		C_Timer.NewTicker = nil
		falsy(S().Start("test", 5, function() end))
		falsy(S().IsRunning("test"))
		eq(#Mock.errors, 0)
	end)

	it("stops every tick at once", function()
		S().Start("a", 1, function() end)
		S().Start("b", 1, function() end)
		S().StopAll()
		deepEq(S().Active(), {})
		eq(Mock.PendingTimers(), 0)
	end)
end)

describe("combat (ARC-05)", function()
	it("stops the ticks bound to combat at COMBAT_ENDED and keeps the others", function()
		Mock.combat.Enter()
		S().Start("threat", 5, function() end, { combat = true })
		S().Start("other", 1, function() end)
		Mock.Advance(1)
		Mock.combat.Leave()
		falsy(S().IsRunning("threat"))
		truthy(S().IsRunning("other"))
	end)
end)

describe("errors (ARC-09, ARC-10)", function()
	it("an error stops that tick only, reaches no player and goes into the error ring", function()
		local good = 0
		S().Start("bad", 10, function() error("tick boom") end)
		S().Start("good", 10, function() good = good + 1 end)
		Mock.Advance(1)
		falsy(S().IsRunning("bad"))
		eq(good, 10)
		eq(#Mock.errors, 0)
		local errors = Mock.ns.Diagnostics.Errors()
		eq(#errors, 1)
		contains(errors[1].text, "tick bad stopped")
		contains(errors[1].text, "tick boom")
	end)
end)

describe("cost (ARC-09)", function()
	it("measures the median and the maximum of the last ticks through Compat", function()
		local ms = 0
		local costs = { 1, 5, 2, 9, 3 }
		local i = 0
		debugprofilestop = function() return ms end
		S().Start("test", 10, function()
			i = i + 1
			ms = ms + costs[(i - 1) % #costs + 1]
		end)
		isNil((S().Cost("test")))
		Mock.Advance(0.5)
		local median, max, ticks, errors = S().Cost("test")
		eq(median, 3)
		eq(max, 9)
		eq(ticks, 5)
		eq(errors, 0)
		contains(S().DebugLines(), "test: 10 Hz, 5 ticks, 3.000 ms median, 9.000 ms max")
		isNil(S().Cost("nothing"))
	end)

	it("keeps only the last SAMPLES ticks, and runs without the profiling clock", function()
		local ms = 0
		debugprofilestop = function() return ms end
		S().Start("test", 10, function() ms = ms + 1 end)
		Mock.Advance((S().SAMPLES + 20) / 10)
		local median, max, ticks = S().Cost("test")
		eq(ticks, S().SAMPLES + 20)
		eq(median, 1)
		eq(max, 1)
		debugprofilestop = nil
		S().Start("blind", 1, function() end)
		Mock.Advance(1)
		local m, _, n = S().Cost("blind")
		isNil(m)
		eq(n, 1)
		contains(S().DebugLines(), "blind: 1 Hz, 1 ticks, ? ms median, ? ms max")
	end)

	it("marks the ticks bound to combat in the report", function()
		S().Start("threat", 5, function() end, { combat = true })
		matches(S().DebugLines()[1], "^threat: 5 Hz %(combat%)")
	end)
end)

describe("performance (ARC-06)", function()
	it("a tick allocates nothing", function()
		local run
		local newTicker = C_Timer.NewTicker
		C_Timer.NewTicker = function(seconds, fn)
			run = fn
			return newTicker(seconds, fn)
		end
		local n = 0
		S().Start("test", 10, function() n = n + 1 end)
		run()   -- warm up
		collectgarbage("collect")
		collectgarbage("stop")
		local before = collectgarbage("count")
		for _ = 1, 2000 do run() end
		local grown = collectgarbage("count") - before
		collectgarbage("restart")
		truthy(grown < 1, "grew by " .. grown .. " KB")
		eq(n, 2001)
	end)
end)
