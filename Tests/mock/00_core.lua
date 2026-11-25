-- Adapted from Azeroth Accord (Tests/mock/00_core.lua), same owner, GPL-3.0 (ADR 0012).
-- Mock client, part 1: the Lua environment of the WoW client and the plumbing shared by every other mock file.
--
-- Imitates: the Lua 5.1 environment of the game (xpcall with arguments, the string, table and math global helpers,
-- hooksecurefunc, the secure-call functions, the error handler), an empty `Enum`, and `print`.
-- Dump (../WoW-Addons/docs/api.json, build 70170, `globals`): securecall, securecallfunction, issecure,
-- issecurevariable, geterrorhandler, seterrorhandler, CallErrorHandler, hooksecurefunc, format, strsplit, strjoin,
-- strtrim, strlenutf8, tinsert, tremove, wipe, tContains, CopyTable, Mixin, CreateFromMixins, debugstack, print, max,
-- min, floor, abs. `Enum` is part of the client's interface code, not of the dump.
--
-- Every mock file is a chunk run with `(Mock, H)`: `Mock` is the table tests use (Mock.Fire, Mock.Advance, ...),
-- `H` is the harness (Tests/lib/harness.lua). Persistent "world" state (clock, player, units, combat, threat) lives in
-- `Mock.world` and survives Mock.Reload(); everything else is rebuilt by a reload, like the client's UI.
local Mock, H = ...
local W = Mock.world

-- The client's xpcall forwards extra arguments (plain Lua 5.1 drops them); AceAddon's safecall relies on it.
local plainXpcall = xpcall
function xpcall(f, handler, ...)
	local n = select("#", ...)
	if n == 0 then return plainXpcall(f, handler) end
	local args = { ... }
	return plainXpcall(function() return f(unpack(args, 1, n)) end, handler)
end

-- Lua errors raised inside handlers are caught like the client does (the error handler shows them, the game goes on).
-- The test library fails a test that leaves errors behind unless it called Mock.ClearErrors().
W.errors = W.errors or {}
Mock.errors = W.errors

local userHandler

