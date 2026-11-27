-- MobTracker: the other mobs of a pull, read by a rotation of their own with a budget, and only shown (SPEC-07 §1.2-§1.7,
-- §2.6, ADR 0019). Lua 5.1. Threatwarden's own.
--
-- The monitor keeps one mob (MT-03): Data/TargetTracker.lua, the scanner, the model and the states do not change. This
-- module finds the other mobs (sources), keys them, gives a few of them a slot, reads them in turn within READ_BUDGET
-- reads per tick, and lets Data/MobRisk.lua give each a state and a reason. The monitored mob has its row in the list
-- too, built from the monitor's own records after each THREAT_UPDATED: the tracker never reads it.
--
-- Sources (SOURCES, in the order of priority; `on` is the one place the M0 probe changes, SPEC-07 §0):
--   monitored  the TargetTracker's mob (never read here)            focus   "focus" (PLAYER_FOCUS_CHANGED)
--   boss       "boss1"-"boss5" (INSTANCE_ENCOUNTER_ENGAGE_UNIT)       group   the targets of the scanner's units but the
--   plate      "nameplate1"-"nameplate40" (NAME_PLATE_UNIT_ADDED,             player: "pettarget", "party1target"...
--              _REMOVED), with settings.mobs.nameplates                       (UNIT_TARGET of a watched unit)
-- Besides the events every tick checks SWEEP tokens in turn. A token is a candidate when it exists, the player can attack
-- it, it is not dead and UnitAffectingCombat is not false (true, or secret, or an error: the first read decides).
--
-- Keys (§1.3): "mob:" .. GUID, the TargetTracker's own key, with every token that names the mob now; before a read the
-- token is checked against the GUID (UnitGUID(token) == guid) and found again with UnitTokenFromGUID. Without a readable
-- GUID only "focus" and "boss1-5" are used, keyed "tok:" .. token .. ":" .. n (n grows at each discovery event of the
-- token), and only when UnitIsUnit may compare them (C_Secrets.CanCompareUnitTokens) and says they are another mob than
-- the monitored one and than each other; otherwise they are not listed. Hence three levels of identity: GUID (every
-- source), comparison only (focus and boss), neither (the target only).
--
-- Reading (§1.6): tick "mobs" at RATE Hz while the `multitarget` switch is on, the client is recognised, the setting
-- settings.mobs.enabled is on, the player is in combat and a consumer wants it (MobTracker.Want). With no other mob known
-- the tick only sweeps (existence and GUID); the threat event UNIT_THREAT_LIST_UPDATE is registered only while there is
-- one. settings.mobs.max slots, the monitored mob included; READ_BUDGET reads per tick (each Threat.Read and ReadLead
-- count); UNITS_PER_MOB units per read (player, pet, designated tanks and the last holder always, the others in turn
-- with a cursor per slot). First the mobs an event marked, then DANGER, then in turn; at least one mob per tick. A mob
-- whose reads were all secret is read again only after RETRY seconds. Rows come from pools made once per slot and roster
-- index (DAT-11): a tick allocates nothing after the warm-up (ARC-06); a key is built only when a mob enters.
--
-- Life cycle (§1.7): a new candidate is `pending`; no watched unit on its list for FORGET seconds, or no token for FORGET
-- seconds: it leaves; dead: it leaves at once; COMBAT_ENDED: the list empties, the reach is kept as lastReach.
-- The reach (§1.4): "unknown", "all", "focus-boss", "target", "none", with reachReason ("no-guid", "no-compare",
-- "secret", "nameplates-off", "no-answer"); it sets the capability otherMobs. Bus: MOBS_UPDATED() after each tick and at
-- the end of a combat. Nothing is saved (MT-05); no name or GUID in an event or in /atw debug.
local ADDON_NAME, ns = ...
ns = ns or {}
ns.modules = ns.modules or {}

local MobTracker = {}
ns.MobTracker, ns.modules.MobTracker = MobTracker, MobTracker

local Compat = ns.Compat
local Unit, Threat = Compat.Unit, Compat.Threat
local Risk = ns.MobRisk
-- The real modules: demo mode puts invented ones in ns.TargetTracker and ns.ThreatScanner (Core/Demo.lua).
local RealTracker, RealScanner = ns.TargetTracker, ns.ThreatScanner
local type, pairs, ipairs, floor, ceil = type, pairs, ipairs, math.floor, math.ceil
local huge = math.huge

-- SPEC-09 Q26: the one place of the constants (the M0 probe P6 and P10 may change RATE and READ_BUDGET, SPEC-07 §0).
MobTracker.RATE = 2
MobTracker.READ_BUDGET = 48
MobTracker.UNITS_PER_MOB = 10
MobTracker.RETRY = 5
MobTracker.FORGET = 10
MobTracker.SWEEP = 12
MobTracker.TICK = "mobs"
-- The sources in their order of priority, each with `on` (all on until M0.7: the one place the probe P5 changes).
MobTracker.SOURCES = {
	{ kind = "monitored", on = true },
	{ kind = "focus", on = true },
	{ kind = "boss", on = true },
	{ kind = "group", on = true },
	{ kind = "plate", on = true },
}
MobTracker.REACHES = { "unknown", "none", "target", "focus-boss", "all" }
local REACH_RANK = {}
for i, reach in ipairs(MobTracker.REACHES) do REACH_RANK[reach] = i end

local PREFIX = "account.settings.mobs."
local ENABLED_PATH, MAX_PATH, PLATES_PATH = PREFIX .. "enabled", PREFIX .. "max", PREFIX .. "nameplates"
local Limits, Defaults = ns.Config.MOBS, ns.Config.MOBS_DEFAULTS

local PRIORITY = {}           -- kind -> rank in SOURCES (1 first)
for i, source in ipairs(MobTracker.SOURCES) do PRIORITY[source.kind] = i end
local NO_SOURCE = #MobTracker.SOURCES + 1
local READ_ORDER = { focus = 1, boss = 2, plate = 3, group = 4 }   -- which of a mob's tokens reads it (§1.3)
local KINDS = { "focus", "boss", "group", "plate" }

