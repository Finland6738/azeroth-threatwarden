-- Data/Metrics.lua (SPEC-06 §1, §5, §6 M6.2; ANA-01–ANA-05; ADR 0003, 0018): known sessions with known answers for
-- every metric of §1.4 in the three probe outcomes and in a mixed, an interrupted, a truncated one, one with the events
-- at their limit and a linked one; equality with the report's cells and the timeline's crossings on the same sessions;
-- the changes of holder split three ways, never the first holder; ANA-02 at 49 % and 50 % on each base and on the
-- coverage; the closest to the tank without rows 2, 3, 4 and at 3843; unstable intervals at the edges of W and K,
-- across two pulls and as a moment; the risk rate under and over 30 s known; the build in slices equal to the one-pass
-- build; the cache and SESSIONS_CHANGED; the session unchanged; nothing built with the switch off; the words.

before_boot(function(M)
	M.features = { monitor = true, alerts = true, coach = true, recording = true, reports = true, timeline = true,
		analytics = true }
end)

local function Mx() return Mock.ns.Metrics end
local function R() return Mock.ns.Report end
local function TL() return Mock.ns.Timeline end
local function S() return Mock.ns.Session end
local function St() return Mock.ns.Storage end

local counter = 0

-- Events in time order (stable), so that Session.AddEvent keeps them all.
local function ordered(list)
	local out = {}
	for i, e in ipairs(list) do out[i] = { e = e, i = i } end
	table.sort(out, function(a, b)
		if a.e[1] ~= b.e[1] then return a.e[1] < b.e[1] end
		return a.i < b.i
	end)
	for i, x in ipairs(out) do out[i] = x.e end
	return out
end

-- A session built with the Session API (as in test_report.lua). spec: units, mobs, events { t, k, m, u, v, a, b, c,
-- n }, rows { t, m, u, p, code }, q, dur, fight, state, ended, trunc, after, rec.
local function build(spec)
	counter = counter + 1
	local s = S().New{ id = "mx-" .. counter, started = 3000 + counter, group = "party", after = spec.after,
		rec = spec.rec or { hz = 2, warning = 80, danger = 95, mode = "values" } }
	for _, u in ipairs(spec.units or {}) do S().AddUnit(s, u, 0) end
	for _, m in ipairs(spec.mobs or {}) do S().AddMob(s, m, 0) end
	for _, e in ipairs(ordered(spec.events or {})) do
		truthy(S().AddEvent(s, e[1], e[2], e[3], e[4], e[5], e[6], e[7], e[8], e[9]), "event at " .. e[1])
	end
	for _, r in ipairs(spec.rows or {}) do S().AddRow(s, r[1], r[2], r[3], r[4], r[5]) end
	if spec.q then
		for key, list in pairs(spec.q) do for i, v in ipairs(list) do s.q[key][i] = v end end
	end
	S().Join(s)
	s.state, s.ended = spec.state or "complete", spec.ended or "combat"
	s.dur, s.fight, s.trunc = spec.dur or 0, spec.fight or spec.dur or 0, spec.trunc
	return s
end

local function metrics(s) return Mx().Compute(s, assert(S().Decode(s))) end
local function report(s) return R().Compute(s, assert(S().Decode(s))) end
local function timeline(s) return TL().Compute(s, assert(S().Decode(s))) end

local ME = { name = "Testchar", role = "DAMAGER", token = "player", me = true }
local TANK = { name = "Bram", class = "WARRIOR", role = "TANK", token = "party1" }
local KOR = { name = "Kor", class = "ROGUE", role = "DAMAGER", token = "party2" }
local OAK = { name = "Oak", class = "DRUID", role = "TANK", token = "party3" }
local BOSS = { name = "Gorrak", class = "elite", npc = 448 }
local ADD = { name = "Pup", class = "normal" }

-- The fight of test_report.lua and test_timeline.lua: 40 s in values with one of everything.
local function known()
	return {
		units = { ME, TANK, KOR }, mobs = { BOSS, ADD }, dur = 400,
		events = {
			{ 0, "C", 0, 0, 0, "1" }, { 0, "M", 0, 0, 0, "v" }, { 0, "T", 1 },
			{ 0, "A", 1, 2, 0, "1" }, { 0, "S", 1, 2, 0, "S", "-" }, { 0, "S", 1, 1, 0, "S", "-" },
			{ 100, "S", 1, 1, 0, "W", "S" }, { 130, "S", 1, 1, 0, "S", "W" }, { 200, "S", 1, 1, 0, "D", "S" },
			{ 260, "S", 1, 1, 0, "W", "D" }, { 300, "S", 1, 1, 0, "S", "W" },
			{ 310, "A", 1, 3, 2, "0", "1" }, { 320, "S", 1, 3, 0, "D", "-" },
			{ 330, "D", 0, 2, 0, "g" }, { 332, "D", 0, 2, 0, "p" },
			{ 350, "L", 1, 1, 0, "w", "1", "0", "ch" }, { 351, "L", 1, 1, 0, "d", "2", "1", "dh" },
			{ 360, "N", 0, 0, 0, "e", "1" }, { 400, "c" },
		},
		rows = {
			{ 10, 1, 1, 400, "0" }, { 10, 1, 2, 1000, "3" }, { 100, 1, 1, 820, "0" }, { 150, 1, 2, 1000, "3" },
			{ 200, 1, 1, 960, "1" }, { 260, 1, 1, 850, "1" }, { 285, 1, 3, 700, "0" }, { 290, 1, 2, 1000, "3" },
			{ 300, 1, 1, 500, "0" }, { 300, 1, 3, 950, "1" }, { 320, 1, 3, 1000, "3" }, { 330, 2, 1, 100, "0" },
		},
		q = { v = { 80, 80, 80 }, s = { 0, 0, 0 }, x = { 0, 0, 0 } },
	}
