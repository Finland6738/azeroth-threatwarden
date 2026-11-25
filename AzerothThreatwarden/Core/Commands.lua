-- Commands: /threatwarden and /atw (SPEC-03 §5, SPEC-09 Q1), through AceConsole. Lua 5.1, no game API.
-- Adapted from Azeroth Accord (the slash commands of Core/Init.lua), same owner, GPL-3.0 (ADR 0012).
--
-- Answers go only to the player's own chat window (AceConsole's Print), never to a channel (ADR 0001), in the active
-- language; the report of `debug` is in English (ADR 0009). A command of a part switched off in Core/Features.lua says
-- when it arrives and does nothing; `help` lists the commands that work.
local ADDON_NAME, ns = ...
ns = ns or {}
ns.modules = ns.modules or {}

local Commands = {}
ns.Commands, ns.modules.Commands = Commands, Commands

local L = ns.L
local ipairs, type = ipairs, type

Commands.SLASH = { "threatwarden", "atw" }

local function say(text)
	if ns.addon then ns.addon:Print(text) end
end

-- The answer of a command that changes `char.ui`: `done` when it was saved, else why nothing changed.
local function report(ok, done)
	say(L[ok and done or "CMD_READ_ONLY"])
end

-- In the order of `help`. `help`: the key of its line. `feature` and `version`: a part of a later milestone.
Commands.LIST = {
	{ name = "show", help = "HELP_SHOW", run = function() ns.Window:Open() end },
	{ name = "hide", help = "HELP_HIDE", run = function() ns.Window:Close() end },
	{ name = "lock", help = "HELP_LOCK", run = function() report(ns.Window:SetLocked(true), "CMD_LOCKED") end },
	{ name = "unlock", help = "HELP_UNLOCK", run = function() report(ns.Window:SetLocked(false), "CMD_UNLOCKED") end },
	{ name = "reset", help = "HELP_RESET", run = function() report(ns.Window:Reset(), "CMD_RESET") end },
	{ name = "settings", help = "HELP_SETTINGS", run = function() ns.Window:OpenPage("settings") end },
	{ name = "about", help = "HELP_ABOUT", run = function() ns.Window:OpenPage("about") end },
	{ name = "debug", help = "HELP_DEBUG", run = function() ns.Diagnostics.Show() end },
	{ name = "help", help = "HELP_HELP", run = function() Commands.Help() end },
	{ name = "demo", help = "HELP_DEMO", feature = "monitor", version = "v0.2.0",
		run = function(rest) ns.Demo.Command(rest) end },
	{ name = "mute", feature = "alerts", version = "v0.3.0" },      -- M3
	{ name = "reports", feature = "reports", version = "v0.4.0" },  -- M4
}

local function available(c)
	return c.run ~= nil and (c.feature == nil or (ns.Features ~= nil and ns.Features.On(c.feature)))
end

function Commands.Help()
	say(L["HELP_HEADER"])
	say("/atw - " .. L["HELP_TOGGLE"])
	for _, c in ipairs(Commands.LIST) do
		if available(c) then say("/atw " .. c.name .. " - " .. L[c.help]) end
	end
end

-- `input`: what follows /atw. The first word counts, in any case; no word shows or hides the window. The second word
-- is passed to the command (`demo stop`).
function Commands.Run(input)
	local word, rest = "", ""
	if type(input) == "string" then word, rest = input:match("^%s*(%S*)%s*(%S*)") end
	local name = word:lower()
	if name == "" then
		ns.Window:Toggle()
		return
	end
	for _, c in ipairs(Commands.LIST) do
		if c.name == name then
			if available(c) then return c.run(rest) end
			return say(L["CMD_LATER"]:format(c.version))
		end
	end
	say(L["CMD_UNKNOWN"]:format((word:gsub("|", "||"))))   -- no colour or link codes from what was typed
end

-- ADDON_LOADED (Core/Init.lua).
function Commands.Register()
	if not ns.addon then return end
	for _, slash in ipairs(Commands.SLASH) do ns.addon:RegisterChatCommand(slash, Commands.Run) end
end

if ns.addon then ns.addon.Commands = Commands end
