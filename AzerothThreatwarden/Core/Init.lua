-- Init: the addon object, the Forever check, the lifecycle, combat start and end, the /atw debug sections and the Addon
-- Compartment functions (SPEC-01 §3.1). Lua 5.1.
-- Adapted from Azeroth Accord (Core/Init.lua), same owner, GPL-3.0 (ADR 0012).
-- Modules attach themselves to the private namespace `ns`; the ones loaded before this file (Bus, Compat, Locale) are
-- attached to the addon object here, the later ones attach themselves (AzerothThreatwarden.Scheduler, ...). Modules
-- that do not exist yet (Config: M1.5; Window: M1.7) are asked for with `if ns.X`. Every game call goes through
-- Core/Compat.lua (ARC-02).
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

-- Opens or closes the window (UI/Window.lua, M1.7): the Addon Compartment and, later, the commands and the minimap.
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
	-- Only /atw debug for now; Core/Commands.lua (M1.7) takes the command over with /threatwarden and the full set.
	self:RegisterChatCommand("atw", "OnSlashCommand")
	emit("ADDON_READY")
end

function ATW:OnEnable()   -- PLAYER_LOGIN
	self.inCombat = false
	self:RegisterEvent("PLAYER_REGEN_DISABLED", "OnCombatStart")
	self:RegisterEvent("PLAYER_REGEN_ENABLED", "OnCombatEnd")
	self:RegisterEvent("ADDON_RESTRICTION_STATE_CHANGED", "OnRestrictionChanged")
	for _, module in ipairs(ns.onEnable or {}) do
		local ok, err = pcall(module)
		if not ok then Compat.ReportError(err) end
	end
end

-- The client is turning an addon restriction on or off [probe P11]: Compat updates the capability restricted.<Type>.
function ATW:OnRestrictionChanged(_, kind)
	Compat:OnRestrictionChanged(kind)
end

-- /atw: `debug` opens the diagnostic report; no argument toggles the window; anything else says the commands are
-- coming (the full set is M1.7).
function ATW:OnSlashCommand(input)
	local command = type(input) == "string" and input:match("^%s*(%S*)"):lower() or ""
	if command == "debug" then
		if ns.Diagnostics then ns.Diagnostics.Show() end
	elseif command == "" then
		self:Toggle()
	else
		self:Print(L["COMMANDS_SOON"])
	end
end

function ATW:OnCombatStart()
	self.inCombat = true
	emit("COMBAT_STARTED")
end

function ATW:OnCombatEnd()
	self.inCombat = false
	emit("COMBAT_ENDED")
end

-- Addon Compartment entry points (globals named in the TOC; UI/Launcher.lua completes them in M1.7).
function AzerothThreatwarden_OnAddonCompartmentClick()
	ATW:Toggle()
end

-- GameTooltip is part of the game's interface code, not of the API dump: Compat looks it up when used.
function AzerothThreatwarden_OnAddonCompartmentEnter(_, menuButtonFrame)
	local tip = Compat.Tooltip()
	if not tip then return end
	tip:SetOwner(menuButtonFrame or Compat.UIParent(), "ANCHOR_LEFT")
	tip:SetText(L["ADDON_TITLE"])
	tip:AddLine(L["COMPARTMENT_HINT"])
	tip:Show()
end

function AzerothThreatwarden_OnAddonCompartmentLeave()
	local tip = Compat.Tooltip()
	if tip then tip:Hide() end
end
