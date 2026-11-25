-- Core/Demo.lua and Data/Demo.lua (SPEC-03 §5.2): the invented fight goes through the real model, states and list,
-- reads nothing from the game, writes no saved data, stops at a real combat, at /atw demo stop and with the window.

before_boot(function(M) M.features = { monitor = true } end)

local function D() return Mock.ns.Demo end
local function A() return AzerothThreatwarden end
local function W() return Mock.ns.Window end
local function V() return Mock.ns.ThreatList.view end
local function TM() return Mock.ns.ThreatModel end
local function ST() return Mock.ns.ThreatState end
local function Config() return Mock.ns.Config end

local function run(command)
	local from = #Mock.output
	A().Commands.Run((command:gsub("^/atw%s*", "")))
	local out = {}
	for i = from + 1, #Mock.output do out[#out + 1] = Mock.output[i] end
	return table.concat(out, "\n")
end

local function rowOf(token) return TM().RowOf(token) end

local function widget(token)
	for _, w in ipairs(V().widgets) do
		if w:IsShown() and w.data and w.data.record.unitToken == token then return w end
	end
end

-- Plays `seconds` of the demo in steps of the tick.
local function play(seconds, each)
	local steps = math.floor(seconds * 5 + 0.5)
	for _ = 1, steps do
		Mock.Advance(0.2)
		if each then each() end
	end
end

