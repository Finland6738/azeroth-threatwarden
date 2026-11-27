-- Data/Alerts.lua (SPEC-04 §1, §6 M3.2, ALR-01-ALR-04, SPEC-09 Q12) on fight scripts: one alert per entry, none on a
-- fall or into UNKNOWN; every kind of §1.2 in `values` and `state`, none in `none`; one alert when the state and the
-- holder change together; bursts, oscillation, cooldowns across target changes and fights, the gaps between others
-- and between sounds; mute, exclusions, channels, the sound through Compat, never chat, the demo, the scanner
-- consumer, the switch off, no allocation per event. The numbers of the mock are assumptions until the M0 probe
-- (Tests/mock/70_threat.lua): where a number matters the script fixes the scaled % or the game's state.

-- recording off: the recorder is a scanner consumer of its own (test_recorder.lua)
before_boot(function(M) M.features = { monitor = true, alerts = true, coach = false, recording = false } end)

local P = "account.settings.alerts."

local function AL() return Mock.ns.Alerts end
local function TS() return Mock.ns.ThreatScanner end
local function keyOf(token) return TS().RecordOf(token).unitKey end
local function set(key, value) truthy(Mock.ns.Config:Set(P .. key, value), key) end

-- Every ALERT_RAISED from now on, copied (the table is reused).
local function record()
	local seen = {}
	Mock.ns.Bus.On("ALERT_RAISED", function(a)
		local copy = {}
		for k, v in pairs(a) do copy[k] = v end
		copy.number = a.args[1]
		seen[#seen + 1] = copy
	end)
	return seen
end

-- "kind/MESSAGE kind/MESSAGE ..." of the recorded alerts.
local function summary(seen)
	local out = {}
	for i, a in ipairs(seen) do out[i] = a.kind .. "/" .. a.message end
	return table.concat(out, " ")
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

local function value(scaled, raw) return { raw = raw or 500, scaled = scaled } end

-- The tank (party1) holds the boss; the player and the rogue at fixed scaled percentages.
local function dpsPull(me, rogue, outcome)
	local pull = newPull()
	if outcome then pull:outcome(outcome) end
	pull:at(0):start():threat("boss", "tank", 1000)
		:threat("boss", "player", value(me or 40))
		:threat("boss", "rogue", value(rogue or 20, 300))
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

-- A hunter alone with a pet (no role anywhere); the pet holds the boss.
local function petPull(def)
	local pull = Fight.new{
		player = { class = "HUNTER", role = (def and def.role) or "NONE", ranged = true },
		party = def and def.party,
		mobs = { { key = "boss", tokens = { "target" } } },
	}
	Mock.units.Add("wolf", { class = "HUNTER" })
	Mock.units.SetToken("pet", "wolf")
	Mock.Fire("UNIT_PET", "player")
	return pull
end

describe("the words by role (SPEC-09 Q7, the owner's decision of 2026-11-26)", function()
	-- The player at 85 % (Warning), then 97 % (Danger), under a tank holding the boss.
	local function climb(pull)
		pull:to(1)
		pull:at(2):threat("boss", "player", value(85))
		pull:to(5)
		pull:at(5.5):threat("boss", "player", value(97))
		pull:to(8)
	end

	it("tells a damage dealer to ease off at Warning and to stop damage at Danger", function()
		local seen = record()
		climb(dpsPull(40))
		eq(summary(seen), "warning/ALERT_WARNING danger/ALERT_DANGER")
		eq(AL().Text(seen[1]), "Threat 85 %: ease off, fewer casts or lower ranks")
		eq(AL().Text(seen[2]), "Threat 97 %: stop damage for a moment")
		eq(select(2, AL().Text(seen[1])), "Your threat passed the Warning threshold (82 %).")
		eq(select(2, AL().Text(seen[2])), "Your threat passed the Danger threshold (91 %).")
	end)

	it("tells a healer to ease off at Warning and to stop healing at Danger", function()
		local seen = record()
		local pull = newPull{
			player = { class = "PRIEST", role = "HEALER", ranged = true },
			party = {
				{ key = "tank", role = "TANK" },
				{ key = "mage", class = "MAGE", role = "DAMAGER" },
				{ key = "rogue", class = "ROGUE", role = "DAMAGER" },
			},
		}
		pull:at(0):start():threat("boss", "tank", 1000):threat("boss", "player", value(40))
			:threat("boss", "rogue", value(20, 300))
		climb(pull)
		eq(summary(seen), "warning/ALERT_WARNING danger/ALERT_DANGER_HEALER")
		eq(AL().Text(seen[2]), "Threat 97 %: stop healing for a moment")
		eq(select(2, AL().Text(seen[2])), "Your threat passed the Danger threshold (91 %).")
	end)

	it("never tells a tank to stop: a tank that does not hold the mob hears only how close it is", function()
		local seen = record()
		local pull = newPull{
			player = { class = "WARRIOR", role = "TANK" },
			party = {
				{ key = "tank", class = "PALADIN", role = "TANK" },
				{ key = "healer", class = "PRIEST", role = "HEALER" },
				{ key = "rogue", class = "ROGUE", role = "DAMAGER" },
			},
		}
		pull:at(0):start():threat("boss", "tank", 1000):threat("boss", "player", value(40))
			:threat("boss", "rogue", value(20, 300))
		climb(pull)
		eq(summary(seen), "warning/ALERT_WARNING_TANK danger/ALERT_DANGER_TANK")
		eq(AL().Text(seen[1]), "Threat 85 %: close to taking aggro")
		eq(AL().Text(seen[2]), "Threat 97 %: very close to taking aggro")
	end)

	it("keeps the tank's margin alerts on the second with the new thresholds", function()
		local seen = record()
		local pull = tankPull(40)
		pull:to(1)
		pull:at(2):threat("boss", "rogue", value(81, 300))
		pull:to(4)
		eq(#seen, 0, "81 % is below the Warning threshold of 82")
		pull:at(4.5):threat("boss", "rogue", value(84, 300))
		pull:to(6)
		eq(summary(seen), "margin/ALERT_MARGIN_WARNING")
		pull:at(14):threat("boss", "rogue", value(92, 300))   -- after the cooldown of `margin` (Q12)
		pull:to(16)
		eq(summary(seen), "margin/ALERT_MARGIN_WARNING margin/ALERT_MARGIN_DANGER")
	end)

	it("speaks Italian on an Italian client", function()
		truthy(Mock.ns.Config:Set("account.settings.language", "itIT"))
		Mock.Reload()
		local seen = record()
		climb(dpsPull(40))
		eq(AL().Text(seen[1]), "Threat 85 %: rallenta, meno lanci o rank più bassi")
		eq(AL().Text(seen[2]), "Threat 97 %: smetti di fare danni per un attimo")
	end)
end)

describe("one alert per entry (ALR-01)", function()
	it("says Warning once, Danger once, nothing on a fall, and again after the cooldown", function()
		local seen = record()
		local pull = dpsPull(40)
		pull:to(1)
		eq(#seen, 0, "SAFE is no alert")
		pull:at(2):threat("boss", "player", value(85))
		pull:to(5)
		eq(summary(seen), "warning/ALERT_WARNING")
		local a = seen[1]
		eq(a.severity, 1)
		eq(a.state, "WARNING")
		eq(a.subject, "self")
		eq(a.unitKey, keyOf("player"))
		isNil(a.otherKey)
		eq(a.mobKey, Mock.ns.ThreatModel.mobKey)
		eq(a.number, 85)
		eq(a.category, "detected")
		eq(a.confidence, "high")
		truthy(a.at >= 2)
		falsy(a.muted)
		falsy(a.demo)
		truthy(a.window)
		truthy(a.visual)
		falsy(a.sound, "the sound is off by default")
		eq(#Mock.sound.calls, 0)
		pull:at(5.5):threat("boss", "player", value(97))
		pull:to(8)
		eq(summary(seen), "warning/ALERT_WARNING danger/ALERT_DANGER")
		eq(seen[2].severity, 2)
		eq(seen[2].state, "DANGER")
		eq(seen[2].number, 97)
		-- falls: to Warning, then to Safe
		pull:at(9):threat("boss", "player", value(85))
		pull:at(12):threat("boss", "player", value(30))
		pull:to(20)
		eq(#seen, 2, "a fall never alerts")
		eq(Mock.ns.ThreatModel.RowOf("player").state, "SAFE")
		pull:at(21):threat("boss", "player", value(85))
		pull:to(22)
		eq(#seen, 3)
		eq(seen[3].message, "ALERT_WARNING")
	end)

	it("alerts when a unit enters the list already in Warning or Danger", function()
		local seen = record()
		local pull = dpsPull(96)
		pull:to(1)
		eq(summary(seen), "danger/ALERT_DANGER")
	end)

	it("says nothing into UNKNOWN, and comes back from it only above the last known state", function()
		local seen = record()
		local pull = dpsPull(85)
		pull:to(1)
		eq(#seen, 1)
		pull:at(2):outcome("none")
		pull:to(15)
		eq(Mock.ns.ThreatModel.RowOf("player").state, "UNKNOWN")
		eq(#seen, 1, "entering UNKNOWN never alerts")
		pull:at(16):outcome("values")
		pull:to(18)
		eq(Mock.ns.ThreatModel.RowOf("player").state, "WARNING")
		eq(#seen, 1, "the same state again after a gap")
		pull:at(19):outcome("none")
		pull:at(22):threat("boss", "player", value(30)):outcome("values")
		pull:to(25)
		eq(#seen, 1, "a lower state after a gap")
		pull:at(26):outcome("none")
		pull:at(29):threat("boss", "player", value(97)):outcome("values")
		pull:to(31)
		eq(summary(seen), "warning/ALERT_WARNING danger/ALERT_DANGER")
	end)

	it("alerts for the first known state of a unit that was UNKNOWN from the start", function()
		local seen = record()
		local pull = dpsPull(85, 20, "none")
		pull:to(3)
		eq(#seen, 0)
		pull:at(4):outcome("values")
		pull:to(5)
		eq(summary(seen), "warning/ALERT_WARNING")
	end)

	it("says nothing in the outcome `none`, whatever happens", function()
		set("others", "always")
		set("sound", true)
		local seen = record()
		local pull = dpsPull(40, 20, "none")
		pull:at(1):threat("boss", "player", value(97)):threat("boss", "rogue", value(99, 300))
		pull:at(3):aggro("boss", "player")
		pull:at(5):aggro("boss", "rogue")
		pull:to(20)
		eq(#seen, 0)
		eq(#Mock.sound.calls, 0)
		eq(#Mock.errors, 0)
	end)

	it("evaluates only in combat and only for the monitored mob", function()
		local seen = record()
		local pull = dpsPull(85)
		pull:to(1)
		local key, mob = keyOf("player"), Mock.ns.ThreatModel.mobKey
		set("cooldown", 3)
		pull:to(10)
		Mock.ns.Bus.Emit("STATE_CHANGED", key, "mob:other", "SAFE", "WARNING")
		eq(#seen, 1, "another mob")
		Mock.ns.Bus.Emit("STATE_CHANGED", key, mob, "SAFE", "WARNING")
		eq(#seen, 2, "the monitored one")
		pull:at(11):stop()
		pull:to(20)
		Mock.ns.Bus.Emit("STATE_CHANGED", key, mob, "SAFE", "WARNING")
		Mock.ns.Bus.Emit("AGGRO_CHANGED", mob, key, nil)
		eq(#seen, 2, "out of combat")
		eq(#Mock.errors, 0)
	end)
end)

describe("the kinds about the player (SPEC-04 §1.2)", function()
	it("predicts a Warning with the seconds and the confidence of the trend", function()
		local seen = record()
		local pull = dpsPull(40)
		for i = 0, 20 do
			pull:at(1 + i * 0.2):threat("boss", "player", value(50 + i * 1.6))
		end
		pull:to(6)
		truthy(#seen >= 1)
		local a = seen[1]
		eq(a.kind, "warning")
		eq(a.message, "ALERT_WARNING_PREDICTED")
		eq(a.category, "predicted")
		truthy(a.confidence == "medium" or a.confidence == "high", a.confidence)
		truthy(a.number >= 1 and a.number <= 3 and a.number == math.floor(a.number), "seconds: " .. tostring(a.number))
		eq(a.severity, 1)
		eq(a.reason, "predicted")
	end)

	it("in state only says the threat is above the tank's, and never a Danger by threshold", function()
		local seen = record()
		local pull = dpsPull(99, 20, "state")
		pull:to(2)
		eq(#seen, 0, "the percentages do not count")
		pull:at(3):threat("boss", "player", { raw = 500, status = 1 })
		pull:to(5)
		eq(summary(seen), "warning/ALERT_WARNING_STATE")
		isNil(seen[1].number)
		eq(seen[1].category, "detected")
	end)

	for _, outcome in ipairs({ "values", "state" }) do
		it("says You have aggro once when the mob turns to you (" .. outcome .. ")", function()
			local seen = record()
			local pull = dpsPull(40, 20, outcome)
			pull:at(2):aggro("boss", "player")
			pull:to(5)
			eq(summary(seen), "aggro/ALERT_AGGRO")
			local a = seen[1]
			eq(a.severity, 3)
			eq(a.state, "DANGER")
			eq(a.reason, "aggro")
			eq(a.subject, "self")
			eq(a.category, "detected")
		end)
	end

	it("says You have aggro when you are the first holder in a group with a tank", function()
		local seen = record()
		local pull = newPull()
		pull:at(0):start():threat("boss", "player", 1000):threat("boss", "tank", value(10, 100))
		pull:to(2)
		eq(summary(seen), "aggro/ALERT_AGGRO")
	end)

	it("does not wait for the cooldown of another kind", function()
		local seen = record()
		local pull = dpsPull(85)
		pull:at(2):aggro("boss", "player")
		pull:to(3)
		eq(summary(seen), "warning/ALERT_WARNING aggro/ALERT_AGGRO")
	end)

	it("alone with the pet: aggro only when the pet held the mob, and one alert for the transition", function()
		local seen = record()
		local pull = petPull()
		pull:at(0):start():threat("boss", "wolf", 1000):threat("boss", "player", value(30, 300))
		pull:to(1)
		eq(#seen, 0)
		-- the pet at 90 % of the player: the margin of the new holder would warn too
		pull:at(2):threat("boss", "wolf", { raw = 1000, scaled = 90 }):aggro("boss", "player")
		pull:to(4)
		eq(summary(seen), "aggro/ALERT_AGGRO")
		eq(Mock.ns.ThreatModel.RowOf("player").state, "DANGER", "the margin state still shows: the pet has more threat")
	end)

	it("alone: pulling your own mob is no aggro", function()
		local seen = record()
		local pull = petPull()
		pull:at(0):start():threat("boss", "player", 1000):threat("boss", "wolf", value(30, 300))
		pull:to(3)
		eq(#seen, 0)
	end)

	it("warns the tank of a shrinking margin with the second and its %, then of Danger after the cooldown", function()
		local seen = record()
		local pull = tankPull(40)
		pull:to(1)
		eq(#seen, 0)
		pull:at(2):threat("boss", "rogue", value(85, 300))
		pull:to(4)
		eq(summary(seen), "margin/ALERT_MARGIN_WARNING")
		eq(seen[1].otherKey, keyOf("party3"))
		eq(seen[1].number, 85)
		eq(seen[1].category, "calculated")
		eq(seen[1].severity, 1)
		eq(seen[1].subject, "self")
		eq(seen[1].unitKey, keyOf("player"))
		pull:at(11):threat("boss", "rogue", value(97, 300))
		pull:to(13)
		eq(summary(seen), "margin/ALERT_MARGIN_WARNING margin/ALERT_MARGIN_DANGER")
		eq(seen[2].otherKey, keyOf("party3"))
		isNil(seen[2].number)
		eq(seen[2].severity, 2)
	end)

	it("keeps one cooldown for the margin kind: the second's own Danger speaks then", function()
		local seen = record()
		local pull = tankPull(85)
		pull:at(3):threat("boss", "rogue", value(97, 300))
		pull:to(4)
		eq(summary(seen), "margin/ALERT_MARGIN_WARNING other/ALERT_OTHER_DANGER")
		eq(AL().stats.cooled, 1)
	end)

	it("gives the tank one alert when the second reaches Danger, and one for another unit that does", function()
		local seen = record()
		local pull = tankPull(40)
		pull:at(0.5):threat("boss", "healer", value(30, 200))
		pull:at(2):threat("boss", "rogue", value(98, 300))
		pull:to(4)
		eq(summary(seen), "margin/ALERT_MARGIN_DANGER", "not a second alert about the same unit")
		pull:at(6):threat("boss", "healer", value(96, 200))
		pull:to(7)
		eq(summary(seen), "margin/ALERT_MARGIN_DANGER other/ALERT_OTHER_DANGER")
		eq(seen[2].unitKey, keyOf("party2"))
	end)

	for _, outcome in ipairs({ "values", "state" }) do
		it("says someone has more threat (situation 2, " .. outcome .. ")", function()
			local seen = record()
			local pull = tankPull(40, outcome)
			pull:at(2):threat("boss", "player", { raw = 1000, status = 2 })
			pull:to(4)
			eq(summary(seen), "margin/ALERT_BEHIND")
			eq(seen[1].severity, 2)
			eq(seen[1].category, "detected")
		end)
	end

	local lead = { { 1, "ALERT_MARGIN_WARNING_STATE", 1 }, { 2, "ALERT_MARGIN_DANGER_STATE", 2 },
		{ 3, "ALERT_MARGIN_DANGER_STATE", 2 } }
	for _, case in ipairs(lead) do
		it("takes the margin from the game's lead " .. case[1] .. " in state only", function()
			local seen = record()
			local pull = tankPull(40, "state")
			pull:at(2):threat("boss", "player", { raw = 1000, leadStatus = case[1] })
			pull:to(4)
			eq(summary(seen), "margin/" .. case[2])
			eq(seen[1].severity, case[3])
			isNil(seen[1].otherKey)
			isNil(seen[1].number)
			eq(seen[1].category, "detected")
		end)
	end

	it("uses the state form when no other row is in values", function()
		local seen = record()
		local pull = tankPull(40)
		pull:secrets{ values = function(unit) return unit ~= "player" end }
		pull:at(2):threat("boss", "player", { raw = 1000, leadStatus = 1 })
		pull:to(4)
		eq(summary(seen), "margin/ALERT_MARGIN_WARNING_STATE")
	end)

	for _, outcome in ipairs({ "values", "state" }) do
		it("says who has the mob when the tank loses it, and nothing else (" .. outcome .. ")", function()
			local seen = record()
			local pull = tankPull(40, outcome)
			pull:at(2):aggro("boss", "rogue")
			pull:to(5)
			eq(summary(seen), "lost/ALERT_LOST")
			local a = seen[1]
			eq(a.severity, 3)
			eq(a.state, "DANGER")
			eq(a.reason, "lost-aggro")
			eq(a.subject, "self")
			eq(a.unitKey, keyOf("player"))
			eq(a.otherKey, keyOf("party3"))
		end)
	end

	it("says only that the mob is lost when your own pet takes it", function()
		local seen = record()
		local pull = petPull{ role = "TANK" }
		pull:at(0):start():threat("boss", "player", 1000):threat("boss", "wolf", value(30, 300))
		pull:at(2):aggro("boss", "wolf")
		pull:to(4)
		eq(summary(seen), "lost/ALERT_LOST")
		eq(seen[1].otherKey, keyOf("pet"))
	end)

	it("says nothing when two designated tanks swap", function()
		set("others", "always")
		local seen = record()
		local pull = newPull{
			player = { class = "WARRIOR", role = "TANK" },
			party = { { key = "ot", class = "PALADIN", role = "TANK" }, { key = "rogue", class = "ROGUE" } },
		}
		-- both at a low scaled % when not holding, so that no threshold is crossed
		pull:at(0):start():threat("boss", "player", { raw = 1000, scaled = 50 })
			:threat("boss", "ot", { raw = 600, scaled = 40 }):threat("boss", "rogue", value(20, 100))
		pull:at(2):aggro("boss", "ot")
		pull:at(5):aggro("boss", "player")
		pull:to(8)
		eq(summary(seen), "")
		eq(Mock.ns.ThreatState.aggroChanges >= 3, true, "the holder changed")
	end)

	it("says nothing about aggro while the holder is unknown, nor when it comes back the same", function()
		local seen = record()
		local pull = dpsPull(40)
		pull:at(1):aggro("boss", "player")
		pull:at(3):outcome("none")
		pull:at(15):outcome("values")
		pull:to(18)
		eq(summary(seen), "aggro/ALERT_AGGRO")
	end)
end)

describe("the pet and the others", function()
	local function petInParty()
		return petPull{ party = { { key = "tank", role = "TANK" } } }
	end

	for _, outcome in ipairs({ "values", "state" }) do
		it("says your pet has the mob, in a group with a tank (" .. outcome .. ")", function()
			local seen = record()
			local pull = petInParty()
			pull:outcome(outcome)
			pull:at(0):start():threat("boss", "tank", 1000):threat("boss", "wolf", value(30, 300))
				:threat("boss", "player", value(20, 200))
			pull:at(2):aggro("boss", "wolf")
			pull:to(4)
			eq(summary(seen), "pet/ALERT_PET")
			local a = seen[1]
			eq(a.severity, 2)
			eq(a.subject, "pet")
			eq(a.unitKey, keyOf("pet"))
			isNil(a.otherKey)
		end)
	end

	it("keeps quiet about the pet with the option off, and about a pet that reaches Danger", function()
		set("pet", false)
		set("others", "always")
		local seen = record()
		local pull = petInParty()
		pull:at(0):start():threat("boss", "tank", 1000):threat("boss", "wolf", value(97, 300))
		pull:at(2):aggro("boss", "wolf")
		pull:to(4)
		eq(summary(seen), "")
	end)

	it("without a designated tank says nothing about the pet", function()
		local seen = record()
		local pull = petPull()
		pull:at(0):start():threat("boss", "player", { raw = 1000, scaled = 10 })
			:threat("boss", "wolf", value(30, 300))
		pull:at(2):aggro("boss", "wolf")
		pull:to(4)
		eq(summary(seen), "")
	end)

	local cases = {
		{ others = "tank", role = "DAMAGER", expect = 0 },
		{ others = "tank", role = "TANK", expect = 1 },
		{ others = "always", role = "DAMAGER", expect = 1 },
		{ others = "never", role = "TANK", expect = 0 },
	}
	for _, case in ipairs(cases) do
		it(("others = %s, the player a %s: %d alert(s) when a DPS reaches Danger"):format(case.others, case.role,
			case.expect), function()
			set("others", case.others)
			local seen = record()
			local pull = newPull{
				player = { class = "WARRIOR", role = case.role },
				party = { { key = "tank", role = "TANK" }, { key = "rogue", class = "ROGUE", role = "DAMAGER" } },
			}
			pull:at(0):start():threat("boss", "tank", 1000):threat("boss", "rogue", value(40, 300))
			pull:at(2):threat("boss", "rogue", value(85, 300))
			pull:at(4):threat("boss", "rogue", value(97, 300))
			pull:to(6)
			eq(#seen, case.expect)
			if case.expect == 1 then
				local a = seen[1]
				eq(a.kind, "other")
				eq(a.message, "ALERT_OTHER_DANGER")
				eq(a.subject, "other")
				eq(a.unitKey, keyOf("party2"))
				eq(a.otherKey, keyOf("party2"))
				eq(a.severity, 2)
			end
		end)
	end

	for _, outcome in ipairs({ "values", "state" }) do
		it("says who took the mob from a tank, once (" .. outcome .. ")", function()
			set("others", "always")
			local seen = record()
			local pull = dpsPull(40, 20, outcome)
			pull:at(0.5):threat("boss", "player", value(40, 100))   -- below the new holder: nothing about the player
			pull:at(2):aggro("boss", "rogue")
			pull:to(5)
			eq(summary(seen), "other/ALERT_OTHER_AGGRO")
			local a = seen[1]
			eq(a.severity, 3)
			eq(a.unitKey, keyOf("party3"))
			eq(a.otherKey, keyOf("party3"))
		end)
	end

	it("says nothing about a holder who did not take the mob from a tank, or about another tank", function()
		set("others", "always")
		local seen = record()
		local pull = newPull{ party = {
			{ key = "mt", role = "TANK" }, { key = "ot", class = "PALADIN", role = "TANK" },
			{ key = "rogue", class = "ROGUE" }, { key = "healer", class = "PRIEST" },
		} }
		pull:at(0):start():threat("boss", "rogue", 1000):threat("boss", "mt", value(10, 100))
			:threat("boss", "ot", value(98, 200))
		pull:at(2):threat("boss", "healer", value(10, 100)):aggro("boss", "healer")
		pull:to(4)
		eq(summary(seen), "", "the rogue pulled; the healer took it from a DPS; the off tank is never a subject")
	end)
end)

describe("cooldowns, bursts and gaps (SPEC-04 §1.3)", function()
	it("keeps the same kind quiet after a target change, and lets a more severe kind through", function()
		local seen = record()
		local pull = dpsPull(85)
		pull:threat("add", "tank", 1000):threat("add", "player", value(85))
		pull:to(1)
		eq(#seen, 1)
		pull:at(2):target("player", "add")
		pull:to(3)
		eq(#seen, 1, "the same warning on the next mob")
		eq(AL().stats.cooled, 1)
		pull:at(3.5):threat("add", "player", value(97))
		pull:to(4)
		eq(summary(seen), "warning/ALERT_WARNING danger/ALERT_DANGER")
		pull:at(10):threat("boss", "player", value(85)):target("player", "boss")
		pull:to(11)
		eq(#seen, 3, "after the cooldown")
		eq(seen[3].message, "ALERT_WARNING")
	end)

	it("keeps the cooldown into the next fight", function()
		local seen = record()
		local pull = dpsPull(85)
		pull:to(1)
		pull:at(2):stop()
		pull:at(4):start():threat("boss", "tank", 1000):threat("boss", "player", value(85))
		pull:to(5)
		eq(#seen, 1)
		pull:at(6):stop()
		pull:at(20):start():threat("boss", "tank", 1000):threat("boss", "player", value(85))
		pull:to(21)
		eq(#seen, 2)
	end)

	it("follows the cooldown setting", function()
		set("cooldown", 3)
		local seen = record()
		local pull = dpsPull(85)
		pull:at(2):threat("boss", "player", value(40))
		pull:at(5):threat("boss", "player", value(85))
		pull:to(6)
		eq(#seen, 2)
		eq(AL().Cooldown(), 3)
	end)

	it("keeps an oscillation around the thresholds to one alert per kind and cooldown", function()
		local seen = record()
		local pull = dpsPull(40)
		for i = 0, 79 do
			local p = ({ 70, 85, 99, 85 })[i % 4 + 1]
			pull:at(1 + i * 0.6):threat("boss", "player", value(p))
		end
		pull:to(50)
		local count, last = { warning = 0, danger = 0 }, {}
		for _, a in ipairs(seen) do
			count[a.kind] = count[a.kind] + 1
			if last[a.kind] then truthy(a.at - last[a.kind] >= 8 - 1e-6, a.kind .. " after " .. (a.at - last[a.kind])) end
			last[a.kind] = a.at
		end
		truthy(count.warning >= 1 and count.warning <= 7, "warnings: " .. count.warning)
		truthy(count.danger >= 1 and count.danger <= 7, "dangers: " .. count.danger)
		truthy(AL().stats.cooled > 5)
	end)

	local function raidOfDps(n)
		local members = { { key = "tank", role = "TANK" } }
		for i = 1, n do members[#members + 1] = { key = "d" .. i, class = "ROGUE", role = "DAMAGER" } end
		local pull = newPull{ player = { class = "WARRIOR", role = "TANK" }, party = members, raid = true }
		pull:at(0):start():threat("boss", "tank", 1000)
		for i = 1, n do pull:at(0):threat("boss", "d" .. i, value(40, 100 + i)) end
		return pull
	end

	it("turns ten entries of others in a second into one alert", function()
		local seen = record()
		local pull = raidOfDps(10)
		pull:to(1)
		for i = 1, 10 do pull:at(2 + i * 0.08):threat("boss", "d" .. i, value(97, 100 + i)) end
		pull:to(6)
		eq(#seen, 1)
		eq(seen[1].kind, "other")
		eq(AL().stats.dropped, 9)
	end)

	it("lets an alert about another unit through every 3 seconds, never limiting your own", function()
		local seen = record()
		local pull = raidOfDps(3)
		pull:at(1):threat("boss", "d1", value(97, 101))
		pull:at(2):threat("boss", "d2", value(97, 102))
		pull:to(2.5)
		eq(#seen, 1, "the second one 1 s later is dropped")
		pull:at(4.5):threat("boss", "d3", value(97, 103))
		pull:to(5)
		eq(#seen, 2)
		pull:at(5.2):threat("boss", "player", value(97, 500))
		pull:to(6)
		eq(#seen, 3)
		eq(seen[3].kind, "danger", "your own alert is not limited")
	end)

	it("plays one sound every 3 seconds at most, never for a Warning", function()
		set("sound", true)
		local seen = record()
		local pull = dpsPull(40)
		pull:at(1):threat("boss", "player", value(85))
		pull:to(2)
		eq(#Mock.sound.calls, 0, "a Warning has no sound")
		falsy(seen[1].sound)
		pull:at(2.5):threat("boss", "player", value(97))
		pull:to(3)
		eq(#Mock.sound.calls, 1)
		eq(Mock.sound.calls[1].kit, AL().SOUND_KIT)
		eq(AL().SOUND_KIT, 8959)
		truthy(seen[2].sound)
		pull:at(3.5):aggro("boss", "player")
		pull:to(4)
		eq(seen[3].kind, "aggro")
		falsy(seen[3].sound, "1 s after the last sound: shown without it")
		truthy(seen[3].window)
		eq(#Mock.sound.calls, 1)
		pull:at(9):aggro("boss", "tank")
		pull:at(12):aggro("boss", "player")
		pull:to(13)
		eq(#Mock.sound.calls, 2)
		eq(AL().stats.sounds, 2)
	end)
end)

describe("channels and settings (SPEC-04 §1.4)", function()
	it("says which channels it used", function()
		set("window", false)
		set("visual", false)
		local seen = record()
		local pull = dpsPull(97)
		pull:to(1)
		eq(#seen, 1, "emitted with no channel: a recording may keep it")
		falsy(seen[1].window)
		falsy(seen[1].visual)
		falsy(seen[1].sound)
		falsy(seen[1].muted)
	end)

	it("emits nothing at all with the alerts off, and consumes no cooldown", function()
		set("enabled", false)
		set("sound", true)
		local seen = record()
		local pull = dpsPull(97)
		pull:to(2)
		eq(#seen, 0)
		eq(#Mock.sound.calls, 0)
		set("enabled", true)
		pull:at(3):threat("boss", "player", value(30))
		pull:at(5):threat("boss", "player", value(97))
		pull:to(6)
		eq(summary(seen), "danger/ALERT_DANGER")
	end)

	it("goes on without an error when the sound is missing or fails, and /atw debug says why", function()
		set("sound", true)
		Mock.sound.fail = true
		local seen = record()
		local pull = dpsPull(97)
		pull:to(1)
		eq(#seen, 1)
		falsy(seen[1].sound)
		eq(AL().stats.soundFailed, 1)
		contains(table.concat(AL().DebugLines(), "\n"), "1 failed (error)")
		boot(function(M)
			M.Remove("PlaySound")
			M.Remove("C_Sound.PlaySound")
		end)
		set("sound", true)
		seen = record()
		pull = dpsPull(97)
		pull:to(1)
		eq(#seen, 1)
		falsy(seen[1].sound)
		contains(table.concat(AL().DebugLines(), "\n"), "ui.PlaySound: missing")
		eq(#Mock.errors, 0)
	end)

	it("never writes to chat (ALR-02)", function()
		local sent = 0
		SendChatMessage = function() sent = sent + 1 end
		SendAddonMessage = function() sent = sent + 1 end
		set("sound", true)
		set("others", "always")
		local before = #Mock.output
		local seen = record()
		local pull = dpsPull(85)
		pull:at(2):threat("boss", "rogue", value(97, 300))
		pull:at(4):aggro("boss", "player")
		pull:at(6):aggro("boss", "rogue")
		pull:to(8)
		AL().ToggleMute()
		AL().ToggleMute()
		pull:at(9):stop()
		pull:to(10)
		truthy(#seen >= 3)
		eq(sent, 0)
		eq(#Mock.output, before, "not even a line in the player's own chat")
	end)
end)

describe("the mute (SPEC-04 §1.5)", function()
	local function mutes()
		local seen = {}
		Mock.ns.Bus.On("MUTE_CHANGED", function(on) seen[#seen + 1] = on end)
		return seen
	end

	it("silences every channel until the end of the fight; the alerts are still evaluated", function()
		set("sound", true)
		local seen, changes = record(), mutes()
		local pull = dpsPull(40)
		pull:to(1)
		eq(AL().ToggleMute(), "muted-fight")
		truthy(AL().IsMuted())
		pull:at(2):threat("boss", "player", value(97))
		pull:to(3)
		eq(#seen, 1)
		truthy(seen[1].muted)
		falsy(seen[1].window)
		falsy(seen[1].visual)
		falsy(seen[1].sound)
		eq(#Mock.sound.calls, 0)
		eq(AL().stats.muted, 1)
		-- the cooldown was consumed
		eq(AL().ToggleMute(), "unmuted")
		pull:at(4):threat("boss", "player", value(30))
		pull:at(6):threat("boss", "player", value(97))
		pull:to(7)
		eq(#seen, 1, "in the cooldown of the muted alert")
		eq(AL().ToggleMute(), "muted-fight")
		pull:at(8):stop()
		pull:to(9)
		falsy(AL().IsMuted())
		deepEq(changes, { true, false, true, false })
	end)

	it("out of combat lasts until the end of the next fight", function()
		local seen = record()
		eq(AL().ToggleMute(), "muted-next")
		local pull = dpsPull(97)
		pull:to(1)
		truthy(AL().IsMuted())
		truthy(seen[1].muted)
		pull:at(2):stop()
		pull:to(3)
		falsy(AL().IsMuted())
		pull:at(20):start():threat("boss", "tank", 1000):threat("boss", "player", value(97))
		pull:to(21)
		falsy(seen[#seen].muted)
	end)

	it("does not survive a /reload", function()
		AL().ToggleMute()
		Mock.Reload()
		falsy(AL().IsMuted())
	end)

	it("changes nothing while the alerts are off in the settings", function()
		set("enabled", false)
		local changes = mutes()
		eq(AL().ToggleMute(), "disabled")
		falsy(AL().IsMuted())
		eq(#changes, 0)
	end)
end)

describe("the exclusions of the session (SPEC-04 §1.5)", function()
	local function pullOfOthers()
		set("others", "always")
		local pull = dpsPull(40)
		pull:to(1)
		return pull
	end

	it("mute one unit until the /reload, by its key", function()
		local seen = record()
		local pull = pullOfOthers()
		local rogue = keyOf("party3")
		truthy(AL().Exclude(rogue, true))
		falsy(AL().Exclude(rogue, true), "already")
		truthy(AL().IsExcluded(rogue))
		pull:at(2):threat("boss", "rogue", value(97, 300))
		pull:at(4):aggro("boss", "rogue")
		pull:to(6)
		eq(summary(seen), "", "neither its Danger nor its aggro")
		truthy(AL().Exclude(rogue, false))
		falsy(AL().IsExcluded(rogue))
		pull:at(15):aggro("boss", "tank")
		pull:at(17):aggro("boss", "rogue")
		pull:to(18)
		eq(summary(seen), "other/ALERT_OTHER_AGGRO")
		AL().Exclude(rogue, true)
		Mock.Reload()
		falsy(AL().IsExcluded(rogue))
	end)

	it("covers the pet too, never the player, and saves no name", function()
		local pull = petPull{ party = { { key = "tank", role = "TANK" } } }
		pull:at(0):start():threat("boss", "tank", 1000):threat("boss", "wolf", value(30, 300))
		pull:to(1)
		falsy(AL().Exclude(keyOf("player"), true))
		falsy(AL().IsExcluded(keyOf("player")))
		falsy(AL().Exclude(nil, true))
		truthy(AL().Exclude(keyOf("pet"), true))
		local seen = record()
		pull:at(2):aggro("boss", "wolf")
		pull:to(3)
		eq(summary(seen), "")
		local saved = Mock.ns.Config.Copy(AzerothThreatwardenDB)
		deepEq(saved.settings.alerts, Mock.ns.Config.ALERTS_DEFAULTS)
	end)
end)

describe("the demo (SPEC-03 §5.2)", function()
	it("raises its alerts marked as demo, in the window only, never with a sound", function()
		local D = Mock.ns.Demo
		local seen = record()
		truthy(D.Start())
		set("sound", true)
		set("others", "always")
		for _ = 1, 200 do Mock.Advance(0.2) end
		truthy(#seen >= 2, "alerts: " .. #seen)
		for _, a in ipairs(seen) do
			truthy(a.demo, a.message)
			falsy(a.sound)
			truthy(a.window)
		end
		eq(#Mock.sound.calls, 0)
		D.Stop()
		eq(#Mock.errors, 0)
		eq(Mock.ns.Bus.errorCount, 0)
	end)
end)

describe("the scanner consumer (SPEC-04 §1.4)", function()
	it("reads with the window closed only while the sound is on and not muted", function()
		truthy(Mock.ns.Config:Set("account.settings.monitor.show", "manual"))
		Mock.ns.Window:Close()
		local seen = record()
		local pull = dpsPull(97)
		pull:to(2)
		falsy(TS().active, "sound off: the window is closed, nothing is read")
		eq(#seen, 0)
		set("sound", true)
		pull:to(3)
		truthy(TS().consumers.alerts)
		truthy(TS().active)
		eq(summary(seen), "danger/ALERT_DANGER")
		eq(#Mock.sound.calls, 1)
		AL().ToggleMute()
		falsy(TS().consumers.alerts)
		falsy(TS().active)
		AL().ToggleMute()
		truthy(TS().consumers.alerts)
		set("enabled", false)
		falsy(TS().consumers.alerts)
		set("enabled", true)
		set("sound", false)
		falsy(TS().consumers.alerts)
	end)

	it("wants the readings again after a /reload with the sound saved", function()
		set("sound", true)
		Mock.Reload()
		truthy(TS().consumers.alerts)
	end)
end)

describe("the messages and /atw debug", function()
	it("every message key exists in both languages", function()
		for _, code in ipairs({ "enUS", "itIT" }) do
			local strings = AzerothThreatwarden.Locale.Strings(code)
			for _, key in ipairs(AL().MESSAGES) do notNil(strings[key], code .. " " .. key) end
		end
	end)

	it("has a section with the switches, the settings and the counts, and no name", function()
		local pull = dpsPull(97)
		pull:to(1)
		local text = Mock.ns.Diagnostics.Report()
		contains(text, "== Alerts and Coach ==")
		contains(text, "switches: alerts on, coach off")
		contains(text, "settings: enabled yes, window yes, visual yes, sound no, cooldown 8 s, others tank, pet yes")
		contains(text, "raised: warning 0, danger 1, aggro 0, margin 0, lost 0, pet 0, other 0")
		contains(text, "in cooldown 0, dropped 0, muted 0")
		matches(text, "last alert: %d+%.%d s ago")
		contains(text, "ui.PlaySound: available, 0 sound(s), 0 failed")
		contains(text, "threat.WarningEnabled: available = true")
		falsy(table.concat(AL().DebugLines(), "\n"):find("Testchar", 1, true))
	end)
end)

describe("the work of an event (ARC-06)", function()
	it("allocates nothing after the warm-up", function()
		local pull = dpsPull(85, 20)
		pull:to(1)
		Mock.ns.Window:Close()   -- the work of the modules: the strip's texts are written only while it shows
		Mock.ns.Scheduler.Stop("threat")
		local Compat, Bus = Mock.ns.Compat, Mock.ns.Bus
		local now = Compat.Now()
		Compat.Now = function() now = now + 10 return now end
		local me, rogue, tank, mob = keyOf("player"), keyOf("party3"), keyOf("party1"), Mock.ns.ThreatModel.mobKey
		local function round()
			Bus.Emit("STATE_CHANGED", me, mob, "SAFE", "WARNING")
			Bus.Emit("STATE_CHANGED", me, mob, "WARNING", "UNKNOWN")
			Bus.Emit("STATE_CHANGED", me, mob, "UNKNOWN", "WARNING")
			Bus.Emit("STATE_CHANGED", rogue, mob, "SAFE", "SAFE")
			Bus.Emit("AGGRO_CHANGED", mob, me, tank)
		end
		for _ = 1, 20 do round() end
		local raised = AL().stats.raised.warning
		local grown = math.huge
		for _ = 1, 3 do
			collectgarbage("collect")
			collectgarbage("stop")
			local before = collectgarbage("count")
			for _ = 1, 500 do round() end
			grown = math.min(grown, collectgarbage("count") - before)
			collectgarbage("restart")
		end
		truthy(AL().stats.raised.warning > raised + 1000, "alerts were really raised")
		truthy(AL().stats.raised.aggro > 1000)
		truthy(grown < 4, "grew by " .. grown .. " KB")
	end)
end)

---------------------------------------------------------------------------------------------------------------------
-- The `mob` kind: alerts about the mobs of Data/MobTracker.lua other than the monitored one (SPEC-07 §2.5, M7.4)
---------------------------------------------------------------------------------------------------------------------
describe("the alerts about other mobs (SPEC-07 §2.5)", function()
	before_boot(function(M)
		M.features = { monitor = true, alerts = true, coach = false, recording = false, multitarget = true }
	end)

	local function MT() return Mock.ns.MobTracker end

	local PARTY = {
		{ key = "tank", class = "WARRIOR", role = "TANK" },
		{ key = "healer", class = "PRIEST", role = "HEALER" },
		{ key = "rogue", class = "ROGUE", role = "DAMAGER" },
		{ key = "hunter", class = "HUNTER", role = "DAMAGER" },
	}

	-- The monitored boss and two adds on nameplates, everything on the tank; the player and the others low. The window is
	-- closed, the tracker wanted by the test and its tick the test's own.
	local function mobPull(def)
		def = def or {}
		truthy(Mock.ns.Config:Set("account.settings.monitor.show", "manual"))
		Mock.ns.Window:Close()
		if def.onlyTarget ~= true then set("onlyTarget", false) end
		if def.others then set("others", def.others) end
		local pull = newPull{
			player = def.player or { class = "MAGE", role = "DAMAGER", ranged = true },
			party = def.party or PARTY,
			mobs = {
				{ key = "boss", tokens = { "target" } },
				{ key = "add1", tokens = { "nameplate1" } },
				{ key = "add2", tokens = { "nameplate2" } },
			},
		}
		if def.outcome then pull:outcome(def.outcome) end
		pull:at(0):start()
		for _, mob in ipairs({ "boss", "add1", "add2" }) do
			pull:threat(mob, def.holder or "tank", 1000)
			for _, unit in ipairs({ "player", "rogue", "healer" }) do
				if unit ~= (def.holder or "tank") then pull:threat(mob, unit, value(20, 200)) end
			end
		end
		pull:to(0)
		TS().Want("test", true)
		MT().Want("test", true)
		Mock.ns.Scheduler.Stop("mobs")
		return pull
	end

	-- `seconds` of fight (the monitor reads on its own), then a tick of the mobs.
	local function step(pull, seconds)
		pull:to(pull.elapsed + (seconds or 0.5))
		MT().Tick()
	end

	local function settle(pull)
		step(pull, 0.5)
		step(pull, 0.5)
	end

	-- Only the `mob` alerts of `seen`.
	local function mobs(seen)
		local out = {}
		for _, a in ipairs(seen) do
			if a.kind == "mob" then out[#out + 1] = a end
		end
		return out
	end

	local function said(seen)
		local out = {}
		for i, a in ipairs(mobs(seen)) do out[i] = a.message end
		return table.concat(out, " ")
	end

	local function mobKey(name) return "mob:" .. Mock.units.Get(name).guid end

	local function tankPlayer(def)
		def.player = { class = "WARRIOR", role = "TANK" }
		def.party = {
			{ key = "tank", class = "PALADIN", role = "TANK" },
			{ key = "healer", class = "PRIEST", role = "HEALER" },
			{ key = "rogue", class = "ROGUE", role = "DAMAGER" },
		}
		return def
	end

	for _, outcome in ipairs({ "values", "state" }) do
		it("says a mob is on someone who is not a tank, once per transition (" .. outcome .. ")", function()
			local seen = record()
			local pull = mobPull{ others = "always", outcome = outcome }
			settle(pull)
			eq(said(seen), "", "a safe pull says nothing")
			pull:aggro("add1", "rogue")
			settle(pull)
			eq(said(seen), "ALERT_MOB_AGGRO")
			local a = mobs(seen)[1]
			eq(a.severity, 3)
			eq(a.state, "DANGER")
			eq(a.reason, "aggro")
			eq(a.subject, "other")
			eq(a.mobKey, mobKey("add1"))
			eq(a.otherKey, keyOf("party3"))
			eq(a.unitKey, keyOf("party3"))
			eq(a.category, "detected")
			local text, why = AL().Text(a)
			eq(text, "A mob is on Rogue")
			eq(why, "Rogue is at the top of its threat list. The cause is not known.")
			for _ = 1, 30 do step(pull) end
			eq(said(seen), "ALERT_MOB_AGGRO", "the same transition does not come again, whatever the time")
			eq(#Mock.errors, 0)
			eq(Mock.ns.Bus.errorCount, 0)
		end)
	end

	it("says again after a fall and a new rise, once the cooldown is over", function()
		local seen = record()
		local pull = mobPull{ others = "always" }
		settle(pull)
		pull:aggro("add1", "rogue")
		settle(pull)
		pull:aggro("add1", "tank")
		step(pull, 2)
		step(pull)
		eq(said(seen), "ALERT_MOB_AGGRO", "a fall says nothing")
		pull:aggro("add1", "rogue")
		step(pull)
		eq(said(seen), "ALERT_MOB_AGGRO", "a rise inside the cooldown of the mob is not raised")
		truthy(AL().stats.cooled >= 1)
		pull:aggro("add1", "tank")
		step(pull, 9)
		step(pull)
		pull:aggro("add1", "rogue")
		step(pull)
		step(pull)
		eq(said(seen), "ALERT_MOB_AGGRO ALERT_MOB_AGGRO")
	end)

	it("says someone is about to pull a mob, and then that the mob is on them, but never a fall back", function()
		local seen = record()
		set("cooldown", 3)
		local pull = mobPull{ others = "always" }
		settle(pull)
		pull:threat("add1", "rogue", value(95, 900))
		settle(pull)
		eq(said(seen), "ALERT_MOB_CLOSE")
		local a = mobs(seen)[1]
		eq(a.severity, 2)
		eq(a.subject, "other")
		eq(a.otherKey, keyOf("party3"))
		eq(AL().Text(a), "Rogue is about to pull a mob")
		eq(select(2, AL().Text(a)), "From the threat of a mob you are not monitoring.")
		step(pull, 4)
		pull:aggro("add1", "rogue")
		settle(pull)
		eq(said(seen), "ALERT_MOB_CLOSE ALERT_MOB_AGGRO", "the condition rose")
		pull:aggro("add1", "tank")
		step(pull, 4)
		settle(pull)
		eq(said(seen), "ALERT_MOB_CLOSE ALERT_MOB_AGGRO", "back to close is a fall")
	end)

	it("says a mob is not on the tank, as a warning without a name and without a sound", function()
		set("sound", true)
		local seen = record()
		local pull = mobPull{ others = "always" }
		settle(pull)
		Mock.units.Add("stranger", { class = "ROGUE" })
		pull:drop("add1", "tank"):threat("add1", "stranger", 5000):aggro("add1", "stranger")
		step(pull, 2)
		step(pull)
		eq(said(seen), "ALERT_MOB_NO_TANK")
		local a = mobs(seen)[1]
		eq(a.severity, 1)
		eq(a.state, "WARNING")
		eq(a.reason, "no-tank")
		eq(a.category, "calculated")
		eq(a.otherKey, false)
		eq(a.unitKey, "")
		falsy(a.sound)
		eq(AL().Text(a), "A mob is not on the tank")
		eq(select(2, AL().Text(a)), "No tank is on the threat list of that mob.")
	end)

	it("tells the player who is close to pulling another mob, and not the others about it", function()
		local seen = record()
		local pull = mobPull{ others = "always" }
		settle(pull)
		pull:threat("add2", "player", value(95, 900))
		settle(pull)
		eq(said(seen), "ALERT_MOB_SELF", "one alert for the transition, the player first")
		local a = mobs(seen)[1]
		eq(a.subject, "self")
		eq(a.severity, 2)
		eq(a.reason, "self")
		eq(a.unitKey, keyOf("player"))
		eq(a.mobKey, mobKey("add2"))
		eq(AL().Text(a), "Your threat on another mob is very high")
		pull:aggro("add2", "player")
		settle(pull)
		eq(said(seen), "ALERT_MOB_SELF", "taking it is the same transition of the player, and no alert about oneself")
	end)

	it("tells the player on a loose mob once, with the sound of a Danger", function()
		set("sound", true)
		local seen = record()
		local pull = mobPull()   -- others = tank: a damage dealer hears only about itself
		settle(pull)
		pull:aggro("add1", "player")
		settle(pull)
		eq(said(seen), "ALERT_MOB_SELF")
		truthy(mobs(seen)[1].sound)
		eq(#Mock.sound.calls, 1)
	end)

	it("tells only a tank about the others by default (alerts.others)", function()
		local seen = record()
		local pull = mobPull()
		settle(pull)
		pull:aggro("add1", "rogue")
		pull:threat("add2", "rogue", value(95, 900))
		settle(pull)
		eq(said(seen), "", "a damage dealer hears nothing about others by default")
	end)

	it("tells a tank about the others by default, and never the tank about itself", function()
		local seen = record()
		local pull = mobPull(tankPlayer({}))
		settle(pull)
		pull:threat("add2", "player", value(95, 900))
		settle(pull)
		eq(said(seen), "", "a tank is not told that it is close to pulling")
		pull:aggro("add1", "rogue")
		step(pull, 4)
		settle(pull)
		eq(said(seen), "ALERT_MOB_AGGRO")
	end)

	it("says nothing about others with others = never, but still speaks to the player", function()
		local seen = record()
		local pull = mobPull{ others = "never" }
		settle(pull)
		pull:aggro("add1", "rogue")
		pull:threat("add2", "player", value(95, 900))
		settle(pull)
		eq(said(seen), "ALERT_MOB_SELF")
	end)

	it("never speaks of a tank about to pull a mob another tank holds", function()
		local seen = record()
		local pull = mobPull(tankPlayer({ others = "always" }))
		settle(pull)
		pull:threat("add1", "player", value(95, 900))
		settle(pull)
		eq(said(seen), "")
	end)

	it("keeps one cooldown per mob, and the gap between alerts about others: the worst speaks first", function()
		local seen = record()
		local pull = mobPull{ others = "always" }
		settle(pull)
		pull:threat("add1", "rogue", value(95, 900))   -- close on add1
		pull:aggro("add2", "healer")                    -- loose on add2: severity 3
		step(pull)
		eq(said(seen), "ALERT_MOB_AGGRO", "one alert about others every few seconds, the most severe first")
		eq(mobs(seen)[1].mobKey, mobKey("add2"))
		truthy(AL().stats.dropped >= 1)
		step(pull, 4)
		eq(said(seen), "ALERT_MOB_AGGRO", "the dropped one is not repeated: it did not enter again")
		pull:threat("add1", "rogue", value(20, 200))
		step(pull, 4)
		settle(pull)
		pull:threat("add1", "rogue", value(95, 900))
		step(pull)
		eq(said(seen), "ALERT_MOB_AGGRO ALERT_MOB_CLOSE", "another mob has its own cooldown")
	end)

	it("leaves out an excluded unit", function()
		local seen = record()
		local pull = mobPull{ others = "always" }
		settle(pull)
		truthy(AL().Exclude(keyOf("party3"), true))
		pull:aggro("add1", "rogue")
		settle(pull)
		pull:threat("add2", "rogue", value(95, 900))
		step(pull, 4)
		settle(pull)
		eq(said(seen), "")
		truthy(AL().Exclude(keyOf("party3"), false))
		pull:threat("add2", "rogue", value(20, 200))
		step(pull, 4)
		settle(pull)
		pull:threat("add2", "rogue", value(95, 900))
		settle(pull)
		eq(said(seen), "ALERT_MOB_CLOSE")
	end)

	it("says nothing about an unreadable mob, and comes back from UNKNOWN only above the last known condition", function()
		local seen = record()
		local pull = mobPull{ others = "always" }
		settle(pull)
		pull:threat("add1", "rogue", value(95, 900))
		settle(pull)
		eq(said(seen), "ALERT_MOB_CLOSE")
		pull:outcome("none")
		step(pull, 6)
		step(pull, 6)
		eq(said(seen), "ALERT_MOB_CLOSE", "UNKNOWN never alerts")
		pull:outcome("values")
		step(pull, 6)
		settle(pull)
		eq(said(seen), "ALERT_MOB_CLOSE", "the same condition is not new")
		pull:aggro("add1", "rogue")
		step(pull, 6)
		settle(pull)
		eq(said(seen), "ALERT_MOB_CLOSE ALERT_MOB_AGGRO")
	end)

	it("learns nothing from a mob that cannot be read but still shows its last state (the dwell)", function()
		local seen = record()
		set("cooldown", 3)
		local pull = mobPull()
		settle(pull)
		pull:aggro("add1", "player")
		settle(pull)
		eq(said(seen), "ALERT_MOB_SELF")
		pull:to(pull.elapsed + 5)
		local entry = MT().Get(mobKey("add1"))
		local mode, mine = entry.mode, entry.selfState
		eq(entry.state, "DANGER")
		entry.mode, entry.selfState = "none", nil   -- stale rows, the state kept (Data/MobRisk.lua)
		Mock.ns.Bus.Emit("MOBS_UPDATED")
		entry.mode, entry.selfState = mode, mine
		Mock.ns.Bus.Emit("MOBS_UPDATED")
		eq(said(seen), "ALERT_MOB_SELF", "the same condition is not new")
		eq(Mock.ns.Bus.errorCount, 0)
	end)

	it("says nothing about the mob that was the target when the player leaves it", function()
		local seen = record()
		local pull = mobPull{ others = "always" }
		settle(pull)
		pull:aggro("boss", "rogue")
		settle(pull)
		eq(said(seen), "", "the monitored mob has the alerts of the monitor")
		pull:target("player", "add1")
		settle(pull)
		step(pull, 2)
		settle(pull)
		eq(said(seen), "", "its condition was already known")
		eq(#Mock.errors, 0)
	end)

	it("is silenced by the mute, with no channel", function()
		set("sound", true)
		local seen = record()
		local pull = mobPull{ others = "always" }
		settle(pull)
		AL().ToggleMute()
		MT().Want("test", true)
		Mock.ns.Scheduler.Stop("mobs")
		pull:aggro("add1", "rogue")
		settle(pull)
		local a = mobs(seen)[1]
		eq(a.message, "ALERT_MOB_AGGRO")
		truthy(a.muted)
		falsy(a.window)
		falsy(a.visual)
		falsy(a.sound)
		eq(#Mock.sound.calls, 0)
	end)

	it("is never raised with alerts.onlyTarget on, and turning it off mid-fight repeats nothing", function()
		local seen = record()
		local pull = mobPull{ others = "always", onlyTarget = true }
		eq(Mock.ns.Config:Get(P .. "onlyTarget"), true)
		settle(pull)
		pull:aggro("add1", "rogue")
		pull:threat("add2", "player", value(95, 900))
		step(pull, 4)
		settle(pull)
		eq(said(seen), "")
		set("onlyTarget", false)
		step(pull, 4)
		settle(pull)
		eq(said(seen), "", "turning the setting on is not a transition")
		pull:aggro("add2", "healer")
		settle(pull)
		eq(said(seen), "ALERT_MOB_AGGRO")
		set("onlyTarget", true)
		pull:aggro("add1", "tank")
		step(pull, 4)
		pull:aggro("add1", "healer")
		settle(pull)
		eq(said(seen), "ALERT_MOB_AGGRO")
	end)

	it("says nothing while the alerts are off", function()
		local seen = record()
		local pull = mobPull{ others = "always" }
		set("enabled", false)
		settle(pull)
		pull:aggro("add1", "rogue")
		settle(pull)
		eq(said(seen), "")
	end)

	it("starts again with each fight", function()
		local seen = record()
		set("cooldown", 3)
		local pull = mobPull{ others = "always" }
		settle(pull)
		pull:aggro("add1", "rogue")
		settle(pull)
		pull:stop()
		pull:to(pull.elapsed + 5)
		pull:start()
		pull:threat("boss", "tank", 1000):threat("add1", "rogue", 1000)
		pull:to(pull.elapsed + 1)
		Mock.ns.Scheduler.Stop("mobs")
		settle(pull)
		eq(said(seen), "ALERT_MOB_AGGRO ALERT_MOB_AGGRO")
	end)

	it("never writes to chat and never opens the window (ALR-02, ALR-04)", function()
		local sent = 0
		SendChatMessage = function() sent = sent + 1 end
		SendAddonMessage = function() sent = sent + 1 end
		local before = #Mock.output
		local seen = record()
		local pull = mobPull{ others = "always" }
		settle(pull)
		pull:aggro("add1", "rogue")
		settle(pull)
		eq(said(seen), "ALERT_MOB_AGGRO")
		eq(sent, 0)
		eq(#Mock.output, before)
		falsy(Mock.ns.Window:IsShown())
	end)

	it("wants the other mobs only while it can speak of them with the window closed", function()
		truthy(Mock.ns.Config:Set("account.settings.monitor.show", "manual"))
		Mock.ns.Window:Close()
		falsy(MT().consumers.alerts)
		set("sound", true)
		falsy(MT().consumers.alerts, "only the target")
		set("onlyTarget", false)
		truthy(MT().consumers.alerts)
		AL().ToggleMute()
		falsy(MT().consumers.alerts)
		AL().ToggleMute()
		truthy(MT().consumers.alerts)
		set("sound", false)
		falsy(MT().consumers.alerts)
		set("sound", true)
		set("enabled", false)
		falsy(MT().consumers.alerts)
		set("enabled", true)
		set("onlyTarget", true)
		falsy(MT().consumers.alerts)
	end)

	it("alerts with the window closed and the sound on, through the tracker's own tick", function()
		truthy(Mock.ns.Config:Set("account.settings.monitor.show", "manual"))
		Mock.ns.Window:Close()
		set("sound", true)
		set("onlyTarget", false)
		set("others", "always")
		local seen = record()
		local pull = newPull{ mobs = { { key = "boss", tokens = { "target" } }, { key = "add1", tokens = { "nameplate1" } } } }
		pull:at(0):start():threat("boss", "tank", 1000):threat("add1", "tank", 1000)
			:threat("add1", "rogue", value(20, 200))
		pull:at(2):aggro("add1", "rogue")
		pull:to(5)
		truthy(MT().ticking)
		eq(said(seen), "ALERT_MOB_AGGRO")
		eq(#Mock.sound.calls, 1)
		pull:stop()
		pull:to(6)
		falsy(MT().ticking)
	end)

	it("says nothing in the demo", function()
		local seen = record()
		set("onlyTarget", false)
		set("others", "always")
		truthy(Mock.ns.Demo.Start())
		for _ = 1, 100 do Mock.Advance(0.2) end
		eq(said(seen), "")
		Mock.ns.Demo.Stop()
		eq(#Mock.errors, 0)
		eq(Mock.ns.Bus.errorCount, 0)
	end)

	it("speaks Italian on an Italian client", function()
		truthy(Mock.ns.Config:Set("account.settings.language", "itIT"))
		Mock.Reload()
		local seen = record()
		local pull = mobPull{ others = "always" }
		settle(pull)
		pull:aggro("add1", "rogue")
		settle(pull)
		eq(AL().Text(mobs(seen)[1]), "Un nemico è su Rogue")
	end)

	it("says in /atw debug how it listens and how many it raised, never a name", function()
		local pull = mobPull{ others = "always" }
		settle(pull)
		pull:aggro("add1", "rogue")
		settle(pull)
		local text = Mock.ns.Diagnostics.Report()
		contains(text, "other mobs: only target no, tracker wanted: no")
		contains(text, "other 0, mob 1")
		contains(text, "alerts about other mobs: on, 1 raised")
		falsy(table.concat(AL().DebugLines(), "\n"):find("Rogue", 1, true))
		falsy(AL().MobDebugLine():find("Rogue", 1, true))
	end)

	it("keeps no memory of the mobs that left", function()
		local pull = mobPull{ others = "always" }
		settle(pull)
		for i = 1, 40 do
			pull:newGUID("add1")
			pull:threat("add1", "tank", 1000):threat("add1", "rogue", value(20, 200))
			step(pull, 11)
			step(pull)
		end
		truthy(MT().count <= 4, "known mobs: " .. MT().count)
	end)
end)

describe("the alerts about other mobs with multitarget off (SPEC-07 §2.7)", function()
	before_boot(function(M)
		M.features = { monitor = true, alerts = true, coach = false, recording = false, multitarget = false }
	end)

	it("counts onlyTarget as on: no consumer, no alert, nothing about other mobs in /atw debug", function()
		set("onlyTarget", false)
		set("sound", true)
		set("others", "always")
		truthy(AL().OnlyTarget())
		local MT = Mock.ns.MobTracker
		falsy(MT.consumers.alerts)
		Mock.ns.Bus.Emit("MOBS_UPDATED")
		eq(AL().stats.raised.mob, 0)
		local text = Mock.ns.Diagnostics.Report()
		falsy(text:find("other mobs", 1, true))
		falsy(text:find("mob 0", 1, true))
		eq(#Mock.errors, 0)
		eq(Mock.ns.Bus.errorCount, 0)
	end)
end)

describe("the alerts switch off (ADR 0014)", function()
	before_boot(function(M)
		M.features = { monitor = true, alerts = false, coach = false, recording = false }
		M.saved = { AzerothThreatwardenDB = { schema = 3, settings = { alerts = { sound = true } } } }
	end)

	it("emits nothing, wants no reading, plays nothing", function()
		local seen = record()
		local pull = dpsPull(97)
		pull:at(2):aggro("boss", "player")
		pull:to(4)
		eq(#seen, 0)
		eq(#Mock.sound.calls, 0)
		falsy(TS().consumers.alerts)
		eq(AL().ToggleMute(), "off")
		falsy(AL().IsMuted())
		falsy(AL().Exclude(keyOf("party3"), true))
		truthy(Mock.ns.Config:Set("account.settings.monitor.show", "manual"))
		Mock.ns.Window:Close()
		pull:to(5)
		falsy(TS().active)
		contains(table.concat(AL().DebugLines(), "\n"), "switches: alerts off, coach off")
		eq(#Mock.errors, 0)
	end)

	it("leaves AGGRO_CHANGED to the monitor", function()
		local changes = 0
		Mock.ns.Bus.On("AGGRO_CHANGED", function() changes = changes + 1 end)
		local pull = dpsPull()
		pull:at(2):aggro("boss", "player")
		pull:to(3)
		eq(changes, 2)
	end)
end)
