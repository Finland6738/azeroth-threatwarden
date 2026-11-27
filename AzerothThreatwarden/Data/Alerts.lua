-- Alerts: a short signal when a risk condition enters (SPEC-04 §1, §4.1, §5; ALR-01-ALR-04; SPEC-09 Q12; ADR 0001,
-- 0003, 0014). Lua 5.1; the only game calls are the clock and the sound, through Compat. Threatwarden's own.
--
-- Two sources, both already cleaned by hysteresis and dwell (Data/ThreatState.lua):
--   STATE_CHANGED(unitKey, mobKey, old, new)   a state entered: nil, SAFE, WARNING -> WARNING or DANGER; from UNKNOWN
--                                              only above the last known state of that unit on that mob. Never a fall,
--                                              never UNKNOWN. The reasons "aggro" and "lost-aggro" do not alert here.
--   AGGRO_CHANGED(mobKey, unitKey, oldUnitKey) the unit holding the mob changed (emitted before the STATE_CHANGED of
--                                              the same update): at most one alert per change, and the self alerts of
--                                              lower or equal severity of that update are dropped (one transition, one
--                                              alert).
--
-- Only while the `alerts` switch is on (ADR 0014), `settings.alerts.enabled`, in combat (the scanner's own flag, which
-- is set before the first scan of a fight) and for the monitored mob. Then, in this order: the subject's exclusion and
-- the settings `others` / `pet`, the cooldown per kind and subject (time only: it survives target changes and fights),
-- the gap between two `other` alerts, and the channels. While muted an alert is evaluated and emitted with `muted` and
-- no channel. Nothing is ever written to chat (ALR-02) and nothing opens the window (ALR-04).
--
-- With the `multitarget` switch on and `alerts.onlyTarget` off, a third source: the mobs of Data/MobTracker.lua other
-- than the monitored one (kind `mob`, SPEC-07 §2.5, M7.4). Alerts looks at the list after each MOBS_UPDATED, so that a
-- change of reason or of the player's own state counts as an entry too (MOB_STATE_CHANGED only tells a change of state).
-- It remembers, per mob key, the condition and the player's state it last knew (also for the monitored mob, so that a mob
-- that was the target says nothing when the player leaves it), and raises, only for what rises:
--   ALERT_MOB_SELF     the player's state on the mob enters DANGER and the player is not a tank (D12); the player first:
--                      one alert per mob and update
--   ALERT_MOB_AGGRO    DANGER `aggro`: someone who is not a tank holds it (severity 3)
--   ALERT_MOB_CLOSE    DANGER `close`: the closest of the others is about to pull it (severity 2)
--   ALERT_MOB_NO_TANK  WARNING `no-tank` (severity 1)
-- The three about others go to `alerts.others` (by default only a tank), keep OTHER_GAP, and say nothing about the
-- player (the alert about oneself is ALERT_MOB_SELF) or about an excluded unit; the cooldown is per kind `mob` and per
-- mob. A mob that cannot be read (UNKNOWN) changes nothing: nothing is remembered from it and nothing is raised, so it
-- speaks again only above the last known condition. With the sound on, the tracker is wanted too ("alerts"). Nothing of
-- it is recorded (Data/Recorder.lua) and nothing is posted in chat.
--
-- ALERT_RAISED(alert): a table of a ring of RING reused ones; a listener that keeps it copies it:
--   { kind, severity (1 WARNING, 2 DANGER, 3 aggro moved), state, reason, subject ("self", "pet", "other"), unitKey
--     ("" for a `mob` alert about no unit: ALERT_MOB_NO_TANK, or ALERT_MOB_CLOSE with no closest one known),
--     otherKey (the unit of the `%s`, when the message has one), mobKey, message (a locale key), args (numbers; a `%s`
--     comes first in the message), category, confidence, at, muted, demo, window, visual, sound (the channels used) }
-- MUTE_CHANGED(muted) at every change of the mute. Never a name, never a secret value.
--
-- Not saved: the mute (until the end of the fight, or of the next one), the session exclusions by unitKey and the
-- cooldowns. Allocation-free per event after the warm-up (the ring, the tables per kind and per unit are reused).
local ADDON_NAME, ns = ...
ns = ns or {}
ns.modules = ns.modules or {}

local Alerts = {}
ns.Alerts, ns.modules.Alerts = Alerts, Alerts

local type, pairs, ipairs, floor, ceil = type, pairs, ipairs, math.floor, math.ceil
local concat = table.concat

Alerts.HOLD = 4          -- seconds the Coach strip shows an alert (UI/CoachStrip.lua, M3.4)
Alerts.OTHER_GAP = 3     -- seconds between two alerts about other units
Alerts.SOUND_GAP = 3     -- seconds between two sounds, whatever the kind
Alerts.SOUND_KIT = 8959  -- the one sound of the game: the raid warning of the modern client [to be tried in game]
Alerts.SOUND_SEVERITY = 2   -- a sound for this severity and above: never for a WARNING
Alerts.RING = 8
Alerts.PRUNE_AT = 200    -- units remembered before the old ones are forgotten at the end of a fight
Alerts.MOB_PRUNE_AT = 64 -- mobs in cooldown before the old ones are forgotten during a fight

