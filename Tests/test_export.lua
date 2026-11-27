-- Data/Export.lua (SPEC-06 §4, §6 M6.5; EXP-01-EXP-07, ANA-04; ADR 0001, 0003, 0018; Q15, Q24): every content and
-- format round-trips through the strict CSV reader of Tests/lib/csv.lua with commas, quotes, line breaks, formulas,
-- accents and realm names; every value carries its category and status; "|" doubled for the box; the text in complete
-- code blocks of at most 1900 characters that split no line; with the names replaced no name of the sessions appears
-- and the numbers are stable; the limit keeps whole rows and says what was left out outside the text; no GUID, no line
-- of /atw debug, nothing written, posted or sent; the build in slices; nothing with the switch off.

local function features(extra)
	local on = { monitor = true, alerts = true, coach = true, recording = true, reports = true, timeline = true,
		replay = true, analytics = true, export = true }
	for k, v in pairs(extra or {}) do on[k] = v end
	return on
end

before_boot(function(M) M.features = features() end)

local function E() return Mock.ns.Export end
local function S() return Mock.ns.Session end
local function St() return Mock.ns.Storage end
local function C() return Mock.ns.Compare end
local function L() return Mock.ns.L end

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

local ME = { name = "Testchar", class = "MAGE", role = "DAMAGER", token = "player", me = true }
local TANK = { name = "Bram", class = "WARRIOR", role = "TANK", token = "party1" }
local KOR = { name = "Kor", class = "ROGUE", role = "DAMAGER", token = "party2" }
local BOSS = { name = "Gorrak", class = "elite", npc = 448 }
local ADD = { name = "Pup", class = "normal" }

-- A stored closed session. spec: units, mobs, events, rows, q, dur, fight, state, ended, rec, zone, started.
local function build(spec)
	counter = counter + 1
	local s = S().New{ id = "ex-" .. counter, started = spec.started or (1767225600 + counter * 100), group = "party",
		diff = 1, zone = spec.zone or "The Deadmines",
		rec = spec.rec or { hz = 2, warning = 80, danger = 95, mode = "values" } }
	for _, u in ipairs(spec.units or { ME, TANK, KOR }) do S().AddUnit(s, u, 0) end
	for _, m in ipairs(spec.mobs or { BOSS, ADD }) do S().AddMob(s, m, 0) end
	for _, e in ipairs(ordered(spec.events or {})) do
		truthy(S().AddEvent(s, e[1], e[2], e[3], e[4], e[5], e[6], e[7], e[8], e[9]), "event at " .. e[1])
	end
	for _, r in ipairs(spec.rows or {}) do S().AddRow(s, r[1], r[2], r[3], r[4], r[5]) end
	if spec.q then
		for key, list in pairs(spec.q) do for i, v in ipairs(list) do s.q[key][i] = v end end
	end
	S().Join(s)
	s.state, s.ended = spec.state or "complete", spec.ended or "combat"
	s.dur, s.fight = spec.dur or 400, spec.fight or spec.dur or 400
	truthy(St().Add(s))
	truthy(St().Closed(s, true))
	return s
end

