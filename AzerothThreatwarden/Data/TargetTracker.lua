-- TargetTracker: the monitored mob (SPEC-03 §1.2, SPEC-01 §3.2). Lua 5.1. Threatwarden's own.
--
-- One rule, evaluated again at PLAYER_TARGET_CHANGED, at UNIT_TARGET for "target", at COMBAT_STARTED and COMBAT_ENDED,
-- and whenever a scan of Data/ThreatScanner.lua calls TargetTracker.Check():
--   1. the target ("target") when it exists, the player can attack it and it is not dead;
--   2. else, with *Follow target of target* on (the default) and a friendly target, the target's target
--      ("targettarget") on the same conditions: a healer who selects the tank sees the tank's mob;
--   3. else no mob: no threat is read.
-- Identity (mobKey, never a name): "mob:" .. GUID when UnitGUID is readable, else "tgt:" .. n, n growing at every change
-- seen [probe P9]. A readable GUID makes the capability mobIdentity available, a secret one restricted.
--
-- TARGET_CHANGED(mobKey) is emitted on the Bus when the monitored mob changes (nil: no mob). TargetTracker.status says
-- why there is none: "none" (no hostile target), "died" (the mob died), "lost" (it no longer exists: it vanished, or
-- the token names nobody any more). After a death or a loss the status stays until another mob is monitored.
--
-- A change of `status` with no mob before or after (a dead mob deselected) emits TARGET_STATUS(status) for the view.
-- It reads existence, hostility, death and GUID (and, when the view asks, the names and classification of the header)
-- only, through Core/Compat.lua, and works out of combat too (the header
-- shows the mob before the pull). While the `monitor` switch is off (Core/Features.lua) it registers no game event and
-- monitors nothing. Check() is allocation-free unless the mob changed (ARC-06): it runs on every scan.
local ADDON_NAME, ns = ...
ns = ns or {}
ns.modules = ns.modules or {}

local TargetTracker = {}
ns.TargetTracker, ns.modules.TargetTracker = TargetTracker, TargetTracker

local Compat = ns.Compat
local Unit = Compat.Unit
local type = type

-- Used until schema 2 of Core/Config.lua (M2.6) stores account.settings.monitor.followTargetOfTarget.
TargetTracker.DEFAULTS = { followTargetOfTarget = true }
local FOLLOW_PATH = "account.settings.monitor.followTargetOfTarget"

TargetTracker.mobToken = nil   -- "target", "targettarget" or nil
TargetTracker.mobKey = nil     -- "mob:<GUID>", "tgt:<n>" or nil
TargetTracker.mobGUID = nil    -- the readable GUID of the mob, nil when secret or unknown (never a secret value)
TargetTracker.status = "none"  -- "active", "none", "died", "lost"
TargetTracker.changes = 0      -- n of the "tgt:" keys: grows at every change seen
TargetTracker.enabled = false  -- game events registered (the monitor switch was on at login)

local function emit(event, ...)
	if ns.Bus then ns.Bus.Emit(event, ...) end
end

function TargetTracker.FollowTargetOfTarget()
	local value = ns.Config and ns.Config.Get and ns.Config:Get(FOLLOW_PATH)
	if type(value) == "boolean" then return value end
	return TargetTracker.DEFAULTS.followTargetOfTarget
end

-- true when `token` names a living mob the player can attack.
local function isMob(token)
	if Unit.Exists(token) ~= true then return false end
	if Unit.CanAttack("player", token) ~= true then return false end
	return Unit.IsDead(token) ~= true
end

-- The token of the mob the rule picks, or nil.
local function pick()
	if isMob("target") then return "target" end
	if TargetTracker.FollowTargetOfTarget() and Unit.Exists("target") == true
		and Unit.CanAttack("player", "target") == false and isMob("targettarget") then
		return "targettarget"
	end
	return nil
end

local function setIdentity(guidReason)
	if guidReason == "secret" then
		Compat:SetCapability("mobIdentity", Compat.RESTRICTED, "secret GUID")
	elseif guidReason == nil then
		Compat:SetCapability("mobIdentity", Compat.AVAILABLE, nil)
	end
end

-- Monitors `token` (nil: no mob, with `status`). `fresh`: an event says the unit behind the token changed, so an
-- unreadable GUID makes a new "tgt:" key.
local function apply(token, fresh, status)
	local old = TargetTracker.mobKey
	if not token then
		TargetTracker.mobToken, TargetTracker.mobKey, TargetTracker.mobGUID = nil, nil, nil
		-- "died" and "lost" stay until the player's target changes
		local before = TargetTracker.status
		if old ~= nil or fresh or TargetTracker.status == "active" then TargetTracker.status = status or "none" end
		if old ~= nil then emit("TARGET_CHANGED", nil)
		elseif TargetTracker.status ~= before then emit("TARGET_STATUS", TargetTracker.status) end
		return
	end
	local guid, reason = Unit.GUID(token)
	setIdentity(reason)
	local key
	if guid then
		if guid == TargetTracker.mobGUID and old then
			key = old
		else
			key = "mob:" .. guid
		end
	elseif old and not fresh and token == TargetTracker.mobToken and TargetTracker.mobGUID == nil then
		key = old   -- the same token, nothing says the unit changed: the same mob
	else
		TargetTracker.changes = TargetTracker.changes + 1
		key = "tgt:" .. TargetTracker.changes
	end
	TargetTracker.mobToken, TargetTracker.mobGUID, TargetTracker.status = token, guid, "active"
	if key ~= old then
		TargetTracker.mobKey = key
		emit("TARGET_CHANGED", key)
	end
