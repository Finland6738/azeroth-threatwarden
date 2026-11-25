-- Data/ThreatModel.lua (SPEC-02 §1–§2, SPEC-03 §1.5–§1.6, §2.5, ADR 0003) on fight scripts: the category and the
-- reason of every field in the three probe outcomes; a unit not on the list is absent, not unknown (MON-05); staleness
-- from the rate and the round robin, and at COMBAT_ENDED; the margin of a non tank and of the tank on the scanner's
-- reads; the trend and the time to overtake of a closing DPS, and their resets (new holder, new mob, new combat); the
-- pool reused and no allocation per update; no secret value kept; THREAT_UPDATED; the monitor switch off.
-- The numbers of the mock are assumptions until the M0 probe (Tests/mock/70_threat.lua).

before_boot(function(M) M.features = { monitor = true } end)

local function TM() return Mock.ns.ThreatModel end
local function TS() return Mock.ns.ThreatScanner end
local function row(token) return TM().RowOf(token) end

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

-- The tank (party1) holds the boss, the player (ranged, 130 %) and the rogue (110 %) follow, the healer is not on it.
local function partyPull(outcome)
	local pull = newPull()
	if outcome then pull:outcome(outcome) end
	pull:at(0):start():threat("boss", "tank", 1000):threat("boss", "player", 500):threat("boss", "rogue", 300)
	return pull
end

local function noSecrets(t, what)
	for k, v in pairs(t) do
		falsy(issecretvalue(v), what .. " field " .. tostring(k) .. " holds a secret")
	end
end

local FIELDS = { "scaledPercent", "rawPercent", "rawThreat", "isTanking", "situation", "leadPercent", "leadSituation",
	"margin", "trend", "overtakeIn" }

