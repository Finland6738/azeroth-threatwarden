-- CoachRules: the rule table of the Threat Coach (SPEC-04 §2.1-§2.2, §2.5; COA-01-COA-05; ADR 0003). Lua 5.1, no game
-- API and no state: Data/Coach.lua fills a context from the rows of Data/ThreatModel.lua and Data/ThreatState.lua and
-- asks the rules of the player's role, in order of priority. Threatwarden's own.
--
-- A rule is { id, name, priority, cooldown (seconds), base (the category it rests on), test(c, out) }. test returns
-- true when the rule holds and then fills `out` (the candidate tip, reused):
--   out.message, out.reason   locale keys (the reason says on what data the tip rests, never a cause, WR-03)
--   out.otherKey              the unitKey of the `%s` name of the keys, or false
--   out.args, out.nargs       the numbers of the message; out.reasonArgs, out.nreason those of the reason
--   out.category, out.confidence   ADR 0003: detected, calculated, estimated, predicted; high, medium (false for A1)
-- The context `c`: c.me (the player's row, on the list), c.role ("tank", "healer", "dps"), c.holder (the row holding
-- the mob, nil: Unknown tank), c.second (the fresh `values` row with the highest scaled % after the holder, or nil),
-- c.others (other rows on the list), c.warning, c.danger (the thresholds in use).
--
-- Every value a rule needs must be known: a rule whose number is missing does not hold (DAT-02, never invented). The
-- rules read only the rows' states (already cleaned by hysteresis and dwell, MON-10, MON-12) and their known numbers;
-- a prediction (D3, T4) holds only with a trend of medium or high confidence (COA-02, WR-01).
--
-- CoachRules.KEYS gives, for every key a tip can carry, the arguments of its text in order: "s" a unit's name (the
-- otherKey), "d" a whole number, "f" a number with one decimal, "c" the confidence word (CONF_*). Data/Coach.lua formats
-- with it and Tests/test_coach_wording.lua checks every language against it.
local ADDON_NAME, ns = ...
ns = ns or {}
ns.modules = ns.modules or {}

local CoachRules = {}
ns.CoachRules, ns.modules.CoachRules = CoachRules, CoachRules

local type, floor, ceil = type, math.floor, math.ceil

CoachRules.RISING = 2   -- points per second beyond which the trend is "rising" (the arrow of the list, ThreatCalc.ARROW)

CoachRules.KEYS = {
	-- messages
	COACH_TANK_LOST = "s", COACH_TANK_BEHIND = "", COACH_TANK_DANGER = "s", COACH_TANK_DANGER_STATE = "",
	COACH_TANK_OVERTAKE = "sd", COACH_TANK_WARNING = "", COACH_TANK_OTHER = "", COACH_TANK_SAFE = "",
	COACH_AGGRO = "", COACH_AGGRO_HEALER = "", COACH_DANGER = "", COACH_DANGER_HEALER = "", COACH_RISING = "",
	COACH_RISING_HEALER = "", COACH_WARNING = "", COACH_WARNING_STATE = "", COACH_SAFE = "", COACH_SAFE_STATE = "",
	COACH_INSUFFICIENT = "",
	-- reasons
	COACH_WHY_HOLDER = "s", COACH_WHY_BEHIND = "", COACH_WHY_SECOND = "sdd", COACH_WHY_STATE = "",
	COACH_WHY_TREND_OTHER = "fc", COACH_WHY_SECOND_W = "sdd", COACH_WHY_HOLDER_TANK = "s", COACH_WHY_MARGIN = "dd",
	COACH_WHY_LEAD = "", COACH_WHY_TOP = "", COACH_WHY_P_DANGER = "dd", COACH_WHY_TREND = "ddc",
	COACH_WHY_P_WARNING = "dd", COACH_WHY_P_SAFE = "dc", COACH_WHY_UNKNOWN_TANK = "", COACH_WHY_MARGIN_UNKNOWN = "",
	-- the reasons of A1 shared with the list (M2.5)
	WHY_SECRET = "", WHY_MISSING = "", WHY_ERROR = "", WHY_NO_UNIT = "", WHY_STALE_SHORT = "", WHY_INSUFFICIENT = "",
	WHY_LOW_CONFIDENCE = "", WHY_STATE_ONLY = "", WHY_UNKNOWN = "",
}

