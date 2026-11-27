-- Recorder: the recording of a fight into a session (SPEC-05 §1, §6; REC-01-REC-06; ADR 0003, 0004, 0014, 0016).
-- Lua 5.1, no threat API: it reads the rows of Data/ThreatModel.lua and the events of the Bus; the game is asked through
-- Core/Compat.lua only for the zone, the instance, the group, the names and the mob's creature number at the opening,
-- and it listens to PLAYER_LOGOUT, UNIT_DIED, PLAYER_DEAD, ENCOUNTER_START and ENCOUNTER_END. Threatwarden's own.
--
-- A session opens at COMBAT_STARTED when every condition of SPEC-05 §1.1 holds (the `monitor` and `recording`
-- switches, a recognised client, settings.recording.enabled, settings.recording.when, no demo, the account data
-- writable); it is appended at once to `sessions` with state "open" (a /reload saves it), event C. COMBAT_ENDED writes
-- c and starts END_DELAY (5 s); a COMBAT_STARTED inside it continues the same session (C with a = 2, chained pulls).
-- At the end of the delay the session is joined (Data/Session.lua), complete, and kept only with at least
-- Session.LIMITS.minFight seconds of combat and one row; otherwise it is taken out of `sessions` (dropped). The demo,
-- the setting turned off or the switch turned off close it at once.
--
-- The tick "record" (settings.recording.rate, 1-5 Hz, combat only) writes one row for every NEW read of a value
-- (codes 0-4) and a row without a number only when the code of the unit changes on that mob (SPEC-05 §1.3), and counts
-- per unit the ticks with values, with the state only and unknown (q.v, q.s, q.x). While a session is open in combat
-- the recorder is a consumer of the scanner ("recorder"), so the threat is read with the window closed too.
--
-- PLAYER_LOGOUT in combat writes only X, `stamp` and state "interrupted" (no heavy work at logout); during END_DELAY it
-- closes the session without joining it (Storage joins it at the next load, M4.3). After a /reload in combat the new
-- session starts with C a = r and `after` = the id of the interrupted session it continues (SPEC-05 §1.6).
--
-- Bus: SESSION_STARTED(id), SESSION_ENDED(id, state) with "complete", "interrupted" or "dropped", SESSIONS_CHANGED()
-- when `sessions` changed (through Data/Storage.lua: Storage.Add at the opening, Storage.Closed at the close, which
-- prunes, M4.3); never a name. While the `recording` switch is off at login nothing is registered, no tick runs and
-- nothing is written (ADR 0014).
local ADDON_NAME, ns = ...
ns = ns or {}
ns.modules = ns.modules or {}

local Recorder = {}
ns.Recorder, ns.modules.Recorder = Recorder, Recorder

local Compat, Config, Session, Storage = ns.Compat, ns.Config, ns.Session, ns.Storage
local type, floor, pairs, ipairs, tostring = type, math.floor, pairs, ipairs, tostring

Recorder.END_DELAY = 5
Recorder.TICK = "record"
Recorder.CONSUMER = "recorder"
local PREFIX = "account.settings.recording."
local ENABLED_PATH, RATE_PATH = PREFIX .. "enabled", PREFIX .. "rate"

-- The real modules: demo mode puts invented ones in ns.TargetTracker and ns.ThreatScanner (nothing is recorded then).
local Tracker, Scanner = ns.TargetTracker, ns.ThreatScanner
local Model, State = ns.ThreatModel, ns.ThreatState

Recorder.current = nil        -- the open session (REC-04: at most one)
Recorder.enabled = false      -- listeners and game events registered (the switches were on at login)
Recorder.stats = { opened = 0, kept = 0, dropped = 0, interrupted = 0, skipped = 0, lastSkip = nil }

-- The runtime part of the open session (never saved): keys -> indexes, the last row per unit, the combat periods.
local rt = {
	unitIdx = {}, mobIdx = {}, lastObs = {}, lastCode = {}, lastMob = {},
	t0 = 0, inFight = false, fightStart = 0, fight = 0, lastC = 0, lastTickAt = nil, gen = 0, lastRule = nil,
	mob = 0,
}
local opened = 0              -- sessions opened since this load (the counter of the id)
local fromReload = false      -- ENTERING_WORLD of a /reload with the player in combat: the next C is "r"
local hz = Config.RECORDING_DEFAULTS.rate

local function emit(event, ...)
	if ns.Bus then ns.Bus.Emit(event, ...) end
