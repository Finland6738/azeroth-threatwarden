-- AzTw Probe: throwaway spike addon for Azeroth Threatwarden (milestone M0). Never distributed.
-- Adapted from Azeroth Accord (tools/probe/AzAc_Probe/AzAc_Probe.lua), same owner, GPL-3.0 (ADR 0012).
-- Answers checks P1-P12 (docs/specs/SPEC-08-quality-probe-release.md, section 1) in the real client.
--
-- Lua 5.1. Rules (SPEC-08, PRB-01 to PRB-06):
--   * every game API call goes through pcall (use Probe.Call);
--   * every returned value is tested with issecretvalue before anything else: a secret value is only ever "secret";
--   * no player, guild or realm name and no player GUID is printed or stored: <player n>, <mob n>, <guild>, <realm>;
--   * no network, no addon messages, nothing sent to chat channels, no setting changed.

-- The second value is the table the client shares between the files of this addon (the Checks_*.lua of later steps).
local ADDON_NAME, Probe = ...

Probe.checks, Probe.order = {}, {}
-- commands[name] = function(arg, rest): slash subcommands (the Checks files add theirs).
-- exportHooks: functions returning extra export lines.
Probe.commands, Probe.exportHooks = {}, {}

local PREFIX = "|cff66ccffAzTw Probe:|r "
local VERDICTS = { ["supported"] = true, ["partial"] = true, ["not supported"] = true, ["todo"] = true }
local LOG_LIMIT = 1000

local function out(msg)
    pcall(print, PREFIX .. tostring(msg))
end
Probe.Print = out

----------------------------------------------------------------------------------------------------------------------
-- Secret values and safe calls
----------------------------------------------------------------------------------------------------------------------

--- True when `v` is a secret value. If the test itself fails, the value is treated as secret.
function Probe.IsSecret(v)
    local test = issecretvalue
    if type(test) ~= "function" then
        return false -- no such API in this client: nothing can be secret (P1 records the absence)
    end
    local ok, secret = pcall(test, v)
    if not ok then
        return true
    end
    return secret and true or false
end

--- The value itself, or `fallback` ("secret" by default) when it is secret. Use before comparing or formatting.
function Probe.Plain(v, fallback)
    if Probe.IsSecret(v) then
        if fallback == nil then
            return "secret"
        end
        return fallback
    end
    return v
end

--- Kind of a returned value (SPEC-08 section 1.3): "secret", "nil", "boolean", "number", "string"...; the second
--- result is the readable value of a boolean or of a number (rounded to 0.1). Texts are never returned.
function Probe.Describe(v)
    if Probe.IsSecret(v) then
        return "secret"
    end
    local t = type(v)
    if t == "number" then
        return t, math.floor(v * 10 + 0.5) / 10
    elseif t == "boolean" then
        return t, v
    end
    return t
end

local function errorText(err)
    if Probe.IsSecret(err) then
        return "secret"
    end
    return Probe.Scrub(tostring(err))
end

local function afterCall(ok, ...)
    if ok then
        return true, ...
    end
    return false, errorText((...))
end

--- Safe call of a game API: returns ok, ...results (never raises). The error text is already scrubbed.
function Probe.Call(fn, ...)
    if type(fn) ~= "function" then
        return false, "API missing"
    end
    return afterCall(pcall(fn, ...))
end

--- Field `name` of a global namespace table (looked up at run time, PRB-05); nil when absent.
local function api(namespace, name)
    local t = rawget(_G, namespace)
    if type(t) ~= "table" then
        return nil
    end
    return t[name]
end
Probe.API = api

----------------------------------------------------------------------------------------------------------------------
-- Name scrubbing (PRB-03). Names and GUIDs are kept in memory only, never saved.
----------------------------------------------------------------------------------------------------------------------

local known = {}                         -- lower-cased name -> placeholder
local playerCount, mobCount = 0, 0
local playerIds, mobIds = {}, {}         -- GUID or name -> number

local function playerNumber(key)
    if not playerIds[key] then
        playerCount = playerCount + 1
        playerIds[key] = playerCount
    end
    return playerIds[key]
end