Alerts.KINDS = { "warning", "danger", "aggro", "margin", "lost", "pet", "other", "mob" }
-- Every message key an alert can carry (the locales and the wording tests read it).
Alerts.MESSAGES = { "ALERT_WARNING", "ALERT_WARNING_TANK", "ALERT_WARNING_PREDICTED", "ALERT_WARNING_STATE",
	"ALERT_DANGER", "ALERT_DANGER_HEALER", "ALERT_DANGER_TANK", "ALERT_AGGRO",
	"ALERT_MARGIN_WARNING", "ALERT_MARGIN_WARNING_STATE", "ALERT_MARGIN_DANGER", "ALERT_MARGIN_DANGER_STATE",
	"ALERT_BEHIND", "ALERT_LOST", "ALERT_PET", "ALERT_OTHER_DANGER", "ALERT_OTHER_AGGRO",
	"ALERT_MOB_AGGRO", "ALERT_MOB_CLOSE", "ALERT_MOB_NO_TANK", "ALERT_MOB_SELF" }
-- Messages whose `%s` is a unit: the word for an unknown one is written when the alert carries none.
local NAMED = { ALERT_MOB_AGGRO = true, ALERT_MOB_CLOSE = true }

local LEVEL = { SAFE = 1, WARNING = 2, DANGER = 3 }
local EPSILON = 1e-9
local PREFIX = "account.settings.alerts."

local Config, Compat = ns.Config, ns.Compat
-- The real scanner and tracker: demo mode puts invented ones in ns.ThreatScanner and ns.MobTracker (no consumers).
local RealScanner, RealMobs = ns.ThreatScanner, ns.MobTracker

local settings = {}
for key, value in pairs(Config.ALERTS_DEFAULTS) do settings[key] = value end

local muted = false
local wantsScanner = false
local wantsMobs = false
local excluded = {}          -- unitKey -> true (session only)
local excludedCount = 0

-- cooldowns[kind][unitKey] = when that kind was last raised about that unit
local cooldowns = {}
for _, kind in ipairs(Alerts.KINDS) do cooldowns[kind] = {} end
local lastOtherAt, lastSoundAt = -math.huge, -math.huge

local known, knownCount = {}, 0    -- unitKey -> level of its last known state on `knownMob` (0: none)
local knownMob = nil
local aggroUnit, aggroAt, aggroSeverity = nil, 0, 0   -- the self alert of the last AGGRO_CHANGED (the merge)
local marginSecond, marginAt = nil, 0   -- the second named by the last Danger margin alert raised (the merge)
-- The other mobs (M7.4), by mob key: the rank of the last known condition, and the player's last known level.
local mobRank, mobSelf = {}, {}
local mobCooldowns = 0       -- the entries of cooldowns.mob

local function newStats()
	local stats = { raised = {}, cooled = 0, dropped = 0, muted = 0, sounds = 0, soundFailed = 0, soundReason = nil,
		lastAt = nil }
	for _, kind in ipairs(Alerts.KINDS) do stats.raised[kind] = 0 end
	return stats
end
Alerts.stats = newStats()

local ring, ringNext = {}, 0
for i = 1, Alerts.RING do
	ring[i] = { kind = "", severity = 0, state = "", reason = false, subject = "", unitKey = "", otherKey = false,
		mobKey = "", message = "", args = { 0 }, category = "", confidence = "", at = 0, muted = false, demo = false,
		window = false, visual = false, sound = false }
end

local function on()
	return ns.Features ~= nil and ns.Features.On("alerts")
end

local function multiOn()
	return ns.Features ~= nil and ns.Features.On("multitarget")
end

-- `alerts.onlyTarget` counts as on while the `multitarget` switch is off (SPEC-07 §2.5).
local function onlyTarget()
	return not multiOn() or settings.onlyTarget
end
Alerts.OnlyTarget = onlyTarget

local function emit(event, ...)
	if ns.Bus then ns.Bus.Emit(event, ...) end
end

---------------------------------------------------------------------------------------------------------------------
-- Settings, the scanner consumer and the mute
---------------------------------------------------------------------------------------------------------------------
-- With the sound on, an alert must come with the window closed too: the alerts want the readings (SPEC-04 §1.4), and
-- the other mobs too when they speak of them (SPEC-07 §1.6).
local function refreshConsumer()
	local want = on() and settings.enabled and settings.sound and not muted or false
	if want ~= wantsScanner and RealScanner then
		wantsScanner = want
		RealScanner.Want("alerts", want)
	end
	local others = want and not onlyTarget() and true or false
	if others ~= wantsMobs and RealMobs and RealMobs.Want then
		wantsMobs = others
		RealMobs.Want("alerts", others)
	end
end

