-- Init: the addon object, the Forever check, the lifecycle, combat start and end, the /atw debug sections and the Addon
-- Compartment functions (SPEC-01 §3.1). Lua 5.1.
-- Adapted from Azeroth Accord (Core/Init.lua), same owner, GPL-3.0 (ADR 0012).
-- Later modules attach themselves to the private namespace `ns` and, when they need to be reachable from tests, to the
-- addon object (AzerothThreatwarden.Compat, .Config, ...). Modules that do not exist yet (Bus, Compat: M1.4; Config:
-- M1.5; Window: M1.7) are asked for with `if ns.X`.
-- The game calls made here move behind Core/Compat.lua in M1.4.
local ADDON_NAME, ns = ...
ns = ns or {}
ns.modules = ns.modules or {}

local ATW = LibStub("AceAddon-3.0"):NewAddon(ADDON_NAME, "AceConsole-3.0", "AceEvent-3.0")
local L = ns.L
ns.addon = ATW
ATW.L, ATW.Locale = L, ns.Locale
_G.AzerothThreatwarden = ATW

local FOREVER_MIN_INTERFACE, FOREVER_MAX_INTERFACE = 16001, 19999

-- True on WoW Forever: the project id constants when the client has them, else the Interface number (ARC-01).
function ATW:IsForever()
	if WOW_PROJECT_ID ~= nil and WOW_PROJECT_CAMELOT ~= nil then
		return WOW_PROJECT_ID == WOW_PROJECT_CAMELOT
	end
	local interface = GetBuildInfo and select(4, GetBuildInfo())
	return type(interface) == "number" and interface >= FOREVER_MIN_INTERFACE and interface <= FOREVER_MAX_INTERFACE
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
	if ns.Compat then ns.Compat:Probe() end
	self.isForever = self:IsForever()   -- false: diagnostic mode, no numbers (ARC-01)
	emit("ADDON_READY")
end

function ATW:OnEnable()   -- PLAYER_LOGIN
	self.inCombat = false
	self:RegisterEvent("PLAYER_REGEN_DISABLED", "OnCombatStart")
	self:RegisterEvent("PLAYER_REGEN_ENABLED", "OnCombatEnd")
	for _, module in ipairs(ns.onEnable or {}) do
		local ok, err = pcall(module)
		if not ok and geterrorhandler then geterrorhandler()(err) end
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

-- GameTooltip is part of the game's interface code, not of the API dump: looked up when used.
function AzerothThreatwarden_OnAddonCompartmentEnter(_, menuButtonFrame)
	if not GameTooltip then return end
	GameTooltip:SetOwner(menuButtonFrame or UIParent, "ANCHOR_LEFT")
	GameTooltip:SetText(L["ADDON_TITLE"])
	GameTooltip:AddLine(L["COMPARTMENT_HINT"])
	GameTooltip:Show()
end

function AzerothThreatwarden_OnAddonCompartmentLeave()
	if GameTooltip then GameTooltip:Hide() end
end
