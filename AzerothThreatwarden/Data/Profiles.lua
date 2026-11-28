-- Profiles: the role profiles and their presets (SPEC-07 §4, SPEC-02 §3.11, ADR 0020, SPEC-09 Q28). Lua 5.1.
-- Threatwarden's own.
--
-- A profile is a copy of a fixed list of settings (Config.PROFILE_KEYS) kept in `account.profiles.<id>`, one for each
-- role of the game: `tank`, `healer`, `damager`. Every module goes on reading `account.settings` with Config:Get:
-- switching profile WRITES the profile's values into the live settings (the thresholds with Config:SetThresholds) while
-- the *applying* flag is up, and a change the player makes in a card is COPIED into the active profile when its
-- CONFIG_CHANGED arrives (outside *applying*). No other module knows that profiles exist.
--
-- The active profile and the automatic choice are the character's (`char.profile = { active, auto, role }`). With
-- `auto` on, the profile follows the role assigned to the player, Compat.Unit.Role("player") (UnitGroupRolesAssigned,
-- [probe P9]), read at ENTERING_WORLD, GROUP_CHANGED, PLAYER_ROLES_ASSIGNED and COMBAT_ENDED, never in a tick:
--   TANK, HEALER, DAMAGER                 -> tank, healer, damager, but only when the role differs from the last role
--                                            that chose a profile (`char.profile.role`): a choice made by hand holds
--                                            until the group assigns a different role, across /reload too;
--   nil, reason "none" (NONE)             -> unchanged (the card says which profile is in use);
--   nil, any other reason (secret...)     -> unchanged (the card says the role cannot be read here).
-- The first choice of a character (no `active` yet) is the role read, else `damager`. A choice made by hand records the
-- role read at that moment as `char.profile.role`, so the role it overrode does not take it back after a fight.
--
-- A switch never happens in combat: asked in combat (by the role or by the player) it waits for COMBAT_ENDED; a switch
-- asked by the role waits for the end of the demo too (the demo never changes the profile). On read-only data nothing
-- changes (SPEC-02 §3.4). PROFILE_CHANGED(id, old, why) is emitted once per switch, after the CONFIG_CHANGED of the
-- settings that changed; `why` is "role", "manual", "copy" or "reset". PROFILE_ROLE_READ(role, reason) is emitted when
-- the role read (or why it cannot be read) differs from the last one, for the card.
--
-- While the `profiles` switch is off (Core/Features.lua, until M8.R) this module registers no game event, copies
-- nothing and writes nothing; the settings work as before. Account schema 7 and character schema 3 are written anyway
-- (Core/Config.lua). Nothing here holds a name (PR-06).
local ADDON_NAME, ns = ...
ns = ns or {}
ns.modules = ns.modules or {}

local Profiles = {}
ns.Profiles, ns.modules.Profiles = Profiles, Profiles

local Compat, Config = ns.Compat, ns.Config
local type, ipairs, pairs, pcall, tostring = type, ipairs, pairs, pcall, tostring

Profiles.IDS = Config.PROFILE_IDS
Profiles.DEFAULT = "damager"            -- the first profile of a character without a role (SPEC-07 §4.3)
Profiles.enabled = false                -- the switch was on at login: events registered
Profiles.applying = false               -- the values of a profile are being written: no copy back
Profiles.pending = nil                  -- { id, why, role, reason }: a switch waiting for the end of the fight
                                        -- (reason "combat") or of the demo ("demo")
Profiles.role, Profiles.reason = nil, "unread"   -- the last role read and why it is missing (never saved)
Profiles.lastWhy = nil                  -- "role" or "manual": what made the last switch since the addon was loaded
Profiles.counts = { role = 0, manual = 0, copy = 0, reset = 0, preset = 0 }   -- since the addon was loaded

local SETTINGS = "account.settings."

local function emit(event, ...)
	if ns.Bus then ns.Bus.Emit(event, ...) end
end

