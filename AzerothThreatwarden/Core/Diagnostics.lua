-- Diagnostics: the report behind `/atw debug` (SPEC-01 §9, ARC-13) and the ring of the addon's own Lua errors. Lua 5.1.
-- Adapted from Azeroth Accord (Core/Diagnostics.lua), same owner, GPL-3.0 (ADR 0012): CleanError, the error ring, the
-- handler wrapper, Format, the length cap and Show come from there; the sections are Threatwarden's (SPEC-01 §9) and
-- the name scrubbing is reduced to what this addon can know (the player, the realm, player GUIDs).
--
-- Pure data: Diagnostics.Report() builds the text and touches no frame; Diagnostics.Show() hands it to the copy box
-- (UI/DiagnosticsBox.lua) when there is one, else prints it. The report is English on purpose (it is pasted into bug
-- reports, ADR 0009 rule 5) and never holds a player, guild or realm name, a player GUID or a folder of the player's
-- computer: every section is made of fixed words, ids, states and numbers, and the one free text, an error message, is
-- cleaned (CleanError) and scrubbed (Redact).
local ADDON_NAME, ns = ...
ns = ns or {}
ns.modules = ns.modules or {}

local Diag = {}
ns.Diagnostics, ns.modules.Diagnostics = Diag, Diag

local Compat = ns.Compat
local type, tostring, pcall, ipairs, pairs = type, tostring, pcall, ipairs, pairs
local concat = table.concat

Diag.MAX_ERRORS = 10        -- distinct errors kept (the oldest goes first)
Diag.MAX_LENGTH = 300       -- characters kept of one error
Diag.MAX_COUNT = 9999
Diag.MAX_CHARS = 30000      -- the report is cut here (the first sections are the ones that matter)
Diag.MIN_NAME = 3           -- a shorter name would turn ordinary words into placeholders
Diag.TITLE = "Azeroth Threatwarden diagnostics"

local errors = {}           -- { { text, count, at }, ... } oldest first
local installed, inside = false, false
Diag.errors = errors

---------------------------------------------------------------------------------------------------------------------
-- The error ring
---------------------------------------------------------------------------------------------------------------------
-- The error text without the player's folders: `Interface\AddOns\AzerothThreatwarden\Core\Compat.lua:12: boom`
-- becomes `AzerothThreatwarden/Core/Compat.lua:12: boom`; any other drive or home path becomes `<path>`; one line, a
-- length limit. A secret value is never turned into text.
function Diag.CleanError(message)
	if Compat and Compat.IsSecret(message) then return "<secret value>" end
	local text = message == nil and "" or tostring(message)
	text = text:gsub("\r", ""):gsub("\n", " | ")
	text = text:gsub("\\", "/")                                  -- one kind of separator from here on
	text = text:gsub("%a:/[^\n]-/AddOns/", "")                   -- C:/Games/WoW/_forever_/Interface/AddOns/
	text = text:gsub("/[^%s:]-/Interface/AddOns/", "")           -- a Unix home folder before Interface/AddOns/
	text = text:gsub("Interface/AddOns/", "")
	text = text:gsub("%a:/[^%s:\"']*", "<path>")                 -- any other drive path
	text = text:gsub("/[Uu]sers/[^%s:\"']*", "<path>")
	text = text:gsub("/[Hh]ome/[^%s:\"']*", "<path>")
	if #text > Diag.MAX_LENGTH then text = text:sub(1, Diag.MAX_LENGTH - 3) .. "..." end
	return text
end

