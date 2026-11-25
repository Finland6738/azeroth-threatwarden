-- Mock client, part 9: the threat API, with computed, scripted, secret and nil answers (ADR 0010, SPEC-01 §8.3).
--
-- Imitates: UnitDetailedThreatSituation, UnitThreatSituation, UnitThreatPercentageOfLead, UnitThreatLeadSituation,
-- GetThreatStatusColor, IsThreatWarningEnabled and the events UNIT_THREAT_LIST_UPDATE (unit: the mob) and
-- UNIT_THREAT_SITUATION_UPDATE (unit: whose status changed).
-- Dump (../WoW-Addons/docs/api.json, build 70170): system Unit —
--   UnitDetailedThreatSituation(unit, mobGUID: UnitToken) -> isTanking, status, scaledPercentage, rawPercentage,
--   rawThreat; UnitThreatSituation(unit [, mobGUID]) -> number, nilable; UnitThreatPercentageOfLead(unit, mobGUID) and
--   UnitThreatLeadSituation(unit, mobGUID) -> number, nilable; system Threat — GetThreatStatusColor(index) -> r, g, b,
--   IsThreatWarningEnabled() -> bool.
--
-- **The dump gives signatures only.** The numbers below follow the retail documentation of these functions and are
-- assumptions until the M0 probe answers P2-P6: status 3 tanking with the most threat, 2 tanking without it, 1 not
-- tanking with more than the tank, 0 otherwise; raw percentage relative to the tank; scaled percentage against 110 %
-- (130 % for a unit with `ranged = true`), at most 100; "percentage of lead" for the tank, over the second; lead status
-- 3 for whoever does not tank; nil for a unit that is not on the mob's list. A test that depends on one of these says so,
-- or scripts the exact answer. The mock holds **no server rule** about who tanks: the first unit given threat holds the
-- mob, and only Aggro, a death or a removal moves it (the fight script, Tests/lib/fight.lua, says when).
--
-- The state (kept across Mock.Reload), by unit keys of Mock.units:
--   Mock.threat.Set(mob, unit, 1000)            raw threat, or { raw =, scaled =, rawPct =, status =, lead =,
--                                               leadStatus =, tanking = } to fix any returned value
--   Mock.threat.Add(mob, unit, 250)             Mock.threat.Raw(mob, unit)
--   Mock.threat.Aggro(mob, unit)                the mob attacks this unit (it must be on the list)
--   Mock.threat.Holder(mob)                     Mock.threat.Remove(mob, unit)      Mock.threat.Wipe(mob)
--   Mock.threat.silent = true                   no threat event is fired (missed events)
--
-- Scripted answers replace what the state would give, per function and per token pair ("*" matches any):
--   Mock.threat.Answer("UnitThreatSituation", "player", "target", Mock.threat.Returns(1))   until ClearAnswers
--   Mock.threat.Queue("UnitDetailedThreatSituation", Mock.threat.NIL, Mock.threat.ERROR)    one call each, in order
--   Mock.threat.Returns(a, b, ...)   exactly these values          Mock.threat.NIL        one nil
--   Mock.threat.NOTHING              no value at all               Mock.threat.SECRET     every value secret
--   Mock.threat.Error("text")        the call raises                Mock.threat.ERROR      raises "mock error"
--   Mock.threat.calls[name]          how many times a function was called
-- Secrets by prediction and by value: Mock.secrets (05_secrets.lua). With only the values secret, the detailed reading
-- and the percentage of lead are secret and the two states stay readable; with the state secret, everything is [P3].
local Mock = ...
local W = Mock.world

W.threat = W.threat or { mobs = {}, warning = true }
local state = W.threat

local threat = { calls = {} }
Mock.threat = threat

-- Answers ----------------------------------------------------------------------------------------------------------
function threat.Returns(...) return { n = select("#", ...), ... } end
function threat.Error(message) return { error = message or "mock error" } end
threat.NIL = { n = 1 }
threat.NOTHING = { n = 0 }
threat.SECRET = { secret = true }
threat.ERROR = threat.Error()

local answers, queues = {}, {}

local KINDS = {
	UnitDetailedThreatSituation = { "boolean", "number", "number", "number", "number" },
	UnitThreatSituation = { "number" },
	UnitThreatPercentageOfLead = { "number" },
	UnitThreatLeadSituation = { "number" },
}

local function checkApi(api)
	if not KINDS[api] then error("mock threat: no function " .. tostring(api), 3) end
end

function threat.Answer(api, unit, mob, answer)
	checkApi(api)
	if answer == nil then error("Mock.threat.Answer: an answer is required (Mock.threat.NIL for nil)", 2) end
	table.insert(answers, 1, { api = api, unit = unit or "*", mob = mob or "*", answer = answer })
end

function threat.Queue(api, ...)
	checkApi(api)
	queues[api] = queues[api] or {}
	for i = 1, select("#", ...) do table.insert(queues[api], (select(i, ...))) end
end

function threat.ClearAnswers()
	for i = #answers, 1, -1 do answers[i] = nil end
	for k in pairs(queues) do queues[k] = nil end
end

