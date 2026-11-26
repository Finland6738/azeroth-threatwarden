-- Coach: the Threat Coach, one tip at a time with its reason, category and confidence (SPEC-04 §2, §4.1, §5;
-- COA-01-COA-05; ADR 0003, 0014). Lua 5.1, no game API but the clock through Compat. Threatwarden's own.
--
-- Evaluated after every THREAT_UPDATED (Coach comes after Data/ThreatState.lua in the TOC, so the states, the tank and
-- the holder of that update are already known; the STATE_CHANGED and AGGRO_CHANGED of an update arrive while the
-- states are still being written, so the Coach does not decide on them), and at COMBAT_ENDED, DEMO_CHANGED and the
-- change of `settings.coach.enabled`. Only while the `coach` switch is on (ADR 0014), the setting is on, in combat
-- (the scanner's own flag) with a monitored mob, with the player on its threat list and someone else on it too
-- (alone with your own mob there is nothing to advise); otherwise no tip.
--
-- The rules of the player's Coach role (Data/CoachRules.lua) are asked in order of priority: the first that holds and
-- is not waiting for its cooldown is the tip. A rule with a cooldown that leaves the strip does not come back before
-- its cooldown (COA-03). When no rule holds, A1 (Not enough data for advice) says why when the data does not allow a
-- tip; when the data is there, there is no tip (the strip stays empty, SPEC-04 §3.1), also while the rule that holds
-- waits for its cooldown. A rule interrupted by a higher fact without a cooldown (aggro, Danger, a tank behind or
-- lost) keeps no cooldown: back from Danger to Warning, the Warning tip comes back at once. Turning the Coach off in
-- the settings forgets the cooldowns. With the same rule the numbers
-- of the text change at most once a second (NUMBERS_EVERY); a change of rule or of key is shown at once.
--
-- COACH_TIP(tip) when the tip changes; COACH_TIP(nil) when there is none any more. `tip` is one reused table (a
-- listener that keeps it copies it):
--   { rule (T1-T7, D1-D5, A1), name, role, message, reason (locale keys), args, nargs, reasonArgs, nreason (numbers of
--     the message and of the reason), otherKey (the unit of the `%s`, or false), category, confidence (false for A1),
--     priority, since, mobKey, demo }
-- Never a name, never a secret value: the rows hold none (SPEC-01 §3.3). Coach.Text formats a tip for the strip
-- (M3.4). Allocation-free per update after the warm-up (ARC-06).
local ADDON_NAME, ns = ...
ns = ns or {}
ns.modules = ns.modules or {}

local Coach = {}
ns.Coach, ns.modules.Coach = Coach, Coach

local type, pairs, ipairs, floor = type, pairs, ipairs, math.floor

Coach.NUMBERS_EVERY = 1   -- seconds between two changes of the numbers of the same rule
local EPSILON = 1e-9
local ENABLED_PATH = "account.settings.coach.enabled"

local Rules, Compat, Config = ns.CoachRules, ns.Compat, ns.Config

local enabled = Config.COACH_DEFAULTS.enabled

local function newTip()
	return { rule = false, name = false, role = false, message = false, reason = false, args = { 0, 0, 0 }, nargs = 0,
		reasonArgs = { 0, 0, 0 }, nreason = 0, otherKey = false, category = false, confidence = false, priority = 0,
		since = 0, mobKey = false, demo = false }
end

local tip = newTip()          -- the tip shown (emitted)
local cand = newTip()         -- the candidate of an evaluation
local shown = nil             -- the id of the rule shown, nil: no tip
local numbersAt = 0           -- when the numbers of the shown tip last changed
local leftAt = {}             -- rule id -> when it last left the strip
for id in pairs(Rules.BY_ID) do leftAt[id] = -math.huge end

local ctx = { me = nil, role = "dps", holder = nil, second = nil, others = 0, warning = 0, danger = 0 }

Coach.stats = { tips = 0, cleared = 0, evaluations = 0, rules = {} }
for id in pairs(Rules.BY_ID) do Coach.stats.rules[id] = 0 end

local function on()
	return ns.Features ~= nil and ns.Features.On("coach")
end

local function emit(event, ...)
	if ns.Bus then ns.Bus.Emit(event, ...) end
end

local function readSettings()
	local value = Config.Get and Config:Get(ENABLED_PATH)
	if type(value) ~= "boolean" then value = Config.COACH_DEFAULTS.enabled end
	enabled = value
end

function Coach.Enabled() return enabled end

-- The tip shown now, or nil.
function Coach.Current()
	if shown == nil then return nil end
	return tip
end

---------------------------------------------------------------------------------------------------------------------
-- The context of an evaluation
---------------------------------------------------------------------------------------------------------------------
-- The Coach role of the player's row (SPEC-04 §2.1): the tank rules for a row treated as a tank, the healer's words for
-- the HEALER role, the damage dealer's for every other (DAMAGER, NONE, or a role that cannot be read [probe P9]).
local function roleOf(me)
	if me.isTank then return "tank" end
	if me.record.role == "HEALER" then return "healer" end
	return "dps"
end

-- Fills ctx; false when there is nothing to advise (no player row, no one else on the list).
local function fillContext()
	local Model, State = ns.ThreatModel, ns.ThreatState
	local me = State.self
	if not me or not me.present or not me.record then return false end
	local holder = State.tank
	local first = holder or me
	local others, second, best = 0, nil, nil
	for i = 1, Model.count do
		local row = Model.rows[i]
		if row ~= me and row.present then others = others + 1 end
		if row ~= first and row.present and not row.stale and row.record.mode == "values" then
			local p = row.record.scaledPercent
			if type(p) == "number" and (best == nil or p > best) then second, best = row, p end
		end
	end
	if others == 0 then return false end
	ctx.me, ctx.role, ctx.holder, ctx.second, ctx.others = me, roleOf(me), holder, second, others
	ctx.warning, ctx.danger = State.Thresholds()
	return true
end

---------------------------------------------------------------------------------------------------------------------
-- Choosing the tip
---------------------------------------------------------------------------------------------------------------------
local function eligible(rule, now)
	if rule.id == shown or rule.cooldown <= 0 then return true end
	return now - leftAt[rule.id] >= rule.cooldown - EPSILON
end

-- The first rule that holds and is not waiting for its cooldown; A1 only when no rule holds at all (a rule that holds
-- but waits means the data is there: no tip, SPEC-04 §2.3).
local function pick(now)
	local list = Rules.For(ctx.role)
	local waiting = false
	for i = 1, #list do
		local rule = list[i]
		if rule.test(ctx, cand) then
			if eligible(rule, now) then return rule end
			waiting = true
		end
	end
	if not waiting and Rules.A1.test(ctx, cand) then return Rules.A1 end
	return nil
end


local function sameNumbers(a, b)
	if a.nargs ~= b.nargs or a.nreason ~= b.nreason or a.otherKey ~= b.otherKey or a.confidence ~= b.confidence then
		return false
	end
	for i = 1, a.nargs do if a.args[i] ~= b.args[i] then return false end end
	for i = 1, a.nreason do if a.reasonArgs[i] ~= b.reasonArgs[i] then return false end end
	return true
end

local function copyCandidate()
	tip.message, tip.reason, tip.otherKey = cand.message, cand.reason, cand.otherKey
	tip.category, tip.confidence = cand.category, cand.confidence
	tip.nargs, tip.nreason = cand.nargs, cand.nreason
	for i = 1, 3 do
		tip.args[i] = i <= cand.nargs and cand.args[i] or 0
		tip.reasonArgs[i] = i <= cand.nreason and cand.reasonArgs[i] or 0
	end
end

-- No tip any more: the rule shown leaves the strip (its cooldown starts) and COACH_TIP(nil) says so once.
local function clear(now)
	if shown == nil then return end
	leftAt[shown] = now or Compat.Now()
	shown = nil
	Coach.stats.cleared = Coach.stats.cleared + 1
	emit("COACH_TIP", nil)
end

local function show(rule, now)
	local mobKey = ns.ThreatModel.mobKey
	local demo = ns.Demo ~= nil and ns.Demo.IsActive() or false
	if rule.id ~= shown then
		-- a rule interrupted by a fact of higher priority without a cooldown (aggro, Danger, a tank behind or lost) did
		-- not end: it keeps no cooldown
		if shown ~= nil and not (rule.priority > tip.priority and rule.cooldown <= 0) then leftAt[shown] = now end
		shown = rule.id
		copyCandidate()
		tip.rule, tip.name, tip.priority, tip.since = rule.id, rule.name, rule.priority, now
		tip.role, tip.mobKey, tip.demo = ctx.role, mobKey, demo
		numbersAt = now
		Coach.stats.rules[rule.id] = Coach.stats.rules[rule.id] + 1
	elseif cand.message ~= tip.message or cand.reason ~= tip.reason or ctx.role ~= tip.role or mobKey ~= tip.mobKey then
		copyCandidate()       -- another form or another role of the same rule: at once
		tip.role, tip.mobKey, tip.demo = ctx.role, mobKey, demo
		numbersAt = now
	elseif sameNumbers(cand, tip) or now - numbersAt < Coach.NUMBERS_EVERY - EPSILON then
		return                -- nothing new, or the numbers changed less than a second ago (the text does not tremble)
	else
		copyCandidate()
		numbersAt = now
	end
	Coach.stats.tips = Coach.stats.tips + 1
	emit("COACH_TIP", tip)
end

-- Everything starts again: no tip and no cooldown (the demo, the Coach turned off in the settings).
local function restart()
	clear(Compat.Now())
	for id in pairs(leftAt) do leftAt[id] = -math.huge end
end

-- One evaluation (SPEC-04 §2.3): at most a few comparisons per rule, nothing allocated.
function Coach.Evaluate()
	if not on() then return nil end
	local now = Compat.Now()
	local Scanner, Model = ns.ThreatScanner, ns.ThreatModel
	if not enabled then
		restart()
		return nil
	end
	if not (Scanner and Scanner.inCombat == true) or not Model or Model.mobKey == nil
		or not ns.ThreatState or not fillContext() then
		clear(now)
		return nil
	end
	Coach.stats.evaluations = Coach.stats.evaluations + 1
	local rule = pick(now)
	if not rule then
		clear(now)
		return nil
	end
	show(rule, now)
	return tip
end

---------------------------------------------------------------------------------------------------------------------
-- The text of a tip (UI/CoachStrip.lua, M3.4)
---------------------------------------------------------------------------------------------------------------------
local function defaultName(unitKey)
	local Model = ns.ThreatModel
	for i = 1, Model.count do
		local rec = Model.rows[i].record
		if rec and rec.unitKey == unitKey then return rec.unitName end
	end
	return nil
end

local function format(L, key, t, numbers, count, name)
	local spec, values, n = Rules.KEYS[key] or "", {}, 0
	for i = 1, #spec do
		local kind = spec:sub(i, i)
		if kind == "s" then
			values[i] = name
		elseif kind == "c" then
			values[i] = L["CONF_" .. tostring(t.confidence):upper()] or L.WHY_UNKNOWN
		else
			n = n + 1
			values[i] = n <= count and numbers[n] or 0
		end
	end
	return L[key]:format(unpack(values, 1, #spec))
end

-- The message and the reason of a tip in the active language. nameOf(unitKey) gives the name of the `%s` (default:
-- the name the scanner read for that row; "Unknown" when there is none).
function Coach.Text(t, nameOf)
	if not t or not t.message then return nil end
	local L = ns.L
	local name = t.otherKey and (nameOf or defaultName)(t.otherKey) or nil
	if type(name) ~= "string" or name == "" then name = L.WHY_UNKNOWN end
	return format(L, t.message, t, t.args, t.nargs, name), format(L, t.reason, t, t.reasonArgs, t.nreason, name)
end

---------------------------------------------------------------------------------------------------------------------
-- The end of a fight, the demo, the settings, /atw debug
---------------------------------------------------------------------------------------------------------------------
-- Lines for the "Alerts and Coach" section of /atw debug (Data/Alerts.lua): never a name.
function Coach.DebugLines()
	local stats = Coach.stats
	local counts = {}
	for _, list in ipairs({ Rules.TANK, Rules.OTHER, { Rules.A1 } }) do
		for _, rule in ipairs(list) do counts[#counts + 1] = rule.id .. " " .. stats.rules[rule.id] end
	end
	return {
		("coach: enabled %s, tip %s, %d tip(s), %d cleared, %d evaluation(s)"):format(enabled and "yes" or "no",
			shown and (shown .. " " .. tip.name .. " (" .. tostring(tip.role) .. ")") or "none", stats.tips,
			stats.cleared, stats.evaluations),
		"coach rules shown: " .. table.concat(counts, ", "),
	}
end

if ns.Bus then
	local Bus = ns.Bus
	Bus.On("THREAT_UPDATED", function() Coach.Evaluate() end)
	Bus.On("COMBAT_ENDED", function()
		if on() then clear(Compat.Now()) end
	end)
	Bus.On("DEMO_CHANGED", function()
		if on() then restart() end
	end)
	Bus.On("CONFIG_LOADED", readSettings)
	Bus.On("CONFIG_CHANGED", function(path)
		if path ~= ENABLED_PATH then return end
		readSettings()
		if on() then Coach.Evaluate() end
	end)
end

if ns.addon then ns.addon.Coach = Coach end
