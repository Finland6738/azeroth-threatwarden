-- Core/Init.lua (SPEC-01 §3.1, §11; ARC-01, ARC-04): the addon boots on the mock client, knows whether the client is
-- WoW Forever, follows the combat, answers the Addon Compartment and survives a simulated /reload.

local function A() return AzerothThreatwarden end

describe("loading the addon", function()
	it("boots with no Lua error, with the addon object and its modules", function()
		eq(#Mock.errors, 0)
		notNil(A())
		eq(A(), Mock.ns.addon)
		eq(A().Features, Mock.ns.Features)
		eq(A().L, Mock.ns.L)
		truthy(A():IsEnabled(), "AceAddon enabled it at PLAYER_LOGIN")
		eq(C_AddOns.GetAddOnMetadata("AzerothThreatwarden", "Interface"), "16001")
	end)

	it("loads the libraries and then the addon files in TOC order", function()
		local first
		for i, name in ipairs(Mock.loadedFiles) do
			if not name:find("/Libs/", 1, true) then first = i break end
		end
		truthy(first and first > 1, "the libraries come first")
		local own = {}
		for i = first, #Mock.loadedFiles do own[#own + 1] = Mock.loadedFiles[i] end
		deepEq(own, {
			"AzerothThreatwarden/Core/Locale.lua", "AzerothThreatwarden/Locales/enUS.lua",
			"AzerothThreatwarden/Locales/itIT.lua", "AzerothThreatwarden/Core/Init.lua",
			"AzerothThreatwarden/Core/Features.lua",
		})
	end)

	it("defines no global but the addon object and the Compartment functions (ARC-04)", function()
		deepEq(Mock.NewGlobals(), {
			"AzerothThreatwarden", "AzerothThreatwarden_OnAddonCompartmentClick",
			"AzerothThreatwarden_OnAddonCompartmentEnter", "AzerothThreatwarden_OnAddonCompartmentLeave",
		})
	end)

	it("prints nothing, writes no saved data and starts no timer at login", function()
		eq(#Mock.output, 0)
		isNil(AzerothThreatwardenDB)
		isNil(AzerothThreatwardenCharDB)
		eq(Mock.PendingTimers(), 0)
	end)
end)

describe("the Forever check (ARC-01)", function()
	it("is true on the client the project targets", function()
		truthy(A().isForever)
		truthy(A():IsForever())
	end)

	it("is false when the client's project is another one, whatever its interface number", function()
		boot(function() WOW_PROJECT_ID = WOW_PROJECT_MAINLINE end)
		falsy(A().isForever)
	end)

	it("falls back to the interface number when the project constants are missing", function()
		boot(function() WOW_PROJECT_ID, WOW_PROJECT_CAMELOT = nil, nil end)
		truthy(A().isForever, "16001")
		for _, case in ipairs({ { 16000, false }, { 16001, true }, { 19999, true }, { 20000, false }, { 120000, false } }) do
			Mock.client.interface = case[1]
			eq(A():IsForever(), case[2], tostring(case[1]))
		end
	end)

	it("is false when the client cannot say anything", function()
		boot(function()
			WOW_PROJECT_ID, WOW_PROJECT_CAMELOT, GetBuildInfo = nil, nil, nil
		end)
		falsy(A().isForever)
	end)
end)

-- A stand-in for Core/Bus.lua (M1.4) that records what Init raises, and keeps the real one working once it exists.
local raised
local function recordBus()
	raised = {}
	Mock.OnFilesLoaded(function()
		Mock.ns.Bus = Mock.ns.Bus or { Emit = function() end }
		local emit = Mock.ns.Bus.Emit
		Mock.ns.Bus.Emit = function(event, ...)
			raised[#raised + 1] = event
			return emit(event, ...)
		end
	end)
end

local function times(event)
	local n = 0
	for _, name in ipairs(raised) do
		if name == event then n = n + 1 end
	end
	return n
end

describe("the lifecycle and combat (SPEC-01 §3.3)", function()
	before_boot(recordBus)

	it("raises ADDON_READY once, at ADDON_LOADED", function()
		eq(times("ADDON_READY"), 1)
	end)

	it("follows PLAYER_REGEN_DISABLED and PLAYER_REGEN_ENABLED", function()
		eq(A().inCombat, false)
		Mock.combat.Enter()
		eq(A().inCombat, true)
		eq(times("COMBAT_STARTED"), 1)
		Mock.combat.Leave()
		eq(A().inCombat, false)
		eq(times("COMBAT_ENDED"), 1)
	end)

	it("runs every OnEnable function, and an error in one does not stop the others", function()
		local ran = {}
		boot(function()
			Mock.OnFilesLoaded(function()
				Mock.ns.OnEnable(function() ran[#ran + 1] = "first" error("boom in OnEnable") end)
				Mock.ns.OnEnable(function() ran[#ran + 1] = "second" end)
			end)
		end)
		deepEq(ran, { "first", "second" })
		eq(#Mock.errors, 1)
		contains(Mock.errors[1].message, "boom in OnEnable")
		Mock.ClearErrors()
	end)
end)

describe("debug sections", function()
	it("keeps one section per title, the last function winning", function()
		local count = #A().debugSections
		A():AddDebugSection("One", function() return { "a" } end)
		A():AddDebugSection("One", function() return { "b" } end)
		eq(#A().debugSections, count + 1)
		deepEq(A().debugSections[count + 1].linesFn(), { "b" })
	end)
end)

describe("the Addon Compartment (TOC functions)", function()
	it("says the window is coming when it is clicked", function()
		AzerothThreatwarden_OnAddonCompartmentClick("AzerothThreatwarden", "LeftButton")
		contains(Mock.PlainOutput(), "This part is coming soon.")
	end)

	it("shows a tooltip on enter and hides it on leave", function()
		AzerothThreatwarden_OnAddonCompartmentEnter("AzerothThreatwarden", CreateFrame("Button"))
		truthy(GameTooltip:IsShown())
		deepEq(Mock.TooltipLines(),
			{ "Azeroth Threatwarden", "The Threatwarden window arrives with the next development steps." })
		AzerothThreatwarden_OnAddonCompartmentLeave()
		falsy(GameTooltip:IsShown())
	end)

	it("does nothing, without an error, on a client with no GameTooltip", function()
		GameTooltip = nil
		AzerothThreatwarden_OnAddonCompartmentEnter("AzerothThreatwarden")
		AzerothThreatwarden_OnAddonCompartmentLeave()
	end)

	it("opens the window when there is one", function()
		local toggled = 0
		Mock.ns.Window = { Toggle = function() toggled = toggled + 1 end }
		AzerothThreatwarden_OnAddonCompartmentClick()
		eq(toggled, 1)
		eq(#Mock.output, 0)
	end)
end)

describe("a /reload", function()
	before_boot(function(M)
		M.saved = {
			AzerothThreatwardenDB = { schema = 1, settings = { language = "itIT" }, note = "line one\nline \"two\" è" },
			AzerothThreatwardenCharDB = { schema = 1, ui = { scale = 1.25, locked = true, pos = { -3.5, 12 } } },
		}
	end)

	it("restores both SavedVariables declared in the TOC", function()
		local before, char = AzerothThreatwardenDB, AzerothThreatwardenCharDB
		Mock.Reload()
		eq(#Mock.errors, 0)
		ne(AzerothThreatwardenDB, before, "read back from the disk, not the same table")
		deepEq(AzerothThreatwardenDB, before)
		deepEq(AzerothThreatwardenCharDB, char)
		notNil(Mock.savedText.AzerothThreatwardenDB)
		notNil(Mock.savedText.AzerothThreatwardenCharDB)
	end)

	it("keeps what was written during the session and drops everything else", function()
		AzerothThreatwardenCharDB.ui.scale = 0.8
		A().onlyInMemory = true
		local old = A()
		Mock.Reload()
		eq(AzerothThreatwardenCharDB.ui.scale, 0.8)
		ne(A(), old, "a new Lua state")
		isNil(A().onlyInMemory)
		truthy(A():IsEnabled())
		truthy(A().isForever)
	end)

	it("logs out first, then enters the world as a reload; a new login is an initial one", function()
		local loggedOut = false
		local f = CreateFrame("Frame")
		f:RegisterEvent("PLAYER_LOGOUT")
		f:SetScript("OnEvent", function() loggedOut = true end)
		Mock.Reload()
		truthy(loggedOut, "PLAYER_LOGOUT before the state is rebuilt")
		Mock.Relog(60)
		deepEq(Mock.world.entries, { { true, false }, { false, true }, { true, false } })
	end)

	it("comes back into a fight that was going on, with the client still in combat", function()
		Mock.combat.Enter()
		Mock.Reload()
		truthy(InCombatLockdown())
		truthy(UnitAffectingCombat("player"))
		Mock.combat.Leave()
		eq(A().inCombat, false)
		eq(#Mock.errors, 0)
	end)

	it("can happen twice in a row", function()
		Mock.Reload()
		Mock.Reload()
		eq(#Mock.errors, 0)
		eq(AzerothThreatwardenDB.settings.language, "itIT")
	end)

	it("a logout and a later login keep the data and move the clock", function()
		local t = GetServerTime()
		Mock.Relog(3600)
		eq(GetServerTime(), t + 3600)
		eq(AzerothThreatwardenDB.schema, 1)
		eq(#Mock.errors, 0)
	end)
end)
