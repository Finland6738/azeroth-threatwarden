-- Data/CoachRules.lua and Data/Coach.lua (SPEC-04 §2, §4.1, §5, §6 M3.3; COA-01-COA-05; ADR 0003, 0014) on fight
-- scripts: every rule of §2.2 fires on its condition and its role only, in `values` and in the `state` forms; the
-- priorities; the cooldowns and the return (COA-03); the numbers at most once a second; predictions only with medium or
-- high confidence; every line of §2.5 (state only, nothing readable, unknown tank, Insufficient data, not on the list);
-- no tip out of combat, without a mob or alone; the setting, the demo, the switch off, the text, /atw debug, no secret
-- value and no allocation per update. The numbers of the mock are assumptions until the M0 probe
-- (Tests/mock/70_threat.lua): where a number matters the script fixes the scaled % or the game's state.

before_boot(function(M) M.features = { monitor = true, coach = true } end)

local function CO() return Mock.ns.Coach end
local function TS() return Mock.ns.ThreatScanner end
local function keyOf(token) return TS().RecordOf(token).unitKey end

-- Every COACH_TIP from now on, copied (the tip is reused); false for COACH_TIP(nil).
local function record()
	local seen = {}
	Mock.ns.Bus.On("COACH_TIP", function(t)
		if t == nil then
			seen[#seen + 1] = false
			return
		end
		local copy = {}
		for k, v in pairs(t) do copy[k] = v end
		copy.args = { unpack(t.args, 1, t.nargs) }
		copy.reasonArgs = { unpack(t.reasonArgs, 1, t.nreason) }
		seen[#seen + 1] = copy
	end)
	return seen
end

-- "D5 D4 - A1": the rules of the recorded tips, "-" for no tip.
local function rules(seen)
	local out = {}
	for i, t in ipairs(seen) do out[i] = t and t.rule or "-" end
	return table.concat(out, " ")
end

-- The rule shown now, or "-".
local function now()
	local t = CO().Current()
	return t and t.rule or "-"
end

local function value(scaled, raw) return { raw = raw or 500, scaled = scaled } end

local function newPull(def)
	def = def or {}
	return Fight.new{
		player = def.player or { class = "MAGE", role = "DAMAGER", ranged = true },
		party = def.party or {
			{ key = "tank", role = "TANK" },
			{ key = "healer", class = "PRIEST", role = "HEALER" },
			{ key = "rogue", class = "ROGUE", role = "DAMAGER" },
		},
		mobs = def.mobs or { { key = "boss", tokens = { "target", "boss1" }, classification = "worldboss" } },
	}
end

-- The tank (party1) holds the boss; the player and the rogue at fixed scaled percentages.
local function dpsPull(me, outcome, role, raw)
	local pull = newPull{ player = { class = "MAGE", role = role or "DAMAGER", ranged = true } }
	if outcome then pull:outcome(outcome) end
	pull:at(0):start():threat("boss", "tank", 1000)
		:threat("boss", "player", value(me or 40, raw))
		:threat("boss", "rogue", value(20, 300))
	return pull
end

-- The player is the tank and holds the boss; the rogue at a fixed scaled percentage.
local function tankPull(rogue, outcome)
	local pull = newPull{
		player = { class = "WARRIOR", role = "TANK" },
		party = {
			{ key = "ot", class = "PALADIN", role = "DAMAGER" },
			{ key = "healer", class = "PRIEST", role = "HEALER" },
			{ key = "rogue", class = "ROGUE", role = "DAMAGER" },
		},
	}
	if outcome then pull:outcome(outcome) end
	pull:at(0):start():threat("boss", "player", 1000):threat("boss", "rogue", value(rogue or 40, 300))
	return pull
end

-- A steady rise of the player's scaled % from `from`, `perSecond` points a second, sampled every 0.2 s.
local function rise(pull, unit, from, perSecond, start, stop)
	local t = start
	while t <= stop + 1e-9 do
		pull:at(t):threat("boss", unit, value(from + (t - start) * perSecond))
		t = t + 0.2
	end
end

describe("the damage dealer (D1-D5, values)", function()
	it("says Insufficient data in the first instants, then that the tank has enough margin (D5)", function()
		local seen = record()
		local pull = dpsPull(40)
		pull:to(0.3)
		eq(now(), "A1")
		eq(seen[1].message, "COACH_INSUFFICIENT")
		eq(seen[1].reason, "WHY_INSUFFICIENT")
		eq(seen[1].category, false)
		eq(seen[1].confidence, false)
		pull:to(3)
		local t = CO().Current()
		eq(t.rule, "D5")
		eq(t.name, "safe")
		eq(t.role, "dps")
		eq(t.message, "COACH_SAFE")
		eq(t.reason, "COACH_WHY_P_SAFE")
		deepEq({ unpack(t.reasonArgs, 1, t.nreason) }, { 40 })
		eq(t.nargs, 0)
		eq(t.category, "estimated")
		eq(t.confidence, "high")
		eq(t.otherKey, false)
		eq(t.priority, 10)
		eq(t.mobKey, Mock.ns.ThreatModel.mobKey)
		falsy(t.demo)
		eq(#Mock.errors, 0)
	end)

	it("says the threshold is close (D4) with the % and the Warning threshold", function()
		local pull = dpsPull(85)
		pull:to(2)
		local t = CO().Current()
		eq(t.rule, "D4")
		eq(t.message, "COACH_WARNING")
		eq(t.reason, "COACH_WHY_P_WARNING")
		deepEq({ unpack(t.reasonArgs, 1, t.nreason) }, { 85, 80 })
		eq(t.category, "detected")
		eq(t.confidence, "high")
	end)

	for _, case in ipairs({ { "DAMAGER", "COACH_DANGER", "dps" }, { "HEALER", "COACH_DANGER_HEALER", "healer" } }) do
		it("says Danger (D2) with the % and the Danger threshold (" .. case[1] .. ")", function()
			local pull = dpsPull(97, nil, case[1])
			pull:to(2)
			local t = CO().Current()
			eq(t.rule, "D2")
			eq(t.role, case[3])
			eq(t.message, case[2])
			eq(t.reason, "COACH_WHY_P_DANGER")
			deepEq({ unpack(t.reasonArgs, 1, t.nreason) }, { 97, 95 })
			eq(t.category, "detected")
		end)
	end

	for _, case in ipairs({ { "DAMAGER", "COACH_AGGRO", "dps" }, { "HEALER", "COACH_AGGRO_HEALER", "healer" },
		{ "NONE", "COACH_AGGRO", "dps" } }) do
		it("says You have aggro (D1) over everything else (" .. case[1] .. ")", function()
			local pull = dpsPull(97, nil, case[1])
			pull:at(1):aggro("boss", "player")
			pull:to(2)
			local t = CO().Current()
			eq(t.rule, "D1", case[1])
			eq(t.message, case[2])
			eq(t.reason, "COACH_WHY_TOP")
			eq(t.role, case[3])
			eq(t.category, "detected")
		end)
	end

	it("predicts a rise (D3) only with a trusted trend, with the seconds and the confidence", function()
		local seen = record()
		local pull = dpsPull(40)
		rise(pull, "player", 40, 8, 0.2, 4)
		pull:to(4)
		local found = nil
		for _, t in ipairs(seen) do if t and t.rule == "D3" then found = t break end end
		notNil(found, rules(seen))
		eq(found.message, "COACH_RISING")
		eq(found.reason, "COACH_WHY_TREND")
		eq(found.category, "predicted")
		truthy(found.confidence == "medium" or found.confidence == "high", found.confidence)
		eq(#found.reasonArgs, 2)
		truthy(found.reasonArgs[1] == 95 or found.reasonArgs[1] == 100, "reach " .. found.reasonArgs[1])
		local secs = found.reasonArgs[2]
		truthy(secs >= 1 and secs <= 10 and secs == math.floor(secs), "seconds " .. secs)
		for _, t in ipairs(seen) do
			if t and t.category == "predicted" then truthy(t.confidence == "medium" or t.confidence == "high") end
		end
	end)

	it("uses the healer's words for a rise", function()
		local pull = dpsPull(40, nil, "HEALER")
		local seen = record()
		rise(pull, "player", 40, 8, 0.2, 4)
		pull:to(4)
		local found = nil
		for _, t in ipairs(seen) do if t and t.rule == "D3" then found = t break end end
		notNil(found, rules(seen))
		eq(found.message, "COACH_RISING_HEALER")
	end)

	it("never predicts with a low confidence: a jumpy rise gives no D3 and no reassurance", function()
		local seen = record()
		local pull = dpsPull(40)
		local jumps = { 30, 70, 31, 71, 30, 70, 32, 72, 30, 70, 31, 71, 32, 72, 30, 70 }
		for i, p in ipairs(jumps) do pull:at(0.2 * i):threat("boss", "player", value(p)) end
		pull:to(3.2)
		for _, t in ipairs(seen) do
			if t then
				truthy(t.rule ~= "D3" and t.rule ~= "D5", t.rule)
				if t.rule == "A1" then
					truthy(t.reason == "WHY_INSUFFICIENT" or t.reason == "WHY_LOW_CONFIDENCE", t.reason)
				end
			end
		end
		truthy(Mock.ns.ThreatModel.RowOf("player").trendConfidence ~= "high")
	end)

	it("gives no reassurance (D5) with a fast rise and no prediction", function()
		local pull = dpsPull(10)
		rise(pull, "player", 10, 3, 0.2, 3)
		pull:to(3)
		local row = Mock.ns.ThreatModel.RowOf("player")
		truthy(row.trend > 2, "the trend rises")
		isNil(row.overtakeIn, "more than 10 s away")
		eq(now(), "-", "the data is there: no tip, not Insufficient data")
	end)
end)

describe("the tank (T1-T7, values)", function()
	it("says the margin is enough (T7) with the second's % and the margin", function()
		local pull = tankPull(40)
		pull:to(2)
		local t = CO().Current()
		eq(t.rule, "T7")
		eq(t.role, "tank")
		eq(t.message, "COACH_TANK_SAFE")
		eq(t.reason, "COACH_WHY_MARGIN")
		deepEq({ unpack(t.reasonArgs, 1, t.nreason) }, { 40, 60 })
		eq(t.category, "calculated")
		eq(t.confidence, "high")
	end)

	it("says the margin shrinks (T5) and that the second is very close (T3), naming the second", function()
		local pull = tankPull(85)
		pull:to(2)
		local t = CO().Current()
		eq(t.rule, "T5")
		eq(t.reason, "COACH_WHY_SECOND_W")
		eq(t.otherKey, keyOf("party3"))
		deepEq({ unpack(t.reasonArgs, 1, t.nreason) }, { 85, 80 })
		pull:at(3):threat("boss", "rogue", value(97, 300))
		pull:to(4)
		t = CO().Current()
		eq(t.rule, "T3")
		eq(t.message, "COACH_TANK_DANGER")
		eq(t.reason, "COACH_WHY_SECOND")
		eq(t.otherKey, keyOf("party3"))
		deepEq({ unpack(t.reasonArgs, 1, t.nreason) }, { 97, 95 })
		eq(t.category, "calculated")
	end)

	it("says someone has more threat (T2)", function()
		local pull = tankPull(40)
		pull:at(1):threat("boss", "player", { raw = 1000, status = 2 })
		pull:to(2)
		local t = CO().Current()
		eq(t.rule, "T2")
		eq(t.message, "COACH_TANK_BEHIND")
		eq(t.reason, "COACH_WHY_BEHIND")
		eq(t.category, "detected")
	end)

	it("says who has the mob when it is lost (T1), never a dps rule", function()
		local pull = tankPull(40)
		pull:at(1):aggro("boss", "rogue")
		pull:to(2)
		local t = CO().Current()
		eq(t.rule, "T1")
		eq(t.message, "COACH_TANK_LOST")
		eq(t.reason, "COACH_WHY_HOLDER")
		eq(t.otherKey, keyOf("party3"))
		eq(t.category, "detected")
	end)

	it("says another tank has the mob (T6) and holds the dps rules off a designated tank", function()
		local pull = newPull{
			player = { class = "WARRIOR", role = "TANK" },
			party = { { key = "ot", class = "PALADIN", role = "TANK" }, { key = "rogue", class = "ROGUE" } },
		}
		pull:at(0):start():threat("boss", "ot", 1000):threat("boss", "player", { raw = 900, scaled = 90 })
			:threat("boss", "rogue", value(20, 100))
		pull:to(2)
		local t = CO().Current()
		eq(t.rule, "T6")
		eq(t.role, "tank")
		eq(t.message, "COACH_TANK_OTHER")
		eq(t.reason, "COACH_WHY_HOLDER_TANK")
		eq(t.otherKey, keyOf("party1"))
	end)

	it("predicts the second's overtake (T4) with its trend, only while it is trusted", function()
		local seen = record()
		local pull = tankPull(30)
		rise(pull, "rogue", 30, 6, 0.2, 4)
		pull:to(4)
		local found = nil
		for _, t in ipairs(seen) do if t and t.rule == "T4" then found = t break end end
		notNil(found, rules(seen))
		eq(found.message, "COACH_TANK_OVERTAKE")
		eq(found.reason, "COACH_WHY_TREND_OTHER")
		eq(found.otherKey, keyOf("party3"))
		eq(found.category, "predicted")
		truthy(found.confidence == "medium" or found.confidence == "high")
		truthy(found.args[1] >= 1 and found.args[1] <= 10)
		truthy(math.abs(found.reasonArgs[1] - 6) < 0.6, "trend " .. found.reasonArgs[1])
	end)

	it("treats the player holding with no designated tank as the tank", function()
		local pull = newPull{ player = { class = "MAGE", role = "NONE" },
			party = { { key = "friend", class = "ROGUE", role = "NONE" } } }
		pull:at(0):start():threat("boss", "player", 1000):threat("boss", "friend", value(30, 300))
		pull:to(2)
		eq(CO().Current().role, "tank")
		eq(now(), "T7")
	end)
end)

describe("the state forms (SPEC-04 §2.5, state only)", function()
	it("gives D5 and D4 in their state forms, never D2 or D3", function()
		local pull = dpsPull(40, "state")
		pull:to(2)
		local t = CO().Current()
		eq(t.rule, "D5")
		eq(t.message, "COACH_SAFE_STATE")
		eq(t.reason, "COACH_WHY_STATE")
		eq(t.category, "detected")
		eq(t.confidence, "high")
		eq(t.nreason, 0)
		pull:at(3):threat("boss", "player", { raw = 1200, status = 1 })
		pull:to(4)
		t = CO().Current()
		eq(t.rule, "D4")
		eq(t.message, "COACH_WARNING_STATE")
		eq(t.reason, "COACH_WHY_STATE")
		eq(Mock.ns.Coach.stats.rules.D2, 0)
		eq(Mock.ns.Coach.stats.rules.D3, 0)
	end)

	it("gives the tank T7 from the game's lead, T5 and T3 in their state forms, and never T4", function()
		local pull = tankPull(40, "state")
		pull:to(2)
		local t = CO().Current()
		eq(t.rule, "T7")
		eq(t.reason, "COACH_WHY_LEAD")
		eq(t.category, "detected")
		eq(t.nreason, 0)
		pull:at(3):threat("boss", "player", { raw = 1000, leadStatus = 1 })
		pull:to(4)
		t = CO().Current()
		eq(t.rule, "T5")
		eq(t.reason, "COACH_WHY_STATE")
		eq(t.otherKey, false)
		pull:at(5):threat("boss", "player", { raw = 1000, leadStatus = 2 })
		pull:to(6)
		t = CO().Current()
		eq(t.rule, "T3")
		eq(t.message, "COACH_TANK_DANGER_STATE")
		eq(t.reason, "COACH_WHY_STATE")
		eq(Mock.ns.Coach.stats.rules.T4, 0)
	end)

	it("uses the state forms when the player reads values but the second does not", function()
		local pull = tankPull(85)
		pull:secrets{ values = function(unit) return unit ~= "player" end }
		pull:at(1):threat("boss", "player", { raw = 1000, leadStatus = 1 })
		pull:to(2)
		local t = CO().Current()
		eq(t.rule, "T5")
		eq(t.reason, "COACH_WHY_STATE")
		eq(t.otherKey, false)
	end)

	it("keeps T2 in state only", function()
		local pull = tankPull(40, "state")
		pull:at(1):threat("boss", "player", { raw = 1000, status = 2 })
		pull:to(2)
		eq(now(), "T2")
	end)

	it("keeps T1 in state only", function()
		local pull = tankPull(40, "state")
		pull:at(1):aggro("boss", "rogue")
		pull:to(2)
		eq(now(), "T1")
	end)
end)

describe("not enough data (A1, SPEC-04 §2.5)", function()
	for _, role in ipairs({ "dps", "tank" }) do
		it("says Not enough data with the row's reason when nothing is readable (" .. role .. ")", function()
			local pull = role == "dps" and dpsPull(97, "none") or tankPull(97, "none")
			pull:at(1):aggro("boss", "player")
			pull:to(3)
			local t = CO().Current()
			eq(t.rule, "A1")
			eq(t.message, "COACH_INSUFFICIENT")
			eq(t.reason, "WHY_SECRET")
			eq(t.category, false)
			eq(t.confidence, false)
			eq(t.nargs + t.nreason, 0)
		end)
	end

	it("says the row is stale when the reads stop", function()
		local pull = dpsPull(40)
		pull:to(3)
		eq(now(), "D5")
		pull:secrets{ state = function(unit) return unit == "player" end,
			values = function(unit) return unit == "player" end }
		pull:to(6)
		eq(now(), "A1")
		truthy(CO().Current().reason == "WHY_SECRET" or CO().Current().reason == "WHY_STALE_SHORT")
	end)

	it("says no one is known to hold the mob before reassuring, but still gives the threshold rules", function()
		local pull = dpsPull(40)
		pull:secrets{ values = function(unit) return unit == "party1" end,
			state = function(unit) return unit == "party1" end }
		pull:to(3)
		isNil(Mock.ns.ThreatState.tank, "Unknown tank")
		local t = CO().Current()
		eq(t.rule, "A1")
		eq(t.reason, "COACH_WHY_UNKNOWN_TANK")
		pull:at(4):threat("boss", "player", value(85))
		pull:to(14)
		eq(now(), "D4", "once the jump is out of the trend and the cooldowns are over")
	end)

	it("says no one is known to hold the mob to a designated tank who does not hold it", function()
		local pull = tankPull(40)
		pull:secrets{ values = function(unit) return unit == "party3" end,
			state = function(unit) return unit == "party3" end }
		pull:at(1):aggro("boss", "rogue")
		pull:to(3)
		eq(now(), "A1")
		eq(CO().Current().reason, "COACH_WHY_UNKNOWN_TANK")
	end)
end)

describe("when there is no tip", function()
	it("gives none out of combat, and says so once at the end of a fight", function()
		local seen = record()
		local pull = dpsPull(40)
		pull:to(3)
		eq(now(), "D5")
		pull:at(4):stop()
		pull:to(6)
		eq(now(), "-")
		eq(seen[#seen], false)
		local n = #seen
		pull:to(10)
		eq(#seen, n, "COACH_TIP(nil) once")
	end)

	it("gives none when the player is not on the list", function()
		local pull = newPull()
		pull:at(0):start():threat("boss", "tank", 1000):threat("boss", "rogue", value(30, 300))
		pull:to(3)
		eq(now(), "-")
		eq(CO().stats.evaluations, 0)
	end)

	it("gives none alone with your own mob, and speaks when someone else joins the list", function()
		local pull = Fight.new{ player = { class = "WARRIOR", role = "NONE" },
			mobs = { { key = "boss", tokens = { "target" } } } }
		pull:at(0):start():threat("boss", "player", 1000)
		pull:to(3)
		eq(now(), "-")
		Mock.units.Add("wolf", { class = "HUNTER" })
		Mock.units.SetToken("pet", "wolf")
		Mock.Fire("UNIT_PET", "player")
		pull:at(4):threat("boss", "wolf", value(30, 300))
		pull:to(6)
		eq(now(), "T7")
	end)

	it("gives none with the Coach off in the settings, and comes back when it is on", function()
		local seen = record()
		local pull = dpsPull(85)
		pull:to(2)
		eq(now(), "D4")
		truthy(Mock.ns.Config:Set("account.settings.coach.enabled", false))
		eq(now(), "-")
		eq(seen[#seen], false)
		falsy(CO().Enabled())
		pull:to(4)
		eq(now(), "-")
		truthy(Mock.ns.Config:Set("account.settings.coach.enabled", true))
		eq(now(), "D4")
	end)
end)

describe("choice, cooldowns and numbers (SPEC-04 §2.3, COA-03)", function()
	it("changes at once for a rule of higher priority, and back when it ends", function()
		local seen = record()
		local pull = dpsPull(85)
		pull:to(2)
		eq(now(), "D4")
		pull:at(3):threat("boss", "player", value(97))
		pull:to(3.5)
		eq(now(), "D2", "Danger at once")
		pull:at(4):threat("boss", "player", value(85))
		pull:to(6)
		eq(now(), "D4", "interrupted by Danger, a fact with no cooldown: D4 keeps none")
	end)

	-- In state only there is no trend: the states alone move the rules.
	it("does not bring back a rule with a cooldown before its cooldown", function()
		local pull = dpsPull(40, "state", nil, 1200)
		pull:to(2)
		eq(now(), "D4")
		pull:at(3):threat("boss", "player", 500)
		pull:to(5)
		eq(now(), "D5", "back to Safe after the dwell")
		local leftAt = CO().Current().since - (Mock.ns.Compat.Now() - pull.elapsed)   -- script time
		pull:at(6):threat("boss", "player", 1200)
		pull:to(7)
		eq(now(), "-", "D4 waits for its 8 s; D5 does not hold in Warning; the data is there")
		pull:to(leftAt + 7.5)
		eq(now(), "-")
		pull:to(leftAt + 8.5)
		eq(now(), "D4")
		truthy(CO().Current().since - (Mock.ns.Compat.Now() - pull.elapsed) - leftAt >= 8 - 1e-6)
	end)

	it("keeps the reassurances away for 15 s once they leave", function()
		local pull = tankPull(40, "state")
		pull:to(2)
		eq(now(), "T7")
		pull:at(3):threat("boss", "player", { raw = 1000, leadStatus = 1 })
		pull:to(4)
		eq(now(), "T5")
		local leftAt = CO().Current().since - (Mock.ns.Compat.Now() - pull.elapsed)   -- script time
		pull:at(5):threat("boss", "player", { raw = 1000, leadStatus = 0 })
		pull:to(7)
		eq(now(), "-", "T7 waits for 15 s, T5 does not hold")
		pull:to(leftAt + 14.5)
		eq(now(), "-")
		pull:to(leftAt + 15.5)
		eq(now(), "T7")
	end)

	it("changes the numbers of the same rule at most once a second", function()
		local seen = record()
		local pull = dpsPull(85)
		pull:to(2)
		eq(rules(seen), "D4")
		for i = 1, 10 do pull:at(2 + i * 0.2):threat("boss", "player", value(85 - (i % 2 == 0 and 0 or 1))) end
		pull:to(4.2)
		truthy(#seen <= 3, "tips: " .. #seen)
		for i = 2, #seen do
			eq(seen[i].rule, "D4")
			truthy(seen[i].reasonArgs[1] ~= seen[i - 1].reasonArgs[1])
		end
		local stamps = {}
		Mock.ns.Bus.On("COACH_TIP", function() stamps[#stamps + 1] = Mock.ns.Compat.Now() end)
		for i = 1, 20 do pull:at(5 + i * 0.2):threat("boss", "player", value(82 + i % 3)) end
		pull:to(9.2)
		for i = 2, #stamps do truthy(stamps[i] - stamps[i - 1] >= 1 - 1e-6) end
		truthy(#stamps >= 2, "the numbers do change")
	end)

	it("keeps its cooldowns into the next fight", function()
		local pull = dpsPull(40, "state")
		pull:at(1):threat("boss", "player", 1200)
		pull:to(2)
		eq(now(), "D4")
		pull:at(2.5):stop()
		pull:at(4):start():threat("boss", "tank", 1000):threat("boss", "player", 1200)
			:threat("boss", "rogue", value(20, 300))
		pull:to(5)
		eq(now(), "-", "D4 left the strip less than 8 s ago")
		pull:to(11)
		eq(now(), "D4")
	end)
end)

describe("never a secret, never a name (ADR 0003, SPEC-01 §3.3)", function()
	for _, outcome in ipairs(Fight.OUTCOMES) do
		it("keeps no secret value and no name in a tip (" .. outcome .. ")", function()
			local seen = record()
			local pull = tankPull(85, outcome)
			pull:at(2):aggro("boss", "rogue")
			pull:at(3):aggro("boss", "player")
			pull:to(5)
			truthy(#seen >= 1)
			for _, t in ipairs(seen) do
				if t then
					for k, v in pairs(t) do
						falsy(issecretvalue(v), tostring(k))
						falsy(type(v) == "string" and v:find("Testchar", 1, true), tostring(k))
					end
					for _, list in ipairs({ t.args, t.reasonArgs }) do
						for _, v in ipairs(list) do
							falsy(issecretvalue(v))
							eq(type(v), "number")
						end
					end
				end
			end
			eq(#Mock.errors, 0)
			eq(Mock.ns.Bus.errorCount, 0)
		end)
	end
end)

describe("the text of a tip (M3.4)", function()
	it("formats the message and the reason with the name, the numbers and the confidence word", function()
		local pull = tankPull(85)
		pull:to(2)
		local message, reason = CO().Text(CO().Current(), function() return "Rogue" end)
		eq(message, "Your margin is shrinking")
		eq(reason, "The second, Rogue, is at 85 % (Warning from 80 %).")
		message, reason = CO().Text(CO().Current())
		matches(reason, "^The second, .+, is at 85 %% %(Warning from 80 %%%)%.$")
		isNil(CO().Text(nil))
	end)

	it("puts the confidence word in the reason", function()
		local pull = dpsPull(40)
		pull:to(3)
		local message, reason = CO().Text(CO().Current())
		eq(message, "The tank has enough margin according to current data")
		eq(reason, "Your threat is 40 % and not rising fast (high confidence).")
		isNil(CO().Text(nil))
	end)

	it("speaks Italian on an Italian client, and says Unknown for a name it cannot find", function()
		truthy(Mock.ns.Config:Set("account.settings.language", "itIT"))
		Mock.Reload()
		local pull = tankPull(85)
		pull:to(2)
		local message, reason = CO().Text(CO().Current(), function() return nil end)
		eq(message, "Il tuo margine si sta riducendo")
		eq(reason, "Il secondo, Sconosciuto, è al 85 % (Attenzione dal 80 %).")
	end)
end)

describe("the demo (SPEC-03 §5.2)", function()
	it("gives its tips on the invented fight, marked as demo", function()
		local seen = record()
		truthy(Mock.ns.Demo.Start())
		for _ = 1, 100 do Mock.Advance(0.2) end
		truthy(#seen >= 1, "tips: " .. #seen)
		for _, t in ipairs(seen) do if t then truthy(t.demo, t.rule) end end
		Mock.ns.Demo.Stop()
		eq(#Mock.errors, 0)
		eq(Mock.ns.Bus.errorCount, 0)
	end)
end)

describe("/atw debug", function()
	it("has the Coach's lines in the Alerts and Coach section, without a name", function()
		local pull = dpsPull(85)
		pull:to(2)
		local text = Mock.ns.Diagnostics.Report()
		contains(text, "== Alerts and Coach ==")
		contains(text, "switches: alerts off, coach on")
		matches(text, "coach: enabled yes, tip D4 warning %(dps%), %d+ tip%(s%), %d+ cleared, %d+ evaluation%(s%)")
		matches(text, "coach rules shown: T1 0, T2 0, T3 0, T4 0, T5 0, T6 0, T7 0, D1 0, D2 0, D3 0, D4 1, D5 0, A1 %d+")
		falsy(table.concat(CO().DebugLines(), "\n"):find("Testchar", 1, true))
	end)
end)

describe("the work of an update (ARC-06)", function()
	it("allocates nothing after the warm-up", function()
		local pull = tankPull(85)
		pull:to(3)
		Mock.ns.Scheduler.Stop("threat")
		local Compat = Mock.ns.Compat
		local t = Compat.Now()
		Compat.Now = function() t = t + 0.6 return t end
		local me = Mock.ns.ThreatModel.RowOf("player")
		local states = { { "WARNING", nil }, { "DANGER", nil }, { "SAFE", nil }, { "DANGER", "behind" },
			{ "UNKNOWN", "secret" }, { "WARNING", "state-only" } }
		local function round()
			for _, s in ipairs(states) do
				me.state, me.stateReason = s[1], s[2]
				CO().Evaluate()
			end
		end
		for _ = 1, 20 do round() end
		local tips = CO().stats.tips
		local grown = math.huge
		for _ = 1, 3 do
			collectgarbage("collect")
			collectgarbage("stop")
			local before = collectgarbage("count")
			for _ = 1, 300 do round() end
			grown = math.min(grown, collectgarbage("count") - before)
			collectgarbage("restart")
		end
		truthy(CO().stats.tips > tips + 1000, "tips were really emitted")
		truthy(grown < 4, "grew by " .. grown .. " KB")
	end)
end)

describe("the coach switch off (ADR 0014)", function()
	before_boot(function(M) M.features = { monitor = true, coach = false } end)

	it("emits nothing and gives no tip, whatever happens", function()
		local seen = record()
		local pull = dpsPull(85)
		pull:at(2):aggro("boss", "player")
		pull:to(4)
		eq(#seen, 0)
		isNil(CO().Current())
		isNil(CO().Evaluate())
		eq(CO().stats.evaluations, 0)
		contains(table.concat(Mock.ns.Alerts.DebugLines(), "\n"), "switches: alerts off, coach off")
		eq(#Mock.errors, 0)
	end)
end)
