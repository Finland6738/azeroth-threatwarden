-- Config: the two SavedVariables, their schemas (account 6, character 2), typed rules, defaults, migrations, read-only on a newer schema and damaged
-- tables set aside under `corrupt` (SPEC-02 §3, ADR 0005). Lua 5.1, no game API but Compat.ServerTime.
-- Adapted from Azeroth Accord (Core/Config.lua), same owner, GPL-3.0 (ADR 0012). Kept from there: the copy, the rules
-- by path checked parents first, the merge of the defaults, the migrations on a copy, read-only on a newer schema, Get
-- and Set by path, the size estimate. Changed: the version key is `schema`; a damaged table is set aside in
-- `account.corrupt` before it goes back to its default; a missing migration step fails like a step that raises; the
-- window size is brought within its limits and the scale rounded instead of reset; Set refuses a whole container and
-- emits only when the value changes; the token, the guild maps and the Base64 helpers of Accord are not needed here.
--
--   AzerothThreatwardenDB      (account)   = { schema, settings = { language, theme, effects, animations, font,
--                                               minimap = { hide, minimapPos }, monitor = { warning, danger, rate,
--                                               maxUnits, show, sort, pinSelf, followTargetOfTarget },
--                                               alerts = { enabled, window, visual, sound, cooldown, others, pet,
--                                               onlyTarget }, coach = { enabled },
--                                               mobs = { enabled, max, nameplates },
--                                               recording = { enabled, when, rate, maxSessions, maxKB, notice } },
--                                               sessions = { ... }, corrupt = { ... } }
--   AzerothThreatwardenCharDB  (character) = { schema, ui = { shown, locked, scale, pos, size, lastTab, lastPage,
--                                               replay = { pos, size, speed } } }
--
-- Load() runs at ADDON_LOADED (Core/Init.lua, before Locale.Apply): the defaults are added without overwriting, old data
-- is migrated step by step, wrong values go back to their defaults and are listed in Config.issues (paths, never
-- names). Data of a NEWER schema is never rewritten: the addon works on a copy and Set refuses (Config:IsReadOnly).
-- Unknown keys stay as they are. Nothing here holds a player, guild or realm name (SPEC-02 §3.3).
--
-- Every module reads its settings with Config:Get(path) and writes them with Config:Set(path, value); the language
-- the interface uses is the one place `account.settings.language` (SPEC-09 Q5), applied by Core/Locale.lua at load.
local ADDON_NAME, ns = ...
ns = ns or {}
ns.modules = ns.modules or {}

local Config = {}
ns.Config, ns.modules.Config = Config, Config

local type, pairs, ipairs, pcall, tostring, next, select = type, pairs, ipairs, pcall, tostring, next, select
local floor, huge, abs = math.floor, math.huge, math.abs
local concat, sort = table.concat, table.sort

-- The schema of each variable that this version of the addon knows (SPEC-02 §3.2, §3.3, §3.5-§3.10).
Config.SCHEMAS = { account = 6, char = 2 }

-- Development build. A checkout of the repository is one; the BigWigs packager comments out the block between the
-- debug markers below in every packaged build, so a release has DEV = false (tools/check_package.py checks it).
Config.DEV = false
--@debug@
Config.DEV = true
--@end-debug@
Config.VARIABLES = { account = "AzerothThreatwardenDB", char = "AzerothThreatwardenCharDB" }
Config.SCOPES = { "account", "char" }

-- The enumerations of SPEC-02 §3.2 and §3.3. LANGUAGES is the one list of the languages a player can choose: every
-- code but "auto" has its file in Locales/ (test_language.lua checks both ways).
Config.LANGUAGES = { "auto", "enUS", "itIT" }
Config.THEMES = { "nebula", "aurora", "warden" }
Config.FONT_SOURCES = { "addon", "game" }
Config.TABS = { "monitor", "settings", "reports" }   -- "reports" from M4 (shown only with its switch, UI/Window.lua)
Config.PAGES = { "settings", "about" }
-- The monitor (schema 2, SPEC-02 §3.5): when the window shows itself (SPEC-03 §5.1) and the list orders (§3).
Config.SHOW_MODES = { "auto", "always", "manual" }
Config.SORTS = { "relative", "absolute", "risk", "change" }