local function secretReturns(api)
	local out = { n = #KINDS[api] }
	for i, kind in ipairs(KINDS[api]) do out[i] = Mock.Secret(kind) end
	return unpack(out, 1, out.n)
end

local function scripted(api, unit, mob)
	local queue = queues[api]
	if queue and queue[1] then return table.remove(queue, 1) end
	for _, entry in ipairs(answers) do
		if entry.api == api and (entry.unit == "*" or entry.unit == unit) and (entry.mob == "*" or entry.mob == mob) then
			return entry.answer
		end
	end
end

-- State ------------------------------------------------------------------------------------------------------------
local function listOf(mobKey, create)
	local list = state.mobs[mobKey]
	if not list and create then
		list = { entries = {}, order = {} }
		state.mobs[mobKey] = list
	end
	return list
end

-- The unit with the most threat (the earliest on the list wins a tie), its raw threat and the next highest raw threat.
local function highest(list)
	local best, bestRaw, nextRaw
	for _, key in ipairs(list.order) do
		local raw = list.entries[key].raw
		if not bestRaw or raw > bestRaw then
			best, bestRaw, nextRaw = key, raw, bestRaw
		elseif not nextRaw or raw > nextRaw then
			nextRaw = raw
		end
	end
	return best, bestRaw, nextRaw
end

-- The values the state gives a unit on a mob, nil when it is not on the list. `best`, `bestRaw` and `nextRaw` are
-- highest(list), passed in by a caller that computes many units at once.
local function compute(mobKey, unitKey, best, bestRaw, nextRaw)
	local list = state.mobs[mobKey]
	local entry = list and list.entries[unitKey]
	if not entry then return nil end
	if not best then best, bestRaw, nextRaw = highest(list) end
	local tanking = entry.tanking
	if tanking == nil then tanking = list.holder == unitKey end
	local holder = list.holder and list.entries[list.holder]
	local second   -- the most threat among the others
	if unitKey == best then second = nextRaw else second = bestRaw end
	local unit = Mock.units.Get(unitKey)
	local v = { tanking = tanking, raw = entry.raw }

	if tanking then
		v.status = (not second or entry.raw >= second) and 3 or 2
		v.rawPct, v.scaled = 100, 100
		if second and second > 0 then v.lead = entry.raw / second * 100 end
		local ratio = (second and entry.raw > 0) and (second / entry.raw) or 0
		v.leadStatus = ratio < 0.8 and 0 or (ratio < 0.95 and 1 or (ratio < 1 and 2 or 3))
	else
		local top = holder and holder.raw or 0
		v.status = entry.raw > top and 1 or 0
		v.rawPct = top > 0 and entry.raw / top * 100 or 0
		v.scaled = math.min(100, v.rawPct / ((unit and unit.ranged) and 1.3 or 1.1))
		v.leadStatus = 3
	end
	for _, field in ipairs({ "scaled", "rawPct", "status", "lead", "leadStatus" }) do
		if entry[field] ~= nil then v[field] = entry[field] end
	end
	return v
end
threat.Compute = compute

local function statuses(mobKey)
	local out, list = {}, state.mobs[mobKey]
	if not list then return out end
	local best, bestRaw, nextRaw = highest(list)
	for _, key in ipairs(list.order) do out[key] = compute(mobKey, key, best, bestRaw, nextRaw).status end
	return out
end

-- Applies a change to a mob's list, then fires the events the change would cause and turns the mob to its new holder.
local function change(mobKey, fn)
	if not Mock.units.Get(mobKey) then error("mock threat: no unit " .. tostring(mobKey), 3) end
	local before = statuses(mobKey)
	local list = listOf(mobKey, true)
	local holderBefore = list.holder
	fn(list)
	local after = statuses(mobKey)
	if not threat.silent then
		if list.holder ~= holderBefore then Mock.units.Target(mobKey, list.holder) end
		for _, token in ipairs(Mock.units.TokensOf(mobKey)) do Mock.Fire("UNIT_THREAT_LIST_UPDATE", token) end
		local changed = {}
		for key, status in pairs(after) do
			if before[key] ~= status then changed[#changed + 1] = key end
		end
		for key in pairs(before) do
			if after[key] == nil then changed[#changed + 1] = key end
		end
		table.sort(changed)
		for _, key in ipairs(changed) do
			for _, token in ipairs(Mock.units.TokensOf(key)) do Mock.Fire("UNIT_THREAT_SITUATION_UPDATE", token) end
		end
	elseif list.holder ~= holderBefore then
		Mock.units.Get(mobKey).target = list.holder   -- the mob still turns, without an event
	end
end

function threat.Set(mobKey, unitKey, value)
	if not Mock.units.Get(unitKey) then error("mock threat: no unit " .. tostring(unitKey), 2) end
	local fields = type(value) == "table" and value or { raw = value }
	change(mobKey, function(list)
		local entry = list.entries[unitKey]
		if not entry then
			entry = { raw = 0 }
			list.entries[unitKey] = entry
			list.order[#list.order + 1] = unitKey
		end
		for k, v in pairs(fields) do entry[k] = v end
		list.holder = list.holder or unitKey
	end)
end

function threat.Raw(mobKey, unitKey)
	local list = state.mobs[mobKey]
	local entry = list and list.entries[unitKey]
	return entry and entry.raw
end

function threat.Add(mobKey, unitKey, delta)
	threat.Set(mobKey, unitKey, (threat.Raw(mobKey, unitKey) or 0) + delta)
end

function threat.Holder(mobKey)
	local list = state.mobs[mobKey]
	return list and list.holder
end

function threat.Aggro(mobKey, unitKey)
	if not threat.Raw(mobKey, unitKey) then
		error("Mock.threat.Aggro: " .. tostring(unitKey) .. " is not on the list of " .. tostring(mobKey), 2)
	end
	change(mobKey, function(list) list.holder = unitKey end)
end

-- A unit leaves the list; if it held the mob, the unit with the most threat left takes it.
function threat.Remove(mobKey, unitKey)
	if not threat.Raw(mobKey, unitKey) then return end
	change(mobKey, function(list)
		list.entries[unitKey] = nil
		for i, key in ipairs(list.order) do
			if key == unitKey then table.remove(list.order, i) break end
		end
		if list.holder == unitKey then list.holder = (highest(list)) end
	end)
end

function threat.Wipe(mobKey)
	if not state.mobs[mobKey] then return end
	change(mobKey, function(list)
		list.entries, list.order, list.holder = {}, {}, nil
	end)
	state.mobs[mobKey] = nil
end

-- The keys of the mobs with a threat list, sorted.
function threat.Mobs()
	local keys = {}
	for key in pairs(state.mobs) do keys[#keys + 1] = key end
	table.sort(keys)
	return keys
end

function threat.SetWarning(on) state.warning = on and true or false end

-- API --------------------------------------------------------------------------------------------------------------
local function checkToken(value, api)
	if type(value) ~= "string" or issecretvalue(value) then error("Usage: " .. api .. "(unit, mobUnit)", 3) end
end

-- Common path: count the call, then a scripted answer, a secret or the computed value.
local function answerCall(api, unit, mob, secretCheck, computed)
	threat.calls[api] = (threat.calls[api] or 0) + 1
	local answer = scripted(api, unit, mob)
	if answer then
		if answer.error then error(answer.error, 3) end
		if answer.secret then return secretReturns(api) end
		return unpack(answer, 1, answer.n)
	end
	local result = computed()
	if result == nil then return nil end
	if secretCheck(unit, mob) then return secretReturns(api) end
	return unpack(result, 1, result.n)
end

local function keyOf(token)
	local e = Mock.units.Resolve(token)
	return e and e.key
end

local function valuesFor(unit, mob)
	local unitKey, mobKey = keyOf(unit), keyOf(mob)
	if unitKey and mobKey then return compute(mobKey, unitKey) end
end

function UnitDetailedThreatSituation(unit, mob)
	checkToken(unit, "UnitDetailedThreatSituation")
	checkToken(mob, "UnitDetailedThreatSituation")
	return answerCall("UnitDetailedThreatSituation", unit, mob, Mock.secrets.ValuesSecret, function()
		local v = valuesFor(unit, mob)
		if v then return threat.Returns(v.tanking, v.status, v.scaled, v.rawPct, v.raw) end
	end)
end

-- Without a mob: the highest status of the unit on any mob, nil when it is on no list.
function UnitThreatSituation(unit, mob)
	checkToken(unit, "UnitThreatSituation")
	if mob ~= nil then checkToken(mob, "UnitThreatSituation") end
	return answerCall("UnitThreatSituation", unit, mob, Mock.secrets.StateSecret, function()
		if mob ~= nil then
			local v = valuesFor(unit, mob)
			return v and threat.Returns(v.status)
		end
		local unitKey, best = keyOf(unit), nil
		for mobKey in pairs(state.mobs) do
			local v = unitKey and compute(mobKey, unitKey)
			if v and (not best or v.status > best) then best = v.status end
		end
		return best and threat.Returns(best)
	end)
end

function UnitThreatPercentageOfLead(unit, mob)
	checkToken(unit, "UnitThreatPercentageOfLead")
	checkToken(mob, "UnitThreatPercentageOfLead")
	return answerCall("UnitThreatPercentageOfLead", unit, mob, Mock.secrets.ValuesSecret, function()
		local v = valuesFor(unit, mob)
		return v and v.lead and threat.Returns(v.lead)
	end)
end

function UnitThreatLeadSituation(unit, mob)
	checkToken(unit, "UnitThreatLeadSituation")
	checkToken(mob, "UnitThreatLeadSituation")
	return answerCall("UnitThreatLeadSituation", unit, mob, Mock.secrets.StateSecret, function()
		local v = valuesFor(unit, mob)
		return v and threat.Returns(v.leadStatus)
	end)
end

local COLORS = { [0] = { 0.69, 0.69, 0.69 }, { 1, 1, 0.47 }, { 1, 0.6, 0 }, { 1, 0, 0 } }
function GetThreatStatusColor(index)
	local c = COLORS[index] or COLORS[0]
	return c[1], c[2], c[3]
end

function IsThreatWarningEnabled() return state.warning end
