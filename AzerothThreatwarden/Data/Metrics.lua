-- Metrics: the analytics of one recorded session (SPEC-06 §1; ANA-01–ANA-05; ADR 0003, 0018). Lua 5.1, no game API
-- (the next frame and the profiling clock through Core/Compat.lua), nothing saved. Behind the `analytics` switch
-- (ADR 0014). Threatwarden's own.
--
-- A read-only view over the session, like the report and the timeline: everything comes from its rows and events
-- (Storage.Decode), with the report's own cells (Report.Compute) and the report's own pass over the events
-- (Report.Walk), so that a metric the report has is the report's number on the same session (ANA-03). Analytics adds
-- what the report has not (time with a unit in Warning or Danger, changes of the enemy's holder, the threat closest
-- to the tank, unstable intervals, risk situations per minute of known combat) and one stricter rule, ANA-02: under
-- half the samples readable, or the enemy monitored for under half of combat, a metric is "Insufficient data". No
-- ranking of people, no verdict, no trend (ANA-01): the units keep the order player, designated tanks, then index.
--
--   Metrics.Compute(session, decoded, step)  the metrics (§1.7); `step` is called once per event and row of each pass
--   Metrics.Build(id, done)                   Storage.Decode, then Compute in slices of SLICE rows or events per frame;
--                                             done(metrics) or done(nil, "off" / "unknown" / "recording" / "damaged" /
--                                             "error"); at most CACHE results in memory, dropped at SESSIONS_CHANGED
--   Metrics.Key(session, mob)                 the comparison key of an enemy (§2.1): "npc:<n>", "name:<name>:<class>"
--   Metrics.Text / ReasonText / Tooltip / IntervalText   the words (ANALYTICS_* keys)
--
-- A cell has the shape of the report's: { key, category, status ("ok", "na", "insufficient"), value, reason, lower,
-- lowerBy (why it is a lower bound), basis, truncated, until, valid, coverage }. Times are tenths of a second.
local ADDON_NAME, ns = ...
ns = ns or {}
ns.modules = ns.modules or {}

local Metrics = {}
ns.Metrics, ns.modules.Metrics = Metrics, Metrics

local Session, Storage, Compat, Report = ns.Session, ns.Storage, ns.Compat, ns.Report
local type, pairs, ipairs, tostring, floor, sort, remove = type, pairs, ipairs, tostring, math.floor, table.sort, table.remove
local concat = table.concat

Metrics.SLICE = 5000              -- rows or events per frame (§1.7)
Metrics.CACHE = 25                -- sessions kept in memory, the least used goes first
Metrics.MIN_VALID = 50            -- % of valid samples under which a metric is "Insufficient data" (ANA-02)
Metrics.MIN_COVERAGE = 50         -- % of combat with the enemy monitored, the same (ANA-02)
Metrics.MIN_RATE_TIME = 300       -- tenths of known combat under which the risk rate is "Insufficient data"
Metrics.UNSTABLE_WINDOW = 100     -- tenths: K changes within this are an unstable interval (§1.5, Q22)
Metrics.UNSTABLE_MIN = 3          -- changes that make an unstable interval
Metrics.MAX_UNSTABLE = 20         -- intervals listed (the others are counted)
Metrics.SESSION_CELLS = { "context", "valid", "crossings", "stateTime", "holders", "aggroTaken", "maxNotHolding",
	"unstable", "risk", "deaths", "alerts" }
Metrics.UNIT_CELLS = Report.UNIT_CELLS
-- The base of each metric of the threat (§1.2): "state" counts values and state-only samples, "values" values only.
Metrics.BASE = { crossings = "state", stateTime = "state", holders = "state", aggroTaken = "state",
	maxNotHolding = "values", unstable = "state", risk = "state", warningCross = "state", dangerCross = "state",
	warningTime = "state", dangerTime = "state", aggro = "state", maxPct = "values" }

local STATE_ONLY = { a = true, b = true, c = true, d = true }
local MODE_NAME = { v = "values", s = "state", n = "none" }
local VALID_MODE = { values = true, state = true, none = true }

local cache = {}                  -- { id, s, metrics }, the most recently used last
Metrics.stats = { builds = 0, ms = nil, frames = 0 }
local listening = false

local function on()
	local F = ns.Features
	return F ~= nil and F.On("analytics")
end

local function noop() end

local I = Report.Intervals

local function percent(part, total) return floor(part * 100 / total + 0.5) end

-- part / total is under limit % (exact, not rounded: 49.6 % is under 50 %).
local function under(part, total, limit) return part * 100 < limit * total end

local function tick(list, i)
	local v = type(list) == "table" and list[i]
	if type(v) == "number" and v == v and v >= 0 then return v end
	return 0
end

local function copy(t)
	local out = {}
	for k, v in pairs(t) do out[k] = v end
	return out
