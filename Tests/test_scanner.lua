-- Data/ThreatScanner.lua (SPEC-03 §1.1, §1.3–§1.4, SPEC-02 §1, ARC-05, ARC-06): reads only in combat, with a mob and a
-- consumer; the tick at its rate and its end at COMBAT_ENDED; events gathered, duplicated, out of order, missed; nil,
-- error, missing and secret answers recorded with their reason; the three probe outcomes and a change of outcome in the
-- middle of a fight; the cap and the round robin in a raid of 40; the pet; a roster that changes; /reload in combat;
-- no allocation per scan; the capabilities. Fight scripts: Tests/lib/fight.lua. The numbers of the mock are
-- assumptions until the M0 probe (Tests/mock/70_threat.lua).

-- recording off: the recorder is a scanner consumer of its own (test_recorder.lua)
before_boot(function(M) M.features = { monitor = true, recording = false } end)

local function TS() return Mock.ns.ThreatScanner end
local function Cap(id) return (Mock.ns.Compat.Capability(id)) end
local function calls(api) return Mock.threat.calls[api] or 0 end
local function reads() return calls("UnitDetailedThreatSituation") + calls("UnitThreatSituation") end
local function rec(token) return TS().RecordOf(token) end

local function newPull(def)
	def = def or {}
	return Fight.new{
		player = { class = "MAGE", role = "DAMAGER", ranged = true },
		party = def.party or {
			{ key = "tank", role = "TANK" },
			{ key = "healer", class = "PRIEST", role = "HEALER" },
			{ key = "rogue", class = "ROGUE", role = "DAMAGER" },
		},
		raid = def.raid,
		mobs = def.mobs or {
			{ key = "boss", tokens = { "target", "boss1" }, classification = "worldboss" },
			{ key = "add", tokens = { "nameplate2" } },
		},
	}
end

-- A party pull: the tank holds the boss, the player and the rogue follow, the healer is not on the list.
local function partyPull(outcome)
	local pull = newPull()
	if outcome then pull:outcome(outcome) end
	pull:at(0):start():threat("boss", "tank", 1000):threat("boss", "player", 500):threat("boss", "rogue", 300)
	return pull
end

-- No record field holds a secret value (DAT-13).
local function noSecrets(r)
	for k, v in pairs(r) do
		falsy(issecretvalue(v), "field " .. tostring(k) .. " holds a secret")
	end
end

describe("when nothing is read (ARC-05, M2.2 Done when)", function()
	it("reads nothing out of combat, even with a hostile target and a threat list", function()
		local pull = newPull()
		pull:threat("boss", "tank", 1000)
		Mock.Advance(3)
		eq(reads(), 0)
		falsy(TS().active)
		falsy(Mock.ns.Scheduler.IsRunning("threat"))
	end)

	it("reads nothing in combat without a monitored mob", function()
		local pull = newPull()
		Mock.units.Target("player", nil)
		pull:at(0):start():threat("boss", "tank", 1000)
		pull:to(3)
		eq(reads(), 0)
		falsy(TS().active)
		falsy(Mock.ns.Scheduler.IsRunning("threat"))
	end)

	it("reads nothing without a consumer, and starts when one wants it", function()
		local pull = newPull()
		TS().Want("window", false)
		pull:at(0):start():threat("boss", "tank", 1000)
		pull:to(2)
		eq(reads(), 0)
		truthy(TS().Want("alerts", true))
		truthy(reads() > 0)
		truthy(Mock.ns.Scheduler.IsRunning("threat"))
		falsy(TS().Want("alerts", false))
		local n = reads()
		Mock.Advance(2)
		eq(reads(), n)
	end)

	it("follows the window: shown on the Monitor tab only", function()
		local pull = partyPull()
		pull:to(0)
		truthy(TS().active)
		Mock.ns.Window:SelectTab("settings")
		falsy(TS().active)
		Mock.ns.Window:SelectTab("monitor")
		truthy(TS().active)
		Mock.ns.Window:Close()
		falsy(TS().active)
		Mock.ns.Window:Open()
		truthy(TS().active)
	end)

	it("registers no threat event while idle", function()
		newPull()
		local before = reads()
		Mock.Fire("UNIT_THREAT_LIST_UPDATE", "target")
		Mock.Fire("UNIT_THREAT_SITUATION_UPDATE", "player")
		Mock.Advance(1)
		eq(reads(), before)
		eq(TS().scans, 0)
	end)
end)

