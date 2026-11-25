-- ThreatModel: the normalized rows of the monitor, one per watched unit (SPEC-02 §1–§2, SPEC-03 §1.5–§1.6, §2.5,
-- ADR 0003). Lua 5.1, no game API (the clock through Compat.Now). Threatwarden's own.
--
-- rows[i] belongs to ThreatScanner.records[i] (row.record): the record is the last read as the scanner and Compat left
-- it (mode, reason, values, observedAt, interval); the row adds what is derived from it, every value with its category
-- and, when it is nil, the reason (DAT-10, ADR 0003):
--
--   row.present          the unit is on the mob's threat list: read, and not reason "nil" (MON-05: absent, not unknown)
--   row.stale            the read is older than max(2 * interval, 0.5 s), or the combat ended (DAT-12, SPEC-03 §1.5)
--   row.reason           why the values are not shown: the read's reason, or "stale"; nil for a fresh `values` row
--   row.isHolder         the row holds the mob (ThreatScanner.holder)
--   row.margin           calculated: 100 - p, or the tank margin for the holder (ThreatCalc), with marginReason
--   row.trend            estimated: points per second, trendConfidence, trendSamples, with trendReason
--                        ("insufficient" = Insufficient data, "state-only", or the row's reason)
--   row.overtakeIn       predicted: whole seconds, with overtakeReason (ThreatCalc.Overtake, "holder")
--   isTank, state, stateReason, stateSince   kept for Data/ThreatState.lua (M2.4)
--
-- The record gets its confidence: "high" for a fresh read in `values` or `state`, "low" when stale, "unknown" in
-- `none`. ThreatModel.Category(row, field) gives the category of a field (detected, calculated, estimated, predicted;
-- "unknown" when the value is nil) and ThreatModel.Reason(row, field) why it is nil.
--
-- Samples of the trend (SPEC-03 §2.5): only from fresh `values` reads with a scaled %, never twice the same observedAt;
-- reset at a new mob (TARGET_CHANGED), at COMBAT_STARTED, when the unit holding the mob changes, after a gap of more
-- than 1 s and when the row leaves the list or changes unit. Rows and their rings come from a pool that only grows with
-- the roster (DAT-11): an update allocates nothing (ARC-06).
--
-- Updates: on THREAT_SCANNED (every full scan and every one-unit read), TARGET_CHANGED, COMBAT_STARTED and COMBAT_ENDED,
-- each followed by THREAT_UPDATED(mobKey) on the Bus; only while the `monitor` switch is on (ADR 0014).
-- ThreatModel.Update() can also be called to age the rows between two scans (the view, M2.5).
local ADDON_NAME, ns = ...
ns = ns or {}
ns.modules = ns.modules or {}

local ThreatModel = {}
ns.ThreatModel, ns.modules.ThreatModel = ThreatModel, ThreatModel

local Calc = ns.ThreatCalc
local type = type

-- The category of each value of a row (ADR 0003 point 4). Fields of the record are read from row.record.
ThreatModel.CATEGORY = {
	scaledPercent = "detected", rawPercent = "detected", rawThreat = "detected", isTanking = "detected",
	situation = "detected", leadPercent = "detected", leadSituation = "detected",
	margin = "calculated", trend = "estimated", overtakeIn = "predicted",
}
local RECORD_FIELD = {
	scaledPercent = true, rawPercent = true, rawThreat = true, isTanking = true, situation = true,
	leadPercent = true, leadSituation = true,
}
local LEAD_FIELD = { leadPercent = true, leadSituation = true }

ThreatModel.rows = {}
ThreatModel.count = 0
ThreatModel.mobKey = nil
ThreatModel.holder = nil       -- the row holding the mob at the last update
ThreatModel.updates = 0
local rows = ThreatModel.rows
local lastHolderRecord = nil   -- the last record seen holding the mob (nil: none yet in this fight and mob)
local lastMobKey, wasInCombat = nil, false

local function emit(event, ...)
	if ns.Bus then ns.Bus.Emit(event, ...) end
end

local function clearDerived(row)
	row.present, row.stale, row.reason, row.isHolder = false, false, nil, false
	row.margin, row.marginReason = nil, nil
	row.trend, row.trendConfidence, row.trendSamples, row.trendReason = nil, "unknown", 0, "insufficient"
	row.overtakeIn, row.overtakeReason = nil, "insufficient"
end

local function newRow()
	local row = { samples = Calc.NewSamples(), isTank = false, state = "UNKNOWN", stateReason = nil, stateSince = 0 }
	clearDerived(row)
	return row
end

-- Resets every ring of samples (a new mob, a new combat, a new holder).
local function resetSamples()
	for i = 1, #rows do Calc.Reset(rows[i].samples) end
end

-- The fresh part of a row: present, stale, reason, the record's confidence, and the sample of the trend.
local function readRow(row, rec, now)
	if row.unitToken ~= rec.unitToken then   -- the roster moved this place to another unit
		row.unitToken = rec.unitToken
		Calc.Reset(row.samples)
	end
	local mode, reason = rec.mode, rec.reason
	local read = (rec.observedAt or 0) > 0 and rec.mobKey ~= nil
	local present = read and not (mode == "none" and reason == "nil")
	row.present = present
	if not present then
		row.stale, row.reason = false, read and reason or nil
		rec.confidence = "unknown"
		Calc.Reset(row.samples)                 -- the row left the list (SPEC-03 §2.5)
		return
	end
	local stale = rec.stale == true or Calc.IsStale(rec.observedAt, rec.interval, now)
	row.stale = stale
	if stale then
		row.reason = "stale"
		rec.confidence = mode == "none" and "unknown" or "low"
		return
	end
	row.reason = reason
	rec.confidence = mode == "none" and "unknown" or "high"
	if mode == "values" and type(rec.scaledPercent) == "number" then
		Calc.Push(row.samples, rec.observedAt, rec.scaledPercent)
	end
end

-- The derived values of a row, once every row has been read (the holder's margin needs the others).
local function calcRow(row, rec, now, second, others, otherReason)
	if not row.present then
		row.margin, row.marginReason = nil, row.reason or "missing"
		row.trend, row.trendConfidence, row.trendSamples, row.trendReason = nil, "unknown", 0, row.reason or "missing"
		row.overtakeIn, row.overtakeReason = nil, row.trendReason
		return
	end
	local mode = rec.mode
	if row.stale or mode == "none" then
		local why = row.reason or "missing"
		row.margin, row.marginReason = nil, why
		row.trend, row.trendConfidence, row.trendSamples, row.trendReason = nil, "unknown", 0, why
		row.overtakeIn, row.overtakeReason = nil, why
		return
	end
	if mode == "state" then
		row.margin, row.marginReason = nil, "state-only"
		row.trend, row.trendConfidence, row.trendSamples, row.trendReason = nil, "unknown", 0, "state-only"
		row.overtakeIn, row.overtakeReason = nil, "state-only"
		return
	end
	-- values
	if row.isHolder then
		row.margin, row.marginReason = Calc.TankMargin(second, others, otherReason, rec.leadPercent)
	else
		row.margin, row.marginReason = Calc.Margin(rec.scaledPercent)
	end
	local trend, confidence, n = Calc.Trend(row.samples, now)
	row.trend, row.trendConfidence, row.trendSamples = trend, confidence, n
	row.trendReason = trend == nil and "insufficient" or nil
	if row.isHolder then
		row.overtakeIn, row.overtakeReason = nil, "holder"
	else
		row.overtakeIn, row.overtakeReason = Calc.Overtake(rec.scaledPercent, trend, confidence)
	end
end

-- Brings every row up to date with the scanner's records. Allocates only when the roster is bigger than ever before.
-- Returns the number of rows.
function ThreatModel.Update()
	local Scanner = ns.ThreatScanner
	if not Scanner then return 0 end
	local records, count = Scanner.records, Scanner.count
	local now = ns.Compat.Now()
	-- a new mob or a new combat: everything starts again. Checked here, not in the Bus handlers, because the scanner
	-- scans inside its own TARGET_CHANGED and COMBAT_STARTED handlers, which run before ours (TOC order).
	local mobKey = ns.TargetTracker and ns.TargetTracker.mobKey or nil
	local inCombat = Scanner.inCombat == true
	if mobKey ~= lastMobKey or (inCombat and not wasInCombat) then
		resetSamples()
		lastHolderRecord = nil
	end
	lastMobKey, wasInCombat = mobKey, inCombat
	local holderRecord = Scanner.holder
	if holderRecord ~= nil and holderRecord ~= lastHolderRecord then
		if lastHolderRecord ~= nil then resetSamples() end   -- the percentages are measured on another tank now
		lastHolderRecord = holderRecord
	end
	for i = 1, count do
		local row = rows[i]
		if not row then
			row = newRow()
			rows[i] = row
		end
		local rec = records[i]
		row.record = rec
		row.isHolder = rec == holderRecord
		readRow(row, rec, now)
	end
	for i = count + 1, #rows do
		local row = rows[i]
		if row.record then
			row.record, row.unitToken = nil, nil
			clearDerived(row)
			Calc.Reset(row.samples)
		end
	end
	-- the second: the highest fresh scaled % among the others read in values (SPEC-03 §2.2)
	local holder, second, others, otherReason = nil, nil, 0, nil
	for i = 1, count do
		local row = rows[i]
		if row.isHolder then
			holder = row
		elseif row.present then
			others = others + 1
			local rec = row.record
			if not row.stale and rec.mode == "values" and type(rec.scaledPercent) == "number" then
				if second == nil or rec.scaledPercent > second then second = rec.scaledPercent end
			elseif otherReason == nil then
				otherReason = (rec.mode == "state" and not row.stale) and "state-only" or row.reason
			end
		end
	end
	for i = 1, count do
		local row = rows[i]
		calcRow(row, row.record, now, second, others, otherReason)
	end
	ThreatModel.count, ThreatModel.holder = count, holder
	ThreatModel.mobKey = mobKey
	ThreatModel.updates = ThreatModel.updates + 1
	return count
end

-- The row of a watched token, or nil.
function ThreatModel.RowOf(token)
	for i = 1, ThreatModel.count do
		local row = rows[i]
		if row.record and row.record.unitToken == token then return row end
	end
	return nil
end

-- The category of `field` in `row` (ADR 0003): its own category when the value is known, "unknown" when it is nil.
function ThreatModel.Category(row, field)
	local category = ThreatModel.CATEGORY[field]
	if not category or not row then return nil end
	local value
	if RECORD_FIELD[field] then
		value = row.record and row.record[field]
	else
		value = row[field]
	end
	if value == nil then return "unknown" end
	return category
end

-- Why `field` of `row` is nil (nil when it is known): the reasons of SPEC-02 §1 and of Data/ThreatCalc.lua.
function ThreatModel.Reason(row, field)
	if not row or not ThreatModel.CATEGORY[field] then return nil end
	if ThreatModel.Category(row, field) ~= "unknown" then return nil end
	if field == "margin" then return row.marginReason end
	if field == "trend" then return row.trendReason end
	if field == "overtakeIn" then return row.overtakeReason end
	local rec = row.record
	if LEAD_FIELD[field] then
		if not row.isHolder then return "not-holder" end
		return rec and rec.leadReason or "missing"
	end
	if row.reason then return row.reason end
	if rec and rec.mode == "state" then return "state-only" end
	return "missing"
end

local function update()
	if not (ns.Features and ns.Features.On("monitor")) then return end
	ThreatModel.Update()
	emit("THREAT_UPDATED", ThreatModel.mobKey)
end

if ns.Bus then
	local Bus = ns.Bus
	Bus.On("THREAT_SCANNED", update)
	Bus.On("TARGET_CHANGED", update)
	Bus.On("COMBAT_STARTED", update)
	Bus.On("COMBAT_ENDED", update)   -- the scanner marked every record stale first (TOC order)
end

if ns.addon then ns.addon.ThreatModel = ThreatModel end
