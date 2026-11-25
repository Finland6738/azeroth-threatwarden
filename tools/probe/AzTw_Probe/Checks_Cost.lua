-- AzTw Probe, checks P10-P12 (step M0.6): cost of sampling, restrictions, reload and logout. Development only, never
-- distributed.
-- Spec: docs/specs/SPEC-08-quality-probe-release.md, section 1 (rules PRB-01 to PRB-06, P10, P11, P12),
-- docs/specs/SPEC-01-platform-architecture.md, section 5, and docs/specs/SPEC-09-risks-open-questions.md, Q14.
-- Every API and event used here was checked against the Forever dump (build 70170) on 2026-11-25: debugprofilestop,
-- GetFramerate, UpdateAddOnMemoryUsage, GetAddOnMemoryUsage, collectgarbage, GetServerTime, GetTime,
-- C_Timer.NewTicker (seconds, callback, iterations), UnitDetailedThreatSituation, UnitThreatSituation,
-- C_Secrets.ShouldUnitThreatValuesBeSecret, C_Secrets.ShouldUnitThreatStateBeSecret,
-- C_RestrictedActions.IsAddOnRestrictionActive, C_RestrictedActions.InCombatLockdown,
-- C_InstanceEncounter.IsEncounterInProgress, UnitAffectingCombat; events ADDON_ACTION_BLOCKED and
-- ADDON_ACTION_FORBIDDEN (isTainted, function), ADDON_RESTRICTION_STATE_CHANGED (type, state), PLAYER_REGEN_DISABLED
-- and PLAYER_REGEN_ENABLED, PLAYER_LOGOUT, PLAYER_LOGIN, PLAYER_ENTERING_WORLD (isInitialLogin, isReloadingUi),
-- ENCOUNTER_START, UNIT_THREAT_LIST_UPDATE, UNIT_THREAT_SITUATION_UPDATE; frame methods RegisterEvent,
-- UnregisterEvent, IsEventRegistered. Not in the dump, looked up at run time (PRB-05): Enum.AddOnRestrictionType,
-- Enum.AddOnRestrictionState.
--
--   P10  `/atwp perf [hz] [units] [mobs]` times a tick that reads the threat of N units on M mobs, at 2, 5 and 10 Hz
--        with 5, 10 and 40 units, 30 seconds each, and measures the memory of the compact samples. It runs only when
--        asked, stops by itself (`/atwp perf stop` stops it earlier) and nothing of it survives a /reload. The samples
--        stay in memory and are dropped at the end of each configuration; only the figures are saved.
--   P11  Always on from login: blocked and forbidden actions, restriction states, and the errors of the probe, per
--        context. `/atwp run P11` adds a burst of 1000 threat readings in one frame (not during an encounter), a
--        register/unregister round of the two threat events and a 10-tick C_Timer ticker.
--   P12  `/atwp run P12` arms a buffer: in combat one compact sample a second goes to the saved variables, with a
--        final stamp at PLAYER_LOGOUT. At the next load the probe compares what it finds and reads the combat state
--        and the threat again. `/atwp note P12 lost` records that a reload did not save the buffer.
--
-- Secret values (PRB-02): every value goes through Probe.IsSecret / Probe.Describe first; a secret is only stored as
-- the code -2 or counted as "secret". GUIDs are compared in memory only; no name is read into a saved or printed text
-- (PRB-03). Everything saved is bounded.

local ADDON_NAME, Probe = ...

local IsSecret, Describe, Call, API = Probe.IsSecret, Probe.Describe, Probe.Call, Probe.API
local out = Probe.Print
local H = Probe.helpers
local now, flag, boolText, store, stamp = H.now, H.flag, H.boolText, H.store, H.stamp
local inCombat, hostile, groupUnits, median, errText = H.inCombat, H.hostile, H.groupUnits, H.median, H.errText
local guidOf, bump, statsFor, sortedKeys, countsText = H.guidOf, H.bump, H.statsFor, H.sortedKeys, H.countsText
local clock, currentContext, invalidateContext = H.clock, H.currentContext, H.invalidateContext
local sub, bumpCapped, number, keep = H.sub, H.bumpCapped, H.number, H.keep

local MVP_CONTEXTS = { "solo-combat", "party", "dungeon", "raid" }

local function watching()
    return Probe.DB().watch == true
end

--- A returned value as a compact number: -1 nil, -2 secret, -3 error or another type; booleans become 1 and 0.
local function code(ok, v)
    if not ok then
        return -3
    end
    if IsSecret(v) then
        return -2
    end
    if v == nil then
        return -1
    end
    local t = type(v)
    if t == "number" then
        return v
    end
    if t == "boolean" then
        return v and 1 or 0
    end
    return -3
end

local function round3(v)
    return v and math.floor(v * 1000 + 0.5) / 1000
end

--- A number for a line of text: "?" when it was not measured.
local function num(v, format)
    return v and string.format(format or "%.2f", v) or "?"
end

----------------------------------------------------------------------------------------------------------------------
-- P10: cost of sampling
----------------------------------------------------------------------------------------------------------------------

local PERF_RATES = { 2, 5, 10 }
local PERF_UNITS = { 5, 10, 40 }
local PERF_SECONDS = 30
local PERF_PAUSE = 3          -- before each configuration: the frame rate "before" is read at its end
local MAX_HZ, MAX_UNITS, MAX_MOBS = 20, 40, 8
local MAX_ROWS = 100000       -- compact samples kept per configuration (the rest is counted as dropped)
local KEEP_RUNS = 3           -- results kept per configuration
local BUDGET_P95, BUDGET_SECOND = 1, 5 -- ms per tick at the 95th percentile, ms of ticks per second (SPEC-08 P10, Q14)