-- The ranges of the monitor's settings. `gap`: danger is at least that many points above warning (more than the
-- hysteresis of Data/ThreatState.lua); a pair that breaks it goes back to both defaults.
Config.MONITOR = {
	warning = { min = 50, max = 99 },
	danger = { min = 60, max = 100 },
	rate = { min = 2, max = 10 },
	maxUnits = { min = 5, max = 40 },
	gap = 5,
}
-- The one place of the monitor's defaults (SPEC-09): the thresholds (Q7, decided by the owner on 2026-11-26: from 82 %
-- ease off, from 91 % stop for a moment), when the window shows itself (Q13), the sampling rate and the units read per
-- scan (Q14, provisional until the probe P10 measures them in the game; their offline cost is in SPEC-01 §5.1).
Config.MONITOR_DEFAULTS = {
	warning = 82, danger = 91,
	rate = 5, maxUnits = 40,
	show = "auto",
	sort = "relative", pinSelf = false,
	followTargetOfTarget = true,
}
-- The alerts (schema 3, SPEC-04 §4.1): who may be alerted about besides the player and the pet, the range of the
-- cooldown (seconds) and the one place of their defaults, the proposed answers of Q12 (SPEC-09). `onlyTarget` (schema 6,
-- SPEC-07 §2.5, Q26): alerts only about the monitored mob; it counts as on while the `multitarget` switch is off.
Config.ALERT_OTHERS = { "tank", "always", "never" }
Config.ALERTS = { cooldown = { min = 3, max = 30 } }
Config.ALERTS_DEFAULTS = {
	enabled = true,
	window = true, visual = true, sound = false,
	cooldown = 8,
	others = "tank", pet = true,
	onlyTarget = true,
}
-- The other mobs (schema 6, SPEC-02 §3.10, SPEC-07 §1.9): the range of the mobs followed (the monitored mob included,
-- MT-02) and the one place of the defaults, the proposed answers of Q26 (SPEC-09).
Config.MOBS = { max = { min = 2, max = 12 } }
Config.MOBS_DEFAULTS = {
	enabled = true,
	max = 8,
	nameplates = true,
}
-- The Threat Coach (schema 3, SPEC-04 §4.1): the one place of its defaults.
Config.COACH_DEFAULTS = {
	enabled = true,
}
-- The recording (schema 4, SPEC-02 §3.7, SPEC-05 §1.1): when a fight is recorded, the ranges and the one place of the
-- defaults, the proposed answers of Q8 (how many sessions and how much) and Q16 (when, how often, the notice).
Config.RECORD_WHEN = { "group", "instance", "always" }
Config.RECORDING = {
	rate = { min = 1, max = 5 },              -- Hz of the recording tick
	maxSessions = { min = 5, max = 100 },
	maxKB = { min = 512, max = 8192 },        -- estimated KB of all the sessions
}
Config.RECORDING_DEFAULTS = {
	enabled = true,
	when = "group",
	rate = 2,
	maxSessions = 25,
	maxKB = 2048,
	notice = false,
}
Config.POINTS = { "TOPLEFT", "TOP", "TOPRIGHT", "LEFT", "CENTER", "RIGHT", "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT" }

-- The window: scale 50-200 % in steps of 5 %; the sizes of the two layouts (SPEC-03 §4) and of the replay window
-- (SPEC-05 §5.5).
Config.SCALE = { min = 0.5, max = 2.0, step = 0.05 }
Config.SIZES = {
	compact = { minW = 220, minH = 140, maxW = 600, maxH = 800 },
	wide = { minW = 480, minH = 420, maxW = 900, maxH = 900 },
	replay = { minW = 640, minH = 420, maxW = 1400, maxH = 1000 },
}

-- `account.corrupt`: at most MAX_CORRUPT entries, the oldest goes first; the copy of a damaged table keeps
-- CORRUPT_DEPTH levels and CORRUPT_KEYS keys in all, strings cut at CORRUPT_TEXT characters.
Config.MAX_CORRUPT = 5
Config.CORRUPT_DEPTH = 3
Config.CORRUPT_KEYS = 50
Config.CORRUPT_TEXT = 200
Config.MAX_ISSUES = 50      -- problems kept from one Load (the report shows the first ones)

