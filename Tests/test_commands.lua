-- Core/Commands.lua (SPEC-03 §5): /threatwarden and /atw, every command in English and in Italian, wrong words, parts
-- switched off, saved data that cannot be written. The answers go to the player's own chat only (ADR 0001).

local function W() return AzerothThreatwarden.Window end
local function ui() return AzerothThreatwardenCharDB.ui end

local function run(line)
	Mock.ClearOutput()
	truthy(Mock.Slash(line), line .. " is not a command")
	eq(#Mock.errors, 0, line)
	return Mock.PlainOutput()
end

local TEXT = {
	enUS = {
		locked = "Window locked.", unlocked = "Window unlocked.", reset = "Window position, size and scale reset.",
		unknown = "Unknown command: dance. Type /atw help.", later = "This arrives in %s.",
		header = "Commands (/atw or /threatwarden):", toggle = "/atw - show or hide the window",
		help = "/atw help - list the commands",
		settings = "Reset settings", about = "Credits",
		readOnly = "Nothing was changed: your saved data is read-only (see /atw debug).",
	},
	itIT = {
		locked = "Finestra bloccata.", unlocked = "Finestra sbloccata.",
		reset = "Posizione, dimensioni e scala della finestra ripristinate.",
		unknown = "Comando sconosciuto: dance. Scrivi /atw help.", later = "Arriva nella %s.",
		header = "Comandi (/atw o /threatwarden):", toggle = "/atw - mostra o nasconde la finestra",
		help = "/atw help - elenca i comandi",
		settings = "Ripristina impostazioni", about = "Crediti",
		readOnly = "Nulla è cambiato: i dati salvati sono in sola lettura (vedi /atw debug).",
	},
}

local NAMES = { "show", "hide", "lock", "unlock", "reset", "settings", "about", "debug", "help" }

for _, code in ipairs({ "enUS", "itIT" }) do
	local T = TEXT[code]
	describe("the commands in " .. code, function()
		before_boot(function(M) M.player.locale = code end)

		it("show or hide the window with no word", function()
			truthy(W():IsShown())
			eq(run("/atw"), "")
			falsy(W():IsShown())
			run("/atw   ")
			truthy(W():IsShown())
		end)

		it("show and hide it", function()
			run("/atw hide")
			falsy(W():IsShown())
			eq(ui().shown, false)
			run("/atw hide")
			falsy(W():IsShown())
			run("/atw show")
			truthy(W():IsShown())
			eq(ui().shown, true)
			run("/atw show")
			truthy(W():IsShown())
		end)

		it("lock and unlock it, and say so", function()
			contains(run("/atw lock"), T.locked)
			eq(ui().locked, true)
			contains(run("/atw unlock"), T.unlocked)
			eq(ui().locked, false)
		end)

		it("reset it and show it", function()
			AzerothThreatwarden.Config:Set("char.ui.scale", 1.5)
			W():Close()
			contains(run("/atw reset"), T.reset)
			eq(ui().scale, 1)
			truthy(W():IsShown())
		end)

		it("open the settings and the Info page", function()
			W():Close()
			run("/atw settings")
			truthy(W():IsShown())
			eq(W():Tab(), "settings")
			local view = W():Frame().pages.settings.view
			eq(view.pageId, "settings")
			eq(view.settings.reset:GetLabel(), T.settings)
			run("/atw about")
			eq(ui().lastPage, "about")
			eq(view.pageId, "about")
			eq(view.info.cards[2].items[1].region:GetText(), T.about)
		end)

		it("open the diagnostic report, in English", function()
			run("/atw debug")
			truthy(AzerothThreatwarden.DiagnosticsBox:IsShown())
			matches(AzerothThreatwarden.DiagnosticsBox:GetText(), "^Azeroth Threatwarden diagnostics")
		end)

		it("list the commands that work, one line each", function()
			local out = run("/atw help")
			contains(out, T.header)
			contains(out, T.toggle)
			contains(out, T.help)
			for _, name in ipairs(NAMES) do contains(out, "/atw " .. name .. " - ") end
			contains(out, "/atw demo - ")
			contains(out, "/atw mute - ")
			contains(out, "/atw reports - ")
			eq(#Mock.output, #NAMES + 5)
		end)

		it("say what an unknown word is", function()
			contains(run("/atw dance now"), T.unknown)
			truthy(W():IsShown(), "nothing else happens")
		end)

		it("say when a command of a part switched off arrives, and do nothing", function()
			boot(function(M) M.player.locale = code; M.features = { reports = false } end)
			contains(run("/atw reports"), T.later:format("v0.4.0"))
			eq(W():Tab(), "monitor")
		end)

		it("change nothing on read-only data, and say why", function()
			boot(function(M)
				M.player.locale = code
				M.saved = { AzerothThreatwardenCharDB = { schema = 99, ui = { locked = false } } }
			end)
			contains(run("/atw lock"), T.readOnly)
			contains(run("/atw unlock"), T.readOnly)
			contains(run("/atw reset"), T.readOnly)
			eq(ui().locked, false)
		end)
	end)
end

local MUTE = {
	enUS = { fight = "Alerts muted until the end of this fight.", next = "Alerts muted until the end of the next fight.",
		back = "Alerts back on.", disabled = "Alerts are off in Settings.", later = "This arrives in v0.3.0.",
		help = "/atw mute - " },
	itIT = { fight = "Avvisi silenziati fino alla fine di questo combattimento.",
		next = "Avvisi silenziati fino alla fine del prossimo combattimento.", back = "Avvisi di nuovo attivi.",
		disabled = "Gli avvisi sono spenti nelle Impostazioni.", later = "Arriva nella v0.3.0.", help = "/atw mute - " },
}

for _, code in ipairs({ "enUS", "itIT" }) do
	local T = MUTE[code]
	describe("/atw mute in " .. code, function()
		before_boot(function(M)
			M.player.locale = code
			M.features = { monitor = true, alerts = true }
		end)

		it("is listed by help", function()
			contains(run("/atw help"), T.help)
		end)

		it("mutes until the end of the next fight outside combat, and again unmutes", function()
			contains(run("/atw mute"), T.next)
			truthy(Mock.ns.Alerts.IsMuted())
			contains(run("/atw MUTE now"), T.back)
			falsy(Mock.ns.Alerts.IsMuted())
		end)

		it("keeps the mute through the next fight and ends it with it", function()
			run("/atw mute")
			Mock.combat.Enter()
			truthy(Mock.ns.Alerts.IsMuted())
			Mock.combat.Leave()
			falsy(Mock.ns.Alerts.IsMuted())
		end)

		it("mutes until the end of this fight in combat, and the fight ends it", function()
			Mock.combat.Enter()
			contains(run("/atw mute"), T.fight)
			Mock.combat.Leave()
			falsy(Mock.ns.Alerts.IsMuted())
		end)

		it("does not survive a reload", function()
			run("/atw mute")
			Mock.Reload()
			falsy(Mock.ns.Alerts.IsMuted())
		end)

		it("says that the alerts are off in Settings", function()
			AzerothThreatwarden.Config:Set("account.settings.alerts.enabled", false)
			contains(run("/atw mute"), T.disabled)
			falsy(Mock.ns.Alerts.IsMuted())
		end)

		it("says when it arrives with the switch off", function()
			boot(function(M) M.features = { monitor = true, alerts = false } end)
			contains(run("/atw mute"), T.later)
			falsy(Mock.ns.Alerts.IsMuted())
			falsy(run("/atw help"):find(T.help, 1, true))
		end)
	end)
end

describe("the way a command is typed", function()
	it("answers to /threatwarden as to /atw", function()
		run("/threatwarden hide")
		falsy(W():IsShown())
		run("/threatwarden")
		truthy(W():IsShown())
		run("/ThreatWarden debug")
		truthy(AzerothThreatwarden.DiagnosticsBox:IsShown())
	end)

	it("takes the first word in any case, with spaces, and ignores the rest", function()
		run("/atw   HIDE  please ")
		falsy(W():IsShown())
	end)

	it("does not print the colour or link codes typed in an unknown word", function()
		run("/atw |cffff0000x|r")
		contains(Mock.output[1], "||cffff0000x||r")
	end)

	it("takes an input that is no string as no word", function()
		AzerothThreatwarden.Commands.Run(nil)
		falsy(W():IsShown())
	end)

	it("never posts to a channel: only the player's own chat window", function()
		local sent = 0
		SendChatMessage = function() sent = sent + 1 end
		run("/atw help")
		run("/atw lock")
		eq(sent, 0)
		truthy(#Mock.output > 0)
	end)

	it("says that the demo arrives in v0.2.0 with the monitor switched off", function()
		boot(function(M) M.features = { monitor = false } end)
		falsy(run("/atw help"):find("/atw demo", 1, true))
		contains(run("/atw demo"), "This arrives in v0.2.0.")
		falsy(AzerothThreatwarden.Demo.IsActive())
	end)

	it("lists and runs the demo", function()
		contains(run("/atw help"), "/atw demo - ")
		contains(run("/atw demo"), "Demo started")
		truthy(AzerothThreatwarden.Demo.IsActive())
		contains(run("/atw DEMO   Stop now"), "Demo stopped.")
		falsy(AzerothThreatwarden.Demo.IsActive())
		contains(run("/atw demo stop"), "The demo is not running.")
		contains(run("/atw demo fast"), "Type /atw demo to start the demo")
		falsy(AzerothThreatwarden.Demo.IsActive())
	end)
end)

describe("/atw reports (SPEC-05 §3.6)", function()
	before_boot(function(M) M.features = { monitor = true, recording = true, reports = true } end)

	it("opens the window on the Reports tab, from closed too, and help lists it", function()
		W():Close()
		eq(run("/atw reports"), "")
		truthy(W():IsShown())
		eq(W():Tab(), "reports")
		notNil(W():Frame().pages.reports.view)
		contains(run("/atw help"), "/atw reports - open the recorded fights and their reports")
	end)

	it("works on read-only data", function()
		boot(function(M)
			M.features = { reports = true }
			M.saved = { AzerothThreatwardenCharDB = { schema = 99, ui = { locked = false } } }
		end)
		run("/atw reports")
		eq(W():Tab(), "reports")
	end)
end)

describe("/atw reports in Italian", function()
	before_boot(function(M) M.features = { reports = true, recording = true } M.player.locale = "itIT" end)
	it("says it in the help", function()
		contains(run("/atw help"), "/atw reports - apre i combattimenti registrati e i loro report")
	end)
end)

-- The window itself and the choice of the recording are in test_replay_window.lua.
describe("/atw replay (SPEC-05 §5.5)", function()
	local requested
	local function listen()
		requested = {}
		Mock.ns.Bus.On("REPLAY_REQUESTED", function(id, t) requested[#requested + 1] = { id = id, t = t } end)
	end

	local function add(id, started)
		local Session = Mock.ns.Session
		local s = Session.New{ id = id, started = started, group = "party", rec = { hz = 2, warning = 82, danger = 91 } }
		Session.Join(s)
		s.state, s.ended, s.dur, s.fight = "complete", "combat", 10, 10
		truthy(Mock.ns.Storage.Add(s))
	end

	before_boot(function(M)
		M.features = { monitor = true, recording = true, reports = true, timeline = true, replay = true }
	end)

	it("asks for the newest recording, or the n-th of the list, with no time", function()
		listen()
		add("old", 100)
		add("new", 200)
		run("/atw replay")
		run("/atw replay 2")
		run("/atw REPLAY 1")
		deepEq(requested, { { id = "new" }, { id = "old" }, { id = "new" } })
	end)

	it("says what is wrong, in the player's own chat only, and asks for nothing", function()
		listen()
		contains(run("/atw replay"), "No recordings to replay yet.")
		add("only", 100)
		contains(run("/atw replay 2"), "No recording number 2: the list has 1.")
		run("/atw replay |cffff0000")
		contains(Mock.output[1], "No recording number ||cffff0000: the list has 1.")
		deepEq(requested, {})
	end)

	it("is listed by help, and says when it arrives with a switch off", function()
		contains(run("/atw help"), "/atw replay - ")
		boot(function(M) M.features = { reports = true, timeline = true, replay = false } end)
		contains(run("/atw replay"), "This arrives in v0.5.0.")
		boot(function(M) M.features = { reports = true, timeline = false, replay = true } end)
		contains(run("/atw replay 1"), "This arrives in v0.5.0.")
		falsy(run("/atw help"):find("/atw replay", 1, true))
	end)
end)

