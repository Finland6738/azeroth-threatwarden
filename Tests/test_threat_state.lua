-- Data/ThreatState.lua (SPEC-03 §2, SPEC-09 Q7, MON-04, MON-10–MON-12) on fight scripts: the rules of §2.2 and §2.3 row
-- by row (non tank, tank holding the mob, designated tank losing it, a swap between two tanks, alone with the pet); the
-- hysteresis on a series oscillating by ±2 points around 80 and 95; the 1 s dwell for falls and the immediate rises,
-- also after the combat; UNKNOWN with its reason; the predicted WARNING; tank detection and the Unknown tank;
-- THREAT_MODE_CHANGED at every change of outcome; the thresholds from the settings; the QA-03 scenarios about states
-- (tank stable, DPS nearing the threshold, taunt, tank death, DPS death, target change, secret values, state only,
-- nothing readable); no allocation per update. The numbers of the mock are assumptions until the M0 probe
-- (Tests/mock/70_threat.lua): where a number matters the script fixes the scaled % or the game's state.

before_boot(function(M) M.features = { monitor = true } end)

local function TS() return Mock.ns.ThreatScanner end
local function TM() return Mock.ns.ThreatModel end
local function ST() return Mock.ns.ThreatState end
local function row(token) return TM().RowOf(token) end
local function state(token)
	local r = row(token)
	return r and r.state, r and r.stateReason
end
local function keyOf(token) return TS().RecordOf(token).unitKey end