-- Keeps one error. The same text as the latest one only raises its counter.
function Diag.Record(message)
	local text = Diag.CleanError(message)
	local now = Compat and Compat.Now() or 0
	local last = errors[#errors]
	if last and last.text == text then
		if last.count < Diag.MAX_COUNT then last.count = last.count + 1 end
		last.at = now
		return
	end
	errors[#errors + 1] = { text = text, count = 1, at = now }
	while #errors > Diag.MAX_ERRORS do table.remove(errors, 1) end
end

function Diag.Errors() return errors end
function Diag.ClearErrors() for i = #errors, 1, -1 do errors[i] = nil end end

-- Wraps the client's error handler once: an error whose text names this addon is kept, then goes on to the previous
-- handler unchanged. Errors of other addons are not recorded.
function Diag.Install()
	if installed or not Compat then return false end
	local previous = Compat.ErrorHandler()
	local ok = Compat.SetErrorHandler(function(message, ...)
		if not inside then
			inside = true
			pcall(function()
				if not Compat.IsSecret(message) and tostring(message):find(ADDON_NAME, 1, true) then
					Diag.Record(message)
				end
			end)
			inside = false
		end
		if previous then return previous(message, ...) end
		return message
	end)
	installed = ok
	return ok
end

---------------------------------------------------------------------------------------------------------------------
-- Names: scrubbed from the one free text of the report (the error messages)
---------------------------------------------------------------------------------------------------------------------
local function knownNames()
	local out = {}
	local function add(name, placeholder)
		if type(name) == "string" and #name >= Diag.MIN_NAME then out[#out + 1] = { name = name, placeholder = placeholder } end
	end
	if Compat then
		pcall(function()
			add(Compat.PlayerName(), "<player>")
			add(Compat.RealmName(), "<realm>")
		end)
	end
	table.sort(out, function(a, b) return #a.name > #b.name end)
	return out
end

-- `text` with the player's name, the realm and anything shaped like a player GUID replaced, whole words only.
function Diag.Redact(text)
	if type(text) ~= "string" or text == "" then return text end
	text = text:gsub("Player%-%d+%-%x+", "<guid>")
	for _, n in ipairs(knownNames()) do
		local word = "%f[%w_]" .. n.name:gsub("%p", "%%%0")
		text = text:gsub(word .. "%-[%w']+", n.placeholder)   -- "Name-Realm"
		text = text:gsub(word .. "%f[^%w_]", n.placeholder)
	end
	return text
end

---------------------------------------------------------------------------------------------------------------------
-- The sections (SPEC-01 §9)
---------------------------------------------------------------------------------------------------------------------
local function yesNo(v) return v and "yes" or "no" end

function Diag.HeaderLines()
	local version = Compat and Compat.AddonVersion()
	local dev = version == nil or version:find("@", 1, true) ~= nil
	return {
		Diag.TITLE,
		"addon: " .. (version and not dev and version or "development copy"),
		"development build: " .. yesNo(dev),
	}
end

function Diag.ClientLines()
	local info = Compat and Compat.BuildInfo() or {}
	local Locale = ns.Locale
	local setting = ns.Config and ns.Config.Get and ns.Config:Get("account.settings.language") or "auto"
	local missing = Locale and Locale.MissingKeys and #Locale.MissingKeys() or 0
	return {
		("client: %s (build %s, %s)"):format(tostring(info.version or "?"), tostring(info.build or "?"),
			tostring(info.date or "?")),
		"interface: " .. tostring(info.interface or "?"),
		("project id: %s, WoW Forever: %s"):format(tostring(info.projectID or "?"), yesNo(info.isForever)),
		"mode: " .. ((ns.addon and ns.addon.isForever == false) and "diagnostic (unsupported client)" or "normal"),
		"client language: " .. (Compat and Compat.ClientLocale() or "?"),
		("language: setting %s, active %s"):format(tostring(setting), Locale and Locale.Active() or "?"),
		"missing language keys: " .. missing,
		"instance: " .. tostring(Compat and Compat.InstanceType() or "?"),
	}
end

function Diag.FeatureLines()
	local Features = ns.Features
	if not Features then return { "not loaded" } end
	local on, off = {}, {}
	for name, value in pairs(Features) do
		if type(value) == "boolean" then
			if value then on[#on + 1] = name else off[#off + 1] = name end
		end
	end
	table.sort(on)
	table.sort(off)
	return { "on: " .. (#on > 0 and concat(on, ", ") or "none"), "off: " .. (#off > 0 and concat(off, ", ") or "none") }
end

-- An estimate of the size of a saved table: the bytes of its keys and values written out.
local function estimate(value, depth, seen)
	local t = type(value)
	if t == "string" then return #value + 3 end
	if t == "number" or t == "boolean" then return 8 end
	if t ~= "table" or seen[value] or depth > 20 then return 0 end
	seen[value] = true
	local size = 2
	for k, v in pairs(value) do size = size + estimate(k, depth + 1, seen) + estimate(v, depth + 1, seen) + 2 end
	return size
end

Diag.SAVED_VARIABLES = { "AzerothThreatwardenDB", "AzerothThreatwardenCharDB" }

function Diag.SavedLines()
	local lines = {}
	for _, name in ipairs(Diag.SAVED_VARIABLES) do
		local data = _G[name]   -- the addon's own SavedVariables (TOC), not a game API
		if type(data) ~= "table" then
			lines[#lines + 1] = name .. ": nothing saved yet"
		else
			local schema = data.schema
			lines[#lines + 1] = ("%s: schema %s, about %.1f KB"):format(name,
				(type(schema) == "number" or type(schema) == "string") and tostring(schema) or "none",
				estimate(data, 0, {}) / 1024)
		end
	end
	local Config = ns.Config
	if Config and Config.DebugLines then
		for _, line in ipairs(Config:DebugLines()) do lines[#lines + 1] = line end
	else
		lines[#lines + 1] = "read-only, problems corrected and corrupt entries: Config arrives in M1.5"
	end
	return lines
end

function Diag.MemoryLines()
	local kb = Compat and Compat.AddonMemoryKB()
	local fps = Compat and Compat.Framerate()
	return {
		"addon memory: " .. (kb and ("%.1f KB"):format(kb) or "unknown"),
		"framerate: " .. (fps and ("%.0f fps"):format(fps) or "unknown"),
	}
end

function Diag.ErrorLines()
	if #errors == 0 then return { "no addon errors recorded this session" } end
	local lines = {}
	for i = #errors, 1, -1 do   -- latest first
		local e = errors[i]
		lines[#lines + 1] = Diag.Redact((e.count > 1 and ("x" .. e.count .. " ") or "") .. e.text)
	end
	return lines
end

local function call(fn)
	if type(fn) ~= "function" then return { "not loaded" } end
	return fn()
end

-- The sections in the order of SPEC-01 §9; the ones modules add with AddDebugSection come before the last errors.
function Diag.Collect()
	local sections = {
		{ title = "Client", fn = Diag.ClientLines },
		{ title = "Features", fn = Diag.FeatureLines },
		{ title = "APIs", fn = function() return call(Compat and Compat.ApiLines) end },
		{ title = "Capabilities", fn = function() return call(Compat and Compat.CapabilityLines) end },
		{ title = "Restrictions", fn = function() return call(Compat and Compat.RestrictionLines) end },
		{ title = "Saved data", fn = Diag.SavedLines },
		{ title = "Memory", fn = Diag.MemoryLines },
		{ title = "Bus", fn = function() return call(ns.Bus and ns.Bus.DebugLines) end },
		{ title = "Scheduler", fn = function() return call(ns.Scheduler and ns.Scheduler.DebugLines) end },
	}
	for _, section in ipairs(ns.addon and ns.addon.debugSections or {}) do
		sections[#sections + 1] = { title = section.title, fn = section.linesFn }
	end
	sections[#sections + 1] = { title = "Last errors", fn = Diag.ErrorLines }
	local out = {}
	for _, section in ipairs(sections) do
		local ok, lines = pcall(section.fn)
		if not ok then
			lines = { "error: " .. Diag.Redact(Diag.CleanError(lines)) }
		elseif type(lines) ~= "table" then
			lines = {}
		end
		out[#out + 1] = { title = section.title, lines = lines }
	end
	local okHeader, header = pcall(Diag.HeaderLines)
	return { header = okHeader and header or { Diag.TITLE }, sections = out }
end

-- data = { header = { "line", ... }, sections = { { title, lines }, ... } } -> the report text.
function Diag.Format(data)
	local out = {}
	for _, line in ipairs(data.header or {}) do out[#out + 1] = line end
	for _, section in ipairs(data.sections or {}) do
		out[#out + 1] = ""
		out[#out + 1] = "== " .. tostring(section.title) .. " =="
		for _, line in ipairs(section.lines or {}) do
			out[#out + 1] = (Compat and Compat.IsSecret(line)) and "<secret value>" or tostring(line)
		end
	end
	return concat(out, "\n")
end

local NL = "\n"
function Diag.Report()
	local text = Diag.Format(Diag.Collect())
	if #text > Diag.MAX_CHARS then
		local cut = text:sub(1, Diag.MAX_CHARS):gsub("[^" .. NL .. "]*$", "")
		text = cut .. (NL .. "... report cut at %d characters"):format(Diag.MAX_CHARS)
	end
	return text
end

-- /atw debug: the copy box when the interface has one, else the report line by line in the chat. Returns the text.
function Diag.Show()
	local text = Diag.Report()
	local box = ns.DiagnosticsBox
	if box and box.Open then
		local ok = pcall(box.Open, box, text)
		if ok then return text end
	end
	local addon = ns.addon
	for line in (text .. NL):gmatch("(.-)\n") do
		if addon and addon.Print then addon:Print(line) end
	end
	return text
end

Diag.Install()
if ns.addon then ns.addon.Diagnostics = Diag end
