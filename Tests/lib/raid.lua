-- A simulated raid for the long scenarios and the per-tick budget of the monitor (Tests/long/, SPEC-08 §3, M2.7).
-- Loaded by Tests/lib/harness.lua; test files see it as the global `Raid`.
--
-- Fight scripts (fight.lua) drive the mock client, whose threat functions allocate a table for every answer and look at
-- the whole list: right for scripted pulls, too slow and too noisy for hours of ticks in a raid of 40. A Raid builds
-- the raid with a fight script and then REPLACES the threat functions and the two secrecy predictions with answers
-- computed once per step into arrays made once: neither a step nor an answer allocates, so what the tests measure is
-- the addon. The rules are the same assumptions as the mock's (Tests/mock/70_threat.lua) until the M0 probe.
--
--   local raid = Raid.new{ adds = 4 }       39 others and the player: raid1 and raid2 tanks, raid3-raid8 healers (raid7
--                                           and raid8 never on a list), the rest damage dealers; "boss" and 4 adds
--                                           ("add1".."add4", nameplate1-4); combat started, the boss targeted
--   raid:step(dt)                           the threat of the monitored mob `dt` seconds later (no client call)
--   raid:advance(dt)                        step, the threat events of what changed, then the client's clock and timers
--   raid:target("add2")                     the player targets that mob
--   raid:kill(u) / raid:revive(u)           a raider leaves every list and comes back (u: 1-39, 40 is the player)
--   raid:outcome("state")                   the probe outcome from now on (Fight.OUTCOMES)
--   raid.holder                             the unit holding the monitored mob
--   raid.wave[u] = { base, amplitude, period }   the scaled % of a unit over time; change it to script a series
--   raid.pullFor, raid.tankSwap             Raid.PULL_FOR and Raid.TANK_SWAP for this raid only (the Raid table is
--                                           shared by every test file: never change it)
local Mock = ...

local Raid = {}
local R = {}
R.__index = R

local floor, sin, pi, min = math.floor, math.sin, math.pi, math.min

Raid.UNITS = 40                       -- 39 raidN and the player
Raid.TANK_SWAP = 45                   -- seconds between two swaps of the tanks
Raid.PULL_EVERY, Raid.PULL_FOR = 20, 4  -- a damage dealer takes a mob for a few seconds

local TOKEN, INDEX = {}, { player = 40 }
for i = 1, 39 do TOKEN[i], INDEX["raid" .. i] = "raid" .. i, i end
TOKEN[40] = "player"
Raid.TOKEN, Raid.INDEX = TOKEN, INDEX

local CLASSES = { "ROGUE", "MAGE", "HUNTER", "WARLOCK", "WARRIOR" }

