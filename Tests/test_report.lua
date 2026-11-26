-- Data/Report.lua (SPEC-05 §3, §7 M4.4; REC-10, REC-11; ADR 0003): known sessions with known answers for every metric
-- in the three probe outcomes and in a mixed session, interrupted and truncated ones, no readable mob, "Insufficient
-- data" under 3 useful readings, lower bounds with partial coverage, the build in slices equal to the one-pass build,
-- the summary `sum`, the words, and recordings of the real recorder in the three outcomes.

before_boot(function(M)
	M.features = { monitor = true, alerts = true, coach = true, recording = true, reports = true }
end)

local function R() return Mock.ns.Report end
local function S() return Mock.ns.Session end
local function St() return Mock.ns.Storage end
local function L() return Mock.ns.L end

local counter = 0

-- A session built with the Session API. spec: units, mobs, events { t, k, m, u, v, a, b, c, n }, rows
-- { t, m, u, p, code }, q = { v, s, x }, dur, fight, state, ended, trunc.
local function build(spec)
	counter = counter + 1
	local s = S().New{ id = "t-" .. counter, started = 1000 + counter, group = "party",
		rec = { hz = 2, warning = 80, danger = 95 } }
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

local function compute(s) return R().Compute(s, assert(S().Decode(s))) end

local function unit(report, name)
	for _, u in ipairs(report.units) do if u.name == name then return u end end
	error("no unit " .. name)
end

local function value(cell)
	eq(cell.status, "ok", cell.key)
	return cell.value
end

local ME = { name = "Testchar", role = "DAMAGER", token = "player", me = true }
local TANK = { name = "Bram", class = "WARRIOR", role = "TANK", token = "party1" }
local KOR = { name = "Kor", class = "ROGUE", role = "DAMAGER", token = "party2" }
local BOSS = { name = "Gorrak", class = "elite", npc = 448 }
local ADD = { name = "Pup", class = "normal" }

-- A fight of 40 s in `values` with one of everything.
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
			{ 350, "L", 1, 1, 0, "w", "1", "0" }, { 351, "L", 1, 1, 0, "d", "2", "1" },
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

