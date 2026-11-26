-- Data/Compare.lua (SPEC-06 §2, §5, §6 M6.3; ANA-01, ANA-04; ADR 0003, 0018; Q23): the keys (creature number, name and
-- classification, none); the filters (group, unknown difficulty, role); different thresholds, game states against
-- thresholds, mixed, percentages only between fights with values; the aggregates (odd and even median, total, lowest,
-- highest, the weighted risk rate), lower bounds passed on, MIN_FIGHTS, MAX_FIGHTS with the older fights counted;
-- interrupted and linked fights; the overview from the headers only (nothing decoded); the queue paused in combat and
-- resumed; a session deleted or damaged while building; SESSIONS_CHANGED afterwards; the words; the switch off.

before_boot(function(M)
	M.features = { monitor = true, alerts = true, coach = true, recording = true, reports = true, timeline = true,
		analytics = true }
end)

local function C() return Mock.ns.Compare end
local function Mx() return Mock.ns.Metrics end
local function S() return Mock.ns.Session end
local function St() return Mock.ns.Storage end

local counter = 0

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

local TANK = { name = "Bram", class = "WARRIOR", role = "TANK", token = "party1" }
local KOR = { name = "Kor", class = "ROGUE", role = "DAMAGER", token = "party2" }
local BOSS = { name = "Gorrak", class = "elite", npc = 448 }
local NAMED = { name = "Gorrak", class = "elite" }
local NAMELESS = { class = "normal" }