function Raid.new(opts)
	opts = opts or {}
	local members = {
		{ key = "r1", class = "WARRIOR", role = "TANK" }, { key = "r2", class = "DRUID", role = "TANK" },
	}
	for i = 3, 8 do members[i] = { key = "r" .. i, class = "PRIEST", role = "HEALER" } end
	for i = 9, 39 do members[i] = { key = "r" .. i, class = CLASSES[i % #CLASSES + 1], role = "DAMAGER" } end
	local mobs = { { key = "boss", tokens = { "target", "boss1" }, classification = "worldboss" } }
	local keys = { "boss" }
	for i = 1, opts.adds or 0 do
		mobs[#mobs + 1] = { key = "add" .. i, tokens = { "nameplate" .. i }, classification = "elite" }
		keys[#keys + 1] = "add" .. i
	end

	local raid = setmetatable({
		pull = Fight.new{ player = { class = "MAGE", role = "DAMAGER", ranged = true }, raid = true, party = members,
			mobs = mobs },
		mobs = keys, mob = 1, elapsed = 0, holder = 1, mode = "values",
		wave = {}, alive = {}, onList = {}, raw = {}, scaled = {}, rawPct = {}, status = {}, sentStatus = {},
		lead = nil, leadStatus = 0,
	}, R)
	for u = 1, Raid.UNITS do
		-- a spread of percentages from 20 to 100, so that every state has rows
		raid.wave[u] = { base = 20 + (u * 17) % 71, amplitude = 2 + u % 13, period = 3 + (u * 7) % 23 }
		raid.alive[u], raid.onList[u] = true, false
		raid.raw[u], raid.scaled[u], raid.rawPct[u], raid.status[u], raid.sentStatus[u] = 0, 0, 0, 0, -1
	end
	raid.wave[2] = { base = 60, amplitude = 5, period = 11 }     -- the second tank
	raid.pull:start()
	raid:install()
	raid:step(0)
	return raid
end

-- The mobs holding order: the tanks swap, now and then a damage dealer pulls; a dead holder passes the mob on.
local function pickHolder(raid)
	local t, alive = raid.elapsed, raid.alive
	local shifted = t + raid.mob * 7
	if shifted % Raid.PULL_EVERY >= Raid.PULL_EVERY - (raid.pullFor or Raid.PULL_FOR) then
		local u = 9 + (floor(shifted / Raid.PULL_EVERY) * 5) % 31
		if alive[u] then return u end
	end
	local first = (floor(shifted / (raid.tankSwap or Raid.TANK_SWAP)) % 2) + 1
	if alive[first] then return first end
	if alive[3 - first] then return 3 - first end
	for u = 9, Raid.UNITS do
		if alive[u] then return u end
	end
	return nil
end

-- Writes the threat of the monitored mob at the raid's time into the arrays.
function R:compute()
	local t, mob = self.elapsed, self.mob
	local holder = pickHolder(self)
	self.holder = holder
	local top = 100000 + floor(t) * 10
	local second = 0
	for u = 1, Raid.UNITS do
		-- raid7 and raid8 are never on a list; every eleventh raider leaves it for a while now and then (not while holding
		-- the mob)
		local on = self.alive[u] and u ~= 7 and u ~= 8
			and (u == holder or not (u % 11 == 0 and (t + u * 3) % 60 < 5))
		self.onList[u] = on
		if not on then
			self.raw[u] = 0
		elseif u == holder then
			self.raw[u], self.scaled[u], self.rawPct[u] = top, 100, 100
		else
			local w = self.wave[u]
			local p = w.base + w.amplitude * sin(2 * pi * (t / w.period + (u + mob * 3) / 41))
			if p < 0 then p = 0 end
			-- p is the scaled % before the cap: against 110 % of the holder's threat
			local raw = top * p * 1.1 / 100
			self.raw[u], self.scaled[u], self.rawPct[u] = raw, min(p, 100), raw / top * 100
			self.status[u] = raw > top and 1 or 0
			if raw > second then second = raw end
		end
	end
	if holder and self.onList[holder] then
		self.status[holder] = second > top and 2 or 3
		if second > 0 then
			self.lead = top / second * 100
			local ratio = second / top
			self.leadStatus = ratio < 0.8 and 0 or (ratio < 0.95 and 1 or (ratio < 1 and 2 or 3))
		else
			self.lead, self.leadStatus = nil, 0
		end
	end
end

function R:step(dt)
	self.elapsed = self.elapsed + dt
	self:compute()
end

-- Replaces the threat functions and the secrecy predictions of the mock with the raid's arrays.
function R:install()
	local raid = self
	local function on(unit)
		local u = INDEX[unit]
		if u and raid.onList[u] then return u end
		return nil
	end
	UnitDetailedThreatSituation = function(unit)
		local u = on(unit)
		if not u then return nil end
		return u == raid.holder, raid.status[u], raid.scaled[u], raid.rawPct[u], raid.raw[u]
	end
	UnitThreatSituation = function(unit)
		local u = on(unit)
		if not u then return nil end
		return raid.status[u]
	end
	UnitThreatPercentageOfLead = function(unit)
		local u = on(unit)
		if u and u == raid.holder then return raid.lead end
		return nil
	end
	UnitThreatLeadSituation = function(unit)
		local u = on(unit)
		if not u then return nil end
		if u == raid.holder then return raid.leadStatus end
		return 3
	end
	C_Secrets.ShouldUnitThreatStateBeSecret = function() return raid.mode == "none" end
	C_Secrets.ShouldUnitThreatValuesBeSecret = function() return raid.mode ~= "values" end
end

function R:outcome(name) self.mode = name end
function R:kill(u) self.alive[u] = false end
function R:revive(u) self.alive[u] = true end

function R:indexOf(key)
	for i = 1, #self.mobs do
		if self.mobs[i] == key then return i end
	end
	error("raid: no mob " .. tostring(key), 3)
end

function R:target(key)
	self.mob = self:indexOf(key)
	self:compute()
	self.pull:target("player", key)
end

-- The threat events the client would send for what changed since the last call: the mob's list, and one situation event
-- per unit whose status changed (-1: not on the list).
function R:events()
	Mock.Fire("UNIT_THREAT_LIST_UPDATE", "target")
	for u = 1, Raid.UNITS do
		local status = self.onList[u] and self.status[u] or -1
		if status ~= self.sentStatus[u] then
			self.sentStatus[u] = status
			Mock.Fire("UNIT_THREAT_SITUATION_UPDATE", TOKEN[u])
		end
	end
end

-- One step of the raid and `dt` seconds of the client: the events (unless events == false), the timers (the tick of the
-- scanner among them) and the OnUpdate of the visible frames.
function R:advance(dt, events)
	self:step(dt)
	if events ~= false then self:events() end
	Mock.Advance(dt, dt)
end

return Raid
