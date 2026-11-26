-- Report: the combat report of a recorded session (SPEC-05 §3; REC-10, REC-11; ADR 0003, 0016). Lua 5.1, no game API
-- (the next frame through Core/Compat.lua) and nothing saved but the summary `sum` of Data/Storage.lua. Behind the
-- `reports` switch (ADR 0014). Threatwarden's own.
--
-- Everything comes from the rows and the events of the session only, so the same data give the same report. A metric
-- that cannot be said is not invented: it is "na" (Not available: the client never gave it in this session),
-- "insufficient" (under MIN_ROWS useful rows or under 1 s of known state) or "unknown" (a name or a mob not readable),
-- with a reason code. With unknown time the counts and times of a unit are lower bounds (category estimated). A
-- report never says why something happened: at most "+N points in the 3 s before" an aggro loss (calculated).
--
--   Report.Compute(session, decoded, step)  the report table (one pass; `step` is called once per row and event)
--   Report.Build(id, done)                  Storage.Decode, then Compute in slices of SLICE rows or events per frame;
--                                           done(report) or done(nil, "off" / "unknown" / "recording" / "damaged" /
--                                           "error"); the last report is kept in memory
--   Report.Summary(session)                 `sum` (SPEC-02 §4.1) for the list, nil while the switch is off
--   Report.Walk(session, decoded, step, hooks)  the pass over the events alone (periods, states, holders, crossings),
--                                           with optional hooks, so that Data/Timeline.lua (M5.2) uses the same
--                                           functions: hooks.state(u, m, state, from, to), hooks.hold(u, m, from, to),
--                                           hooks.cross(u, m, t, state, event), hooks.watch(m, from, to)
--   Report.Intervals, Report.Prevailing(acc) the interval helpers and the prevailing reason, shared with the timeline
--   Report.CellText(report, cell) ...       the words of the report, for the Reports tab (M4.5)
--
-- A cell is { key, category, status ("ok", "na", "insufficient", "unknown"), value, reason, lower, unknownTime
-- (tenths), basis ("thresholds", "game", "mixed"), truncated }. report.rows holds the cells of the session,
-- report.units one entry per unit with its cells in `cells`. Times are tenths of a second from the start.
local ADDON_NAME, ns = ...
ns = ns or {}
ns.modules = ns.modules or {}

local Report = {}
ns.Report, ns.modules.Report = Report, Report

local Session, Storage, Compat = ns.Session, ns.Storage, ns.Compat
local type, pairs, ipairs, tostring, floor, max, min, sort = type, pairs, ipairs, tostring, math.floor, math.max, math.min, table.sort
local concat = table.concat

Report.SLICE = 5000                 -- rows or events per frame (§3.4)
Report.MIN_ROWS = 3                 -- useful readings below which a unit metric is "Insufficient data" (REC-10)
Report.MIN_KNOWN = 10               -- tenths of known state below which a state metric is "Insufficient data"
Report.POINTS_WINDOW = 30           -- tenths before an aggro loss for "+N points in the 3 s before"
Report.DEATH_WINDOW = 30            -- tenths: two death events of one unit this close are one death
Report.SESSION_ROWS = { "duration", "mob", "tanks", "tankChanges", "aggroLosses", "quality", "deaths", "alerts" }
Report.UNIT_CELLS = { "warningCross", "dangerCross", "warningTime", "dangerTime", "maxPct", "aggro", "quality" }

local LEVEL = { S = 1, W = 2, D = 3 }
local WORST = { U = 1, S = 2, W = 3, D = 4 }
-- Codes of the rows without a readable value (SPEC-02 §4.2) and of the reasons of M (SPEC-02 §4.3).
local ROW_REASON = { S = "secret", E = "error", M = "missing", U = "no-unit", X = "other", T = "stale" }
local ROW_REASON_ORDER = { "S", "E", "M", "U", "X", "T" }
local MODE_REASON = { S = "secret", E = "error", M = "missing", U = "no-unit", T = "stale", X = "other" }
local STATE_ONLY = { a = true, b = true, c = true, d = true }
local ALERT_NAME = { w = "warning", d = "danger", a = "aggro", m = "margin", l = "lost", p = "pet", o = "other" }
Report.ALERT_ORDER = { "warning", "danger", "aggro", "margin", "lost", "pet", "other" }

local cache = { s = nil, report = nil }

local function on()
	local F = ns.Features
	return F ~= nil and F.On("reports")
end