local function readSettings()
	local Defaults = Config.ALERTS_DEFAULTS
	for key, default in pairs(Defaults) do
		local value = Config.Get and Config:Get(PREFIX .. key)
		if type(value) ~= type(default) then value = default end
		settings[key] = value
	end
	local limits = Config.ALERTS.cooldown
	local cooldown = floor(settings.cooldown + 0.5)
	if cooldown < limits.min or cooldown > limits.max then cooldown = Defaults.cooldown end
	settings.cooldown = cooldown
end

function Alerts.Cooldown() return settings.cooldown end
function Alerts.IsMuted() return muted end

local function setMuted(value)
	if muted == value then return end
	muted = value
	refreshConsumer()
	emit("MUTE_CHANGED", value)
end

-- /atw mute and the key (M3.5). Returns what happened, for the answer: "muted-fight" (until the end of this fight),
-- "muted-next" (until the end of the next one), "unmuted", "disabled" (alerts off in Settings: nothing changed) or
-- "off" (the switch).
function Alerts.ToggleMute()
	if not on() then return "off" end
	if not settings.enabled then return "disabled" end
	if muted then
		setMuted(false)
		return "unmuted"
	end
	setMuted(true)
	return (ns.addon and ns.addon.inCombat) and "muted-fight" or "muted-next"
end

local function isPlayerKey(unitKey)
	local Scanner = ns.ThreatScanner
	if not Scanner then return false end
	for i = 1, Scanner.count do
		local rec = Scanner.records[i]
		if rec.unitToken == "player" then return rec.unitKey == unitKey end
	end
	return false
end

-- Mutes (value true) or unmutes the alerts about one unit until the /reload (the row menu, M3.5). Kept by unitKey in
-- memory only: no name in the settings. The player cannot be excluded. Returns true when it changed.
function Alerts.Exclude(unitKey, value)
	if not on() or type(unitKey) ~= "string" or isPlayerKey(unitKey) then return false end
	local want = value and true or nil
	if excluded[unitKey] == want then return false end
	excluded[unitKey] = want
	excludedCount = excludedCount + (want and 1 or -1)
	return true
end

function Alerts.IsExcluded(unitKey) return excluded[unitKey] == true end

---------------------------------------------------------------------------------------------------------------------
-- The rows (Data/ThreatModel.lua, the same module in demo mode)
---------------------------------------------------------------------------------------------------------------------
local function rowOfKey(unitKey)
	local Model = ns.ThreatModel
	if not Model or unitKey == nil then return nil end
	for i = 1, Model.count do
		local row = Model.rows[i]
		if row.record and row.record.unitKey == unitKey then return row end
	end
	return nil
end

local function playerRow()
	local Model = ns.ThreatModel
	for i = 1, Model.count do
		local row = Model.rows[i]
		if row.record and row.record.unitToken == "player" then return row end
	end
	return nil
end

-- The player counts as a tank for `others = tank`: the TANK role, or holding the mob with no designated tank.
local function playerIsTank()
	local row = playerRow()
	if not row then return false end
	return row.record.role == "TANK" or (row.present and row.isTank == true) or false
end

local function subjectOf(row)
	local token = row.record.unitToken
	if token == "player" then return "self" end
	if token == "pet" then return "pet" end
	return "other"
end

-- The second of the list: the fresh row in `values` with the highest scaled %, other than the holder.
local function secondRow(holder)
	local Model = ns.ThreatModel
	local best = nil
	for i = 1, Model.count do
		local row = Model.rows[i]
		local rec = row.record
		if row ~= holder and rec and row.present and not row.stale and rec.mode == "values"
			and type(rec.scaledPercent) == "number" then
			if not best or rec.scaledPercent > best.record.scaledPercent then best = row end
		end
	end
	return best
end

-- Alerts are evaluated in combat only, for the monitored mob only (in M3 there is one, SPEC-04 §1.1).
local function listening(mobKey)
	if not settings.enabled or mobKey == nil then return false end
	local Scanner, Tracker = ns.ThreatScanner, ns.TargetTracker
	if not (Scanner and Scanner.inCombat == true) then return false end
	return Tracker ~= nil and Tracker.mobKey == mobKey
end

---------------------------------------------------------------------------------------------------------------------
-- Raising one alert
---------------------------------------------------------------------------------------------------------------------
-- Writes one alert in the ring with its channels and emits it.
local function deliver(kind, severity, subject, unitKey, otherKey, mobKey, message, reason, number, category,
	confidence, now)
	local stats = Alerts.stats
	ringNext = ringNext % Alerts.RING + 1
	local alert = ring[ringNext]
	alert.kind, alert.severity, alert.reason, alert.subject = kind, severity, reason, subject
	alert.state = severity == 1 and "WARNING" or "DANGER"
	alert.unitKey, alert.otherKey, alert.mobKey, alert.message = unitKey, otherKey, mobKey, message
	alert.args[1] = number
	alert.category, alert.confidence, alert.at = category, confidence, now
	alert.demo = ns.Demo ~= nil and ns.Demo.IsActive() or false
	alert.muted = muted
	alert.window = not muted and settings.window
	alert.visual = not muted and settings.visual
	alert.sound = false
	-- the sound: never in demo mode, which calls nothing of the game (MON-14), at most one every SOUND_GAP
	if not muted and not alert.demo and settings.sound and severity >= Alerts.SOUND_SEVERITY
		and now - lastSoundAt >= Alerts.SOUND_GAP - EPSILON then
		local played, why = Compat.PlaySound(Alerts.SOUND_KIT)
		if played then
			lastSoundAt, alert.sound = now, true
			stats.sounds = stats.sounds + 1
		else
			stats.soundFailed, stats.soundReason = stats.soundFailed + 1, why
		end
	end
	stats.raised[kind] = stats.raised[kind] + 1
	if muted then stats.muted = stats.muted + 1 end
	stats.lastAt = now
	emit("ALERT_RAISED", alert)
	return alert
