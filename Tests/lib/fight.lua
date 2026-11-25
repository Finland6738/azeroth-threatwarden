-- Fight scripts (ADR 0010 point 4): a small language for scripted pulls — who does what threat, who takes aggro, when
-- the tank dies, when a mob disappears or changes GUID — so that states, alerts and recordings are tested against known
-- answers. Loaded by Tests/lib/harness.lua; test files see it as the global `Fight`. It only drives the mock client
-- (Tests/mock/): the "server rules" it applies are the ones written in the script.
--
--   local pull = Fight.new{
--     player = { class = "MAGE", role = "DAMAGER", ranged = true },
--     party  = { { key = "tank", class = "WARRIOR", role = "TANK" }, { key = "healer", class = "PRIEST" } },
--     mobs   = { { key = "boss", tokens = { "target", "boss1" }, classification = "worldboss" } },
--     raid   = false,            -- true: the party is a raid (raid1..raidN)
--   }
--   pull:at(0):start():threat("boss", "tank", 1000)
--   pull:at(1):threat("boss", "player", 500)
--   pull:at(4):die("tank")
--   pull:to(1)       -- plays the script up to second 1, then returns; the client's timers run on the way, and the
--                    -- timers due at a step's time fire before the step
--   pull:finish()    -- plays the rest
--
-- Verbs (each also works at once, without `at`: pull:add("boss", "player", 100)):
--   start()                    the player, the group and the mobs enter combat
--   stop()                     the threat lists are wiped and combat ends
--   threat(mob, unit, raw)     sets a unit's raw threat (or a table, Mock.threat.Set); the first unit holds the mob
--   add(mob, unit, delta)      adds raw threat
--   drop(mob, unit)            the unit leaves the mob's list
--   aggro(mob, unit)           the mob turns to a unit that is on its list
--   taunt(mob, unit)           the unit gets at least the highest threat and the mob turns to it
--   die(key)                   a unit or a mob dies: it leaves the lists (a mob's list is wiped); UNIT_DIED
--   vanish(mob)                the mob disappears: its list is wiped, no token or target names it any more
--   newGUID(mob [, guid])      the same tokens now name a different creature, without any event
--   token(token, key)          gives or clears (nil) a token ("nameplate2", "focus", "boss2", "target")
--   target(unit, key)          the unit targets someone else
--   call(fn)                   fn(pull)
local Mock = ...

local Fight = {}
local Pull = {}
Pull.__index = Pull

local VERBS = { "start", "stop", "threat", "add", "drop", "aggro", "taunt", "die", "vanish", "newGUID", "token",
	"target", "call" }

function Fight.new(def)
	def = def or {}
	local pull = setmetatable({ units = {}, mobs = {}, steps = {}, next = 1, elapsed = 0 }, Pull)
	for k, v in pairs(def.player or {}) do Mock.player[k] = v end
	local members = {}
	for i, member in ipairs(def.party or {}) do
		members[i] = member
		pull.units[i] = member.key
	end
	if #members > 0 then Mock.group.Set{ raid = def.raid, members = members } end
	for _, mob in ipairs(def.mobs or {}) do
		local copy = { hostile = true }
		for k, v in pairs(mob) do copy[k] = v end
		Mock.units.Add(mob.key, copy)
		for _, token in ipairs(mob.tokens or {}) do Mock.units.SetToken(token, mob.key) end
		pull.mobs[#pull.mobs + 1] = mob.key
	end
	return pull
end

function Pull:start()
	local keys = {}
	for _, key in ipairs(self.units) do keys[#keys + 1] = key end
	for _, key in ipairs(self.mobs) do keys[#keys + 1] = key end
	Mock.combat.Enter(unpack(keys))
	return self
end

function Pull:stop()
	for _, mob in ipairs(Mock.threat.Mobs()) do Mock.threat.Wipe(mob) end
	Mock.combat.Leave()
	return self
end

function Pull:threat(mob, unit, raw) Mock.threat.Set(mob, unit, raw) return self end
function Pull:add(mob, unit, delta) Mock.threat.Add(mob, unit, delta) return self end
function Pull:drop(mob, unit) Mock.threat.Remove(mob, unit) return self end
function Pull:aggro(mob, unit) Mock.threat.Aggro(mob, unit) return self end

function Pull:taunt(mob, unit)
	local holder = Mock.threat.Holder(mob)
	local top = holder and Mock.threat.Raw(mob, holder) or 0
	for _, key in ipairs({ "player", unpack(self.units) }) do
		top = math.max(top, Mock.threat.Raw(mob, key) or 0)
	end
	Mock.threat.Set(mob, unit, math.max(top, Mock.threat.Raw(mob, unit) or 0))
	Mock.threat.Aggro(mob, unit)
	return self
end

local function entityOf(key)
	return Mock.units.Get(key) or error("fight script: no unit " .. tostring(key), 3)
end

function Pull:die(key)
	local e = entityOf(key)
	e.dead, e.combat = true, false
	if e.hostile then
		Mock.threat.Wipe(key)
	else
		for _, mob in ipairs(Mock.threat.Mobs()) do Mock.threat.Remove(mob, key) end
	end
	for _, token in ipairs(Mock.units.TokensOf(key)) do
		Mock.Fire("UNIT_HEALTH", token)
		Mock.Fire("UNIT_FLAGS", token)
	end
	local guid = e.guid
	if Mock.secrets.IdentitySecret(key) then guid = Mock.Secret("string") end
	Mock.Fire("UNIT_DIED", guid)
	return self
end

function Pull:vanish(mob)
	local e = entityOf(mob)
	Mock.threat.Wipe(mob)
	e.combat = false
	for _, unit in ipairs({ "player", unpack(self.units) }) do
		if Mock.units.Get(unit).target == mob then Mock.units.Target(unit, nil) end
	end
	for _, token in ipairs(Mock.units.TokensOf(mob)) do
		Mock.units.SetToken(token, nil)
	end
	return self
end

function Pull:newGUID(mob, guid)
	local e = entityOf(mob)
	e.guid = guid or Mock.units.NewGUID(e)
	return self
end

function Pull:token(token, key) Mock.units.SetToken(token, key) return self end
function Pull:target(unit, key) Mock.units.Target(unit, key) return self end
function Pull:call(fn) fn(self) return self end

-- The timeline: pull:at(seconds):verb(...):verb(...) records steps; pull:to(seconds) plays them.
function Pull:at(seconds)
	if type(seconds) ~= "number" or seconds < self.elapsed then
		error("fight script: at(" .. tostring(seconds) .. ") is not a time from " .. self.elapsed .. " s on", 2)
	end
	local pull, step = self, {}
	for _, verb in ipairs(VERBS) do
		step[verb] = function(_, ...)
			local steps = pull.steps
			local at = #steps + 1
			while at > pull.next and steps[at - 1].time > seconds do at = at - 1 end
			table.insert(steps, at, { time = seconds, verb = verb, args = { n = select("#", ...), ... } })
			return step
		end
	end
	return setmetatable(step, { __index = function(_, key) error("fight script: no verb " .. tostring(key), 2) end })
end

local function advanceTo(pull, seconds)
	if seconds > pull.elapsed then
		Mock.Advance(seconds - pull.elapsed)
		pull.elapsed = seconds
	end
end

-- Plays every step up to and including `seconds`, moving the clock (and the client's timers) with it.
function Pull:to(seconds)
	while self.steps[self.next] and self.steps[self.next].time <= seconds do
		local step = self.steps[self.next]
		self.next = self.next + 1
		advanceTo(self, step.time)
		Pull[step.verb](self, unpack(step.args, 1, step.args.n))
	end
	advanceTo(self, seconds)
	return self
end

function Pull:finish()
	local last = self.steps[#self.steps]
	return self:to(last and math.max(last.time, self.elapsed) or self.elapsed)
end

return Fight
