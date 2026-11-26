-- Timeline: the model of the Threat Timeline of a recorded session (SPEC-05 §4.1–§4.7; RPL-01–RPL-05; ADR 0003, 0017).
-- Lua 5.1, no game API (the next frame and the profiling clock through Core/Compat.lua), nothing saved. Behind the
-- `timeline` switch (ADR 0014). Threatwarden's own.
--
-- A view over the session: everything comes from its rows and events (Storage.Decode), with the periods, the states,
-- the holders and the crossings of Data/Report.lua itself (Report.Walk), so that report and timeline cannot say
-- different things. Nothing is interpolated, averaged or rebuilt: every vertex is a recorded reading, a segment between
-- two readings is solid (detected), dashed (estimated) or absent with its reason, and every gap keeps its kind and its
-- reason (unknown, never filled).
--
--   Timeline.Compute(session, decoded, step)   the model (one pass; `step` is called once per event and row)
--   Timeline.Build(id, done)                    Storage.Decode, then Compute in slices of SLICE rows or events per frame;
--                                               done(model) or done(nil, "off" / "unknown" / "recording" / "damaged" /
--                                               "error"); one model is kept in memory, dropped at SESSIONS_CHANGED
--   Timeline.View(model, a, b, buckets, series, out)   the first, last, lowest and highest reading per column
--   Timeline.Summary(model, a, b, out, series)  the summary of an interval (calculated; estimated with unknown time)
--   Timeline.Group(markers, a, b, width, out)   the markers of the event track grouped under MARKER_PX
--   Timeline.MarkerText / GapText / OutcomeText / ModeText / ReasonText / TimeText / PercentText   the words
--                                               (TIMELINE_* keys)
--
-- Times are tenths of a second from the start of the session. A segment is kept on the reading it ends at: for the
-- k-th reading of a series, segs[k] is "solid", "dashed" or "none" (from reading k - 1) and why[k] the reason of "none".
local ADDON_NAME, ns = ...
ns = ns or {}
ns.modules = ns.modules or {}

local Timeline = {}
ns.Timeline, ns.modules.Timeline = Timeline, Timeline

local Session, Storage, Compat, Report = ns.Session, ns.Storage, ns.Compat, ns.Report
local type, pairs, ipairs, tostring, floor, max, min, sort = type, pairs, ipairs, tostring, math.floor, math.max, math.min, table.sort

Timeline.SLICE = 5000           -- rows or events per frame (§4.2)
Timeline.ESTIMATE_MAX = 100     -- tenths: two readings further apart are not joined (§4.3)
Timeline.MIN_VIEW = 50          -- tenths: the narrowest view (§4.7)
Timeline.BUCKET_PX = 2          -- pixels per column (§4.7)
Timeline.MAX_BUCKETS = 400      -- columns at most
Timeline.MARKER_PX = 8          -- markers of the track closer than this are one (§4.5)
Timeline.GROUP_LINES = 8        -- markers listed in the tooltip of a group, then "and N more"
Timeline.MAX_SERIES = 6         -- series shown (§4.7, Q20)
Timeline.MAX_LANES = 10         -- state lanes (§4.6)

-- The category of every element (RPL-02, ADR 0003).
Timeline.SEGMENT_CATEGORY = { solid = "detected", dashed = "estimated", none = "unknown" }
Timeline.GAP_CATEGORY = "unknown"
Timeline.GAP_KINDS = { "unknown", "stale", "mode", "nomob", "tick", "limit" }
-- The reasons a segment is absent (§4.3), in the order they are checked.
Timeline.BREAKS = { "first", "mob", "row", "target", "tick", "mode", "combat", "limit", "exit", "far" }

local ROW_REASON = { S = "secret", E = "error", M = "missing", U = "no-unit", X = "other", T = "stale" }
local MODE_REASON = { S = "secret", E = "error", M = "missing", U = "no-unit", T = "stale", X = "other" }
local MODE_NAME = { v = "values", s = "state", n = "none" }
local VALID_MODE = { values = true, state = true, none = true }
local STATE_ONLY = { a = true, b = true, c = true, d = true }
local NOMOB_REASON = { n = "none", d = "died", l = "lost" }
local CATEGORY_NAME, CONFIDENCE_NAME, RULE_NAME = {}, {}, {}
for name, code in pairs(Session.CATEGORY_CODE) do CATEGORY_NAME[code] = name end
for name, code in pairs(Session.CONFIDENCE_CODE) do CONFIDENCE_NAME[code] = name end
for name, code in pairs(Session.RULE_CODE) do RULE_NAME[code] = name end

-- Grouping: the icon of a group is the most important marker's (§4.5).
local PRIO = { D = 1, took = 2, C = 3, c = 3, T = 4, N = 5, L = 6, H = 7 }

local cache = { s = nil, model = nil }
Timeline.stats = { builds = 0, ms = nil, frames = 0 }
local listening = false

local function on()
	local F = ns.Features
	return F ~= nil and F.On("timeline")
end

local function noop() end

local I = Report.Intervals

