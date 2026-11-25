-- Adapted from Azeroth Accord (Tests/test_features.lua), same owner, GPL-3.0 (ADR 0012).
-- The feature switches (Core/Features.lua, SPEC-01 §3.4, ADR 0014): in the shipped code every part of a later milestone
-- is off, and a part that is off registers no game event, prints nothing and writes no data. The release step that turns
-- a switch on changes this file with it.

local function A() return AzerothThreatwarden end

-- SPEC-01 §3.4: the switches of v0.1.0.
local SWITCHES = { "alerts", "analytics", "coach", "export", "heatmap", "monitor", "multitarget", "profiles",
	"recording", "replay", "reports", "timeline" }

local function switchNames()
	local names = {}
	for key, value in pairs(A().Features) do
		if type(value) ~= "function" then names[#names + 1] = key end
	end
	table.sort(names)
	return names
end

describe("the feature switches in the shipped code", function()
	it("are exactly those of SPEC-01 §3.4", function()
		deepEq(switchNames(), SWITCHES)
	end)

	it("are all off", function()
		for _, name in ipairs(switchNames()) do
			eq(A().Features[name], false, name)
			eq(A().Features.On(name), false, name)
		end
	end)

	it("are written as false in the source, one per line", function()
		local source = Mock.ReadSource("AzerothThreatwarden/Core/Features.lua")
		local body = source:match("local Features = (%b{})")
		notNil(body)
		local found = 0
		for name, value in body:gmatch("([%a_]+)%s*=%s*(%a+)") do
			eq(value, "false", name)
			found = found + 1
		end
		eq(found, #SWITCHES)
		falsy(source:find("Features%.[%a_]+%s*=%s*true"), "no switch is turned on after the table")
	end)

	it("answer false for a name without a switch", function()
		eq(A().Features.On("unknown"), false)
		eq(A().Features.On(nil), false)
		eq(A().Features.On("On"), false)
	end)
end)

describe("a part that is switched off", function()
	local GAME_EVENTS = { "UNIT_THREAT_LIST_UPDATE", "UNIT_THREAT_SITUATION_UPDATE", "PLAYER_TARGET_CHANGED",
		"UNIT_TARGET", "GROUP_ROSTER_UPDATE", "ENCOUNTER_START", "ENCOUNTER_END" }

	it("registers none of the game events of the later parts (SPEC-01 §8.2)", function()
		for _, event in ipairs(GAME_EVENTS) do eq(Mock.Listeners(event), 0, event) end
		truthy(Mock.Listeners("PLAYER_REGEN_DISABLED") > 0, "the events of M1 are registered")
	end)

	it("reads no threat, prints nothing and writes nothing during a fight", function()
		local pull = Fight.new{ party = { { key = "tank", role = "TANK" } },
			mobs = { { key = "boss", tokens = { "target" } } } }
		pull:at(0):start():threat("boss", "tank", 1000)
		pull:at(2):threat("boss", "player", 900)
		pull:at(5):stop()
		pull:finish()
		for _, name in ipairs({ "UnitDetailedThreatSituation", "UnitThreatSituation", "UnitThreatPercentageOfLead",
			"UnitThreatLeadSituation" }) do
			isNil(Mock.threat.calls[name], name)
		end
		eq(#Mock.output, 0)
		isNil(AzerothThreatwardenDB)
		eq(Mock.PendingTimers(), 0)
	end)
end)

describe("a test that turns a switch on", function()
	before_boot(function(M) M.features = { monitor = true } end)

	it("has it from before ADDON_LOADED, through a /reload too", function()
		eq(A().Features.On("monitor"), true)
		eq(A().Features.On("alerts"), false)
		Mock.Reload()
		eq(A().Features.On("monitor"), true)
	end)
end)

describe("the next test", function()
	it("gets the shipped switches again", function()
		eq(A().Features.On("monitor"), false)
	end)
end)
