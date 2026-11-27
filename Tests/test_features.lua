-- Adapted from Azeroth Accord (Tests/test_features.lua), same owner, GPL-3.0 (ADR 0012).
-- The feature switches (Core/Features.lua, SPEC-01 §3.4, ADR 0014): in the shipped code the parts of the released
-- milestones are on and every part of a later milestone is off; a part that is off registers no game event, prints
-- nothing and writes no data. The release step that turns
-- a switch on changes this file with it.

local function A() return AzerothThreatwarden end

-- SPEC-01 §3.4: the switches, and those on in this version (M2.R: the threat monitor; M3.R: alerts
-- and Coach; M4.R: recording and report; M5.R: timeline and replay;
-- M6.R: analytics and export; M7.R: multi-target).
local SWITCHES = { "alerts", "analytics", "coach", "export", "heatmap", "monitor", "multitarget", "profiles",
	"recording", "replay", "reports", "timeline" }
local SHIPPED_ON = { alerts = true, analytics = true, coach = true, export = true, monitor = true, multitarget = true,
	recording = true, reports = true, replay = true, timeline = true }

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

	it("are on for the released parts only", function()
		for _, name in ipairs(switchNames()) do
			local on = SHIPPED_ON[name] == true
			eq(A().Features[name], on, name)
			eq(A().Features.On(name), on, name)
		end
	end)

	it("are written as false in the source, one per line", function()
		local source = Mock.ReadSource("AzerothThreatwarden/Core/Features.lua")
		local body = source:match("local Features = (%b{})")
		notNil(body)
		local found = 0
		for name, value in body:gmatch("([%a_]+)%s*=%s*(%a+)") do
			eq(value, tostring(SHIPPED_ON[name] == true), name)
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

	before_boot(function(M)
		M.features = { monitor = false, alerts = false, coach = false, recording = false, reports = false,
			timeline = false, replay = false, analytics = false, export = false, multitarget = false }
	end)

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
		deepEq(AzerothThreatwardenDB, Mock.ns.Config.defaults.account, "only the defaults Config writes at load")
		deepEq(AzerothThreatwardenCharDB, Mock.ns.Config.defaults.char)
		eq(Mock.PendingTimers(), 0)
	end)
end)

describe("the shipped code", function()
	it("runs the monitor, the alerts, the Coach and the recording of fights", function()
		truthy(Mock.Listeners("PLAYER_TARGET_CHANGED") > 0, "the monitor is on")
		truthy(Mock.Listeners("GROUP_ROSTER_UPDATE") > 0, "the monitor is on")
		for _, event in ipairs({ "ENCOUNTER_START", "ENCOUNTER_END", "PLAYER_LOGOUT" }) do
			truthy(Mock.Listeners(event) > 0, "recording is on: " .. event)
		end
	end)
end)

describe("a test that changes a switch", function()
	before_boot(function(M) M.features = { monitor = false, alerts = false } end)

	it("has it from before ADDON_LOADED, through a /reload too", function()
		eq(A().Features.On("monitor"), false)
		eq(A().Features.On("alerts"), false)
		Mock.Reload()
		eq(A().Features.On("monitor"), false)
		eq(A().Features.On("alerts"), false)
	end)
end)

describe("the next test", function()
	it("gets the shipped switches again", function()
		eq(A().Features.On("monitor"), true)
		eq(A().Features.On("alerts"), true)
	end)
end)
