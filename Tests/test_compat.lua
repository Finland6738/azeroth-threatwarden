-- Core/Compat.lua (SPEC-01 §2, §8; ARC-02, ARC-10, ARC-11, ARC-12; ADR 0003, DAT-02, DAT-03, DAT-10): the API table
-- and its four states in the mock client, the capabilities, the restrictions, the secret-value checks (a secret of the
-- mock raises on any use, so a test that passes never read one) and the normalized threat read of §8.3 with scripted
-- answers: values, state only, secret, nil, error, missing.

local function C() return Mock.ns.Compat end
local function api(id) return C().api[id] end

-- The ids of SPEC-01 §8.2, in its order: the table of Compat must be exactly this one.
local SPEC_IDS = {
	"client.GetBuildInfo", "client.GetLocale", "client.ProjectID", "client.RealmName", "secret.issecretvalue",
	"secret.issecrettable", "secret.canaccessvalue", "secret.HasSecretRestrictions", "secret.ThreatValues",
	"secret.ThreatState", "secret.Identity", "secret.Comparison", "threat.Detailed", "threat.Situation",
	"threat.PercentageOfLead", "threat.LeadSituation", "threat.StatusColor", "threat.WarningEnabled", "unit.Exists",
	"unit.GUID", "unit.TokenFromGUID", "unit.Name", "unit.Class", "unit.Classification", "unit.CanAttack",
	"unit.IsDead", "unit.IsUnit", "unit.AffectingCombat", "unit.Role", "group.InGroup", "group.InRaid", "group.Size",
	"group.RaidIndex",
	"instance.InInstance", "instance.Info", "restriction.InCombatLockdown", "restriction.IsActive",
	"restriction.Types", "combatlog.Restricted", "damagemeter.Available", "time.GetTime", "time.ServerTime",
	"time.After", "time.NewTicker", "time.NewTimer", "time.ProfileStop", "addon.Metadata", "addon.Memory",
	"addon.Framerate", "addon.ErrorHandler", "ui.Reload", "ui.CreateFrame", "ui.CreateFont", "ui.CreateColor",
	"ui.ScreenSize",
	"ui.SettingsPanel", "ui.SpecialFrames", "ui.SlashCmdList", "ui.ClassColor", "ui.PlaySound",
}

-- What the mock client does not imitate yet (Tests/mock headers): reported missing, never raised.
local NOT_MOCKED = { ["ui.ClassColor"] = true }

