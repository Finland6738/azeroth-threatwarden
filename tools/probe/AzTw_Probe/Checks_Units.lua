-- AzTw Probe, checks P5, P6 and P9 (step M0.4): units, mobs and threat events. Development only, never distributed.
-- Spec: docs/specs/SPEC-08-quality-probe-release.md, section 1 (rules PRB-01 to PRB-06, P5, P6, P9) and
-- docs/specs/SPEC-07-multi-target-heatmap-profiles.md, section 1.
-- Every API and event used here was checked against the Forever dump (build 70170) on 2026-11-25: UnitExists,
-- UnitCanAttack, UnitIsPlayer, UnitIsUnit, UnitDetailedThreatSituation, UnitThreatSituation (second argument named
-- mobGUID, typed UnitToken), UnitGUID (argument UnitTokenPvPRestrictedForAddOns, result nilable), UnitTokenFromGUID,
-- UnitGroupRolesAssigned, debugprofilestop, C_Secrets.CanCompareUnitTokens, C_Secrets.ShouldUnitIdentityBeSecret,
-- C_Secrets.ShouldUnitComparisonBeSecret; events UNIT_THREAT_LIST_UPDATE and UNIT_THREAT_SITUATION_UPDATE (payload
-- unitTarget), NAME_PLATE_UNIT_ADDED and NAME_PLATE_UNIT_REMOVED (payload unitToken), PLAYER_TARGET_CHANGED,
-- PLAYER_FOCUS_CHANGED, INSTANCE_ENCOUNTER_ENGAGE_UNIT.
--
-- All three checks read through /atwp watch (Probe.watchHooks of Checks_ThreatAPI.lua):
--   P5  every second in combat (every third second in a raid): every unit of the group on every hostile mob that a
--       token reaches (target, focus, mouseover, targettarget, pettarget, boss1-5, partyNtarget, raidNtarget,
--       nameplate1-40), deduplicated by GUID in memory; mobs seen earlier in the fight are looked up again with
--       UnitTokenFromGUID. One summary per fight.
--   P6  counts the two threat events and their payload kind; while in combat it samples the threat on the target at
--       10 Hz and measures the delay between a change seen by the sampling and the next event.
--   P9  `/atwp run P9` (and each encounter start) reads UnitGUID and the identity prediction on every unit, the roles and
--       the unit comparisons; while watching, it checks that a token keeps the same mob GUID until the token changes.
--
-- Secret values (PRB-02): every value goes through Probe.IsSecret / Probe.Describe first; a secret is only counted as
-- "secret", never compared, formatted, concatenated, stored or printed. GUIDs are compared in memory only and never
-- saved; mobs are "<mob n>" with GUID type and creature id; players are never named and their GUIDs never kept beyond
-- the call (PRB-03). Saved counters are bounded: fixed keys, capped lists.

local _, Probe = ...

local IsSecret, Describe, Call, API = Probe.IsSecret, Probe.Describe, Probe.Call, Probe.API
local out = Probe.Print
local H = Probe.helpers
local now, flag, boolText, store, elapsed, stamp = H.now, H.flag, H.boolText, H.store, H.elapsed, H.stamp
local contextKey, inCombat, exists, hostile, groupUnits = H.contextKey, H.inCombat, H.exists, H.hostile, H.groupUnits
local mobText, median = H.mobText, H.median

local GROUP_CODES = { party = true, dungeon = true, raid = true }
local INSTANCE_CODES = { dungeon = true, raid = true }

----------------------------------------------------------------------------------------------------------------------
-- Small helpers
----------------------------------------------------------------------------------------------------------------------

-- Unit token kinds the probe saves (digits removed). Anything else becomes "other", so that no free text is ever kept.
local KNOWN_KINDS = {}
for _, kind in ipairs({ "player", "pet", "target", "focus", "mouseover", "targettarget", "pettarget", "focustarget",
    "npc", "vehicle", "party", "partytarget", "partypet", "raid", "raidtarget", "raidpet", "nameplate", "boss", "arena",
    "arenapet", "softenemy", "softfriend", "softinteract", "anyenemy", "anyfriend", "none" }) do
    KNOWN_KINDS[kind] = true
end

--- Kind of a unit token: "nameplate" for "nameplate7", "partytarget" for "party2target"; "secret", "nil" or "other".
local function tokenKind(token)
    if IsSecret(token) then
        return "secret"
    end
    if type(token) ~= "string" then
        return token == nil and "nil" or "other"
    end
    local kind = token:lower():gsub("%d+", "")
    return KNOWN_KINDS[kind] and kind or "other"
end

