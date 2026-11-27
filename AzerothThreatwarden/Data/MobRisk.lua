-- MobRisk: the state and reason of one mob from its rows, and the order of the Dungeon Focus (SPEC-07 §1.8, §2.1,
-- ADR 0019). Lua 5.1, no game API (the clock is the caller's). Threatwarden's own.
--
-- A mob's rows are records as Compat.Threat.Read fills them (mode, reason, isTanking, situation, scaledPercent,
-- leadSituation, observedAt, interval) with the unit's role, unitKey and unitToken, and `mobKey` set to the mob they were
-- read on: the pooled rows of a slot of Data/MobTracker.lua, or, for the monitored mob, the records of
-- Data/ThreatScanner.lua themselves (never read twice, MT-03). A row counts when it was read on this mob and is fresh
-- (max(2 * interval, floor) old at most, DAT-12); a row "none" with reason "nil" is a unit not on the mob's list (MON-05).
--
-- Written on the entry of the mob:
--   entry.mode          "values", "state" or "none": the best of its fresh rows (MON-04)
--   entry.holder        the row holding the mob (isTanking, or situation 2-3), nil when no watched unit does
--   entry.top           the closest of the others: highest scaled % (values) or situation (state); topPercent,
--                       topSituation; entry.margin = 100 - topPercent (calculated)
--   entry.selfRec       the player's row when on the list; entry.selfState its state with the rules of a non tank
--                       (SPEC-03 §2.2-§2.3), for the alerts of SPEC-07 §2.5
--   entry.state         the shown state "DANGER", "WARNING", "SAFE", "UNKNOWN" (nil: not listed), entry.reason why
--                       ("aggro", "close", "no-tank", "near"; for SAFE nil, "not-watched" or "margin-unknown"; for
--                       UNKNOWN the reason of SPEC-07 §1.5), entry.stateSince the time of its last change
--
-- Rules (§1.8): DANGER `aggro` with designated tanks and a holder that is not one of them; DANGER `close` when one that
-- does not hold it reaches DANGER D (values), or the holder has situation 2 or a lead situation 2-3 (state); WARNING
-- `no-tank` with designated tanks, none on its list and no watched holder; WARNING `near` from WARNING W (values), or
-- situation 1 or lead 1 (state); otherwise SAFE. Without designated tanks the holder counts as the tank, so `aggro` and
-- `no-tank` never apply. The higher state wins; on a tie the reason in the table's order. Hysteresis and dwell are the
-- monitor's (ThreatState.DEFAULTS, MON-10, MON-12): a state rises at once and falls or turns UNKNOWN only `dwell`
-- seconds after its last change.
--
-- MOB_STATE_CHANGED(mobKey, old, new, reason) is emitted for the shown state of a mob other than the monitored one
-- (old nil: it entered the list, new nil: it left it). Allocation-free (ARC-06).
local ADDON_NAME, ns = ...
ns = ns or {}
ns.modules = ns.modules or {}

local MobRisk = {}
ns.MobRisk, ns.modules.MobRisk = MobRisk, MobRisk

local type = type

-- SPEC-07 §2.1, SPEC-09 Q27: the order of the reasons of the same state (the one place).
MobRisk.REASON_ORDER = { "aggro", "close", "no-tank", "near" }
local REASON_RANK = {}
for i, reason in ipairs(MobRisk.REASON_ORDER) do REASON_RANK[reason] = i end
local OTHER_RANK = #MobRisk.REASON_ORDER + 1

local LEVEL = { SAFE = 1, WARNING = 2, DANGER = 3 }   -- UNKNOWN has no level: leaving it is a rise, entering it a fall
local ORDER_RANK = { DANGER = 3, WARNING = 2, SAFE = 1, UNKNOWN = 0 }

MobRisk.changes = 0          -- MOB_STATE_CHANGED emitted

local function emit(event, ...)
	if ns.Bus then ns.Bus.Emit(event, ...) end
end

