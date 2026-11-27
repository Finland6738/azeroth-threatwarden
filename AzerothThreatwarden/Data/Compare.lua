-- Compare: recorded fights against the same enemy side by side, with their aggregates, and the overview by enemy
-- (SPEC-06 §2; ANA-01, ANA-04; ADR 0003, 0018; Q23). Lua 5.1, no game API (the next frame and the player's combat
-- flag through Core/Compat.lua), nothing saved. Behind the `analytics` switch (ADR 0014). Threatwarden's own.
--
-- Only what can be compared honestly is compared: fights with the same key (the main enemy: its creature number, else
-- its name and classification, never an unknown enemy), by default with the same group size, difficulty and role of
-- the player; the state metrics only between fights with the same recorded thresholds or all with the game states,
-- the percentages only where values were recorded. A fight that cannot be compared on a metric says why and stays out
-- of that aggregate; a lower bound stays a lower bound in every aggregate it enters. No ranking, no trend (ANA-01):
-- the fights go from the most recent to the oldest, the aggregates are a total, a median, the lowest and highest values.
--
--   Compare.Set(key, filters)                  the fights of `key` from the headers (newest first, at most MAX_FIGHTS)
--                                              and the ones left out with the reason; nothing decoded
--   Compare.Build(key, filters, progress, done) Metrics.Build one session at a time, paused in combat; progress(i, n,
--                                              paused), done(result) or done(nil, "off" / "no-key" / "cancelled")
--   Compare.Assemble(set, rows)                the comparison of rows already built: comparability and aggregates
--   Compare.Value(row, measure)                one cell of the comparison table: { status, value, lower, ... }
--   Compare.Overview()                         one row per enemy from the headers only (§2.3), never decoded
--   Compare.Current() / Compare.OnChange(fn)   the last comparison, kept up to date at SESSIONS_CHANGED
--   Compare.*Text                              the words (ANALYTICS_* keys)
local ADDON_NAME, ns = ...
ns = ns or {}
ns.modules = ns.modules or {}

local Compare = {}
ns.Compare, ns.modules.Compare = Compare, Compare

local Storage, Compat, Metrics, Report = ns.Storage, ns.Compat, ns.Metrics, ns.Report
local type, pairs, ipairs, tostring, floor, sort = type, pairs, ipairs, tostring, math.floor, table.sort

-- Q23, each answer in one place.
Compare.KEY = Metrics.Key          -- the key of a session: the creature number, else name and classification, else nil
Compare.FILTERS = { group = true, diff = true, role = true }   -- on by default
Compare.MAX_FIGHTS = 20            -- the most recent fights of the key after the filters
Compare.MIN_FIGHTS = 2             -- comparable fights an aggregate needs
Compare.PAUSE_IN_COMBAT = true     -- the queue stops in combat (the monitor first, P10), as the replay (Q18)

