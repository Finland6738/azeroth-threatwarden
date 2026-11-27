-- Export: the recorded fights as CSV or as text to paste elsewhere (SPEC-06 §4; EXP-01-EXP-07, ANA-04; ADR 0001, 0003,
-- 0018; Q15, Q24). Lua 5.1, no game API (the next frame and the date through Core/Compat.lua), nothing saved, nothing
-- sent, posted or written: it makes a string that UI/ExportBox.lua shows, selected, for the player to copy. Behind the
-- `export` switch, with `analytics` and `reports` (ADR 0014).
-- Adapted from Azeroth Accord (Data/Export.lua), same owner, GPL-3.0 (ADR 0012): the CSV escape and the formula guard,
-- the "||" of the edit box, the code blocks in parts, the limit with whole rows. Changes: Threatwarden's four contents
-- and their columns, the categories and statuses of every value, the replaced names, the build in slices.
--
--   Export.Build(request, done)   request = { kind, format, id (a session) or result (a comparison), replace }
--                                   kind    "fight"    the context, the report and the metrics of one session
--                                           "events"   every event of one session ("csv" only)
--                                           "readings" every row of one session ("csv" only)
--                                           "compare"  the rows (and in text the aggregates) of a comparison
--                                   format  "csv" | "text"
--                                 done(text, info) with info = { kind, format, rows, left, bytes, replaced, parts }, or
--                                 done(nil, "off" / "kind" / "format" / "unknown" / "recording" / "damaged" / "empty" /
--                                 "error"). Events and readings are built in slices of SLICE records per frame; a new
--                                 Build (or Export.Cancel) drops the one running.
--   Export.Display(text)          the text as the edit box takes it: "|" doubled (EXP-04)
--   Export.Names(replace, words)  who is who in an export, with the names replaced (§4.5)
--
-- The CSV is English with a fixed header; the text is in the language of the interface.
local ADDON_NAME, ns = ...
ns = ns or {}
ns.modules = ns.modules or {}

local Export = {}
ns.Export, ns.modules.Export = Export, Export

local Session, Storage, Compat, Report, Metrics, Compare =
	ns.Session, ns.Storage, ns.Compat, ns.Report, ns.Metrics, ns.Compare
local type, pairs, ipairs, tostring, pcall, floor, max = type, pairs, ipairs, tostring, pcall, math.floor, math.max
local concat = table.concat

-- Q24 and Q15, each answer in one place.
Export.KINDS = { "fight", "events", "readings", "compare" }
Export.FORMATS = { "csv", "text" }
Export.CSV_ONLY = { events = true, readings = true }   -- too long to read as text
Export.MAX_TEXT = 262144          -- 256 KB: over it, whole rows (and whole parts) only (EXP-07)
Export.PART_MAX = 1900            -- characters of one part of the text (a chat message takes 2000)
Export.SLICE = 2000               -- events or rows per frame
Export.NAME_CUT = 18              -- characters of a name in the table of the text
Export.ANONYMOUS_DEFAULT = false  -- the names stay unless the player asks to replace them (Q15)

-- The CSV columns, fixed and not translated: a program reads them (§4.3). `detected` and `calculated` list, like
-- `at_least` (the estimates), the metrics of a comparison with that category (EXP-06).
Export.CSV = {
	fight = { "session", "started_utc", "zone", "enemy", "unit", "role", "class", "metric", "value", "category",
		"status", "reason", "at_least", "basis" },
	compare = { "session", "started_utc", "enemy", "group", "difficulty", "player_role", "state", "outcome",
		"duration_s", "combat_s", "valid_pct", "coverage_pct", "warning_crossings", "danger_crossings", "warning_any_s",
		"danger_any_s", "holder_changes", "taken_by_non_tank", "unstable_intervals", "unstable_s", "risk_situations",
		"risk_per_min", "player_max_pct", "closest_to_tank_pct", "at_least", "not_available", "insufficient",
		"not_comparable", "detected", "calculated" },
	events = { "t_s", "event", "enemy", "unit", "other_unit", "detail", "category" },
	readings = { "t_s", "enemy", "unit", "percent", "reading", "situation", "reason", "category", "at_least" },
}

-- The words of the replaced names in the CSV, which stays in English.
local CSV_WORDS = { you = "You", ownPet = "Your pet", pet = "Pet %d", player = "Player %d", unknown = "unknown" }

local EVENT_NAME = { C = "combat_start", c = "combat_end", T = "target", S = "state", A = "holder", M = "mode",
	D = "death", L = "alert", H = "coach_tip", N = "encounter", G = "recording_paused", X = "interrupted", Z = "limit" }
local STATE_NAME = { S = "safe", W = "warning", D = "danger", U = "unknown", ["-"] = "none" }
local MODE_NAME = { v = "values", s = "state", n = "none" }
local TARGET_WHY = { n = "none", d = "dead", l = "lost" }
local DEATH_SOURCE = { g = "unit_died", p = "player_dead", t = "target" }
local LIMIT_NAME = { r = "rows", u = "units", m = "mobs", t = "time", e = "events" }
local ROW_REASON = { S = "secret", E = "error", M = "missing", U = "no-unit", X = "other", T = "stale" }
local STATE_ONLY = { a = 0, b = 1, c = 2, d = 3 }
local ROLES = { TANK = true, HEALER = true, DAMAGER = true }

local function invert(t)
	local out = {}
	for name, code in pairs(t) do out[code] = name end
	return out
end
local REASON_NAME = invert(Session.REASON_CODE)
REASON_NAME.X = "other"
local CATEGORY_NAME = invert(Session.CATEGORY_CODE)
local CONFIDENCE_NAME = invert(Session.CONFIDENCE_CODE)
local ALERT_NAME = invert(Session.ALERT_CODE)
local RULE_NAME = invert(Session.RULE_CODE)