-- The thresholds of the monitor (the player's settings, SPEC-03 §2) and its hysteresis and dwell.
local function thresholds()
	local State = ns.ThreatState
	local w, d = 82, 91
	if State and State.Thresholds then w, d = State.Thresholds() end
	local D = State and State.DEFAULTS or { hysteresis = 3, dwell = 1 }
	return w, d, D.hysteresis, D.dwell
end

-- The level a percentage reaches with hysteresis from the shown level `level` (MON-10).
local function byThreshold(p, level, w, d, h)
	if p >= d or (level >= 3 and p >= d - h) then return 3 end
	if p >= w or (level >= 2 and p >= w - h) then return 2 end
	return 1
end

local function holds(rec)
	if rec.mode == "none" then return false end
	if rec.isTanking == true then return true end
	local g = rec.situation
	return type(g) == "number" and g >= 2
end

-- true when `rec` was read on this mob and is fresh at `now` (DAT-12); the floor is 1 s for the mobs of the rotation
-- and the monitor's 0.5 s for the monitored mob.
local function usable(rec, key, now, floor)
	if rec.mobKey ~= key or rec.stale == true then return false end
	local at = rec.observedAt
	if type(at) ~= "number" or at <= 0 then return false end
	local limit = floor
	local interval = rec.interval
	if type(interval) == "number" and 2 * interval > limit then limit = 2 * interval end
	return now - at <= limit + 1e-9
end

-- The rows of the mob: its mode, holder, closest other and the player's row. Returns the reason of a mob in `none`.
local function summarize(entry, recs, count, now, floor, designated)
	local key = entry.key
	local best, noneReason = nil, nil
	local holder, selfRec = nil, nil
	local top, topPercent, topSituation = nil, nil, nil
	local tankOnList, anyRow = false, false
	for i = 1, count do
		local rec = recs[i]
		if rec and usable(rec, key, now, floor) then
			anyRow = true
			local mode, reason = rec.mode, rec.reason
			local present = not (mode == "none" and reason == "nil")
			if present then
				if mode == "values" then best = "values"
				elseif mode == "state" then if best ~= "values" then best = "state" end
				elseif not noneReason then noneReason = reason end
				if rec.role == "TANK" then tankOnList = true end
				if not holder and holds(rec) then holder = rec end
				if rec.unitToken == "player" then selfRec = rec end
			end
		end
	end
	-- the closest of the others, once the holder is known
	for i = 1, count do
		local rec = recs[i]
		if rec and rec ~= holder and usable(rec, key, now, floor) and rec.mode ~= "none" then
			local p = rec.mode == "values" and rec.scaledPercent or nil
			if type(p) == "number" then
				if topPercent == nil or p > topPercent then top, topPercent = rec, p end
			end
			local g = rec.situation
			if type(g) == "number" and (topSituation == nil or g > topSituation) then
				topSituation = g
				if topPercent == nil then top = rec end
			end
		end
	end
	entry.mode = best or "none"
	entry.holder, entry.selfRec, entry.top = holder, selfRec, top
	entry.topPercent, entry.topSituation = topPercent, topSituation
	entry.margin = topPercent and (100 - topPercent) or nil
	entry.tankOnList, entry.designated = tankOnList, designated
	if best then return nil end
	if not anyRow then return "pending" end
	return noneReason or "missing"
end

-- The state the mob should show, before the dwell: state, reason.
local function target(entry, w, d, h)
	local holder = entry.holder
	local tanks = entry.designated > 0
	local level = LEVEL[entry.state] or 0
	local noTank = tanks and not entry.tankOnList and holder == nil
	if entry.mode == "values" then
		if tanks and holder and holder.role ~= "TANK" then return "DANGER", "aggro" end
		if holder and holder.situation == 2 then return "DANGER", "close" end
		local p = entry.topPercent
		local reached = type(p) == "number" and byThreshold(p, level, w, d, h) or 1
		if reached == 3 then return "DANGER", "close" end
		if noTank then return "WARNING", "no-tank" end
		if reached == 2 then return "WARNING", "near" end
		return "SAFE", holder == nil and "not-watched" or nil
	end
	-- state only: the game's situations, no thresholds (SPEC-03 §2.3)
	if tanks and holder and holder.role ~= "TANK" then return "DANGER", "aggro" end
	local lead = holder and holder.leadSituation
	if holder and (holder.situation == 2 or (type(lead) == "number" and lead >= 2)) then return "DANGER", "close" end
	if noTank then return "WARNING", "no-tank" end
	if entry.topSituation == 1 or lead == 1 then return "WARNING", "near" end
	if holder == nil then return "SAFE", "not-watched" end
	if type(lead) ~= "number" then return "SAFE", "margin-unknown" end
	return "SAFE", nil
end

-- The player's own state on the mob with the rules of a non tank (SPEC-03 §2.2-§2.3); nil when not on its list.
local function selfTarget(entry, w, d, h)
	local rec = entry.selfRec
	if not rec then return nil end
	if rec.mode == "none" then return "UNKNOWN" end
	if holds(rec) then return "DANGER" end
	if rec.mode == "state" then
		local g = rec.situation
		if g == 1 then return "WARNING" end
		if g == 0 then return "SAFE" end
		return "UNKNOWN"
	end
	local p = rec.scaledPercent
	if type(p) ~= "number" then return "UNKNOWN" end
	local level = byThreshold(p, LEVEL[entry.selfState] or 0, w, d, h)
	return level == 3 and "DANGER" or (level == 2 and "WARNING" or "SAFE")
end

local function rises(old, new)
	if old == "UNKNOWN" then return new ~= "UNKNOWN" end
	if new == "UNKNOWN" then return false end
	return LEVEL[new] > LEVEL[old]
end

-- Brings the entry's state up to date from `recs[1..count]` at `now`. `unknown`: why the mob cannot be read now
-- (pending, no-token, stale, secret...), nil when its rows decide. `designated`: the watched units with the TANK role.
-- `floor`: the minimum freshness of a row (1 s, or 0.5 s for the monitored mob). Returns true when the shown state
-- changed. MOB_STATE_CHANGED only for a mob that is not the monitored one (entry.monitored).
function MobRisk.Evaluate(entry, recs, count, now, unknown, designated, floor)
	local w, d, h, dwell = thresholds()
	local why = summarize(entry, recs, count or 0, now, floor or 1, designated or 0)
	local new, reason
	if unknown then
		new, reason = "UNKNOWN", unknown
		entry.mode = "none"
	elseif why then
		new, reason = "UNKNOWN", why
	else
		new, reason = target(entry, w, d, h)
	end
	entry.selfState = selfTarget(entry, w, d, h)
	local old = entry.state
	if new == old then
		entry.reason = reason
		return false
	end
	if old ~= nil and not rises(old, new) and now - (entry.stateSince or 0) < dwell - 1e-9 then
		return false   -- a fall too soon: kept (MON-12); the next tick looks again
	end
	entry.state, entry.reason, entry.stateSince = new, reason, now
	if not entry.monitored then
		MobRisk.changes = MobRisk.changes + 1
		emit("MOB_STATE_CHANGED", entry.key, old, new, reason)
	end
	return true
end

-- The mob leaves the list: MOB_STATE_CHANGED(key, old, nil) for a mob other than the monitored one, and no state.
function MobRisk.Leave(entry)
	local old = entry.state
	entry.state, entry.reason, entry.stateSince, entry.selfState = nil, nil, 0, nil
	if old ~= nil and not entry.monitored then
		MobRisk.changes = MobRisk.changes + 1
		emit("MOB_STATE_CHANGED", entry.key, old, nil, nil)
	end
end

-- The rank of a reason in REASON_ORDER (1 first), after them every other reason.
function MobRisk.ReasonRank(reason) return REASON_RANK[reason] or OTHER_RANK end

-- true when mob `a` comes before mob `b` in the Dungeon Focus (SPEC-07 §2.1): the state (UNKNOWN last), the reason,
-- the smaller margin (values) or the higher situation of the closest (state), the player's own state, then the order of
-- discovery (entry.n), never the name.
function MobRisk.Before(a, b)
	local ra, rb = ORDER_RANK[a.state] or 0, ORDER_RANK[b.state] or 0
	if ra ~= rb then return ra > rb end
	local qa, qb = REASON_RANK[a.reason] or OTHER_RANK, REASON_RANK[b.reason] or OTHER_RANK
	if qa ~= qb then return qa < qb end
	local ma, mb = a.margin, b.margin
	if ma ~= nil and mb ~= nil then
		if ma ~= mb then return ma < mb end
	elseif ma ~= nil or mb ~= nil then
		return ma ~= nil
	else
		local ga, gb = a.topSituation or -1, b.topSituation or -1
		if ga ~= gb then return ga > gb end
	end
	local sa, sb = ORDER_RANK[a.selfState] or -1, ORDER_RANK[b.selfState] or -1
	if sa ~= sb then return sa > sb end
	return (a.n or 0) < (b.n or 0)
end

-- Sorts list[1..count] in place in the order of §2.1 (an insertion sort: stable and allocation-free). Returns list.
function MobRisk.Order(list, count)
	local Before = MobRisk.Before
	for i = 2, count do
		local item = list[i]
		local j = i - 1
		while j >= 1 and Before(item, list[j]) do
			list[j + 1] = list[j]
			j = j - 1
		end
		list[j + 1] = item
	end
	return list
end

if ns.addon then ns.addon.MobRisk = MobRisk end
