-- ThreatState: the state of every row (SAFE, WARNING, DANGER, UNKNOWN), who the tank is, and the mode of the monitor
-- (SPEC-03 §1.1 MON-04, §2, SPEC-09 Q7, ADR 0003). Lua 5.1, no game API (the clock and the timer through Compat).
-- Threatwarden's own.
--
-- Written on the rows of Data/ThreatModel.lua after each THREAT_UPDATED:
--   row.isTank       the row is treated as a tank (SPEC-03 §2.1): a designated tank (role TANK), or, when no watched unit
--                    has the TANK role (solo, roles NONE or secret [probe P9]), the row holding the mob
--   row.state        "SAFE", "WARNING", "DANGER", "UNKNOWN", or nil when the unit is not on the threat list (MON-05)
--   row.stateReason  why: nil (plain threshold), "predicted" (WARNING from the trend), "aggro" (a non tank holds the mob),
--                    "lost-aggro" (a designated tank lost the mob to a non tank), "behind" (the tank holds the mob but
--                    another has more threat, situation 2), "alone" (no one else on the list), "margin-unknown" (state
--                    only, no lead readable), "state-only" (from the game's state, the thresholds do not apply), or the
--                    reason of an UNKNOWN: secret, missing, error, no-unit, stale (or the second's reason for a tank)
--   row.stateSince   Compat.Now() of the last change of the shown state
--   row.predictedIn  seconds to DANGER of a predicted WARNING, else nil (predicted, ADR 0003)
--
-- Rules (SPEC-03 §2.2–§2.4): in `values` a non tank compares its scaled % p with WARNING W and DANGER D, and is DANGER
-- while it holds the mob; the tank holding the mob compares the second's s = 100 - margin; in `state` the game's
-- situation (and the holder's lead situation) decide, without thresholds. Hysteresis HYSTERESIS points: a higher state
-- is entered at its threshold and left only HYSTERESIS points below it (MON-10). Dwell DWELL seconds: a row rises at
-- once, but goes down or to UNKNOWN only when its last change is at least DWELL seconds old (MON-12); a held downgrade
-- is checked again by one timer, so it happens after the combat too (no scan then). Entering or leaving the threat
-- list is not a state change of the row and is immediate.
--
-- STATE_CHANGED(unitKey, mobKey, old, new) is emitted only for the shown state, after hysteresis and dwell: old nil =
-- the unit entered the list, new nil = it left it. A new mob or a new combat starts every row again without an event
-- (the pair (unit, mob) is new). THREAT_MODE_CHANGED(mode, reason) is emitted when ThreatScanner.mode or its reason
-- changes (MON-04).
--
-- Thresholds: DEFAULTS (Q7, the one place), overridden by account.settings.monitor.warning and .danger when they exist
-- (schema 2, M2.6) and valid (warning 50-99, danger 60-100 and at least warning + 5; otherwise both defaults).
-- Allocation-free per update (ARC-06).
local ADDON_NAME, ns = ...
ns = ns or {}
ns.modules = ns.modules or {}

local ThreatState = {}
ns.ThreatState, ns.modules.ThreatState = ThreatState, ThreatState

local type, floor = type, math.floor

-- Provisional (SPEC-09 Q7): tuned with the M2 checklist; the player's settings (M2.6) override warning and danger.
ThreatState.DEFAULTS = { warning = 80, danger = 95, hysteresis = 3, dwell = 1 }
ThreatState.MIN_WARNING, ThreatState.MAX_WARNING = 50, 99
ThreatState.MIN_DANGER, ThreatState.MAX_DANGER = 60, 100
ThreatState.MIN_GAP = 5          -- danger at least warning + MIN_GAP
local WARNING_PATH, DANGER_PATH = "account.settings.monitor.warning", "account.settings.monitor.danger"

ThreatState.STATES = { "SAFE", "WARNING", "DANGER", "UNKNOWN" }
local LEVEL = { SAFE = 1, WARNING = 2, DANGER = 3 }   -- UNKNOWN has no level: leaving it is a rise, entering it a fall

ThreatState.mode, ThreatState.modeReason = "none", nil   -- the last mode announced (MON-04)
ThreatState.tank = nil          -- the row holding the mob, or nil: Unknown tank
ThreatState.tankReason = "unknown"   -- nil with a tank; "not-watched" (readable reads, no watched unit holds the mob)
                                     -- or "unknown" (nothing readable says who holds it)
ThreatState.designated = 0      -- watched units with the TANK role
ThreatState.self = nil          -- the player's row when on the list (the header's state, SPEC-03 §2.4)
ThreatState.changes = 0         -- STATE_CHANGED emitted

local warning, danger = ThreatState.DEFAULTS.warning, ThreatState.DEFAULTS.danger
local lastMobKey, wasInCombat = nil, false
local timerPending, recheckAt = false, nil

local function emit(event, ...)
	if ns.Bus then ns.Bus.Emit(event, ...) end
end

local function whole(v)
	if type(v) ~= "number" or v ~= v then return nil end
	return floor(v + 0.5)
end

local function readSettings()
	local Config = ns.Config
	local w, d
	if Config and Config.Get then
		w, d = whole(Config:Get(WARNING_PATH)), whole(Config:Get(DANGER_PATH))
	end
	local D = ThreatState.DEFAULTS
	w, d = w or D.warning, d or D.danger
	if w < ThreatState.MIN_WARNING or w > ThreatState.MAX_WARNING or d < ThreatState.MIN_DANGER
		or d > ThreatState.MAX_DANGER or d < w + ThreatState.MIN_GAP then
		w, d = D.warning, D.danger
	end
	warning, danger = w, d
end

-- The thresholds in use: warning, danger (percent of the scaled threat).
function ThreatState.Thresholds() return warning, danger end

---------------------------------------------------------------------------------------------------------------------
-- The rules
---------------------------------------------------------------------------------------------------------------------
local function holds(rec)
	if rec.isTanking == true then return true end
	local g = rec.situation
	return type(g) == "number" and g >= 2
end

-- The level a value reaches with hysteresis from the shown state `cur` (SPEC-03 §2.2, MON-10).
local function byThreshold(v, cur)
	local h = ThreatState.DEFAULTS.hysteresis
	local level = LEVEL[cur] or 0
	if v >= danger or (level >= 3 and v >= danger - h) then return "DANGER" end
	if v >= warning or (level >= 2 and v >= warning - h) then return "WARNING" end
	return "SAFE"
end

-- The game's lead situation of the holder (0-3) as a state (SPEC-03 §2.3); nil when not readable.
local function byLead(l)
	if type(l) ~= "number" then return nil end
	if l <= 0 then return "SAFE" end
	if l == 1 then return "WARNING" end
	return "DANGER", "margin"
end

-- The state the row should show, before the dwell: state, reason, predicted seconds.
local function target(row, holderRow, holderTank)
	local rec = row.record
	if row.stale or rec.mode == "none" then return "UNKNOWN", row.reason or "missing" end
	local cur = row.state
	local mode = rec.mode
	if row.isHolder and row.isTank then
		-- the tank holding the mob: its margin over the second (MON-11)
		if rec.situation == 2 then return "DANGER", "behind" end
		if mode == "values" and type(row.margin) == "number" then
			return byThreshold(100 - row.margin, cur), nil
		end
		if mode == "values" and row.marginReason == "alone" then return "SAFE", "alone" end
		local state, why = byLead(rec.leadSituation)
		if state then return state, why or (mode == "state" and "state-only" or nil) end
		if mode == "state" then
			if rec.situation == 3 then return "SAFE", "margin-unknown" end
			return "UNKNOWN", rec.leadReason or "missing"
		end
		return "UNKNOWN", row.marginReason or "missing"
	end
	-- a designated tank that lost the mob to a non tank
	if row.isTank and holderRow and not holderTank then return "DANGER", "lost-aggro" end
	if holds(rec) then return "DANGER", "aggro" end
	if mode == "state" then
		local g = rec.situation
		if g == 1 then return "WARNING", "state-only" end
		if g == 0 then return "SAFE", "state-only" end
		return "UNKNOWN", "missing"
	end
	local p = rec.scaledPercent
	if type(p) ~= "number" then return "UNKNOWN", row.reason or "missing" end
	local state = byThreshold(p, cur)
	if state == "SAFE" then
		local Calc = ns.ThreatCalc
		local predicted, t = Calc.PredictedWarning(p, row.trend, row.trendConfidence, danger)
		if predicted then return "WARNING", "predicted", t end
	end
	return state, nil
end

-- True when going from `old` to `new` is a rise (immediate, MON-12).
local function rises(old, new)
	if old == "UNKNOWN" then return new ~= "UNKNOWN" end
	if new == "UNKNOWN" then return false end
	return LEVEL[new] > LEVEL[old]
end

local recheck

local function holdUntil(due)
	if recheckAt == nil or due < recheckAt then recheckAt = due end
end

local function resetRow(row)
	row.state, row.stateReason, row.stateSince, row.predictedIn, row.stateUnit = nil, nil, 0, nil, nil
end

---------------------------------------------------------------------------------------------------------------------
-- Update
---------------------------------------------------------------------------------------------------------------------
-- Brings every row's state up to date with the model, emits STATE_CHANGED and THREAT_MODE_CHANGED. Returns the number
-- of shown state changes.
function ThreatState.Update()
	local Model, Scanner = ns.ThreatModel, ns.ThreatScanner
	if not Model or not Scanner then return 0 end
	local now = ns.Compat.Now()
	local rows, count, mobKey = Model.rows, Model.count, Model.mobKey
	local inCombat = Scanner.inCombat == true
	if mobKey ~= lastMobKey or (inCombat and not wasInCombat) then
		for i = 1, #rows do resetRow(rows[i]) end
	end
	lastMobKey, wasInCombat = mobKey, inCombat

	-- who is a tank (SPEC-03 §2.1)
	local designated, readable = 0, false
	for i = 1, count do
		local rec = rows[i].record
		if rec.role == "TANK" then designated = designated + 1 end
		local row = rows[i]
		if row.present and not row.stale and rec.mode ~= "none" then readable = true end
	end
	local holderRow = Model.holder
	ThreatState.designated = designated
	ThreatState.tank = holderRow
	if holderRow then
		ThreatState.tankReason = nil
	else
		ThreatState.tankReason = readable and "not-watched" or "unknown"
	end
	local holderTank = false
	for i = 1, count do
		local row = rows[i]
		if designated > 0 then row.isTank = row.record.role == "TANK" else row.isTank = row.isHolder == true end
		if row == holderRow then holderTank = row.isTank end
	end

	local dwell, changes, selfRow = ThreatState.DEFAULTS.dwell, 0, nil
	recheckAt = nil
	for i = 1, count do
		local row = rows[i]
		local rec = row.record
		local unitKey = rec.unitKey
		if row.stateUnit ~= unitKey then resetRow(row) end   -- the roster moved this place to another unit
		row.stateUnit = unitKey
		local old = row.state
		if not row.present then
			if old ~= nil then
				resetRow(row)
				row.stateUnit = unitKey
				changes = changes + 1
				ThreatState.changes = ThreatState.changes + 1
				emit("STATE_CHANGED", unitKey, mobKey, old, nil)
			end
		else
			if rec.unitToken == "player" then selfRow = row end
			local new, why, t = target(row, holderRow, holderTank)
			if new == old then
				row.stateReason, row.predictedIn = why, t
			elseif old == nil or rises(old, new) or now - row.stateSince >= dwell - 1e-9 then
				row.state, row.stateReason, row.predictedIn, row.stateSince = new, why, t, now
				changes = changes + 1
				ThreatState.changes = ThreatState.changes + 1
				emit("STATE_CHANGED", unitKey, mobKey, old, new)
			else
				holdUntil(row.stateSince + dwell)   -- a fall too soon: kept, checked again (MON-12)
			end
		end
	end
	for i = count + 1, #rows do
		local row = rows[i]
		if row.stateUnit ~= nil or row.state ~= nil then resetRow(row) end
	end
	ThreatState.self = selfRow

	local mode, reason = Scanner.mode or "none", Scanner.modeReason
	if mode ~= ThreatState.mode or reason ~= ThreatState.modeReason then
		ThreatState.mode, ThreatState.modeReason = mode, reason
		emit("THREAT_MODE_CHANGED", mode, reason)
	end

	if recheckAt and not timerPending then
		timerPending = true
		if not ns.Compat.After(recheckAt - now + 1e-3, recheck) then timerPending = false end
	end
	return changes
end

-- The state of a row (nil when the unit is not on the list) and its reason.
function ThreatState.Of(row)
	if not row then return nil end
	return row.state, row.stateReason
end

-- The one timer of the held downgrades: the rows age (the model) and the states follow, also after the combat.
recheck = function()
	timerPending = false
	if not (ns.Features and ns.Features.On("monitor")) or not ns.ThreatModel then return end
	ns.ThreatModel.Update()
	emit("THREAT_UPDATED", ns.ThreatModel.mobKey)
end

if ns.Bus then
	local Bus = ns.Bus
	Bus.On("THREAT_UPDATED", function()
		if not (ns.Features and ns.Features.On("monitor")) then return end
		ThreatState.Update()
	end)
	Bus.On("CONFIG_CHANGED", function(path)
		if path == WARNING_PATH or path == DANGER_PATH then readSettings() end
	end)
	Bus.On("CONFIG_LOADED", readSettings)
end

if ns.addon then ns.addon.ThreatState = ThreatState end