describe("categories and reasons in the three probe outcomes (SPEC-03 §1.6, ADR 0003)", function()
	it("values: detected reads, a calculated margin, an estimated trend once there are samples", function()
		local pull = partyPull("values")
		pull:to(2)
		local me = row("player")
		eq(me.record.mode, "values")
		truthy(me.present)
		falsy(me.stale)
		isNil(me.reason)
		eq(me.record.source, "detected")
		eq(me.record.confidence, "high")
		for _, field in ipairs({ "scaledPercent", "rawPercent", "rawThreat", "isTanking", "situation" }) do
			eq(TM().Category(me, field), "detected", field)
			isNil(TM().Reason(me, field), field)
		end
		eq(TM().Category(me, "margin"), "calculated")
		near(me.margin, 100 - 500 / 1000 * 100 / 1.3, 1e-6)
		eq(TM().Category(me, "trend"), "estimated")
		near(me.trend, 0, 1e-9, "the threat did not move")
		eq(me.trendConfidence, "high")
		-- a flat trend predicts nothing: the reason says why
		eq(TM().Category(me, "overtakeIn"), "unknown")
		eq(TM().Reason(me, "overtakeIn"), "not-rising")
		-- the lead is read for the holder only
		eq(TM().Category(me, "leadPercent"), "unknown")
		eq(TM().Reason(me, "leadPercent"), "not-holder")
		local tank = row("party1")
		truthy(tank.isHolder)
		eq(TM().holder, tank)
		eq(TM().Category(tank, "leadSituation"), "detected")
		eq(TM().Reason(tank, "overtakeIn"), "holder")
		for _, field in ipairs(FIELDS) do
			notNil(TM().CATEGORY[field], field)
		end
	end)

	it("state: the game's state is detected, every number is unknown with its reason", function()
		local pull = partyPull("state")
		pull:to(2)
		local me = row("player")
		eq(me.record.mode, "state")
		truthy(me.present)
		eq(me.reason, "secret")
		eq(me.record.confidence, "high", "a fresh read of the state")
		eq(TM().Category(me, "situation"), "detected")
		for _, field in ipairs({ "scaledPercent", "rawPercent", "rawThreat" }) do
			eq(TM().Category(me, field), "unknown", field)
			eq(TM().Reason(me, field), "secret", field)
		end
		isNil(me.margin)
		eq(me.marginReason, "state-only")
		isNil(me.trend)
		eq(me.trendReason, "state-only")
		eq(me.trendConfidence, "unknown")
		isNil(me.overtakeIn)
		eq(TM().Reason(me, "margin"), "state-only")
		eq(me.samples.count, 0, "no sample from a state read")
		local tank = row("party1")
		truthy(tank.isHolder)
		isNil(tank.margin)
		eq(tank.marginReason, "state-only")
	end)

	it("none: nothing is known, every field says why", function()
		local pull = partyPull("none")
		pull:to(2)
		local me = row("player")
		eq(me.record.mode, "none")
		truthy(me.present, "a secret row is unknown, not absent")
		eq(me.reason, "secret")
		eq(me.record.source, "unknown")
		eq(me.record.confidence, "unknown")
		for _, field in ipairs(FIELDS) do
			eq(TM().Category(me, field), "unknown", field)
			notNil(TM().Reason(me, field), field)
		end
		eq(TM().Reason(me, "margin"), "secret")
		eq(TM().Reason(me, "trend"), "secret")
		isNil(TM().holder, "no one can be seen holding the mob")
	end)

	for _, outcome in ipairs(Fight.OUTCOMES) do
		it("keeps no secret value in rows or records (" .. outcome .. ", DAT-13)", function()
			local pull = partyPull(outcome)
			pull:to(2)
			for i = 1, TM().count do
				local r = TM().rows[i]
				noSecrets(r, "row")
				noSecrets(r.record, "record")
				noSecrets(r.samples.p, "sample")
			end
			eq(#Mock.errors, 0)
		end)
	end

	it("leaves a unit that is not on the list absent, not unknown (MON-05)", function()
		local pull = partyPull()
		pull:to(1)
		local healer = row("party2")
		falsy(healer.present)
		eq(healer.reason, "nil")
		eq(healer.record.confidence, "unknown")
		eq(healer.marginReason, "nil")
	end)

	it("keeps each row in its own mode (MON-04) [probe P3, P5]", function()
		local pull = partyPull()
		pull:secrets{ values = function(unit) return unit ~= "player" end }
		pull:to(2)
		eq(row("player").record.mode, "values")
		notNil(row("player").margin)
		notNil(row("player").trend)
		eq(row("party3").record.mode, "state")
		eq(row("party3").marginReason, "state-only")
	end)
end)

describe("staleness (SPEC-03 §1.5, DAT-12)", function()
	it("turns a row stale after max(2 * I, 0.5 s) without a read", function()
		local pull = partyPull()
		pull:to(1)
		Mock.ns.Scheduler.Stop("threat")
		pull:silent(true)
		local at = row("player").record.observedAt
		Mock.Advance(0.5)
		TM().Update()
		falsy(row("player").stale, "0.5 s is still fresh at 5 Hz")
		Mock.Advance(0.05)
		TM().Update()
		local me = row("player")
		truthy(me.stale)
		eq(me.reason, "stale")
		eq(me.record.confidence, "low")
		eq(me.record.observedAt, at, "the last read is kept")
		eq(TM().Category(me, "scaledPercent"), "detected", "the last value stays, marked stale")
		isNil(me.margin)
		eq(me.marginReason, "stale")
		isNil(me.trend)
		eq(me.trendReason, "stale")
		eq(row("party1").marginReason, "stale")
	end)

	it("follows the round robin: a row read every sixth scan is fresh for 2.4 s", function()
		local members = { { key = "m1", role = "TANK" } }
		for i = 2, 39 do members[i] = { key = "m" .. i, class = "ROGUE", role = "DAMAGER" } end
		local pull = newPull{ raid = true, party = members }
		TS().DEFAULTS.maxUnits = 10
		pull:at(0):start():threat("boss", "m2", 1000):threat("boss", "player", 10)
		for i = 3, 39 do pull:threat("boss", "m" .. i, 5) end
		pull:to(3)
		local r9 = row("raid9")
		near(r9.record.interval, 6 / 5, 1e-9)
		Mock.ns.Scheduler.Stop("threat")
		pull:silent(true)
		local age = Mock.ns.Compat.Now() - r9.record.observedAt
		Mock.Advance(2.4 - age - 0.01)
		TM().Update()
		falsy(row("raid9").stale)
		truthy(row("player").stale, "the player is read every scan: 0.5 s")
		Mock.Advance(0.05)
		TM().Update()
		truthy(row("raid9").stale)
		TS().DEFAULTS.maxUnits = 40
	end)

	it("makes every row stale at COMBAT_ENDED and publishes it", function()
		local pull = partyPull()
		local updates = {}
		Mock.ns.Bus.On("THREAT_UPDATED", function(key) updates[#updates + 1] = key or "none" end)
		pull:at(2):stop()
		pull:to(1.9)
		notNil(row("player").trend)
		local n = #updates
		pull:to(2)
		truthy(#updates > n)
		local me = row("player")
		truthy(me.stale)
		eq(me.reason, "stale")
		isNil(me.trend)
		isNil(me.overtakeIn)
		eq(me.record.mode, "values", "the last reading stays")
	end)
end)

describe("the margin on the scanner's reads (SPEC-03 §2.2)", function()
	it("is 100 - p for a non tank and 100 - the second for the tank", function()
		local pull = partyPull()
		pull:to(1)
		local me, rogue, tank = row("player"), row("party3"), row("party1")
		local pMe, pRogue = 500 / 1000 * 100 / 1.3, 300 / 1000 * 100 / 1.1
		near(me.margin, 100 - pMe, 1e-6)
		near(rogue.margin, 100 - pRogue, 1e-6)
		near(tank.margin, 100 - pMe, 1e-6, "the player is the second")
		eq(TM().Category(tank, "margin"), "calculated")
	end)

	it("is unknown with 'alone' when no one else is on the list", function()
		local pull = newPull()
		pull:at(0):start():threat("boss", "player", 500)
		pull:to(1)
		local me = row("player")
		truthy(me.isHolder)
		isNil(me.margin)
		eq(me.marginReason, "alone")
	end)

	it("is unknown with the others' reason when no one else is readable", function()
		local pull = partyPull()
		pull:secrets{ values = function(unit) return unit ~= "party1" end }
		pull:to(1)
		local tank = row("party1")
		eq(tank.record.mode, "values")
		truthy(tank.isHolder)
		isNil(tank.margin)
		eq(tank.marginReason, "state-only")
	end)
end)

describe("trend and time to overtake on a fight (SPEC-03 §2.5)", function()
	-- The tank stays at 1000; the player (130 %) gains 100 raw per second from 400: p = (400 + 100 t) / 13.
	local function closing(pull, from, to)
		for i = math.floor(from * 20), math.floor(to * 20) do
			local t = i / 20
			pull:at(t):threat("boss", "player", 400 + 100 * t)
		end
	end

	it("follows a DPS closing on the tank", function()
		local pull = newPull()
		pull:at(0):start():threat("boss", "tank", 1000):threat("boss", "player", 400):threat("boss", "rogue", 100)
		closing(pull, 0, 4)
		pull:to(0.25)
		local me = row("player")
		isNil(me.trend, "fewer than 3 samples over 0.5 s")
		eq(me.trendReason, "insufficient")
		eq(TM().Reason(me, "overtakeIn"), "insufficient")
		pull:to(3)
		me = row("player")
		near(me.trend, 100 / 13, 0.5)
		eq(me.trendConfidence, "high")
		truthy(me.trendSamples >= 8)
		-- at 3 s p = 700 / 13 = 53.8: (100 - 53.8) / 7.7 = 6 s
		local p = me.record.scaledPercent
		eq(me.overtakeIn, math.ceil((100 - p) / me.trend - 1e-9))
		eq(TM().Category(me, "overtakeIn"), "predicted")
		truthy(me.overtakeIn >= 6 and me.overtakeIn <= 7)
		eq(row("party1").overtakeReason, "holder")
	end)

	it("starts the samples again when another unit holds the mob", function()
		local pull = newPull()
		pull:at(0):start():threat("boss", "tank", 1000):threat("boss", "player", 400):threat("boss", "rogue", 100)
		closing(pull, 0, 2)
		pull:at(2):taunt("boss", "rogue")
		pull:to(1.9)
		notNil(row("player").trend)
		pull:to(2.3)
		truthy(row("party3").isHolder)
		isNil(row("player").trend, "measured on another tank: Insufficient data again")
		eq(row("player").trendReason, "insufficient")
	end)

	it("starts again at a new mob and at a new combat", function()
		local pull = partyPull()
		pull:to(2)
		notNil(row("player").trend)
		local before = TM().mobKey
		pull:newGUID("boss")
		TS().Scan()
		Mock.Advance(0.25)
		ne(TM().mobKey, before)
		truthy(row("player").samples.count <= 2)
		isNil(row("player").trend)
		pull:to(4)
		notNil(row("player").trend)
		pull:stop()
		Mock.Advance(1)
		pull:start():threat("boss", "tank", 1000):threat("boss", "player", 500)
		Mock.Advance(0.25)
		isNil(row("player").trend, "a new combat")
	end)

	it("drops a row's samples when it leaves the list", function()
		local pull = partyPull()
		pull:at(2):drop("boss", "rogue")
		pull:to(1.9)
		truthy(row("party3").samples.count > 0)
		pull:to(2.3)
		falsy(row("party3").present)
		eq(row("party3").samples.count, 0)
	end)
end)

describe("the pool (DAT-11, ARC-06)", function()
	it("reuses its rows across scans and fights", function()
		local pull = partyPull()
		pull:to(1)
		local first, ring = row("player"), row("player").samples
		eq(TM().count, 4)
		pull:at(2):stop()
		pull:at(3):start():threat("boss", "tank", 1000):threat("boss", "player", 500)
		pull:to(4)
		eq(row("player"), first)
		eq(row("player").samples, ring)
	end)

	it("allocates nothing per update after the warm-up, in a raid of 40", function()
		local members = { { key = "m1", role = "TANK" } }
		for i = 2, 39 do members[i] = { key = "m" .. i, class = "ROGUE" } end
		local pull = newPull{ raid = true, party = members }
		pull:at(0):start():threat("boss", "m1", 1000)
		for i = 2, 39 do pull:threat("boss", "m" .. i, i * 10) end
		pull:threat("boss", "player", 600)
		pull:to(0.5)
		Mock.ns.Scheduler.Stop("threat")
		-- the mock client allocates for its own answers: constant stand-ins, so that only the addon is measured
		local mobGUID = UnitGUID("target")
		UnitExists = function() return true end
		UnitIsDead = function() return false end
		UnitGUID = function() return mobGUID end
		C_Secrets.ShouldUnitThreatStateBeSecret = function() return false end
		C_Secrets.ShouldUnitThreatValuesBeSecret = function() return false end
		local step = 0
		UnitDetailedThreatSituation = function(unit)
			if unit == "raid1" then return true, 3, 100, 100, 1000 end
			return false, 0, 40 + step % 10, 44, 440
		end
		UnitThreatPercentageOfLead = function() return 150 end
		UnitThreatLeadSituation = function() return 0 end
		for _ = 1, 60 do
			step = step + 1
			Mock.StepClock(0.2)
			TS().Scan()
		end
		collectgarbage("collect")
		collectgarbage("stop")
		local before = collectgarbage("count")
		-- 2000 updates: one small table per update would be about 80 KB; a single resize of the VM's own tables (seen
		-- once in a full run of the suite, never alone) stays under 4 KB
		for _ = 1, 2000 do
			step = step + 1
			Mock.StepClock(0.2)
			TS().Scan()
		end
		local grown = collectgarbage("count") - before
		collectgarbage("restart")
		truthy(grown < 4, "grew by " .. grown .. " KB")
		eq(TM().count, 40)
		notNil(row("player").trend)
		notNil(row("raid1").margin)
	end)
end)

describe("THREAT_UPDATED", function()
	it("follows every scan with the mob's key", function()
		local pull = partyPull()
		local keys = {}
		Mock.ns.Bus.On("THREAT_UPDATED", function(key) keys[#keys + 1] = key or "none" end)
		pull:to(1)
		truthy(#keys >= 5)
		eq(keys[#keys], "mob:" .. Mock.units.Get("boss").guid)
		eq(TM().mobKey, keys[#keys])
	end)
end)

describe("the monitor switch off", function()
	before_boot(function(M) M.features = { monitor = false } end)

	it("updates nothing and publishes nothing", function()
		local pull = partyPull()
		local seen = 0
		Mock.ns.Bus.On("THREAT_UPDATED", function() seen = seen + 1 end)
		pull:to(2)
		eq(seen, 0)
		eq(TM().updates, 0)
		eq(TM().count, 0)
	end)
end)