describe("a known session in values (SPEC-05 §3.2)", function()
	it("gives the known answer for every session metric, each with its category", function()
		local r = compute(build(known()))
		local d = r.rows.duration
		eq(d.category, "detected")
		eq(value(d).dur, 400)
		eq(d.value.fight, 400)
		eq(d.value.pulls, 1)
		falsy(d.lower)
		local mob = value(r.rows.mob)
		eq(mob.index, 1)
		eq(mob.name, "Gorrak")
		eq(mob.class, "elite")
		eq(mob.others, 1)
		eq(mob.encounter, "success")
		local tanks = value(r.rows.tanks)
		eq(r.rows.tanks.timeCategory, "calculated")
		eq(#tanks, 2)
		eq(tanks[1].unit, 2)
		eq(tanks[1].held, 310)
		eq(tanks[1].designated, true)
		eq(tanks[2].unit, 3)
		eq(tanks[2].held, 90)
		eq(tanks[2].designated, false)
		eq(#value(r.rows.tankChanges), 0)
		local losses = value(r.rows.aggroLosses)
		eq(#losses, 1)
		eq(losses[1].t, 310)
		eq(losses[1].to, 3)
		eq(losses[1].from, 2)
		eq(losses[1].points, 25)
		local deaths = value(r.rows.deaths)
		eq(#deaths, 1, "two records of one death")
		eq(deaths[1].unit, 2)
		local alerts = value(r.rows.alerts)
		eq(alerts.count, 2)
		eq(alerts.muted, 1)
		eq(alerts.kinds.warning, 1)
		eq(alerts.kinds.danger, 1)
		local q = value(r.rows.quality)
		eq(r.rows.quality.category, "calculated")
		eq(q.values, 100)
		eq(q.unknown, 0)
		eq(q.noMobTime, 0)
		eq(r.rows.quality.reason, nil)
	end)

	it("gives each unit its crossings, times, maximum, aggro and quality", function()
		local r = compute(build(known()))
		eq(r.units[1].name, "Testchar", "the player first")
		eq(r.units[2].name, "Bram", "then the designated tanks")
		local me = unit(r, "Testchar").cells
		eq(value(me.warningCross), 1, "S to W; D to W is no rise")
		eq(value(me.dangerCross), 1)
		eq(value(me.warningTime), 70)
		eq(value(me.dangerTime), 60)
		eq(me.warningTime.category, "calculated")
		eq(me.warningTime.basis, "thresholds")
		falsy(me.warningTime.lower)
		eq(value(me.maxPct).pct, 96)
		eq(me.maxPct.value.t, 200)
		eq(me.maxPct.category, "detected")
		eq(value(me.aggro), 0)
		local kor = unit(r, "Kor").cells
		eq(value(kor.dangerCross), 1, "the entry on the list")
		eq(value(kor.dangerTime), 80, "until the end of the combat")
		eq(value(kor.aggro), 1)
	end)

	it("summarizes it for the list (SPEC-02 §4.1)", function()
		deepEq(R().Summary(build(known())), { mob = 1, worst = "D", cross = 3, aggro = 1, valid = 100 })
	end)

	it("lists tank changes between two units treated as tanks", function()
		local spec = known()
		spec.events[12] = { 310, "A", 1, 3, 2, "1", "1" }
		local r = compute(build(spec))
		eq(#value(r.rows.tankChanges), 1)
		deepEq(r.rows.tankChanges.value[1], { t = 310, mob = 1, from = 2, to = 3 })
		eq(#value(r.rows.aggroLosses), 0)
	end)

	it("says points only with two readings with a number in the 3 s before and a rise", function()
		local spec = known()
		spec.rows[7] = { 200, 1, 3, 700, "0" }
		table.sort(spec.rows, function(a, b) return a[1] < b[1] end)
		local r = compute(build(spec))
		isNil(r.rows.aggroLosses.value[1].points)
	end)

	it("counts a rise from UNKNOWN only above the last known state", function()
		local spec = known()
		spec.events = {
			{ 0, "C", 0, 0, 0, "1" }, { 0, "M", 0, 0, 0, "v" }, { 0, "T", 1 },
			{ 0, "S", 1, 1, 0, "W", "-" }, { 50, "S", 1, 1, 0, "U", "W" }, { 60, "S", 1, 1, 0, "W", "U" },
			{ 70, "S", 1, 1, 0, "U", "W" }, { 80, "S", 1, 1, 0, "D", "U" }, { 400, "c" },
		}
		local me = unit(compute(build(spec)), "Testchar").cells
		eq(me.warningCross.value, 1)
		eq(me.dangerCross.value, 1)
	end)

	it("counts only inside the combat periods and while the mob is monitored", function()
		local spec = known()
		spec.events = {
			{ 0, "C", 0, 0, 0, "1" }, { 0, "M", 0, 0, 0, "v" }, { 0, "T", 1 }, { 0, "S", 1, 1, 0, "W", "-" },
			{ 100, "T", 2 }, { 150, "S", 2, 1, 0, "D", "-" }, { 200, "c" }, { 260, "C", 0, 0, 0, "2" },
			{ 270, "S", 2, 1, 0, "D", "-" }, { 300, "c" },
		}
		spec.dur, spec.fight = 300, 240
		local r = compute(build(spec))
		local me = unit(r, "Testchar").cells
		eq(me.warningTime.value, 100, "until the other mob")
		eq(me.dangerTime.value, 80, "until each end of combat")
		eq(me.dangerCross.value, 2, "a new combat starts again")
		eq(r.rows.duration.value.pulls, 2)
		eq(r.rows.duration.value.fight, 240)
	end)
end)

describe("partial coverage (REC-10)", function()
	it("shows lower bounds with the unknown time, in mode none, gaps and UNKNOWN states", function()
		local spec = known()
		spec.events = {
			{ 0, "C", 0, 0, 0, "1" }, { 0, "M", 0, 0, 0, "v" }, { 0, "T", 1 }, { 0, "S", 1, 1, 0, "W", "-" },
			{ 100, "M", 0, 0, 0, "n", "S" }, { 150, "M", 0, 0, 0, "v" }, { 250, "G", 0, 0, 0, "t", "-", "-", 20 },
			{ 300, "S", 1, 1, 0, "U", "W" }, { 320, "S", 1, 1, 0, "S", "U" }, { 400, "c" },
		}
		local r = compute(build(spec))
		local me = unit(r, "Testchar").cells
		eq(me.warningTime.status, "ok")
		eq(me.warningTime.category, "estimated")
		eq(me.warningTime.lower, true)
		eq(me.warningTime.unknownTime, 90, "50 s none + 20 gap + 20 UNKNOWN")
		eq(me.warningCross.lower, true)
		eq(me.aggro.category, "estimated")
		eq(r.rows.quality.value.noneTime, 50)
		eq(r.rows.quality.value.gapTime, 20)
		eq(R().CellText(r, me.warningTime), "at least 30.0 s · 9.0 s unknown")
		eq(R().CellText(r, me.warningCross), "at least 1")
	end)

	it("marks a unit with a read without a value", function()
		local spec = known()
		spec.rows[#spec.rows + 1] = { 340, 1, 1, -1, "S" }
		local me = unit(compute(build(spec)), "Testchar").cells
		eq(me.warningTime.lower, true)
		eq(me.warningTime.category, "estimated")
	end)

	it("counts the time without a monitored mob", function()
		local spec = known()
		spec.events = { { 0, "C", 0, 0, 0, "1" }, { 100, "T", 1 }, { 300, "T", 0, 0, 0, "n" }, { 400, "c" } }
		eq(compute(build(spec)).rows.quality.value.noMobTime, 200)
	end)
end)

describe("Insufficient data (REC-10)", function()
	it("is said for the whole row under 3 useful readings", function()
		local spec = known()
		spec.units = { ME, TANK, KOR, { name = "Sela", role = "HEALER", token = "party3" } }
		spec.rows[#spec.rows + 1] = { 340, 1, 4, 100, "0" }
		spec.rows[#spec.rows + 1] = { 350, 1, 4, 110, "0" }
		spec.q = { v = { 80, 80, 80, 2 }, s = { 0, 0, 0, 0 }, x = { 0, 0, 0, 0 } }
		local sela = unit(compute(build(spec)), "Sela")
		eq(sela.status, "insufficient")
		for _, key in ipairs(R().UNIT_CELLS) do
			eq(sela.cells[key].status, "insufficient", key)
			eq(sela.cells[key].category, "unknown", key)
		end
	end)

	it("is said for the maximum under 3 readings with a number and for states under 1 s known", function()
		local spec = known()
		spec.units = { ME }
		spec.rows = { { 10, 1, 1, 400, "0" }, { 20, 1, 1, 410, "0" }, { 30, 1, 1, -1, "a" } }
		spec.events = { { 0, "C", 0, 0, 0, "1" }, { 0, "T", 1 }, { 0, "S", 1, 1, 0, "S", "-" }, { 5, "c" } }
		spec.q = { v = { 5 }, s = { 0 }, x = { 0 } }
		local me = unit(compute(build(spec)), "Testchar").cells
		eq(me.maxPct.status, "insufficient")
		eq(me.warningTime.status, "insufficient")
		eq(me.quality.status, "ok")
	end)
end)

describe("state only", function()
	local function stateSpec()
		return {
			units = { ME, TANK }, mobs = { BOSS }, dur = 200,
			events = {
				{ 0, "C", 0, 0, 0, "1" }, { 0, "M", 0, 0, 0, "s" }, { 0, "T", 1 }, { 0, "A", 1, 2, 0, "1" },
				{ 0, "S", 1, 1, 0, "S", "-", "s" }, { 100, "S", 1, 1, 0, "W", "S", "s" },
				{ 150, "A", 1, 1, 2, "0", "1" }, { 200, "c" },
			},
			rows = { { 5, 1, 1, -1, "a" }, { 5, 1, 2, -1, "d" }, { 100, 1, 1, -1, "b" } },
			q = { v = { 0, 0 }, s = { 40, 40 }, x = { 0, 0 } },
		}
	end

	it("gives everything but the percentages, from the game states", function()
		local r = compute(build(stateSpec()))
		local me = unit(r, "Testchar").cells
		eq(me.warningCross.value, 1)
		eq(me.warningTime.value, 100)
		eq(me.warningTime.basis, "game")
		eq(me.maxPct.status, "na")
		eq(me.maxPct.reason, "state-only")
		eq(R().CellText(r, me.maxPct), "Not available")
		eq(R().BasisText(r, "game"), "Game states")
		local losses = r.rows.aggroLosses.value
		eq(#losses, 1)
		isNil(losses[1].points)
		eq(r.rows.quality.value.state, 100)
		eq(r.rows.tanks.status, "ok")
	end)

	it("mixes game states and thresholds when the mode changes midway", function()
		local spec = known()
		table.insert(spec.events, 11, { 305, "M", 0, 0, 0, "s", "s" })
		table.insert(spec.events, 14, { 340, "S", 1, 1, 0, "D", "S", "s" })
		local me = unit(compute(build(spec)), "Testchar").cells
		eq(me.dangerTime.basis, "mixed")
		eq(me.maxPct.status, "ok")
	end)
end)

describe("nothing readable", function()
	local function noneSpec()
		return {
			units = { ME, TANK }, mobs = { { name = "Gorrak" }, ADD }, dur = 300,
			events = {
				{ 0, "C", 0, 0, 0, "1" }, { 0, "M", 0, 0, 0, "n", "S" }, { 0, "T", 1 }, { 200, "T", 2 },
				{ 250, "D", 0, 1, 0, "p" }, { 300, "c" },
			},
			rows = { { 5, 1, 1, -1, "S" }, { 5, 1, 2, -1, "S" } },
			q = { v = { 0, 0 }, s = { 0, 0 }, x = { 60, 60 } },
		}
	end

	it("says duration, mob, deaths and quality, and Not available with its reason for the threat", function()
		local r = compute(build(noneSpec()))
		eq(r.rows.duration.value.dur, 300)
		eq(r.rows.mob.value.index, 1, "the most monitored")
		eq(#r.rows.deaths.value, 1)
		eq(r.rows.quality.value.unknown, 100)
		eq(r.rows.quality.reason, "secret")
		for _, key in ipairs({ "tanks", "tankChanges", "aggroLosses", "alerts" }) do
			eq(r.rows[key].status, "na", key)
			eq(r.rows[key].reason, "secret", key)
			eq(r.rows[key].category, "unknown", key)
		end
		eq(R().CellText(r, r.rows.tanks), "Not available (unknown tank)")
		local me = unit(r, "Testchar")
		eq(me.status, "na")
		eq(me.cells.warningCross.status, "na")
		eq(me.cells.quality.status, "ok")
		deepEq(r.summary, { mob = 1, valid = 0 })
	end)

	it("shows an unreadable mob name as unknown and no mob at all as unknown", function()
		local spec = noneSpec()
		spec.mobs = { {} }
		spec.events = { { 0, "C", 0, 0, 0, "1" }, { 0, "T", 1 }, { 300, "c" } }
		local r = compute(build(spec))
		eq(r.rows.mob.status, "unknown")
		contains(R().CellText(r, r.rows.mob), L().MON_UNKNOWN_MOB)
		spec.mobs, spec.rows, spec.events = {}, {}, { { 0, "C", 0, 0, 0, "1" }, { 300, "c" } }
		r = compute(build(spec))
		eq(r.rows.mob.status, "unknown")
		eq(R().CellText(r, r.rows.mob), "Unknown")
	end)
end)

describe("interrupted and truncated sessions (SPEC-05 §3.1)", function()
	it("counts up to the last record and says why and until when", function()
		local spec = known()
		spec.events[#spec.events] = nil            -- no `c`: the combat never ended
		spec.state, spec.ended, spec.dur, spec.fight = "interrupted", "reload", 360, 0
		local r = compute(build(spec))
		eq(r.interrupted, true)
		eq(r.recordedUntil, 360)
		eq(r.rows.duration.lower, true)
		isNil(r.rows.duration.value.fight, "a fight of 0 after a crash is unknown, never invented")
		eq(unit(r, "Kor").cells.dangerTime.value, 40, "until the last record")
		deepEq(R().Headlines(r), { "Interrupted (reload)", "Recorded until 0:36" })
		eq(R().CellText(r, r.rows.duration), "at least 0:36")
	end)

	it("says where the samples stopped", function()
		local spec = known()
		spec.trunc = 320
		local r = compute(build(spec))
		eq(r.truncated, 320)
		eq(unit(r, "Testchar").cells.maxPct.truncated, true)
		eq(r.rows.quality.truncated, true)
		deepEq(R().Headlines(r), { "Samples stopped at 0:32: limit reached" })
	end)
end)

describe("the words (REC-11, ADR 0009)", function()
	it("writes every cell in both languages", function()
		local s = build(known())
		for _, code in ipairs({ "enUS", "itIT" }) do
			Mock.ns.Locale.Apply(code)
			local r = compute(s)
			for _, c in ipairs(r.rows) do truthy(#R().CellText(r, c) > 0, c.key) end
			for _, u in ipairs(r.units) do
				for _, key in ipairs(R().UNIT_CELLS) do truthy(#R().CellText(r, u.cells[key]) > 0, key) end
			end
		end
		Mock.ns.Locale.Apply("enUS")
		local r = compute(s)
		eq(R().CellText(r, r.rows.duration), "0:40 · 0:40 in combat")
		eq(R().CellText(r, r.rows.aggroLosses), "0:31  Kor took aggro from Bram (+25 points in the 3 s before)")
		eq(R().CellText(r, r.rows.tankChanges), "No tank change recorded")
		eq(R().CellText(r, r.rows.deaths), "0:33  Bram died")
		eq(R().CellText(r, unit(r, "Testchar").cells.maxPct), "96 % at 0:20")
		eq(R().ReasonText("secret"), L().REPORT_WHY_SECRET)
	end)

	it("has a key for every metric, reason and alert kind", function()
		for _, list in ipairs({ R().METRIC_KEYS, R().REASON_KEYS }) do
			for _, key in pairs(list) do notNil(Mock.ns.Locale.Strings("itIT")[key], key) end
		end
		for _, kind in ipairs(R().ALERT_ORDER) do
			notNil(Mock.ns.Locale.Strings("enUS")["REPORT_ALERT_" .. kind:upper()], kind)
		end
	end)
end)

local function add(s)
	truthy(St().Add(s))
	truthy(St().Closed(s, true))
	return s
end

describe("Build (SPEC-05 §3.4)", function()
	it("gives the same report in slices as in one pass, over several frames", function()
		local s = add(build(known()))
		local whole = compute(s)
		R().SLICE = 3
		local got, calls = nil, 0
		R().Build(s.id, function(report) got, calls = report, calls + 1 end)
		isNil(got, "more frames to go")
		for _ = 1, 40 do Mock.Advance(0.05) end
		eq(calls, 1)
		deepEq(got, whole)
		eq(R().Cached(), got)
		R().Build(s.id, function(report) eq(report, got, "from memory") calls = calls + 1 end)
		eq(calls, 2)
		eq(#Mock.errors, 0)
	end)

	it("refuses an unknown, damaged or open session, and drops what is gone", function()
		local why
		local function done(_, reason) why = reason end
		R().Build("nope", done)
		eq(why, "unknown")
		local s = add(build(known()))
		R().Build(s.id, done)
		eq(R().Cached().id, s.id)
		truthy(St().Delete(s.id))
		isNil(R().Cached())
		local bad = add(build(known()))
		bad.cols.s = string.rep("?", bad.n)
		R().Build(bad.id, done)
		eq(why, "damaged")
		local open = build(known())
		open.state = "open"
		St().Add(open)
		R().Build(open.id, done)
		eq(why, "recording")
	end)

	it("stops when the session goes while it is being built", function()
		local s = add(build(known()))
		R().SLICE = 3
		local why
		R().Build(s.id, function(_, reason) why = reason end)
		truthy(St().Delete(s.id))
		for _ = 1, 40 do Mock.Advance(0.05) end
		eq(why, "unknown")
	end)

	it("lets Storage write `sum` at the close", function()
		local s = add(build(known()))
		deepEq(s.sum, { mob = 1, worst = "D", cross = 3, aggro = 1, valid = 100 })
		deepEq(St().List()[1].sum, s.sum)
	end)
end)

describe("with the `reports` switch off (ADR 0014)", function()
	before_boot(function(M)
		M.features = { monitor = true, alerts = true, coach = true, recording = true, reports = false }
	end)

	it("builds nothing and writes no summary", function()
		local s = add(build(known()))
		isNil(s.sum)
		local why
		R().Build(s.id, function(_, reason) why = reason end)
		eq(why, "off")
	end)
end)

describe("recordings of the real recorder", function()
	for _, outcome in ipairs(Fight.OUTCOMES) do
		it("report a party fight in " .. outcome, function()
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
			notNil(list[1].sum, "summary at the close")
			local report
			R().Build(list[1].id, function(r) report = r end)
			Mock.Advance(1)
			notNil(report)
			eq(report.rows.duration.value.dur, 200)
			eq(report.rows.mob.value.name, outcome == "none" and report.rows.mob.value.name or "Gorrak")
			local me
			for _, u in ipairs(report.units) do if u.me then me = u end end
			notNil(me)
			if outcome == "values" then
				eq(me.cells.maxPct.status, "ok")
				truthy(me.cells.maxPct.value.pct >= 85)
				truthy(me.cells.warningCross.value + me.cells.dangerCross.value >= 1)
				truthy(#report.rows.aggroLosses.value >= 1)
			elseif outcome == "state" then
				eq(me.cells.maxPct.status, "na")
				eq(me.cells.maxPct.reason, "state-only")
				truthy(me.cells.dangerCross.status == "ok", me.cells.dangerCross.status)
				truthy(#report.rows.aggroLosses.value >= 1)
			else
				eq(me.status, "na")
				eq(report.rows.aggroLosses.status, "na")
				eq(report.rows.quality.value.unknown, 100)
			end
			for _, c in ipairs(report.rows) do truthy(#R().CellText(report, c) > 0, c.key) end
			eq(#Mock.errors, 0)
		end)
	end
end)