local function mobNumber(key)
    if not mobIds[key] then
        mobCount = mobCount + 1
        mobIds[key] = mobCount
    end
    return mobIds[key]
end

--- Remembers a name so that Probe.Scrub replaces it with `placeholder` from now on.
function Probe.Remember(name, placeholder)
    if Probe.IsSecret(name) or type(name) ~= "string" or #name < 2 then
        return
    end
    local key = name:lower()
    if key == "unknown" or name == rawget(_G, "UNKNOWNOBJECT") then
        return
    end
    known[key] = known[key] or placeholder
end

local function readableString(ok, v)
    if ok and not Probe.IsSecret(v) and type(v) == "string" and v ~= "" then
        return v
    end
end

local function truthy(ok, v)
    return ok and not Probe.IsSecret(v) and v and true or false
end

--- Placeholder of a non-player unit: "<mob n>", GUID type, creature id. "<mob ?>" when its GUID cannot be read.
function Probe.Mob(unit)
    local guid = readableString(Probe.Call(UnitGUID, unit))
    if not guid then
        return "<mob ?>"
    end
    local parts = {}
    for part in guid:gmatch("[^-]+") do
        parts[#parts + 1] = part
    end
    if parts[1] == "Player" then
        return "<player " .. playerNumber(guid) .. ">"
    end
    return "<mob " .. mobNumber(guid) .. ">", parts[1], tonumber(parts[6])
end

--- Learns the names behind one unit token (name, realm, guild).
local function learnUnit(unit)
    if not truthy(Probe.Call(UnitExists, unit)) then
        return
    end
    local ok, name, realm = Probe.Call(UnitName, unit)
    local readable = readableString(ok, name)
    if truthy(Probe.Call(UnitIsPlayer, unit)) then
        local guid = readableString(Probe.Call(UnitGUID, unit))
        if readable then
            local n = playerNumber(guid or readable:lower())
            Probe.Remember(readable, "<player " .. n .. ">")
        end
        Probe.Remember(readableString(ok, realm), "<realm>")
        Probe.Remember(readableString(Probe.Call(GetGuildInfo, unit)), "<guild>")
    elseif readable then
        local placeholder = Probe.Mob(unit)
        if placeholder == "<mob ?>" then
            placeholder = "<mob " .. mobNumber(readable:lower()) .. ">"
        end
        Probe.Remember(readable, placeholder)
    end
end

local UNITS = { "player", "pet", "target", "targettarget", "focus", "mouseover", "npc" }
for i = 1, 4 do
    UNITS[#UNITS + 1] = "party" .. i
    UNITS[#UNITS + 1] = "party" .. i .. "target"
    UNITS[#UNITS + 1] = "partypet" .. i
end
for i = 1, 40 do
    UNITS[#UNITS + 1] = "raid" .. i
    UNITS[#UNITS + 1] = "raid" .. i .. "target"
    UNITS[#UNITS + 1] = "raidpet" .. i
    UNITS[#UNITS + 1] = "nameplate" .. i
end
for i = 1, 5 do
    UNITS[#UNITS + 1] = "boss" .. i
end

--- Learns every name currently visible through a unit token.
function Probe.LearnNames()
    for _, unit in ipairs(UNITS) do
        pcall(learnUnit, unit)
    end
    Probe.Remember(readableString(Probe.Call(GetRealmName)), "<realm>")
    Probe.Remember(readableString(Probe.Call(GetNormalizedRealmName)), "<realm>")
end

-- A byte that can be part of a word: ASCII letters and digits, and every byte of a non-ASCII character.
local function isWordByte(b)
    return b ~= nil and (b >= 128 or string.char(b):match("%w") ~= nil)
end

-- Replaces whole-word occurrences of `needle` (lower case) in `text`, ignoring the case of ASCII letters.
local function replaceWord(text, needle, replacement)
    local lower, pieces, from, search = text:lower(), {}, 1, 1
    while true do
        local s, e = lower:find(needle, search, true)
        if not s then
            break
        end
        if (s == 1 or not isWordByte(lower:byte(s - 1))) and not isWordByte(lower:byte(e + 1)) then
            pieces[#pieces + 1] = text:sub(from, s - 1) .. replacement
            from, search = e + 1, e + 1
        else
            search = s + 1
        end
    end
    pieces[#pieces + 1] = text:sub(from)
    return table.concat(pieces)
end

--- Free text (error messages, the owner's notes) with GUIDs and every known name replaced by placeholders.
--- It only knows the names the probe has seen through a unit token: never type other names in a note.
function Probe.Scrub(text)
    text = tostring(text)
    -- Placeholders are first written as \001<index>\001, so that a later name cannot match inside one of them.
    local held = {}
    local function hold(placeholder)
        held[#held + 1] = placeholder
        return "\001" .. #held .. "\001"
    end
    text = text:gsub("Player%-%d+%-%x+", function(guid)
        return hold("<player " .. playerNumber(guid) .. ">")
    end)
    text = text:gsub("%a+%-%d+%-%d+%-%d+%-%d+%-%d+%-%x+", function(guid)
        return hold("<mob " .. mobNumber(guid) .. ">")
    end)
    local names = {}
    for name in pairs(known) do
        names[#names + 1] = name
    end
    table.sort(names, function(a, b)
        if #a ~= #b then
            return #a > #b
        end
        return a < b
    end)
    for _, name in ipairs(names) do
        if text:lower():find(name, 1, true) then
            text = replaceWord(text, name, hold(known[name]))
        end
    end
    return (text:gsub("\001(%d+)\001", function(i)
        return held[tonumber(i)]
    end))
end

----------------------------------------------------------------------------------------------------------------------
-- Context stamp (SPEC-08, section 1.2)
----------------------------------------------------------------------------------------------------------------------

local encounterActive = false

-- One game value for the stamp: "unknown" when the call fails, "secret" when it is secret. Booleans become yes/no.
local function stampValue(ok, v)
    if not ok then
        return "unknown"
    end
    if Probe.IsSecret(v) then
        return "secret"
    end
    if v == nil then
        return "unknown"
    end
    if type(v) == "boolean" then
        return v and "yes" or "no"
    end
    return v
end

local function activeRestrictions()
    local enum = api("Enum", "AddOnRestrictionType")
    local isActive = api("C_RestrictedActions", "IsAddOnRestrictionActive")
    if type(enum) ~= "table" or type(isActive) ~= "function" then
        return "unknown"
    end
    local names = {}
    for name, value in pairs(enum) do
        local ok, active = Probe.Call(isActive, value)
        local state = stampValue(ok, active)
        if state == "yes" then
            names[#names + 1] = tostring(name)
        elseif state ~= "no" then
            names[#names + 1] = tostring(name) .. "=" .. state
        end
    end
    table.sort(names)
    return #names > 0 and table.concat(names, ",") or "none"
end

--- The context of this moment, computed by the probe. Never contains a name.
function Probe.Context()
    local c = {}
    local okInstance, inInstance, instanceType = Probe.Call(IsInInstance)
    c.instance = stampValue(okInstance, instanceType)
    c.inInstance = stampValue(okInstance, inInstance)
    -- GetInstanceInfo: name (never read), instanceType, difficultyID, difficultyName, maxPlayers, dynamicDifficulty,
    -- isDynamic, instanceID, ...
    local ok, _, _, difficulty, _, maxPlayers, _, _, instanceID = Probe.Call(GetInstanceInfo)
    c.difficultyID = stampValue(ok, difficulty)
    c.maxPlayers = stampValue(ok, maxPlayers)
    c.instanceID = stampValue(ok, instanceID)
    local inRaid = stampValue(Probe.Call(IsInRaid))
    local inGroup = stampValue(Probe.Call(IsInGroup))
    if inRaid == "yes" then
        c.group = "raid"
    elseif inGroup == "yes" then
        c.group = "party"
    elseif inRaid == "no" and inGroup == "no" then
        c.group = "solo"
    else
        c.group = "unknown"
    end
    c.members = stampValue(Probe.Call(GetNumGroupMembers))
    c.combat = stampValue(Probe.Call(UnitAffectingCombat, "player"))
    c.lockdown = stampValue(Probe.Call(api("C_RestrictedActions", "InCombatLockdown")))
    c.encounter = encounterActive and "yes" or "no" -- "yes" between ENCOUNTER_START and ENCOUNTER_END
    c.restrictions = activeRestrictions()
    c.label = Probe.DB().label -- set by /atwp ctx (M0.3)

    if c.instance == "party" then
        c.code = "dungeon"
    elseif c.instance == "raid" then
        c.code = "raid"
    elseif c.instance == "pvp" or c.instance == "arena" then
        c.code = "bg"
    elseif c.group == "raid" or c.group == "party" then
        c.code = c.group
    elseif c.group == "solo" then
        c.code = c.combat == "yes" and "solo-combat" or "solo"
    else
        c.code = "unknown"
    end
    return c
end

local CONTEXT_FIELDS = { "code", "label", "instance", "inInstance", "difficultyID", "maxPlayers", "instanceID",
    "group", "members", "combat", "lockdown", "encounter", "restrictions" }

--- A stamp as one line of "field=value" pairs.
function Probe.ContextText(c)
    if type(c) ~= "table" then
        return "unknown"
    end
    local parts = {}
    for _, field in ipairs(CONTEXT_FIELDS) do
        if c[field] ~= nil then
            parts[#parts + 1] = field .. "=" .. tostring(c[field])
        end
    end
    return table.concat(parts, " ")
end

----------------------------------------------------------------------------------------------------------------------
-- Results, logs and the check registry
----------------------------------------------------------------------------------------------------------------------

local function db()
    if type(AzTw_ProbeDB) ~= "table" then
        AzTw_ProbeDB = {}
    end
    AzTw_ProbeDB.results = AzTw_ProbeDB.results or {}
    AzTw_ProbeDB.log = AzTw_ProbeDB.log or {}
    return AzTw_ProbeDB
end
Probe.DB = db

local function buildString()
    local ok, version, build, _, interface = Probe.Call(GetBuildInfo)
    if not ok then
        return "unknown"
    end
    return string.format("%s.%s (%s)", tostring(Probe.Plain(version)), tostring(Probe.Plain(build)),
        tostring(Probe.Plain(interface)))
end
Probe.BuildString = buildString

local function timeString(format)
    local ok, text = Probe.Call(date, format or "%Y-%m-%d %H:%M:%S")
    return ok and tostring(Probe.Plain(text)) or "unknown"
end

--- Registers a check (or replaces its stub). fn(probe) returns verdict ("supported" | "partial" | "not supported" |
--- "todo") and details (string). Details must never contain names (use the placeholders above).
function Probe:Register(id, description, fn)
    assert(type(id) == "string" and type(fn) == "function", "Register(id, description, fn)")
    if not self.checks[id] then
        self.order[#self.order + 1] = id
    end
    self.checks[id] = { id = id, description = description, fn = fn }
end

--- Stores a result in AzTw_ProbeDB.results[id].
function Probe:Record(id, verdict, details)
    if not VERDICTS[verdict] then
        verdict = "todo"
    end
    local entry = {
        id = id,
        verdict = verdict,
        details = tostring(details or ""),
        build = buildString(),
        context = Probe.Context(),
        time = timeString(),
    }
    db().results[id] = entry
    return entry
end

--- Appends a line to AzTw_ProbeDB.log[name] (the oldest lines are dropped), included in the export.
function Probe:Log(name, line)
    local log = db().log
    local l = log[name] or {}
    log[name] = l
    l[#l + 1] = timeString("%H:%M:%S") .. " " .. tostring(line)
    while #l > LOG_LIMIT do
        table.remove(l, 1)
    end
end

--- Runs one check inside pcall and stores its result.
function Probe:Run(id)
    local check = self.checks[id]
    if not check then
        out("unknown check '" .. tostring(id) .. "' (try /atwp list)")
        return
    end
    local ok, verdict, details = pcall(check.fn, self)
    if not ok then
        verdict, details = "todo", "error: " .. errorText(verdict)
    end
    local entry = self:Record(id, verdict, details)
    out(string.format("%s [%s] %s", id, entry.verdict, entry.details))
    return entry
end

function Probe:List()
    for _, id in ipairs(self.order) do
        local check, last = self.checks[id], db().results[id]
        out(string.format("%s - %s - %s", id, check.description,
            last and (last.verdict .. ": " .. last.details) or "no result"))
    end
end

function Probe:Reset()
    local d = db()
    d.results, d.log = {}, {}
    out("results and logs cleared")
end

----------------------------------------------------------------------------------------------------------------------
-- Export
----------------------------------------------------------------------------------------------------------------------

function Probe:ExportText()
    local d = db()
    local lines = {
        "AzTw Probe export (build " .. buildString() .. ", " .. timeString() .. ")",
        "now: " .. Probe.ContextText(Probe.Context()),
    }
    for _, id in ipairs(self.order) do
        local r = d.results[id]
        if r then
            lines[#lines + 1] = string.format("%s ; %s ; %s ; build %s ; %s", id, tostring(r.verdict),
                tostring(r.details), tostring(r.build), tostring(r.time))
            lines[#lines + 1] = "    context: " .. Probe.ContextText(r.context)
        else
            lines[#lines + 1] = id .. " ; no result"
        end
    end
    local names = {}
    for name in pairs(d.log) do
        names[#names + 1] = name
    end
    table.sort(names)
    for _, name in ipairs(names) do
        lines[#lines + 1] = "-- log: " .. name
        for _, line in ipairs(d.log[name]) do
            lines[#lines + 1] = line
        end
    end
    for _, hook in ipairs(self.exportHooks) do
        local ok, extra = pcall(hook, self)
        if ok and type(extra) == "table" then
            for _, line in ipairs(extra) do
                lines[#lines + 1] = line
            end
        elseif not ok then
            lines[#lines + 1] = "export hook error: " .. errorText(extra)
        end
    end
    -- A "|" starts an escape sequence in an edit box: it is replaced so that the copied text is exactly what is saved.
    return (table.concat(lines, "\n"):gsub("|", "/"))
end

local exportFrame

local function createExportFrame()
    local template = rawget(_G, "BackdropTemplateMixin") and "BackdropTemplate" or nil
    local f = CreateFrame("Frame", nil, UIParent, template)
    f:SetSize(620, 380)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    if f.SetBackdrop then
        f:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true, tileSize = 32, edgeSize = 32,
            insets = { left = 8, right = 8, top = 8, bottom = 8 },
        })
    end
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", 0, -14)
    title:SetText("AzTw Probe export (Ctrl+C to copy, drag to move)")
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)
    local scroll = CreateFrame("ScrollFrame", "AzTw_ProbeExportScroll", f, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 18, -40)
    scroll:SetPoint("BOTTOMRIGHT", -36, 18)
    local edit = CreateFrame("EditBox", nil, scroll)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    edit:SetFontObject("ChatFontNormal")
    edit:SetWidth(560)
    edit:SetMaxLetters(0) -- 0 = no limit
    edit:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
        f:Hide()
    end)
    scroll:SetScrollChild(edit)
    f.edit = edit
    return f
end

local function showExport(text)
    exportFrame = exportFrame or createExportFrame()
    exportFrame.edit:SetText(text)
    exportFrame:Show()
    exportFrame.edit:SetFocus()
    exportFrame.edit:HighlightText()
end

--- Opens the export frame with all results and logs, already selected.
function Probe:Export()
    local ok, err = pcall(function()
        showExport(self:ExportText())
    end)
    if not ok then
        out("export error: " .. errorText(err))
    end
end

----------------------------------------------------------------------------------------------------------------------
-- Checks P1-P12: stubs until the step named here replaces them by calling Probe:Register with the same id.
----------------------------------------------------------------------------------------------------------------------

local STUBS = {
    { "P1", "M0.3", "Client version, build, project, interface, restrictions" },
    { "P2", "M0.3", "Threat functions on the target: presence, arguments, returns" },
    { "P3", "M0.3", "Secret values: predictions and issecretvalue per context" },
    { "P4", "M0.3", "Standard threat rules: percentages when aggro changes" },
    { "P5", "M0.4", "Which units and mobs can be queried" },
    { "P6", "M0.4", "Threat events: payload, rate, delay" },
    { "P7", "M0.5", "Combat events: combat log, targets, encounters, deaths, taunts" },
    { "P8", "M0.5", "C_DamageMeter: availability, sessions, deaths" },
    { "P9", "M0.4", "GUIDs and roles in instances" },
    { "P10", "M0.6", "Cost of sampling: time per tick and memory" },
    { "P11", "M0.6", "Restrictions: blocked actions, errors, limits" },
    { "P12", "M0.6", "Reload and logout during a fight" },
}
for _, stub in ipairs(STUBS) do
    local step = stub[2]
    Probe:Register(stub[1], stub[3], function()
        return "todo", "not implemented yet, step " .. step
    end)
end

----------------------------------------------------------------------------------------------------------------------
-- Slash command
----------------------------------------------------------------------------------------------------------------------

local USAGE = "/atwp [list] | run <id> | export | note <id> <text> | reset | help"
local BUILT_IN = { note = true }

--- The usage line, with the commands added by the Checks files.
function Probe.Usage()
    local names = {}
    for name in pairs(Probe.commands) do
        if not BUILT_IN[name] then
            names[#names + 1] = name
        end
    end
    table.sort(names)
    return USAGE .. (#names > 0 and (" | " .. table.concat(names, " | ")) or "")
end

-- /atwp note P4 <text>: a free-text observation of the owner, scrubbed, stored in the log and exported.
Probe.commands.note = function(id, text)
    id = id:upper()
    if not Probe.checks[id] or text == "" then
        out("usage: /atwp note <id> <text> (id P1-P12; never write player or guild names)")
        return
    end
    Probe.LearnNames()
    Probe:Log("notes", id .. " [" .. Probe.Context().code .. "]: " .. Probe.Scrub(text))
    out("note stored for " .. id)
end

local function handle(message)
    local cmd, arg, rest = (message or ""):match("^%s*(%S*)%s*(%S*)%s*(.-)%s*$")
    cmd = cmd:lower()
    if cmd == "" or cmd == "list" then
        Probe:List()
    elseif cmd == "run" and arg ~= "" then
        Probe:Run(arg:upper())
    elseif cmd == "export" then
        Probe.LearnNames()
        Probe:Export()
    elseif cmd == "reset" then
        Probe:Reset()
    elseif Probe.commands[cmd] then
        Probe.commands[cmd](arg, rest)
    else
        out(Probe.Usage())
    end
end

SLASH_AZTWPROBE1 = "/atwp"
SlashCmdList["AZTWPROBE"] = function(message)
    local ok, err = pcall(handle, message)
    if not ok then
        out("error in /atwp: " .. errorText(err))
    end
end

----------------------------------------------------------------------------------------------------------------------
-- Events
----------------------------------------------------------------------------------------------------------------------

local handlers = {} -- event -> list of functions
local frame

--- Calls fn(...) with the event payload every time `event` fires. Returns false if the client refuses the event.
function Probe:On(event, fn)
    if not frame then
        return false
    end
    if not handlers[event] then
        local ok = pcall(frame.RegisterEvent, frame, event)
        if not ok then
            return false
        end
        handlers[event] = {}
    end
    table.insert(handlers[event], fn)
    return true
end

local created, newFrame = pcall(CreateFrame, "Frame")
if created and newFrame then
    local ok = pcall(newFrame.SetScript, newFrame, "OnEvent", function(_, event, ...)
        for _, fn in ipairs(handlers[event] or {}) do
            local fine, err = pcall(fn, ...)
            if not fine then
                Probe:Log("errors", event .. ": " .. errorText(err))
            end
        end
    end)
    if ok then
        frame = newFrame
    end
end

Probe:On("ADDON_LOADED", function(name)
    if name == ADDON_NAME then
        db()
        out("loaded (development only). " .. Probe.Usage())
    end
end)
Probe:On("ENCOUNTER_START", function()
    encounterActive = true
end)
Probe:On("ENCOUNTER_END", function()
    encounterActive = false
end)
-- Names are learned as they appear, so that a note or an error can be scrubbed after the unit is gone.
Probe:On("PLAYER_LOGIN", Probe.LearnNames)
Probe:On("GROUP_ROSTER_UPDATE", Probe.LearnNames)
Probe:On("PLAYER_TARGET_CHANGED", Probe.LearnNames)
