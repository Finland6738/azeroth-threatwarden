-- Data/TargetTracker.lua (SPEC-03 §1.2, SPEC-01 §3.2): the monitored mob from the target or the target of target, its
-- key from the GUID or a counter, death, disappearance, a GUID that changes without an event, UNIT_TARGET, the
-- capability mobIdentity, and nothing at all while the monitor switch is off. Fight scripts: Tests/lib/fight.lua.

before_boot(function(M) M.features = { monitor = true } end)

local function TT() return Mock.ns.TargetTracker end

-- Every TARGET_CHANGED from now on, nil written as "nil".
local function watch()
	local seen = {}
	Mock.ns.Bus.On("TARGET_CHANGED", function(key) seen[#seen + 1] = key == nil and "nil" or key end)
	return seen
end

local function newPull(def)
	def = def or {}
	return Fight.new{
		player = { class = "PRIEST", role = "HEALER" },
		party = def.party or { { key = "tank", role = "TANK" }, { key = "rogue", class = "ROGUE", role = "DAMAGER" } },
		mobs = def.mobs or {
			{ key = "boss", tokens = { "boss1" }, classification = "worldboss" },
			{ key = "add", tokens = { "nameplate2" } },
		},
	}
end

local function mobKeyOf(key) return "mob:" .. Mock.units.Get(key).guid end

describe("the rule (SPEC-03 §1.2)", function()
	it("monitors a hostile target, with the GUID as its key", function()
		newPull()
		local seen = watch()
		Mock.units.Target("player", "boss")
		eq(TT().MobToken(), "target")
		eq(TT().MobKey(), mobKeyOf("boss"))
		eq(TT().Status(), "active")
		deepEq(seen, { mobKeyOf("boss") })
		eq(Mock.ns.Compat.Capability("mobIdentity"), "available")
	end)

	it("follows the target of a friendly target: the healer sees the tank's mob", function()
		newPull()
		Mock.units.Target("tank", "boss")
		local seen = watch()
		Mock.units.Target("player", "tank")
		eq(TT().MobToken(), "targettarget")
		eq(TT().MobKey(), mobKeyOf("boss"))
		deepEq(seen, { mobKeyOf("boss") })
	end)

	it("does not with Follow target of target off", function()
		newPull()
		TT().DEFAULTS.followTargetOfTarget = false
		Mock.units.Target("tank", "boss")
		Mock.units.Target("player", "tank")
		isNil(TT().MobToken())
		isNil(TT().MobKey())
		eq(TT().Status(), "none")
		TT().DEFAULTS.followTargetOfTarget = true
		TT().Evaluate(false)
		eq(TT().MobToken(), "targettarget")
	end)

	it("monitors nothing without a target, with a friendly target that targets no enemy, or a dead one", function()
		newPull()
		isNil(TT().MobKey())
		eq(TT().Status(), "none")
		Mock.units.Target("player", "rogue")
		isNil(TT().MobKey())
		Mock.units.Get("add").dead = true
		Mock.units.Target("player", "add")
		isNil(TT().MobKey())
		eq(TT().Status(), "none")
	end)

	it("never reads the threat", function()
		newPull()
		Mock.ns.ThreatScanner.Want("window", false)   -- the scanner reads for its consumers; the tracker never does
		Mock.units.Target("player", "boss")
		Mock.combat.Enter("tank", "boss")
		Mock.units.Target("player", "add")
		eq(Mock.threat.calls.UnitDetailedThreatSituation or 0, 0)
		eq(Mock.threat.calls.UnitThreatSituation or 0, 0)
	end)
end)

describe("changes", function()
	before_boot(function(M)
		M.OnFilesLoaded(function() M.ns.ThreatScanner.Want = function() return false end end)
	end)

	it("emits TARGET_CHANGED once per change of mob, and nil when the player clears the target", function()
		newPull()
		local seen = watch()
		Mock.units.Target("player", "boss")
		Mock.Fire("PLAYER_TARGET_CHANGED")   -- a duplicate: the same mob
		Mock.units.Target("player", "add")
		Mock.units.Target("player", nil)
		deepEq(seen, { mobKeyOf("boss"), mobKeyOf("add"), "nil" })
		eq(TT().Status(), "lost", "the target token names nobody any more")
	end)

	it("sees the mob die at a check or at the end of combat, and keeps Target died until the target changes", function()
		local pull = newPull()
		Mock.units.Target("player", "boss")
		local seen = watch()
		pull:at(0):start():threat("boss", "tank", 100)
		pull:at(1):die("boss")
		pull:finish()
		falsy(TT().Check())
		deepEq(seen, { "nil" })
		eq(TT().Status(), "died")
		Mock.combat.Leave()
		eq(TT().Status(), "died")
		TT().Evaluate(false)
		eq(TT().Status(), "died")
		Mock.units.Target("player", "add")
		eq(TT().Status(), "active")
		eq(TT().MobKey(), mobKeyOf("add"))
	end)

	it("sees the mob vanish: Target lost", function()
		local pull = newPull()
		Mock.units.Target("player", "boss")
		local seen = watch()
		pull:vanish("boss")
		deepEq(seen, { "nil" })
		eq(TT().Status(), "lost")
		isNil(TT().MobToken())
	end)

	it("sees a new creature behind the same token without any event (newGUID) at the next check", function()
		local pull = newPull()
		Mock.units.Target("player", "boss")
		local old = TT().MobKey()
		local seen = watch()
		pull:newGUID("boss")
		eq(TT().MobKey(), old, "nothing said it yet")
		truthy(TT().Check())
		ne(TT().MobKey(), old)
		eq(TT().MobKey(), mobKeyOf("boss"))
		deepEq(seen, { mobKeyOf("boss") })
		truthy(TT().Check())
		eq(#seen, 1, "a second check changes nothing")
	end)

	it("follows UNIT_TARGET: the tank turns to another mob", function()
		newPull()
		Mock.units.Target("tank", "boss")
		Mock.units.Target("player", "tank")
		local seen = watch()
		Mock.units.Target("tank", "add")
		eq(TT().MobKey(), mobKeyOf("add"))
		deepEq(seen, { mobKeyOf("add") })
		Mock.Fire("UNIT_TARGET", Mock.Secret("string"))   -- a secret payload is ignored
		Mock.Fire("UNIT_TARGET", "party2")                 -- somebody else's target: not the monitored mob
		deepEq(seen, { mobKeyOf("add") })
		eq(#Mock.errors, 0)
	end)

	it("stops following when the friendly target turns to nobody", function()
		newPull()
		Mock.units.Target("tank", "boss")
		Mock.units.Target("player", "tank")
		local seen = watch()
		Mock.units.Target("tank", nil)
		deepEq(seen, { "nil" })
		isNil(TT().MobToken())
	end)
end)

describe("a secret GUID [probe P9]", function()
	before_boot(function(M) M.OnFilesLoaded(function() M.ns.ThreatScanner.Want = function() return false end end) end)

	it("keys the mob by a counter, a new one at every change seen, and makes mobIdentity restricted", function()
		newPull()
		Mock.secrets.Set{ identity = true }
		local seen = watch()
		Mock.units.Target("player", "boss")
		local first = TT().MobKey()
		matches(first, "^tgt:%d+$")
		TT().Evaluate(false)
		eq(TT().MobKey(), first, "the same token and nothing changed: the same mob")
		truthy(TT().Check())
		eq(TT().MobKey(), first)
		Mock.units.Target("player", "add")
		matches(TT().MobKey(), "^tgt:%d+$")
		ne(TT().MobKey(), first)
		eq(#seen, 2)
		eq(Mock.ns.Compat.Capability("mobIdentity"), "restricted")
		isNil(TT().mobGUID, "no secret is kept")
		eq(#Mock.errors, 0)
	end)
end)

describe("the monitor switch off", function()
	before_boot(function(M) M.features = { monitor = false } end)

	it("registers nothing and monitors nothing (ADR 0014)", function()
		newPull()
		local seen = watch()
		Mock.units.Target("player", "boss")
		falsy(TT().enabled)
		isNil(TT().MobKey())
		deepEq(seen, {})
		eq(Mock.ns.Compat.Capability("mobIdentity"), "unknown")
	end)
end)

describe("the debug section", function()
	it("tells the token and how the mob is known, never its GUID", function()
		newPull()
		Mock.units.Target("player", "boss")
		local line = TT().DebugLines()[1]
		eq(line, "mob: target (GUID), status active, follow target of target on")
		falsy(line:find(Mock.units.Get("boss").guid, 1, true))
	end)
end)
