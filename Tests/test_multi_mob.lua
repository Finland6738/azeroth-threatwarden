-- Data/MobTracker.lua (SPEC-07 §1.2-§1.7, §2.6, ADR 0019, M7.2): the sources with their events and the sweep, the
-- candidates, the keys and the three levels of identity, the same mob on several tokens once, a nameplate that changes
-- index, UnitTokenFromGUID, the slots and their priority, the budget and the rotation, the events that only move a mob
-- forward, the three outcomes per mob and the reasons of an unknown mob, the life cycle, the reach and the capability
-- otherMobs, the monitored mob's row from the monitor, the consumers, no allocation per tick, and nothing at all with the
-- switch or the setting off. Fight scripts: Tests/lib/fight.lua; the mock client has nameplates, focus, boss tokens,
-- UnitTokenFromGUID, CanCompareUnitTokens and secrets per pair.

before_boot(function(M) M.features = { monitor = true, multitarget = true, recording = false } end)

local function MT() return Mock.ns.MobTracker end
local function TT() return Mock.ns.TargetTracker end
local function keyOf(unit) return "mob:" .. Mock.units.Get(unit).guid end

local PARTY = {
	{ key = "tank", class = "WARRIOR", role = "TANK" },
	{ key = "rogue", class = "ROGUE", role = "DAMAGER" },
	{ key = "healer", class = "PRIEST", role = "HEALER" },
}

-- Nobody wants the tracker: the window (a consumer on the Monitor tab) closed and never opening by itself.
local function noWindow()
	truthy(Mock.ns.Config:Set("account.settings.monitor.show", "manual"))
	Mock.ns.Window:Close()
end

-- A pull: the player (a mage) with a tank, a rogue and a healer; the boss is the target unless the mobs say otherwise.
-- The window is closed, so that the tracker runs only when a test wants it (engage).
local function newPull(def)
	def = def or {}
	noWindow()
	return Fight.new{
		player = def.player or { class = "MAGE", role = "DAMAGER" },
		party = def.party or PARTY,
		raid = def.raid,
		mobs = def.mobs or {
			{ key = "boss", tokens = { "target" } },
			{ key = "add1", tokens = { "nameplate1" } },
			{ key = "add2", tokens = { "focus" } },
		},
	}
end

-- In combat with the tracker wanted; the scheduler's tick stopped so that every tick is the test's own.
local function engage(pull, wantScanner)
	pull:to(pull.elapsed)
	if wantScanner ~= false then Mock.ns.ThreatScanner.Want("test", true) end
	MT().Want("test", true)
	Mock.ns.Scheduler.Stop("mobs")
end

local function ticks(n)
	for _ = 1, n or 1 do MT().Tick() end
end

-- The listed entries by key.
local function listed()
	local out, list, n = {}, MT().List()
	for i = 1, n do out[list[i].key] = list[i] end
	return out, n
end

local function entryOf(unit) return MT().Get(keyOf(unit)) end

