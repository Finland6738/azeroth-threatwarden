-- Data/Timeline.lua (SPEC-05 §4.1–§4.7, §10 M5.2; RPL-01–RPL-05; ADR 0003, 0017): known sessions with known models in
-- the three probe outcomes and in a mixed, an interrupted and a truncated one; every kind of segment and every gap of
-- §4.3–§4.4 with its category and reason; every marker of §4.5 and their grouping; crossings equal to the report's;
-- default series and lanes; View against a brute-force pass; the build in slices equal to the one-pass build; nothing
-- built with the switch off; recordings of the real recorder in the three outcomes.

before_boot(function(M)
	M.features = { monitor = true, alerts = true, coach = true, recording = true, reports = true, timeline = true }
end)

local function TL() return Mock.ns.Timeline end
local function R() return Mock.ns.Report end
local function S() return Mock.ns.Session end
local function St() return Mock.ns.Storage end

local counter = 0

-- A session built with the Session API (as in test_report.lua). spec: units, mobs, events { t, k, m, u, v, a, b, c,
-- n }, rows { t, m, u, p, code }, q, dur, fight, state, ended, trunc, after, rec.
local function build(spec)
	counter = counter + 1
	local s = S().New{ id = "tl-" .. counter, started = 2000 + counter, group = "party", after = spec.after,
		rec = spec.rec or { hz = 2, warning = 80, danger = 95, mode = "values" } }
	for _, u in ipairs(spec.units or {}) do S().AddUnit(s, u, 0) end
	for _, m in ipairs(spec.mobs or {}) do S().AddMob(s, m, 0) end
	for _, e in ipairs(spec.events or {}) do
		S().AddEvent(s, e[1], e[2], e[3], e[4], e[5], e[6], e[7], e[8], e[9])
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

local function model(s) return TL().Compute(s, assert(S().Decode(s))) end
local function report(s) return R().Compute(s, assert(S().Decode(s))) end

local ME = { name = "Testchar", role = "DAMAGER", token = "player", me = true }
local TANK = { name = "Bram", class = "WARRIOR", role = "TANK", token = "party1" }
local KOR = { name = "Kor", class = "ROGUE", role = "DAMAGER", token = "party2" }
local BOSS = { name = "Gorrak", class = "elite", npc = 448 }
local ADD = { name = "Pup", class = "normal" }

-- The fight of test_report.lua: 40 s in values with one of everything.
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