local function switchOn() return ns.Features ~= nil and ns.Features.On("profiles") end
local function inCombat() return ns.addon ~= nil and ns.addon.inCombat == true end
local function inDemo() return ns.Demo ~= nil and ns.Demo.IsActive ~= nil and ns.Demo.IsActive() == true end
local function readOnly() return Config:IsReadOnly() end

local function isId(id)
	for _, known in ipairs(Profiles.IDS) do if known == id then return true end end
	return false
end

function Profiles.Enabled() return Profiles.enabled end

-- The active profile of this character, nil before the first choice.
function Profiles.Active()
	local id = Config:Get("char.profile.active")
	if isId(id) then return id end
	return nil
end

function Profiles.Auto() return Config:Get("char.profile.auto") ~= false end

-- Where the active profile comes from (PR-05): "role" (the group role chose it and still says it), "first" (the first
-- profile of a character that has had no role yet, unless the player chose it since the addon was loaded: what chose
-- the last switch is not saved) or "manual".
function Profiles.Source()
	local active, role = Profiles.Active(), Config:Get("char.profile.role")
	if active == nil then return nil end
	if Profiles.Auto() and role ~= nil and Config.ROLE_PROFILE[role] == active then return "role" end
	if role == nil and active == Profiles.DEFAULT and Profiles.Auto() and Profiles.lastWhy ~= "manual" then return "first" end
	return "manual"
end

-- Reads the assigned role (SPEC-07 §4.3). Returns role, reason; PROFILE_ROLE_READ when the answer changed.
function Profiles.ReadRole()
	local role, reason = Compat.Unit.Role("player")
	if role ~= nil then reason = nil elseif reason == nil then reason = "nil" end
	if role ~= Profiles.role or reason ~= Profiles.reason then
		Profiles.role, Profiles.reason = role, reason
		emit("PROFILE_ROLE_READ", role, reason)
	end
	return role, reason
end

---------------------------------------------------------------------------------------------------------------------
-- Applying a profile onto the live settings
---------------------------------------------------------------------------------------------------------------------
-- The values of profile `id`, each checked by the rule of its key: a wrong one goes back to the preset, into the profile
-- too, and into Config.issues (a path and fixed words).
local function valuesOf(id)
	local profile = Config:Get("account.profiles." .. id)
	local preset = Config.PRESETS[id]
	local values, fixed = {}, {}
	for _, key in ipairs(Config.PROFILE_KEYS) do
		local v = Config.ProfileValue(profile, key)
		local why = Config.Violation(Config.rules[SETTINGS .. key], v)
		if why then
			v = Config.Copy(Config.ProfileValue(preset, key))
			fixed[key] = v
			Config.AddIssue("account.profiles." .. id .. "." .. key .. ": back to the preset (" .. why .. ")")
		end
		values[key] = v
	end
	local broken = Config.PairViolation(values["monitor.warning"], values["monitor.danger"])
	if broken then
		values["monitor.warning"], values["monitor.danger"] = preset.monitor.warning, preset.monitor.danger
		fixed["monitor.warning"], fixed["monitor.danger"] = preset.monitor.warning, preset.monitor.danger
		Config.AddIssue("account.profiles." .. id .. ".monitor: thresholds back to the preset (" .. broken .. ")")
	end
	if next(fixed) ~= nil then
		for _ in pairs(fixed) do Profiles.counts.preset = Profiles.counts.preset + 1 end
		Config:SetProfileValues(id, fixed)
	end
	return values
end

-- Writes profile `id` into the live settings and makes it the active one. Out of combat, on writable data only.
local function apply(id, why, role)
	local old = Profiles.Active()
	local values = valuesOf(id)
	Profiles.applying = true
	local ok, err = pcall(function()
		Config:SetThresholds(values["monitor.warning"], values["monitor.danger"])
		for _, key in ipairs(Config.PROFILE_KEYS) do
			if key ~= "monitor.warning" and key ~= "monitor.danger" then Config:Set(SETTINGS .. key, values[key]) end
		end
	end)
	Profiles.applying = false
	if not ok then Compat.ReportError(err) end
	Config:Set("char.profile.active", id)
	if role ~= nil then Config:Set("char.profile.role", role) end
	Profiles.counts[why] = (Profiles.counts[why] or 0) + 1
	Profiles.lastWhy = why == "role" and "role" or "manual"
	emit("PROFILE_CHANGED", id, old, why)
	return true
