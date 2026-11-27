-- Data/TargetTracker.lua (SPEC-03 §1.2, SPEC-01 §3.2): the monitored mob from the target or the target of target, its
-- key from the GUID or a counter, death, disappearance, a GUID that changes without an event, UNIT_TARGET, the
-- capability mobIdentity, and nothing at all while the monitor switch is off. Fight scripts: Tests/lib/fight.lua.

-- recording off: the recorder would make the scanner read (test_recorder.lua)
before_boot(function(M) M.features = { monitor = true, recording = false } end)

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
		truthy(Mock.ns.Config:Set("account.settings.monitor.followTargetOfTarget", false))
		Mock.units.Target("tank", "boss")
		Mock.units.Target("player", "tank")
		isNil(TT().MobToken())
		isNil(TT().MobKey())
		eq(TT().Status(), "none")
		truthy(Mock.ns.Config:Set("account.settings.monitor.followTargetOfTarget", true))
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

describe("the pinned mob (rule 0, SPEC-07 §2.4, M7.2)", function()
	before_boot(function(M) M.features = { monitor = true, multitarget = true, recording = false } end)

	-- In combat: the boss is the target, the add is on a nameplate; the tracker of the other mobs runs.
	local function pinPull(def)
		def = def or {}
		truthy(Mock.ns.Config:Set("account.settings.monitor.show", "manual"))
		Mock.ns.Window:Close()
		local mobs = def.mobs or { { key = "boss", tokens = { "target" } }, { key = "add", tokens = { "nameplate2" } },
			{ key = "other", tokens = { "nameplate3" } } }
		local pull = Fight.new{
			player = { class = "MAGE", role = "DAMAGER" },
			party = { { key = "tank", role = "TANK" }, { key = "rogue", class = "ROGUE", role = "DAMAGER" } },
			mobs = mobs,
		}
		pull:at(0):start()
		for _, mob in ipairs(mobs) do pull:threat(mob.key, "tank", 100) end
		pull:to(0)
		if def.before then def.before(pull) end
		Mock.ns.MobTracker.Want("test", true)
		Mock.ns.Scheduler.Stop("mobs")
		Mock.ns.MobTracker.Tick()
		return pull
	end

	local function events()
		local seen = {}
		Mock.ns.Bus.On("TARGET_CHANGED", function(key) seen[#seen + 1] = "target " .. tostring(key) end)
		Mock.ns.Bus.On("PIN_CHANGED", function(key) seen[#seen + 1] = "pin " .. tostring(key) end)
		return seen
	end

	it("pins a mob of the list: its token, its key, TARGET_CHANGED then PIN_CHANGED", function()
		pinPull()
		local seen = events()
		truthy(TT().Pin(mobKeyOf("add")))
		eq(TT().Pinned(), mobKeyOf("add"))
		eq(TT().MobKey(), mobKeyOf("add"))
		eq(TT().MobToken(), "nameplate2")
		eq(TT().Status(), "active")
		deepEq(seen, { "target " .. mobKeyOf("add"), "pin " .. mobKeyOf("add") })
		eq(UnitGUID("target"), Mock.units.Get("boss").guid, "the game's target never changes (MT-06)")
	end)

	it("asks the token again at every check: a nameplate that changes index keeps the pin", function()
		local pull = pinPull()
		truthy(TT().Pin(mobKeyOf("add")))
		pull:token("nameplate2", nil)
		pull:token("nameplate8", "add")
		truthy(TT().Check())
		eq(TT().MobToken(), "nameplate8")
		eq(TT().MobKey(), mobKeyOf("add"))
		eq(TT().Pinned(), mobKeyOf("add"))
	end)

	it("is released by a new hostile target that is another mob, not by the same mob nor a friendly target", function()
		local pull = pinPull()
		truthy(TT().Pin(mobKeyOf("add")))
		pull:target("player", "tank")
		eq(TT().Pinned(), mobKeyOf("add"), "a friendly target")
		pull:target("player", "add")
		eq(TT().Pinned(), mobKeyOf("add"), "the pinned mob itself")
		local seen = events()
		pull:target("player", "other")
		isNil(TT().Pinned())
		eq(TT().MobKey(), mobKeyOf("other"))
		deepEq(seen, { "target " .. mobKeyOf("other"), "pin nil" })
	end)

	it("is released when the mob dies (Target died, then rules 1-3) or vanishes (Target lost)", function()
		local pull = pinPull()
		truthy(TT().Pin(mobKeyOf("add")))
		pull:die("add")
		falsy(TT().Check() and TT().MobKey() == mobKeyOf("add"))
		isNil(TT().Pinned())
		eq(TT().MobKey(), mobKeyOf("boss"), "back to the target")
		truthy(TT().Pin(mobKeyOf("other")))
		pull:target("player", nil)
		eq(TT().Pinned(), mobKeyOf("other"), "clearing the target is not a new hostile target")
		pull:vanish("other")
		TT().Check()
		isNil(TT().Pinned())
		isNil(TT().MobKey())
		eq(TT().Status(), "lost")
	end)

	it("says Target died when the pinned mob died and nothing else is monitored", function()
		local pull = pinPull()
		truthy(TT().Pin(mobKeyOf("add")))
		pull:target("player", nil)
		pull:die("add")
		TT().Check()
		isNil(TT().Pinned())
		eq(TT().Status(), "died")
	end)

	it("is released at COMBAT_ENDED, with the setting off, and by Pin(nil)", function()
		local pull = pinPull()
		truthy(TT().Pin(mobKeyOf("add")))
		local seen = events()
		truthy(TT().Pin(nil))
		isNil(TT().Pinned())
		eq(TT().MobKey(), mobKeyOf("boss"))
		deepEq(seen, { "target " .. mobKeyOf("boss"), "pin nil" })
		falsy(TT().Pin(nil), "nothing to release")
		truthy(TT().Pin(mobKeyOf("add")))
		truthy(Mock.ns.Config:Set("account.settings.mobs.enabled", false))
		isNil(TT().Pinned())
		truthy(Mock.ns.Config:Set("account.settings.mobs.enabled", true))
		for _ = 1, 4 do Mock.ns.MobTracker.Tick() end   -- found again by the sweep
		truthy(TT().Pin(mobKeyOf("add")))
		pull:stop()
		isNil(TT().Pinned())
		eq(TT().MobKey(), mobKeyOf("boss"))
	end)

	it("refuses the monitored mob, a key that cannot be followed and a mob no token names", function()
		pinPull()
		eq(select(2, TT().Pin(mobKeyOf("boss"))), "monitored")
		eq(select(2, TT().Pin("tgt:1")), "no-identity")
		eq(select(2, TT().Pin("tok:nameplate3:1")), "no-identity")
		eq(select(2, TT().Pin("mob:Creature-0-1-0-1-100-FFFFFFFFFF")), "no-token")
		isNil(TT().Pinned())
	end)

	it("keeps the key of a focus mob without a readable GUID [probe P9]", function()
		pinPull{
			mobs = { { key = "boss", tokens = { "target" } }, { key = "add", tokens = { "focus" } } },
			before = function(pull) pull:secrets{ identity = true } end,
		}
		truthy(TT().Pin("tok:focus:1"))
		eq(TT().MobKey(), "tok:focus:1")
		eq(TT().MobToken(), "focus")
		truthy(TT().Check())
		eq(TT().MobKey(), "tok:focus:1")
		isNil(TT().mobGUID)
		eq(#Mock.errors, 0)
	end)
end)

describe("the pin with the multitarget switch off", function()
	before_boot(function(M) M.features = { monitor = true, multitarget = false, recording = false } end)

	it("does nothing (ADR 0014)", function()
		newPull()
		Mock.units.Target("player", "boss")
		eq(select(2, TT().Pin(mobKeyOf("add"))), "off")
		isNil(TT().Pinned())
		eq(TT().MobKey(), mobKeyOf("boss"))
	end)
end)
