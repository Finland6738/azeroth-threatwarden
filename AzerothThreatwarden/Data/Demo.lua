-- DemoData: the invented fight of demo mode (SPEC-03 §5.2, M2.6). Lua 5.1.
-- Modelled on Azeroth Accord (Data/Demo.lua), same owner, GPL-3.0 (ADR 0012): pure data and a deterministic function of
-- the time, no call to the game client and no other module. Every name and number is invented (ADR 0013). Only the
-- shape of the records is the one Data/ThreatScanner.lua fills, so Data/ThreatModel.lua reads them like real ones.
--
--   DemoData.UNITS          the watched units, in roster order: { token, name, classFile, role }; the player's name is
--                           nil (the view says "You"): the demo reads no name from the game
--   DemoData.LENGTH         seconds of one turn of the fight; then it starts again
--   DemoData.Holder(t)      the token holding the mob at second t
--   DemoData.Percent(token, t)   the scaled threat of a unit that does not hold the mob, in points
--   DemoData.Fill(records, t)    writes the threat of every unit at second t into records[i] (one per unit, in order)
--                                and returns the record holding the mob. Allocation-free.
--
-- The story, in one turn: the player climbs (a predicted WARNING, then DANGER) and eases off; the rogue climbs, takes the
-- mob (the tank has lost it) and the tank takes it back.
local ADDON_NAME, ns = ...
ns = ns or {}
ns.modules = ns.modules or {}

local DemoData = {}
ns.DemoData, ns.modules.DemoData = DemoData, DemoData
if ns.addon then ns.addon.DemoData = DemoData end

local ipairs = ipairs

DemoData.LENGTH = 40

DemoData.UNITS = {
	{ token = "player", name = nil, classFile = "MAGE", role = "DAMAGER", ranged = true },
	{ token = "party1", name = "Brannok", classFile = "WARRIOR", role = "TANK" },
	{ token = "party2", name = "Sela", classFile = "PRIEST", role = "HEALER", ranged = true },
	{ token = "party3", name = "Kor", classFile = "ROGUE", role = "DAMAGER" },
}

-- { second, scaled % } by token, linear in between; the tank's line counts only while somebody else holds the mob.
local LINES = {
	player = { { 0, 20 }, { 8, 50 }, { 14, 86 }, { 18, 97 }, { 19, 97 }, { 23, 62 }, { 32, 50 }, { 40, 20 } },
	party1 = { { 0, 90 }, { 40, 90 } },
	party2 = { { 0, 8 }, { 18, 14 }, { 32, 26 }, { 40, 8 } },
	party3 = { { 0, 35 }, { 18, 55 }, { 22, 65 }, { 28, 99 }, { 32, 99 }, { 34, 76 }, { 40, 35 } },
}

-- Who holds the mob: { from second, token }.
local HOLDERS = { { 0, "party1" }, { 28, "party3" }, { 32, "party1" } }

-- The game's raw threat is higher than the scaled one by this much (melee 110 %, ranged 130 %): invented like the rest.
local MELEE, RANGED = 1.1, 1.3

function DemoData.Holder(t)
	local token = HOLDERS[1][2]
	for i = 2, #HOLDERS do
		if t >= HOLDERS[i][1] then token = HOLDERS[i][2] end
	end
	return token
end

function DemoData.Percent(token, t)
	local line = LINES[token]
	if not line then return nil end
	local previous = line[1]
	if t <= previous[1] then return previous[2] end
	for i = 2, #line do
		local point = line[i]
		if t <= point[1] then
			local span = point[1] - previous[1]
			return previous[2] + (point[2] - previous[2]) * (t - previous[1]) / span
		end
		previous = point
	end
	return previous[2]
end

function DemoData.Fill(records, t)
	local holderToken = DemoData.Holder(t)
	local holderThreat = 1000 + 220 * t
	local holder, second, secondThreat = nil, 0, 0
	for i, unit in ipairs(DemoData.UNITS) do
		local rec = records[i]
		rec.mode, rec.reason, rec.source = "values", nil, "demo"
		rec.leadPercent, rec.leadSituation, rec.leadReason = nil, nil, "not-holder"
		if unit.token == holderToken then
			holder = rec
			rec.isTanking, rec.situation = true, 3
			rec.scaledPercent, rec.rawPercent, rec.rawThreat = 100, 100, holderThreat
		else
			local scaled = DemoData.Percent(unit.token, t)
			local raw = scaled * (unit.ranged and RANGED or MELEE)
			rec.isTanking, rec.situation = false, raw >= 100 and 1 or 0
			rec.scaledPercent, rec.rawPercent, rec.rawThreat = scaled, raw, holderThreat * raw / 100
			if scaled > second then second = scaled end
			if rec.rawThreat > secondThreat then secondThreat = rec.rawThreat end
		end
	end
	if holder then
		if secondThreat > holderThreat then holder.situation = 2 end
		holder.leadReason = nil
		holder.leadPercent = secondThreat > 0 and holderThreat * 100 / secondThreat or 0
		local defaults = ns.Config.MONITOR_DEFAULTS
		holder.leadSituation = (second >= defaults.danger and 3) or (second >= defaults.warning and 1) or 0
	end
	return holder
end