---------------------------------------------------------------------------------------------------------------------
-- Small helpers
---------------------------------------------------------------------------------------------------------------------
-- Intervals of `list` ({ from, to, ... }) cut to the periods `periods` ({ from, to }), with the rest of each entry.
local function clipTo(list, periods, out)
	for _, g in ipairs(list) do
		for _, p in ipairs(periods) do
			local from, to = max(g[1], p[1]), min(g[2], p[2])
			if to > from then out[#out + 1] = { from, to, g[3], g[4] } end
		end
	end
	return out
end

-- Length of the part of the intervals of `list` inside [a, b].
local function overlap(list, a, b, field, value)
	local total = 0
	for _, i in ipairs(list) do
		if field == nil or i[field] == value then
			local from, to = max(i[1], a), min(i[2], b)
			if to > from then total = total + to - from end
		end
	end
	return total
end

-- The end of the watched period of mob `m` (else the combat period) that holds time `t`; `t` itself without one.
local function periodEnd(model, t, m)
	for _, p in ipairs(model.mobs) do
		if p[3] == m and t >= p[1] and t < p[2] then return p[2] end
	end
	for _, p in ipairs(model.combat) do
		if t >= p[1] and t < p[2] then return p[2] end
	end
	return t
end

local function newSeries(index)
	return {
		index = index, rows = {}, segs = {}, why = {}, states = {}, holds = {}, unknown = {}, present = {},
		crossings = {}, maxP = nil, maxT = nil, readings = 0, held = 0, wd = 0, stateRows = 0, unknownAll = {},
	}
end

---------------------------------------------------------------------------------------------------------------------
-- The model (§4.2)
---------------------------------------------------------------------------------------------------------------------
-- The events of the timeline's own: mode bands, whole-chart gaps, the breaks of the segments, the markers.
local function walkEvents(model, d, crossingOf, step)
	local modes, gaps, events = model.modes, {}, model.events
	local breaks, exits = {}, {}
	local mode = model.startMode
	local modeFrom, modeReason = 0, nil
	local nomob = nil                      -- the open gap without a mob: { from, reason }

	local function closeMode(t)
		if mode and t > modeFrom then modes[#modes + 1] = { modeFrom, t, mode, modeReason } end
	end
	local function closeNomob(t)
		if nomob then
			if t > nomob[1] then gaps[#gaps + 1] = { nomob[1], t, "nomob", nomob[2] } end
			nomob = nil
		end
	end

	for _, e in ipairs(d.events) do
		local t, k = e.t, e.k
		local mk = { t = t, k = k, m = e.m, u = e.u, v = e.v, a = e.a, b = e.b, c = e.c, n = e.n,
			category = "detected", place = "track", prio = PRIO[k] or 8 }
		if k == "C" then
			mk.kind = "combat"
		elseif k == "c" then
			mk.kind, mk.place = "end", "chart"
			breaks[#breaks + 1] = { t, "combat" }
		elseif k == "T" then
			mk.place = "chart"
			breaks[#breaks + 1] = { t, "target" }
			if e.m > 0 then
				mk.kind = "target"
				closeNomob(t)
			else
				mk.kind, mk.reason = "nomob", NOMOB_REASON[e.a] or "none"
				if not nomob or nomob[2] ~= mk.reason then
					closeNomob(t)
					nomob = { t, mk.reason }
				end
			end
		elseif k == "S" then
			mk.place, mk.state = "lane", e.a
			mk.category = mode == "state" and "detected" or "calculated"
			if crossingOf[e] then
				mk.kind, mk.place = "cross", "series"
			elseif e.a == "-" then
				mk.kind = "leave"
			elseif e.b == "-" then
				mk.kind = "enter"
			else
				mk.kind = "state"
			end
			if e.a == "-" then
				local list = exits[e.u]
				if not list then list = {} exits[e.u] = list end
				list[#list + 1] = t
			end
		elseif k == "A" then
			if e.a == "1" then
				mk.kind, mk.place = "holder", "lane"
			else
				mk.kind, mk.prio, mk.lane = "took", PRIO.took, true
			end
		elseif k == "M" then
			mk.kind, mk.place = "mode", "chart"
			local name = MODE_NAME[e.a]
			if name then
				local reason = name == "none" and (MODE_REASON[e.b] or "other") or nil
				mk.mode, mk.reason = name, reason
				if name ~= mode or reason ~= modeReason then
					closeMode(t)
					mode, modeFrom, modeReason = name, t, reason
				end
				if name ~= "values" then breaks[#breaks + 1] = { t, "mode" } end
			end
		elseif k == "G" then
			mk.kind, mk.place = "tick", "chart"
			if e.n > 0 then
				local from = max(t - e.n, 0)
				gaps[#gaps + 1] = { from, t, "tick", nil }
				breaks[#breaks + 1] = { from, "tick" }
				breaks[#breaks + 1] = { t, "tick" }
			end
		elseif k == "D" then
			mk.kind = "death"
		elseif k == "L" then
			mk.kind = "alert"
			local raw = e.raw or "--"
			mk.category = CATEGORY_NAME[raw:sub(1, 1)] or "unknown"
			mk.confidence = CONFIDENCE_NAME[raw:sub(2, 2)] or "unknown"
		elseif k == "H" then
			mk.kind = "coach"
			mk.rule = RULE_NAME[e.a]
			mk.category = CATEGORY_NAME[e.b] or "unknown"
			mk.confidence = CONFIDENCE_NAME[e.c] or "unknown"
		elseif k == "N" then
			mk.kind = "encounter"
		elseif k == "X" then
			mk.kind = "interrupted"
		elseif k == "Z" then
			mk.kind = "limit"
			if e.a == "r" or e.a == "t" then breaks[#breaks + 1] = { t, "limit" } end
		end
		events[#events + 1] = mk
		step()
	end
	closeMode(model.dur)
	closeNomob(model.dur)

	-- The gaps of the whole chart (§4.4): mode and no mob only inside combat (out of combat is not a gap).
	local whole = {}
	local none = {}
	for _, band in ipairs(modes) do
		if band[3] == "none" then none[#none + 1] = { band[1], band[2], "mode", band[4] } end
	end
	clipTo(none, model.combat, whole)
	local nomobs = {}
	for _, g in ipairs(gaps) do
		if g[3] == "nomob" then nomobs[#nomobs + 1] = g else whole[#whole + 1] = g end
	end
	clipTo(nomobs, model.combat, whole)
	if model.trunc and model.dur > model.trunc then whole[#whole + 1] = { model.trunc, model.dur, "limit", "samples" } end
	sort(whole, function(x, y)
		if x[1] ~= y[1] then return x[1] < y[1] end
		return x[2] < y[2]
	end)
	model.gaps = whole

	-- The breaks, in order of time: two arrays walked with one pointer per unit.
	for i, b in ipairs(breaks) do b[3] = i end
	sort(breaks, function(x, y)
		if x[1] ~= y[1] then return x[1] < y[1] end
		return x[3] < y[3]
	end)
	local bt, bk = {}, {}
	for i, b in ipairs(breaks) do bt[i], bk[i] = b[1], b[2] end
	return bt, bk, exits
end

-- The rows: the series with their readings and segments, the unknown and stale gaps of each unit.
local function walkRows(model, d, bt, bk, exits, acc, step)
	local units, join = model.units, model.join
	local NUMBERED = Session.NUMBERED
	local lastNum, dirty, openGap, bp, ep = {}, {}, {}, {}, {}
	local reasons = acc.reasons
	local hasNum, hasState = false, false
	local dt, dm, dp, du, ds = d.t, d.m, d.p, d.u, d.s

	local function segment(u, prev, i)
		local t1, t2 = dt[prev], dt[i]
		if dm[prev] ~= dm[i] then return "none", "mob" end
		if dirty[u] then return "none", "row" end
		local j = bp[u] or 1
		while bt[j] and bt[j] <= t1 do j = j + 1 end
		bp[u] = j
		if bt[j] and bt[j] < t2 then return "none", bk[j] end
		local list = exits[u]
		if list then
			local x = ep[u] or 1
			while list[x] and list[x] <= t1 do x = x + 1 end
			ep[u] = x
			if list[x] and list[x] < t2 then return "none", "exit" end
		end
		if t2 - t1 > Timeline.ESTIMATE_MAX then return "none", "far" end
		if t2 - t1 <= join then return "solid", nil end
		return "dashed", nil
	end
	local function closeGap(u, t)
		local g = openGap[u]
		if not g then return end
		openGap[u] = nil
		local to = min(t, periodEnd(model, g[1], g.m))
		if to > g[1] then
			local list = units[u].unknown
			list[#list + 1] = { g[1], to, g[3], g[4] }
		end
	end

	for i = 1, d.n do
		local u, t, code = du[i], dt[i], ds[i]
		local se = units[u]
		if se then
			-- the next row on the same mob ends an open gap; on another mob it ended with its own mob's period
			local g = openGap[u]
			if g then closeGap(u, g.m == dm[i] and t or model.dur) end
			if NUMBERED[code] then
				hasNum = true
				local k = se.readings + 1
				se.readings = k
				se.rows[k] = i
				local p = dp[i]
				if not se.maxP or p > se.maxP then se.maxP, se.maxT = p, t end
				local prev = lastNum[u]
				if prev then
					se.segs[k], se.why[k] = segment(u, prev, i)
				else
					se.segs[k], se.why[k] = "none", "first"
				end
				lastNum[u], dirty[u] = i, false
			else
				dirty[u] = true
				if STATE_ONLY[code] then
					hasState = true
					se.stateRows = se.stateRows + 1
				elseif ROW_REASON[code] then
					reasons[code] = (reasons[code] or 0) + 1
					openGap[u] = { t, nil, code == "T" and "stale" or "unknown", ROW_REASON[code], m = dm[i] }
				end
			end
		end
		step()
	end
	for u in pairs(openGap) do closeGap(u, model.dur) end
	return hasNum, hasState
end

-- The default series and lanes (§4.7): the player, then who held the mob by time held, then the others by the highest
-- reading (lanes: by the time in WARNING and DANGER); a tie goes to the index.
local function ranked(model, keep, score, limit)
	local list = {}
	for u, se in ipairs(model.units) do
		if keep(se) then list[#list + 1] = se end
	end
	local info = model.info
	local function rank(se) return (info[se.index].me and 1) or (se.held > 0 and 2) or 3 end
	sort(list, function(x, y)
		local rx, ry = rank(x), rank(y)
		if rx ~= ry then return rx < ry end
		if rx == 2 and x.held ~= y.held then return x.held > y.held end
		if rx == 3 then
			local sx, sy = score(x), score(y)
			if sx ~= sy then return sx > sy end
		end
		return x.index < y.index
	end)
	local out = {}
	for i = 1, min(#list, limit) do out[i] = list[i].index end
	return out
end

local function knownStates(se)
	for _, st in ipairs(se.states) do
		if st[3] == "S" or st[3] == "W" or st[3] == "D" then return true end
	end
	return false
end

-- The model of `s` from its decoded rows and events `d` (§4.2). `step` (may be nil) is called once per event and
-- row, so the work can be cut into slices; the result is the same either way.
function Timeline.Compute(s, d, step)
	step = step or noop
	local rec = type(s.rec) == "table" and s.rec or {}
	local hz = (type(rec.hz) == "number" and rec.hz > 0) and rec.hz or 2
	local last = type(s.dur) == "number" and s.dur or 0
	if d.n > 0 then last = max(last, d.t[d.n]) end
	if d.ne > 0 then last = max(last, d.events[d.ne].t) end

	local model = {
		id = s.id, dur = last, state = s.state, ended = s.ended, after = s.after, trunc = s.trunc,
		hz = hz, join = max(30 / hz, 10),
		warning = type(rec.warning) == "number" and rec.warning or nil,
		danger = type(rec.danger) == "number" and rec.danger or nil,
		startMode = VALID_MODE[rec.mode] and rec.mode or nil,
		combat = {}, mobs = {}, modes = {}, gaps = {}, units = {}, events = {}, info = {}, mobInfo = {},
		rows = d.n, ne = d.ne, d = d,
	}
	for i, entry in ipairs(s.units) do
		model.units[i] = newSeries(i)
		model.info[i] = { name = type(entry.name) == "string" and entry.name ~= "" and entry.name or nil,
			token = entry.token, me = entry.me == true or nil, role = entry.role }
	end
	for i, entry in ipairs(s.mobs) do
		model.mobInfo[i] = { name = type(entry.name) == "string" and entry.name ~= "" and entry.name or nil }
	end

	-- The periods, states, holders and crossings by the report's rules (Report.Walk).
	local units, crossingOf = model.units, {}
	local acc = Report.Walk(s, d, step, {
		state = function(u, m, state, from, to)
			local se = units[u]
			if not se then return end
			se.states[#se.states + 1] = { from, to, state, m }
			if state == "W" or state == "D" then se.wd = se.wd + to - from end
		end,
		hold = function(u, m, from, to)
			local se = units[u]
			if not se then return end
			se.holds[#se.holds + 1] = { from, to, m }
			se.held = se.held + to - from
		end,
		cross = function(u, m, t, state, e)
			local se = units[u]
			crossingOf[e] = state
			if se then se.crossings[#se.crossings + 1] = { t, state, m } end
		end,
		watch = function(m, from, to) model.mobs[#model.mobs + 1] = { from, to, m } end,
	})
	for _, p in ipairs(acc.combat) do model.combat[#model.combat + 1] = { p[1], p[2] } end

	local bt, bk, exits = walkEvents(model, d, crossingOf, step)
	local hasNum, hasState = walkRows(model, d, bt, bk, exits, acc, step)

	-- Per unit: states in order, presence on the list, all the unknown time (for the summary).
	local byFrom = function(x, y)
		if x[1] ~= y[1] then return x[1] < y[1] end
		return x[2] < y[2]
	end
	local wholeUnknown = {}
	for _, g in ipairs(model.gaps) do
		if g[3] == "mode" or g[3] == "tick" then wholeUnknown[#wholeUnknown + 1] = { g[1], g[2] } end
	end
	wholeUnknown = I.merge(wholeUnknown)
	for _, se in ipairs(units) do
		sort(se.states, byFrom)
		sort(se.holds, byFrom)
		local present = se.present
		for _, st in ipairs(se.states) do
			local p = present[#present]
			if p and p[3] == st[4] and st[1] <= p[2] then
				if st[2] > p[2] then p[2] = st[2] end
			else
				present[#present + 1] = { st[1], st[2], st[4] }
			end
		end
		local all = {}
		for _, g in ipairs(se.unknown) do all[#all + 1] = { g[1], g[2] } end
		for _, st in ipairs(se.states) do
			if st[3] == "U" then all[#all + 1] = { st[1], st[2] } end
		end
		local listed = {}
		for _, p in ipairs(present) do listed[#listed + 1] = { p[1], p[2] } end
		for _, i in ipairs(I.intersect(I.merge(listed), wholeUnknown)) do all[#all + 1] = i end
		se.unknownAll = I.merge(all)
	end

	-- The outcome (§4.6): from the rows, mixed when the mode changes during combat. A `none` band before the first
	-- readable one is the monitor's first tenth before its first read (the recorder opens with the mode in force):
	-- it stays a gap, but it does not make the session mixed.
	local outcome
	if hasNum and not hasState then outcome = "values"
	elseif hasState and not hasNum then outcome = "state"
	elseif not hasNum and not hasState then outcome = "none"
	else outcome = "mixed" end
	if outcome == "values" or outcome == "state" then
		local seen = false
		for _, band in ipairs(clipTo(model.modes, model.combat, {})) do
			if band[3] == outcome then
				seen = true
			elseif seen or band[3] ~= "none" then
				outcome = "mixed"
				break
			end
		end
	end
	model.outcome = outcome
	acc.reasons = acc.reasons or {}
	model.reason = Report.Prevailing(acc)

	model.series = ranked(model, function(se) return se.readings > 0 end,
		function(se) return se.maxP or 0 end, Timeline.MAX_SERIES)
	model.lanes = ranked(model, knownStates, function(se) return se.wd end, Timeline.MAX_LANES)
	model.startMode = nil
	return model
end

---------------------------------------------------------------------------------------------------------------------
-- Readings, the view and the summary (§4.3, §4.7, §4.8)
---------------------------------------------------------------------------------------------------------------------
-- The k-th reading of unit `u`: percentage, time and category. The top of the column (3843) is a lower bound.
function Timeline.Reading(model, u, k)
	local se = model.units[u]
	local i = se and se.rows[k]
	if not i then return nil end
	local p = model.d.p[i]
	if p >= Session.MAX_N then return p / 10, model.d.t[i], "estimated", true end
	return p / 10, model.d.t[i], "detected", false
end

-- Columns for a chart `width` pixels wide.
function Timeline.Buckets(width)
	local n = floor((width or 0) / Timeline.BUCKET_PX)
	if n > Timeline.MAX_BUCKETS then n = Timeline.MAX_BUCKETS end
	if n < 1 then n = 1 end
	return n
end

-- The view [a, b] widened to MIN_VIEW and kept inside the session.
function Timeline.Clamp(model, a, b)
	a, b = a or 0, b or model.dur
	if a < 0 then a = 0 end
	if b - a < Timeline.MIN_VIEW then b = a + Timeline.MIN_VIEW end
	return a, b
end

-- The column (1 .. buckets) of time `t` in a view [a, a + span].
local function column(t, a, span, buckets)
	local c = floor((t - a) * buckets / span) + 1
	if c > buckets then c = buckets end
	return c
end
Timeline.Column = column

-- Per series of `series` (default the model's) and column: the first, last, lowest and highest reading (positions in
-- the series' rows, 0 for none; the lowest and highest are the earliest of equals), `cut` when a segment inside the
-- column is absent and `dash` when one is an estimate. Writes into `out` (reused: no table made for a view of the same width after the first).
function Timeline.View(model, a, b, buckets, series, out)
	out = out or {}
	a, b = Timeline.Clamp(model, a, b)
	buckets = floor(buckets or 1)
	if buckets > Timeline.MAX_BUCKETS then buckets = Timeline.MAX_BUCKETS end
	if buckets < 1 then buckets = 1 end
	series = series or model.series
	local span = b - a
	local dt, dp = model.d.t, model.d.p
	out.a, out.b, out.buckets, out.n = a, b, buckets, #series
	for j = 1, #series do
		local u = series[j]
		local col = out[j]
		if not col then
			col = { first = {}, last = {}, lo = {}, hi = {}, cut = {}, dash = {} }
			out[j] = col
		end
		col.u = u
		local first, lastc, lo, hi, cut, dash = col.first, col.last, col.lo, col.hi, col.cut, col.dash
		for c = 1, buckets do first[c], lastc[c], lo[c], hi[c], cut[c], dash[c] = 0, 0, 0, 0, false, false end
		local se = model.units[u]
		if se then
			local rows, segs = se.rows, se.segs
			local L, H = 1, se.readings
			while L <= H do                                 -- the first reading not before a
				local mid = floor((L + H) / 2)
				if dt[rows[mid]] < a then L = mid + 1 else H = mid - 1 end
			end
			for k = L, se.readings do
				local i = rows[k]
				local t = dt[i]
				if t > b then break end
				local c = floor((t - a) * buckets / span) + 1
				if c > buckets then c = buckets end
				if first[c] == 0 then
					first[c], lo[c], hi[c] = k, k, k
				else
					local p = dp[i]
					if p < dp[rows[lo[c]]] then lo[c] = k end
					if p > dp[rows[hi[c]]] then hi[c] = k end
					local kind = segs[k]
					if kind == "none" then cut[c] = true elseif kind == "dashed" then dash[c] = true end
				end
				lastc[c] = k
			end
		end
	end
	return out
end

-- The summary of [a, b] (§4.8, calculated): per series the highest reading, the readings, the crossings, the time in
-- WARNING and DANGER and the unknown time (a lower bound when there is some, like the report); the events by kind.
function Timeline.Summary(model, a, b, out, series)
	out = out or {}
	series = series or model.series
	out.a, out.b, out.dur, out.n = a, b, max(b - a, 0), #series
	out.series = out.series or {}
	local dt, dp = model.d.t, model.d.p
	for j, u in ipairs(series) do
		local se = model.units[u]
		local r = out.series[j]
		if not r then r = {} out.series[j] = r end
		r.u, r.readings, r.maxP, r.maxT, r.maxCategory, r.warningCross, r.dangerCross = u, 0, nil, nil, nil, 0, 0
		r.warningTime, r.dangerTime, r.unknownTime, r.lower, r.category = 0, 0, 0, false, "calculated"
		if se then
			for k = 1, se.readings do
				local i = se.rows[k]
				local t = dt[i]
				if t > b then break end
				if t >= a then
					r.readings = r.readings + 1
					if not r.maxP or dp[i] > r.maxP then r.maxP, r.maxT = dp[i], t end
				end
			end
			if r.maxP then r.maxCategory = r.maxP >= Session.MAX_N and "estimated" or "detected" end
			for _, c in ipairs(se.crossings) do
				if c[1] >= a and c[1] <= b then
					if c[2] == "W" then r.warningCross = r.warningCross + 1 else r.dangerCross = r.dangerCross + 1 end
				end
			end
			r.warningTime = overlap(se.states, a, b, 3, "W")
			r.dangerTime = overlap(se.states, a, b, 3, "D")
			r.unknownTime = overlap(se.unknownAll, a, b)
			r.lower = r.unknownTime > 0
			r.category = r.lower and "estimated" or "calculated"
		end
	end
	local kinds = out.events or {}
	out.events = kinds
	for k in pairs(Session.EVENT_KINDS) do kinds[k] = 0 end
	for _, mk in ipairs(model.events) do
		if mk.t >= a and mk.t <= b then kinds[mk.k] = kinds[mk.k] + 1 end
	end
	return out
end

-- The markers of the event track inside [a, b] grouped under MARKER_PX (§4.5), a pure function: out[1 .. out.n] =
-- { x, t, count, top, items } with the most important marker in `top` (the earliest of equals).
function Timeline.Group(markers, a, b, width, out)
	out = out or {}
	local n, span = 0, max(b - a, 1)
	for _, mk in ipairs(markers) do
		if mk.place == "track" and mk.t >= a and mk.t <= b then
			local x = (mk.t - a) * width / span
			local g = out[n]
			if n > 0 and x - g.x < Timeline.MARKER_PX then
				g.count = g.count + 1
				g.items[g.count] = mk
				if mk.prio < g.top.prio then g.top = mk end
			else
				n = n + 1
				g = out[n]
				if not g then
					g = { items = {} }
					out[n] = g
				end
				g.x, g.t, g.count, g.top = x, mk.t, 1, mk
				g.items[1] = mk
			end
		end
	end
	out.n = n
	return out
end

---------------------------------------------------------------------------------------------------------------------
-- Building in slices (§4.2)
---------------------------------------------------------------------------------------------------------------------
local function listen()
	if listening or not ns.Bus then return end
	listening = true
	ns.Bus.On("SESSIONS_CHANGED", function()
		if cache.s and Storage.Get(cache.model.id) ~= cache.s then cache.s, cache.model = nil, nil end
	end)
end

function Timeline.Listening() return listening end

function Timeline.Build(id, done)
	if not on() then done(nil, "off") return end
	listen()
	local s = Storage.Get(id)
	if not s then done(nil, "unknown") return end
	if s.state == "open" or (ns.Recorder and ns.Recorder.current == s) then done(nil, "recording") return end
	if cache.s == s then done(cache.model) return end
	local d, why = Storage.Decode(id)
	if not d then done(nil, why) return end

	local count, slice, ms, frames = 0, Timeline.SLICE, 0, 0
	local co = coroutine.create(function()
		return Timeline.Compute(s, d, function()
			count = count + 1
			if count >= slice then
				count = 0
				coroutine.yield()
			end
		end)
	end)
	local function resume()
		if Storage.Get(id) ~= s then done(nil, "unknown") return end   -- deleted while building
		local before = Compat.ProfileMs()
		local ok, result = coroutine.resume(co)
		local after = Compat.ProfileMs()
		frames = frames + 1
		if before and after then ms = ms + after - before end
		if not ok then
			local Diag = ns.Diagnostics
			Timeline.lastError = Diag and Diag.CleanError(result) or tostring(result)
			done(nil, "error")
		elseif coroutine.status(co) == "dead" then
			cache.s, cache.model = s, result
			local st = Timeline.stats
			st.builds, st.frames, st.ms = st.builds + 1, frames, (before and after) and ms or nil
			done(result)
		elseif not Compat.After(0, resume) then
			resume()
		end
	end
	resume()
end

function Timeline.Cached() return cache.model end

---------------------------------------------------------------------------------------------------------------------
-- Words (ADR 0009; RPL-03: no cause, no hypothesis)
---------------------------------------------------------------------------------------------------------------------
Timeline.REASON_KEYS = {
	secret = "TIMELINE_WHY_SECRET", missing = "TIMELINE_WHY_MISSING", error = "TIMELINE_WHY_ERROR",
	["no-unit"] = "TIMELINE_WHY_NO_UNIT", other = "TIMELINE_WHY_OTHER", stale = "TIMELINE_WHY_STALE",
}
Timeline.NOMOB_KEYS = { none = "TIMELINE_GAP_NOMOB", died = "TIMELINE_GAP_DIED", lost = "TIMELINE_GAP_LOST" }
Timeline.STATE_KEYS = { S = "TIMELINE_STATE_SAFE", W = "TIMELINE_STATE_WARNING", D = "TIMELINE_STATE_DANGER",
	U = "TIMELINE_STATE_UNKNOWN" }
Timeline.LIMIT_KEYS = { r = "TIMELINE_LIMIT_ROWS", e = "TIMELINE_LIMIT_EVENTS", u = "TIMELINE_LIMIT_UNITS",
	m = "TIMELINE_LIMIT_MOBS", t = "TIMELINE_LIMIT_TIME" }
local ALERT_KEY = { w = "REPORT_ALERT_WARNING", d = "REPORT_ALERT_DANGER", a = "REPORT_ALERT_AGGRO",
	m = "REPORT_ALERT_MARGIN", l = "REPORT_ALERT_LOST", p = "REPORT_ALERT_PET", o = "REPORT_ALERT_OTHER" }
local COMBAT_KEY = { ["1"] = "TIMELINE_COMBAT_STARTED", ["2"] = "TIMELINE_NEXT_PULL", r = "TIMELINE_COMBAT_RELOAD" }

-- "1:12.4"
function Timeline.TimeText(t)
	t = floor((t or 0) + 0.5)
	local seconds = floor(t / 10)
	return ("%d:%02d.%d"):format(floor(seconds / 60), seconds % 60, t % 10)
end

-- A value of the column (tenths of a percent); its top is a lower bound.
function Timeline.PercentText(p)
	local text = ns.L.TIMELINE_PERCENT:format(p / 10)
	if p >= Session.MAX_N then return ns.L.REPORT_AT_LEAST:format(text) end
	return text
end

function Timeline.ReasonText(reason)
	local L = ns.L
	return L[Timeline.REASON_KEYS[reason or ""] or "TIMELINE_WHY_OTHER"]
end

function Timeline.UnitName(model, u)
	local info = model.info[u or 0]
	if not info then return ns.L.REPORT_UNKNOWN end
	return info.name or info.token or ns.L.REPORT_UNKNOWN
end

function Timeline.MobName(model, m)
	local info = model.mobInfo[m or 0]
	return info and info.name or ns.L.MON_UNKNOWN_MOB
end

-- The text of a gap (§4.4).
function Timeline.GapText(gap)
	local L, kind = ns.L, gap[3]
	if kind == "unknown" then return L.TIMELINE_GAP_UNKNOWN:format(Timeline.ReasonText(gap[4])) end
	if kind == "stale" then return L.TIMELINE_GAP_STALE end
	if kind == "mode" then return L.TIMELINE_GAP_MODE:format(Timeline.ReasonText(gap[4])) end
	if kind == "nomob" then return L[Timeline.NOMOB_KEYS[gap[4] or ""] or "TIMELINE_GAP_NOMOB"] end
	if kind == "tick" then return L.TIMELINE_GAP_TICK:format(L.REPORT_SECONDS:format((gap[2] - gap[1]) / 10)) end
	if kind == "limit" then return L.TIMELINE_GAP_LIMIT end
	return L.REPORT_UNKNOWN
end

-- The text of a marker (§4.5).
function Timeline.MarkerText(model, mk)
	local L, k = ns.L, mk.k
	if k == "C" then return L[COMBAT_KEY[mk.a] or "TIMELINE_COMBAT_STARTED"] end
	if k == "c" then return L.TIMELINE_COMBAT_ENDED end
	if k == "T" then
		if mk.m > 0 then return L.TIMELINE_TARGET:format(Timeline.MobName(model, mk.m)) end
		return L[Timeline.NOMOB_KEYS[mk.reason or ""] or "TIMELINE_GAP_NOMOB"]
	end
	if k == "S" then
		local name = Timeline.UnitName(model, mk.u)
		if mk.kind == "leave" then return L.TIMELINE_LEFT_LIST:format(name) end
		local text = L.TIMELINE_STATE:format(name, L[Timeline.STATE_KEYS[mk.state] or "TIMELINE_STATE_UNKNOWN"])
		if mk.kind == "cross" then
			if mk.category == "detected" then
				text = L.TIMELINE_WITH:format(text, L.TIMELINE_GAME_STATE)
			elseif model.warning and model.danger then
				text = L.TIMELINE_WITH:format(text, L.TIMELINE_THRESHOLDS:format(model.warning, model.danger))
			end
		end
		return text
	end
	if k == "A" then
		local name = Timeline.UnitName(model, mk.u)
		if mk.kind == "holder" then return L.TIMELINE_HOLDS:format(name) end
		if mk.v > 0 and model.info[mk.v] then return L.TIMELINE_TOOK_FROM:format(name, Timeline.UnitName(model, mk.v)) end
		return L.TIMELINE_TOOK:format(name)
	end
	if k == "D" then
		if mk.u == 0 then return L.TIMELINE_TARGET_DIED end
		if model.info[mk.u] and model.info[mk.u].me then return L.TIMELINE_YOU_DIED end
		return L.TIMELINE_DIED:format(Timeline.UnitName(model, mk.u))
	end
	if k == "L" then
		local text = L.TIMELINE_ALERT:format(L[ALERT_KEY[mk.a] or "REPORT_ALERT_OTHER"])
		if mk.c == "1" then text = L.TIMELINE_MUTED:format(text) end
		return text
	end
	if k == "H" then return L.TIMELINE_COACH:format(mk.rule or "?") end
	if k == "N" then
		if mk.a == "s" then return L.TIMELINE_ENCOUNTER_START end
		if mk.b == "1" then return L.TIMELINE_ENCOUNTER_SUCCESS end
		if mk.b == "0" then return L.TIMELINE_ENCOUNTER_FAILED end
		return L.TIMELINE_ENCOUNTER_END
	end
	if k == "M" then
		if mk.mode == "values" then return L.TIMELINE_MODE_VALUES end
		if mk.mode == "state" then return L.TIMELINE_MODE_STATE end
		return L.TIMELINE_MODE_NONE:format(Timeline.ReasonText(mk.reason))
	end
	if k == "G" then return L.TIMELINE_GAP_TICK:format(L.REPORT_SECONDS:format((mk.n > 0 and mk.n or 0) / 10)) end
	if k == "X" then return L.TIMELINE_INTERRUPTED end
	if k == "Z" then return L.TIMELINE_LIMIT:format(L[Timeline.LIMIT_KEYS[mk.a] or "TIMELINE_LIMIT_ROWS"]) end
	return L.REPORT_UNKNOWN
end

-- The tooltip lines of a group of markers: at most GROUP_LINES, then "and N more".
function Timeline.GroupLines(model, group)
	local lines = {}
	for i = 1, min(group.count, Timeline.GROUP_LINES) do lines[i] = Timeline.MarkerText(model, group.items[i]) end
	if group.count > Timeline.GROUP_LINES then
		lines[#lines + 1] = ns.L.TIMELINE_MORE:format(group.count - Timeline.GROUP_LINES)
	end
	return lines
end

-- The note in place of the chart (§4.6): state only and nothing readable; nil otherwise.
function Timeline.OutcomeText(model)
	local L = ns.L
	if model.outcome == "state" then return L.TIMELINE_OUTCOME_STATE end
	if model.outcome == "none" then return L.TIMELINE_OUTCOME_NONE:format(Timeline.ReasonText(model.reason)) end
	return nil
end

-- The band of a mode in a mixed session (§4.6): "State only from 1:12"; nil for values.
function Timeline.ModeText(band)
	local L = ns.L
	if band[3] == "state" then return L.TIMELINE_STATE_FROM:format(Report.Time(band[1])) end
	if band[3] == "none" then return L.TIMELINE_NONE_FROM:format(Report.Time(band[1])) end
	return nil
end

---------------------------------------------------------------------------------------------------------------------
-- /atw debug, section Timeline and replay (SPEC-05 §9): switches and counts, never a name, a zone or a mob
---------------------------------------------------------------------------------------------------------------------
function Timeline.DebugLines()
	local F = ns.Features
	local lines = {
		("switches: timeline %s, replay %s"):format(F and F.On("timeline") and "on" or "off",
			F and F.On("replay") and "on" or "off"),
	}
	local model = cache.model
	if not model then
		lines[#lines + 1] = "model: none in memory"
	else
		local st = Timeline.stats
		lines[#lines + 1] = ("model: %d rows, %d events, %d series, %d lanes, outcome %s, built in %s over %d frames"):format(
			model.rows, model.ne, #model.series, #model.lanes, model.outcome,
			st.ms and ("%.1f ms"):format(st.ms) or "unknown ms", st.frames)
	end
	if Timeline.PoolLines then Timeline.PoolLines(lines) end   -- the widget's (UI/Timeline.lua)
	if ns.Replay then ns.Replay.DebugLines(lines) end           -- the controller's (Data/Replay.lua)
	if Timeline.lastError then lines[#lines + 1] = "last build error: " .. Timeline.lastError end
	return lines
end

-- The section comes after Recording: it is added at PLAYER_LOGIN, like the recorder's.
local function addSection()
	if ns.addon and ns.addon.AddDebugSection then ns.addon:AddDebugSection("Timeline and replay", Timeline.DebugLines) end
end
if ns.OnEnable then ns.OnEnable(addSection) else addSection() end
if ns.addon then ns.addon.Timeline = Timeline end
