-- Locale: the addon's own language tables (SPEC-01 §10, ADR 0009 and its update). Lua 5.1.
-- Every file of Locales/ registers its table whatever the client's language; ns.L answers in the active language with
-- English as the fallback. AceLocale is not used: its choice of language is global for every Ace addon.
-- Until ADDON_LOADED (and until Config exists, M1.5) the active language is the client's.
local ADDON_NAME, ns = ...
ns = ns or {}
ns.modules = ns.modules or {}

local Locale = { BASE = "enUS" }
ns.Locale, ns.modules.Locale = Locale, Locale

local tables = {}          -- [code] = { KEY = "text" }
local missing = {}         -- keys with no English string, [key] = true (for /atw debug)
local active = {}          -- the table of the active language
local activeCode = Locale.BASE

-- Client languages that share the table of another.
local ALIASES = { enGB = "enUS" }

local L = setmetatable({}, {
	__index = function(_, key)
		local text = active[key]
		if text == nil then text = tables[Locale.BASE] and tables[Locale.BASE][key] end
		if text == nil then
			missing[key] = true
			return key       -- visible on screen, so it gets noticed
		end
		return text
	end,
})
ns.L = L

-- The client's language code, "enUS" when the client cannot say.
-- Core/Compat.lua loads before this file, because the language is asked while the files of Locales/ load.
local function clientLocale()
	local code = ns.Compat and ns.Compat.ClientLocale()
	return type(code) == "string" and code or Locale.BASE
end

-- Picks the active language. `setting` is "auto" (or nil: follow the client) or a language code; a language without a
-- file falls back to English. Returns the code applied.
function Locale.Apply(setting)
	local code = setting
	if code == nil or code == "auto" then code = clientLocale() end
	code = ALIASES[code] or code
	if not tables[code] then code = Locale.BASE end
	activeCode, active = code, tables[code] or {}
	return code
end

-- Called once by each file of Locales/.
function Locale.Register(code, strings)
	tables[code] = strings
	-- Follow the client while the files load, so that text asked for before ADDON_LOADED is already translated.
	local client = clientLocale()
	if (ALIASES[client] or client) == code then
		activeCode, active = code, strings
	end
end

function Locale.Active()
	return activeCode
end

-- The registered table of a language, nil when it has no file.
function Locale.Strings(code)
	return tables[code]
end

-- The keys asked for that English does not have.
function Locale.MissingKeys()
	local keys = {}
	for key in pairs(missing) do keys[#keys + 1] = tostring(key) end
	table.sort(keys)
	return keys
end
