-- Launcher: the minimap button (LibDataBroker + LibDBIcon, hideable) and the Addon Compartment entry (the three global
-- functions named by the TOC), with the same tooltip and the same clicks (SPEC-03 §4.6). Lua 5.1.
-- Adapted from Azeroth Accord (the Compartment functions of Core/Init.lua), same owner, GPL-3.0 (ADR 0012); the minimap
-- button is Threatwarden's own (Accord has none).
--
-- Left click shows or hides the window, right click opens Settings. The button's place and visibility are
-- `account.settings.minimap`, the table handed to LibDBIcon. No game API is named here (ARC-02).
local ADDON_NAME, ns = ...
ns = ns or {}
ns.modules = ns.modules or {}

local Launcher = {}
ns.Launcher, ns.modules.Launcher = Launcher, Launcher

local L, Assets, Compat = ns.L, ns.Assets, ns.Compat

Launcher.NAME = ADDON_NAME   -- the name of the data object and of the button (LibDBIcon10_AzerothThreatwarden)

-- "Version 0.1.0"; a copy from the repository has no packaged version.
local function versionLine()
	local version = Compat.AddonVersion()
	if not version or version:find("@", 1, true) then return L["TOOLTIP_DEV"] end
	return L["TOOLTIP_VERSION"]:format(version)
end

-- The tooltip of both entries: name, version, module state and what the clicks do. `tip` is a game tooltip already
-- owned by the caller.
function Launcher.FillTooltip(tip)
	tip:SetText(L["ADDON_TITLE"])
	tip:AddLine(versionLine())
	if ns.Window then
		local state = ns.Window.STATES[ns.Window.ModuleState()]
		tip:AddLine(L["TOOLTIP_STATE"]:format(L[state.labelKey]))
	end
	tip:AddLine(L["TOOLTIP_LEFT"])
	tip:AddLine(L["TOOLTIP_RIGHT"])
end

function Launcher.Click(button)
	if not ns.Window then return end
	if button == "RightButton" then ns.Window:OpenPage("settings") else ns.Window:Toggle() end
end

local function minimapSettings()
	return ns.Config and ns.Config:Get("account.settings.minimap")
end

-- Creates the data object and the button once (PLAYER_LOGIN). False when the libraries are not there.
function Launcher:Register()
	local ldb = LibStub("LibDataBroker-1.1", true)
	local dbicon = LibStub("LibDBIcon-1.0", true)
	local db = minimapSettings()
	if not ldb or not dbicon or not db then return false end
	self.object = self.object or ldb:GetDataObjectByName(Launcher.NAME) or ldb:NewDataObject(Launcher.NAME, {
		type = "launcher",
		label = L["ADDON_TITLE"],
		icon = Assets.logos.logo_64.path,
		OnClick = function(_, button) Launcher.Click(button) end,
		OnTooltipShow = function(tip) Launcher.FillTooltip(tip) end,
	})
	if not dbicon:IsRegistered(Launcher.NAME) then dbicon:Register(Launcher.NAME, self.object, db) end
	self.icon = dbicon
	return true
end

-- Applies `account.settings.minimap` to the button (shown or hidden, its place on the ring).
function Launcher:Refresh()
	local db = minimapSettings()
	if self.icon and db then self.icon:Refresh(Launcher.NAME, db) end
end

-- Addon Compartment entry points (globals named in the TOC).
function AzerothThreatwarden_OnAddonCompartmentClick(_, button)
	Launcher.Click(button)
end

-- GameTooltip is part of the game's interface code, not of the API dump: Compat looks it up when used.
function AzerothThreatwarden_OnAddonCompartmentEnter(_, menuButtonFrame)
	local tip = Compat.Tooltip()
	if not tip then return end
	tip:SetOwner(menuButtonFrame or Compat.UIParent(), "ANCHOR_LEFT")
	Launcher.FillTooltip(tip)
	tip:Show()
end

function AzerothThreatwarden_OnAddonCompartmentLeave()
	local tip = Compat.Tooltip()
	if tip then tip:Hide() end
end

if ns.Bus then
	ns.Bus.On("CONFIG_CHANGED", function(path)
		if type(path) == "string" and path:find("^account%.settings%.minimap%.") then Launcher:Refresh() end
	end)
end
if ns.OnEnable then ns.OnEnable(function() Launcher:Register() end) end
if ns.addon then ns.addon.Launcher = Launcher end
