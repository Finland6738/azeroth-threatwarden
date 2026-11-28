-- Core/Bus.lua (SPEC-01 §3, §3.3; ARC-03, ARC-06, ARC-10): order, duplicates, Off during an Emit, isolated errors,
-- secret arguments refused, no allocation while an event is delivered.

local function Bus() return Mock.ns.Bus end

describe("subscribing and emitting", function()
	it("calls the listeners in subscription order with the arguments, and counts those that ran", function()
		local seen = {}
		Bus().On("TEST_EVENT", function(a, b) seen[#seen + 1] = "one " .. a .. b end)
		Bus().On("TEST_EVENT", function(a, b) seen[#seen + 1] = "two " .. a .. b end)
		eq(Bus().Emit("TEST_EVENT", "x", "y"), 2)
		deepEq(seen, { "one xy", "two xy" })
		eq(Bus().ListenerCount("TEST_EVENT"), 2)
	end)

	it("registers the same function once per event", function()
		local n = 0
		local fn = function() n = n + 1 end
		truthy(Bus().On("TEST_EVENT", fn))
		falsy(Bus().On("TEST_EVENT", fn))
		Bus().Emit("TEST_EVENT")
		eq(n, 1)
	end)

	it("refuses a bad event name or listener", function()
		falsy(Bus().On(nil, function() end))
		falsy(Bus().On("TEST_EVENT", "not a function"))
		eq(Bus().Emit("NOBODY_LISTENS"), 0)
	end)

	it("removes one listener, or all of an event", function()
		local a, b = 0, 0
		local fa, fb = function() a = a + 1 end, function() b = b + 1 end
		Bus().On("TEST_EVENT", fa)
		Bus().On("TEST_EVENT", fb)
		truthy(Bus().Off("TEST_EVENT", fa))
		falsy(Bus().Off("TEST_EVENT", fa))
		Bus().Emit("TEST_EVENT")
		eq(a, 0)
		eq(b, 1)
		truthy(Bus().Off("TEST_EVENT"))
		eq(Bus().ListenerCount("TEST_EVENT"), 0)
		eq(Bus().Emit("TEST_EVENT"), 0)
	end)
end)

describe("changes while an event is delivered", function()
	it("a listener removed by an earlier one does not run, and the list is compacted afterwards", function()
		local ran = {}
		local second = function() ran[#ran + 1] = "second" end
		Bus().On("TEST_EVENT", function() ran[#ran + 1] = "first" Bus().Off("TEST_EVENT", second) end)
		Bus().On("TEST_EVENT", second)
		Bus().On("TEST_EVENT", function() ran[#ran + 1] = "third" end)
		eq(Bus().Emit("TEST_EVENT"), 2)
		deepEq(ran, { "first", "third" })
		eq(Bus().ListenerCount("TEST_EVENT"), 2)
		Bus().Emit("TEST_EVENT")
		deepEq(ran, { "first", "third", "first", "third" })
	end)

	it("a listener that removes itself runs once", function()
		local n = 0
		local fn
		fn = function() n = n + 1 Bus().Off("TEST_EVENT", fn) end
		Bus().On("TEST_EVENT", fn)
		Bus().Emit("TEST_EVENT")
		Bus().Emit("TEST_EVENT")
		eq(n, 1)
		eq(Bus().ListenerCount("TEST_EVENT"), 0)
	end)

	it("a listener added during an Emit runs from the next one", function()
		local ran = {}
		Bus().On("TEST_EVENT", function()
			ran[#ran + 1] = "first"
			Bus().On("TEST_EVENT", function() ran[#ran + 1] = "late" end)
		end)
		Bus().Emit("TEST_EVENT")
		deepEq(ran, { "first" })
		Bus().Emit("TEST_EVENT")
		deepEq(ran, { "first", "first", "late" })
	end)

	it("a nested Emit of the same event delivers to everyone still subscribed", function()
		local ran = {}
		Bus().On("TEST_EVENT", function(level)
			ran[#ran + 1] = "a" .. level
			if level == 1 then Bus().Emit("TEST_EVENT", 2) end
		end)
		Bus().On("TEST_EVENT", function(level) ran[#ran + 1] = "b" .. level end)
		Bus().Emit("TEST_EVENT", 1)
		deepEq(ran, { "a1", "a2", "b2", "b1" })
	end)
end)

describe("errors (ARC-10)", function()
	it("an error in one listener does not stop the others, never reaches the player and is kept", function()
		local after = false
		Bus().On("TEST_EVENT", function() error("listener boom") end)
		Bus().On("TEST_EVENT", function() after = true end)
		eq(Bus().Emit("TEST_EVENT"), 1)
		truthy(after)
		eq(#Mock.errors, 0, "not shown by the client's error handler")
		eq(Bus().errorCount, 1)
		contains(Bus().errors[1].message, "listener boom")
		eq(Bus().errors[1].event, "TEST_EVENT")
		contains(Mock.ns.Diagnostics.Errors()[1].text, "listener boom")
	end)

	it("keeps only the last errors", function()
		Bus().On("TEST_EVENT", function(i) error("boom " .. i) end)
		for i = 1, Bus().MAX_ERRORS + 5 do Bus().Emit("TEST_EVENT", i) end
		eq(#Bus().errors, Bus().MAX_ERRORS)
		eq(Bus().errorCount, Bus().MAX_ERRORS + 5)
		contains(Bus().errors[#Bus().errors].message, "boom " .. (Bus().MAX_ERRORS + 5))
	end)

	it("refuses an event whose argument is a secret value (SPEC-01 §3.3)", function()
		local ran = false
		Bus().On("TEST_EVENT", function() ran = true end)
		eq(Bus().Emit("TEST_EVENT", "unitKey", Mock.Secret("number")), 0)
		falsy(ran)
		contains(Bus().errors[1].message, "secret value")
	end)
end)

describe("the report and the lifecycle", function()
	it("lists the events with listeners and the errors", function()
		Bus().On("TEST_EVENT", function() error("x") end)
		Bus().Emit("TEST_EVENT")
		local lines = Bus().DebugLines()
		matches(lines[1], "^events with listeners: %d+, listener errors: 1$")
		contains(lines, "TEST_EVENT: 1 listener(s)")
		contains(lines, "COMBAT_ENDED: 14 listener(s)",
			"the Scheduler, TargetTracker, ThreatScanner, ThreatModel, the profiles, the other mobs, the alerts, the Coach, "
				.. "the strip, the raid frame overlay, the window, Storage, the recorder and the replay")
	end)

	it("carries COMBAT_STARTED and COMBAT_ENDED from Init", function()
		local seen = {}
		Bus().On("COMBAT_STARTED", function() seen[#seen + 1] = "start" end)
		Bus().On("COMBAT_ENDED", function() seen[#seen + 1] = "end" end)
		Mock.combat.Enter()
		Mock.combat.Leave()
		deepEq(seen, { "start", "end" })
	end)

	it("is the same table on the addon object", function()
		eq(AzerothThreatwarden.Bus, Bus())
	end)
end)

describe("performance (ARC-06)", function()
	it("delivers an event without allocating", function()
		local sum = 0
		Bus().On("TEST_EVENT", function(a, b) sum = sum + a + b end)
		Bus().On("TEST_EVENT", function(a) sum = sum + a end)
		Bus().Emit("TEST_EVENT", 1, 2)   -- warm up
		collectgarbage("collect")
		collectgarbage("stop")
		local before = collectgarbage("count")
		for _ = 1, 2000 do Bus().Emit("TEST_EVENT", 1, 2) end
		local grown = collectgarbage("count") - before
		collectgarbage("restart")
		truthy(grown < 1, "grew by " .. grown .. " KB")
		eq(sum, 4 * 2001)
	end)
end)
