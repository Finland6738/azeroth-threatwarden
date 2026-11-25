-- ThreatScanner: who is read, when, and the pooled records of the reads (SPEC-03 §1.3–§1.4, SPEC-02 §1, ADR 0004).
-- Lua 5.1. Threatwarden's own.
--
-- Units watched, in roster order: "player", "pet" (when it exists), then party1-party4 in a party or raid1-raidN in a
-- raid, without the player's own raidN (Compat.Group.RaidIndex, UnitInRaid). The list is rebuilt only at
-- GROUP_ROSTER_UPDATE, UNIT_PET of the player and COMBAT_STARTED; names, class and role are read then, never per scan.
-- One record per unit from a pool that only grows (DAT-11): a scan allocates nothing (ARC-06, MON-08).
--
-- maxUnits (default 40, until schema 2 of Core/Config.lua in M2.6) is how many units one scan reads: player, pet, the
-- designated tanks (role TANK) and whoever held the mob at the last scan are read every time, the other places go round
-- robin in roster order. Each record carries `interval`, the time expected between two reads of it (1 / rate, times the
-- number of turns of the round robin), for the freshness of Data/ThreatModel.lua (SPEC-03 §1.5).
--
-- The scanner is active only while all of these hold (SPEC-03 §1.4, ARC-05): the `monitor` switch is on and the client
-- is recognised (ARC-01); the player is in combat; TargetTracker has a mob; a consumer wants it
-- (ThreatScanner.Want(name, on): in M2 the window, while it is shown on the Monitor tab). Otherwise nothing is read, no
-- tick runs and the threat events are not registered.
--
--   Tick: Scheduler.Start("threat", rate, scan, { combat = true }), rate 2-10 Hz, 5 provisional (Q14) [probe P10].
--   UNIT_THREAT_LIST_UPDATE(unit) for the mob (its token, or UnitIsUnit with it): a full scan is asked.
--   UNIT_THREAT_SITUATION_UPDATE(unit) for a watched token: that unit is read.
-- Asked scans are gathered (MON-07): at most one full scan every MIN_GAP (0.1 s); the waiting one runs at the end of the
-- gap, with one callback made once; a one-unit read merges into a waiting scan. Every read is of the current state,
-- with its own observedAt, so a duplicate or late event costs one read at most and never a wrong value; an event for a
-- unit that is not watched, for another mob, or with a secret payload, is ignored. [probe P6]: with timely events M0.7
-- may lower the tick to a safety net (SAFETY_HZ).
--
-- A read is Compat.Threat.Read (values, state only or none, with the reason: secret, nil, error, missing, no-unit),
-- plus Compat.Threat.ReadLead once per scan for the unit holding the mob. Secret values are never read: Compat turns
-- them into nil with their reason. Each full scan emits THREAT_SCANNED(mobKey) and sets the threat capabilities
-- (SPEC-03 §1.1); the mode of the monitor (MON-04) is kept in ThreatScanner.mode for Data/ThreatState.lua (M2.4).
local ADDON_NAME, ns = ...
ns = ns or {}
ns.modules = ns.modules or {}

local ThreatScanner = {}
ns.ThreatScanner, ns.modules.ThreatScanner = ThreatScanner, ThreatScanner

local Compat = ns.Compat
local Unit, Group, Threat = Compat.Unit, Compat.Group, Compat.Threat
local type, pairs, pcall, error = type, pairs, pcall, error
local floor, ceil = math.floor, math.ceil

-- Used until schema 2 of Core/Config.lua (M2.6) stores account.settings.monitor.rate and .maxUnits (Q14).
ThreatScanner.DEFAULTS = { rate = 5, maxUnits = 40 }
ThreatScanner.MIN_RATE, ThreatScanner.MAX_RATE = 2, 10
ThreatScanner.MIN_UNITS, ThreatScanner.MAX_UNITS = 5, 40
ThreatScanner.MIN_GAP = 0.1          -- seconds between two full scans asked by events (MON-07)
ThreatScanner.SAFETY_HZ = nil        -- [probe P6]: a lower safety-net tick when the events prove timely
ThreatScanner.TICK = "threat"
local RATE_PATH, UNITS_PATH = "account.settings.monitor.rate", "account.settings.monitor.maxUnits"

local PARTY, RAID = {}, {}
for i = 1, 4 do PARTY[i] = "party" .. i end
for i = 1, 40 do RAID[i] = "raid" .. i end