end

-- The gates (exclusion and settings, cooldown, gap between others) and the channels. Returns the alert, or nil.
local function raise(kind, severity, row, mobKey, message, reason, otherKey, number, category, confidence)
	local unitKey = row.record.unitKey
	local subject = subjectOf(row)
	if subject ~= "self" and excluded[unitKey] then return nil end
	if kind == "pet" and not settings.pet then return nil end
	if kind == "other" then
		local others = settings.others
		if others == "never" or (others ~= "always" and not playerIsTank()) then return nil end
	end
	local now = Compat.Now()
	local stats = Alerts.stats
	local times = cooldowns[kind]
	local last = times[unitKey]
	if last and now - last < settings.cooldown - EPSILON then
		stats.cooled = stats.cooled + 1
		return nil
	end
	if kind == "other" then
		if now - lastOtherAt < Alerts.OTHER_GAP - EPSILON then
			stats.dropped = stats.dropped + 1
			return nil
		end
		lastOtherAt = now
	end
	times[unitKey] = now
	return deliver(kind, severity, subject, unitKey, otherKey, mobKey, message, reason, number, category, confidence, now)
end

---------------------------------------------------------------------------------------------------------------------
-- STATE_CHANGED: a state entered
---------------------------------------------------------------------------------------------------------------------
local function forgetKnown()
	for unitKey in pairs(known) do known[unitKey] = 0 end
end

-- Keeps the last known state of every unit on the mob and says whether `old` -> `new` is an entry to alert about.
local function entered(unitKey, mobKey, old, new)
	if mobKey ~= knownMob then
		forgetKnown()
		knownMob = mobKey
	end
	local before = known[unitKey]
	if before == nil then
		before = 0
		knownCount = knownCount + 1
	end
	if old == nil then before = 0 end          -- the unit enters the list: nothing from before
	local level = LEVEL[new]
	if not level then                          -- UNKNOWN, or off the list: never an alert
		known[unitKey] = new and (LEVEL[old] or before) or 0
		return false
	end
	known[unitKey] = level
	if level < LEVEL.WARNING then return false end
	if old == nil then return true end
	if old == "UNKNOWN" then return level > before end
	return level > (LEVEL[old] or 0)
end

local function percent(row)
	local p = row.record.scaledPercent
	if type(p) ~= "number" then return nil end
	return floor(p + 0.5)
end

-- The player holding the mob as a tank: its margin over the second (SPEC-04 §1.2 `margin`).
local function marginAlert(row, mobKey, state, reason)
	local severity = state == "DANGER" and 2 or 1
	if reason == "behind" then
		return "margin", severity, "ALERT_BEHIND", nil, nil, "detected", "high"
	end
	if row.record.mode == "values" and type(row.margin) == "number" and (reason == nil) then
		local second = secondRow(row)
		if second then
			return "margin", severity, state == "DANGER" and "ALERT_MARGIN_DANGER" or "ALERT_MARGIN_WARNING",
				second.record.unitKey, state ~= "DANGER" and percent(second) or nil, "calculated", "high"
		end
	end
	if reason == nil or reason == "state-only" or reason == "margin" then
		return "margin", severity, state == "DANGER" and "ALERT_MARGIN_DANGER_STATE" or "ALERT_MARGIN_WARNING_STATE",
			nil, nil, "detected", "high"
	end
	return nil
end

-- The words of the player's own threshold alerts by role (SPEC-09 Q7, the owner's decision of 2026-11-26): the damage
-- dealer and the healer are told to ease off at WARNING and to stop damage or healing for a moment at DANGER; a tank
-- (a designated tank that does not hold the mob) is never told to stop, only how close it is.
local OWN_WARNING = { dps = "ALERT_WARNING", healer = "ALERT_WARNING", tank = "ALERT_WARNING_TANK" }
local OWN_DANGER = { dps = "ALERT_DANGER", healer = "ALERT_DANGER_HEALER", tank = "ALERT_DANGER_TANK" }

-- The role of the player's row, as the Coach reads it (Data/Coach.lua, SPEC-04 §2.1).
local function roleOf(row)
	if row.isTank or row.record.role == "TANK" then return "tank" end
	if row.record.role == "HEALER" then return "healer" end
	return "dps"
