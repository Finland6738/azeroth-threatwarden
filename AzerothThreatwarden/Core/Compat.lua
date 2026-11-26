-- Compat: the only door to the game API (SPEC-01 §2, §8; ARC-02, ARC-10, ARC-11, ARC-12). Lua 5.1.
-- Adapted from Azeroth Accord (Core/Compat.lua), same owner, GPL-3.0 (ADR 0012): Resolve, the guarded calls, the
-- states and the secret-value checks come from there; the API table, the capabilities, the normalized threat read
-- (SPEC-01 §8.3), the restrictions and the timers are Threatwarden's own. Accord's guild, club, chat and encoding
-- helpers are left out.
--
-- Every path below is in the Forever API dump (../WoW-Addons/docs/api.json, build 70170, checked 2026-11-25; consulted,
-- never copied, ADR 0002) with the signature SPEC-01 §8.2 gives, except the interface code the dump does not list
-- (WOW_PROJECT_ID, WOW_PROJECT_CAMELOT, Enum, Settings, UISpecialFrames, SlashCmdList, GameTooltip): those are looked up
-- at run time and "absent" is an answer (PRB-05).
--
-- Secret values (ARC-11): a value the client gives is checked with Compat.IsSecret **before anything else**, and the
-- check itself only hands the value to issecretvalue, canaccessvalue and issecrettable (and asks type(), which the
-- client answers for a secret too): it never compares, indexes, concatenates, formats or stores one. A secret becomes
-- nil with the reason "secret". What waits for the M0 probe is marked [probe Pn].
local ADDON_NAME, ns = ...
ns = ns or {}
ns.modules = ns.modules or {}

local Compat = {}
ns.Compat, ns.modules.Compat = Compat, Compat

local AVAILABLE, MISSING, RESTRICTED, ERROR, UNKNOWN = "available", "missing", "restricted", "error", "unknown"
Compat.AVAILABLE, Compat.MISSING, Compat.RESTRICTED, Compat.ERROR, Compat.UNKNOWN =
	AVAILABLE, MISSING, RESTRICTED, ERROR, UNKNOWN

local _G = _G
local type, pcall, select, pairs, ipairs, tostring = type, pcall, select, pairs, ipairs, tostring
local DETAIL_LENGTH = 120

---------------------------------------------------------------------------------------------------------------------
-- Resolve, secret values, guarded calls
---------------------------------------------------------------------------------------------------------------------
local function index(value, part) return value[part] end   -- one function for every step: no closure per lookup
local PARTS = {}                                              -- path -> its names, split once (the paths are a fixed set)

