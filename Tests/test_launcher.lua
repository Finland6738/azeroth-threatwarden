-- UI/Launcher.lua (SPEC-03 §4.6): the minimap button (shown, hidden, saved in Config) and the Addon Compartment, with
-- the same tooltip and the same clicks.

local function W() return AzerothThreatwarden.Window end
local function icon() return LibStub("LibDBIcon-1.0") end
local function button() return icon():GetMinimapButton("AzerothThreatwarden") end
local function Config() return AzerothThreatwarden.Config end

local TIP = { "Azeroth Threatwarden", "Development build", "Threat monitor: Idle", "Left-click: show or hide",
	"Right-click: settings" }

describe("the minimap button", function()
	it("is on the minimap at login, with the logo", function()
		notNil(button())
		truthy(button():IsShown())
		eq(button().dataObject.type, "launcher")
		eq(button().icon:GetTexture(), "Interface\\AddOns\\AzerothThreatwarden\\Media\\logo_64.tga")
		eq(button():GetParent(), Minimap)
	end)

	it("shows or hides the window with the left button and opens Settings with the right one", function()
		button():Click("LeftButton")
		falsy(W():IsShown())
		button():Click("LeftButton")
		truthy(W():IsShown())
		eq(W():Tab(), "monitor")
		W():Close()
		button():Click("RightButton")
		truthy(W():IsShown())
		eq(W():Tab(), "settings")
		eq(AzerothThreatwardenCharDB.ui.lastPage, "settings")
	end)

	it("keeps its settings in the account's saved data", function()
		eq(button().db, AzerothThreatwardenDB.settings.minimap)
	end)

	it("hides and comes back with account.settings.minimap.hide, also after a /reload", function()
		truthy(Config():Set("account.settings.minimap.hide", true))
		falsy(button():IsShown())
		Mock.Reload()
		eq(#Mock.errors, 0)
		isNil(button(), "a hidden button is not even made")
		Config():Set("account.settings.minimap.hide", false)
		truthy(button():IsShown())
		Mock.Reload()
		truthy(button():IsShown())
	end)

	it("comes back when the settings are reset", function()
		Config():Set("account.settings.minimap.hide", true)
		Config():ResetSettings()
		truthy(button():IsShown())
	end)

	it("keeps its place on the ring across a /reload", function()
		Config():Set("account.settings.minimap.minimapPos", 45)
		Mock.Reload()
		eq(button().db.minimapPos, 45)
	end)

	it("shows the tooltip with the version, the module state and the clicks", function()
		Mock.RunScript(button(), "OnEnter")
		local tip = icon().tooltip
		deepEq(Mock.TooltipLines(tip), TIP)
		Mock.RunScript(button(), "OnLeave")
		falsy(tip:IsShown())
	end)

	it("shows the version of a packaged build", function()
		C_AddOns.GetAddOnMetadata = function() return "0.1.0" end
		Mock.RunScript(button(), "OnEnter")
		eq(Mock.TooltipLines(icon().tooltip)[2], "Version 0.1.0")
	end)
end)

describe("the Addon Compartment (TOC functions)", function()
	it("shows or hides the window with a click and opens Settings with the right button", function()
		AzerothThreatwarden_OnAddonCompartmentClick("AzerothThreatwarden", "LeftButton")
		falsy(W():IsShown())
		AzerothThreatwarden_OnAddonCompartmentClick("AzerothThreatwarden")
		truthy(W():IsShown())
		AzerothThreatwarden_OnAddonCompartmentClick("AzerothThreatwarden", "RightButton")
		eq(W():Tab(), "settings")
		eq(#Mock.output, 0)
	end)

	it("shows the same tooltip as the minimap on enter and hides it on leave", function()
		AzerothThreatwarden_OnAddonCompartmentEnter("AzerothThreatwarden", CreateFrame("Button"))
		truthy(GameTooltip:IsShown())
		deepEq(Mock.TooltipLines(), TIP)
		AzerothThreatwarden_OnAddonCompartmentLeave()
		falsy(GameTooltip:IsShown())
	end)

	it("does nothing, without an error, on a client with no GameTooltip", function()
		GameTooltip = nil
		AzerothThreatwarden_OnAddonCompartmentEnter("AzerothThreatwarden")
		AzerothThreatwarden_OnAddonCompartmentLeave()
	end)
end)

describe("an Italian client", function()
	before_boot(function(M) M.player.locale = "itIT" end)

	it("shows the tooltip in Italian", function()
		AzerothThreatwarden_OnAddonCompartmentEnter("AzerothThreatwarden")
		deepEq(Mock.TooltipLines(), { "Azeroth Threatwarden", "Versione di sviluppo", "Monitor della threat: In attesa",
			"Clic sinistro: mostra o nascondi", "Clic destro: impostazioni" })
	end)
end)
