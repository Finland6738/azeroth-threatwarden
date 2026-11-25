-- Init: the addon object, the Forever check, the lifecycle, combat start and end, screen changes and the /atw debug
-- sections (SPEC-01 §3.1). Lua 5.1.
-- Adapted from Azeroth Accord (Core/Init.lua), same owner, GPL-3.0 (ADR 0012).
-- Modules attach themselves to the private namespace `ns`; the ones loaded before this file (Bus, Compat, Locale) are
-- attached to the addon object here, the later ones attach themselves (AzerothThreatwarden.Scheduler, Config, ...).
-- Modules loaded after this file are asked for with `if ns.X`. Every game call goes through Core/Compat.lua (ARC-02).
-- The commands are Core/Commands.lua, the Addon Compartment and the minimap button UI/Launcher.lua.
--
-- At ADDON_LOADED the order matters: Config loads the saved data first, then Locale picks the language from
-- `account.settings.language` (the one place of SPEC-09 Q5), then Compat probes the client.
local ADDON_NAME, ns = ...
ns = ns or {}
ns.modules = ns.modules or {}

local ATW = LibStub("AceAddon-3.0"):NewAddon(ADDON_NAME, "AceConsole-3.0", "AceEvent-3.0")
local L = ns.L
local Compat = ns.Compat
ns.addon = ATW
ATW.L, ATW.Locale, ATW.Bus, ATW.Compat = L, ns.Locale, ns.Bus, Compat
_G.AzerothThreatwarden = ATW

-- True on WoW Forever: the project id constants when the client has them, else the Interface number (ARC-01).
function ATW:IsForever()
	return Compat.IsForever()
end

local function emit(event, ...)
	if ns.Bus then ns.Bus.Emit(event, ...) end
end

-- /atw debug sections: modules add a function returning text lines (never player, guild or realm names).
ATW.debugSections = {}
function ATW:AddDebugSection(title, linesFn)
	for _, section in ipairs(self.debugSections) do
		if section.title == title then
			section.linesFn = linesFn
			return
		end
	end
	self.debugSections[#self.debugSections + 1] = { title = title, linesFn = linesFn }
end

-- Shows or hides the window (UI/Window.lua).
function ATW:Toggle()
	if ns.Window then return ns.Window:Toggle() end
	self:Print(L["COMING_SOON"])
end

-- Modules that need PLAYER_LOGIN call this at load time; the functions run in order from OnEnable.
function ns.OnEnable(fn)
	ns.onEnable = ns.onEnable or {}
	ns.onEnable[#ns.onEnable + 1] = fn
end

function ATW:OnInitialize()   -- ADDON_LOADED: the SavedVariables are available now
	if ns.Config then ns.Config:Load() end
	ns.Locale.Apply(ns.Config and ns.Config:Get("account.settings.language") or "auto")
	Compat:Probe()
	self.isForever = self:IsForever()   -- false: diagnostic mode, no numbers (ARC-01)
	if ns.Commands then ns.Commands.Register() end   -- /threatwarden and /atw
	emit("ADDON_READY")
end

function ATW:OnEnable()   -- PLAYER_LOGIN
	self.inCombat = false
	self:RegisterEvent("PLAYER_REGEN_DISABLED", "OnCombatStart")
	self:RegisterEvent("PLAYER_REGEN_ENABLED", "OnCombatEnd")
	self:RegisterEvent("ADDON_RESTRICTION_STATE_CHANGED", "OnRestrictionChanged")
	self:RegisterEvent("DISPLAY_SIZE_CHANGED", "OnDisplayChanged")
	self:RegisterEvent("UI_SCALE_CHANGED", "OnDisplayChanged")
	for _, module in ipairs(ns.onEnable or {}) do
		local ok, err = pcall(module)
		if not ok then Compat.ReportError(err) end
	end
end

-- The client is turning an addon restriction on or off [probe P11]: Compat updates the capability restricted.<Type>.
function ATW:OnRestrictionChanged(_, kind)
	Compat:OnRestrictionChanged(kind)
end

-- The screen or the interface scale changed: the window brings itself back inside.
function ATW:OnDisplayChanged()
	emit("DISPLAY_CHANGED")
end

function ATW:OnCombatStart()
	self.inCombat = true
	emit("COMBAT_STARTED")
end

function ATW:OnCombatEnd()
	self.inCombat = false
	emit("COMBAT_ENDED")
end