ThreatScanner.units = {}      -- the watched tokens, in roster order
ThreatScanner.records = {}    -- the pool: records[i] is the record of units[i] (more may wait unused)
ThreatScanner.count = 0       -- watched units
local units, records = ThreatScanner.units, ThreatScanner.records
local byToken = {}            -- token -> record, for the situation events

ThreatScanner.consumers = {}  -- name -> true
ThreatScanner.enabled = false -- game events of the roster registered (the monitor switch was on at login)
ThreatScanner.active = false
ThreatScanner.inCombat = false
ThreatScanner.mode = "none"   -- the best mode of the last full scan (MON-04)
ThreatScanner.modeReason = nil
ThreatScanner.lastScanAt = -math.huge
ThreatScanner.scans, ThreatScanner.reads = 0, 0
ThreatScanner.turns = 1       -- turns of the round robin at the last scan (1: everybody read)
ThreatScanner.holder = nil    -- the record holding the mob at the last scan

local rate, maxUnits = ThreatScanner.DEFAULTS.rate, ThreatScanner.DEFAULTS.maxUnits
local scanning, pending = false, false
local window = { shown = false, tab = nil }
local cursor = 0              -- the round robin: the last record index read in turn

local function emit(event, ...)
	if ns.Bus then ns.Bus.Emit(event, ...) end
end

local function clampSetting(path, low, high, default)
	local value = ns.Config and ns.Config.Get and ns.Config:Get(path)
	if type(value) ~= "number" or value ~= value then return default end
	value = floor(value + 0.5)
	if value < low then return low end
	if value > high then return high end
	return value
end

local function readSettings()
	rate = clampSetting(RATE_PATH, ThreatScanner.MIN_RATE, ThreatScanner.MAX_RATE, ThreatScanner.DEFAULTS.rate)
	maxUnits = clampSetting(UNITS_PATH, ThreatScanner.MIN_UNITS, ThreatScanner.MAX_UNITS, ThreatScanner.DEFAULTS.maxUnits)
end

function ThreatScanner.Rate() return rate end
function ThreatScanner.MaxUnits() return maxUnits end

---------------------------------------------------------------------------------------------------------------------
-- Records and the roster
---------------------------------------------------------------------------------------------------------------------
local function clearReading(rec)
	rec.mode, rec.reason, rec.observedAt, rec.source, rec.stale = "none", nil, 0, "unknown", false
	rec.isTanking, rec.situation, rec.scaledPercent, rec.rawPercent, rec.rawThreat = nil, nil, nil, nil, nil
	rec.leadPercent, rec.leadSituation, rec.leadReason = nil, nil, nil
	rec.mobToken, rec.mobKey, rec.scanned = nil, nil, false
end

local function newRecord()
	local rec = Threat.NewRecord()
	rec.interval = 1 / rate
	clearReading(rec)
	return rec
end

-- Name, class and role of a record, and its key ("unit:" .. GUID, else "tok:" .. token). Never a secret value.
local function readIdentity(rec)
	local token = rec.unitToken
	local guid = Unit.GUID(token)
	rec.unitKey = guid and ("unit:" .. guid) or ("tok:" .. token)
	rec.unitName = (Unit.Name(token))
	rec.classFile = (Unit.Class(token))
	local role, reason = Unit.Role(token)
	rec.role = role
	if reason == "secret" then
		Compat:SetCapability("roles", Compat.RESTRICTED, "secret role")
	elseif reason == nil or reason == "none" then
		Compat:SetCapability("roles", Compat.AVAILABLE, nil)
	end
end

local function addUnit(n, token, always)
	local rec = records[n]
	if not rec then
		rec = newRecord()
		records[n] = rec
	end
	if rec.unitToken ~= token then clearReading(rec) end
	rec.unitToken, rec.always, rec.inUse = token, always, true
	units[n] = token
	byToken[token] = rec
	readIdentity(rec)
	return n
end

-- Builds the list of watched units again (SPEC-03 §1.3). Allocates only for a bigger roster than ever before.
function ThreatScanner.Rebuild()
	for token in pairs(byToken) do byToken[token] = nil end
	local n = addUnit(1, "player", true)
	if Unit.Exists("pet") == true then n = addUnit(n + 1, "pet", true) end
	if Group.InRaid() then
		local size, me = Group.Size(), Group.RaidIndex()
		if size > 40 then size = 40 end
		for i = 1, size do
			local token = RAID[i]
			if i ~= me and not (me == nil and Unit.IsUnit(token, "player") == true) then
				n = addUnit(n + 1, token, false)
			end
		end
	elseif Group.InGroup() then
		local size = Group.Size() - 1
		if size > 4 then size = 4 end
		for i = 1, size do n = addUnit(n + 1, PARTY[i], false) end
	end
	for i = n + 1, #units do units[i] = nil end
	for i = n + 1, #records do
		local rec = records[i]
		if rec.inUse then
			clearReading(rec)
			rec.inUse, rec.unitToken, rec.unitKey, rec.unitName, rec.classFile, rec.role = false, nil, nil, nil, nil, nil
		end
	end
	ThreatScanner.count = n
	if cursor > n then cursor = 0 end
	ThreatScanner.holder = nil
	return n