end

-- The player not holding the mob (`warning`, `danger`).
local function ownAlert(row, state, reason)
	if state == "DANGER" then
		local p = percent(row)
		if reason ~= nil or not p then return nil end   -- aggro, lost-aggro: AGGRO_CHANGED speaks for them
		return "danger", 2, OWN_DANGER[roleOf(row)], nil, p, "detected", "high"
	end
	if reason == nil then
		local p = percent(row)
		if not p then return nil end
		return "warning", 1, OWN_WARNING[roleOf(row)], nil, p, "detected", "high"
	end
	if reason == "predicted" then
		local t = row.predictedIn
		if not t or not ns.ThreatCalc.Trusted(row.trendConfidence) then return nil end
		return "warning", 1, "ALERT_WARNING_PREDICTED", nil, ceil(t - EPSILON), "predicted", row.trendConfidence
	end
	if reason == "state-only" then
		return "warning", 1, "ALERT_WARNING_STATE", nil, nil, "detected", "high"
	end
	return nil
end

-- One transition, one alert (SPEC-04 §1.2): nothing for a unit whose holder change already spoke in this update with a
-- severity at least as high, nor about the second the tank's own Danger margin alert of this update is about.
local function raiseIf(row, mobKey, reason, kind, severity, message, otherKey, number, category, confidence)
	if not kind then return end
	local unitKey, now = row.record.unitKey, Compat.Now()
	if unitKey == aggroUnit and severity <= aggroSeverity and now == aggroAt then return end
	if kind == "other" and unitKey == marginSecond and now == marginAt then return end
	local alert = raise(kind, severity, row, mobKey, message, reason, otherKey, number, category, confidence)
	if alert and kind == "margin" and severity >= 2 then
		local second = secondRow(row)   -- the player's row is the first, so this comes before the second's own change
		marginSecond, marginAt = second and second.record.unitKey or nil, now
	end
end

local function onStateChanged(unitKey, mobKey, old, new)
	if not on() or unitKey == nil or not listening(mobKey) then return end
	if not entered(unitKey, mobKey, old, new) then return end
	local row = rowOfKey(unitKey)
	if not row then return end
	local subject, reason = subjectOf(row), row.stateReason
	if reason == "aggro" or reason == "lost-aggro" then return end
	if subject == "self" then
		if row.isTank and row.isHolder then
			raiseIf(row, mobKey, reason, marginAlert(row, mobKey, new, reason))
		elseif not row.isHolder then
			raiseIf(row, mobKey, reason, ownAlert(row, new, reason))
		end
	elseif subject == "other" and new == "DANGER" and reason == nil and not row.isTank
		and row.record.role ~= "TANK" then
		raiseIf(row, mobKey, reason, "other", 2, "ALERT_OTHER_DANGER", unitKey, nil, "detected", "high")
	end
end

---------------------------------------------------------------------------------------------------------------------
-- AGGRO_CHANGED: the unit holding the mob changed
---------------------------------------------------------------------------------------------------------------------
local function onAggroChanged(mobKey, unitKey, oldUnitKey)
	if not on() or not listening(mobKey) then return end
	local row = rowOfKey(unitKey)
	if not row then return end
	local old = rowOfKey(oldUnitKey)
	local me = playerRow()
	local designated = ns.ThreatState and ns.ThreatState.designated or 0
	local role = row.record.role
	local subject = subjectOf(row)

	-- the player first: one change, one alert, the most severe one
	local own, kind, message, otherKey = nil, nil, nil, nil
	if subject == "self" then
		-- not a designated tank; with no designated tank at all, only when the own pet held the mob
		if role ~= "TANK" and (designated > 0 or (old ~= nil and subjectOf(old) == "pet")) then
			own, kind, message = row, "aggro", "ALERT_AGGRO"
		end
	elseif me and old == me and me.record.role == "TANK" and role ~= "TANK" then
		own, kind, message, otherKey = me, "lost", "ALERT_LOST", unitKey
	end
	if own then
		aggroUnit, aggroAt, aggroSeverity = own.record.unitKey, Compat.Now(), 3
		raise(kind, 3, own, mobKey, message, kind == "lost" and "lost-aggro" or "aggro", otherKey, nil, "detected", "high")
		return
	end
	if subject == "pet" then
		if designated > 0 then
			raise("pet", 2, row, mobKey, "ALERT_PET", "aggro", nil, nil, "detected", "high")
		end
	elseif subject == "other" and role ~= "TANK" and old ~= nil and old.record.role == "TANK" then
		raise("other", 3, row, mobKey, "ALERT_OTHER_AGGRO", "aggro", unitKey, nil, "detected", "high")
	end
end

---------------------------------------------------------------------------------------------------------------------
-- MOBS_UPDATED: the other mobs (SPEC-07 §2.5, M7.4)
---------------------------------------------------------------------------------------------------------------------
-- The conditions of a mob, the higher the worse: only a rise is an entry, and only the ones with a message speak.
local SELF_LEVEL = { SAFE = 0, WARNING = 1, DANGER = 2 }
local MOB_RANK = { aggro = 4, close = 3, ["no-tank"] = 2 }