local recording
local function record(msg)
	-- a handler installed with seterrorhandler may wrap this recorder (the addon's diagnostics will): no second record
	if recording then return msg end
	recording = true
	W.errors[#W.errors + 1] = { message = tostring(msg), trace = H.traceback(tostring(msg), 3) }
	if userHandler then
		pcall(userHandler, msg)
	end
	recording = false
	return msg
end

function seterrorhandler(fn) userHandler = fn end
function geterrorhandler() return userHandler or record end
function CallErrorHandler(msg) return record(msg) end

-- Runs fn(...) the way the client runs a script handler: an error is recorded, not propagated. Returns ok, results.
function Mock.safecall(fn, ...)
	local args, n = { ... }, select("#", ...)
	return xpcall(function() return fn(unpack(args, 1, n)) end, record)
end

-- Real (CPU) seconds, for the performance budgets of the tests; the game clock of 10_clock.lua is simulated.
function Mock.RealClock() return H.os.clock() end

function Mock.ClearErrors()
	for i = #W.errors, 1, -1 do W.errors[i] = nil end
end

-- Takes a function, or a table field, out of the client before the addon loads: Mock.Remove("UnitThreatSituation"),
-- Mock.Remove("C_Secrets.ShouldUnitThreatValuesBeSecret"). The way a test says "this API is missing".
function Mock.Remove(path)
	local parent, key = _G, nil
	for part in path:gmatch("[^%.]+") do
		if key then parent = parent[key] end
		if type(parent) ~= "table" then error("Mock.Remove: nothing at " .. path, 2) end
		key = part
	end
	if not key or parent[key] == nil then error("Mock.Remove: nothing at " .. path, 2) end
	parent[key] = nil
end

function securecall(fn, ...)
	if type(fn) == "string" then fn = _G[fn] end
	return fn(...)
end
-- securecallfunction(fn, ...): CallbackHandler (AceEvent) calls handlers through it; the mock has no taint to protect.
function securecallfunction(fn, ...) return fn(...) end
function issecure() return true end
function issecurevariable() return true end

-- String and math helpers of the client. format is the plain Lua one.
format, gsub, strfind, strlower, strupper, strsub, strlen, strmatch, strrep, strbyte, strchar =
	string.format, string.gsub, string.find, string.lower, string.upper, string.sub, string.len, string.match,
	string.rep, string.byte, string.char
gmatch = string.gmatch
max, min, floor, ceil, abs = math.max, math.min, math.floor, math.ceil, math.abs

function strtrim(s, chars)
	chars = chars or " \t\r\n"
	local class = "[" .. chars:gsub("[%]%^%-%%]", "%%%0") .. "]"
	return (s:gsub("^" .. class .. "+", ""):gsub(class .. "+$", ""))
end

function strsplit(delim, str, pieces)
	local out, pos, n = {}, 1, 0
	local class = "[" .. delim:gsub("[%]%^%-%%]", "%%%0") .. "]"
	while true do
		if pieces and n >= pieces - 1 then break end
		local s = str:find(class, pos)
		if not s then break end
		n = n + 1
		out[n] = str:sub(pos, s - 1)
		pos = s + 1
	end
	out[n + 1] = str:sub(pos)
	return unpack(out, 1, n + 1)
end

function strjoin(delim, ...)
	local t = { ... }
	for i = 1, select("#", ...) do t[i] = tostring(t[i]) end
	return table.concat(t, delim)
end

function strlenutf8(s)
	local _, count = s:gsub("[^\128-\191]", "")
	return count
end

-- Table helpers.
tinsert, tremove = table.insert, table.remove
function wipe(t)
	for k in pairs(t) do t[k] = nil end
	return t
end
table.wipe = wipe
function tContains(t, value)
	for _, v in ipairs(t) do if v == value then return true end end
	return false
end
function CopyTable(src, seen)
	local out = {}
	seen = seen or {}
	seen[src] = out
	for k, v in pairs(src) do
		out[k] = type(v) == "table" and (seen[v] or CopyTable(v, seen)) or v
	end
	return setmetatable(out, getmetatable(src))
end
function Mixin(object, ...)
	for i = 1, select("#", ...) do
		for k, v in pairs((select(i, ...))) do object[k] = v end
	end
	return object
end
function CreateFromMixins(...) return Mixin({}, ...) end

-- hooksecurefunc(table|name, name|hook, hook): runs `hook` after the original with the same arguments.
-- Every wrapper it installs is remembered in Mock.secureHooks: a test can tell a field changed by hooksecurefunc from a
-- Blizzard function the addon replaced.
Mock.secureHooks = setmetatable({}, { __mode = "k" })
function hooksecurefunc(a, b, c)
	local tbl, name, hook = _G, a, b
	if type(a) == "table" then tbl, name, hook = a, b, c end
	local original = tbl[name]
	assert(type(original) == "function", "hooksecurefunc: " .. tostring(name) .. " is not a function")
	local wrapper = function(...)
		local results = { original(...) }
		hook(...)
		return unpack(results)
	end
	tbl[name] = wrapper
	Mock.secureHooks[wrapper] = true
end

function debugstack() return H.traceback("", 2) end

-- The enumerations of the client's interface code; the files that need one add it.
Enum = {}

-- Chat output: print() and chat frames write to Mock.output (raw lines, colour codes kept), never to the console.
W.output = W.output or {}
Mock.output = W.output

function Mock.ClearOutput()
	for i = #W.output, 1, -1 do W.output[i] = nil end
end

function Mock.Strip(text)
	return (tostring(text):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", ""):gsub("||", "|"))
end

-- The lines printed so far without colour codes, joined by new lines.
function Mock.PlainOutput()
	local lines = {}
	for i, line in ipairs(W.output) do lines[i] = Mock.Strip(line) end
	return table.concat(lines, "\n")
end

function print(...)
	local parts = { ... }
	for i = 1, select("#", ...) do parts[i] = tostring(parts[i]) end
	W.output[#W.output + 1] = table.concat(parts, " ")
end
