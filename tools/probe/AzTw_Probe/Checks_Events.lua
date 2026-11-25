-- AzTw Probe, checks P7 and P8 (step M0.5): combat events and C_DamageMeter. Development only, never distributed.
-- Spec: docs/specs/SPEC-08-quality-probe-release.md, section 1 (rules PRB-01 to PRB-06, P7, P8) and
-- docs/specs/SPEC-05-recording-report-replay.md, section 1 (the recorder events these checks decide).
-- Every API and event used here was checked against the Forever dump (build 70170) on 2026-11-25:
--   events COMBAT_LOG_EVENT_UNFILTERED and COMBAT_LOG_EVENT (C_CombatLog, no payload documented),
--   COMBAT_LOG_EVENT_INTERNAL_UNFILTERED (C_CombatLogInternal), PLAYER_REGEN_DISABLED/ENABLED, UNIT_TARGET,
--   UNIT_HEALTH and UNIT_FLAGS (payload unitTarget), PLAYER_TARGET_CHANGED, ENCOUNTER_START (encounterID,
--   encounterName, difficultyID, groupSize), ENCOUNTER_END (the same plus success and encounterUnitStatus),
--   UNIT_SPELLCAST_SUCCEEDED (unitTarget, castGUID, spellID, castBarID), UNIT_DIED (unitGUID), PARTY_KILL
--   (attackerGUID, targetGUID), PLAYER_DEAD, ADDON_ACTION_BLOCKED/FORBIDDEN (isTainted, function),
--   DAMAGE_METER_COMBAT_SESSION_UPDATED (type, sessionID), DAMAGE_METER_CURRENT_SESSION_UPDATED, DAMAGE_METER_RESET;
--   functions C_CombatLog.IsCombatLogRestricted, C_CombatLogInternal.GetCurrentEventInfo and
--   C_CombatLogSecure.GetCurrentEventInfo (both namespaces are absent from the dump's list of globals),
--   UnitAffectingCombat, C_RestrictedActions.InCombatLockdown, UnitIsDead, UnitIsDeadOrGhost, UnitHealth (unit,
--   usePredicted), UnitHealthMax, C_Secrets.ShouldUnitHealthMaxBeSecret, C_InstanceEncounter.IsEncounterInProgress,
--   C_DamageMeter.IsDamageMeterAvailable (isAvailable, failureReason), GetAvailableCombatSessions,
--   GetSessionDurationSeconds (sessionType), GetCombatSessionFromType (sessionType, type), issecrettable;
--   frame methods RegisterEvent (returns registered) and IsEventRegistered.
--   Not in the dump, looked up at run time (PRB-05): CombatLogGetCurrentEventInfo, Enum.DamageMeterType,
--   Enum.DamageMeterSessionType.
--
--   P7  At login the probe tries to register the three combat log events on a frame of its own (inside pcall) and
--       records whether the client accepted them and any ADDON_ACTION_BLOCKED/FORBIDDEN that followed. Every delivery
--       is counted with the number and the kind of its arguments, never their content; on the first deliveries (and
--       on the first of each fight) it calls each combat log reader it finds and records only what kind of values
--       came back. While /atwp watch is on it also counts PLAYER_REGEN_* against UnitAffectingCombat, UNIT_TARGET,
--       PLAYER_TARGET_CHANGED, encounters (ids and numbers, never the name), deaths per source (UNIT_HEALTH,
--       UNIT_FLAGS, UNIT_DIED, PARTY_KILL, PLAYER_DEAD, a poll every second) and the spells cast by the group
--       (UNIT_SPELLCAST_SUCCEEDED), with whether the mob the caster targets turned to the caster within 0.5 s.
--   P8  After every fight (with or without the watch) and at /atwp run P8 it reads C_DamageMeter: availability,
--       the enum values, the sessions and their durations against the measured length of the fight, and of every
--       source only the kind of each field, the deaths and the local player flag; never name or sourceGUID.
--
-- Secret values (PRB-02): every value goes through Probe.IsSecret / Probe.Describe first; a secret is only counted as
-- "secret". GUIDs are compared in memory only and never saved; spell ids, encounter ids and creature ids are saved
-- (not personal data); no name is ever read into a saved or printed text (PRB-03). Saved counters are bounded.

local ADDON_NAME, Probe = ...

local IsSecret, Describe, Call, API = Probe.IsSecret, Probe.Describe, Probe.Call, Probe.API
local out = Probe.Print
local H = Probe.helpers
local now, flag, boolText, store, elapsed = H.now, H.flag, H.boolText, H.store, H.elapsed
local contextKey, exists, hostile, groupUnits = H.contextKey, H.exists, H.hostile, H.groupUnits
local median, errText = H.median, H.errText
local tokenKind, guidOf, bump, statsFor = H.tokenKind, H.guidOf, H.bump, H.statsFor
local sortedKeys, countsText, currentContext, invalidateContext = H.sortedKeys, H.countsText, H.currentContext,
    H.invalidateContext

local GROUP_CODES = { party = true, dungeon = true, raid = true }
local INSTANCE_CODES = { dungeon = true, raid = true }
local GROUP_KINDS = { player = true, pet = true, party = true, raid = true, partypet = true, raidpet = true }

----------------------------------------------------------------------------------------------------------------------
-- Small helpers
----------------------------------------------------------------------------------------------------------------------

local function watching()
    return Probe.DB().watch == true
end

--- Kind of what one call returned: "missing", "error", or the kind of its first value (Probe.Describe).
local function callKind(ok, v)
    if not ok then
        return v == "API missing" and "missing" or "error"
    end
    return (Describe(v))
end

local function ms(seconds)
    return math.floor(seconds * 1000 + 0.5)
end

local function keep(list, v, max)
    list[#list + 1] = v
    while #list > max do
        table.remove(list, 1)
    end
end

--- bump() on a table that holds at most `max` keys: further keys are counted under "other".
local function bumpCapped(t, key, max, n)
    if t[key] == nil then
        local count = 0
        for _ in pairs(t) do
            count = count + 1
        end
        if count >= max then
            key = "other"
        end
    end
    bump(t, key, n)
end

--- t[name] as a table, created when missing.
local function sub(t, name)
    local v = t[name]
    if type(v) ~= "table" then
        v = {}
        t[name] = v
    end
    return v
end

--- A plain number (readable, not secret) or nil.
local function number(v)
    if not IsSecret(v) and type(v) == "number" then
        return v
    end
end

--- The value of a number for the logs: rounded to 0.1, "secret", "nil" or the kind.
local function shownNumber(v)
    local kind, value = Describe(v)
    if value ~= nil and kind == "number" then
        return tostring(value)
    end
    return kind
end

--- Kind of a table returned by the game: "table", "secret", "secret table" (issecrettable), "nil" or another type.
local function tableKind(t)
    if IsSecret(t) then
        return "secret"
    end
    if type(t) ~= "table" then
        return t == nil and "nil" or type(t)
    end
    local test = rawget(_G, "issecrettable")
    if type(test) == "function" then
        local ok, secret = pcall(test, t)
        if not ok or IsSecret(secret) or secret == true then
            return "secret table"
        end
    end
    return "table"
end

local function index(t, k)
    return t[k]
end

--- t[k] read inside pcall: ok, value.
local function getField(t, k)
    return pcall(index, t, k)
end

--- Calls fn(entry) for the first `max` array entries of t; returns how many entries there are, nil if not iterable.
local function eachEntry(t, max, fn)
    local n = 0
    local ok = pcall(function()
        for _, entry in ipairs(t) do
            n = n + 1
            if n <= max then
                fn(entry)
            end
        end
    end)
    return ok and n or nil
end

--- "group" (the player, the pets, party or raid members), "players" (other players), "mobs" or "unknown".
local function whoOf(unit, kind)
    if GROUP_KINDS[kind] then
        return "group"
    end
    local isPlayer = flag(Call(UnitIsPlayer, unit))
    if isPlayer == true then
        return "players"
    elseif isPlayer == false then
        return "mobs"
    end
    return "unknown"
end

local function statsNow(name, force)
    local key, code, combat = currentContext(force)
    return statsFor(name, key, code, combat), key, code
end

----------------------------------------------------------------------------------------------------------------------
-- P7: the combat log
----------------------------------------------------------------------------------------------------------------------

local CL_EVENTS = { "COMBAT_LOG_EVENT_UNFILTERED", "COMBAT_LOG_EVENT", "COMBAT_LOG_EVENT_INTERNAL_UNFILTERED" }
local READERS = {
    { key = "CombatLogGetCurrentEventInfo", get = function()
        return rawget(_G, "CombatLogGetCurrentEventInfo")
    end },
    { key = "C_CombatLogInternal.GetCurrentEventInfo", get = function()
        return API("C_CombatLogInternal", "GetCurrentEventInfo")
    end },
    { key = "C_CombatLogSecure.GetCurrentEventInfo", get = function()
        return API("C_CombatLogSecure", "GetCurrentEventInfo")
    end },
}
local READS_FIRST = 5          -- reader calls on the first deliveries of a session (then one per fight)
local DESCRIBE_FIRST = 500     -- deliveries whose argument kinds are all counted (then one in 100)
local MAX_ARGS = 32            -- argument positions counted
local MAX_ATTEMPTS = 3         -- registration attempts per session (at login and at /atwp run P7)

-- Memory only: what this session did.
local cl = { frame = nil, registered = {}, attempts = 0, attemptAt = nil, reads = {}, fightReads = {}, described = 0 }

local function clStore()
    local c = sub(store("p7"), "combatLog")
    sub(c, "registration")
    sub(c, "deliveries")
    sub(c, "arity")
    sub(c, "argKinds")
    sub(c, "readers")
    sub(c, "restricted")
    return c
end

local function describeReturns(rs, ok, ...)
    if not ok then
        bump(rs, "error")
        rs.lastError = tostring((...)):sub(1, 120)
        return false
    end
    local n = select("#", ...)
    bumpCapped(sub(rs, "returns"), n, 16)
    local kinds, readable = sub(rs, "kinds"), false
    for i = 1, math.min(n, MAX_ARGS) do
        local kind = (Describe((select(i, ...))))
        bump(kinds, kind)
        if kind ~= "secret" and kind ~= "nil" then
            readable = true
        end
    end
    bump(rs, readable and "readable" or "unreadable")
    return readable
end

--- Calls one combat log reader and records only the kinds of what it returned. `where` is "event" or "outside".
local function readCombatLog(reader, where)
    local c = clStore()
    local rs = sub(c.readers, reader.key .. " (" .. where .. ")")
    bump(rs, "calls")
    local fn = reader.get()
    if type(fn) ~= "function" then
        bump(rs, "missing")
        return
    end
    local readable = describeReturns(rs, Call(fn))
    if readable and (rs.readable or 0) == 1 then
        Probe:Log("P7", "combat log: " .. reader.key .. " returned readable values (" .. where .. ")")
    end
end

local function onCombatLog(event, ...)
    local c = clStore()
    bump(c.deliveries, event)
    local st = statsNow("p7")
    bump(sub(st, "clDeliveries"), event)
    cl.described = cl.described + 1
    if cl.described <= DESCRIBE_FIRST or cl.described % 100 == 0 then
        local n = select("#", ...)
        bumpCapped(c.arity, n, 16)
        for i = 1, math.min(n, MAX_ARGS) do
            bump(sub(c.argKinds, i), (Describe((select(i, ...)))))
        end
    end
    for _, reader in ipairs(READERS) do
        local done = cl.reads[reader.key] or 0
        if done < READS_FIRST or (cl.fightReads and not cl.fightReads[reader.key]) then
            cl.reads[reader.key] = done + 1
            if cl.fightReads then
                cl.fightReads[reader.key] = true
            end
            readCombatLog(reader, "event")
        end
    end
    if (c.deliveries[event] or 0) == 1 then
        Probe:Log("P7", string.format("combat log: first %s delivered, %d arguments", event, select("#", ...)))
    end
end

--- Tries to register the combat log events not registered yet, on a frame of the probe's own.
local function registerCombatLog(trigger)
    if cl.attempts >= MAX_ATTEMPTS then
        return
    end
    local c = clStore()
    if not cl.frame then
        local ok, f = Call(CreateFrame, "Frame")
        if not ok or IsSecret(f) or type(f) ~= "table" then
            c.frame = "error"
            return
        end
        local fine = pcall(f.SetScript, f, "OnEvent", function(_, event, ...)
            local done, err = pcall(onCombatLog, event, ...)
            if not done then
                Probe:Log("errors", tostring(event) .. ": " .. errText(err))
            end
        end)
        if not fine then
            c.frame = "SetScript error"
            return
        end
        cl.frame = f
        c.frame = "ok"
    end
    cl.attempts = cl.attempts + 1
    cl.attemptAt = now()
    local f = cl.frame
    for _, event in ipairs(CL_EVENTS) do
        if not cl.registered[event] then
            local r = sub(c.registration, event)
            bump(r, "attempts")
            local ok, registered = Call(f.RegisterEvent, f, event)
            if ok then
                r.call = "ok"
                r.returned = boolText(true, registered)
                r.error = nil
            else
                r.call = "error"
                r.error = tostring(registered):sub(1, 120)
            end
            r.isRegistered = boolText(Call(f.IsEventRegistered, f, event))
            if r.isRegistered == "yes" then
                cl.registered[event] = true
            end
            Probe:Log("P7", string.format("%s: RegisterEvent %s %s (returned %s, IsEventRegistered %s)%s", trigger,
                event, r.call, tostring(r.returned or "-"), r.isRegistered, r.error and (": " .. r.error) or ""))
        end
    end
end

local function readRestricted(st)
    local kind = boolText(Call(API("C_CombatLog", "IsCombatLogRestricted")))
    bump(clStore().restricted, kind)
    if st then
        bump(sub(st, "restricted"), kind)
    end
    return kind
end

-- ADDON_ACTION_BLOCKED / ADDON_ACTION_FORBIDDEN: the function and whether the probe was blamed; never another name.
local function onAction(event, isTainted, fnName)
    local s = store("p7")
    local actions = sub(s, "actions")
    local who
    if IsSecret(isTainted) then
        who = "secret"
    elseif isTainted == ADDON_NAME then
        who = "probe"
    elseif type(isTainted) == "string" and isTainted ~= "" then
        who = "other addon"
    else
        who = "none"
    end
    local name = "secret"
    if not IsSecret(fnName) then
        name = (type(fnName) == "string" and fnName:match("^[%w_%.:]+$")) and fnName:sub(1, 64) or "other"
    end
    local short = event == "ADDON_ACTION_BLOCKED" and "blocked" or "forbidden"
    bumpCapped(sub(actions, short), who .. " " .. name, 20)
    local t = now()
    if cl.attemptAt and t and t - cl.attemptAt <= 2 then
        bump(actions, "afterRegistration")
    end
    Probe:Log("P7", string.format("%s by %s: %s [%s]", event, who, name, (currentContext())))
end

Probe:On("ADDON_ACTION_BLOCKED", function(isTainted, fnName)
    onAction("ADDON_ACTION_BLOCKED", isTainted, fnName)
end)
Probe:On("ADDON_ACTION_FORBIDDEN", function(isTainted, fnName)
    onAction("ADDON_ACTION_FORBIDDEN", isTainted, fnName)
end)
-- At login the saved variables are loaded: the attempt is recorded in them.
Probe:On("PLAYER_LOGIN", function()
    registerCombatLog("login")
end)

----------------------------------------------------------------------------------------------------------------------
-- P7: combat start and end
----------------------------------------------------------------------------------------------------------------------

local fight7          -- the fight in progress while watching: { key, code, started, casts, changed, deaths... }
local p8Fight         -- the last fight for P8 (watch or not): { key, code, started, duration, groupDeaths }
local regenPending    -- { expect, at, st }: waiting for UnitAffectingCombat to agree with PLAYER_REGEN_*
local REGEN_WAIT = 3
local DELAYS_KEEP = 100

local function regenStats(st)
    local r = sub(st, "regen")
    for _, k in ipairs({ "disabled", "enabled", "same", "later", "never", "secret" }) do
        r[k] = r[k] or 0
    end
    sub(r, "delays")
    sub(r, "lockdown")
    return r
end

local function regenPoll()
    local p = regenPending
    local t = now()
    if not p or not t then
        Probe.Cancel("P7-regen")
        return
    end
    local cur = flag(Call(UnitAffectingCombat, "player"))
    if cur == p.expect then
        p.r.later = p.r.later + 1
        keep(p.r.delays, ms(t - p.at), DELAYS_KEEP)
        regenPending = nil
        Probe.Cancel("P7-regen")
    elseif t - p.at > REGEN_WAIT then
        p.r.never = p.r.never + 1
        Probe:Log("P7", string.format("UnitAffectingCombat did not follow %s within %d s",
            p.expect and "PLAYER_REGEN_DISABLED" or "PLAYER_REGEN_ENABLED", REGEN_WAIT))
        regenPending = nil
        Probe.Cancel("P7-regen")
    end
end

local function onRegen(expect)
    if not watching() then
        return
    end
    invalidateContext()
    local st = statsNow("p7", true)
    local r = regenStats(st)
    r[expect and "disabled" or "enabled"] = r[expect and "disabled" or "enabled"] + 1
    bump(r.lockdown, (expect and "start " or "end ") .. boolText(Call(API("C_RestrictedActions", "InCombatLockdown"))))
    local okC, cur = Call(UnitAffectingCombat, "player")
    if not okC or IsSecret(cur) then
        r.secret = r.secret + 1
        return
    end
    if (cur and true or false) == expect then
        r.same = r.same + 1
        return
    end
    regenPending = { expect = expect, at = now() or 0, r = r }
    Probe.Every("P7-regen", 0.05, regenPoll, 0.05)
end

Probe:On("PLAYER_REGEN_DISABLED", function()
    onRegen(true)
end)
Probe:On("PLAYER_REGEN_ENABLED", function()
    onRegen(false)
end)

Probe:On("PLAYER_TARGET_CHANGED", function()
    if not watching() then
        return
    end
    local st = statsNow("p7")
    local kind
    if not exists("target") then
        kind = "none"
    elseif hostile("target") then
        kind = "hostile"
    else
        kind = "other"
    end
    bump(sub(st, "targetChanged"), kind)
end)

----------------------------------------------------------------------------------------------------------------------
-- P7: UNIT_TARGET and taunts (UNIT_SPELLCAST_SUCCEEDED)
----------------------------------------------------------------------------------------------------------------------

local CASTER_KINDS = { player = true, pet = true, party = true, raid = true, partypet = true, raidpet = true }
local MAX_SPELLS = 64          -- spell ids counted per context
local MAX_PENDING = 10         -- casts followed at once
local FOLLOW = 0.5             -- seconds to wait for the mob's target to change
local RECENT_KEEP = 30         -- casts kept in memory for the taunt note
local LOG_CHANGES_PER_FIGHT = 20

local pending = {}             -- slot -> cast followed (memory only: GUIDs are compared here and dropped)
local recent = {}              -- the last casts of the group: { t, spell, kind, outcome }

--- What the mob behind `unit` targets now: "player", "group", "other player", "npc", "nothing" or "secret".
local function mobTargetKind(unit)
    local tt = unit .. "target"
    local okE, there = Call(UnitExists, tt)
    if not okE or IsSecret(there) then
        return "secret"
    end
    if not there then
        return "nothing"
    end
    local okM, me = Call(UnitIsUnit, tt, "player")
    if not okM or IsSecret(me) then
        return "secret"
    end
    if me then
        return "player"
    end
    for _, g in ipairs(groupUnits()) do
        if flag(Call(UnitIsUnit, tt, g)) == true then
            return "group"
        end
    end
    local isPlayer = flag(Call(UnitIsPlayer, tt))
    if isPlayer == nil then
        return "secret"
    end
    return isPlayer and "other player" or "npc"
end

local function onUnitTarget(unit)
    if not watching() then
        return
    end
    local st = statsNow("p7")
    local ut = sub(st, "unitTarget")
    local kind = tokenKind(unit)
    bump(sub(ut, "kinds"), kind)
    if kind == "secret" or type(unit) ~= "string" or GROUP_KINDS[kind] or not hostile(unit) then
        return
    end
    bump(sub(ut, "mobTargets"), mobTargetKind(unit))
    if fight7 then
        fight7.unitTarget = fight7.unitTarget + 1
    end
    if next(pending) == nil then
        return
    end
    -- A followed cast: did this mob turn to its caster?
    local g = guidOf(unit)
    if g.kind ~= "readable" then
        return
    end
    for _, p in pairs(pending) do
        if p.mobGuid == g.guid and not p.eventAt and flag(Call(UnitIsUnit, unit .. "target", p.caster)) == true then
            p.eventAt = now()
        end
    end
end

Probe:On("UNIT_TARGET", onUnitTarget)

local function spellCell(st, spell)
    local spells = sub(sub(st, "casts"), "spells")
    local key = spell
    if not spells[key] then
        local count = 0
        for _ in pairs(spells) do
            count = count + 1
        end
        if count >= MAX_SPELLS then
            key = "other"
        end
    end
    local cell = spells[key]
    if not cell then
        cell = { casts = 0, onMob = 0, changed = 0, already = 0, unchanged = 0, unknown = 0, byEvent = 0 }
        spells[key] = cell
    end
    return cell
end

local function finishCast(slot)
    local p = pending[slot]
    pending[slot] = nil
    if not p then
        return
    end
    local outcome
    local g = guidOf(p.casterTarget)
    if p.mobGuid and (g.kind ~= "readable" or g.guid ~= p.mobGuid) then
        outcome = "unknown" -- the caster changed target: the mob cannot be read again through the same token
    else
        local after = flag(Call(UnitIsUnit, p.mobTarget, p.caster))
        if p.before == true then
            outcome = "already"
        elseif after == true and p.before == false then
            outcome = "changed"
        elseif after == false then
            outcome = "unchanged"
        else
            outcome = "unknown"
        end
    end
    p.cell[outcome] = p.cell[outcome] + 1
    if outcome == "changed" and p.eventAt then
        p.cell.byEvent = p.cell.byEvent + 1
    end
    p.recent.outcome = outcome
    if outcome == "changed" and fight7 then
        fight7.changed = fight7.changed + 1
        if fight7.logged < LOG_CHANGES_PER_FIGHT then
            fight7.logged = fight7.logged + 1
            Probe:Log("P7", string.format("t=%.1f [%s] spell %d by %s: the mob turned to the caster within %.1f s%s",
                elapsed("P7"), p.key, p.spell, p.kind, FOLLOW, p.eventAt and string.format(" (UNIT_TARGET after %d ms)",
                ms(p.eventAt - p.at)) or " (no UNIT_TARGET)"))
        end
    end
end

local function freeSlot()
    for i = 1, MAX_PENDING do
        if not pending[i] then
            return i
        end
    end
end

local function onCast(unit, _, spellID)
    if not watching() then
        return
    end
    local st, key = statsNow("p7")
    local casts = sub(st, "casts")
    local kind = tokenKind(unit)
    bump(sub(casts, "payload"), kind)
    if not CASTER_KINDS[kind] or type(unit) ~= "string" then
        return
    end
    -- In a raid the same cast also arrives as partyN, and the player's own (or the pet's) as raidN: count it once.
    if (kind == "party" or kind == "partypet") and flag(Call(IsInRaid)) == true then
        return
    end
    if (kind == "party" or kind == "raid") and flag(Call(UnitIsUnit, unit, "player")) == true then
        return
    end
    if (kind == "partypet" or kind == "raidpet") and flag(Call(UnitIsUnit, unit, "pet")) == true then
        return
    end
    local spellKind = (Describe(spellID))
    bump(sub(casts, "spellKinds"), spellKind)
    if spellKind ~= "number" then
        return -- a secret spell id is only counted (PRB-02)
    end
    local spell = spellID
    local cell = spellCell(st, spell)
    cell.casts = cell.casts + 1
    if fight7 then
        fight7.casts = fight7.casts + 1
    end
    local r = { t = now() or 0, spell = spell, kind = kind, outcome = "no mob targeted" }
    keep(recent, r, RECENT_KEEP)
    local casterTarget = unit == "player" and "target" or (unit .. "target")
    if not hostile(casterTarget) then
        return
    end
    cell.onMob = cell.onMob + 1
    r.outcome = "pending"
    local slot = freeSlot()
    if not slot then
        cell.unknown = cell.unknown + 1
        r.outcome = "not followed"
        return
    end
    local g = guidOf(casterTarget)
    pending[slot] = { at = r.t, caster = unit, kind = kind, casterTarget = casterTarget,
        mobTarget = casterTarget .. "target", mobGuid = g.kind == "readable" and g.guid or nil,
        before = flag(Call(UnitIsUnit, casterTarget .. "target", unit)), cell = cell, spell = spell, key = key,
        recent = r }
    if not Probe.After("P7-cast" .. slot, FOLLOW, function()
        finishCast(slot)
    end) then
        pending[slot] = nil
    end
end

Probe:On("UNIT_SPELLCAST_SUCCEEDED", onCast)

-- /atwp note P7 taunt: logs the group's casts of the last 10 s, so that M0.7 can tell the taunt's spell id.
table.insert(Probe.noteHooks, function(id)
    if id ~= "P7" then
        return
    end
    local t = now() or 0
    local parts = {}
    for i = #recent, 1, -1 do
        local r = recent[i]
        if t - r.t > 10 then
            break
        end
        parts[#parts + 1] = string.format("spell %d by %s %.1f s before: %s", r.spell, r.kind, t - r.t, r.outcome)
    end
    bump(store("p7"), "notes")
    Probe:Log("P7", "note: group casts in the last 10 s: " .. (#parts > 0 and table.concat(parts, "; ") or "none"))
end)

----------------------------------------------------------------------------------------------------------------------
-- P7: encounters
----------------------------------------------------------------------------------------------------------------------

local MAX_ENCOUNTERS = 30

local function onEncounter(what, encounterID, difficultyID, groupSize, success, unitStatus)
    local s = store("p7")
    local list = sub(s, "encounters")
    local c = Probe.Context()
    local entry = string.format("%s [%s] id=%s difficulty=%s size=%s inProgress=%s", what, contextKey(c),
        shownNumber(encounterID), shownNumber(difficultyID), shownNumber(groupSize),
        boolText(Call(API("C_InstanceEncounter", "IsEncounterInProgress"))))
    if what == "end" then
        entry = entry .. " success=" .. shownNumber(success) .. " unitStatus=" .. tableKind(unitStatus)
    end
    keep(list, entry, MAX_ENCOUNTERS)
    bump(sub(s, "encounterCounts"), what .. " " .. tostring(c.code))
    Probe:Log("P7", "encounter " .. entry)
end

-- The encounter name (second value) is never read.
Probe:On("ENCOUNTER_START", function(encounterID, _, difficultyID, groupSize)
    onEncounter("start", encounterID, difficultyID, groupSize)
end)
Probe:On("ENCOUNTER_END", function(encounterID, _, difficultyID, groupSize, success, unitStatus)
    onEncounter("end", encounterID, difficultyID, groupSize, success, unitStatus)
end)

----------------------------------------------------------------------------------------------------------------------
-- P7: deaths
----------------------------------------------------------------------------------------------------------------------

local MAX_DEATHS = 300          -- deaths remembered (memory only, by GUID or token)
local SAME_DEATH = 2            -- seconds within which another source sees the same death
local LOG_DEATHS_PER_FIGHT = 10

local deaths, deathCount = {}, 0   -- id -> { t, who, sources }

local function deathStats(st)
    local d = sub(st, "deaths")
    for _, name in ipairs({ "who", "first", "seenBy", "method", "health", "healthMax", "healthMaxPred", "isDead",
        "events" }) do
        sub(d, name)
    end
    return d
end

local function forgetOldDeaths()
    local t = now() or 0
    for id, e in pairs(deaths) do
        if e.who ~= "group" and t - e.t > 30 then
            deaths[id] = nil
            deathCount = deathCount - 1
        end
    end
end

--- A death seen by `source` for the unit known as `id` (GUID in memory, or a token).
local function noteDeath(d, id, who, source, method, label)
    local t = now() or 0
    local e = deaths[id]
    if not e then
        if deathCount >= MAX_DEATHS then
            forgetOldDeaths()
            if deathCount >= MAX_DEATHS then
                return
            end
        end
        deathCount = deathCount + 1
        e = { t = t, who = who, sources = {} }
        deaths[id] = e
        bump(d.who, who)
        bump(d.first, source)
        if method then
            bump(d.method, method)
        end
        if fight7 then
            fight7.deaths[who] = (fight7.deaths[who] or 0) + 1
            if fight7.deathLines < LOG_DEATHS_PER_FIGHT then
                fight7.deathLines = fight7.deathLines + 1
                Probe:Log("P7", string.format("t=%.1f death of %s (%s), first seen by %s%s", elapsed("P7"), who,
                    label or "?", source, method and (" via " .. method) or ""))
            end
        end
    end
    if not e.sources[source] and t - e.t <= SAME_DEATH then
        e.sources[source] = true
        bump(d.seenBy, who .. " " .. source)
    end
end

--- Reads whether `unit` is dead (UnitIsDead, UnitIsDeadOrGhost, health 0) after `source` named it.
local function checkDeath(unit, source)
    local kind = tokenKind(unit)
    if kind == "secret" or type(unit) ~= "string" or not exists(unit) then
        return
    end
    local d = deathStats((statsNow("p7")))
    local who = whoOf(unit, kind)
    local okA, deadA = Call(UnitIsDead, unit)
    local okB, deadB = Call(UnitIsDeadOrGhost, unit)
    local okH, hp = Call(UnitHealth, unit, false)
    local okM, hpMax = Call(UnitHealthMax, unit)
    bump(d.isDead, who .. " " .. callKind(okA, deadA))
    bump(d.health, who .. " " .. callKind(okH, hp))
    bump(d.healthMax, who .. " " .. callKind(okM, hpMax))
    bump(d.healthMaxPred, who .. " " .. boolText(Call(API("C_Secrets", "ShouldUnitHealthMaxBeSecret"), unit)))
    local byFlag = flag(okA, deadA) == true or flag(okB, deadB) == true
    local zero = okH and number(hp) ~= nil and hp <= 0
    local g = guidOf(unit)
    local id = g.kind == "readable" and g.guid or ("token:" .. unit)
    if not byFlag and not zero then
        if flag(okA, deadA) == false and deaths[id] then
            deaths[id] = nil -- alive again (resurrected): a later death counts again
            deathCount = deathCount - 1
            bump(d, "revived")
        end
        return
    end
    if zero and flag(okA, deadA) == false then
        bump(d, "health0Alive") -- health 0 while UnitIsDead says no (feign death, a hidden health)
    end
    local method = byFlag and (zero and "both" or "UnitIsDead") or "health 0"
    local label = kind
    if who == "mobs" then
        label = (Probe.Mob(unit))
    end
    noteDeath(d, id, who, source, method, label)
end

--- A death named by a GUID payload (UNIT_DIED, PARTY_KILL): its kind, and the death if the GUID is readable.
local function guidDeath(source, guid)
    local d = deathStats((statsNow("p7")))
    if IsSecret(guid) then
        bump(d.events, source .. " secret")
        return
    end
    if type(guid) ~= "string" or guid == "" then
        bump(d.events, source .. " nil")
        return
    end
    bump(d.events, source .. " readable")
    local guidType = guid:match("^(%a+)%-") or "other"
    local who = guidType == "Player" and "players" or "mobs"
    local units = groupUnits()
    table.insert(units, 1, "player")
    for _, unit in ipairs(units) do
        local g = guidOf(unit)
        if g.kind == "readable" and g.guid == guid then
            who = "group"
            break
        end
    end
    noteDeath(d, guid, who, source, nil, guidType ~= "Player" and guidType or "player")
end

local function onUnitEvent(event, unit)
    if not watching() then
        return
    end
    local d = deathStats((statsNow("p7")))
    bump(d.events, event .. " " .. tokenKind(unit))
    checkDeath(unit, event)
end

Probe:On("UNIT_HEALTH", function(unit)
    onUnitEvent("UNIT_HEALTH", unit)
end)
Probe:On("UNIT_FLAGS", function(unit)
    onUnitEvent("UNIT_FLAGS", unit)
end)
Probe:On("UNIT_DIED", function(guid)
    if watching() then
        guidDeath("UNIT_DIED", guid)
    end
end)
Probe:On("PARTY_KILL", function(_, targetGUID)
    if watching() then
        guidDeath("PARTY_KILL", targetGUID) -- the attacker (first value) is never read
    end
end)
Probe:On("PLAYER_DEAD", function()
    if watching() then
        local d = deathStats((statsNow("p7")))
        bump(d.events, "PLAYER_DEAD")
        checkDeath("player", "PLAYER_DEAD")
    end
end)

local POLLED = { "player", "target", "focus", "boss1", "boss2", "boss3", "boss4", "boss5" }

local function pollDeaths()
    for _, unit in ipairs(POLLED) do
        checkDeath(unit, "poll")
    end
    for _, unit in ipairs(groupUnits()) do
        checkDeath(unit, "poll")
    end
end

----------------------------------------------------------------------------------------------------------------------
-- P7: the watch and the verdict
----------------------------------------------------------------------------------------------------------------------

local function totalDeliveries()
    local n = 0
    for _, v in pairs(clStore().deliveries) do
        n = n + v
    end
    return n
end

local function p7FinishFight()
    local f = fight7
    fight7 = nil
    cl.fightReads = nil
    if not f then
        return
    end
    if p8Fight then
        p8Fight.groupDeaths = f.deaths.group or 0 -- P8 compares them with the damage meter's deaths
    end
    local t = now()
    Probe:Log("P7", string.format("fight end [%s] %.0f s: %d group casts, the mob turned to the caster %d times; " ..
        "UNIT_TARGET on mobs %d; deaths %s; combat log deliveries %d", tostring(f.key),
        (t and f.started) and (t - f.started) or 0, f.casts, f.changed, f.unitTarget, countsText(f.deaths),
        totalDeliveries() - f.deliveries))
end

local function p7Watch(trigger)
    if trigger == "combat-start" then
        p7FinishFight()
        forgetOldDeaths()
        local st, key, code = statsNow("p7", true)
        bump(st, "fights")
        fight7 = { key = key, code = code, started = now(), casts = 0, changed = 0, unitTarget = 0, deaths = {},
            deathLines = 0, logged = 0, deliveries = totalDeliveries() }
        cl.fightReads = {}
        elapsed("P7", true)
        readRestricted(st)
    elseif trigger == "tick" then
        pollDeaths()
    elseif trigger == "combat-end" then
        pollDeaths()
        p7FinishFight()
    end
end

table.insert(Probe.watchHooks, p7Watch)

--- What the combat log gave: "readable" (some reader returned a readable value during an event), "secret" (only
--- secret values), "nothing" (delivered but no reader answered) or "not delivered"; and a text.
local function combatLogSummary()
    local c = clStore()
    local delivered = totalDeliveries()
    local readable, secretOnly = {}, false
    for _, key in ipairs(sortedKeys(c.readers)) do
        local rs = c.readers[key]
        if key:find("(event)", 1, true) then
            if (rs.readable or 0) > 0 then
                readable[#readable + 1] = key
            elseif rs.kinds and (rs.kinds.secret or 0) > 0 then
                secretOnly = true
            end
        end
    end
    local regs = {}
    for _, event in ipairs(CL_EVENTS) do
        local r = c.registration[event]
        regs[#regs + 1] = string.format("%s %s", event, r and (r.isRegistered == "yes" and "registered" or
            ("refused (" .. tostring(r.call) .. ", returned " .. tostring(r.returned or "-") .. ")")) or "not tried")
    end
    local readers = {}
    for _, key in ipairs(sortedKeys(c.readers)) do
        local rs = c.readers[key]
        readers[#readers + 1] = string.format("%s: %d calls, missing %d, error %d, readable %d, unreadable %d " ..
            "(kinds %s)", key, rs.calls or 0, rs.missing or 0, rs.error or 0, rs.readable or 0, rs.unreadable or 0,
            countsText(rs.kinds))
    end
    local actions = store("p7").actions or {}
    local text = string.format("Combat log: %s; deliveries %s; readers %s; IsCombatLogRestricted %s; blocked %s, " ..
        "forbidden %s (%d within 2 s of a registration).", table.concat(regs, ", "), countsText(c.deliveries),
        #readers > 0 and table.concat(readers, "; ") or "never called", countsText(c.restricted),
        countsText(actions.blocked), countsText(actions.forbidden), actions.afterRegistration or 0)
    if #readable > 0 then
        return "readable", text, readable
    elseif delivered == 0 then
        return "not delivered", text
    elseif secretOnly then
        return "secret", text
    end
    return "nothing", text
end

local function p7Verdict()
    local s = store("p7")
    local clState, clText, readable = combatLogSummary()
    local fights, perCode = 0, {}
    local regen = { disabled = 0, enabled = 0, same = 0, later = 0, never = 0, secret = 0 }
    local delays = {}
    local ut = { kinds = {}, mobTargets = {} }
    local casts = { payload = {}, spellKinds = {}, total = 0, onMob = 0, changed = 0, byEvent = 0 }
    local changedSpells, instanceSecretSpells, instanceReadableSpells = {}, 0, 0
    local dd = { who = {}, first = {}, seenBy = {}, events = {}, health = {} }
    for _, st in pairs(s.stats or {}) do
        if GROUP_CODES[st.code] then
            fights = fights + (st.fights or 0)
            bump(perCode, st.code, st.fights or 0)
            local r = st.regen
            if r then
                for k in pairs(regen) do
                    regen[k] = regen[k] + (r[k] or 0)
                end
                for _, v in ipairs(r.delays or {}) do
                    delays[#delays + 1] = v
                end
            end
            for name, t in pairs(st.unitTarget or {}) do
                for k, n in pairs(t) do
                    bump(ut[name], k, n)
                end
            end
            local c = st.casts
            if c then
                for k, n in pairs(c.payload or {}) do
                    bump(casts.payload, k, n)
                end
                for k, n in pairs(c.spellKinds or {}) do
                    bump(casts.spellKinds, k, n)
                    if INSTANCE_CODES[st.code] then
                        if k == "secret" then
                            instanceSecretSpells = instanceSecretSpells + n
                        elseif k == "number" then
                            instanceReadableSpells = instanceReadableSpells + n
                        end
                    end
                end
                for spell, cell in pairs(c.spells or {}) do
                    casts.total = casts.total + cell.casts
                    casts.onMob = casts.onMob + cell.onMob
                    casts.changed = casts.changed + cell.changed
                    casts.byEvent = casts.byEvent + cell.byEvent
                    if cell.changed > 0 and spell ~= "other" then
                        changedSpells[spell] = (changedSpells[spell] or 0) + cell.changed
                    end
                end
            end
            for name, t in pairs(st.deaths or {}) do
                if dd[name] then
                    for k, n in pairs(t) do
                        bump(dd[name], k, n)
                    end
                end
            end
        end
    end
    local encounters = s.encounterCounts or {}
    local encounterEnds = (encounters["end dungeon"] or 0) + (encounters["end raid"] or 0)
    local spellText = {}
    for _, spell in ipairs(sortedKeys(changedSpells)) do
        spellText[#spellText + 1] = tostring(spell) .. " x" .. changedSpells[spell]
    end
    local delayText = "no delay"
    if #delays > 0 then
        local copy = {}
        for i, v in ipairs(delays) do
            copy[i] = v
        end
        delayText = "late by median " .. tostring(median(copy)) .. " ms"
    end
    local tail = string.format(" Fights %s. PLAYER_REGEN_DISABLED %d, ENABLED %d: UnitAffectingCombat agreed at " ..
        "once %d, later %d (%s), not within 3 s %d, secret %d. UNIT_TARGET payload %s; mob targets %s. Group " ..
        "casts %d (spell id %s; payload %s), on a hostile target %d, mob turned to the caster %d (UNIT_TARGET " ..
        "seen %d); " ..
        "spells followed by a turn: %s. Deaths %s, first seen by %s, seen by %s; events %s; UnitHealth %s. " ..
        "Encounters %s; taunt notes %d. %s", countsText(perCode), regen.disabled, regen.enabled, regen.same,
        regen.later, delayText, regen.never, regen.secret, countsText(ut.kinds), countsText(ut.mobTargets),
        casts.total, countsText(casts.spellKinds), countsText(casts.payload), casts.onMob, casts.changed,
        casts.byEvent, #spellText > 0 and table.concat(spellText, ", ") or "none", countsText(dd.who),
        countsText(dd.first), countsText(dd.seenBy), countsText(dd.events), countsText(dd.health),
        countsText(encounters), s.notes or 0, clText)
    if fights == 0 then
        return "todo", "no fight yet in a party, dungeon or raid with /atwp watch on." .. tail
    end

    -- Unit events missing or secret where they matter: the recorder would have only samples (SPEC-08 P7).
    local failures = {}
    local utTotal, utSecret = 0, ut.kinds.secret or 0
    for _, n in pairs(ut.kinds) do
        utTotal = utTotal + n
    end
    local utMobs = 0
    for _, n in pairs(ut.mobTargets) do
        utMobs = utMobs + n
    end
    if utTotal > 0 and utSecret == utTotal then
        failures[#failures + 1] = "UNIT_TARGET payload always secret"
    elseif utMobs == 0 and fights >= 3 then
        failures[#failures + 1] = "UNIT_TARGET never arrived for a hostile mob in " .. fights .. " fights"
    end
    if instanceSecretSpells > 0 and instanceReadableSpells == 0 then
        failures[#failures + 1] = "spellID of the group's casts secret in instances"
    end
    if regen.disabled + regen.enabled > 0 and regen.same + regen.later == 0 then
        failures[#failures + 1] = "UnitAffectingCombat never agreed with PLAYER_REGEN_*"
    end
    if #failures > 0 then
        return "not supported", table.concat(failures, "; ") .. "." .. tail
    end

    local todo = {}
    if (perCode.dungeon or 0) == 0 then
        todo[#todo + 1] = "a dungeon"
    end
    if encounterEnds == 0 then
        todo[#todo + 1] = "a boss (ENCOUNTER_END in a dungeon or raid)"
    end
    if casts.total == 0 then
        todo[#todo + 1] = "a cast of the group with a readable spell id"
    end
    if casts.changed == 0 then
        todo[#todo + 1] = "a taunt (/atwp note P7 taunt)"
    end
    if next(dd.who) == nil then
        todo[#todo + 1] = "a death seen"
    end
    if utMobs == 0 then
        todo[#todo + 1] = "a UNIT_TARGET on a mob"
    end
    if (perCode.raid or 0) == 0 then
        todo[#todo + 1] = "a raid (optional for the verdict)"
    end
    local essential = #todo - ((perCode.raid or 0) == 0 and 1 or 0)
    local clLine = clState == "readable" and ("the combat log is readable through " .. table.concat(readable, ", "))
        or ("the combat log is not readable (" .. clState .. ")")
    if essential > 0 then
        return "todo", clLine .. "; nothing failed so far; still to play: " .. table.concat(todo, ", ") .. "." .. tail
    end
    if clState == "readable" then
        return "supported", clLine .. "; unit events work." .. tail
    end
    return "partial", clLine .. "; unit events work (the expected case)." .. tail
end

Probe:Register("P7", "Combat events: combat log, targets, encounters, deaths, taunts", function()
    Probe.LearnNames()
    registerCombatLog("run")
    for _, reader in ipairs(READERS) do
        readCombatLog(reader, "outside")
    end
    local restricted = readRestricted()
    if not watching() then
        out("P7 counts unit events only while /atwp watch is on")
    end
    out(string.format("P7 now: combat log deliveries %d, IsCombatLogRestricted %s", totalDeliveries(), restricted))
    return p7Verdict()
end)

----------------------------------------------------------------------------------------------------------------------
-- P8: C_DamageMeter
----------------------------------------------------------------------------------------------------------------------

local SOURCE_FIELDS = { "sourceGUID", "sourceCreatureID", "name", "classFilename", "totalAmount", "amountPerSecond",
    "isLocalPlayer", "deathRecapID", "deathTimeSeconds", "classification" }
local MAX_ENUM = 16
local MAX_SOURCES = 40
local MAX_SESSIONS = 50
local DIFFS_KEEP = 30
local DM_EVENTS = { DAMAGE_METER_COMBAT_SESSION_UPDATED = "session updated",
    DAMAGE_METER_CURRENT_SESSION_UPDATED = "current updated", DAMAGE_METER_RESET = "reset" }

local function dm(name)
    return API("C_DamageMeter", name)
end

--- The values of Enum[name] found at run time, sorted by value: { {name, value} }; nil when the table is missing.
local function enumValues(name)
    local enum = API("Enum", name)
    if IsSecret(enum) or type(enum) ~= "table" then
        return nil
    end
    local list = {}
    pcall(function()
        for k, v in pairs(enum) do
            if #list >= MAX_ENUM then
                break
            end
            if not IsSecret(k) and not IsSecret(v) and type(k) == "string" and type(v) == "number" then
                list[#list + 1] = { name = k:match("^[%w_]+$") and k:sub(1, 40) or "other", value = v }
            end
        end
    end)
    table.sort(list, function(a, b)
        return a.value < b.value
    end)
    return list
end

local function enumText(list)
    if not list then
        return "absent"
    end
    local parts = {}
    for _, e in ipairs(list) do
        parts[#parts + 1] = e.name .. "=" .. tostring(e.value)
    end
    return #parts > 0 and table.concat(parts, ",") or "empty"
end

--- Kinds of the fields of a session and of its sources, counted in `cell`. Returns the readable duration or nil.
local function describeSession(session, cell)
    local deaths = 0
    local kind = tableKind(session)
    bump(sub(cell, "session"), kind)
    if kind ~= "table" then
        return nil
    end
    local fields = sub(cell, "fields")
    local okD, duration = getField(session, "durationSeconds")
    bump(fields, "durationSeconds " .. (okD and (Describe(duration)) or "error"))
    local okS, sources = getField(session, "combatSources")
    local sk = okS and tableKind(sources) or "error"
    if sk ~= "table" then
        bump(fields, "combatSources " .. sk)
        return okD and number(duration) or nil, 0
    end
    local n = eachEntry(sources, MAX_SOURCES, function(src)
        local srcKind = tableKind(src)
        if srcKind ~= "table" then
            bump(fields, "source " .. srcKind)
            return
        end
        bump(cell, "sources")
        for _, f in ipairs(SOURCE_FIELDS) do
            local okF, v = getField(src, f)
            local k = okF and (Describe(v)) or "error"
            bump(fields, f .. " " .. k)
            if k == "boolean" and f == "isLocalPlayer" and v == true then
                bump(cell, "localSources")
            elseif k == "number" and (f == "deathTimeSeconds" or f == "deathRecapID") and v ~= 0 then
                bump(cell, f)
                if f == "deathTimeSeconds" then
                    deaths = deaths + 1
                end
            end
        end
    end)
    if not n then
        bump(fields, "combatSources not iterable")
    end
    return okD and number(duration) or nil, deaths
end

--- The sessions of GetAvailableCombatSessions: how many, and the readable durations (never the name).
local function readSessions(st)
    local ok, sessions = Call(dm("GetAvailableCombatSessions"))
    local a = sub(st, "available")
    local kind = ok and tableKind(sessions) or callKind(ok, sessions)
    bump(sub(a, "list"), kind)
    if kind ~= "table" then
        return nil
    end
    local newestId, newestDuration, count = nil, nil, 0
    local n = eachEntry(sessions, MAX_SESSIONS, function(entry)
        if tableKind(entry) ~= "table" then
            bump(sub(a, "fields"), "entry " .. tableKind(entry))
            return
        end
        count = count + 1
        local okI, id = getField(entry, "sessionID")
        local okD, duration = getField(entry, "durationSeconds")
        bump(sub(a, "fields"), "sessionID " .. (okI and (Describe(id)) or "error"))
        bump(sub(a, "fields"), "durationSeconds " .. (okD and (Describe(duration)) or "error"))
        local plainId = okI and number(id) or nil
        if plainId and (not newestId or plainId > newestId) then
            newestId, newestDuration = plainId, okD and number(duration) or nil
        end
    end)
    a.maxCount = math.max(a.maxCount or 0, n or 0)
    return newestDuration, n
end

local regenAt = { event = nil, at = nil, seen = {} }

--- One reading of C_DamageMeter; `fight` (optional) is the fight that just ended, to compare the durations.
local function p8Read(trigger, fight)
    local st, key
    if fight then
        st, key = statsFor("p8", fight.key, fight.code, true), fight.key
    else
        st, key = statsNow("p8", true)
    end
    bump(st, "reads")
    local ok, isAvailable, reason = Call(dm("IsDamageMeterAvailable"))
    local avail = boolText(ok, isAvailable)
    bump(sub(st, "isAvailable"), avail)
    local reasonText = "-"
    if ok then
        if IsSecret(reason) then
            reasonText = "secret"
        elseif type(reason) == "string" and reason ~= "" then
            reasonText = Probe.Scrub(reason):gsub("[|\r\n]", " "):sub(1, 80)
        end
        st.reason = reasonText
    end
    local sessionTypes = enumValues("DamageMeterSessionType") or {}
    local meterTypes = enumValues("DamageMeterType") or {}
    local newest, count = readSessions(st)
    local durations, parts, sessionDeaths = {}, {}, {}
    for _, stype in ipairs(sessionTypes) do
        local okD, duration = Call(dm("GetSessionDurationSeconds"), stype.value)
        local dk = callKind(okD, duration)
        bump(sub(sub(st, "durations"), stype.name), dk)
        if dk == "number" then
            durations[stype.name] = duration
        end
        for _, mtype in ipairs(meterTypes) do
            local cells = sub(st, "sessions")
            local cell = sub(cells, stype.name .. "/" .. mtype.name)
            local okC, session = Call(dm("GetCombatSessionFromType"), stype.value, mtype.value)
            if okC then
                local _, deaths = describeSession(session, cell)
                sessionDeaths[stype.name] = math.max(sessionDeaths[stype.name] or 0, deaths or 0)
            else
                bump(sub(cell, "session"), callKind(okC, session))
            end
        end
        parts[#parts + 1] = stype.name .. " " .. (durations[stype.name] and string.format("%.1f s",
            durations[stype.name]) or dk)
    end
    if newest then
        durations["newest available"] = newest
    end
    -- Durations against the measured fight (SPEC-08 P8: aligned within 1 s).
    local diffs = {}
    if fight and fight.duration then
        bump(st, "fights")
        local align = sub(st, "align")
        for name, duration in pairs(durations) do
            local diff = math.floor((duration - fight.duration) * 10 + 0.5) / 10
            keep(sub(align, name), diff, DIFFS_KEEP)
            diffs[#diffs + 1] = name .. " " .. string.format("%+.1f", diff)
        end
        table.sort(diffs)
        -- Deaths per session type (the largest count over the meter types) against the group deaths the watch saw.
        for name, n in pairs(sessionDeaths) do
            bump(sub(st, "sessionDeaths"), name, n)
        end
        bump(st, "p7GroupDeaths", fight.groupDeaths or 0)
    end
    Probe:Log("P8", string.format("%s [%s] available %s (reason %s); sessions %s (newest %s); durations %s%s", trigger,
        key, avail, reasonText, tostring(count or "unreadable"), newest and string.format("%.1f s", newest) or "-",
        #parts > 0 and table.concat(parts, ", ") or "no session type",
        fight and fight.duration and string.format("; fight %.1f s, differences %s", fight.duration,
            #diffs > 0 and table.concat(diffs, ", ") or "none") or ""))
    return avail, reasonText
end

Probe:On("PLAYER_REGEN_DISABLED", function()
    regenAt = { event = "start", at = now(), seen = {} }
    local c = Probe.Context()
    -- UnitAffectingCombat may not be set yet when the event fires: this is a fight in any case.
    c.combat = "yes"
    if c.code == "solo" then
        c.code = "solo-combat"
    end
    p8Fight = { key = contextKey(c), code = c.code, started = now() }
end)
Probe:On("PLAYER_REGEN_ENABLED", function()
    regenAt = { event = "end", at = now(), seen = {} }
    local f = p8Fight
    local t = now()
    if not f or not f.started or not t then
        return
    end
    f.duration = t - f.started
    Probe.After("P8-after", 2, function()
        p8Read("after-fight", f)
    end)
end)

for event, short in pairs(DM_EVENTS) do
    local name, label = event, short
    Probe:On(name, function(...)
        local st = statsNow("p8")
        local e = sub(sub(st, "events"), label)
        bump(e, "count")
        local kinds = {}
        for i = 1, math.min(select("#", ...), 4) do
            kinds[#kinds + 1] = (Describe((select(i, ...))))
        end
        bump(sub(e, "payload"), #kinds > 0 and table.concat(kinds, "/") or "none")
        local t = now()
        if regenAt.at and t and not regenAt.seen[name] then
            regenAt.seen[name] = true
            keep(sub(e, "after " .. regenAt.event), ms(t - regenAt.at), DIFFS_KEEP)
        end
    end)
end

local function delaysText(list)
    if not list or #list == 0 then
        return "-"
    end
    local copy, high = {}, nil
    for i, v in ipairs(list) do
        copy[i] = v
        high = math.max(high or v, v)
    end
    return string.format("median %s ms, max %d ms (%d)", tostring(median(copy)), high, #list)
end

local function p8Verdict(avail, reasonText)
    local s = store("p8")
    local sessionTypes, meterTypes = enumValues("DamageMeterSessionType"), enumValues("DamageMeterType")
    s.enums = { sessionTypes = enumText(sessionTypes), meterTypes = enumText(meterTypes) }
    local threatType
    for _, e in ipairs(meterTypes or {}) do
        if e.name:lower():find("threat") then
            threatType = e.name
        end
    end
    local head = threatType and ("a damage meter type named " .. threatType .. " exists (a new ADR). ") or ""
    local enumsText = string.format(" Enum.DamageMeterSessionType %s; Enum.DamageMeterType %s.", s.enums.sessionTypes,
        s.enums.meterTypes)
    if type(dm("IsDamageMeterAvailable")) ~= "function" then
        return "not supported", head .. "C_DamageMeter.IsDamageMeterAvailable is missing." .. enumsText
    end
    if avail == "no" then
        return "not supported", head .. "not available, failureReason " .. reasonText .. "." .. enumsText
    end
    if avail == "error" then
        return "not supported", head .. "IsDamageMeterAvailable fails." .. enumsText
    end

    local perCode, secretInInstance, groupSources, groupLocal = {}, {}, 0, 0
    local deathKinds, align = {}, {}
    local dmDeaths, p7Deaths = {}, 0
    for _, st in pairs(s.stats or {}) do
        bump(perCode, st.code, st.fights or 0)
        for _, cell in pairs(st.sessions or {}) do
            for k, n in pairs(cell.fields or {}) do
                if k:find("^deathTimeSeconds ") or k:find("^deathRecapID ") then
                    bump(deathKinds, k, n)
                end
                if INSTANCE_CODES[st.code] and (k:find(" secret$") or k:find(" secret table$")) then
                    bump(secretInInstance, (k:gsub(" secret table$", ""):gsub(" secret$", "")), n)
                end
            end
            for k, n in pairs(cell.session or {}) do
                if INSTANCE_CODES[st.code] and (k == "secret" or k == "secret table") then
                    bump(secretInInstance, "session " .. k, n)
                end
            end
            if GROUP_CODES[st.code] then
                groupSources = groupSources + (cell.sources or 0)
                groupLocal = groupLocal + (cell.localSources or 0)
            end
        end
        for name, n in pairs(st.sessionDeaths or {}) do
            bump(dmDeaths, name, n)
        end
        p7Deaths = p7Deaths + (st.p7GroupDeaths or 0)
        for name, list in pairs(st.align or {}) do
            local a = align[name] or { n = 0, within = 0 }
            align[name] = a
            for _, diff in ipairs(list) do
                a.n = a.n + 1
                if math.abs(diff) <= 1 then
                    a.within = a.within + 1
                end
            end
        end
    end
    local best, alignParts = nil, {}
    for _, name in ipairs(sortedKeys(align)) do
        local a = align[name]
        alignParts[#alignParts + 1] = string.format("%s %d/%d", name, a.within, a.n)
        if not best or a.within > align[best].within then
            best = name
        end
    end
    local events = {}
    for _, st in pairs(s.stats or {}) do
        for label, e in pairs(st.events or {}) do
            local a = events[label] or { count = 0, start = {}, ["end"] = {} }
            events[label] = a
            a.count = a.count + (e.count or 0)
            for _, v in ipairs(e["after start"] or {}) do
                a.start[#a.start + 1] = v
            end
            for _, v in ipairs(e["after end"] or {}) do
                a["end"][#a["end"] + 1] = v
            end
        end
    end
    local eventParts = {}
    for _, label in ipairs(sortedKeys(events)) do
        local a = events[label]
        eventParts[#eventParts + 1] = string.format("%s %d (after combat start %s; after combat end %s)", label,
            a.count, delaysText(a.start), delaysText(a["end"]))
    end
    local fights = 0
    for _, n in pairs(perCode) do
        fights = fights + n
    end
    local tail = string.format(" Fights measured %s. Durations within 1 s of the fight (per session): %s. Death " ..
        "fields %s; deaths in the sessions per type %s (the watch saw %d group deaths). Group contexts: %d sources, " ..
        "%d of them the local player. Secret in instances: %s. Events %s.%s", countsText(perCode),
        #alignParts > 0 and table.concat(alignParts, ", ") or "none", countsText(deathKinds), countsText(dmDeaths),
        p7Deaths, groupSources, groupLocal, countsText(secretInInstance),
        #eventParts > 0 and table.concat(eventParts, "; ") or "none", enumsText)
    if fights == 0 then
        return "todo", head .. "available " .. avail .. "; no fight measured yet (fight, wait 2 s, /atwp run P8)." ..
            tail
    end
    local issues = {}
    if avail == "secret" then
        issues[#issues + 1] = "availability secret"
    end
    if next(secretInInstance) then
        issues[#issues + 1] = "secret fields in instances"
    end
    if groupSources > 0 and groupSources == groupLocal then
        issues[#issues + 1] = "only the player's own data in a group"
    end
    if (deathKinds["deathTimeSeconds secret"] or 0) > 0 then
        issues[#issues + 1] = "death times secret"
    end
    if best and align[best].within < align[best].n then
        issues[#issues + 1] = string.format("durations not aligned within 1 s (best %s, %d/%d)", best,
            align[best].within, align[best].n)
    elseif not best then
        issues[#issues + 1] = "no readable session duration"
    end
    if #issues > 0 then
        return "partial", head .. table.concat(issues, "; ") .. "." .. tail
    end
    local todo = {}
    if (perCode["solo-combat"] or 0) == 0 then
        todo[#todo + 1] = "a fight alone"
    end
    if (perCode.dungeon or 0) == 0 then
        todo[#todo + 1] = "a fight in a dungeon"
    end
    if not (deathKinds["deathTimeSeconds number"]) then
        todo[#todo + 1] = "a readable death field"
    end
    if #todo > 0 then
        return "todo", head .. "nothing failed so far; still to play: " .. table.concat(todo, ", ") .. "." .. tail
    end
    return "supported", head .. "available, sessions aligned with the fights (" .. best .. "), deaths readable." .. tail
end

Probe:Register("P8", "C_DamageMeter: availability, sessions, deaths", function()
    local avail, reasonText = p8Read("run")
    out("P8 now: available " .. avail .. ", reason " .. reasonText)
    return p8Verdict(avail, reasonText)
end)

----------------------------------------------------------------------------------------------------------------------
-- Export and reset
----------------------------------------------------------------------------------------------------------------------

table.insert(Probe.exportHooks, function()
    local lines = { "-- P7 combat log (kinds only, never the content)" }
    local c = clStore()
    for _, event in ipairs(CL_EVENTS) do
        local r = c.registration[event]
        lines[#lines + 1] = string.format("%s: %s", event, r and string.format("attempts %d, call %s, returned %s, " ..
            "IsEventRegistered %s%s", r.attempts or 0, tostring(r.call), tostring(r.returned or "-"),
            tostring(r.isRegistered), r.error and (", error " .. r.error) or "") or "not tried")
    end
    lines[#lines + 1] = string.format("frame %s; deliveries %s; arguments per delivery %s; IsCombatLogRestricted %s",
        tostring(c.frame or "-"), countsText(c.deliveries), countsText(c.arity), countsText(c.restricted))
    for _, i in ipairs(sortedKeys(c.argKinds)) do
        lines[#lines + 1] = string.format("argument %s: %s", tostring(i), countsText(c.argKinds[i]))
    end
    for _, key in ipairs(sortedKeys(c.readers)) do
        local rs = c.readers[key]
        lines[#lines + 1] = string.format("reader %s: %d calls, missing %d, error %d%s, readable %d, unreadable %d, " ..
            "returns %s, kinds %s", key, rs.calls or 0, rs.missing or 0, rs.error or 0,
            rs.lastError and (" (" .. rs.lastError .. ")") or "", rs.readable or 0, rs.unreadable or 0,
            countsText(rs.returns), countsText(rs.kinds))
    end
    local p7 = store("p7")
    local actions = p7.actions or {}
    lines[#lines + 1] = string.format("ADDON_ACTION_BLOCKED %s; ADDON_ACTION_FORBIDDEN %s; within 2 s of a " ..
        "registration %d", countsText(actions.blocked), countsText(actions.forbidden), actions.afterRegistration or 0)
    lines[#lines + 1] = "-- P7 per context"
    for _, key in ipairs(sortedKeys(p7.stats)) do
        local st = p7.stats[key]
        local r = st.regen
        lines[#lines + 1] = string.format("%s: %d fights; combat log %s; regen %s; UNIT_TARGET %s, mob targets %s; " ..
            "PLAYER_TARGET_CHANGED %s", key, st.fights or 0, countsText(st.clDeliveries), r and string.format(
                "disabled %d, enabled %d, agreed %d, later %d (%s), never %d, secret %d, lockdown %s", r.disabled,
                r.enabled, r.same, r.later, delaysText(r.delays), r.never, r.secret, countsText(r.lockdown)) or "-",
            countsText(st.unitTarget and st.unitTarget.kinds), countsText(st.unitTarget and st.unitTarget.mobTargets),
            countsText(st.targetChanged))
        local casts = st.casts
        if casts then
            local spells = {}
            for _, spell in ipairs(sortedKeys(casts.spells)) do
                local cell = casts.spells[spell]
                spells[#spells + 1] = string.format("%s %d/%d/%d/%d/%d/%d (UNIT_TARGET %d)", tostring(spell),
                    cell.casts, cell.onMob, cell.changed, cell.already, cell.unchanged, cell.unknown, cell.byEvent)
            end
            lines[#lines + 1] = string.format("%s casts: payload %s; spell id %s; per spell casts/on a mob/turned/" ..
                "already/unchanged/unknown: %s", key, countsText(casts.payload), countsText(casts.spellKinds),
                #spells > 0 and table.concat(spells, ", ") or "-")
        end
        local d = st.deaths
        if d then
            lines[#lines + 1] = string.format("%s deaths: %s; first seen by %s; seen by %s; method %s; revived %d; " ..
                "health 0 alive %d; events %s; UnitIsDead %s; UnitHealth %s; UnitHealthMax %s (prediction %s)", key,
                countsText(d.who), countsText(d.first), countsText(d.seenBy), countsText(d.method), d.revived or 0,
                d.health0Alive or 0, countsText(d.events), countsText(d.isDead), countsText(d.health),
                countsText(d.healthMax), countsText(d.healthMaxPred))
        end
    end
    lines[#lines + 1] = "-- P7 encounters (ids and numbers, never the name)"
    for _, entry in ipairs(p7.encounters or {}) do
        lines[#lines + 1] = entry
    end
    local p8 = store("p8")
    lines[#lines + 1] = string.format("-- P8 C_DamageMeter: Enum.DamageMeterSessionType %s; Enum.DamageMeterType %s",
        enumText(enumValues("DamageMeterSessionType")), enumText(enumValues("DamageMeterType")))
    for _, key in ipairs(sortedKeys(p8.stats)) do
        local st = p8.stats[key]
        local durations, align = {}, {}
        for _, name in ipairs(sortedKeys(st.durations)) do
            durations[#durations + 1] = name .. " [" .. countsText(st.durations[name]) .. "]"
        end
        for _, name in ipairs(sortedKeys(st.align)) do
            local diffs = {}
            for i, v in ipairs(st.align[name]) do
                diffs[i] = string.format("%+.1f", v)
            end
            align[#align + 1] = name .. " " .. table.concat(diffs, " ")
        end
        lines[#lines + 1] = string.format("%s: %d reads, %d fights; available %s (reason %s); sessions list %s, " ..
            "max %d, fields %s; durations %s; differences from the fight %s; deaths per session type %s (watch: " ..
            "%d group deaths)", key, st.reads or 0, st.fights or 0,
            countsText(st.isAvailable), tostring(st.reason or "-"), countsText(st.available and st.available.list),
            st.available and st.available.maxCount or 0, countsText(st.available and st.available.fields),
            #durations > 0 and table.concat(durations, " ") or "-", #align > 0 and table.concat(align, "; ") or "-",
            countsText(st.sessionDeaths), st.p7GroupDeaths or 0)
        for _, name in ipairs(sortedKeys(st.sessions)) do
            local cell = st.sessions[name]
            lines[#lines + 1] = string.format("%s %s: session %s; sources %d (local %d, deathTimeSeconds %d, " ..
                "deathRecapID %d); fields %s", key, name, countsText(cell.session), cell.sources or 0,
                cell.localSources or 0, cell.deathTimeSeconds or 0, cell.deathRecapID or 0, countsText(cell.fields))
        end
        for _, label in ipairs(sortedKeys(st.events)) do
            local e = st.events[label]
            lines[#lines + 1] = string.format("%s event %s: %d, payload %s, after combat start %s, after combat end %s",
                key, label, e.count or 0, countsText(e.payload), delaysText(e["after start"]),
                delaysText(e["after end"]))
        end
    end
    return lines
end)

-- Helpers shared with Checks_Cost.lua (M0.6).
for name, fn in pairs({ keep = keep, bumpCapped = bumpCapped, sub = sub, number = number }) do
    Probe.helpers[name] = fn
end

table.insert(Probe.resetHooks, function()
    local d = Probe.DB()
    -- The registration happens once per session: its record survives a reset, the counters do not.
    local old = type(d.p7) == "table" and type(d.p7.combatLog) == "table" and d.p7.combatLog or {}
    d.p7, d.p8 = nil, nil
    local c = clStore()
    c.registration, c.frame = old.registration or {}, old.frame
    fight7, regenPending, p8Fight = nil, nil, nil
    regenAt = { event = nil, at = nil, seen = {} }
    pending, recent, deaths, deathCount = {}, {}, {}, 0
    cl.reads, cl.fightReads, cl.described = {}, nil, 0
    Probe.Cancel("P7-regen")
    Probe.Cancel("P8-after")
    for i = 1, MAX_PENDING do
        Probe.Cancel("P7-cast" .. i)
    end
end)
