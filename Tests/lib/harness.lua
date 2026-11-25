-- Adapted from Azeroth Accord (Tests/lib/harness.lua), same owner, GPL-3.0 (ADR 0012).
-- The Lua side of the offline test harness (ADR 0010). Tests/run_tests.py loads this chunk with a config table and
-- calls H.run().
--
-- Two Lua "worlds" live in one Lua 5.1 state (lupa.lua51):
--   * the harness (this file, the assertion library, the test files' own helpers) runs in the real globals;
--   * the "game" (mock client, the libraries, the addon) runs in the table E, its global environment, via setfenv.
-- Booting empties E in place and fills it again, so a test that holds `_G` or `Mock` keeps a valid reference, while a
-- value copied out of the game before a reload goes stale, as it would after a real /reload.
--
-- Boot order, as the client does it: the mock client, the setups of the test, the libraries and the addon files in TOC
-- order (each called with the addon name and one private table, Mock.ns), the SavedVariables, ADDON_LOADED,
-- PLAYER_LOGIN, PLAYER_ENTERING_WORLD.
--
-- What a setup (before_boot, T.boot) can do besides configuring the mock client:
--   Mock.saved = { AzerothThreatwardenDB = { ... } }   the saved data "on disk" before the first login
--   Mock.features = { monitor = true }                 feature switches turned on for this test (ADR 0014)
--   Mock.OnFilesLoaded(function() ... end)             runs after the addon files, before ADDON_LOADED
local cfg = ...

local H = {
	addonName = cfg.addonName,
	tocFields = cfg.tocFields,
	savedVars = cfg.savedVars,
	validEvents = cfg.events,
	traceback = debug.traceback,
	os = os,
}

local E, Mock = {}, {}
H.E, H.Mock = E, Mock

local T = assert(loadstring(cfg.readfile(cfg.assertPath), "@Tests/lib/assert.lua"))()

local STD_GLOBALS = {
	"assert", "error", "ipairs", "pairs", "next", "pcall", "xpcall", "select", "tonumber", "tostring", "type", "unpack",
	"rawget", "rawset", "rawequal", "setmetatable", "getmetatable", "getfenv", "setfenv", "collectgarbage", "newproxy",
}

local function copyTable(t)
	local c = {}
	for k, v in pairs(t) do c[k] = v end
	return c
end

local function readSource(path)
	local source = cfg.readfile(path)
	if source:sub(1, 3) == "\239\187\191" then source = source:sub(4) end   -- a UTF-8 byte order mark
	return source
end

local function loadChunk(path, display, env)
	local chunk, err = loadstring(readSource(path), "@" .. display)
	if not chunk then error(err, 0) end
	setfenv(chunk, env or E)
	return chunk
end

-- SavedVariables as the client writes them: a table literal per variable. Functions and userdata cannot be saved (the
-- client drops them silently; the harness fails, because it is always a bug in the addon, and a secret value of the mock
-- is userdata: saving one fails the test, SPEC-01 ARC-11).
local function serialize(value, path, seen)
	local t = type(value)
	if t == "number" then
		if value ~= value or value == math.huge or value == -math.huge then
			error("SavedVariables: " .. path .. " is not a finite number", 0)
		end
		return string.format("%.17g", value)
	elseif t == "string" then
		return string.format("%q", value)
	elseif t == "boolean" then
		return tostring(value)
	elseif t == "table" then
		seen = seen or {}
		if seen[value] then error("SavedVariables: " .. path .. " is a circular table", 0) end
		seen[value] = true
		local keys = {}
		for k in pairs(value) do
			local kt = type(k)
			if kt ~= "string" and kt ~= "number" and kt ~= "boolean" then
				error("SavedVariables: " .. path .. " has a key of type " .. kt
					.. (kt == "userdata" and " (a secret value?)" or ""), 0)
			end
			keys[#keys + 1] = k
		end
		table.sort(keys, function(a, b)
			local ta, tb = type(a), type(b)
			if ta ~= tb then return ta < tb end
			if ta == "number" or ta == "string" then return a < b end
			return tostring(a) < tostring(b)
		end)
		local parts = {}
		for _, k in ipairs(keys) do
			parts[#parts + 1] = "[" .. serialize(k, path .. ".<key>", seen) .. "]="
				.. serialize(value[k], path .. "." .. tostring(k), seen)
		end
		seen[value] = nil
		return "{" .. table.concat(parts, ",") .. "}"
	end
	error("SavedVariables: " .. path .. " is a " .. t .. ", which cannot be saved"
		.. (t == "userdata" and " (a secret value?)" or ""), 0)
end
H.serialize = serialize

local function deserialize(text)
	local chunk = assert(loadstring("return " .. text, "=SavedVariables"))
	setfenv(chunk, {})
	return chunk()
end

local function isLibrary(name)
	return name:find("^" .. cfg.addonName .. "/Libs/") ~= nil or name:find("^" .. cfg.addonName .. "/embeds%.xml") ~= nil
end

-- Builds a fresh client and loads the addon.
--   opts.carry     keep Mock.world (clock, player, units, threat, saved text, errors): true on /reload and re-login
--   opts.setups    functions called with Mock after the mock client is built, before the addon loads
--   opts.saved     { VariableName = "table literal" } restored before ADDON_LOADED
--   opts.isReload  second argument of PLAYER_ENTERING_WORLD
function H.boot(opts)
	opts = opts or {}
	local world = opts.carry and Mock.world or {}

	setmetatable(E, nil)
	for k in pairs(E) do rawset(E, k, nil) end
	for k in pairs(Mock) do Mock[k] = nil end
	Mock.world = world

	E._G = E
	for _, name in ipairs(STD_GLOBALS) do E[name] = _G[name] end
	E.string, E.table, E.math, E.coroutine = copyTable(string), copyTable(table), copyTable(math), copyTable(coroutine)
	E.loadstring = function(source, name)
		local chunk, err = loadstring(source, name)
		if chunk then setfenv(chunk, E) end
		return chunk, err
	end

	for _, file in ipairs(cfg.mockFiles) do
		loadChunk(file.path, file.name)(Mock, H)
	end
	Mock.Reload = H.reload
	Mock.Relog = H.relog
	Mock.player.loggedIn = false

	local ns = {}
	Mock.ns = ns   -- the addon's private table, shared by all its files
	local filesLoaded = {}
	function Mock.OnFilesLoaded(fn) filesLoaded[#filesLoaded + 1] = fn end

	for _, setup in ipairs(opts.setups or {}) do setup(Mock) end

	Mock.loadedFiles = {}
	local sourcePaths = {}
	-- The text of a file of the addon as it was loaded ("AzerothThreatwarden/Core/Init.lua"), for the source audits
	-- (locale keys, API boundary); nil for a name that was not loaded.
	function Mock.ReadSource(name)
		local path = sourcePaths[name]
		if not path then return nil end
		return readSource(path)
	end

	-- The global names that exist before the addon's own files run: what appears afterwards is the addon's (ARC-04).
	local before
	local function snapshot()
		before = {}
		for k in pairs(E) do before[k] = true end
	end
	function Mock.NewGlobals()
		local names = {}
		for k in pairs(E) do
			if not before[k] then names[#names + 1] = tostring(k) end
		end
		table.sort(names)
		return names
	end

	for _, entry in ipairs(cfg.plan) do
		if not before and not isLibrary(entry.name) then snapshot() end
		Mock.loadedFiles[#Mock.loadedFiles + 1] = entry.name
		if entry.path then sourcePaths[entry.name] = entry.path end
		if entry.code then
			local chunk, err = loadstring(entry.code, "@" .. entry.name)
			if not chunk then error(err, 0) end
			setfenv(chunk, E)
			chunk(cfg.addonName, ns)
		else
			loadChunk(entry.path, entry.name)(cfg.addonName, ns)
		end
	end
	if not before then snapshot() end

	-- Feature switches (Core/Features.lua): a setup writes Mock.features = { monitor = true }, and it holds from before
	-- ADDON_LOADED, through /reload too (Mock.world keeps it).
	if Mock.features then Mock.world.features = Mock.features end
	if ns.Features then
		for name, on in pairs(Mock.world.features or {}) do ns.Features[name] = on end
	end

	for _, fn in ipairs(filesLoaded) do fn() end

	-- The saved data on disk: the text of the last logout, or what a setup put in Mock.saved (copied through the same
	-- serializer, so the addon never holds the test's own tables).
	local saved = opts.saved
	if not saved and Mock.saved then
		saved = {}
		for name, value in pairs(Mock.saved) do saved[name] = serialize(value, name) end
	end
	for name, text in pairs(saved or {}) do E[name] = deserialize(text) end

	Mock.Fire("ADDON_LOADED", cfg.addonName, false)
	Mock.player.loggedIn = true
	Mock.Fire("PLAYER_LOGIN")
	Mock.Fire("PLAYER_ENTERING_WORLD", not opts.isReload, opts.isReload == true)
end

-- Logout: PLAYER_LOGOUT, then the SavedVariables the TOC declares, as the client would write them. Mock.savedText keeps
-- the text "written to disk". H.boot({ carry = true, saved = <that table> }) logs in again.
function H.logout()
	Mock.Fire("PLAYER_LOGOUT")
	local saved = {}
	for _, name in ipairs(cfg.savedVars) do
		local value = E[name]
		if value ~= nil then saved[name] = serialize(value, name) end
	end
	Mock.world.savedText = saved
	return saved
end

-- /reload: logout, the Lua state rebuilt, the SavedVariables read back; the world (time, player, units, combat, threat)
-- is untouched, so a reload in the middle of a fight comes back into it.
function H.reload()
	local saved = H.logout()
	H.boot({ carry = true, saved = saved, isReload = true })
	Mock.savedText = saved
end

-- Logout, `away` seconds out of the game, and a new login (not a /reload). `change` runs while out of the game, on the
-- world only (the clock, the group, a fight that ended).
function H.relog(away, change)
	local saved = H.logout()
	Mock.StepClock(away or 0)
	if change then change() end
	H.boot({ carry = true, saved = saved })
	Mock.savedText = saved
end

-- Test files -------------------------------------------------------------------------------------------------------
-- Test files see: the assertion library, Mock, Fight (Tests/lib/fight.lua), the game's globals, and (while the game is
-- not built, e.g. when the file is first loaded) the plain Lua library.
local plainLua = { string = true, table = true, math = true, coroutine = true }
for _, name in ipairs(STD_GLOBALS) do plainLua[name] = true end

local testEnv = setmetatable({ T = T, Mock = Mock }, {
	__index = function(_, key)
		local v = T[key]
		if v ~= nil then return v end
		v = E[key]
		if v == nil and plainLua[key] then return _G[key] end
		return v
	end,
	__newindex = function(_, key, value) E[key] = value end,
})

-- true when the long scenarios run too (run_tests.py --long, or AZTW_LONG=1; the "Long tests" workflow).
T.long = cfg.long == true

local currentSetups = {}
T.log = function(...)
	local parts = { ... }
	for i = 1, select("#", ...) do parts[i] = tostring(parts[i]) end
	cfg.log("    " .. table.concat(parts, " ") .. "\n")
end

-- A Lua error caught by the client's error handler fails the test that left it behind.
local function checkErrors()
	local errors = Mock.errors
	if errors and #errors > 0 then
		local extra = #errors > 1 and (" (+" .. (#errors - 1) .. " more)") or ""
		error("Lua error caught by the client's error handler" .. extra .. ": " .. errors[1].message .. "\n"
			.. errors[1].trace, 0)
	end
end

-- Boots a fresh client again inside a test (new world), keeping the setups of the enclosing groups.
T.boot = function(extraSetup)
	checkErrors()   -- the new world would forget them
	local setups = { unpack(currentSetups) }
	if extraSetup then setups[#setups + 1] = extraSetup end
	H.boot({ setups = setups })
end

rawset(testEnv, "Fight", loadChunk(cfg.fightPath, "Tests/lib/fight.lua", testEnv)(Mock))

local function matchesFilter(name)
	local filter = cfg.filter
	return filter == "" or name:lower():find(filter:lower(), 1, true) ~= nil
end

local function handler(err)
	return { message = tostring(err), trace = debug.traceback("", 2) }
end

local function runTest(fullName, setups, fn, totals)
	currentSetups = setups
	local ok, failure = xpcall(function()
		H.boot({ setups = setups })
		fn()
		checkErrors()
	end, handler)
	if ok then
		totals.passed = totals.passed + 1
		cfg.log("  ok    " .. fullName .. "\n")
	else
		totals.failed = totals.failed + 1
		cfg.log("  FAIL  " .. fullName .. "\n")
		for line in (failure.message .. "\n"):gmatch("(.-)\n") do
			if line ~= "" then cfg.log("          " .. line .. "\n") end
		end
		if cfg.verbose then
			cfg.log("          " .. failure.trace:gsub("\n", "\n          ") .. "\n")
		end
	end
end

-- The filter matches "file > group > test"; the log shows the file once, then "group > test".
local function walk(node, path, setups, fileName, totals)
	local own = { unpack(setups) }
	for _, s in ipairs(node.setups) do own[#own + 1] = s end
	for _, child in ipairs(node.children) do
		local childPath = path
		if child.name ~= "" then childPath = (path ~= "" and path .. " > " or "") .. child.name end
		if child.kind == "group" then
			walk(child, childPath, own, fileName, totals)
		elseif matchesFilter(fileName .. " > " .. childPath) then
			if totals.header ~= fileName then
				totals.header = fileName
				totals.files = totals.files + 1
				cfg.log(fileName .. "\n")
			end
			runTest(childPath, own, child.fn, totals)
		end
	end
end

-- Runs every test file; returns passed, failed, files.
function H.run()
	local totals = { passed = 0, failed = 0, files = 0 }
	for _, file in ipairs(cfg.testFiles) do
		local root = T._reset()
		local ok, err = pcall(function() loadChunk(file.path, file.name, testEnv)() end)
		if not ok then
			totals.failed = totals.failed + 1
			totals.files = totals.files + 1
			cfg.log(file.name .. "\n  FAIL  (could not load the file)\n          " .. tostring(err) .. "\n")
		else
			walk(root, "", {}, file.name, totals)
		end
	end
	if totals.passed + totals.failed == 0 then
		cfg.log(cfg.filter ~= "" and ("No test matches '" .. cfg.filter .. "'.\n") or "No tests found.\n")
	end
	return totals.passed, totals.failed, totals.files
end

return H