-- Tokens: their kind, and the target token of a watched unit, each string made once.
local KIND = { focus = "focus" }
local BOSS, PLATE = {}, {}
for i = 1, 5 do BOSS[i] = "boss" .. i; KIND[BOSS[i]] = "boss" end
for i = 1, 40 do PLATE[i] = "nameplate" .. i; KIND[PLATE[i]] = "plate" end
local TARGET_OF = {}          -- unit token -> its target token ("party1" -> "party1target")
local OWNER = {}              -- "party1target" -> "party1"

local function targetOf(token)
	local t = TARGET_OF[token]
	if not t then
		t = token .. "target"
		TARGET_OF[token] = t
	end
	return t
end

---------------------------------------------------------------------------------------------------------------------
-- State
---------------------------------------------------------------------------------------------------------------------
MobTracker.enabled = false    -- the game events may be registered (the switch was on at login)
MobTracker.ticking = false    -- the tick runs
MobTracker.reading = false    -- there is a mob to read: the threat event is registered
MobTracker.inCombat = false
MobTracker.consumers = {}
MobTracker.mobs = {}          -- every entry known now (no order)
MobTracker.count = 0
MobTracker.list = {}          -- the listed mobs: the monitored one first, then the slots in order
MobTracker.listCount = 0
MobTracker.reach, MobTracker.reachReason = "unknown", nil
MobTracker.lastReach, MobTracker.lastReasonReach = nil, nil
MobTracker.identity = "unknown"   -- "guid", "compare", "target" or "unknown" in this combat
MobTracker.lastTickAt = nil
MobTracker.monitored = nil    -- the entry of the monitored mob

local mobs, list = MobTracker.mobs, MobTracker.list
local byKey, byGuid, tokenMob = {}, {}, {}
local pool = {}               -- free entries (their tables kept)
local slots = {}              -- slots[s] = { rows = {}, entry, cursor }
local cand = {}               -- the candidates of a tick (reused)
local sweepList, sweepCount, sweepCursor = {}, 0, 0
local groupBase, groupCount = {}, 0   -- the units whose targets are tokens of the `group` source
local serial = 0              -- order of discovery
local tokSerial = {}          -- token -> n of its "tok:" keys
local goneKey, goneWhy = nil, nil     -- the last mob that left, and why ("dead", "lost")
local maxMobs, plates, settingOn = Defaults.max, Defaults.nameplates, Defaults.enabled
local window = { shown = false, tab = nil }
local discoveryOn, threatOn = false, false
local rrSlot = 0              -- the rotation: the last slot read in turn

-- What this combat proved, for the reach (§1.4).
local fight = { wide = false, stable = false, monitorRead = false, monitorNone = false, otherSecret = false,
	otherError = false, otherMissing = false, otherRead = false, plateSeen = false, guidSeen = false,
	guidSecret = false, compareOk = false, compareRefused = false }

-- /atw debug: counts only.
local stats = { ticks = 0, reads = 0, lastReads = 0, mobsRead = 0, turns = 1, events = {}, bySource = {} }
for _, kind in ipairs(KINDS) do
	stats.events[kind] = 0
	stats.bySource[kind] = { values = 0, state = 0, none = 0 }
end
stats.events.threat = 0
stats.bySource.lookup = { values = 0, state = 0, none = 0 }
MobTracker.stats = stats

local function emit(event, ...)
	if ns.Bus then ns.Bus.Emit(event, ...) end
end

local function sourceOn(kind)
	local i = PRIORITY[kind]
	local source = i and MobTracker.SOURCES[i]
	if not source or source.on ~= true then return false end
	if kind == "plate" and not plates then return false end
	return true
end

local function switchOn() return ns.Features ~= nil and ns.Features.On("multitarget") end

---------------------------------------------------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------------------------------------------------
local function readSettings()
	local Config = ns.Config
	local function bool(path, default)
		local v = Config and Config.Get and Config:Get(path)
		if type(v) == "boolean" then return v end
		return default
	end
	settingOn = bool(ENABLED_PATH, Defaults.enabled)
	plates = bool(PLATES_PATH, Defaults.nameplates)
	local v = Config and Config.Get and Config:Get(MAX_PATH)
	if type(v) ~= "number" or v ~= v then v = Defaults.max end
	v = floor(v + 0.5)
	if v < Limits.max.min then v = Limits.max.min elseif v > Limits.max.max then v = Limits.max.max end
	maxMobs = v
end

function MobTracker.Max() return maxMobs end
function MobTracker.Enabled() return settingOn end
function MobTracker.Nameplates() return plates end

---------------------------------------------------------------------------------------------------------------------
-- Entries
---------------------------------------------------------------------------------------------------------------------
local function clearReading(entry)
	entry.observedAt, entry.interval, entry.mode, entry.unknown = 0, nil, "none", "pending"
	entry.holder, entry.top, entry.selfRec, entry.topPercent, entry.topSituation, entry.margin = nil, nil, nil, nil, nil, nil
	entry.tankOnList, entry.designated, entry.marked, entry.readThisTick = false, 0, false, false
	entry.allSecret = false
end

