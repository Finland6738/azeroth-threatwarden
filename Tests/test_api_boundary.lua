-- The door to the game (SPEC-01 ARC-02; CLAUDE.md "every game API goes through Core/Compat.lua"): no file of the addon
-- but Core/Compat.lua names a game API. Files of UI/ may make frames (CreateFrame, CreateFont: the client's interface
-- toolkit, SPEC-01 §8.2 ui.CreateFrame) and call the methods of their own frames; everything else of the client, data
-- and interface code alike (GameTooltip, UIParent, UISpecialFrames), comes through Compat.
--
-- How: the code of each file without comments and strings is split into names; a name that is not a field (after `.`
-- or `:`, except `_G.`) is refused when the mock client defines it as a global (the game API the mock imitates, from
-- the dump) or when it looks like a game API the mock does not have yet (C_*, Unit*, Get*, Is*, ...). The plain Lua
-- library, the client's Lua helpers (format, wipe, tinsert...) and the addon's own globals are allowed.

local ADDON = "AzerothThreatwarden/"

-- The plain Lua library and the client's Lua helpers (Tests/mock/00_core.lua): not game API.
local LUA = {}
for name in ([[
	_G assert error ipairs pairs next pcall xpcall select tonumber tostring type unpack rawget rawset rawequal
	setmetatable getmetatable getfenv setfenv collectgarbage newproxy loadstring string table math coroutine os
	format gsub gmatch strfind strlower strupper strsub strlen strmatch strrep strbyte strchar strtrim strsplit strjoin
	strlenutf8 max min floor ceil abs tinsert tremove wipe tContains CopyTable Mixin CreateFromMixins LibStub
]]):gmatch("%S+") do LUA[name] = true end

-- What files of UI/ may name besides: they make frames.
local UI_ONLY = { CreateFrame = true, CreateFont = true }

-- Names shaped like a game API, for the ones the mock does not imitate.
local SHAPES = { "^C_%u", "^Unit%u", "^Get%u", "^Is%u", "^Can%u", "^Has%u", "^Should%u", "^Play%u", "^Reload%u",
	"^Enum$", "^WOW_PROJECT_" }

local KEYWORDS = {}
for word in ([[and break do else elseif end false for function if in local nil not or repeat return then true until
	while]]):gmatch("%S+") do KEYWORDS[word] = true end

