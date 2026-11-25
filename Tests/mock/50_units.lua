-- Mock client, part 7: units, unit tokens and the party or raid.
--
-- Imitates: UnitExists, UnitGUID, UnitTokenFromGUID, UnitName, UnitClass, UnitClassification, UnitCanAttack,
-- UnitIsDead, UnitIsUnit, UnitIsPlayer, UnitAffectingCombat, UnitGroupRolesAssigned, UnitInRaid, IsInGroup, IsInRaid,
-- GetNumGroupMembers.
-- Dump (../WoW-Addons/docs/api.json, build 70170): system Unit (the Unit* functions, UnitGUID with a nilable result
-- and the argument type UnitTokenPvPRestrictedForAddOns); IsInGroup, IsInRaid and GetNumGroupMembers are in `globals`
-- without a signature; UnitInRaid(unit [, partyIndex]) -> luaIndex, nilable. Events: PLAYER_TARGET_CHANGED,
-- UNIT_TARGET, PLAYER_FOCUS_CHANGED, NAME_PLATE_UNIT_ADDED, NAME_PLATE_UNIT_REMOVED, INSTANCE_ENCOUNTER_ENGAGE_UNIT,
-- GROUP_ROSTER_UPDATE, UNIT_PET (fired by hand: the mock has no pets of its own, "pet" is a token set by a test).
-- GUID and name secrecy inside instances is P9: Mock.secrets.Set{ identity = true } (05_secrets.lua).
--
-- A unit is an entity with a short key ("player", "tank", "boss"); a token ("party1", "target", "boss1targettarget")
-- names it. Everything is kept across Mock.Reload.
--   Mock.units.Add("boss", { name = "Test Boss", hostile = true, classification = "worldboss", npcID = 100 })
--   Mock.units.Add("tank", { class = "WARRIOR", role = "TANK" })      -- a player: no `hostile`
--   Mock.units.SetToken("nameplate1", "boss")      -- "target", "focus", "mouseover", "boss1"..., nil to clear
--   Mock.units.Target("tank", "boss")              -- who a unit targets ("boss" .. "target" resolves through it)
--   Mock.units.Get("boss")                         -- the entity: change .dead, .name, .guid, .combat directly
--   Mock.units.Resolve("targettarget") -> entity, Mock.units.TokensOf("boss") -> { "target", "nameplate1" }
--   Mock.group.Set{ raid = false, members = { "tank", "healer" } }     -- the OTHER members; fires GROUP_ROSTER_UPDATE
--   Mock.group.Leave()
local Mock = ...
local W = Mock.world

local CLASSES = {
	WARRIOR = { "Warrior", 1 }, PALADIN = { "Paladin", 2 }, HUNTER = { "Hunter", 3 }, ROGUE = { "Rogue", 4 },
	PRIEST = { "Priest", 5 }, SHAMAN = { "Shaman", 7 }, MAGE = { "Mage", 8 }, WARLOCK = { "Warlock", 9 },
	DRUID = { "Druid", 11 },
}

W.units = W.units or { entities = {}, order = {}, tokens = {}, serial = 0 }
W.group = W.group or { raid = false, members = {} }
local state = W.units
state.entities.player = W.player
if state.order[1] ~= "player" then table.insert(state.order, 1, "player") end

local units, group = {}, W.group
Mock.units, Mock.group = units, group

-- A mob GUID as the client writes it: type-0-server-instance-zone-npcID-spawn.
function units.NewGUID(entity)
	state.serial = state.serial + 1
	if entity and entity.hostile then
		return string.format("Creature-0-1-0-1-%d-%010X", entity.npcID or 100, state.serial)
	end
	return string.format("Player-1-%08X", 0x2000 + state.serial)
end

function units.Get(key) return state.entities[key] end