end

function ThreatScanner.RecordOf(token) return byToken[token] end

local function clearAll()
	for i = 1, ThreatScanner.count do clearReading(records[i]) end
	ThreatScanner.holder = nil
	ThreatScanner.mode, ThreatScanner.modeReason = "none", nil
end

---------------------------------------------------------------------------------------------------------------------
-- Reading
---------------------------------------------------------------------------------------------------------------------
local RANK = { values = 3, state = 2, none = 1 }

local function readOne(rec, mobToken, mobKey)
	rec.mode = Threat.Read(rec.unitToken, mobToken, rec)
	rec.mobToken, rec.mobKey, rec.stale, rec.scanned = mobToken, mobKey, false, true
	ThreatScanner.reads = ThreatScanner.reads + 1
end

local function holds(rec)
	if rec.isTanking == true then return true end
	local s = rec.situation
	return rec.mode ~= "none" and type(s) == "number" and s >= 2
end

-- What the reads of the last scan proved (SPEC-03 §1.1). Only a decisive answer changes a capability.
local function setCapabilities(anyValues, anyState, anySecret, anyMissing, groupRead, holder)
	if anyValues then
		Compat:SetCapability("threatValues", Compat.AVAILABLE, nil)
	elseif anySecret then
		Compat:SetCapability("threatValues", Compat.RESTRICTED, "secret values")
	elseif anyMissing then
		Compat:SetCapability("threatValues", Compat.MISSING, nil)
	end
	if anyValues or anyState then
		Compat:SetCapability("threatState", Compat.AVAILABLE, nil)
	elseif anySecret then
		Compat:SetCapability("threatState", Compat.RESTRICTED, "secret state")
	elseif anyMissing then
		Compat:SetCapability("threatState", Compat.MISSING, nil)
	end
	if holder then
		if holder.leadPercent ~= nil then
			Compat:SetCapability("threatLead", Compat.AVAILABLE, nil)
		elseif holder.leadReason == "secret" then
			Compat:SetCapability("threatLead", Compat.RESTRICTED, "secret lead")
		elseif holder.leadReason == "missing" then
			Compat:SetCapability("threatLead", Compat.MISSING, nil)
		end
	end
	if groupRead then Compat:SetCapability("groupThreat", Compat.AVAILABLE, nil) end
end

local function scanBody()
	local Tracker = ns.TargetTracker
	if not (Tracker and Tracker.Check()) or not ThreatScanner.active then return end
	local mobToken, mobKey = Tracker.mobToken, Tracker.mobKey
	local count, period = ThreatScanner.count, 1 / rate
	local budget = maxUnits
	local lastHolder = ThreatScanner.holder

	-- first the units read every time
	local fixed = 0
	for i = 1, count do
		local rec = records[i]
		rec.scanned = false
		if rec.always or rec.role == "TANK" or rec == lastHolder then
			fixed = fixed + 1
			if budget > 0 then
				readOne(rec, mobToken, mobKey)
				rec.interval = period
				budget = budget - 1
			end
		end
	end
	-- then the others in turn
	local others = count - fixed
	local turns = 1
	if others > 0 then
		if budget <= 0 then
			turns = 0   -- no place left: they wait (interval nil below)
		else
			turns = ceil(others / budget)
			local visited, i = 0, cursor
			while budget > 0 and visited < count do
				i = i % count + 1
				visited = visited + 1
				local rec = records[i]
				if not rec.scanned then
					readOne(rec, mobToken, mobKey)
					budget = budget - 1
					cursor = i
				end
			end
		end
		for i = 1, count do
			local rec = records[i]
			if not (rec.always or rec.role == "TANK" or rec == lastHolder) then
				rec.interval = turns > 0 and period * turns or nil
			end
		end
	end
	ThreatScanner.turns = turns

	-- who holds the mob, the lead of the holder, the mode and the capabilities
	local holder, best, bestReason, playerRec = nil, nil, nil, nil
	local anyValues, anyState, anySecret, anyMissing, groupRead = false, false, false, false, false
	for i = 1, count do
		local rec = records[i]
		if rec.scanned then
			local mode, reason = rec.mode, rec.reason
			if not holder and holds(rec) then holder = rec end
			if mode == "values" then anyValues = true elseif mode == "state" then anyState = true end
			if reason == "secret" then anySecret = true elseif reason == "missing" then anyMissing = true end
			if mode ~= "none" and not rec.always then groupRead = true end
			if reason ~= "nil" or mode ~= "none" then
				if not best or RANK[mode] > RANK[best] then best = mode end
				if mode == "none" and not bestReason then bestReason = reason end
			end
			if rec.unitToken == "player" then playerRec = rec end
		end
	end
	if holder then Threat.ReadLead(holder.unitToken, mobToken, holder) end
	ThreatScanner.holder = holder
	if playerRec and (playerRec.reason ~= "nil" or playerRec.mode ~= "none") then bestReason = playerRec.reason end
	ThreatScanner.mode = best or "none"
	if best then ThreatScanner.modeReason = bestReason else ThreatScanner.modeReason = "nil" end
	setCapabilities(anyValues, anyState, anySecret, anyMissing, groupRead, holder)

	ThreatScanner.lastScanAt = Compat.Now()
	ThreatScanner.scans = ThreatScanner.scans + 1
	emit("THREAT_SCANNED", mobKey)