-- The source with comments and strings blanked out (new lines kept, so line numbers stay right).
local function codeOnly(source)
	local out, i, n = {}, 1, #source
	local function blank(s) return (s:gsub("[^\n]", " ")) end
	while i <= n do
		local c = source:sub(i, i)
		local longOpen = source:match("^%-%-%[(=*)%[", i) or source:match("^%[(=*)%[", i)
		if source:sub(i, i + 1) == "--" and longOpen then
			local close = "]" .. longOpen .. "]"
			local _, e = source:find(close, i, true)
			e = e or n
			out[#out + 1] = blank(source:sub(i, e))
			i = e + 1
		elseif source:sub(i, i + 1) == "--" then
			local e = source:find("\n", i, true) or (n + 1)
			out[#out + 1] = blank(source:sub(i, e - 1))
			i = e
		elseif c == "[" and longOpen then
			local close = "]" .. longOpen .. "]"
			local _, e = source:find(close, i + 2 + #longOpen, true)
			e = e or n
			out[#out + 1] = " " .. blank(source:sub(i + 1, e - 1)) .. " "
			i = e + 1
		elseif c == '"' or c == "'" then
			local j = i + 1
			while j <= n do
				local d = source:sub(j, j)
				if d == "\\" then j = j + 2
				elseif d == c or d == "\n" then break
				else j = j + 1 end
			end
			out[#out + 1] = c .. blank(source:sub(i + 1, j - 1)) .. c
			i = j + 1
		else
			out[#out + 1] = c
			i = i + 1
		end
	end
	return table.concat(out)
end

-- { { line, name } } of the names of `source` that are not fields.
local function globalNames(source)
	local code = codeOnly(source)
	local found, line, last = {}, 1, 1
	for pos, name in code:gmatch("()([%a_][%w_]*)") do
		local _, newlines = code:sub(last, pos):gsub("\n", "")
		line, last = line + newlines, pos + 1
		local j = pos - 1
		while j > 0 and code:sub(j, j):match("%s") do j = j - 1 end
		local before, beforeThat = code:sub(j, j), code:sub(j - 1, j - 1)
		local isField = before == ":" or (before == "." and beforeThat ~= ".")
		if before == "." and code:sub(math.max(1, j - 12), j):match("[^%w_]_G%s*%.$") then isField = false end
		local isNumber = code:sub(pos - 1, pos - 1):match("%d") ~= nil
		if not isField and not isNumber and not KEYWORDS[name] then found[#found + 1] = { line, name } end
	end
	return found
end

-- The game's global names as the mock client defines them, minus the Lua ones and the addon's own.
local function gameNames()
	local own = {}
	for _, name in ipairs(Mock.NewGlobals()) do own[name] = true end
	local names = {}
	for name in pairs(_G) do
		if type(name) == "string" and not LUA[name] and not own[name] and not name:find("^AzerothThreatwarden") then
			names[name] = true
		end
	end
	return names
end

local function refused(name, game, isUI)
	if LUA[name] or (isUI and UI_ONLY[name]) then return false end
	if game[name] then return true end
	for _, shape in ipairs(SHAPES) do
		if name:find(shape) then return true end
	end
	return false
end

-- "file:line: name" for every game API a source names.
local function violations(file, source, game, isUI)
	local out, seen = {}, {}
	for _, hit in ipairs(globalNames(source)) do
		local key = hit[1] .. ":" .. hit[2]
		if refused(hit[2], game, isUI) and not seen[key] then
			seen[key] = true
			out[#out + 1] = file .. ":" .. key
		end
	end
	return out
end

local function addonFiles()
	local files = {}
	for _, name in ipairs(Mock.loadedFiles) do
		if name:find("^" .. ADDON) and not name:find("/Libs/", 1, true) and name:match("%.lua$") then
			files[#files + 1] = name
		end
	end
	return files
end

describe("the door to the game (ARC-02)", function()
	it("no file of UI/ names a game API", function()
		local game, problems, scanned = gameNames(), {}, 0
		for _, file in ipairs(addonFiles()) do
			if file:find("^" .. ADDON .. "UI/") then
				scanned = scanned + 1
				for _, p in ipairs(violations(file, Mock.ReadSource(file), game, true)) do problems[#problems + 1] = p end
			end
		end
		truthy(scanned >= 1, "UI/DiagnosticsBox.lua at least")
		deepEq(problems, {})
	end)

	it("no other file but Core/Compat.lua names one either", function()
		local game, problems, scanned = gameNames(), {}, 0
		for _, file in ipairs(addonFiles()) do
			if not file:find("^" .. ADDON .. "UI/") and file ~= ADDON .. "Core/Compat.lua" then
				scanned = scanned + 1
				for _, p in ipairs(violations(file, Mock.ReadSource(file), game, false)) do problems[#problems + 1] = p end
			end
		end
		truthy(scanned >= 8, "Bus, Locale, the locales, Init, Features, Scheduler, Diagnostics")
		deepEq(problems, {})
	end)

	it("covers the modules of the other mobs (M7.2): MobRisk and MobTracker are checked like the others", function()
		local files = {}
		for _, file in ipairs(addonFiles()) do files[file] = true end
		local game = gameNames()
		for _, name in ipairs({ "Data/MobRisk.lua", "Data/MobTracker.lua" }) do
			truthy(files[ADDON .. name], name .. " is loaded and scanned")
			deepEq(violations(name, Mock.ReadSource(ADDON .. name), game, false), {}, name)
		end
		-- the new client functions they use are named only by Core/Compat.lua
		local compat = Mock.ReadSource(ADDON .. "Core/Compat.lua")
		truthy(compat:find("UnitTokenFromGUID", 1, true))
		truthy(compat:find("C_Secrets.CanCompareUnitTokens", 1, true))
	end)

	it("Core/Compat.lua is where the game is named", function()
		local game = gameNames()
		truthy(#violations("Compat", Mock.ReadSource(ADDON .. "Core/Compat.lua"), game, false) > 0)
	end)
end)

describe("the check itself", function()
	local function check(source, isUI)
		local list = violations("x", source, gameNames(), isUI)
		local names = {}
		for _, v in ipairs(list) do names[#names + 1] = v:match("^x:(.*)$") end
		return names
	end

	it("finds direct calls, game tables, constants and _G lookups, with their lines", function()
		deepEq(check([[
local t = GetTime()
C_Timer.After(1, f)
if WOW_PROJECT_ID then print("x") end
local u = _G.UnitName("player")
x = "a" .. GetLocale()
]]), { "1:GetTime", "2:C_Timer", "3:WOW_PROJECT_ID", "3:print", "4:UnitName", "5:GetLocale" })
	end)

	it("finds a game API the mock does not have by its shape", function()
		deepEq(check("local s = C_Nothing.Do() local v = UnitFancy('x') local h = HasSomething()"),
			{ "1:C_Nothing", "1:UnitFancy", "1:HasSomething" })
	end)

	it("allows fields, methods, strings, comments, the Lua library and the addon's names", function()
		deepEq(check([==[
local Compat = ns.Compat
local t = Compat.Now() + frame:GetTime() + obj.UnitName
-- GetTime() in a comment
--[[ UnitName("player") in a long comment ]]
local s = "GetTime()" .. 'C_Timer' .. [[UnitName]]
local n = math.floor(tonumber("1e3")) + #string.format("%d", 1)
AzerothThreatwarden.x = format("%s", tostring(wipe({})))
]==]), {})
	end)

	it("lets only UI/ make frames", function()
		deepEq(check("local f = CreateFrame('Frame')", true), {})
		deepEq(check("local f = CreateFrame('Frame')", false), { "1:CreateFrame" })
		deepEq(check("local p = UIParent local t = GameTooltip", true), { "1:UIParent", "1:GameTooltip" })
	end)
end)

describe("the role profiles (M8.2)", function()
	it("Data/Profiles.lua is loaded and names no game API; the role is read only through Core/Compat.lua", function()
		local files = {}
		for _, file in ipairs(addonFiles()) do files[file] = true end
		truthy(files[ADDON .. "Data/Profiles.lua"])
		deepEq(violations("Data/Profiles.lua", Mock.ReadSource(ADDON .. "Data/Profiles.lua"), gameNames(), false), {})
		local source = Mock.ReadSource(ADDON .. "Data/Profiles.lua")
		falsy(codeOnly(source):find("UnitGroupRolesAssigned", 1, true), "only Compat.Unit.Role")
		truthy(Mock.ReadSource(ADDON .. "Core/Compat.lua"):find("UnitGroupRolesAssigned", 1, true))
	end)
end)