-- Counts every read of the game the monitor can make (all go through Core/Compat.lua) and every write of a setting.
local function watch()
	local calls = { game = {}, writes = {} }
	local Compat = Mock.ns.Compat
	for _, name in ipairs({ "Unit", "Group", "Threat" }) do
		for fn, real in pairs(Compat[name]) do
			if type(real) == "function" and fn ~= "NewRecord" then
				Compat[name][fn] = function(...)
					calls.game[#calls.game + 1] = name .. "." .. fn
					return real(...)
				end
			end
		end
	end
	local set, thresholds = Config().Set, Config().SetThresholds
	Config().Set = function(self, path, ...) calls.writes[#calls.writes + 1] = path; return set(self, path, ...) end
	Config().SetThresholds = function(self, ...) calls.writes[#calls.writes + 1] = "thresholds"; return thresholds(self, ...) end
	return calls
end

local function saved()
	return Config().Copy(AzerothThreatwardenDB), Config().Copy(AzerothThreatwardenCharDB)
end

describe("starting the demo", function()
	it("shows an invented fight in the list, said to be a demo in the pill, the footer and the tooltips", function()
		contains(run("/atw demo"), "Demo started")
		truthy(D().IsActive())
		eq(V().situation, "list")
		eq(V().mob:GetText(), "Demo golem")
		eq(V().shownRows, 4)
		eq(W().ModuleState(), "demo")
		eq(W():Frame().titles.compact.chip.label:GetText(), "Demo")
		eq(V().quality:GetText(), "DEMO · invented fight, not the game")
		Mock.RunScript(widget("party1"), "OnEnter")
		contains(table.concat(Mock.ns.Widgets.Tooltip.Lines(), "\n"), "Demo: invented values")
		Mock.RunScript(V().footer, "OnEnter")
		contains(table.concat(Mock.ns.Widgets.Tooltip.Lines(), "\n"), "Demo: invented values")
		eq(widget("player").name:GetText(), "You")
		eq(widget("party1").name:GetText(), "Brannok")
		eq(#Mock.errors, 0)
	end)

	it("goes through the same model and states as a real fight", function()
		local changes, scans = {}, 0
		Mock.ns.Bus.On("STATE_CHANGED", function(unit, _, _, new) changes[#changes + 1] = unit .. "=" .. tostring(new) end)
		Mock.ns.Bus.On("THREAT_UPDATED", function() scans = scans + 1 end)
		D().Start()
		local seen = {}
		play(39, function()
			for _, token in ipairs({ "player", "party1", "party2", "party3" }) do
				local row = rowOf(token)
				seen[token .. " " .. row.state .. " " .. tostring(row.stateReason)] = true
				eq(row.record.mode, "values")
				falsy(row.stale)
			end
		end)
		truthy(scans >= 190, "one update per tick: " .. scans)
		truthy(seen["player SAFE nil"])
		truthy(seen["player WARNING predicted"], "the trend of ThreatCalc predicts")
		truthy(seen["player WARNING nil"])
		truthy(seen["player DANGER nil"])
		truthy(seen["party1 SAFE nil"], "the tank with a margin")
		truthy(seen["party1 DANGER lost-aggro"], "the tank loses the mob")
		truthy(seen["party3 DANGER aggro"])
		truthy(#changes > 6)
		eq(#Mock.errors, 0)
	end)

	it("starts the fight again after a turn, as a new mob", function()
		D().Start()
		local first = TM().mobKey
		play(Mock.ns.DemoData.LENGTH + 1)
		ne(TM().mobKey, first)
		eq(rowOf("player").state, "SAFE")
		truthy(D().IsActive())
	end)

	it("obeys the thresholds, the order, the pin and the rate while it plays", function()
		D().Start()
		truthy(Config():SetThresholds(50, 60))
		play(8)
		eq(rowOf("player").state, "WARNING", "50 % with warning 50")
		truthy(Config():Set("account.settings.monitor.pinSelf", true))
		eq(V().widgets[1].data.record.unitToken, "player")
		eq(Mock.ns.Scheduler.Rate("demo"), 5)
		truthy(Config():Set("account.settings.monitor.rate", 10))
		eq(Mock.ns.Scheduler.Rate("demo"), 10)
		play(1)
		near(rowOf("player").record.interval, 0.1, 1e-9)
	end)

	it("is refused during combat, and says so", function()
		Mock.combat.Enter()
		contains(run("/atw demo"), "cannot start during combat")
		falsy(D().IsActive())
		deepEq({ D().Start() }, { false, "combat" })
		Mock.combat.Leave()
		truthy(D().Start())
		deepEq({ D().Start() }, { false, "active" })
	end)

	it("is refused with the monitor switched off, and on another client", function()
		boot(function(M) M.features = { monitor = false } end)
		deepEq({ D().Start() }, { false, "off" })
		contains(run("/atw demo"), "This arrives in v0.2.0.")
		boot(function(M) M.features = { monitor = true }; M.client.project = 1 end)
		A().isForever = false
		deepEq({ D().Start() }, { false, "unsupported" })
		isNil(Mock.ns.Scheduler.Rate("demo"))
	end)

	it("speaks Italian on an Italian client", function()
		boot(function(M) M.features = { monitor = true }; M.player.locale = "itIT" end)
		contains(run("/atw demo"), "Demo avviata")
		eq(V().mob:GetText(), "Golem della demo")
		eq(V().quality:GetText(), "DEMO · scontro inventato, non il gioco")
		contains(run("/atw demo stop"), "Demo terminata.")
	end)
end)

describe("what the demo does not do", function()
	it("reads nothing from the game", function()
		local calls = watch()
		D().Start()
		play(45)
		Mock.RunScript(widget("party1"), "OnEnter")
		D().Stop()
		-- Stop puts the real sources back without asking them to read
		deepEq(calls.game, {})
		eq(#Mock.threat.calls, 0)
	end)

	it("writes no saved data, from the start to the end", function()
		local account, char = saved()
		local calls = watch()
		D().Start()
		play(45)
		D().Stop()
		deepEq(calls.writes, {})
		deepEq(AzerothThreatwardenDB, account)
		deepEq(AzerothThreatwardenCharDB, char)
	end)

	it("opens a closed window on the Monitor tab without saving that it did", function()
		W():SelectTab("settings")
		W():Close()
		local account, char = saved()
		D().Start()
		truthy(W():IsShown())
		eq(W():Tab(), "monitor")
		play(3)
		D().Stop()
		deepEq(AzerothThreatwardenCharDB, char)
		deepEq(AzerothThreatwardenDB, account)
		eq(AzerothThreatwardenCharDB.ui.shown, false)
		eq(AzerothThreatwardenCharDB.ui.lastTab, "settings")
	end)

	it("changes nothing on read-only data either", function()
		boot(function(M)
			M.features = { monitor = true }
			M.saved = { AzerothThreatwardenDB = { schema = 99 }, AzerothThreatwardenCharDB = { schema = 99 } }
		end)
		D().Start()
		play(3)
		D().Stop()
		deepEq(AzerothThreatwardenDB, { schema = 99 })
		deepEq(AzerothThreatwardenCharDB, { schema = 99 })
		eq(#Mock.errors, 0)
	end)
end)

describe("ending the demo", function()
	it("puts the real sources back, stops its tick and redraws", function()
		local tracker, scanner = Mock.ns.TargetTracker, Mock.ns.ThreatScanner
		local seen = {}
		Mock.ns.Bus.On("DEMO_CHANGED", function(active) seen[#seen + 1] = active end)
		D().Start()
		ne(Mock.ns.TargetTracker, tracker)
		ne(Mock.ns.ThreatScanner, scanner)
		contains(run("/atw demo"), "Demo stopped.")
		eq(Mock.ns.TargetTracker, tracker)
		eq(Mock.ns.ThreatScanner, scanner)
		isNil(Mock.ns.Scheduler.Rate("demo"))
		eq(V().situation, "none")
		eq(V().shownRows, 0)
		eq(W().ModuleState(), "idle")
		eq(ST().mode, "none")
		deepEq(seen, { true, false })
		play(2)
		eq(V().shownRows, 0)
		eq(#Mock.errors, 0)
	end)

	it("brings back the last rows of a fight that had ended", function()
		local pull = Fight.new{ party = { { key = "tank", role = "TANK" } },
			mobs = { { key = "boss", tokens = { "target" } } } }
		truthy(Config():Set("account.settings.monitor.show", "manual"))
		pull:at(0):start():threat("boss", "tank", 1000):threat("boss", "player", 300)
		pull:to(1)
		pull:stop()
		eq(V().situation, "ended")
		local rows = V().shownRows
		D().Start()
		eq(V().situation, "list")
		D().Stop()
		eq(V().situation, "ended")
		eq(V().shownRows, rows)
	end)

	it("stops at the start of a real combat, before the monitor reads it", function()
		local pull = Fight.new{ party = { { key = "tank", role = "TANK", name = "Bram" } },
			mobs = { { key = "boss", tokens = { "target" }, name = "Gorrak" } } }
		D().Start()
		play(2)
		local from = #Mock.output
		pull:at(0):start():threat("boss", "tank", 1000):threat("boss", "player", 300)
		pull:to(1)
		falsy(D().IsActive())
		contains(table.concat(Mock.output, "\n", from + 1), "Demo stopped: combat started.")
		truthy(Mock.ns.ThreatScanner.active, "the real scanner reads the fight")
		isNil(Mock.ns.Scheduler.Rate("demo"))
		eq(V().mob:GetText(), "Gorrak")
		eq(rowOf("party1").record.unitName, "Bram")
		eq(W().ModuleState(), "live")
		eq(#Mock.errors, 0)
	end)

	it("stops when the window is closed", function()
		D().Start()
		W():Close()
		falsy(D().IsActive())
		isNil(Mock.ns.Scheduler.Rate("demo"))
	end)

	it("goes on while the player looks at Settings", function()
		D().Start()
		W():SelectTab("settings")
		play(1)
		truthy(D().IsActive())
		W():SelectTab("monitor")
		eq(V().situation, "list")
	end)

	it("does not survive a /reload", function()
		D().Start()
		Mock.Reload()
		falsy(D().IsActive())
		eq(V().situation, "none")
		eq(#Mock.errors, 0)
	end)

	it("answers when there is nothing to stop", function()
		contains(run("/atw demo stop"), "The demo is not running.")
		contains(run("/atw demo off"), "The demo is not running.")
		falsy(D().Stop())
	end)
end)

describe("the invented fight (Data/Demo.lua)", function()
	local function records()
		local out = {}
		for i = 1, #Mock.ns.DemoData.UNITS do out[i] = {} end
		return out
	end

	it("has the player, a tank, a healer and a damage dealer, and no player name", function()
		local units = Mock.ns.DemoData.UNITS
		eq(units[1].token, "player")
		isNil(units[1].name)
		local roles = {}
		for _, u in ipairs(units) do roles[u.role] = true end
		truthy(roles.TANK and roles.HEALER and roles.DAMAGER)
	end)

	it("gives the same numbers for the same second, one holder at 100 and the others in range", function()
		local DD = Mock.ns.DemoData
		local a, b = records(), records()
		for tenth = 0, DD.LENGTH * 10 do
			local t = tenth / 10
			local holder = DD.Fill(a, t)
			DD.Fill(b, t)
			eq(holder.scaledPercent, 100)
			local holders = 0
			for i, rec in ipairs(a) do
				eq(rec.scaledPercent, b[i].scaledPercent)
				truthy(rec.scaledPercent >= 0 and rec.scaledPercent <= 100, "at " .. t)
				if rec.isTanking then holders = holders + 1 end
				truthy(rec.rawThreat > 0)
			end
			eq(holders, 1)
		end
	end)

	it("starts and ends alike, so a new turn does not jump", function()
		local DD = Mock.ns.DemoData
		for _, u in ipairs(DD.UNITS) do eq(DD.Percent(u.token, 0), DD.Percent(u.token, DD.LENGTH), u.token) end
		eq(DD.Holder(0), DD.Holder(DD.LENGTH))
	end)
end)