describe("the API table (SPEC-01 §8.2, ARC-02)", function()
	it("has every API of the specification, once, in its order", function()
		local ids = {}
		for i, entry in ipairs(C().APIS) do
			ids[i] = entry.id
			truthy(entry.check == "call" or entry.check == "exists" or entry.check == "read", entry.id)
			truthy(#entry.paths >= 1, entry.id)
			notNil(entry.since, entry.id)
			notNil(entry.probe, entry.id)
		end
		deepEq(ids, SPEC_IDS)
	end)

	it("is probed at ADDON_LOADED: available on the mock client, missing where the mock has nothing", function()
		truthy(C().probed)
		for _, id in ipairs(SPEC_IDS) do
			local state, detail = C().ApiState(id)
			eq(state, NOT_MOCKED[id] and "missing" or "available", id .. " " .. tostring(detail))
		end
		eq(#Mock.errors, 0)
	end)

	it("shows only plain values of the calls that are meant for the report", function()
		eq(api("client.GetLocale").value, "enUS")
		eq(api("secret.HasSecretRestrictions").value, "false")
		eq(api("instance.InInstance").value, "false")
		eq(api("restriction.InCombatLockdown").value, "false")
		isNil(api("unit.GUID").value, "the player's GUID is never kept")
		isNil(api("client.GetBuildInfo").value)
		eq(Mock.threat.calls.UnitDetailedThreatSituation, nil, "the threat functions are never called by Probe")
	end)

	it("says which alternative it found", function()
		boot(function(M) M.Remove("C_RestrictedActions.InCombatLockdown") end)
		eq(api("restriction.InCombatLockdown").state, "available")
		eq(api("restriction.InCombatLockdown").path, "InCombatLockdown")
		contains(C().ApiLines(), "restriction.InCombatLockdown: available = false [InCombatLockdown]")
	end)

	it("reports a missing API, and a capability that needs it, without an error (ARC-10)", function()
		boot(function(M)
			M.Remove("UnitDetailedThreatSituation")
			M.Remove("C_Secrets.ShouldUnitThreatValuesBeSecret")
			M.Remove("WOW_PROJECT_CAMELOT")
			M.Remove("UpdateAddOnMemoryUsage")
		end)
		eq(#Mock.errors, 0)
		eq(C().ApiState("threat.Detailed"), "missing")
		eq(C().ApiState("secret.ThreatValues"), "missing")
		eq(C().ApiState("client.ProjectID"), "missing")
		deepEq({ C().ApiState("addon.Memory") }, { "missing", "partly missing" })
		eq(C().Capability("threatValues"), "missing")
		eq(C().Capability("threatState"), "unknown")
		truthy(AzerothThreatwarden.isForever, "the interface number decides without the constants")
	end)

	it("reports a secret answer or a restriction error as restricted, any other error as error", function()
		boot(function(M)
			C_Secrets.HasSecretRestrictions = function() return M.Secret("boolean") end
			IsThreatWarningEnabled = function() error("Interface action blocked: restricted for addons") end
			GetLocale = function()
				error("C:\\Users\\Someone\\Games\\WoW\\_forever_\\Interface\\AddOns\\AzerothThreatwarden\\Core\\X.lua:3: boom", 0)
			end
			IsInGroup = "not a function"
		end)
		eq(#Mock.errors, 0)
		deepEq({ C().ApiState("secret.HasSecretRestrictions") }, { "restricted", "secret value" })
		eq(C().ApiState("threat.WarningEnabled"), "restricted")
		local state, detail = C().ApiState("client.GetLocale")
		eq(state, "error")
		eq(detail, "AzerothThreatwarden/Core/X.lua:3: boom", "cleaned of the folders")
		deepEq({ C().ApiState("group.InGroup") }, { "error", "not a function" })
		eq(C().ClientLocale(), "enUS", "the language falls back to English")
	end)

	it("answers nil for an id that is not in the table", function()
		isNil(C().ApiState("nothing.Here"))
	end)
end)

describe("resolving and calling", function()
	it("resolves nested paths and never raises", function()
		eq(C().Resolve("C_Secrets.HasSecretRestrictions"), C_Secrets.HasSecretRestrictions)
		isNil(C().Resolve("C_Nothing.Here"))
		isNil(C().Resolve("GetTime.field"))
		isNil(C().Resolve(""))
		isNil(C().Resolve(nil))
		C_Trap = setmetatable({}, { __index = function() error("trap") end })
		isNil(C().Resolve("C_Trap.Anything"))
	end)

	it("returns the state and every value, a secret value as nil", function()
		deepEq({ C().Call("GetBuildInfo") }, { "available", "1.60.1", "70170", "Oct  1 2026", 16001, "1.60.1", "Release" })
		eq((C().Call("Nothing")), "missing")
		C_Test = { Two = function() return Mock.Secret("number"), 5 end, Gap = function() return nil, 7 end }
		deepEq({ C().Call("C_Test.Two") }, { "restricted", nil, 5 })
		local _, a, b = C().Call("C_Test.Gap")
		isNil(a)
		eq(b, 7, "a value after a nil is kept")
	end)
end)

describe("secret values (ARC-11, DAT-03)", function()
	it("are told apart without being read", function()
		local secret = Mock.Secret("number")
		truthy(C().IsSecret(secret))
		truthy(C().IsSecret(Mock.Secret("table")))
		for _, plain in ipairs({ 0, "x", true, false, {} }) do falsy(C().IsSecret(plain), tostring(plain)) end
		falsy(C().IsSecret(nil))
		isNil(C().Readable(secret))
		eq(C().Readable(12), 12)
	end)

	it("are nothing on a client without the checks", function()
		boot(function(M)
			M.Remove("issecretvalue")
			M.Remove("canaccessvalue")
			M.Remove("issecrettable")
		end)
		falsy(C().IsSecret(5))
		eq(#Mock.errors, 0)
		eq(C().ApiState("secret.issecretvalue"), "missing")
	end)

	it("use canaccessvalue and issecrettable when issecretvalue does not tell", function()
		local hidden = {}
		issecretvalue = function() return false end
		canaccessvalue = function(v) return v ~= hidden end
		truthy(C().IsSecret(hidden))
		canaccessvalue = nil
		issecrettable = function(t) return t == hidden end
		truthy(C().IsSecret(hidden))
		falsy(C().IsSecret({}))
	end)
end)

describe("capabilities (SPEC-01 §8.4, ARC-12)", function()
	it("start unknown until a reading proves them; the combat log is missing, as expected", function()
		for _, id in ipairs({ "threatValues", "threatState", "threatLead", "threatEvents", "groupThreat", "otherMobs",
			"mobIdentity", "damageMeter" }) do
			eq(C().Capability(id), "unknown", id)
		end
		eq(C().Capability("roles"), "available", "proven at login: the monitor reads the player's role")
		deepEq({ C().Capability("combatLog") }, { "missing", "CombatLogGetCurrentEventInfo missing" })
	end)

	it("follow what the damage meter says", function()
		boot(function(M) M.world.combat.damageMeter = false end)
		deepEq({ C().Capability("damageMeter") }, { "missing", "Unavailable" })
		boot(function(M) M.Remove("C_DamageMeter.IsDamageMeterAvailable") end)
		eq(C().Capability("damageMeter"), "missing")
	end)

	it("change through SetCapability, which emits CAPABILITY_CHANGED once per change", function()
		local seen = {}
		Mock.ns.Bus.On("CAPABILITY_CHANGED", function(id, state) seen[#seen + 1] = id .. "=" .. state end)
		truthy(C():SetCapability("threatValues", "available"))
		falsy(C():SetCapability("threatValues", "available"))
		truthy(C():SetCapability("threatValues", "restricted", "secret in instance"))
		deepEq(seen, { "threatValues=available", "threatValues=restricted" })
		deepEq({ C().Capability("threatValues") }, { "restricted", "secret in instance" })
	end)

	it("refuse a bad state and drop a secret detail", function()
		falsy(C():SetCapability("threatValues", "maybe"))
		falsy(C():SetCapability(Mock.Secret("string"), "available"))
		truthy(C():SetCapability("threatState", "available", Mock.Secret("string")))
		deepEq({ C().Capability("threatState") }, { "available", nil })
		eq(C().Capability("neverSet"), "unknown")
	end)
end)

describe("client restrictions [probe P11]", function()
	it("are read from the client's enumeration, one capability per type", function()
		local names = {}
		for _, t in ipairs(C().restrictionTypes) do names[#names + 1] = t.name end
		deepEq(names, { "Combat", "Encounter", "ChallengeMode", "PvPMatch", "Map" })
		eq(C().Capability("restricted.Encounter"), "available")
		deepEq(C().ActiveRestrictions(), {})
	end)

	it("start restricted when the client says so at login", function()
		boot(function(M) M.combat.SetRestriction("Encounter", true) end)
		eq(C().Capability("restricted.Encounter"), "restricted")
		deepEq(C().ActiveRestrictions(), { "Encounter" })
	end)

	it("follow ADDON_RESTRICTION_STATE_CHANGED and say so on the Bus", function()
		local seen = {}
		Mock.ns.Bus.On("CAPABILITY_CHANGED", function(id, state) seen[#seen + 1] = id .. "=" .. state end)
		Mock.combat.SetRestriction("Combat", true)
		deepEq(C().ActiveRestrictions(), { "Combat" })
		Mock.combat.SetRestriction("Combat", false)
		deepEq(seen, { "restricted.Combat=restricted", "restricted.Combat=available" })
		contains(C().RestrictionLines(), "active: none")
	end)

	it("take an unknown type by its number, and ignore a payload that is not one", function()
		Enum.AddOnRestrictionType.Future = 9
		Mock.Fire("ADDON_RESTRICTION_STATE_CHANGED", 9, 2)
		eq(C().Capability("restricted.9"), "available")
		falsy(C():OnRestrictionChanged(Mock.Secret("number")))
		falsy(C():OnRestrictionChanged("Combat"))
		eq(#Mock.errors, 0)
	end)

	it("are unknown on a client without the enumeration", function()
		boot(function() Enum.AddOnRestrictionType = nil end)
		eq(#C().restrictionTypes, 0)
		eq(C().ApiState("restriction.Types"), "missing")
		contains(C().RestrictionLines(), "restriction types: unknown (Enum.AddOnRestrictionType missing)")
	end)
end)

describe("client and addon facts", function()
	it("give the build, the language, the version, the memory and the clocks", function()
		local info = C().BuildInfo()
		eq(info.version, "1.60.1")
		eq(info.interface, 16001)
		eq(info.projectID, WOW_PROJECT_CAMELOT)
		truthy(info.isForever)
		eq(C().ClientLocale(), "enUS")
		eq(C().AddonVersion(), "@project-version@")
		eq(C().AddonMemoryKB(), 2048.25)
		eq(C().Framerate(), 60)
		eq(C().Now(), GetTime())
		eq(C().ProfileMs(), debugprofilestop())
		eq(C().InstanceType(), "none")
		eq(C().PlayerName(), "Testchar")
		eq(C().RealmName(), "Test Realm")
	end)

	it("answer nil, never an error, when the client cannot say", function()
		boot(function(M)
			M.player.addonMemory = false
			M.Remove("GetTime")
			M.Remove("debugprofilestop")
			M.Remove("C_Timer.NewTicker")
			M.Remove("GetFramerate")
		end)
		isNil(C().AddonMemoryKB())
		eq(C().Now(), 0)
		isNil(C().ProfileMs())
		isNil(C().NewTicker(1, function() end))
		isNil(C().Framerate())
		eq(#Mock.errors, 0)
	end)

	it("add a frame to the ones Esc closes, once", function()
		truthy(C().CloseOnEscape("AzerothThreatwardenTestFrame"))
		truthy(C().CloseOnEscape("AzerothThreatwardenTestFrame"))
		local n = 0
		for _, name in ipairs(UISpecialFrames) do if name == "AzerothThreatwardenTestFrame" then n = n + 1 end end
		eq(n, 1)
		UISpecialFrames = nil
		falsy(C().CloseOnEscape("AzerothThreatwardenTestFrame"))
	end)
end)

describe("the sound of an alert (SPEC-04 §1.4, M3.2)", function()
	it("plays the kit through the game, with PlaySound or else C_Sound.PlaySound", function()
		deepEq({ C().PlaySound(8959) }, { true })
		eq(#Mock.sound.calls, 1)
		eq(Mock.sound.calls[1].kit, 8959)
		boot(function(M) M.Remove("PlaySound") end)
		truthy(C().PlaySound(12))
		eq(Mock.sound.calls[1].kit, 12)
		eq(api("ui.PlaySound").path, "C_Sound.PlaySound")
	end)

	it("answers false and why, never an error", function()
		deepEq({ C().PlaySound(nil) }, { false, "no-kit" })
		deepEq({ C().PlaySound(Mock.Secret("number")) }, { false, "no-kit" })
		Mock.sound.refuse = true
		deepEq({ C().PlaySound(1) }, { false, "refused" })
		Mock.sound.refuse, Mock.sound.fail = false, true
		deepEq({ C().PlaySound(1) }, { false, "error" })
		boot(function(M)
			M.Remove("PlaySound")
			M.Remove("C_Sound.PlaySound")
		end)
		deepEq({ C().PlaySound(1) }, { false, "missing" })
		eq(C().ApiState("ui.PlaySound"), "missing")
		eq(#Mock.errors, 0)
	end)
end)

-- The threat read (SPEC-01 §8.3) -----------------------------------------------------------------------------------
local function fight(M)
	M.units.Add("boss", { hostile = true, classification = "worldboss" })
	M.units.Add("mage", { class = "MAGE", ranged = true })
	M.units.SetToken("target", "boss")
	M.group.Set({ members = { "mage" } })
	M.threat.Set("boss", "player", 1000)
	M.threat.Set("boss", "mage", 650)
end

local function read(unit, mob, record)
	record = record or C().Threat.NewRecord()
	local mode = C().Threat.Read(unit or "player", mob or "target", record)
	return mode, record
end

local function calls(name) return Mock.threat.calls[name] or 0 end

-- No field of a record holds a secret (it would be saved by a recording, DAT-03).
local function noSecret(record)
	for key, value in pairs(record) do falsy(issecretvalue(value), "field " .. key .. " is a secret") end
end

describe("the threat read (SPEC-01 §8.3)", function()
	before_boot(fight)

	it("reads the values when nothing is secret", function()
		local mode, r = read()
		eq(mode, "values")
		eq(r.isTanking, true)
		eq(r.situation, 3)
		eq(r.scaledPercent, 100)
		eq(r.rawPercent, 100)
		eq(r.rawThreat, 1000)
		eq(r.source, "detected")
		isNil(r.reason)
		eq(r.observedAt, GetTime())
		mode, r = read("party1")
		eq(mode, "values")
		eq(r.isTanking, false)
		eq(r.situation, 0)
		near(r.rawPercent, 65)
		near(r.scaledPercent, 50, 1e-9, "65 % against the 130 % line [P2]")
	end)

	it("says nil, without a number, for a unit that is not on the list", function()
		Mock.units.Add("healer", {})
		Mock.units.SetToken("focus", "healer")
		local mode, r = read("focus")
		eq(mode, "none")
		eq(r.reason, "nil")
		eq(r.source, "unknown")
		isNil(r.situation)
		isNil(r.scaledPercent)
	end)

	it("reads only the state when the values are predicted secret", function()
		Mock.secrets.Set({ values = true })
		local mode, r = read()
		eq(mode, "state")
		eq(r.situation, 3)
		eq(r.reason, "secret")
		isNil(r.scaledPercent)
		isNil(r.rawThreat)
		isNil(r.isTanking)
		eq(calls("UnitDetailedThreatSituation"), 0, "not called")
		noSecret(r)
	end)

	it("calls nothing when the state is predicted secret", function()
		Mock.secrets.Set({ state = true })
		local mode, r = read()
		eq(mode, "none")
		eq(r.reason, "secret")
		eq(calls("UnitDetailedThreatSituation") + calls("UnitThreatSituation"), 0)
		noSecret(r)
	end)

	it("never touches a secret when a prediction lies (values)", function()
		Mock.secrets.Set({ values = true, predictValues = false })
		local mode, r = read()
		eq(mode, "state", "the state of the detailed answer is secret too, so the state function answers")
		eq(r.situation, 3)
		eq(r.reason, "secret")
		eq(calls("UnitDetailedThreatSituation"), 1)
		noSecret(r)
		eq(#Mock.errors, 0)
	end)

	it("never touches a secret when a prediction lies (state)", function()
		Mock.secrets.Set({ state = true, predictState = false, predictValues = false })
		local mode, r = read()
		eq(mode, "none")
		eq(r.reason, "secret")
		noSecret(r)
	end)

	it("keeps a readable status when only the numbers of the detailed answer are secret", function()
		Mock.threat.Answer("UnitDetailedThreatSituation", "*", "*",
			Mock.threat.Returns(true, 3, Mock.Secret("number"), Mock.Secret("number"), Mock.Secret("number")))
		local mode, r = read()
		eq(mode, "state")
		eq(r.situation, 3)
		eq(r.reason, "secret")
		isNil(r.isTanking)
		isNil(r.rawThreat)
		eq(calls("UnitThreatSituation"), 0)
	end)

	it("follows scripted answers: every value secret, nil, nothing, an error", function()
		Mock.threat.Queue("UnitDetailedThreatSituation", Mock.threat.SECRET, Mock.threat.NIL, Mock.threat.NOTHING,
			Mock.threat.ERROR)
		local mode, r = read()
		deepEq({ mode, r.reason, r.situation }, { "state", "secret", 3 })
		mode, r = read()
		deepEq({ mode, r.reason }, { "none", "nil" })
		mode, r = read()
		deepEq({ mode, r.reason }, { "none", "nil" })
		mode, r = read()
		deepEq({ mode, r.reason, r.situation }, { "state", "error", 3 }, "an error falls back to the state")
		eq(#Mock.errors, 0)
	end)

	it("falls back to the state when the detailed function is missing, and to none when both are", function()
		Mock.Remove("UnitDetailedThreatSituation")
		local mode, r = read()
		deepEq({ mode, r.reason, r.situation }, { "state", "missing", 3 })
		Mock.Remove("UnitThreatSituation")
		mode, r = read()
		deepEq({ mode, r.reason }, { "none", "missing" })
	end)

	it("says none when the state function fails too, gives no number or a secret", function()
		Mock.threat.Answer("UnitDetailedThreatSituation", "*", "*", Mock.threat.ERROR)
		Mock.threat.Queue("UnitThreatSituation", Mock.threat.ERROR, Mock.threat.Returns("three"),
			Mock.threat.Returns(Mock.Secret("number")))
		local mode, r = read()
		deepEq({ mode, r.reason }, { "none", "error" })
		mode, r = read()
		deepEq({ mode, r.reason }, { "none", "error" }, "the reason the values are missing")
		mode, r = read()
		deepEq({ mode, r.reason }, { "none", "secret" })
		noSecret(r)
	end)

	it("works without C_Secrets, checking only the values", function()
		Mock.Remove("C_Secrets")
		eq(read(), "values")
		Mock.secrets.Set({ values = true })
		local mode, r = read()
		deepEq({ mode, r.reason, r.situation }, { "state", "secret", 3 })
		noSecret(r)
	end)

	it("ignores a prediction that fails or is itself secret", function()
		C_Secrets.ShouldUnitThreatStateBeSecret = function() error("prediction failed") end
		C_Secrets.ShouldUnitThreatValuesBeSecret = function() return Mock.Secret("boolean") end
		eq(read(), "values")
		eq(#Mock.errors, 0)
	end)

	it("calls nothing for a unit that is not a plain token", function()
		local mode, r = read(Mock.Secret("string"))
		deepEq({ mode, r.reason }, { "none", "no-unit" })
		mode = C().Threat.Read("player", nil, r)
		deepEq({ mode, r.reason }, { "none", "no-unit" })
		mode = C().Threat.Read(42, "target", r)
		deepEq({ mode, r.reason }, { "none", "no-unit" })
		eq(calls("UnitDetailedThreatSituation") + calls("UnitThreatSituation"), 0)
	end)

	it("reuses the record, clearing what the last read left", function()
		local r = C().Threat.NewRecord()
		read("player", "target", r)
		eq(r.rawThreat, 1000)
		Mock.secrets.Set({ values = true })
		local mode, same = read("player", "target", r)
		eq(same, r)
		eq(mode, "state")
		isNil(r.rawThreat)
		isNil(r.scaledPercent)
	end)

	it("counts the reads for /atw debug", function()
		read()
		Mock.secrets.Set({ state = true })
		read()
		local s = C().Threat.stats
		eq(s.values, 1)
		eq(s.none, 1)
		eq(s.secret, 1)
		contains(C().CapabilityLines(),
			"threat reads: 1 values, 0 state, 1 none (secret 1, nil 0, error 0, missing 0)")
	end)

	it("reads without allocating (ARC-06)", function()
		C_Secrets.ShouldUnitThreatStateBeSecret = function() return false end
		C_Secrets.ShouldUnitThreatValuesBeSecret = function() return false end
		UnitDetailedThreatSituation = function() return true, 3, 100, 100, 5000 end
		local r = C().Threat.NewRecord()
		read("player", "target", r)
		collectgarbage("collect")
		collectgarbage("stop")
		local before = collectgarbage("count")
		for _ = 1, 2000 do C().Threat.Read("player", "target", r) end
		local grown = collectgarbage("count") - before
		collectgarbage("restart")
		truthy(grown < 1, "grew by " .. grown .. " KB")
		eq(r.rawThreat, 5000)
	end)
end)

describe("the lead of the holder (M2.2, SPEC-03 §2.2)", function()
	before_boot(fight)

	it("reads the percentage and the situation of the lead, and a Read clears them", function()
		local r = C().Threat.NewRecord()
		C().Threat.ReadLead("player", "target", r)
		near(r.leadPercent, 1000 / 650 * 100, 1e-9)
		eq(r.leadSituation, 0)
		isNil(r.leadReason)
		read("player", "target", r)
		isNil(r.leadPercent)
		isNil(r.leadSituation)
	end)

	it("keeps no secret: values secret leaves the situation, state secret leaves nothing", function()
		local r = C().Threat.NewRecord()
		Mock.secrets.Set{ values = true }
		local before = calls("UnitThreatPercentageOfLead")
		C().Threat.ReadLead("player", "target", r)
		eq(calls("UnitThreatPercentageOfLead"), before, "predicted secret: not asked")
		isNil(r.leadPercent)
		eq(r.leadSituation, 0)
		eq(r.leadReason, "secret")
		Mock.secrets.Set{ values = true, state = true }
		C().Threat.ReadLead("player", "target", r)
		isNil(r.leadSituation)
		eq(r.leadReason, "secret")
		noSecret(r)
	end)

	it("says missing, error or no-unit", function()
		local r = C().Threat.NewRecord()
		Mock.Remove("UnitThreatPercentageOfLead")
		C().Threat.ReadLead("player", "target", r)
		eq(r.leadReason, "missing")
		eq(r.leadSituation, 0)
		Mock.threat.Answer("UnitThreatLeadSituation", "*", "*", Mock.threat.ERROR)
		C().Threat.ReadLead("player", "target", r)
		eq(r.leadReason, "missing")
		isNil(r.leadSituation)
		C().Threat.ReadLead(Mock.Secret("string"), "target", r)
		eq(r.leadReason, "no-unit")
		eq(#Mock.errors, 0)
	end)
end)

describe("units and the group (M2.2)", function()
	before_boot(fight)

	it("answers existence, death, hostility, identity and role without keeping a secret", function()
		local U = C().Unit
		eq(U.Exists("target"), true)
		eq(U.Exists("party3"), false)
		eq(U.IsDead("target"), false)
		eq(U.CanAttack("player", "target"), true)
		eq(U.CanAttack("player", "party1"), false)
		eq(U.IsUnit("party1", "party1"), true)
		eq(U.GUID("target"), Mock.units.Get("boss").guid)
		eq(U.Class("party1"), "MAGE")
		eq(U.Name("party1"), "Mage")
		eq(U.AffectingCombat("player"), false)
		local role, why = U.Role("party1")
		isNil(role)
		eq(why, "none")
		Mock.units.Get("mage").role = "TANK"
		eq(U.Role("party1"), "TANK")
		Mock.secrets.Set{ identity = true, comparison = true }
		local guid, reason = U.GUID("target")
		isNil(guid)
		eq(reason, "secret")
		eq(select(2, U.Name("party1")), "secret")
		eq(select(2, U.IsUnit("party1", "target")), "secret")
		eq(select(2, U.Exists(Mock.Secret("string"))), "no-unit")
		eq(select(2, U.Exists(nil)), "no-unit")
		eq(#Mock.errors, 0)
	end)

	it("knows the party, the raid and the player's raidN", function()
		local G = C().Group
		truthy(G.InGroup())
		falsy(G.InRaid())
		eq(G.Size(), 2)
		isNil(G.RaidIndex())
		Mock.group.Set{ raid = true, members = { "mage" } }
		truthy(G.InRaid())
		eq(G.RaidIndex(), 2)
		Mock.group.Leave()
		eq(G.Size(), 0)
		Mock.Remove("UnitInRaid")
		isNil(G.RaidIndex())
	end)
end)