-- The message keys (the strip shows them; WR-06 limits their length) and the predicted ones (WR-01).
CoachRules.MESSAGES = { "COACH_TANK_LOST", "COACH_TANK_BEHIND", "COACH_TANK_DANGER", "COACH_TANK_DANGER_STATE",
	"COACH_TANK_OVERTAKE", "COACH_TANK_WARNING", "COACH_TANK_OTHER", "COACH_TANK_SAFE", "COACH_AGGRO",
	"COACH_AGGRO_HEALER", "COACH_DANGER", "COACH_DANGER_HEALER", "COACH_RISING", "COACH_RISING_HEALER", "COACH_WARNING",
	"COACH_WARNING_STATE", "COACH_SAFE", "COACH_SAFE_STATE", "COACH_INSUFFICIENT" }
CoachRules.PREDICTED = { COACH_TANK_OVERTAKE = true, COACH_RISING = true, COACH_RISING_HEALER = true,
	COACH_WHY_TREND = true }

-- The reason of an unknown row, a trend or a margin (Data/ThreatModel.lua, Data/ThreatState.lua) as a key of A1.
CoachRules.WHY = {
	secret = "WHY_SECRET", missing = "WHY_MISSING", error = "WHY_ERROR", ["no-unit"] = "WHY_NO_UNIT",
	stale = "WHY_STALE_SHORT", insufficient = "WHY_INSUFFICIENT", ["low-confidence"] = "WHY_LOW_CONFIDENCE",
	["state-only"] = "WHY_STATE_ONLY", ["margin-unknown"] = "COACH_WHY_MARGIN_UNKNOWN",
}

local function trusted(confidence) return ns.ThreatCalc.Trusted(confidence) end

local function whole(v) return floor(v + 0.5) end

-- The scaled % of a fresh `values` row, whole, or nil.
local function percent(row)
	if not row or not row.present or row.stale or row.record.mode ~= "values" then return nil end
	local p = row.record.scaledPercent
	if type(p) ~= "number" then return nil end
	return whole(p)
end

local function fresh(row)
	return row.present and not row.stale and row.record.mode == "values"
end

local function set(out, message, reason, otherKey, category, confidence)
	out.message, out.reason, out.otherKey = message, reason, otherKey or false
	out.category, out.confidence = category, confidence
	out.nargs, out.nreason = 0, 0
	return true
end

local function arg(out, v)
	out.nargs = out.nargs + 1
	out.args[out.nargs] = v
end

local function rarg(out, v)
	out.nreason = out.nreason + 1
	out.reasonArgs[out.nreason] = v
end

local function keyOf(row) return row and row.record and row.record.unitKey or false end

-- The tank's numbers form: its margin is known and the second is a fresh `values` row (SPEC-04 §2.5: with the second
-- in `state`, the state form).
local function numbersForm(c)
	local me = c.me
	return me.stateReason == nil and type(me.margin) == "number" and percent(c.second) ~= nil
end

-- A state of the holding tank read from the game's lead (SPEC-03 §2.3): every holder state that is not plain numbers,
-- not "alone" and not "margin-unknown".
local function leadForm(c)
	local why = c.me.stateReason
	return why == nil or why == "state-only" or why == "margin"
end

local function healer(c, plain, forHealer)
	return c.role == "healer" and forHealer or plain
end