Config.defaults = {
	account = {
		schema = Config.SCHEMAS.account,
		settings = {
			language = "auto",        -- SPEC-09 Q5: follows the client; takes effect after /reload
			theme = "nebula",         -- UI/Theme.lua (M1.6)
			effects = true,
			animations = true,
			font = "addon",           -- takes effect when the client restarts
			minimap = { hide = false, minimapPos = 200 },   -- handed to LibDBIcon (M1.7), which may add keys of its own
			monitor = {},             -- filled from MONITOR_DEFAULTS below
			alerts = {},              -- filled from ALERTS_DEFAULTS below
			coach = {},               -- filled from COACH_DEFAULTS below
			recording = {},           -- filled from RECORDING_DEFAULTS below
			mobs = {},                -- filled from MOBS_DEFAULTS below (schema 6, M7)
		},
		sessions = {},                -- the recorded sessions, the oldest first (SPEC-02 §4; their content is Storage's)
		corrupt = {},
	},
	char = {
		schema = Config.SCHEMAS.char,
		ui = {
			shown = true,
			locked = false,
			scale = 1.0,
			-- pos: nil until the window is moved (the centre)
			size = {},                -- compact = { w, h }, wide = { w, h }: nil until resized
			lastTab = "monitor",
			lastPage = "settings",
			-- the replay window (schema 2, SPEC-02 §3.9): pos and size nil until moved or resized
			replay = { speed = 1 },
		},
	},
}

for key, value in pairs(Config.MONITOR_DEFAULTS) do Config.defaults.account.settings.monitor[key] = value end
for key, value in pairs(Config.ALERTS_DEFAULTS) do Config.defaults.account.settings.alerts[key] = value end
for key, value in pairs(Config.COACH_DEFAULTS) do Config.defaults.account.settings.coach[key] = value end
for key, value in pairs(Config.RECORDING_DEFAULTS) do Config.defaults.account.settings.recording[key] = value end
for key, value in pairs(Config.MOBS_DEFAULTS) do Config.defaults.account.settings.mobs[key] = value end

---------------------------------------------------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------------------------------------------------
local function isFinite(v)
	return type(v) == "number" and v == v and v ~= huge and v ~= -huge
end
Config.IsFinite = isFinite

local function copy(value, seen)
	if type(value) ~= "table" then return value end
	seen = seen or {}
	if seen[value] then return seen[value] end
	local out = {}
	seen[value] = out
	for k, v in pairs(value) do out[copy(k, seen)] = copy(v, seen) end
	return out
end
Config.Copy = copy

-- true when a and b hold the same plain content (CONFIG_CHANGED is emitted only on a change).
local function same(a, b)
	if a == b then return true end
	if type(a) ~= "table" or type(b) ~= "table" then return false end
	for k, v in pairs(a) do if not same(v, b[k]) then return false end end
	for k in pairs(b) do if a[k] == nil then return false end end
	return true
end

local function contains(list, value)
	for _, option in ipairs(list) do if option == value then return true end end
	return false
end

local function emit(event, ...)
	if ns.Bus then ns.Bus.Emit(event, ...) end
end

local function split(path)
	local parts = {}
	for part in tostring(path):gmatch("[^.]+") do parts[#parts + 1] = part end
	return parts
end

-- The table that holds `path` (from part `from` on) and the key: nil when a parent is missing or not a table.
local function locate(root, parts, from)
	local node = root
	for i = from, #parts - 1 do
		node = node[parts[i]]
		if type(node) ~= "table" then return nil end
	end
	return node, parts[#parts]
end

-- A window position: { point, relativePoint, x, y }, both points among the nine anchors, x and y finite.
function Config.IsPos(v)
	return type(v) == "table" and contains(Config.POINTS, v.point) and contains(Config.POINTS, v.relativePoint)
		and isFinite(v.x) and isFinite(v.y)
end

-- A size of one layout: { w, h } finite numbers (the limits are applied by clamping, not by refusing).
function Config.IsSize(v)
	return type(v) == "table" and isFinite(v.w) and isFinite(v.h)
end

local function clamp(v, lo, hi)
	if v < lo then return lo end
	if v > hi then return hi end
	return v
end

local function sizeFixer(layout)
	return function(v)
		local lim = Config.SIZES[layout]
		local w, h = clamp(v.w, lim.minW, lim.maxW), clamp(v.h, lim.minH, lim.maxH)
		if w == v.w and h == v.h then return v end
		local out = copy(v)
		out.w, out.h = w, h
		return out, "brought within the limits"
	end
end

local function roundScale(v)
	local step = Config.SCALE.step
	local r = floor(v / step + 0.5) * step
	if abs(r - v) < 1e-9 then return v end
	return r, "rounded to " .. step
end

---------------------------------------------------------------------------------------------------------------------
-- Rules
---------------------------------------------------------------------------------------------------------------------
-- By path, scope first. type: boolean | number | string | table. number: min, max, integer, check(v). string: enum.
-- table: validate(v) for the whole table. optional: nil is allowed (the default is nil). fix(v) -> value, note: a value that
-- passes the rule but is corrected (clamped, rounded); note nil when nothing changed. container: a table that holds
-- other rules (Set refuses it whole). keep = false: a damaged value is reset without a `corrupt` entry.
local function isArrayOfTables(v)
	local n = #v
	for k, x in pairs(v) do
		if type(k) ~= "number" or k < 1 or k > n or k ~= floor(k) or type(x) ~= "table" then return false end
	end
	return true
end

Config.rules = {
	["account.settings"] = { type = "table", container = true },
	["account.settings.language"] = { type = "string", enum = Config.LANGUAGES },
	["account.settings.theme"] = { type = "string", enum = Config.THEMES },
	["account.settings.effects"] = { type = "boolean" },
	["account.settings.animations"] = { type = "boolean" },
	["account.settings.font"] = { type = "string", enum = Config.FONT_SOURCES },
	["account.settings.minimap"] = { type = "table", container = true },
	["account.settings.minimap.hide"] = { type = "boolean" },
	["account.settings.minimap.minimapPos"] = { type = "number", min = 0, max = 360 },
	["account.settings.monitor"] = { type = "table", container = true },
	["account.settings.monitor.warning"] = { type = "number", integer = true, min = Config.MONITOR.warning.min,
		max = Config.MONITOR.warning.max },
	["account.settings.monitor.danger"] = { type = "number", integer = true, min = Config.MONITOR.danger.min,
		max = Config.MONITOR.danger.max },
	["account.settings.monitor.rate"] = { type = "number", integer = true, min = Config.MONITOR.rate.min,
		max = Config.MONITOR.rate.max },
	["account.settings.monitor.maxUnits"] = { type = "number", integer = true, min = Config.MONITOR.maxUnits.min,
		max = Config.MONITOR.maxUnits.max },
	["account.settings.monitor.show"] = { type = "string", enum = Config.SHOW_MODES },
	["account.settings.monitor.sort"] = { type = "string", enum = Config.SORTS },
	["account.settings.monitor.pinSelf"] = { type = "boolean" },
	["account.settings.monitor.followTargetOfTarget"] = { type = "boolean" },
	["account.settings.alerts"] = { type = "table", container = true },
	["account.settings.alerts.enabled"] = { type = "boolean" },
	["account.settings.alerts.window"] = { type = "boolean" },
	["account.settings.alerts.visual"] = { type = "boolean" },
	["account.settings.alerts.sound"] = { type = "boolean" },
	["account.settings.alerts.cooldown"] = { type = "number", integer = true, min = Config.ALERTS.cooldown.min,
		max = Config.ALERTS.cooldown.max },
	["account.settings.alerts.others"] = { type = "string", enum = Config.ALERT_OTHERS },
	["account.settings.alerts.pet"] = { type = "boolean" },
	["account.settings.alerts.onlyTarget"] = { type = "boolean" },
	["account.settings.mobs"] = { type = "table", container = true },
	["account.settings.mobs.enabled"] = { type = "boolean" },
	["account.settings.mobs.max"] = { type = "number", integer = true, min = Config.MOBS.max.min,
		max = Config.MOBS.max.max },
	["account.settings.mobs.nameplates"] = { type = "boolean" },
	["account.settings.coach"] = { type = "table", container = true },
	["account.settings.coach.enabled"] = { type = "boolean" },
	["account.settings.recording"] = { type = "table", container = true },
	["account.settings.recording.enabled"] = { type = "boolean" },
	["account.settings.recording.when"] = { type = "string", enum = Config.RECORD_WHEN },
	["account.settings.recording.rate"] = { type = "number", integer = true, min = Config.RECORDING.rate.min,
		max = Config.RECORDING.rate.max },
	["account.settings.recording.maxSessions"] = { type = "number", integer = true,
		min = Config.RECORDING.maxSessions.min, max = Config.RECORDING.maxSessions.max },
	["account.settings.recording.maxKB"] = { type = "number", integer = true, min = Config.RECORDING.maxKB.min,
		max = Config.RECORDING.maxKB.max },
	["account.settings.recording.notice"] = { type = "boolean" },
	-- Config checks only that `sessions` is a table (anything else: its type in `corrupt`, a new table); every session
	-- is checked by Data/Storage.lua (M4.3, SPEC-02 §3.7).
	["account.sessions"] = { type = "table", container = true },
	["account.corrupt"] = { type = "table", container = true, keep = false, validate = isArrayOfTables,
		fix = function(v)
			if #v <= Config.MAX_CORRUPT then return v end
			local out = {}
			for i = #v - Config.MAX_CORRUPT + 1, #v do out[#out + 1] = v[i] end
			return out, "oldest entries dropped"
		end },
	["char.ui"] = { type = "table", container = true },
	["char.ui.shown"] = { type = "boolean" },
	["char.ui.locked"] = { type = "boolean" },
	["char.ui.scale"] = { type = "number", min = Config.SCALE.min, max = Config.SCALE.max, fix = roundScale },
	["char.ui.pos"] = { type = "table", optional = true, validate = Config.IsPos },
	["char.ui.size"] = { type = "table", container = true },
	["char.ui.size.compact"] = { type = "table", optional = true, validate = Config.IsSize, fix = sizeFixer("compact") },
	["char.ui.size.wide"] = { type = "table", optional = true, validate = Config.IsSize, fix = sizeFixer("wide") },
	["char.ui.lastTab"] = { type = "string", enum = Config.TABS },
	["char.ui.lastPage"] = { type = "string", enum = Config.PAGES },
	["char.ui.replay"] = { type = "table", container = true },
	["char.ui.replay.pos"] = { type = "table", optional = true, validate = Config.IsPos },
	["char.ui.replay.size"] = { type = "table", optional = true, validate = Config.IsSize, fix = sizeFixer("replay") },
	-- the speeds are those of Data/Replay.lua (SPEC-09 Q19: one place), loaded after this file
	["char.ui.replay.speed"] = { type = "number", check = function(v)
		local speeds = ns.Replay and ns.Replay.SPEEDS
		return speeds ~= nil and contains(speeds, v)
	end },
}

-- nil when `value` satisfies `rule`, else the reason (fixed words, no value).
local function violation(rule, value)
	if value == nil then return (not rule.optional) and "missing" or nil end
	local t = rule.type
	if type(value) ~= t then return "expected " .. t .. ", got " .. type(value) end
	if t == "number" then
		if not isFinite(value) then return "not a finite number" end
		if rule.integer and value ~= floor(value) then return "not an integer" end
		if rule.min and value < rule.min then return "below " .. rule.min end
		if rule.max and value > rule.max then return "above " .. rule.max end
		if rule.check and not rule.check(value) then return "not an allowed value" end
	elseif t == "string" then
		if rule.enum and not contains(rule.enum, value) then return "not an allowed value" end
	elseif t == "table" and rule.validate and not rule.validate(value) then
		return "bad shape"
	end
	return nil
end
Config.Violation = violation

local THRESHOLDS = { "account.settings.monitor.warning", "account.settings.monitor.danger" }
Config.THRESHOLD_PATHS = THRESHOLDS

-- nil when the two thresholds keep the gap, else the reason (fixed words).
local function pairViolation(warning, danger)
	if danger < warning + Config.MONITOR.gap then
		return "danger less than " .. Config.MONITOR.gap .. " above warning"
	end
	return nil
end

-- The default of a path below its scope, a fresh copy.
local function defaultAt(scope, parts, from)
	local node = Config.defaults[scope]
	for i = from, #parts do
		if type(node) ~= "table" then return nil end
		node = node[parts[i]]
	end
	return copy(node)
end

-- Fills what is missing from `defaults`, recursively; an existing value is never overwritten.
local function mergeDefaults(db, defaults)
	for k, v in pairs(defaults) do
		if db[k] == nil then
			db[k] = copy(v)
		elseif type(v) == "table" and type(db[k]) == "table" then
			mergeDefaults(db[k], v)
		end
	end
end
Config.MergeDefaults = mergeDefaults

---------------------------------------------------------------------------------------------------------------------
-- Problems and `corrupt`
---------------------------------------------------------------------------------------------------------------------
Config.issues = {}          -- problems found and fixed by the last Load (paths and fixed words, no names)
Config.readOnly = {}        -- readOnly[scope] = "newer" | "migration": writes refused, the variable never rewritten
Config.db = {}              -- Config.db.account / Config.db.char: the tables the addon works on
Config.found = {}           -- found[scope]: the schema in the saved data, "none" (nothing saved) or "damaged"
local pending = {}          -- `corrupt` entries of this Load, added to account.corrupt at its end

local function issue(text)
	if #Config.issues < Config.MAX_ISSUES then Config.issues[#Config.issues + 1] = text end
end

-- A bounded copy of a damaged value for `corrupt`: plain values only, CORRUPT_DEPTH levels, CORRUPT_KEYS keys.
local function boundedCopy(value)
	local budget = Config.CORRUPT_KEYS
	local function plain(v)
		local t = type(v)
		if t == "number" then return isFinite(v) and v or tostring(v) end
		if t == "string" then return #v > Config.CORRUPT_TEXT and v:sub(1, Config.CORRUPT_TEXT) or v end
		if t == "boolean" then return v end
		return "<" .. t .. ">"
	end
	local function walk(t, depth)
		local out = {}
		for k, v in pairs(t) do
			if budget <= 0 then break end
			local kt = type(k)
			if (kt == "string" or kt == "boolean" or (kt == "number" and isFinite(k))) then
				budget = budget - 1
				if type(v) == "table" then
					if depth < Config.CORRUPT_DEPTH then out[plain(k)] = walk(v, depth + 1) else out[plain(k)] = "<table>" end
				else
					out[plain(k)] = plain(v)
				end
			end
		end
		return out
	end
	return walk(value, 1)
end
Config.BoundedCopy = boundedCopy

-- Sets a damaged value aside: { scope, path, at, kind, data } (data only for a table).
local function setAside(scope, path, value)
	local Compat = ns.Compat
	pending[#pending + 1] = {
		scope = scope,
		path = path,
		at = Compat and Compat.ServerTime and Compat.ServerTime() or 0,
		kind = type(value),
		data = type(value) == "table" and boundedCopy(value) or nil,
	}
end

-- Adds the entries of this Load to account.corrupt, the oldest dropped beyond MAX_CORRUPT. A read-only account gets
-- them in its working copy only (never saved).
local function flushCorrupt()
	local db = Config.db.account
	if not db or #pending == 0 then pending = {} return end
	local list = db.corrupt
	for _, entry in ipairs(pending) do list[#list + 1] = entry end
	while #list > Config.MAX_CORRUPT do table.remove(list, 1) end
	pending = {}
end

-- A damaged value that another module checks sets itself aside (SPEC-02 §3.7, M4.3): a session of `account.sessions`
-- that Data/Storage.lua finds damaged goes into `corrupt` on its own, with the bounded copy of §3.4 (the caller passes
-- only what may be kept: for a session its header, never the columns). `kind` is the type found unless given
-- ("session"). The oldest entries go beyond MAX_CORRUPT. Refused while the account is read-only (nothing is written).
-- Returns true, or false and the reason.
function Config:SetAside(path, value, kind)
	if type(path) ~= "string" or path == "" then return false, "unknown path" end
	local db = Config.db.account
	if not db or type(db.corrupt) ~= "table" then return false, "not loaded" end
	if Config.readOnly.account then return false, "read-only" end
	local Compat = ns.Compat
	local list = db.corrupt
	list[#list + 1] = {
		scope = path:match("^(%a+)%.") or path,
		path = path,
		at = Compat and Compat.ServerTime and Compat.ServerTime() or 0,
		kind = type(kind) == "string" and kind or type(value),
		data = type(value) == "table" and boundedCopy(value) or nil,
	}
	while #list > Config.MAX_CORRUPT do table.remove(list, 1) end
	return true
end

-- A problem found and fixed by a module that checks its own data at CONFIG_LOADED (Storage): a path and fixed words,
-- never a value or a name. Listed with those of the last Load (/atw debug).
function Config.AddIssue(text)
	if type(text) == "string" then issue(text) end
end

---------------------------------------------------------------------------------------------------------------------
-- Sanitize: the rules, parents first
---------------------------------------------------------------------------------------------------------------------
local function depthOf(path) return select(2, path:gsub("%.", "")) end

local function rulePaths(scope)
	local paths, prefix = {}, scope .. "."
	for path in pairs(Config.rules) do
		if path:sub(1, #prefix) == prefix then paths[#paths + 1] = path end
	end
	sort(paths, function(a, b)   -- parents first, so a reset parent is checked again below
		local da, db = depthOf(a), depthOf(b)
		if da ~= db then return da < db end
		return a < b
	end)
	return paths
end

-- Brings `db` (the working table of `scope`) within the rules. Returns the number of fixes.
function Config.Sanitize(scope, db)
	local before = #Config.issues
	for _, path in ipairs(rulePaths(scope)) do
		local rule = Config.rules[path]
		local parts = split(path)
		local parent, key = locate(db, parts, 2)
		if parent then
			local value = parent[key]
			local why = violation(rule, value)
			if why then
				if rule.type == "table" and value ~= nil and rule.keep ~= false then setAside(scope, path, value) end
				parent[key] = defaultAt(scope, parts, 2)
				issue(path .. ": reset (" .. why .. ")")
			elseif rule.fix and value ~= nil then
				local fixed, note = rule.fix(value)
				if note then
					parent[key] = fixed
					issue(path .. ": " .. note)
				end
			end
		end
	end
	-- the pair of the thresholds, once each of them is right by itself: if it breaks the gap, both go back
	local monitor = scope == "account" and type(db.settings) == "table" and db.settings.monitor
	if type(monitor) == "table" then
		local why = pairViolation(monitor.warning, monitor.danger)
		if why then
			monitor.warning, monitor.danger = Config.MONITOR_DEFAULTS.warning, Config.MONITOR_DEFAULTS.danger
			issue("account.settings.monitor: thresholds reset (" .. why .. ")")
		end
	end
	return #Config.issues - before
end

---------------------------------------------------------------------------------------------------------------------
-- Migrations
---------------------------------------------------------------------------------------------------------------------
-- Config.migrations[scope][n] brings the data from version n - 1 to n. Each step is idempotent (on data that already
-- has the new shape it changes nothing) and has a test that starts from the data of the version before (DAT-20).
-- Step 1: data without a version is version 0 and needs only the defaults and the rules, so it has nothing to do.
-- Account step 2 (M2.6): `settings.monitor` is new, and the defaults add its keys: nothing to do either.
-- Account step 3 (M3.2, M3.3): `settings.alerts` and `settings.coach` are new: the defaults again.
-- Account step 4 (M4.2): `settings.recording` and `sessions` are new: the defaults again (a `sessions` already there
-- stays as it is; Storage checks it, SPEC-05 §2.3).
-- Account step 5 (fix Q7): the default thresholds went from 80 / 95 to 82 / 91. The defaults are written into the saved
-- data, so a pair still at exactly 80 and 95 is the old default and moves to the new one; any other pair is the
-- player's and stays (one threshold changed counts as the player's choice of the pair).
-- Account step 6 (M7.2): `settings.mobs` and `settings.alerts.onlyTarget` are new, and the defaults add them: nothing to
-- do (a key already there stays and the rules check it). Written with the `multitarget` switch off too.
-- Character step 2 (M5.5): `ui.replay` is new, and the defaults add it: nothing to do (a key already there stays and
-- the rules check it).
Config.OLD_THRESHOLDS = { warning = 80, danger = 95 }
Config.migrations = {
	account = {
		[1] = function(db) end,
		[2] = function(db) end,
		[3] = function(db) end,
		[4] = function(db) end,
		[5] = function(db)
			local monitor = type(db.settings) == "table" and db.settings.monitor or nil
			if type(monitor) ~= "table" then return end
			local old = Config.OLD_THRESHOLDS
			if monitor.warning == old.warning and monitor.danger == old.danger then
				monitor.warning, monitor.danger = Config.MONITOR_DEFAULTS.warning, Config.MONITOR_DEFAULTS.danger
			end
		end,
		[6] = function(db) end,
	},
	char = {
		[1] = function(db) end,
		[2] = function(db) end,
	},
}

-- Runs the steps after `from` up to `target` on `db`. Returns true, or false and the reason (db may be half changed:
-- callers pass a copy). A missing step fails too: every version has its step.
local function migrate(scope, db, from, target)
	local steps = Config.migrations[scope] or {}
	for n = from + 1, target do
		local step = steps[n]
		if type(step) ~= "function" then return false, "step " .. n .. " missing" end
		local ok, err = pcall(step, db)
		if not ok then return false, "step " .. n .. " failed" end
		db.schema = n
	end
	return true
end
Config.Migrate = migrate

---------------------------------------------------------------------------------------------------------------------
-- Load (SPEC-02 §3.4)
---------------------------------------------------------------------------------------------------------------------
-- The version in the saved table: a whole number >= 0, 0 when absent, nil when damaged.
local function schemaOf(raw)
	local v = raw.schema
	if v == nil then return 0 end
	if isFinite(v) and v >= 0 and v == floor(v) then return v end
	return nil
end

local function loadScope(scope)
	local var = Config.VARIABLES[scope]
	local raw = _G[var]       -- the addon's own SavedVariables (TOC), not a game API
	local target = Config.SCHEMAS[scope]
	Config.readOnly[scope] = nil
	local work

	if type(raw) ~= "table" then
		-- 1. Absent: a new table. Not a table: its type goes into `corrupt`, then a new table.
		if raw ~= nil then
			setAside(scope, scope, raw)
			issue(var .. ": not a table, replaced by the defaults")
			Config.found[scope] = "damaged"
		else
			Config.found[scope] = "none"
		end
		raw = {}
		_G[var] = raw
		work = raw
	else
		-- 2. A missing or damaged schema is 0.
		local version = schemaOf(raw)
		if version == nil then
			issue(var .. ": damaged schema, treated as 0")
			Config.found[scope] = "damaged"
			version = 0
		else
			if raw.schema == nil and next(raw) ~= nil then issue(var .. ": schema missing, treated as 0") end
			Config.found[scope] = raw.schema == nil and "none" or version
		end

		if version > target then
			-- 4. Written by a newer version of the addon: read it, never rewrite it. All work happens on a copy.
			Config.readOnly[scope] = "newer"
			issue(("%s: schema %d is newer than %d, read-only"):format(var, version, target))
			work = copy(raw)
		elseif version < target and next(raw) ~= nil then
			-- 3. Older: the steps run on a copy; on success the copy's content replaces the saved table's (same table).
			local trial = copy(raw)
			local ok, why = migrate(scope, trial, version, target)
			if ok then
				for k in pairs(raw) do raw[k] = nil end
				for k, v in pairs(trial) do raw[k] = v end
				work = raw
			else
				Config.readOnly[scope] = "migration"
				issue(var .. ": migration " .. why .. ", read-only")
				work = copy(raw)
			end
		else
			work = raw
		end
	end

	work.schema = target
	Config.db[scope] = work
	mergeDefaults(work, Config.defaults[scope])   -- 5.
	Config.Sanitize(scope, work)                  -- 6. (7: unknown keys are never touched)
end

-- Loads both variables (ADDON_LOADED). Safe to call again: a second run on clean data changes nothing.
function Config:Load()
	Config.issues = {}
	pending = {}
	for _, scope in ipairs(Config.SCOPES) do loadScope(scope) end
	flushCorrupt()
	Config.loaded = true
	emit("CONFIG_LOADED")
	return #Config.issues == 0
end

-- true when `scope` (or, without one, either scope) refuses writes.
function Config:IsReadOnly(scope)
	if scope then return Config.readOnly[scope] ~= nil end
	return Config.readOnly.account ~= nil or Config.readOnly.char ~= nil
end

---------------------------------------------------------------------------------------------------------------------
-- Get / Set by path: "account.settings.language", "char.ui.scale"
---------------------------------------------------------------------------------------------------------------------
-- path -> its names, split once for Get and never changed afterwards (the paths are a fixed set): Get runs in frequent
-- paths (Motion.On, at every tween of a threat bar) and must not allocate (ARC-06).
local GET_PARTS = {}

-- The value at `path`, nil when absent. A table is the live one (LibDBIcon keeps the minimap table): change it only
-- through Set.
function Config:Get(path)
	local parts = GET_PARTS[path]
	if not parts then
		parts = split(path)
		if type(path) == "string" then GET_PARTS[path] = parts end
	end
	local node = Config.db[parts[1]]
	for i = 2, #parts do
		if type(node) ~= "table" then return nil end
		node = node[parts[i]]
	end
	return node
end

-- Validated write. Returns true, or false and the reason: "unknown path", "not a value" (a whole container),
-- "read-only", or the rule broken. A size is brought within its limits and the scale rounded, as at load.
-- CONFIG_CHANGED(path) is emitted only when the stored value changes.
function Config:Set(path, value)
	local parts = split(path)
	local scope = parts[1]
	local rule = Config.rules[path]
	if not rule or not Config.db[scope] then return false, "unknown path" end
	if rule.container then return false, "not a value" end
	if Config.readOnly[scope] then return false, "read-only" end
	local why = violation(rule, value)
	if why then return false, why end
	if rule.fix and value ~= nil then value = (rule.fix(value)) end
	local parent, leaf = locate(Config.db[scope], parts, 2)
	if not parent then return false, "parent missing" end
	if path == THRESHOLDS[1] or path == THRESHOLDS[2] then
		local w = path == THRESHOLDS[1] and value or parent.warning
		local d = path == THRESHOLDS[2] and value or parent.danger
		local broken = pairViolation(w, d)
		if broken then return false, broken end
	end
	if same(parent[leaf], value) then return true end
	parent[leaf] = copy(value)
	emit("CONFIG_CHANGED", path)
	return true
end

-- Both thresholds at once (the Settings card, where moving one may push the other). Each CONFIG_CHANGED is emitted
-- when both are stored, so a listener never sees half of the pair. Returns true, or false and the reason.
function Config:SetThresholds(warning, danger)
	if not Config.db.account then return false, "unknown path" end
	if Config.readOnly.account then return false, "read-only" end
	local why = violation(Config.rules[THRESHOLDS[1]], warning) or violation(Config.rules[THRESHOLDS[2]], danger)
		or pairViolation(warning, danger)
	if why then return false, why end
	local monitor = Config.db.account.settings.monitor
	local changed = {}
	if monitor.warning ~= warning then changed[#changed + 1] = THRESHOLDS[1] end
	if monitor.danger ~= danger then changed[#changed + 1] = THRESHOLDS[2] end
	monitor.warning, monitor.danger = warning, danger
	for _, path in ipairs(changed) do emit("CONFIG_CHANGED", path) end
	return true
end

-- Puts every path of `prefix` that has a rule and no container back to its default, in place (unknown keys stay).
local function resetUnder(scope, prefix)
	local changed = {}
	for _, path in ipairs(rulePaths(scope)) do
		local rule = Config.rules[path]
		if not rule.container and path:sub(1, #prefix) == prefix then
			local parts = split(path)
			local parent, key = locate(Config.db[scope], parts, 2)
			local default = defaultAt(scope, parts, 2)
			if parent and not same(parent[key], default) then
				parent[key] = default
				changed[#changed + 1] = path
			end
		end
	end
	for _, path in ipairs(changed) do emit("CONFIG_CHANGED", path) end
	return true
end

-- *Reset settings* (Settings, M1.8): account.settings back to the defaults and `corrupt` emptied. Recordings and
-- profiles are not touched.
function Config:ResetSettings()
	if not Config.db.account then return false, "not loaded" end
	if Config.readOnly.account then return false, "read-only" end
	resetUnder("account", "account.settings.")
	local list = Config.db.account.corrupt
	for i = #list, 1, -1 do list[i] = nil end
	return true
end

-- /atw reset (M1.7): the window's position, sizes and scale back to the defaults.
function Config:ResetWindow()
	if not Config.db.char then return false, "not loaded" end
	if Config.readOnly.char then return false, "read-only" end
	resetUnder("char", "char.ui.pos")
	resetUnder("char", "char.ui.size.")
	resetUnder("char", "char.ui.scale")
	return true
end

---------------------------------------------------------------------------------------------------------------------
-- Size and /atw debug (SPEC-01 §9: schema per variable, read-only, problems corrected, `corrupt`, size in KB)
---------------------------------------------------------------------------------------------------------------------
-- An estimate of the bytes a value takes in the saved file: keys, values and punctuation, as the client writes it.
function Config.EstimateSize(value, seen)
	local t = type(value)
	if t == "string" then return #value + 3 end
	if t == "number" or t == "boolean" then return 8 end
	if t ~= "table" then return 0 end
	seen = seen or {}
	if seen[value] then return 0 end
	seen[value] = true
	local total = 2
	for k, v in pairs(value) do total = total + Config.EstimateSize(k, seen) + Config.EstimateSize(v, seen) + 4 end
	return total
end

local READ_ONLY_WHY = {
	newer = "READ-ONLY: saved by a newer version, never rewritten",
	migration = "READ-ONLY: a migration failed, never rewritten",
}

function Config:DebugLines()
	local lines = {}
	if not Config.loaded then return { "not loaded" } end
	for _, scope in ipairs(Config.SCOPES) do
		local db = Config.db[scope]
		lines[#lines + 1] = ("%s: schema found %s, current %d, about %.1f KB%s"):format(Config.VARIABLES[scope],
			tostring(Config.found[scope]), Config.SCHEMAS[scope], (db and Config.EstimateSize(db) or 0) / 1024,
			Config.readOnly[scope] and (" - " .. READ_ONLY_WHY[Config.readOnly[scope]]) or "")
	end
	local corrupt = Config.db.account and Config.db.account.corrupt or {}
	lines[#lines + 1] = ("corrupt entries: %d (at most %d kept)"):format(#corrupt, Config.MAX_CORRUPT)
	for _, entry in ipairs(corrupt) do
		local path = type(entry) == "table" and type(entry.path) == "string" and entry.path:match("^[%w%.]+$") or "?"
		local kind = type(entry) == "table" and type(entry.kind) == "string" and entry.kind:match("^%a+$") or "?"
		lines[#lines + 1] = ("  %s: %s found"):format(path, kind)
	end
	if #Config.issues == 0 then
		lines[#lines + 1] = "problems corrected at load: none"
	else
		lines[#lines + 1] = ("problems corrected at load: %d"):format(#Config.issues)
		for i, text in ipairs(Config.issues) do
			if i > 15 then lines[#lines + 1] = "  ..." break end
			lines[#lines + 1] = "  " .. text
		end
	end
	return lines
end

if ns.addon then ns.addon.Config = Config end