end

local function cell(key, category, value, extra)
	local out = { key = key, category = category, status = "ok", value = value }
	if extra then for k, v in pairs(extra) do out[k] = v end end
	return out
end

local function missing(key, status, reason, extra)
	local out = { key = key, category = "unknown", status = status, reason = reason }
	if extra then for k, v in pairs(extra) do out[k] = v end end
	return out
end

-- The comparison key of mob `index` of `s` (§2.1): its creature number, else its name and classification, else nil.
function Metrics.Key(s, index)
	local mob = type(s) == "table" and type(s.mobs) == "table" and s.mobs[index or 0]
	if type(mob) ~= "table" then return nil end
	if (type(mob.npc) == "number" or type(mob.npc) == "string") and mob.npc ~= "" then return "npc:" .. tostring(mob.npc) end
	if type(mob.name) == "string" and mob.name ~= "" then
		return "name:" .. mob.name .. ":" .. (type(mob.class) == "string" and mob.class or "")
	end
	return nil
end

---------------------------------------------------------------------------------------------------------------------
-- Unstable intervals (§1.5)
---------------------------------------------------------------------------------------------------------------------
local function unstableIntervals(changes)
	sort(changes, function(a, b)
		if a.t ~= b.t then return a.t < b.t end
		return a.seq < b.seq
	end)
	local K, W, n = Metrics.UNSTABLE_MIN, Metrics.UNSTABLE_WINDOW, #changes
	local found = {}
	for i = 1, n - K + 1 do
		local j = i + K - 1
		local a, b = changes[i], changes[j]
		if a.pull == b.pull and b.t - a.t <= W then
			local last = found[#found]
			if last and last.pull == a.pull and a.t <= last.to then
				if b.t > last.to then last.to = b.t end
				last.hi = j
			else
				found[#found + 1] = { from = a.t, to = b.t, pull = a.pull, lo = i, hi = j }
			end
		end
	end
	local list, total = {}, 0
	for k, iv in ipairs(found) do
		local lo, hi = iv.lo, iv.hi
		-- the changes in the same tenth as an end belong to the interval too
		while lo > 1 and changes[lo - 1].t == iv.from and changes[lo - 1].pull == iv.pull do lo = lo - 1 end
		while hi < n and changes[hi + 1].t == iv.to and changes[hi + 1].pull == iv.pull do hi = hi + 1 end
		local holders, crossings = 0, 0
		for x = lo, hi do
			if changes[x].kind == "holder" then holders = holders + 1 else crossings = crossings + 1 end
		end
		total = total + iv.to - iv.from
		if k <= Metrics.MAX_UNSTABLE then
			list[k] = { from = iv.from, to = iv.to, holders = holders, crossings = crossings,
				moment = iv.from == iv.to or nil }
		end
	end
	return { count = #found, total = total, list = list, changes = n }
end

---------------------------------------------------------------------------------------------------------------------
-- The metrics (§1.2–§1.7)
---------------------------------------------------------------------------------------------------------------------
-- The metrics of `s` from its decoded rows and events `d`. `step` (may be nil) is called once per event and row of
-- every pass, so the work can be cut into slices; the result is the same either way. Nothing of `s` or `d` changes.
function Metrics.Compute(s, d, step)
	step = step or noop
	local report = Report.Compute(s, d, step)
	local sunits = s.units

	-- The report's pass over the events, with the hooks of the metrics.
	local wd, dd, watch, changes, pending = {}, {}, {}, {}, {}
	local holders = { total = 0, tankToTank = 0, toOther = 0, backToTank = 0, other = 0, targets = 0 }
	local seq = 0
	local function change(kind, t, e)
		seq = seq + 1
		local c = { kind = kind, t = t, seq = seq }
		changes[seq] = c
		pending[e] = c
	end
	local acc = Report.Walk(s, d, step, {
		state = function(_, _, state, from, to)
			if state == "W" or state == "D" then wd[#wd + 1] = { from, to } end
			if state == "D" then dd[#dd + 1] = { from, to } end
		end,
		cross = function(_, _, t, _, e) change("cross", t, e) end,
		watch = function(m, from, to) watch[#watch + 1] = { from, to, m } end,
		holder = function(_, _, t, e)
			-- a change only from a known old holder: the first holder of a period (v = 0) is not one
			local v = e.v
			if not (v and v > 0 and sunits[v]) then return end
			holders.total = holders.total + 1
			if e.a == "1" and e.b == "1" then holders.tankToTank = holders.tankToTank + 1
			elseif e.a == "0" then holders.toOther = holders.toOther + 1
			elseif e.a == "1" and e.b == "0" then holders.backToTank = holders.backToTank + 1
			else holders.other = holders.other + 1 end
			change("holder", t, e)
		end,
	})

	-- A short pass of its own over the events: the pull of every change and the mode bands (the outcome, SPEC-05 §4.6).
	local last = report.dur
	local rec = type(s.rec) == "table" and s.rec or {}
	local pull, inFight = 0, false
	local modes, mode, modeFrom, modeReason = {}, VALID_MODE[rec.mode] and rec.mode or nil, 0, nil
	local function closeMode(t)
		if mode and t > modeFrom then modes[#modes + 1] = { modeFrom, t, mode } end
	end
	for _, e in ipairs(d.events) do
		local k = e.k
		if k == "C" then
			if not inFight then inFight, pull = true, pull + 1 end
		elseif k == "c" then
			inFight = false
		elseif k == "M" then
			local name = MODE_NAME[e.a]
			if name then
				local reason = name == "none" and (e.b or "X") or nil
				if name ~= mode or reason ~= modeReason then
					closeMode(e.t)
					mode, modeFrom, modeReason = name, e.t, reason
				end
			end
		end
		local c = pending[e]
		if c then c.pull = pull end
		step()
	end
	closeMode(last)

	-- The rows: what was readable, and the highest percentage of a unit not holding the enemy (codes 0 and 1).
	local hasNum, hasState, nh = false, false, 0
	local best, bestT, bestU, bestM
	local NUMBERED = Session.NUMBERED
	local du, ds, dp, dt, dm = d.u, d.s, d.p, d.t, d.m
	for i = 1, d.n do
		local u, code = du[i], ds[i]
		if sunits[u] then
			if NUMBERED[code] then
				hasNum = true
				if code == "0" or code == "1" then
					nh = nh + 1
					local p = dp[i]
					if not best or p > best then best, bestT, bestU, bestM = p, dt[i], u, dm[i] end
				end
			elseif STATE_ONLY[code] then
				hasState = true
			end
		end
		step()
	end

	-- The outcome: from the rows, mixed when the readable mode changes during combat (as the timeline).
	local outcome
	if hasNum and not hasState then outcome = "values"
	elseif hasState and not hasNum then outcome = "state"
	elseif not hasNum and not hasState then outcome = "none"
	else outcome = "mixed" end
	if outcome == "values" or outcome == "state" then
		local seen = false
		for _, band in ipairs(modes) do
			for _, p in ipairs(acc.combat) do
				if band[2] > p[1] and band[1] < p[2] then
					if band[3] == outcome then
						seen = true
					elseif seen or band[3] ~= "none" then
						outcome = "mixed"
					end
				end
			end
		end
	end

	-- The bases (§1.2): combat, monitored, the enemy's unknown time, known time, coverage, valid samples.
	local combatList = {}
	for _, p in ipairs(acc.combat) do combatList[#combatList + 1] = { p[1], p[2] } end
	local combat = I.length(I.merge(combatList))
	local watched = {}
	for _, w in ipairs(watch) do watched[#watched + 1] = { w[1], w[2] } end
	watched = I.merge(watched)
	local holes = {}
	for _, h in ipairs(acc.none) do holes[#holes + 1] = { h[1], h[2] } end
	for _, h in ipairs(acc.gaps) do holes[#holes + 1] = { h[1], h[2] } end
	local unknownMob = I.length(I.intersect(watched, I.merge(holes)))
	local known = I.length(watched) - unknownMob
	local coverage = combat > 0 and percent(known, combat) or nil

	local q = type(s.q) == "table" and s.q or {}
	local V, S, X = 0, 0, 0
	for i = 1, #sunits do V, S, X = V + tick(q.v, i), S + tick(q.s, i), X + tick(q.x, i) end
	local N = V + S + X
	local valid = N > 0 and { state = percent(V + S, N), values = percent(V, N) } or nil

	local readable = report.readable
	local rows = report.rows
	local prevailing = rows.tanks.reason or "other"
	local interrupted = s.state == "interrupted"
	local eventsCut = acc.eventsCut == true
	local sessionLower = unknownMob > 0 or eventsCut
	local function lowerBy(extra)
		local by = {}
		if unknownMob > 0 then by.unknown = true end
		if eventsCut then by.events = true end
		if extra then for k in pairs(extra) do by[k] = true end end
		return next(by) and by or nil
	end

	-- §1.3 points 1 and 3 for a metric of the session: nil when it may be computed, else its cell.
	local function gate(key, base)
		local extra = { basis = nil, valid = valid and valid[base] or nil, coverage = coverage }
		if base == "values" then
			if not readable.values then
				return missing(key, "na", readable.state and "state-only" or prevailing, extra)
			end
		elseif not readable.any then
			return missing(key, "na", prevailing, extra)
		end
		if N == 0 then return missing(key, "insufficient", "no-ticks", extra) end
		if under(base == "values" and V or V + S, N, Metrics.MIN_VALID) then
			return missing(key, "insufficient", "low-valid", extra)
		end
		if combat == 0 or under(known, combat, Metrics.MIN_COVERAGE) then
			return missing(key, "insufficient", "little-monitored", extra)
		end
		return nil
	end
	local function withBase(c, base)
		c.valid, c.coverage = valid and valid[base] or nil, coverage
		return c
	end

	-- The units, in the order player, designated tanks, then index (ANA-01: never by a metric).
	local byIndex = {}
	for _, u in ipairs(report.units) do byIndex[u.index] = u end
	local function unitValid(index, base)
		local qv, qs, qx = tick(q.v, index), tick(q.s, index), tick(q.x, index)
		local total = qv + qs + qx
		if total == 0 then return false, "no-ticks", nil end
		local part = base == "values" and qv or qv + qs
		local pct = percent(part, total)
		if under(part, total, Metrics.MIN_VALID) then return false, "low-valid", pct end
		return true, nil, pct
	end
	local units = {}
	for i in ipairs(sunits) do
		local ru = byIndex[i]
		local cells = {}
		for _, key in ipairs(Metrics.UNIT_CELLS) do
			local rc = ru.cells[key]
			local c = copy(rc)
			local base = Metrics.BASE[key]
			if base and c.status == "ok" then
				local ok, why, pct = unitValid(i, base)
				c.valid = pct
				if not ok then c = missing(key, "insufficient", why, { valid = pct }) end
			end
			cells[key] = c
		end
		units[#units + 1] = { index = i, name = ru.name, class = ru.class, role = ru.role, token = ru.token,
			me = ru.me, pet = ru.pet, status = ru.status, reason = ru.reason, cells = cells }
	end
	local function rank(u) return (u.me and 1) or (u.role == "TANK" and 2) or 3 end
	sort(units, function(a, b)
		if rank(a) ~= rank(b) then return rank(a) < rank(b) end
		return a.index < b.index
	end)

	-- The basis of the state metrics of the session: the units' (thresholds, game states or both).
	local game, thresholds = false, false
	for _, u in ipairs(units) do
		local b = u.cells.warningCross.basis
		if b == "game" or b == "mixed" then game = true end
		if b == "thresholds" or b == "mixed" then thresholds = true end
	end
	local basis = (game and thresholds and "mixed") or (game and "game") or (thresholds and "thresholds")
		or (outcome == "state" and "game") or (outcome == "values" and "thresholds") or nil

	local cells = {}
	local metrics = {
		id = s.id, started = s.started, zone = s.zone, outcome = outcome, state = s.state, ended = s.ended,
		after = s.after, trunc = s.trunc, eventsCut = eventsCut or nil, group = s.group, inst = s.inst, diff = s.diff,
		rec = copy(rec), dur = last, recordedUntil = interrupted and last or nil, combat = combat, known = known,
		unknownTime = unknownMob, coverage = coverage, valid = valid, cells = cells, units = units, mobs = {},
	}
	for i, entry in ipairs(s.mobs) do
		metrics.mobs[i] = { index = i, name = type(entry.name) == "string" and entry.name ~= "" and entry.name or nil,
			class = entry.class }
	end
	for _, u in ipairs(units) do
		if u.me then metrics.role = u.role end
	end
	local mobRow = rows.mob
	metrics.mob = mobRow.value and mobRow.value.index or nil
	metrics.key = Metrics.Key(s, metrics.mob)

	-- context (detected; the duration at least in an interrupted session, as the report)
	local dv = rows.duration.value
	cells.context = cell("context", "detected", {
		dur = dv.dur, fight = dv.fight, pulls = dv.pulls, mob = metrics.mob,
		mobName = mobRow.value and mobRow.value.name or nil, mobClass = mobRow.value and mobRow.value.class or nil,
		others = mobRow.value and mobRow.value.others or 0, encounter = mobRow.value and mobRow.value.encounter or nil,
		group = s.group, inst = s.inst, diff = s.diff, zone = s.zone, units = #sunits, rec = metrics.rec,
		outcome = outcome, state = s.state, ended = s.ended, after = s.after,
	}, { lower = interrupted or nil, ["until"] = metrics.recordedUntil })

	-- valid (calculated): the report's data quality and the coverage
	local quality = rows.quality
	if quality.status ~= "ok" then
		cells.valid = missing("valid", "insufficient", "no-ticks", { coverage = coverage })
	else
		local qv = quality.value
		cells.valid = cell("valid", "calculated", { values = qv.values, state = qv.state, unknown = qv.unknown,
			ticks = qv.ticks, coverage = coverage, known = known, combat = combat },
			{ reason = quality.reason, truncated = s.trunc and true or nil, ["until"] = s.trunc })
	end

	-- crossings: the sum over the units whose report cell (and ANA-02 of the unit) is ok
	local crossings = gate("crossings", "state")
	if not crossings then
		local W, D, counted, excluded, partial = 0, 0, 0, 0, false
		for _, u in ipairs(units) do
			local wc, dc = u.cells.warningCross, u.cells.dangerCross
			if wc.status == "ok" and dc.status == "ok" then
				W, D, counted = W + wc.value, D + dc.value, counted + 1
				if wc.lower then partial = true end
			else
				excluded = excluded + 1
			end
		end
		if counted == 0 then
			crossings = withBase(missing("crossings", "insufficient", "no-units"), "state")
		else
			local by = lowerBy({ units = excluded > 0 or nil, partial = partial or nil })
			crossings = withBase(cell("crossings", by and "estimated" or "calculated",
				{ warning = W, danger = D, units = counted, excluded = excluded },
				{ lower = by and true or nil, lowerBy = by }), "state")
		end
	end
	crossings.basis = basis
	cells.crossings = crossings

	-- stateTime: the union of the state intervals of all units (already cut to combat and the monitored enemy)
	local stateTime = gate("stateTime", "state")
	if not stateTime then
		if known < Report.MIN_KNOWN then
			stateTime = withBase(missing("stateTime", "insufficient", "little-known"), "state")
		else
			local by = lowerBy()
			stateTime = withBase(cell("stateTime", by and "estimated" or "calculated",
				{ warningAny = I.length(I.merge(wd)), dangerAny = I.length(I.merge(dd)),
					unknownTime = unknownMob > 0 and unknownMob or nil },
				{ lower = by and true or nil, lowerBy = by }), "state")
		end
	end
	stateTime.basis = basis
	cells.stateTime = stateTime

	-- holders: who took the enemy from a known holder, split three ways; the monitored enemy's own changes as context
	local prevW
	for _, w in ipairs(watch) do
		if prevW and prevW[3] ~= w[3] then
			for _, p in ipairs(acc.combat) do
				if prevW[1] >= p[1] and w[2] <= p[2] then holders.targets = holders.targets + 1 break end
			end
		end
		prevW = w
	end
	local held = gate("holders", "state")
	if not held and rows.tankChanges.status ~= "ok" then
		held = missing("holders", rows.tankChanges.status, rows.tankChanges.reason)
	end
	if not held then
		local by = lowerBy()
		held = withBase(cell("holders", by and "estimated" or "detected", holders,
			{ lower = by and true or nil, lowerBy = by }), "state")
	end
	cells.holders = held

	-- aggroTaken: the report's aggro losses (every A to a non-tank, the first holder too)
	local taken = gate("aggroTaken", "state")
	if not taken and rows.aggroLosses.status ~= "ok" then
		taken = missing("aggroTaken", rows.aggroLosses.status, rows.aggroLosses.reason)
	end
	if not taken then
		local by = lowerBy()
		taken = withBase(cell("aggroTaken", by and "estimated" or "detected", #rows.aggroLosses.value,
			{ lower = by and true or nil, lowerBy = by }), "state")
	end
	cells.aggroTaken = taken

	-- maxNotHolding: the highest percentage of a unit that did not hold the enemy (rows 0 and 1)
	local closest = gate("maxNotHolding", "values")
	if not closest then
		if nh < Report.MIN_ROWS then
			closest = withBase(missing("maxNotHolding", "insufficient", "few-not-holding"), "values")
		else
			local cap = best >= Session.MAX_N
			closest = withBase(cell("maxNotHolding", cap and "estimated" or "detected",
				{ pct = best / 10, t = bestT, unit = bestU, mob = bestM, rows = nh },
				{ lower = cap or nil, lowerBy = cap and { cap = true } or nil, truncated = s.trunc and true or nil,
					["until"] = s.trunc }), "values")
		end
	end
	cells.maxNotHolding = closest

	-- unstable: K changes within W in the same pull (§1.5)
	local unstable = gate("unstable", "state")
	if not unstable then
		local by = lowerBy()
		unstable = withBase(cell("unstable", by and "estimated" or "calculated", unstableIntervals(changes),
			{ lower = by and true or nil, lowerBy = by }), "state")
	end
	unstable.basis = basis
	cells.unstable = unstable

	-- risk: entries into Danger of the counted units plus the enemy taken by a non-tank, per minute of known combat
	local risk = gate("risk", "state")
	if not risk then
		if crossings.status ~= "ok" then
			risk = withBase(missing("risk", crossings.status, crossings.reason), "state")
		elseif taken.status ~= "ok" then
			risk = withBase(missing("risk", taken.status, taken.reason), "state")
		elseif known < Metrics.MIN_RATE_TIME then
			risk = withBase(missing("risk", "insufficient", "short-known"), "state")
		else
			local situations = crossings.value.danger + taken.value
			local by
			if crossings.lowerBy or taken.lowerBy then
				by = {}
				for k in pairs(crossings.lowerBy or {}) do by[k] = true end
				for k in pairs(taken.lowerBy or {}) do by[k] = true end
			end
			risk = withBase(cell("risk", by and "estimated" or "calculated",
				{ situations = situations, perMinute = floor(situations * 6000 / known + 0.5) / 10, known = known },
				{ lower = by and true or nil, lowerBy = by }), "state")
		end
	end
	risk.basis = basis
	cells.risk = risk

	-- deaths and alerts: the report's rows, as context
	cells.deaths = copy(rows.deaths)
	cells.alerts = copy(rows.alerts)
	return metrics
end

---------------------------------------------------------------------------------------------------------------------
-- Building in slices, the cache (§1.7)
---------------------------------------------------------------------------------------------------------------------
local function find(id, s)
	for i, entry in ipairs(cache) do
		if entry.id == id then
			if entry.s == s then
				remove(cache, i)
				cache[#cache + 1] = entry
				return entry.metrics
			end
			remove(cache, i)
			return nil
		end
	end
	return nil
end

local function store(id, s, metrics)
	for i, entry in ipairs(cache) do
		if entry.id == id then remove(cache, i) break end
	end
	cache[#cache + 1] = { id = id, s = s, metrics = metrics }
	while #cache > Metrics.CACHE do remove(cache, 1) end
end

local function listen()
	if listening or not ns.Bus then return end
	listening = true
	ns.Bus.On("SESSIONS_CHANGED", function()
		for i = #cache, 1, -1 do
			if Storage.Get(cache[i].id) ~= cache[i].s then remove(cache, i) end
		end
	end)
end

function Metrics.Listening() return listening end

function Metrics.Build(id, done)
	if not on() then done(nil, "off") return end
	listen()
	local s = Storage.Get(id)
	if not s then done(nil, "unknown") return end
	if s.state == "open" or (ns.Recorder and ns.Recorder.current == s) then done(nil, "recording") return end
	local hit = find(id, s)
	if hit then done(hit) return end
	local d, why = Storage.Decode(id)
	if not d then done(nil, why) return end

	local count, slice, ms, frames = 0, Metrics.SLICE, 0, 0
	local co = coroutine.create(function()
		return Metrics.Compute(s, d, function()
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
			Metrics.lastError = Diag and Diag.CleanError(result) or tostring(result)
			done(nil, "error")
		elseif coroutine.status(co) == "dead" then
			store(id, s, result)
			local st = Metrics.stats
			st.builds, st.frames, st.ms = st.builds + 1, frames, (before and after) and ms or nil
			done(result)
		elseif not Compat.After(0, resume) then
			resume()
		end
	end
	resume()
end

-- The metrics of session `id` kept in memory, nil without them (or when the session is not the same table).
function Metrics.Cached(id)
	for _, entry in ipairs(cache) do
		if entry.id == id and Storage.Get(id) == entry.s then return entry.metrics end
	end
	return nil
end

function Metrics.CacheSize() return #cache end

---------------------------------------------------------------------------------------------------------------------
-- Words (ADR 0009; ANA-01: no ranking, no merit, no blame, no trend; ANA-04: the category of every value)
---------------------------------------------------------------------------------------------------------------------
local STATUS_KEY = { na = "REPORT_NA", insufficient = "REPORT_INSUFFICIENT", unknown = "REPORT_UNKNOWN" }
Metrics.REASON_KEYS = {
	["low-valid"] = "ANALYTICS_WHY_LOW_VALID", ["little-monitored"] = "ANALYTICS_WHY_LITTLE_MONITORED",
	["no-units"] = "ANALYTICS_WHY_NO_UNITS", ["few-not-holding"] = "ANALYTICS_WHY_FEW_NOT_HOLDING",
	["short-known"] = "ANALYTICS_WHY_SHORT_KNOWN",
}
Metrics.METRIC_KEYS = {
	context = "ANALYTICS_METRIC_CONTEXT", valid = "ANALYTICS_METRIC_VALID", crossings = "ANALYTICS_METRIC_CROSSINGS",
	stateTime = "ANALYTICS_METRIC_STATE_TIME", holders = "ANALYTICS_METRIC_HOLDERS",
	aggroTaken = "ANALYTICS_METRIC_AGGRO_TAKEN", maxNotHolding = "ANALYTICS_METRIC_CLOSEST",
	unstable = "ANALYTICS_METRIC_UNSTABLE", risk = "ANALYTICS_METRIC_RISK", deaths = "REPORT_METRIC_DEATHS",
	alerts = "REPORT_METRIC_ALERTS",
}
Metrics.ABOUT_KEYS = {
	context = "ANALYTICS_ABOUT_CONTEXT", valid = "ANALYTICS_ABOUT_VALID", crossings = "ANALYTICS_ABOUT_CROSSINGS",
	stateTime = "ANALYTICS_ABOUT_STATE_TIME", holders = "ANALYTICS_ABOUT_HOLDERS",
	aggroTaken = "ANALYTICS_ABOUT_AGGRO_TAKEN", maxNotHolding = "ANALYTICS_ABOUT_CLOSEST",
	unstable = "ANALYTICS_ABOUT_UNSTABLE", risk = "ANALYTICS_ABOUT_RISK", deaths = "ANALYTICS_ABOUT_DEATHS",
	alerts = "ANALYTICS_ABOUT_ALERTS",
}
local LOWER_KEYS = { { "unknown", "ANALYTICS_LOWER_UNKNOWN" }, { "events", "ANALYTICS_LOWER_EVENTS" },
	{ "units", "ANALYTICS_LOWER_UNITS" }, { "partial", "ANALYTICS_LOWER_PARTIAL" }, { "cap", "ANALYTICS_LOWER_CAP" } }
local CATEGORY_KEY = { detected = "CAT_DETECTED", calculated = "CAT_CALCULATED", estimated = "CAT_ESTIMATED" }
local CLASS_KEY = { elite = "MON_CLASS_ELITE", rare = "MON_CLASS_RARE", rareelite = "MON_CLASS_RAREELITE",
	worldboss = "MON_CLASS_BOSS" }

local function atLeast(text, lower)
	if lower then return ns.L.REPORT_AT_LEAST:format(text) end
	return text
end

function Metrics.UnitName(metrics, index)
	return Report.UnitName(metrics, index)
end

-- "0:12–0:19 · 3 changes" or "at 1:12 · 3 changes"
function Metrics.IntervalText(iv)
	local L = ns.L
	local n = iv.holders + iv.crossings
	if iv.moment then return L.ANALYTICS_MOMENT:format(Report.Time(iv.from), n) end
	return L.ANALYTICS_INTERVAL:format(Report.Time(iv.from), Report.Time(iv.to), n)
end

local words = {}

function words.context(metrics, c)
	local L, v = ns.L, c.value
	local parts = { atLeast(Report.Time(v.dur), c.lower) }
	if v.fight then parts[#parts + 1] = L.REPORT_IN_COMBAT:format(atLeast(Report.Time(v.fight), c.lower)) end
	if v.pulls > 1 then parts[#parts + 1] = L.REPORT_PULLS:format(v.pulls) end
	parts[#parts + 1] = v.mobName or L.MON_UNKNOWN_MOB
	if CLASS_KEY[v.mobClass or ""] then parts[#parts + 1] = L[CLASS_KEY[v.mobClass]] end
	return concat(parts, " · ")
end

function words.valid(_, c)
	local L, v = ns.L, c.value
	local text = L.REPORT_QUALITY:format(v.values, v.state, v.unknown)
	if v.coverage then text = text .. " · " .. L.ANALYTICS_COVERAGE:format(v.coverage) end
	return text
end

function words.crossings(_, c)
	local L, v = ns.L, c.value
	local text = L.ANALYTICS_CROSSINGS:format(atLeast(("%d"):format(v.warning), c.lower),
		atLeast(("%d"):format(v.danger), c.lower))
	if v.excluded == 1 then text = text .. " · " .. L.ANALYTICS_NOT_COUNTED_ONE
	elseif v.excluded > 1 then text = text .. " · " .. L.ANALYTICS_NOT_COUNTED:format(v.excluded) end
	return text
end

function words.stateTime(_, c)
	local v = c.value
	return ns.L.ANALYTICS_STATE_TIME:format(atLeast(Report.Time(v.warningAny), c.lower),
		atLeast(Report.Time(v.dangerAny), c.lower))
end

function words.holders(_, c)
	local L, v = ns.L, c.value
	local text
	if v.total == 0 then
		text = L.ANALYTICS_HOLDERS_NONE
	else
		text = L.ANALYTICS_HOLDERS:format(atLeast(("%d"):format(v.total), c.lower), v.tankToTank, v.toOther,
			v.backToTank)
	end
	if v.targets > 0 then text = text .. " · " .. L.ANALYTICS_TARGETS:format(v.targets) end
	return text
end

function words.aggroTaken(_, c)
	return atLeast(("%d"):format(c.value), c.lower)
end

function words.maxNotHolding(metrics, c)
	local L, v = ns.L, c.value
	return L.ANALYTICS_CLOSEST:format(Report.UnitName(metrics, v.unit),
		atLeast(L.TIMELINE_PERCENT:format(v.pct), c.lower), Report.Time(v.t))
end

function words.unstable(_, c)
	local L, v = ns.L, c.value
	if v.count == 0 then return L.ANALYTICS_UNSTABLE_NONE end
	local span = atLeast(Report.Time(v.total), c.lower)
	if v.count == 1 then return L.ANALYTICS_UNSTABLE_ONE:format(span) end
	return L.ANALYTICS_UNSTABLE:format(atLeast(("%d"):format(v.count), c.lower), span)
end

function words.risk(_, c)
	local v = c.value
	return ns.L.ANALYTICS_RISK:format(atLeast(("%d"):format(v.situations), c.lower),
		atLeast(("%.1f"):format(v.perMinute), c.lower))
end

-- The text of a cell of `metrics`: its value, or Not available / Insufficient data.
function Metrics.Text(metrics, c)
	if c.status ~= "ok" then return ns.L[STATUS_KEY[c.status] or "REPORT_UNKNOWN"] end
	if c.key == "deaths" or c.key == "alerts" then return Report.CellText(metrics, c) end
	local fn = words[c.key]
	return fn and fn(metrics, c) or ns.L.REPORT_UNKNOWN
end

-- The short reason of a cell that is not ok ("Fewer than half the samples readable: 38 %"), nil without one.
function Metrics.ReasonText(c)
	local L, reason = ns.L, c.reason
	if reason == "low-valid" then return L.ANALYTICS_WHY_LOW_VALID:format(c.valid or 0) end
	if reason == "little-monitored" then return L.ANALYTICS_WHY_LITTLE_MONITORED:format(c.coverage or 0) end
	local key = Metrics.REASON_KEYS[reason or ""]
	if key then return L[key] end
	return Report.ReasonText(reason)
end

-- The tooltip of a cell (§1.3): what it measures, the category, the basis, the valid samples and the coverage, the
-- reason, why it is a lower bound, how far the data go.
function Metrics.Tooltip(metrics, c)
	local L, lines = ns.L, {}
	local about = Metrics.ABOUT_KEYS[c.key]
	if about then lines[#lines + 1] = L[about] end
	if CATEGORY_KEY[c.category] then lines[#lines + 1] = L.ANALYTICS_TIP_CATEGORY:format(L[CATEGORY_KEY[c.category]]) end
	local basis = Report.BasisText(metrics, c.basis)
	if basis then lines[#lines + 1] = basis end
	if c.valid then lines[#lines + 1] = L.ANALYTICS_TIP_VALID:format(c.valid) end
	if c.coverage then lines[#lines + 1] = L.ANALYTICS_COVERAGE:format(c.coverage) end
	if c.status ~= "ok" then
		local reason = Metrics.ReasonText(c)
		if reason then lines[#lines + 1] = reason end
		if c.reason == "low-valid" or c.reason == "little-monitored" then lines[#lines + 1] = L.ANALYTICS_TIP_STRICTER end
	elseif c.reason then
		local reason = Metrics.ReasonText(c)
		if reason then lines[#lines + 1] = reason end
	end
	if c.lower and c.lowerBy then
		for _, pair in ipairs(LOWER_KEYS) do
			if c.lowerBy[pair[1]] then lines[#lines + 1] = L[pair[2]] end
		end
	end
	if metrics.recordedUntil then lines[#lines + 1] = L.REPORT_RECORDED_UNTIL:format(Report.Time(metrics.recordedUntil)) end
	if c.truncated and metrics.trunc then lines[#lines + 1] = L.REPORT_TRUNCATED:format(Report.Time(metrics.trunc)) end
	return lines
end

---------------------------------------------------------------------------------------------------------------------
-- /atw debug, section Analytics and export (SPEC-06 §5): switches and counts, never a name, a zone or an enemy
---------------------------------------------------------------------------------------------------------------------
function Metrics.DebugLines()
	local F = ns.Features
	local lines = {
		("switches: analytics %s, export %s"):format(F and F.On("analytics") and "on" or "off",
			F and F.On("export") and "on" or "off"),
	}
	local st = Metrics.stats
	lines[#lines + 1] = ("metrics cache: %d of %d sessions"):format(#cache, Metrics.CACHE)
	if st.builds == 0 then
		lines[#lines + 1] = "metrics last build: none"
	else
		lines[#lines + 1] = ("metrics last build: %s over %d frames, %d builds"):format(
			st.ms and ("%.1f ms"):format(st.ms) or "unknown ms", st.frames, st.builds)
	end
	if Metrics.lastError then lines[#lines + 1] = "metrics last build error: " .. Metrics.lastError end
	if Metrics.ExtraLines then   -- the comparison's (Data/Compare.lua)
		for _, line in ipairs(Metrics.ExtraLines()) do lines[#lines + 1] = line end
	end
	return lines
end

-- The section comes after Timeline and replay: it is added at PLAYER_LOGIN, like theirs.
local function addSection()
	if ns.addon and ns.addon.AddDebugSection then ns.addon:AddDebugSection("Analytics and export", Metrics.DebugLines) end
end
if ns.OnEnable then ns.OnEnable(addSection) else addSection() end
if ns.addon then ns.addon.Metrics = Metrics end
