-- Mock client, part: the game's own party and raid frames (Compact Raid Frames) for the overlay of M8.3 (SPEC-07 §3.3,
-- §6; ADR 0021), with a log of every touch that is not an allowed read. Threatwarden's own.
--
-- Imitates: the global frames CompactPartyFrameMember1-5, CompactRaidFrame1-40 and CompactRaidGroup1-8Member1-5, which
-- the dump does not list by name (it lists the CompactUnitFrame_* functions of the interface code, imitated here as
-- functions that log when called); their `unit` and `displayedUnit` fields; IsVisible(), GetRect() and
-- GetEffectiveScale() (SimpleScriptRegionAPI and SimpleFrameAPI in the dump). Nothing exists until a test makes it.
--
-- The log (Mock.raidFrames.log, a list of "name: what") gets an entry for:
--   * reading any key of a frame through its metatable but the three allowed methods (a method looked up, a field the
--     frame does not have);
--   * writing any new field into a frame;
--   * calling any method but the three (the method looked up logs, and calling it logs again);
--   * hooksecurefunc on a frame, or on a CompactUnitFrame_* function;
--   * calling a CompactUnitFrame_* function;
--   * SetPoint / SetAllPoints of any widget relative to a frame, and SetParent to a frame.
-- The fields `unit` and `displayedUnit` are plain fields of the frame, read with rawget by Core/Compat.lua.
--
--   Mock.raidFrames.Add(name, def)   def = { unit, displayedUnit, visible (true), left, bottom, width, height,
--                                    scale (1), mode = "ok" | "secret" | "error" }: makes (or replaces) one frame
--   Mock.raidFrames.Party(units)     CompactPartyFrameMember1..n, stacked 72 x 36 from (20, 600)
--   Mock.raidFrames.Raid(units, grouped)  CompactRaidFrame1..n, or CompactRaidGroupGMemberM (5 per group)
--   Mock.raidFrames.Get(name)        the definition of a frame, to change (move it, hide it, make it secret)
--   Mock.raidFrames.Clear()          removes every frame; Mock.raidFrames.ClearLog()
local Mock = ...

local raidFrames = { log = {}, frames = {} }
Mock.raidFrames = raidFrames
local defs = setmetatable({}, { __mode = "k" })   -- frame -> its definition
local ALLOWED = { IsVisible = true, GetRect = true, GetEffectiveScale = true }

local function log(name, what) raidFrames.log[#raidFrames.log + 1] = tostring(name) .. ": " .. what end
function raidFrames.ClearLog() for i = #raidFrames.log, 1, -1 do raidFrames.log[i] = nil end end
function raidFrames.IsFrame(value) return type(value) == "table" and defs[value] ~= nil end

local function answer(def, ...)
	if def.mode == "error" then error("Interface action failed because of an AddOn", 2) end
	if def.mode == "secret" then
		local n = select("#", ...)
		local out = {}
		for i = 1, n do out[i] = Mock.Secret(type((select(i, ...)))) end
		return unpack(out, 1, n)
	end
	return ...
end

local methods = {
	IsVisible = function(self) local d = defs[self]; return answer(d, d.visible ~= false) end,
	GetRect = function(self)
		local d = defs[self]
		return answer(d, d.left or 0, d.bottom or 0, d.width or 72, d.height or 36)
	end,
	GetEffectiveScale = function(self) local d = defs[self]; return answer(d, d.scale or 1) end,
}

local frameMeta = {
	__index = function(self, key)
		local d = defs[self]
		if ALLOWED[key] then return methods[key] end
		log(d.name, "read " .. tostring(key))
		return function() log(d.name, "call " .. tostring(key)) end
	end,
	__newindex = function(self, key, value)
		log(defs[self].name, "write " .. tostring(key))
		rawset(self, key, value)
	end,
}

function raidFrames.Add(name, def)
	def = def or {}
	def.name = name
	local frame = setmetatable({}, frameMeta)
	rawset(frame, "unit", def.unit)
	rawset(frame, "displayedUnit", def.displayedUnit)
	defs[frame] = def
	def.frame = frame
	raidFrames.frames[name] = frame
	_G[name] = frame
	return frame
end

function raidFrames.Get(name)
	local frame = raidFrames.frames[name]
	return frame and defs[frame]
end

-- Changes the unit of a frame, as the game does when the roster changes.
function raidFrames.SetUnit(name, unit)
	local frame = raidFrames.frames[name]
	rawset(frame, "unit", unit)
	defs[frame].unit = unit
end

function raidFrames.Clear()
	for name in pairs(raidFrames.frames) do
		_G[name] = nil
		raidFrames.frames[name] = nil
	end
end

function raidFrames.Party(units)
	for i, unit in ipairs(units) do
		raidFrames.Add("CompactPartyFrameMember" .. i,
			{ unit = unit, left = 20, bottom = 600 - (i - 1) * 36, width = 72, height = 36 })
	end
end

function raidFrames.Raid(units, grouped)
	for i, unit in ipairs(units) do
		local g, m = math.floor((i - 1) / 5) + 1, (i - 1) % 5 + 1
		local name = grouped and ("CompactRaidGroup" .. g .. "Member" .. m) or ("CompactRaidFrame" .. i)
		raidFrames.Add(name, { unit = unit, left = 20 + (g - 1) * 74, bottom = 700 - (m - 1) * 30, width = 72,
			height = 30 })
	end
end

-- The interface functions of the frames (listed in the dump): calling one logs.
for _, name in ipairs({ "CompactUnitFrame_UpdateAll", "CompactUnitFrame_UpdateHealthColor",
	"CompactUnitFrame_UpdateAggroHighlight", "CompactUnitFrame_SetUnit", "CompactUnitFrame_UpdateName" }) do
	_G[name] = function() log(name, "called") end
end

local plainHook = hooksecurefunc
function hooksecurefunc(a, b, c)
	if raidFrames.IsFrame(a) then log(defs[a].name, "hooksecurefunc " .. tostring(b))
	elseif type(a) == "string" and a:find("^CompactUnitFrame") then log(a, "hooksecurefunc")
	elseif type(a) == "table" and type(b) == "string" and b:find("^CompactUnitFrame") then log(b, "hooksecurefunc") end
	return plainHook(a, b, c)
end

-- Widgets anchored or parented to a frame of the game.
local Widget = getmetatable(UIParent).__index
local setPoint, setAllPoints, setParent = Widget.SetPoint, Widget.SetAllPoints, Widget.SetParent
function Widget:SetPoint(point, relativeTo, ...)
	if raidFrames.IsFrame(relativeTo) then log(defs[relativeTo].name, "anchored to") end
	return setPoint(self, point, relativeTo, ...)
end
function Widget:SetAllPoints(relativeTo)
	if raidFrames.IsFrame(relativeTo) then log(defs[relativeTo].name, "anchored to") end
	return setAllPoints(self, relativeTo)
end
function Widget:SetParent(parent)
	if raidFrames.IsFrame(parent) then
		log(defs[parent].name, "parented to")
		return
	end
	return setParent(self, parent)
end
