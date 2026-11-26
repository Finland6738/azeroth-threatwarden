-- Mock client, part 8: combat state, restrictions, instances and encounters.
--
-- Imitates: InCombatLockdown, C_RestrictedActions.InCombatLockdown and IsAddOnRestrictionActive,
-- Enum.AddOnRestrictionType, C_CombatLog.IsCombatLogRestricted, C_DamageMeter.IsDamageMeterAvailable, IsInInstance,
-- GetInstanceInfo, GetRealZoneText, and the events PLAYER_REGEN_DISABLED, PLAYER_REGEN_ENABLED, ADDON_RESTRICTION_STATE_CHANGED,
-- ENCOUNTER_START, ENCOUNTER_END.
-- Dump (../WoW-Addons/docs/api.json, build 70170): systems RestrictedActions, CombatLog, DamageMeter, Instance, Unit,
-- EncounterInfo, ZoneScript (GetRealZoneText); InCombatLockdown is in `globals`. The values of Enum.AddOnRestrictionType and
-- Enum.AddOnRestrictionState are not in the dump (P11): the ones below are the retail names and are **invented** for
-- Forever; the addon must read them at run time. CombatLogGetCurrentEventInfo is absent from the dump and from the mock.
--
--   Mock.combat.Enter("tank", "boss")      -- the player (and the listed units) enter combat
--   Mock.combat.Leave()                    -- everybody leaves combat
--   Mock.combat.InCombat()
--   Mock.combat.SetRestriction("Encounter", true)
--   Mock.combat.StartEncounter(101, "Test Boss", 1, 5) / Mock.combat.EndEncounter(true)
--   Mock.instance.Set{ type = "party", difficultyID = 1, maxPlayers = 5, id = 36 }   -- nil leaves the instance
--   Mock.instance.SetZone("Elwynn Forest")   -- the zone's name (GetRealZoneText); nil gives "" as the client does
local Mock = ...
local W = Mock.world

W.combat = W.combat or { inCombat = false, restrictions = {} }
local state = W.combat
local combat, instance = {}, {}
Mock.combat, Mock.instance = combat, instance

Enum.AddOnRestrictionType = { Combat = 0, Encounter = 1, ChallengeMode = 2, PvPMatch = 3, Map = 4 }
Enum.AddOnRestrictionState = { Inactive = 0, Activating = 1, Active = 2 }

function combat.InCombat() return state.inCombat end

function combat.Enter(...)
	for _, key in ipairs({ "player", ... }) do
		local e = Mock.units.Get(key)
		if not e then error("Mock.combat.Enter: no unit " .. tostring(key), 2) end
		e.combat = true
	end
	if not state.inCombat then
		state.inCombat = true
		Mock.Fire("PLAYER_REGEN_DISABLED")
	end
end

function combat.Leave()
	for _, e in pairs(W.units.entities) do e.combat = false end
	if state.inCombat then
		state.inCombat = false
		Mock.Fire("PLAYER_REGEN_ENABLED")
	end
end

function InCombatLockdown() return state.inCombat end

C_RestrictedActions = {}
function C_RestrictedActions.InCombatLockdown() return state.inCombat end
function C_RestrictedActions.IsAddOnRestrictionActive(kind)
	if type(kind) ~= "number" then error("Usage: IsAddOnRestrictionActive(type)", 2) end
	return state.restrictions[kind] == true
end

function combat.SetRestriction(name, active)
	local kind = Enum.AddOnRestrictionType[name]
	if not kind then error("Mock.combat.SetRestriction: no restriction " .. tostring(name), 2) end
	state.restrictions[kind] = active and true or nil
	local value = active and Enum.AddOnRestrictionState.Active or Enum.AddOnRestrictionState.Inactive
	Mock.Fire("ADDON_RESTRICTION_STATE_CHANGED", kind, value)
end

C_CombatLog = {}
function C_CombatLog.IsCombatLogRestricted() return state.combatLogRestricted == true end

C_DamageMeter = {}
-- isAvailable, failureReason
function C_DamageMeter.IsDamageMeterAvailable()
	if state.damageMeter == false then return false, "Unavailable" end
	return true, ""
end

function combat.StartEncounter(id, name, difficultyID, groupSize)
	state.encounter = { id = id, name = name or "Test Encounter", difficultyID = difficultyID or 1, size = groupSize or 5 }
	Mock.Fire("ENCOUNTER_START", id, state.encounter.name, state.encounter.difficultyID, state.encounter.size)
end

function combat.EndEncounter(success)
	local e = state.encounter
	if not e then error("Mock.combat.EndEncounter: no encounter", 2) end
	state.encounter = nil
	Mock.Fire("ENCOUNTER_END", e.id, e.name, e.difficultyID, e.size, success and 1 or 0, {})
end

function instance.Set(config) W.instance = config end

function IsInInstance()
	local i = W.instance
	if i then return true, i.type or "party" end
	return false, "none"
end

-- name, instanceType, difficultyID, difficultyName, maxPlayers, dynamicDifficulty, isDynamic, instanceID,
-- instanceGroupSize, lfgDungeonID, hasWorldTier
function GetInstanceInfo()
	local i = W.instance or {}
	return i.name or (W.instance and "Test Instance" or "Test Continent"), i.type or "none", i.difficultyID or 0, "",
		i.maxPlayers or 0, 0, false, i.id or 0, GetNumGroupMembers(), nil, false
end

function instance.SetZone(name) W.zone = name end

-- The name of the zone: "Test Zone" until a test sets another; an empty string when it is set to false.
function GetRealZoneText(mapID)
	if W.zone == false then return "" end
	return W.zone or "Test Zone"
end