-- Every STATE_CHANGED from now on: { unitKey, mobKey, old, new }, nil written as "nil".
local function recordChanges()
	local seen = {}
	Mock.ns.Bus.On("STATE_CHANGED", function(unitKey, mobKey, old, new)
		seen[#seen + 1] = { unit = unitKey, mob = mobKey, old = old or "nil", new = new or "nil" }
	end)
	return seen
end

-- The transitions of one token, as "OLD>NEW" strings.
local function changesOf(seen, token)
	local key, out = keyOf(token), {}
	for _, c in ipairs(seen) do
		if c.unit == key then out[#out + 1] = c.old .. ">" .. c.new end
	end
	return out
end

local function newPull(def)
	def = def or {}
	return Fight.new{
		player = def.player or { class = "MAGE", role = "DAMAGER", ranged = true },
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

-- The tank (party1) holds the boss; the player and the rogue at fixed scaled percentages.
local function partyPull(me, rogue, outcome)
	local pull = newPull()
	if outcome then pull:outcome(outcome) end
	pull:at(0):start():threat("boss", "tank", 1000)
		:threat("boss", "player", { raw = 500, scaled = me or 40 })
		:threat("boss", "rogue", { raw = 300, scaled = rogue or 20 })
	return pull
end

describe("values: a non tank (SPEC-03 §2.2)", function()
	local cases = {
		{ 40, "SAFE" }, { 79.9, "SAFE" }, { 80, "WARNING" }, { 94.9, "WARNING" }, { 95, "DANGER" }, { 100, "DANGER" },
	}
	for _, case in ipairs(cases) do
		it("is " .. case[2] .. " at " .. case[1] .. " %", function()
			local pull = partyPull(case[1])
			pull:to(1)
			local s, why = state("player")
			eq(s, case[2])
			isNil(why)
			falsy(row("player").isTank)
		end)
	end

	it("is DANGER while it holds the mob, with the reason aggro", function()
		local pull = partyPull(40)
		pull:at(1):aggro("boss", "player")
		pull:to(2)
		eq(state("player"), "DANGER")
		eq(select(2, state("player")), "aggro")
	end)

	it("leaves a unit that is not on the list without a state (MON-05)", function()
		local pull = partyPull()
		pull:to(1)
		isNil(state("party2"), "the healer has no threat on the boss")
		falsy(row("party2").present)
	end)
end)

describe("values: the tank holding the mob, on its margin over the second (MON-11)", function()
	local cases = { { 60, "SAFE" }, { 80, "WARNING" }, { 90, "WARNING" }, { 95, "DANGER" } }
	for _, case in ipairs(cases) do
		it("is " .. case[2] .. " when the second is at " .. case[1] .. " %", function()
			local pull = partyPull(case[1], 10)
			pull:to(1)
			local tank = row("party1")
			truthy(tank.isTank)
			truthy(tank.isHolder)
			eq(tank.state, case[2])
			near(tank.margin, 100 - case[1], 1e-6)
		end)
	end

	it("is DANGER when it holds the mob but another has more threat (situation 2)", function()
		local pull = partyPull(40)
		pull:threat("boss", "tank", { raw = 1000, status = 2 })
		pull:to(1)
		eq(state("party1"), "DANGER")
		eq(select(2, state("party1")), "behind")
	end)

	it("is SAFE alone on the list, with the reason alone", function()
		local pull = newPull()
		pull:at(0):start():threat("boss", "tank", 1000)
		pull:to(1)
		eq(state("party1"), "SAFE")
		eq(select(2, state("party1")), "alone")
		eq(ST().tank, row("party1"))
		isNil(ST().tankReason)
	end)

	it("follows the game's lead situation when no other row is in values, else UNKNOWN with the second's reason", function()
		local pull = partyPull(40, 20)
		pull:secrets{ values = function(unit) return unit ~= "party1" end }
		pull:threat("boss", "tank", { raw = 1000, leadStatus = 1 })
		pull:to(1)
		eq(row("party1").record.mode, "values")
		eq(state("party1"), "WARNING")
		pull:answer("UnitThreatLeadSituation", "party1", "*", Mock.threat.NIL)
		pull:at(1.5):threat("boss", "tank", 1001)
		pull:to(3)
		eq(state("party1"), "UNKNOWN")
		eq(select(2, state("party1")), "state-only")
	end)
end)

describe("AGGRO_CHANGED (SPEC-04 §1.1, M3.2)", function()
	-- Every AGGRO_CHANGED from now on, as "mob old>new" with the tokens of the watched units.
	local function recordAggro()
		local seen = {}
		local function token(key)
			if key == nil then return "nil" end
			for i = 1, TS().count do
				if TS().records[i].unitKey == key then return TS().records[i].unitToken end
			end
			return key
		end
		Mock.ns.Bus.On("AGGRO_CHANGED", function(mobKey, unitKey, oldUnitKey)
			seen[#seen + 1] = { mob = mobKey, change = token(oldUnitKey) .. ">" .. token(unitKey) }
		end)
		return seen
	end

	local function changes(seen)
		local out = {}
		for i, c in ipairs(seen) do out[i] = c.change end
		return table.concat(out, " ")
	end

	for _, outcome in ipairs({ "values", "state" }) do
		it("says the first holder, then every change with the one before (" .. outcome .. ")", function()
			local seen = recordAggro()
			local pull = partyPull(40, 20, outcome)
			pull:to(2)
			eq(changes(seen), "nil>party1")
			eq(seen[1].mob, TM().mobKey)
			pull:at(3):aggro("boss", "rogue")
			pull:at(5):aggro("boss", "tank")
			pull:to(7)
			eq(changes(seen), "nil>party1 party1>party3 party3>party1")
			eq(ST().aggroChanges, 3)
		end)
	end

	it("says nothing in the outcome none", function()
		local seen = recordAggro()
		local pull = partyPull(40, 20, "none")
		pull:at(2):aggro("boss", "rogue")
		pull:to(4)
		eq(#seen, 0)
	end)

	it("says nothing while the holder is unknown, nor when the same one comes back", function()
		local seen = recordAggro()
		local pull = partyPull(40, 20)
		pull:at(2):outcome("none")
		pull:at(6):outcome("values")
		pull:to(8)
		eq(changes(seen), "nil>party1")
		pull:at(9):outcome("none")
		pull:at(10):aggro("boss", "rogue")
		pull:at(12):outcome("values")
		pull:to(14)
		eq(changes(seen), "nil>party1 party1>party3", "another one after the gap is a change")
	end)

	it("starts again at a new mob and a new fight", function()
		local seen = recordAggro()
		local pull = partyPull(40, 20)
		pull:threat("add", "rogue", 800):threat("add", "player", 100)
		pull:to(2)
		pull:at(3):target("player", "add")
		pull:to(4)
		pull:at(5):target("player", "boss")
		pull:to(6)
		eq(changes(seen), "nil>party1 nil>party3 nil>party1")
		pull:at(7):stop()
		pull:at(10):start():threat("boss", "tank", 1000)
		pull:to(11)
		eq(changes(seen), "nil>party1 nil>party3 nil>party1 nil>party1")
	end)

	it("comes before the STATE_CHANGED of the same update, with the tanks known", function()
		local pull = partyPull(40, 20)
		pull:to(2)
		local order = {}
		Mock.ns.Bus.On("AGGRO_CHANGED", function()
			order[#order + 1] = "aggro"
			eq(ST().designated, 1)
			eq(ST().tank, row("party3"))
		end)
		Mock.ns.Bus.On("STATE_CHANGED", function() order[#order + 1] = "state" end)
		pull:at(3):aggro("boss", "rogue")
		pull:to(4)
		eq(order[1], "aggro")
		contains(order, "state")
	end)
end)

describe("tank detection (SPEC-03 §2.1)", function()
	it("takes the designated tanks from the assigned role", function()
		local pull = partyPull()
		pull:to(1)
		eq(ST().designated, 1)
		truthy(row("party1").isTank)
		falsy(row("player").isTank)
		falsy(row("party3").isTank)
		eq(ST().tank, row("party1"))
	end)

	it("makes a designated tank that lost the mob to a non tank DANGER (lost aggro), and the non tank DANGER (aggro)", function()
		local pull = partyPull(60)
		pull:at(1):aggro("boss", "rogue")
		pull:to(2)
		eq(state("party1"), "DANGER")
		eq(select(2, state("party1")), "lost-aggro")
		eq(state("party3"), "DANGER")
		eq(select(2, state("party3")), "aggro")
		eq(ST().tank, row("party3"), "the tank of the mob is whoever holds it")
	end)

	it("swaps two tanks on a taunt: the new holder on its margin, the old one by the non tank rule", function()
		local pull = newPull{ party = {
			{ key = "mt", role = "TANK" }, { key = "ot", class = "PALADIN", role = "TANK" },
			{ key = "rogue", class = "ROGUE", role = "DAMAGER" },
		} }
		pull:at(0):start():threat("boss", "mt", 1000):threat("boss", "ot", 600)
			:threat("boss", "player", { raw = 300, scaled = 30 })
		pull:to(1)
		eq(ST().designated, 2)
		eq(state("party1"), "SAFE")
		local seen = recordChanges()
		pull:at(2):taunt("boss", "ot")
		pull:to(3)
		eq(ST().tank, row("party2"))
		truthy(row("party2").isHolder)
		local mt, why = state("party1")
		falsy(why == "lost-aggro", "another tank holds it")
		falsy(why == "aggro")
		eq(mt, "WARNING", "the old tank at 1000 / 1000 / 1.1 = 90.9 %")
		notNil(state("party2"))
		eq(#changesOf(seen, "player"), 0, "the DPS is not touched")
	end)

	it("treats the holder as the tank when no one has the TANK role: alone with the pet", function()
		local pull = Fight.new{
			player = { class = "HUNTER", role = "NONE", ranged = true },
			mobs = { { key = "boss", tokens = { "target" } } },
		}
		Mock.units.Add("wolf", { class = "HUNTER" })
		Mock.units.SetToken("pet", "wolf")
		Mock.Fire("UNIT_PET", "player")
		pull:at(0):start()
		pull:threat("boss", "wolf", 1000):threat("boss", "player", { raw = 700, scaled = 85 })
		pull:to(1)
		eq(ST().designated, 0)
		truthy(row("pet").isTank)
		truthy(row("pet").isHolder)
		falsy(row("player").isTank)
		eq(state("pet"), "WARNING", "the second (the player) at 85 %")
		eq(state("player"), "WARNING")
		pull:at(1.2):aggro("boss", "player")
		pull:to(2)
		truthy(row("player").isTank, "now the player holds it")
		falsy(row("pet").isTank)
	end)

	it("says Unknown tank when nothing readable says who holds the mob", function()
		local pull = partyPull(40, 20, "none")
		pull:to(1)
		isNil(ST().tank)
		eq(ST().tankReason, "unknown")
	end)

	it("says not-watched when the reads are readable but no watched unit holds the mob", function()
		local pull = partyPull(40, 20)
		pull:answer("UnitDetailedThreatSituation", "party1", "*", Mock.threat.NIL)
		pull:answer("UnitThreatSituation", "party1", "*", Mock.threat.NIL)
		pull:to(1)
		isNil(ST().tank)
		eq(ST().tankReason, "not-watched")
		eq(state("player"), "SAFE")
	end)
end)

describe("state only (SPEC-03 §2.3, MON-02)", function()
	local rows = {
		{ "a non tank", "player", { raw = 500, status = 0 }, "SAFE" },
		{ "a non tank", "player", { raw = 500, status = 1 }, "WARNING" },
	}
	for _, case in ipairs(rows) do
		it("makes " .. case[1] .. " with situation " .. case[3].status .. " " .. case[4], function()
			local pull = partyPull(40, 20, "state")
			pull:threat("boss", "player", case[3])
			pull:to(1)
			eq(row("player").record.mode, "state")
			eq(state("player"), case[4])
			eq(select(2, state("player")), "state-only")
		end)
	end

	it("makes a non tank holding the mob (situation 2-3) DANGER", function()
		local pull = partyPull(40, 20, "state")
		pull:at(1):aggro("boss", "player")
		pull:to(2)
		truthy(row("player").record.situation >= 2)
		eq(state("player"), "DANGER")
	end)

	local tanks = { { 3, 0, "SAFE" }, { 3, 1, "WARNING" }, { 3, 2, "DANGER" }, { 3, 3, "DANGER" }, { 2, 0, "DANGER" } }
	for _, case in ipairs(tanks) do
		it(("makes the tank with situation %d and lead %d %s"):format(case[1], case[2], case[3]), function()
			local pull = partyPull(40, 20, "state")
			pull:threat("boss", "tank", { raw = 1000, status = case[1], leadStatus = case[2] })
			pull:to(1)
			truthy(row("party1").isHolder)
			eq(state("party1"), case[3])
		end)
	end

	it("makes the tank SAFE with Margin unknown when the lead is not readable", function()
		local pull = partyPull(40, 20, "state")
		pull:answer("UnitThreatLeadSituation", "party1", "*", Mock.threat.NIL)
		pull:to(1)
		eq(state("party1"), "SAFE")
		eq(select(2, state("party1")), "margin-unknown")
	end)

	it("keeps no secret value anywhere (secret values, DAT-13)", function()
		local pull = partyPull(40, 20, "state")
		pull:to(2)
		for i = 1, TM().count do
			for k, v in pairs(TM().rows[i]) do falsy(issecretvalue(v), "row field " .. tostring(k)) end
		end
		eq(#Mock.errors, 0)
	end)
end)

describe("UNKNOWN with its reason (MON-01, MON-05)", function()
	it("nothing readable: every row on the list is UNKNOWN, secret", function()
		local pull = partyPull(40, 20, "none")
		pull:to(1)
		for _, token in ipairs({ "player", "party1", "party3" }) do
			eq(state(token), "UNKNOWN", token)
			eq(select(2, state(token)), "secret", token)
		end
		eq(ST().mode, "none")
	end)

	it("a read error: UNKNOWN, error", function()
		local pull = partyPull(40, 20)
		pull:answer("UnitDetailedThreatSituation", "player", "*", Mock.threat.ERROR)
		pull:answer("UnitThreatSituation", "player", "*", Mock.threat.ERROR)
		pull:to(1)
		eq(state("player"), "UNKNOWN")
		eq(select(2, state("player")), "error")
	end)

	it("a stale row: UNKNOWN, stale, after the dwell", function()
		local pull = partyPull(40, 20)
		pull:to(2)
		eq(state("player"), "SAFE")
		Mock.ns.Scheduler.Stop("threat")
		pull:silent(true)
		Mock.Advance(0.6)
		TM().Update()
		ST().Update()
		eq(state("player"), "UNKNOWN", "SAFE since 0 s: the dwell is over")
		eq(select(2, state("player")), "stale")
	end)
end)

describe("hysteresis and dwell (MON-10, MON-12)", function()
	-- p oscillates by ±2 points around `around` every 0.2 s for 6 s, after one step above it.
	local function oscillate(around, start)
		local pull = partyPull(start, 10)
		pull:at(0.5):threat("boss", "player", { raw = 500, scaled = around + 2 })
		local seen
		pull:at(0.6):call(function() seen = recordChanges() end)
		for i = 1, 30 do
			local t = 0.6 + i * 0.2
			pull:at(t):threat("boss", "player", { raw = 500 + i, scaled = around + ((i % 2 == 1) and -2 or 2) })
		end
		return pull, function() return seen end
	end

	it("does not flicker around WARNING 80", function()
		local pull, seen = oscillate(80, 60)
		pull:to(0.55)
		eq(state("player"), "WARNING")
		pull:finish()
		eq(#changesOf(seen(), "player"), 0, "78 stays WARNING: it leaves only below 77")
		eq(state("player"), "WARNING")
	end)

	it("does not flicker around DANGER 95", function()
		local pull, seen = oscillate(95, 60)
		pull:to(0.55)
		eq(state("player"), "DANGER")
		pull:finish()
		eq(#changesOf(seen(), "player"), 0, "93 stays DANGER: it leaves only below 92")
	end)

	it("does not flicker on the tank's margin either", function()
		local pull = partyPull(60, 10)
		pull:at(0.5):threat("boss", "player", { raw = 500, scaled = 82 })
		local seen
		pull:at(0.6):call(function() seen = recordChanges() end)
		for i = 1, 20 do
			pull:at(0.6 + i * 0.2):threat("boss", "player", { raw = 500 + i, scaled = (i % 2 == 1) and 78 or 82 })
		end
		pull:finish()
		eq(state("party1"), "WARNING")
		eq(#changesOf(seen, "party1"), 0)
	end)

	it("leaves a higher state 3 points below its threshold", function()
		local pull = partyPull(85, 10)
		pull:to(1)
		eq(state("player"), "WARNING")
		pull:at(2.5):threat("boss", "player", { raw = 500, scaled = 76.9 })
		pull:to(3)
		eq(state("player"), "SAFE")
	end)

	it("rises at once and falls only 1 s after the last change", function()
		local pull = partyPull(40, 10)
		pull:to(1)
		local seen = recordChanges()
		pull:at(1.5):threat("boss", "player", { raw = 500, scaled = 97 })
		pull:to(1.5)
		eq(state("player"), "DANGER", "immediately")
		local since = row("player").stateSince
		pull:at(1.7):threat("boss", "player", { raw = 501, scaled = 50 })
		pull:to(2.4)
		eq(state("player"), "DANGER", "held: the change was less than 1 s ago")
		pull:to(2.7)
		eq(state("player"), "SAFE")
		truthy(row("player").stateSince >= since + 1 - 1e-6)
		deepEq(changesOf(seen, "player"), { "SAFE>DANGER", "DANGER>SAFE" })
	end)

	it("never changes a row more than once a second except for rises", function()
		local pull = partyPull(40, 10)
		local times = {}
		pull:at(0.5):call(function()
			Mock.ns.Bus.On("STATE_CHANGED", function(unitKey, _, old, new)
				if unitKey == keyOf("player") then
					times[#times + 1] = { at = Mock.ns.Compat.Now(), old = old, new = new }
				end
			end)
		end)
		local values = { 97, 50, 85, 40, 96, 30, 88, 20, 97, 10 }
		for i, v in ipairs(values) do pull:at(0.5 + i * 0.3):threat("boss", "player", { raw = 500 + i, scaled = v }) end
		pull:to(8)
		truthy(#times >= 4)
		local LEVEL = { SAFE = 1, WARNING = 2, DANGER = 3 }
		for i = 2, #times do
			local c = times[i]
			if LEVEL[c.new] < LEVEL[c.old] then
				truthy(c.at - times[i - 1].at >= 1 - 1e-6, "a fall " .. (c.at - times[i - 1].at) .. " s after a change")
			end
		end
		eq(state("player"), "SAFE")
	end)
end)

describe("the predicted WARNING (SPEC-03 §2.2, §2.5)", function()
	it("warns a DPS rising towards DANGER before 80 %, with the seconds, and ends when the prediction stops", function()
		local pull = partyPull(50, 10)
		for i = 0, 15 do
			pull:at(0.2 + i * 0.2):threat("boss", "player", { raw = 500 + i, scaled = 50 + i * 2 })   -- +10 %/s
		end
		pull:to(2.3)
		local me = row("player")
		truthy(me.record.scaledPercent < 80)
		eq(me.state, "WARNING")
		eq(me.stateReason, "predicted")
		truthy(me.predictedIn <= 3)
		truthy(me.trendConfidence == "medium" or me.trendConfidence == "high")
		-- flat from here: the prediction ends, the fall waits for the dwell
		for i = 1, 25 do pull:at(3.2 + i * 0.2):threat("boss", "player", { raw = 600 + i, scaled = 70 }) end
		pull:finish()
		eq(me.state, "SAFE")
		isNil(me.predictedIn)
	end)

	it("does not predict with a low confidence", function()
		local pull = partyPull(50, 10)
		local values = { 50, 70, 52, 74, 55, 60, 72, 58, 75, 61 }
		for i, v in ipairs(values) do pull:at(0.2 + i * 0.2):threat("boss", "player", { raw = 500 + i, scaled = v }) end
		pull:to(2.3)
		local me = row("player")
		falsy(me.stateReason == "predicted" and me.trendConfidence == "low")
	end)
end)

describe("QA-03 scenarios about states (SPEC-08)", function()
	it("tank stable: no state changes over 10 s", function()
		local pull = partyPull(40, 20)
		pull:to(1)
		local seen = recordChanges()
		for i = 1, 20 do pull:at(1 + i * 0.5):add("boss", "tank", 50):add("boss", "player", 20) end
		pull:finish()
		eq(#seen, 0)
		eq(state("party1"), "SAFE")
	end)

	it("DPS nearing the threshold: SAFE, WARNING, DANGER, then the aggro", function()
		local pull = partyPull(40, 20)
		pull:to(0.5)
		local seen = recordChanges()
		pull:at(1):threat("boss", "player", { raw = 500, scaled = 82 })
		pull:at(2):threat("boss", "player", { raw = 501, scaled = 96 })
		pull:at(3):aggro("boss", "player")
		pull:to(4)
		deepEq(changesOf(seen, "player"), { "SAFE>WARNING", "WARNING>DANGER" })
		eq(select(2, state("player")), "aggro")
		eq(state("party1"), "DANGER")
		eq(select(2, state("party1")), "lost-aggro")
	end)

	it("taunt: the tank takes the mob back and the DPS falls after the dwell", function()
		local pull = partyPull(40, 20)
		pull:at(1):aggro("boss", "player")
		pull:to(1.5)
		eq(state("player"), "DANGER")
		pull:at(2):taunt("boss", "tank")
		pull:at(2.1):threat("boss", "player", { raw = 500, scaled = 50 })
		pull:to(2.5)
		eq(ST().tank, row("party1"))
		pull:to(4)
		eq(state("player"), "SAFE")
		notNil(state("party1"))
		falsy(select(2, state("party1")) == "lost-aggro")
	end)

	it("tank death: the tank leaves the list (new nil) and whoever takes the mob is DANGER", function()
		local pull = partyPull(40, 20)
		pull:to(1)
		local seen = recordChanges()
		pull:at(2):die("tank")
		pull:to(3)
		isNil(state("party1"))
		deepEq(changesOf(seen, "party1"), { "SAFE>nil" })
		eq(state("player"), "DANGER", "the most threat left takes the mob")
		eq(select(2, state("player")), "aggro")
	end)

	it("DPS death: its row leaves the list, once", function()
		local pull = partyPull(40, 20)
		pull:to(1)
		local seen = recordChanges()
		pull:at(2):die("rogue")
		pull:to(3)
		deepEq(changesOf(seen, "party3"), { "SAFE>nil" })
	end)

	it("target change: the states start again for the new mob, without an event for the old one", function()
		local pull = partyPull(85, 20)
		pull:threat("add", "tank", 800):threat("add", "player", { raw = 100, scaled = 10 })
		pull:to(1)
		eq(state("player"), "WARNING")
		local oldMob = TM().mobKey
		local seen = recordChanges()
		pull:at(1.5):token("target", "add"):event("PLAYER_TARGET_CHANGED")
		pull:to(2.5)
		local mob = TM().mobKey
		falsy(mob == oldMob)
		eq(state("player"), "SAFE", "no dwell: a new pair (unit, mob)")
		for _, c in ipairs(seen) do
			eq(c.mob, mob, "no event for the old mob")
			eq(c.old, "nil")
		end
	end)

	it("the end of the combat: every row becomes UNKNOWN stale after the dwell, without a scan", function()
		local pull = partyPull(40, 20)
		pull:at(2.3):call(function() Mock.combat.Leave() end)   -- the combat ends before the lists are read again
		pull:to(2.3)
		local scans = TS().scans
		pull:to(4)
		eq(TS().scans, scans, "the scanner stopped")
		pull:to(4)
		eq(state("player"), "UNKNOWN")
		eq(select(2, state("player")), "stale")
	end)

	it("the end of the combat soon after a change: the fall waits, then happens on the timer", function()
		local pull = partyPull(40, 20)
		pull:at(1.9):threat("boss", "player", { raw = 500, scaled = 97 })
		pull:at(2.2):stop()
		pull:to(2.5)
		eq(state("player"), "DANGER", "held")
		Mock.Advance(1)
		eq(state("player"), "UNKNOWN")
		eq(select(2, state("player")), "stale")
	end)
end)

describe("THREAT_MODE_CHANGED (MON-04)", function()
	it("is emitted at every change of outcome, once", function()
		local seen = {}
		local pull = partyPull(40, 20)
		pull:to(1)
		eq(ST().mode, "values")
		Mock.ns.Bus.On("THREAT_MODE_CHANGED", function(mode, reason) seen[#seen + 1] = mode .. ":" .. tostring(reason) end)
		pull:at(2):outcome("state"):add("boss", "tank", 1)
		pull:at(4):outcome("none"):add("boss", "tank", 1)
		pull:at(6):outcome("values"):add("boss", "tank", 1)
		pull:to(7)
		deepEq(seen, { "state:secret", "none:secret", "values:nil" })
		eq(ST().mode, "values")
	end)
end)

describe("thresholds (SPEC-09 Q7, SPEC-02 §3.5)", function()
	it("uses DEFAULTS 80 / 95, hysteresis 3 and dwell 1 s", function()
		local D = ST().DEFAULTS
		eq(D.warning, 80)
		eq(D.danger, 95)
		eq(D.hysteresis, 3)
		eq(D.dwell, 1)
		local w, d = ST().Thresholds()
		eq(w, 80)
		eq(d, 95)
	end)

	it("reads the player's thresholds when they change, and refuses an invalid pair", function()
		local Config = Mock.ns.Config
		Config.db.account.settings.monitor = { warning = 70, danger = 90 }
		Mock.ns.Bus.Emit("CONFIG_CHANGED", "account.settings.monitor.warning")
		local w, d = ST().Thresholds()
		eq(w, 70)
		eq(d, 90)
		local pull = partyPull(72, 10)
		pull:to(1)
		eq(state("player"), "WARNING", "72 % over a warning at 70")
		Config.db.account.settings.monitor = { warning = 90, danger = 92 }
		Mock.ns.Bus.Emit("CONFIG_CHANGED", "account.settings.monitor.danger")
		w, d = ST().Thresholds()
		eq(w, 80, "danger below warning + 5: both defaults")
		eq(d, 95)
	end)
end)

describe("performance and the switch", function()
	it("allocates nothing per update with stable states (ARC-06)", function()
		local pull = partyPull(40, 20)
		pull:to(1)
		Mock.ns.Scheduler.Stop("threat")
		for _ = 1, 20 do ST().Update() end
		local grown = math.huge
		for _ = 1, 3 do   -- the smallest of three batches under 4 KB, as test_scanner and test_threat_model
			collectgarbage("collect")
			collectgarbage("stop")
			local before = collectgarbage("count")
			for _ = 1, 1000 do ST().Update() end
			grown = math.min(grown, collectgarbage("count") - before)
			collectgarbage("restart")
		end
		truthy(grown < 4, "grew by " .. grown .. " KB")
	end)

end)

describe("the monitor switch off", function()
	before_boot(function(M) M.features = { monitor = false } end)

	it("emits nothing", function()
		local seen = recordChanges()
		local pull = partyPull(97, 20)
		pull:to(2)
		eq(#seen, 0)
	end)
end)
