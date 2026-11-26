-- Core/Diagnostics.lua and UI/DiagnosticsBox.lua (SPEC-01 §9, ARC-13; ADR 0009 rule 5): the sections of the report
-- in order, no names, errors cleaned and counted, the copy box, and /atw debug.

local function D() return Mock.ns.Diagnostics end
local function Box() return Mock.ns.DiagnosticsBox end

-- The titles of the sections of a report, in order.
local function titles(text)
	local out = {}
	for title in text:gmatch("\n== (.-) ==") do out[#out + 1] = title end
	return out
end

local SECTIONS = { "Client", "Features", "APIs", "Capabilities", "Restrictions", "Saved data", "Memory", "Bus",
	"Scheduler", "Demo", "Alerts and Coach", "Look", "Window", "Settings",
	"Target", "Threat scanner", "Recording", "Timeline and replay", "Last errors" }

describe("the report (SPEC-01 §9)", function()
	it("has the header and the sections in order", function()
		local text = D().Report()
		matches(text, "^Azeroth Threatwarden diagnostics\naddon: development copy\ndevelopment build: yes\n")
		deepEq(titles(text), SECTIONS)
	end)

	it("says what the client is, the language and the features", function()
		local text = D().Report()
		contains(text, "client: 1.60.1 (build 70170, Oct  1 2026)")
		contains(text, "interface: 16001")
		contains(text, "project id: 99, WoW Forever: yes")
		contains(text, "mode: normal")
		contains(text, "client language: enUS")
		contains(text, "language: setting auto, active enUS")
		contains(text, "missing language keys: 0")
		contains(text, "instance: none")
		contains(text, "on: alerts, coach, monitor, recording, reports")
		contains(text, "off: analytics, export, heatmap, multitarget, profiles, replay, timeline")
	end)

	it("lists what Compat found: every API, the capabilities and the restrictions", function()
		local text = D().Report()
		contains(text, "63 available, 1 missing, 0 restricted, 0 error")
		contains(text, "threat.Detailed: available")
		contains(text, "ui.ClassColor: missing")
		contains(text, "secret.HasSecretRestrictions: available = false")
		contains(text, "threatValues: unknown")
		contains(text, "combatLog: missing (CombatLogGetCurrentEventInfo missing)")
		contains(text, "combat lockdown: no")
		contains(text, "Encounter (1): available")
	end)

	it("gives the saved data, the memory, the Bus and the Scheduler", function()
		local text = D().Report()
		contains(text, "AzerothThreatwardenDB: schema found none, current 5, about 0.")
		contains(text, "AzerothThreatwardenCharDB: schema found none, current 2, about 0.")
		contains(text, "corrupt entries: 0 (at most 5 kept)")
		contains(text, "problems corrected at load: none")
		contains(text, "addon memory: 2048.2 KB")
		contains(text, "framerate: 60 fps")
		contains(text, "COMBAT_ENDED: 10 listener(s)")
		contains(text, "no tick running")
		contains(text, "no addon errors recorded this session")
	end)

	it("adds the sections of modules before the last errors, and survives one that fails", function()
		AzerothThreatwarden:AddDebugSection("Extra", function() return { "extra line" } end)
		AzerothThreatwarden:AddDebugSection("Broken", function() error("section boom") end)
		local text = D().Report()
		local t = titles(text)
		eq(t[#t], "Last errors")
		eq(t[#t - 2], "Extra")
		eq(t[#t - 1], "Broken")
		contains(text, "extra line")
		matches(text, "== Broken ==\nerror: [^\n]*section boom")
		eq(#Mock.errors, 0)
	end)

	it("is cut when it is too long", function()
		AzerothThreatwarden:AddDebugSection("Long", function()
			local lines = {}
			for i = 1, 4000 do lines[i] = "a long line of the report number " .. i end
			return lines
		end)
		local text = D().Report()
		truthy(#text <= D().MAX_CHARS + 60)
		matches(text, "%.%.%. report cut at 30000 characters$")
	end)

	it("says the version of a packaged copy, and the diagnostic mode on another client (ARC-01)", function()
		boot(function(M)
			M.Remove("WOW_PROJECT_ID")
			M.client.interface = 120000
			C_AddOns.GetAddOnMetadata = function(_, field) if field == "Version" then return "v0.1.0" end end
		end)
		local text = D().Report()
		matches(text, "\naddon: v0%.1%.0\ndevelopment build: no\n")
		contains(text, "mode: diagnostic (unsupported client)")
		contains(text, "WoW Forever: no")
	end)

	it("counts the saved data and their schema, from Config (SPEC-01 §9)", function()
		boot(function(M)
			M.saved = { AzerothThreatwardenDB = { schema = 1, settings = { language = "itIT", theme = "pink" } },
				AzerothThreatwardenCharDB = { schema = 9 } }
		end)
		local text = D().Report()
		matches(text, "AzerothThreatwardenDB: schema found 1, current 5, about %d+%.%d KB\n")
		matches(text, "AzerothThreatwardenCharDB: schema found 9, current 2, about %d+%.%d KB %- READ%-ONLY")
		contains(text, "problems corrected at load: 2")
		contains(text, "  account.settings.theme: reset (not an allowed value)")
	end)
end)

describe("names stay out of the report (ARC-13)", function()
	before_boot(function(M)
		M.player.name = "Uniquehero"
		M.player.realm = "Silvermoon"
		M.units.Add("tank", { name = "Othertank", class = "WARRIOR", role = "TANK" })
		M.group.Set({ members = { "tank" } })
	end)

	it("in every section, with a group and errors that name people", function()
		D().Record("Interface\\AddOns\\AzerothThreatwarden\\Data\\X.lua:5: Uniquehero-Silvermoon lost aggro")
		D().Record("Uniquehero hit Player-1-0000A001 on Silvermoon")
		local text = D().Report()
		for _, name in ipairs({ "Uniquehero", "Silvermoon", "Player-1-0000A001", "Othertank" }) do
			falsy(text:find(name, 1, true), name .. " is in the report")
		end
		contains(text, "AzerothThreatwarden/Data/X.lua:5: <player> lost aggro")
		contains(text, "<player> hit <guid> on <realm>")
	end)

	it("in the API table, though Probe called UnitGUID for the player", function()
		local text = D().Report()
		contains(text, "unit.GUID: available")
		falsy(text:find("Player-", 1, true))
	end)
end)

describe("the error ring", function()
	it("keeps the addon's errors from the client's handler, cleaned of the folders", function()
		local handler = geterrorhandler()
		handler("C:\\Games\\World of Warcraft\\_forever_\\Interface\\AddOns\\AzerothThreatwarden\\Core\\Init.lua:9: boom")
		handler("Interface\\AddOns\\OtherAddon\\x.lua:1: not ours")
		eq(#Mock.errors, 2, "the client's handler still sees both")
		Mock.ClearErrors()
		local errors = D().Errors()
		eq(#errors, 1)
		eq(errors[1].text, "AzerothThreatwarden/Core/Init.lua:9: boom")
	end)

	it("counts a repeated error instead of keeping it twice, and keeps the last ten", function()
		D().Record("same")
		D().Record("same")
		eq(#D().Errors(), 1)
		eq(D().Errors()[1].count, 2)
		contains(D().Report(), "x2 same")
		for i = 1, 15 do D().Record("error " .. i) end
		eq(#D().Errors(), D().MAX_ERRORS)
		eq(D().Errors()[D().MAX_ERRORS].text, "error 15")
		local lines = D().ErrorLines()
		eq(lines[1], "error 15", "latest first")
		D().ClearErrors()
		eq(#D().Errors(), 0)
	end)

	it("cleans paths, new lines and length, and never turns a secret into text", function()
		eq(D().CleanError("a\nb\r\nc"), "a | b | c")
		eq(D().CleanError("see D:\\Data\\file.txt now"), "see <path> now")
		eq(D().CleanError("/home/<user>/x.lua:1: y"), "<path>:1: y")
		eq(D().CleanError("/Users/<user>/x.lua:1: y"), "<path>:1: y")
		eq(#D().CleanError(string.rep("x", 1000)), D().MAX_LENGTH)
		eq(D().CleanError(Mock.Secret("string")), "<secret value>")
		eq(D().CleanError(nil), "")
	end)

	it("wraps the client's handler once", function()
		falsy(D().Install())
	end)
end)

describe("the copy box (UI/DiagnosticsBox.lua)", function()
	it("opens with the report selected and its size", function()
		local text = D().Show()
		truthy(Box():IsShown())
		eq(Box():GetText(), text)
		local f = Box():Frame()
		eq(f.edit:GetText(), text)
		truthy(f.edit:HasFocus())
		truthy(f.edit._highlighted)
		matches(f.size:GetText(), "^%d+ lines, %d+ characters$")
		eq(f.title:GetText(), "Diagnostic report")
		contains(UISpecialFrames, "AzerothThreatwardenDiagnosticsBox")
		eq(#Mock.output, 0, "nothing in the chat")
	end)

	it("is read-only and closes with its button or Esc", function()
		Box():Open("report text")
		local f = Box():Frame()
		Mock.TypeInto(f.edit, "typed")
		eq(f.edit:GetText(), "report text")
		f.close:Click()
		falsy(Box():IsShown())
		Box():Open()
		matches(Box():GetText(), "^Azeroth Threatwarden diagnostics")
		Mock.RunScript(f.edit, "OnEscapePressed")
		falsy(Box():IsShown())
	end)

	it("speaks Italian on an Italian client, while the report stays English (ADR 0009)", function()
		boot(function(M) M.player.locale = "itIT" end)
		D().Show()
		local f = Box():Frame()
		eq(f.title:GetText(), "Rapporto diagnostico")
		eq(f.close:GetLabel(), "Chiudi")
		matches(f.size:GetText(), "^%d+ righe, %d+ caratteri$")
		matches(Box():GetText(), "^Azeroth Threatwarden diagnostics")
	end)

	it("falls back to the chat when the box cannot open", function()
		Mock.ns.DiagnosticsBox = nil
		D().Show()
		contains(Mock.PlainOutput(), "Azeroth Threatwarden diagnostics")
		contains(Mock.PlainOutput(), "== Last errors ==")
	end)
end)

describe("/atw debug", function()
	it("opens the report", function()
		truthy(Mock.Slash("/atw debug"))
		truthy(Box():IsShown())
		matches(Box():GetText(), "^Azeroth Threatwarden diagnostics")
		eq(#Mock.errors, 0)
	end)

	it("takes the word in any case and with spaces", function()
		Mock.Slash("/atw   DEBUG  ")
		truthy(Box():IsShown())
	end)
end)
