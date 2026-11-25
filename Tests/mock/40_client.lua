-- Adapted from Azeroth Accord (Tests/mock/60_client.lua), same owner, GPL-3.0 (ADR 0012).
-- Mock client, part 6: the player, the client build and the addon manager.
--
-- Imitates: GetBuildInfo, GetLocale, WOW_PROJECT_ID / WOW_PROJECT_CAMELOT, IsLoggedIn, GetRealmName,
-- C_AddOns.GetAddOnMetadata, UpdateAddOnMemoryUsage, GetAddOnMemoryUsage, GetFramerate.
-- Dump (../WoW-Addons/docs/api.json; meta: version 1.60.1, build 70170, interface 16001): systems Build, Locale,
-- PlayerScript, ConnectionScript, AddOns, PerformanceScript, Client. WOW_PROJECT_ID and WOW_PROJECT_CAMELOT are not in
-- the dump and their value is P1 of the probe: the addon uses the constants, never a number.
--
-- Mock.player (kept across Mock.Reload): name, realm, guid, class ("WARRIOR"), level, role, ranged, locale, loggedIn,
-- addonMemory (KB; false: the client has no figure). Mock.player is also the unit "player" (50_units.lua).
-- A setup imitating another client assigns the globals: WOW_PROJECT_ID = 1, or WOW_PROJECT_ID = nil and
-- Mock.client.interface = 120000.
local Mock, H = ...
local W = Mock.world

W.player = W.player or {
	key = "player", name = "Testchar", realm = "Test Realm", guid = "Player-1-0000A001", isPlayer = true,
	class = "WARRIOR", level = 60, role = "NONE", locale = "enUS", loggedIn = false,
}
local player = W.player
Mock.player = player

W.client = W.client or { version = "1.60.1", build = "70170", date = "Oct  1 2026", interface = 16001 }
Mock.client = W.client

WOW_PROJECT_MAINLINE, WOW_PROJECT_CLASSIC = 1, 2
WOW_PROJECT_CAMELOT = 99
WOW_PROJECT_ID = WOW_PROJECT_CAMELOT

function GetLocale() return player.locale end
function GetRealmName() return player.realm end
-- buildVersion, buildNumber, buildDate, interfaceVersion, localizedVersion, buildInfo
function GetBuildInfo()
	local c = Mock.client
	return c.version, c.build, c.date, c.interface, c.version, "Release"
end
function IsLoggedIn() return player.loggedIn end
function GetFramerate() return 60 end

-- The memory the game attributes to an addon (KB): 2048.25 by default.
function UpdateAddOnMemoryUsage() end
function GetAddOnMemoryUsage()
	if player.addonMemory == false then return nil end
	return player.addonMemory or 2048.25
end

-- Every PLAYER_ENTERING_WORLD of this world, as { isInitialLogin, isReloadingUi }, for the harness's own tests.
W.entries = W.entries or {}
local watcher = CreateFrame("Frame")
watcher:RegisterEvent("PLAYER_ENTERING_WORLD")
watcher:SetScript("OnEvent", function(_, _, initial, reload)
	W.entries[#W.entries + 1] = { initial, reload }
end)

-- AddOn metadata comes from the TOC the harness parsed; any other addon has none.
C_AddOns = {}
function C_AddOns.GetAddOnMetadata(name, field)
	if name == H.addonName then return H.tocFields[field] end
end