-- A recorded fight against one enemy, stored and summarized like a closed recording. o: started, group, diff (false:
-- unknown), role, mode ("values" or "state"), rec, mob, dur, warn and danger (times the player rises), taken (times
-- Kor takes the enemy), peak (the player's last reading), cut (the events at their limit), interrupted, after.
local function session(o)
	o = o or {}
	counter = counter + 1
	local mode = o.mode or "values"
	local diff = o.diff
	if diff == nil then diff = 1 elseif diff == false then diff = nil end
	local s = S().New{ id = "cmp-" .. counter, started = o.started or (5000 + counter * 10), group = o.group or "party",
		diff = diff, after = o.after, rec = o.rec or { hz = 2, warning = 80, danger = 95, mode = mode } }
	local me = { name = "Testchar", role = o.role or "DAMAGER", token = "player", me = true }
	for _, u in ipairs({ me, TANK, KOR }) do S().AddUnit(s, u, 0) end
	S().AddMob(s, o.mob or BOSS, 0)
	local dur = o.dur or 1000
	local events = { { 0, "C", 0, 0, 0, "1" }, { 0, "M", 0, 0, 0, mode == "state" and "s" or "v" }, { 0, "T", 1 },
		{ 0, "A", 1, 2, 0, "1" }, { 0, "S", 1, 1, 0, "S", "-" }, { 0, "S", 1, 2, 0, "S", "-" },
		{ 0, "S", 1, 3, 0, "S", "-" } }
	for _, t in ipairs(o.warn or {}) do
		events[#events + 1] = { t, "S", 1, 1, 0, "W", "S" }
		events[#events + 1] = { t + 1, "S", 1, 1, 0, "S", "W" }
	end
	for _, t in ipairs(o.danger or {}) do
		events[#events + 1] = { t, "S", 1, 1, 0, "D", "S" }
		events[#events + 1] = { t + 1, "S", 1, 1, 0, "S", "D" }
	end
	for _, t in ipairs(o.taken or {}) do
		events[#events + 1] = { t, "A", 1, 3, 2, "0", "1" }
		events[#events + 1] = { t + 5, "A", 1, 2, 3, "1", "0" }
	end
	if o.cut then events[#events + 1] = { dur - 100, "Z", 0, 0, 0, "e" } end
	events[#events + 1] = { dur, o.interrupted and "X" or "c" }
	for _, e in ipairs(ordered(events)) do
		truthy(S().AddEvent(s, e[1], e[2], e[3], e[4], e[5], e[6], e[7], e[8], e[9]), "event at " .. e[1])
	end
	for i, t in ipairs({ 50, 150, 250 }) do
		if mode == "state" then
			S().AddRow(s, t, 1, 1, -1, "a")
			S().AddRow(s, t, 1, 2, -1, "d")
			S().AddRow(s, t, 1, 3, -1, "b")
		else
			S().AddRow(s, t, 1, 1, i == 3 and (o.peak or 440) or 400 + i * 10, "0")
			S().AddRow(s, t, 1, 2, 1000, "3")
			S().AddRow(s, t, 1, 3, 300 + i, "0")
		end
	end
	for i = 1, 3 do
		if mode == "state" then s.q.s[i] = 100 else s.q.v[i] = 100 end
	end
	S().Join(s)
	s.state, s.ended = o.interrupted and "interrupted" or "complete", o.interrupted and "reload" or "combat"
	s.dur, s.fight = dur, o.interrupted and 0 or dur
	truthy(St().Add(s))
	truthy(St().Closed(s, true))
	return s
end

local KEY = "npc:448"

local function frames(n)
	for _ = 1, n or 200 do Mock.Advance(0.05) end
end

-- Compare.Build to the end: the result (or nil and the reason) and the calls of progress.
local function compare(key, filters)
	local got, why, calls = nil, nil, {}
	local finished = false
	C().Build(key, filters, function(i, n, paused) calls[#calls + 1] = { i, n, paused } end, function(result, reason)
		got, why, finished = result, reason, true
	end)
	for _ = 1, 400 do
		if finished then break end
		Mock.Advance(0.05)
	end
	truthy(finished, "the comparison finished")
	return got, why, calls
end

local function rowOf(result, s)
	for _, row in ipairs(result.rows) do if row.id == s.id then return row end end
end

local function idsOf(list)
	local out = {}
	for i, x in ipairs(list) do out[i] = x.id end
	return out
end

describe("the key of a fight (§2.1)", function()
	it("is the creature number, else the name and classification, else none, the same as the metrics'", function()
		local a, b, c = session(), session{ mob = NAMED }, session{ mob = NAMELESS }
		local keys = {}
		for _, h in ipairs(St().List()) do keys[h.id] = C().HeaderKey(h) end
		eq(keys[a.id], "npc:448")
		eq(keys[b.id], "name:Gorrak:elite", "same name, no creature number: another key")
		isNil(keys[c.id])
		for _, s in ipairs({ a, b, c }) do
			local m = Mx().Compute(s, assert(S().Decode(s)))
			eq(keys[s.id], m.key, s.id)
		end
		local _, why = compare(nil)
		eq(why, "no-key")
		eq(Mock.ns.L.ANALYTICS_UNKNOWN_ENEMY, C().KeyText(nil))
	end)

	it("never takes the open recording", function()
		session()
		local open = S().New{ id = "cmp-open", started = 99999, group = "party", diff = 1, rec = {} }
		S().AddUnit(open, { name = "Testchar", me = true, role = "DAMAGER" }, 0)
		S().AddMob(open, BOSS, 0)
		open.sum = { mob = 1 }
		St().Add(open)
		local set = C().Set(KEY)
		eq(#set.fights, 1)
		eq(set.total, 1)
	end)
end)

describe("the filters (§2.1, Q23)", function()
	it("keep the same group size, difficulty and role as the most recent fight", function()
		local raid = session{ group = "raid" }
		local heroic = session{ diff = 2 }
		local healer = session{ role = "HEALER" }
		local unknown = session{ diff = false }
		local newest = session()
		local set = C().Set(KEY)
		deepEq(set.ref, { group = "party", diff = 1, role = "DAMAGER" })
		deepEq(idsOf(set.fights), { newest.id, unknown.id }, "a fight with no difficulty passes")
		local why = {}
		for _, x in ipairs(set.excluded) do why[x.id] = x.reason end
		deepEq(why, { [raid.id] = "group", [heroic.id] = "diff", [healer.id] = "role" })
		local result = compare(KEY)
		eq(rowOf(result, unknown).diffUnknown, true)
		contains(table.concat(C().RowNotes(rowOf(result, unknown)), "\n"), "Difficulty not recorded")
		contains(table.concat(C().NoteLines(result), "\n"), "3 fights left out by the filters")
	end)

	it("let every fight in when off, the player's columns not comparable with another role", function()
		local raid = session{ group = "raid", warn = { 100 } }
		local healer = session{ role = "HEALER", warn = { 100, 200 } }
		local newest = session{ warn = { 100, 200, 300 } }
		local result = compare(KEY, { group = false, diff = false, role = false })
		eq(#result.rows, 3)
		local mine = C().MEASURE.myWarningCross
		local v = C().Value(rowOf(result, healer), mine)
		eq(v.status, "not-comparable")
		eq(C().CellText(mine, v), "Not comparable: another role")
		eq(C().Value(rowOf(result, raid), mine).status, "ok")
		eq(C().Value(rowOf(result, newest), mine).value, 3)
		eq(result.aggregates.myWarningCross.n, 2, "the healer's fight is out of the player's aggregate")
		eq(result.aggregates.warningCross.n, 3, "the fight's own metrics are compared with every role")
	end)
end)

describe("what is comparable on each metric (§2.1)", function()
	it("never aggregates fights with different thresholds", function()
		local old = session{ rec = { hz = 2, warning = 82, danger = 91, mode = "values" }, warn = { 100 } }
		local a = session{ warn = { 100, 200 } }
		local b = session{ warn = { 100, 200, 300 }, taken = { 400 } }
		local result = compare(KEY)
		eq(result.basis, "thresholds:80/95")
		local row = rowOf(result, old)
		deepEq(row.nc.state, { reason = "basis", basis = "thresholds:82/91", ref = "thresholds:80/95" })
		local ms = C().MEASURE.warningCross
		local v = C().Value(row, ms)
		eq(v.status, "not-comparable")
		eq(C().CellText(ms, v), "Not comparable: thresholds 82 / 91 and 80 / 95")
		local agg = result.aggregates.warningCross
		eq(agg.n, 2)
		eq(agg.of, 3)
		eq(agg.total, 5, "2 + 3, never the 1 of the other thresholds")
		eq(C().CountText(agg), "2 of 3 fights")
		-- what does not depend on the thresholds is compared with every fight
		eq(result.aggregates.holders.n, 3)
		eq(result.aggregates.aggroTaken.n, 3)
		eq(result.aggregates.aggroTaken.total, 1)
		eq(result.aggregates.closest.n, 3)
		notNil(b)
		notNil(a)
	end)

	it("keeps game states and thresholds apart, and the percentages to fights with values", function()
		local v1 = session{ warn = { 100 } }
		local v2 = session{ warn = { 100, 200 } }
		local st = session{ mode = "state", warn = { 100, 200, 300 } }
		local result = compare(KEY)
		eq(result.basis, "game", "the most recent fight decides")
		eq(C().Value(rowOf(result, v1), C().MEASURE.warningCross).status, "not-comparable")
		eq(C().CellText(C().MEASURE.warningCross, C().Value(rowOf(result, v2), C().MEASURE.warningCross)),
			"Not comparable: thresholds 80 / 95 (compared: game states)")
		eq(result.aggregates.warningCross.status, "insufficient")
		eq(result.aggregates.warningCross.reason, "one-fight")
		eq(C().AggregateText(result.aggregates.warningCross, "total"), "Only one comparable fight")
		-- the percentages: only the two fights with values, never the state-only one
		local closest = result.aggregates.closest
		eq(closest.n, 2)
		eq(C().Value(rowOf(result, st), C().MEASURE.closest).status, "na")
		eq(result.aggregates.holders.n, 3)
	end)

	it("compares a mixed fight only with mixed fights of the same thresholds", function()
		local function mixed()
			counter = counter + 1
			local s = S().New{ id = "cmp-mixed-" .. counter, started = 5000 + counter * 10, group = "party", diff = 1,
				rec = { hz = 2, warning = 80, danger = 95, mode = "values" } }
			S().AddUnit(s, { name = "Testchar", role = "DAMAGER", token = "player", me = true }, 0)
			S().AddUnit(s, TANK, 0)
			S().AddMob(s, BOSS, 0)
			for _, e in ipairs({ { 0, "C", 0, 0, 0, "1" }, { 0, "M", 0, 0, 0, "v" }, { 0, "T", 1 },
				{ 0, "A", 1, 2, 0, "1" }, { 0, "S", 1, 1, 0, "S", "-" }, { 0, "S", 1, 2, 0, "S", "-" },
				{ 100, "S", 1, 1, 0, "W", "S" }, { 200, "S", 1, 1, 0, "S", "W" }, { 500, "M", 0, 0, 0, "s" },
				{ 600, "S", 1, 1, 0, "D", "S" }, { 1000, "c" } }) do
				S().AddEvent(s, e[1], e[2], e[3], e[4], e[5], e[6], e[7])
			end
			for _, r in ipairs({ { 50, 1, 1, 400, "0" }, { 50, 1, 2, 1000, "3" }, { 150, 1, 1, 850, "1" },
				{ 150, 1, 2, 1000, "3" }, { 250, 1, 1, 500, "0" }, { 250, 1, 2, 1000, "3" }, { 550, 1, 1, -1, "a" },
				{ 650, 1, 1, -1, "b" } }) do
				S().AddRow(s, r[1], r[2], r[3], r[4], r[5])
			end
			s.q.v[1], s.q.v[2], s.q.s[1], s.q.s[2] = 50, 50, 50, 50
			S().Join(s)
			s.state, s.ended, s.dur, s.fight = "complete", "combat", 1000, 1000
			St().Add(s)
			St().Closed(s, true)
			return s
		end
		local plain = session{ warn = { 100 } }
		mixed()
		mixed()
		local result = compare(KEY)
		eq(result.basis, "mixed:80/95")
		eq(result.aggregates.warningCross.n, 2)
		eq(result.aggregates.dangerCross.total, 2)
		eq(C().CellText(C().MEASURE.warningCross, C().Value(rowOf(result, plain), C().MEASURE.warningCross)),
			"Not comparable: thresholds 80 / 95 (compared: thresholds 80 / 95 and game states)")
	end)
end)

describe("the aggregates (§2.2)", function()
	it("give the total, the median of an odd count, the lowest and highest with their fight", function()
		local a = session{ warn = { 100 } }
		local b = session{ warn = { 100, 200, 300, 400, 500 } }
		local c = session{ warn = { 100, 200 } }
		local agg = compare(KEY).aggregates.warningCross
		eq(agg.status, "ok")
		eq(agg.category, "calculated")
		eq(agg.n, 3)
		eq(agg.total, 8)
		eq(agg.median, 2)
		eq(agg.min.value, 1)
		eq(agg.min.id, a.id)
		eq(agg.min.started, a.started)
		eq(agg.max.value, 5)
		eq(agg.max.id, b.id)
		eq(C().AggregateText(agg, "total"), "8")
		eq(C().AggregateText(agg, "median"), "2")
		eq(C().AggregateText(agg, "min"), "1")
		eq(C().AggregateText(agg, "max"), "5")
		notNil(c)
	end)

	it("give the median of an even count with one decimal, and ties to the most recent fight", function()
		session{ warn = { 100 } }
		session{ warn = { 100, 200 } }
		session{ warn = { 100, 200, 300 } }
		local last = session{ warn = { 100, 200, 300, 400, 500 } }
		local tied = session{ warn = { 100, 200, 300, 400, 500 } }
		local agg = compare(KEY).aggregates.warningCross
		eq(agg.n, 5)
		eq(agg.median, 3)
		eq(agg.max.id, tied.id, "the most recent of two equal values")
		notNil(last)
		local even = C().Assemble({ key = KEY, filters = C().FILTERS, ref = { role = "DAMAGER" }, excluded = {},
			older = 0 }, { compare(KEY).rows[1], compare(KEY).rows[2], compare(KEY).rows[3], compare(KEY).rows[4] })
		eq(even.aggregates.warningCross.median, 4, "5, 5, 3, 2: (3 + 5) / 2")
		local odd = C().Assemble({ key = KEY, filters = C().FILTERS, ref = { role = "DAMAGER" }, excluded = {},
			older = 0 }, { compare(KEY).rows[3], compare(KEY).rows[4] })
		eq(odd.aggregates.warningCross.median, 2.5, "3 and 2")
		eq(C().AggregateText(odd.aggregates.warningCross, "median"), "2.5")
	end)

	it("weigh the risk rate on the known time, never the mean of the rates", function()
		session{ danger = { 100, 200 }, dur = 1000 }       -- 2 in 100 s: 1.2 per minute
		session{ danger = { 100 }, dur = 2000 }            -- 1 in 200 s: 0.3 per minute
		local agg = compare(KEY).aggregates.risk
		eq(agg.status, "ok")
		eq(agg.situations, 3)
		eq(agg.known, 3000)
		eq(agg.rate, 0.6, "3 situations in 300 s, not (1.2 + 0.3) / 2")
		eq(agg.median, 0.8)
		isNil(agg.total, "rates do not add up")
		eq(C().AggregateText(agg, "rate"), "0.6 per minute of known combat, over all fights")
	end)

	it("pass a lower bound on to every aggregate it enters", function()
		session{ warn = { 100 }, cut = true }
		session{ warn = { 100, 200 } }
		local result = compare(KEY)
		local agg = result.aggregates.warningCross
		eq(agg.lower, true)
		eq(agg.category, "estimated")
		eq(agg.total, 3)
		eq(C().AggregateText(agg, "total"), "at least 3")
		eq(C().AggregateText(agg, "median"), "~1.5")
		eq(agg.min.lower, true)
		eq(C().AggregateText(agg, "min"), "at least 1")
		isNil(agg.max.lower and true or nil, "the highest comes from a whole fight")
		eq(result.aggregates.risk.lower, true)
		contains(table.concat(C().AggregateTip(agg), "\n"), "Category: estimated")
		contains(table.concat(C().AggregateTip(agg), "\n"), "a lower bound")
	end)

	it("need MIN_FIGHTS comparable fights", function()
		session{ warn = { 100 } }
		local agg = compare(KEY).aggregates.warningCross
		eq(agg.status, "insufficient")
		eq(agg.reason, "one-fight")
		eq(agg.n, 1)
		isNil(agg.total)
		isNil(agg.median)
		C().MIN_FIGHTS = 1
		eq(compare(KEY).aggregates.warningCross.status, "ok")
	end)

	it("take at most MAX_FIGHTS, the most recent, and count the older ones", function()
		C().MAX_FIGHTS = 3
		local list = {}
		for i = 1, 5 do list[i] = session() end
		local set = C().Set(KEY)
		deepEq(idsOf(set.fights), { list[5].id, list[4].id, list[3].id })
		eq(set.older, 2)
		local result = compare(KEY)
		eq(#result.rows, 3)
		eq(result.rows[1].id, list[5].id, "the most recent first, never by a number")
		contains(table.concat(C().NoteLines(result), "\n"), "2 older fights not included")
	end)

	it("say the different recording rates on the percentages", function()
		session{ rec = { hz = 2, warning = 80, danger = 95, mode = "values" } }
		session{ rec = { hz = 4, warning = 80, danger = 95, mode = "values" } }
		local result = compare(KEY)
		eq(result.aggregates.closest.hz, true)
		eq(result.aggregates.closest.n, 2, "a different rate does not exclude")
		contains(table.concat(C().AggregateTip(result.aggregates.closest), "\n"), "different rates")
	end)
end)

describe("interrupted and linked fights (§1.6)", function()
	it("make the counts and times of an interrupted fight lower bounds, not its rate", function()
		local cut = session{ warn = { 100, 200 }, danger = { 300 }, interrupted = true, dur = 600 }
		session{ warn = { 100 }, danger = { 300 } }
		local result = compare(KEY)
		local row = rowOf(result, cut)
		eq(row.interrupted, true)
		local v = C().Value(row, C().MEASURE.warningCross)
		eq(v.status, "ok")
		eq(v.lower, true)
		eq(v.category, "estimated")
		eq(C().CellText(C().MEASURE.warningCross, v), "at least 2")
		eq(C().Value(row, C().MEASURE.risk).lower, false, "a rate per known time stays as it is")
		eq(result.aggregates.warningCross.lower, true)
		contains(table.concat(C().RowNotes(row), "\n"), "interrupted")
	end)

	it("keep two fights split by a /reload as two rows with their link", function()
		local first = session{ warn = { 100 } }
		local second = session{ warn = { 100 }, after = first.id }
		local result = compare(KEY)
		eq(#result.rows, 2)
		eq(rowOf(result, second).after, first.id)
		eq(result.aggregates.warningCross.total, 2)
	end)
end)

describe("the overview by enemy (§2.3)", function()
	it("comes from the headers only, the most recent first, the unknown enemies last", function()
		local a = session{ started = 7000, dur = 1000 }
		session{ started = 7100, interrupted = true, dur = 600 }
		local add = session{ started = 7200, mob = { name = "Pup", class = "normal" }, group = "raid" }
		session{ started = 7050, mob = NAMELESS }
		local nosum = session{ started = 6900 }
		nosum.sum = nil
		local decodes = 0
		local sDecode, stDecode = S().Decode, St().Decode
		S().Decode = function(...) decodes = decodes + 1 return sDecode(...) end
		St().Decode = function(...) decodes = decodes + 1 return stDecode(...) end
		local rows = C().Overview()
		S().Decode, St().Decode = sDecode, stDecode
		eq(decodes, 0, "nothing decoded")
		eq(#rows, 3)
		eq(rows[1].key, "name:Pup:normal")
		eq(rows[1].last, add.started)
		eq(rows[1].group, "raid")
		eq(rows[2].key, KEY)
		eq(rows[2].name, "Gorrak")
		eq(rows[2].class, "elite")
		eq(rows[2].count, 2)
		eq(rows[2].fight, a.fight, "the interrupted fight adds nothing")
		eq(rows[2].fightLower, true, "an interrupted fight with no length: at least")
		eq(rows[2].last, 7100)
		eq(rows[2].validMin, 100)
		eq(rows[2].validMax, 100)
		eq(rows[2].validUnknown, 0)
		eq(rows[3].unknown, true)
		eq(rows[3].count, 2, "no name, and no summary yet")
		eq(rows[3].validUnknown, 1)
		eq(C().OverviewName(rows[3]), "Unknown enemies (not comparable)")
		eq(C().OverviewName(rows[2]), "Gorrak")
	end)
end)

describe("the queue (§2.4)", function()
	it("builds one session at a time, pauses in combat and resumes at COMBAT_ENDED", function()
		for _ = 1, 3 do session() end
		local got, calls = nil, {}
		C().Build(KEY, nil, function(i, n, paused) calls[#calls + 1] = { i, n, paused } end,
			function(result) got = result end)
		deepEq(calls[1], { 1, 3, false })
		isNil(got, "the next session on the next frame")
		Mock.combat.Enter()
		frames(40)
		isNil(got, "paused")
		local q = C().Queue()
		eq(q.paused, true)
		eq(q.i, 1)
		deepEq(calls[#calls], { 1, 3, true })
		eq(C().ProgressText(1, 3, true), "Paused during combat")
		contains(Mock.ns.Diagnostics.Report(), "compare queue: 1 of 3, paused in combat")
		Mock.combat.Leave()
		frames(40)
		notNil(got)
		eq(#got.rows, 3)
		eq(C().ProgressText(2, 3, false), "Building 2 of 3…")
		isNil(C().Queue())
		eq(#Mock.errors, 0)
	end)

	it("does not pause when PAUSE_IN_COMBAT is off", function()
		C().PAUSE_IN_COMBAT = false
		for _ = 1, 2 do session() end
		Mock.combat.Enter()
		local result = compare(KEY)
		eq(#result.rows, 2)
		Mock.combat.Leave()
	end)

	it("leaves out a session deleted while building, and counts a damaged one apart", function()
		local a = session{ warn = { 100 } }
		local b = session{ warn = { 100, 200 } }
		local bad = session{ warn = { 100, 200, 300 } }
		local newest = session{ warn = { 100 } }
		bad.cols.s = string.rep("?", bad.n)
		local got
		C().Build(KEY, nil, nil, function(result) got = result end)
		truthy(St().Delete(b.id), "deleted before its turn")
		frames(80)
		notNil(got)
		deepEq(idsOf(got.rows), { newest.id, bad.id, a.id })
		eq(got.gone, 1)
		eq(got.damaged, 1)
		eq(rowOf(got, bad).status, "damaged")
		eq(C().Value(rowOf(got, bad), C().MEASURE.warningCross).status, "damaged")
		eq(got.aggregates.warningCross.of, 2, "the damaged one does not count")
		eq(got.aggregates.warningCross.total, 2)
		local notes = table.concat(C().NoteLines(got), "\n")
		contains(notes, "1 deleted fight left out")
		contains(notes, "1 damaged recording not counted")
	end)

	it("drops a fight deleted after it was built, and cancels a comparison replaced by another", function()
		session()
		local newest = session()
		local got
		C().Build(KEY, nil, nil, function(result) got = result end)
		isNil(got)
		notNil(Mx().Cached(newest.id), "the most recent fight is built first")
		truthy(St().Delete(newest.id))
		frames(80)
		notNil(got)
		eq(#got.rows, 1)
		eq(got.gone, 1)
		-- a new comparison cancels the one being built
		session()
		local first, why
		C().Build(KEY, nil, nil, function(result, reason) first, why = result, reason end)
		C().Build(KEY, nil, nil, function() end)
		isNil(first)
		eq(why, "cancelled")
		frames(80)
		falsy(C().Cancel(), "nothing left to cancel")
	end)

	it("keeps the last comparison up to date at SESSIONS_CHANGED: deleted fights out, new ones counted", function()
		local a = session{ warn = { 100 } }
		session{ warn = { 100, 200 } }
		session{ warn = { 100, 200, 300 } }
		local result = compare(KEY)
		eq(result.aggregates.warningCross.total, 6)
		isNil(result.rows[1].metrics, "a row keeps what the comparison needs, the metrics stay in their cache")
		local seen
		C().OnChange(function(r) seen = r end)
		truthy(St().Delete(a.id))
		notNil(seen)
		eq(#seen.rows, 2)
		eq(seen.gone, 1)
		eq(seen.aggregates.warningCross.total, 5)
		eq(C().Current(), seen)
		session()
		eq(C().Current().newFights, 1)
		contains(table.concat(C().NoteLines(C().Current()), "\n"), "1 new fight: Refresh")
		C().OnChange(nil)
	end)

	it("writes its lines in /atw debug, with counts only", function()
		session()
		session()
		local text = Mock.ns.Diagnostics.Report()
		contains(text, "compare last set: none")
		contains(text, "compare queue: idle")
		compare(KEY)
		text = Mock.ns.Diagnostics.Report()
		contains(text, "compare last set: 2 fights, 0 left out, 0 older, 0 deleted, 0 damaged")
		contains(text, "compare builds: 1")
		falsy(text:find("Gorrak", 1, true), "no enemy name")
		falsy(text:find("448", 1, true), "no key")
	end)
end)

describe("the words (ANA-01, ANA-04)", function()
	it("have a label for every measure and filter, and mark every value with its category", function()
		local L = Mock.ns.L
		for _, ms in ipairs(C().MEASURES) do notNil(L[C().MEASURE_KEYS[ms.id]], ms.id) end
		for name in pairs(C().FILTERS) do notNil(L[C().FILTER_KEYS[name]], name) end
		for _, key in pairs(C().AGGREGATE_KEYS) do notNil(L[key], key) end
		session{ warn = { 100 }, peak = 520 }
		session{ warn = { 100 }, peak = 460 }
		local result = compare(KEY)
		eq(C().AggregateText(result.aggregates.closest, "max"), "52.0 %")
		eq(C().AggregateText(result.aggregates.fight, "total"), "3:20")
		eq(C().AggregateText(result.aggregates.valid, "median"), "100 %")
		eq(C().CellText(C().MEASURE.risk, C().Value(result.rows[1], C().MEASURE.risk)), "0.0")
		local tip = table.concat(C().AggregateTip(result.aggregates.warningCross), "\n")
		contains(tip, "2 of 2 fights")
		contains(tip, "Category: calculated")
	end)
end)

describe("with the `analytics` switch off (ADR 0014)", function()
	before_boot(function(M)
		M.features = { monitor = true, alerts = true, coach = true, recording = true, reports = true, timeline = true,
			analytics = false }
	end)

	it("builds nothing, shows no overview and listens to nothing", function()
		session()
		local why
		C().Build(KEY, nil, nil, function(_, reason) why = reason end)
		eq(why, "off")
		deepEq(C().Overview(), {})
		falsy(C().Listening())
		isNil(C().Current())
	end)
end)