local function on()
	local F = ns.Features
	return F ~= nil and F.On("export") and F.On("analytics") and F.On("reports")
end
Export.On = on

local function noop() end

---------------------------------------------------------------------------------------------------------------------
-- Names (§4.5, EXP-05)
---------------------------------------------------------------------------------------------------------------------
local Names = {}
Names.__index = Names

-- `words`: { you, ownPet, pet (%d), player (%d), unknown }; the CSV's when not given.
function Export.Names(replace, words)
	return setmetatable({ replace = replace == true, words = words or CSV_WORDS, map = {}, players = 0, pets = 0 }, Names)
end

local function named(entry)
	return type(entry.name) == "string" and entry.name ~= "" and entry.name or nil
end

-- The word of unit `index` of session `s`: its name (its token when the name is unknown), or its replacement. The same
-- name keeps the same replacement in the whole export, across sessions too; a nameless unit has one per session.
function Names:Unit(s, index)
	local entry = s.units[index]
	if not entry then return self.words.unknown end
	local name = named(entry)
	if not self.replace then return name or entry.token or self.words.unknown end
	local key = name or ("\001" .. tostring(s.id) .. "#" .. index)
	if entry.me then
		self.map[key] = self.words.you
		return self.words.you
	end
	local known = self.map[key]
	if known then return known end
	local token = type(entry.token) == "string" and entry.token or ""
	local out
	if entry.pet or token == "pet" then
		out = self.words.ownPet
	elseif token:find("^partypet%d+$") or token:find("^raidpet%d+$") then
		self.pets = self.pets + 1
		out = self.words.pet:format(self.pets)
	else
		self.players = self.players + 1
		out = self.words.player:format(self.players)
	end
	self.map[key] = out
	return out
end

-- The name of enemy `index`, nil when unknown. An enemy that bears the name of a unit of the session (a member turned
-- against the group) is replaced like that unit.
function Names:Mob(s, index)
	local entry = s.mobs[index or 0]
	if not entry then return nil end
	local name = named(entry)
	if not (name and self.replace) then return name end
	for i, unit in ipairs(s.units) do
		if unit.name == name then return self:Unit(s, i) end
	end
	return name
end

---------------------------------------------------------------------------------------------------------------------
-- CSV (§4.3, EXP-02, EXP-03)
---------------------------------------------------------------------------------------------------------------------
-- One value as it stands in the file: a number as it is; a text that a spreadsheet would read as a formula with an
-- apostrophe in front (EXP-03), then quoted when it needs to be (EXP-02).
function Export.CSVValue(v)
	if type(v) == "number" then return tostring(v) end
	v = tostring(v == nil and "" or v)
	if v:find("^%-?%d+%.?%d*$") then return v end
	if v:find("^[=+%-@\t\r]") then v = "'" .. v end
	if v:find('[,"\r\n]') or v:find("^[ \t]") or v:find("[ \t]$") then v = '"' .. v:gsub('"', '""') .. '"' end
	return v
end