end

-- One full scan now (the tick, a gathered event, a test). Allocation-free after the warm-up (MON-08).
function ThreatScanner.Scan()
	if scanning or not ThreatScanner.active then return false end
	scanning = true
	local ok, err = pcall(scanBody)
	scanning = false
	if not ok then error(err, 0) end
	return true
end
local scan = ThreatScanner.Scan

-- The waiting scan of MON-07: the one callback, made once.
local function flush()
	pending = false
	if ThreatScanner.active and Compat.Now() - ThreatScanner.lastScanAt >= ThreatScanner.MIN_GAP - 1e-6 then scan() end
end

-- An event asks a full scan: now, or at the end of the gap when one ran less than MIN_GAP ago.
function ThreatScanner.RequestScan()
	if not ThreatScanner.active or scanning or pending then return false end
	local wait = ThreatScanner.lastScanAt + ThreatScanner.MIN_GAP - Compat.Now()
	if wait <= 1e-6 then return scan() end
	pending = true
	if not Compat.After(wait, flush) then pending = false end
	return false
end

-- An event asks one unit: read now, unless a full scan is waiting (it will read the unit).
local function requestUnit(rec)
	if not ThreatScanner.active or scanning or pending then return end
	local Tracker = ns.TargetTracker
	local mobToken, mobKey = Tracker.mobToken, Tracker.mobKey
	if not mobToken then return end
	readOne(rec, mobToken, mobKey)
	emit("THREAT_SCANNED", mobKey)
end

---------------------------------------------------------------------------------------------------------------------
-- Being active
---------------------------------------------------------------------------------------------------------------------
local function hasConsumer()
	for _ in pairs(ThreatScanner.consumers) do return true end
	return false
end

local function shouldRun()
	if not ThreatScanner.enabled or not (ns.Features and ns.Features.On("monitor")) then return false end
	if ns.addon and ns.addon.isForever == false then return false end
	local Tracker = ns.TargetTracker
	return ThreatScanner.inCombat and Tracker ~= nil and Tracker.mobToken ~= nil and hasConsumer()
end

local threatEvents = {}

local function tick() scan() end

local function start()
	ThreatScanner.active = true
	readSettings()
	ThreatScanner:RegisterEvent("UNIT_THREAT_LIST_UPDATE", threatEvents.onEvent)
	ThreatScanner:RegisterEvent("UNIT_THREAT_SITUATION_UPDATE", threatEvents.onEvent)
	ns.Scheduler.Start(ThreatScanner.TICK, rate, tick, { combat = true })
	scan()
end

local function stop()
	ThreatScanner.active, pending = false, false
	ns.Scheduler.Stop(ThreatScanner.TICK)
	ThreatScanner:UnregisterEvent("UNIT_THREAT_LIST_UPDATE")
	ThreatScanner:UnregisterEvent("UNIT_THREAT_SITUATION_UPDATE")
end

-- Starts or stops the scanner to match its conditions. Returns whether it is active.
function ThreatScanner.Refresh()
	local want = shouldRun()
	if want and not ThreatScanner.active then start()
	elseif not want and ThreatScanner.active then stop() end
	return ThreatScanner.active
end