end

-- Why the mob monitored until now is gone: "died" or "lost" ("none" when there was none).
local function goneStatus()
	local token = TargetTracker.mobToken
	if not token then return "none" end
	local exists = Unit.Exists(token)
	if exists ~= true then return "lost" end
	if Unit.IsDead(token) == true then return "died" end
	return "none"
end

-- Evaluates the rule again. `fresh`: an event says the unit behind a token changed. Returns the mobKey.
function TargetTracker.Evaluate(fresh)
	if not (ns.Features and ns.Features.On("monitor")) then
		apply(nil, true, "none")
		return nil
	end
	local token = pick()
	if not token then
		apply(nil, fresh, goneStatus())
	else
		apply(token, fresh, nil)
	end
	return TargetTracker.mobKey
end

-- Called by every scan: true while the monitored mob is still there and the same. A dead or vanished mob, or a readable
-- GUID different from the key (the same tokens now name another creature, without an event), evaluates the rule again
-- (TARGET_CHANGED). Allocation-free while nothing changed.
function TargetTracker.Check()
	local token = TargetTracker.mobToken
	if not token then return false end
	if Unit.Exists(token) ~= true or Unit.IsDead(token) == true then
		TargetTracker.Evaluate(false)
		return TargetTracker.mobToken ~= nil
	end
	local known = TargetTracker.mobGUID
	if known then
		local guid = Unit.GUID(token)
		if guid and guid ~= known then
			TargetTracker.Evaluate(true)
			return TargetTracker.mobToken ~= nil
		end
	end
	return true
end

-- The header of the monitor (SPEC-03 §1.6): the mob's name and classification, and the name of its target, who
-- holds it when no watched unit does (SPEC-03 §1.3). Read when asked, never per scan; nil when secret or unknown.
local TARGET_OF = { target = "targettarget", targettarget = "targettargettarget" }

function TargetTracker.MobName()
	local token = TargetTracker.mobToken
	if not token then return nil end
	return (Unit.Name(token))
end

function TargetTracker.MobClassification()
	local token = TargetTracker.mobToken
	if not token then return nil end
	return (Unit.Classification(token))
end

function TargetTracker.HolderName()
	local of = TARGET_OF[TargetTracker.mobToken or ""]
	if not of then return nil end
	return (Unit.Name(of))
end

function TargetTracker.MobToken() return TargetTracker.mobToken end
function TargetTracker.MobKey() return TargetTracker.mobKey end
function TargetTracker.Status() return TargetTracker.status end

-- Game events (registered at login only while the monitor switch is on).
local events = {}

function events.PLAYER_TARGET_CHANGED()
	TargetTracker.Evaluate(true)
end

-- UNIT_TARGET(unit): only the player's target turning matters (the target of target); a secret payload is ignored.
function events.UNIT_TARGET(_, unit)
	if Compat.IsSecret(unit) or unit ~= "target" then return end
	TargetTracker.Evaluate(TargetTracker.mobToken ~= "target")
end

local function onEvent(event, ...)
	local handler = events[event]
	if handler then handler(event, ...) end
end

function TargetTracker.Enable()
	if TargetTracker.enabled or not (ns.Features and ns.Features.On("monitor")) then return false end
	local AceEvent = LibStub and LibStub("AceEvent-3.0", true)
	if not AceEvent then return false end
	AceEvent:Embed(TargetTracker)
	TargetTracker:RegisterEvent("PLAYER_TARGET_CHANGED", onEvent)
	TargetTracker:RegisterEvent("UNIT_TARGET", onEvent)
	TargetTracker.enabled = true
	if ns.addon and ns.addon.AddDebugSection then ns.addon:AddDebugSection("Target", TargetTracker.DebugLines) end
	TargetTracker.Evaluate(true)
	return true
end

if ns.Bus then
	ns.Bus.On("COMBAT_STARTED", function() if TargetTracker.enabled then TargetTracker.Evaluate(false) end end)
	ns.Bus.On("COMBAT_ENDED", function() if TargetTracker.enabled then TargetTracker.Evaluate(false) end end)
	ns.Bus.On("CONFIG_CHANGED", function(path)
		if TargetTracker.enabled and path == FOLLOW_PATH then TargetTracker.Evaluate(false) end
	end)
end
if ns.OnEnable then ns.OnEnable(TargetTracker.Enable) end

-- /atw debug: the token and how the mob is known, never its name or GUID.
function TargetTracker.DebugLines()
	local key = TargetTracker.mobKey
	local kind = key and (key:find("^mob:") and "GUID" or "counter") or "none"
	return { ("mob: %s (%s), status %s, follow target of target %s"):format(TargetTracker.mobToken or "none", kind,
		TargetTracker.status, TargetTracker.FollowTargetOfTarget() and "on" or "off") }
end

if ns.addon then ns.addon.TargetTracker = TargetTracker end
