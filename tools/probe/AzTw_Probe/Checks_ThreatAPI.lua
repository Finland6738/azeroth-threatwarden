-- AzTw Probe, checks P1-P4 (step M0.3): client and threat API. Development only, never distributed.
-- Spec: docs/specs/SPEC-08-quality-probe-release.md, section 1 (rules PRB-01 to PRB-06, P1, P2, P3 with P3b, P4).
-- Every API used here was checked against the Forever dump (build 70170) on 2026-11-25; the ones the dump does not list
-- as globals (WOW_PROJECT_ID, the Enum tables, CombatLogGetCurrentEventInfo) are looked up at run time (PRB-05).
--
-- Also adds:
--   /atwp ctx [label|clear]  labels the current context (the stamp of SPEC-08 1.2 carries it);
--   /atwp watch [on|off]     automatic readings in combat: at combat start, every second, at encounter start, at
--                            combat end and 2 s later. P3 reads through it; later checks add functions to
--                            Probe.watchHooks (called with the trigger name).
--   Probe.Every / Probe.After / Probe.Cancel, a small timer on one OnUpdate frame (no C_Timer needed).
--
-- Secret values (PRB-02): a returned value is only ever passed to Probe.Describe (issecretvalue first), to
-- canaccessvalue, or, for P3b, to StatusBar:SetValue and FontString:SetText of a hidden frame. It is never compared,
-- formatted, concatenated, stored or printed. Mobs are "<mob n>" with GUID type and creature id; no names (PRB-03).

local _, Probe = ...

local IsSecret, Describe, Call, API = Probe.IsSecret, Probe.Describe, Probe.Call, Probe.API
local out = Probe.Print

----------------------------------------------------------------------------------------------------------------------
-- Small helpers
----------------------------------------------------------------------------------------------------------------------

local function errText(err)
    if IsSecret(err) then
        return "secret"
    end
    return Probe.Scrub(tostring(err))
end

--- GetTime() as a plain number, or nil.
local function now()
    local ok, t = Call(GetTime)
    if ok and not IsSecret(t) and type(t) == "number" then
        return t
    end
end

--- A boolean API answer: true or false, nil when the call failed or the answer is secret.
local function flag(ok, v)
    if not ok or IsSecret(v) then
        return nil
    end
    return v and true or false
end

--- A prediction or another boolean answer as text: yes, no, secret, nil, missing or error.
local function boolText(ok, v)
    if not ok then
        return v == "API missing" and "missing" or "error"
    end
    if IsSecret(v) then
        return "secret"
    end
    if v == nil then
        return "nil"
    end
    if type(v) == "boolean" then
        return v and "yes" or "no"
    end
    return type(v)
end

--- A value for a log line: "secret", "nil", the number rounded to 0.1, a boolean, or the type of anything else.
local function shown(v)
    local kind, value = Describe(v)
    if kind == "secret" or kind == "nil" then
        return kind
    end
    if value ~= nil then
        return tostring(value)
    end
    return kind
end

--- A text value (build strings, locale): "secret", "nil" or the scrubbed text.
local function shownText(v)
    if IsSecret(v) then
        return "secret"
    end
    if v == nil then
        return "nil"
    end
    return Probe.Scrub(tostring(v))
end

local function store(name)
    local d = Probe.DB()
    if type(d[name]) ~= "table" then
        d[name] = {}
    end
    return d[name]
end

local starts = {}

--- Seconds since the start of check `id` (SPEC-08 1.3, field t); `restart` starts a new count.
local function elapsed(id, restart)
    local t = now() or 0
    if restart or not starts[id] then
        starts[id] = t
    end
    return t - starts[id]
end

local lastStamp = {}

--- The context of this reading. The full stamp goes into the log of `logName` whenever it changes, so every reading
--- line below it carries that stamp (SPEC-08 1.2).
local function stamp(logName)
    local c = Probe.Context()
    local text = Probe.ContextText(c)
    if lastStamp[logName] ~= text then
        lastStamp[logName] = text
        Probe:Log(logName, "stamp: " .. text)
    end
    return c
end

--- Short context key for the per-context counters: code, combat, encounter and the owner's label.
local function contextKey(c)
    local key = tostring(c.code)
    if c.code ~= "solo" and c.code ~= "solo-combat" then
        key = key .. (c.combat == "yes" and ":combat" or ":idle")
    end
    if c.encounter == "yes" then
        key = key .. "+encounter"
    end
    if c.label then
        key = key .. "[" .. tostring(c.label) .. "]"
    end
    return key
end

local function inCombat()
    return flag(Call(UnitAffectingCombat, "player")) == true
end

local function exists(unit)
    return flag(Call(UnitExists, unit)) == true
end

--- Exists and can be attacked by the player.
local function hostile(unit)
    return exists(unit) and flag(Call(UnitCanAttack, "player", unit)) == true
end