-- What the comparison table shows, and aggregates (§2.1, §2.2). `group`: "state" compared only with the same basis
-- (thresholds or game states), "values" only where values were recorded (the cell is ok), "all" with every fight.
-- `kind`: "count" and "time" add up (a total) and become lower bounds in an interrupted fight; "pct" and "rate" do not.
-- `unit`: a cell of the player's unit, compared only with the same role.
local function field(name) return function(v) return v[name] end end
Compare.MEASURES = {
	{ id = "fight", cell = "context", group = "all", kind = "time", get = field("fight") },
	{ id = "valid", cell = "valid", group = "all", kind = "pct", get = function(_, m) return m.valid and m.valid.state end },
	{ id = "validValues", cell = "valid", group = "all", kind = "pct",
		get = function(_, m) return m.valid and m.valid.values end },
	{ id = "warningCross", cell = "crossings", group = "state", kind = "count", get = field("warning") },
	{ id = "dangerCross", cell = "crossings", group = "state", kind = "count", get = field("danger") },
	{ id = "warningAny", cell = "stateTime", group = "state", kind = "time", get = field("warningAny") },
	{ id = "dangerAny", cell = "stateTime", group = "state", kind = "time", get = field("dangerAny") },
	{ id = "holders", cell = "holders", group = "all", kind = "count", get = field("total") },
	{ id = "aggroTaken", cell = "aggroTaken", group = "all", kind = "count", get = function(v) return v end },
	{ id = "closest", cell = "maxNotHolding", group = "values", kind = "pct", get = field("pct") },
	{ id = "unstable", cell = "unstable", group = "state", kind = "count", get = field("count") },
	{ id = "unstableTime", cell = "unstable", group = "state", kind = "time", get = field("total") },
	{ id = "risk", cell = "risk", group = "state", kind = "rate", get = field("perMinute") },
	{ id = "deaths", cell = "deaths", group = "all", kind = "count",
		get = function(v) return type(v) == "table" and #v or nil end },
	{ id = "myWarningCross", cell = "warningCross", unit = true, group = "state", kind = "count",
		get = function(v) return v end },
	{ id = "myDangerCross", cell = "dangerCross", unit = true, group = "state", kind = "count",
		get = function(v) return v end },
	{ id = "myWarningTime", cell = "warningTime", unit = true, group = "state", kind = "time",
		get = function(v) return v end },
	{ id = "myDangerTime", cell = "dangerTime", unit = true, group = "state", kind = "time",
		get = function(v) return v end },
	{ id = "myMaxPct", cell = "maxPct", unit = true, group = "values", kind = "pct", get = field("pct") },
	{ id = "myAggro", cell = "aggro", unit = true, group = "all", kind = "count", get = function(v) return v end },
}
Compare.MEASURE = {}
for _, ms in ipairs(Compare.MEASURES) do Compare.MEASURE[ms.id] = ms end

local job                         -- the comparison being built
local last                        -- the last comparison built
local changed                     -- the listener of Compare.OnChange
local listening = false
Compare.stats = { builds = 0 }

local function on()
	local F = ns.Features
	return F ~= nil and F.On("analytics")
end

local function noop() end

local function inCombat()
	if ns.addon and ns.addon.inCombat then return true end
	return Compat.Unit.AffectingCombat("player") == true
end

local function filtersOf(filters)
	local out = {}
	for name, default in pairs(Compare.FILTERS) do
		local v
		if type(filters) == "table" then v = filters[name] end
		if v == nil then v = default end
		out[name] = v == true
	end
	return out
end

---------------------------------------------------------------------------------------------------------------------
-- Keys and sets, from the headers only (§2.1)
---------------------------------------------------------------------------------------------------------------------
-- The key of a header of Storage.List: its main enemy (from `sum`), nil when unknown or not yet summarized.
function Compare.HeaderKey(h)
	if type(h) ~= "table" or type(h.enemy) ~= "table" then return nil end
	return Compare.KEY({ mobs = { h.enemy } }, 1)
end

local function closed(h) return not h.open and h.state ~= "open" end

-- The fights of `key`: { key, filters, ref, fights (headers, newest first), excluded { id, reason }, older, total }.
function Compare.Set(key, filters)
	filters = filtersOf(filters)
	local set = { key = key, filters = filters, fights = {}, excluded = {}, older = 0, total = 0, ref = {} }
	if key == nil then return set end
	local candidates = {}
	for _, h in ipairs(Storage.List()) do
		if closed(h) and Compare.HeaderKey(h) == key then candidates[#candidates + 1] = h end
	end
	set.total = #candidates
	-- the reference: the most recent fight of the key (its group and role), the most recent known difficulty
	local first = candidates[1]
	if first then
		set.ref.group, set.ref.role = first.group, first.role
		for _, h in ipairs(candidates) do
			if h.diff ~= nil then set.ref.diff = h.diff break end
		end
	end
	for _, h in ipairs(candidates) do
		local reason
		if filters.group and h.group ~= set.ref.group then reason = "group"
		elseif filters.diff and h.diff ~= nil and set.ref.diff ~= nil and h.diff ~= set.ref.diff then reason = "diff"
		elseif filters.role and h.role ~= set.ref.role then reason = "role" end
		if reason then
			set.excluded[#set.excluded + 1] = { id = h.id, reason = reason }
		elseif #set.fights < Compare.MAX_FIGHTS then
			set.fights[#set.fights + 1] = h
		else
			set.older = set.older + 1
		end
	end
	return set
end

---------------------------------------------------------------------------------------------------------------------
-- Comparability and aggregates (§2.1, §2.2)
---------------------------------------------------------------------------------------------------------------------
-- The basis of the state metrics of a fight: "game", "thresholds:82/91", "mixed:82/91", nil without one.
function Compare.Basis(m)
	local b = m.cells and m.cells.crossings and m.cells.crossings.basis
	if b == "game" then return "game" end
	if b ~= "thresholds" and b ~= "mixed" then return nil end
	local rec = m.rec or {}
	return b .. ":" .. tostring(rec.warning) .. "/" .. tostring(rec.danger)
end

local function playerOf(m)
	for _, u in ipairs(m.units or {}) do
		if u.me then return u end
	end
	return nil
end

-- What the comparison keeps of a fight, once, from its metrics: a few header values and one plain entry per measure
-- (the metrics themselves stay in the cache of Data/Metrics.lua only, so the memory follows the cache, not the set).
-- An entry is { status ("ok", "na", "insufficient"), value, lower, category, reason }; a count or a time of an
-- interrupted fight is a lower bound (§1.6); the risk rate keeps its situations and known time for the weighted rate.
local function extract(row)
	local m = row.metrics
	row.metrics = nil
	row.basis = Compare.Basis(m)
	row.state, row.outcome, row.after, row.role = m.state, m.outcome, m.after, m.role
	row.group, row.diff, row.hz = m.group, m.diff, m.rec and m.rec.hz
	row.dur, row.coverage = m.dur, m.coverage       -- for the export (Data/Export.lua)
	row.interrupted = m.state == "interrupted" or nil
	local player = playerOf(m)
	row.hasPlayer = player ~= nil
	row.raw = {}
	for _, ms in ipairs(Compare.MEASURES) do
		local c
		if ms.unit then c = player and player.cells[ms.cell] else c = m.cells[ms.cell] end
		local entry
		if type(c) ~= "table" then
			entry = { status = "na", reason = ms.unit and "no-player" or nil }
		elseif c.status ~= "ok" then
			entry = { status = c.status, reason = c.reason, valid = c.valid, coverage = c.coverage }
		else
			local value = ms.get(c.value, m)
			if type(value) ~= "number" then
				entry = { status = "na" }
			else
				local lower = c.lower == true or (row.interrupted and (ms.kind == "count" or ms.kind == "time")) or false
				entry = { status = "ok", value = value, lower = lower, lowerBy = c.lowerBy, valid = c.valid,
					coverage = c.coverage, category = lower and "estimated" or c.category }
				if ms.kind == "rate" then
					entry.situations, entry.known, entry.cellLower = c.value.situations, c.value.known, c.lower == true
				end
			end
		end
		row.raw[ms.id] = entry
	end
end

-- One cell of the table: the entry of the measure, or { status = "not-comparable", nc } (another basis for a state
-- metric, another role for the player's), or { status = "damaged" / "error" } for a fight that could not be read.
function Compare.Value(row, ms)
	if row.status ~= "ok" then return { status = row.status } end
	if ms.unit and row.nc.player then return { status = "not-comparable", nc = row.nc.player } end
	if ms.group == "state" and row.nc.state then return { status = "not-comparable", nc = row.nc.state } end
	return row.raw[ms.id]
end

local function median(values)
	local n = #values
	if n % 2 == 1 then return values[(n + 1) / 2] end
	local a, b = values[n / 2], values[n / 2 + 1]
	return floor((a + b) * 10 / 2 + 0.5) / 10
end

-- The aggregate of one measure over the rows (newest first).
local function aggregate(rows, ms)
	local values, of, lower, hz, hzSeen = {}, 0, false, false, nil
	local lo, hi
	local situations, known, rateLower = 0, 0, false
	for _, row in ipairs(rows) do
		if row.status == "ok" then
			of = of + 1
			local v = Compare.Value(row, ms)
			if v.status == "ok" then
				local entry = { value = v.value, lower = v.lower, category = v.category, id = row.id,
					started = row.started }
				values[#values + 1] = v.value
				if v.lower then lower = true end
				-- ties go to the most recent fight
				if not lo or v.value < lo.value then lo = entry end
				if not hi or v.value > hi.value then hi = entry end
				if ms.kind == "pct" then
					if hzSeen == nil then hzSeen = row.hz elseif row.hz ~= hzSeen then hz = true end
				end
				if ms.kind == "rate" then
					situations, known = situations + v.situations, known + v.known
					if v.cellLower then rateLower = true end
				end
			end
		end
	end
	local agg = { id = ms.id, n = #values, of = of }
	if #values < Compare.MIN_FIGHTS then
		agg.status, agg.reason = "insufficient", #values == 0 and "no-fight" or "one-fight"
		return agg
	end
	sort(values)
	agg.status, agg.lower = "ok", lower or nil
	agg.category = lower and "estimated" or "calculated"
	agg.median, agg.min, agg.max = median(values), lo, hi
	if ms.kind == "count" or ms.kind == "time" then
		local total = 0
		for _, v in ipairs(values) do total = total + v end
		agg.total = total
	end
	if ms.kind == "pct" and hz then agg.hz = true end
	if ms.kind == "rate" then
		-- weighted on the known time, not the mean of the rates
		agg.situations, agg.known = situations, known
		agg.rate = known > 0 and floor(situations * 6000 / known + 0.5) / 10 or nil
		agg.lower = (lower or rateLower) or nil
		agg.category = agg.lower and "estimated" or "calculated"
	end
	return agg
end

-- The comparison of `rows` built from `set`: rows { id, started, status, metrics } (newest first; a row assembled
-- before keeps what it took) get the basis and why they are not comparable; then one aggregate per measure.
function Compare.Assemble(set, rows, gone)
	local result = { key = set.key, filters = set.filters, ref = set.ref, rows = rows, excluded = set.excluded,
		older = set.older, gone = gone or 0, damaged = 0, counted = 0, aggregates = {} }
	-- the reference basis: the most recent fight that has one
	local refBasis
	for _, row in ipairs(rows) do
		if row.status == "ok" then
			if row.metrics then extract(row) end
			if refBasis == nil then refBasis = row.basis end
		end
	end
	result.basis = refBasis
	for _, row in ipairs(rows) do
		row.nc = {}
		if row.status == "ok" then
			result.counted = result.counted + 1
			row.diffUnknown = (set.filters and set.filters.diff and row.diff == nil) or nil
			if row.basis and row.basis ~= refBasis then
				row.nc.state = { reason = "basis", basis = row.basis, ref = refBasis }
			end
			if row.role ~= set.ref.role then
				row.nc.player = { reason = "role", role = row.role, ref = set.ref.role }
			end
		elseif row.status == "damaged" or row.status == "error" then
			result.damaged = result.damaged + 1
		end
	end
	for _, ms in ipairs(Compare.MEASURES) do result.aggregates[ms.id] = aggregate(rows, ms) end
	return result
end

---------------------------------------------------------------------------------------------------------------------
-- Building: a queue of Metrics.Build, one session at a time, paused in combat (§2.4)
---------------------------------------------------------------------------------------------------------------------
local function notify()
	if changed then changed(last) end
end

local function finish(j)
	job = nil
	-- a session deleted after it was built leaves the comparison
	local rows, gone = {}, j.gone
	for _, row in ipairs(j.rows) do
		if row.status ~= "ok" or Storage.Get(row.id) then rows[#rows + 1] = row else gone = gone + 1 end
	end
	last = Compare.Assemble(j.set, rows, gone)
	last.newFights = 0
	Compare.stats.builds = Compare.stats.builds + 1
	j.done(last)
end

local function take(j, h, m, why)
	if m then
		j.rows[#j.rows + 1] = { id = h.id, started = h.started, status = "ok", metrics = m }
	elseif why == "damaged" or why == "error" then
		j.rows[#j.rows + 1] = { id = h.id, started = h.started, status = why }
	else
		j.gone = j.gone + 1             -- deleted, or now open: out of the set
	end
end

local run
local function later(j)
	if not Compat.After(0, function() run(j) end) then run(j) end
end

function run(j)
	while job == j do
		local n = #j.set.fights
		if j.i >= n then finish(j) return end
		if Compare.PAUSE_IN_COMBAT and inCombat() then
			j.paused = true
			j.progress(j.i, n, true)
			return
		end
		j.paused = false
		j.i = j.i + 1
		local h = j.set.fights[j.i]
		j.progress(j.i, n, false)
		local hit = Metrics.Cached(h.id) ~= nil
		local waiting, answered = true, false
		Metrics.Build(h.id, function(m, why)
			answered = true
			if job ~= j then return end
			if why == "off" then
				job = nil
				j.done(nil, "off")
				return
			end
			take(j, h, m, why)
			if not waiting then later(j) end   -- answered in a later frame: the next session on the next frame
		end)
		waiting = false
		if not answered then return end
		-- answered at once: from memory the next one follows in this frame; else on the next frame
		if not hit then later(j) return end
	end
end

local function onCombatEnded()
	if job and job.paused then run(job) end
end

local function onSessionsChanged()
	if not last then return end
	local keep, gone = {}, 0
	for _, row in ipairs(last.rows) do
		if row.status ~= "ok" or Storage.Get(row.id) then keep[#keep + 1] = row else gone = gone + 1 end
	end
	local known = {}
	for _, row in ipairs(last.rows) do known[row.id] = true end
	for _, x in ipairs(last.excluded) do known[x.id] = true end
	local fresh = 0
	for _, h in ipairs(Compare.Set(last.key, last.filters).fights) do
		if not known[h.id] then fresh = fresh + 1 end
	end
	if gone == 0 and fresh == last.newFights then return end
	if gone > 0 then
		local set = { key = last.key, filters = last.filters, ref = last.ref, excluded = last.excluded,
			older = last.older }
		last = Compare.Assemble(set, keep, last.gone + gone)
	end
	last.newFights = fresh
	notify()
end

local function listen()
	if listening or not ns.Bus then return end
	listening = true
	ns.Bus.On("COMBAT_ENDED", onCombatEnded)
	ns.Bus.On("COMBAT_STARTED", function()
		if job then job.progress(job.i, #job.set.fights, true) end
	end)
	ns.Bus.On("SESSIONS_CHANGED", onSessionsChanged)
end

function Compare.Listening() return listening end

function Compare.Build(key, filters, progress, done)
	progress, done = progress or noop, done or noop
	if not on() then done(nil, "off") return end
	listen()
	if job then
		local old = job
		job = nil
		old.done(nil, "cancelled")
	end
	if key == nil then done(nil, "no-key") return end
	local j = { set = Compare.Set(key, filters), i = 0, rows = {}, gone = 0, progress = progress,
		done = done }
	job = j
	run(j)
end

function Compare.Cancel()
	if not job then return false end
	local old = job
	job = nil
	old.done(nil, "cancelled")
	return true
end

-- The comparison being built: { i, n, paused }, nil without one.
function Compare.Queue()
	if not job then return nil end
	return { i = job.i, n = #job.set.fights, paused = job.paused == true }
end

function Compare.Current() return last end
function Compare.OnChange(fn) changed = fn end

---------------------------------------------------------------------------------------------------------------------
-- The overview by enemy, from the headers only (§2.3)
---------------------------------------------------------------------------------------------------------------------
-- One row per key, the most recent recording first (never by a number of the threat), then one row for the fights
-- without a key: { key, name, class, group, groups, count, fight, fightLower, last, validMin, validMax, validUnknown,
-- unknown }.
function Compare.Overview()
	local rows, byKey, unknown = {}, {}, nil
	if not on() then return rows end
	for _, h in ipairs(Storage.List()) do
		if closed(h) then
			local key = Compare.HeaderKey(h)
			local row = key and byKey[key] or (not key and unknown)
			if not row then
				row = { key = key, count = 0, fight = 0, last = h.started, group = h.group, groups = {},
					validUnknown = 0, unknown = not key or nil }
				if key then
					row.name, row.class = h.enemy.name, h.enemy.class
					byKey[key] = row
					rows[#rows + 1] = row
				else
					unknown = row
				end
			end
			row.count = row.count + 1
			row.fight = row.fight + (type(h.fight) == "number" and h.fight or 0)
			if h.state == "interrupted" and not ((h.fight or 0) > 0) then row.fightLower = true end
			local g = h.group or "unknown"
			row.groups[g] = (row.groups[g] or 0) + 1
			local valid = type(h.sum) == "table" and h.sum.valid
			if type(valid) == "number" then
				if not row.validMin or valid < row.validMin then row.validMin = valid end
				if not row.validMax or valid > row.validMax then row.validMax = valid end
			else
				row.validUnknown = row.validUnknown + 1
			end
		end
	end
	if unknown then rows[#rows + 1] = unknown end
	return rows
end

---------------------------------------------------------------------------------------------------------------------
-- Words (ADR 0009; ANA-01: no ranking, no merit, no trend; ANA-04: the category of every value)
---------------------------------------------------------------------------------------------------------------------
Compare.MEASURE_KEYS = {
	fight = "ANALYTICS_M_FIGHT", valid = "ANALYTICS_M_VALID", validValues = "ANALYTICS_M_VALID_VALUES",
	warningCross = "ANALYTICS_M_WARNING_CROSS", dangerCross = "ANALYTICS_M_DANGER_CROSS",
	warningAny = "ANALYTICS_M_WARNING_ANY", dangerAny = "ANALYTICS_M_DANGER_ANY", holders = "ANALYTICS_METRIC_HOLDERS",
	aggroTaken = "ANALYTICS_METRIC_AGGRO_TAKEN", closest = "ANALYTICS_METRIC_CLOSEST",
	unstable = "ANALYTICS_METRIC_UNSTABLE", unstableTime = "ANALYTICS_M_UNSTABLE_TIME", risk = "ANALYTICS_M_RISK",
	deaths = "ANALYTICS_M_DEATHS", myWarningCross = "ANALYTICS_M_MY_WARNING_CROSS",
	myDangerCross = "ANALYTICS_M_MY_DANGER_CROSS", myWarningTime = "ANALYTICS_M_MY_WARNING_TIME",
	myDangerTime = "ANALYTICS_M_MY_DANGER_TIME", myMaxPct = "ANALYTICS_M_MY_MAX", myAggro = "ANALYTICS_M_MY_AGGRO",
}
Compare.FILTER_KEYS = { group = "ANALYTICS_FILTER_GROUP", diff = "ANALYTICS_FILTER_DIFF", role = "ANALYTICS_FILTER_ROLE" }
Compare.AGGREGATE_KEYS = { total = "ANALYTICS_AGG_TOTAL", median = "ANALYTICS_AGG_MEDIAN", min = "ANALYTICS_AGG_MIN",
	max = "ANALYTICS_AGG_MAX", rate = "ANALYTICS_AGG_RATE" }

local function number(ms, v)
	local L = ns.L
	if ms.kind == "time" then return Report.Time(floor(v + 0.5)) end
	if ms.kind == "pct" then
		if ms.id == "valid" or ms.id == "validValues" then return L.ANALYTICS_PCT_WHOLE:format(floor(v + 0.5)) end
		return L.TIMELINE_PERCENT:format(v)
	end
	if ms.kind == "rate" or v ~= floor(v) then return ("%.1f"):format(v) end
	return ("%d"):format(v)
end

-- A value of a measure with its marker: "at least 3", "~2.5" (a median with a lower bound in it).
function Compare.NumberText(ms, v, lower, approx)
	local text = number(ms, v)
	if lower then
		if approx then return ns.L.ANALYTICS_APPROX:format(text) end
		return ns.L.REPORT_AT_LEAST:format(text)
	end
	return text
end

-- The basis of a fight in words: "thresholds 82 / 91", "game states", "thresholds 82 / 91 and game states".
function Compare.BasisText(basis)
	local L = ns.L
	if basis == "game" then return L.ANALYTICS_BASIS_GAME end
	local kind, w, d = tostring(basis):match("^(%a+):([^/]*)/(.*)$")
	if kind == "thresholds" then return L.ANALYTICS_BASIS_THRESHOLDS:format(w, d) end
	if kind == "mixed" then return L.ANALYTICS_BASIS_MIXED:format(w, d) end
	return L.REPORT_UNKNOWN
end

-- "Not comparable: thresholds 82 / 91 and 80 / 95", "Not comparable: another role".
function Compare.NotComparableText(nc)
	local L = ns.L
	if nc.reason == "role" then return L.ANALYTICS_NC_ROLE end
	local a, b = tostring(nc.basis), tostring(nc.ref)
	local aw, ad = a:match("^thresholds:([^/]*)/(.*)$")
	local bw, bd = b:match("^thresholds:([^/]*)/(.*)$")
	if aw and bw then return L.ANALYTICS_NC_THRESHOLDS:format(aw, ad, bw, bd) end
	return L.ANALYTICS_NC_BASES:format(Compare.BasisText(nc.basis), Compare.BasisText(nc.ref))
end

-- The text of a cell of the table (Compare.Value).
function Compare.CellText(ms, v)
	local L = ns.L
	if v.status == "ok" then return Compare.NumberText(ms, v.value, v.lower) end
	if v.status == "not-comparable" then return Compare.NotComparableText(v.nc) end
	if v.status == "damaged" or v.status == "error" then return L.ANALYTICS_DAMAGED_ROW end
	if v.status == "insufficient" then return L.REPORT_INSUFFICIENT end
	return L.REPORT_NA
end

-- The text of one aggregate of a measure (`which`: total, median, min, max, rate), or why there is none.
function Compare.AggregateText(agg, which)
	local L = ns.L
	if agg.status ~= "ok" then
		return agg.reason == "one-fight" and L.ANALYTICS_ONE_FIGHT or L.ANALYTICS_NO_FIGHT
	end
	local ms = Compare.MEASURE[agg.id]
	if which == "min" or which == "max" then
		local e = agg[which]
		return Compare.NumberText(ms, e.value, e.lower)
	end
	if which == "rate" then
		if not agg.rate then return L.REPORT_NA end
		return L.ANALYTICS_RISK_ALL:format(Compare.NumberText(ms, agg.rate, agg.lower))
	end
	local v = agg[which]
	if v == nil then return "" end
	return Compare.NumberText(ms, v, agg.lower, which == "median")
end

-- The tooltip of an aggregate: how many fights, the category, why it is a lower bound, different recording rates.
function Compare.AggregateTip(agg)
	local L, lines = ns.L, { Compare.CountText(agg) }
	if agg.status ~= "ok" then
		lines[#lines + 1] = Compare.AggregateText(agg)
		return lines
	end
	local cat = agg.category == "estimated" and "CAT_ESTIMATED" or "CAT_CALCULATED"
	lines[#lines + 1] = L.ANALYTICS_TIP_CATEGORY:format(L[cat])
	if agg.lower then lines[#lines + 1] = L.ANALYTICS_LOWER_IN_SET end
	if agg.hz then lines[#lines + 1] = L.ANALYTICS_HZ_DIFFERS end
	return lines
end

-- The notes of one fight of the table: interrupted (its counts and times at least), difficulty not recorded.
function Compare.RowNotes(row)
	local L, lines = ns.L, {}
	if row.status ~= "ok" then
		lines[1] = L.ANALYTICS_DAMAGED_ROW
		return lines
	end
	if row.interrupted then lines[#lines + 1] = L.ANALYTICS_LOWER_INTERRUPTED end
	if row.diffUnknown then lines[#lines + 1] = L.ANALYTICS_DIFF_UNKNOWN end
	return lines
end

-- The name of a row of the overview, or of a key that cannot be compared.
function Compare.OverviewName(row)
	if row.unknown then return ns.L.ANALYTICS_UNKNOWN_ENEMIES end
	return row.name or ns.L.MON_UNKNOWN_MOB
end

function Compare.KeyText(key, name)
	if key == nil then return ns.L.ANALYTICS_UNKNOWN_ENEMY end
	return name or ns.L.MON_UNKNOWN_MOB
end

-- "4 of 5 fights"
function Compare.CountText(agg)
	return ns.L.ANALYTICS_OF_FIGHTS:format(agg.n, agg.of)
end

-- "Building 4 of 9…" or "Paused during combat"
function Compare.ProgressText(i, n, paused)
	if paused then return ns.L.ANALYTICS_PAUSED end
	return ns.L.ANALYTICS_BUILDING:format(i, n)
end

local function counted(one, many, n)
	if n == 1 then return ns.L[one] end
	return ns.L[many]:format(n)
end

-- The lines under a comparison: the fights left out by the filters, the older ones, the deleted, the damaged, the new.
function Compare.NoteLines(result)
	local lines = {}
	local excluded = #result.excluded
	if excluded > 0 then lines[#lines + 1] = counted("ANALYTICS_EXCLUDED_ONE", "ANALYTICS_EXCLUDED", excluded) end
	if result.older > 0 then lines[#lines + 1] = counted("ANALYTICS_OLDER_ONE", "ANALYTICS_OLDER", result.older) end
	if result.gone > 0 then lines[#lines + 1] = counted("ANALYTICS_GONE_ONE", "ANALYTICS_GONE", result.gone) end
	if result.damaged > 0 then
		lines[#lines + 1] = counted("ANALYTICS_DAMAGED_ONE", "ANALYTICS_DAMAGED", result.damaged)
	end
	if (result.newFights or 0) > 0 then
		lines[#lines + 1] = counted("ANALYTICS_NEW_FIGHTS_ONE", "ANALYTICS_NEW_FIGHTS", result.newFights)
	end
	return lines
end

---------------------------------------------------------------------------------------------------------------------
-- /atw debug, in the section Analytics and export: counts only, never a key, a name or an enemy
---------------------------------------------------------------------------------------------------------------------
function Compare.DebugLines()
	local lines = {}
	if last then
		lines[#lines + 1] = ("compare last set: %d fights, %d left out, %d older, %d deleted, %d damaged"):format(
			last.counted, #last.excluded, last.older, last.gone, last.damaged)
	else
		lines[#lines + 1] = "compare last set: none"
	end
	local q = Compare.Queue()
	if q then
		lines[#lines + 1] = ("compare queue: %d of %d%s"):format(q.i, q.n, q.paused and ", paused in combat" or "")
	else
		lines[#lines + 1] = "compare queue: idle"
	end
	lines[#lines + 1] = ("compare builds: %d"):format(Compare.stats.builds)
	return lines
end

Metrics.ExtraLines = Compare.DebugLines   -- in Metrics.DebugLines, after the metrics' own
if ns.addon then ns.addon.Compare = Compare end