-- 40 s in values with one of every event.
local function known(extra)
	local spec = {
		dur = 400,
		events = {
			{ 0, "C", 0, 0, 0, "1" }, { 0, "M", 0, 0, 0, "v" }, { 0, "T", 1 },
			{ 0, "A", 1, 2, 0, "1" }, { 0, "S", 1, 2, 0, "S", "-" }, { 0, "S", 1, 1, 0, "S", "-" },
			{ 100, "S", 1, 1, 0, "W", "S", "p" }, { 130, "S", 1, 1, 0, "S", "W" }, { 200, "S", 1, 1, 0, "D", "S" },
			{ 260, "S", 1, 1, 0, "W", "D" }, { 300, "S", 1, 1, 0, "S", "W" },
			{ 310, "A", 1, 3, 2, "0", "1" }, { 320, "S", 1, 3, 0, "D", "-" },
			{ 330, "D", 0, 2, 0, "g" }, { 340, "D", 2, 0, 0, "t" },
			{ 350, "L", 1, 1, 0, "w", "1", "0", "ch" }, { 351, "H", 0, 1, 0, "1", "p", "m" },
			{ 360, "N", 0, 0, 0, "e", "1", nil, 663 }, { 400, "c" },
		},
		rows = {
			{ 10, 1, 1, 400, "0" }, { 10, 1, 2, 1000, "3" }, { 100, 1, 1, 820, "0" }, { 150, 1, 2, 1000, "3" },
			{ 200, 1, 1, 960, "1" }, { 260, 1, 1, 850, "1" }, { 285, 1, 3, 700, "0" }, { 290, 1, 2, 1000, "3" },
			{ 300, 1, 1, 500, "0" }, { 300, 1, 3, 950, "1" }, { 320, 1, 3, 1000, "3" }, { 330, 2, 1, 100, "0" },
			{ 340, 1, 1, -1, "b" }, { 345, 1, 3, -1, "S" }, { 350, 1, 3, 3843, "4" },
		},
		q = { v = { 80, 80, 80 }, s = { 0, 0, 0 }, x = { 0, 0, 0 } },
	}
	for k, v in pairs(extra or {}) do
		if k == "more" then
			for _, e in ipairs(v) do spec.events[#spec.events + 1] = e end
		else
			spec[k] = v
		end
	end
	return spec
end

-- A recording pause of 2.4 s and the enemy lost near the end.
local PAUSE = { { 355, "G", 0, 0, 0, "t", nil, nil, 24 }, { 370, "T", 0, 0, 0, "d" } }

-- Builds and returns text, info (or nil, why), running the frames.
local function export(kind, format, s, extra)
	local text, info, called
	local request = { kind = kind, format = format, id = s and s.id }
	for k, v in pairs(extra or {}) do request[k] = v end
	E().Build(request, function(a, b) text, info, called = a, b, true end)
	for _ = 1, 400 do
		if called then break end
		Mock.Advance(0.05)
	end
	truthy(called, kind .. " " .. format .. " done")
	return text, info
end

local function records(kind, s, extra)
	local text, info = export(kind, "csv", s, extra)
	truthy(text, tostring(info))
	local header, out = CSV.records(text)
	deepEq(header, E().CSV[kind])
	return out, text, info
end

local function find(list, fields)
	for _, r in ipairs(list) do
		local ok = true
		for k, v in pairs(fields) do
			if r[k] ~= v then ok = false break end
		end
		if ok then return r end
	end
	return nil
end

local function metric(list, name, unit) return find(list, { metric = name, unit = unit or "" }) end

local function parts(text)
	local out = {}
	for block in text:gmatch("```\n(.-)\n```") do out[#out + 1] = block end
	return out
end

local STATUS = { ok = true, na = true, insufficient = true, unknown = true }
local CATEGORY = { detected = true, calculated = true, estimated = true, unknown = true }

local function compare(key, filters)
	local result
	C().Build(key or "npc:448", filters, nil, function(r) result = r end)
	for _ = 1, 200 do
		if result then break end
		Mock.Advance(0.05)
	end
	truthy(result)
	return result
end

describe("the fight, CSV (SPEC-06 §4.3)", function()
	it("has one row per metric of the session and of each unit, with the known values", function()
		local s = build(known())
		local list = records("fight", s)
		eq(#list, 25 + 3 * 9)
		local d = metric(list, "duration_s")
		eq(d.value, "40.0")
		eq(d.session, s.id)
		matches(d.started_utc, "^%d%d%d%d%-%d%d%-%d%d %d%d:%d%d$")
		eq(d.zone, "The Deadmines")
		eq(d.enemy, "Gorrak")
		eq(d.category, "detected")
		eq(d.status, "ok")
		eq(d.at_least, "")
		eq(metric(list, "combat_s").value, "40.0")
		eq(metric(list, "pulls").value, "1")
		eq(metric(list, "warning_threshold").value, "80")
		eq(metric(list, "danger_threshold").value, "95")
		eq(metric(list, "valid_values_pct").value, "100.0")
		eq(metric(list, "valid_state_pct").value, "100.0")
		eq(metric(list, "unknown_pct").value, "0.0")
		eq(metric(list, "coverage_pct").value, "100.0")
		eq(metric(list, "warning_crossings").value, "1")
		eq(metric(list, "danger_crossings").value, "2")
		eq(metric(list, "warning_crossings").basis, "thresholds")
		eq(metric(list, "warning_any_s").value, "21.0")
		eq(metric(list, "danger_any_s").value, "14.0")
		eq(metric(list, "holder_changes").value, "1")
		eq(metric(list, "to_non_tank").value, "1")
		eq(metric(list, "tank_to_tank").value, "0")
		eq(metric(list, "back_to_tank").value, "0")
		eq(metric(list, "taken_by_non_tank").value, "1")
		eq(metric(list, "unstable_intervals").value, "0")
		eq(metric(list, "unstable_s").value, "0.0")
		eq(metric(list, "risk_situations").value, "3")
		eq(metric(list, "risk_per_min").value, "4.5")
		eq(metric(list, "deaths").value, "2")
		eq(metric(list, "alerts").value, "1")
		local me = metric(list, "max_pct", "Testchar")
		eq(me.value, "96.0")
		eq(me.role, "DAMAGER")
		eq(me.class, "MAGE")
		eq(metric(list, "warning_time_s", "Testchar").value, "7.0")
		eq(metric(list, "danger_time_s", "Testchar").value, "6.0")
		eq(metric(list, "taken_by_non_tank", "Kor").value, "1")
		eq(metric(list, "max_pct", "Kor").value, "384.3")
		eq(metric(list, "max_pct", "Kor").category, "detected")
		eq(metric(list, "valid_state_pct", "Bram").value, "100.0")
		-- the units in the order player, tanks, index
		eq(list[26].unit, "Testchar")
		eq(list[35].unit, "Bram")
		eq(list[44].unit, "Kor")
		eq(#Mock.errors, 0)
	end)

	it("carries a category and a status on every row, empty when there is no value (EXP-06)", function()
		local state = build(known{ rec = { hz = 2, warning = 80, danger = 95, mode = "state" },
			events = { { 0, "C", 0, 0, 0, "1" }, { 0, "M", 0, 0, 0, "s" }, { 0, "T", 1 }, { 0, "A", 1, 2, 0, "1" },
				{ 0, "S", 1, 1, 0, "S", "-" }, { 400, "c" } },
			rows = { { 10, 1, 1, -1, "a" }, { 20, 1, 1, -1, "a" }, { 30, 1, 1, -1, "a" }, { 10, 1, 2, -1, "d" } },
			q = { v = { 0, 0, 0 }, s = { 80, 80, 80 }, x = { 0, 0, 0 } } })
		local low = build(known{ q = { v = { 30, 30, 30 }, s = { 0, 0, 0 }, x = { 70, 70, 70 } } })
		local nothing = build(known{ rec = { hz = 2, warning = 80, danger = 95, mode = "none" },
			events = { { 0, "C", 0, 0, 0, "1" }, { 0, "M", 0, 0, 0, "n", "S" }, { 0, "T", 1 }, { 400, "c" } },
			rows = { { 10, 1, 1, -1, "S" }, { 20, 1, 1, -1, "S" }, { 30, 1, 1, -1, "S" } },
			q = { v = { 0, 0, 0 }, s = { 0, 0, 0 }, x = { 80, 80, 80 } } })
		local interrupted = build(known{ state = "interrupted", ended = "reload", fight = 0 })
		for _, s in ipairs({ state, low, nothing, interrupted }) do
			for _, r in ipairs(records("fight", s)) do
				truthy(STATUS[r.status], r.metric .. " " .. r.status)
				truthy(CATEGORY[r.category], r.metric .. " " .. r.category)
				if r.status == "ok" then
					truthy(r.value ~= "", r.metric)
					truthy(r.category ~= "unknown", r.metric)
				else
					eq(r.value, "", r.metric)
					eq(r.category, "unknown", r.metric)
				end
			end
		end
		local list = records("fight", state)
		local max = metric(list, "max_pct", "Testchar")
		eq(max.status, "na")
		eq(max.reason, "state-only")
		eq(metric(list, "closest_to_tank_pct").status, "na")
		eq(metric(list, "warning_crossings").status, "ok")
		eq(metric(list, "warning_crossings").basis, "game")
		list = records("fight", low)
		eq(metric(list, "warning_crossings").status, "insufficient")
		eq(metric(list, "warning_crossings").reason, "low-valid")
		list = records("fight", nothing)
		eq(metric(list, "warning_crossings").status, "na")
		eq(metric(list, "warning_crossings").reason, "secret")
		list = records("fight", interrupted)
		eq(metric(list, "duration_s").at_least, "yes")
		eq(metric(list, "combat_s").status, "unknown")
	end)
end)

describe("the fight, text (SPEC-06 §4.4)", function()
	it("is one code block with the title, the report, Analytics, the units and the legend", function()
		local s = build(known())
		local text, info = export("fight", "text", s)
		local blocks = parts(text)
		eq(#blocks, info.parts)
		matches(text, "^```\nThreatwarden · Gorrak · [%d%-]+ [%d:]+ · The Deadmines")
		matches(text, "\n```$")
		contains(text, L().REPORT_METRIC_DURATION .. " (" .. L().CAT_DETECTED .. "): 0:40")
		contains(text, L().REPORT_METRIC_TANKS .. " (" .. L().CAT_DETECTED .. "): Bram")
		contains(text, "\n" .. L().ANALYTICS_PAGE .. "\n")
		contains(text, L().ANALYTICS_METRIC_CROSSINGS .. " (" .. L().CAT_ESTIMATED .. "): at least 1 Warning · at least 2")
		contains(text, L().ANALYTICS_METRIC_AGGRO_TAKEN .. " (" .. L().CAT_DETECTED .. "): 1")
		contains(text, L().ANALYTICS_METRIC_CLOSEST)
		matches(text, "\nUnit%s+Warning%s+Danger%s+Time in Warning")
		matches(text, "\nTestchar%s+1 C%s+1 C%s+7%.0 s C")
		contains(text, L().EXPORT_LEGEND_MARKS)
		contains(text, L().EXPORT_LEGEND)
		eq(info.left, 0)
		eq(info.bytes, #text)
		eq(#Mock.errors, 0)
	end)

	it("marks an estimate with ~ and at least, and writes Not available and Insufficient data with the reason", function()
		local s = build(known{ state = "interrupted", ended = "reload" })
		local text = export("fight", "text", s)
		contains(text, L().REPORT_METRIC_DURATION .. " (" .. L().CAT_DETECTED .. "): at least 0:40")
		contains(text, L().REPORT_INTERRUPTED:format(L().REPORT_ENDED_RELOAD))
		local low = build(known{ q = { v = { 30, 30, 30 }, s = { 0, 0, 0 }, x = { 70, 70, 70 } } })
		text = export("fight", "text", low)
		contains(text, L().ANALYTICS_METRIC_CROSSINGS .. ": " .. L().REPORT_INSUFFICIENT .. " · "
			.. L().ANALYTICS_WHY_LOW_VALID:format(30))
		contains(text, "Testchar: " .. L().ANALYTICS_WHY_LOW_VALID:format(30))
		contains(text, L().REPORT_METRIC_QUALITY)
		local gaps = build(known{ events = { { 0, "C", 0, 0, 0, "1" }, { 0, "M", 0, 0, 0, "v" }, { 0, "T", 1 },
			{ 0, "S", 1, 1, 0, "S", "-" }, { 100, "S", 1, 1, 0, "W", "S" }, { 200, "G", 0, 0, 0, "t", nil, nil, 50 },
			{ 400, "c" } } })
		text = export("fight", "text", gaps)
		contains(text, "(" .. L().CAT_ESTIMATED .. "): at least")
		contains(text, "at least")
		falsy(text:find("~at least", 1, true))
	end)

	it("speaks the interface language while the CSV stays English", function()
		boot(function(M) M.player.locale = "itIT" end)
		local s = build(known())
		local text = export("fight", "text", s, { replace = true })
		contains(text, "Superamenti di soglia")
		contains(text, "\nTu ")
		contains(text, "Giocatore 1")
		local csv = export("fight", "csv", s, { replace = true })
		contains(csv, ",You,")
		contains(csv, ",Player 1,")
	end)

	it("replaces backticks and line breaks inside the block", function()
		local s = build(known{ mobs = { { name = "Go`rak", class = "elite", npc = 448 }, ADD }, zone = "A```B" })
		local text = export("fight", "text", s)
		local _, fences = text:gsub("```", "")
		eq(fences, 2 * #parts(text))
		contains(text, "Go'rak")
		eq(E().TextValue("a`b\r\n\tc"), "a'b   c")
		contains(text, "A'''B")
	end)

	it("splits a long text into complete parts of at most 1900 characters, never a line", function()
		local units, q = {}, { v = {}, s = {}, x = {} }
		local events = { { 0, "C", 0, 0, 0, "1" }, { 0, "M", 0, 0, 0, "v" }, { 0, "T", 1 }, { 0, "A", 1, 2, 0, "1" } }
		local rows = {}
		for u = 1, 40 do
			units[u] = { name = "Raidèr" .. u .. "-Realmlongname", token = "raid" .. u, role = u <= 2 and "TANK" or "DAMAGER" }
			events[#events + 1] = { 0, "S", 1, u, 0, "S", "-" }
			q.v[u], q.s[u], q.x[u] = 100, 0, 0
			for _, t in ipairs({ 10, 20, 30 }) do rows[#rows + 1] = { t, 1, u, 500, "0" } end
		end
		table.sort(rows, function(a, b) return a[1] < b[1] end)
		local s = build{ units = units, events = events, rows = rows, q = q, dur = 400 }
		local text, info = export("fight", "text", s)
		local blocks = parts(text)
		truthy(#blocks > 2, "parts: " .. #blocks)
		eq(#blocks, info.parts)
		local names = 0
		for i, block in ipairs(blocks) do
			truthy(E().Length("```\n" .. block .. "\n```") <= E().PART_MAX, "part " .. i)
			matches(block, "^Threatwarden · Gorrak · [^\n]+ %(" .. i .. "/" .. #blocks .. "%)\n")
			for line in block:gmatch("[^\n]+") do
				if line:find("^Raidèr") and line:find(" C") then
					names = names + 1
					-- cut at 18 characters with "…", the row whole
					matches(line, "^Raidèr%d+%-[%a]*…%s+0 C%s+0 C")
				end
			end
		end
		eq(names, 40)
		-- the header of the table is repeated in every part the table crosses
		for i = 2, #blocks do
			if blocks[i]:find("\nRaidèr") then matches(blocks[i], "\nUnit%s+Warning") end
		end
		eq(text, table.concat((function()
			local whole = {}
			for i, block in ipairs(blocks) do whole[i] = "```\n" .. block .. "\n```" end
			return whole
		end)(), "\n\n"))
	end)
end)

describe("the events (SPEC-06 §4.3)", function()
	it("lists every event in order with its words, detail and category", function()
		local s = build(known{ more = PAUSE })
		local list, _, info = records("events", s)
		eq(#list, s.ne)
		eq(info.left, 0)
		eq(list[1].event, "combat_start")
		eq(list[1].detail, "pull=1")
		eq(list[1].category, "detected")
		eq(find(list, { event = "mode" }).detail, "mode=values")
		eq(find(list, { event = "target" }).enemy, "Gorrak")
		eq(find(list, { event = "holder", t_s = "0.0" }).detail, "kind=first")
		local taken = find(list, { event = "holder", t_s = "31.0" })
		eq(taken.detail, "kind=to_non_tank")
		eq(taken.unit, "Kor")
		eq(taken.other_unit, "Bram")
		local warn = find(list, { event = "state", t_s = "10.0" })
		eq(warn.detail, "new=warning;old=safe;reason=predicted")
		eq(warn.category, "calculated")
		eq(warn.unit, "Testchar")
		eq(find(list, { event = "death", t_s = "33.0" }).detail, "source=unit_died")
		local mobDeath = find(list, { event = "death", t_s = "34.0" })
		eq(mobDeath.detail, "source=target")
		eq(mobDeath.enemy, "Pup")
		eq(mobDeath.unit, "")
		local alert = find(list, { event = "alert" })
		eq(alert.detail, "kind=warning;severity=1;muted=no;category=calculated;confidence=high")
		eq(alert.category, "calculated")
		local tip = find(list, { event = "coach_tip" })
		eq(tip.detail, "rule=T1;category=predicted;confidence=medium")
		eq(tip.category, "predicted")
		eq(find(list, { event = "recording_paused" }).detail, "seconds=2.4")
		eq(find(list, { event = "encounter" }).detail, "phase=end;result=success;encounter=663")
		eq(find(list, { event = "target", t_s = "37.0" }).detail, "reason=dead")
		eq(list[#list].event, "combat_end")
		for _, r in ipairs(list) do truthy(r.category ~= "", r.event) end
	end)

	it("says a state read from the game as detected, an interrupted recording and a limit", function()
		local s = build(known{ rec = { hz = 2, warning = 80, danger = 95, mode = "state" },
			events = { { 0, "C", 0, 0, 0, "1" }, { 0, "M", 0, 0, 0, "s" }, { 0, "T", 1 }, { 0, "S", 1, 1, 0, "S", "-" },
				{ 100, "C", 0, 0, 0, "r" }, { 200, "M", 0, 0, 0, "n", "S" }, { 200, "S", 1, 1, 0, "U", "S", "S" },
				{ 300, "Z", 0, 0, 0, "e" }, { 400, "X", 0, 0, 0, "o" } } })
		local list = records("events", s)
		eq(find(list, { event = "state", t_s = "0.0" }).category, "detected")
		eq(find(list, { event = "combat_start", t_s = "10.0" }).detail, "pull=2;continued=reload")
		eq(find(list, { event = "mode", t_s = "20.0" }).detail, "mode=none;reason=secret")
		eq(find(list, { event = "state", t_s = "20.0" }).category, "unknown")
		eq(find(list, { event = "limit" }).detail, "limit=events")
		truthy(find(list, { event = "interrupted" }))
	end)

	it("is CSV only", function()
		local s = build(known())
		local text, why = export("events", "text", s)
		isNil(text)
		eq(why, "format")
		eq(select(2, export("readings", "text", s)), "format")
	end)
end)

describe("the readings (SPEC-06 §4.3)", function()
	it("gives every row with its reading, situation, reason, category and at least", function()
		local s = build(known())
		local list, _, info = records("readings", s)
		eq(#list, s.n)
		eq(info.left, 0)
		local first = list[1]
		deepEq(first, { t_s = "1.0", enemy = "Gorrak", unit = "Testchar", percent = "40.0", reading = "value",
			situation = "0", reason = "", category = "detected", at_least = "" })
		local state = find(list, { t_s = "34.0" })
		deepEq({ state.reading, state.situation, state.percent, state.category }, { "state_only", "1", "", "detected" })
		local secret = find(list, { t_s = "34.5" })
		deepEq({ secret.reading, secret.reason, secret.percent, secret.category }, { "unknown", "secret", "", "unknown" })
		local cap = find(list, { t_s = "35.0" })
		deepEq({ cap.percent, cap.category, cap.at_least, cap.situation }, { "384.3", "estimated", "yes", "" })
	end)
end)

describe("escaping (EXP-02-EXP-04)", function()
	local HARD = { { name = "=HYPER(\"x\")", token = "player", me = true }, { name = "Bram, the \"Tall\"", token = "party1" },
		{ name = "@echo", token = "party2" } }

	it("round-trips commas, quotes, line breaks, formulas, accents and realm names", function()
		local mobs = { { name = "-Évil Boss, \"II\"", class = "elite", npc = 448 }, ADD }
		local s = build(known{ units = HARD, mobs = mobs, zone = "  Zóna  ", events = known().events })
		local list = records("fight", s)
		eq(list[1].enemy, "'-Évil Boss, \"II\"")
		-- a line break inside a field survives the reader
		local header, record = CSV.records("a,b\n" .. E().CSVValue("one\ntwo") .. "," .. E().CSVValue("x,\"y\""))
		deepEq({ header, record }, { { "a", "b" }, { { a = "one\ntwo", b = "x,\"y\"" } } })
		eq(list[1].zone, "  Zóna  ")
		truthy(metric(list, "max_pct", "'=HYPER(\"x\")"))
		truthy(metric(list, "max_pct", "Bram, the \"Tall\""))
		truthy(metric(list, "max_pct", "'@echo"))
		local rows = records("readings", s)
		eq(rows[1].unit, "'=HYPER(\"x\")")
		local events = records("events", s)
		truthy(find(events, { unit = "Bram, the \"Tall\"" }))
		local realm = build(known{ units = { { name = "Ana-Dalaran", token = "player", me = true } }, events = {
			{ 0, "C", 0, 0, 0, "1" }, { 400, "c" } }, rows = { { 1, 1, 1, 100, "0" } } })
		eq(records("readings", realm)[1].unit, "Ana-Dalaran")
		eq(E().CSVValue("+1"), "'+1")
		eq(E().CSVValue("\ttab"), "'\ttab")
		eq(E().CSVValue("a\rb"), "\"a\rb\"")
		eq(E().CSVValue(" x "), "\" x \"")
		eq(E().CSVValue(-3), "-3")
		eq(E().CSVValue("12.4"), "12.4")
		eq(E().CSVValue(nil), "")
	end)

	it("doubles | only for the box (EXP-04)", function()
		local s = build(known{ units = { { name = "Pi|pe", token = "player", me = true } },
			events = { { 0, "C", 0, 0, 0, "1" }, { 400, "c" } }, rows = { { 1, 1, 1, 100, "0" } } })
		local list, text = records("readings", s)
		eq(list[1].unit, "Pi|pe")
		eq(E().Display("a|b||"), "a||b||||")
		contains(E().Display(text), "Pi||pe")
	end)
end)

describe("the names (SPEC-06 §4.5, EXP-05)", function()
	local ROSTER = {
		{ name = "Zeldris", token = "player", me = true, role = "DAMAGER" }, { name = "Whiskers", token = "pet", pet = true },
		{ name = "Mordane", token = "party1", role = "TANK" }, { name = "Fangtooth", token = "partypet1" },
		{ token = "party2" }, { name = "Quillon-Dalaran", token = "party3" },
	}
	local function roster(extra)
		local rows, events = {}, { { 0, "C", 0, 0, 0, "1" }, { 0, "M", 0, 0, 0, "v" }, { 0, "T", 1 },
			{ 0, "A", 1, 3, 0, "1" }, { 310, "A", 1, 6, 3, "0", "1" }, { 330, "D", 0, 3, 0, "g" },
			{ 350, "L", 1, 1, 4, "w", "1", "0", "ch" }, { 400, "c" } }
		for u = 1, #ROSTER do
			events[#events + 1] = { 0, "S", 1, u, 0, "S", "-" }
			for _, t in ipairs({ 10, 20, 30 }) do rows[#rows + 1] = { t, 1, u, 500, "0" } end
		end
		table.sort(rows, function(a, b) return a[1] < b[1] end)
		local spec = { units = ROSTER, events = events, rows = rows,
			q = { v = { 100, 100, 100, 100, 100, 100 }, s = { 0, 0, 0, 0, 0, 0 }, x = { 0, 0, 0, 0, 0, 0 } } }
		for k, v in pairs(extra or {}) do spec[k] = v end
		return build(spec)
	end
	local NAMES = { "Zeldris", "Whiskers", "Mordane", "Fangtooth", "Quillon", "Dalaran", "party2" }

	local function noName(text)
		for _, name in ipairs(NAMES) do falsy(text:find(name, 1, true), "found " .. name .. " in:\n" .. text) end
	end

	it("keeps every name by default", function()
		eq(E().ANONYMOUS_DEFAULT, false)
		local s = roster()
		local text, info = export("fight", "text", s)
		falsy(info.replaced)
		for _, name in ipairs({ "Zeldris", "Mordane", "Quillon-Dalaran", "party2" }) do contains(text, name) end
	end)

	it("replaces every name of the sessions in every content and format", function()
		local first = roster()
		local second = roster{ started = 1767300000 }
		for _, kind in ipairs({ "fight", "events", "readings" }) do
			for _, format in ipairs({ "csv", "text" }) do
				if not (format == "text" and kind ~= "fight") then
					local text, info = export(kind, format, first, { replace = true })
					truthy(info.replaced)
					noName(text)
				end
			end
		end
		local result = compare()
		truthy(result.counted >= 2, "two fights: " .. second.id)
		for _, format in ipairs({ "csv", "text" }) do noName(export("compare", format, nil, { result = result, replace = true })) end
	end)

	it("says You, Your pet, Pet n and Player n in the order they appear, the same through the export", function()
		local s = roster()
		local list = records("events", s, { replace = true })
		local holder = find(list, { event = "holder", t_s = "0.0" })
		eq(holder.unit, "Player 1", "the first unit to appear")
		local taken = find(list, { event = "holder", t_s = "31.0" })
		eq(taken.unit, "Player 3")
		eq(taken.other_unit, "Player 1")
		eq(find(list, { event = "death" }).unit, "Player 1")
		local alert = find(list, { event = "alert" })
		eq(alert.unit, "You")
		eq(alert.other_unit, "Pet 1")
		eq(find(list, { event = "state", unit = "Your pet" }) ~= nil, true)
		truthy(find(list, { event = "state", unit = "Player 2" }), "the nameless unit has a number")
		local fight = records("fight", s, { replace = true })
		for _, unit in ipairs({ "You", "Your pet", "Player 1", "Player 2", "Player 3", "Pet 1" }) do
			truthy(metric(fight, "max_pct", unit), unit)
		end
		local text = export("fight", "text", s, { replace = true })
		-- the first name of the text is the tank holding the enemy
		contains(text, L().REPORT_METRIC_TANKS .. " (" .. L().CAT_DETECTED .. "): Player 1")
	end)

	it("keeps the number across sessions, with a number of its own for a nameless unit of each", function()
		local a, b = roster(), roster()
		local names = E().Names(true)
		local x = names:Unit(a, 3)
		eq(names:Unit(b, 3), x)
		eq(names:Unit(a, 6), names:Unit(b, 6))
		ne(names:Unit(a, 5), names:Unit(b, 5))
		eq(names:Unit(b, 1), "You")
		eq(E().Names(false):Unit(a, 5), "party2")
	end)

	it("replaces an enemy that bears a member's name, and keeps enemy and zone names", function()
		local s = roster{ mobs = { { name = "Mordane", class = "elite", npc = 448 }, { name = "Gorrak", npc = 9 } } }
		local text = export("fight", "text", s, { replace = true })
		noName(text)
		contains(text, "The Deadmines")
		contains(records("events", s, { replace = true })[3].enemy, "Player")
		local other = export("fight", "text", roster(), { replace = true })
		contains(other, "Gorrak")
	end)

	it("changes nothing in the saved session", function()
		local s = roster()
		local function copy(t)
			if type(t) ~= "table" then return t end
			local out = {}
			for k, v in pairs(t) do out[k] = copy(v) end
			return out
		end
		local before = copy(s)
		export("fight", "text", s, { replace = true })
		export("events", "csv", s, { replace = true })
		deepEq(s, before)
	end)
end)

describe("the comparison (SPEC-06 §4.2, §4.3)", function()
	local METRICS = { "duration_s", "combat_s", "valid_pct", "coverage_pct", "warning_crossings", "danger_crossings",
		"warning_any_s", "danger_any_s", "holder_changes", "taken_by_non_tank", "unstable_intervals", "unstable_s",
		"risk_situations", "risk_per_min", "player_max_pct", "closest_to_tank_pct" }

	local function listed(value)
		local out = {}
		for name in value:gmatch("[^;]+") do out[name] = true end
		return out
	end

	local function three()
		local a = build(known())
		local b = build(known{ state = "interrupted", ended = "reload", started = 1767250000 })
		local c = build(known{ rec = { hz = 2, warning = 90, danger = 99, mode = "values" }, started = 1767260000 })
		return a, b, c
	end

	it("writes a row per fight newest first, every metric in a list of its status or category (EXP-06)", function()
		local a, b, c = three()
		local result = compare()
		local list = records("compare", nil, { result = result })
		eq(#list, 3)
		eq(list[1].session, c.id)
		eq(list[3].session, a.id)
		eq(list[1].enemy, "Gorrak")
		eq(list[1].group, "party")
		eq(list[1].difficulty, "1")
		eq(list[1].player_role, "DAMAGER")
		eq(list[2].state, "interrupted")
		eq(list[3].outcome, "mixed")
		eq(list[3].duration_s, "40.0")
		-- other thresholds than the newest: not comparable, never a number
		eq(list[1].warning_crossings, "1")
		eq(list[3].warning_crossings, "")
		eq(list[3].player_max_pct, "96.0")
		eq(list[1].risk_situations, "3")
		eq(list[1].risk_per_min, "4.5")
				local older = list[3]
		for _, r in ipairs(list) do
			local lists = {}
			for _, key in ipairs({ "at_least", "not_available", "insufficient", "not_comparable", "detected",
				"calculated" }) do lists[key] = listed(r[key]) end
			for _, name in ipairs(METRICS) do
				local count = 0
				for _, key in ipairs({ "at_least", "detected", "calculated" }) do
					if lists[key][name] then
						count = count + 1
						truthy(r[name] ~= "", name .. " in " .. key)
					end
				end
				for _, key in ipairs({ "not_available", "insufficient", "not_comparable" }) do
					if lists[key][name] then
						count = count + 1
						eq(r[name], "", name .. " in " .. key)
					end
				end
				eq(count, 1, r.session .. " " .. name)
			end
		end
		truthy(listed(list[2].at_least).duration_s)
		-- the newest sets the basis: the others have other thresholds
		truthy(listed(older.not_comparable).warning_crossings)
		truthy(listed(older.not_comparable).risk_situations)
		truthy(listed(older.calculated).valid_pct)
		truthy(listed(older.detected).duration_s)
		-- with the interrupted fight the newest of its basis, its counts are lower bounds and listed so
		truthy(St().Delete(c.id))
		local again = records("compare", nil, { result = compare() })
		eq(again[1].session, b.id)
		truthy(listed(again[1].at_least).risk_situations)
		truthy(listed(again[1].at_least).holder_changes)
		eq(again[1].risk_situations, "3")
	end)

	it("says a state only fight and a damaged one without a number", function()
		local a = build(known())
		build(known{ rec = { hz = 2, warning = 80, danger = 95, mode = "state" }, started = 1767250000,
			events = { { 0, "C", 0, 0, 0, "1" }, { 0, "M", 0, 0, 0, "s" }, { 0, "T", 1 }, { 0, "A", 1, 2, 0, "1" },
				{ 0, "S", 1, 1, 0, "S", "-" }, { 400, "c" } },
			rows = { { 10, 1, 1, -1, "a" }, { 20, 1, 1, -1, "a" }, { 30, 1, 1, -1, "a" } },
			q = { v = { 0, 0, 0 }, s = { 80, 80, 80 }, x = { 0, 0, 0 } } })
		local result = compare()
		result.rows[2].status = "damaged"
		local list = records("compare", nil, { result = result })
		truthy(listed(list[1].not_available).player_max_pct)
		eq(list[2].state, "damaged")
		eq(list[2].duration_s, "")
		for _, name in ipairs(METRICS) do truthy(listed(list[2].not_available)[name], name) end
		notNil(a)
	end)

	it("writes the text with the filters, the aggregates, a row per fight and the legend", function()
		three()
		local result = compare()
		local text, info = export("compare", "text", nil, { result = result })
		eq(#parts(text), info.parts)
		matches(text, "^```\nThreatwarden · Comparison · Gorrak · ")
		contains(text, "Filters: Same group size: on · Same difficulty: on · Same role: on")
		contains(text, "3 fights · Basis: thresholds 90 / 99")
		contains(text, L().ANALYTICS_M_FIGHT .. " (" .. L().CAT_ESTIMATED .. "): Median ~")
		contains(text, L().ANALYTICS_M_WARNING_CROSS .. ": " .. L().REPORT_INSUFFICIENT)
		contains(text, "1 of 3 fights")
		matches(text, "\nDate%s+Length%s+Readable%s+Crossings W/D")
		contains(text, L().ANALYTICS_NOT_COMPARABLE)
		contains(text, "Not comparable: thresholds 80 / 95 and 90 / 99")
		contains(text, L().ANALYTICS_LOWER_INTERRUPTED)
		contains(text, "0:40 D")
		contains(text, "at least")
		falsy(text:find("~at least", 1, true))
		contains(text, L().EXPORT_LEGEND)
	end)

	it("needs a comparison with fights", function()
		local text, why = export("compare", "csv", nil, {})
		isNil(text)
		eq(why, "empty")
		eq(select(2, export("compare", "csv", nil, { result = { rows = {} } })), "empty")
	end)
end)

describe("the limit (EXP-07)", function()
	it("keeps whole rows and counts the rows left out outside the text", function()
		local s = build(known())
		local full = export("readings", "csv", s)
		E().MAX_TEXT = 300
		local text, info = export("readings", "csv", s)
		truthy(#text <= 300)
		truthy(info.left > 0)
		eq(info.rows + info.left, s.n)
		eq(full:sub(1, #text), text)
		eq(full:sub(#text + 1, #text + 1), "\n", "cut at the end of a row")
		eq(#CSV.parse(text), info.rows + 1)
		falsy(text:find("left out", 1, true))
		local events, einfo = export("events", "csv", s)
		truthy(#events <= 300)
		eq(einfo.rows + einfo.left, s.ne)
		local fight, finfo = export("fight", "csv", s)
		truthy(#fight <= 300)
		eq(finfo.rows + finfo.left, 25 + 27)
		eq(#CSV.parse(fight), finfo.rows + 1)
		compare()
		E().MAX_TEXT = 600
		local c, cinfo = export("compare", "csv", nil, { result = C().Current() })
		truthy(#c <= 600)
		eq(cinfo.rows + cinfo.left, 1)
	end)

	it("keeps whole parts of the text", function()
		local s = build(known())
		E().PART_MAX = 600
		local text, info = export("fight", "text", s)
		truthy(info.parts > 1)
		E().MAX_TEXT = #parts(text)[1] + 100
		local cut, cinfo = export("fight", "text", s)
		eq(cinfo.parts, 1)
		truthy(cinfo.left > 0)
		eq(cinfo.rows + cinfo.left, info.rows)
		truthy(#cut <= E().MAX_TEXT)
		matches(cut, "^```\n.*\n```$")
	end)
end)

describe("what leaves (EXP-01, ADR 0001)", function()
	it("has no GUID, no setting and no line of /atw debug, and writes, posts and sends nothing", function()
		local s = build(known())
		compare()
		local saved = Mock.ns.Config and AzerothThreatwardenDB.sessions
		local count = #saved
		local sent = 0
		for _, kind in ipairs({ "fight", "events", "readings", "compare" }) do
			for _, format in ipairs({ "csv", "text" }) do
				local text = export(kind, format, s, { result = C().Current() })
				if text then
					sent = sent + 1
					falsy(text:find("Player%-%d"), kind)
					falsy(text:find("Creature%-"), kind)
					falsy(text:find("switches:", 1, true), kind)
					falsy(text:find("maxKB", 1, true), kind)
				end
			end
		end
		eq(sent, 6)
		eq(#saved, count)
		eq(#Mock.output, 0)
		eq(#Mock.errors, 0)
	end)

	it("answers for what it cannot export", function()
		eq(select(2, export("fight", "csv", { id = "nowhere" })), "unknown")
		eq(select(2, export("other", "csv", nil)), "kind")
		local s = build(known())
		eq(select(2, export("fight", "xml", s)), "format")
		local open = S().New{ id = "open-1", started = 1767225600 }
		St().Add(open)
		eq(select(2, export("readings", "csv", open)), "recording")
	end)
end)

describe("the build in slices (SPEC-06 §4.6)", function()
	it("gives the same text in several frames as in one", function()
		local s = build(known())
		local one = export("readings", "csv", s)
		local events = export("events", "csv", s)
		E().SLICE = 2
		local done
		E().Build({ kind = "readings", format = "csv", id = s.id }, function(t) done = t end)
		truthy(E().Building())
		isNil(done)
		for _ = 1, 200 do Mock.Advance(0.05) end
		eq(done, one)
		falsy(E().Building())
		eq(export("events", "csv", s), events)
	end)

	it("drops the build that a newer one or Cancel replaces, and one whose recording went", function()
		local s = build(known())
		E().SLICE = 2
		local first, second = 0, 0
		E().Build({ kind = "readings", format = "csv", id = s.id }, function() first = first + 1 end)
		E().Build({ kind = "events", format = "csv", id = s.id }, function() second = second + 1 end)
		for _ = 1, 200 do Mock.Advance(0.05) end
		deepEq({ first, second }, { 0, 1 })
		E().Build({ kind = "readings", format = "csv", id = s.id }, function() first = first + 1 end)
		truthy(E().Cancel())
		falsy(E().Cancel())
		for _ = 1, 200 do Mock.Advance(0.05) end
		eq(first, 0)
		local why
		E().Build({ kind = "readings", format = "csv", id = s.id }, function(_, w) why = w end)
		truthy(St().Delete(s.id))
		for _ = 1, 200 do Mock.Advance(0.05) end
		eq(why, "unknown")
	end)

	it("tells /atw debug what the last export was, never a name", function()
		local s = build(known())
		local lines = table.concat(Mock.ns.Metrics.DebugLines(), "\n")
		contains(lines, "export last: none")
		export("fight", "csv", s, { replace = true })
		lines = table.concat(Mock.ns.Metrics.DebugLines(), "\n")
		contains(lines, "export last: fight csv, ")
		contains(lines, " bytes, 0 rows left out, names replaced yes")
		contains(lines, "compare queue: idle")
		for _, name in ipairs({ "Testchar", "Gorrak", "Deadmines", "Bram" }) do falsy(lines:find(name, 1, true), name) end
	end)
end)

describe("the switches off (ADR 0014)", function()
	it("builds nothing", function()
		for _, off in ipairs({ { export = false }, { analytics = false }, { reports = false } }) do
			boot(function(M) M.features = features(off) end)
			local why
			E().Build({ kind = "fight", format = "csv", id = "x" }, function(_, w) why = w end)
			eq(why, "off")
		end
	end)
end)