end

local function on()
	local F = ns.Features
	return F ~= nil and F.On("monitor") and F.On("recording")
end

local function get(key)
	return Config:Get(PREFIX .. key)
end

local function readRate()
	local value = get("rate")
	local R = Config.RECORDING.rate
	if type(value) ~= "number" or value ~= value then value = Config.RECORDING_DEFAULTS.rate end
	value = floor(value + 0.5)
	if value < R.min then value = R.min elseif value > R.max then value = R.max end
	hz = value
end

function Recorder.Rate() return hz end

-- Tenths of a second since the first C of the open session.
local function tenths(now)
	local t = floor((now - rt.t0) * 10 + 0.5)
	if t < 0 then t = 0 end
	return t
end

local function nowT() return tenths(Compat.Now()) end

---------------------------------------------------------------------------------------------------------------------
-- Conditions (SPEC-05 §1.1)
---------------------------------------------------------------------------------------------------------------------
local function instanceType()
	local kind = Compat.InstanceInfo()
	if kind == nil then kind = Compat.InstanceType() end
	return kind
end

-- nil when a fight may be recorded now, else the first reason missing (/atw debug).
function Recorder.WhyNot()
	if not on() then return "switch" end
	if ns.addon and ns.addon.isForever == false then return "client" end
	if get("enabled") ~= true then return "off" end
	local when = get("when")
	if when ~= "always" then
		local kind = instanceType()
		local inInstance = kind ~= nil and kind ~= "none"
		if when == "instance" then
			if not inInstance then return "when" end
		elseif not (inInstance or Compat.Group.InGroup()) then
			return "when"
		end
	end
	if ns.Demo and ns.Demo.IsActive() then return "demo" end
	if Config:IsReadOnly("account") or type(Config:Get("account.sessions")) ~= "table" then return "read-only" end
	return nil
end

---------------------------------------------------------------------------------------------------------------------
-- Units and mobs of the session
---------------------------------------------------------------------------------------------------------------------
local function recordOfKey(unitKey)
	for i = 1, Scanner.count do
		local rec = Scanner.records[i]
		if rec.unitKey == unitKey then return rec end
	end
	return nil
end

-- The index of a unit in `units` (a new entry from its record the first time); nil when it is not watched or past
-- the limit.
local function unitIndex(unitKey, rec)
	if unitKey == nil then return nil end
	local u = rt.unitIdx[unitKey]
	if u ~= nil then return u or nil end
	rec = rec or recordOfKey(unitKey)
	if not rec then return nil end
	local token = rec.unitToken
	u = Session.AddUnit(Recorder.current, { name = rec.unitName, class = rec.classFile, role = rec.role, token = token,
		me = token == "player" or nil, pet = token == "pet" or nil }, nowT())
	rt.unitIdx[unitKey] = u or false
	if u then rt.lastObs[u], rt.lastCode[u], rt.lastMob[u] = 0, nil, 0 end
	return u
end

-- The index of a mob in `mobs`: name, classification and creature number when it is the monitored one, else unknown.
local function mobIndex(mobKey)
	if mobKey == nil then return nil end
	local m = rt.mobIdx[mobKey]
	if m ~= nil then return m or nil end
	local entry = {}
	if mobKey == Tracker.mobKey and Tracker.mobToken then
		entry.name = (Compat.Unit.Name(Tracker.mobToken))
		entry.class = (Compat.Unit.Classification(Tracker.mobToken))
		entry.npc = (Compat.Unit.NpcID(Tracker.mobGUID))
	end
	m = Session.AddMob(Recorder.current, entry, nowT())
	rt.mobIdx[mobKey] = m or false
	return m
end

local function event(k, m, u, v, a, b, c, n)
	local s = Recorder.current
	if not s then return false end
	return Session.AddEvent(s, nowT(), k, m or 0, u or 0, v or 0, a, b, c, n)
end