function units.Add(key, def)
	if state.entities[key] then error("Mock.units.Add: the unit " .. key .. " already exists", 2) end
	local entity = { key = key }
	for k, v in pairs(def or {}) do
		if k ~= "tokens" and k ~= "key" then entity[k] = v end
	end
	entity.name = entity.name or (key:sub(1, 1):upper() .. key:sub(2))
	entity.isPlayer = not entity.hostile and entity.isPlayer ~= false
	entity.class = entity.class or "WARRIOR"
	entity.level = entity.level or 60
	entity.guid = entity.guid or units.NewGUID(entity)
	state.entities[key] = entity
	state.order[#state.order + 1] = key
	for _, token in ipairs(def and def.tokens or {}) do units.SetToken(token, key) end
	return entity
end

local function memberKey(unit)
	local n = tonumber(unit:match("^party(%d)$"))
	if n then
		if group.raid then return nil end   -- in a raid, partyN (the own subgroup) is not imitated
		return group.members[n]
	end
	n = tonumber(unit:match("^raid(%d+)$"))
	if n and group.raid then
		if n == #group.members + 1 then return "player" end   -- the player is last, as the client may put them anywhere
		return group.members[n]
	end
	return nil
end

-- The key of the entity a token names, nil when it names nobody. A GUID is not a token.
local function resolveKey(unit)
	if type(unit) ~= "string" or issecretvalue(unit) then return nil end
	if unit == "player" then return "player" end
	if unit == "target" then return W.player.target end
	local key = state.tokens[unit] or memberKey(unit)
	if key then return key end
	local base = unit:match("^(.+)target$")
	if base then
		local entity = state.entities[resolveKey(base) or false]
		return entity and entity.target or nil
	end
	return nil
end

function units.Resolve(unit)
	local key = resolveKey(unit)
	return key and state.entities[key] or nil
end

-- The base tokens that exist, in the order UnitTokenFromGUID and the events walk them.
local function baseTokens()
	local list = { "player", "target", "focus", "mouseover" }
	for i = 1, 5 do list[#list + 1] = "boss" .. i end
	for i = 1, 4 do list[#list + 1] = "party" .. i end
	for i = 1, 40 do list[#list + 1] = "raid" .. i end
	for i = 1, 40 do list[#list + 1] = "nameplate" .. i end
	return list
end
local BASE_TOKENS = baseTokens()
local TOKEN_ORDER = {}
for i, token in ipairs(BASE_TOKENS) do TOKEN_ORDER[token] = i end

-- The base tokens naming a unit now (compound ones like "targettarget" are never in an event).
function units.TokensOf(key)
	local out = {}
	if key == "player" then out[#out + 1] = "player" end
	if W.player.target == key then out[#out + 1] = "target" end
	for token, named in pairs(state.tokens) do
		if named == key and TOKEN_ORDER[token] then out[#out + 1] = token end
	end
	for i, member in ipairs(group.members) do
		if member == key then out[#out + 1] = (group.raid and "raid" or "party") .. i end
	end
	if key == "player" and group.raid and #group.members > 0 then out[#out + 1] = "raid" .. (#group.members + 1) end
	table.sort(out, function(a, b) return TOKEN_ORDER[a] < TOKEN_ORDER[b] end)
	return out
end

local function checkKey(key)
	if key ~= nil and not state.entities[key] then error("mock units: no unit " .. tostring(key), 3) end
end

-- Sets who a unit targets; fires PLAYER_TARGET_CHANGED for the player and UNIT_TARGET for each of the unit's tokens.
function units.Target(key, targetKey)
	checkKey(key)
	checkKey(targetKey)
	local entity = state.entities[key]
	if entity.target == targetKey then return end
	entity.target = targetKey
	if key == "player" then Mock.Fire("PLAYER_TARGET_CHANGED") end
	for _, token in ipairs(units.TokensOf(key)) do Mock.Fire("UNIT_TARGET", token) end
end

function units.SetToken(token, key)
	checkKey(key)
	if token == "player" or token:find("^party%d$") or token:find("^raid%d+$") or token:find(".target$") then
		error("Mock.units.SetToken: " .. token .. " follows the group or a target, it cannot be set", 2)
	end
	if token == "target" then return units.Target("player", key) end
	local old = state.tokens[token]
	if old == key then return end
	if old and token:find("^nameplate") then
		Mock.Fire("NAME_PLATE_UNIT_REMOVED", token)   -- while the token still names the unit, as in the client
	end
	state.tokens[token] = key
	if token:find("^nameplate") then
		if key then Mock.Fire("NAME_PLATE_UNIT_ADDED", token) end
	elseif token == "focus" then
		Mock.Fire("PLAYER_FOCUS_CHANGED")
	elseif token:find("^boss%d$") then
		Mock.Fire("INSTANCE_ENCOUNTER_ENGAGE_UNIT")
	end
end

-- Group ------------------------------------------------------------------------------------------------------------
-- Members are unit keys, or definitions { key = "tank", ... } added on the way.
function group.Set(config)
	local members = {}
	for i, m in ipairs(config.members or {}) do
		if type(m) == "table" then
			units.Add(m.key, m)
			m = m.key
		end
		checkKey(m)
		members[i] = m
	end
	group.raid = config.raid == true
	group.members = members
	Mock.Fire("GROUP_ROSTER_UPDATE")
end

function group.Leave()
	group.raid, group.members = false, {}
	Mock.Fire("GROUP_ROSTER_UPDATE")
end

-- API --------------------------------------------------------------------------------------------------------------
local function entityOf(unit, name)
	if type(unit) ~= "string" then error("Usage: " .. name .. "(unit)", 3) end
	if issecretvalue(unit) then error(name .. ": a secret value is not a unit token", 3) end
	return units.Resolve(unit)
end

-- A value of a unit's identity: secret when the mock says so for this token.
local function identity(unit, value, kind)
	if value ~= nil and Mock.secrets.IdentitySecret(unit) then return Mock.Secret(kind or "string") end
	return value
end

function UnitExists(unit)
	if unit == nil then return false end
	return entityOf(unit, "UnitExists") ~= nil
end

function UnitGUID(unit)
	local e = entityOf(unit, "UnitGUID")
	if e then return identity(unit, e.guid) end
end

function UnitTokenFromGUID(guid)
	if issecretvalue(guid) then error("UnitTokenFromGUID: a secret value is not a GUID", 2) end
	for _, token in ipairs(BASE_TOKENS) do
		local e = units.Resolve(token)
		if e and e.guid == guid then return token end
	end
end

function UnitName(unit)
	local e = entityOf(unit, "UnitName")
	if e then return identity(unit, e.name), identity(unit, e.server) end
end

-- className (localized: the mock has English only), classFilename, classID
function UnitClass(unit)
	local e = entityOf(unit, "UnitClass")
	if not e then return nil end
	local class = CLASSES[e.class] or { e.class, 0 }
	return identity(unit, class[1]), identity(unit, e.class), identity(unit, class[2], "number")
end

function UnitClassification(unit)
	local e = entityOf(unit, "UnitClassification")
	if e then return e.classification or "normal" end
end

function UnitCanAttack(unit, target)
	local a, b = entityOf(unit, "UnitCanAttack"), entityOf(target, "UnitCanAttack")
	return a ~= nil and b ~= nil and (a.hostile == true) ~= (b.hostile == true)
end

function UnitIsDead(unit)
	local e = entityOf(unit, "UnitIsDead")
	return e ~= nil and e.dead == true
end

function UnitIsPlayer(unit)
	if unit == nil then return false end
	local e = entityOf(unit, "UnitIsPlayer")
	return e ~= nil and e.isPlayer == true
end

function UnitIsUnit(unit1, unit2)
	local a, b = entityOf(unit1, "UnitIsUnit"), entityOf(unit2, "UnitIsUnit")
	if Mock.secrets.ComparisonSecret(unit1, unit2) then return Mock.Secret("boolean") end
	return a ~= nil and a == b
end

function UnitAffectingCombat(unit)
	local e = entityOf(unit, "UnitAffectingCombat")
	return e ~= nil and e.combat == true
end

function UnitGroupRolesAssigned(unit)
	local e = unit and entityOf(unit, "UnitGroupRolesAssigned")
	return e and e.role or "NONE"
end

-- The raidN index of a unit, nil outside a raid (the player is last, as memberKey says).
function UnitInRaid(unit)
	if unit == nil or not group.raid or #group.members == 0 then return nil end
	local e = entityOf(unit, "UnitInRaid")
	if not e then return nil end
	if e.key == "player" then return #group.members + 1 end
	for i, member in ipairs(group.members) do
		if member == e.key then return i end
	end
	return nil
end

function IsInGroup() return #group.members > 0 end
function IsInRaid() return #group.members > 0 and group.raid end
function GetNumGroupMembers() return #group.members > 0 and (#group.members + 1) or 0 end
