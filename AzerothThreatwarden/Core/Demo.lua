-- Demo: demo mode, an invented fight through the same model, states and list as a real one (SPEC-03 §5.2, M2.6).
-- Lua 5.1, no game API. `/atw demo` starts it, `/atw demo stop` ends it.
-- Modelled on Azeroth Accord (Core/Demo.lua), same owner, GPL-3.0 (ADR 0012). Changed: no overlay of the game's API and
-- no copy of the saved data; the demo stands in for the two modules that read the game, TargetTracker and
-- ThreatScanner, and writes nothing.
--
--   * Reads nothing: while it runs, ns.TargetTracker and ns.ThreatScanner are two invented sources (Data/Demo.lua);
--     Data/ThreatModel.lua, Data/ThreatState.lua and UI/ThreatList.lua read them as they read the real ones. The real
--     modules stay as they were and are put back at the end.
--   * Saves nothing: the demo writes no setting; it shows the window without recording it (`char.ui` stays). What the
--     player does meanwhile (a setting, the list's order, moving the window) is saved as always.
--   * Stops by itself: at the start of a real combat, before any module reacts to it (this file loads before the Data
--     modules, so its listener runs first), and when the window is closed (nothing runs while nobody looks, ARC-05).
--     It never survives a /reload or a logout.
--   * Shows itself: the module state of the title bar says *Demo*, the list's footer and tooltips say that the fight is
--     invented.
-- Alerts (M3) and recording (M4) must ignore the events of a demo: Demo.IsActive().
--
-- One tick (Scheduler "demo") at the configured rate (account.settings.monitor.rate), so the setting can be tried.
-- Bus: THREAT_SCANNED(mobKey) at every step, DEMO_CHANGED(active) after the mode changed.
local ADDON_NAME, ns = ...
ns = ns or {}
ns.modules = ns.modules or {}

local Demo = {}
ns.Demo, ns.modules.Demo = Demo, Demo

local ipairs, type, floor = ipairs, type, math.floor

Demo.TICK = "demo"
local RATE_PATH = "account.settings.monitor.rate"

local active = false
local real = {}           -- the modules put aside: real.tracker, real.scanner
local startedAt = 0       -- of the current turn of the fight
local turns = 0           -- every turn is a new mob, so samples and states start again
Demo.starts = 0

---------------------------------------------------------------------------------------------------------------------
-- The two invented sources: only what the model, the states, the list and the window read
---------------------------------------------------------------------------------------------------------------------
local Tracker = { status = "active", enabled = true }
function Tracker.MobName() return ns.L.DEMO_MOB end
function Tracker.MobClassification() return "elite" end
function Tracker.HolderName() return nil end

local Scanner = { records = {}, count = 0, inCombat = true, mode = "values", scans = 0, lastScanAt = 0 }
local rate = 5
function Scanner.Rate() return rate end
function Scanner.Quality() return 100 end

local function readRate()
	local value = ns.Config and ns.Config:Get(RATE_PATH)
	rate = type(value) == "number" and floor(value) or ns.Config.MONITOR_DEFAULTS.rate
end

local function buildRecords()
	local units = ns.DemoData.UNITS
	for i, unit in ipairs(units) do
		local rec = ns.Compat.Threat.NewRecord()
		rec.unitToken, rec.unitKey = unit.token, "demo:" .. unit.token
		rec.unitName, rec.classFile, rec.role = unit.name, unit.classFile, unit.role
		rec.stale = false
		Scanner.records[i] = rec
	end
	Scanner.count = #units
end

local function emit(event, ...)
	if ns.Bus then ns.Bus.Emit(event, ...) end
end

local function say(key)
	if ns.addon then ns.addon:Print(ns.L[key]) end
end

---------------------------------------------------------------------------------------------------------------------
-- Playing
---------------------------------------------------------------------------------------------------------------------
local function newTurn(now)
	turns = turns + 1
	startedAt = now
	Tracker.mobKey, Tracker.mobToken = "demo:" .. turns, nil
end

-- One step of the fight: the records written, then the model as after a scan.
function Demo.Tick()
	if not active then return false end
	local now = ns.Compat.Now()
	if now - startedAt >= ns.DemoData.LENGTH then newTurn(now) end
	local period, key = 1 / rate, Tracker.mobKey
	Scanner.holder = ns.DemoData.Fill(Scanner.records, now - startedAt)
	for i = 1, Scanner.count do
		local rec = Scanner.records[i]
		rec.observedAt, rec.interval, rec.mobKey = now, period, key
	end
	Scanner.lastScanAt, Scanner.scans = now, Scanner.scans + 1
	emit("THREAT_SCANNED", key)
	return true
end

local function tick() Demo.Tick() end

function Demo.IsActive() return active end

-- Starts the demo. Returns true, or false and why: "active", "off" (the monitor is switched off), "unsupported",
-- "combat".
function Demo.Start()
	if active then return false, "active" end
	if not (ns.Features and ns.Features.On("monitor")) then return false, "off" end
	if ns.addon and ns.addon.isForever == false then return false, "unsupported" end
	if ns.addon and ns.addon.inCombat then return false, "combat" end
	readRate()
	buildRecords()
	Scanner.scans = 0
	real.tracker, real.scanner = ns.TargetTracker, ns.ThreatScanner
	ns.TargetTracker, ns.ThreatScanner = Tracker, Scanner
	active = true
	Demo.starts = Demo.starts + 1
	newTurn(ns.Compat.Now())
	if ns.Window then ns.Window:ShowMonitor() end
	Demo.Tick()
	ns.Scheduler.Start(Demo.TICK, rate, tick)
	emit("DEMO_CHANGED", true)
	return true
end

-- Ends the demo and puts the real sources back. Returns false when it was not running.
function Demo.Stop()
	if not active then return false end
	active = false
	ns.Scheduler.Stop(Demo.TICK)
	ns.TargetTracker, ns.ThreatScanner = real.tracker, real.scanner
	real.tracker, real.scanner = nil, nil
	-- the model and the states go back to what the real modules last read
	emit("THREAT_SCANNED", ns.TargetTracker and ns.TargetTracker.mobKey)
	emit("DEMO_CHANGED", false)
	return true
end

-- "off" is not listed: with the monitor switched off neither the command nor the button reaches the demo.
local WHY_NOT = { unsupported = "MODULE_TIP_UNSUPPORTED", combat = "DEMO_IN_COMBAT" }

-- Starts or ends the demo and answers in the chat window (the command and the button of Settings).
function Demo.Toggle()
	if active then
		Demo.Stop()
		say("DEMO_STOPPED")
		return true
	end
	local ok, why = Demo.Start()
	if ok then say("DEMO_STARTED") elseif WHY_NOT[why] then say(WHY_NOT[why]) end
	return ok, why
end

-- `/atw demo [stop]`.
function Demo.Command(word)
	word = type(word) == "string" and word:lower() or ""
	if word == "" then return Demo.Toggle() end
	if word == "stop" or word == "off" then
		if active then return Demo.Toggle() end
		return say("DEMO_NOT_RUNNING")
	end
	say("DEMO_USAGE")
end

function Demo.DebugLines()
	return { ("%s, started %d time(s)"):format(active and "running" or "off", Demo.starts) }
end

if ns.Bus then
	local Bus = ns.Bus
	-- registered before the Data modules (TOC order): the real sources are back before they see the combat
	Bus.On("COMBAT_STARTED", function()
		if Demo.Stop() then say("DEMO_COMBAT") end
	end)
	Bus.On("WINDOW_SHOWN", function(shown)
		if not shown and Demo.Stop() then say("DEMO_STOPPED") end
	end)
	Bus.On("CONFIG_CHANGED", function(path)
		if active and path == RATE_PATH then
			readRate()
			ns.Scheduler.Start(Demo.TICK, rate, tick)
		end
	end)
end

if ns.addon then
	ns.addon.Demo = Demo
	ns.addon:AddDebugSection("Demo", Demo.DebugLines)
end