end

-- A switch now, or later: in combat it waits for COMBAT_ENDED; a switch of the role waits for the end of the demo too.
-- Returns true when applied, or false and why ("combat", "demo"): then it is the pending one.
local function request(id, why, role)
	if inCombat() or (why == "role" and inDemo()) then
		local reason = inCombat() and "combat" or "demo"
		Profiles.pending = { id = id, why = why, role = role, reason = reason }
		return false, reason
	end
	Profiles.pending = nil
	return apply(id, why, role)
end

local function usable()
	if not Profiles.enabled then return false, "off" end
	if readOnly() then return false, "read-only" end
	if not Config:Get("account.profiles") then return false, "not loaded" end
	return true
end

---------------------------------------------------------------------------------------------------------------------
-- The choice, by the role and by hand
---------------------------------------------------------------------------------------------------------------------
-- The choice of SPEC-07 §4.3 from the role read now. Returns true when a switch was applied or is waiting.
function Profiles.Evaluate()
	if not usable() then return false end
	local role = Profiles.ReadRole()
	local active = Profiles.Active()
	if active == nil then
		request(role and Config.ROLE_PROFILE[role] or Profiles.DEFAULT, "role", role)
		return true
	end
	if not Profiles.Auto() or role == nil then return false end   -- NONE or a role that cannot be read: unchanged
	if role == Config:Get("char.profile.role") then return false end
	request(Config.ROLE_PROFILE[role], "role", role)
	return true
end

-- Profiles.Switch(id, why): `why` "manual" (the player: the card, /atw profile) or "role". Returns true when applied,
-- or false and why: "off", "read-only", "unknown", "combat" or "demo" (the last two: it waits and applies then).
function Profiles.Switch(id, why)
	local ok, reason = usable()
	if not ok then return false, reason end
	if not isId(id) then return false, "unknown" end
	why = why == "role" and "role" or "manual"
	-- a choice by hand records the role read now too: the role it overrode does not take it back (SPEC-07 §4.3)
	return request(id, why, (Profiles.ReadRole()))
end

-- `char.profile.auto`. Turned on, the profile follows the role read now at once (a role that cannot be read changes
-- nothing). Returns true, or false and why.
function Profiles.SetAuto(on)
	local ok, reason = usable()
	if not ok then return false, reason end
	local stored, why = Config:Set("char.profile.auto", on == true)
	if not stored then return false, why end
	if on then
		local role = Profiles.ReadRole()
		if role ~= nil then request(Config.ROLE_PROFILE[role], "role", role) end
	end
	return true
end

-- *Copy from…*: the values of profile `from` become those of the active one, and apply. Returns true, or false and why.
function Profiles.CopyFrom(from)
	local ok, reason = usable()
	if not ok then return false, reason end
	local active = Profiles.Active()
	if active == nil or not isId(from) or from == active then return false, "unknown" end
	local values = valuesOf(from)
	local stored, why = Config:SetProfileValues(active, values)
	if not stored then return false, why end
	return request(active, "copy", nil)
end

-- *Reset to preset*: the active profile back to its preset, and apply. Returns true, or false and why.
function Profiles.ResetActive()
	local ok, reason = usable()
	if not ok then return false, reason end
	local active = Profiles.Active()
	if active == nil then return false, "unknown" end
	local values = {}
	for _, key in ipairs(Config.PROFILE_KEYS) do values[key] = Config.ProfileValue(Config.PRESETS[active], key) end
	local stored, why = Config:SetProfileValues(active, values)
	if not stored then return false, why end
	return request(active, "reset", nil)
end