--- The other members of the group, as unit tokens (party1-4 or raid1-40, without the player).
local function groupUnits()
    local units = {}
    local prefix, max = "party", 4
    if flag(Call(IsInRaid)) then
        prefix, max = "raid", 40
    end
    for i = 1, max do
        local unit = prefix .. i
        if exists(unit) and flag(Call(UnitIsUnit, unit, "player")) ~= true then
            units[#units + 1] = unit
        end
    end
    return units
end

--- "<mob n> <GUID type> <creature id> <classification>" of a unit; never its name.
local function mobText(unit)
    local placeholder, guidType, creatureId = Probe.Mob(unit)
    local ok, class = Call(UnitClassification, unit)
    local classText = (ok and not IsSecret(class) and type(class) == "string") and class or boolText(ok, class)
    return string.format("%s %s %s %s", placeholder, tostring(guidType or "?"), tostring(creatureId or "?"), classText)
end

----------------------------------------------------------------------------------------------------------------------
-- Timers: one hidden-when-idle OnUpdate frame
----------------------------------------------------------------------------------------------------------------------

local timers, timerFrame = {}, nil

local function onUpdate()
    local t = now()
    if not t then
        return
    end
    local due = {}
    for name, timer in pairs(timers) do
        if t >= timer.at then
            due[#due + 1] = name
        end
    end
    table.sort(due)
    for _, name in ipairs(due) do
        local timer = timers[name]
        if timer then
            if timer.every then
                timer.at = t + timer.every
            else
                timers[name] = nil
            end
            local ok, err = pcall(timer.fn)
            if not ok then
                Probe:Log("errors", "timer " .. name .. ": " .. errText(err))
            end
        end
    end
    if next(timers) == nil and timerFrame then
        timerFrame:Hide()
    end
end

local function schedule(name, delay, every, fn)
    if not timerFrame then
        local ok, f = pcall(CreateFrame, "Frame")
        if not ok or not f or not pcall(f.SetScript, f, "OnUpdate", onUpdate) then
            return false
        end
        timerFrame = f
    end
    local t = now()
    if not t then
        return false
    end
    timers[name] = { at = t + delay, every = every, fn = fn }
    timerFrame:Show()
    return true
end

--- Calls fn every `interval` seconds (the first time after `firstDelay`, default `interval`) until Probe.Cancel(name).
function Probe.Every(name, interval, fn, firstDelay)
    return schedule(name, firstDelay or interval, interval, fn)
end

--- Calls fn once after `delay` seconds.
function Probe.After(name, delay, fn)
    return schedule(name, delay, nil, fn)
end

function Probe.Cancel(name)
    timers[name] = nil
end

----------------------------------------------------------------------------------------------------------------------
-- Threat readings (SPEC-08 1.3)
----------------------------------------------------------------------------------------------------------------------

-- The four functions of P2 (plus UnitThreatSituation with one argument). role: "state" or "value" per returned value;
-- numeric: the dump types the value as a number (only those are passed to the P3b display test).
local THREAT = {
    { key = "UDTS", name = "UnitDetailedThreatSituation", expect = 5,
      role = { "state", "state", "value", "value", "value" }, numeric = { false, true, true, true, true } },
    { key = "UTS", name = "UnitThreatSituation", expect = 1, role = { "state" }, numeric = { true } },
    { key = "POL", name = "UnitThreatPercentageOfLead", expect = 1, role = { "value" }, numeric = { true } },
    { key = "ULS", name = "UnitThreatLeadSituation", expect = 1, role = { "state" }, numeric = { true } },
}
local SINGLE = { key = "UTS1", name = "UnitThreatSituation", expect = 1, role = { "state" }, numeric = { true },
    single = true }
local BY_KEY = { UTS1 = SINGLE }
for _, spec in ipairs(THREAT) do
    BY_KEY[spec.key] = spec
end

local currentCode = "unknown" -- context code of the reading in progress, for P3b
local displayFrame

--- P3b (SPEC-08 P3): can a secret value be SHOWN without being read? The value is passed, inside pcall, to
--- StatusBar:SetValue and FontString:SetText of a hidden frame of the probe; only ok or the error is recorded, once per
--- context code. The bar and the text are cleared right after, so no secret stays anywhere.
local function displayTest(v)
    local results = store("p3")
    results.p3b = results.p3b or {}
    if results.p3b[currentCode] then
        return
    end
    local entry = {}
    results.p3b[currentCode] = entry
    if not displayFrame then
        local ok, f = pcall(CreateFrame, "Frame", nil, UIParent)
        if ok and f then
            pcall(f.Hide, f)
            local okBar, bar = pcall(CreateFrame, "StatusBar", nil, f)
            local okText, text = pcall(f.CreateFontString, f, nil, "OVERLAY", "GameFontNormal")
            displayFrame = { bar = okBar and bar or nil, text = okText and text or nil }
            if displayFrame.bar then
                pcall(displayFrame.bar.SetMinMaxValues, displayFrame.bar, 0, 100)
            end
        else
            displayFrame = {}
        end
    end
    local bar, text = displayFrame.bar, displayFrame.text
    if bar then
        local ok, err = pcall(bar.SetValue, bar, v)
        entry.setValue = ok and "ok" or ("error: " .. errText(err))
        pcall(bar.SetValue, bar, 0)
    else
        entry.setValue = "no StatusBar"
    end
    if text then
        local ok, err = pcall(text.SetText, text, v)
        entry.setText = ok and "ok" or ("error: " .. errText(err))
        pcall(text.SetText, text, "")
    else
        entry.setText = "no FontString"
    end
    Probe:Log("P3", string.format("P3b [%s] StatusBar:SetValue(secret) %s; FontString:SetText(secret) %s",
        currentCode, entry.setValue, entry.setText))
end

local function accessText(v)
    local test = rawget(_G, "canaccessvalue")
    if type(test) ~= "function" then
        return "missing"
    end
    local ok, can = pcall(test, v)
    if not ok or IsSecret(can) then
        return "?"
    end
    return can and "yes" or "no"
end

--- Describes what one call returned, keeping no secret value: { n, kinds, values, access, secret, err, missing }.
local function describeResults(spec, ok, ...)
    local r = { n = 0, kinds = {}, values = {} }
    if not ok then
        local err = ...
        if err == "API missing" then
            r.missing = true
        else
            r.err = err -- already scrubbed by Probe.Call
        end
        return r
    end
    r.n = select("#", ...)
    for i = 1, r.n do
        local v = select(i, ...)
        local kind, value = Describe(v)
        r.kinds[i] = kind
        r.values[i] = value
        if kind == "secret" then
            r.secret = true
            r.access = r.access or {}
            r.access[i] = accessText(v)
            if spec.numeric[i] then
                displayTest(v)
            end
        end
    end
    return r
end

--- True when the call returned at least one value that is not nil (a secret value counts).
local function answered(r)
    if r.err or r.missing then
        return false
    end
    for i = 1, r.n do
        if r.kinds[i] ~= "nil" then
            return true
        end
    end
    return false
end

local SHORT = { boolean = "b", number = "n", secret = "S", ["nil"] = "-", string = "str", table = "tbl" }

--- "UDTS#5 b:false n:3 n:100 n:100 n:1520" (S = secret, S(access) when canaccessvalue says yes, - = nil).
local function resultText(key, r)
    if r.missing then
        return key .. " missing"
    end
    if r.err then
        return key .. " error(" .. r.err .. ")"
    end
    local parts = { key .. "#" .. r.n }
    for i = 1, r.n do
        local kind = r.kinds[i]
        local s = SHORT[kind] or kind
        if kind == "secret" then
            if r.access and r.access[i] == "yes" then
                s = "S(access)"
            end
        elseif r.values[i] ~= nil then
            s = s .. ":" .. tostring(r.values[i])
        end
        parts[#parts + 1] = s
    end
    return table.concat(parts, " ")
end

--- Same as resultText without the readable values: changes only when the kinds change.
local function kindsText(key, r)
    if r.missing or r.err then
        return key .. (r.missing and "?" or "!")
    end
    local parts = { key }
    for i = 1, r.n do
        parts[#parts + 1] = SHORT[r.kinds[i]] or r.kinds[i]
    end
    return table.concat(parts, "")
end

local function call(spec, unit, second)
    local fn = rawget(_G, spec.name)
    if spec.single then
        return describeResults(spec, Call(fn, unit))
    end
    return describeResults(spec, Call(fn, unit, second))
end

--- One reading of `unit` on `mob`. form "token" passes the mob's unit token (and also calls UnitThreatSituation with
--- the unit alone); form "guid" passes the mob's GUID instead, only when the GUID is readable (it is never stored).
local function read(unit, mob, form)
    local reading = { unit = unit, mob = mob, form = form, calls = {} }
    local second = mob
    if form == "guid" then
        local ok, guid = Call(UnitGUID, mob)
        if not ok or IsSecret(guid) or type(guid) ~= "string" then
            reading.skipped = not ok and "UnitGUID error" or (IsSecret(guid) and "GUID secret" or "no GUID")
            return reading
        end
        second = guid
    end
    for _, spec in ipairs(THREAT) do
        reading.calls[spec.key] = call(spec, unit, second)
    end
    if form == "token" then
        reading.calls.UTS1 = call(SINGLE, unit)
    end
    return reading
end

local ORDER = { "UDTS", "UTS", "POL", "ULS", "UTS1" }

local function readingText(reading)
    if reading.skipped then
        return "skipped (" .. reading.skipped .. ")"
    end
    local parts = {}
    for _, key in ipairs(ORDER) do
        if reading.calls[key] then
            parts[#parts + 1] = resultText(key, reading.calls[key])
        end
    end
    return table.concat(parts, " | ")
end

local function readingKinds(reading)
    local parts = {}
    for _, key in ipairs(ORDER) do
        if reading.calls[key] then
            parts[#parts + 1] = kindsText(key, reading.calls[key])
        end
    end
    return table.concat(parts, " ")
end

--- Which roles came back secret, and which came back at all (a number, a boolean or a secret).
local function secrecy(reading)
    local s = { valuesSecret = false, stateSecret = false, valuesSeen = false, stateSeen = false, errors = 0 }
    for key, r in pairs(reading.calls) do
        if r.err then
            s.errors = s.errors + 1
        end
        local spec = BY_KEY[key]
        for i = 1, r.n do
            local role, kind = spec.role[i], r.kinds[i]
            if role and kind ~= "nil" then
                if role == "value" then
                    s.valuesSeen = true
                    s.valuesSecret = s.valuesSecret or kind == "secret"
                else
                    s.stateSeen = true
                    s.stateSecret = s.stateSecret or kind == "secret"
                end
            end
        end
    end
    return s
end

--- The secrecy predictions of C_Secrets for this pair (the dump has them in C_Secrets, not as globals).
local function predictions(unit, mob)
    return {
        values = boolText(Call(API("C_Secrets", "ShouldUnitThreatValuesBeSecret"), unit, mob)),
        state = boolText(Call(API("C_Secrets", "ShouldUnitThreatStateBeSecret"), unit, mob)),
        state1 = boolText(Call(API("C_Secrets", "ShouldUnitThreatStateBeSecret"), unit)),
    }
end

--- "right", "wrong" or "unknown": does the prediction match what came back?
local function judge(prediction, seen, secret)
    if not seen or (prediction ~= "yes" and prediction ~= "no") then
        return "unknown"
    end
    return ((prediction == "yes") == secret) and "right" or "wrong"
end

----------------------------------------------------------------------------------------------------------------------
-- /atwp ctx and /atwp watch
----------------------------------------------------------------------------------------------------------------------

Probe.commands.ctx = function(arg, rest)
    local label = arg
    if rest ~= "" then
        label = label .. " " .. rest
    end
    local d = Probe.DB()
    if label:lower() == "clear" or label == "-" then
        d.label = nil
    elseif label ~= "" then
        Probe.LearnNames()
        d.label = Probe.Scrub(label):gsub("[%s|]+", "-"):sub(1, 32)
    end
    local text = Probe.ContextText(Probe.Context())
    Probe:Log("context", "ctx: " .. text)
    out("context: " .. text)
end

-- Functions(trigger) called by the watch: "combat-start", "tick" (every second in combat), "encounter-start",
-- "combat-end" and "after-combat" (2 s after the end).
Probe.watchHooks = {}

local function fireWatch(trigger)
    for _, hook in ipairs(Probe.watchHooks) do
        local ok, err = pcall(hook, trigger)
        if not ok then
            Probe:Log("errors", "watch " .. trigger .. ": " .. errText(err))
        end
    end
end

local function watching()
    return Probe.DB().watch == true
end

local function startTicks()
    Probe.Every("watch", 1, function()
        fireWatch("tick")
    end)
end

Probe.commands.watch = function(arg)
    arg = arg:lower()
    local d = Probe.DB()
    if arg == "on" then
        d.watch = true
        if inCombat() then
            startTicks()
        end
    elseif arg == "off" then
        d.watch = nil
        Probe.Cancel("watch")
    end
    out("watch " .. (watching() and "on" or "off") .. " (/atwp watch on|off)")
end

Probe:On("PLAYER_REGEN_DISABLED", function()
    if watching() then
        fireWatch("combat-start")
        startTicks()
    end
end)
Probe:On("ENCOUNTER_START", function(encounterID, _, difficultyID, groupSize)
    -- The encounter name (second value) is never read.
    Probe:Log("P3", string.format("ENCOUNTER_START id=%s difficulty=%s size=%s", shown(encounterID),
        shown(difficultyID), shown(groupSize)))
    if watching() then
        fireWatch("encounter-start")
    end
end)
Probe:On("ENCOUNTER_END", function(encounterID, _, difficultyID, groupSize, success)
    Probe:Log("P3", string.format("ENCOUNTER_END id=%s difficulty=%s size=%s success=%s", shown(encounterID),
        shown(difficultyID), shown(groupSize), shown(success)))
end)
Probe:On("PLAYER_REGEN_ENABLED", function()
    Probe.Cancel("watch")
    if watching() then
        fireWatch("combat-end")
        Probe.After("watch-after", 2, function()
            fireWatch("after-combat")
        end)
    end
end)
-- After a /reload in combat PLAYER_REGEN_DISABLED does not fire again: resume the ticks.
Probe:On("PLAYER_ENTERING_WORLD", function()
    if watching() and inCombat() then
        startTicks()
    end
end)
Probe:On("ADDON_RESTRICTION_STATE_CHANGED", function(restrictionType, state)
    local results = store("p3")
    results.restrictionEvents = (results.restrictionEvents or 0) + 1
    Probe:Log("P3", string.format("ADDON_RESTRICTION_STATE_CHANGED type=%s state=%s [%s]", shown(restrictionType),
        shown(state), contextKey(Probe.Context())))
end)

----------------------------------------------------------------------------------------------------------------------
-- P1: client and interface
----------------------------------------------------------------------------------------------------------------------

-- What P2-P12 call. "C_X.Name" is looked up in the namespace, anything else as a global. Enum tables are tables.
local CENSUS = {
    "UnitDetailedThreatSituation", "UnitThreatSituation", "UnitThreatPercentageOfLead", "UnitThreatLeadSituation",
    "GetThreatStatusColor", "IsThreatWarningEnabled", "issecretvalue", "canaccessvalue", "issecrettable",
    "canaccesstable", "C_Secrets.HasSecretRestrictions", "C_Secrets.ShouldUnitThreatValuesBeSecret",
    "C_Secrets.ShouldUnitThreatStateBeSecret", "ShouldUnitThreatValuesBeSecret", "ShouldUnitThreatStateBeSecret",
    "C_CombatLog.IsCombatLogRestricted", "CombatLogGetCurrentEventInfo", "C_RestrictedActions.IsAddOnRestrictionActive",
    "C_RestrictedActions.InCombatLockdown", "InCombatLockdown", "Enum.AddOnRestrictionType",
    "C_DamageMeter.IsDamageMeterAvailable", "C_DamageMeter.GetAvailableCombatSessions",
    "C_DamageMeter.GetCombatSessionFromType", "C_DamageMeter.GetSessionDurationSeconds", "Enum.DamageMeterType",
    "Enum.DamageMeterSessionType", "C_InstanceEncounter.IsEncounterInProgress", "IsEncounterInProgress", "UnitGUID",
    "UnitGroupRolesAssigned", "UnitTokenFromGUID", "C_Secrets.CanCompareUnitTokens",
    "C_Secrets.ShouldUnitIdentityBeSecret", "C_Secrets.ShouldUnitComparisonBeSecret", "UnitClassification", "UnitExists", "UnitIsDead", "UnitCanAttack", "UnitIsUnit",
    "UnitAffectingCombat", "IsInInstance", "GetInstanceInfo", "IsInGroup", "IsInRaid", "GetNumGroupMembers", "GetTime",
    "debugprofilestop", "UpdateAddOnMemoryUsage", "GetAddOnMemoryUsage", "C_Timer.After", "C_Timer.NewTicker",
    "CreateFrame", "GetFramerate", "collectgarbage", "GetServerTime", "Enum.AddOnRestrictionState",
}

local function censusEntry(path)
    local namespace, name = path:match("^([%w_]+)%.([%w_]+)$")
    local v
    if namespace then
        v = API(namespace, name)
    else
        v = rawget(_G, path)
    end
    if v == nil then
        return "absent"
    end
    return type(v)
end

--- The WOW_PROJECT_* globals (not in the dump): which project the client says it is.
local function projectGlobals()
    local names = {}
    for name, value in pairs(_G) do
        if type(name) == "string" and name:find("^WOW_PROJECT_") and type(value) == "number" then
            names[#names + 1] = name .. "=" .. tostring(value)
        end
    end
    table.sort(names)
    return names
end

Probe:Register("P1", "Client version, build, project, interface, restrictions", function()
    elapsed("P1", true)
    local ok, version, build, buildDate, interface, localized, info = Call(GetBuildInfo)
    if not ok then
        Probe:Log("P1", "GetBuildInfo error: " .. tostring(version))
        return "not supported", "GetBuildInfo error: " .. tostring(version)
    end
    local buildText = string.format("version=%s build=%s date=%s interface=%s localized=%s info=%s",
        shownText(version), shownText(build), shownText(buildDate), shown(interface), shownText(localized), shownText(info))
    Probe:Log("P1", "GetBuildInfo: " .. buildText)

    local project = rawget(_G, "WOW_PROJECT_ID")
    local projectText = project == nil and "absent" or shown(project)
    local projects = projectGlobals()
    Probe:Log("P1", "WOW_PROJECT_ID=" .. projectText .. "; " .. (#projects > 0 and table.concat(projects, " ") or
        "no WOW_PROJECT_* global"))
    local okLocale, locale = Call(GetLocale)
    local localeText = okLocale and shownText(locale) or "error"
    local hasSecret = boolText(Call(API("C_Secrets", "HasSecretRestrictions")))
    local logRestricted = boolText(Call(API("C_CombatLog", "IsCombatLogRestricted")))
    Probe:Log("P1", string.format("locale=%s C_Secrets.HasSecretRestrictions=%s C_CombatLog.IsCombatLogRestricted=%s",
        localeText, hasSecret, logRestricted))

    local absent = {}
    for _, path in ipairs(CENSUS) do
        local kind = censusEntry(path)
        Probe:Log("P1", "census " .. path .. " = " .. kind)
        if kind == "absent" then
            absent[#absent + 1] = path
        end
    end

    local versionPlain = Probe.Plain(version, nil)
    local buildNumber = tonumber(Probe.Plain(build, nil))
    local interfacePlain = Probe.Plain(interface, nil)
    local details = string.format("%s; WOW_PROJECT_ID=%s; locale=%s; HasSecretRestrictions=%s; " ..
        "IsCombatLogRestricted=%s; census %d/%d present, absent: %s", buildText, projectText, localeText, hasSecret,
        logRestricted, #CENSUS - #absent, #CENSUS, #absent > 0 and table.concat(absent, ", ") or "none")
    if versionPlain == "1.60.1" and buildNumber and buildNumber >= 70170 and interfacePlain == 16001 then
        return "supported", "as the dump (1.60.1, build >= 70170, interface 16001). " .. details
    end
    return "partial", "build or interface differ from the dump (1.60.1 / 70170 / 16001). " .. details
end)

----------------------------------------------------------------------------------------------------------------------
-- P2: the threat functions on the target
----------------------------------------------------------------------------------------------------------------------

--- The case of SPEC-08 P2, recognised from the target: a no target, b friendly, c hostile not engaged, d in combat
--- with the player, e in combat with someone else, f dead mob; "?" when the answers are not readable.
local function targetCase()
    if not exists("target") then
        return "a", "no target"
    end
    if flag(Call(UnitIsDead, "target")) == true then
        if flag(Call(UnitIsPlayer, "target")) == true then
            return "b", "dead player"
        end
        return "f", "dead mob"
    end
    local canAttack = flag(Call(UnitCanAttack, "player", "target"))
    if canAttack == nil then
        return "?", "UnitCanAttack not readable"
    end
    if not canAttack then
        return "b", "friendly"
    end
    if flag(Call(UnitAffectingCombat, "target")) ~= true then
        return "c", "hostile, not engaged"
    end
    if inCombat() then
        return "d", "in combat with you"
    end
    return "e", "in combat with someone else"
end

local function inRange(key, r)
    for i = 1, r.n do
        local kind, v = r.kinds[i], r.values[i]
        if kind ~= "secret" and kind ~= "nil" then
            if key == "UDTS" and i == 1 then
                if kind ~= "boolean" then
                    return false
                end
            elseif kind ~= "number" then
                return false
            elseif (key == "UDTS" and i == 2) or key == "UTS" or key == "UTS1" or key == "ULS" then
                if v < 0 or v > 3 or v ~= math.floor(v) then
                    return false
                end
            elseif key == "UDTS" and i == 3 then
                if v < 0 or v > 100 then
                    return false
                end
            elseif key == "UDTS" and v < 0 then
                return false
            end
        end
    end
    return true
end

local function tally(caseStats, callKey, key, r)
    local s = caseStats[callKey]
    if not s then
        s = { calls = 0, values = 0, nils = 0, secret = 0, errors = 0, missing = 0, bad = 0, arity = {} }
        caseStats[callKey] = s
    end
    s.calls = s.calls + 1
    if r.missing then
        s.missing = s.missing + 1
    elseif r.err then
        s.errors = s.errors + 1
    elseif answered(r) then
        s.values = s.values + 1
        s.arity[tostring(r.n)] = (s.arity[tostring(r.n)] or 0) + 1
        if r.secret then
            s.secret = s.secret + 1
        end
        if not inRange(key, r) then
            s.bad = s.bad + 1
        end
    else
        s.nils = s.nils + 1
    end
end

local function tallyReading(caseStats, reading)
    if reading.skipped then
        local k = "guid-skipped"
        caseStats[k] = caseStats[k] or { calls = 0 }
        caseStats[k].calls = caseStats[k].calls + 1
        return
    end
    for key, r in pairs(reading.calls) do
        tally(caseStats, key .. "/" .. (key == "UTS1" and "none" or reading.form), key, r)
    end
end

local p2Active, p2Count, p2LastKinds = false, 0, nil

local function p2Reading(trigger)
    local c = stamp("P2")
    local case, caseText = targetCase()
    local results = store("p2")
    results[case] = results[case] or {}
    local token = read("player", "target", "token")
    local guid = case == "a" and { skipped = "no target", calls = {} } or read("player", "target", "guid")
    tallyReading(results[case], token)
    tallyReading(results[case], guid)
    p2Count = p2Count + 1
    local kinds = case .. readingKinds(token) .. "/" .. readingKinds(guid)
    local line = string.format("%s t=%.1f [%s] case %s (%s) %s | token: %s | guid: %s", trigger, elapsed("P2"),
        contextKey(c), case, caseText, case == "a" and "-" or mobText("target"), readingText(token),
        readingText(guid))
    -- Automatic readings (every 0.5 s in combat) are logged when the kinds change, else once every 5 s.
    if trigger ~= "auto" or kinds ~= p2LastKinds or p2Count % 10 == 0 then
        Probe:Log("P2", line)
    end
    p2LastKinds = kinds
    return case, line
end

local function p2StartAuto()
    Probe.Every("P2", 0.5, function()
        if inCombat() then
            p2Reading("auto")
        else
            Probe.Cancel("P2")
        end
    end, 0)
end

Probe:On("PLAYER_REGEN_DISABLED", function()
    if p2Active then
        elapsed("P2", true)
        p2StartAuto()
    end
end)
Probe:On("PLAYER_REGEN_ENABLED", function()
    Probe.Cancel("P2")
end)

local REQUIRED_CASES = { "a", "b", "c", "d", "f" }

local function present(name)
    return type(rawget(_G, name)) == "function"
end

local function arityIssues(s, expect)
    local issues = {}
    for n in pairs(s.arity or {}) do
        if tonumber(n) ~= expect then
            issues[#issues + 1] = n
        end
    end
    table.sort(issues)
    return issues
end

local function p2Verdict()
    local results = store("p2")
    if not present("UnitDetailedThreatSituation") and not present("UnitThreatSituation") then
        return "not supported", "UnitDetailedThreatSituation and UnitThreatSituation are missing"
    end
    local seen, missing = {}, {}
    for _, case in ipairs(REQUIRED_CASES) do
        if results[case] then
            seen[#seen + 1] = case
        else
            missing[#missing + 1] = case
        end
    end
    local issues = {}
    for _, spec in ipairs(THREAT) do
        if not present(spec.name) then
            issues[#issues + 1] = spec.name .. " missing"
        end
    end
    local d = results.d
    local summary = {}
    if d then
        local udts, uts = d["UDTS/token"] or { values = 0 }, d["UTS/token"] or { values = 0 }
        if udts.values == 0 and uts.values == 0 then
            return "not supported", "in combat (case d) UnitDetailedThreatSituation and UnitThreatSituation never " ..
                "answered (nil or error)"
        end
        for _, key in ipairs({ "UDTS", "UTS", "POL", "ULS", "UTS1" }) do
            local spec = BY_KEY[key]
            local tok = d[key .. "/" .. (key == "UTS1" and "none" or "token")]
            local byGuid = d[key .. "/guid"]
            if tok and present(spec.name) then
                summary[#summary + 1] = string.format("%s %d/%d answered, %d secret, %d nil, %d errors", key,
                    tok.values, tok.calls, tok.secret, tok.nils, tok.errors)
                if tok.values == 0 then
                    if byGuid and (byGuid.values or 0) > 0 then
                        issues[#issues + 1] = key .. " answers only with the mob's GUID"
                    else
                        issues[#issues + 1] = key .. " nil even in combat"
                    end
                end
                if tok.errors > 0 then
                    issues[#issues + 1] = key .. " errors in combat (" .. tok.errors .. ")"
                end
                local arity = arityIssues(tok, spec.expect)
                if #arity > 0 then
                    issues[#issues + 1] = key .. " returns " .. table.concat(arity, "/") .. " values (dump: " ..
                        spec.expect .. ")"
                end
                if tok.bad > 0 then
                    issues[#issues + 1] = key .. " out of the dump's range " .. tok.bad .. " times"
                end
            end
        end
    end
    local tail = " Cases seen: " .. (#seen > 0 and table.concat(seen, ",") or "none") ..
        (#missing > 0 and ("; missing: " .. table.concat(missing, ",")) or "") ..
        (#summary > 0 and (". Case d: " .. table.concat(summary, "; ")) or "")
    if #issues > 0 then
        return "partial", table.concat(issues, "; ") .. "." .. tail
    end
    if #missing > 0 then
        return "todo", "no problem so far." .. tail
    end
    return "supported", "the four functions accept the mob's token and answer as the dump; nil only out of combat." ..
        tail
end

Probe:Register("P2", "Threat functions on the target: presence, arguments, returns", function()
    Probe.LearnNames()
    if not p2Active then
        p2Active = true
        elapsed("P2", true)
    end
    local case, line = p2Reading("run")
    out("P2 " .. line)
    -- Out of combat colours and warning setting, once per run.
    local colours = {}
    for i = 0, 3 do
        local ok, r, g, b = Call(GetThreatStatusColor, i)
        colours[#colours + 1] = ok and (i .. "=" .. shown(r) .. "," .. shown(g) .. "," .. shown(b)) or
            (i .. "=error")
    end
    Probe:Log("P2", "GetThreatStatusColor " .. table.concat(colours, " ") .. "; IsThreatWarningEnabled=" ..
        boolText(Call(IsThreatWarningEnabled)))
    -- The same moment also counts for P3 (solo, a mob targeted out of combat).
    if case ~= "a" then
        Probe.p3Readings("P2")
    end
    if case == "d" or case == "e" then
        p2StartAuto()
    end
    return p2Verdict()
end)

----------------------------------------------------------------------------------------------------------------------
-- P3: secret values, per context
----------------------------------------------------------------------------------------------------------------------

local function newCounters()
    return { readings = 0, answered = 0, valuesSecret = 0, stateSecret = 0, errors = 0,
        predValues = { right = 0, wrong = 0, unknown = 0 }, predState = { right = 0, wrong = 0, unknown = 0 } }
end

local p3Kinds, p3Ticks = {}, 0

--- Readings of the threat on one hostile mob (the target, or the target's target for a healer) by the player, the
--- other group members and targettarget, with the C_Secrets predictions; counted per context, logged.
function Probe.p3Readings(trigger)
    local c = stamp("P3")
    local key = contextKey(c)
    currentCode = tostring(c.code)
    local results = store("p3")
    results.stats = results.stats or {}
    local stats = results.stats[key]
    if not stats then
        stats = { code = c.code, combat = c.combat == "yes", units = {}, noMob = 0 }
        results.stats[key] = stats
    end
    if trigger == "combat-start" then
        elapsed("P3", true)
    end
    if trigger == "tick" then
        p3Ticks = p3Ticks + 1
    else
        local hasSecret = boolText(Call(API("C_Secrets", "HasSecretRestrictions")))
        results.hasSecretRestrictions = hasSecret
        Probe:Log("P3", trigger .. " [" .. key .. "] C_Secrets.HasSecretRestrictions=" .. hasSecret)
    end
    local mob = hostile("target") and "target" or (hostile("targettarget") and "targettarget" or nil)
    if not mob then
        stats.noMob = stats.noMob + 1
        if trigger ~= "tick" then
            Probe:Log("P3", trigger .. " [" .. key .. "] no hostile target or target's target")
        end
        return
    end
    local pairsToRead = { { "player", "player" } }
    for _, unit in ipairs(groupUnits()) do
        pairsToRead[#pairsToRead + 1] = { unit, "group" }
    end
    if mob == "target" and exists("targettarget") then
        pairsToRead[#pairsToRead + 1] = { "targettarget", "targettarget" }
    end
    local mobLine = mobText(mob)
    local t = elapsed("P3")
    for _, pair in ipairs(pairsToRead) do
        local unit, unitKind = pair[1], pair[2]
        local pred = predictions(unit, mob)
        local reading = read(unit, mob, "token")
        local s = secrecy(reading)
        local counters = stats.units[unitKind] or newCounters()
        stats.units[unitKind] = counters
        counters.readings = counters.readings + 1
        if s.valuesSeen or s.stateSeen then
            counters.answered = counters.answered + 1
        end
        if s.valuesSecret then
            counters.valuesSecret = counters.valuesSecret + 1
        end
        if s.stateSecret then
            counters.stateSecret = counters.stateSecret + 1
        end
        if s.errors > 0 then
            counters.errors = counters.errors + 1
        end
        local jv = judge(pred.values, s.valuesSeen, s.valuesSecret)
        local js = judge(pred.state, s.stateSeen, s.stateSecret)
        counters.predValues[jv] = counters.predValues[jv] + 1
        counters.predState[js] = counters.predState[js] + 1
        local kinds = string.format("%s %s %s %s", pred.values, pred.state, pred.state1, readingKinds(reading))
        local id = key .. ">" .. unit .. ">" .. mob
        if trigger ~= "tick" or p3Kinds[id] ~= kinds or (unit == "player" and p3Ticks % 10 == 0) then
            Probe:Log("P3", string.format("%s t=%.1f [%s] %s>%s %s | pred values=%s(%s) state=%s(%s) state1=%s | %s",
                trigger, t, key, unit, mob, mobLine, pred.values, jv, pred.state, js, pred.state1,
                readingText(reading)))
        end
        p3Kinds[id] = kinds
    end
end

table.insert(Probe.watchHooks, Probe.p3Readings)

local MVP_CONTEXTS = { "solo-combat", "party", "dungeon", "raid" }
local GROUP_CONTEXTS = { party = true, dungeon = true, raid = true }

local function p3Verdict()
    local results = store("p3")
    local hasSecret = results.hasSecretRestrictions
    local perCode, rightWrong = {}, { right = 0, wrong = 0 }
    local secretWhere, playerBoth = {}, {}
    for key, stats in pairs(results.stats or {}) do
        for unitKind, n in pairs(stats.units) do
            if stats.combat and n.answered > 0 then
                perCode[stats.code] = true
            end
            rightWrong.right = rightWrong.right + n.predValues.right + n.predState.right
            rightWrong.wrong = rightWrong.wrong + n.predValues.wrong + n.predState.wrong
            if n.valuesSecret > 0 or n.stateSecret > 0 then
                secretWhere[#secretWhere + 1] = string.format("%s %s values %d/%d state %d/%d", key, unitKind,
                    n.valuesSecret, n.readings, n.stateSecret, n.readings)
                if unitKind == "player" and stats.combat and GROUP_CONTEXTS[stats.code] and n.valuesSecret > 0 and
                    n.stateSecret > 0 then
                    playerBoth[#playerBoth + 1] = key
                end
            end
        end
    end
    table.sort(secretWhere)
    table.sort(playerBoth)
    local missing = {}
    for _, code in ipairs(MVP_CONTEXTS) do
        if not perCode[code] then
            missing[#missing + 1] = code
        end
    end
    local p3b = {}
    for code, entry in pairs(results.p3b or {}) do
        p3b[#p3b + 1] = code .. " SetValue " .. tostring(entry.setValue) .. ", SetText " .. tostring(entry.setText)
    end
    table.sort(p3b)
    local seen = {}
    for code in pairs(perCode) do
        seen[#seen + 1] = code
    end
    table.sort(seen)
    local tail = string.format(" HasSecretRestrictions=%s. Predictions right %d, wrong %d. Combat contexts seen: %s." ..
        " P3b: %s.", tostring(hasSecret), rightWrong.right, rightWrong.wrong,
        #seen > 0 and table.concat(seen, ",") or "none",
        #p3b > 0 and table.concat(p3b, "; ") or "not run (nothing secret yet)")
    if #missing > 0 then
        tail = tail .. " Still to play in combat: " .. table.concat(missing, ", ") .. "."
    end
    if hasSecret == "no" then
        return "supported", "C_Secrets.HasSecretRestrictions() is false: nothing in this build is secret." .. tail
    end
    if #playerBoth > 0 then
        return "not supported", "values and state secret for the player in combat in " ..
            table.concat(playerBoth, ", ") .. ". Secret: " .. table.concat(secretWhere, "; ") .. "." .. tail
    end
    if #secretWhere > 0 then
        return "partial", "secret: " .. table.concat(secretWhere, "; ") .. "." .. tail
    end
    if #missing > 0 then
        return "todo", "no secret value so far." .. tail
    end
    return "supported", "no secret value in any context." .. tail
end

Probe:Register("P3", "Secret values: predictions and issecretvalue per context", function()
    Probe.LearnNames()
    Probe.p3Readings("run")
    return p3Verdict()
end)

----------------------------------------------------------------------------------------------------------------------
-- P4: standard threat rules, the guided tank and DPS trial
----------------------------------------------------------------------------------------------------------------------

local p4 = { armed = false }

--- One sample of UnitDetailedThreatSituation(unit, "target"): plain values, "secret", or nil.
local function sampleUnit(unit)
    local ok, isTanking, status, scaled, raw, rawThreat = Call(rawget(_G, "UnitDetailedThreatSituation"), unit,
        "target")
    if not ok then
        return { err = tostring(isTanking) }
    end
    local function plain(v)
        local kind, value = Describe(v)
        if kind == "secret" then
            return "secret"
        end
        return value
    end
    return { isTanking = plain(isTanking), status = plain(status), scaled = plain(scaled), raw = plain(raw),
        rawThreat = plain(rawThreat) }
end

--- The tank of the trial: the member with the TANK role, else the one the mob targets, else the only member, else the
--- pet (P4 in solo-combat with a pet, when P3 finds the values secret in a party).
local function findTank()
    local units = groupUnits()
    for _, unit in ipairs(units) do
        local ok, role = Call(UnitGroupRolesAssigned, unit)
        if ok and not IsSecret(role) and role == "TANK" then
            return unit
        end
    end
    for _, unit in ipairs(units) do
        if flag(Call(UnitIsUnit, unit, "targettarget")) == true then
            return unit
        end
    end
    if #units == 1 then
        return units[1]
    end
    if exists("pet") then
        return "pet"
    end
end

local function sampleText(s)
    local function unitText(name, u)
        if not u then
            return name .. " -"
        end
        if u.err then
            return name .. " error(" .. u.err .. ")"
        end
        return string.format("%s isTanking=%s status=%s scaled=%s raw=%s rawThreat=%s", name, tostring(u.isTanking),
            tostring(u.status), tostring(u.scaled), tostring(u.raw), tostring(u.rawThreat))
    end
    return string.format("t=%.1f %s | %s | targettarget=player:%s", s.t, unitText("player", s.player),
        unitText(tostring(p4.tank or "tank"), s.tank), s.tt == nil and "?" or (s.tt and "yes" or "no"))
end

local function finishTrial()
    local before, after = p4.before or {}, p4.after or {}
    local rawMax, rawLast, scaledMax, secret = nil, nil, nil, false
    for _, s in ipairs(before) do
        local p = s.player or {}
        if type(p.raw) == "number" then
            rawLast = p.raw
            rawMax = math.max(rawMax or p.raw, p.raw)
        end
        if type(p.scaled) == "number" then
            scaledMax = math.max(scaledMax or p.scaled, p.scaled)
        end
        secret = secret or p.raw == "secret" or p.scaled == "secret"
    end
    local at = (after[1] and after[1].player) or {}
    local c = Probe.Context()
    local trials = store("p4")
    trials.trials = trials.trials or {}
    local trial = {
        kind = p4.kind, trigger = p4.trigger, rawMax = rawMax, rawLast = rawLast, scaledMax = scaledMax,
        scaledAt = type(at.scaled) == "number" and at.scaled or nil, secret = secret, samples = #before,
        tank = p4.tank or "none", context = contextKey(c),
    }
    table.insert(trials.trials, trial)
    local n = #trials.trials
    Probe:Log("P4", string.format("trial %d (%s) [%s]: aggro changed (%s); before: raw max %s, last %s, scaled max " ..
        "%s; at the change: scaled %s; tank %s", n, tostring(p4.kind), trial.context, tostring(p4.trigger),
        tostring(rawMax), tostring(rawLast), tostring(scaledMax), tostring(trial.scaledAt), trial.tank))
    for _, s in ipairs(before) do
        Probe:Log("P4", "  before " .. sampleText(s))
    end
    for _, s in ipairs(after) do
        Probe:Log("P4", "  after  " .. sampleText(s))
    end
    p4.armed, p4.before, p4.after = false, nil, nil
    Probe.Cancel("P4")
    out(string.format("P4 trial %d (%s): aggro changed; raw before %s, scaled before %s. Next: /atwp note P4 " ..
        "melee|ranged, or /atwp run P4", n, tostring(p4.kind), tostring(rawMax), tostring(scaledMax)))
end

local function p4Sample()
    if not p4.armed then
        Probe.Cancel("P4")
        return
    end
    if not hostile("target") then
        return
    end
    local s = { t = elapsed("P4") }
    s.player = sampleUnit("player")
    p4.tank = p4.tank or findTank()
    if p4.tank then
        s.tank = sampleUnit(p4.tank)
    end
    s.tt = flag(Call(UnitIsUnit, "targettarget", "player"))
    if p4.after then
        p4.after[#p4.after + 1] = s
        if s.t - p4.changeAt >= 1 then
            finishTrial()
        end
        return
    end
    local buffer = p4.buffer
    buffer[#buffer + 1] = s
    while buffer[1] and buffer[1].t < s.t - 3 do
        table.remove(buffer, 1)
    end
    local tanking = s.player.isTanking
    local trigger
    if p4.lastTanking == false and tanking == true then
        trigger = "isTanking"
    elseif p4.lastTT == false and s.tt == true then
        trigger = "targettarget"
    end
    if tanking == true or tanking == false then
        p4.lastTanking = tanking
    end
    if s.tt ~= nil then
        p4.lastTT = s.tt
    end
    if trigger then
        p4.trigger, p4.changeAt = trigger, s.t
        p4.before = {}
        for i = 1, #buffer - 1 do
            p4.before[i] = buffer[i]
        end
        p4.after = { s }
    end
end

-- /atwp note P4 melee|ranged arms one trial: samples at 10 Hz (last 3 s kept) until the aggro changes, then 1 s more.
table.insert(Probe.noteHooks, function(id, text)
    if id ~= "P4" then
        return
    end
    local kind = text:lower():match("^%s*(%a+)")
    if kind ~= "melee" and kind ~= "ranged" then
        out("P4: write '/atwp note P4 melee' or '/atwp note P4 ranged' to start a trial")
        return
    end
    p4.armed, p4.kind, p4.buffer, p4.before, p4.after = true, kind, {}, nil, nil
    p4.tank, p4.lastTanking, p4.lastTT, p4.trigger = nil, nil, nil, nil
    elapsed("P4", true)
    Probe:Log("P4", "trial armed (" .. kind .. ")")
    if Probe.Every("P4", 0.1, p4Sample, 0) then
        out("P4 " .. kind .. " trial armed: sampling at 10 Hz until you take the aggro")
    else
        out("P4: no timer available (GetTime or CreateFrame failed)")
    end
end)

Probe:On("UNIT_TARGET", function(unit)
    if p4.armed and not IsSecret(unit) and unit == "target" then
        p4Sample()
    end
end)

local function median(list)
    table.sort(list)
    local n = #list
    if n == 0 then
        return nil
    end
    if n % 2 == 1 then
        return list[(n + 1) / 2]
    end
    return (list[n / 2] + list[n / 2 + 1]) / 2
end

local function spread(list)
    local low, high
    for _, v in ipairs(list) do
        low, high = math.min(low or v, v), math.max(high or v, v)
    end
    return low and (high - low) or 0
end

local function allNear(list, target, tolerance)
    for _, v in ipairs(list) do
        if math.abs(v - target) > tolerance then
            return false
        end
    end
    return #list > 0
end

local function p4Verdict()
    local trials = store("p4").trials or {}
    local raws = { melee = {}, ranged = {} }
    local counts = { melee = 0, ranged = 0 }
    local scaledBad, readable = {}, 0
    for i, trial in ipairs(trials) do
        counts[trial.kind] = (counts[trial.kind] or 0) + 1
        -- The scaled percentage that matters is the highest one BEFORE the change (after it the player tanks, and
        -- scaled is 100 by definition).
        if type(trial.rawMax) == "number" and type(trial.scaledMax) == "number" and raws[trial.kind] then
            readable = readable + 1
            table.insert(raws[trial.kind], trial.rawMax)
            if math.abs(trial.scaledMax - 100) > 2 then
                scaledBad[#scaledBad + 1] = "trial " .. i .. " scaled " .. tostring(trial.scaledMax)
            end
        end
    end
    local function list(kind)
        local parts = {}
        for _, v in ipairs(raws[kind]) do
            parts[#parts + 1] = tostring(v)
        end
        return kind .. " " .. counts[kind] .. " trials, raw " .. (#parts > 0 and table.concat(parts, ",") or "-")
    end
    local tail = " (" .. list("melee") .. "; " .. list("ranged") .. ")"
    if counts.melee + counts.ranged == 0 then
        return "todo", "no trial yet: with a tank, '/atwp note P4 melee' (or ranged) then take the aggro"
    end
    if readable == 0 then
        return "todo", "values secret or missing in every trial: repeat in solo-combat with a companion or a pet" ..
            tail
    end
    if #scaledBad > 0 then
        return "not supported", "scaled percentage not 100 at the change: " .. table.concat(scaledBad, "; ") .. tail
    end
    if #raws.melee == 0 or #raws.ranged == 0 then
        return "todo", "scaled is 100 at the change; melee and ranged trials both needed" .. tail
    end
    local few = (counts.melee < 3 or counts.ranged < 3) and " Fewer than 3 trials per kind." or ""
    local m, r = median(raws.melee), median(raws.ranged)
    if allNear(raws.melee, 110, 2) and allNear(raws.ranged, 130, 2) then
        return "supported", string.format("aggro changes at raw %.1f%% in melee and %.1f%% at range, scaled 100.%s%s",
            m, r, few, tail)
    end
    if spread(raws.melee) <= 4 and spread(raws.ranged) <= 4 then
        return "partial", string.format("constant ratios but not 110/130: melee %.1f%%, ranged %.1f%%; scaled 100.%s%s",
            m, r, few, tail)
    end
    return "partial", "scaled coherent (100 at the change), raw not constant." .. few .. tail
end

Probe:Register("P4", "Standard threat rules: percentages when aggro changes", function()
    if p4.armed then
        out("P4: a " .. tostring(p4.kind) .. " trial is still armed (no aggro change yet)")
    end
    return p4Verdict()
end)

----------------------------------------------------------------------------------------------------------------------
-- Export and reset
----------------------------------------------------------------------------------------------------------------------

table.insert(Probe.exportHooks, function()
    local lines = { "-- P2 per case (calls: answered/nil/secret/errors, arity, out of range)" }
    local p2 = store("p2")
    local cases = {}
    for case in pairs(p2) do
        cases[#cases + 1] = case
    end
    table.sort(cases)
    for _, case in ipairs(cases) do
        local keys = {}
        for key in pairs(p2[case]) do
            keys[#keys + 1] = key
        end
        table.sort(keys)
        for _, key in ipairs(keys) do
            local s = p2[case][key]
            local arity = {}
            for n, count in pairs(s.arity or {}) do
                arity[#arity + 1] = n .. "x" .. count
            end
            table.sort(arity)
            lines[#lines + 1] = string.format("case %s %s: %d calls, %d answered, %d nil, %d secret, %d errors, " ..
                "%d missing, arity %s, out of range %d", case, key, s.calls or 0, s.values or 0, s.nils or 0,
                s.secret or 0, s.errors or 0, s.missing or 0, #arity > 0 and table.concat(arity, ",") or "-",
                s.bad or 0)
        end
    end
    lines[#lines + 1] = "-- P3 per context and unit (readings, answered, values secret, state secret, errors, " ..
        "predictions values/state right-wrong-unknown)"
    local p3 = store("p3")
    local keys = {}
    for key in pairs(p3.stats or {}) do
        keys[#keys + 1] = key
    end
    table.sort(keys)
    for _, key in ipairs(keys) do
        local stats = p3.stats[key]
        for _, unitKind in ipairs({ "player", "group", "targettarget" }) do
            local n = stats.units[unitKind]
            if n then
                lines[#lines + 1] = string.format("%s %s: %d readings, %d answered, %d values secret, %d state " ..
                    "secret, %d errors, values %d-%d-%d, state %d-%d-%d", key, unitKind, n.readings, n.answered,
                    n.valuesSecret, n.stateSecret, n.errors, n.predValues.right, n.predValues.wrong,
                    n.predValues.unknown, n.predState.right, n.predState.wrong, n.predState.unknown)
            end
        end
        if stats.noMob > 0 then
            lines[#lines + 1] = key .. ": " .. stats.noMob .. " readings without a hostile mob"
        end
    end
    lines[#lines + 1] = "-- P4 trials (kind, trigger, raw max/last before, scaled max before, scaled at, tank)"
    for i, trial in ipairs(store("p4").trials or {}) do
        lines[#lines + 1] = string.format("trial %d %s %s [%s]: raw %s/%s, scaled %s, at %s, tank %s, %d samples",
            i, tostring(trial.kind), tostring(trial.trigger), tostring(trial.context), tostring(trial.rawMax),
            tostring(trial.rawLast), tostring(trial.scaledMax), tostring(trial.scaledAt), tostring(trial.tank),
            trial.samples or 0)
    end
    return lines
end)

-- Helpers shared with the later Checks files (Checks_Units.lua, M0.4 on), so that every check reads the same way.
Probe.helpers = {
    now = now, flag = flag, boolText = boolText, shown = shown, store = store, elapsed = elapsed, stamp = stamp,
    contextKey = contextKey, inCombat = inCombat, exists = exists, hostile = hostile, groupUnits = groupUnits,
    mobText = mobText, median = median, errText = errText,
}

table.insert(Probe.resetHooks, function()
    local d = Probe.DB()
    d.p2, d.p3, d.p4 = nil, nil, nil
    p2Active, p2Count, p2LastKinds = false, 0, nil
    p3Kinds, p3Ticks = {}, 0
    p4.armed, p4.before, p4.after = false, nil, nil
    lastStamp = {}
    Probe.Cancel("P2")
    Probe.Cancel("P4")
end)