-- A consumer wants the readings (on) or no longer (off): the window in M2, alerts (M3) and recording (M4) later.
function ThreatScanner.Want(name, on)
	if type(name) ~= "string" then return false end
	ThreatScanner.consumers[name] = on and true or nil
	return ThreatScanner.Refresh()
end

local function windowWants()
	local tab = window.tab
	if tab == nil then tab = ns.Config and ns.Config.Get and ns.Config:Get("char.ui.lastTab") or "monitor" end
	return window.shown and tab == "monitor"
end

---------------------------------------------------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------------------------------------------------
function threatEvents.onEvent(event, unit)
	if not ThreatScanner.active or type(unit) ~= "string" or Compat.IsSecret(unit) then return end
	local mobToken = ns.TargetTracker and ns.TargetTracker.mobToken
	if not mobToken then return end
	if event == "UNIT_THREAT_LIST_UPDATE" then
		if unit == mobToken or Unit.IsUnit(unit, mobToken) == true then
			Compat:SetCapability("threatEvents", Compat.AVAILABLE, nil)
			ThreatScanner.RequestScan()
		end
	elseif event == "UNIT_THREAT_SITUATION_UPDATE" then
		local rec = byToken[unit]
		if rec then requestUnit(rec) end
	end
end

local function onRoster(event, unit)
	if event == "UNIT_PET" and unit ~= "player" then return end
	ThreatScanner.Rebuild()
	ThreatScanner.Refresh()
end

function ThreatScanner.Enable()
	if ThreatScanner.enabled or not (ns.Features and ns.Features.On("monitor")) then return false end
	local AceEvent = LibStub and LibStub("AceEvent-3.0", true)
	if not AceEvent then return false end
	AceEvent:Embed(ThreatScanner)
	ThreatScanner:RegisterEvent("GROUP_ROSTER_UPDATE", onRoster)
	ThreatScanner:RegisterEvent("UNIT_PET", onRoster)
	ThreatScanner.enabled = true
	readSettings()
	ThreatScanner.inCombat = ns.addon and ns.addon.inCombat == true or false
	if ns.addon and ns.addon.AddDebugSection then ns.addon:AddDebugSection("Threat scanner", ThreatScanner.DebugLines) end
	ThreatScanner.Rebuild()
	ThreatScanner.Refresh()
	return true
end

if ns.Bus then
	local Bus = ns.Bus
	Bus.On("COMBAT_STARTED", function()
		ThreatScanner.inCombat = true
		if not ThreatScanner.enabled then return end
		ThreatScanner.Rebuild()
		clearAll()
		ThreatScanner.Refresh()
	end)
	Bus.On("COMBAT_ENDED", function()
		ThreatScanner.inCombat = false
		for i = 1, ThreatScanner.count do records[i].stale = true end   -- SPEC-03 §1.4: kept, all stale
		ThreatScanner.Refresh()
	end)
	Bus.On("TARGET_CHANGED", function()
		if not ThreatScanner.enabled then return end
		clearAll()
		local was = ThreatScanner.active
		if ThreatScanner.Refresh() and was then ThreatScanner.RequestScan() end
	end)
	Bus.On("WINDOW_SHOWN", function(shown)
		window.shown = shown == true
		ThreatScanner.Want("window", windowWants())
	end)
	Bus.On("TAB_CHANGED", function(tabId)
		window.tab = tabId
		ThreatScanner.Want("window", windowWants())
	end)
	Bus.On("CONFIG_CHANGED", function(path)
		if path ~= RATE_PATH and path ~= UNITS_PATH then return end
		local oldRate = rate
		readSettings()
		if ThreatScanner.active and rate ~= oldRate then
			ns.Scheduler.Start(ThreatScanner.TICK, rate, tick, { combat = true })
		end
	end)
end
if ns.OnEnable then ns.OnEnable(ThreatScanner.Enable) end

-- /atw debug: counts and modes only, never a name, a GUID or a value.
function ThreatScanner.DebugLines()
	return {
		("%s, %d unit(s) watched, max %d, %g Hz, %d turn(s)"):format(ThreatScanner.active and "active" or "idle",
			ThreatScanner.count, maxUnits, rate, ThreatScanner.turns),
		("%d scan(s), %d read(s), mode %s%s"):format(ThreatScanner.scans, ThreatScanner.reads, ThreatScanner.mode,
			ThreatScanner.modeReason and (" (" .. ThreatScanner.modeReason .. ")") or ""),
	}
end

if ns.addon then ns.addon.ThreatScanner = ThreatScanner end