---------------------------------------------------------------------------------------------------------------------
-- Intervals (tenths): lists of { from, to }
---------------------------------------------------------------------------------------------------------------------
local function add(list, from, to)
	if to > from then list[#list + 1] = { from, to } end
end

local function merge(list)
	sort(list, function(a, b) return a[1] < b[1] end)
	local out = {}
	for _, i in ipairs(list) do
		local last = out[#out]
		if last and i[1] <= last[2] then
			if i[2] > last[2] then last[2] = i[2] end
		else
			out[#out + 1] = { i[1], i[2] }
		end
	end
	return out
end

local function intersect(a, b)
	local out, i, j = {}, 1, 1
	while i <= #a and j <= #b do
		local from, to = max(a[i][1], b[j][1]), min(a[i][2], b[j][2])
		add(out, from, to)
		if a[i][2] < b[j][2] then i = i + 1 else j = j + 1 end
	end
	return out
end

local function length(list)
	local total = 0
	for _, i in ipairs(list) do total = total + i[2] - i[1] end
	return total
end

---------------------------------------------------------------------------------------------------------------------
-- The pass over the events
---------------------------------------------------------------------------------------------------------------------
local function newUnit(index, entry)
	return {
		index = index, name = entry.name, class = entry.class, role = entry.role, token = entry.token,
		me = entry.me == true, pet = entry.pet == true,
		numbered = {},              -- indexes of the rows with a number
		stateRows = 0, unknownRows = 0, max = nil, maxAt = nil, maxMob = nil,
		inList = {}, unknownState = {}, warning = {}, danger = {}, safe = {},
		warningCross = 0, dangerCross = 0, aggro = 0, game = false, thresholds = false, worst = nil,
	}
end

-- Walks the events: combat periods, mob periods, mode, gaps, states, holders, crossings, deaths, alerts, encounters.
local function walkEvents(s, d, acc, step)
	local units, mobs = acc.units, acc.mobs
	local inFight, curMob, mode = false, 0, nil
	local fightFrom, monFrom, noneFrom = 0, nil, nil
	local open = {}                     -- unit * 100 + mob -> { u, m, state, from }
	local holders = {}                  -- mob -> { u, from }
	local lastKnown = {}                -- unit * 100 + mob -> level of the last known state
	local deathAt = {}

	local hooks = acc.hooks or {}
	local function closeState(key, t)
		local o = open[key]
		if not o then return end
		open[key] = nil
		local u = units[o.u]
		if t <= o.from then return end
		add(u.inList, o.from, t)
		if o.state == "W" then add(u.warning, o.from, t)
		elseif o.state == "D" then add(u.danger, o.from, t)
		elseif o.state == "S" then add(u.safe, o.from, t)
		else add(u.unknownState, o.from, t) end
		if hooks.state then hooks.state(o.u, o.m, o.state, o.from, t) end
	end
	local function closeHolder(m, t)
		local h = holders[m]
		if not h then return end
		holders[m] = nil
		if t > h.from then
			acc.held[h.u] = (acc.held[h.u] or 0) + t - h.from
			if hooks.hold then hooks.hold(h.u, m, h.from, t) end
		end
	end
	-- The monitored mob stops being watched (combat ends or another mob): what rested on it ends.
	local function endWatch(t)
		for key, o in pairs(open) do
			if o.m == curMob or not inFight then closeState(key, t) end
		end
		closeHolder(curMob, t)
		if monFrom then
			if hooks.watch and t > monFrom then hooks.watch(curMob, monFrom, t) end
			if mobs[curMob] then mobs[curMob].monitored = mobs[curMob].monitored + t - monFrom end
			acc.monitored = acc.monitored + t - monFrom
			monFrom = nil
		end
	end
	local function startFight(t)
		if inFight then return end
		inFight, fightFrom = true, t
		acc.pulls = acc.pulls + 1
		for key in pairs(lastKnown) do lastKnown[key] = nil end
		if curMob > 0 then monFrom = t end
		if mode == "n" then noneFrom = t end
	end
	local function endFight(t)
		if not inFight then return end
		for key in pairs(open) do closeState(key, t) end
		for m in pairs(holders) do closeHolder(m, t) end
		endWatch(t)
		if noneFrom then add(acc.none, noneFrom, t) noneFrom = nil end
		add(acc.combat, fightFrom, t)
		inFight = false
	end

	for _, e in ipairs(d.events) do
		local t, k, m, u, v = e.t, e.k, e.m, e.u, e.v
		if k == "C" then
			startFight(t)
		elseif k == "c" then
			endFight(t)
		elseif k == "T" then
			if m ~= curMob then
				if inFight then endWatch(t) end
				for key in pairs(lastKnown) do lastKnown[key] = nil end
				curMob = m
				if inFight and m > 0 then monFrom = t end
			end
			if m > 0 and mobs[m] and not mobs[m].first then mobs[m].first = t end
		elseif k == "M" then
			if inFight and noneFrom then add(acc.none, noneFrom, t) noneFrom = nil end
			mode = e.a
			if inFight and mode == "n" then noneFrom = t end
			if mode == "n" and MODE_REASON[e.b] then acc.modeReason = MODE_REASON[e.b] end
			if mode == "v" then acc.valuesMode = true elseif mode == "s" then acc.stateMode = true end
		elseif k == "G" then
			if e.n > 0 then add(acc.gaps, max(t - e.n, 0), t) end
		elseif k == "S" and units[u] then
			local unit, key = units[u], u * 100 + m
			local new, old = e.a, e.b
			if new == "S" or new == "W" or new == "D" then acc.readableState = true end
			if inFight then
				if unit.me and WORST[new] and (not unit.worst or WORST[new] > WORST[unit.worst]) then unit.worst = new end
				local level, before = LEVEL[new], lastKnown[key] or 0
				if level then
					if level >= LEVEL.W then
						local entry
						if old == "U" then entry = level > before else entry = level > (LEVEL[old] or 0) end
						if entry then
							if new == "W" then unit.warningCross = unit.warningCross + 1
							else unit.dangerCross = unit.dangerCross + 1 end
							if hooks.cross then hooks.cross(u, m, t, new, e) end
						end
					end
					lastKnown[key] = level
				else
					lastKnown[key] = new == "U" and (LEVEL[old] or before) or 0
				end
				if level then
					if mode == "s" then unit.game = true elseif mode == "v" then unit.thresholds = true end
				end
			end
			closeState(key, t)
			if inFight and m > 0 and m == curMob and new ~= "-" then open[key] = { u = u, m = m, state = new, from = t } end
		elseif k == "A" then
			if inFight and m > 0 then
				closeHolder(m, t)
				if units[u] and m == curMob then holders[m] = { u = u, from = t } end
				if units[u] then
					if not acc.heldOrder[u] then
						acc.heldOrder[u] = true
						acc.holderList[#acc.holderList + 1] = u
					end
					if e.a == "1" and e.b == "1" and units[v] then
						acc.changes[#acc.changes + 1] = { t = t, mob = m, from = v, to = u }
					elseif e.a == "0" then
						units[u].aggro = units[u].aggro + 1
						acc.losses[#acc.losses + 1] = { t = t, mob = m, to = u, from = units[v] and v or nil }
					end
				end
			end
		elseif k == "D" then
			local key = u > 0 and ("u" .. u) or ("m" .. m)
			if (u > 0 and units[u]) or (u == 0 and mobs[m]) then
				if not deathAt[key] or t - deathAt[key] > Report.DEATH_WINDOW then
					acc.deaths[#acc.deaths + 1] = { t = t, unit = u > 0 and u or nil, mob = u == 0 and m or nil }
				end
				deathAt[key] = t
			end
		elseif k == "L" then
			local kind = ALERT_NAME[e.a] or "other"
			acc.alerts.count = acc.alerts.count + 1
			acc.alerts.kinds[kind] = (acc.alerts.kinds[kind] or 0) + 1
			if e.c == "1" then acc.alerts.muted = acc.alerts.muted + 1 end
		elseif k == "N" then
			if e.a == "s" then acc.encounter = "started"
			elseif e.a == "e" then
				acc.encounter = (e.b == "1" and "success") or (e.b == "0" and "failed") or "ended"
			end
		elseif k == "Z" then
			if e.a == "e" then acc.eventsCut = true end
		end
		step()
	end
	endFight(acc.last)              -- an interrupted session: the open period ends at the last record
end

local function walkRows(d, acc, step)
	local units, mobs = acc.units, acc.mobs
	local NUMBERED = Session.NUMBERED
	for i = 1, d.n do
		local unit, mob = units[d.u[i]], mobs[d.m[i]]
		local code = d.s[i]
		if mob then mob.rows = mob.rows + 1 end
		if unit then
			if NUMBERED[code] then
				unit.numbered[#unit.numbered + 1] = i
				acc.readableValue = true
				local p = d.p[i]
				if not unit.max or p > unit.max then unit.max, unit.maxAt, unit.maxMob = p, d.t[i], d.m[i] end
			elseif STATE_ONLY[code] then
				unit.stateRows = unit.stateRows + 1
				acc.readableState = true
			elseif ROW_REASON[code] then
				unit.unknownRows = unit.unknownRows + 1
				acc.reasons[code] = (acc.reasons[code] or 0) + 1
			end
		end
		step()
	end
end

-- "+N points in the 3 s before": the unit's numbered rows on that mob in the window, at least two, and N > 0.
local function pointsBefore(d, unit, loss)
	local rows = unit.numbered
	local lo, hi = 1, #rows
	while lo <= hi do                          -- the last row not after the loss
		local mid = floor((lo + hi) / 2)
		if d.t[rows[mid]] <= loss.t then lo = mid + 1 else hi = mid - 1 end
	end
	local newest, oldest, count
	count = 0
	for i = hi, 1, -1 do
		local row = rows[i]
		if d.t[row] < loss.t - Report.POINTS_WINDOW then break end
		if d.m[row] == loss.mob then
			newest = newest or d.p[row]
			oldest = d.p[row]
			count = count + 1
		end
	end
	if count < 2 then return nil end
	local points = floor((newest - oldest) / 10 + 0.5)
	if points <= 0 then return nil end
	return points
end

---------------------------------------------------------------------------------------------------------------------
-- The cells
---------------------------------------------------------------------------------------------------------------------
local function cell(key, category, value, extra)
	local out = { key = key, category = category, status = "ok", value = value }
	if extra then for k, v in pairs(extra) do out[k] = v end end
	return out
end

local function missing(key, status, reason)
	return { key = key, category = "unknown", status = status, reason = reason }
end

local function percent(part, total) return floor(part * 100 / total + 0.5) end

local function quality(v, s, x, reason)
	local total = v + s + x
	if total <= 0 then return missing("quality", "insufficient", "no-ticks") end
	return cell("quality", "calculated", { values = percent(v, total), state = percent(s, total),
		unknown = percent(x, total), ticks = total }, { reason = x > 0 and reason or nil })
end

local function prevailing(acc)
	local best, count = nil, 0
	for _, code in ipairs(ROW_REASON_ORDER) do
		local n = acc.reasons[code]
		if n and n > count then best, count = ROW_REASON[code], n end
	end
	return best or acc.modeReason or "other"
end

local function tick(list, i)
	local v = type(list) == "table" and list[i]
	if type(v) == "number" and v == v and v >= 0 then return v end
	return 0
end

local function unitCells(s, d, acc, unit, readable)
	local q = type(s.q) == "table" and s.q or {}
	local qv, qs, qx = tick(q.v, unit.index), tick(q.s, unit.index), tick(q.x, unit.index)
	local cells = {}
	unit.cells = cells
	cells.quality = quality(qv, qs, qx, acc.reason)

	local gaps = {}
	for _, i in ipairs(acc.none) do gaps[#gaps + 1] = { i[1], i[2] } end
	for _, i in ipairs(acc.gaps) do gaps[#gaps + 1] = { i[1], i[2] } end
	local unknown = intersect(merge(unit.inList), merge(gaps))
	for _, i in ipairs(unit.unknownState) do unknown[#unknown + 1] = { i[1], i[2] } end
	local unknownTime = length(merge(unknown))
	local known = length(unit.warning) + length(unit.danger) + length(unit.safe)
	local partial = unknownTime > 0 or unit.unknownRows > 0
	unit.unknownTime, unit.partial = unknownTime, partial

	local useful = #unit.numbered + max(qs, unit.stateRows)
	unit.status = "ok"
	if not readable then
		unit.status, unit.reason = "na", acc.reason
	elseif useful < Report.MIN_ROWS then
		unit.status, unit.reason = "insufficient", "few-rows"
	end
	if unit.status ~= "ok" then
		for _, key in ipairs(Report.UNIT_CELLS) do
			if key ~= "quality" or unit.status == "insufficient" then cells[key] = missing(key, unit.status, unit.reason) end
		end
		return
	end

	local basis = (unit.game and unit.thresholds and "mixed") or (unit.game and "game")
		or (unit.thresholds and "thresholds") or nil
	local category = partial and "estimated" or "calculated"
	local function stateCell(key, value, isTime)
		if known < Report.MIN_KNOWN then return missing(key, "insufficient", "little-known") end
		return cell(key, category, value, { lower = partial or nil,
			unknownTime = isTime and unknownTime > 0 and unknownTime or nil, basis = basis })
	end
	cells.warningCross = stateCell("warningCross", unit.warningCross, false)
	cells.dangerCross = stateCell("dangerCross", unit.dangerCross, false)
	cells.warningTime = stateCell("warningTime", length(unit.warning), true)
	cells.dangerTime = stateCell("dangerTime", length(unit.danger), true)
	if not acc.readableValue then
		cells.maxPct = missing("maxPct", "na", acc.readableState and "state-only" or acc.reason)
	elseif #unit.numbered < Report.MIN_ROWS then
		cells.maxPct = missing("maxPct", "insufficient", "few-values")
	else
		cells.maxPct = cell("maxPct", "detected", { pct = unit.max / 10, t = unit.maxAt, mob = unit.maxMob },
			{ truncated = s.trunc and true or nil })
	end
	cells.aggro = cell("aggro", partial and "estimated" or "detected", unit.aggro, { lower = partial or nil })
	if s.trunc then cells.quality.truncated = true end
end

local function mainMob(acc, readable)
	local best
	for _, mob in ipairs(acc.mobs) do
		-- most rows (with nothing readable: most monitored time); the first monitored wins a tie
		local score = readable and mob.rows or mob.monitored
		if not best or score > (readable and best.rows or best.monitored) then best = mob end
	end
	return best
end

local function newAcc(s, d)
	local units, mobs = {}, {}
	for i, entry in ipairs(s.units) do units[i] = newUnit(i, entry) end
	for i, entry in ipairs(s.mobs) do
		mobs[i] = { index = i, name = entry.name, class = entry.class, rows = 0, monitored = 0 }
	end
	local last = type(s.dur) == "number" and s.dur or 0
	if d.n > 0 then last = max(last, d.t[d.n]) end
	if d.ne > 0 then last = max(last, d.events[d.ne].t) end
	local acc = {
		units = units, mobs = mobs, last = last, pulls = 0, monitored = 0, combat = {}, none = {}, gaps = {},
		held = {}, heldOrder = {}, holderList = {}, changes = {}, losses = {}, deaths = {}, reasons = {},
		alerts = { count = 0, muted = 0, kinds = {} },
	}
	return acc
end

Report.Intervals = { add = add, merge = merge, intersect = intersect, length = length }
Report.Prevailing = prevailing

-- The pass over the events of `s` alone, with the hooks of the timeline (see the head of the file): the periods
-- (acc.combat, acc.none, acc.gaps), the states, the holders and the crossings by the report's own rules.
function Report.Walk(s, d, step, hooks)
	local acc = newAcc(s, d)
	acc.hooks = hooks
	walkEvents(s, d, acc, step or function() end)
	return acc
end

-- The report of `s` from its decoded rows and events `d`. `step` (may be nil) is called once per event and row, so the
-- work can be cut into slices.
function Report.Compute(s, d, step)
	step = step or function() end
	local acc = newAcc(s, d)
	local units, mobs, last = acc.units, acc.mobs, acc.last
	walkEvents(s, d, acc, step)
	walkRows(d, acc, step)

	local q = type(s.q) == "table" and s.q or {}
	local sv, ss, sx = 0, 0, 0
	for i = 1, #units do
		sv, ss, sx = sv + tick(q.v, i), ss + tick(q.s, i), sx + tick(q.x, i)
	end
	if sv > 0 then acc.readableValue = true end
	if ss > 0 then acc.readableState = true end
	local readable = acc.readableValue == true or acc.readableState == true
	acc.reason = prevailing(acc)

	for _, loss in ipairs(acc.losses) do
		loss.points = pointsBefore(d, units[loss.to], loss)
	end
	for _, unit in ipairs(units) do unitCells(s, d, acc, unit, readable) end

	local combat = length(acc.combat)
	local interrupted = s.state == "interrupted"
	local fight = type(s.fight) == "number" and s.fight or 0
	local report = {
		id = s.id, started = s.started, state = s.state, ended = s.ended, interrupted = interrupted or nil,
		truncated = s.trunc, eventsCut = acc.eventsCut, recordedUntil = interrupted and last or nil, dur = last,
		pulls = acc.pulls, zone = s.zone, group = s.group, inst = s.inst, diff = s.diff, rec = s.rec or {},
		readable = { values = acc.readableValue == true, state = acc.readableState == true, any = readable },
		units = {}, mobs = mobs, rows = {},
	}
	local rows = report.rows
	local function row(c) rows[#rows + 1] = c rows[c.key] = c end

	-- Duration: a fight of 0 in an interrupted session is unknown, never invented.
	row(cell("duration", "detected", { dur = last, fight = (not (interrupted and fight == 0)) and fight or nil,
		pulls = acc.pulls }, { lower = interrupted or nil }))

	local mob = mainMob(acc, readable)
	if not mob then
		row(missing("mob", "unknown", "no-mob"))
	else
		local c = cell("mob", "detected", { index = mob.index, name = mob.name, class = mob.class,
			others = #mobs - 1, encounter = acc.encounter })
		if mob.name == nil then c.status, c.category, c.reason = "unknown", "unknown", "name" end
		row(c)
	end

	if not readable then
		row(missing("tanks", "na", acc.reason))
		row(missing("tankChanges", "na", acc.reason))
		row(missing("aggroLosses", "na", acc.reason))
	else
		local tanks = {}
		for _, u in ipairs(acc.holderList) do
			tanks[#tanks + 1] = { unit = u, held = acc.held[u] or 0, designated = units[u].role == "TANK",
				lower = units[u].partial or nil }
		end
		sort(tanks, function(a, b)
			if a.held ~= b.held then return a.held > b.held end
			return a.unit < b.unit
		end)
		row(cell("tanks", "detected", tanks, { timeCategory = "calculated" }))
		row(cell("tankChanges", "detected", acc.changes))
		row(cell("aggroLosses", "detected", acc.losses))
	end

	local sq = quality(sv, ss, sx, acc.reason)
	if sq.status == "ok" then
		sq.value.noneTime = length(merge(acc.none))
		sq.value.noMobTime = max(combat - acc.monitored, 0)
		sq.value.gapTime = length(merge(acc.gaps))
		sq.truncated = s.trunc and true or nil
	end
	row(sq)
	row(cell("deaths", "detected", acc.deaths))
	if not readable then
		row(missing("alerts", "na", acc.reason))
	else
		row(cell("alerts", "detected", acc.alerts))
	end

	-- The units: the player first, then the designated tanks, then by the number of crossings.
	local order = {}
	for i, unit in ipairs(units) do order[i] = unit end
	local function rank(u) return (u.me and 1) or (u.role == "TANK" and 2) or 3 end
	sort(order, function(a, b)
		if rank(a) ~= rank(b) then return rank(a) < rank(b) end
		local ca, cb = a.warningCross + a.dangerCross, b.warningCross + b.dangerCross
		if ca ~= cb then return ca > cb end
		return a.index < b.index
	end)
	for i, u in ipairs(order) do
		report.units[i] = { index = u.index, name = u.name, class = u.class, role = u.role, token = u.token,
			me = u.me or nil, pet = u.pet or nil, status = u.status, reason = u.reason, cells = u.cells,
			worst = u.worst }
	end

	local cross, aggro = 0, #acc.losses
	for _, u in ipairs(units) do cross = cross + u.warningCross + u.dangerCross end
	local worst
	for _, u in ipairs(units) do
		if u.me and u.worst and (not worst or WORST[u.worst] > WORST[worst]) then worst = u.worst end
	end
	local total = sv + ss + sx
	report.summary = { mob = mob and mob.index or nil, worst = worst, cross = readable and cross or nil,
		aggro = readable and aggro or nil, valid = total > 0 and percent(sv + ss, total) or nil }
	return report
end

-- `sum` (SPEC-02 §4.1): computed by the same functions as the report, nil while the switch is off.
function Report.Summary(s)
	if not on() then return nil end
	local d = Session.Decode(s)
	if not d then return nil end
	return Report.Compute(s, d).summary
end

---------------------------------------------------------------------------------------------------------------------
-- Building in slices (§3.4)
---------------------------------------------------------------------------------------------------------------------
function Report.Build(id, done)
	if not on() then done(nil, "off") return end
	local s = Storage.Get(id)
	if not s then done(nil, "unknown") return end
	if s.state == "open" or (ns.Recorder and ns.Recorder.current == s) then done(nil, "recording") return end
	if cache.s == s then done(cache.report) return end
	local d, why = Storage.Decode(id)
	if not d then done(nil, why) return end

	local count, slice = 0, Report.SLICE
	local co = coroutine.create(function()
		return Report.Compute(s, d, function()
			count = count + 1
			if count >= slice then
				count = 0
				coroutine.yield()
			end
		end)
	end)
	local function resume()
		if Storage.Get(id) ~= s then done(nil, "unknown") return end   -- deleted while building
		local ok, result = coroutine.resume(co)
		if not ok then
			Report.lastError = tostring(result)
			done(nil, "error")
		elseif coroutine.status(co) == "dead" then
			cache.s, cache.report = s, result
			done(result)
		elseif not Compat.After(0, resume) then
			resume()
		end
	end
	resume()
end

function Report.Cached() return cache.report end

if ns.Bus then
	ns.Bus.On("SESSIONS_CHANGED", function()
		if cache.s and Storage.Get(cache.report.id) ~= cache.s then cache.s, cache.report = nil, nil end
	end)
end

---------------------------------------------------------------------------------------------------------------------
-- Words (SPEC-04 §2.4, ADR 0009): what the Reports tab and the notice write. No cause, no ability, no hypothesis.
---------------------------------------------------------------------------------------------------------------------
local STATUS_KEY = { na = "REPORT_NA", insufficient = "REPORT_INSUFFICIENT", unknown = "REPORT_UNKNOWN" }
Report.REASON_KEYS = {
	secret = "REPORT_WHY_SECRET", missing = "REPORT_WHY_MISSING", error = "REPORT_WHY_ERROR",
	["no-unit"] = "REPORT_WHY_NO_UNIT", other = "REPORT_WHY_OTHER", stale = "REPORT_WHY_STALE",
	["state-only"] = "REPORT_WHY_STATE_ONLY", ["few-rows"] = "REPORT_WHY_FEW_ROWS",
	["few-values"] = "REPORT_WHY_FEW_VALUES", ["little-known"] = "REPORT_WHY_LITTLE_KNOWN",
	["no-ticks"] = "REPORT_WHY_NO_TICKS", ["no-mob"] = "REPORT_WHY_NO_MOB", name = "REPORT_WHY_NAME",
}
Report.METRIC_KEYS = {
	duration = "REPORT_METRIC_DURATION", mob = "REPORT_METRIC_MOB", tanks = "REPORT_METRIC_TANKS",
	tankChanges = "REPORT_METRIC_TANK_CHANGES", aggroLosses = "REPORT_METRIC_AGGRO_LOSSES",
	quality = "REPORT_METRIC_QUALITY", deaths = "REPORT_METRIC_DEATHS", alerts = "REPORT_METRIC_ALERTS",
	warningCross = "REPORT_METRIC_WARNING_CROSS", dangerCross = "REPORT_METRIC_DANGER_CROSS",
	warningTime = "REPORT_METRIC_WARNING_TIME", dangerTime = "REPORT_METRIC_DANGER_TIME",
	maxPct = "REPORT_METRIC_MAX", aggro = "REPORT_METRIC_AGGRO",
}
local BASIS_KEY = { thresholds = "REPORT_BASIS_THRESHOLDS", game = "REPORT_BASIS_GAME", mixed = "REPORT_BASIS_MIXED" }
local ENDED_KEY = { reload = "REPORT_ENDED_RELOAD", login = "REPORT_ENDED_LOGIN" }
local ENCOUNTER_KEY = { started = "REPORT_ENCOUNTER_STARTED", success = "REPORT_ENCOUNTER_SUCCESS",
	failed = "REPORT_ENCOUNTER_FAILED", ended = "REPORT_ENCOUNTER_ENDED" }
local CLASS_KEY = { elite = "MON_CLASS_ELITE", rare = "MON_CLASS_RARE", rareelite = "MON_CLASS_RAREELITE",
	worldboss = "MON_CLASS_BOSS" }

-- "1:42"
function Report.Time(tenths)
	local seconds = floor((tenths or 0) / 10)
	return ("%d:%02d"):format(floor(seconds / 60), seconds % 60)
end

-- "12.5 s"
function Report.Seconds(tenths)
	return ns.L.REPORT_SECONDS:format((tenths or 0) / 10)
end

function Report.UnitName(report, index)
	for _, u in ipairs(report.units) do
		if u.index == index then
			if type(u.name) == "string" and u.name ~= "" then return u.name end
			return u.token or ns.L.REPORT_UNKNOWN
		end
	end
	return ns.L.REPORT_UNKNOWN
end

function Report.MobName(report, index)
	local mob = report.mobs[index or 0]
	if mob and type(mob.name) == "string" and mob.name ~= "" then return mob.name end
	return ns.L.MON_UNKNOWN_MOB
end

-- The reason of a cell for its tooltip, nil without one.
function Report.ReasonText(reason)
	local key = Report.REASON_KEYS[reason or ""]
	return key and ns.L[key] or nil
end

-- The basis of a state metric ("game states", or the thresholds the report was recorded with).
function Report.BasisText(report, basis)
	local key = BASIS_KEY[basis or ""]
	if not key then return nil end
	if basis == "game" then return ns.L[key] end
	return ns.L[key]:format(report.rec.warning or 0, report.rec.danger or 0)
end

local function atLeast(text, lower)
	if lower then return ns.L.REPORT_AT_LEAST:format(text) end
	return text
end

local function list(lines, empty)
	if #lines == 0 then return ns.L[empty] end
	return concat(lines, "\n")
end

local words = {}

function words.duration(report, c)
	local L, v = ns.L, c.value
	local parts = { atLeast(Report.Time(v.dur), c.lower) }
	if v.fight then parts[#parts + 1] = L.REPORT_IN_COMBAT:format(atLeast(Report.Time(v.fight), c.lower)) end
	if v.pulls > 1 then parts[#parts + 1] = L.REPORT_PULLS:format(v.pulls) end
	return concat(parts, " · ")
end

function words.mob(report, c)
	local L, v = ns.L, c.value
	local parts = { Report.MobName(report, v.index) }
	if CLASS_KEY[v.class or ""] then parts[#parts + 1] = L[CLASS_KEY[v.class]] end
	if v.others == 1 then parts[#parts + 1] = L.REPORT_OTHER_MOB
	elseif v.others > 1 then parts[#parts + 1] = L.REPORT_OTHER_MOBS:format(v.others) end
	if ENCOUNTER_KEY[v.encounter or ""] then parts[#parts + 1] = L[ENCOUNTER_KEY[v.encounter]] end
	return concat(parts, " · ")
end

function words.tanks(report, c)
	local L, lines = ns.L, {}
	for _, h in ipairs(c.value) do
		local line = L.REPORT_HELD:format(Report.UnitName(report, h.unit), atLeast(Report.Seconds(h.held), h.lower))
		if h.designated then line = L.REPORT_DESIGNATED:format(line) end
		lines[#lines + 1] = line
	end
	return list(lines, "REPORT_NO_HOLDER")
end

function words.tankChanges(report, c)
	local L, lines = ns.L, {}
	for _, e in ipairs(c.value) do
		lines[#lines + 1] = L.REPORT_TANK_CHANGE:format(Report.Time(e.t), Report.UnitName(report, e.from),
			Report.UnitName(report, e.to))
	end
	return list(lines, "REPORT_NO_TANK_CHANGE")
end

function words.aggroLosses(report, c)
	local L, lines = ns.L, {}
	for _, e in ipairs(c.value) do
		local line
		if e.from then
			line = L.REPORT_AGGRO_FROM:format(Report.Time(e.t), Report.UnitName(report, e.to),
				Report.UnitName(report, e.from))
		else
			line = L.REPORT_AGGRO:format(Report.Time(e.t), Report.UnitName(report, e.to))
		end
		if e.points then line = L.REPORT_WITH_POINTS:format(line, L.REPORT_POINTS:format(e.points)) end
		lines[#lines + 1] = line
	end
	return list(lines, "REPORT_NO_AGGRO_LOSS")
end

function words.quality(_, c)
	local L, v = ns.L, c.value
	local lines = { L.REPORT_QUALITY:format(v.values, v.state, v.unknown) }
	if (v.noneTime or 0) > 0 then lines[#lines + 1] = L.REPORT_GAP_NONE:format(Report.Seconds(v.noneTime)) end
	if (v.noMobTime or 0) > 0 then lines[#lines + 1] = L.REPORT_GAP_NO_MOB:format(Report.Seconds(v.noMobTime)) end
	if (v.gapTime or 0) > 0 then lines[#lines + 1] = L.REPORT_GAP_TICK:format(Report.Seconds(v.gapTime)) end
	return concat(lines, "\n")
end

function words.deaths(report, c)
	local L, lines = ns.L, {}
	for _, e in ipairs(c.value) do
		local name = e.unit and Report.UnitName(report, e.unit) or Report.MobName(report, e.mob)
		lines[#lines + 1] = L.REPORT_DEATH:format(Report.Time(e.t), name)
	end
	return list(lines, "REPORT_NO_DEATH")
end

function words.alerts(_, c)
	local L, v = ns.L, c.value
	if v.count == 0 then return L.REPORT_NO_ALERT end
	local lines = { L.REPORT_ALERT_TOTAL:format(v.count, v.muted) }
	for _, kind in ipairs(Report.ALERT_ORDER) do
		if v.kinds[kind] then
			lines[#lines + 1] = L.REPORT_ALERT_KIND:format(L["REPORT_ALERT_" .. kind:upper()], v.kinds[kind])
		end
	end
	return concat(lines, "\n")
end

local function count(_, c) return atLeast(("%d"):format(c.value), c.lower) end

local function duration(_, c)
	local text = atLeast(Report.Seconds(c.value), c.lower)
	if c.unknownTime then text = text .. " · " .. ns.L.REPORT_UNKNOWN_TIME:format(Report.Seconds(c.unknownTime)) end
	return text
end

words.warningCross, words.dangerCross, words.aggro = count, count, count
words.warningTime, words.dangerTime = duration, duration

function words.maxPct(_, c)
	return ns.L.REPORT_MAX:format(c.value.pct, Report.Time(c.value.t))
end

-- The text of a cell of `report`: its value, or Not available / Insufficient data / Unknown.
function Report.CellText(report, c)
	if c.status ~= "ok" then
		if c.key == "mob" and c.value then return words.mob(report, c) end
		if c.key == "tanks" and c.status == "na" then return ns.L.REPORT_NA_TANKS end
		return ns.L[STATUS_KEY[c.status]]
	end
	local fn = words[c.key]
	return fn and fn(report, c) or ns.L.REPORT_UNKNOWN
end

-- The lines above the report: interrupted, recorded until, samples or events stopped at a limit.
function Report.Headlines(report)
	local L, out = ns.L, {}
	if report.interrupted then
		out[#out + 1] = L.REPORT_INTERRUPTED:format(L[ENDED_KEY[report.ended or ""] or "REPORT_ENDED_UNKNOWN"])
		out[#out + 1] = L.REPORT_RECORDED_UNTIL:format(Report.Time(report.recordedUntil))
	end
	if report.truncated then out[#out + 1] = L.REPORT_TRUNCATED:format(Report.Time(report.truncated)) end
	if report.eventsCut then out[#out + 1] = L.REPORT_EVENTS_CUT end
	return out
end

if ns.addon then ns.addon.Report = Report end