---------------------------------------------------------------------------------------------------------------------
-- The tick (SPEC-05 §1.3)
---------------------------------------------------------------------------------------------------------------------
local function tick()
	local s = Recorder.current
	if not s then return end
	if not on() then Recorder.Close("switch") return end
	if not rt.inFight then return end
	local now = Compat.Now()
	local last = rt.lastTickAt
	rt.lastTickAt = now
	if last then
		local gap = 3 / hz
		if gap < 1 then gap = 1 end
		if now - last > gap + 1e-6 then
			local n = floor((now - last) * 10 + 0.5)
			Session.AddEvent(s, tenths(now), "G", 0, 0, 0, "t", "-", "-", n > Session.MAX_N and Session.MAX_N or n)
		end
	end
	if s.trunc then return end                  -- samples and counters stopped at a limit
	local mobKey = Model.mobKey
	if mobKey == nil then return end
	local m = mobIndex(mobKey)
	if not m then return end
	local rows, q = Model.rows, s.q
	local lastObs, lastCode, lastMob = rt.lastObs, rt.lastCode, rt.lastMob
	for i = 1, Model.count do
		local row = rows[i]
		local rec = row.record
		if row.present and rec then
			local u = unitIndex(rec.unitKey, rec)
			if u then
				local fresh = not Model.IsStale(rec, now)
				local code, p, numbered = Session.RowCode(rec, fresh)
				if numbered then q.v[u] = q.v[u] + 1
				elseif code == "a" or code == "b" or code == "c" or code == "d" then q.s[u] = q.s[u] + 1
				else q.x[u] = q.x[u] + 1 end
				local observed = rec.observedAt or 0
				local write = false
				if numbered then
					write = observed > lastObs[u] + 1e-9
				else
					write = code ~= lastCode[u] or lastMob[u] ~= m
				end
				if write then
					local t = code == "T" and tenths(now) or tenths(observed)
					if not Session.AddRow(s, t, m, u, p, code) then return end
					if observed > lastObs[u] then lastObs[u] = observed end
					lastCode[u], lastMob[u] = code, m
				end
			end
		end
	end
end

local function startTick()
	readRate()
	ns.Scheduler.Start(Recorder.TICK, hz, tick, { combat = true })
end

---------------------------------------------------------------------------------------------------------------------
-- The life cycle (SPEC-05 §1.2)
---------------------------------------------------------------------------------------------------------------------
local function sessions() return Config:Get("account.sessions") end

