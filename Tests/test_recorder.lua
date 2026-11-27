-- Data/Recorder.lua (SPEC-05 §1, §6, §7 M4.2; REC-01-REC-06; SPEC-08 QA-03) on fight scripts: when a session opens
-- (the six conditions, `when` in its three choices), the life cycle with END_DELAY and chained pulls, a fight under 3 s
-- dropped, the rows of the three probe outcomes (SPEC-02 §4.2), the events of §1.4 (C c T S A M D L H N G X), deaths
-- with a readable and a secret GUID, the target that dies, vanishes or is replaced, missed events, duplicates, a /reload
-- and a logout during and after a session (X, stamp, the linked session), the demo, read-only data, the switch off.
-- The numbers of the mock are assumptions until the M0 probe (Tests/mock/70_threat.lua).

before_boot(function(M) M.features = { monitor = true, alerts = true, coach = true, recording = true } end)

local function R() return Mock.ns.Recorder end
local function S() return Mock.ns.Session end
local function list() return AzerothThreatwardenDB.sessions end
local function C() return Mock.ns.Config end

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
			{ key = "boss", tokens = { "target", "boss1" }, classification = "worldboss", npcID = 448 },
			{ key = "add", tokens = { "nameplate2" } },
		},
	}
end

local function value(scaled, raw) return { raw = raw or 500, scaled = scaled } end

-- A party fight of `seconds`: the tank holds the boss, the player at `me` scaled %, the rogue at 20 %.
local function partyFight(seconds, me, outcome)
	local pull = newPull()
	if outcome then pull:outcome(outcome) end
	pull:at(0):start():threat("boss", "tank", 1000):threat("boss", "player", value(me or 40))
		:threat("boss", "rogue", value(20, 300))
	pull:at(seconds):stop()
	return pull
end

local function decode(s) return assert(S().Decode(s)) end