-- "C_Secrets.HasSecretRestrictions" -> the value in the global table, or nil. Never raises. Looked up on every call:
-- a function may appear late, and tests replace them.
function Compat.Resolve(path)
	if type(path) ~= "string" or path == "" then return nil end
	local parts = PARTS[path]
	if not parts then
		parts = {}
		for part in path:gmatch("[^.]+") do parts[#parts + 1] = part end
		PARTS[path] = parts
	end
	local value = _G
	for i = 1, #parts do
		if type(value) ~= "table" then return nil end
		local ok, nextValue = pcall(index, value, parts[i])
		if not ok then return nil end
		value = nextValue
	end
	return value
end
local Resolve = Compat.Resolve

-- true when the client hides `value`. Only the client's own checks look at it (ARC-11); without them nothing is
-- secret (an older client has no secret values).
function Compat.IsSecret(value)
	local isSecret = _G.issecretvalue
	if type(isSecret) == "function" then
		local ok, answer = pcall(isSecret, value)
		if ok and answer == true then return true end
	end
	local canAccess = _G.canaccessvalue
	if type(canAccess) == "function" then
		local ok, answer = pcall(canAccess, value)
		if ok and answer == false then return true end
	end
	if type(value) == "table" then
		local isSecretTable = _G.issecrettable
		if type(isSecretTable) == "function" then
			local ok, answer = pcall(isSecretTable, value)
			if ok and answer == true then return true end
		end
	end
	return false
end
local IsSecret = Compat.IsSecret

-- The value, or nil when the client hides it.
function Compat.Readable(value)
	if IsSecret(value) then return nil end
	return value
end

local function cleanText(text)
	local Diag = ns.Diagnostics
	text = (Diag and Diag.CleanError) and Diag.CleanError(text) or tostring(text):gsub("[\r\n]+", " ")
	if #text > DETAIL_LENGTH then text = text:sub(1, DETAIL_LENGTH - 3) .. "..." end
	return text
end

-- An error message made safe to show or keep: one line, no paths, cut short (Core/Diagnostics.lua when loaded).
function Compat.CleanText(text) return cleanText(text) end

-- An error that talks about restrictions is "restricted", any other "error" [probe P11: the client's wording].
local function restrictedMessage(message)
	message = message:lower()
	return message:find("restrict", 1, true) or message:find("secret", 1, true) or message:find("forbidden", 1, true)
		or message:find("blocked", 1, true) or message:find("lockdown", 1, true)
end

-- Every value with its count (a trailing nil is a value too).
local function pack(...) return { n = select("#", ...), ... } end

-- Runs fn(...) under pcall. Returns state, detail, count, values: a secret result becomes nil and the state
-- "restricted"; a failed call "restricted" or "error" with a cleaned message. Allocates a table: for the cold paths
-- (Probe, the report); the threat read below has its own allocation-free path.
local function run(fn, ...)
	if type(fn) ~= "function" then return MISSING, nil, 0, {} end
	local packed = pack(pcall(fn, ...))
	if not packed[1] then
		local message = cleanText(packed[2])
		return restrictedMessage(message) and RESTRICTED or ERROR, message, 0, {}
	end
	local state, values, count = AVAILABLE, {}, packed.n - 1
	for i = 1, count do
		local v = packed[i + 1]
		if IsSecret(v) then
			state, v = RESTRICTED, nil
		end
		values[i] = v
	end
	return state, state == RESTRICTED and "secret value" or nil, count, values
end

-- Compat.Call("GetBuildInfo") -> state, value1, value2, ... (secret values as nil).
function Compat.Call(path, ...)
	local state, _, count, values = run(Resolve(path), ...)
	return state, unpack(values, 1, count)
end
local Call = Compat.Call

-- The first value when the call worked and it is readable, else nil; the state second.
local function first(path, ...)
	local state, _, _, values = run(Resolve(path), ...)
	if state == AVAILABLE then return values[1], state end
	return nil, state
end
Compat.First = first

local function plainString(v) return type(v) == "string" and v ~= "" and v or nil end
local function plainNumber(v) return type(v) == "number" and v == v and v or nil end

---------------------------------------------------------------------------------------------------------------------
-- The API table (SPEC-01 §8.2)
---------------------------------------------------------------------------------------------------------------------
-- id, paths (alternatives: the first that exists, or every one with all = true), how Probe checks it ("call": called
-- once with `args`, cheap and without side effects; "exists": only looked up; "read": a constant or table of the
-- interface code), show = the first value goes into the report (booleans, numbers and fixed client words only),
-- since = the milestone that uses it, probe = the checks of the M0 probe that decide its behaviour.
Compat.APIS = {
	{ id = "client.GetBuildInfo", paths = { "GetBuildInfo" }, check = "call", since = "M1", probe = "P1" },
	{ id = "client.GetLocale", paths = { "GetLocale" }, check = "call", show = true, since = "M1", probe = "P1" },
	{ id = "client.ProjectID", paths = { "WOW_PROJECT_ID", "WOW_PROJECT_CAMELOT" }, all = true, check = "read",
		since = "M1", probe = "P1" },
	{ id = "client.RealmName", paths = { "GetRealmName" }, check = "exists", since = "M1", probe = "-" },
	{ id = "secret.issecretvalue", paths = { "issecretvalue" }, check = "exists", since = "M1", probe = "P3" },
	{ id = "secret.issecrettable", paths = { "issecrettable" }, check = "exists", since = "M1", probe = "P3" },
	{ id = "secret.canaccessvalue", paths = { "canaccessvalue" }, check = "exists", since = "M1", probe = "P3" },
	{ id = "secret.HasSecretRestrictions", paths = { "C_Secrets.HasSecretRestrictions" }, check = "call", show = true,
		since = "M1", probe = "P1, P3" },
	{ id = "secret.ThreatValues", paths = { "C_Secrets.ShouldUnitThreatValuesBeSecret" }, check = "exists",
		since = "M1", probe = "P3" },
	{ id = "secret.ThreatState", paths = { "C_Secrets.ShouldUnitThreatStateBeSecret" }, check = "exists",
		since = "M1", probe = "P3" },
	{ id = "secret.Identity", paths = { "C_Secrets.ShouldUnitIdentityBeSecret" }, check = "exists", since = "M2",
		probe = "P9" },
	{ id = "secret.Comparison", paths = { "C_Secrets.ShouldUnitComparisonBeSecret" }, check = "exists", since = "M2",
		probe = "P9" },
	{ id = "threat.Detailed", paths = { "UnitDetailedThreatSituation" }, check = "exists", since = "M1",
		probe = "P2-P5" },
	{ id = "threat.Situation", paths = { "UnitThreatSituation" }, check = "exists", since = "M1", probe = "P2, P3" },
	{ id = "threat.PercentageOfLead", paths = { "UnitThreatPercentageOfLead" }, check = "exists", since = "M1",
		probe = "P2" },
	{ id = "threat.LeadSituation", paths = { "UnitThreatLeadSituation" }, check = "exists", since = "M1", probe = "P2" },
	{ id = "threat.StatusColor", paths = { "GetThreatStatusColor" }, check = "exists", since = "M1", probe = "P2" },
	{ id = "threat.WarningEnabled", paths = { "IsThreatWarningEnabled" }, check = "call", show = true, since = "M1",
		probe = "-" },
	{ id = "unit.Exists", paths = { "UnitExists" }, check = "exists", since = "M2", probe = "P2" },
	{ id = "unit.GUID", paths = { "UnitGUID" }, check = "call", args = { "player" }, since = "M2", probe = "P9" },
	{ id = "unit.TokenFromGUID", paths = { "UnitTokenFromGUID" }, check = "exists", since = "M7", probe = "P5, P9" },
	{ id = "unit.Name", paths = { "UnitName" }, check = "exists", since = "M2", probe = "P9" },
	{ id = "unit.Class", paths = { "UnitClass" }, check = "exists", since = "M2", probe = "-" },
	{ id = "unit.Classification", paths = { "UnitClassification" }, check = "exists", since = "M2", probe = "P5" },
	{ id = "unit.CanAttack", paths = { "UnitCanAttack" }, check = "exists", since = "M2", probe = "P2" },
	{ id = "unit.IsDead", paths = { "UnitIsDead" }, check = "exists", since = "M2", probe = "P7" },
	{ id = "unit.IsUnit", paths = { "UnitIsUnit" }, check = "exists", since = "M2", probe = "P9" },
	{ id = "unit.AffectingCombat", paths = { "UnitAffectingCombat" }, check = "call", args = { "player" }, show = true,
		since = "M1", probe = "P7" },
	{ id = "unit.Role", paths = { "UnitGroupRolesAssigned" }, check = "exists", since = "M2", probe = "P9" },
	{ id = "group.InGroup", paths = { "IsInGroup" }, check = "call", show = true, since = "M2", probe = "P5" },
	{ id = "group.InRaid", paths = { "IsInRaid" }, check = "call", show = true, since = "M2", probe = "P5" },
	{ id = "group.Size", paths = { "GetNumGroupMembers" }, check = "call", show = true, since = "M2", probe = "P5" },
	{ id = "group.RaidIndex", paths = { "UnitInRaid" }, check = "exists", since = "M2", probe = "P5" },
	{ id = "instance.InInstance", paths = { "IsInInstance" }, check = "call", show = true, since = "M1", probe = "P3" },
	{ id = "instance.Info", paths = { "GetInstanceInfo" }, check = "exists", since = "M4", probe = "P3" },
	{ id = "zone.RealZoneText", paths = { "GetRealZoneText" }, check = "exists", since = "M4", probe = "-" },
	{ id = "restriction.InCombatLockdown", paths = { "C_RestrictedActions.InCombatLockdown", "InCombatLockdown" },
		check = "call", show = true, since = "M1", probe = "P11" },
	{ id = "restriction.IsActive", paths = { "C_RestrictedActions.IsAddOnRestrictionActive" }, check = "exists",
		since = "M1", probe = "P11" },
	{ id = "restriction.Types", paths = { "Enum.AddOnRestrictionType" }, check = "read", since = "M1", probe = "P11" },
	{ id = "combatlog.Restricted", paths = { "C_CombatLog.IsCombatLogRestricted" }, check = "call", show = true,
		since = "M1", probe = "P7" },
	{ id = "damagemeter.Available", paths = { "C_DamageMeter.IsDamageMeterAvailable" }, check = "call", show = true,
		since = "M4", probe = "P8" },
	{ id = "time.GetTime", paths = { "GetTime" }, check = "call", since = "M1", probe = "-" },
	{ id = "time.ServerTime", paths = { "GetServerTime" }, check = "call", since = "M1", probe = "P12" },
	{ id = "time.Date", paths = { "date" }, check = "exists", since = "M4", probe = "-" },
	{ id = "time.After", paths = { "C_Timer.After" }, check = "exists", since = "M1", probe = "P11" },
	{ id = "time.NewTicker", paths = { "C_Timer.NewTicker" }, check = "exists", since = "M1", probe = "P11" },
	{ id = "time.NewTimer", paths = { "C_Timer.NewTimer" }, check = "exists", since = "M1", probe = "P11" },
	{ id = "time.ProfileStop", paths = { "debugprofilestop" }, check = "exists", since = "M1", probe = "P10" },
	{ id = "addon.Metadata", paths = { "C_AddOns.GetAddOnMetadata" }, check = "call", args = { ADDON_NAME, "Version" },
		since = "M1", probe = "-" },
	{ id = "addon.Memory", paths = { "UpdateAddOnMemoryUsage", "GetAddOnMemoryUsage" }, all = true, check = "exists",
		since = "M1", probe = "P10" },
	{ id = "addon.Framerate", paths = { "GetFramerate" }, check = "exists", since = "M1", probe = "P10" },
	{ id = "addon.ErrorHandler", paths = { "geterrorhandler", "seterrorhandler" }, all = true, check = "exists",
		since = "M1", probe = "-" },
	{ id = "ui.Reload", paths = { "C_UI.Reload", "ReloadUI" }, check = "exists", since = "M1", probe = "-" },
	{ id = "ui.CreateFrame", paths = { "CreateFrame" }, check = "exists", since = "M1", probe = "-" },
	{ id = "ui.CreateFont", paths = { "CreateFont" }, check = "exists", since = "M1", probe = "-" },
	{ id = "ui.CreateColor", paths = { "CreateColor" }, check = "exists", since = "M1", probe = "-" },
	{ id = "ui.ScreenSize", paths = { "GetPhysicalScreenSize", "GetScreenWidth", "GetScreenHeight" }, all = true,
		check = "exists", since = "M1", probe = "-" },
	{ id = "ui.SettingsPanel", paths = { "Settings.RegisterCanvasLayoutCategory", "Settings.RegisterAddOnCategory",
		"Settings.OpenToCategory" }, all = true, check = "exists", since = "M1", probe = "game" },
	{ id = "ui.SpecialFrames", paths = { "UISpecialFrames" }, check = "read", since = "M1", probe = "game" },
	{ id = "ui.SlashCmdList", paths = { "SlashCmdList" }, check = "read", since = "M1", probe = "game" },
	{ id = "ui.ClassColor", paths = { "C_ClassColor.GetClassColor" }, check = "exists", since = "M2", probe = "-" },
	{ id = "ui.PlaySound", paths = { "PlaySound", "C_Sound.PlaySound" }, check = "exists", since = "M3", probe = "-" },
	{ id = "ui.CursorPosition", paths = { "GetCursorPosition" }, check = "exists", since = "M5", probe = "game" },
	{ id = "ui.Modifiers", paths = { "IsShiftKeyDown", "IsControlKeyDown", "IsAltKeyDown" }, all = true,
		check = "exists", since = "M5", probe = "-" },
}

local apiById = {}
for _, entry in ipairs(Compat.APIS) do apiById[entry.id] = entry end

-- The capabilities of SPEC-01 §8.4, in report order; restricted.<Type> entries follow, one per restriction type.
Compat.CAPABILITIES = { "threatValues", "threatState", "threatLead", "threatEvents", "groupThreat", "otherMobs",
	"mobIdentity", "roles", "combatLog", "damageMeter" }
local CAPABILITY_STATES = { available = true, missing = true, restricted = true, unknown = true }

Compat.api = {}            -- id -> { state, detail, path (the one found), value (show entries only) }
Compat.capabilities = {}   -- id -> { state, detail }
Compat.restrictionTypes = {}   -- { { name, value } } sorted by value, from Enum.AddOnRestrictionType [probe P11]
Compat.probed = false

local function showable(v)
	local t = type(v)
	if t == "boolean" or t == "number" then return tostring(v) end
	if t == "string" and #v <= 24 and not v:find("[^%w_%-%.]") then return v end
	return nil
end

-- One entry of the API table: { state, detail, path, value }.
local function probeEntry(entry)
	local result = { state = MISSING }
	local found = {}
	for _, path in ipairs(entry.paths) do
		local value = Resolve(path)
		if not IsSecret(value) and value ~= nil then found[#found + 1] = path end
	end
	if entry.all and #found < #entry.paths then
		result.detail = #found == 0 and nil or "partly missing"
		return result
	end
	if #found == 0 then return result end
	result.path = found[1]
	local value = Resolve(found[1])
	if entry.check == "read" then
		result.state = AVAILABLE
		return result
	end
	if type(value) ~= "function" then
		result.state, result.detail = ERROR, "not a function"
		return result
	end
	if entry.check == "call" then
		local args = entry.args or {}
		local state, detail, _, values = run(value, unpack(args))
		result.state, result.detail = state, detail
		if state == AVAILABLE and entry.show then result.value = showable(values[1]) end
		return result
	end
	result.state = AVAILABLE
	return result
end

-- The restriction types the client names (Enum.AddOnRestrictionType), sorted by value [probe P11: names and values].
local function readRestrictionTypes()
	local types = {}
	local enum = Resolve("Enum.AddOnRestrictionType")
	if type(enum) == "table" and not IsSecret(enum) then
		for name, value in pairs(enum) do
			if type(name) == "string" and plainNumber(value) then types[#types + 1] = { name = name, value = value } end
		end
	end
	table.sort(types, function(a, b) return a.value < b.value end)
	return types
end

local function setCapability(id, state, detail)
	local cap = Compat.capabilities[id]
	if not cap then
		cap = {}
		Compat.capabilities[id] = cap
	end
	local changed = cap.state ~= state
	cap.state, cap.detail = state, detail
	return changed
end

-- restricted.<Type>: "restricted" while the client restriction is active, "available" while not, "unknown" when the
-- client cannot say.
local function restrictionState(value)
	local active, state = first("C_RestrictedActions.IsAddOnRestrictionActive", value)
	if state ~= AVAILABLE or type(active) ~= "boolean" then return UNKNOWN, state ~= MISSING and state or nil end
	return active and RESTRICTED or AVAILABLE, nil
end

local function initialCapabilities()
	local function fromApi(id, apiId)
		local state = Compat.api[apiId].state
		if state == MISSING then setCapability(id, MISSING, apiId .. " missing")
		else setCapability(id, UNKNOWN, nil) end   -- ARC-12: no reading has proved it yet
	end
	fromApi("threatValues", "threat.Detailed")
	fromApi("threatState", "threat.Situation")
	fromApi("threatLead", "threat.PercentageOfLead")
	for _, id in ipairs({ "threatEvents", "groupThreat", "otherMobs", "mobIdentity", "roles" }) do
		setCapability(id, UNKNOWN, nil)
	end
	-- the combat log is not used (ADR 0004); the report says whether an addon could read it [probe P7]
	if Resolve("CombatLogGetCurrentEventInfo") == nil then
		setCapability("combatLog", MISSING, "CombatLogGetCurrentEventInfo missing")
	else
		local restricted = first("C_CombatLog.IsCombatLogRestricted")
		setCapability("combatLog", restricted == true and RESTRICTED or UNKNOWN, nil)
	end
	local state, available, reason = Call("C_DamageMeter.IsDamageMeterAvailable")
	if state == AVAILABLE and available == true then
		setCapability("damageMeter", UNKNOWN, nil)   -- available by the client's word; M4 checks the data [probe P8]
	elseif state == AVAILABLE then
		setCapability("damageMeter", MISSING, plainString(reason) and cleanText(reason) or "not available")
	else
		setCapability("damageMeter", state == MISSING and MISSING or UNKNOWN, "C_DamageMeter " .. state)
	end
	for _, t in ipairs(Compat.restrictionTypes) do
		setCapability("restricted." .. t.name, restrictionState(t.value))
	end
end

-- ADDON_LOADED (Core/Init.lua): fills the API table and the capabilities. Never raises; may run again.
function Compat:Probe()
	for _, entry in ipairs(Compat.APIS) do
		local ok, result = pcall(probeEntry, entry)
		if not ok then result = { state = ERROR, detail = cleanText(result) } end
		Compat.api[entry.id] = result
	end
	Compat.restrictionTypes = readRestrictionTypes()
	local ok, err = pcall(initialCapabilities)
	if not ok and ns.Diagnostics then ns.Diagnostics.Record(err) end
	Compat.probed = true
	return Compat.api
end

-- state, detail of an API of the table; nil for an id that is not in it.
function Compat.ApiState(id)
	local result = Compat.api[id]
	if result then return result.state, result.detail end
	if apiById[id] then return UNKNOWN, "not probed yet" end
	return nil
end

-- state, detail of a capability ("unknown" for one nobody has set).
function Compat.Capability(id)
	local cap = Compat.capabilities[id]
	if cap then return cap.state, cap.detail end
	return UNKNOWN, nil
end

-- A module tells what a reading proved (ARC-12): CAPABILITY_CHANGED(id, state) is emitted when the state changes.
-- Returns true when it changed. A state outside available / missing / restricted / unknown is refused.
function Compat:SetCapability(id, state, detail)
	if type(id) ~= "string" or IsSecret(id) or not CAPABILITY_STATES[state] then return false end
	if IsSecret(detail) or type(detail) ~= "string" then detail = nil else detail = cleanText(detail) end
	local changed = setCapability(id, state, detail)
	if changed and ns.Bus then ns.Bus.Emit("CAPABILITY_CHANGED", id, state) end
	return changed
end

-- ADDON_RESTRICTION_STATE_CHANGED(type, state) (registered by Core/Init.lua): the client is about to turn a
-- restriction on, or has turned it off. The state is asked again rather than read from the payload, whose values the
-- dump does not give [probe P11].
function Compat:OnRestrictionChanged(kind)
	if IsSecret(kind) or not plainNumber(kind) then return false end
	local name
	for _, t in ipairs(Compat.restrictionTypes) do
		if t.value == kind then name = t.name break end
	end
	if not name then
		name = tostring(kind)
		Compat.restrictionTypes[#Compat.restrictionTypes + 1] = { name = name, value = kind }
	end
	return Compat:SetCapability("restricted." .. name, (restrictionState(kind)))
end

-- The names of the client restrictions active now (from the capabilities).
function Compat.ActiveRestrictions()
	local out = {}
	for _, t in ipairs(Compat.restrictionTypes) do
		if Compat.Capability("restricted." .. t.name) == RESTRICTED then out[#out + 1] = t.name end
	end
	return out
end

---------------------------------------------------------------------------------------------------------------------
-- Client, addon, time
---------------------------------------------------------------------------------------------------------------------
local FOREVER_MIN_INTERFACE, FOREVER_MAX_INTERFACE = 16001, 19999

-- { version, build, date, interface, projectID, isForever } (nil fields when the client does not say).
function Compat.BuildInfo()
	local state, version, build, date, interface = Call("GetBuildInfo")
	local info = {}
	if state == AVAILABLE then
		info.version, info.build, info.date = plainString(version), plainString(build), plainString(date)
		info.interface = plainNumber(interface)
	end
	info.projectID = plainNumber(Compat.Readable(Resolve("WOW_PROJECT_ID")))
	info.isForever = Compat.IsForever()
	return info
end

-- true on WoW Forever (ARC-01): the project constants when the client has both (their value is P1), else the
-- Interface number of GetBuildInfo between 16001 and 19999.
function Compat.IsForever()
	local id, camelot = Compat.Readable(Resolve("WOW_PROJECT_ID")), Compat.Readable(Resolve("WOW_PROJECT_CAMELOT"))
	if id ~= nil and camelot ~= nil then return id == camelot end
	local state, _, _, _, interface = Call("GetBuildInfo")
	interface = state == AVAILABLE and plainNumber(interface)
	return interface and interface >= FOREVER_MIN_INTERFACE and interface <= FOREVER_MAX_INTERFACE or false
end

-- The client's language code ("enUS" when it cannot say).
function Compat.ClientLocale()
	return plainString((first("GetLocale"))) or "enUS"
end

-- Seconds since the epoch of the realm clock (GetServerTime), nil when unknown: the date of a `corrupt` entry of
-- Core/Config.lua (SPEC-02 §3.4) and, from M4, of the recorded sessions.
function Compat.ServerTime()
	return plainNumber((first("GetServerTime")))
end

-- `epoch` written with the strftime pattern `format` in the PC's own time zone (`date`), nil for an unknown time
-- (0 or no number) or a client that cannot say: the date of a recording in the Reports tab.
function Compat.DateText(format, epoch)
	if type(format) ~= "string" or not plainNumber(epoch) or epoch <= 0 then return nil end
	return plainString((first("date", format, epoch)))
end

-- The Version field of the TOC ("@project-version@" in a development copy), nil when unknown.
function Compat.AddonVersion()
	return plainString((first("C_AddOns.GetAddOnMetadata", ADDON_NAME, "Version")))
end

-- The memory the client attributes to the addon, in KB, nil when unknown.
function Compat.AddonMemoryKB()
	first("UpdateAddOnMemoryUsage")
	return plainNumber((first("GetAddOnMemoryUsage", ADDON_NAME)))
end

function Compat.Framerate()
	return plainNumber((first("GetFramerate")))
end

-- Seconds of the client clock (GetTime), 0 when unknown. Allocation-free.
function Compat.Now()
	local fn = Resolve("GetTime")
	if type(fn) ~= "function" then return 0 end
	local ok, now = pcall(fn)
	if ok and not IsSecret(now) and plainNumber(now) then return now end
	return 0
end

-- Milliseconds of the profiling clock (debugprofilestop), nil when unknown. Allocation-free (Scheduler, ARC-09).
function Compat.ProfileMs()
	local fn = Resolve("debugprofilestop")
	if type(fn) ~= "function" then return nil end
	local ok, ms = pcall(fn)
	if ok and not IsSecret(ms) and plainNumber(ms) then return ms end
	return nil
end

-- A repeating client timer calling fn every `seconds`: the ticker, or nil when the client has no timers.
function Compat.NewTicker(seconds, fn)
	local new = Resolve("C_Timer.NewTicker")
	if type(new) ~= "function" or type(fn) ~= "function" then return nil end
	local ok, ticker = pcall(new, seconds, fn)
	if ok and type(ticker) == "table" then return ticker end
	return nil
end

-- fn once after `seconds`; false when the client has no timers.
function Compat.After(seconds, fn)
	local after = Resolve("C_Timer.After")
	if type(after) ~= "function" or type(fn) ~= "function" then return false end
	return (pcall(after, seconds, fn))
end

function Compat.CancelTicker(ticker)
	if type(ticker) == "table" and type(ticker.Cancel) == "function" then pcall(ticker.Cancel, ticker) end
end

function Compat.InCombatLockdown()
	local v = first("C_RestrictedActions.InCombatLockdown")
	if v == nil then v = first("InCombatLockdown") end
	return v == true
end

-- "none", "party", "raid"... (a fixed word of the client, never the name of the instance), nil when unknown.
function Compat.InstanceType()
	local state, _, kind = Call("IsInInstance")
	if state ~= AVAILABLE then return nil end
	return showable(kind)
end

-- The type and the difficulty of the current instance (GetInstanceInfo, M4: the header of a recorded session, SPEC-02
-- §4.1): instanceType ("none", "party", "raid"... a fixed word of the client, never the instance's name, which is not
-- read) and difficultyID; each nil when the client cannot say or hides it.
function Compat.InstanceInfo()
	local fn = Resolve("GetInstanceInfo")
	if type(fn) ~= "function" then return nil, nil end
	local ok, _, kind, difficulty = pcall(fn)
	if not ok then return nil, nil end
	if IsSecret(kind) then kind = nil end
	if IsSecret(difficulty) then difficulty = nil end
	return showable(kind), plainNumber(difficulty)
end

-- The name of the zone the player is in (GetRealZoneText, M4): kept only in a recorded session (SPEC-02 §4.1), never in
-- the report of /atw debug. nil when absent, empty or secret.
function Compat.ZoneText()
	local fn = Resolve("GetRealZoneText")
	if type(fn) ~= "function" then return nil end
	local ok, zone = pcall(fn)
	if not ok or IsSecret(zone) then return nil end
	return plainString(zone)
end

-- The player's own name and realm, only to take them out of the report (Core/Diagnostics.lua); never stored.
function Compat.PlayerName()
	return plainString((first("UnitName", "player")))
end

function Compat.RealmName()
	return plainString((first("GetRealmName")))
end

-- The client's error handler, and a way to wrap it (Core/Diagnostics.lua).
function Compat.ErrorHandler()
	local get = Resolve("geterrorhandler")
	if type(get) ~= "function" then return nil end
	local ok, handler = pcall(get)
	if ok and type(handler) == "function" then return handler end
	return nil
end

function Compat.SetErrorHandler(fn)
	local set = Resolve("seterrorhandler")
	if type(set) ~= "function" or type(fn) ~= "function" then return false end
	return (pcall(set, fn))
end

-- Hands an error to the client's handler (shown in the error frame, kept by Diagnostics) without raising.
function Compat.ReportError(message)
	local handler = Compat.ErrorHandler()
	if handler then pcall(handler, message) end
end

-- The interface frames the dump does not list (FrameXML), looked up when used: nil when the client has none.
function Compat.Tooltip()
	local tip = Resolve("GameTooltip")
	return type(tip) == "table" and tip or nil
end

function Compat.UIParent()
	local parent = Resolve("UIParent")
	return type(parent) == "table" and parent or nil
end

-- The height of the physical screen in pixels (UI/Theme.lua, one physical pixel), nil when the client cannot say.
function Compat.PhysicalScreenHeight()
	local fn = Resolve("GetPhysicalScreenSize")
	if type(fn) ~= "function" then return nil end
	local ok, _, height = pcall(fn)
	if ok and not Compat.IsSecret(height) and type(height) == "number" and height > 0 then return height end
	return nil
end

-- Where the pointer is, in the pixels of the screen (GetCursorPosition): x, y, or nil when the client cannot say or
-- hides it. A frame's own coordinates are these divided by its effective scale. Allocation-free: it runs while the pointer
-- is over the timeline (SPEC-05 §4.8). How it follows the UI and window scale is [to be tried in game].
function Compat.CursorPosition()
	local fn = Resolve("GetCursorPosition")
	if type(fn) ~= "function" then return nil end
	local ok, x, y = pcall(fn)
	if not ok or IsSecret(x) or IsSecret(y) or not plainNumber(x) or not plainNumber(y) then return nil end
	return x, y
end

-- Whether a modifier key is held: name "shift", "ctrl" or "alt" (the keys of the replay window, SPEC-05 §5.5): true or
-- false, nil when the client cannot say or hides it.
local MODIFIERS = { shift = "IsShiftKeyDown", ctrl = "IsControlKeyDown", alt = "IsAltKeyDown" }
function Compat.ModifierDown(name)
	local fn = MODIFIERS[name] and Resolve(MODIFIERS[name])
	if type(fn) ~= "function" then return nil end
	local ok, down = pcall(fn)
	if not ok or IsSecret(down) or type(down) ~= "boolean" then return nil end
	return down
end

-- A colour object for the widget methods that want one (SetGradient); a plain table when the client has no CreateColor.
function Compat.CreateColor(r, g, b, a)
	local fn = Resolve("CreateColor")
	if type(fn) == "function" then
		local ok, colour = pcall(fn, r, g, b, a)
		if ok and colour then return colour end
	end
	return { r = r, g = g, b = b, a = a }
end

-- The path of a font of the game, the fallback of an addon font: "FRIZQT" for the display face, anything else for text.
-- Interface globals the dump does not list.
function Compat.GameFontPath(key)
	local path = Resolve(key == "FRIZQT" and "UNIT_NAME_FONT" or "STANDARD_TEXT_FONT")
	return type(path) == "string" and path or "Fonts\\FRIZQT__.TTF"
end

-- The 9-slice mode of a texture (Enum.UITextureSliceMode.Stretched), 0 when the client does not name it.
function Compat.SliceModeStretched()
	local mode = Resolve("Enum.UITextureSliceMode.Stretched")
	return type(mode) == "number" and mode or 0
end

-- Plays the sound kit `kit` of the game (the sound of an alert, Data/Alerts.lua, SPEC-04 §1.4): true when the client
-- took the call, else false and why ("no-kit", "missing", "error", or "refused" when the client answers that it did not
-- play it). Both paths of the dump take the kit first; every other argument keeps its default. Never raises and
-- allocates nothing. Whether the kit exists and is heard on Forever is [to be tried in game].
function Compat.PlaySound(kit)
	if IsSecret(kit) or plainNumber(kit) == nil then return false, "no-kit" end
	local fn = Resolve("PlaySound")
	if type(fn) ~= "function" then fn = Resolve("C_Sound.PlaySound") end
	if type(fn) ~= "function" then return false, "missing" end
	local ok, played = pcall(fn, kit)
	if not ok then return false, "error" end
	if not IsSecret(played) and played == false then return false, "refused" end
	return true, nil
end

-- Whether the game's own threat warning is on (ALR-03, the note of the *Alerts* card): true or false, nil when the
-- client does not say (no function, an error, a secret or another type). What it shows on Forever is [to be tried in
-- game].
function Compat.ThreatWarningEnabled()
	local value = first("IsThreatWarningEnabled")
	if type(value) == "boolean" then return value end
	return nil
end

-- Reloads the interface (the *Reload now* button of Settings): true when the client took the call. A click is the
-- hardware event the client may ask for.
function Compat.Reload()
	local fn = Resolve("C_UI.Reload")
	if type(fn) ~= "function" then fn = Resolve("ReloadUI") end
	if type(fn) ~= "function" then return false end
	return (pcall(fn))
end

-- The game's own Settings window (interface code the dump does not list [to be tried in game]): true when a panel can
-- be registered in it.
function Compat.HasSettingsPanel()
	return type(Resolve("Settings.RegisterCanvasLayoutCategory")) == "function"
		and type(Resolve("Settings.RegisterAddOnCategory")) == "function"
end

-- Adds `frame` to Options > AddOns under `name`. Returns the category, or nil and "unavailable" or "failed". Never
-- raises.
function Compat.RegisterSettingsPanel(frame, name)
	if not Compat.HasSettingsPanel() then return nil, "unavailable" end
	local ok, category = pcall(function()
		local made = Resolve("Settings.RegisterCanvasLayoutCategory")(frame, name)
		Resolve("Settings.RegisterAddOnCategory")(made)
		return made
	end)
	if ok and category then return category end
	if not ok and ns.Diagnostics then ns.Diagnostics.Record(category) end
	return nil, "failed"
end

-- Esc closes the named frame (UISpecialFrames). False when the client has no such list.
function Compat.CloseOnEscape(frameName)
	local list = Resolve("UISpecialFrames")
	if type(list) ~= "table" or type(frameName) ~= "string" then return false end
	for i = 1, #list do
		if list[i] == frameName then return true end
	end
	list[#list + 1] = frameName
	return true
end

---------------------------------------------------------------------------------------------------------------------
-- Units and the group (M2.2: Data/TargetTracker.lua, Data/ThreatScanner.lua). Allocation-free, unlike Call and First:
-- they run on every scan of the threat tick (ARC-06). Each answers the value, or nil and why it is missing ("missing",
-- "error", "secret"); a secret answer is never kept (ARC-11). An argument that is a secret or not a string is
-- "no-unit", without a call.
---------------------------------------------------------------------------------------------------------------------
local Unit = {}
Compat.Unit = Unit

local function unitArg(unit) return type(unit) == "string" and not IsSecret(unit) end

-- The first value of path(a, b) under pcall, checked for secrecy.
local function one(path, a, b)
	local fn = Resolve(path)
	if type(fn) ~= "function" then return nil, "missing" end
	local ok, value = pcall(fn, a, b)
	if not ok then return nil, "error" end
	if IsSecret(value) then return nil, "secret" end
	return value, nil
end

-- A boolean question about one or two units: true, false, or nil and the reason.
local function ask(path, a, b)
	if not unitArg(a) or (b ~= nil and not unitArg(b)) then return nil, "no-unit" end
	local value, reason = one(path, a, b)
	if reason then return nil, reason end
	return value == true or (value ~= nil and value ~= false and value ~= 0), nil
end

function Unit.Exists(unit) return ask("UnitExists", unit) end
function Unit.IsDead(unit) return ask("UnitIsDead", unit) end
function Unit.CanAttack(unit, other) return ask("UnitCanAttack", unit, other) end
function Unit.IsUnit(unit, other) return ask("UnitIsUnit", unit, other) end
function Unit.AffectingCombat(unit) return ask("UnitAffectingCombat", unit) end

-- A non-empty string answer (GUID, name, role), or nil and the reason ("nil" when the client gave none).
local function text(path, unit)
	if not unitArg(unit) then return nil, "no-unit" end
	local value, reason = one(path, unit)
	if reason then return nil, reason end
	value = plainString(value)
	if value == nil then return nil, "nil" end
	return value, nil
end

-- The GUID of a unit [probe P9: readable and stable in instances?].
function Unit.GUID(unit) return text("UnitGUID", unit) end
-- The name shown for a unit (never stored outside the sessions, SPEC-02 §1) [probe P9].
function Unit.Name(unit) return text("UnitName", unit) end

-- The creature number of a mob from a readable GUID ("Creature-0-1-2-3-<npcID>-<spawn>", or "Vehicle-..."): the sixth
-- field, a whole number; nil and why otherwise ("no-guid": not a plain string or secret; "not-creature": a player, a
-- pet or another kind). Reads only the string it is given, never the game (SPEC-02 §4.1: `npc`, never the whole GUID).
function Unit.NpcID(guid)
	if type(guid) ~= "string" or IsSecret(guid) then return nil, "no-guid" end
	local kind, id = guid:match("^(%a+)%-[^-]*%-[^-]*%-[^-]*%-[^-]*%-(%d+)%-")
	if kind ~= "Creature" and kind ~= "Vehicle" then return nil, "not-creature" end
	return tonumber(id), nil
end

-- The classification of a unit ("normal", "elite", "rare", "rareelite", "worldboss", "minus"...) [probe P5].
function Unit.Classification(unit) return text("UnitClassification", unit) end

-- The class file ("WARRIOR"...), the second value of UnitClass.
function Unit.Class(unit)
	if not unitArg(unit) then return nil, "no-unit" end
	local fn = Resolve("UnitClass")
	if type(fn) ~= "function" then return nil, "missing" end
	local ok, _, classFile = pcall(fn, unit)
	if not ok then return nil, "error" end
	if IsSecret(classFile) then return nil, "secret" end
	classFile = plainString(classFile)
	if classFile == nil then return nil, "nil" end
	return classFile, nil
end

local ROLES = { TANK = "TANK", HEALER = "HEALER", DAMAGER = "DAMAGER" }
-- The assigned role: "TANK", "HEALER", "DAMAGER"; nil for NONE (reason "none") or when unknown [probe P9].
function Unit.Role(unit)
	local role, reason = text("UnitGroupRolesAssigned", unit)
	if reason then return nil, reason end
	if ROLES[role] then return ROLES[role], nil end
	return nil, "none"
end

-- The game's colour of a class file: r, g, b in 0..1, or nil (unknown class, no API, a secret or bad answer).
function Compat.ClassColor(classFile)
	if type(classFile) ~= "string" or IsSecret(classFile) then return nil end
	local fn = Resolve("C_ClassColor.GetClassColor")
	if type(fn) ~= "function" then return nil end
	local ok, color = pcall(fn, classFile)
	if not ok or IsSecret(color) or type(color) ~= "table" then return nil end
	local r, g, b = plainNumber(color.r), plainNumber(color.g), plainNumber(color.b)
	if r and g and b then return r, g, b end
	return nil
end

local Group = {}
Compat.Group = Group

-- true / false (false when the client cannot say).
function Group.InGroup() return (one("IsInGroup")) == true end
function Group.InRaid() return (one("IsInRaid")) == true end

-- How many members, the player included (0 when not in a group or unknown).
function Group.Size()
	local n = plainNumber((one("GetNumGroupMembers")))
	if n and n > 0 then return math.floor(n) end
	return 0
end

-- The player's own raidN index (UnitInRaid("player")), nil when not in a raid or unknown.
function Group.RaidIndex()
	local n = plainNumber((one("UnitInRaid", "player")))
	if n and n >= 1 then return math.floor(n) end
	return nil
end

---------------------------------------------------------------------------------------------------------------------
-- The normalized threat read (SPEC-01 §8.3), used from M2. Allocation-free: it fills the caller's record.
---------------------------------------------------------------------------------------------------------------------
local Threat = {}
Compat.Threat = Threat
Threat.MODES = { values = true, state = true, none = true }
-- How many reads ended in each mode and why the values were missing, for /atw debug (numbers only).
Threat.stats = { values = 0, state = 0, none = 0, secret = 0, ["nil"] = 0, error = 0, missing = 0, ["no-unit"] = 0 }

-- Asks a C_Secrets prediction; true only for a readable true. A missing, failing or secret answer is no prediction.
local function predicts(path, unit, mob)
	local fn = Resolve(path)
	if type(fn) ~= "function" then return false end
	local ok, answer = pcall(fn, unit, mob)
	if not ok or IsSecret(answer) then return false end
	return answer == true
end

local function clear(record)
	record.isTanking, record.situation, record.scaledPercent, record.rawPercent, record.rawThreat =
		nil, nil, nil, nil, nil
	record.leadPercent, record.leadSituation, record.leadReason = nil, nil, nil
end

local function finish(record, mode, reason)
	record.reason = reason
	record.source = mode == "none" and "unknown" or "detected"
	local stats = Threat.stats
	stats[mode] = stats[mode] + 1
	if reason then stats[reason] = (stats[reason] or 0) + 1 end
	return mode, record
end

-- The state only (UnitThreatSituation). `reason` says why the values are missing.
local function readState(unit, mob, record, reason)
	local fn = Resolve("UnitThreatSituation")
	if type(fn) ~= "function" then return finish(record, "none", reason or "missing") end
	local ok, status = pcall(fn, unit, mob)
	if not ok then return finish(record, "none", "error") end
	if IsSecret(status) then return finish(record, "none", "secret") end
	if plainNumber(status) == nil then return finish(record, "none", reason or "nil") end
	record.situation = status
	return finish(record, "state", reason)
end

-- Compat.Threat.Read(unit, mob, record) -> mode ("values", "state" or "none"), record. The record (SPEC-02 §1) gets
-- isTanking, situation, scaledPercent, rawPercent, rawThreat (nil when not known), observedAt, source ("detected", or
-- "unknown" with mode none) and reason (nil, "secret", "nil", "error", "missing", "no-unit"):
--   1. ShouldUnitThreatStateBeSecret(unit, mob) true  -> no call, mode none, reason secret;
--   2. ShouldUnitThreatValuesBeSecret(unit, mob) true -> UnitThreatSituation only, mode state, reason secret;
--   3. else UnitDetailedThreatSituation -> mode values; a value that is secret anyway clears the values and the read
--      goes down to the state (reason secret); a missing or failing function too (reason missing or error).
-- The shape of the arguments (token of the mob, as the dump says) and which prediction can be trusted are
-- [probe P2, P3]: they change here only. Without C_Secrets only the checks of the values remain (ARC-11).
function Threat.Read(unit, mob, record)
	clear(record)
	record.observedAt = Compat.Now()
	if IsSecret(unit) or IsSecret(mob) or type(unit) ~= "string" or type(mob) ~= "string" then
		return finish(record, "none", "no-unit")
	end
	if predicts("C_Secrets.ShouldUnitThreatStateBeSecret", unit, mob) then
		return finish(record, "none", "secret")
	end
	if predicts("C_Secrets.ShouldUnitThreatValuesBeSecret", unit, mob) then
		return readState(unit, mob, record, "secret")
	end
	local fn = Resolve("UnitDetailedThreatSituation")
	if type(fn) ~= "function" then return readState(unit, mob, record, "missing") end
	local ok, tanking, status, scaled, raw, threat = pcall(fn, unit, mob)
	if not ok then return readState(unit, mob, record, "error") end
	if IsSecret(tanking) or IsSecret(status) or IsSecret(scaled) or IsSecret(raw) or IsSecret(threat) then
		if not IsSecret(status) and plainNumber(status) then
			record.situation = status
			return finish(record, "state", "secret")
		end
		return readState(unit, mob, record, "secret")
	end
	status = plainNumber(status)
	if status == nil then return finish(record, "none", "nil") end   -- the unit is not on the mob's threat list
	record.situation = status
	if type(tanking) == "boolean" then record.isTanking = tanking end
	record.scaledPercent, record.rawPercent, record.rawThreat = plainNumber(scaled), plainNumber(raw), plainNumber(threat)
	return finish(record, "values", nil)
end

-- One number of a lead function (UnitThreatPercentageOfLead, UnitThreatLeadSituation): the value or nil, and the
-- reason it is missing ("missing", "error", "secret", "nil").
local function leadValue(path, holder, mob)
	local fn = Resolve(path)
	if type(fn) ~= "function" then return nil, "missing" end
	local ok, value = pcall(fn, holder, mob)
	if not ok then return nil, "error" end
	if IsSecret(value) then return nil, "secret" end
	value = plainNumber(value)
	if value == nil then return nil, "nil" end
	return value, nil
end

-- Compat.Threat.ReadLead(holder, mob, record) -> the record, with leadPercent (UnitThreatPercentageOfLead) and
-- leadSituation (UnitThreatLeadSituation) of the unit that holds the mob, nil when unknown, and leadReason (why the
-- percentage, or failing that the situation, is missing). Called once per scan for the holder only (SPEC-03 §1.6,
-- §2.2); the meaning of the percentage is [probe P2]. Allocation-free; a Read of the same record clears these fields.
-- With the values predicted secret the percentage is not asked; with the state predicted secret neither is.
function Threat.ReadLead(holder, mob, record)
	record.leadPercent, record.leadSituation, record.leadReason = nil, nil, nil
	if IsSecret(holder) or IsSecret(mob) or type(holder) ~= "string" or type(mob) ~= "string" then
		record.leadReason = "no-unit"
		return record
	end
	if predicts("C_Secrets.ShouldUnitThreatStateBeSecret", holder, mob) then
		record.leadReason = "secret"
		return record
	end
	local percentReason
	if predicts("C_Secrets.ShouldUnitThreatValuesBeSecret", holder, mob) then
		percentReason = "secret"
	else
		record.leadPercent, percentReason = leadValue("UnitThreatPercentageOfLead", holder, mob)
	end
	local situationReason
	record.leadSituation, situationReason = leadValue("UnitThreatLeadSituation", holder, mob)
	record.leadReason = percentReason or situationReason
	return record
end

-- A record with every field of SPEC-02 §1 (the pool of M2 makes them; tests and the report use this one).
function Threat.NewRecord()
	return { observedAt = 0, source = "unknown", confidence = "unknown" }
end

---------------------------------------------------------------------------------------------------------------------
-- /atw debug lines
---------------------------------------------------------------------------------------------------------------------
local function withDetail(state, detail)
	if detail then return state .. " (" .. detail .. ")" end
	return state
end

function Compat.ApiLines()
	if not Compat.probed then return { "not probed yet" } end
	local lines, counts = {}, { available = 0, missing = 0, restricted = 0, error = 0 }
	for _, entry in ipairs(Compat.APIS) do
		local r = Compat.api[entry.id] or { state = UNKNOWN }
		counts[r.state] = (counts[r.state] or 0) + 1
		local line = entry.id .. ": " .. withDetail(r.state, r.detail)
		if r.value then line = line .. " = " .. r.value end
		if r.path and r.path ~= entry.paths[1] then line = line .. " [" .. r.path .. "]" end
		lines[#lines + 1] = line
	end
	table.insert(lines, 1, ("%d available, %d missing, %d restricted, %d error"):format(counts.available,
		counts.missing, counts.restricted, counts.error))
	return lines
end

function Compat.CapabilityLines()
	local lines = {}
	for _, id in ipairs(Compat.CAPABILITIES) do
		lines[#lines + 1] = id .. ": " .. withDetail(Compat.Capability(id))
	end
	local extra = {}
	for id in pairs(Compat.capabilities) do
		if not id:find("^restricted%.") then
			local known = false
			for _, k in ipairs(Compat.CAPABILITIES) do if k == id then known = true break end end
			if not known then extra[#extra + 1] = id end
		end
	end
	table.sort(extra)
	for _, id in ipairs(extra) do lines[#lines + 1] = id .. ": " .. withDetail(Compat.Capability(id)) end
	local s = Threat.stats
	lines[#lines + 1] = ("threat reads: %d values, %d state, %d none (secret %d, nil %d, error %d, missing %d)"):format(
		s.values, s.state, s.none, s.secret, s["nil"], s.error, s.missing)
	return lines
end

function Compat.RestrictionLines()
	local lines = { "combat lockdown: " .. (Compat.InCombatLockdown() and "yes" or "no") }
	if #Compat.restrictionTypes == 0 then
		lines[#lines + 1] = "restriction types: unknown (Enum.AddOnRestrictionType missing)"
		return lines
	end
	local active = Compat.ActiveRestrictions()
	lines[#lines + 1] = "active: " .. (#active > 0 and table.concat(active, ", ") or "none")
	for _, t in ipairs(Compat.restrictionTypes) do
		lines[#lines + 1] = ("%s (%d): %s"):format(t.name, t.value, withDetail(Compat.Capability("restricted." .. t.name)))
	end
	return lines
end