local function rankOf(entry)
	if entry.state == "DANGER" then return entry.reason == "aggro" and MOB_RANK.aggro or MOB_RANK.close end
	if entry.state == "WARNING" then return entry.reason == "no-tank" and MOB_RANK["no-tank"] or 1 end
	return 0
end

-- The player is a tank: the TANK role (the scanner's record: the player may be on no list), or the monitored mob's.
local function playerTanks()
	local Scanner = ns.ThreatScanner
	local me = Scanner and Scanner.RecordOf and Scanner.RecordOf("player")
	if me and me.role == "TANK" then return true end
	return ns.ThreatModel ~= nil and playerIsTank()
end

-- Alerts about other mobs found in one update, kept until all mobs are looked at so that the worst speaks first (the
-- gap between alerts about others lets one through). Pooled, made once each.
local found, foundCount = {}, 0

local function add(message, severity, subject, unitKey, otherKey, mobKey, reason, category)
	foundCount = foundCount + 1
	local f = found[foundCount]
	if not f then
		f = {}
		found[foundCount] = f
	end
	f.message, f.severity, f.subject, f.unitKey, f.otherKey = message, severity, subject, unitKey, otherKey
	f.mobKey, f.reason, f.category = mobKey, reason, category
end

-- The alert of one mob, if any: first about the player, else about the mob (never both, SPEC-04 §1.2).
local function judge(entry, mobRose, selfRose)
	local key, holder = entry.key, entry.holder
	if selfRose and entry.selfRec and not playerTanks()
		and not (entry.designated == 0 and holder and holder.unitToken == "player") then
		add("ALERT_MOB_SELF", 2, "self", entry.selfRec.unitKey, false, key, "self", "detected")
		return
	end
	if not mobRose then return end
	local others = settings.others
	if others == "never" or (others ~= "always" and not playerTanks()) then return end
	local rank = rankOf(entry)
	if rank == MOB_RANK.aggro then
		-- about the player: the alert about oneself speaks (or the player is a tank)
		if not holder or holder.unitToken == "player" or excluded[holder.unitKey] then return end
		local subject = holder.unitToken == "pet" and "pet" or "other"
		if subject == "pet" and not settings.pet then return end
		add("ALERT_MOB_AGGRO", 3, subject, holder.unitKey, holder.unitKey, key, "aggro", "detected")
	elseif rank == MOB_RANK.close then
		local top = entry.top
		if top and (top.unitToken == "player" or top.role == "TANK" or excluded[top.unitKey]) then return end
		local subject = top and top.unitToken == "pet" and "pet" or "other"
		add("ALERT_MOB_CLOSE", 2, subject, top and top.unitKey or "", top and top.unitKey or false, key, "close",
			"detected")
	elseif rank == MOB_RANK["no-tank"] then
		add("ALERT_MOB_NO_TANK", 1, "other", "", false, key, "no-tank", "calculated")
	end
end

-- Drops the cooldowns of mobs that no alert can wait for any more, once many of them are kept (a long fight).
local function pruneMobs(now)
	if mobCooldowns <= Alerts.MOB_PRUNE_AT then return end
	local times, oldest, n = cooldowns.mob, now - Config.ALERTS.cooldown.max, 0
	for key, at in pairs(times) do
		if at < oldest then times[key] = nil else n = n + 1 end
	end
	mobCooldowns = n
end

local function raiseMob(f)
	local now, stats, times = Compat.Now(), Alerts.stats, cooldowns.mob
	local last = times[f.mobKey]
	if last and now - last < settings.cooldown - EPSILON then
		stats.cooled = stats.cooled + 1
		return
	end
	if f.subject ~= "self" then
		if now - lastOtherAt < Alerts.OTHER_GAP - EPSILON then
			stats.dropped = stats.dropped + 1
			return
		end
		lastOtherAt = now
	end
	if not last then mobCooldowns = mobCooldowns + 1 end
	times[f.mobKey] = now
	pruneMobs(now)
	deliver("mob", f.severity, f.subject, f.unitKey, f.otherKey, f.mobKey, f.message, f.reason, nil, f.category, "high",
		now)
end

-- The order the alerts of one update are raised in: a mob on someone, the player's own, then the others by severity.
local PASSES = {
	function(f) return f.severity == 3 end,
	function(f) return f.subject == "self" end,
	function(f) return f.severity == 2 and f.subject ~= "self" end,
	function(f) return f.severity == 1 end,
}

local function forgetMobs()
	for key in pairs(mobRank) do mobRank[key], mobSelf[key] = nil, nil end
end

-- After each tick of the tracker: what each mob now shows against what was last known of it.
local function onMobsUpdated()
	if not on() or not multiOn() or not RealMobs then return end
	if ns.Demo and ns.Demo.IsActive() then return end
	for key in pairs(mobRank) do
		if not RealMobs.Get(key) then mobRank[key], mobSelf[key] = nil, nil end   -- the mob left for good
	end
	local Scanner = ns.ThreatScanner
	if not (Scanner and Scanner.inCombat == true) then return end
	local speak = settings.enabled and not onlyTarget()
	local list, n = RealMobs.List()
	foundCount = 0
	for i = 1, n do
		local entry = list[i]
		local state, key = entry.state, entry.key
		-- a mob that cannot be read now may still show its last state for a moment (the dwell): nothing is learnt from it
		if key and state and state ~= "UNKNOWN" and entry.mode ~= "none" then
			local rank, before = rankOf(entry), mobRank[key] or 0
			local mine = entry.selfState
			local level, knownSelf = SELF_LEVEL[mine], mobSelf[key] or 0
			if mine == nil then level = 0 elseif level == nil then level = knownSelf end   -- UNKNOWN: what was known
			mobRank[key], mobSelf[key] = rank, level
			if speak and not entry.monitored then
				judge(entry, rank > before, level == SELF_LEVEL.DANGER and knownSelf < level)
			end
		end
	end
	for p = 1, #PASSES do
		local pass = PASSES[p]
		for i = 1, foundCount do
			local f = found[i]
			if f.message and pass(f) then
				raiseMob(f)
				f.message = nil
			end
		end
	end
end

---------------------------------------------------------------------------------------------------------------------
-- The text of an alert (UI/CoachStrip.lua)
---------------------------------------------------------------------------------------------------------------------
-- The reason of each message (SPEC-04 §3.1: on which data it rests, never a cause, WR-03).
Alerts.REASONS = {
	ALERT_WARNING = "ALERT_WHY_P_WARNING", ALERT_WARNING_TANK = "ALERT_WHY_P_WARNING",
	ALERT_WARNING_PREDICTED = "ALERT_WHY_PREDICTED", ALERT_WARNING_STATE = "ALERT_WHY_STATE",
	ALERT_DANGER = "ALERT_WHY_P_DANGER", ALERT_DANGER_HEALER = "ALERT_WHY_P_DANGER",
	ALERT_DANGER_TANK = "ALERT_WHY_P_DANGER",
	ALERT_AGGRO = "ALERT_WHY_TOP",
	ALERT_MARGIN_WARNING = "ALERT_WHY_MARGIN_WARNING", ALERT_MARGIN_WARNING_STATE = "ALERT_WHY_STATE",
	ALERT_MARGIN_DANGER = "ALERT_WHY_MARGIN_DANGER", ALERT_MARGIN_DANGER_STATE = "ALERT_WHY_STATE",
	ALERT_BEHIND = "ALERT_WHY_BEHIND", ALERT_LOST = "ALERT_WHY_HOLDER", ALERT_PET = "ALERT_WHY_PET",
	ALERT_OTHER_DANGER = "ALERT_WHY_OTHER_DANGER", ALERT_OTHER_AGGRO = "ALERT_WHY_HOLDER",
	ALERT_MOB_AGGRO = "ALERT_WHY_HOLDER", ALERT_MOB_CLOSE = "ALERT_WHY_MOB",
	ALERT_MOB_NO_TANK = "ALERT_WHY_MOB_NO_TANK", ALERT_MOB_SELF = "ALERT_WHY_MOB",
}
local REASON_AT_WARNING = { ALERT_WHY_P_WARNING = true, ALERT_WHY_MARGIN_WARNING = true }
local REASON_AT_DANGER = { ALERT_WHY_P_DANGER = true, ALERT_WHY_MARGIN_DANGER = true, ALERT_WHY_OTHER_DANGER = true }

local function defaultName(unitKey)
	local row = rowOfKey(unitKey)
	return row and row.record.unitName or nil
end

-- The message and the reason of an alert in the active language. nameOf(unitKey) gives the name of the `%s` (default:
-- the name the scanner read for that row; "Unknown" when there is none).
function Alerts.Text(alert, nameOf)
	if not alert or not alert.message or alert.message == "" then return nil end
	local L = ns.L
	local name = alert.otherKey and (nameOf or defaultName)(alert.otherKey) or nil
	if type(name) ~= "string" or name == "" then name = L.WHY_UNKNOWN end
	local message
	if alert.otherKey or NAMED[alert.message] then
		message = L[alert.message]:format(name, alert.args[1])
	else
		message = L[alert.message]:format(alert.args[1])
	end
	local key = Alerts.REASONS[alert.message]
	local reason = L[key]
	if REASON_AT_WARNING[key] or REASON_AT_DANGER[key] then
		local warning, danger = ns.ThreatState.Thresholds()
		reason = reason:format(REASON_AT_WARNING[key] and warning or danger)
	elseif key == "ALERT_WHY_PREDICTED" then
		reason = reason:format(L["CONF_" .. tostring(alert.confidence):upper()] or L.WHY_UNKNOWN)
	elseif key == "ALERT_WHY_HOLDER" then
		reason = reason:format(name)
	end
	return message, reason
end

---------------------------------------------------------------------------------------------------------------------
-- The end of a fight, the demo, the settings
---------------------------------------------------------------------------------------------------------------------
-- Drops what can no longer matter once many units have been seen (a long session of groups).
local function prune()
	if knownCount > Alerts.PRUNE_AT then
		known, knownCount, knownMob = {}, 0, nil
	end
	local oldest = Compat.Now() - Config.ALERTS.cooldown.max
	for _, kind in ipairs(Alerts.KINDS) do
		local times, n = cooldowns[kind], 0
		for _ in pairs(times) do n = n + 1 end
		if n > Alerts.PRUNE_AT then
			for unitKey, at in pairs(times) do
				if at < oldest then times[unitKey] = nil end
			end
		end
	end
	mobCooldowns = 0
	for _ in pairs(cooldowns.mob) do mobCooldowns = mobCooldowns + 1 end
end

local function restart()
	forgetKnown()
	forgetMobs()
	knownMob, aggroUnit, marginSecond = nil, nil, nil
end

local function onCombatEnded()
	if not on() then return end
	restart()
	prune()
	setMuted(false)   -- the mute lasts until the end of this fight, or of the next one
end

-- The invented fight starts or ends: nothing of the other one is remembered.
local function onDemoChanged()
	if not on() then return end
	restart()
	lastOtherAt = -math.huge
end

---------------------------------------------------------------------------------------------------------------------
-- /atw debug (SPEC-04 §5): switches, settings, counters and the two game APIs; never a name
---------------------------------------------------------------------------------------------------------------------
local function yesNo(v) return v and "yes" or "no" end

function Alerts.DebugLines()
	local Features = ns.Features
	local lines = {
		("switches: alerts %s, coach %s"):format(on() and "on" or "off",
			(Features and Features.On("coach")) and "on" or "off"),
		("settings: enabled %s, window %s, visual %s, sound %s, cooldown %d s, others %s, pet %s"):format(
			yesNo(settings.enabled), yesNo(settings.window), yesNo(settings.visual), yesNo(settings.sound),
			settings.cooldown, settings.others, yesNo(settings.pet)),
		("mute: %s, %d unit(s) excluded, scanner wanted: %s"):format(muted and "on" or "off", excludedCount,
			yesNo(wantsScanner)),
	}
	if multiOn() then
		lines[#lines + 1] = ("other mobs: only target %s, tracker wanted: %s"):format(yesNo(settings.onlyTarget),
			yesNo(wantsMobs))
	end
	local stats, counts = Alerts.stats, {}
	for _, kind in ipairs(Alerts.KINDS) do
		if kind ~= "mob" or multiOn() then counts[#counts + 1] = kind .. " " .. stats.raised[kind] end
	end
	lines[#lines + 1] = "raised: " .. concat(counts, ", ")
	lines[#lines + 1] = ("in cooldown %d, dropped %d, muted %d"):format(stats.cooled, stats.dropped, stats.muted)
	lines[#lines + 1] = "last alert: " .. (stats.lastAt and ("%.1f s ago"):format(Compat.Now() - stats.lastAt) or "none")
	local state, detail = Compat.ApiState("ui.PlaySound")
	lines[#lines + 1] = ("ui.PlaySound: %s%s, %d sound(s), %d failed%s"):format(tostring(state),
		detail and (" (" .. detail .. ")") or "", stats.sounds, stats.soundFailed,
		stats.soundReason and (" (" .. stats.soundReason .. ")") or "")
	local warn = Compat.api and Compat.api["threat.WarningEnabled"]
	lines[#lines + 1] = ("threat.WarningEnabled: %s%s"):format(tostring(warn and warn.state or "unknown"),
		warn and warn.value and (" = " .. warn.value) or "")
	if ns.Coach then   -- the Coach's part (Data/Coach.lua, loaded after this file)
		for _, line in ipairs(ns.Coach.DebugLines()) do lines[#lines + 1] = line end
	end
	return lines
end

-- The `mob` alerts raised, for the *Mobs* section of /atw debug (SPEC-07 §2.6).
function Alerts.MobDebugLine()
	return ("alerts about other mobs: %s, %d raised"):format((on() and not onlyTarget()) and "on" or "off",
		Alerts.stats.raised.mob)
end

if ns.Bus then
	local Bus = ns.Bus
	Bus.On("MOBS_UPDATED", onMobsUpdated)
	Bus.On("STATE_CHANGED", onStateChanged)
	Bus.On("AGGRO_CHANGED", onAggroChanged)
	Bus.On("COMBAT_ENDED", onCombatEnded)
	Bus.On("DEMO_CHANGED", onDemoChanged)
	Bus.On("CONFIG_LOADED", function()
		readSettings()
		refreshConsumer()
	end)
	Bus.On("CONFIG_CHANGED", function(path)
		if type(path) ~= "string" or path:sub(1, #PREFIX) ~= PREFIX then return end
		readSettings()
		refreshConsumer()
	end)
end

if ns.addon then
	ns.addon.Alerts = Alerts
	ns.addon:AddDebugSection("Alerts and Coach", Alerts.DebugLines)
end