local function uniqueId(list, id)
	local taken = {}
	for _, s in ipairs(list) do
		if type(s) == "table" and type(s.id) == "string" then taken[s.id] = true end
	end
	if not taken[id] then return id end
	for i = 2, 26 do
		local candidate = id .. "-" .. string.char(96 + i)
		if not taken[candidate] then return candidate end
	end
	return id .. "-" .. tostring(#list + 1)
end

-- The id of the most recent interrupted session that ended less than LIMITS.link seconds ago (SPEC-05 §1.6).
local function linkedId(list, server)
	if not server then return nil end
	for i = #list, 1, -1 do
		local s = list[i]
		if type(s) == "table" and (s.state == "interrupted" or s.state == "open") and type(s.started) == "number" then
			local ended = s.started + (type(s.dur) == "number" and s.dur or 0) / 10
			if server - ended <= Session.LIMITS.link then return s.id end
			return nil
		end
	end
	return nil
end

local function resetRuntime(now)
	for k in pairs(rt.unitIdx) do rt.unitIdx[k] = nil end
	for k in pairs(rt.mobIdx) do rt.mobIdx[k] = nil end
	for i = #rt.lastObs, 1, -1 do rt.lastObs[i], rt.lastCode[i], rt.lastMob[i] = nil, nil, nil end
	rt.t0, rt.inFight, rt.fightStart, rt.fight, rt.lastC, rt.lastTickAt = now, true, 0, 0, 0, nil
	rt.lastRule, rt.mob = nil, 0
end

local function groupKind()
	if Compat.Group.InRaid() then return "raid" end
	if Compat.Group.InGroup() then return "party" end
	return "solo"
end

local function modeEvent()
	local mode = State and State.mode or "none"
	event("M", 0, 0, 0, Session.MODE_CODE[mode] or "n", Session.Reason(State and State.modeReason))
end

local function targetEvent(mobKey)
	if mobKey ~= nil then
		local m = mobIndex(mobKey)
		rt.mob = m or 0
		event("T", m or 0, 0, 0, "-")
		return
	end
	local status = Tracker.status
	local previous = rt.mob
	rt.mob = 0
	if status == "died" then
		event("T", 0, 0, 0, "d")
		if previous > 0 then event("D", previous, 0, 0, "t") end
	elseif status == "lost" then
		event("T", 0, 0, 0, "l")
	else
		event("T", 0, 0, 0, "n")
	end
end

local function open(kind)
	local list = sessions()
	local now, server = Compat.Now(), Compat.ServerTime()
	opened = opened + 1
	local zone = Compat.ZoneText()
	local inst, diff = Compat.InstanceInfo()
	if inst == nil then inst = Compat.InstanceType() end
	local warning, danger = State.Thresholds()
	readRate()
	local s = Session.New{
		id = uniqueId(list, tostring(server or 0) .. "-" .. opened),
		started = server or 0,
		after = kind == "r" and linkedId(list, server) or nil,
		group = groupKind(), zone = zone, inst = inst, diff = diff,
		rec = { hz = hz, monitorHz = Scanner.Rate(), maxUnits = Scanner.MaxUnits(), warning = warning, danger = danger,
			mode = State.mode or "none", version = Compat.AddonVersion() },
	}
	Recorder.current = s
	Storage.Add(s)
	resetRuntime(now)
	Recorder.stats.opened = Recorder.stats.opened + 1
	Session.AddEvent(s, 0, "C", 0, 0, 0, kind)
	modeEvent()
	if Tracker.mobKey ~= nil then targetEvent(Tracker.mobKey) end
	startTick()
	Scanner.Want(Recorder.CONSUMER, true)
	emit("SESSION_STARTED", s.id)
end

-- The end of a combat period: event c, the time in combat counted.
local function endPeriod()
	local t = nowT()
	event("c")
	rt.fight = rt.fight + (t - rt.fightStart)
	rt.lastC = t
	rt.inFight = false
	rt.lastTickAt = nil
	ns.Scheduler.Stop(Recorder.TICK)
	Scanner.Want(Recorder.CONSUMER, false)
end

-- Closes the open session (SPEC-05 §1.2 point 4 and 5). `join` false: at logout the pieces stay for Storage.
function Recorder.Close(why, join)
	local s = Recorder.current
	if not s then return nil end
	rt.gen = rt.gen + 1                          -- a pending END_DELAY timer does nothing
	if rt.inFight then endPeriod() end
	Recorder.current = nil
	ns.Scheduler.Stop(Recorder.TICK)
	Scanner.Want(Recorder.CONSUMER, false)
	s.dur, s.fight = rt.lastC, rt.fight
	if join ~= false then Session.Join(s) end
	s.state, s.ended = "complete", "combat"
	local state = "complete"
	if s.fight < Session.LIMITS.minFight * 10 or s.n < 1 then
		state = "dropped"
		Recorder.stats.dropped = Recorder.stats.dropped + 1
	else
		Recorder.stats.kept = Recorder.stats.kept + 1
	end
	Recorder.stats.lastClose = why
	Storage.Closed(s, state ~= "dropped")      -- a dropped one taken out; pruning; SESSIONS_CHANGED
	emit("SESSION_ENDED", s.id, state)
	return state
end

local function onCombatStarted()
	local kind = fromReload and "r" or "1"
	fromReload = false
	local s = Recorder.current
	if s then
		if rt.inFight then return end            -- REC-04: already recording this combat
		if not on() then Recorder.Close("switch") return end
		rt.gen = rt.gen + 1                      -- a chained pull: the timer of END_DELAY is cancelled
		rt.inFight, rt.fightStart, rt.lastTickAt = true, nowT(), nil
		event("C", 0, 0, 0, "2")
		startTick()
		Scanner.Want(Recorder.CONSUMER, true)
		return
	end
	local why = Recorder.WhyNot()
	if why then
		Recorder.stats.skipped = Recorder.stats.skipped + 1
		Recorder.stats.lastSkip = why
		return
	end
	Recorder.stats.lastSkip = nil
	open(kind)
end

local function onCombatEnded()
	fromReload = false
	local s = Recorder.current
	if not s or not rt.inFight then return end   -- REC-04: no combat going on
	endPeriod()
	local gen = rt.gen
	if not Compat.After(Recorder.END_DELAY, function()
		if rt.gen == gen and Recorder.current == s then Recorder.Close("combat") end
	end) then
		Recorder.Close("combat")
	end
end

-- PLAYER_LOGOUT (also at a /reload [probe P12]): in combat only X and the stamp; in END_DELAY the close without join.
local function onLogout()
	local s = Recorder.current
	if not s then return end
	if rt.inFight then
		local t = nowT()
		event("X", 0, 0, 0, "o")
		s.stamp, s.state = true, "interrupted"
		s.dur, s.fight = t, rt.fight + (t - rt.fightStart)
		Recorder.current = nil
		Recorder.stats.interrupted = Recorder.stats.interrupted + 1
		emit("SESSION_ENDED", s.id, "interrupted")
	else
		Recorder.Close("logout", false)
	end
end

---------------------------------------------------------------------------------------------------------------------
-- Events of the Bus (SPEC-05 §1.4)
---------------------------------------------------------------------------------------------------------------------
local function fighting() return Recorder.current ~= nil and rt.inFight end

local function onTargetChanged(mobKey)
	if not fighting() then return end
	targetEvent(mobKey)
end

local function onStateChanged(unitKey, mobKey, old, new)
	if not fighting() then return end
	local u = unitIndex(unitKey)
	local m = mobIndex(mobKey)
	local reason = nil
	if new ~= nil then
		for i = 1, Model.count do
			local row = Model.rows[i]
			if row.record and row.record.unitKey == unitKey then reason = row.stateReason break end
		end
	end
	local C = Session.STATE_CODE
	event("S", m or 0, u or 0, 0, new and C[new] or "-", old and C[old] or "-", Session.Reason(reason))
end

local function tankFlag(unitKey)
	if unitKey == nil then return "-" end
	for i = 1, Model.count do
		local row = Model.rows[i]
		if row.record and row.record.unitKey == unitKey then return row.isTank and "1" or "0" end
	end
	return "-"
end

local function onAggroChanged(mobKey, unitKey, oldUnitKey)
	if not fighting() then return end
	event("A", mobIndex(mobKey) or 0, unitIndex(unitKey) or 0, oldUnitKey and unitIndex(oldUnitKey) or 0,
		tankFlag(unitKey), tankFlag(oldUnitKey))
end

local function onModeChanged(mode, reason)
	if not Recorder.current then return end
	event("M", 0, 0, 0, Session.MODE_CODE[mode] or "n", Session.Reason(reason))
end

local function onAlert(alert)
	if not fighting() or type(alert) ~= "table" or alert.demo then return end
	if alert.kind == "mob" then return end   -- about a mob that is not in the session (SPEC-07 §2.5, ADR 0019)
	local other = alert.otherKey
	local n = (Session.CATEGORY_CODE[alert.category] or "u") .. (Session.CONFIDENCE_CODE[alert.confidence] or "u")
	local severity = type(alert.severity) == "number" and alert.severity >= 1 and alert.severity <= 3
		and Session.DIGIT[alert.severity] or "-"
	event("L", mobIndex(alert.mobKey) or 0, unitIndex(alert.unitKey) or 0, other and unitIndex(other) or 0,
		Session.ALERT_CODE[alert.kind] or "-", severity, alert.muted and "1" or "0", n)
end

local function playerIndex()
	local rec = Scanner.RecordOf("player")
	return rec and unitIndex(rec.unitKey, rec) or 0
end

local function onCoachTip(tip)
	if not Recorder.current then return end
	if tip == nil then rt.lastRule = nil return end
	if type(tip) ~= "table" or tip.demo or tip.rule == rt.lastRule then return end
	rt.lastRule = tip.rule
	event("H", 0, playerIndex(), 0, Session.RULE_CODE[tip.rule] or "-",
		tip.category and Session.CATEGORY_CODE[tip.category] or "-",
		tip.confidence and Session.CONFIDENCE_CODE[tip.confidence] or "-")
end

local function onDemo(active)
	if active and Recorder.current then Recorder.Close("demo") end
end

local function onConfigChanged(path)
	if path == ENABLED_PATH then
		if get("enabled") ~= true and Recorder.current then Recorder.Close("off") end
	elseif path == RATE_PATH then
		local old = hz
		readRate()
		if hz ~= old and ns.Scheduler.IsRunning(Recorder.TICK) then startTick() end
	end
end

local function onEnteringWorld(isInitialLogin, isReloadingUi)
	fromReload = isReloadingUi == true and Compat.Unit.AffectingCombat("player") == true
end

---------------------------------------------------------------------------------------------------------------------
-- Game events (SPEC-05 §1.4, §1.6 [probe P7, P12])
---------------------------------------------------------------------------------------------------------------------
local game = {}

function game.PLAYER_LOGOUT() onLogout() end

-- UNIT_DIED(unitGUID): only a readable GUID of a watched unit or of a mob of the session.
function game.UNIT_DIED(_, guid)
	if not Recorder.current or Compat.IsSecret(guid) or type(guid) ~= "string" then return end
	local u = rt.unitIdx["unit:" .. guid]
	if u then event("D", 0, u, 0, "g") return end
	local m = rt.mobIdx["mob:" .. guid]
	if m then event("D", m, 0, 0, "g") end
end

function game.PLAYER_DEAD()
	if not Recorder.current then return end
	event("D", 0, playerIndex(), 0, "p")
end

local function encounterId(id)
	if Compat.IsSecret(id) or type(id) ~= "number" or id ~= floor(id) or id < 0 or id > Session.MAX_N then return nil end
	return id
end

function game.ENCOUNTER_START(_, id)
	if not Recorder.current then return end
	event("N", 0, 0, 0, "s", "-", "-", encounterId(id))
end

function game.ENCOUNTER_END(_, id, _, _, _, success)
	if not Recorder.current then return end
	local ok = "-"
	if not Compat.IsSecret(success) and type(success) == "number" then ok = success == 1 and "1" or "0" end
	event("N", 0, 0, 0, "e", ok, "-", encounterId(id))
end

local function onGame(name, ...)
	local fn = game[name]
	if fn then fn(name, ...) end
end

function Recorder.Enable()
	if Recorder.enabled or not on() then return false end
	local AceEvent = LibStub and LibStub("AceEvent-3.0", true)
	if not AceEvent then return false end
	AceEvent:Embed(Recorder)
	for name in pairs(game) do Recorder:RegisterEvent(name, onGame) end
	local Bus = ns.Bus
	Bus.On("COMBAT_STARTED", onCombatStarted)
	Bus.On("COMBAT_ENDED", onCombatEnded)
	Bus.On("TARGET_CHANGED", onTargetChanged)
	Bus.On("STATE_CHANGED", onStateChanged)
	Bus.On("AGGRO_CHANGED", onAggroChanged)
	Bus.On("THREAT_MODE_CHANGED", onModeChanged)
	Bus.On("ALERT_RAISED", onAlert)
	Bus.On("COACH_TIP", onCoachTip)
	Bus.On("DEMO_CHANGED", onDemo)
	Bus.On("CONFIG_CHANGED", onConfigChanged)
	Bus.On("ENTERING_WORLD", onEnteringWorld)
	readRate()
	Recorder.enabled = true
	if ns.addon and ns.addon.AddDebugSection then ns.addon:AddDebugSection("Recording", Recorder.DebugLines) end
	return true
end
if ns.OnEnable then ns.OnEnable(Recorder.Enable) end

---------------------------------------------------------------------------------------------------------------------
-- /atw debug, section Recording (SPEC-05 §6): counts only, never a name, a zone or a mob
---------------------------------------------------------------------------------------------------------------------
function Recorder.DebugLines()
	local F = ns.Features
	local lines = {
		("switches: recording %s, reports %s; enabled %s, when %s, %d Hz, at most %s sessions / %s KB"):format(
			F.On("recording") and "on" or "off", F.On("reports") and "on" or "off", tostring(get("enabled")),
			tostring(get("when")), hz, tostring(get("maxSessions")), tostring(get("maxKB"))),
	}
	local s = Recorder.current
	if s then
		lines[#lines + 1] = ("open: %.1f s, %s, %d row(s), %d event(s), %d unit(s), %d mob(s), %d piece(s)%s"):format(
			Compat.Now() - rt.t0, rt.inFight and "in combat" or "end delay", s.n, s.ne, #s.units, #s.mobs,
			Session.Pieces(s), s.trunc and ", samples stopped at a limit" or "")
	else
		lines[#lines + 1] = "no session open; last fight not recorded because: " .. tostring(Recorder.stats.lastSkip or "-")
	end
	local st = Recorder.stats
	lines[#lines + 1] = ("recorder this load: %d opened, %d kept, %d dropped, %d interrupted"):format(st.opened, st.kept,
		st.dropped, st.interrupted)
	for _, line in ipairs(Storage.DebugLines()) do lines[#lines + 1] = line end
	local median, max = ns.Scheduler.Cost(Recorder.TICK)
	lines[#lines + 1] = ("record tick: %s ms median, %s ms max"):format(median and ("%.3f"):format(median) or "?",
		max and ("%.3f"):format(max) or "?")
	return lines
end

if ns.addon then ns.addon.Recorder = Recorder end