local MOB_SEARCH = { "target", "focus", "mouseover", "targettarget", "pettarget" }
for i = 1, 5 do
    MOB_SEARCH[#MOB_SEARCH + 1] = "boss" .. i
end
for i = 1, 4 do
    MOB_SEARCH[#MOB_SEARCH + 1] = "party" .. i .. "target"
end
for i = 1, 40 do
    MOB_SEARCH[#MOB_SEARCH + 1] = "raid" .. i .. "target"
end
for i = 1, 40 do
    MOB_SEARCH[#MOB_SEARCH + 1] = "nameplate" .. i
end

local perf -- the run in progress, in memory only

--- Addon memory (KB, after UpdateAddOnMemoryUsage) and the whole Lua memory (KB); nil when not measurable.
local function memoryKB()
    local addon
    if Call(rawget(_G, "UpdateAddOnMemoryUsage")) then
        local ok, v = Call(rawget(_G, "GetAddOnMemoryUsage"), ADDON_NAME)
        addon = ok and number(v) or nil
    end
    local ok, v = Call(rawget(_G, "collectgarbage"), "count")
    return addon, ok and number(v) or nil
end

local function frameRate()
    local ok, v = Call(rawget(_G, "GetFramerate"))
    return ok and number(v) or nil
end

local function logMemory(label)
    local addon, lua = memoryKB()
    local line = string.format("memory %s: addon %s KB, Lua %s KB", label, num(addon, "%.0f"), num(lua, "%.0f"))
    keep(sub(store("p10"), "memory"), line, 20)
    Probe:Log("P10", line)
end

--- The units read: the player and the other members of the group.
local function perfUnits()
    local units = { "player" }
    for _, unit in ipairs(groupUnits()) do
        units[#units + 1] = unit
    end
    return units
end

--- Up to `max` tokens of distinct hostile mobs, and how many were found (with none, "target" is read anyway).
local function perfMobs(max)
    local list, seen = {}, {}
    for _, token in ipairs(MOB_SEARCH) do
        if #list >= max then
            break
        end
        if hostile(token) then
            local g = guidOf(token)
            local key = g.kind == "readable" and g.guid or token
            if not seen[key] then
                seen[key] = true
                list[#list + 1] = token
            end
        end
    end
    local found = #list
    if found == 0 then
        list[1] = "target"
    end
    return list, found
end

--- One timed tick (SPEC-08 P10): units x mobs readings of the threat, the state and the two secrecy predictions, each
--- saved as a compact sample. Nothing is allocated per reading apart from the samples themselves.
local function sampleTick(cfg, t)
    local udts, uts = rawget(_G, "UnitDetailedThreatSituation"), rawget(_G, "UnitThreatSituation")
    local valuesSecret = API("C_Secrets", "ShouldUnitThreatValuesBeSecret")
    local stateSecret = API("C_Secrets", "ShouldUnitThreatStateBeSecret")
    local units, mobs, cols = cfg.unitList, cfg.mobList, cfg.cols
    local unitCount, mobCount = #units, #mobs
    local started = clock()
    for i = 1, cfg.units do
        local u = (cfg.offset + i - 1) % unitCount + 1
        local unit = units[u]
        for m = 1, cfg.mobs do
            local mob = mobs[(m - 1) % mobCount + 1]
            local okDetail, _, _, scaled = pcall(udts, unit, mob)
            local okState, situation = pcall(uts, unit, mob)
            local okValues, predictedValues = pcall(valuesSecret, unit, mob)
            local okPredicted, predictedState = pcall(stateSecret, unit, mob)
            local pct, status = code(okDetail, scaled), code(okState, situation)
            if pct == -3 or status == -3 then
                cfg.errorPairs = cfg.errorPairs + 1
            elseif pct == -2 or status == -2 then
                cfg.secretPairs = cfg.secretPairs + 1
            elseif pct == -1 and status == -1 then
                cfg.nilPairs = cfg.nilPairs + 1
            else
                cfg.numberPairs = cfg.numberPairs + 1
            end
            if code(okValues, predictedValues) == 1 or code(okPredicted, predictedState) == 1 then
                cfg.predictedSecret = cfg.predictedSecret + 1
            end
            local row = cfg.rows
            if row < MAX_ROWS then
                row = row + 1
                cfg.rows = row
                cols.t[row], cols.unit[row], cols.mob[row] = t, u, m
                cols.pct[row], cols.situation[row] = pct, status
            else
                cfg.dropped = cfg.dropped + 1
            end
        end
    end
    local finished = clock()
    if started and finished then
        cfg.times[#cfg.times + 1] = finished - started
    end
    cfg.offset = (cfg.offset + cfg.units) % unitCount
end

--- Units, mobs, context and frame rate, once a second, outside the timed part.
local function refresh(cfg, t)
    cfg.refreshedAt = t
    cfg.unitList = perfUnits()
    cfg.mobList, cfg.mobsFound = perfMobs(cfg.mobs)
    invalidateContext()
    local key, contextCode, combat = currentContext()
    cfg.key, cfg.code, cfg.combat = key, contextCode, combat
    local fps = frameRate()
    if fps and cfg.ticks > 0 then
        cfg.fpsSum, cfg.fpsCount = cfg.fpsSum + fps, cfg.fpsCount + 1
        cfg.fpsMin = math.min(cfg.fpsMin or fps, fps)
    end
end

local function stopTimers()
    if perf and perf.ticker then
        local ticker = perf.ticker
        perf.ticker = nil
        pcall(function()
            ticker:Cancel()
        end)
    end
    Probe.Cancel("P10-watchdog")
    Probe.Cancel("P10-next")
end

--- Ends the run (finished, stopped or failed): nothing of it keeps running.
local function endRun(reason)
    if not perf then
        return
    end
    stopTimers()
    Probe.Cancel("P10-memory")
    local done, total = perf.done, #perf.queue
    perf = nil
    logMemory("at the end of the run")
    out(string.format("P10 run %s: %d of %d configurations measured", reason, done, total))
    Probe:Run("P10")
end

local function runKey(hz, units, mobs)
    return string.format("%dHz x %d units x %d mobs", hz, units, mobs)
end

local function resultLine(r)
    return string.format("%s [%s]: %d ticks in %.0f s (%d expected); ms per tick median %s, p95 %s, max %s; %s ms " ..
        "per second; samples %d (dropped %d), retained %s KB/min (addon; Lua %s), gross %s KB/min (addon; " ..
        "Lua %s); FPS before %s, during %s (min %s); readings number %d, nil %d, secret %d, error %d, " ..
        "predicted secret %d; ticks in combat %d, in a raid fight %d, units repeated %d, no hostile mob %d, " ..
        "fewer mobs %d; watch %s%s",
        runKey(r.hz, r.units, r.mobs), r.kind, r.ticks, r.seconds, r.expected, num(r.median, "%.3f"),
        num(r.p95, "%.3f"), num(r.max, "%.3f"), num(r.perSecond, "%.3f"), r.rows, r.dropped,
        num(r.retained, "%.0f"), num(r.retainedLua, "%.0f"), num(r.gross, "%.0f"), num(r.grossLua, "%.0f"),
        num(r.fpsBefore, "%.0f"), num(r.fps, "%.0f"), num(r.fpsMin, "%.0f"), r.numberPairs, r.nilPairs, r.secretPairs,
        r.errorPairs, r.predictedSecret, r.combatTicks, r.raidTicks, r.rotatedTicks, r.noMobTicks, r.fewMobTicks,
        r.watch, r.stopped and ("; " .. r.stopped) or "")
end

local nextConfig

--- Closes the configuration in progress: figures, memory of its samples (a full garbage collection with the samples
--- and one without them, outside any timed tick: a short stutter), saved result, then the next one. `stopped` says why
--- it ended early (it is then left out of the verdict); `abort` ends the whole run.
local function finishConfig(stopped, abort)
    local run = perf
    local cfg = run and run.cfg
    if not cfg then
        return
    end
    run.cfg = nil
    stopTimers()
    local seconds = (now() or cfg.startedAt) - cfg.startedAt
    local addon, lua = memoryKB()
    local function perMinute(after, before)
        if after and before and seconds > 0 then
            return (after - before) * 60 / seconds
        end
    end
    local gross, grossLua = perMinute(addon, cfg.addonBefore), perMinute(lua, cfg.luaBefore)
    Call(rawget(_G, "collectgarbage"), "collect")
    local withSamples, withSamplesLua = memoryKB()
    cfg.cols = nil
    local collected = Call(rawget(_G, "collectgarbage"), "collect")
    local without, withoutLua = memoryKB()
    local total, count = 0, #cfg.times
    for _, v in ipairs(cfg.times) do
        total = total + v
    end
    local middle = median(cfg.times) -- sorts cfg.times
    local r = {
        hz = cfg.hz, units = cfg.units, mobs = cfg.mobs, seconds = seconds, ticks = cfg.ticks,
        expected = cfg.hz * PERF_SECONDS, median = round3(middle),
        p95 = count > 0 and round3(cfg.times[math.ceil(count * 0.95)]) or nil,
        max = count > 0 and round3(cfg.times[count]) or nil,
        perSecond = (count > 0 and seconds > 0) and round3(total / seconds) or nil,
        rows = cfg.rows, dropped = cfg.dropped, gross = gross, grossLua = grossLua,
        retained = collected and perMinute(withSamples, without) or nil,
        retainedLua = collected and perMinute(withSamplesLua, withoutLua) or nil,
        fpsBefore = cfg.fpsBefore, fps = cfg.fpsCount > 0 and (cfg.fpsSum / cfg.fpsCount) or nil, fpsMin = cfg.fpsMin,
        numberPairs = cfg.numberPairs, nilPairs = cfg.nilPairs, secretPairs = cfg.secretPairs,
        errorPairs = cfg.errorPairs, predictedSecret = cfg.predictedSecret, combatTicks = cfg.combatTicks,
        raidTicks = cfg.raidTicks, rotatedTicks = cfg.rotatedTicks, noMobTicks = cfg.noMobTicks,
        fewMobTicks = cfg.fewMobTicks, watch = watching() and "on" or "off", stopped = stopped,
        -- Real only when every tick read distinct units and mobs in a raid fight (SPEC-08 P10); else simulated.
        kind = (cfg.ticks > 0 and cfg.realTicks == cfg.ticks) and "raid fight" or "simulated",
        context = cfg.key,
    }
    if r.ticks > 0 then
        keep(sub(sub(store("p10"), "runs"), runKey(r.hz, r.units, r.mobs)), r, KEEP_RUNS)
        run.done = run.done + 1
    end
    Probe:Log("P10", resultLine(r) .. " [" .. tostring(r.context) .. "]")
    out(string.format("P10 %s [%s]: p95 %s ms per tick, %s ms per second, %s KB of samples per minute",
        runKey(r.hz, r.units, r.mobs), r.kind, num(r.p95, "%.3f"), num(r.perSecond, "%.3f"), num(r.retained, "%.0f")))
    if abort then
        endRun("stopped (" .. stopped .. ")")
        return
    end
    nextConfig()
end

local function onTick()
    local run = perf
    local cfg = run and run.cfg
    if not cfg then
        return
    end
    local t = now()
    if not t then
        finishConfig("GetTime failed", true)
        return
    end
    if t - cfg.refreshedAt >= 1 then
        refresh(cfg, t)
    end
    cfg.ticks = cfg.ticks + 1
    if cfg.combat then
        cfg.combatTicks = cfg.combatTicks + 1
    end
    local raidFight = cfg.code == "raid" and cfg.combat
    if raidFight then
        cfg.raidTicks = cfg.raidTicks + 1
    end
    if #cfg.unitList < cfg.units then
        cfg.rotatedTicks = cfg.rotatedTicks + 1
    end
    if cfg.mobsFound == 0 then
        cfg.noMobTicks = cfg.noMobTicks + 1
    elseif cfg.mobsFound < cfg.mobs then
        cfg.fewMobTicks = cfg.fewMobTicks + 1
    end
    if raidFight and #cfg.unitList >= cfg.units and cfg.mobsFound >= cfg.mobs then
        cfg.realTicks = cfg.realTicks + 1
    end
    sampleTick(cfg, round3(t - cfg.startedAt))
    if t - cfg.startedAt >= PERF_SECONDS or cfg.ticks >= cfg.iterations then
        finishConfig()
    end
end

local function startConfig()
    local run = perf
    if not run then
        return
    end
    local entry = run.queue[run.index]
    local t = now()
    local newTicker = API("C_Timer", "NewTicker")
    if not t or type(newTicker) ~= "function" then
        Probe:Log("P10", "no ticker: GetTime or C_Timer.NewTicker missing")
        endRun("failed (no GetTime or C_Timer.NewTicker)")
        return
    end
    local cfg = {
        hz = entry.hz, units = entry.units, mobs = entry.mobs, startedAt = t, ticks = 0, offset = 0, rows = 0,
        dropped = 0, times = {}, cols = { t = {}, unit = {}, mob = {}, pct = {}, situation = {} },
        numberPairs = 0, nilPairs = 0, secretPairs = 0, errorPairs = 0, predictedSecret = 0, combatTicks = 0,
        raidTicks = 0, realTicks = 0, rotatedTicks = 0, noMobTicks = 0, fewMobTicks = 0, fpsSum = 0, fpsCount = 0,
        -- The ticker stops by itself even if nothing else does.
        iterations = entry.hz * (PERF_SECONDS + 5),
        fpsBefore = frameRate(),
    }
    refresh(cfg, t)
    cfg.addonBefore, cfg.luaBefore = memoryKB()
    run.cfg = cfg
    local ok, ticker = Call(newTicker, 1 / cfg.hz, function()
        local fine, err = pcall(onTick)
        if not fine then
            Probe:Log("errors", "perf tick: " .. errText(err))
            endRun("failed (error in a tick)")
        end
    end, cfg.iterations)
    if not ok then
        Probe:Log("P10", "C_Timer.NewTicker error: " .. tostring(ticker))
        endRun("failed (C_Timer.NewTicker error)")
        return
    end
    run.ticker = ticker
    -- A ticker that stops delivering must not leave the configuration open.
    Probe.After("P10-watchdog", PERF_SECONDS + 5, function()
        finishConfig("the ticker stopped delivering")
    end)
end

nextConfig = function()
    local run = perf
    if not run then
        return
    end
    run.index = run.index + 1
    if not run.queue[run.index] then
        endRun("finished")
        return
    end
    if not Probe.After("P10-next", PERF_PAUSE, startConfig) then
        endRun("failed (no timer)")
    end
end

local PERF_USAGE = "usage: /atwp perf [hz 1-20] [units 1-40] [mobs 1-8], or /atwp perf stop"

--- A whole number of the command between 1 and `max`: nil when absent, false when not valid.
local function argument(word, max)
    if not word then
        return nil
    end
    local v = tonumber(word)
    if not v or v ~= math.floor(v) or v < 1 or v > max then
        return false
    end
    return v
end

Probe.commands.perf = function(arg, rest)
    local words = {}
    for word in (arg .. " " .. rest):gmatch("%S+") do
        words[#words + 1] = word:lower()
    end
    if words[1] == "stop" then
        if not perf then
            out("P10: no run in progress")
        elseif perf.cfg then
            finishConfig("by /atwp perf stop", true)
        else
            endRun("stopped (by /atwp perf stop)")
        end
        return
    end
    if perf then
        out("P10: a run is in progress (/atwp perf stop to stop it)")
        return
    end
    local hz, units, mobs = argument(words[1], MAX_HZ), argument(words[2], MAX_UNITS), argument(words[3], MAX_MOBS)
    if hz == false or units == false or mobs == false or #words > 3 then
        out(PERF_USAGE)
        return
    end
    local queue = {}
    for _, u in ipairs(units and { units } or PERF_UNITS) do
        for _, rate in ipairs(hz and { hz } or PERF_RATES) do
            queue[#queue + 1] = { hz = rate, units = u, mobs = mobs or 1 }
        end
    end
    perf = { queue = queue, index = 0, done = 0 }
    stamp("P10")
    logMemory("at the start of the run")
    Probe.Every("P10-memory", 60, function()
        logMemory("during the run")
    end)
    out(string.format("P10: %d configurations of %d s each, about %d s; play normally, /atwp perf stop to stop%s",
        #queue, PERF_SECONDS, #queue * (PERF_SECONDS + PERF_PAUSE),
        watching() and " (the watch is on and adds its own load: /atwp watch off for a cleaner measure)" or ""))
    nextConfig()
end

local function withinBudget(r)
    return r.p95 ~= nil and r.perSecond ~= nil and r.p95 <= BUDGET_P95 and r.perSecond <= BUDGET_SECOND
end

--- Per configuration with timed ticks, the latest raid fight result, else the latest simulated one.
local function bestRuns()
    local list = {}
    local runs = store("p10").runs or {}
    for _, key in ipairs(sortedKeys(runs)) do
        local best
        for _, r in ipairs(runs[key]) do
            if r.p95 and not r.stopped and (not best or r.kind == "raid fight" or best.kind ~= "raid fight") then
                best = r
            end
        end
        if best then
            list[#list + 1] = best
        end
    end
    table.sort(list, function(a, b)
        if a.mobs ~= b.mobs then
            return a.mobs < b.mobs
        end
        if a.units ~= b.units then
            return a.units < b.units
        end
        return a.hz < b.hz
    end)
    return list
end

local function short(r)
    return string.format("%d Hz x %d units: p95 %s ms, %s ms/s, %s KB/min, %s, %s", r.hz, r.units,
        num(r.p95, "%.3f"), num(r.perSecond, "%.3f"), num(r.retained, "%.0f"), r.kind,
        withinBudget(r) and "within" or "over")
end

local function p10Verdict()
    local parts, reference, low, fallback, mostUnits = {}, nil, nil, nil, nil
    for _, r in ipairs(bestRuns()) do
        if r.mobs == 1 then
            parts[#parts + 1] = short(r)
            if r.hz == 5 and r.units == 40 then
                reference = r
            elseif r.hz == 2 and r.units == 5 then
                low = r
            end
            if r.hz == 2 and withinBudget(r) then
                if r.units == 40 then
                    fallback = r
                end
                if not mostUnits or r.units > mostUnits.units then
                    mostUnits = r
                end
            end
        end
    end
    if #parts == 0 then
        return "todo", "nothing measured yet: /atwp perf (in a raid fight if possible)"
    end
    local verdict, summary
    if reference and withinBudget(reference) then
        verdict = "supported"
        summary = "40 units at 5 Hz within budget; proposed default 5 Hz (" .. short(reference) .. ")"
    elseif low and not withinBudget(low) then
        verdict = "not supported"
        summary = "even 5 units at 2 Hz over budget; no default rate to propose (" .. short(low) .. ")"
    elseif reference and mostUnits then
        verdict = "partial"
        if fallback then
            summary = "40 units at 5 Hz over budget; proposed default 2 Hz (" .. short(fallback) .. ")"
        else
            summary = "40 units at 5 Hz over budget; proposed default 2 Hz limited to " .. mostUnits.units ..
                " units (" .. short(mostUnits) .. ")"
        end
    else
        verdict = "todo"
        summary = "40 units at 5 Hz and, if that is over budget, 5 units at 2 Hz still to be measured"
    end
    if reference and reference.kind ~= "raid fight" then
        summary = summary .. "; 40 units simulated: repeat in a raid fight if you can"
    end
    return verdict, string.format("%s. Budget p95 <= %d ms per tick and <= %d ms per second. %s", summary,
        BUDGET_P95, BUDGET_SECOND, table.concat(parts, " | "))
end

-- Only summarises what was measured: a run starts only with /atwp perf.
Probe:Register("P10", "Cost of sampling: time per tick and memory", function()
    if perf then
        out("P10: a run is still in progress")
    end
    return p10Verdict()
end)

----------------------------------------------------------------------------------------------------------------------
-- P11: restrictions, blocked actions and errors
----------------------------------------------------------------------------------------------------------------------

local THREAT_FUNCTIONS = { "UnitDetailedThreatSituation", "UnitThreatSituation", "UnitThreatPercentageOfLead",
    "UnitThreatLeadSituation" }
local THREAT_EVENTS = { "UNIT_THREAT_LIST_UPDATE", "UNIT_THREAT_SITUATION_UPDATE" }
local BURST = 1000
local TICKS = 10
local MAX_ERROR_TEXTS = 30
local KEEP_RESULTS = 10

local loaded, counting = false, false -- errors count once the saved variables are loaded, never recursively
local earlyErrors = {}
local registrationAt -- GetTime of the last register/unregister round
local regFrame
local ticker11       -- the P11 ticker in progress

local function p11Stats(force)
    if force then
        invalidateContext()
    end
    local key, contextCode, combat = currentContext()
    return statsFor("p11", key, contextCode, combat), key
end

local function countError(fn, text)
    local source = fn == nil and "probe" or "other API"
    for _, name in ipairs(THREAT_FUNCTIONS) do
        if fn ~= nil and rawget(_G, name) == fn then
            source = name
        end
    end
    local st, key = p11Stats()
    bump(sub(st, "errors"), source)
    local texts = sub(store("p11"), "errorTexts")
    text = tostring(text):sub(1, 160)
    bumpCapped(texts, text, MAX_ERROR_TEXTS)
    if texts[text] == 1 then -- the first time a text is seen (and kept)
        Probe:Log("P11", string.format("error [%s] %s: %s", key, source, text))
    end
end

local function onError(fn, text)
    if counting then
        return
    end
    if not loaded then
        keep(earlyErrors, { fn = fn, text = text }, 20)
        return
    end
    counting = true
    pcall(countError, fn, text)
    counting = false
end
table.insert(Probe.errorHooks, onError)

-- Blocked and forbidden actions: the function and whether the probe was blamed; never another addon's name.
-- `list` is "blocked" or "forbidden".
local function onAction(list, isTainted, fnName)
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
        name = (type(fnName) == "string" and fnName:match("^[%w_%.:%(%)]+$")) and
            Probe.Scrub(fnName:sub(1, 64)) or "other"
    end
    local st, key = p11Stats(true)
    local counts = sub(st, list)
    local entry = who .. " " .. name
    bumpCapped(counts, entry, 20)
    -- Only a blocked threat call, or a block during P11's own event registration round, touches what the addon needs
    -- (the combat log registration of P7 is expected to be refused and is only counted).
    local t = now()
    local duringRound = registrationAt and t and t - registrationAt <= 2
    if who == "probe" and (name:find("Threat") or duringRound) then
        bumpCapped(sub(st, "threatBlocks"), list .. " " .. name, 10)
    end
    local n = counts[entry] or 0
    if n == 1 or n % 50 == 0 then
        Probe:Log("P11", string.format("%s [%s] by %s: %s (%d)", list, key, who, name, n))
    end
end
Probe:On("ADDON_ACTION_BLOCKED", function(isTainted, fnName)
    onAction("blocked", isTainted, fnName)
end)
Probe:On("ADDON_ACTION_FORBIDDEN", function(isTainted, fnName)
    onAction("forbidden", isTainted, fnName)
end)

--- The name of a value of an Enum table looked up at run time; the number itself when it has none.
local function enumName(enum, v)
    if IsSecret(v) then
        return "secret"
    end
    local t = API("Enum", enum)
    if type(t) == "table" then
        for name, value in pairs(t) do
            if value == v then
                return tostring(name)
            end
        end
    end
    return type(v) == "number" and tostring(v) or type(v)
end

--- The restriction types active now and the combat lockdown, counted in the context.
local function snapshot()
    local st = p11Stats(true)
    local active = sub(st, "active")
    local types = API("Enum", "AddOnRestrictionType")
    local isActive = API("C_RestrictedActions", "IsAddOnRestrictionActive")
    if type(types) == "table" and type(isActive) == "function" then
        for name, value in pairs(types) do
            bumpCapped(active, tostring(name) .. " " .. boolText(Call(isActive, value)), 40)
        end
    else
        bump(active, "unavailable")
    end
    bump(sub(st, "lockdown"), boolText(Call(API("C_RestrictedActions", "InCombatLockdown"))))
end

Probe:On("ADDON_RESTRICTION_STATE_CHANGED", function(restrictionType, state)
    local st, key = p11Stats(true)
    local entry = enumName("AddOnRestrictionType", restrictionType) .. " " ..
        enumName("AddOnRestrictionState", state)
    bumpCapped(sub(st, "restrictionEvents"), entry, 20)
    Probe:Log("P11", string.format("restriction state changed [%s]: %s", key, entry))
end)
Probe:On("PLAYER_REGEN_DISABLED", snapshot)
Probe:On("PLAYER_REGEN_ENABLED", snapshot)
Probe:On("ENCOUNTER_START", snapshot)
Probe:On("PLAYER_ENTERING_WORLD", snapshot)

--- One threat reading as a signature (number and kind of the values), its class (answered, nil, secret or error) and,
--- for an error, its scrubbed text.
local function signature(ok, ...)
    if not ok then
        return "error", "error", errText((...)):sub(1, 160)
    end
    local n = select("#", ...)
    local text, class = tostring(n), "nil"
    for i = 1, n do
        local kind = Describe((select(i, ...)))
        text = text .. " " .. kind
        if kind == "secret" then
            class = "secret"
        elseif kind ~= "nil" and class == "nil" then
            class = "answered"
        end
    end
    return text, class
end

--- 1000 readings of the player on the target in one frame (SPEC-08 P11): do the answers degrade? Not in an encounter.
local function burst(st, key)
    local c = Probe.Context()
    local encounter = flag(Call(API("C_InstanceEncounter", "IsEncounterInProgress")))
    if c.encounter == "yes" or encounter == true then
        Probe:Log("P11", "burst skipped [" .. key .. "]: an encounter is active")
        return "burst skipped (encounter)"
    end
    local fn = rawget(_G, "UnitDetailedThreatSituation")
    if type(fn) ~= "function" then
        bump(sub(st, "errors"), "UnitDetailedThreatSituation")
        return "burst impossible (UnitDetailedThreatSituation missing)"
    end
    local r = { answered = 0, ["nil"] = 0, secret = 0, error = 0, differ = 0,
        -- Only a fight with a hostile target can show a degradation.
        meaningful = inCombat() and hostile("target"), restrictions = tostring(c.restrictions) }
    r.baseline = (signature(pcall(fn, "player", "target")))
    local started = clock()
    for i = 1, BURST do
        local text, class, err = signature(pcall(fn, "player", "target"))
        r[class] = r[class] + 1
        r.errorText = r.errorText or err
        if text ~= r.baseline then
            r.differ = r.differ + 1
            r.firstDiffer = r.firstDiffer or i
        end
    end
    local finished = clock()
    r.ms = (started and finished) and round3(finished - started) or nil
    keep(sub(st, "bursts"), r, KEEP_RESULTS)
    Probe.After("P11-after-burst", 1, function()
        local text = signature(pcall(fn, "player", "target"))
        r.after = text == r.baseline and "same" or text
        Probe:Log("P11", "one second after the burst [" .. key .. "]: " .. r.after)
    end)
    local line = string.format("burst of %d [%s]%s: answered %d, nil %d, secret %d, error %d, differ %d (first %s), " ..
        "baseline %s, %s ms%s", BURST, key, r.meaningful and "" or " (not in a fight with a hostile target)",
        r.answered, r["nil"], r.secret, r.error, r.differ, tostring(r.firstDiffer or "-"), r.baseline, num(r.ms),
        r.errorText and (", " .. r.errorText) or "")
    Probe:Log("P11", line)
    return line
end

--- Registers and unregisters the two threat events on a frame of the probe's own (in or out of combat).
local function registration(st, key)
    if not regFrame then
        local ok, f = Call(CreateFrame, "Frame")
        if not ok or IsSecret(f) or type(f) ~= "table" then
            return "no frame"
        end
        regFrame = f
    end
    local f = regFrame
    registrationAt = now()
    local failed = 0
    for _, event in ipairs(THREAT_EVENTS) do
        local okOn = Call(f.RegisterEvent, f, event)
        local on = boolText(Call(f.IsEventRegistered, f, event))
        local okOff = Call(f.UnregisterEvent, f, event)
        local off = boolText(Call(f.IsEventRegistered, f, event))
        local text = string.format("register %s (registered %s), unregister %s (registered %s)",
            okOn and "ok" or "error", on, okOff and "ok" or "error", off)
        bumpCapped(sub(st, "registration"), event .. ": " .. text, 20)
        if not okOn or on == "no" or not okOff or off == "yes" then
            failed = failed + 1
            bump(st, "registrationFailed")
        end
        Probe:Log("P11", string.format("[%s] %s: %s", key, event, text))
    end
    return failed == 0 and "event registration ok" or ("event registration failed for " .. failed)
end

local function finishTicker()
    local t = ticker11
    if not t then
        return
    end
    ticker11 = nil
    pcall(function()
        t.handle:Cancel()
    end)
    local r = { ticks = t.ticks, expected = TICKS, inCombat = t.inCombat }
    local st = statsFor("p11", t.key, t.code, t.combat)
    keep(sub(st, "tickers"), r, KEEP_RESULTS)
    Probe:Log("P11", string.format("ticker started in [%s]: %d of %d ticks, %d in combat", t.key, r.ticks, r.expected,
        r.inCombat))
end

--- A C_Timer ticker of 10 ticks, one a second: does it keep ticking in combat? It stops by itself.
local function startTicker(key, contextCode, combat)
    if ticker11 then
        return "ticker still running"
    end
    local newTicker = API("C_Timer", "NewTicker")
    local t = { ticks = 0, inCombat = 0, key = key, code = contextCode, combat = combat }
    local ok, handle = Call(newTicker, 1, function()
        t.ticks = t.ticks + 1
        if inCombat() then
            t.inCombat = t.inCombat + 1
        end
    end, TICKS)
    if not ok then
        Probe:Log("P11", "C_Timer.NewTicker: " .. tostring(handle))
        return "no ticker (" .. tostring(handle) .. ")"
    end
    t.handle = handle
    ticker11 = t
    Probe.After("P11-ticker", TICKS + 2.5, finishTicker)
    return "ticker started (" .. TICKS .. " s)"
end

--- All the P11 counters as one verdict (SPEC-08 P11) and its details.
local function p11Verdict()
    local stats = store("p11").stats or {}
    local fought, hurt, limited, restricted, blocked, threatErrors = {}, {}, {}, {}, {}, {}
    local probeBlocks, otherBlocks, errors = 0, 0, 0
    for _, key in ipairs(sortedKeys(stats)) do
        local st = stats[key]
        -- A problem counts as "where it matters" in a fight of an MVP context (SPEC-08 section 1.4).
        local relevant = st.code == "solo-combat"
        for _, c in ipairs(MVP_CONTEXTS) do
            relevant = relevant or (st.code == c and st.combat)
        end
        local function problem(text)
            local list = relevant and hurt or limited
            list[#list + 1] = key .. " " .. text
        end
        local function limit(text)
            limited[#limited + 1] = key .. " " .. text
        end
        for _, list in ipairs({ "blocked", "forbidden" }) do
            for entry, n in pairs(st[list] or {}) do
                if entry:find("^probe ") then
                    probeBlocks = probeBlocks + n
                    blocked[entry:sub(7)] = true
                else
                    otherBlocks = otherBlocks + n
                end
            end
        end
        for _, entry in ipairs(sortedKeys(st.threatBlocks)) do
            problem(entry)
        end
        for source, n in pairs(st.errors or {}) do
            errors = errors + n
            if source:find("Threat") then
                threatErrors[#threatErrors + 1] = key .. " " .. source .. " " .. n
            end
        end
        local active = {}
        for _, entry in ipairs(sortedKeys(st.active)) do
            local name = entry:match("^(.+) yes$")
            if name then
                active[#active + 1] = name
            end
        end
        if #active > 0 then
            restricted[#restricted + 1] = key .. " " .. table.concat(active, ",")
        end
        for _, b in ipairs(st.bursts or {}) do
            local restrictedNil = b["nil"] > 0 and b.restrictions ~= "none" and b.restrictions ~= "unknown"
            if b.error > 0 then
                problem("burst errors " .. b.error)
            elseif b.meaningful then
                if b.secret > 0 then
                    limit("burst secret " .. b.secret)
                elseif restrictedNil then
                    limit("burst nil " .. b["nil"] .. " with " .. b.restrictions)
                end
                if b.differ > 0 then
                    limit("burst answers changed " .. b.differ .. " times")
                end
                if relevant and (b.answered > 0 or b.secret > 0 or restrictedNil) then
                    fought[st.code] = true
                end
            end
        end
        for _, t in ipairs(st.tickers or {}) do
            if t.ticks < t.expected then
                limit("ticker " .. t.ticks .. "/" .. t.expected)
            end
        end
        if (st.registrationFailed or 0) > 0 then
            limit("event registration failed " .. st.registrationFailed)
        end
    end
    local missing = {}
    for _, c in ipairs(MVP_CONTEXTS) do
        if not fought[c] then
            missing[#missing + 1] = c
        end
    end
    local names = {}
    for name in pairs(blocked) do
        names[#names + 1] = name
    end
    table.sort(names)
    table.sort(threatErrors)
    local details = string.format("blocked or forbidden: probe %d (%s), others %d; errors %d (threat " ..
        "functions: %s); restrictions active: %s; answered bursts in a fight missing for: %s", probeBlocks,
        #names > 0 and table.concat(names, ", ") or "-", otherBlocks, errors,
        #threatErrors > 0 and table.concat(threatErrors, "; ") or "none",
        #restricted > 0 and table.concat(restricted, "; ") or "none",
        #missing > 0 and table.concat(missing, ", ") or "none")
    if #hurt > 0 then
        return "not supported", "threat calls blocked or failing: " .. table.concat(hurt, "; ") .. ". " .. details
    end
    if #limited > 0 then
        return "partial", "limits seen: " .. table.concat(limited, "; ") .. ". " .. details
    end
    if #threatErrors > 0 then
        -- P2 also tries the GUID form, which a client may refuse: M0.7 reads the error texts before deciding.
        return "todo", "threat functions raised errors, to be read in the log (P2 also tries the GUID form). " ..
            details
    end
    if #missing > 0 then
        return "todo", "no problem so far; /atwp run P11 in a fight in each context. " .. details
    end
    return "supported", "no block, error or limit on the threat calls. " .. details
end

Probe:Register("P11", "Restrictions: blocked actions, errors, limits", function()
    snapshot()
    local st, key = p11Stats(true)
    local _, contextCode, combat = currentContext()
    local burstText = burst(st, key)
    local registrationText = registration(st, key)
    local tickerText = startTicker(key, contextCode, combat)
    out(string.format("P11 [%s]: %s; %s; %s", key, burstText, registrationText, tickerText))
    return p11Verdict()
end)

----------------------------------------------------------------------------------------------------------------------
-- P12: /reload and logout during a fight
----------------------------------------------------------------------------------------------------------------------

local P12_SAMPLES = 600 -- compact samples kept (10 minutes at one a second)
local P12_TRIALS = 10
local pending           -- the trial analysed at this load, while its after-load checks run (memory only)
local loadedAt

local function serverTime()
    local ok, t = Call(rawget(_G, "GetServerTime"))
    return ok and number(t) or -1
end

local function p12Store()
    return store("p12")
end

--- One compact sample { counter, server time, state, scaled percentage } in the saved variables, in combat only.
local function p12Sample()
    local current = p12Store().current
    if not current then
        Probe.Cancel("P12")
        return
    end
    if not inCombat() then
        return
    end
    local ok, _, status, scaled = Call(rawget(_G, "UnitDetailedThreatSituation"), "player", "target")
    current.written = current.written + 1
    keep(current.samples, { current.written, serverTime(), code(ok, status), code(ok, scaled) }, P12_SAMPLES)
end

local function p12Start()
    if p12Store().current then
        Probe.Every("P12", 1, p12Sample, 0)
    end
end

Probe:On("PLAYER_REGEN_DISABLED", function()
    if pending and not pending.after.regenAgain then
        local t = now()
        pending.after.regenAgain = (t and loadedAt) and round3(t - loadedAt) or "yes"
        Probe:Log("P12", "PLAYER_REGEN_DISABLED again after the load, at " .. tostring(pending.after.regenAgain) ..
            " s")
    end
    p12Start()
end)
Probe:On("PLAYER_REGEN_ENABLED", function()
    Probe.Cancel("P12")
end)

-- The final stamp: written at logout and at /reload, just before the saved variables.
Probe:On("PLAYER_LOGOUT", function()
    local current = p12Store().current
    if current then
        current.final = {
            counter = current.written, time = serverTime(),
            combat = boolText(Call(UnitAffectingCombat, "player")),
            lockdown = boolText(Call(API("C_RestrictedActions", "InCombatLockdown"))),
        }
    end
end)

--- Reads the combat state and the threat on the target after the load.
local function p12Read(label)
    local trial = pending
    if not trial then
        return
    end
    local t = now()
    local text, class = signature(Call(rawget(_G, "UnitDetailedThreatSituation"), "player", "target"))
    local r = {
        label = label, t = (t and loadedAt) and round3(t - loadedAt) or 0,
        combat = boolText(Call(UnitAffectingCombat, "player")),
        lockdown = boolText(Call(API("C_RestrictedActions", "InCombatLockdown"))),
        hostile = hostile("target") and "yes" or "no", threat = class,
    }
    keep(trial.after.reads, r, 12)
    if r.combat == "yes" or r.combat == "no" then
        trial.after.combatReadable = true
    end
    if r.combat == "yes" and r.hostile == "yes" then
        trial.after.fightSeen = true
        if (class == "answered" or class == "secret") and not trial.after.resumed then
            trial.after.resumed = r.t
        end
    end
    Probe:Log("P12", string.format("after the load (%s, %s s): combat %s, lockdown %s, hostile target %s, threat %s " ..
        "(%s)", label, tostring(r.t), r.combat, r.lockdown, r.hostile, class, text))
end

local function p12Finish()
    p12Read("10 s")
    if pending then
        pending.after.done = true
        pending = nil
        out("P12: after-load readings done, /atwp run P12 shows the trial")
    end
end

--- At the next load: what is left of the buffer? Moves it to the trials and disarms it.
local function p12Load()
    local s = p12Store()
    local current = s.current
    if not current then
        return
    end
    if (current.written or 0) == 0 then
        current.final = nil
        out("P12: buffer still armed, no sample yet (if you reloaded during a fight, /atwp note P12 lost)")
        return
    end
    local samples = current.samples or {}
    local last = samples[#samples]
    local loadTime = serverTime()
    local final = current.final
    local trial = {
        written = current.written, found = #samples, lastCounter = last and last[1],
        lastTime = last and last[2], final = final, loadTime = loadTime,
        gap = (last and loadTime >= 0 and last[2] >= 0) and (loadTime - last[2]) or nil,
        finalGap = (last and final and final.time >= 0 and last[2] >= 0) and (final.time - last[2]) or nil,
        tail = {}, after = { reads = {} },
    }
    for i = math.max(1, #samples - 4), #samples do
        trial.tail[#trial.tail + 1] = samples[i]
    end
    s.current = nil
    s.unreported = true
    s.trials = s.trials or {}
    keep(s.trials, trial, P12_TRIALS)
    pending = trial
    loadedAt = now()
    Probe:Log("P12", string.format("load: %d samples written, %d found, last counter %s, %s s before the load; " ..
        "final stamp %s", trial.written, trial.found, tostring(trial.lastCounter), tostring(trial.gap or "?"),
        final and string.format("yes (counter %d, combat %s, lockdown %s, %s s after the last sample)",
            final.counter, final.combat, final.lockdown, tostring(trial.finalGap or "?")) or "missing"))
    out(string.format("P12: %d of %d samples found, final stamp %s; /atwp run P12 in a few seconds", trial.found,
        trial.written, final and "present" or "missing"))
end

Probe:On("ADDON_LOADED", function(name)
    if name ~= ADDON_NAME then
        return
    end
    loaded = true
    local early = earlyErrors
    earlyErrors = {}
    for _, e in ipairs(early) do
        onError(e.fn, e.text)
    end
    p12Load()
end)
Probe:On("PLAYER_LOGIN", function()
    p12Read("PLAYER_LOGIN")
end)
Probe:On("PLAYER_ENTERING_WORLD", function(isInitialLogin, isReloadingUi)
    if pending and not pending.kind then
        if flag(true, isReloadingUi) then
            pending.kind = "reload"
        elseif flag(true, isInitialLogin) then
            pending.kind = "login"
        else
            pending.kind = "unknown"
        end
        Probe:Log("P12", "this load is a " .. pending.kind)
        p12Read("PLAYER_ENTERING_WORLD")
        for _, delay in ipairs({ 1, 3, 5 }) do
            Probe.After("P12-after" .. delay, delay, function()
                p12Read(delay .. " s")
            end)
        end
        Probe.After("P12-after10", 10, p12Finish)
    end
end)

--- Everything that was in the buffer at the end is there after the load.
local function complete(trial)
    local final = trial.final
    return final ~= nil and trial.found == math.min(trial.written, P12_SAMPLES) and final.counter == trial.written and
        trial.lastCounter == trial.written and
        (final.combat ~= "yes" or (trial.finalGap ~= nil and trial.finalGap <= 2))
end

local function trialText(i, trial)
    local final = trial.final
    return string.format("trial %d (%s): %d/%d samples, final stamp %s, load %s s after the last sample, " ..
        "REGEN_DISABLED again %s, combat readable %s, threat resumed %s", i, tostring(trial.kind or "?"),
        trial.found, trial.written, final and ("combat " .. final.combat .. ", " .. tostring(trial.finalGap or "?") ..
            " s after the last sample") or "missing", tostring(trial.gap or "?"),
        trial.after.regenAgain and (tostring(trial.after.regenAgain) .. " s") or "no",
        trial.after.combatReadable and "yes" or "no",
        trial.after.resumed and ("after " .. tostring(trial.after.resumed) .. " s") or
        (trial.after.fightSeen and "no" or "no fight to read"))
end

local function p12Verdict()
    local s = p12Store()
    local parts, problems = {}, {}
    local reloadInFight, logout = false, false
    for i, trial in ipairs(s.trials or {}) do
        parts[#parts + 1] = trialText(i, trial)
        if not complete(trial) then
            problems[#problems + 1] = "trial " .. i .. " incomplete"
        elseif trial.after.done and not trial.after.combatReadable then
            problems[#problems + 1] = "trial " .. i .. " combat state not readable after the load"
        elseif trial.after.done and trial.after.fightSeen and not trial.after.resumed then
            problems[#problems + 1] = "trial " .. i .. " threat not readable after the load"
        end
        if trial.kind == "reload" and trial.final and trial.final.combat == "yes" and trial.after.done then
            reloadInFight = true
        elseif trial.kind == "login" and trial.after.done then
            logout = true
        end
    end
    local list = #parts > 0 and table.concat(parts, " | ") or "no trial yet"
    if (s.lost or 0) > 0 then
        return "not supported", "a reload did not save the buffer (noted " .. s.lost .. " times). " .. list
    end
    if #problems > 0 then
        return "partial", table.concat(problems, "; ") .. ". " .. list
    end
    if reloadInFight and logout then
        return "supported", "everything up to the last tick survived and the fight was readable after. " .. list
    end
    local missing = {}
    if not reloadInFight then
        missing[#missing + 1] = "a /reload during a fight"
    end
    if not logout then
        missing[#missing + 1] = "a logout"
    end
    return "todo", "still needed: " .. table.concat(missing, " and ") .. ". " .. list
end

-- The first run arms a buffer; the run after the reload reports the trial; the next one arms again.
Probe:Register("P12", "Reload and logout during a fight", function()
    local s = p12Store()
    local state
    if s.unreported then
        if pending then
            state = "after-load readings still running, run P12 again in a few seconds"
        else
            s.unreported = nil
            state = "trial reported; run P12 again to arm another one"
        end
    elseif s.current then
        state = "armed, " .. s.current.written .. " samples so far"
        if inCombat() then
            p12Start()
        end
    else
        s.current = { samples = {}, written = 0 }
        if inCombat() then
            p12Start()
        end
        state = "armed a new buffer: engage a mob, /reload (or log out) in the middle of the fight, then run P12 " ..
            "again. If you expected a trial here, the reload lost the buffer: /atwp note P12 lost"
    end
    out("P12: " .. state)
    local verdict, details = p12Verdict()
    return verdict, state .. ". " .. details
end)

table.insert(Probe.noteHooks, function(id, text)
    if id == "P12" and text:lower():find("^%s*lost") then
        local s = p12Store()
        s.lost = (s.lost or 0) + 1
        out("P12: recorded that a reload lost the buffer")
    end
end)

----------------------------------------------------------------------------------------------------------------------
-- Export and reset
----------------------------------------------------------------------------------------------------------------------

table.insert(Probe.exportHooks, function()
    local lines = { "-- P10 per configuration (latest " .. KEEP_RUNS .. " runs)" }
    local p10 = store("p10")
    for _, key in ipairs(sortedKeys(p10.runs)) do
        for _, r in ipairs(p10.runs[key]) do
            lines[#lines + 1] = resultLine(r) .. " [" .. tostring(r.context) .. "]"
        end
    end
    for _, line in ipairs(p10.memory or {}) do
        lines[#lines + 1] = line
    end
    lines[#lines + 1] = "-- P11 per context"
    local p11 = store("p11")
    for _, key in ipairs(sortedKeys(p11.stats)) do
        local st = p11.stats[key]
        lines[#lines + 1] = string.format("%s: blocked %s; forbidden %s; errors %s; restriction events %s; " ..
            "active %s; lockdown %s; registration %s", key, countsText(st.blocked), countsText(st.forbidden),
            countsText(st.errors), countsText(st.restrictionEvents), countsText(st.active), countsText(st.lockdown),
            countsText(st.registration))
        for _, b in ipairs(st.bursts or {}) do
            lines[#lines + 1] = string.format("%s burst%s: answered %d, nil %d, secret %d, error %d, differ %d, " ..
                "baseline %s, after %s, %s ms, restrictions %s", key, b.meaningful and "" or " (no fight)",
                b.answered, b["nil"], b.secret, b.error, b.differ, b.baseline, tostring(b.after or "?"), num(b.ms),
                b.restrictions)
        end
        for _, t in ipairs(st.tickers or {}) do
            lines[#lines + 1] = string.format("%s ticker: %d/%d ticks, %d in combat", key, t.ticks, t.expected,
                t.inCombat)
        end
    end
    for _, text in ipairs(sortedKeys(p11.errorTexts)) do
        lines[#lines + 1] = "error x" .. p11.errorTexts[text] .. ": " .. text
    end
    lines[#lines + 1] = "-- P12 trials"
    local p12 = p12Store()
    for i, trial in ipairs(p12.trials or {}) do
        lines[#lines + 1] = trialText(i, trial)
        local tail = {}
        for _, sample in ipairs(trial.tail or {}) do
            tail[#tail + 1] = table.concat(sample, ",")
        end
        lines[#lines + 1] = "    last samples (counter,time,state,scaled): " .. table.concat(tail, " ; ")
        for _, r in ipairs(trial.after.reads) do
            lines[#lines + 1] = string.format("    %s (%s s): combat %s, lockdown %s, hostile %s, threat %s", r.label,
                tostring(r.t), r.combat, r.lockdown, r.hostile, r.threat)
        end
    end
    lines[#lines + 1] = string.format("buffer %s, noted lost %d", p12.current and
        ("armed with " .. p12.current.written .. " samples") or "not armed", p12.lost or 0)
    return lines
end)

table.insert(Probe.resetHooks, function()
    if perf then
        stopTimers()
        Probe.Cancel("P10-memory")
        perf = nil
        out("P10: run stopped by the reset")
    end
    if ticker11 then
        pcall(function()
            ticker11.handle:Cancel()
        end)
        ticker11 = nil
    end
    Probe.Cancel("P11-ticker")
    Probe.Cancel("P11-after-burst")
    local d = Probe.DB()
    d.p10, d.p11 = nil, nil
    -- An armed P12 buffer is kept: only its trials are cleared.
    local current = d.p12 and d.p12.current
    d.p12 = current and { current = current } or nil
    if current then
        out("P12: the armed buffer is kept")
    end
    pending, registrationAt = nil, nil
    for _, delay in ipairs({ 1, 3, 5, 10 }) do
        Probe.Cancel("P12-after" .. delay)
    end
    invalidateContext()
end)