describe("the tick (SPEC-03 §1.4)", function()
	it("scans at the rate while the fight lasts and stops at COMBAT_ENDED", function()
		local pull = partyPull()
		local scanned = {}
		Mock.ns.Bus.On("THREAT_SCANNED", function(key) scanned[#scanned + 1] = key end)
		pull:at(0.05):silent(true)    -- only the tick from here on
		pull:to(0.15)                 -- after the scan the threat events of second 0 asked for
		local s0 = TS().scans
		eq(Mock.ns.Scheduler.Rate("threat"), 5)
		pull:to(2.15)
		eq(TS().scans - s0, 10, "5 Hz for 2 s")
		eq(scanned[#scanned], "mob:" .. Mock.units.Get("boss").guid)
		pull:at(2.2):stop()
		pull:to(2.2)
		falsy(Mock.ns.Scheduler.IsRunning("threat"))
		falsy(TS().active)
		local n = reads()
		Mock.Advance(3)
		eq(reads(), n, "nothing after the fight")
		truthy(rec("player").stale, "the rows stay, all stale")
		eq(rec("player").mode, "values", "with their last reading")
	end)

	it("scans by itself when the events are missed (silent)", function()
		local pull = partyPull()
		pull:at(0.1):silent(true)
		pull:at(1):threat("boss", "player", 950)
		pull:to(0.5)
		near(rec("player").scaledPercent, 500 / 1000 * 100 / 1.3, 1e-6)
		pull:to(1.3)
		near(rec("player").scaledPercent, 950 / 1000 * 100 / 1.3, 1e-6)
	end)

	it("follows the rate setting of schema 2 when it exists (M2.6), within 2-10 Hz", function()
		local pull = partyPull()
		pull:to(0)
		local values = { ["account.settings.monitor.rate"] = 30 }
		local get = Mock.ns.Config.Get
		Mock.ns.Config.Get = function(self, path)
			if values[path] ~= nil then return values[path] end
			return get(self, path)
		end
		Mock.ns.Bus.Emit("CONFIG_CHANGED", "account.settings.monitor.rate")
		eq(TS().Rate(), 10)
		eq(Mock.ns.Scheduler.Rate("threat"), 10)
		values["account.settings.monitor.rate"] = 1
		Mock.ns.Bus.Emit("CONFIG_CHANGED", "account.settings.monitor.rate")
		eq(Mock.ns.Scheduler.Rate("threat"), 2)
		Mock.ns.Config.Get = get
	end)
end)

describe("events (MON-07)", function()
	local function quietPull()
		local pull = partyPull()
		pull:to(0)
		Mock.ns.Scheduler.Stop("threat")   -- the events alone
		Mock.Advance(0.5)
		return pull
	end

	it("gathers the requests: at most one full scan every 100 ms", function()
		quietPull()
		local s0 = TS().scans
		for _ = 1, 6 do Mock.Fire("UNIT_THREAT_LIST_UPDATE", "target") end
		eq(TS().scans - s0, 1, "the first now")
		Mock.Fire("UNIT_THREAT_LIST_UPDATE", "boss1")   -- the same mob by another token (UnitIsUnit)
		eq(TS().scans - s0, 1)
		eq(Mock.PendingTimers(), 1, "one waiting scan")
		Mock.Advance(0.1)
		eq(TS().scans - s0, 2, "the waiting one at the end of the gap")
		Mock.Advance(1)
		eq(TS().scans - s0, 2)
		eq(Cap("threatEvents"), "available")
	end)

	it("ignores an event for another mob, an unwatched unit or a secret payload", function()
		quietPull()
		local s0, r0 = TS().scans, reads()
		Mock.Fire("UNIT_THREAT_LIST_UPDATE", "nameplate2")
		Mock.Fire("UNIT_THREAT_SITUATION_UPDATE", "raid7")
		Mock.Fire("UNIT_THREAT_SITUATION_UPDATE", "nameplate2")
		Mock.Fire("UNIT_THREAT_LIST_UPDATE", Mock.Secret("string"))
		Mock.Fire("UNIT_THREAT_SITUATION_UPDATE", Mock.Secret("string"))
		Mock.Advance(0.5)
		eq(TS().scans, s0)
		eq(reads(), r0)
		eq(#Mock.errors, 0)
	end)

	it("reads one unit for its situation event; a duplicate costs one read and never a wrong value", function()
		local pull = quietPull()
		pull:silent(true):threat("boss", "rogue", 900):silent(false)
		local r0 = reads()
		Mock.Fire("UNIT_THREAT_SITUATION_UPDATE", "party3")
		eq(reads() - r0, 1)
		near(rec("party3").scaledPercent, 900 / 1000 * 100 / 1.1, 1e-6)
		local t1 = rec("party3").observedAt
		Mock.Advance(0.2)
		Mock.Fire("UNIT_THREAT_SITUATION_UPDATE", "party3")   -- late and duplicated
		eq(reads() - r0, 2)
		near(rec("party3").scaledPercent, 900 / 1000 * 100 / 1.1, 1e-6)
		truthy(rec("party3").observedAt > t1, "a newer sample, never an older one")
	end)

	it("merges a unit's read into a waiting scan", function()
		quietPull()
		Mock.Fire("UNIT_THREAT_LIST_UPDATE", "target")
		Mock.Fire("UNIT_THREAT_LIST_UPDATE", "target")   -- now one waits
		local r0 = reads()
		Mock.Fire("UNIT_THREAT_SITUATION_UPDATE", "party1")
		eq(reads(), r0)
		Mock.Advance(0.1)
		eq(reads() - r0, 4, "the waiting scan read everybody")
	end)

	it("follows a fight driven by events: who holds the mob, and the lead of the holder", function()
		local pull = partyPull()
		pull:to(0.1)
		eq(TS().holder, rec("party1"))
		truthy(rec("party1").isTanking)
		eq(rec("party1").leadSituation, 0)
		near(rec("party1").leadPercent, 1000 / 500 * 100, 1e-6)
		eq(Cap("threatLead"), "available")
		pull:at(1):taunt("boss", "player")
		pull:to(1.3)
		eq(TS().holder, rec("player"))
		isNil(rec("party1").leadSituation, "the lead is read for the holder only")
	end)
end)

describe("answers (SPEC-01 §8.3, MON-05)", function()
	it("records nil for a unit that is not on the list: the row is absent, not unknown", function()
		local pull = partyPull()
		pull:to(0.5)
		eq(rec("party2").mode, "none")
		eq(rec("party2").reason, "nil")
		eq(TS().mode, "values")
		isNil(TS().modeReason)
	end)

	it("records an error with its reason and goes on with the others", function()
		local pull = partyPull()
		pull:answer("UnitDetailedThreatSituation", "party3", "target", Mock.threat.ERROR)
		pull:answer("UnitThreatSituation", "party3", "target", Mock.threat.ERROR)
		pull:to(0.5)
		eq(rec("party3").mode, "none")
		eq(rec("party3").reason, "error")
		eq(rec("player").mode, "values")
		eq(#Mock.errors, 0)
		pull:clearAnswers()
		pull:to(1)
		eq(rec("party3").mode, "values")
		isNil(rec("party3").reason)
	end)

	it("falls back to the state when the detailed function is missing", function()
		Mock.Remove("UnitDetailedThreatSituation")
		local pull = partyPull()
		pull:to(0.5)
		eq(rec("player").mode, "state")
		eq(rec("player").reason, "missing")
		eq(rec("player").situation, 0)
		isNil(rec("player").scaledPercent)
		eq(Cap("threatValues"), "missing")
		eq(Cap("threatState"), "available")
		eq(TS().mode, "state")
	end)

	it("records a secret answer of a unit as secret, never its value", function()
		local pull = partyPull()
		pull:answer("UnitDetailedThreatSituation", "party1", "target", Mock.threat.SECRET)
		pull:answer("UnitThreatSituation", "party1", "target", Mock.threat.SECRET)
		pull:to(0.5)
		eq(rec("party1").mode, "none")
		eq(rec("party1").reason, "secret")
		noSecrets(rec("party1"))
		eq(rec("player").mode, "values", "the other rows keep their own mode (MON-04)")
		eq(#Mock.errors, 0)
	end)
end)

describe("the three probe outcomes (SPEC-03 §1.1, Fight.OUTCOMES)", function()
	local expected = {
		values = { mode = "values", reason = nil, values = "available", state = "available" },
		state = { mode = "state", reason = "secret", values = "restricted", state = "available" },
		none = { mode = "none", reason = "secret", values = "restricted", state = "restricted" },
	}
	for _, outcome in ipairs(Fight.OUTCOMES) do
		it("reads " .. outcome .. " with its reason, and keeps no secret", function()
			local want = expected[outcome]
			local pull = partyPull(outcome)
			pull:to(1)
			for _, token in ipairs({ "player", "party1", "party3" }) do
				local r = rec(token)
				eq(r.mode, want.mode, token)
				eq(r.reason, want.reason, token)
				noSecrets(r)
				eq(r.mobKey, "mob:" .. Mock.units.Get("boss").guid)
				eq(r.mobToken, "target")
			end
			if outcome == "values" then
				near(rec("player").scaledPercent, 500 / 1000 * 100 / 1.3, 1e-6)
				eq(rec("player").rawThreat, 500)
			else
				isNil(rec("player").scaledPercent)
				isNil(rec("player").rawThreat)
			end
			if outcome == "state" then eq(rec("party1").situation, 3) else
				if outcome == "none" then isNil(rec("party1").situation) end
			end
			eq(TS().mode, want.mode)
			eq(Cap("threatValues"), want.values)
			eq(Cap("threatState"), want.state)
			eq(Cap("groupThreat"), outcome == "none" and "unknown" or "available")
			eq(#Mock.errors, 0)
		end)
	end

	it("follows a change of outcome in the middle of the fight", function()
		local pull = partyPull("values")
		pull:at(2):outcome("state")
		pull:at(4):outcome("none")
		pull:at(6):outcome("values")
		pull:to(1)
		eq(TS().mode, "values")
		pull:to(3)
		eq(TS().mode, "state")
		eq(rec("player").mode, "state")
		pull:to(5)
		eq(TS().mode, "none")
		eq(TS().modeReason, "secret")
		pull:to(7)
		eq(TS().mode, "values")
		eq(Cap("threatValues"), "available")
	end)

	it("lets a row be values while another is state (values readable for the player only) [probe P3, P5]", function()
		local pull = partyPull()
		pull:secrets{ values = function(unit) return unit ~= "player" end }
		pull:to(1)
		eq(rec("player").mode, "values")
		eq(rec("party1").mode, "state")
		eq(TS().mode, "values")
	end)
end)

describe("the units watched (SPEC-03 §1.3)", function()
	local function raid(n)
		local members = { { key = "m1", role = "TANK" } }
		for i = 2, n do members[i] = { key = "m" .. i, class = "ROGUE", role = "DAMAGER" } end
		return newPull{ raid = true, party = members }
	end

	it("watches player, party1-4 in a party, in roster order, with names, classes, roles and keys", function()
		local pull = partyPull()
		pull:to(0)
		eq(TS().count, 4)
		deepEq({ TS().units[1], TS().units[2], TS().units[3], TS().units[4] }, { "player", "party1", "party2", "party3" })
		eq(rec("party1").role, "TANK")
		eq(rec("party2").classFile, "PRIEST")
		eq(rec("party2").unitName, "Healer")
		eq(rec("party1").unitKey, "unit:" .. Mock.units.Get("tank").guid)
		eq(Cap("roles"), "available")
	end)

	it("keys a unit by its token when its GUID is secret [probe P9]", function()
		Mock.secrets.Set{ identity = true }
		local pull = partyPull()
		pull:to(0)
		eq(rec("party1").unitKey, "tok:party1")
		isNil(rec("party1").unitName)
		isNil(rec("party1").classFile)
		eq(rec("player").unitKey, "unit:" .. Mock.player.guid)
	end)

	it("watches the raid without the player's own raidN, every unit with the default cap of 40", function()
		local pull = raid(39)
		pull:at(0):start():threat("boss", "m1", 1000):threat("boss", "player", 10)
		pull:to(0)
		eq(TS().count, 40)
		isNil(rec("raid40"), "raid40 is the player")
		eq(TS().turns, 1)
		local r0 = reads()
		TS().Scan()
		eq(reads() - r0, 40)
	end)

	it("reads maxUnits per scan, player, tanks and holder every time, the others in turn", function()
		local pull = raid(39)
		truthy(Mock.ns.Config:Set("account.settings.monitor.maxUnits", 10))
		pull:at(0):start():threat("boss", "m2", 1000):threat("boss", "player", 10)
		pull:to(0)
		eq(TS().MaxUnits(), 10)
		for _ = 1, 5 do TS().Scan() end   -- the holder is found by a read in turn, then read every time
		eq(TS().holder, rec("raid2"))
		local seen = {}
		for _ = 1, 6 do
			local r0 = reads()
			TS().Scan()
			eq(reads() - r0, 10)
			for i = 1, TS().count do
				local r = TS().records[i]
				if r.scanned then seen[r.unitToken] = (seen[r.unitToken] or 0) + 1 end
			end
		end
		eq(seen.player, 6)
		eq(seen.raid1, 6, "the designated tank")
		eq(seen.raid2, 6, "the holder")
		local all = 0
		for _ in pairs(seen) do all = all + 1 end
		eq(all, 40, "everybody read within six scans")
		eq(TS().turns, 6, "37 others on 7 places")
		near(rec("raid9").interval, 6 / 5, 1e-9)
		near(rec("player").interval, 1 / 5, 1e-9)
	end)

	it("adds the pet at UNIT_PET, second in the roster", function()
		local pull = partyPull()
		Mock.units.Add("wolf", { class = "HUNTER" })
		pull:to(0)
		Mock.units.SetToken("pet", "wolf")
		Mock.Fire("UNIT_PET", "party1")   -- another unit's pet: nothing
		eq(TS().count, 4)
		Mock.Fire("UNIT_PET", "player")
		eq(TS().count, 5)
		eq(TS().units[2], "pet")
		Mock.threat.Set("boss", "wolf", 200)
		Mock.Advance(0.3)
		eq(rec("pet").mode, "values")
	end)

	it("rebuilds the roster when it changes, in combat too, and reuses the records", function()
		local pull = partyPull()
		pull:to(0)
		local first = TS().records[2]
		Mock.group.Set{ members = { "tank" } }
		eq(TS().count, 2)
		eq(TS().records[2], first, "the same record")
		falsy(TS().records[3].inUse)
		isNil(rec("party3"))
		Mock.group.Set{ members = { "tank", "healer", "rogue" } }
		eq(TS().count, 4)
		Mock.Advance(0.3)
		eq(rec("party3").mode, "values")
	end)
end)

describe("the mob", function()
	it("clears the readings and scans the new mob at TARGET_CHANGED", function()
		local pull = partyPull()
		pull:threat("add", "player", 50)
		pull:to(0.5)
		eq(rec("party1").mode, "values")
		Mock.units.Target("player", "add")
		eq(rec("player").mobKey, "mob:" .. Mock.units.Get("add").guid)
		eq(rec("party1").reason, "nil", "the tank is not on the add's list")
	end)

	it("stops reading when the mob dies or vanishes", function()
		local pull = partyPull()
		pull:at(1):die("boss")
		pull:to(1.5)
		falsy(TS().active)
		local n = reads()
		Mock.Advance(1)
		eq(reads(), n)
	end)

	it("follows a new GUID behind the same token at the next scan", function()
		local pull = partyPull()
		local keys = {}
		Mock.ns.Bus.On("TARGET_CHANGED", function(key) keys[#keys + 1] = key end)
		pull:at(1):newGUID("boss")
		pull:to(1.3)
		eq(#keys, 1)
		eq(rec("player").mobKey, "mob:" .. Mock.units.Get("boss").guid)
		truthy(TS().active)
	end)
end)

describe("/reload in combat [probe P12]", function()
	it("starts again from the player's combat flag at PLAYER_ENTERING_WORLD", function()
		local pull = partyPull()
		pull:to(0.5)
		Mock.Reload()
		truthy(Mock.ns.addon.inCombat)
		truthy(Mock.ns.ThreatScanner.active)
		local n = reads()
		Mock.Advance(1)
		truthy(reads() > n)
	end)
end)

describe("performance (ARC-06, MON-08)", function()
	it("allocates nothing per scan after the warm-up, in a raid of 40", function()
		local members = { { key = "m1", role = "TANK" } }
		for i = 2, 39 do members[i] = { key = "m" .. i, class = "ROGUE" } end
		local pull = newPull{ raid = true, party = members }
		pull:at(0):start():threat("boss", "m1", 1000)
		for i = 2, 39, 2 do pull:threat("boss", "m" .. i, i * 10) end
		pull:threat("boss", "player", 600)
		pull:to(0.5)
		Mock.ns.Scheduler.Stop("threat")
		for _ = 1, 20 do TS().Scan() end
		eq(rec("player").mode, "values")
		-- the mock client allocates for its own answers: constant stand-ins, so that only the addon is measured
		local mobGUID = UnitGUID("target")
		UnitExists = function() return true end
		UnitIsDead = function() return false end
		UnitGUID = function() return mobGUID end
		C_Secrets.ShouldUnitThreatStateBeSecret = function() return false end
		C_Secrets.ShouldUnitThreatValuesBeSecret = function() return false end
		UnitDetailedThreatSituation = function(unit)
			if unit == "raid1" then return true, 3, 100, 100, 1000 end
			return false, 0, 40, 44, 440
		end
		UnitThreatPercentageOfLead = function() return 150 end
		UnitThreatLeadSituation = function() return 0 end
		for _ = 1, 20 do TS().Scan() end
		-- the smallest growth of three batches, under 4 KB (as test_threat_model): a growth of the Lua state outside the
		-- scans (seen now and then at 2.5-2.8 KB, with no Bus error and no state change) stays under it, while an
		-- allocation per scan (500 scans: at least 16 KB for one table each) does not
		local grown = math.huge
		for _ = 1, 3 do
			collectgarbage("collect")
			collectgarbage("stop")
			local before = collectgarbage("count")
			for _ = 1, 500 do TS().Scan() end
			grown = math.min(grown, collectgarbage("count") - before)
			collectgarbage("restart")
		end
		truthy(grown < 4, "grew by " .. grown .. " KB")
		eq(rec("player").mode, "values")
		eq(TS().holder, rec("raid1"))
		eq(rec("raid1").leadSituation, 0)
	end)
end)

describe("the monitor switch off", function()
	before_boot(function(M) M.features = { monitor = false } end)

	it("reads nothing and registers nothing, in combat with a target", function()
		local pull = partyPull()
		pull:to(3)
		eq(reads(), 0)
		falsy(TS().enabled)
		falsy(TS().active)
		eq(TS().count, 0)
	end)
end)

describe("the debug section", function()
	it("gives counts and the mode, never a name", function()
		local pull = partyPull()
		pull:to(0.5)
		local lines = TS().DebugLines()
		matches(lines[1], "^active, 4 unit%(s%) watched, max 40, 5 Hz, 1 turn%(s%)$")
		matches(lines[2], "^%d+ scan%(s%), %d+ read%(s%), mode values$")
		falsy(table.concat(lines, " "):find("Tank", 1, true))
	end)
end)