--- The GUID of a unit: { kind = "readable" | "secret" | "nil" | "error", guid (memory only), guidType, creatureId }.
local function guidOf(unit)
    local ok, guid = Call(UnitGUID, unit)
    if not ok then
        return { kind = "error" }
    end
    if IsSecret(guid) then
        return { kind = "secret" }
    end
    if type(guid) ~= "string" or guid == "" then
        return { kind = "nil" }
    end
    local parts = {}
    for part in guid:gmatch("[^-]+") do
        parts[#parts + 1] = part
    end
    local guidType = parts[1] or "?"
    if not guidType:find("^%a+$") or #guidType > 16 then
        guidType = "other"
    end
    local g = { kind = "readable", guid = guid, guidType = guidType }
    if guidType ~= "Player" then
        g.creatureId = tonumber(parts[6])
    end
    return g
end

local function watching()
    return Probe.DB().watch == true
end

local function bump(t, key, n)
    t[key] = (t[key] or 0) + (n or 1)
end

--- Saved counters of one check for one context key (contextKey of Checks_ThreatAPI.lua).
local function statsFor(name, key, code, combat)
    local s = store(name)
    s.stats = s.stats or {}
    local st = s.stats[key]
    if not st then
        st = { code = code, combat = combat }
        s.stats[key] = st
    end
    return st
end

local function sortedKeys(t)
    local keys = {}
    for k in pairs(t or {}) do
        keys[#keys + 1] = k
    end
    table.sort(keys, function(a, b)
        return tostring(a) < tostring(b)
    end)
    return keys
end

--- "a 3, b 1" from a table of counters.
local function countsText(t)
    local parts = {}
    for _, k in ipairs(sortedKeys(t)) do
        parts[#parts + 1] = tostring(k) .. " " .. tostring(t[k])
    end
    return #parts > 0 and table.concat(parts, ", ") or "-"
end

--- Elapsed milliseconds from debugprofilestop (nil when it is missing or secret).
local function clock()
    local ok, ms = Call(rawget(_G, "debugprofilestop"))
    if ok and not IsSecret(ms) and type(ms) == "number" then
        return ms
    end
end

-- The context of the events, refreshed at most once a second (events can fire many times a second).
local cache = { at = nil }

local function currentContext(force)
    local t = now() or 0
    if force or not cache.at or t - cache.at >= 1 then
        local c = Probe.Context()
        cache.key, cache.code, cache.combat, cache.at = contextKey(c), c.code, c.combat == "yes", t
    end
    return cache.key, cache.code, cache.combat
end

local function invalidateContext()
    cache.at = nil
end

----------------------------------------------------------------------------------------------------------------------
-- P5: which units and mobs can be queried
----------------------------------------------------------------------------------------------------------------------

local MOB_TOKENS = { "target", "focus", "mouseover", "targettarget", "pettarget" }
for i = 1, 5 do
    MOB_TOKENS[#MOB_TOKENS + 1] = "boss" .. i
end
for i = 1, 4 do
    MOB_TOKENS[#MOB_TOKENS + 1] = "party" .. i .. "target"
end
for i = 1, 40 do
    MOB_TOKENS[#MOB_TOKENS + 1] = "raid" .. i .. "target"
end
for i = 1, 40 do
    MOB_TOKENS[#MOB_TOKENS + 1] = "nameplate" .. i
end

-- Token kinds through which somebody targets the mob. A mob reached by none of them is "untargeted" (SPEC-08 P5).
local TARGETING = { target = true, targettarget = true, pettarget = true, partytarget = true, raidtarget = true }

local MAX_MOBS = 16        -- distinct mobs read per sweep
local MAX_FIGHT_MOBS = 64  -- distinct mobs remembered per fight (GUIDs in memory only)
local MAX_FROM_GUID = 16   -- UnitTokenFromGUID lookups per sweep
local CLASSES = { "number", "state", "secret", "nil", "error" }

--- The units whose threat is read: the player, the pet and every other member of the group.
local function readers()
    local list = { { "player", "player" } }
    if exists("pet") then
        list[#list + 1] = { "pet", "pet" }
    end
    for _, unit in ipairs(groupUnits()) do
        list[#list + 1] = { unit, tokenKind(unit) }
    end
    return list
end

--- One reading of `unit` on `mob` (SPEC-08 P5): "number" (scaled percentage readable), "state" (only the status is
--- readable), "secret" (something came back, all of it secret), "nil" or "error".
local function classify(unit, mob)
    local okD, isTanking, status, scaled = Call(rawget(_G, "UnitDetailedThreatSituation"), unit, mob)
    local okS, situation = Call(rawget(_G, "UnitThreatSituation"), unit, mob)
    if not okD and not okS then
        return "error"
    end
    local tankKind, statusKind, scaledKind, situationKind = "nil", "nil", "nil", "nil"
    if okD then
        tankKind = (Describe(isTanking))
        statusKind = (Describe(status))
        scaledKind = (Describe(scaled))
    end
    if okS then
        situationKind = (Describe(situation))
    end
    if scaledKind == "number" then
        return "number"
    end
    if statusKind == "number" or situationKind == "number" then
        return "state"
    end
    if tankKind == "secret" or statusKind == "secret" or scaledKind == "secret" or situationKind == "secret" then
        return "secret"
    end
    if not okD or not okS then
        return "error"
    end
    return "nil"
end

local function newCell()
    return { number = 0, state = 0, secret = 0, ["nil"] = 0, error = 0 }
end

local fight            -- the fight in progress: { mobs = {[id] = record}, count, key, code, sweeps, signature }
local p5Ticks = 0
local plates = {}      -- nameplate tokens shown now (from NAME_PLATE_UNIT_ADDED/REMOVED)

local function newFight()
    return { mobs = {}, count = 0, sweeps = 0 }
end

local scratch = {} -- record of a mob beyond MAX_FIGHT_MOBS: counted in the sweep, not remembered

local function fightMob(m, token)
    local fm = fight.mobs[m.id]
    if fm then
        return fm
    end
    if fight.count >= MAX_FIGHT_MOBS then
        fight.capped = true
        for k in pairs(scratch) do
            scratch[k] = nil
        end
        scratch.kinds, scratch.answeredBy = {}, {}
        return scratch
    end
    fight.count = fight.count + 1
    fm = { text = mobText(token), guid = m.guid, guidKind = m.guidKind, kinds = {}, answeredBy = {} }
    fight.mobs[m.id] = fm
    return fm
end

--- Reads every unit on `token` (a mob token of kind `kind`) and counts the results in `row`. Returns the unit kinds
--- that answered (a number, a state or a secret).
local function readMob(row, token, units)
    local answered = {}
    for _, u in ipairs(units) do
        local class = classify(u[1], token)
        local cell = row[u[2]]
        if not cell then
            cell = newCell()
            row[u[2]] = cell
        end
        cell[class] = cell[class] + 1
        if class ~= "nil" and class ~= "error" then
            answered[u[2]] = true
        end
    end
    return answered
end

--- One sweep of P5: which mobs the tokens reach now, and who answers the threat API on each of them.
local function p5Sweep(trigger)
    local started = clock()
    local c = stamp("P5")
    local key = contextKey(c)
    local st = statsFor("p5", key, c.code, c.combat == "yes")
    st.matrix = st.matrix or {}
    fight = fight or newFight()
    fight.key, fight.code, fight.combat = key, c.code, c.combat == "yes"
    fight.sweeps = fight.sweeps + 1

    -- 1. The mobs the tokens reach now, deduplicated by GUID (compared in memory only).
    local mobs, order, plateCount, capped = {}, {}, 0, 0
    for _, token in ipairs(MOB_TOKENS) do
        if hostile(token) then
            local kind = tokenKind(token)
            if kind == "nameplate" then
                plateCount = plateCount + 1
            end
            local g = guidOf(token)
            local id = g.kind == "readable" and g.guid or (g.kind .. ":" .. token)
            local m = mobs[id]
            if not m and #order >= MAX_MOBS then
                capped = capped + 1
            else
                if not m then
                    m = { id = id, guid = g.guid, guidKind = g.kind, tokens = {}, kinds = {} }
                    mobs[id] = m
                    order[#order + 1] = id
                end
                if not m.tokens[kind] then
                    m.tokens[kind] = token
                    m.kinds[#m.kinds + 1] = kind
                end
            end
        end
    end

    -- 2. Every unit on every mob, through the first token of each kind that reaches it.
    local units = readers()
    local lines = {}
    for _, id in ipairs(order) do
        local m = mobs[id]
        local fm = fightMob(m, m.tokens[m.kinds[1]])
        local answeredNow, untargeted, onlyPlate = {}, true, true
        for _, kind in ipairs(m.kinds) do
            if TARGETING[kind] then
                untargeted = false
            end
            if kind ~= "nameplate" then
                onlyPlate = false
            end
            fm.kinds[kind] = true
            local row = st.matrix[kind]
            if not row then
                row = {}
                st.matrix[kind] = row
            end
            for unitKind in pairs(readMob(row, m.tokens[kind], units)) do
                answeredNow[unitKind] = true
                fm.answeredBy[unitKind] = true
            end
        end
        local any = next(answeredNow) ~= nil
        if untargeted then
            fm.untargeted = true
            fm.untargetedAnswered = fm.untargetedAnswered or any
        end
        if untargeted and onlyPlate then
            fm.plateOnly = true
            fm.plateOnlyAnswered = fm.plateOnlyAnswered or any
        end
        if m.guidKind == "secret" then
            fm.secretGuid = true
        end
        lines[#lines + 1] = string.format("%s via %s%s answered by %s", fm.text or "<mob ?>",
            table.concat(m.kinds, ","), untargeted and " (untargeted)" or "",
            any and table.concat(sortedKeys(answeredNow), ",") or "nobody")
    end

    -- 3. Mobs seen earlier in this fight that no token reaches now: does UnitTokenFromGUID give them one?
    st.fromGuid = st.fromGuid or {}
    local looked = 0
    for id, fm in pairs(fight.mobs) do
        if looked >= MAX_FROM_GUID then
            break
        end
        if fm.guid and not mobs[id] then
            looked = looked + 1
            local ok, token = Call(rawget(_G, "UnitTokenFromGUID"), fm.guid)
            local kind
            if not ok then
                kind = "error"
            elseif IsSecret(token) then
                kind = "secret"
            elseif token == nil then
                kind = "nil"
            else
                kind = tokenKind(token)
            end
            bump(st.fromGuid, kind)
            if kind ~= "error" and kind ~= "secret" and kind ~= "nil" and hostile(token) then
                local row = st.matrix.fromguid
                if not row then
                    row = {}
                    st.matrix.fromguid = row
                end
                for unitKind in pairs(readMob(row, token, units)) do
                    fm.answeredBy[unitKind] = true
                end
                fm.kinds.fromguid = true
            end
        end
    end

    -- 4. Can the target be compared with the other mob tokens (C_Secrets.CanCompareUnitTokens)?
    if exists("target") then
        st.compare = st.compare or {}
        local done = {}
        for _, id in ipairs(order) do
            for kind, token in pairs(mobs[id].tokens) do
                if kind ~= "target" and not done[kind] then
                    done[kind] = true
                    st.compare[kind] = st.compare[kind] or {}
                    bump(st.compare[kind], boolText(Call(API("C_Secrets", "CanCompareUnitTokens"), "target", token)))
                end
            end
        end
    end

    -- 5. Counters and log.
    bump(st, "sweeps")
    st.maxMobs = math.max(st.maxMobs or 0, #order)
    st.maxPlates = math.max(st.maxPlates or 0, plateCount)
    if capped > 0 then
        bump(st, "mobsCapped", capped)
    end
    local finished = clock()
    local ms = (started and finished) and (finished - started) or nil
    if ms then
        st.msMax = math.max(st.msMax or 0, math.floor(ms * 10 + 0.5) / 10)
        bump(st, "msTotal", ms)
    end
    local signature = table.concat(lines, " | ")
    if trigger ~= "tick" or signature ~= fight.signature then
        Probe:Log("P5", string.format("%s t=%.1f [%s] %d mobs, %d plates, %d units, %s ms: %s", trigger, elapsed("P5"),
            key, #order, plateCount, #units, ms and string.format("%.1f", ms) or "?",
            #lines > 0 and signature or "no hostile mob"))
    end
    fight.signature = signature
    return #order, plateCount
end

--- Adds the fight's per-mob findings to the saved counters and logs one summary line.
local function p5FinishFight()
    local f = fight
    fight = nil
    if not f or f.count == 0 or not f.key then
        return
    end
    local st = statsFor("p5", f.key, f.code, f.combat)
    local n = { mobs = 0, untargeted = 0, untargetedAnswered = 0, plateOnly = 0, plateOnlyAnswered = 0,
        groupAnswered = 0, secretGuid = 0, viaGuid = 0 }
    for _, fm in pairs(f.mobs) do
        n.mobs = n.mobs + 1
        if fm.untargeted then
            n.untargeted = n.untargeted + 1
            if fm.untargetedAnswered then
                n.untargetedAnswered = n.untargetedAnswered + 1
            end
        end
        if fm.plateOnly then
            n.plateOnly = n.plateOnly + 1
            if fm.plateOnlyAnswered then
                n.plateOnlyAnswered = n.plateOnlyAnswered + 1
            end
        end
        if fm.answeredBy.party or fm.answeredBy.raid then
            n.groupAnswered = n.groupAnswered + 1
        end
        if fm.secretGuid then
            n.secretGuid = n.secretGuid + 1
        end
        if fm.kinds.fromguid then
            n.viaGuid = n.viaGuid + 1
        end
    end
    bump(st, "fights")
    for k, v in pairs(n) do
        bump(st, k, v)
    end
    Probe:Log("P5", string.format("fight end [%s]: %d mobs%s, %d sweeps; untargeted %d (answered %d), only on a " ..
        "nameplate %d (answered %d), answered by a group member %d, GUID secret %d, reached again via " ..
        "UnitTokenFromGUID %d", f.key, n.mobs, f.capped and " (cap reached)" or "", f.sweeps, n.untargeted,
        n.untargetedAnswered, n.plateOnly, n.plateOnlyAnswered, n.groupAnswered, n.secretGuid, n.viaGuid))
end

local function p5Watch(trigger)
    if trigger == "combat-start" then
        p5FinishFight()
        fight = newFight()
        elapsed("P5", true)
        p5Ticks = 0
        p5Sweep(trigger)
    elseif trigger == "tick" then
        p5Ticks = p5Ticks + 1
        -- In a raid a sweep reads up to 40 units on up to 16 mobs: one every third second.
        if not flag(Call(IsInRaid)) or p5Ticks % 3 == 0 then
            p5Sweep(trigger)
        end
    elseif trigger == "encounter-start" then
        p5Sweep(trigger)
    elseif trigger == "combat-end" then
        p5FinishFight()
    end
end

table.insert(Probe.watchHooks, p5Watch)

local function plateEvent(added, token)
    if not watching() then
        return
    end
    local key, code, combat = currentContext()
    local st = statsFor("p5", key, code, combat)
    st.plateEvents = st.plateEvents or {}
    if IsSecret(token) or type(token) ~= "string" then
        bump(st.plateEvents, "secret")
        return
    end
    bump(st.plateEvents, added and "added" or "removed")
    plates[token] = added or nil
    local shown = 0
    for _ in pairs(plates) do
        shown = shown + 1
    end
    st.maxPlateEvents = math.max(st.maxPlateEvents or 0, shown)
end

local MOB_GROUP = { partytarget = "grouptarget", raidtarget = "grouptarget" }
local UNIT_GROUP = { party = "group", raid = "group" }
local REQUIRED_PAIRS = { "target x player", "target x group", "nameplate x player", "nameplate x group",
    "grouptarget x player", "grouptarget x group" }

local function p5Verdict()
    local s = store("p5")
    local agg, totals, codes = {}, {}, {}
    for _, st in pairs(s.stats or {}) do
        if GROUP_CODES[st.code] and st.combat then
            codes[st.code] = true
            for mobKind, row in pairs(st.matrix or {}) do
                for unitKind, cell in pairs(row) do
                    local pair = (MOB_GROUP[mobKind] or mobKind) .. " x " .. (UNIT_GROUP[unitKind] or unitKind)
                    local a = agg[pair] or { readings = 0, answered = 0, secret = 0 }
                    agg[pair] = a
                    for _, class in ipairs(CLASSES) do
                        a.readings = a.readings + (cell[class] or 0)
                    end
                    a.answered = a.answered + cell.number + cell.state + cell.secret
                    a.secret = a.secret + cell.secret
                end
            end
            for _, k in ipairs({ "fights", "mobs", "untargeted", "untargetedAnswered", "plateOnly",
                "plateOnlyAnswered", "groupAnswered", "secretGuid", "viaGuid" }) do
                bump(totals, k, st[k] or 0)
            end
        end
    end
    if next(agg) == nil then
        return "todo", "no reading yet in a party, dungeon or raid fight: /atwp watch on, then pull 3 or more mobs"
    end
    local parts, secret = {}, 0
    for _, pair in ipairs(sortedKeys(agg)) do
        local a = agg[pair]
        secret = secret + a.secret
        parts[#parts + 1] = string.format("%s %d/%d%s", pair, a.answered, a.readings,
            a.secret > 0 and (" (" .. a.secret .. " secret)") or "")
    end
    local codeList = sortedKeys(codes)
    local tail = string.format(" Answered/readings: %s. Fights %d (%s), mobs %d, untargeted %d (answered %d), only " ..
        "on a nameplate %d (answered %d), answered by a group member %d, GUID secret %d, via UnitTokenFromGUID %d.",
        table.concat(parts, "; "), totals.fights or 0, table.concat(codeList, ","), totals.mobs or 0,
        totals.untargeted or 0, totals.untargetedAnswered or 0, totals.plateOnly or 0, totals.plateOnlyAnswered or 0,
        totals.groupAnswered or 0, totals.secretGuid or 0, totals.viaGuid or 0)
    if secret > 0 then
        -- P5 asks which tokens answer; whether the answers are usable is P3's question.
        tail = string.format(" %d answers were secret (see P3).", secret) .. tail
    end

    local onlyPlayerTarget, otherRead = true, false
    for pair, a in pairs(agg) do
        if pair ~= "target x player" then
            if a.readings > 0 then
                otherRead = true
            end
            if a.answered > 0 then
                onlyPlayerTarget = false
            end
        end
    end
    if onlyPlayerTarget and otherRead then
        return "not supported", "only the player on the target answers." .. tail
    end
    local required = {}
    for _, pair in ipairs(REQUIRED_PAIRS) do
        required[#required + 1] = pair
    end
    if agg["boss x player"] then
        required[#required + 1] = "boss x player"
        required[#required + 1] = "boss x group"
    end
    local missing, failing = {}, {}
    for _, pair in ipairs(required) do
        local a = agg[pair]
        if not a or a.readings == 0 then
            missing[#missing + 1] = pair
        elseif a.answered == 0 then
            failing[#failing + 1] = pair
        end
    end
    if (totals.plateOnly or 0) > 0 and (totals.plateOnlyAnswered or 0) == 0 then
        failing[#failing + 1] = "mobs only on a nameplate"
    end
    if #failing > 0 then
        return "partial", "never answered: " .. table.concat(failing, ", ") .. "." .. tail
    end
    if #missing > 0 or (totals.plateOnly or 0) == 0 then
        local todo = {}
        if #missing > 0 then
            todo[#todo + 1] = "no reading of " .. table.concat(missing, ", ")
        end
        if (totals.plateOnly or 0) == 0 then
            todo[#todo + 1] = "no mob seen only on a nameplate (pull 3+ mobs, one nobody targets, nameplates shown)"
        end
        return "todo", "nothing failed so far; still to play: " .. table.concat(todo, "; ") .. "." .. tail
    end
    return "supported", "every member answers on every mob with a token, including mobs only on a nameplate." .. tail
end

Probe:Register("P5", "Which units and mobs can be queried", function()
    Probe.LearnNames()
    local combat = inCombat()
    if not combat then
        elapsed("P5", true)
    end
    local mobs, plateCount = p5Sweep("run")
    if not combat then
        fight = nil -- a reading out of combat is counted, but it does not open a fight
    end
    out(string.format("P5 now: %d hostile mobs reachable, %d through nameplates", mobs, plateCount))
    return p5Verdict()
end)

----------------------------------------------------------------------------------------------------------------------
-- P6: threat events, payload, rate and delay
----------------------------------------------------------------------------------------------------------------------

local EVENTS = { UNIT_THREAT_LIST_UPDATE = "list", UNIT_THREAT_SITUATION_UPDATE = "situation" }
local registered = {}   -- event -> true / false (the client refused it)
local buckets = {}      -- event -> { sec, n }: events in the current second
local p6 = { sampling = false, delay = nil, fight = nil, logged = 0, targetChanged = false }
local DELAY_KEEP = 200  -- delays kept per context (ms), for the median
local EVENT_LOG_PER_FIGHT = 20

local function newDelay()
    return { samples = 0, notMeasurable = 0, changes = 0, matched = 0, eventFirst = 0, changesWithoutEvent = 0,
        eventsWithoutChange = 0, list = {} }
end

local function newFightCounters()
    return { list = 0, situation = 0, changes = 0, delays = {}, eventFirst = 0, changesWithoutEvent = 0,
        eventsWithoutChange = 0 }
end

local function delayStats(key)
    local _, code, combat = currentContext()
    local st = statsFor("p6", key, code, combat)
    st.delay = st.delay or newDelay()
    return st.delay
end

local function count(dl, field)
    dl[field] = dl[field] + 1
    if p6.fight and p6.fight[field] then
        p6.fight[field] = p6.fight[field] + 1
    end
end

local function recordDelay(dl, seconds)
    local ms = math.floor(seconds * 1000 + 0.5)
    dl.matched = dl.matched + 1
    dl.list[#dl.list + 1] = ms
    while #dl.list > DELAY_KEEP do
        table.remove(dl.list, 1)
    end
    dl.max = math.max(dl.max or ms, ms)
    if p6.fight and #p6.fight.delays < DELAY_KEEP then
        p6.fight.delays[#p6.fight.delays + 1] = ms
    end
end

--- Kinds and readable values of what one call returned, appended to `parts`; true when something was readable.
local function signaturePart(parts, ok, ...)
    if not ok then
        parts[#parts + 1] = "E"
        return false
    end
    local readable = false
    for i = 1, select("#", ...) do
        local kind, value = Describe((select(i, ...)))
        if kind == "secret" then
            parts[#parts + 1] = "S"
        elseif value ~= nil then
            parts[#parts + 1] = tostring(value)
            readable = true
        else
            parts[#parts + 1] = kind:sub(1, 1)
        end
    end
    return readable
end

--- The threat on the target of the player, the pet and up to four group members, as one text (no secret in it).
local function signature()
    local units = { "player" }
    if exists("pet") then
        units[#units + 1] = "pet"
    end
    for i, unit in ipairs(groupUnits()) do
        if i > 4 then
            break
        end
        units[#units + 1] = unit
    end
    local parts, measurable = {}, false
    for _, unit in ipairs(units) do
        parts[#parts + 1] = unit .. ":"
        if signaturePart(parts, Call(rawget(_G, "UnitDetailedThreatSituation"), unit, "target")) then
            measurable = true
        end
    end
    return table.concat(parts, " "), measurable
end

--- One 10 Hz sample: a change of the threat on the target starts a wait for the next threat event.
local function p6Sample()
    if not watching() or not inCombat() then
        Probe.Cancel("P6")
        p6.delay = nil
        return
    end
    local d = p6.delay
    local t = now()
    if not d or not t then
        return
    end
    d.matched = false -- a new window between two samples starts
    local key = currentContext()
    local dl = delayStats(key)
    dl.samples = dl.samples + 1
    if d.pending and t - d.pending > 1 then
        count(dl, "changesWithoutEvent")
        d.pending = nil
    end
    if not hostile("target") then
        d.base, d.mob, d.eventAt = nil, nil, nil
        return
    end
    local g = guidOf("target")
    local mob = g.kind == "readable" and g.guid or nil
    local sig, measurable = signature()
    if not measurable then
        dl.notMeasurable = dl.notMeasurable + 1
    end
    if p6.targetChanged or not d.base or mob ~= d.mob or not measurable then
        -- A new baseline: another target (a target change is not a threat change) or nothing readable.
        p6.targetChanged = false
        d.base, d.mob, d.pending, d.eventAt = measurable and sig or nil, mob, nil, nil
        return
    end
    if sig ~= d.base then
        count(dl, "changes")
        if d.eventAt then
            -- The event came between the previous sample and this one: it was first (negative delay).
            count(dl, "eventFirst")
            recordDelay(dl, d.eventAt - t)
            d.eventAt = nil
        elseif not d.pending then
            d.pending = t
        end
        d.base = sig
    elseif d.eventAt then
        count(dl, "eventsWithoutChange")
        d.eventAt = nil
    end
end

local function startSampling()
    if p6.delay then
        return
    end
    p6.delay = {}
    p6.targetChanged = false
    if not Probe.Every("P6", 0.1, p6Sample, 0) then
        p6.delay = nil
    end
end

local function stopSampling()
    Probe.Cancel("P6")
    p6.delay = nil
end

--- A threat event that may follow a change seen by the sampling: the list of the target, or the situation of one of
--- the units the sampling reads (the player, the pet, the group).
local function relevant(event, unit, kind)
    if kind == "secret" or type(unit) ~= "string" then
        return false
    end
    if event == "UNIT_THREAT_LIST_UPDATE" then
        return unit == "target" or flag(Call(UnitIsUnit, unit, "target")) == true
    end
    return kind == "player" or kind == "pet" or kind == "party" or kind == "raid"
end

local function onThreatEvent(event, unit)
    if not watching() then
        return
    end
    local t = now()
    if not t then
        return
    end
    local short = EVENTS[event]
    local key, code, combat = currentContext()
    local st = statsFor("p6", key, code, combat)
    st.events = st.events or {}
    local e = st.events[short]
    if not e then
        e = { count = 0, maxPerSecond = 0, kinds = {} }
        st.events[short] = e
    end
    e.count = e.count + 1
    local kind = tokenKind(unit)
    bump(e.kinds, kind)
    local sec = math.floor(t)
    local b = buckets[event]
    if not b or b.sec ~= sec then
        b = { sec = sec, n = 0 }
        buckets[event] = b
    end
    b.n = b.n + 1
    e.maxPerSecond = math.max(e.maxPerSecond, b.n)
    if p6.fight then
        p6.fight[short] = p6.fight[short] + 1
        if p6.logged < EVENT_LOG_PER_FIGHT then
            p6.logged = p6.logged + 1
            Probe:Log("P6", string.format("%s t=%.2f [%s] payload %s", short, elapsed("P6"), key, kind))
        end
    end
    local d = p6.delay
    if d and relevant(event, unit, kind) then
        if d.pending then
            recordDelay(delayStats(key), t - d.pending)
            d.pending, d.eventAt, d.matched = nil, nil, true
        elseif not d.matched then
            -- The other events of the same window (one change often fires both events) belong to the same change.
            d.eventAt = d.eventAt or t
        end
    end
end

for event in pairs(EVENTS) do
    local name = event
    registered[name] = Probe:On(name, function(unit)
        onThreatEvent(name, unit)
    end)
end

local function delayText(list)
    if #list == 0 then
        return "no delay measured"
    end
    local copy, high = {}, nil
    for i, v in ipairs(list) do
        copy[i] = v
        high = math.max(high or v, v)
    end
    return string.format("delay median %s ms, max %d ms (%d)", tostring(median(copy)), high, #list)
end

local function p6FinishFight()
    local f = p6.fight
    p6.fight = nil
    stopSampling()
    if not f then
        return
    end
    local t = now()
    Probe:Log("P6", string.format("fight end [%s] %.0f s: list %d, situation %d events; %d changes on the target, " ..
        "%s; event first %d, changes without event within 1 s %d, events without change %d", tostring(f.key),
        (t and f.started) and (t - f.started) or 0, f.list, f.situation, f.changes, delayText(f.delays), f.eventFirst,
        f.changesWithoutEvent, f.eventsWithoutChange))
end

local function p6Watch(trigger)
    if trigger == "combat-start" then
        p6FinishFight()
        invalidateContext()
        local key, code, combat = currentContext(true)
        bump(statsFor("p6", key, code, combat), "fights")
        p6.fight = newFightCounters()
        p6.fight.key, p6.fight.started = key, now()
        p6.logged = 0
        elapsed("P6", true)
        startSampling()
    elseif trigger == "tick" then
        local key, code, combat = currentContext()
        bump(statsFor("p6", key, code, combat), "combatSeconds")
        if not p6.delay then
            startSampling() -- after a /reload in combat
        end
    elseif trigger == "combat-end" then
        invalidateContext()
        p6FinishFight()
    end
end

table.insert(Probe.watchHooks, p6Watch)

local MOB_PAYLOADS = { target = true, focus = true, mouseover = true, targettarget = true, pettarget = true,
    boss = true, nameplate = true, partytarget = true, raidtarget = true, softenemy = true, npc = true }

local function p6Verdict()
    local s = store("p6")
    s.registered = {}
    for event, ok in pairs(registered) do
        s.registered[EVENTS[event]] = ok and "yes" or "refused"
    end
    if not registered.UNIT_THREAT_LIST_UPDATE and not registered.UNIT_THREAT_SITUATION_UPDATE then
        return "not supported", "the client refused both UNIT_THREAT_LIST_UPDATE and UNIT_THREAT_SITUATION_UPDATE"
    end
    local fights, seconds, perCode = 0, 0, {}
    local ev = { list = { count = 0, max = 0, kinds = {} }, situation = { count = 0, max = 0, kinds = {} } }
    local dl, delays = newDelay(), {}
    for _, st in pairs(s.stats or {}) do
        if GROUP_CODES[st.code] then
            fights = fights + (st.fights or 0)
            bump(perCode, st.code, st.fights or 0)
            if st.combat then
                seconds = seconds + (st.combatSeconds or 0)
                for short, e in pairs(st.events or {}) do
                    local a = ev[short]
                    if a then
                        a.count = a.count + e.count
                        a.max = math.max(a.max, e.maxPerSecond or 0)
                        for kind, n in pairs(e.kinds) do
                            bump(a.kinds, kind, n)
                        end
                    end
                end
                local d = st.delay
                if d then
                    for _, k in ipairs({ "samples", "notMeasurable", "changes", "matched", "eventFirst",
                        "changesWithoutEvent", "eventsWithoutChange" }) do
                        dl[k] = dl[k] + (d[k] or 0)
                    end
                    for _, v in ipairs(d.list or {}) do
                        delays[#delays + 1] = v
                    end
                end
            end
        end
    end
    if fights == 0 then
        return "todo", "no fight yet in a party or dungeon with /atwp watch on (three per context)"
    end
    local total = ev.list.count + ev.situation.count
    local function eventText(short)
        local a = ev[short]
        return string.format("%s %d (%s/s on average, max %d/s; payload %s)", short, a.count,
            seconds > 0 and string.format("%.1f", a.count / seconds) or "?", a.max, countsText(a.kinds))
    end
    local med
    if #delays > 0 then
        local copy = {}
        for i, v in ipairs(delays) do
            copy[i] = v
        end
        med = median(copy)
    end
    local tail = string.format(" Fights %s, %d s in combat; %s; %s; %s; %d changes on the target, event first %d, " ..
        "changes without event within 1 s %d, events without change %d; samples not measurable %d/%d.",
        countsText(perCode), seconds, eventText("list"), eventText("situation"), delayText(delays), dl.changes,
        dl.eventFirst, dl.changesWithoutEvent, dl.eventsWithoutChange, dl.notMeasurable, dl.samples)
    local enough = (perCode.party or 0) >= 3 or (perCode.dungeon or 0) >= 3
    if total == 0 then
        if enough then
            return "not supported", "no threat event arrived in combat." .. tail
        end
        return "todo", "no threat event yet." .. tail
    end
    local secret = (ev.list.kinds.secret or 0) + (ev.situation.kinds.secret or 0)
    if secret == total then
        return "not supported", "the payload of every threat event is secret." .. tail
    end
    local mobPayload, onlyPlayer = false, true
    for _, a in pairs(ev) do
        for kind in pairs(a.kinds) do
            if MOB_PAYLOADS[kind] then
                mobPayload = true
            end
            if kind ~= "player" then
                onlyPlayer = false
            end
        end
    end
    local issues = {}
    if onlyPlayer then
        issues[#issues + 1] = "payload only player"
    elseif not mobPayload then
        issues[#issues + 1] = "no mob token in the payload"
    end
    if ev.list.count == 0 or ev.situation.count == 0 then
        issues[#issues + 1] = (ev.list.count == 0 and "UNIT_THREAT_LIST_UPDATE" or "UNIT_THREAT_SITUATION_UPDATE") ..
            " never arrived"
    end
    if med and med > 200 then
        issues[#issues + 1] = "median delay " .. tostring(med) .. " ms (> 200 ms)"
    end
    if dl.changes > 0 and dl.changesWithoutEvent > dl.changes * 0.1 then
        issues[#issues + 1] = dl.changesWithoutEvent .. " of " .. dl.changes .. " changes without an event within 1 s"
    end
    if #issues > 0 then
        return "partial", table.concat(issues, "; ") .. "." .. tail
    end
    if not med then
        return "todo", "events arrive; the delay is not measurable yet (no readable change on the target)." .. tail
    end
    if not enough then
        return "todo", "no problem so far; fewer than three fights in a party or a dungeon." .. tail
    end
    return "supported", "both events arrive for mobs and units, median delay within a 200 ms tick." .. tail
end

Probe:Register("P6", "Threat events: payload, rate, delay", function()
    if not watching() then
        out("P6 counts only while /atwp watch is on")
    end
    return p6Verdict()
end)

----------------------------------------------------------------------------------------------------------------------
-- P9: GUIDs and roles
----------------------------------------------------------------------------------------------------------------------

local P9_UNITS = { "player", "pet", "target", "focus", "targettarget" }
for i = 1, 4 do
    P9_UNITS[#P9_UNITS + 1] = "party" .. i
end
for i = 1, 40 do
    P9_UNITS[#P9_UNITS + 1] = "raid" .. i
end
for i = 1, 5 do
    P9_UNITS[#P9_UNITS + 1] = "boss" .. i
end
for i = 1, 40 do
    P9_UNITS[#P9_UNITS + 1] = "nameplate" .. i
end

local ROLES = { TANK = true, HEALER = true, DAMAGER = true, NONE = true }
local MAX_CREATURES = 50
local MAX_UNSTABLE = 20
local MAX_MOB_STATES = 500

-- Stability (memory only): the GUID each token pointed to when it was last read. A token keeps its mob until it
-- changes (PLAYER_TARGET_CHANGED, PLAYER_FOCUS_CHANGED, NAME_PLATE_UNIT_ADDED/REMOVED, INSTANCE_ENCOUNTER_ENGAGE_UNIT).
local tracked = {}       -- token -> { guid, text, placeholder }
local mobStates = {}     -- "<mob n>" -> "stable" / "unstable"
local mobStateCount = 0
local TRACKED_TOKENS = { "target", "focus" }
for i = 1, 5 do
    TRACKED_TOKENS[#TRACKED_TOKENS + 1] = "boss" .. i
end
for i = 1, 40 do
    TRACKED_TOKENS[#TRACKED_TOKENS + 1] = "nameplate" .. i
end

local function newGuidCell()
    return { readable = 0, secret = 0, ["nil"] = 0, error = 0, pred = {}, right = 0, wrong = 0 }
end

local function p9Stats()
    local c = stamp("P9")
    return statsFor("p9", contextKey(c), c.code, c.combat == "yes"), contextKey(c)
end

local function setMobState(placeholder, state)
    if not placeholder or placeholder == "<mob ?>" then
        return
    end
    if not mobStates[placeholder] then
        if mobStateCount >= MAX_MOB_STATES then
            return
        end
        mobStateCount = mobStateCount + 1
    end
    if state == "unstable" or not mobStates[placeholder] then
        mobStates[placeholder] = state
    end
end

local function stabilityOf(st)
    st.stability = st.stability or { checks = 0, changed = 0, secret = 0, unstable = {} }
    return st.stability
end

--- Reads the GUID behind a tracked token and compares it, in memory, with the one read last time.
local function track(st, token)
    if not exists(token) then
        tracked[token] = nil
        return
    end
    local g = guidOf(token)
    local stab = stabilityOf(st)
    if g.kind == "secret" then
        stab.secret = stab.secret + 1
        return
    end
    if g.kind ~= "readable" or g.guidType == "Player" then
        tracked[token] = nil
        return
    end
    local prev = tracked[token]
    if not prev then
        local placeholder = (Probe.Mob(token))
        tracked[token] = { guid = g.guid, text = mobText(token), placeholder = placeholder }
        setMobState(placeholder, "stable")
        return
    end
    stab.checks = stab.checks + 1
    if prev.guid == g.guid then
        return
    end
    stab.changed = stab.changed + 1
    local text = mobText(token)
    if #stab.unstable < MAX_UNSTABLE then
        stab.unstable[#stab.unstable + 1] = prev.placeholder .. " via " .. tokenKind(token)
    end
    setMobState(prev.placeholder, "unstable")
    Probe:Log("P9", string.format("GUID changed on %s without a token change: was %s, now %s", token, prev.text, text))
    local placeholder = (Probe.Mob(token))
    tracked[token] = { guid = g.guid, text = text, placeholder = placeholder }
    setMobState(placeholder, "stable")
end

local function trackAll(st)
    for _, token in ipairs(TRACKED_TOKENS) do
        track(st, token)
    end
end

--- UnitTokenFromGUID(guid) then UnitGUID(token): does the round trip come back to the same GUID?
local function roundTrip(st, guid)
    st.roundTrip = st.roundTrip or {}
    local ok, token = Call(rawget(_G, "UnitTokenFromGUID"), guid)
    if not ok then
        bump(st.roundTrip, "error")
    elseif IsSecret(token) then
        bump(st.roundTrip, "secret")
    elseif type(token) ~= "string" then
        bump(st.roundTrip, "no token")
    else
        local back = guidOf(token)
        if back.kind == "readable" then
            bump(st.roundTrip, back.guid == guid and "same" or "different")
        else
            bump(st.roundTrip, "back " .. back.kind)
        end
    end
end

--- At the end of a fight: the mobs still tracked go through the round trip (SPEC-08 P9, "alla fine").
local function finishTracking()
    local st = p9Stats()
    trackAll(st)
    for _, entry in pairs(tracked) do
        roundTrip(st, entry.guid)
    end
end

--- The census of `/atwp run P9`: GUID of every unit, identity prediction, types, creature ids, round trips, roles
--- and unit comparisons, counted for this context.
local function p9Census(trigger)
    local st, key = p9Stats()
    bump(st, "runs")
    st.guids = st.guids or {}
    st.byWho = st.byWho or {}
    st.types = st.types or {}
    st.creatures = st.creatures or {}
    local seen = 0
    for _, unit in ipairs(P9_UNITS) do
        if exists(unit) then
            seen = seen + 1
            local kind = tokenKind(unit)
            local pred = boolText(Call(API("C_Secrets", "ShouldUnitIdentityBeSecret"), unit))
            local g = guidOf(unit)
            local cell = st.guids[kind] or newGuidCell()
            st.guids[kind] = cell
            cell[g.kind] = cell[g.kind] + 1
            bump(cell.pred, pred)
            if (pred == "yes" or pred == "no") and (g.kind == "readable" or g.kind == "secret") then
                if (pred == "yes") == (g.kind == "secret") then
                    cell.right = cell.right + 1
                else
                    cell.wrong = cell.wrong + 1
                end
            end
            local isPlayer = flag(Call(UnitIsPlayer, unit))
            local who = isPlayer == true and "players" or (isPlayer == false and "mobs" or "unknown")
            st.byWho[who] = st.byWho[who] or newGuidCell()
            st.byWho[who][g.kind] = st.byWho[who][g.kind] + 1
            if g.kind == "readable" then
                bump(st.types, g.guidType)
                if g.creatureId and not st.creatures[g.creatureId] then
                    local n = 0
                    for _ in pairs(st.creatures) do
                        n = n + 1
                    end
                    if n < MAX_CREATURES then
                        st.creatures[g.creatureId] = true
                    end
                end
                roundTrip(st, g.guid)
            end
        end
    end
    -- Roles of the player and of every member.
    st.roles = st.roles or {}
    local members = groupUnits()
    table.insert(members, 1, "player")
    for _, unit in ipairs(members) do
        local ok, role = Call(UnitGroupRolesAssigned, unit)
        if not ok then
            bump(st.roles, "error")
        elseif IsSecret(role) then
            bump(st.roles, "secret")
        elseif type(role) == "string" and ROLES[role] then
            bump(st.roles, role)
        else
            bump(st.roles, "other")
        end
    end
    -- Comparisons: is the target also the target of each member?
    st.compare = st.compare or { pred = {}, result = {} }
    if exists("target") then
        for _, unit in ipairs(groupUnits()) do
            local other = unit .. "target"
            if exists(other) then
                bump(st.compare.pred, boolText(Call(API("C_Secrets", "ShouldUnitComparisonBeSecret"), "target", other)))
                local ok, same = Call(UnitIsUnit, "target", other)
                local kind = not ok and "error" or (IsSecret(same) and "secret" or type(same))
                bump(st.compare.result, kind)
            end
        end
    end
    trackAll(st)
    Probe:Log("P9", string.format("%s [%s] %d units; GUID %s; types %s; roles %s; round trip %s; comparisons %s",
        trigger, key, seen, (function()
            local parts = {}
            for _, k in ipairs(sortedKeys(st.guids)) do
                local cell = st.guids[k]
                parts[#parts + 1] = string.format("%s %d/%d/%d/%d", k, cell.readable, cell.secret, cell["nil"],
                    cell.error)
            end
            return table.concat(parts, " ") .. " (readable/secret/nil/error, totals of this context)"
        end)(), countsText(st.types), countsText(st.roles), countsText(st.roundTrip), countsText(st.compare.result)))
    return seen
end

local function onTokenChanged(token)
    if IsSecret(token) or type(token) ~= "string" then
        return
    end
    tracked[token] = nil
end

Probe:On("PLAYER_TARGET_CHANGED", function()
    tracked.target = nil
    p6.targetChanged = true
end)
Probe:On("PLAYER_FOCUS_CHANGED", function()
    tracked.focus = nil
end)
Probe:On("NAME_PLATE_UNIT_ADDED", function(token)
    onTokenChanged(token)
    plateEvent(true, token)
end)
Probe:On("NAME_PLATE_UNIT_REMOVED", function(token)
    onTokenChanged(token)
    plateEvent(false, token)
end)
Probe:On("INSTANCE_ENCOUNTER_ENGAGE_UNIT", function()
    for i = 1, 5 do
        tracked["boss" .. i] = nil
    end
end)
Probe:On("PLAYER_ENTERING_WORLD", function()
    tracked = {}
    plates = {}
end)

local function p9Watch(trigger)
    if trigger == "combat-start" or trigger == "tick" then
        trackAll((p9Stats()))
    elseif trigger == "encounter-start" then
        p9Census(trigger) -- boss tokens exist only during the encounter
    elseif trigger == "combat-end" then
        finishTracking()
    end
end

table.insert(Probe.watchHooks, p9Watch)

local function p9Verdict()
    local s = store("p9")
    local codes, who, roles, rt, stab = {}, {}, {}, {}, { checks = 0, changed = 0, secret = 0, unstable = {} }
    for _, st in pairs(s.stats or {}) do
        if INSTANCE_CODES[st.code] then
            if (st.runs or 0) > 0 then
                codes[st.code] = true
            end
            for w, cell in pairs(st.byWho or {}) do
                who[w] = who[w] or newGuidCell()
                for _, k in ipairs({ "readable", "secret", "nil", "error" }) do
                    who[w][k] = who[w][k] + cell[k]
                end
            end
            for role, n in pairs(st.roles or {}) do
                bump(roles, role, n)
            end
            for k, n in pairs(st.roundTrip or {}) do
                bump(rt, k, n)
            end
        end
        local sst = st.stability
        if sst then
            stab.checks = stab.checks + sst.checks
            stab.changed = stab.changed + sst.changed
            stab.secret = stab.secret + sst.secret
            for _, text in ipairs(sst.unstable) do
                if #stab.unstable < MAX_UNSTABLE then
                    stab.unstable[#stab.unstable + 1] = text
                end
            end
        end
    end
    local stable, unstable = 0, 0
    for _, state in pairs(mobStates) do
        if state == "stable" then
            stable = stable + 1
        else
            unstable = unstable + 1
        end
    end
    s.mobs = { stable = stable, unstable = unstable }
    local function whoText(w)
        local cell = who[w]
        if not cell then
            return w .. " -"
        end
        return string.format("%s readable %d, secret %d, nil %d, error %d", w, cell.readable, cell.secret, cell["nil"],
            cell.error)
    end
    local tail = string.format(" In instances: GUID %s; %s; roles %s; round trip %s. Stability: %d checks, %d " ..
        "changes, %d secret; mobs this session stable %d, unstable %d%s. Runs in: %s.", whoText("mobs"),
        whoText("players"), countsText(roles), countsText(rt), stab.checks, stab.changed, stab.secret, stable,
        unstable, #stab.unstable > 0 and (" (" .. table.concat(stab.unstable, ", ") .. ")") or "",
        next(codes) and table.concat(sortedKeys(codes), ",") or "none")
    if not next(codes) then
        return "todo", "no run in a dungeon or raid yet: /atwp run P9 when entering, after a pull and after a boss." ..
            tail
    end
    local mobs, players = who.mobs or newGuidCell(), who.players or newGuidCell()
    if mobs.readable == 0 and mobs.secret > 0 then
        return "not supported", "mob GUIDs are secret in instances." .. tail
    end
    if stab.changed > 0 then
        return "not supported", "a mob GUID changed while its token did not." .. tail
    end
    local issues = {}
    if players.secret > 0 then
        issues[#issues + 1] = "player GUIDs secret"
    end
    if mobs.secret > 0 then
        issues[#issues + 1] = "some mob GUIDs secret"
    end
    if (roles.secret or 0) > 0 then
        issues[#issues + 1] = "roles secret"
    end
    if (roles.TANK or 0) + (roles.HEALER or 0) + (roles.DAMAGER or 0) == 0 then
        issues[#issues + 1] = "roles always NONE (a hand-made group?)"
    end
    if (rt.different or 0) > 0 then
        issues[#issues + 1] = "UnitTokenFromGUID round trip came back to another GUID"
    end
    if #issues > 0 then
        return "partial", table.concat(issues, "; ") .. "." .. tail
    end
    if stab.checks == 0 then
        return "todo", "GUIDs and roles readable; stability not checked yet (fight with /atwp watch on)." .. tail
    end
    if not codes.dungeon then
        return "todo", "no problem so far; still to run in a dungeon." .. tail
    end
    return "supported", "GUIDs readable and stable, roles readable." .. tail
end

Probe:Register("P9", "GUIDs and roles in instances", function()
    Probe.LearnNames()
    local seen = p9Census("run")
    out("P9 read " .. seen .. " units")
    return p9Verdict()
end)

----------------------------------------------------------------------------------------------------------------------
-- Export and reset
----------------------------------------------------------------------------------------------------------------------

table.insert(Probe.exportHooks, function()
    local lines = { "-- P5 per context: mob token kind x unit kind (number/state/secret/nil/error)" }
    local p5 = store("p5")
    for _, key in ipairs(sortedKeys(p5.stats)) do
        local st = p5.stats[key]
        for _, mobKind in ipairs(sortedKeys(st.matrix)) do
            for _, unitKind in ipairs(sortedKeys(st.matrix[mobKind])) do
                local cell = st.matrix[mobKind][unitKind]
                lines[#lines + 1] = string.format("%s %s x %s: %d/%d/%d/%d/%d", key, mobKind, unitKind, cell.number,
                    cell.state, cell.secret, cell["nil"], cell.error)
            end
        end
        lines[#lines + 1] = string.format("%s: %d sweeps, %d fights, max %d mobs and %d plates per sweep, mobs %d, " ..
            "untargeted %d (answered %d), only on a nameplate %d (answered %d), answered by a group member %d, GUID " ..
            "secret %d, via UnitTokenFromGUID %d, capped %d; sweep max %s ms, total %s ms", key, st.sweeps or 0,
            st.fights or 0, st.maxMobs or 0, st.maxPlates or 0, st.mobs or 0, st.untargeted or 0,
            st.untargetedAnswered or 0, st.plateOnly or 0, st.plateOnlyAnswered or 0, st.groupAnswered or 0,
            st.secretGuid or 0, st.viaGuid or 0, st.mobsCapped or 0, tostring(st.msMax or "?"),
            st.msTotal and string.format("%.0f", st.msTotal) or "?")
        lines[#lines + 1] = string.format("%s: UnitTokenFromGUID %s; CanCompareUnitTokens(target, x) %s; nameplate " ..
            "events %s, max shown %d", key, countsText(st.fromGuid), (function()
                local parts = {}
                for _, kind in ipairs(sortedKeys(st.compare)) do
                    parts[#parts + 1] = kind .. " [" .. countsText(st.compare[kind]) .. "]"
                end
                return #parts > 0 and table.concat(parts, " ") or "-"
            end)(), countsText(st.plateEvents), st.maxPlateEvents or 0)
    end
    lines[#lines + 1] = "-- P6 per context (fights, seconds in combat, events, delay)"
    local p6s = store("p6")
    for _, key in ipairs(sortedKeys(p6s.stats)) do
        local st = p6s.stats[key]
        local parts = {}
        for _, short in ipairs({ "list", "situation" }) do
            local e = st.events and st.events[short]
            if e then
                parts[#parts + 1] = string.format("%s %d (max %d/s; payload %s)", short, e.count, e.maxPerSecond,
                    countsText(e.kinds))
            end
        end
        local d = st.delay
        lines[#lines + 1] = string.format("%s: %d fights, %d s in combat; %s; %s", key, st.fights or 0,
            st.combatSeconds or 0, #parts > 0 and table.concat(parts, "; ") or "no event", d and string.format(
                "samples %d (not measurable %d), changes %d, %s, event first %d, changes without event %d, events " ..
                "without change %d", d.samples, d.notMeasurable, d.changes, delayText(d.list), d.eventFirst,
                d.changesWithoutEvent, d.eventsWithoutChange) or "no sampling")
    end
    lines[#lines + 1] = "-- P9 per context (GUID readable/secret/nil/error per token kind, identity predictions)"
    local p9 = store("p9")
    for _, key in ipairs(sortedKeys(p9.stats)) do
        local st = p9.stats[key]
        for _, kind in ipairs(sortedKeys(st.guids)) do
            local cell = st.guids[kind]
            lines[#lines + 1] = string.format("%s %s: %d/%d/%d/%d, prediction %s, right %d, wrong %d", key, kind,
                cell.readable, cell.secret, cell["nil"], cell.error, countsText(cell.pred), cell.right, cell.wrong)
        end
        local creatures = {}
        for id in pairs(st.creatures or {}) do
            creatures[#creatures + 1] = id
        end
        table.sort(creatures)
        local stab = st.stability
        lines[#lines + 1] = string.format("%s: %d runs; types %s; creature ids %s; roles %s; round trip %s; " ..
            "comparisons %s (prediction %s); stability %s", key, st.runs or 0, countsText(st.types),
            #creatures > 0 and table.concat(creatures, ",") or "-", countsText(st.roles), countsText(st.roundTrip),
            countsText(st.compare and st.compare.result), countsText(st.compare and st.compare.pred),
            stab and string.format("%d checks, %d changes, %d secret%s", stab.checks, stab.changed, stab.secret,
                #stab.unstable > 0 and (" (" .. table.concat(stab.unstable, ", ") .. ")") or "") or "-")
    end
    return lines
end)

table.insert(Probe.resetHooks, function()
    local d = Probe.DB()
    d.p5, d.p6, d.p9 = nil, nil, nil
    fight, p5Ticks, plates = nil, 0, {}
    stopSampling()
    p6.fight, p6.logged, p6.targetChanged = nil, 0, false
    buckets = {}
    tracked, mobStates, mobStateCount = {}, {}, 0
    invalidateContext()
end)