---------------------------------------------------------------------------------------------------------------------
-- The tank (T1-T7)
---------------------------------------------------------------------------------------------------------------------
CoachRules.TANK = {
	{ id = "T1", name = "tank-lost", priority = 100, cooldown = 0, base = "detected",
		test = function(c, out)
			local me = c.me
			if me.state ~= "DANGER" or me.stateReason ~= "lost-aggro" or not c.holder then return false end
			return set(out, "COACH_TANK_LOST", "COACH_WHY_HOLDER", keyOf(c.holder), "detected", "high")
		end },
	{ id = "T2", name = "tank-behind", priority = 90, cooldown = 0, base = "detected",
		test = function(c, out)
			local me = c.me
			if not me.isHolder or me.state ~= "DANGER" or me.stateReason ~= "behind" then return false end
			return set(out, "COACH_TANK_BEHIND", "COACH_WHY_BEHIND", false, "detected", "high")
		end },
	{ id = "T3", name = "tank-danger", priority = 80, cooldown = 0, base = "calculated",
		test = function(c, out)
			local me = c.me
			if not me.isHolder or me.state ~= "DANGER" or not leadForm(c) then return false end
			if numbersForm(c) then
				set(out, "COACH_TANK_DANGER", "COACH_WHY_SECOND", keyOf(c.second), "calculated", "high")
				rarg(out, percent(c.second))
				rarg(out, c.danger)
				return true
			end
			return set(out, "COACH_TANK_DANGER_STATE", "COACH_WHY_STATE", false, "detected", "high")
		end },
	{ id = "T4", name = "tank-overtake", priority = 70, cooldown = 8, base = "predicted",
		test = function(c, out)
			local me, second = c.me, c.second
			if not me.isHolder or not fresh(me) or (me.state ~= "SAFE" and me.state ~= "WARNING") then return false end
			if not second or not fresh(second) then return false end
			local t, trend = second.overtakeIn, second.trend
			if type(t) ~= "number" or type(trend) ~= "number" or trend <= 0 or not trusted(second.trendConfidence) then
				return false
			end
			set(out, "COACH_TANK_OVERTAKE", "COACH_WHY_TREND_OTHER", keyOf(second), "predicted", second.trendConfidence)
			arg(out, ceil(t - 1e-9))
			rarg(out, floor(trend * 10 + 0.5) / 10)
			return true
		end },
	{ id = "T5", name = "tank-warning", priority = 60, cooldown = 8, base = "calculated",
		test = function(c, out)
			local me = c.me
			if not me.isHolder or me.state ~= "WARNING" or not leadForm(c) then return false end
			if numbersForm(c) then
				set(out, "COACH_TANK_WARNING", "COACH_WHY_SECOND_W", keyOf(c.second), "calculated", "high")
				rarg(out, percent(c.second))
				rarg(out, c.warning)
				return true
			end
			return set(out, "COACH_TANK_WARNING", "COACH_WHY_STATE", false, "detected", "high")
		end },
	{ id = "T6", name = "tank-other", priority = 30, cooldown = 8, base = "detected",
		test = function(c, out)
			local me, holder = c.me, c.holder
			if me.record.role ~= "TANK" or me.isHolder or not holder or holder == me or not holder.isTank then
				return false
			end
			return set(out, "COACH_TANK_OTHER", "COACH_WHY_HOLDER_TANK", keyOf(holder), "detected", "high")
		end },
	{ id = "T7", name = "tank-safe", priority = 10, cooldown = 15, base = "calculated",
		test = function(c, out)
			local me = c.me
			if not me.isHolder or me.state ~= "SAFE" or c.others < 1 or not leadForm(c) then return false end
			if numbersForm(c) then
				set(out, "COACH_TANK_SAFE", "COACH_WHY_MARGIN", false, "calculated", "high")
				rarg(out, percent(c.second))
				rarg(out, whole(me.margin))
				return true
			end
			return set(out, "COACH_TANK_SAFE", "COACH_WHY_LEAD", false, "detected", "high")
		end },
}