-- One unit on one mob for 100 s: the base of the exact cases. `events` go between the opening and the end of combat.
local function single(events, rows, extra)
	local list = { { 0, "C", 0, 0, 0, "1" }, { 0, "M", 0, 0, 0, "v" }, { 0, "T", 1 }, { 0, "S", 1, 1, 0, "S", "-" } }
	for _, e in ipairs(events or {}) do list[#list + 1] = e end
	list[#list + 1] = { 1000, "c" }
	local spec = { units = { ME }, mobs = { BOSS, ADD }, dur = 1000, events = list, rows = rows }
	for k, v in pairs(extra or {}) do spec[k] = v end
	return model(build(spec))
end

-- The segments of unit 1 as "kind/why" strings, from the second reading on.
local function segs(m)
	local se, out = m.units[1], {}
	for k = 2, se.readings do out[#out + 1] = se.segs[k] .. (se.why[k] and ("/" .. se.why[k]) or "") end
	return out
end

local function gapsOf(list)
	local out = {}
	for _, g in ipairs(list) do out[#out + 1] = { g[1], g[2], g[3], g[4] } end
	return out
end

describe("the model of a known session (SPEC-05 §4.2)", function()
	it("gives the periods, mode bands, series, states, holders and the outcome", function()
		local m = model(build(known()))
		eq(m.dur, 400)
		eq(m.hz, 2)
		eq(m.join, 15, "max(30 / hz, 10) tenths")
		eq(m.warning, 80)
		eq(m.danger, 95)
		deepEq(m.combat, { { 0, 400 } })
		deepEq(m.mobs, { { 0, 400, 1 } })
		deepEq(m.modes, { { 0, 400, "values" } })
		deepEq(m.gaps, {})
		eq(m.outcome, "values")
		isNil(TL().OutcomeText(m))
		local me = m.units[1]
		eq(me.readings, 6)
		eq(me.maxP, 960)
		eq(me.maxT, 200)
		deepEq(me.states, { { 0, 100, "S", 1 }, { 100, 130, "W", 1 }, { 130, 200, "S", 1 }, { 200, 260, "D", 1 },
			{ 260, 300, "W", 1 }, { 300, 400, "S", 1 } })
		deepEq(me.present, { { 0, 400, 1 } })
		deepEq(me.crossings, { { 100, "W", 1 }, { 200, "D", 1 } })
		deepEq(m.units[2].holds, { { 0, 310, 1 } })
		deepEq(m.units[3].holds, { { 310, 400, 1 } })
		deepEq(m.series, { 1, 2, 3 }, "the player, then who held the mob by time held")
		deepEq(m.lanes, { 1, 2, 3 })
		eq(#m.events, 19)
	end)

	it("gives the crossings of the report (§3.2) for every unit", function()
		local s = build(known())
		local m, r = model(s), report(s)
		for _, u in ipairs(r.units) do
			local w, d = 0, 0
			for _, c in ipairs(m.units[u.index].crossings) do
				if c[2] == "W" then w = w + 1 else d = d + 1 end
			end
			eq(w, u.cells.warningCross.value, u.name)
			eq(d, u.cells.dangerCross.value, u.name)
		end
	end)

	it("gives the same model from the same data (RPL-01)", function()
		local s = build(known())
		deepEq(model(s), model(s))
	end)

	it("leaves the report as it was (the exposed functions change nothing)", function()
		local r = report(build(known()))
		local me
		for _, u in ipairs(r.units) do if u.me then me = u end end
		eq(me.cells.warningTime.value, 70)
		eq(me.cells.dangerTime.value, 60)
		eq(r.rows.tanks.value[1].held, 310)
	end)
end)

describe("segments (SPEC-05 §4.3)", function()
	it("is solid up to `join`, dashed beyond and absent past ESTIMATE_MAX, with its category", function()
		local m = single({}, { { 10, 1, 1, 300, "0" }, { 25, 1, 1, 310, "0" }, { 41, 1, 1, 320, "0" },
			{ 141, 1, 1, 330, "0" }, { 242, 1, 1, 340, "0" } })
		deepEq(segs(m), { "solid", "dashed", "dashed", "none/far" })
		eq(m.units[1].segs[1], "none")
		eq(m.units[1].why[1], "first")
		eq(TL().SEGMENT_CATEGORY.solid, "detected")
		eq(TL().SEGMENT_CATEGORY.dashed, "estimated")
		eq(TL().SEGMENT_CATEGORY.none, "unknown")
	end)

	it("follows the recording rate: join = max(30 / hz, 10)", function()
		local rows = { { 10, 1, 1, 300, "0" }, { 40, 1, 1, 310, "0" } }
		eq(single({}, rows, { rec = { hz = 1 } }).join, 30)
		deepEq(segs(single({}, rows, { rec = { hz = 1 } })), { "solid" })
		eq(single({}, rows, { rec = { hz = 5 } }).join, 10)
		deepEq(segs(single({}, rows, { rec = { hz = 5 } })), { "dashed" })
		eq(single({}, rows, { rec = {} }).hz, 2, "2 when the header has none")
	end)

	it("breaks at every cause, with its reason", function()
		local two = { { 10, 1, 1, 300, "0" }, { 70, 1, 1, 310, "0" } }
		deepEq(segs(single({ { 60, "G", 0, 0, 0, "t", "-", "-", 10 } }, two)), { "none/tick" })
		deepEq(segs(single({ { 50, "M", 0, 0, 0, "s", "s" } }, two)), { "none/mode" })
		deepEq(segs(single({ { 50, "M", 0, 0, 0, "n", "S" } }, two)), { "none/mode" })
		deepEq(segs(single({ { 50, "M", 0, 0, 0, "v" } }, two)), { "dashed" }, "back to values is no break")
		deepEq(segs(single({ { 40, "c" }, { 50, "C", 0, 0, 0, "2" } }, two)), { "none/combat" })
		deepEq(segs(single({ { 40, "T", 2 }, { 50, "T", 1 } }, two)), { "none/target" })
		deepEq(segs(single({ { 40, "S", 1, 1, 0, "-", "S" }, { 50, "S", 1, 1, 0, "S", "-" } }, two)), { "none/exit" })
		deepEq(segs(single({ { 40, "Z", 0, 0, 0, "r" } }, two)), { "none/limit" })
		deepEq(segs(single({}, { { 10, 1, 1, 300, "0" }, { 30, 1, 1, -1, "S" }, { 50, 1, 1, 310, "0" } })),
			{ "none/row" })
		deepEq(segs(single({}, { { 10, 1, 1, 300, "0" }, { 30, 1, 1, -1, "b" }, { 50, 1, 1, 310, "0" } })),
			{ "none/row" }, "a state-only row too")
		deepEq(segs(single({}, { { 10, 1, 1, 300, "0" }, { 20, 2, 1, 310, "0" } })), { "none/mob" })
	end)

	it("keeps 3843 as a lower bound", function()
		local m = single({}, { { 10, 1, 1, 3843, "1" }, { 20, 1, 1, 500, "0" } })
		local pct, t, category, lower = TL().Reading(m, 1, 1)
		eq(pct, 384.3)
		eq(t, 10)
		eq(category, "estimated")
		eq(lower, true)
		local _, _, c2, l2 = TL().Reading(m, 1, 2)
		eq(c2, "detected")
		eq(l2, false)
		eq(TL().Summary(m, 0, 1000).series[1].maxCategory, "estimated")
	end)
end)

describe("gaps (SPEC-05 §4.4)", function()
	it("gives each unit its unknown and stale gaps with the reason, to the next row or the end of the period", function()
		local m = single({}, { { 10, 1, 1, 300, "0" }, { 30, 1, 1, -1, "S" }, { 50, 1, 1, 310, "0" },
			{ 60, 1, 1, -1, "T" }, { 90, 1, 1, 320, "0" }, { 120, 1, 1, -1, "E" } })
		deepEq(gapsOf(m.units[1].unknown), { { 30, 50, "unknown", "secret" }, { 60, 90, "stale", "stale" },
			{ 120, 1000, "unknown", "error" } })
		eq(TL().GapText(m.units[1].unknown[1]), "No reading: secret value")
		eq(TL().GapText(m.units[1].unknown[2]), "Reading too old")
		eq(TL().GAP_CATEGORY, "unknown")
	end)

	it("ends a unit's gap with its mob's period", function()
		local m = single({ { 80, "T", 2 } }, { { 30, 1, 1, -1, "M" }, { 90, 2, 1, 310, "0" } })
		deepEq(gapsOf(m.units[1].unknown), { { 30, 80, "unknown", "missing" } })
	end)

	it("gives the gaps of the whole chart: mode, no mob, tick and limit", function()
		local m = single({ { 50, "M", 0, 0, 0, "n", "S" }, { 80, "M", 0, 0, 0, "v" }, { 100, "T", 0, 0, 0, "d" },
			{ 130, "T", 1 }, { 200, "G", 0, 0, 0, "t", "-", "-", 24 }, { 300, "T", 0, 0, 0, "l" }, { 310, "T", 1 },
			{ 400, "T", 0, 0, 0, "n" }, { 410, "T", 1 } }, { { 10, 1, 1, 300, "0" } }, { trunc = 900 })
		deepEq(gapsOf(m.gaps), { { 50, 80, "mode", "secret" }, { 100, 130, "nomob", "died" },
			{ 176, 200, "tick" }, { 300, 310, "nomob", "lost" }, { 400, 410, "nomob", "none" },
			{ 900, 1000, "limit", "samples" } })
		local L = {}
		for _, g in ipairs(m.gaps) do L[#L + 1] = TL().GapText(g) end
		deepEq(L, { "Nothing readable: secret value", "Target died", "Recording paused for 2.4 s", "Target lost",
			"No monitored enemy", "Samples stopped: limit reached" })
	end)

	it("keeps out of combat out of the gaps", function()
		local m = single({ { 50, "M", 0, 0, 0, "n", "S" }, { 100, "c" }, { 200, "C", 0, 0, 0, "2" },
			{ 250, "M", 0, 0, 0, "v" } }, { { 10, 1, 1, 300, "0" } })
		deepEq(gapsOf(m.gaps), { { 50, 100, "mode", "secret" }, { 200, 250, "mode", "secret" } })
		deepEq(m.combat, { { 0, 100 }, { 200, 1000 } })
		deepEq(m.modes, { { 0, 50, "values" }, { 50, 250, "none", "secret" }, { 250, 1000, "values" } })
	end)
end)

describe("markers (SPEC-05 §4.5)", function()
	local function everything()
		return {
			units = { ME, TANK, KOR }, mobs = { BOSS, {} }, dur = 600, state = "interrupted", ended = "reload",
			events = {
				{ 0, "C", 0, 0, 0, "1" }, { 0, "M", 0, 0, 0, "v" }, { 0, "T", 1 }, { 0, "A", 1, 2, 0, "1" },
				{ 0, "S", 1, 3, 0, "S", "-" }, { 50, "S", 1, 3, 0, "D", "S" }, { 60, "S", 1, 3, 0, "S", "D" },
				{ 70, "A", 1, 3, 2, "0", "1" }, { 80, "A", 1, 2, 3, "1", "0" }, { 90, "D", 0, 2, 0, "g" },
				{ 95, "D", 0, 1, 0, "p" }, { 100, "L", 1, 1, 0, "w", "1", "1", "eh" }, { 110, "H", 0, 1, 0, "1", "d", "h" },
				{ 120, "N", 0, 0, 0, "s" }, { 130, "N", 0, 0, 0, "e", "1" }, { 140, "M", 0, 0, 0, "n", "S" },
				{ 150, "G", 0, 0, 0, "t", "-", "-", 12 }, { 160, "c" }, { 170, "C", 0, 0, 0, "2" }, { 180, "T", 2 },
				{ 190, "D", 2, 0, 0, "t" }, { 190, "T", 0, 0, 0, "d" }, { 200, "C", 0, 0, 0, "r" },
				{ 210, "S", 1, 3, 0, "-", "S" }, { 220, "Z", 0, 0, 0, "r" }, { 600, "X", 0, 0, 0, "o" },
			},
			rows = { { 10, 1, 1, 300, "0" } },
		}
	end

	it("gives every event its kind, place and category, and words in English", function()
		local m = model(build(everything()))
		local got = {}
		for _, mk in ipairs(m.events) do
			got[#got + 1] = mk.kind .. "|" .. mk.place .. "|" .. mk.category .. "|" .. TL().MarkerText(m, mk)
		end
		deepEq(got, {
			"combat|track|detected|Combat started",
			"mode|chart|detected|Threat values readable",
			"target|chart|detected|Target: Gorrak",
			"holder|lane|detected|Bram holds the enemy",
			"enter|lane|calculated|Kor: Safe",
			"cross|series|calculated|Kor: Danger · thresholds 80 / 95",
			"state|lane|calculated|Kor: Safe",
			"took|track|detected|Kor took the enemy from Bram",
			"holder|lane|detected|Bram holds the enemy",
			"death|track|detected|Bram died",
			"death|track|detected|You died",
			"alert|track|estimated|Alert: Warning (muted)",
			"coach|track|detected|Coach tip (rule T1)",
			"encounter|track|detected|Encounter started",
			"encounter|track|detected|Encounter ended: success",
			"mode|chart|detected|Nothing readable: secret value",
			"tick|chart|detected|Recording paused for 1.2 s",
			"end|chart|detected|Combat ended",
			"combat|track|detected|Next pull",
			"target|chart|detected|Target: Unknown mob",
			"death|track|detected|The target died",
			"nomob|chart|detected|Target died",
			"combat|track|detected|Combat continued after a reload",
			"leave|lane|calculated|Kor left the threat list",
			"limit|track|detected|Limit reached: samples",
			"interrupted|track|detected|Recording interrupted (logout or reload)",
		})
		eq(m.events[12].confidence, "high")
		eq(m.events[13].confidence, "high")
		eq(m.events[8].lane, true, "a non-tank taking the mob is on the holder's lane too")
	end)

	it("says game state for a crossing in state only", function()
		local spec = everything()
		spec.events[2] = { 0, "M", 0, 0, 0, "s", "s" }
		local m = model(build(spec))
		eq(m.events[6].category, "detected")
		eq(TL().MarkerText(m, m.events[6]), "Kor: Danger · game state")
	end)

	it("has words for every marker and gap in both languages", function()
		local m = model(build(everything()))
		for _, code in ipairs({ "enUS", "itIT" }) do
			Mock.ns.Locale.Apply(code)
			for _, mk in ipairs(m.events) do truthy(#TL().MarkerText(m, mk) > 0, mk.kind) end
			for _, g in ipairs(m.gaps) do truthy(#TL().GapText(g) > 0, g[3]) end
			for _, kind in ipairs(TL().GAP_KINDS) do truthy(#TL().GapText({ 0, 10, kind, "secret" }) > 0, kind) end
		end
		Mock.ns.Locale.Apply("it" .. "IT")
		eq(TL().MarkerText(m, m.events[1]), "Combattimento iniziato")
		Mock.ns.Locale.Apply("enUS")
	end)

	it("groups the markers of the track under 8 px, a pure function", function()
		local list = {
			{ t = 0, place = "track", prio = 6 }, { t = 5, place = "track", prio = 1 }, { t = 6, place = "chart", prio = 1 },
			{ t = 7, place = "track", prio = 3 }, { t = 100, place = "track", prio = 8 }, { t = 500, place = "track", prio = 2 },
		}
		local out = TL().Group(list, 0, 1000, 100, {})   -- 10 tenths per pixel
		eq(out.n, 3, "0, 5 and 7 tenths are under a pixel apart; 100 tenths is 10 px away, 500 another 40 px")
		local first = out[1]
		eq(first.count, 3)
		eq(first.top, list[2], "the most important")
		eq(first.items[3], list[4])
		eq(out[2].count, 1)
		eq(out[3].top, list[6])
		out = TL().Group(list, 0, 1000, 10, out)       -- 100 tenths per pixel: one group, reusing the tables
		eq(out.n, 1)
		eq(out[1].count, 5)
	end)

	it("lists at most 8 markers of a group, then how many more", function()
		local m = model(build(everything()))
		local group = { count = 10, items = {} }
		for i = 1, 10 do group.items[i] = m.events[1] end
		local lines = TL().GroupLines(m, group)
		eq(#lines, 9)
		eq(lines[9], "and 2 more")
	end)
end)

describe("the three outcomes over time (SPEC-05 §4.6)", function()
	it("is state only with states and holders, and says so", function()
		local m = model(build({
			units = { ME, TANK }, mobs = { BOSS }, dur = 200, rec = { hz = 2, mode = "state" },
			events = {
				{ 0, "C", 0, 0, 0, "1" }, { 0, "M", 0, 0, 0, "s" }, { 0, "T", 1 }, { 0, "A", 1, 2, 0, "1" },
				{ 0, "S", 1, 1, 0, "S", "-", "s" }, { 100, "S", 1, 1, 0, "W", "S", "s" },
				{ 150, "A", 1, 1, 2, "0", "1" }, { 200, "c" },
			},
			rows = { { 5, 1, 1, -1, "a" }, { 5, 1, 2, -1, "d" }, { 100, 1, 1, -1, "b" } },
		}))
		eq(m.outcome, "state")
		deepEq(m.series, {}, "no unit without a reading with a number is a series")
		deepEq(m.lanes, { 1 })
		eq(TL().OutcomeText(m), "Percentages were not available in this fight (state only): states and who held the "
			.. "enemy are shown.")
		deepEq(m.units[1].crossings, { { 100, "W", 1 } })
	end)

	it("is nothing readable with the prevailing reason", function()
		local m = model(build({
			units = { ME, TANK }, mobs = { BOSS }, dur = 300, rec = { hz = 2, mode = "none" },
			events = { { 0, "C", 0, 0, 0, "1" }, { 0, "M", 0, 0, 0, "n", "S" }, { 0, "T", 1 }, { 300, "c" } },
			rows = { { 5, 1, 1, -1, "S" }, { 5, 1, 2, -1, "S" } },
		}))
		eq(m.outcome, "none")
		eq(m.reason, "secret")
		deepEq(m.series, {})
		deepEq(m.lanes, {})
		eq(TL().OutcomeText(m), "Nothing was readable in this fight (secret value): only the events are shown.")
		deepEq(gapsOf(m.gaps), { { 0, 300, "mode", "secret" } })
	end)

	it("is mixed when values and state rows meet, or when the readable mode changes in combat", function()
		local spec = known()
		table.insert(spec.events, 11, { 305, "M", 0, 0, 0, "s", "s" })
		spec.rows[#spec.rows + 1] = { 340, 1, 1, -1, "a" }
		local m = model(build(spec))
		eq(m.outcome, "mixed")
		deepEq(m.modes, { { 0, 305, "values" }, { 305, 400, "state" } })
		eq(TL().ModeText(m.modes[2]), "State only from 0:30")
		isNil(TL().ModeText(m.modes[1]))
		spec = known()
		table.insert(spec.events, 11, { 305, "M", 0, 0, 0, "n", "S" })
		m = model(build(spec))
		eq(m.outcome, "mixed", "values rows only, but nothing readable for a while")
		eq(TL().ModeText(m.modes[2]), "Nothing readable from 0:30")
		spec = known()
		spec.events[2] = { 0, "M", 0, 0, 0, "n", "-" }
		table.insert(spec.events, 3, { 1, "M", 0, 0, 0, "v" })
		m = model(build(spec))
		eq(m.outcome, "values", "nothing readable before the first read is no change of mode")
		deepEq(gapsOf(m.gaps), { { 0, 1, "mode", "other" } }, "but it stays a gap")
	end)
end)

describe("interrupted, truncated and continued sessions", function()
	it("ends the axis at the last record of an interrupted one", function()
		local spec = known()
		spec.events[#spec.events] = { 360, "X", 0, 0, 0, "o" }
		spec.state, spec.ended, spec.dur, spec.fight = "interrupted", "reload", 0, 0
		local m = model(build(spec))
		eq(m.dur, 360, "the last record")
		eq(m.state, "interrupted")
		eq(m.ended, "reload")
		deepEq(m.combat, { { 0, 360 } })
		eq(m.events[#m.events].kind, "interrupted")
		eq(m.units[3].states[#m.units[3].states][2], 360, "nothing after the last record")
	end)

	it("stops the series at `trunc` while the events go on", function()
		local spec = known()
		spec.trunc = 320
		local m = model(build(spec))
		eq(m.trunc, 320)
		deepEq(gapsOf(m.gaps), { { 320, 400, "limit", "samples" } })
		eq(m.events[#m.events].k, "c")
	end)

	it("keeps the link to the session before", function()
		local spec = known()
		spec.after = "tl-earlier"
		eq(model(build(spec)).after, "tl-earlier")
	end)
end)

describe("default series and lanes (SPEC-05 §4.7)", function()
	it("puts the player first, then the holders by time held, then the highest readings, at most 6", function()
		local units, rows = { ME }, { { 1, 1, 1, 100, "0" } }
		for i = 2, 9 do units[i] = { name = "U" .. i, token = "raid" .. i } end
		local top = { [2] = 500, [3] = 500, [4] = 900, [5] = 950, [6] = 950, [7] = 300, [8] = 200, [9] = 100 }
		for u = 2, 9 do rows[#rows + 1] = { u, 1, u, top[u], "0" } end
		table.sort(rows, function(a, b) return a[1] < b[1] end)
		local m = model(build({
			units = units, mobs = { BOSS }, dur = 400,
			events = { { 0, "C", 0, 0, 0, "1" }, { 0, "T", 1 }, { 0, "A", 1, 2, 0, "1" }, { 50, "A", 1, 3, 2, "1", "1" },
				{ 300, "S", 1, 7, 0, "W", "-" }, { 310, "S", 1, 8, 0, "D", "-" }, { 400, "c" } },
			rows = rows,
		}))
		deepEq(m.series, { 1, 3, 2, 5, 6, 4 }, "3 held 350, 2 held 50; 5 and 6 tie on 95 % (the index)")
		deepEq(m.lanes, { 7, 8 }, "only units with known states; by the time in Warning and Danger (100 and 90)")
	end)
end)

-- A random session (a fixed generator: the same sessions on every run).
local seed = 12345
local function random(n)
	seed = (seed * 1103515245 + 12345) % 2147483648
	return seed % n + 1
end

local function randomSession(units, count)
	local list, rows, t = {}, {}, 0
	for i = 1, units do list[i] = { name = "R" .. i, token = "raid" .. i } end
	list[1].me = true
	for _ = 1, count do
		t = t + random(4) - 1
		local code = random(10) <= 8 and "0" or (random(2) == 1 and "S" or "T")
		rows[#rows + 1] = { t, 1, random(units), code == "0" and random(3000) or -1, code }
	end
	return build({ units = list, mobs = { BOSS }, dur = t + 10, rows = rows,
		events = { { 0, "C", 0, 0, 0, "1" }, { 0, "M", 0, 0, 0, "v" }, { 0, "T", 1 },
			{ math.floor(t / 2), "G", 0, 0, 0, "t", "-", "-", 30 }, { t + 10, "c" } } })
end

-- The view by brute force: every reading of the series against every column.
local function brute(m, a, b, buckets, series)
	local out = {}
	a, b = TL().Clamp(m, a, b)
	local d = m.d
	for j, u in ipairs(series) do
		local se = m.units[u]
		local col = { first = {}, last = {}, lo = {}, hi = {}, cut = {} }
		for c = 1, buckets do col.first[c], col.last[c], col.lo[c], col.hi[c], col.cut[c] = 0, 0, 0, 0, false end
		for k = 1, se.readings do
			local t = d.t[se.rows[k]]
			if t >= a and t <= b then
				local c = math.min(math.floor((t - a) * buckets / (b - a)) + 1, buckets)
				local p = d.p[se.rows[k]]
				if col.first[c] == 0 then
					col.first[c], col.lo[c], col.hi[c] = k, k, k
				else
					if p < d.p[se.rows[col.lo[c]]] then col.lo[c] = k end
					if p > d.p[se.rows[col.hi[c]]] then col.hi[c] = k end
					if se.segs[k] == "none" then col.cut[c] = true end
				end
				col.last[c] = k
			end
		end
		out[j] = col
	end
	return out
end

describe("View (SPEC-05 §4.7)", function()
	it("equals a brute-force pass on random sessions, in wide and narrow views", function()
		for round = 1, 6 do
			local m = model(randomSession(5, 600))
			local all = {}
			for u = 1, 5 do all[u] = u end
			for _ = 1, 8 do
				local a = random(m.dur) - 1
				local b = a + random(m.dur)
				if round % 2 == 0 then b = a + random(60) end      -- narrow: down to MIN_VIEW
				local buckets = random(TL().MAX_BUCKETS)
				local out = TL().View(m, a, b, buckets, all, {})
				local want = brute(m, a, b, buckets, all)
				for j = 1, 5 do
					for _, field in ipairs({ "first", "last", "lo", "hi", "cut" }) do
						for c = 1, buckets do eq(out[j][field][c], want[j][field][c], field .. " " .. c) end
					end
				end
				truthy(out.b - out.a >= TL().MIN_VIEW)
			end
		end
	end)

	it("keeps every peak: the highest reading of a series is a column's highest", function()
		local m = model(randomSession(3, 2000))
		for u = 1, 3 do
			local out = TL().View(m, 0, m.dur, 7, { u }, {})
			local se, best = m.units[u], 0
			for c = 1, 7 do
				local k = out[1].hi[c]
				if k > 0 and m.d.p[se.rows[k]] > best then best = m.d.p[se.rows[k]] end
			end
			eq(best, se.maxP, "unit " .. u)
		end
	end)

	it("is the exact line of the readings when every column holds one", function()
		local m = single({}, { { 10, 1, 1, 300, "0" }, { 25, 1, 1, 310, "0" }, { 41, 1, 1, 320, "0" } })
		local out = TL().View(m, 0, 50, 50, { 1 }, {})
		local got = {}
		for c = 1, 50 do if out[1].first[c] > 0 then got[#got + 1] = out[1].first[c] end end
		deepEq(got, { 1, 2, 3 })
	end)

	it("clamps the columns and the view, and makes no table once warm", function()
		eq(TL().Buckets(1000), 400)
		eq(TL().Buckets(300), 150)
		eq(TL().Buckets(1), 1)
		local m = model(randomSession(4, 3000))
		local out = TL().View(m, 0, m.dur, 900, m.series, {})
		eq(out.buckets, TL().MAX_BUCKETS)
		TL().View(m, 0, m.dur, 400, m.series, out)
		collectgarbage("collect")
		collectgarbage("stop")
		local before = collectgarbage("count")
		for _ = 1, 5 do TL().View(m, 100, m.dur - 100, 400, m.series, out) end
		local grown = collectgarbage("count") - before
		collectgarbage("restart")
		truthy(grown < 0.5, ("%.2f KB made by a warm view"):format(grown))
	end)
end)

describe("Summary (SPEC-05 §4.8)", function()
	it("gives the report's times and crossings for the whole fight, calculated", function()
		local m = model(build(known()))
		local out = TL().Summary(m, 0, 400, {})
		eq(out.dur, 400)
		local me = out.series[1]
		eq(me.u, 1)
		eq(me.readings, 6)
		eq(me.maxP, 960)
		eq(me.maxT, 200)
		eq(me.maxCategory, "detected")
		eq(me.warningCross, 1)
		eq(me.dangerCross, 1)
		eq(me.warningTime, 70)
		eq(me.dangerTime, 60)
		eq(me.unknownTime, 0)
		eq(me.category, "calculated")
		eq(out.events.S, 8)
		eq(out.events.L, 2)
		local part = TL().Summary(m, 150, 250, out)
		eq(part.series[1].dangerTime, 50)
		eq(part.series[1].warningCross, 0)
		eq(part.series[1].dangerCross, 1)
	end)

	it("is a lower bound with unknown time, like the report", function()
		local spec = known()
		spec.events = {
			{ 0, "C", 0, 0, 0, "1" }, { 0, "M", 0, 0, 0, "v" }, { 0, "T", 1 }, { 0, "S", 1, 1, 0, "W", "-" },
			{ 100, "M", 0, 0, 0, "n", "S" }, { 150, "M", 0, 0, 0, "v" }, { 250, "G", 0, 0, 0, "t", "-", "-", 20 },
			{ 300, "S", 1, 1, 0, "U", "W" }, { 320, "S", 1, 1, 0, "S", "U" }, { 400, "c" },
		}
		local r = report(build(spec))
		local m = model(build(spec))
		local me = TL().Summary(m, 0, 400, {}).series[1]
		local cells
		for _, u in ipairs(r.units) do if u.me then cells = u.cells end end
		eq(me.unknownTime, cells.warningTime.unknownTime, "50 s none + 20 gap + 20 UNKNOWN")
		eq(me.lower, true)
		eq(me.category, "estimated")
		eq(me.warningTime, cells.warningTime.value)
	end)
end)

local function add(s)
	truthy(St().Add(s))
	truthy(St().Closed(s, true))
	return s
end

describe("Build (SPEC-05 §4.2)", function()
	it("gives the same model in slices as in one pass, over several frames", function()
		local s = add(build(known()))
		local whole = model(s)
		TL().SLICE = 3
		local got, calls = nil, 0
		TL().Build(s.id, function(m) got, calls = m, calls + 1 end)
		isNil(got, "more frames to go")
		for _ = 1, 60 do Mock.Advance(0.05) end
		eq(calls, 1)
		deepEq(got, whole)
		eq(TL().Cached(), got)
		truthy(TL().stats.frames > 1)
		TL().Build(s.id, function(m) eq(m, got, "from memory") calls = calls + 1 end)
		eq(calls, 2)
		eq(#Mock.errors, 0)
	end)

	it("refuses an unknown, damaged or open session, and drops what is gone", function()
		local why
		local function done(_, reason) why = reason end
		TL().Build("nope", done)
		eq(why, "unknown")
		local s = add(build(known()))
		TL().Build(s.id, done)
		eq(TL().Cached().id, s.id)
		truthy(St().Delete(s.id))
		isNil(TL().Cached())
		local bad = add(build(known()))
		bad.cols.s = string.rep("?", bad.n)
		TL().Build(bad.id, done)
		eq(why, "damaged")
		local open = build(known())
		open.state = "open"
		St().Add(open)
		TL().Build(open.id, done)
		eq(why, "recording")
	end)

	it("stops when the session goes while it is being built", function()
		local s = add(build(known()))
		TL().SLICE = 3
		local why
		TL().Build(s.id, function(_, reason) why = reason end)
		truthy(St().Delete(s.id))
		for _ = 1, 60 do Mock.Advance(0.05) end
		eq(why, "unknown")
	end)

	it("writes its lines in /atw debug, with counts only", function()
		local s = add(build(known()))
		local text = Mock.ns.Diagnostics.Report()
		contains(text, "== Timeline and replay ==")
		contains(text, "switches: timeline on, replay off")
		contains(text, "model: none in memory")
		TL().Build(s.id, function() end)
		text = Mock.ns.Diagnostics.Report()
		contains(text, "model: 12 rows, 19 events, 3 series, 3 lanes, outcome values")
		falsy(text:find("Gorrak", 1, true), "no mob name")
		falsy(text:find("Bram", 1, true), "no unit name")
	end)
end)

describe("with the `timeline` switch off (ADR 0014)", function()
	before_boot(function(M)
		M.features = { monitor = true, alerts = true, coach = true, recording = true, reports = true, timeline = false }
	end)

	it("builds nothing and listens to nothing", function()
		local s = add(build(known()))
		local why
		TL().Build(s.id, function(_, reason) why = reason end)
		eq(why, "off")
		isNil(TL().Cached())
		falsy(TL().Listening())
		contains(Mock.ns.Diagnostics.Report(), "switches: timeline off, replay off")
	end)
end)

describe("recordings of the real recorder", function()
	for _, outcome in ipairs(Fight.OUTCOMES) do
		it("give a model of a party fight in " .. outcome, function()
			local pull = Fight.new{
				player = { class = "MAGE", role = "DAMAGER", ranged = true },
				party = { { key = "tank", role = "TANK", name = "Bram" }, { key = "healer", class = "PRIEST" } },
				mobs = { { key = "boss", tokens = { "target", "boss1" }, classification = "worldboss", name = "Gorrak" } },
			}
			pull:outcome(outcome)
			pull:at(0):start():threat("boss", "tank", 1000):threat("boss", "player", { raw = 500, scaled = 40 })
			pull:at(5):threat("boss", "player", { raw = 900, scaled = 85 })
			pull:at(10):threat("boss", "player", { raw = 1200, scaled = 120 }):aggro("boss", "player")
			pull:at(20):stop()
			pull:finish()
			Mock.Advance(7)
			local list = St().List()
			eq(#list, 1)
			local m
			TL().Build(list[1].id, function(result) m = result end)
			Mock.Advance(1)
			notNil(m)
			local s = St().Get(list[1].id)
			local r = report(s)
			eq(m.dur, r.dur)
			eq(m.outcome, outcome)
			local me
			for u, info in ipairs(m.info) do if info.me then me = u end end
			notNil(me)
			-- crossings equal the report's, whatever the outcome
			for _, u in ipairs(r.units) do
				if u.cells.warningCross.status == "ok" then
					local w, d = 0, 0
					for _, c in ipairs(m.units[u.index].crossings) do
						if c[2] == "W" then w = w + 1 else d = d + 1 end
					end
					eq(w, u.cells.warningCross.value)
					eq(d, u.cells.dangerCross.value)
				end
			end
			if outcome == "values" then
				eq(m.series[1], me, "the player first")
				truthy(m.units[me].readings >= 3)
				truthy(m.units[me].maxP >= 850)
				local solid = 0
				for k = 2, m.units[me].readings do if m.units[me].segs[k] == "solid" then solid = solid + 1 end end
				truthy(solid > 0, "readings at the recording's rate are joined")
			elseif outcome == "state" then
				deepEq(m.series, {})
				truthy(#m.lanes >= 1)
				notNil(TL().OutcomeText(m))
			else
				deepEq(m.series, {})
				eq(m.reason, "secret")
				notNil(TL().OutcomeText(m))
			end
			for _, mk in ipairs(m.events) do truthy(#TL().MarkerText(m, mk) > 0, mk.kind) end
			eq(#Mock.errors, 0)
		end)
	end
end)
