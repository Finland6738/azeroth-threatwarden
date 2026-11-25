-- The game parts of the mock client: units and groups (50_units.lua), combat (60_combat.lua), the threat API
-- (70_threat.lua) and secret values (05_secrets.lua). They pin the answers later tests build on (SPEC-01 §8.3,
-- SPEC-08 §2 QA-03); the numbers the mock computes are assumptions until the M0 probe (see 70_threat.lua).

-- A party of two others and one mob on the player's target and a nameplate.
local function party(M)
	M.units.Add("tank", { class = "WARRIOR", role = "TANK" })
	M.units.Add("healer", { class = "PRIEST", role = "HEALER" })
	M.units.Add("boss", { hostile = true, classification = "worldboss", npcID = 4242 })
	M.group.Set{ members = { "tank", "healer" } }
	M.units.SetToken("target", "boss")
	M.units.SetToken("nameplate3", "boss")
end

local function record(events)
	local got = {}
	local f = CreateFrame("Frame")
	for _, event in ipairs(events) do f:RegisterEvent(event) end
	f:SetScript("OnEvent", function(_, event, arg) got[#got + 1] = event .. (arg and (" " .. tostring(arg)) or "") end)
	return got
end

describe("units and groups", function()
	before_boot(party)

	it("resolves party, raid, target and compound tokens", function()
		truthy(UnitExists("player"))
		truthy(UnitExists("party1"))
		truthy(UnitExists("target"))
		falsy(UnitExists("party3"))
		falsy(UnitExists("raid1"))
		falsy(UnitExists(nil))
		eq(UnitName("party1"), "Tank")
		eq(UnitGUID("target"), UnitGUID("nameplate3"))
		matches(UnitGUID("target"), "^Creature%-0%-1%-0%-1%-4242%-")
		matches(UnitGUID("party1"), "^Player%-")
		isNil(UnitGUID("party4"))
		isNil(UnitName("focus"))
		Mock.units.Target("boss", "tank")
		truthy(UnitIsUnit("targettarget", "party1"))
		truthy(UnitIsUnit("nameplate3target", "party1"))
		falsy(UnitIsUnit("targettarget", "player"))
		eq(UnitTokenFromGUID(UnitGUID("nameplate3")), "target")
	end)

	it("answers class, role, classification and hostility", function()
		deepEq({ UnitClass("party2") }, { "Priest", "PRIEST", 5 })
		eq(UnitGroupRolesAssigned("party1"), "TANK")
		eq(UnitGroupRolesAssigned("player"), "NONE")
		eq(UnitClassification("target"), "worldboss")
		truthy(UnitCanAttack("player", "target"))
		falsy(UnitCanAttack("player", "party1"))
		truthy(UnitIsPlayer("party1"))
		falsy(UnitIsPlayer("target"))
		falsy(UnitIsDead("target"))
	end)

	it("counts the group, as a party and as a raid", function()
		truthy(IsInGroup())
		falsy(IsInRaid())
		eq(GetNumGroupMembers(), 3)
		Mock.group.Set{ raid = true, members = { "tank", "healer" } }
		truthy(IsInRaid())
		truthy(UnitIsUnit("raid3", "player"))
		eq(UnitName("raid2"), "Healer")
		isNil(UnitName("party1"))
		Mock.group.Leave()
		falsy(IsInGroup())
		eq(GetNumGroupMembers(), 0)
	end)

	it("fires the target and nameplate events", function()
		local got = record({ "PLAYER_TARGET_CHANGED", "UNIT_TARGET", "NAME_PLATE_UNIT_ADDED",
			"NAME_PLATE_UNIT_REMOVED", "GROUP_ROSTER_UPDATE" })
		Mock.units.Target("tank", "boss")
		Mock.units.SetToken("target", nil)
		Mock.units.SetToken("nameplate3", nil)
		Mock.units.SetToken("nameplate1", "boss")
		deepEq(got, { "UNIT_TARGET party1", "PLAYER_TARGET_CHANGED", "UNIT_TARGET player",
			"NAME_PLATE_UNIT_REMOVED nameplate3", "NAME_PLATE_UNIT_ADDED nameplate1" })
		isNil(UnitName("target"))
	end)

	it("keeps units and group through a /reload", function()
		Mock.Reload()
		eq(UnitName("party1"), "Tank")
		eq(GetNumGroupMembers(), 3)
		truthy(UnitExists("nameplate3"))
	end)
end)

describe("combat, restrictions and instances", function()
	before_boot(party)

	it("enters and leaves combat with the client's events", function()
		local got = record({ "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" })
		falsy(InCombatLockdown())
		Mock.combat.Enter("tank")
		truthy(C_RestrictedActions.InCombatLockdown())
		truthy(UnitAffectingCombat("party1"))
		falsy(UnitAffectingCombat("party2"))
		Mock.combat.Leave()
		falsy(UnitAffectingCombat("player"))
		deepEq(got, { "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" })
	end)

	it("reports restrictions, encounters and instances", function()
		local got = record({ "ADDON_RESTRICTION_STATE_CHANGED", "ENCOUNTER_START", "ENCOUNTER_END" })
		local kind = Enum.AddOnRestrictionType.Encounter
		falsy(C_RestrictedActions.IsAddOnRestrictionActive(kind))
		Mock.combat.SetRestriction("Encounter", true)
		truthy(C_RestrictedActions.IsAddOnRestrictionActive(kind))
		Mock.combat.StartEncounter(101)
		Mock.combat.EndEncounter(true)
		eq(#got, 3)
		deepEq({ IsInInstance() }, { false, "none" })
		Mock.instance.Set{ type = "raid", difficultyID = 3, maxPlayers = 40, id = 409 }
		deepEq({ IsInInstance() }, { true, "raid" })
		local _, kindOfInstance, difficulty, _, maxPlayers, _, _, id = GetInstanceInfo()
		deepEq({ kindOfInstance, difficulty, maxPlayers, id }, { "raid", 3, 40, 409 })
	end)
end)

describe("the threat API", function()
	before_boot(party)

	it("answers nil for a unit that is not on the list, and for a unit that does not exist", function()
		isNil(UnitDetailedThreatSituation("player", "target"))
		isNil(UnitThreatSituation("player", "target"))
		isNil(UnitThreatSituation("player"))
		isNil(UnitThreatPercentageOfLead("player", "target"))
		isNil(UnitThreatLeadSituation("player", "target"))
		Mock.threat.Set("boss", "tank", 100)
		isNil(UnitDetailedThreatSituation("party4", "target"))
		isNil(UnitDetailedThreatSituation("party1", "focus"))
	end)

	it("computes the tank and the others from the scripted raw threat", function()
		Mock.threat.Set("boss", "tank", 1000)
		Mock.threat.Set("boss", "player", 550)
		deepEq({ UnitDetailedThreatSituation("party1", "target") }, { true, 3, 100, 100, 1000 })
		local isTanking, status, scaled, rawPct, raw = UnitDetailedThreatSituation("player", "target")
		deepEq({ isTanking, status, raw }, { false, 0, 550 })
		near(rawPct, 55, 1e-9)
		near(scaled, 50, 1e-9)
		near(UnitThreatPercentageOfLead("party1", "target"), 1000 / 550 * 100, 1e-9)
		eq(UnitThreatLeadSituation("player", "target"), 3)
		eq(UnitThreatLeadSituation("party1", "target"), 0)
		eq(UnitThreatSituation("player"), 0)
	end)

	it("gives a ranged unit the 130 % line", function()
		Mock.player.ranged = true
		Mock.threat.Set("boss", "tank", 1000)
		Mock.threat.Set("boss", "player", 650)
		near(select(3, UnitDetailedThreatSituation("player", "target")), 50, 1e-9)
	end)

	it("keeps the mob on its holder until a script moves it", function()
		Mock.threat.Set("boss", "tank", 1000)
		Mock.threat.Set("boss", "player", 1500)
		eq(Mock.threat.Holder("boss"), "tank")
		eq(UnitThreatSituation("player", "target"), 1)
		eq(UnitThreatSituation("party1", "target"), 2)
		Mock.threat.Aggro("boss", "player")
		eq(UnitThreatSituation("player", "target"), 3)
		eq(UnitThreatSituation("party1", "target"), 0)
		truthy(UnitIsUnit("targettarget", "player"))
		Mock.threat.Remove("boss", "player")
		eq(Mock.threat.Holder("boss"), "tank")
	end)

	it("fires the threat events with every token of the mob and of the unit", function()
		local got = record({ "UNIT_THREAT_LIST_UPDATE", "UNIT_THREAT_SITUATION_UPDATE" })
		Mock.threat.Set("boss", "tank", 1000)
		deepEq(got, { "UNIT_THREAT_LIST_UPDATE target", "UNIT_THREAT_LIST_UPDATE nameplate3",
			"UNIT_THREAT_SITUATION_UPDATE party1" })
		Mock.threat.Add("boss", "tank", 10)
		eq(#got, 5, "a new value without a new status: the list events only")
		Mock.threat.silent = true
		Mock.threat.Add("boss", "tank", 10)
		eq(#got, 5)
		eq(select(5, UnitDetailedThreatSituation("party1", "target")), 1020)
	end)

	it("can fix any value", function()
		Mock.threat.Set("boss", "tank", { raw = 10, status = 2, scaled = 87, lead = 120, leadStatus = 1, tanking = false })
		deepEq({ UnitDetailedThreatSituation("party1", "target") }, { false, 2, 87, 100, 10 })
		eq(UnitThreatPercentageOfLead("party1", "target"), 120)
		eq(UnitThreatLeadSituation("party1", "target"), 1)
	end)

	it("gives scripted answers: values, nil, nothing, an error, one call at a time", function()
		Mock.threat.Set("boss", "player", 100)
		local call = "UnitThreatSituation"
		Mock.threat.Answer(call, "player", "target", Mock.threat.Returns(2))
		eq(UnitThreatSituation("player", "target"), 2)
		eq(UnitThreatSituation("player", "nameplate3"), 3, "the answer is for one pair of tokens")
		Mock.threat.Answer(call, "*", "*", Mock.threat.NIL)
		eq(select("#", UnitThreatSituation("player", "nameplate3")), 1)
		Mock.threat.Queue(call, Mock.threat.NOTHING, Mock.threat.ERROR, Mock.threat.Error("restricted"))
		eq(select("#", UnitThreatSituation("player", "target")), 0)
		raises(function() UnitThreatSituation("player", "target") end, "mock error")
		raises(function() UnitThreatSituation("player", "target") end, "restricted")
		Mock.threat.ClearAnswers()
		eq(UnitThreatSituation("player", "target"), 3)
		eq(Mock.threat.calls[call], 7)
		raises(function() Mock.threat.Answer("UnitNothing", "player", "target", Mock.threat.NIL) end, "no function")
	end)

	it("refuses a call the client would refuse", function()
		raises(function() UnitDetailedThreatSituation("player") end, "Usage")
		raises(function() UnitThreatSituation(nil) end, "Usage")
		raises(function() UnitThreatSituation(Mock.Secret("string")) end, "Usage")
	end)

	it("answers the warning setting and the colours", function()
		truthy(IsThreatWarningEnabled())
		Mock.threat.SetWarning(false)
		falsy(IsThreatWarningEnabled())
		deepEq({ GetThreatStatusColor(3) }, { 1, 0, 0 })
	end)
end)

describe("secret values", function()
	before_boot(party)
	before_boot(function(M)
		M.threat.Set("boss", "tank", 1000)
		M.threat.Set("boss", "player", 500)
	end)

	it("are told apart by issecretvalue and canaccessvalue, and keep their type", function()
		local n, b = Mock.Secret("number"), Mock.Secret("boolean")
		truthy(issecretvalue(n))
		falsy(canaccessvalue(n))
		falsy(issecretvalue(5))
		truthy(canaccessvalue(nil))
		eq(type(n), "number")
		eq(type(b), "boolean")
		eq(type(5), "number")
		falsy(rawequal(n, Mock.Secret("number")))
	end)

	it("raise on any use of them", function()
		local s, other = Mock.Secret("number"), Mock.Secret("number")
		local uses = {
			function() return s + 1 end, function() return 1 - s end, function() return s * 2 end,
			function() return s / 2 end, function() return -s end, function() return s % 2 end,
			function() return s < other end, function() return s <= other end, function() return s == other end,
			function() return s .. "x" end, function() return tostring(s) end, function() return s.field end,
			function() s.field = 1 end, function() return s() end, function() return #s end,
		}
		for i, use in ipairs(uses) do raises(use, "secret value", "use " .. i) end
		raises(function() return string.format("%d", s) end)
		raises(function() print(s) end, "secret value")
		raises(function() return s < 1 end)
	end)

	it("are not there until a test asks for them", function()
		falsy(C_Secrets.HasSecretRestrictions())
		falsy(C_Secrets.ShouldUnitThreatValuesBeSecret("player", "target"))
		falsy(C_Secrets.ShouldUnitThreatStateBeSecret("player"))
		for _, v in ipairs({ UnitDetailedThreatSituation("player", "target") }) do falsy(issecretvalue(v)) end
	end)

	it("hide the values and leave the state readable", function()
		Mock.secrets.Set{ values = true }
		truthy(C_Secrets.HasSecretRestrictions())
		truthy(C_Secrets.ShouldUnitThreatValuesBeSecret("player", "target"))
		falsy(C_Secrets.ShouldUnitThreatStateBeSecret("player", "target"))
		local returns = { UnitDetailedThreatSituation("player", "target") }
		eq(#returns, 5)
		for i, v in ipairs(returns) do truthy(issecretvalue(v), "return " .. i) end
		truthy(issecretvalue(UnitThreatPercentageOfLead("party1", "target")))
		eq(UnitThreatSituation("player", "target"), 0)
		eq(UnitThreatLeadSituation("player", "target"), 3)
	end)

	it("hide the state too", function()
		Mock.secrets.Set{ state = true }
		truthy(C_Secrets.ShouldUnitThreatValuesBeSecret("player", "target"))
		truthy(C_Secrets.ShouldUnitThreatStateBeSecret("player"))
		truthy(issecretvalue(UnitThreatSituation("player", "target")))
		truthy(issecretvalue(UnitThreatLeadSituation("player", "target")))
		Mock.units.Add("stranger", {})
		Mock.units.SetToken("focus", "stranger")
		isNil(UnitThreatSituation("focus", "target"), "nil stays nil")
	end)

	it("can depend on the unit and the mob, and survive a /reload", function()
		Mock.secrets.Set{ values = function(unit) return unit ~= "player" end }
		falsy(issecretvalue((UnitDetailedThreatSituation("player", "target"))))
		truthy(issecretvalue((UnitDetailedThreatSituation("party1", "target"))))
		Mock.Reload()
		truthy(issecretvalue((UnitDetailedThreatSituation("party1", "target"))))
		Mock.secrets.Reset()
		falsy(issecretvalue((UnitDetailedThreatSituation("party1", "target"))))
	end)

	it("can come with a prediction that lies, and as a scripted answer", function()
		Mock.secrets.Set{ values = true, predictValues = false }
		falsy(C_Secrets.ShouldUnitThreatValuesBeSecret("player", "target"))
		truthy(issecretvalue((UnitDetailedThreatSituation("player", "target"))))
		Mock.secrets.Reset()
		Mock.threat.Queue("UnitThreatSituation", Mock.threat.SECRET)
		truthy(issecretvalue(UnitThreatSituation("player", "target")))
		falsy(issecretvalue(UnitThreatSituation("player", "target")))
		raises(function() Mock.secrets.Set{ everything = true } end, "unknown field")
	end)

	it("hide the identity of the others, not the player's", function()
		Mock.secrets.Set{ identity = true }
		truthy(C_Secrets.ShouldUnitIdentityBeSecret("party1"))
		truthy(issecretvalue(UnitGUID("party1")))
		truthy(issecretvalue((UnitName("target"))))
		truthy(issecretvalue((UnitClass("party2"))))
		falsy(issecretvalue(UnitGUID("player")))
		isNil(UnitGUID("party4"), "nil stays nil")
		Mock.secrets.Set{ comparison = true }
		truthy(issecretvalue(UnitIsUnit("targettarget", "player")))
		falsy(C_Secrets.CanCompareUnitTokens("targettarget", "player"))
	end)
end)