---------------------------------------------------------------------------------------------------------------------
-- The damage dealer and the healer (D1-D5): the healer has its own words for D1-D3
---------------------------------------------------------------------------------------------------------------------
CoachRules.OTHER = {
	{ id = "D1", name = "aggro", priority = 100, cooldown = 0, base = "detected",
		test = function(c, out)
			local me = c.me
			if me.state ~= "DANGER" or me.stateReason ~= "aggro" then return false end
			return set(out, healer(c, "COACH_AGGRO", "COACH_AGGRO_HEALER"), "COACH_WHY_TOP", false, "detected", "high")
		end },
	{ id = "D2", name = "danger", priority = 90, cooldown = 0, base = "detected",
		test = function(c, out)
			local me = c.me
			local p = percent(me)
			if me.isHolder or me.state ~= "DANGER" or me.stateReason ~= nil or not p then return false end
			set(out, healer(c, "COACH_DANGER", "COACH_DANGER_HEALER"), "COACH_WHY_P_DANGER", false, "detected", "high")
			rarg(out, p)
			rarg(out, c.danger)
			return true
		end },
	{ id = "D3", name = "rising", priority = 80, cooldown = 8, base = "predicted",
		test = function(c, out)
			local me = c.me
			local trend = me.trend
			if me.isHolder or not fresh(me) or type(trend) ~= "number" or trend <= 0
				or not trusted(me.trendConfidence) then
				return false
			end
			-- the predicted Warning of the list (ThreatState) speaks first; else the time to the overtake, when rising
			local reach, t
			if me.stateReason == "predicted" and type(me.predictedIn) == "number" then
				reach, t = c.danger, me.predictedIn
			elseif trend > CoachRules.RISING and type(me.overtakeIn) == "number" then
				reach, t = 100, me.overtakeIn
			else
				return false
			end
			set(out, healer(c, "COACH_RISING", "COACH_RISING_HEALER"), "COACH_WHY_TREND", false, "predicted",
				me.trendConfidence)
			rarg(out, reach)
			rarg(out, ceil(t - 1e-9))
			return true
		end },
	{ id = "D4", name = "warning", priority = 60, cooldown = 8, base = "detected",
		test = function(c, out)
			local me = c.me
			if me.state ~= "WARNING" then return false end
			if me.stateReason == "state-only" then
				return set(out, "COACH_WARNING_STATE", "COACH_WHY_STATE", false, "detected", "high")
			end
			local p = percent(me)
			if me.stateReason ~= nil or not p then return false end
			set(out, "COACH_WARNING", "COACH_WHY_P_WARNING", false, "detected", "high")
			rarg(out, p)
			rarg(out, c.warning)
			return true
		end },
	{ id = "D5", name = "safe", priority = 10, cooldown = 15, base = "estimated",
		test = function(c, out)
			local me = c.me
			if me.state ~= "SAFE" or not c.holder then return false end
			if me.stateReason == "state-only" then
				return set(out, "COACH_SAFE_STATE", "COACH_WHY_STATE", false, "detected", "high")
			end
			local p, trend = percent(me), me.trend
			if me.stateReason ~= nil or not p or type(trend) ~= "number" or trend > CoachRules.RISING
				or not trusted(me.trendConfidence) then
				return false
			end
			set(out, "COACH_SAFE", "COACH_WHY_P_SAFE", false, "estimated", me.trendConfidence)
			rarg(out, p)
			return true
		end },
}

---------------------------------------------------------------------------------------------------------------------
-- A1: not enough data for advice
---------------------------------------------------------------------------------------------------------------------
-- The reason key of A1 when the data does not allow a tip, or nil when the data is there (then no rule holding means
-- there is nothing to say now, or the rule that holds waits for its cooldown: no tip, not "not enough data").
function CoachRules.Insufficient(c)
	local me = c.me
	local rec = me.record
	if me.stale or rec.mode == "none" or me.state == "UNKNOWN" or me.state == nil then
		return CoachRules.WHY[me.stateReason or me.reason or "missing"] or "WHY_UNKNOWN"
	end
	if not c.holder then return "COACH_WHY_UNKNOWN_TANK" end
	if c.role == "tank" then
		if me.isHolder and me.stateReason == "margin-unknown" then return "COACH_WHY_MARGIN_UNKNOWN" end
		return nil
	end
	if rec.mode == "values" and not me.isHolder then
		if me.trend == nil then return CoachRules.WHY[me.trendReason or "insufficient"] or "WHY_INSUFFICIENT" end
		if not trusted(me.trendConfidence) then return "WHY_LOW_CONFIDENCE" end
	end
	return nil
end

CoachRules.A1 = { id = "A1", name = "insufficient", priority = 0, cooldown = 0, base = false,
	test = function(c, out)
		local why = CoachRules.Insufficient(c)
		if not why then return false end
		return set(out, "COACH_INSUFFICIENT", why, false, false, false)
	end }

CoachRules.BY_ID = { A1 = CoachRules.A1 }
for _, list in ipairs({ CoachRules.TANK, CoachRules.OTHER }) do
	for _, rule in ipairs(list) do CoachRules.BY_ID[rule.id] = rule end
end

-- The rules of a Coach role, in order of priority (A1 is asked last, by Data/Coach.lua).
function CoachRules.For(role)
	return role == "tank" and CoachRules.TANK or CoachRules.OTHER
end

if ns.addon then ns.addon.CoachRules = CoachRules end