-- "C1 M T ..." : kind and code `a` of every event ("-" left out).
local function kinds(s)
	local out = {}
	for _, e in ipairs(decode(s).events) do out[#out + 1] = e.k .. (e.a ~= "-" and e.a or "") end
	return table.concat(out, " ")
end

local function eventsOf(s, k)
	local out = {}
	for _, e in ipairs(decode(s).events) do if e.k == k then out[#out + 1] = e end end
	return out
end

local function bus(event)
	local seen = {}
	Mock.ns.Bus.On(event, function(...) seen[#seen + 1] = { ... } end)
	return seen
end

local function unitOf(s, token)
	for i, u in ipairs(s.units) do if u.token == token then return i, u end end
	return nil
end

describe("a fight in a group (SPEC-05 §1.2-§1.4)", function()
	it("gives one session with its header, rows and events, the window closed", function()
		local started, ended, changed = bus("SESSION_STARTED"), bus("SESSION_ENDED"), bus("SESSIONS_CHANGED")
		local pull = partyFight(10)
		pull:to(0)
		eq(#list(), 1)
		local s = list()[1]
		eq(s.state, "open")
		eq(R().current, s)
		truthy(Mock.ns.ThreatScanner.active, "the recorder is a consumer of the scanner")
		eq(started[1][1], s.id)
		pull:finish()
		Mock.Advance(6)
		isNil(R().current)
		eq(#list(), 1)
		eq(s.state, "complete")
		eq(s.ended, "combat")
		eq(s.group, "party")
		eq(s.zone, "Test Zone")
		eq(s.inst, "none")
		truthy(math.abs(s.started - (GetServerTime() - 16)) <= 1, "the server time at the opening")
		matches(s.id, "^%d+%-1$")
		eq(s.dur, 100)
		eq(s.fight, 100)
		isNil(s.parts)
		isNil(s.buf)
		eq(s.rec.hz, 2)
		eq(s.rec.monitorHz, 5)
		eq(s.rec.warning, 82)
		eq(s.rec.mode, "none", "the mode at the opening, before the first scan")
		eq(#s.mobs, 1)
		deepEq(s.mobs[1], { name = "Boss", class = "worldboss", npc = 448 })
		eq(#s.units, 3, "the healer is not on the list: no entry")
		local me, player = unitOf(s, "player")
		eq(player.name, "Testchar")
		eq(player.me, true)
		eq(select(2, unitOf(s, "party1")).role, "TANK")
		truthy(s.n >= 4, "rows: " .. s.n)
		eq(#s.cols.t, 3 * s.n)
		matches(kinds(s), "^C1 Mn T ")
		matches(kinds(s), " c$")
		local d = decode(s)
		for i = 1, d.n do
			if d.u[i] == me then eq(d.s[i], "0") eq(d.p[i], 400) end
		end
		truthy(s.q.v[me] >= 18 and s.q.v[me] <= 21, "ticks with values: " .. s.q.v[me])
		eq(s.q.x[me], 0)
		eq(ended[1][1], s.id)
		eq(ended[1][2], "complete")
		eq(#changed, 2)
		eq(#Mock.errors, 0)
	end)

	it("writes a numbered row only for a new read and a row without a number only when the code changes (REC-06)", function()
		local pull = partyFight(10, 40, "state")
		pull:finish()
		Mock.Advance(6)
		local s = list()[1]
		local d = decode(s)
		local me = unitOf(s, "player")
		local mine = 0
		for i = 1, d.n do
			if d.u[i] == me then
				mine = mine + 1
				eq(d.p[i], -1)
			end
		end
		eq(mine, 1, "one row: the code never changed")
		truthy(s.q.s[me] >= 18, "ticks with the state only: " .. s.q.s[me])
		eq(s.q.v[me], 0)
	end)

	it("gives the rows of SPEC-02 §4.2 in the three outcomes", function()
		local want = { values = "^[0-4]$", state = "^[a-d]$", none = "^S$" }
		for _, outcome in ipairs(Fight.OUTCOMES) do
			T.boot()
			local pull = partyFight(6, 40, outcome)
			pull:finish()
			Mock.Advance(6)
			local s = list()[1]
			notNil(s, outcome)
			local d = decode(s)
			truthy(d.n >= 1, outcome)
			local me, tank = unitOf(s, "player"), unitOf(s, "party1")
			for i = 1, d.n do
				if d.u[i] == me or d.u[i] == tank then matches(d.s[i], want[outcome]) end
				if outcome ~= "values" then eq(d.p[i], -1) end
			end
			if outcome == "none" then
				local me = unitOf(s, "player")
				truthy(s.q.x[me] >= 10, "unknown ticks")
				matches(kinds(s), "Mn")
			end
		end
	end)

	it("records in a raid too", function()
		local members = {}
		for i = 1, 10 do members[i] = { key = "r" .. i, role = i == 1 and "TANK" or "DAMAGER" } end
		local pull = newPull{ raid = true, party = members }
		pull:at(0):start():threat("boss", "r1", 1000):threat("boss", "player", 300)
		pull:at(5):stop()
		pull:finish()
		Mock.Advance(6)
		eq(list()[1].group, "raid")
		eq(#list()[1].units, 2, "only the units on the list")
		eq(select(2, unitOf(list()[1], "raid1")).role, "TANK")
	end)
end)

describe("when a fight is recorded (SPEC-05 §1.1, Q16)", function()
	local boars = 0
	local function soloFight()
		boars = boars + 1
		local boar = "boar" .. boars
		local pull = Fight.new{ player = { class = "WARRIOR", role = "NONE" },
			mobs = { { key = boar, tokens = { "target" } } } }
		pull:at(0):start():threat(boar, "player", 500)
		pull:at(5):stop()
		pull:finish()
		Mock.Advance(6)
	end

	it("solo: not with `group` (the default) nor `instance`, yes with `always`", function()
		soloFight()
		eq(#list(), 0)
		eq(R().stats.lastSkip, "when")
		contains(table.concat(R().DebugLines(), "\n"), "not recorded because: when")
		truthy(C():Set("account.settings.recording.when", "instance"))
		soloFight()
		eq(#list(), 0)
		truthy(C():Set("account.settings.recording.when", "always"))
		soloFight()
		eq(#list(), 1)
		eq(list()[1].group, "solo")
	end)

	it("solo in an instance: yes with `group` and `instance`, with the type and the difficulty", function()
		Mock.instance.Set{ type = "party", difficultyID = 2 }
		soloFight()
		eq(#list(), 1)
		eq(list()[1].inst, "party")
		eq(list()[1].diff, 2)
		truthy(C():Set("account.settings.recording.when", "instance"))
		soloFight()
		eq(#list(), 2)
	end)

	it("not with the setting off, in demo mode or on read-only data, and the first reason is said", function()
		truthy(C():Set("account.settings.recording.enabled", false))
		partyFight(5):finish()
		Mock.Advance(6)
		eq(#list(), 0)
		eq(R().stats.lastSkip, "off")
		truthy(C():Set("account.settings.recording.enabled", true))
		Mock.ns.Demo.Start()
		eq(R().WhyNot(), "demo")
		Mock.ns.Demo.Stop()
		boot(function(M)
			M.features = { monitor = true, recording = true }
			M.saved = { AzerothThreatwardenDB = { schema = 7 } }
		end)
		partyFight(5):finish()
		Mock.Advance(6)
		eq(R().stats.lastSkip, "read-only")
		isNil(C().db.account.sessions[1])
		isNil(AzerothThreatwardenDB.sessions, "the newer data is never rewritten")
	end)

	it("not on a client that is not recognised", function()
		boot(function(M)
			M.features = { monitor = true, recording = true }
			WOW_PROJECT_ID = 1
		end)
		partyFight(5):finish()
		Mock.Advance(6)
		eq(#list(), 0)
	end)

	it("the demo started during END_DELAY closes the session at once", function()
		local pull = partyFight(8)
		pull:finish()
		Mock.Advance(1)
		notNil(R().current)
		local ended = bus("SESSION_ENDED")
		truthy(Mock.ns.Demo.Start())
		isNil(R().current)
		eq(ended[1][2], "complete")
		eq(list()[1].fight, 80)
		matches(kinds(list()[1]), " c$")
		Mock.ns.Demo.Stop()
		eq(#list(), 1)
	end)

	it("turning the setting off during a session closes it", function()
		local pull = partyFight(20)
		pull:to(5)
		truthy(C():Set("account.settings.recording.enabled", false))
		isNil(R().current)
		eq(list()[1].state, "complete")
		pull:finish()
	end)

	it("the switch turned off during a session closes it at the next tick", function()
		local pull = partyFight(20)
		pull:to(5)
		Mock.ns.Features.recording = false
		Mock.Advance(1)
		isNil(R().current)
		eq(list()[1].state, "complete")
		pull:finish()
		Mock.Advance(6)
		eq(#list(), 1)
	end)
end)

describe("the switch off (ADR 0014)", function()
	before_boot(function(M) M.features = { monitor = true, recording = false } end)

	it("registers nothing, opens nothing and writes nothing but the defaults", function()
		falsy(R().enabled)
		for _, event in ipairs({ "UNIT_DIED", "PLAYER_DEAD", "ENCOUNTER_START", "ENCOUNTER_END" }) do
			eq(Mock.Listeners(event), 0, event)
		end
		partyFight(5):finish()
		Mock.Advance(6)
		deepEq(list(), {})
		falsy(Mock.ns.Scheduler.IsRunning("record"))
		deepEq(C():Get("account.settings.recording"), C().RECORDING_DEFAULTS)
	end)
end)

describe("the life cycle (SPEC-05 §1.2, REC-04)", function()
	it("keeps chained pulls within 5 s in one session, C a = 2, the pause out of `fight`", function()
		local pull = newPull()
		pull:at(0):start():threat("boss", "tank", 1000):threat("boss", "player", 300)
		pull:at(4):stop()
		pull:at(7):start():threat("boss", "tank", 1000):threat("boss", "player", 300)
		pull:at(10):stop()
		pull:finish()
		notNil(R().current, "waiting for END_DELAY")
		Mock.Advance(6)
		eq(#list(), 1)
		local s = list()[1]
		matches(kinds(s), "^C1 .* c .*C2 .* c$")
		eq(s.fight, 70)
		eq(s.dur, 100)
	end)

	it("opens a new session after more than 5 s", function()
		local pull = newPull()
		pull:at(0):start():threat("boss", "tank", 1000):threat("boss", "player", 300)
		pull:at(4):stop()
		pull:at(10):start():threat("boss", "tank", 1000):threat("boss", "player", 300)
		pull:at(15):stop()
		pull:finish()
		Mock.Advance(6)
		eq(#list(), 2)
		ne(list()[1].id, list()[2].id)
		matches(list()[2].id, "%-2$")
	end)

	it("drops a fight under 3 s, without a notice", function()
		local ended = bus("SESSION_ENDED")
		partyFight(2):finish()
		Mock.Advance(6)
		eq(#list(), 0)
		eq(ended[1][2], "dropped")
		eq(R().stats.dropped, 1)
		eq(#Mock.output, 0)
	end)

	it("drops a fight without a row (no mob monitored)", function()
		local pull = newPull()
		pull:target("player", nil)
		Mock.units.SetToken("target", nil)
		pull:at(0):start():threat("add", "tank", 100)
		pull:at(6):stop()
		pull:finish()
		Mock.Advance(6)
		eq(#list(), 0)
	end)

	it("ignores a second COMBAT_STARTED in combat and a COMBAT_ENDED out of it", function()
		local pull = partyFight(10)
		pull:to(2)
		Mock.ns.Bus.Emit("COMBAT_STARTED")
		eq(#list(), 1)
		pull:finish()
		Mock.ns.Bus.Emit("COMBAT_ENDED")
		Mock.Advance(6)
		local cs = 0
		for _, e in ipairs(decode(list()[1]).events) do if e.k == "c" then cs = cs + 1 end end
		eq(cs, 1)
	end)

	it("gives a duplicate id a suffix", function()
		list()[1] = { id = tostring(GetServerTime()) .. "-1", state = "complete" }
		partyFight(5):finish()
		Mock.Advance(6)
		eq(list()[2].id, list()[1].id .. "-b")
	end)
end)

describe("events (SPEC-05 §1.4)", function()
	it("records the states, the aggro and the alerts of a DPS that nears the threshold", function()
		local pull = newPull()
		pull:at(0):start():threat("boss", "tank", 1000):threat("boss", "player", value(50))
		pull:at(2):threat("boss", "player", value(85))
		pull:at(4):threat("boss", "player", value(97))
		pull:at(6):aggro("boss", "player")
		pull:at(8):stop()
		pull:finish()
		Mock.Advance(6)
		local s = list()[1]
		local me = unitOf(s, "player")
		local states = {}
		for _, e in ipairs(eventsOf(s, "S")) do if e.u == me then states[#states + 1] = e.b .. ">" .. e.a end end
		contains(table.concat(states, " "), "->S")
		contains(table.concat(states, " "), "S>W")
		contains(table.concat(states, " "), "W>D")
		local alerts = eventsOf(s, "L")
		truthy(#alerts >= 2, "alerts: " .. #alerts)
		eq(alerts[1].a, "w")
		eq(alerts[1].u, me)
		eq(alerts[1].b, "1")
		eq(alerts[1].c, "0")
		local aggro = eventsOf(s, "A")
		eq(aggro[1].u, unitOf(s, "party1"))
		eq(aggro[1].v, 0)
		eq(aggro[1].a, "1")
		eq(aggro[#aggro].u, me)
		eq(aggro[#aggro].a, "0")
		eq(aggro[#aggro].b, "1")
		local modes = eventsOf(s, "M")
		eq(modes[#modes].a, "v")
		local tips = eventsOf(s, "H")
		truthy(#tips >= 1, "the Coach")
		eq(tips[1].u, me)
		for i = 2, #tips do ne(tips[i].a, tips[i - 1].a, "only when the rule changes") end
	end)

	it("records a change of target, several mobs, and the mob that dies", function()
		local pull = newPull()
		pull:at(0):start():threat("boss", "tank", 1000):threat("boss", "player", 300)
			:threat("add", "tank", 500):threat("add", "player", 200)
		pull:at(3):token("target", "add")
		pull:event("PLAYER_TARGET_CHANGED")
		pull:at(6):die("add")
		pull:at(8):stop()
		pull:finish()
		Mock.Advance(6)
		local s = list()[1]
		eq(#s.mobs, 2)
		eq(s.mobs[2].name, "Add")
		local d = decode(s)
		local mobs = {}
		for i = 1, d.n do mobs[d.m[i]] = true end
		truthy(mobs[1] and mobs[2], "rows of both mobs")
		matches(kinds(s), "T .*T .*Td .*Dt")
		local deaths = eventsOf(s, "D")
		eq(deaths[#deaths].m, 2)
	end)

	it("records the death of the tank and of a DPS with a readable GUID, and none with a secret one", function()
		local pull = partyFight(10)
		pull:at(3):die("tank")
		pull:at(5):die("rogue")
		pull:finish()
		Mock.Advance(6)
		local s = list()[1]
		local deaths = eventsOf(s, "D")
		eq(#deaths, 2)
		eq(deaths[1].u, unitOf(s, "party1"))
		eq(deaths[1].a, "g")
		eq(deaths[2].u, unitOf(s, "party3"))
		T.boot()
		local pull2 = partyFight(10)
		pull2:secrets{ identity = function(unit) return unit ~= "player" end }
		pull2:at(3):die("tank")
		pull2:finish()
		Mock.Advance(6)
		eq(#eventsOf(list()[1], "D"), 0)
		eq(#Mock.errors, 0)
	end)

	it("records the player's death, the encounters and a gap of the tick", function()
		local pull = partyFight(12)
		pull:at(1):call(function() Mock.combat.StartEncounter(101, "Test Boss", 1, 5) end)
		pull:at(2):event("ENCOUNTER_START", 101, "Test Boss", 1, 5)
		pull:at(3):call(function() Mock.StepClock(4) end)
		pull:at(8):event("PLAYER_DEAD")
		pull:at(9):call(function() Mock.combat.EndEncounter(false) end)
		pull:at(10):event("ENCOUNTER_START", 5000, "Big", 1, 5)
		pull:finish()
		Mock.Advance(6)
		local s = list()[1]
		local n = eventsOf(s, "N")
		eq(#n, 4, "the duplicate in another tenth is written")
		eq(n[1].n, 101)
		eq(n[3].a, "e")
		eq(n[3].b, "0")
		eq(n[4].n, -1, "an id past 3843 is not written")
		local d = eventsOf(s, "D")
		eq(d[1].a, "p")
		eq(d[1].u, unitOf(s, "player"))
		local g = eventsOf(s, "G")
		eq(#g, 1)
		truthy(g[1].n >= 40, "the gap in tenths: " .. g[1].n)
	end)

	it("records a mob that vanishes and a target replaced without an event", function()
		local pull = partyFight(10)
		pull:at(3):newGUID("boss")
		pull:at(6):vanish("boss")
		pull:finish()
		Mock.Advance(6)
		local s = list()[1]
		eq(#s.mobs, 2)
		matches(kinds(s), "T .*T .*Tl")
	end)

	it("writes no duplicate row for duplicated or late threat events (REC-06)", function()
		local pull = partyFight(6)
		pull:at(2):event("UNIT_THREAT_LIST_UPDATE", "target"):event("UNIT_THREAT_LIST_UPDATE", "target")
			:event("UNIT_THREAT_SITUATION_UPDATE", "player")
		pull:finish()
		Mock.Advance(6)
		local d = decode(list()[1])
		for i = 2, d.n do
			truthy(d.t[i] >= d.t[i - 1])
			truthy(not (d.t[i] == d.t[i - 1] and d.u[i] == d.u[i - 1] and d.s[i] == d.s[i - 1]), "row " .. i)
		end
	end)

	it("keeps recording when the threat events are missed (the tick reads)", function()
		local pull = partyFight(8)
		pull:at(0):silent(true)
		pull:finish()
		Mock.Advance(6)
		truthy(list()[1].n >= 10)
	end)

	it("records the reason of an API that answers nil, an error or a unit that cannot be read", function()
		local pull = partyFight(8)
		pull:at(2):answer("UnitDetailedThreatSituation", "player", "*", Mock.threat.ERROR)
			:answer("UnitThreatSituation", "player", "*", Mock.threat.ERROR)
		pull:at(4):answer("UnitDetailedThreatSituation", "party3", "*", Mock.threat.NIL)
			:answer("UnitThreatSituation", "party3", "*", Mock.threat.NIL)
		pull:finish()
		Mock.Advance(6)
		local s = list()[1]
		local d = decode(s)
		local me, rogue = unitOf(s, "player"), unitOf(s, "party3")
		local mine, rogueAfter = {}, 0
		for i = 1, d.n do
			if d.u[i] == me then mine[#mine + 1] = d.s[i] end
			if d.u[i] == rogue and d.t[i] > 45 then rogueAfter = rogueAfter + 1 end
		end
		local text = table.concat(mine)
		matches(text, "E$")
		eq(select(2, text:gsub("E", "")), 1, "the reason once, while it does not change")
		eq(rogueAfter, 0, "a unit off the list (nil) has no rows (DAT-31)")
		eq(#Mock.errors, 0)
	end)

	it("records the units with a secret GUID under their token", function()
		local pull = partyFight(6)
		pull:secrets{ identity = function(unit) return unit ~= "player" end }
		pull:finish()
		Mock.Advance(6)
		local s = list()[1]
		truthy(#s.units >= 3)
		isNil(select(2, unitOf(s, "party1")).name, "a secret name is unknown")
		eq(select(2, unitOf(s, "player")).name, "Testchar")
		eq(#Mock.errors, 0)
	end)

	it("never saves a GUID of a player or a secret (DAT-33)", function()
		local pull = partyFight(6)
		pull:finish()
		Mock.Advance(6)
		Mock.Reload()
		local text = Mock.savedText.AzerothThreatwardenDB
		falsy(text:find("Player%-"), "no player GUID")
		falsy(text:find("Creature%-"), "no mob GUID")
	end)
end)

describe("the alerts about other mobs (SPEC-07 §2.5, M7.4)", function()
	before_boot(function(M)
		M.features = { monitor = true, alerts = true, coach = false, recording = true, multitarget = true }
	end)

	it("are never written: the mob is not in the session", function()
		truthy(C():Set("account.settings.alerts.onlyTarget", false))
		truthy(C():Set("account.settings.alerts.others", "always"))
		local pull = newPull{ mobs = { { key = "boss", tokens = { "target" } },
			{ key = "add", tokens = { "nameplate2" } } } }
		pull:at(0):start():threat("boss", "tank", 1000):threat("boss", "player", value(40))
			:threat("add", "tank", 1000):threat("add", "rogue", value(20, 300))
		pull:at(2):aggro("add", "rogue")
		pull:at(6):threat("boss", "player", value(97))
		pull:at(8):stop()
		pull:finish()
		Mock.Advance(6)
		truthy(Mock.ns.Alerts.stats.raised.mob >= 1, "the mob alert was raised")
		local s = list()[1]
		local alerts = eventsOf(s, "L")
		truthy(#alerts >= 1, "the monitor's alert is recorded")
		for _, e in ipairs(alerts) do
			truthy(e.a == "d" or e.a == "w", "only the monitor's alerts: " .. e.a)
		end
		eq(#alerts, Mock.ns.Alerts.stats.raised.warning + Mock.ns.Alerts.stats.raised.danger)
		eq(#s.mobs, 1, "the other mob is not in the session")
		eq(#Mock.errors, 0)
		eq(Mock.ns.Bus.errorCount, 0)
	end)
end)

describe("reload and logout (SPEC-05 §1.6, REC-04)", function()
	it("a /reload in combat leaves the session interrupted with the X stamp, and the new one is linked", function()
		local ended = bus("SESSION_ENDED")
		local pull = partyFight(30)
		pull:to(8)
		local id = list()[1].id
		Mock.Reload()
		local old = list()[1]
		eq(old.id, id)
		eq(old.state, "interrupted")
		eq(old.stamp, true)
		eq(old.dur, 80)
		contains(Mock.savedText.AzerothThreatwardenDB, '["buf"]', "saved with its pieces and buf")
		isNil(old.buf, "joined by Storage at the load (M4.3)")
		eq(old.ended, "reload", "from ENTERING_WORLD")
		matches(kinds(old), " Xo$")
		eq(#list(), 2, "a new session in the fight going on")
		local new = list()[2]
		eq(new.after, id)
		matches(kinds(new), "^Cr ")
		pull:finish()
		Mock.Advance(6)
		eq(new.state, "complete")
		eq(#Mock.errors, 0)
	end)

	it("a logout during END_DELAY closes the session without joining it", function()
		local pull = partyFight(6)
		pull:finish()
		Mock.Advance(2)
		Mock.Relog(60)
		local s = list()[1]
		eq(s.state, "complete")
		eq(s.ended, "combat")
		falsy(s.stamp)
		isNil(s.buf, "joined by Storage at the load (M4.3)")
		eq(s.fight, 60)
		eq(#list(), 1)
		contains(Mock.savedText.AzerothThreatwardenDB, '["buf"]', "saved with its pieces and buf")
	end)

	it("a logout after the session changes nothing; no link after more than 120 s", function()
		local pull = partyFight(6)
		pull:finish()
		Mock.Advance(6)
		Mock.Relog(60)
		eq(list()[1].state, "complete")
		isNil(list()[1].buf)
		T.boot()
		local pull2 = partyFight(60)
		pull2:to(5)
		Mock.Relog(200, function() end)
		eq(list()[1].state, "interrupted")
		Mock.combat.Leave()
	end)

	it("a /reload in combat without END of the previous one links only within LIMITS.link", function()
		local pull = partyFight(300)
		pull:to(5)
		Mock.Reload()
		eq(list()[2].after, list()[1].id)
		eq(#Mock.errors, 0)
	end)
end)

describe("/atw debug, section Recording", function()
	it("says the settings, the open session and the counts, never a name", function()
		local pull = partyFight(10)
		pull:to(4)
		local text = table.concat(R().DebugLines(), "\n")
		contains(text, "switches: recording on")
		contains(text, "open: ")
		contains(text, "in combat")
		falsy(text:find("Boss"))
		falsy(text:find("Testchar"))
		falsy(text:find("Test Zone"))
		pull:finish()
		Mock.Advance(6)
		text = table.concat(R().DebugLines(), "\n")
		contains(text, "sessions kept: 1")
		contains(Mock.ns.Diagnostics.Report(), "== Recording ==")
	end)
end)