-- How many reads were made with each mob token while `fn` runs (the scanner's are made with "target"). Every
-- Compat.Threat.Read and ReadLead asks the prediction of the state first, whatever the outcome.
local function readsDuring(fn)
	local seen = {}
	local real = C_Secrets.ShouldUnitThreatStateBeSecret
	C_Secrets.ShouldUnitThreatStateBeSecret = function(unit, mob)
		if mob ~= nil then seen[mob] = (seen[mob] or 0) + 1 end
		return real(unit, mob)
	end
	fn()
	C_Secrets.ShouldUnitThreatStateBeSecret = real
	return seen
end

-- A standard fight: the tank holds every mob, the rogue is close on add1. `before(pull)` runs in combat, before the
-- tracker is wanted (its first tick runs at once): an outcome, a setting.
local function standard(before)
	local pull = newPull()
	pull:at(0):start()
		:threat("boss", "tank", 1000):threat("boss", "player", 300)
		:threat("add1", "tank", 500):threat("add1", "rogue", 480)
		:threat("add2", "tank", 400):threat("add2", "player", 100)
	pull:to(0)
	if before then before(pull) end
	engage(pull)
	return pull
end


describe("sources and discovery (SPEC-07 §1.2)", function()
	it("finds the mobs of the sweep, keyed by GUID like the TargetTracker, the monitored one first", function()
		standard()
		ticks(1)
		local mobs, n = listed()
		eq(n, 3)
		local list = MT().List()
		eq(list[1].key, keyOf("boss"), "the monitored mob first")
		eq(list[1].key, TT().MobKey(), "the same key as the TargetTracker")
		truthy(list[1].monitored)
		notNil(mobs[keyOf("add1")])
		notNil(mobs[keyOf("add2")])
		truthy(entryOf("add1").tokens.nameplate1)
		truthy(entryOf("add2").tokens.focus)
		eq(#Mock.errors, 0)
	end)

	it("follows the events of each source: nameplates, focus, boss, the members' targets", function()
		local pull = newPull{ mobs = { { key = "boss", tokens = { "target" } }, { key = "a" }, { key = "b" }, { key = "c" },
			{ key = "d" } } }
		pull:at(0):start()
		engage(pull)
		pull:token("nameplate7", "a")
		truthy(entryOf("a") and entryOf("a").tokens.nameplate7, "NAME_PLATE_UNIT_ADDED")
		pull:token("focus", "b")
		truthy(entryOf("b").tokens.focus, "PLAYER_FOCUS_CHANGED")
		pull:token("boss2", "c")
		truthy(entryOf("c").tokens.boss2, "INSTANCE_ENCOUNTER_ENGAGE_UNIT")
		pull:target("rogue", "d")
		truthy(entryOf("d").tokens.party2target, "UNIT_TARGET of a watched unit")
		pull:token("nameplate7", nil)
		falsy(entryOf("a").tokens.nameplate7, "NAME_PLATE_UNIT_REMOVED")
		local stats = MT().stats.events
		eq(stats.plate, 2)
		eq(stats.focus, 1)
		eq(stats.boss, 1)
		truthy(stats.group >= 1)
	end)

	it("the sweep finds a mob whose event never came, SWEEP tokens per tick", function()
		local pull = newPull{ mobs = { { key = "boss", tokens = { "target" } }, { key = "far", tokens = { "nameplate30" } } } }
		pull:at(0):start()
		engage(pull)
		eq(MT().SWEEP, 12)
		isNil(entryOf("far"), "not reached yet")
		ticks(3)
		notNil(entryOf("far"), "nameplate30 is reached on the third turn of the sweep")
	end)

	it("takes only candidates: hostile, alive and in combat (or with a secret combat flag)", function()
		local pull = newPull{ mobs = { { key = "boss", tokens = { "target" } }, { key = "dead", tokens = { "nameplate1" } },
			{ key = "idle", tokens = { "nameplate2" } }, { key = "odd", tokens = { "nameplate3" } } } }
		pull:at(0):start()
		pull:to(0)
		Mock.units.Get("dead").dead = true
		Mock.units.Get("idle").combat = false
		Mock.units.SetToken("nameplate4", "tank")   -- a friendly unit on a plate (a test's shortcut)
		local real = UnitAffectingCombat
		UnitAffectingCombat = function(unit)
			if unit == "nameplate3" then return Mock.Secret("boolean") end
			return real(unit)
		end
		engage(pull)
		ticks(1)
		isNil(entryOf("dead"))
		isNil(entryOf("idle"))
		isNil(MT().Get(keyOf("tank")))
		notNil(entryOf("odd"), "a secret combat flag lets the first read decide")
		UnitAffectingCombat = real
		eq(#Mock.errors, 0)
	end)
end)

describe("identity and keys (SPEC-07 §1.3)", function()
	it("lists a mob named by several tokens once, with all of them", function()
		local pull = newPull()
		pull:at(0):start():threat("add1", "tank", 100)
		engage(pull)
		pull:token("focus", "add1"):token("boss3", "add1"):target("tank", "add1")
		ticks(1)
		local e = entryOf("add1")
		truthy(e.tokens.nameplate1 and e.tokens.focus and e.tokens.boss3 and e.tokens.party1target)
		eq(e.tokenCount, 4)
		local count = 0
		for _, item in pairs(listed()) do if item.guid == Mock.units.Get("add1").guid then count = count + 1 end end
		eq(count, 1)
		eq(e.readToken, "focus", "read with the first of focus, boss, nameplate, group")
	end)

	it("keeps its mob when a nameplate changes index (REMOVED, then ADDED on another index)", function()
		local pull = standard()
		ticks(1)
		local e, key = entryOf("add1"), keyOf("add1")
		pull:token("nameplate1", nil)
		pull:token("nameplate9", "add1")
		eq(MT().Get(key), e, "the same entry")
		truthy(e.tokens.nameplate9)
		falsy(e.tokens.nameplate1)
		ticks(1)
		eq(listed()[key], e)
	end)

	it("finds a mob again with UnitTokenFromGUID when none of its tokens names it", function()
		local pull = standard()
		ticks(1)
		local e = entryOf("add1")
		pull:token("nameplate1", nil)
		Mock.units.SetToken("mouseover", "add1")   -- no event: only UnitTokenFromGUID knows
		eq(e.tokenCount, 0)
		ticks(3)
		eq(e.readToken, "mouseover")
		eq(e.source, "lookup")
		truthy(MT().stats.bySource.lookup.values > 0)
		eq(e.mode, "values")
	end)

	it("moves a token whose GUID changed to the new mob", function()
		local pull = standard()
		ticks(1)
		local old = entryOf("add1")
		local oldKey = old.key
		pull:newGUID("add1")
		ticks(5)
		local new = entryOf("add1")
		notNil(new)
		ne(new.key, oldKey)
		truthy(new.tokens.nameplate1)
		falsy(old.key == oldKey and old.tokens.nameplate1, "the old one lost the token")
	end)

	describe("without a readable GUID [probe P9]", function()
		it("keys focus and boss by token and counter when they can be compared; no plates, no members' targets", function()
			local pull = newPull{ mobs = { { key = "boss", tokens = { "target" } }, { key = "add1", tokens = { "nameplate1" } },
				{ key = "add2", tokens = { "focus" } }, { key = "add3", tokens = { "boss2" } } } }
			pull:at(0):start():threat("add2", "tank", 100):threat("add3", "tank", 100):threat("add1", "tank", 100)
			pull:secrets{ identity = true }
			engage(pull)
			ticks(1)
			local keys = {}
			for key in pairs(listed()) do keys[#keys + 1] = key end
			table.sort(keys)
			eq(#keys, 3, table.concat(keys, " "))
			matches(TT().MobKey(), "^tgt:")
			truthy(listed()["tok:focus:1"])
			truthy(listed()["tok:boss2:1"])
			eq(MT().identity, "compare")
			eq(Mock.ns.Compat.Capability("mobIdentity"), "restricted")
			eq(MT().Reach(), "focus-boss")
			eq(select(2, MT().Reach()), "no-guid")
			-- a new focus event makes a new key; the old mob without a GUID cannot be followed and leaves
			pull:token("focus", "add1")
			isNil(listed()["tok:focus:1"])
			ticks(1)
			truthy(listed()["tok:focus:2"])
			eq(#Mock.errors, 0)
		end)

		it("does not list a stable token that cannot be told apart from the monitored mob", function()
			local pull = newPull{ mobs = { { key = "boss", tokens = { "target" } }, { key = "add2", tokens = { "focus" } } } }
			pull:at(0):start():threat("add2", "tank", 100):threat("boss", "tank", 100)
			pull:secrets{ identity = true, comparison = function(a, b) return a == "target" or b == "target" end }
			engage(pull)
			ticks(1)
			local _, n = listed()
			eq(n, 1, "only the monitored mob")
		end)

		it("attaches a stable token that is the monitored mob to its entry instead of listing it twice", function()
			local pull = newPull{ mobs = { { key = "boss", tokens = { "target", "boss1" } } } }
			pull:at(0):start():threat("boss", "tank", 100)
			pull:secrets{ identity = true }
			engage(pull)
			ticks(1)
			local _, n = listed()
			eq(n, 1)
			truthy(MT().monitored.tokens.boss1)
		end)

		it("lists only the target when the comparison is refused too: reach target, no-compare", function()
			local pull = newPull()
			pull:at(0):start():threat("boss", "tank", 100):threat("add2", "tank", 100)
			pull:secrets{ identity = true, comparison = true }
			engage(pull)
			ticks(2)
			Mock.Advance(0.3)
			ticks(1)
			local _, n = listed()
			eq(n, 1)
			eq(MT().identity, "target")
			eq(MT().Reach(), "target")
			eq(select(2, MT().Reach()), "no-compare")
		end)
	end)
end)

describe("slots and priority (MT-02, SPEC-07 §1.6)", function()
	local function crowd(n, extra)
		local mobs = { { key = "boss", tokens = { "target" } } }
		for i = 1, n do mobs[#mobs + 1] = { key = "m" .. i, tokens = { "nameplate" .. i } } end
		for _, m in ipairs(extra or {}) do mobs[#mobs + 1] = m end
		local pull = newPull{ mobs = mobs }
		pull:at(0):start():threat("boss", "tank", 1000)
		for i = 1, n do pull:threat("m" .. i, "tank", 100 + i) end
		for _, m in ipairs(extra or {}) do pull:threat(m.key, "tank", 50) end
		return pull
	end

	it("give max places, the monitored mob included, the better sources first", function()
		local pull = crowd(5, { { key = "foc", tokens = { "focus" } } })
		truthy(Mock.ns.Config:Set("account.settings.mobs.max", 2))
		engage(pull)
		ticks(5)
		local mobs, n = listed()
		eq(n, 2)
		truthy(mobs[keyOf("boss")])
		truthy(mobs[keyOf("foc")], "focus before the nameplates")
		eq(MT().count, 7, "the others are known, without a place")
	end)

	it("go up to 12", function()
		local pull = crowd(14)
		truthy(Mock.ns.Config:Set("account.settings.mobs.max", 12))
		engage(pull)
		ticks(4)
		local _, n = listed()
		eq(n, 12)
		eq(MT().Max(), 12)
	end)

	it("a mob more members target comes first among the members' targets", function()
		local pull = newPull{ mobs = { { key = "boss", tokens = { "target" } }, { key = "x" }, { key = "y" } } }
		pull:at(0):start():threat("x", "tank", 100):threat("y", "tank", 100)
		truthy(Mock.ns.Config:Set("account.settings.mobs.max", 2))
		engage(pull)
		pull:target("tank", "x"):target("rogue", "y"):target("healer", "y")
		ticks(1)
		truthy(listed()[keyOf("y")])
		falsy(listed()[keyOf("x")])
	end)
end)

describe("budget and rotation (SPEC-07 §1.6)", function()
	it("in a party reads every unit of a mob, never more than READ_BUDGET reads per tick", function()
		local mobs = { { key = "boss", tokens = { "target" } } }
		for i = 1, 7 do mobs[#mobs + 1] = { key = "m" .. i, tokens = { "nameplate" .. i } } end
		local pull = newPull{ mobs = mobs }
		pull:at(0):start()
		for i = 1, 7 do pull:threat("m" .. i, "tank", 100):threat("m" .. i, "rogue", 50) end
		engage(pull)
		for _ = 1, 6 do
			ticks(1)
			truthy(MT().stats.lastReads <= MT().READ_BUDGET, "reads " .. MT().stats.lastReads)
		end
		eq(MT().READ_BUDGET, 40)
		-- 4 units and a lead per mob: 9 mobs fit... 7 others: all read each tick (35 reads)
		eq(MT().stats.lastReads, 35)
		eq(MT().stats.turns, 1)
	end)

	it("in a raid of 40 reads UNITS_PER_MOB units per mob, in turn with a cursor per mob", function()
		local members = { { key = "r1", role = "TANK" } }
		for i = 2, 39 do members[i] = { key = "r" .. i, class = "ROGUE" } end
		local mobs = { { key = "boss", tokens = { "target" } } }
		for i = 1, 7 do mobs[#mobs + 1] = { key = "m" .. i, tokens = { "nameplate" .. i } } end
		local pull = newPull{ raid = true, party = members, mobs = mobs }
		pull:at(0):start()
		for i = 1, 7 do
			pull:threat("m" .. i, "r1", 1000)
			for j = 2, 39 do pull:threat("m" .. i, "r" .. j, j) end
		end
		engage(pull)
		ticks(8)   -- the sweep reaches the nameplates after the 39 members' targets
		ticks(1)
		eq(MT().stats.lastReads, 33, "3 mobs of 10 units and a lead")
		eq(MT().stats.turns, 3)
		-- the cursor of one mob moves on: after enough of its reads every unit was read once
		local e = entryOf("m1")
		local slot = e.slot
		local rows, count = MT().Rows(e.key)
		eq(count, 40)
		local scanned = 0
		for i = 1, count do if rows[i] and rows[i].scanned then scanned = scanned + 1 end end
		eq(scanned, 10, "one read: the player, the tank, then 8 in turn")
		ticks(18)
		local readOnce
		eq(e.slot, slot, "the same place")
		readOnce = 0
		for i = 1, count do if rows[i].mobKey == e.key and rows[i].observedAt > 0 then readOnce = readOnce + 1 end end
		eq(readOnce, 40, "every unit read in turn")
		eq(e.mode, "values")
		eq(MT().Rows(keyOf("boss")), Mock.ns.ThreatScanner.records)
	end)

	it("reads at least one mob per tick even when one read does not fit in the budget", function()
		local pull = standard()
		MT().READ_BUDGET = 1
		ticks(1)
		eq(MT().stats.mobsRead > 0, true)
		truthy(MT().stats.lastReads > 1, "one whole mob")
		MT().READ_BUDGET = 40
	end)

	it("an event moves a mob forward without a read outside the tick", function()
		local mobs = { { key = "boss", tokens = { "target" } } }
		for i = 1, 12 do mobs[#mobs + 1] = { key = "m" .. i, tokens = { "nameplate" .. i } } end
		local pull = newPull{ mobs = mobs }
		pull:at(0):start()
		for i = 1, 12 do pull:threat("m" .. i, "tank", 100) end
		MT().READ_BUDGET = 6   -- one mob per tick
		engage(pull, false)
		ticks(2)
		local outside = readsDuring(function()
			pull:threat("m6", "rogue", 50)   -- fires UNIT_THREAT_LIST_UPDATE for nameplate6
		end)
		isNil(outside.nameplate6, "no read outside the tick")
		truthy(entryOf("m6").marked)
		local seen = readsDuring(function() ticks(1) end)
		truthy(seen.nameplate6, "the marked mob is read first")
		falsy(entryOf("m6").marked)
		MT().READ_BUDGET = 40
	end)
end)

describe("the three outcomes per mob (SPEC-07 §1.5)", function()
	for _, outcome in ipairs(Fight.OUTCOMES) do
		it("a mob in " .. outcome, function()
			standard(function(pull) pull:outcome(outcome) end)
			Mock.Advance(0.3)   -- a scan of the monitor
			ticks(2)
			local e = entryOf("add1")
			if outcome == "values" then
				eq(e.mode, "values")
				eq(e.state, "WARNING")
				eq(e.reason, "near")
				eq(MT().Reach(), "all")
				eq(Mock.ns.Compat.Capability("otherMobs"), "available")
			elseif outcome == "state" then
				eq(e.mode, "state")
				notNil(e.state)
				ne(e.state, "UNKNOWN")
				eq(MT().Reach(), "all")
			else
				eq(e.state, "UNKNOWN")
				eq(e.reason, "secret")
				eq(Mock.ns.Compat.Capability("otherMobs"), "restricted")
				eq(select(2, MT().Reach()), "secret")
			end
			eq(#Mock.errors, 0)
		end)
	end

	it("a secret mob is read again only after RETRY seconds", function()
		standard(function(pull) pull:outcome("none") end)
		local seen = readsDuring(function()
			for _ = 1, 4 do
				Mock.Advance(0.5)
				ticks(1)
			end
		end)
		isNil(seen.nameplate1, "not read within RETRY")
		eq(entryOf("add1").reason, "secret")
		seen = readsDuring(function()
			Mock.Advance(3.1)
			ticks(1)
		end)
		truthy(seen.nameplate1, "read again after 5 s")
	end)

	it("pending before the first read, stale when the reads are too old", function()
		local mobs = { { key = "boss", tokens = { "target" } }, { key = "a", tokens = { "nameplate1" } },
			{ key = "b", tokens = { "nameplate2" } }, { key = "c", tokens = { "nameplate3" } } }
		local pull = newPull{ mobs = mobs }
		pull:at(0):start():threat("a", "tank", 10):threat("b", "tank", 10):threat("c", "tank", 10)
		MT().READ_BUDGET = 1   -- one mob per tick
		engage(pull)
		local pending = 0
		for _, e in pairs(listed()) do if e.reason == "pending" then pending = pending + 1 end end
		eq(pending, 2)
		ticks(2)
		Mock.Advance(4)
		ticks(1)
		local stale = 0
		for _, e in pairs(listed()) do if e.reason == "stale" then stale = stale + 1 end end
		eq(stale, 2, "the two not read in this tick are too old")
		MT().READ_BUDGET = 40
	end)
end)

describe("the life cycle (SPEC-07 §1.7)", function()
	local function changes()
		local seen = {}
		Mock.ns.Bus.On("MOB_STATE_CHANGED", function(key, old, new)
			seen[#seen + 1] = { key = key, old = old, new = new }
		end)
		return seen
	end

	it("a dead mob leaves at once, with MOB_STATE_CHANGED to nil", function()
		local pull = standard()
		ticks(1)
		local seen = changes()
		local key = keyOf("add1")
		pull:die("add1")
		ticks(1)
		isNil(MT().Get(key))
		local last = seen[#seen]
		eq(last.key, key)
		isNil(last.new)
	end)

	it("a mob no token names is no-token, and leaves after FORGET", function()
		local pull = standard()
		ticks(1)
		local key = keyOf("add2")
		pull:token("focus", nil)
		Mock.Advance(1.1)   -- UNKNOWN is a fall: after the dwell
		ticks(1)
		eq(MT().Get(key).reason, "no-token")
		eq(MT().Get(key).state, "UNKNOWN")
		Mock.Advance(MT().FORGET + 0.5)
		ticks(1)
		isNil(MT().Get(key))
	end)

	it("a mob with no watched unit on its list leaves after FORGET: not the group's fight", function()
		local pull = newPull{ mobs = { { key = "boss", tokens = { "target" } }, { key = "stray", tokens = { "nameplate1" } } } }
		pull:at(0):start():threat("boss", "tank", 100)
		engage(pull)
		ticks(1)
		notNil(entryOf("stray"))
		Mock.Advance(5)
		ticks(1)
		notNil(entryOf("stray"))
		Mock.Advance(5.5)
		ticks(1)
		isNil(entryOf("stray"))
	end)

	it("empties at COMBAT_ENDED, keeps the reach as lastReach, and starts again at COMBAT_STARTED", function()
		local pull = standard()
		ticks(2)
		eq(MT().Reach(), "all")
		local updated = 0
		Mock.ns.Bus.On("MOBS_UPDATED", function() updated = updated + 1 end)
		pull:stop()
		eq(MT().count, 0)
		eq(select(2, MT().List()), 0)
		eq(MT().lastReach, "all")
		eq(updated, 1)
		falsy(MT().ticking)
		pull:start()
		eq(MT().Reach(), "unknown")
	end)

	it("keeps the readings when the roster changes, the cursors starting again", function()
		local pull = standard()
		ticks(2)
		local e = entryOf("add1")
		Mock.group.Set{ members = { "tank", "rogue", "healer", { key = "hunter", class = "HUNTER" } } }
		ticks(1)
		eq(entryOf("add1"), e)
		eq(e.mode, "values")
		eq(#Mock.errors, 0)
	end)
end)

describe("the reach (SPEC-07 §1.4)", function()
	it("is unknown before a decisive read, all when a plate answers", function()
		standard(function() eq(MT().Reach(), "unknown") end)
		eq(MT().Reach(), "all")
		isNil(select(2, MT().Reach()))
	end)

	it("is focus-boss when only focus and boss answer, nameplates-off with the setting off", function()
		standard(function() truthy(Mock.ns.Config:Set("account.settings.mobs.nameplates", false)) end)
		ticks(2)
		eq(MT().Reach(), "focus-boss")
		eq(select(2, MT().Reach()), "nameplates-off")
		isNil(entryOf("add1"), "the plates are not a source")
	end)

	it("is target when only the monitored mob answers, and none when not even it does", function()
		local pull = newPull{ mobs = { { key = "boss", tokens = { "target" } } } }
		pull:at(0):start():threat("boss", "tank", 100)
		engage(pull)
		Mock.Advance(0.3)
		ticks(1)
		eq(MT().Reach(), "target")
		eq(select(2, MT().Reach()), "nameplates-off", "no nameplate seen")
	end)

	it("is none when not even the monitored mob answers", function()
		local pull = newPull{ mobs = { { key = "boss", tokens = { "target" } } } }
		pull:at(0):start():threat("boss", "tank", 100):outcome("none")
		engage(pull)
		Mock.Advance(0.3)
		ticks(1)
		eq(MT().Reach(), "none")
	end)
end)

describe("the monitored mob (MT-03)", function()
	it("is never read by the tracker: its row comes from the monitor's rows", function()
		local pull = standard()
		local seen = readsDuring(function() ticks(3) end)
		isNil(seen.target, "the scanner reads the target, not in a tick of the mobs")
		local _ = pull
		local mon = MT().monitored
		eq(mon.key, keyOf("boss"))
		Mock.Advance(0.25)   -- a scan of the monitor
		ticks(1)
		eq(mon.mode, "values")
		eq(mon.state, "SAFE")
		eq(mon.holder.unitToken, "party1")
	end)

	it("is never read even when the scanner does not run and the mob is also on a nameplate", function()
		local pull = newPull{ mobs = { { key = "boss", tokens = { "target", "nameplate1" } }, { key = "add1", tokens = { "nameplate2" } } } }
		pull:at(0):start():threat("boss", "tank", 100):threat("add1", "tank", 100)
		engage(pull, false)
		local seen = readsDuring(function() ticks(4) end)
		isNil(seen.nameplate1)
		isNil(seen.target)
		truthy(seen.nameplate2)
		eq(MT().monitored.state, "UNKNOWN")
	end)

	it("goes back to the rotation when another mob is monitored", function()
		local pull = standard()
		ticks(1)
		local boss = MT().monitored
		pull:target("player", "add1")
		ticks(1)
		eq(MT().monitored.key, keyOf("add1"))
		falsy(boss.monitored)
	end)
end)

describe("consumers and activity (SPEC-07 §1.6, ARC-05)", function()
	it("nothing ticks nor reads without a consumer; Want starts and stops it", function()
		local pull = newPull()
		pull:at(0):start():threat("add1", "tank", 100)
		pull:to(2)
		falsy(MT().ticking)
		MT().Want("test", true)
		truthy(MT().ticking)
		truthy(Mock.ns.Scheduler.IsRunning("mobs"))
		eq(Mock.ns.Scheduler.Rate("mobs"), MT().RATE)
		MT().Want("test", false)
		falsy(MT().ticking)
		falsy(Mock.ns.Scheduler.IsRunning("mobs"))
	end)

	it("the window on the Monitor tab is a consumer", function()
		local pull = newPull()
		pull:at(0):start()
		pull:to(0)
		falsy(MT().ticking)
		Mock.ns.Window:ShowMonitor()
		truthy(MT().ticking)
		Mock.ns.Window:SelectTab("settings", true)
		falsy(MT().ticking)
	end)

	it("only sweeps when no other mob is known: no threat event registered", function()
		local pull = newPull{ mobs = { { key = "boss", tokens = { "target" } } } }
		pull:at(0):start()
		engage(pull)
		ticks(1)
		falsy(MT().reading)
		local add = Mock.units.Add("late", { hostile = true })
		add.combat = true
		pull:token("nameplate5", "late")
		ticks(1)
		truthy(MT().reading)
	end)

	it("does not survive the end of combat", function()
		local pull = standard()
		ticks(1)
		pull:stop()
		falsy(MT().ticking)
		falsy(Mock.ns.Scheduler.IsRunning("mobs"))
	end)
end)

describe("performance (ARC-06)", function()
	it("allocates nothing per tick after the warm-up, in a raid of 40 with 8 mobs", function()
		local members = { { key = "r1", role = "TANK" } }
		for i = 2, 39 do members[i] = { key = "r" .. i, class = "ROGUE" } end
		local mobs = { { key = "boss", tokens = { "target" } } }
		for i = 1, 9 do mobs[#mobs + 1] = { key = "m" .. i, tokens = { "nameplate" .. i } } end
		local pull = newPull{ raid = true, party = members, mobs = mobs }
		pull:at(0):start()
		for i = 1, 9 do pull:threat("m" .. i, "r1", 1000):threat("m" .. i, "r5", 900) end
		engage(pull, false)
		ticks(30)
		-- the mock client allocates for its own answers: constant stand-ins, so that only the addon is measured
		local guidOf = {}
		for i = 1, 9 do guidOf["nameplate" .. i] = Mock.units.Get("m" .. i).guid end
		guidOf.target = Mock.units.Get("boss").guid
		UnitExists = function(u) return guidOf[u] ~= nil or u == "player" or u:find("^raid") ~= nil end
		UnitIsDead = function() return false end
		UnitCanAttack = function(_, u) return guidOf[u] ~= nil end
		UnitAffectingCombat = function() return true end
		UnitGUID = function(u) return guidOf[u] end
		UnitIsUnit = function() return false end
		C_Secrets.ShouldUnitThreatStateBeSecret = function() return false end
		C_Secrets.ShouldUnitThreatValuesBeSecret = function() return false end
		UnitDetailedThreatSituation = function(unit)
			if unit == "raid1" then return true, 3, 100, 100, 1000 end
			return false, 0, 40, 44, 440
		end
		UnitThreatPercentageOfLead = function() return 150 end
		UnitThreatLeadSituation = function() return 0 end
		ticks(30)
		local grown = math.huge
		for _ = 1, 3 do
			collectgarbage("collect")
			collectgarbage("stop")
			local before = collectgarbage("count")
			for _ = 1, 300 do MT().Tick() end
			grown = math.min(grown, collectgarbage("count") - before)
			collectgarbage("restart")
		end
		truthy(grown < 4, "grew by " .. grown .. " KB")
		eq(select(2, MT().List()), 8)
		truthy(MT().stats.lastReads <= MT().READ_BUDGET)
	end)
end)

describe("the setting off (settings.mobs.enabled)", function()
	it("stops everything, registers nothing and reads nothing", function()
		local pull = standard()
		ticks(1)
		truthy(Mock.Listeners("NAME_PLATE_UNIT_ADDED") > 0)
		truthy(Mock.ns.Config:Set("account.settings.mobs.enabled", false))
		falsy(MT().ticking)
		eq(MT().count, 0)
		eq(Mock.Listeners("NAME_PLATE_UNIT_ADDED"), 0)
		eq(Mock.Listeners("PLAYER_FOCUS_CHANGED"), 0)
		eq(Mock.Listeners("INSTANCE_ENCOUNTER_ENGAGE_UNIT"), 0)
		falsy(MT().Want("test", true))
		local seen = readsDuring(function() pull:at(3):threat("add1", "rogue", 600) pull:to(3) end)
		isNil(seen.nameplate1)
		isNil(seen.focus)
	end)
end)

describe("the multitarget switch off (ADR 0014, SPEC-07 §2.7)", function()
	before_boot(function(M) M.features = { monitor = true, multitarget = false, recording = false } end)

	it("registers no game event, has no tick, reads nothing and has no debug section", function()
		local pull = newPull()
		pull:at(0):start():threat("add1", "tank", 100):threat("add2", "tank", 100)
		Mock.ns.ThreatScanner.Want("test", true)
		falsy(MT().Want("test", true))
		local seen = readsDuring(function() pull:to(3) end)
		falsy(MT().enabled)
		falsy(MT().ticking)
		eq(MT().count, 0)
		for _, event in ipairs({ "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED", "PLAYER_FOCUS_CHANGED",
			"INSTANCE_ENCOUNTER_ENGAGE_UNIT" }) do
			eq(Mock.Listeners(event), 0, event)
		end
		isNil(seen.nameplate1)
		isNil(seen.focus)
		falsy(Mock.ns.Diagnostics.Report():find("== Mobs ==", 1, true))
		eq(Mock.ns.Compat.Capability("otherMobs"), "unknown")
	end)
end)

describe("/atw debug, section Mobs (SPEC-07 §2.6)", function()
	it("says the switch, the settings, the reach, the slots, the reads and the events, never a name or a GUID", function()
		local pull = standard()
		ticks(2)
		local text = Mock.ns.Diagnostics.Report()
		contains(text, "== Mobs ==")
		contains(text, "switch on, setting on, reading, nameplates on, max 8")
		contains(text, "reach all, identity guid")
		contains(text, "3 of 8 listed")
		contains(text, "pinned no")
		for _, unit in ipairs({ "boss", "add1", "add2" }) do
			falsy(text:find(Mock.units.Get(unit).guid, 1, true), unit)
		end
		falsy(text:find("Add1", 1, true), "no name")
	end)
end)