local function newEntry(key, guid, now)
	local entry = pool[#pool]
	if entry then
		pool[#pool] = nil
	else
		entry = { tokens = {} }
	end
	serial = serial + 1
	entry.key, entry.guid, entry.n = key, guid, serial
	entry.tokenCount, entry.groupCount, entry.best = 0, 0, NO_SOURCE
	entry.monitored, entry.slot, entry.lookup, entry.readToken, entry.source = false, nil, nil, nil, nil
	entry.found = nil
	entry.enteredAt, entry.lastTokenAt, entry.lastOnListAt = now, now, now
	entry.state, entry.reason, entry.stateSince, entry.selfState, entry.holderKey = nil, nil, 0, nil, nil
	entry.name, entry.classification, entry.nameAt = nil, nil, -huge
	clearReading(entry)
	byKey[key] = entry
	if guid then byGuid[guid] = entry end
	MobTracker.count = MobTracker.count + 1
	mobs[MobTracker.count] = entry
	return entry
end

local function bestOf(entry)
	if entry.monitored then return PRIORITY.monitored end
	local best = NO_SOURCE
	for token in pairs(entry.tokens) do
		local rank = PRIORITY[KIND[token]] or NO_SOURCE
		if rank < best then best = rank end
	end
	return best
end

local function attach(entry, token, now)
	if tokenMob[token] == entry then
		entry.lastTokenAt = now
		return
	end
	tokenMob[token] = entry
	entry.tokens[token] = true
	entry.tokenCount = entry.tokenCount + 1
	local kind = KIND[token]
	if kind == "group" then entry.groupCount = entry.groupCount + 1 end
	if kind == "plate" then fight.plateSeen = true end
	entry.found = entry.found or kind
	entry.lastTokenAt = now
	entry.best = bestOf(entry)
end

local removeEntry

local function detach(entry, token)
	if tokenMob[token] ~= entry then return end
	tokenMob[token] = nil
	entry.tokens[token] = nil
	entry.tokenCount = entry.tokenCount - 1
	if KIND[token] == "group" then entry.groupCount = entry.groupCount - 1 end
	if entry.readToken == token then entry.readToken = nil end
	entry.best = bestOf(entry)
	-- a mob without a GUID cannot be found again once its stable token names another; without the tick (nobody looks)
	-- a mob that no token names is not kept either
	if entry.tokenCount == 0 and not entry.monitored and (entry.guid == nil or not MobTracker.ticking) then
		removeEntry(entry, "lost")
	end
end

local function freeSlot(entry)
	local s = entry.slot
	if not s then return end
	local slot = slots[s]
	if slot and slot.entry == entry then slot.entry = nil end
	entry.slot = nil
end

removeEntry = function(entry, why)
	for token in pairs(entry.tokens) do
		tokenMob[token] = nil
		entry.tokens[token] = nil
	end
	entry.tokenCount, entry.groupCount = 0, 0
	freeSlot(entry)
	Risk.Leave(entry)
	byKey[entry.key] = nil
	if entry.guid and byGuid[entry.guid] == entry then byGuid[entry.guid] = nil end
	for i = 1, MobTracker.count do
		if mobs[i] == entry then
			mobs[i] = mobs[MobTracker.count]
			mobs[MobTracker.count] = nil
			MobTracker.count = MobTracker.count - 1
			break
		end
	end
	if MobTracker.monitored == entry then MobTracker.monitored = nil end
	goneKey, goneWhy = entry.key, why
	entry.key, entry.guid, entry.monitored = nil, nil, false
	entry.holder, entry.top, entry.selfRec = nil, nil, nil
	entry.name, entry.classification = nil, nil
	pool[#pool + 1] = entry
end

local function clearAll()
	while MobTracker.count > 0 do removeEntry(mobs[MobTracker.count], nil) end
	for _, slot in ipairs(slots) do slot.entry = nil end
	MobTracker.monitored = nil
	MobTracker.listCount = 0
	for i = #list, 1, -1 do list[i] = nil end
	goneKey, goneWhy = nil, nil
	rrSlot, sweepCursor = 0, 0
end

---------------------------------------------------------------------------------------------------------------------
-- Identity
---------------------------------------------------------------------------------------------------------------------
local function noteGuid(reason)
	if reason == nil then
		fight.guidSeen = true
		Compat:SetCapability("mobIdentity", Compat.AVAILABLE, nil)
	elseif reason == "secret" then
		fight.guidSecret = true
		Compat:SetCapability("mobIdentity", Compat.RESTRICTED, "secret GUID")
	end
end

local function identity()
	if fight.guidSeen then return "guid" end
	if fight.guidSecret then
		if fight.compareOk then return "compare" end
		if fight.compareRefused then return "target" end
	end
	return "unknown"
end

-- Whether two tokens name the same unit: true, false, or nil when the client does not let them be compared.
local function sameUnit(a, b)
	local can = Unit.CanCompare(a, b)
	if can ~= true then
		fight.compareRefused = true
		return nil
	end
	fight.compareOk = true
	local same = Unit.IsUnit(a, b)
	if same == nil then return nil end
	return same
end

-- For a stable token without a GUID: the entry of the same mob, or nil and whether it is known to be another mob than
-- the monitored one and every other entry without a GUID.
local function findSame(token)
	local Tracker = RealTracker
	local mobToken = Tracker and Tracker.mobToken
	if mobToken then
		local same = sameUnit(token, mobToken)
		if same == nil then return nil, false end
		if same then return MobTracker.monitored, true end
	end
	for i = 1, MobTracker.count do
		local entry = mobs[i]
		if entry.guid == nil and not entry.monitored then
			for other in pairs(entry.tokens) do
				if other ~= token then
					local same = sameUnit(token, other)
					if same == nil then return nil, false end
					if same then return entry, true end
				end
			end
		end
	end
	return nil, true
end

---------------------------------------------------------------------------------------------------------------------
-- Discovery
---------------------------------------------------------------------------------------------------------------------
local function candidate(token)
	if Unit.Exists(token) ~= true then return false, "gone" end
	if Unit.CanAttack("player", token) ~= true then return false, "friendly" end
	if Unit.IsDead(token) == true then return false, "dead" end
	if Unit.AffectingCombat(token) == false then return false, "idle" end
	return true, nil
end

-- Looks at `token` again: a new mob, the same one, another one, or none. `fresh`: an event says the unit behind it
-- changed (a no-GUID key starts again).
local function see(token, fresh, now)
	local kind = KIND[token]
	if not kind or not sourceOn(kind) then return end
	local current = tokenMob[token]
	-- the cheap path of the sweep: the token still names the same mob
	if current and current.guid and not fresh then
		if Unit.Exists(token) ~= true then
			detach(current, token)
			return
		end
		local guid = Unit.GUID(token)
		if guid == current.guid then
			if Unit.IsDead(token) == true and not current.monitored then removeEntry(current, "dead") end
			return
		end
	end
	local ok, why = candidate(token)
	if not ok then
		if current then
			if why == "dead" and not current.monitored and (current.guid == nil or Unit.GUID(token) == current.guid) then
				removeEntry(current, "dead")
			else
				detach(current, token)
			end
		end
		return
	end
	local guid, reason = Unit.GUID(token)
	noteGuid(reason)
	if guid then
		local entry = byGuid[guid]
		if current and current ~= entry then detach(current, token) end
		if not entry then
			local mon = MobTracker.monitored
			if mon and mon.guid == guid then
				entry = mon
			else
				entry = newEntry("mob:" .. guid, guid, now)
			end
		end
		attach(entry, token, now)
		return
	end
	-- no readable GUID: only the stable tokens, told apart from the monitored mob and from each other (§1.3)
	if kind ~= "focus" and kind ~= "boss" then
		if current then detach(current, token) end
		return
	end
	if current and current.guid == nil and not fresh then return end
	if current then detach(current, token) end
	local same, distinct = findSame(token)
	if same then
		attach(same, token, now)
		return
	end
	if not distinct then return end
	tokSerial[token] = (tokSerial[token] or 0) + 1
	local entry = newEntry("tok:" .. token .. ":" .. tokSerial[token], nil, now)
	attach(entry, token, now)
end
MobTracker.See = see

-- The tokens of the `group` source follow the scanner's units: rebuilt when they changed (allocation only then).
local function checkRoster()
	local Scanner = RealScanner
	local units, count = Scanner and Scanner.units or {}, Scanner and Scanner.count or 0
	local n, changed = 0, false
	for i = 1, count do
		local unit = units[i]
		if unit ~= "player" then
			n = n + 1
			if groupBase[n] ~= unit then changed = true end
		end
	end
	if not changed and n == groupCount and sweepCount > 0 then return false end
	-- forget the old group tokens
	for i = 1, groupCount do
		local token = TARGET_OF[groupBase[i]]
		local entry = token and tokenMob[token]
		if entry then detach(entry, token) end
		if token then KIND[token], OWNER[token] = nil, nil end
		groupBase[i] = nil
	end
	n = 0
	for i = 1, count do
		local unit = units[i]
		if unit ~= "player" then
			n = n + 1
			groupBase[n] = unit
			local token = targetOf(unit)
			KIND[token], OWNER[token] = "group", unit
		end
	end
	groupCount = n
	-- the sweep list: focus, boss, group, plates
	local k = 0
	local function add(token) k = k + 1; sweepList[k] = token end
	add("focus")
	for i = 1, 5 do add(BOSS[i]) end
	for i = 1, groupCount do add(TARGET_OF[groupBase[i]]) end
	for i = 1, 40 do add(PLATE[i]) end
	for i = k + 1, #sweepList do sweepList[i] = nil end
	sweepCount = k
	if sweepCursor > k then sweepCursor = 0 end
	for _, slot in ipairs(slots) do slot.cursor = 0 end   -- §1.7: the roster changed, readings kept
	return true
end

local function sweep(now)
	local n = sweepCount
	if n == 0 then return end
	local todo = MobTracker.SWEEP
	if todo > n then todo = n end
	for _ = 1, todo do
		sweepCursor = sweepCursor % n + 1
		see(sweepList[sweepCursor], false, now)
	end
end

-- The monitored mob's entry follows the TargetTracker (TARGET_CHANGED and every tick).
local function syncMonitored(now)
	local Tracker = RealTracker
	local key = Tracker and Tracker.mobKey or nil
	local mon = MobTracker.monitored
	if mon and mon.key == key then return mon end
	if mon then
		Risk.Leave(mon)   -- while still monitored: its state was the monitor's, never announced
		mon.monitored = false
		mon.best = bestOf(mon)
		clearReading(mon)
		MobTracker.monitored = nil
		if mon.tokenCount == 0 and (mon.guid == nil or not Unit.TokenFromGUID(mon.guid)) then removeEntry(mon, nil) end
	end
	if not key then return nil end
	local entry = byKey[key]
	if not entry then
		local guid = Tracker.mobGUID
		entry = (guid and byGuid[guid]) or newEntry(key, guid, now)
	end
	freeSlot(entry)
	clearReading(entry)
	Risk.Leave(entry)
	entry.monitored = true
	entry.best = PRIORITY.monitored
	MobTracker.monitored = entry
	return entry
end

---------------------------------------------------------------------------------------------------------------------
-- The token that reads a mob (§1.3)
---------------------------------------------------------------------------------------------------------------------
-- The best token naming the entry now, checked against its GUID; UnitTokenFromGUID when none of its own does. Returns
-- the token and its kind ("lookup" for one UnitTokenFromGUID gave), or nil.
local function tokenFor(entry, now)
	for _ = 1, 4 do   -- a token that names another mob is dropped and the next one tried
		local best, bestRank = nil, huge
		for token in pairs(entry.tokens) do
			local rank = READ_ORDER[KIND[token]] or 9
			if rank < bestRank then best, bestRank = token, rank end
		end
		if not best then break end
		if entry.guid == nil then
			if Unit.Exists(best) == true then
				entry.lastTokenAt = now
				return best, KIND[best]
			end
			detach(entry, best)
			if not byKey[entry.key or ""] then return nil end
		elseif Unit.GUID(best) == entry.guid then
			entry.lastTokenAt = now
			return best, KIND[best]
		else
			detach(entry, best)
		end
	end
	if entry.guid == nil then return nil end
	local lookup = entry.lookup
	if lookup and Unit.GUID(lookup) == entry.guid then
		entry.lastTokenAt = now
		return lookup, "lookup"
	end
	lookup = Unit.TokenFromGUID(entry.guid)
	entry.lookup = lookup
	if lookup then
		entry.lastTokenAt = now
		return lookup, "lookup"
	end
	return nil
end

-- The token naming the mob of `key` now, for the TargetTracker's pinned mob (asked again at each Check): the token, or
-- nil and why ("dead" or "lost").
function MobTracker.TokenOf(key)
	if type(key) ~= "string" then return nil, "lost" end
	local entry = byKey[key]
	if not entry then
		if key == goneKey then return nil, goneWhy or "lost" end
		return nil, "lost"
	end
	local token = tokenFor(entry, Compat.Now())
	if token then return token end
	return nil, "lost"
end

-- The entry of a key (read only), nil when the mob is not known.
function MobTracker.Get(key) return byKey[key] end

-- The rows of a listed mob (read only) and their count: its slot's rows, or the monitor's records for the monitored mob;
-- nil for a mob without a place. A row counts only when row.mobKey is the mob's key (Data/MobRisk.lua).
function MobTracker.Rows(key)
	local entry = byKey[key]
	if not entry then return nil, 0 end
	local Scanner = RealScanner
	if entry.monitored then return Scanner.records, Scanner.count end
	local slot = entry.slot and slots[entry.slot]
	if not slot then return nil, 0 end
	return slot.rows, Scanner.count
end

---------------------------------------------------------------------------------------------------------------------
-- Reading
---------------------------------------------------------------------------------------------------------------------
local function newRow()
	local row = Threat.NewRecord()
	row.mode, row.mobKey, row.observedAt, row.scanned = "none", nil, 0, false
	return row
end

local function slotOf(s)
	local slot = slots[s]
	if not slot then
		slot = { rows = {}, entry = nil, cursor = 0 }
		slots[s] = slot
	end
	return slot
end

local function clearRows(slot)
	local rows = slot.rows
	for i = 1, #rows do
		local row = rows[i]
		row.mobKey, row.observedAt, row.mode, row.reason, row.scanned = nil, 0, "none", nil, false
	end
	slot.cursor = 0
end

local tickReads = 0

local function readRow(row, srec, token, key, interval)
	if row.unitToken ~= srec.unitToken then
		row.mobKey, row.observedAt = nil, 0
	end
	row.unitToken, row.unitKey, row.role, row.always = srec.unitToken, srec.unitKey, srec.role, srec.always
	row.mode = Threat.Read(srec.unitToken, token, row)
	row.mobKey, row.scanned, row.stale, row.interval = key, true, false, interval
	tickReads = tickReads + 1
end

-- How many reads one read of a mob costs: its units and the lead of the holder.
local function costOf(entry)
	local Scanner = RealScanner
	local count = Scanner.count
	local recs = Scanner.records
	local fixed = 0
	for i = 1, count do
		local srec = recs[i]
		if srec.always or srec.role == "TANK" or (entry.holderKey and srec.unitKey == entry.holderKey) then
			fixed = fixed + 1
		end
	end
	local n = count
	if n > MobTracker.UNITS_PER_MOB then n = MobTracker.UNITS_PER_MOB end
	if fixed > n then n = fixed end
	return n + 1
end

local function readMob(entry, now, period)
	local slot = slots[entry.slot]
	entry.readThisTick, entry.marked = true, false
	local token, kind = tokenFor(entry, now)
	if not token then
		entry.unknown = "no-token"
		return
	end
	if Unit.IsDead(token) == true then
		removeEntry(entry, "dead")   -- §1.7: a dead mob leaves at once
		return
	end
	entry.unknown = nil
	entry.readToken, entry.source = token, kind
	local Scanner = RealScanner
	local count, recs, rows = Scanner.count, Scanner.records, slot.rows
	local key = entry.key
	local interval = entry.interval or period
	-- the units read every time (§1.6), then the others in turn from the slot's cursor
	local budget = MobTracker.UNITS_PER_MOB
	local fixed = 0
	for i = 1, count do
		local row = rows[i]
		if not row then
			row = newRow()
			rows[i] = row
		end
		row.scanned = false
		local srec = recs[i]
		if srec.always or srec.role == "TANK" or (entry.holderKey and srec.unitKey == entry.holderKey) then
			fixed = fixed + 1
			readRow(row, srec, token, key, interval)
			budget = budget - 1
		end
	end
	local others = count - fixed
	local turns = 1
	if others > 0 and budget > 0 then
		turns = ceil(others / budget)
		local visited, i = 0, slot.cursor
		while budget > 0 and visited < count do
			i = i % count + 1
			visited = visited + 1
			local row = rows[i]
			if not row.scanned then
				readRow(row, recs[i], token, key, interval * turns)
				budget = budget - 1
				slot.cursor = i
			end
		end
	elseif others > 0 then
		turns = 0
	end
	for i = count + 1, #rows do
		local row = rows[i]
		if row.mobKey then row.mobKey, row.observedAt = nil, 0 end
	end
	-- the holder, its lead, the mode of the read
	local holder, best, allSecret, onList, any = nil, nil, true, false, false
	for i = 1, count do
		local row = rows[i]
		if row.scanned then
			any = true
			local mode, reason = row.mode, row.reason
			if mode ~= "none" then
				allSecret = false
				onList = true
				if mode == "values" or best == nil then best = mode end
				if not holder and (row.isTanking == true or (type(row.situation) == "number" and row.situation >= 2)) then
					holder = row
				end
			else
				if reason ~= "secret" then allSecret = false end
				if reason ~= "nil" then onList = true end
				if reason == "error" then fight.otherError = true elseif reason == "missing" then fight.otherMissing = true end
			end
		end
	end
	if holder then
		Threat.ReadLead(holder.unitToken, token, holder)
		tickReads = tickReads + 1
		entry.holderKey = holder.unitKey
	end
	entry.observedAt = now
	entry.allSecret = any and allSecret
	if onList then entry.lastOnListAt = now end
	local mode = best or "none"
	local by = stats.bySource[kind] or stats.bySource.lookup
	by[mode] = by[mode] + 1
	fight.otherRead = true
	if best then
		local found = kind == "lookup" and entry.found or kind
		if found == "plate" or found == "group" then fight.wide = true else fight.stable = true end
	elseif entry.allSecret then
		fight.otherSecret = true
	end
	stats.mobsRead = stats.mobsRead + 1
end

---------------------------------------------------------------------------------------------------------------------
-- Slots, the order of a tick, the life cycle
---------------------------------------------------------------------------------------------------------------------
local LEVEL = { DANGER = 4, WARNING = 3, SAFE = 2, UNKNOWN = 1 }

-- The order of the slots (§1.6): best source, more members targeting it, the state of the last read, readable before
-- secret, then the order of discovery.
local function slotBefore(a, b)
	if a.best ~= b.best then return a.best < b.best end
	if a.groupCount ~= b.groupCount then return a.groupCount > b.groupCount end
	local la, lb = LEVEL[a.state] or 0, LEVEL[b.state] or 0
	if la ~= lb then return la > lb end
	local sa, sb = a.unknown == "secret", b.unknown == "secret"
	if sa ~= sb then return sb end
	return a.n < b.n
end

local function assignSlots()
	local n = 0
	for i = 1, MobTracker.count do
		local entry = mobs[i]
		if not entry.monitored then
			n = n + 1
			cand[n] = entry
		end
	end
	for i = n + 1, #cand do cand[i] = nil end
	-- insertion sort: stable, allocation-free, a few dozen entries at most
	for i = 2, n do
		local item, j = cand[i], i - 1
		while j >= 1 and slotBefore(item, cand[j]) do
			cand[j + 1] = cand[j]
			j = j - 1
		end
		cand[j + 1] = item
	end
	local places = maxMobs - (MobTracker.monitored and 1 or 0)
	for s = places + 1, #slots do
		local slot = slots[s]
		if slot.entry then
			local entry = slot.entry
			slot.entry, entry.slot = nil, nil
			clearReading(entry)
			Risk.Leave(entry)
		end
	end
	-- those that lose their place hold nothing
	for i = places + 1, n do
		local entry = cand[i]
		if entry.slot then
			freeSlot(entry)
			clearReading(entry)
			Risk.Leave(entry)
		end
	end
	-- the newcomers take the free places, with clean rows
	for i = 1, (n < places and n or places) do
		local entry = cand[i]
		if not entry.slot then
			for s = 1, places do
				local slot = slotOf(s)
				if not slot.entry then
					slot.entry, entry.slot = entry, s
					clearRows(slot)
					clearReading(entry)
					break
				end
			end
		end
	end
	return n
end

local function retryWaits(entry, now)
	return entry.allSecret and entry.observedAt > 0 and now - entry.observedAt < MobTracker.RETRY - 1e-9
end

local readMobs, tickNow, tickPeriod = 0, 0, 0.5

-- Reads `entry` when it is due and its read fits in the budget: false when it does not fit (the tick stops there, but
-- at least one mob is read per tick).
local function try(entry)
	if not entry or entry.readThisTick or not entry.slot or retryWaits(entry, tickNow) then return true end
	if readMobs > 0 and tickReads + costOf(entry) > MobTracker.READ_BUDGET then return false end
	readMob(entry, tickNow, tickPeriod)
	readMobs = readMobs + 1
	return true
end

-- The reads of one tick (§1.6): 1. the mobs an event marked, 2. DANGER, 3. in turn after the last one read. Returns
-- how many mobs were read.
local function readTick(now, period)
	readMobs, tickNow, tickPeriod = 0, now, period
	local places = maxMobs - (MobTracker.monitored and 1 or 0)
	for s = 1, places do
		local slot = slots[s]
		if slot and slot.entry then slot.entry.readThisTick = false end
	end
	for pass = 1, 2 do
		for s = 1, places do
			local slot = slots[s]
			local entry = slot and slot.entry
			if entry and ((pass == 1 and entry.marked) or (pass == 2 and entry.state == "DANGER")) then
				if not try(entry) then return readMobs end
			end
		end
	end
	for _ = 1, places do
		rrSlot = rrSlot % places + 1
		local slot = slots[rrSlot]
		if not try(slot and slot.entry) then
			rrSlot = rrSlot - 1   -- the one that did not fit comes first next time
			return readMobs
		end
	end
	return readMobs
end

local function designatedTanks()
	local Scanner = RealScanner
	local n = 0
	for i = 1, Scanner.count do
		if Scanner.records[i].role == "TANK" then n = n + 1 end
	end
	return n
end

-- Why a listed mob cannot be read now (§1.5), nil when its rows decide.
local function unknownOf(entry, now)
	if entry.unknown == "no-token" then return "no-token" end
	if entry.observedAt <= 0 then return "pending" end
	if entry.allSecret then return "secret" end
	local limit = 1
	local interval = entry.interval
	if type(interval) == "number" and 2 * interval > limit then limit = 2 * interval end
	if now - entry.observedAt > limit + 1e-9 then return "stale" end
	return nil
end

local function lifecycle(now, designated)
	local forget = MobTracker.FORGET
	local i = 1
	while i <= MobTracker.count do
		local entry = mobs[i]
		local gone = false
		if not entry.monitored then
			if entry.tokenCount == 0 and now - entry.lastTokenAt > forget then
				removeEntry(entry, "lost")
				gone = true
			elseif entry.observedAt > 0 and now - entry.lastOnListAt > forget then
				removeEntry(entry, "lost")   -- no watched unit on its list: not the group's fight
				gone = true
			end
		end
		if not gone then
			if entry.slot then
				local slot = slots[entry.slot]
				local unknown = unknownOf(entry, now)
				entry.unknown = unknown
				Risk.Evaluate(entry, slot.rows, RealScanner.count, now, unknown, designated, 1)
			end
			i = i + 1
		end
	end
end

local function buildList()
	local n = 0
	local mon = MobTracker.monitored
	if mon then
		n = 1
		list[1] = mon
	end
	local places = maxMobs - (mon and 1 or 0)
	for s = 1, places do
		local slot = slots[s]
		if slot and slot.entry then
			n = n + 1
			list[n] = slot.entry
		end
	end
	for i = n + 1, #list do list[i] = nil end
	MobTracker.listCount = n
end

-- The listed mobs (read only): the array and its count; the monitored mob first, then the slots. Data/MobRisk.lua's
-- Order sorts a copy in the order of the Dungeon Focus.
function MobTracker.List() return list, MobTracker.listCount end

---------------------------------------------------------------------------------------------------------------------
-- The reach (§1.4)
---------------------------------------------------------------------------------------------------------------------
local function updateReach()
	local r = "unknown"
	if fight.wide then r = "all"
	elseif fight.stable then r = "focus-boss"
	elseif fight.monitorRead then r = "target"
	elseif fight.monitorNone then r = "none" end
	local level = identity()
	MobTracker.identity = level
	if level == "compare" and REACH_RANK[r] > REACH_RANK["focus-boss"] then r = "focus-boss" end
	if level == "target" and REACH_RANK[r] > REACH_RANK.target then r = "target" end
	if REACH_RANK[r] > REACH_RANK[MobTracker.reach] then MobTracker.reach = r end
	r = MobTracker.reach
	local reason = nil
	if r ~= "all" and r ~= "unknown" then
		if level == "target" then reason = "no-compare"
		elseif level == "compare" then reason = "no-guid"
		elseif fight.otherSecret then reason = "secret"
		elseif not plates or not fight.plateSeen then reason = "nameplates-off"
		elseif fight.otherRead then reason = "no-answer" end
	end
	MobTracker.reachReason = reason
	if r == "all" or r == "focus-boss" then
		Compat:SetCapability("otherMobs", Compat.AVAILABLE, r)
	elseif fight.otherSecret then
		Compat:SetCapability("otherMobs", Compat.RESTRICTED, "secret")
	elseif fight.otherMissing then
		Compat:SetCapability("otherMobs", Compat.MISSING, nil)
	end
end

function MobTracker.Reach() return MobTracker.reach, MobTracker.reachReason end

---------------------------------------------------------------------------------------------------------------------
-- The tick
---------------------------------------------------------------------------------------------------------------------
local function demoOn() return ns.Demo ~= nil and ns.Demo.IsActive ~= nil and ns.Demo.IsActive() end

local function hasConsumer()
	for _ in pairs(MobTracker.consumers) do return true end
	return false
end

-- The discovery events may be registered: the switch, the setting, the client, the monitor, and combat.
local function mayDiscover()
	if not MobTracker.enabled or not switchOn() or not settingOn then return false end
	if ns.addon and ns.addon.isForever == false then return false end
	if not (RealTracker and RealTracker.enabled and RealScanner and RealScanner.enabled) then return false end
	return MobTracker.inCombat and not demoOn()
end

local function hasOther()
	for i = 1, MobTracker.count do
		if not mobs[i].monitored then return true end
	end
	return false
end

local events = {}

local function setThreatEvents(on)
	if on == threatOn then return end
	threatOn = on
	MobTracker.reading = on
	if on then
		MobTracker:RegisterEvent("UNIT_THREAT_LIST_UPDATE", events.onEvent)
	else
		MobTracker:UnregisterEvent("UNIT_THREAT_LIST_UPDATE")
	end
end

local DISCOVERY = { "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED", "PLAYER_FOCUS_CHANGED",
	"INSTANCE_ENCOUNTER_ENGAGE_UNIT", "UNIT_TARGET" }

local function setDiscovery(on)
	if on == discoveryOn then return end
	discoveryOn = on
	for _, event in ipairs(DISCOVERY) do
		if on then MobTracker:RegisterEvent(event, events.onEvent) else MobTracker:UnregisterEvent(event) end
	end
end

local tick

local function tickBody()
	local now = Compat.Now()
	local period = 1 / MobTracker.RATE
	checkRoster()
	syncMonitored(now)
	sweep(now)
	local other = hasOther()
	setThreatEvents(other)
	tickReads = 0
	local designated = designatedTanks()
	local read = 0
	if other then
		local n = assignSlots()
		read = readTick(now, period)
		-- the expected time between two reads of a mob: the turns of the rotation (§1.5)
		local places = maxMobs - (MobTracker.monitored and 1 or 0)
		local slotted = n < places and n or places
		local turns = 1
		if read > 0 and slotted > read then turns = ceil(slotted / read) end
		stats.turns = turns
		for s = 1, places do
			local slot = slots[s]
			local entry = slot and slot.entry
			if entry and entry.readThisTick and entry.observedAt == now then entry.interval = period * turns end
		end
	end
	lifecycle(now, designated)
	local mon = MobTracker.monitored
	if mon then Risk.Evaluate(mon, RealScanner.records, RealScanner.count, now, nil, designated, 0.5) end
	buildList()
	updateReach()
	stats.ticks = stats.ticks + 1
	stats.lastReads = tickReads
	stats.reads = stats.reads + tickReads
	MobTracker.lastTickAt = now
	emit("MOBS_UPDATED")
end

local busy = false

-- One tick now (the Scheduler, a test). Returns false when the tracker does not run.
function MobTracker.Tick()
	if busy or not MobTracker.ticking then return false end
	busy = true
	local ok, err = pcall(tickBody)
	busy = false
	if not ok then error(err, 0) end
	return true
end
tick = MobTracker.Tick

local function startTick()
	MobTracker.ticking = true
	ns.Scheduler.Start(MobTracker.TICK, MobTracker.RATE, tick, { combat = true })
end

local function stopTick()
	MobTracker.ticking = false
	ns.Scheduler.Stop(MobTracker.TICK)
	setThreatEvents(false)
end

-- Starts or stops the tick and the events to match their conditions (§1.6). Returns whether the tick runs.
function MobTracker.Refresh()
	local discover = mayDiscover()
	if not MobTracker.enabled then return false end
	setDiscovery(discover)
	local want = discover and hasConsumer()
	if want and not MobTracker.ticking then
		startTick()
		tick()
	elseif not want and MobTracker.ticking then
		stopTick()
	end
	return MobTracker.ticking
end

-- A consumer wants the other mobs (on) or no longer (off): the pull bar and the list (M7.3), the `mob` alerts (M7.4).
function MobTracker.Want(name, on)
	if type(name) ~= "string" then return false end
	MobTracker.consumers[name] = on and true or nil
	return MobTracker.Refresh()
end

local function windowWants()
	local tab = window.tab
	if tab == nil then tab = ns.Config and ns.Config.Get and ns.Config:Get("char.ui.lastTab") or "monitor" end
	return window.shown and tab == "monitor"
end

local function resetFight()
	clearAll()
	for k in pairs(fight) do fight[k] = false end
	MobTracker.reach, MobTracker.reachReason = "unknown", nil
	MobTracker.identity = "unknown"
end

-- Everything off (the setting or the switch): nothing read, nothing registered, the pin released.
local function shutDown()
	if MobTracker.ticking then stopTick() end
	setDiscovery(false)
	setThreatEvents(false)
	clearAll()
	if RealTracker and RealTracker.Pinned and RealTracker.Pinned() then RealTracker.Pin(nil) end
end

---------------------------------------------------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------------------------------------------------
function events.onEvent(event, unit)
	if not MobTracker.enabled then return end
	local now = Compat.Now()
	if event == "PLAYER_FOCUS_CHANGED" then
		stats.events.focus = stats.events.focus + 1
		see("focus", true, now)
		return
	end
	if event == "INSTANCE_ENCOUNTER_ENGAGE_UNIT" then
		stats.events.boss = stats.events.boss + 1
		for i = 1, 5 do see(BOSS[i], true, now) end
		return
	end
	if type(unit) ~= "string" or Compat.IsSecret(unit) then return end
	if event == "UNIT_THREAT_LIST_UPDATE" then
		local entry = tokenMob[unit]
		if entry and entry.slot then
			stats.events.threat = stats.events.threat + 1
			entry.marked = true   -- read first at the next tick, never now (§1.6)
		end
	elseif event == "NAME_PLATE_UNIT_ADDED" then
		stats.events.plate = stats.events.plate + 1
		see(unit, false, now)
	elseif event == "NAME_PLATE_UNIT_REMOVED" then
		stats.events.plate = stats.events.plate + 1
		local entry = tokenMob[unit]
		if entry then detach(entry, unit) end
	elseif event == "UNIT_TARGET" then
		local token = TARGET_OF[unit]
		if token and OWNER[token] == unit then
			stats.events.group = stats.events.group + 1
			see(token, false, now)
		end
	end
end

function MobTracker.Enable()
	if MobTracker.enabled or not switchOn() then return false end
	local AceEvent = LibStub and LibStub("AceEvent-3.0", true)
	if not AceEvent then return false end
	AceEvent:Embed(MobTracker)
	MobTracker.enabled = true
	readSettings()
	MobTracker.inCombat = ns.addon and ns.addon.inCombat == true or false
	if ns.addon and ns.addon.AddDebugSection then ns.addon:AddDebugSection("Mobs", MobTracker.DebugLines) end
	MobTracker.Refresh()
	return true
end

if ns.Bus then
	local Bus = ns.Bus
	Bus.On("COMBAT_STARTED", function()
		MobTracker.inCombat = true
		if not MobTracker.enabled then return end
		resetFight()
		MobTracker.Refresh()
	end)
	Bus.On("COMBAT_ENDED", function()
		MobTracker.inCombat = false
		if not MobTracker.enabled then return end
		MobTracker.lastReach, MobTracker.lastReasonReach = MobTracker.reach, MobTracker.reachReason
		if MobTracker.ticking then stopTick() end
		setDiscovery(false)
		clearAll()
		emit("MOBS_UPDATED")
	end)
	Bus.On("TARGET_CHANGED", function()
		if not MobTracker.ticking then return end
		syncMonitored(Compat.Now())
	end)
	Bus.On("THREAT_UPDATED", function()
		if not MobTracker.ticking or demoOn() then return end
		local Scanner = RealScanner
		local mode, reason = Scanner.mode, Scanner.modeReason
		if mode == "values" or mode == "state" then fight.monitorRead = true
		elseif Scanner.scans > 0 and reason ~= nil and reason ~= "nil" then fight.monitorNone = true end
		local mon = MobTracker.monitored
		if mon and RealTracker and mon.key == RealTracker.mobKey then
			Risk.Evaluate(mon, Scanner.records, Scanner.count, Compat.Now(), nil, designatedTanks(), 0.5)
		end
	end)
	Bus.On("WINDOW_SHOWN", function(shown)
		window.shown = shown == true
		if MobTracker.enabled then MobTracker.Want("window", windowWants()) end
	end)
	Bus.On("TAB_CHANGED", function(tabId)
		window.tab = tabId
		if MobTracker.enabled then MobTracker.Want("window", windowWants()) end
	end)
	Bus.On("CONFIG_LOADED", readSettings)
	Bus.On("CONFIG_CHANGED", function(path)
		if path ~= ENABLED_PATH and path ~= MAX_PATH and path ~= PLATES_PATH then return end
		readSettings()
		if not MobTracker.enabled then return end
		if not settingOn then
			shutDown()
			return
		end
		if path == PLATES_PATH and not plates then
			for i = 1, 40 do
				local entry = tokenMob[PLATE[i]]
				if entry then detach(entry, PLATE[i]) end
			end
		end
		MobTracker.Refresh()
	end)
	Bus.On("DEMO_CHANGED", function()
		if not MobTracker.enabled then return end
		if demoOn() then shutDown() else MobTracker.Refresh() end
	end)
end
if ns.OnEnable then ns.OnEnable(MobTracker.Enable) end

---------------------------------------------------------------------------------------------------------------------
-- /atw debug (SPEC-07 §2.6): counts, keys' kinds and words only, never a name or a GUID
---------------------------------------------------------------------------------------------------------------------
function MobTracker.DebugLines()
	local secret, noToken, pending = 0, 0, 0
	for i = 1, MobTracker.listCount do
		local u = list[i].state == "UNKNOWN" and list[i].reason
		if u == "secret" then secret = secret + 1 elseif u == "no-token" then noToken = noToken + 1
		elseif u == "pending" then pending = pending + 1 end
	end
	local avg = stats.ticks > 0 and stats.reads / stats.ticks or 0
	local e, b = stats.events, stats.bySource
	local function modes(t) return ("%d/%d/%d"):format(t.values, t.state, t.none) end
	local Tracker = RealTracker
	return {
		("switch %s, setting %s, %s, nameplates %s, max %d"):format(switchOn() and "on" or "off",
			settingOn and "on" or "off", MobTracker.ticking and (MobTracker.reading and "reading" or "sweeping") or "idle",
			plates and "on" or "off", maxMobs),
		("reach %s%s, identity %s, last reach %s"):format(MobTracker.reach,
			MobTracker.reachReason and (" (" .. MobTracker.reachReason .. ")") or "", MobTracker.identity,
			MobTracker.lastReach or "none"),
		("%d of %d listed, %d known; %d read(s) last tick, %.1f per tick, %d turn(s), %d tick(s)"):format(
			MobTracker.listCount, maxMobs, MobTracker.count, stats.lastReads, avg, stats.turns, stats.ticks),
		("unknown: %d secret, %d no-token, %d pending; pinned %s"):format(secret, noToken, pending,
			Tracker and Tracker.Pinned and Tracker.Pinned() and "yes" or "no"),
		("events: %d plate, %d focus, %d boss, %d group, %d threat"):format(e.plate, e.focus, e.boss, e.group, e.threat),
		("reads by source (values/state/none): focus %s, boss %s, group %s, plate %s, lookup %s"):format(
			modes(b.focus), modes(b.boss), modes(b.group), modes(b.plate), modes(b.lookup)),
	}
end

if ns.addon then ns.addon.MobTracker = MobTracker end