-- *Reset settings* with the switch on (SPEC-07 §4.4): the settings outside the profiles back to their defaults, the
-- active profile back to its preset (applied, after the fight in combat); the other two profiles stay. Returns true, or
-- false and why (like Config:ResetSettings).
function Profiles.ResetSettings()
	if not Profiles.enabled or Profiles.Active() == nil then return Config:ResetSettings() end
	local ok, why = Config:ResetSettings(Config.PROFILE_PATHS)
	if not ok then return false, why end
	Profiles.ResetActive()
	return true
end

---------------------------------------------------------------------------------------------------------------------
-- The copy back and the events
---------------------------------------------------------------------------------------------------------------------
-- A change of a setting of the profiles, outside *applying*, goes into the active profile (both thresholds together).
local function onConfigChanged(path)
	if not Profiles.enabled or Profiles.applying then return end
	local key = Config.PROFILE_PATHS[path]
	local active = key and Profiles.Active()
	if not active then return end
	local values = { [key] = Config:Get(path) }
	if key == "monitor.warning" or key == "monitor.danger" then
		values["monitor.warning"] = Config:Get(SETTINGS .. "monitor.warning")
		values["monitor.danger"] = Config:Get(SETTINGS .. "monitor.danger")
	end
	Config:SetProfileValues(active, values)
end

-- The pending switch, once the fight (and, for a role, the demo) is over; then the role is read again.
local function settle()
	if not Profiles.enabled then return end
	local p = Profiles.pending
	if p and not inCombat() and not (p.why == "role" and inDemo()) and not readOnly() then
		Profiles.pending = nil
		apply(p.id, p.why, p.role)
	end
	if not inCombat() then Profiles.Evaluate() end
end

local events = {}
function events.PLAYER_ROLES_ASSIGNED() Profiles.Evaluate() end

local function onEvent(event, ...)
	local handler = events[event]
	if handler then handler(event, ...) end
end

-- PLAYER_LOGIN (Core/Init.lua). Nothing with the switch off.
function Profiles.Enable()
	if Profiles.enabled or not switchOn() then return false end
	local AceEvent = LibStub and LibStub("AceEvent-3.0", true)
	if not AceEvent then return false end
	AceEvent:Embed(Profiles)
	Profiles:RegisterEvent("PLAYER_ROLES_ASSIGNED", onEvent)   -- PartyInfo in the dump, no payload
	Profiles.enabled = true
	if ns.addon and ns.addon.AddDebugSection then ns.addon:AddDebugSection("Profiles", Profiles.DebugLines) end
	return true
end

if ns.Bus then
	ns.Bus.On("CONFIG_LOADED", function() if Profiles.enabled then Profiles.pending = nil end end)
	ns.Bus.On("CONFIG_CHANGED", onConfigChanged)
	ns.Bus.On("ENTERING_WORLD", function() if Profiles.enabled then Profiles.Evaluate() end end)
	ns.Bus.On("GROUP_CHANGED", function() if Profiles.enabled then Profiles.Evaluate() end end)
	ns.Bus.On("COMBAT_ENDED", settle)
	ns.Bus.On("DEMO_CHANGED", function(active) if not active then settle() end end)
end
if ns.OnEnable then ns.OnEnable(Profiles.Enable) end

-- /atw debug, section *Profiles* (English, fixed words; never a name).
function Profiles.DebugLines()
	local p, c = Profiles.pending, Profiles.counts
	return {
		"switch: " .. (switchOn() and "on" or "off"),
		("active profile: %s (%s), follow the group role: %s"):format(tostring(Profiles.Active() or "none"),
			tostring(Profiles.Source() or "none"), Profiles.Auto() and "on" or "off"),
		("last role read: %s%s, role that chose a profile: %s"):format(tostring(Profiles.role or "none"),
			Profiles.reason and (" (" .. tostring(Profiles.reason) .. ")") or "",
			tostring(Config:Get("char.profile.role") or "none")),
		"switch waiting: " .. (p and ("yes (" .. p.id .. ", " .. p.why .. ")") or "no"),
		("switches by role %d, by hand %d, copies %d, resets %d; values put back to the preset %d"):format(c.role,
			c.manual, c.copy, c.reset, c.preset),
	}
end

if ns.addon then ns.addon.Profiles = Profiles end