-- A CSV being written: whole rows while they fit in MAX_TEXT.
local function csvWriter(kind)
	local columns = Export.CSV[kind]
	local head = concat(columns, ",")
	local w = { lines = { head }, size = #head, rows = 0, full = false }
	function w:Add(record)
		if self.full then return false end
		local cells = {}
		for i, column in ipairs(columns) do cells[i] = Export.CSVValue(record[column]) end
		local line = concat(cells, ",")
		if self.size + 1 + #line > Export.MAX_TEXT then
			self.full = true
			return false
		end
		self.lines[#self.lines + 1] = line
		self.size = self.size + 1 + #line
		self.rows = self.rows + 1
		return true
	end
	function w:Text() return concat(self.lines, "\n") end
	return w
end

local function decimal(v) return v and ("%.1f"):format(v) or nil end
local function seconds(tenths) return tenths and ("%.1f"):format(tenths / 10) or nil end
local function whole(v) return v and ("%d"):format(v) or nil end

local function utc(epoch) return Compat.DateText("!%Y-%m-%d %H:%M", epoch) or "" end

---------------------------------------------------------------------------------------------------------------------
-- This fight, CSV: one row per metric, for the session and for every unit
---------------------------------------------------------------------------------------------------------------------
local function fightCSV(s, metrics, names)
	local w = csvWriter("fight")
	local total = 0
	local zone = type(s.zone) == "string" and s.zone or ""
	local enemy = names:Mob(s, metrics.mob) or ""
	local started = utc(s.started)

	-- `c` a cell (nil: no cell), `value` its text when the cell is ok (nil: unknown inside an ok cell)
	local function add(unit, metric, c, value, extra)
		local ok = c.status == "ok"
		local status, category, reason = c.status, c.category, c.reason
		if ok and value == nil then status, category = "unknown", "unknown" end
		if extra and extra.status then status, category, reason = extra.status, "unknown", extra.reason end
		total = total + 1
		w:Add({ session = s.id, started_utc = started, zone = zone, enemy = enemy, unit = unit and unit.name or "",
			role = unit and unit.role or "", class = unit and unit.class or "", metric = metric,
			value = status == "ok" and value or "", category = status == "ok" and category or "unknown", status = status,
			reason = reason or "", at_least = (status == "ok" and c.lower) and "yes" or "",
			basis = c.basis or "" })
	end

	local cells = metrics.cells
	local context = cells.context
	local function part(c, fn)
		if c.status ~= "ok" then return nil end
		return fn(c.value)
	end
	add(nil, "duration_s", context, seconds(context.value.dur))
	add(nil, "combat_s", context, seconds(context.value.fight))
	add(nil, "pulls", context, whole(context.value.pulls))
	local rec = metrics.rec or {}
	local settings = { status = "ok", category = "detected" }
	add(nil, "warning_threshold", settings, whole(rec.warning))
	add(nil, "danger_threshold", settings, whole(rec.danger))
	local valid = cells.valid
	local bases = metrics.valid or {}
	add(nil, "valid_values_pct", valid, part(valid, function() return decimal(bases.values) end))
	add(nil, "valid_state_pct", valid, part(valid, function() return decimal(bases.state) end))
	add(nil, "unknown_pct", valid, part(valid, function(v) return decimal(v.unknown) end))
	local coverage = { status = "ok", category = "calculated" }
	add(nil, "coverage_pct", coverage, decimal(metrics.coverage),
		not metrics.coverage and { status = "na" } or nil)

	local crossings = cells.crossings
	add(nil, "warning_crossings", crossings, part(crossings, function(v) return whole(v.warning) end))
	add(nil, "danger_crossings", crossings, part(crossings, function(v) return whole(v.danger) end))
	local stateTime = cells.stateTime
	add(nil, "warning_any_s", stateTime, part(stateTime, function(v) return seconds(v.warningAny) end))
	add(nil, "danger_any_s", stateTime, part(stateTime, function(v) return seconds(v.dangerAny) end))
	local closest = cells.maxNotHolding
	add(nil, "closest_to_tank_pct", closest, part(closest, function(v) return decimal(v.pct) end))
	local holders = cells.holders
	add(nil, "holder_changes", holders, part(holders, function(v) return whole(v.total) end))
	add(nil, "tank_to_tank", holders, part(holders, function(v) return whole(v.tankToTank) end))
	add(nil, "to_non_tank", holders, part(holders, function(v) return whole(v.toOther) end))
	add(nil, "back_to_tank", holders, part(holders, function(v) return whole(v.backToTank) end))
	local taken = cells.aggroTaken
	add(nil, "taken_by_non_tank", taken, part(taken, whole))
	local unstable = cells.unstable
	add(nil, "unstable_intervals", unstable, part(unstable, function(v) return whole(v.count) end))
	add(nil, "unstable_s", unstable, part(unstable, function(v) return seconds(v.total) end))
	local risk = cells.risk
	add(nil, "risk_situations", risk, part(risk, function(v) return whole(v.situations) end))
	add(nil, "risk_per_min", risk, part(risk, function(v) return decimal(v.perMinute) end))
	add(nil, "deaths", cells.deaths, part(cells.deaths, function(v) return whole(#v) end))
	add(nil, "alerts", cells.alerts, part(cells.alerts, function(v) return whole(v.count) end))

	local q = type(s.q) == "table" and s.q or {}
	local function tick(list, i)
		local v = type(list) == "table" and list[i]
		if type(v) == "number" and v >= 0 then return v end
		return 0
	end
	for _, u in ipairs(metrics.units) do
		local who = { name = names:Unit(s, u.index), role = ROLES[u.role or ""] and u.role or "", class = u.class or "" }
		local c = u.cells
		add(who, "warning_crossings", c.warningCross, part(c.warningCross, whole))
		add(who, "danger_crossings", c.dangerCross, part(c.dangerCross, whole))
		add(who, "warning_time_s", c.warningTime, part(c.warningTime, seconds))
		add(who, "danger_time_s", c.dangerTime, part(c.dangerTime, seconds))
		add(who, "max_pct", c.maxPct, part(c.maxPct, function(v) return decimal(v.pct) end))
		add(who, "taken_by_non_tank", c.aggro, part(c.aggro, whole))
		local quality = c.quality
		local qv, qs, qx = tick(q.v, u.index), tick(q.s, u.index), tick(q.x, u.index)
		local sum = qv + qs + qx
		add(who, "valid_values_pct", quality, part(quality, function(v) return decimal(v.values) end))
		add(who, "valid_state_pct", quality, part(quality, function()
			return sum > 0 and decimal(floor((qv + qs) * 100 / sum + 0.5)) or nil
		end))
		add(who, "unknown_pct", quality, part(quality, function(v) return decimal(v.unknown) end))
	end
	return w:Text(), { rows = w.rows, left = total - w.rows }
end

---------------------------------------------------------------------------------------------------------------------
-- Events and readings, CSV: one row per record, in order of time
---------------------------------------------------------------------------------------------------------------------
-- "key=value;key=value" from a list of { key, value }, without the nil ones.
local function detail(list)
	local out = {}
	for _, pair in ipairs(list) do
		if pair[2] ~= nil then out[#out + 1] = pair[1] .. "=" .. tostring(pair[2]) end
	end
	return concat(out, ";")
end

local function holderKind(e)
	if e.a == "0" then return "to_non_tank" end
	if e.v == 0 then return "first" end
	if e.a == "1" and e.b == "1" then return "tank_to_tank" end
	if e.a == "1" and e.b == "0" then return "back_to_tank" end
	return "other"
end

local function eventsCSV(s, d, names, step)
	local w = csvWriter("events")
	local rec = type(s.rec) == "table" and s.rec or {}
	local mode = rec.mode == "values" and "v" or rec.mode == "state" and "s" or rec.mode == "none" and "n" or nil
	local pull = 0
	for i = 1, d.ne do
		local e = d.events[i]
		local k = e.k
		local category = "detected"
		local info = {}
		local unit, other, enemy = e.u, e.v, e.m
		if k == "C" then
			pull = pull + 1
			info = { { "pull", pull }, { "continued", e.a == "r" and "reload" or nil } }
		elseif k == "T" then
			if e.m == 0 then info = { { "reason", TARGET_WHY[e.a] } } end
		elseif k == "S" then
			category = mode == "v" and "calculated" or mode == "s" and "detected" or "unknown"
			info = { { "new", STATE_NAME[e.a] }, { "old", STATE_NAME[e.b] }, { "reason", REASON_NAME[e.c] } }
		elseif k == "A" then
			info = { { "kind", holderKind(e) }, { "first", (e.v == 0 and e.a == "0") and "yes" or nil } }
		elseif k == "M" then
			mode = e.a
			info = { { "mode", MODE_NAME[e.a] }, { "reason", REASON_NAME[e.b] } }
		elseif k == "D" then
			info = { { "source", DEATH_SOURCE[e.a] } }
		elseif k == "L" then
			local cat, confidence = CATEGORY_NAME[e.raw:sub(1, 1)], CONFIDENCE_NAME[e.raw:sub(2, 2)]
			category = cat or "unknown"
			info = { { "kind", ALERT_NAME[e.a] }, { "severity", e.b ~= "-" and e.b or nil },
				{ "muted", e.c == "1" and "yes" or "no" }, { "category", cat }, { "confidence", confidence } }
		elseif k == "H" then
			local cat = CATEGORY_NAME[e.b]
			category = cat or "unknown"
			info = { { "rule", RULE_NAME[e.a] }, { "category", cat }, { "confidence", CONFIDENCE_NAME[e.c] } }
		elseif k == "N" then
			info = { { "phase", e.a == "s" and "start" or e.a == "e" and "end" or nil },
				{ "result", e.a == "e" and (e.b == "1" and "success" or e.b == "0" and "failed") or nil },
				{ "encounter", e.n >= 0 and e.n or nil } }
		elseif k == "G" then
			info = { { "seconds", e.n >= 0 and seconds(e.n) or nil } }
		elseif k == "Z" then
			info = { { "limit", LIMIT_NAME[e.a] } }
		end
		local record = {
			t_s = seconds(e.t), event = EVENT_NAME[k] or k, detail = detail(info), category = category,
			enemy = (enemy > 0 and s.mobs[enemy]) and (names:Mob(s, enemy) or "unknown") or "",
			unit = (unit > 0 and s.units[unit]) and names:Unit(s, unit) or "",
			other_unit = (other > 0 and s.units[other]) and names:Unit(s, other) or "",
		}
		if not w:Add(record) then break end
		step()
	end
	return w:Text(), { rows = w.rows, left = d.ne - w.rows }
end

local function readingsCSV(s, d, names, step)
	local w = csvWriter("readings")
	local NUMBERED = Session.NUMBERED
	for i = 1, d.n do
		local code, u, m = d.s[i], d.u[i], d.m[i]
		local record = { t_s = seconds(d.t[i]),
			enemy = (m > 0 and s.mobs[m]) and (names:Mob(s, m) or "unknown") or "",
			unit = (u > 0 and s.units[u]) and names:Unit(s, u) or "" }
		if NUMBERED[code] then
			local p = d.p[i]
			local cap = p >= Session.MAX_N
			record.percent = p >= 0 and decimal(p / 10) or ""
			record.reading = "value"
			record.situation = code ~= "4" and code or ""
			record.category = cap and "estimated" or "detected"
			record.at_least = cap and "yes" or ""
		elseif STATE_ONLY[code] then
			record.reading, record.situation, record.category = "state_only", STATE_ONLY[code], "detected"
		else
			record.reading, record.reason, record.category = "unknown", ROW_REASON[code] or "other", "unknown"
		end
		if not w:Add(record) then break end
		step()
	end
	return w:Text(), { rows = w.rows, left = d.n - w.rows }
end

---------------------------------------------------------------------------------------------------------------------
-- Comparison, CSV: one row per fight, the most recent first
---------------------------------------------------------------------------------------------------------------------
-- column -> measure of Data/Compare.lua (the value, in its unit)
local COMPARE_COLUMNS = {
	{ "combat_s", "fight", seconds }, { "valid_pct", "valid", decimal },
	{ "warning_crossings", "warningCross", whole }, { "danger_crossings", "dangerCross", whole },
	{ "warning_any_s", "warningAny", seconds }, { "danger_any_s", "dangerAny", seconds },
	{ "holder_changes", "holders", whole }, { "taken_by_non_tank", "aggroTaken", whole },
	{ "unstable_intervals", "unstable", whole }, { "unstable_s", "unstableTime", seconds },
	{ "risk_per_min", "risk", decimal }, { "player_max_pct", "myMaxPct", decimal },
	{ "closest_to_tank_pct", "closest", decimal },
}

local function enemyOf(id)
	local s = Storage.Get(id)
	local index = s and type(s.sum) == "table" and s.sum.mob
	return s, index
end

local function compareRecord(row, names)
	local lists = { at_least = {}, not_available = {}, insufficient = {}, not_comparable = {}, detected = {},
		calculated = {} }
	local function put(list, column) lists[list][#lists[list] + 1] = column end
	local function value(column, v, format, entry)
		if entry.status == "ok" and v ~= nil then
			if entry.lower then put("at_least", column)
			elseif entry.category == "calculated" then put("calculated", column)
			else put("detected", column) end
			return format(v)
		end
		local status = entry.status
		put(status == "insufficient" and "insufficient" or status == "not-comparable" and "not_comparable"
			or "not_available", column)
		return nil
	end

	local s, mob = enemyOf(row.id)
	local ok = row.status == "ok"
	local record = {
		session = row.id, started_utc = utc(row.started), enemy = s and names:Mob(s, mob) or "",
		group = ok and row.group or "", difficulty = ok and row.diff or "",
		player_role = (ok and ROLES[row.role or ""]) and row.role or "",
		state = ok and row.state or row.status, outcome = ok and row.outcome or "",
	}
	record.duration_s = value("duration_s", ok and row.dur or nil, seconds,
		(ok and row.dur) and { status = "ok", lower = row.interrupted, category = "detected" } or { status = "na" })
	for _, c in ipairs(COMPARE_COLUMNS) do
		local entry = Compare.Value(row, Compare.MEASURE[c[2]])
		record[c[1]] = value(c[1], entry.value, c[3], entry)
	end
	record.coverage_pct = value("coverage_pct", ok and row.coverage or nil, decimal,
		(ok and row.coverage) and { status = "ok", category = "calculated" } or { status = "na" })
	-- the situations are a count: a lower bound of an interrupted fight, unlike the rate
	local risk = Compare.Value(row, Compare.MEASURE.risk)
	local situations = risk.status == "ok" and {
		status = "ok", category = "calculated", lower = risk.cellLower or row.interrupted } or risk
	record.risk_situations = value("risk_situations", risk.situations, whole, situations)
	for name, list in pairs(lists) do record[name] = concat(list, ";") end
	return record
end

local function compareCSV(result, names)
	local w = csvWriter("compare")
	for _, row in ipairs(result.rows) do
		if not w:Add(compareRecord(row, names)) then break end
	end
	return w:Text(), { rows = w.rows, left = #result.rows - w.rows }
end

---------------------------------------------------------------------------------------------------------------------
-- Text (§4.4): lines in code blocks, in parts of at most PART_MAX characters
---------------------------------------------------------------------------------------------------------------------
-- The number of characters of a UTF-8 text.
function Export.Length(text)
	local _, n = text:gsub("[^\128-\191]", "")
	return n
end

-- A value inside the code block: one line, no backtick (it would close the block), cut to `limit` characters with "…".
function Export.TextValue(v, limit)
	v = tostring(v == nil and "" or v):gsub("[\r\n\t]", " "):gsub("%c", ""):gsub("`", "'")
	if limit and Export.Length(v) > limit then
		local count = 0
		for i = 1, #v do
			local b = v:byte(i)
			if b < 128 or b >= 192 then
				count = count + 1
				if count == limit then return v:sub(1, i - 1) .. "…" end
			end
		end
	end
	return v
end
local clean = Export.TextValue

-- The lines of a text export: { text, head = the header of the table it belongs to, repeated at the top of a new part }.
local function document()
	local doc = { lines = {} }
	function doc:Add(text, head) self.lines[#self.lines + 1] = { text = clean(text), head = head } end
	-- a value of several lines under "label (category): "
	function doc:Value(label, text)
		local first = true
		for line in (tostring(text) .. "\n"):gmatch("([^\n]*)\n") do
			self:Add(first and (label .. ": " .. line) or ("  " .. line))
			first = false
		end
	end
	-- `rows` of cells aligned with spaces under `header`; the header is repeated in the parts the table crosses
	function doc:Table(header, rows)
		local widths = {}
		local function measure(cells)
			for i, c in ipairs(cells) do
				cells[i] = clean(c)
				widths[i] = max(widths[i] or 0, Export.Length(cells[i]))
			end
		end
		measure(header)
		for _, cells in ipairs(rows) do measure(cells) end
		local function line(cells)
			local out = {}
			for i = 1, #header do
				local c = cells[i] or ""
				out[i] = i < #header and (c .. (" "):rep(widths[i] - Export.Length(c))) or c
			end
			return (concat(out, "  "):gsub(" +$", ""))
		end
		local head = line(header)
		self:Add(head)
		for _, cells in ipairs(rows) do self:Add(line(cells), head) end
	end
	return doc
end

-- A line longer than a part can hold, cut at spaces into several.
local function wrap(text, room)
	if Export.Length(text) <= room then return { text } end
	local out, current = {}, nil
	for word in text:gmatch("%S+") do
		word = clean(word, room)
		if not current then current = word
		elseif Export.Length(current) + 1 + Export.Length(word) > room then
			out[#out + 1] = current
			current = word
		else current = current .. " " .. word end
	end
	out[#out + 1] = current or ""
	return out
end

-- The parts: every one a complete code block with the title (and "(1/3)" when there are several), no line split, a
-- blank line between them; over MAX_TEXT the last parts are left out whole.
local function render(title, lines)
	title = clean(title, 200)
	-- what every part holds besides its lines, with room for " (999/999)"
	local frame = Export.Length(title) + 10 + Export.Length("```\n\n```")
	local room = Export.PART_MAX - frame
	local parts, current, chars = {}, nil, 0
	local function start()
		current, chars = { count = 0 }, frame
		parts[#parts + 1] = current
	end
	for _, line in ipairs(lines) do
		for _, text in ipairs(wrap(line.text, room - 1)) do
			local length = Export.Length(text) + 1
			if not current or (current.count > 0 and chars + length > Export.PART_MAX) then
				start()
				local head = line.head
				if head and Export.Length(head) + 1 + length <= room then
					current[#current + 1] = head
					chars = chars + Export.Length(head) + 1
				end
			end
			current[#current + 1] = text
			current.count = current.count + 1
			chars = chars + length
		end
	end
	if #parts == 0 then start() end
	local function block(i, total)
		local out = { "```", total > 1 and ("%s (%d/%d)"):format(title, i, total) or title }
		for _, text in ipairs(parts[i]) do out[#out + 1] = text end
		out[#out + 1] = "```"
		return concat(out, "\n")
	end
	local kept, bytes = #parts, 0
	for i = 1, #parts do
		bytes = bytes + #block(i, #parts) + (i > 1 and 2 or 0)
		if bytes > Export.MAX_TEXT then kept = i - 1 break end
	end
	local out, rows, left = {}, 0, 0
	for i, part in ipairs(parts) do
		if i <= kept then
			out[#out + 1] = block(i, kept)
			rows = rows + part.count
		else
			left = left + part.count
		end
	end
	return concat(out, "\n\n"), { rows = rows, left = left, parts = kept }
end

local CATEGORY_WORD = { detected = "CAT_DETECTED", calculated = "CAT_CALCULATED", estimated = "CAT_ESTIMATED" }
local MARK = { detected = "ANALYTICS_MARK_DETECTED", calculated = "ANALYTICS_MARK_CALCULATED" }
local STATUS_WORD = { na = "REPORT_NA", insufficient = "REPORT_INSUFFICIENT", unknown = "REPORT_UNKNOWN",
	["not-comparable"] = "ANALYTICS_NOT_COMPARABLE" }

local function localWords()
	local L = ns.L
	return { you = L.UNIT_YOU, ownPet = L.EXPORT_YOUR_PET, pet = L.EXPORT_PET_N, player = L.EXPORT_PLAYER_N,
		unknown = L.REPORT_UNKNOWN }
end

local function dateText(started)
	-- the locale writes the strftime fields as {Y}, {m}...: a % there would be a placeholder (ADR 0009)
	local pattern = ns.L.REPORTS_DATE_FORMAT:gsub("{(%a)}", "%%%1")
	return Compat.DateText(pattern, started) or ns.L.REPORTS_DATE_UNKNOWN
end

-- "label (category)", and the value; the status word and the reason when not ok.
local function line(doc, label, c, text, reason)
	if c.status == "ok" then
		local category = CATEGORY_WORD[c.category]
		if category then label = ns.L.TIP_TAGGED:format(label, ns.L[category]) end
		-- "~" for an estimate that does not already say "at least"
		if c.category == "estimated" and not c.lower then text = ns.L.ANALYTICS_APPROX:format(text) end
	elseif reason then
		text = text .. " · " .. reason
	end
	doc:Value(label, text)
end

-- A cell of a table: "3 C", "at least 3", "~2.5", "Not available".
local function tableCell(status, category, text, lower)
	local L = ns.L
	if status ~= "ok" then return L[STATUS_WORD[status] or "REPORT_UNKNOWN"] end
	if category == "estimated" then return lower and text or L.ANALYTICS_APPROX:format(text) end
	local mark = MARK[category]
	return mark and (text .. " " .. L[mark]) or text
end

local function legend(doc)
	doc:Add(ns.L.EXPORT_LEGEND_MARKS)
	doc:Add(ns.L.EXPORT_LEGEND)
end

---------------------------------------------------------------------------------------------------------------------
-- This fight, text
---------------------------------------------------------------------------------------------------------------------
-- A copy of the report or of the metrics whose unit and enemy names are the export's, asked as they are written, so
-- that the replaced names are numbered in the order they appear.
local function renamed(source, s, names)
	local out = {}
	for k, v in pairs(source) do out[k] = v end
	out.units, out.mobs = {}, {}
	for i, u in ipairs(source.units) do
		local unit = {}
		for k, v in pairs(u) do
			if k ~= "name" then unit[k] = v end
		end
		out.units[i] = setmetatable(unit, { __index = function(t, k)
			if k ~= "name" then return nil end
			local name = names:Unit(s, t.index)
			rawset(t, "name", name)
			return name
		end })
	end
	for i, m in ipairs(source.mobs) do
		out.mobs[i] = setmetatable({ index = i, class = m.class }, { __index = function(t, k)
			if k ~= "name" then return nil end
			return names:Mob(s, t.index)
		end })
	end
	return out
end

local ANALYTICS_ROWS = { "valid", "crossings", "stateTime", "holders", "aggroTaken", "unstable", "risk",
	"maxNotHolding" }
local WITH_BASIS = { crossings = true, stateTime = true, unstable = true, risk = true }

local UNIT_COLUMNS = {
	{ "EXPORT_COL_WARNING", "warningCross" }, { "EXPORT_COL_DANGER", "dangerCross" },
	{ "EXPORT_COL_WARNING_TIME", "warningTime" }, { "EXPORT_COL_DANGER_TIME", "dangerTime" },
	{ "EXPORT_COL_MAX", "maxPct" }, { "EXPORT_COL_TAKEN", "aggro" }, { "EXPORT_COL_READABLE", "quality" },
}

local function unitValue(key, c)
	local L, v = ns.L, c.value
	local text
	if key == "warningTime" or key == "dangerTime" then text = Report.Seconds(v)
	elseif key == "maxPct" then text = L.TIMELINE_PERCENT:format(v.pct)
	elseif key == "quality" then text = L.ANALYTICS_PCT_WHOLE:format(v.values + v.state)
	else text = ("%d"):format(v) end
	if c.lower then text = L.REPORT_AT_LEAST:format(text) end
	return text
end

local function fightText(s, report, metrics, names)
	local L = ns.L
	local r, m = renamed(report, s, names), renamed(metrics, s, names)
	local doc = document()
	for _, headline in ipairs(Report.Headlines(report)) do doc:Add(headline) end
	for _, key in ipairs(Report.SESSION_ROWS) do
		local c = report.rows[key]
		if c then line(doc, L[Report.METRIC_KEYS[key]], c, Report.CellText(r, c), Report.ReasonText(c.reason)) end
	end

	doc:Add(L.ANALYTICS_PAGE)
	local nothing = metrics.outcome == "none"
	for _, key in ipairs(ANALYTICS_ROWS) do
		if key == "valid" or not nothing then
			local c = metrics.cells[key]
			local text = Metrics.Text(m, c)
			if c.status == "ok" and WITH_BASIS[key] then
				local basis = Report.BasisText(m, c.basis)
				if basis then text = text .. "\n" .. basis end
			end
			line(doc, L[Metrics.METRIC_KEYS[key]], c, text, Metrics.ReasonText(c))
			if key == "unstable" and c.status == "ok" then
				for _, iv in ipairs(c.value.list) do doc:Add("  " .. Metrics.IntervalText(iv)) end
				local rest = c.value.count - #c.value.list
				if rest > 0 then
					doc:Add("  " .. (rest == 1 and L.ANALYTICS_MORE_ONE or L.ANALYTICS_MORE:format(rest)))
				end
			end
		end
	end
	if nothing then doc:Add(L.ANALYTICS_CARD_NOTHING) end

	if #metrics.units > 0 then
		local header = { L.EXPORT_COL_UNIT }
		for i, column in ipairs(UNIT_COLUMNS) do header[i + 1] = L[column[1]] end
		local rows, reasons = {}, {}
		for i, u in ipairs(m.units) do
			local name = clean(u.name, Export.NAME_CUT)
			local cells = { name }
			local seen = {}
			for n, column in ipairs(UNIT_COLUMNS) do
				local c = u.cells[column[2]]
				cells[n + 1] = tableCell(c.status, c.category, c.status == "ok" and unitValue(column[2], c), c.lower)
				if c.status ~= "ok" then
					local why = Metrics.ReasonText(c)
					if why and not seen[why] then
						seen[why] = true
						reasons[#reasons + 1] = name .. ": " .. why
					end
				end
			end
			rows[i] = cells
		end
		doc:Table(header, rows)
		for _, why in ipairs(reasons) do doc:Add(why) end
	end
	legend(doc)

	local title = L.EXPORT_TITLE_TEXT:format(names:Mob(s, metrics.mob) or L.MON_UNKNOWN_MOB, dateText(s.started),
		(type(s.zone) == "string" and s.zone ~= "") and s.zone or L.REPORTS_ZONE_UNKNOWN)
	return render(title, doc.lines)
end

---------------------------------------------------------------------------------------------------------------------
-- Comparison, text
---------------------------------------------------------------------------------------------------------------------
local TEXT_COLUMNS = {
	{ "ANALYTICS_COL_LENGTH", { "fight" } }, { "ANALYTICS_COL_READABLE", { "valid" } },
	{ "ANALYTICS_COL_CROSSINGS", { "warningCross", "dangerCross" } }, { "ANALYTICS_COL_DANGER", { "dangerAny" } },
	{ "ANALYTICS_COL_HOLDERS", { "holders" } }, { "ANALYTICS_COL_UNSTABLE", { "unstable" } },
	{ "ANALYTICS_COL_RISK", { "risk" } }, { "ANALYTICS_COL_HIGHEST", { "myMaxPct" } },
	{ "ANALYTICS_COL_CLOSEST", { "closest" } },
}

local function aggregateLine(doc, agg)
	local L = ns.L
	local ms = Compare.MEASURE[agg.id]
	local label = L[Compare.MEASURE_KEYS[agg.id]]
	if agg.status ~= "ok" then
		doc:Value(label, concat({ L.REPORT_INSUFFICIENT, Compare.AggregateText(agg), Compare.CountText(agg) }, " · "))
		return
	end
	local parts = {}
	for _, which in ipairs({ "median", "total", "min", "max", "rate" }) do
		local present = which == "median" or which == "min" or which == "max" or (which == "total" and agg.total ~= nil)
			or (which == "rate" and ms.kind == "rate" and agg.rate ~= nil)
		if present then
			local text = which == "rate" and Compare.NumberText(ms, agg.rate, agg.lower)
				or Compare.AggregateText(agg, which)
			parts[#parts + 1] = L.ANALYTICS_AGG_PART:format(L[Compare.AGGREGATE_KEYS[which]], text)
		end
	end
	parts[#parts + 1] = Compare.CountText(agg)
	doc:Value(L.TIP_TAGGED:format(label, L[CATEGORY_WORD[agg.category]]), concat(parts, " · "))
end

local function compareText(result, names)
	local L = ns.L
	local doc = document()
	local filters = {}
	for _, name in ipairs({ "group", "diff", "role" }) do
		filters[#filters + 1] = L.REPORTS_TIP_LINE:format(L[Compare.FILTER_KEYS[name]],
			result.filters[name] and L.EXPORT_ON or L.EXPORT_OFF)
	end
	doc:Add(L.EXPORT_FILTERS:format(concat(filters, " · ")))
	local counted = result.counted == 1 and L.ANALYTICS_FIGHTS_ONE or L.ANALYTICS_FIGHTS:format(result.counted)
	if result.basis then counted = counted .. " · " .. L.ANALYTICS_TIP_BASIS:format(Compare.BasisText(result.basis)) end
	doc:Add(counted)
	for _, note in ipairs(Compare.NoteLines(result)) do doc:Add(note) end

	doc:Add(L.ANALYTICS_ALL_FIGHTS)
	for _, ms in ipairs(Compare.MEASURES) do aggregateLine(doc, result.aggregates[ms.id]) end

	local header = { L.ANALYTICS_COL_DATE }
	for i, column in ipairs(TEXT_COLUMNS) do header[i + 1] = L[column[1]] end
	local rows, notes, seen = {}, {}, {}
	local function note(text)
		if not seen[text] then
			seen[text] = true
			notes[#notes + 1] = text
		end
	end
	for _, row in ipairs(result.rows) do
		local day = dateText(row.started)
		local cells = { day }
		if row.status ~= "ok" then
			cells[2] = L.ANALYTICS_DAMAGED_ROW
		else
			for i, column in ipairs(TEXT_COLUMNS) do
				local shown = {}
				for n, id in ipairs(column[2]) do
					local ms = Compare.MEASURE[id]
					local v = Compare.Value(row, ms)
					shown[n] = tableCell(v.status, v.category, v.status == "ok" and Compare.CellText(ms, v), v.lower)
					if v.status == "not-comparable" then
						note(day .. ": " .. Compare.NotComparableText(v.nc))
					elseif v.status ~= "ok" then
						local why = Metrics.ReasonText({ reason = v.reason, valid = v.valid, coverage = v.coverage })
						if v.reason == "no-player" then why = L.ANALYTICS_WHY_NO_PLAYER end
						if why then note(day .. ": " .. why) end
					end
				end
				cells[i + 1] = concat(shown, " / ")
			end
			for _, text in ipairs(Compare.RowNotes(row)) do note(day .. ": " .. text) end
		end
		rows[#rows + 1] = cells
	end
	doc:Table(header, rows)
	for _, text in ipairs(notes) do doc:Add(text) end
	legend(doc)

	local newest = result.rows[1]
	local s, mob = enemyOf(newest.id)
	local title = L.EXPORT_TITLE_COMPARE:format(s and names:Mob(s, mob) or L.MON_UNKNOWN_MOB,
		dateText(newest.started))
	return render(title, doc.lines)
end

---------------------------------------------------------------------------------------------------------------------
-- Building
---------------------------------------------------------------------------------------------------------------------
Export.stats = { builds = 0 }
local job

function Export.Cancel()
	if not job then return false end
	job = nil
	return true
end

function Export.Building() return job ~= nil end

local function finish(j, text, info)
	if job ~= j then return end
	job = nil
	info.kind, info.format, info.bytes, info.replaced = j.kind, j.format, #text, j.replace
	Export.stats.builds = Export.stats.builds + 1
	Export.stats.last = info
	j.done(text, info)
end

local function fail(j, why, err)
	if job ~= j then return end
	job = nil
	if err then
		local Diag = ns.Diagnostics
		Export.lastError = Diag and Diag.CleanError(err) or tostring(err)
	end
	j.done(nil, why)
end

-- Runs `compose` (a text of a few kilobytes) in this frame.
local function atOnce(j, compose)
	local ok, text, info = pcall(compose)
	if ok then finish(j, text, info) else fail(j, "error", text) end
end

-- Runs `compose(step)` as a coroutine, SLICE records per frame.
local function sliced(j, compose)
	local count = 0
	local co = coroutine.create(function()
		return compose(function()
			count = count + 1
			if count >= Export.SLICE then
				count = 0
				coroutine.yield()
			end
		end)
	end)
	local function resume()
		if job ~= j then return end
		if Storage.Get(j.id) ~= j.session then fail(j, "unknown") return end   -- deleted while building
		local ok, text, info = coroutine.resume(co)
		if not ok then fail(j, "error", text)
		elseif coroutine.status(co) == "dead" then finish(j, text, info)
		elseif not Compat.After(0, resume) then resume() end
	end
	resume()
end

local function isOne(list, value)
	for _, v in ipairs(list) do
		if v == value then return true end
	end
	return false
end

function Export.Build(request, done)
	done = done or noop
	if not on() then done(nil, "off") return end
	local kind, format = request.kind, request.format
	if not isOne(Export.KINDS, kind) then done(nil, "kind") return end
	if not isOne(Export.FORMATS, format) or (Export.CSV_ONLY[kind] and format ~= "csv") then
		done(nil, "format")
		return
	end
	job = nil
	local replace = request.replace
	if replace == nil then replace = Export.ANONYMOUS_DEFAULT end
	local j = { kind = kind, format = format, id = request.id, replace = replace == true, done = done }
	job = j
	local names = Export.Names(j.replace, format == "text" and localWords() or nil)

	if kind == "compare" then
		local result = request.result
		if not (result and result.rows and #result.rows > 0) then fail(j, "empty") return end
		atOnce(j, function()
			if format == "csv" then return compareCSV(result, names) end
			return compareText(result, names)
		end)
		return
	end

	local s = Storage.Get(j.id)
	if not s then fail(j, "unknown") return end
	if s.state == "open" or (ns.Recorder and ns.Recorder.current == s) then fail(j, "recording") return end
	j.session = s

	if kind == "fight" then
		-- the report's cells and the metrics, each built in slices by its module
		Report.Build(j.id, function(report, why)
			if job ~= j then return end
			if not report then fail(j, why) return end
			Metrics.Build(j.id, function(metrics, reason)
				if job ~= j then return end
				if not metrics then fail(j, reason) return end
				atOnce(j, function()
					if format == "csv" then return fightCSV(s, metrics, names) end
					return fightText(s, report, metrics, names)
				end)
			end)
		end)
		return
	end

	local d, why = Storage.Decode(j.id)
	if not d then fail(j, why) return end
	sliced(j, function(step)
		if kind == "events" then return eventsCSV(s, d, names, step) end
		return readingsCSV(s, d, names, step)
	end)
end

-- The text as the edit box takes it: "|" doubled, which the client shows and copies as one (EXP-04).
function Export.Display(text)
	return (text:gsub("|", "||"))
end

---------------------------------------------------------------------------------------------------------------------
-- /atw debug, in the section Analytics and export: what the last export was, never a name, a zone or an enemy
---------------------------------------------------------------------------------------------------------------------
function Export.DebugLines()
	local lines = {}
	local last = Export.stats.last
	if last then
		lines[#lines + 1] = ("export last: %s %s, %d bytes, %d rows left out, names replaced %s"):format(last.kind,
			last.format, last.bytes, last.left, last.replaced and "yes" or "no")
	else
		lines[#lines + 1] = "export last: none"
	end
	lines[#lines + 1] = ("export builds: %d%s"):format(Export.stats.builds, job and ", building" or "")
	if Export.lastError then lines[#lines + 1] = "export last error: " .. Export.lastError end
	return lines
end

do
	local before = Metrics.ExtraLines     -- the comparison's (Data/Compare.lua), then these
	Metrics.ExtraLines = function()
		local lines = before and before() or {}
		for _, text in ipairs(Export.DebugLines()) do lines[#lines + 1] = text end
		return lines
	end
end

if ns.addon then ns.addon.Export = Export end