end

-- Three units on the boss for 100 s in values, every unit with 3 readings and every sample readable; `events` and
-- `rows` are added, `extra` replaces fields of the spec.
local function fight(events, rows, extra)
	local list = { { 0, "C", 0, 0, 0, "1" }, { 0, "M", 0, 0, 0, "v" }, { 0, "T", 1 }, { 0, "A", 1, 2, 0, "1" },
		{ 0, "S", 1, 1, 0, "S", "-" }, { 0, "S", 1, 2, 0, "S", "-" }, { 0, "S", 1, 3, 0, "S", "-" } }
	for _, e in ipairs(events or {}) do list[#list + 1] = e end
	local spec = { units = { ME, TANK, KOR }, mobs = { BOSS, ADD }, dur = 1000, events = list,
		rows = { { 50, 1, 1, 400, "0" }, { 50, 1, 2, 1000, "3" }, { 50, 1, 3, 300, "0" }, { 150, 1, 1, 420, "0" },
			{ 150, 1, 2, 1000, "3" }, { 150, 1, 3, 310, "0" }, { 250, 1, 1, 440, "0" }, { 250, 1, 2, 1000, "3" },
			{ 250, 1, 3, 320, "0" } },
		q = { v = { 100, 100, 100 }, s = { 0, 0, 0 }, x = { 0, 0, 0 } } }
	for _, r in ipairs(rows or {}) do spec.rows[#spec.rows + 1] = r end
	table.sort(spec.rows, function(a, b) return a[1] < b[1] end)
	for k, v in pairs(extra or {}) do spec[k] = v end
	if not (extra and extra.noEnd) then spec.events[#spec.events + 1] = { spec.dur, "c" } end
	spec.noEnd = nil
	return build(spec)
end

-- Unit `u` rises to Warning at each of `times` (and falls back right after).
local function rises(u, times)
	local out = {}
	for _, t in ipairs(times) do
		out[#out + 1] = { t, "S", 1, u, 0, "W", "S" }
		out[#out + 1] = { t, "S", 1, u, 0, "S", "W" }
	end
	return out
end

local function unitOf(m, index)
	for _, u in ipairs(m.units) do if u.index == index then return u end end
end

local function deepCopy(t)
	if type(t) ~= "table" then return t end
	local out = {}
	for k, v in pairs(t) do out[k] = deepCopy(v) end
	return out
end

local function add(s)
	truthy(St().Add(s))
	truthy(St().Closed(s, true))
	return s
end

describe("the metrics of a known session (SPEC-06 §1.4)", function()
	it("gives the context, the bases and every metric", function()
		local m = metrics(build(known()))
		eq(m.outcome, "values")
		eq(m.key, "npc:448")
		eq(m.mob, 1)
		eq(m.role, "DAMAGER")
		eq(m.group, "party")
		eq(m.combat, 400)
		eq(m.known, 400)
		eq(m.coverage, 100)
		deepEq(m.valid, { state = 100, values = 100 })
		local c = m.cells
		eq(c.context.status, "ok")
		eq(c.context.category, "detected")
		eq(c.context.value.dur, 400)
		eq(c.context.value.pulls, 1)
		eq(c.context.value.mobName, "Gorrak")
		eq(c.context.value.encounter, "success")
		eq(c.context.value.units, 3)
		eq(c.valid.category, "calculated")
		eq(c.valid.value.values, 100)
		eq(c.valid.value.coverage, 100)
		eq(c.crossings.category, "calculated")
		deepEq(c.crossings.value, { warning = 1, danger = 2, units = 3, excluded = 0 })
		eq(c.crossings.basis, "thresholds")
		eq(c.stateTime.category, "calculated")
		eq(c.stateTime.value.warningAny, 210, "[100,130] + [200,300] + [320,400]")
		eq(c.stateTime.value.dangerAny, 140, "[200,260] + [320,400]")
		eq(c.holders.category, "detected")
		eq(c.holders.value.total, 1)
		eq(c.holders.value.toOther, 1)
		eq(c.holders.value.tankToTank, 0)
		eq(c.aggroTaken.value, 1)
		eq(c.maxNotHolding.category, "detected")
		deepEq(c.maxNotHolding.value, { pct = 96, t = 200, unit = 1, mob = 1, rows = 8 })
		eq(c.unstable.value.count, 0, "100, 200, 310, 320: never 3 within 10 s")
		eq(c.unstable.value.changes, 4)
		deepEq(c.risk.value, { situations = 3, perMinute = 4.5, known = 400 })
		eq(c.risk.category, "calculated")
		eq(#c.deaths.value, 1)
		eq(c.alerts.value.count, 2)
		for _, key in ipairs(Mx().SESSION_CELLS) do
			eq(c[key].key, key)
			eq(c[key].status, "ok", key)
			isNil(c[key].lower, key)
		end
		-- the units: the player, the designated tanks, then the index (ANA-01: never by a metric)
		eq(#m.units, 3)
		eq(m.units[1].index, 1)
		eq(m.units[2].index, 2)
		eq(m.units[3].index, 3)
	end)

	it("equals the report's cells and the timeline's crossings on the same session (ANA-03)", function()
		local s = build(known())
		local m, r, tl = metrics(s), report(s), timeline(s)
		local w, d = 0, 0
		for _, ru in ipairs(r.units) do
			local mu = unitOf(m, ru.index)
			for _, key in ipairs(R().UNIT_CELLS) do
				eq(mu.cells[key].status, ru.cells[key].status, key)
				deepEq(mu.cells[key].value, ru.cells[key].value, key)
			end
			w, d = w + ru.cells.warningCross.value, d + ru.cells.dangerCross.value
			local tw, td = 0, 0
			for _, x in ipairs(tl.units[ru.index].crossings) do
				if x[2] == "W" then tw = tw + 1 else td = td + 1 end
			end
			eq(mu.cells.warningCross.value, tw)
			eq(mu.cells.dangerCross.value, td)
		end
		eq(m.cells.crossings.value.warning, w)
		eq(m.cells.crossings.value.danger, d)
		eq(m.cells.aggroTaken.value, #r.rows.aggroLosses.value)
		eq(m.cells.holders.value.tankToTank, #r.rows.tankChanges.value)
		deepEq(m.cells.deaths.value, r.rows.deaths.value)
		deepEq(m.cells.alerts.value, r.rows.alerts.value)
		eq(m.outcome, tl.outcome)
	end)

	it("gives the same metrics from the same data and changes nothing in the session (ANA-03, ANA-05)", function()
		local s = build(known())
		local before = deepCopy(s)
		local d = assert(S().Decode(s))
		local dBefore = deepCopy(d)
		local a = Mx().Compute(s, d)
		deepEq(s, before)
		deepEq(d, dBefore)
		deepEq(Mx().Compute(s, d), a)
	end)

	it("leaves the report as it was with the holder hook (its results unchanged)", function()
		local r = report(build(known()))
		local me
		for _, u in ipairs(r.units) do if u.me then me = u end end
		eq(me.cells.warningTime.value, 70)
		eq(me.cells.dangerTime.value, 60)
		eq(r.rows.tanks.value[1].held, 310)
		eq(#r.rows.aggroLosses.value, 1)
		local calls = {}
		R().Walk(build(known()), assert(S().Decode(build(known()))), nil, {
			holder = function(u, mob, t, e) calls[#calls + 1] = { u, mob, t, e.k } end,
		})
		deepEq(calls, { { 2, 1, 0, "A" }, { 3, 1, 310, "A" } })
	end)
end)

describe("changes of the enemy's holder (§1.4 holders, aggroTaken)", function()
	it("splits them three ways and never counts the first holder", function()
		local s = build{
			units = { ME, TANK, KOR, OAK }, mobs = { BOSS }, dur = 600,
			events = {
				{ 0, "C", 0, 0, 0, "1" }, { 0, "M", 0, 0, 0, "v" }, { 0, "T", 1 },
				{ 0, "A", 1, 2, 0, "1" },                    -- the first holder: not a change
				{ 100, "A", 1, 4, 2, "1", "1" },             -- tank to tank
				{ 200, "A", 1, 3, 4, "0", "1" },             -- to a non-tank
				{ 300, "A", 1, 2, 3, "1", "0" },             -- back to a tank
				{ 400, "A", 1, 1, 0, "0" },                  -- the old holder unknown: taken, not a change
				{ 600, "c" },
			},
			q = { v = { 10, 10, 10, 10 }, s = { 0, 0, 0, 0 }, x = { 0, 0, 0, 0 } },
		}
		local m, r = metrics(s), report(s)
		deepEq(m.cells.holders.value, { total = 3, tankToTank = 1, toOther = 1, backToTank = 1, other = 0, targets = 0 })
		eq(m.cells.aggroTaken.value, 2, "the non-tank and the player, as the report")
		eq(m.cells.aggroTaken.value, #r.rows.aggroLosses.value)
		eq(m.cells.holders.value.tankToTank, #r.rows.tankChanges.value)
		contains(Mx().Text(m, m.cells.holders), "3 times: 1 tank to tank · 1 to a non-tank · 1 back to a tank")
	end)

	it("counts the monitored enemy's own changes in a pull as context", function()
		local m = metrics(fight({ { 300, "T", 2 }, { 500, "T", 1 } }))
		eq(m.cells.holders.value.targets, 2)
		contains(Mx().Text(m, m.cells.holders), "monitored enemy changed 2 times")
		contains(Mx().Text(m, m.cells.holders), "No change of holder recorded")
	end)
end)

describe("ANA-02: Insufficient data under half (§1.1, §1.3)", function()
	it("switches at 50 % on the state base", function()
		local low = metrics(fight(nil, nil, { q = { v = { 49, 49, 49 }, s = { 0, 0, 0 }, x = { 51, 51, 51 } } }))
		eq(low.valid.state, 49)
		for _, key in ipairs({ "crossings", "stateTime", "holders", "aggroTaken", "unstable", "risk" }) do
			eq(low.cells[key].status, "insufficient", key)
			eq(low.cells[key].reason, "low-valid", key)
			eq(low.cells[key].valid, 49, key)
		end
		eq(low.cells.valid.status, "ok", "the valid samples themselves are described")
		eq(unitOf(low, 1).cells.warningCross.status, "insufficient", "the unit's own counters")
		eq(unitOf(low, 1).cells.quality.status, "ok")
		local ok = metrics(fight(nil, nil, { q = { v = { 50, 50, 50 }, s = { 0, 0, 0 }, x = { 50, 50, 50 } } }))
		for _, key in ipairs({ "crossings", "stateTime", "holders", "aggroTaken", "unstable", "risk" }) do
			eq(ok.cells[key].status, "ok", key)
		end
		eq(unitOf(ok, 1).cells.warningCross.status, "ok")
	end)

	it("switches at 50 % on the values base, the state base staying whole", function()
		local low = metrics(fight(nil, nil, { q = { v = { 49, 49, 49 }, s = { 51, 51, 51 }, x = { 0, 0, 0 } } }))
		deepEq(low.valid, { state = 100, values = 49 })
		eq(low.cells.maxNotHolding.status, "insufficient")
		eq(low.cells.maxNotHolding.reason, "low-valid")
		eq(unitOf(low, 1).cells.maxPct.status, "insufficient")
		eq(unitOf(low, 1).cells.maxPct.reason, "low-valid")
		eq(low.cells.crossings.status, "ok")
		local ok = metrics(fight(nil, nil, { q = { v = { 50, 50, 50 }, s = { 50, 50, 50 }, x = { 0, 0, 0 } } }))
		eq(ok.cells.maxNotHolding.status, "ok")
		eq(unitOf(ok, 1).cells.maxPct.status, "ok")
	end)

	it("switches at 50 % of combat with the enemy monitored", function()
		local low = metrics(fight({ { 490, "T", 0, 0, 0, "n" } }))
		eq(low.coverage, 49)
		eq(low.cells.holders.status, "insufficient")
		eq(low.cells.holders.reason, "little-monitored")
		eq(low.cells.holders.coverage, 49)
		eq(low.cells.context.status, "ok")
		local ok = metrics(fight({ { 500, "T", 0, 0, 0, "n" } }))
		eq(ok.coverage, 50)
		eq(ok.cells.holders.status, "ok")
	end)

	it("says no-ticks with no sample at all (§1.2)", function()
		local m = metrics(fight(nil, nil, { q = { v = {}, s = {}, x = {} } }))
		isNil(m.valid)
		eq(m.cells.valid.status, "insufficient")
		eq(m.cells.valid.reason, "no-ticks")
		eq(m.cells.crossings.reason, "no-ticks")
		eq(unitOf(m, 1).cells.warningCross.reason, "no-ticks")
	end)

	it("never shows Not available or Insufficient data as a number (ANA-04)", function()
		local m = metrics(fight(nil, nil, { q = { v = { 49, 49, 49 }, s = { 0, 0, 0 }, x = { 51, 51, 51 } } }))
		eq(Mx().Text(m, m.cells.crossings), "Insufficient data")
		eq(Mx().ReasonText(m.cells.crossings), "Fewer than half the samples readable: 49 %")
		isNil(m.cells.crossings.value)
		local tip = table.concat(Mx().Tooltip(m, m.cells.crossings), "\n")
		contains(tip, "Readable samples: 49 %")
		contains(tip, "Analytics describes a metric only with at least half the samples readable")
	end)
end)

describe("threshold crossings and time in Warning or Danger", function()
	it("counts only the units with enough data and says how many were left out", function()
		-- a fourth unit with a single reading
		local s = build{
			units = { ME, TANK, KOR, OAK }, mobs = { BOSS }, dur = 1000,
			events = { { 0, "C", 0, 0, 0, "1" }, { 0, "M", 0, 0, 0, "v" }, { 0, "T", 1 }, { 0, "S", 1, 1, 0, "S", "-" },
				{ 0, "S", 1, 2, 0, "S", "-" }, { 0, "S", 1, 3, 0, "S", "-" },
				{ 100, "S", 1, 1, 0, "W", "S" }, { 120, "S", 1, 4, 0, "W", "-" }, { 1000, "c" } },
			rows = { { 50, 1, 1, 400, "0" }, { 50, 1, 2, 1000, "3" }, { 50, 1, 3, 300, "0" }, { 100, 1, 4, 850, "1" },
				{ 150, 1, 1, 420, "0" }, { 150, 1, 2, 1000, "3" }, { 150, 1, 3, 310, "0" }, { 250, 1, 1, 440, "0" },
				{ 250, 1, 2, 1000, "3" }, { 250, 1, 3, 320, "0" } },
			q = { v = { 100, 100, 100, 100 }, s = { 0, 0, 0, 0 }, x = { 0, 0, 0, 0 } },
		}
		local m = metrics(s)
		local c = m.cells.crossings
		deepEq(c.value, { warning = 1, danger = 0, units = 3, excluded = 1 })
		eq(c.category, "estimated")
		eq(c.lower, true)
		eq(c.lowerBy.units, true)
		eq(Mx().Text(m, c), "at least 1 Warning · at least 0 Danger · 1 unit with too little data not counted")
		contains(table.concat(Mx().Tooltip(m, c), "\n"), "units with too little data are not counted")
		-- the time in Warning counts every unit, the one with too little data too
		eq(m.cells.stateTime.value.warningAny, 900 - 0, "[100, 1000] of the player and [120, 1000] of Oak")
	end)

	it("is a lower bound with unknown time of the enemy, and says how much", function()
		local m = metrics(fight({ { 100, "S", 1, 1, 0, "W", "S" }, { 300, "M", 0, 0, 0, "n", "S" },
			{ 400, "M", 0, 0, 0, "v" } }))
		eq(m.unknownTime, 100)
		eq(m.known, 900)
		eq(m.coverage, 90)
		local c = m.cells.stateTime
		eq(c.category, "estimated")
		eq(c.lowerBy.unknown, true)
		eq(c.value.unknownTime, 100)
		eq(m.cells.holders.category, "estimated")
		contains(table.concat(Mx().Tooltip(m, c), "\n"), "part of the time is unknown")
	end)

	it("is Insufficient data with less than 1 s known", function()
		local m = metrics(fight(nil, nil, { dur = 8 }))
		eq(m.known, 8)
		eq(m.cells.stateTime.status, "insufficient")
		eq(m.cells.stateTime.reason, "little-known")
		eq(m.cells.holders.status, "ok", "a count needs no minimum of time")
		eq(m.cells.crossings.reason, "no-units", "no unit has 1 s of known state")
		eq(m.cells.risk.status, "insufficient")
		eq(m.cells.risk.reason, "no-units", "the risk takes the state of its parts")
	end)
end)

describe("closest to the tank (§1.4 maxNotHolding)", function()
	it("takes only the rows 0 and 1, never 2, 3 or 4", function()
		local m = metrics(fight(nil, { { 300, 1, 3, 2000, "2" }, { 300, 1, 1, 3000, "4" }, { 350, 1, 1, 1500, "3" },
			{ 400, 1, 3, 900, "1" } }))
		deepEq(m.cells.maxNotHolding.value, { pct = 90, t = 400, unit = 3, mob = 1, rows = 7 })
		eq(Mx().Text(m, m.cells.maxNotHolding), "Kor 90.0 % at 0:40 (not holding the enemy)")
	end)

	it("is a lower bound at the top of the column (3843)", function()
		local m = metrics(fight(nil, { { 400, 1, 3, 3843, "1" } }))
		local c = m.cells.maxNotHolding
		eq(c.value.pct, 384.3)
		eq(c.category, "estimated")
		eq(c.lower, true)
		eq(c.lowerBy.cap, true)
		eq(Mx().Text(m, c), "Kor at least 384.3 % at 0:40 (not holding the enemy)")
	end)

	it("needs 3 rows of units not holding the enemy", function()
		local s = build{
			units = { ME, TANK }, mobs = { BOSS }, dur = 1000,
			events = { { 0, "C", 0, 0, 0, "1" }, { 0, "M", 0, 0, 0, "v" }, { 0, "T", 1 }, { 1000, "c" } },
			rows = { { 50, 1, 1, 400, "0" }, { 50, 1, 2, 1000, "3" }, { 150, 1, 1, 420, "1" }, { 150, 1, 2, 1000, "3" },
				{ 250, 1, 1, 440, "2" }, { 250, 1, 2, 1000, "3" } },
			q = { v = { 100, 100 }, s = { 0, 0 }, x = { 0, 0 } },
		}
		local m = metrics(s)
		eq(m.cells.maxNotHolding.status, "insufficient")
		eq(m.cells.maxNotHolding.reason, "few-not-holding")
		eq(Mx().ReasonText(m.cells.maxNotHolding), "Fewer than 3 readings of units not holding the enemy.")
	end)
end)

describe("unstable intervals (§1.5)", function()
	local function unstable(times, extra)
		return metrics(fight(rises(1, times), nil, extra)).cells.unstable.value
	end

	it("finds 3 changes within 10 s, and not within 10.1 s", function()
		local v = unstable({ 100, 150, 200 })
		eq(v.count, 1)
		deepEq(v.list[1], { from = 100, to = 200, holders = 0, crossings = 3 })
		eq(v.total, 100)
		eq(unstable({ 100, 150, 201 }).count, 0)
	end)

	it("needs 3 changes (K)", function()
		eq(unstable({ 100, 101 }).count, 0)
		eq(unstable({ 100, 101, 102 }).count, 1)
	end)

	it("joins intervals that touch or overlap", function()
		local v = unstable({ 100, 150, 200, 250, 600, 650, 700 })
		eq(v.count, 2)
		deepEq(v.list[1], { from = 100, to = 250, holders = 0, crossings = 4 })
		deepEq(v.list[2], { from = 600, to = 700, holders = 0, crossings = 3 })
		eq(v.total, 250)
		local m = metrics(fight(rises(1, { 100, 150, 200, 250, 600, 650, 700 })))
		eq(Mx().Text(m, m.cells.unstable), "2 intervals, 0:25 in all")
		eq(Mx().IntervalText(v.list[1]), "0:10–0:25 · 4 changes")
	end)

	it("counts the changes of holder with the crossings", function()
		local m = metrics(fight({ { 100, "S", 1, 1, 0, "W", "S" }, { 120, "A", 1, 3, 2, "0", "1" },
			{ 150, "A", 1, 2, 3, "1", "0" } }))
		deepEq(m.cells.unstable.value.list[1], { from = 100, to = 150, holders = 2, crossings = 1 })
	end)

	it("never joins across a pause between two pulls", function()
		local events = rises(1, { 480, 490 })
		events[#events + 1] = { 500, "c" }
		events[#events + 1] = { 500, "C", 0, 0, 0, "2" }
		events[#events + 1] = { 505, "S", 1, 1, 0, "W", "S" }
		local m = metrics(fight(events))
		eq(m.cells.context.value.pulls, 2)
		eq(m.cells.unstable.value.changes, 3)
		eq(m.cells.unstable.value.count, 0)
	end)

	it("is a moment when three changes share one tenth", function()
		local m = metrics(fight({ { 300, "S", 1, 1, 0, "W", "S" }, { 300, "S", 1, 2, 0, "W", "S" },
			{ 300, "S", 1, 3, 0, "W", "S" } }))
		local v = m.cells.unstable.value
		deepEq(v.list[1], { from = 300, to = 300, holders = 0, crossings = 3, moment = true })
		eq(v.total, 0)
		eq(Mx().IntervalText(v.list[1]), "at 0:30 · 3 changes")
		eq(Mx().Text(m, m.cells.unstable), "1 interval, 0:00 in all")
	end)

	it("lists at most MAX_UNSTABLE and counts them all", function()
		local times = {}
		for i = 0, 24 do
			for k = 0, 2 do times[#times + 1] = 30 + i * 110 + k end
		end
		local v = unstable(times, { dur = 3000 })
		eq(v.count, 25)
		eq(#v.list, 20)
	end)

	it("says no unstable interval recorded, never stable", function()
		local m = metrics(fight())
		eq(Mx().Text(m, m.cells.unstable), "No unstable interval recorded")
	end)
end)

describe("risk situations (§1.4 risk)", function()
	it("is Insufficient data under 30 s of known combat, and a rate from 30 s", function()
		local short = metrics(fight({ { 100, "S", 1, 1, 0, "D", "S" } }, nil, { dur = 299 }))
		eq(short.cells.risk.status, "insufficient")
		eq(short.cells.risk.reason, "short-known")
		local enough = metrics(fight({ { 100, "S", 1, 1, 0, "D", "S" }, { 200, "A", 1, 3, 2, "0", "1" } }, nil,
			{ dur = 300 }))
		deepEq(enough.cells.risk.value, { situations = 2, perMinute = 4, known = 300 })
		eq(Mx().Text(enough, enough.cells.risk), "2 · 4.0 per minute of known combat")
	end)
end)

describe("the three outcomes, mixed, interrupted, truncated, limit and linked sessions (§0, §1.6)", function()
	it("gives state only: no percentages, the states on the game's", function()
		local s = build{
			units = { ME, TANK }, mobs = { BOSS }, dur = 1000, rec = { hz = 2, mode = "state" },
			events = { { 0, "C", 0, 0, 0, "1" }, { 0, "M", 0, 0, 0, "s" }, { 0, "T", 1 }, { 0, "A", 1, 2, 0, "1" },
				{ 0, "S", 1, 1, 0, "S", "-" }, { 0, "S", 1, 2, 0, "S", "-" }, { 100, "S", 1, 1, 0, "W", "S" },
				{ 200, "S", 1, 1, 0, "D", "W" },
				{ 1000, "c" } },
			rows = { { 50, 1, 1, -1, "a" }, { 50, 1, 2, -1, "d" }, { 150, 1, 1, -1, "b" }, { 150, 1, 2, -1, "d" },
				{ 250, 1, 1, -1, "b" }, { 250, 1, 2, -1, "d" } },
			q = { v = { 0, 0 }, s = { 100, 100 }, x = { 0, 0 } },
		}
		local m = metrics(s)
		eq(m.outcome, "state")
		eq(m.outcome, timeline(s).outcome)
		deepEq(m.valid, { state = 100, values = 0 })
		eq(m.cells.maxNotHolding.status, "na")
		eq(m.cells.maxNotHolding.reason, "state-only")
		eq(unitOf(m, 1).cells.maxPct.status, "na")
		eq(m.cells.crossings.status, "ok")
		eq(m.cells.crossings.basis, "game")
		deepEq(m.cells.crossings.value, { warning = 1, danger = 1, units = 2, excluded = 0 })
		eq(m.cells.stateTime.value.warningAny, 900)
		eq(m.cells.holders.status, "ok")
		eq(Mx().Text(m, m.cells.maxNotHolding), "Not available")
		contains(table.concat(Mx().Tooltip(m, m.cells.crossings), "\n"), "Game states")
	end)

	it("gives nothing readable: the context and the valid samples only", function()
		local s = build{
			units = { ME, TANK }, mobs = { BOSS }, dur = 1000, rec = { hz = 2, mode = "none" },
			events = { { 0, "C", 0, 0, 0, "1" }, { 0, "M", 0, 0, 0, "n", "S" }, { 0, "T", 1 },
				{ 500, "D", 0, 1, 0, "g" }, { 1000, "c" } },
			rows = { { 50, 1, 1, -1, "S" }, { 50, 1, 2, -1, "S" }, { 150, 1, 1, -1, "S" } },
			q = { v = { 0, 0 }, s = { 0, 0 }, x = { 10, 10 } },
		}
		local m = metrics(s)
		eq(m.outcome, "none")
		eq(m.outcome, timeline(s).outcome)
		eq(m.cells.context.status, "ok")
		eq(m.cells.valid.status, "ok")
		eq(m.cells.valid.value.unknown, 100)
		eq(m.cells.valid.reason, "secret")
		eq(m.cells.deaths.status, "ok")
		eq(#m.cells.deaths.value, 1)
		for _, key in ipairs({ "crossings", "stateTime", "holders", "aggroTaken", "maxNotHolding", "unstable", "risk",
			"alerts" }) do
			eq(m.cells[key].status, "na", key)
			eq(m.cells[key].reason, "secret", key)
		end
		contains(Mx().Text(m, m.cells.valid), "Unknown 100 %")
	end)

	it("gives a mixed session the basis of both", function()
		local s = build{
			units = { ME, TANK }, mobs = { BOSS }, dur = 1000,
			events = { { 0, "C", 0, 0, 0, "1" }, { 0, "M", 0, 0, 0, "v" }, { 0, "T", 1 }, { 0, "A", 1, 2, 0, "1" },
				{ 0, "S", 1, 1, 0, "S", "-" }, { 0, "S", 1, 2, 0, "S", "-" }, { 100, "S", 1, 1, 0, "W", "S" },
				{ 200, "S", 1, 1, 0, "S", "W" },
				{ 500, "M", 0, 0, 0, "s" }, { 600, "S", 1, 1, 0, "D", "S" }, { 1000, "c" } },
			rows = { { 50, 1, 1, 400, "0" }, { 50, 1, 2, 1000, "3" }, { 150, 1, 1, 850, "1" }, { 150, 1, 2, 1000, "3" },
				{ 250, 1, 1, 500, "0" }, { 250, 1, 2, 1000, "3" }, { 550, 1, 1, -1, "a" }, { 650, 1, 1, -1, "b" } },
			q = { v = { 50, 50 }, s = { 50, 50 }, x = { 0, 0 } },
		}
		local m = metrics(s)
		eq(m.outcome, "mixed")
		eq(m.outcome, timeline(s).outcome)
		eq(m.cells.crossings.basis, "mixed")
		deepEq(m.cells.crossings.value, { warning = 1, danger = 1, units = 2, excluded = 0 })
		eq(m.cells.maxNotHolding.value.pct, 85, "the percentages of the values stretch only")
		contains(table.concat(Mx().Tooltip(m, m.cells.crossings), "\n"), "Game states and thresholds")
	end)

	it("gives an interrupted session its values up to the last record, the length at least", function()
		local m = metrics(fight({ { 100, "S", 1, 1, 0, "W", "S" }, { 600, "X" } }, nil,
			{ state = "interrupted", ended = "reload", dur = 600, fight = 0, noEnd = true }))
		eq(m.state, "interrupted")
		eq(m.combat, 600)
		eq(m.recordedUntil, 600)
		eq(m.cells.context.lower, true)
		eq(m.cells.context["until"], 600)
		isNil(m.cells.context.value.fight, "a fight of 0 in an interrupted session is unknown")
		eq(m.cells.stateTime.value.warningAny, 500)
		contains(Mx().Text(m, m.cells.context), "at least 1:00")
		contains(table.concat(Mx().Tooltip(m, m.cells.stateTime), "\n"), "Recorded until 1:00")
	end)

	it("stops the sample metrics at `trunc` and says so", function()
		local m = metrics(fight(nil, nil, { trunc = 300 }))
		eq(m.trunc, 300)
		eq(m.cells.maxNotHolding.truncated, true)
		eq(m.cells.maxNotHolding["until"], 300)
		eq(m.cells.valid.truncated, true)
		isNil(m.cells.holders.truncated, "the events go on")
		contains(table.concat(Mx().Tooltip(m, m.cells.maxNotHolding), "\n"), "Samples stopped at 0:30")
	end)

	it("makes the metrics from the events lower bounds when they stopped at their limit (Z e)", function()
		local m = metrics(fight({ { 100, "S", 1, 1, 0, "W", "S" }, { 900, "Z", 0, 0, 0, "e" } }))
		eq(m.eventsCut, true)
		for _, key in ipairs({ "crossings", "stateTime", "holders", "aggroTaken", "unstable", "risk" }) do
			eq(m.cells[key].category, "estimated", key)
			eq(m.cells[key].lowerBy.events, true, key)
		end
		eq(m.cells.maxNotHolding.category, "detected", "the samples are not events")
		contains(table.concat(Mx().Tooltip(m, m.cells.holders), "\n"), "the events stopped at their limit")
	end)

	it("keeps a linked session apart, with its link", function()
		local first = fight()
		local m = metrics(fight(nil, nil, { after = first.id }))
		eq(m.after, first.id)
		eq(m.cells.context.value.after, first.id)
		eq(m.combat, 1000, "no union with the session before")
	end)

	it("gives no key without a readable enemy, and the name key without a creature number", function()
		eq(Mx().Key({ mobs = { { name = "Pup", class = "normal" } } }, 1), "name:Pup:normal")
		eq(Mx().Key({ mobs = { { npc = 448, name = "Gorrak" } } }, 1), "npc:448")
		isNil(Mx().Key({ mobs = { {} } }, 1))
		isNil(Mx().Key({ mobs = {} }, nil))
	end)
end)

describe("recordings of the real recorder", function()
	for _, outcome in ipairs(Fight.OUTCOMES) do
		it("give the metrics of a party fight in " .. outcome, function()
			local pull = Fight.new{
				player = { class = "MAGE", role = "DAMAGER", ranged = true },
				party = { { key = "tank", role = "TANK", name = "Bram" }, { key = "healer", class = "PRIEST" } },
				mobs = { { key = "boss", tokens = { "target", "boss1" }, classification = "worldboss", name = "Gorrak" } },
			}
			pull:outcome(outcome)
			pull:at(0):start():threat("boss", "tank", 1000):threat("boss", "player", { raw = 500, scaled = 40 })
			pull:at(5):threat("boss", "player", { raw = 900, scaled = 85 })
			pull:at(10):threat("boss", "player", { raw = 1200, scaled = 120 }):aggro("boss", "player")
			pull:at(40):stop()
			pull:finish()
			Mock.Advance(7)
			local list = St().List()
			eq(#list, 1)
			local m
			Mx().Build(list[1].id, function(result) m = result end)
			Mock.Advance(1)
			notNil(m)
			local s = St().Get(list[1].id)
			local r, tl = report(s), timeline(s)
			eq(m.outcome, tl.outcome)
			eq(m.dur, r.dur)
			for _, ru in ipairs(r.units) do
				local mu = unitOf(m, ru.index)
				for _, key in ipairs(R().UNIT_CELLS) do
					if mu.cells[key].status == "ok" then deepEq(mu.cells[key].value, ru.cells[key].value, key) end
				end
			end
			for _, key in ipairs(Mx().SESSION_CELLS) do
				local c = m.cells[key]
				truthy(c.status == "ok" or c.status == "na" or c.status == "insufficient", key)
				truthy(#Mx().Text(m, c) > 0, key)
				truthy(#Mx().Tooltip(m, c) > 0, key)
				if c.status ~= "ok" then isNil(c.value, key) end
			end
			if outcome == "values" then
				eq(m.cells.crossings.status, "ok")
				eq(m.cells.maxNotHolding.status, "ok")
				eq(m.cells.aggroTaken.value, #r.rows.aggroLosses.value)
			elseif outcome == "state" then
				eq(m.cells.maxNotHolding.status, "na")
				eq(m.cells.maxNotHolding.reason, "state-only")
				eq(m.cells.crossings.status, "ok")
			else
				eq(m.cells.crossings.status, "na")
				eq(m.cells.context.status, "ok")
				eq(m.cells.deaths.status, "ok")
			end
			eq(#Mock.errors, 0)
		end)
	end
end)

describe("Build (§1.7)", function()
	it("gives the same metrics in slices as in one pass, over several frames", function()
		local s = add(build(known()))
		local whole = metrics(s)
		Mx().SLICE = 3
		local got, calls = nil, 0
		Mx().Build(s.id, function(m) got, calls = m, calls + 1 end)
		isNil(got, "more frames to go")
		for _ = 1, 80 do Mock.Advance(0.05) end
		eq(calls, 1)
		deepEq(got, whole)
		eq(Mx().Cached(s.id), got)
		truthy(Mx().stats.frames > 1)
		Mx().Build(s.id, function(m) eq(m, got, "from memory") calls = calls + 1 end)
		eq(calls, 2)
		eq(#Mock.errors, 0)
	end)

	it("leaves the session as it was (ANA-05)", function()
		local s = add(build(known()))
		local before = deepCopy(s)
		local got
		Mx().Build(s.id, function(m) got = m end)
		notNil(got)
		deepEq(St().Get(s.id), before)
	end)

	it("keeps at most CACHE sessions, the least used going first", function()
		Mx().CACHE = 2
		local a, b, c = add(build(known())), add(build(known())), add(build(known()))
		local function build1(s) local m Mx().Build(s.id, function(x) m = x end) return m end
		build1(a)
		build1(b)
		build1(a)                                   -- a used again: b is now the least used
		build1(c)
		eq(Mx().CacheSize(), 2)
		notNil(Mx().Cached(a.id))
		isNil(Mx().Cached(b.id))
		notNil(Mx().Cached(c.id))
	end)

	it("drops what is gone at SESSIONS_CHANGED, and refuses an unknown, damaged or open session", function()
		local why
		local function done(_, reason) why = reason end
		Mx().Build("nope", done)
		eq(why, "unknown")
		local s = add(build(known()))
		Mx().Build(s.id, function() end)
		eq(Mx().CacheSize(), 1)
		truthy(St().Delete(s.id))
		eq(Mx().CacheSize(), 0)
		isNil(Mx().Cached(s.id))
		local bad = add(build(known()))
		bad.cols.s = string.rep("?", bad.n)
		Mx().Build(bad.id, done)
		eq(why, "damaged")
		local open = build(known())
		open.state = "open"
		St().Add(open)
		Mx().Build(open.id, done)
		eq(why, "recording")
	end)

	it("stops when the session goes while it is being built", function()
		local s = add(build(known()))
		Mx().SLICE = 3
		local why
		Mx().Build(s.id, function(_, reason) why = reason end)
		truthy(St().Delete(s.id))
		for _ = 1, 80 do Mock.Advance(0.05) end
		eq(why, "unknown")
	end)

	it("writes its lines in /atw debug, with counts only", function()
		local s = add(build(known()))
		local text = Mock.ns.Diagnostics.Report()
		contains(text, "== Analytics and export ==")
		contains(text, "switches: analytics on, export off")
		contains(text, "metrics cache: 0 of 25 sessions")
		contains(text, "metrics last build: none")
		Mx().Build(s.id, function() end)
		text = Mock.ns.Diagnostics.Report()
		contains(text, "metrics cache: 1 of 25 sessions")
		contains(text, "over 1 frames, 1 builds")
		falsy(text:find("Gorrak", 1, true), "no enemy name")
		falsy(text:find("Bram", 1, true), "no unit name")
	end)
end)

describe("the words (ANALYTICS_* keys)", function()
	it("have a text and a tooltip for every cell, with the category", function()
		local m = metrics(build(known()))
		eq(Mx().Text(m, m.cells.context), "0:40 · 0:40 in combat · Gorrak · Elite")
		eq(Mx().Text(m, m.cells.valid), "Values 100 % · State only 0 % · Unknown 0 % · enemy monitored 100 % of combat")
		eq(Mx().Text(m, m.cells.crossings), "1 Warning · 2 Danger")
		eq(Mx().Text(m, m.cells.stateTime), "0:21 in Warning or Danger · 0:14 in Danger")
		eq(Mx().Text(m, m.cells.holders), "1 times: 0 tank to tank · 1 to a non-tank · 0 back to a tank")
		eq(Mx().Text(m, m.cells.aggroTaken), "1")
		eq(Mx().Text(m, m.cells.maxNotHolding), "Testchar 96.0 % at 0:20 (not holding the enemy)")
		eq(Mx().Text(m, m.cells.risk), "3 · 4.5 per minute of known combat")
		contains(Mx().Text(m, m.cells.deaths), "Bram died")
		contains(Mx().Text(m, m.cells.alerts), "Alerts: 2")
		for _, key in ipairs(Mx().SESSION_CELLS) do
			local tip = Mx().Tooltip(m, m.cells[key])
			notNil(Mock.ns.L[Mx().METRIC_KEYS[key]], key)
			truthy(#tip >= 2, key)
		end
		contains(table.concat(Mx().Tooltip(m, m.cells.crossings), "\n"), "Category: calculated")
		contains(table.concat(Mx().Tooltip(m, m.cells.crossings), "\n"), "Warning from 80 %, Danger from 95 %")
	end)
end)

describe("with the `analytics` switch off (ADR 0014)", function()
	before_boot(function(M)
		M.features = { monitor = true, alerts = true, coach = true, recording = true, reports = true, timeline = true,
			analytics = false }
	end)

	it("builds nothing and listens to nothing", function()
		local s = add(build(known()))
		local why
		Mx().Build(s.id, function(_, reason) why = reason end)
		eq(why, "off")
		isNil(Mx().Cached(s.id))
		eq(Mx().CacheSize(), 0)
		falsy(Mx().Listening())
		contains(Mock.ns.Diagnostics.Report(), "switches: analytics off, export off")
	end)
end)
