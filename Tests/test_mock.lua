-- Adapted from Azeroth Accord (Tests/test_mock.lua), same owner, GPL-3.0 (ADR 0012).
-- The harness and the general parts of the mock client (clock, timers, frames, events, errors, saved data): they pin
-- the behaviour later tests rely on. The game parts (units, threat, secrets, fights) are in test_mock_game.lua.

describe("the game environment", function()
	it("is Lua 5.1 with the client's helpers", function()
		isNil(_G.require, "the game has no require")
		isNil(_G.io, "nor io")
		eq(strtrim("  a  "), "a")
		deepEq({ strsplit("-", "a-b-c") }, { "a", "b", "c" })
		local t = { 1, 2 }
		wipe(t)
		eq(#t, 0)
	end)

	it("is fresh for each test (1)", function() LEFTOVER = true truthy(LEFTOVER) end)
	it("is fresh for each test (2)", function() isNil(LEFTOVER) end)

	it("can take an API away before the addon loads", function()
		boot(function(M)
			M.Remove("UnitThreatSituation")
			M.Remove("C_Secrets.ShouldUnitThreatValuesBeSecret")
		end)
		isNil(UnitThreatSituation)
		isNil(C_Secrets.ShouldUnitThreatValuesBeSecret)
		notNil(C_Secrets.ShouldUnitThreatStateBeSecret)
		raises(function() Mock.Remove("C_Nothing.AtAll") end, "nothing at")
	end)
end)

describe("clock and timers", function()
	it("time moves only through Mock.Advance", function()
		local t0, s0 = GetTime(), GetServerTime()
		eq(GetTime(), t0)
		Mock.Advance(2.5)
		near(GetTime() - t0, 2.5, 1e-6)
		eq(GetServerTime() - s0, 2)
		near(debugprofilestop(), GetTime() * 1000, 1e-6)
	end)

	it("date and time are UTC and follow the fake epoch", function()
		eq(date("%Y-%m-%d %H:%M:%S", GetServerTime()), "2026-01-01 00:00:00")
		eq(time({ year = 2026, month = 1, day = 2, hour = 0 }), GetServerTime() + 86400)
		eq(time(), GetServerTime())
	end)

	it("C_Timer.After fires once, in order, after its delay", function()
		local log = {}
		C_Timer.After(2, function() log[#log + 1] = "b" end)
		C_Timer.After(1, function() log[#log + 1] = "a" end)
		Mock.Advance(0.5)
		deepEq(log, {})
		Mock.Advance(1)
		deepEq(log, { "a" })
		Mock.Advance(5)
		deepEq(log, { "a", "b" })
	end)

	it("a ticker repeats, stops after its iterations and can be cancelled", function()
		local n, m = 0, 0
		C_Timer.NewTicker(1, function() n = n + 1 end, 3)
		local ticker = C_Timer.NewTicker(1, function() m = m + 1 end)
		Mock.Advance(10)
		eq(n, 3)
		eq(m, 10)
		ticker:Cancel()
		Mock.Advance(5)
		eq(m, 10)
		truthy(ticker:IsCancelled())
		eq(Mock.PendingTimers(), 0)
	end)

	it("a timer created inside a callback waits for a later frame", function()
		local log = {}
		C_Timer.After(0, function()
			log[#log + 1] = "outer"
			C_Timer.After(0, function() log[#log + 1] = "inner" end)
		end)
		Mock.Advance(0.1)
		deepEq(log, { "outer" })
		Mock.Advance(0.1)
		deepEq(log, { "outer", "inner" })
	end)

	it("runs OnUpdate of visible frames with the elapsed time", function()
		local total, frames = 0, 0
		local f = CreateFrame("Frame")
		f:SetScript("OnUpdate", function(_, elapsed) total = total + elapsed; frames = frames + 1 end)
		Mock.Advance(1)
		near(total, 1, 1e-6)
		eq(frames, 10)
		f:Hide()
		Mock.Advance(1)
		eq(frames, 10)
	end)
end)

describe("frames and events", function()
	it("delivers events to registered frames only", function()
		local got = {}
		local a, b = CreateFrame("Frame"), CreateFrame("Frame")
		a:RegisterEvent("UNIT_TARGET")
		a:SetScript("OnEvent", function(_, event, ...) got[#got + 1] = { event, ... } end)
		b:SetScript("OnEvent", function() got[#got + 1] = "b" end)
		Mock.Fire("UNIT_TARGET", "party1")
		deepEq(got, { { "UNIT_TARGET", "party1" } })
		a:UnregisterEvent("UNIT_TARGET")
		Mock.Fire("UNIT_TARGET", "party1")
		eq(#got, 1)
	end)

	it("RegisterUnitEvent delivers only its units", function()
		local got = {}
		local f = CreateFrame("Frame")
		f:RegisterUnitEvent("UNIT_THREAT_LIST_UPDATE", "target", "focus")
		f:SetScript("OnEvent", function(_, _, unit) got[#got + 1] = unit end)
		Mock.Fire("UNIT_THREAT_LIST_UPDATE", "nameplate1")
		Mock.Fire("UNIT_THREAT_LIST_UPDATE", "target")
		Mock.Fire("UNIT_THREAT_LIST_UPDATE", Mock.Secret("string"))
		deepEq(got, { "target" })
		f:RegisterEvent("UNIT_THREAT_LIST_UPDATE")
		Mock.Fire("UNIT_THREAT_LIST_UPDATE", "nameplate1")
		eq(#got, 2)
	end)

	it("rejects event names the Forever client does not have (when the API dump is present)", function()
		if not Mock.validEvents then T.log("skipped: no API dump") return end
		raises(function() CreateFrame("Frame"):RegisterEvent("NOT_A_REAL_EVENT") end, "unknown event")
		raises(function() Mock.Fire("NOT_A_REAL_EVENT") end, "not an event")
	end)

	it("catches errors in handlers like the client does and reports them to the test", function()
		local f = CreateFrame("Frame")
		f:RegisterEvent("PLAYER_LOGIN")
		f:SetScript("OnEvent", function() error("boom") end)
		Mock.Fire("PLAYER_LOGIN")
		eq(#Mock.errors, 1)
		contains(Mock.errors[1].message, "boom")
		Mock.ClearErrors()
	end)

	it("Show and Hide run OnShow and OnHide; visibility follows the parent", function()
		local log = {}
		local parent = CreateFrame("Frame")
		local child = CreateFrame("Frame", nil, parent)
		child:SetScript("OnHide", function() log[#log + 1] = "hide" end)
		truthy(child:IsVisible())
		parent:Hide()
		falsy(child:IsVisible())
		truthy(child:IsShown())
		child:Hide()
		deepEq(log, { "hide" })
	end)

	it("an unknown widget method is nil, so calling it fails loudly", function()
		raises(function() CreateFrame("Frame"):NoSuchMethod() end, "NoSuchMethod")
	end)

	it("slash commands reach the handler registered for them", function()
		local got
		SlashCmdList.TEST, SLASH_TEST1 = function(rest) got = rest end, "/atwtest"
		truthy(Mock.Slash("/ATWtest one two"))
		eq(got, "one two")
		falsy(Mock.Slash("/nothing"))
	end)

	it("print and the chat frame write to Mock.output without colour codes in PlainOutput", function()
		print("|cff00ff00green|r", 1)
		DEFAULT_CHAT_FRAME:AddMessage("second")
		eq(Mock.PlainOutput(), "green 1\nsecond")
		Mock.ClearOutput()
		eq(#Mock.output, 0)
	end)
end)

describe("the saved data of a /reload", function()
	it("keeps numbers, strings, booleans, nested tables and odd keys", function()
		AzerothThreatwardenDB = { n = 0.1, big = 1234567890123, s = "a\0b\n\"c\" è", b = false,
			list = { 1, 2, { 3 } }, [7] = "seven", [true] = "yes" }
		local copy = AzerothThreatwardenDB
		Mock.Reload()
		deepEq(AzerothThreatwardenDB, copy)
	end)

	it("refuses what the client cannot save", function()
		local bad = {
			{ function() end, "function" },
			{ 0 / 0, "finite" },
			{ math.huge, "finite" },
			{ Mock.Secret("number"), "secret value" },
		}
		for _, case in ipairs(bad) do
			AzerothThreatwardenDB = { value = case[1] }
			raises(function() Mock.Reload() end, case[2])
		end
		local loop = {}
		loop.loop = loop
		AzerothThreatwardenDB = loop
		raises(function() Mock.Reload() end, "circular")
		AzerothThreatwardenDB = nil
	end)

	it("does not save globals the TOC does not declare", function()
		SomethingElse = { 1 }
		AzerothThreatwardenCharDB = { kept = true }
		Mock.Reload()
		isNil(SomethingElse)
		isNil(AzerothThreatwardenDB)
		truthy(AzerothThreatwardenCharDB.kept)
	end)

	it("keeps the world: clock, player, errors", function()
		Mock.Advance(5)
		local t = GetTime()
		Mock.player.level = 42
		Mock.Reload()
		eq(GetTime(), t)
		eq(Mock.player.level, 42)
	end)

	it("a new world is refused while an error is pending, so none gets lost", function()
		C_Timer.After(0, function() error("pending") end)
		Mock.Advance(0.2)
		raises(function() boot() end, "pending")
		Mock.ClearErrors()
	end)

	it("a second world starts empty", function()
		Mock.player.level = 42
		boot()
		eq(Mock.player.level, 60)
	end)
end)
