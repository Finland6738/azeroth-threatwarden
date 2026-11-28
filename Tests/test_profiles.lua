-- Data/Profiles.lua (SPEC-07 §4, §6; SPEC-02 §3.11; ADR 0020): the role profiles and their presets. A new installation
-- gets the presets; an upgrade from schema 6 changes nothing on screen; every answer of the role gives the profile of
-- SPEC-07 §4.3; a switch never happens in combat; a change in a card lands in the active profile and only there; with
-- the `profiles` switch off nothing is registered and the settings work as before.

local ON = { profiles = true }

local function C() return Mock.ns.Config end
local function P() return Mock.ns.Profiles end
local function S(key) return C():Get("account.settings." .. key) end
local function profile(id) return AzerothThreatwardenDB.profiles[id] end
local function char() return AzerothThreatwardenCharDB.profile end

-- The role the game assigns to the player, and the event that says it changed.
local function role(r)
	Mock.player.role = r
	Mock.Fire("PLAYER_ROLES_ASSIGNED")
end

-- PROFILE_CHANGED as "id<old:why" from now on.
local function switches()
	local seen = {}
	Mock.ns.Bus.On("PROFILE_CHANGED", function(id, old, why)
		seen[#seen + 1] = tostring(id) .. "<" .. tostring(old) .. ":" .. tostring(why)
	end)
	return seen
end

-- The live values of the keys of the profiles, in the shape of a profile.
local function live()
	local out = {}
	for _, group in ipairs(C().PROFILE_GROUPS) do out[group] = {} end
	for _, key in ipairs(C().PROFILE_KEYS) do
		local g, k = key:match("^([^.]+)%.(.+)$")
		out[g][k] = S(key)
	end
	return out
end

-- The settings of a player of v0.7.0 (schema 6), all different from the defaults where they can be.
local function playerSettings()
	return { theme = "warden", language = "itIT",
		monitor = { warning = 70, danger = 85, rate = 4, maxUnits = 20, show = "always", sort = "absolute", pinSelf = true,
			followTargetOfTarget = false },
		alerts = { enabled = true, window = false, visual = true, sound = true, cooldown = 12, others = "always",
			pet = false, onlyTarget = false },
		coach = { enabled = false },
		mobs = { enabled = false, max = 5, nameplates = true },
		recording = { enabled = true, when = "always", rate = 2, maxSessions = 30, maxKB = 4096, notice = true },
	}
end

describe("a new installation (SPEC-02 §3.11)", function()
	before_boot(function(M) M.features = ON end)

	it("has the three presets and, alone, chooses Damage and writes its preset into the settings", function()
		for _, id in ipairs({ "tank", "healer", "damager" }) do deepEq(profile(id), C().PRESETS[id], id) end
		eq(char().active, "damager")
		eq(char().auto, true)
		isNil(char().role, "no role chose it")
		eq(P().Source(), "first")
		deepEq(live(), C().PRESETS.damager)
		eq(S("monitor.pinSelf"), true, "a damage dealer looks for their own row")
		eq(#C().issues, 0)
		eq(#Mock.errors, 0)
	end)

	it("with the role of a tank chooses the tank's preset at the first login", function()
		local seen
		boot(function(M)
			M.player.role = "TANK"
			M.OnFilesLoaded(function() seen = switches() end)
		end)
		eq(char().active, "tank")
		eq(char().role, "TANK")
		eq(P().Source(), "role")
		deepEq(live(), C().PRESETS.tank)
		eq(S("alerts.onlyTarget"), false, "a tank wants the alerts about the other mobs")
		deepEq(seen, { "tank<nil:role" })
	end)

	it("has presets with the owner's thresholds for every role (D12) and only the keys of a profile", function()
		for _, id in ipairs(C().PROFILE_IDS) do
			eq(C().PRESETS[id].monitor.warning, 82)
			eq(C().PRESETS[id].monitor.danger, 91)
			local n = 0
			for _, group in pairs(C().PRESETS[id]) do for _ in pairs(group) do n = n + 1 end end
			eq(n, #C().PROFILE_KEYS, id)
		end
		eq(C().PRESETS.tank.monitor.pinSelf, false)
		eq(C().PRESETS.healer.monitor.pinSelf, true)
		eq(C().PRESETS.healer.alerts.onlyTarget, true)
	end)
end)

describe("an upgrade from schema 6 (DAT-20)", function()
	it("copies today's settings into the three profiles and changes nothing on screen", function()
		local seen
		boot(function(M)
			M.features = ON
			M.player.role = "HEALER"
			M.saved = { AzerothThreatwardenDB = { schema = 6, settings = playerSettings() },
				AzerothThreatwardenCharDB = { schema = 2, ui = { scale = 1.25 } } }
			M.OnFilesLoaded(function()
				seen = {}
				M.ns.Bus.On("CONFIG_CHANGED", function(path)
					if path:find("^account%.settings%.") then seen[#seen + 1] = path end
				end)
			end)
		end)
		eq(AzerothThreatwardenDB.schema, 7)
		eq(AzerothThreatwardenCharDB.schema, 3)
		local mine = playerSettings()
		for _, key in ipairs(C().PROFILE_KEYS) do
			local g, k = key:match("^([^.]+)%.(.+)$")
			if mine[g] and mine[g][k] ~= nil then eq(S(key), mine[g][k], key) end
		end
		deepEq(seen, {}, "the first choice wrote the same values: no setting changed")
		eq(char().active, "healer")
		for _, id in ipairs({ "tank", "healer", "damager" }) do deepEq(profile(id), live(), id) end
		eq(S("theme"), "warden")
		eq(S("monitor.rate"), 4, "a setting outside the profiles stays")
		eq(#C().issues, 0)
	end)

	it("with the switch off fills the profiles too, and writes nothing else", function()
		boot(function(M)
			M.features = { profiles = false }
			M.saved = { AzerothThreatwardenDB = { schema = 6, settings = playerSettings() } }
		end)
		eq(AzerothThreatwardenDB.schema, 7)
		for _, id in ipairs({ "tank", "healer", "damager" }) do deepEq(profile(id), live(), id) end
		deepEq(char(), { auto = true })
		eq(S("monitor.warning"), 70)
	end)

	it("gives a value that breaks its rule the preset of each profile", function()
		local settings = playerSettings()
		settings.monitor.sort = "sideways"
		settings.alerts.cooldown = 99
		settings.monitor.pinSelf = "yes"
		boot(function(M)
			M.features = { profiles = false }
			M.saved = { AzerothThreatwardenDB = { schema = 6, settings = settings } }
		end)
		for _, id in ipairs({ "tank", "healer", "damager" }) do
			eq(profile(id).monitor.sort, "relative", id)
			eq(profile(id).alerts.cooldown, 8, id)
			eq(profile(id).monitor.pinSelf, C().PRESETS[id].monitor.pinSelf, id .. ": the preset, not the default")
			eq(profile(id).alerts.sound, true, id .. ": a good value is copied")
		end
		eq(S("monitor.sort"), "relative", "the setting goes back to its default as before")
	end)

	it("gives a pair of thresholds that breaks the gap the preset pair", function()
		local settings = playerSettings()
		settings.monitor.warning, settings.monitor.danger = 90, 92
		boot(function(M)
			M.features = { profiles = false }
			M.saved = { AzerothThreatwardenDB = { schema = 6, settings = settings } }
		end)
		eq(profile("tank").monitor.warning, 82)
		eq(profile("tank").monitor.danger, 91)
		eq(S("monitor.warning"), 82)
	end)

	it("keeps a character of schema 2, with or without a profile key already there", function()
		boot(function(M)
			M.features = { profiles = false }
			M.saved = { AzerothThreatwardenCharDB = { schema = 2, ui = { locked = true } } }
		end)
		eq(AzerothThreatwardenCharDB.schema, 3)
		deepEq(char(), { auto = true })
		eq(C():Get("char.ui.locked"), true)
		boot(function(M)
			M.features = { profiles = false }
			M.saved = { AzerothThreatwardenCharDB = { schema = 2, profile = { active = "tank", auto = false, extra = 1 } } }
		end)
		deepEq(char(), { active = "tank", auto = false, extra = 1 })
		eq(#C().issues, 0)
	end)

	it("is idempotent: step 7 leaves profiles that are already there, the character step changes nothing", function()
		local data = { schema = 6, settings = playerSettings() }
		truthy(C().Migrate("account", data, 6, 7))
		local once = C().Copy(data)
		C().migrations.account[7](data)
		deepEq(data, once)
		local mine = { schema = 6, settings = {}, profiles = { tank = { monitor = { warning = 60 } } } }
		C().migrations.account[7](mine)
		deepEq(mine.profiles, { tank = { monitor = { warning = 60 } } }, "a table already there stays")
		for _, odd in ipairs({ {}, { settings = "x" }, { settings = { monitor = 3 } } }) do
			truthy(C().Migrate("account", odd, 6, 7))
			deepEq(odd.profiles.damager, C().PRESETS.damager)
		end
		local c = { schema = 2, ui = { locked = true } }
		local before = C().Copy(c)
		truthy(C().Migrate("char", c, 2, 3))
		before.schema = 3
		deepEq(c, before)
	end)

	it("sets a `profiles` that is not a table aside and copies the settings anyway", function()
		boot(function(M)
			M.features = { profiles = false }
			M.saved = { AzerothThreatwardenDB = { schema = 6, settings = playerSettings(), profiles = "broken" } }
		end)
		eq(profile("tank").monitor.warning, 70)
		eq(AzerothThreatwardenDB.corrupt[1].path, "account.profiles")
		eq(AzerothThreatwardenDB.corrupt[1].kind, "string")
	end)

	it("survives a /reload and a new login unchanged", function()
		boot(function(M)
			M.features = ON
			M.saved = { AzerothThreatwardenDB = { schema = 6, settings = playerSettings() } }
		end)
		local before = C().Copy(AzerothThreatwardenDB.profiles)
		Mock.Reload()
		deepEq(AzerothThreatwardenDB.profiles, before)
		Mock.Relog(3600)
		deepEq(AzerothThreatwardenDB.profiles, before)
		eq(C().found.account, 7)
	end)
end)

describe("the choice from the role (SPEC-07 §4.3)", function()
	before_boot(function(M) M.features = ON end)

	it("follows TANK, HEALER and DAMAGER, each once", function()
		local seen = switches()
		local pull = Fight.new{ party = { { key = "tank", role = "TANK" } } }
		pull:at(0):role("player", "TANK"):event("PLAYER_ROLES_ASSIGNED")
		pull:at(1):role("player", "HEALER"):event("PLAYER_ROLES_ASSIGNED")
		pull:at(2):role("player", "DAMAGER"):event("PLAYER_ROLES_ASSIGNED")
		pull:at(3):event("PLAYER_ROLES_ASSIGNED")
		pull:finish()
		deepEq(seen, { "tank<damager:role", "healer<tank:role", "damager<healer:role" })
		eq(char().role, "DAMAGER")
		eq(P().Source(), "role")
	end)

	it("reads the role when the group changes", function()
		Mock.player.role = "TANK"
		Mock.units.Add("mate", { class = "PRIEST", role = "HEALER" })
		Mock.group.Set{ members = { "mate" } }
		eq(char().active, "tank")
	end)

	it("leaves the profile as it is with NONE, and says so", function()
		role("TANK")
		local seen = switches()
		role("NONE")
		eq(char().active, "tank")
		eq(char().role, "TANK", "NONE does not change the last role")
		isNil(P().role)
		eq(P().reason, "none")
		deepEq(seen, {})
	end)

	it("leaves the profile as it is with a role that is secret, missing or an error", function()
		role("HEALER")
		local cases = {
			secret = function() return Mock.Secret("string") end,
			error = function() error("boom") end,
		}
		for reason, fn in pairs(cases) do
			UnitGroupRolesAssigned = fn
			Mock.Fire("PLAYER_ROLES_ASSIGNED")
			eq(char().active, "healer", reason)
			eq(P().reason, reason)
			eq(char().role, "HEALER", reason)
		end
		UnitGroupRolesAssigned = nil
		Mock.Fire("PLAYER_ROLES_ASSIGNED")
		eq(P().reason, "missing")
		eq(char().active, "healer")
		eq(#Mock.errors, 0)
	end)

	it("keeps a choice made by hand until the group assigns a different role, across a /reload", function()
		role("TANK")
		truthy(P().Switch("healer", "manual"))
		eq(char().active, "healer")
		eq(P().Source(), "manual")
		role("TANK")
		eq(char().active, "healer", "the same role does not undo the choice")
		Mock.Reload()
		eq(char().active, "healer", "nor does a /reload")
		eq(Mock.ns.Config:Get("char.profile.active"), "healer")
		role("DAMAGER")
		eq(char().active, "damager", "a different role does")
	end)

	it("a choice by hand is not taken back by the role it overrode", function()
		role("TANK")
		local pull = Fight.new{ mobs = { { key = "boss", tokens = { "target" } } } }
		pull:at(0):start()
		pull:at(1):role("player", "HEALER"):event("PLAYER_ROLES_ASSIGNED")   -- waits: in combat
		pull:at(2):call(function() falsy(P().Switch("damager", "manual")) end)
		pull:at(3):stop()
		pull:finish()
		eq(char().active, "damager", "the player's choice wins over the role it replaced")
		eq(char().role, "HEALER")
	end)

	it("with auto off changes only by hand, and turned on follows the role at once", function()
		role("TANK")
		truthy(P().SetAuto(false))
		eq(char().auto, false)
		role("HEALER")
		eq(char().active, "tank")
		truthy(P().Switch("damager"))
		eq(char().active, "damager")
		eq(P().Source(), "manual")
		truthy(P().SetAuto(true))
		eq(char().active, "healer")
		eq(char().role, "HEALER")
	end)
end)

describe("never in combat (PR-04)", function()
	before_boot(function(M) M.features = ON end)

	it("a switch of the role waits for COMBAT_ENDED, then applies once", function()
		local seen = switches()
		local pull = Fight.new{ party = { { key = "tank", role = "TANK" } }, mobs = { { key = "boss", tokens = { "target" } } } }
		pull:at(0):start():threat("boss", "tank", 1000)
		pull:at(1):role("player", "TANK"):event("PLAYER_ROLES_ASSIGNED")
		pull:at(2):call(function()
			eq(char().active, "damager")
			eq(S("monitor.pinSelf"), true, "nothing written in combat")
			eq(P().pending.id, "tank")
			eq(P().pending.reason, "combat")
			deepEq(seen, {})
		end)
		pull:at(5):stop()
		pull:finish()
		eq(char().active, "tank")
		eq(S("monitor.pinSelf"), false)
		isNil(P().pending)
		deepEq(seen, { "tank<damager:role" })
	end)

	it("a switch by hand waits too and says why", function()
		local pull = Fight.new{ mobs = { { key = "boss", tokens = { "target" } } } }
		pull:at(0):start()
		pull:at(1):call(function()
			local ok, why = P().Switch("tank", "manual")
			falsy(ok)
			eq(why, "combat")
			eq(char().active, "damager")
		end)
		pull:at(2):stop()
		pull:finish()
		eq(char().active, "tank")
	end)

	it("the thresholds a fight starts with stay the thresholds of that fight", function()
		truthy(C():SetProfileValues("tank", { ["monitor.warning"] = 60, ["monitor.danger"] = 70 }))
		local seen = {}
		local pull = Fight.new{ mobs = { { key = "boss", tokens = { "target" } } } }
		pull:at(0):start()
		pull:at(1):call(function() P().Switch("tank") end)
		pull:at(2):call(function() seen[#seen + 1] = S("monitor.warning") end)
		pull:at(3):stop()
		pull:finish()
		deepEq(seen, { 82 })
		eq(S("monitor.warning"), 60)
	end)
end)

describe("writing, copy back and the pair of thresholds (SPEC-07 §4.4)", function()
	before_boot(function(M) M.features = ON end)

	it("a change in a card lands in the active profile and only there", function()
		truthy(C():Set("account.settings.alerts.cooldown", 15))
		eq(profile("damager").alerts.cooldown, 15)
		eq(profile("tank").alerts.cooldown, 8)
		eq(profile("healer").alerts.cooldown, 8)
		truthy(C():SetThresholds(70, 85))
		eq(profile("damager").monitor.warning, 70)
		eq(profile("damager").monitor.danger, 85)
		eq(profile("tank").monitor.warning, 82)
		truthy(C():Set("account.settings.theme", "aurora"))
		isNil(profile("damager").theme, "a setting outside the profiles is not copied")
		truthy(C():Set("account.settings.monitor.rate", 3))
		isNil(profile("damager").monitor.rate)
	end)

	it("copies nothing back while a profile is being applied", function()
		truthy(P().Switch("tank"))
		deepEq(profile("damager"), C().PRESETS.damager, "the old profile keeps its own values")
		deepEq(profile("tank"), C().PRESETS.tank)
		deepEq(live(), C().PRESETS.tank)
		truthy(C():Set("account.settings.monitor.pinSelf", true))
		eq(profile("tank").monitor.pinSelf, true)
		eq(profile("damager").monitor.pinSelf, true)
		truthy(P().Switch("damager"))
		eq(S("monitor.pinSelf"), true)
		eq(profile("tank").monitor.pinSelf, true, "kept in the tank's profile")
	end)

	it("writes the thresholds as a pair: no listener ever sees the gap broken", function()
		truthy(C():SetProfileValues("tank", { ["monitor.warning"] = 95, ["monitor.danger"] = 100 }))
		local broken = 0
		Mock.ns.Bus.On("CONFIG_CHANGED", function()
			if S("monitor.danger") < S("monitor.warning") + C().MONITOR.gap then broken = broken + 1 end
		end)
		truthy(P().Switch("tank"))
		eq(S("monitor.warning"), 95)
		eq(S("monitor.danger"), 100)
		truthy(P().Switch("damager"))
		eq(S("monitor.warning"), 82)
		eq(broken, 0)
		falsy(C():SetProfileValues("tank", { ["monitor.warning"] = 99 }), "the profile keeps the gap too")
		falsy(C():SetProfileValues("tank", { ["monitor.sort"] = "sideways" }))
		falsy(C():SetProfileValues("tank", { theme = "aurora" }))
		falsy(C():SetProfileValues("nobody", {}))
	end)

	it("emits PROFILE_CHANGED once per switch, after the CONFIG_CHANGED of the settings", function()
		local order = {}
		Mock.ns.Bus.On("CONFIG_CHANGED", function(path) order[#order + 1] = path end)
		Mock.ns.Bus.On("PROFILE_CHANGED", function(id) order[#order + 1] = "PROFILE_CHANGED " .. id end)
		truthy(P().Switch("tank"))
		eq(order[#order], "PROFILE_CHANGED tank")
		local n = 0
		for _, v in ipairs(order) do if v:find("^PROFILE_CHANGED") then n = n + 1 end end
		eq(n, 1)
		contains(order, "account.settings.monitor.pinSelf")
		contains(order, "account.settings.alerts.onlyTarget")
	end)

	it("puts a wrong value of a profile back to its preset, into Config.issues", function()
		AzerothThreatwardenDB.profiles.tank.monitor.sort = "sideways"
		AzerothThreatwardenDB.profiles.tank.alerts.cooldown = 1
		truthy(P().Switch("tank"))
		eq(S("monitor.sort"), "relative")
		eq(S("alerts.cooldown"), 8)
		eq(profile("tank").monitor.sort, "relative")
		eq(P().counts.preset, 2)
		local text = table.concat(C().issues, "\n")
		contains(text, "account.profiles.tank.monitor.sort: back to the preset (not an allowed value)")
		contains(text, "account.profiles.tank.alerts.cooldown: back to the preset (below 3)")
	end)
end)

describe("copy and reset (SPEC-07 §4.4)", function()
	before_boot(function(M) M.features = ON end)

	it("Copy from makes the active profile a copy of another one and applies it", function()
		truthy(C():SetProfileValues("healer", { ["alerts.cooldown"] = 20, ["alerts.sound"] = true }))
		local seen = switches()
		truthy(P().CopyFrom("healer"))
		deepEq(profile("damager"), profile("healer"))
		eq(S("alerts.cooldown"), 20)
		eq(S("alerts.sound"), true)
		deepEq(seen, { "damager<damager:copy" })
		falsy(P().CopyFrom("damager"), "not from itself")
		falsy(P().CopyFrom("nobody"))
	end)

	it("Reset to preset puts the active profile back and applies it; the others stay", function()
		truthy(C():Set("account.settings.alerts.cooldown", 15))
		truthy(C():SetProfileValues("tank", { ["alerts.cooldown"] = 20 }))
		truthy(P().ResetActive())
		deepEq(profile("damager"), C().PRESETS.damager)
		eq(S("alerts.cooldown"), 8)
		eq(profile("tank").alerts.cooldown, 20)
	end)

	it("Reset settings resets the rest and the active profile only", function()
		truthy(C():Set("account.settings.theme", "aurora"))
		truthy(C():Set("account.settings.monitor.rate", 3))
		truthy(C():Set("account.settings.alerts.cooldown", 15))
		truthy(C():SetProfileValues("tank", { ["alerts.cooldown"] = 20 }))
		truthy(P().ResetSettings())
		eq(S("theme"), "nebula")
		eq(S("monitor.rate"), 5)
		eq(S("alerts.cooldown"), 8)
		eq(S("monitor.pinSelf"), true, "the active profile's preset, not the default of the setting")
		deepEq(profile("damager"), C().PRESETS.damager)
		eq(profile("tank").alerts.cooldown, 20)
	end)

	it("in combat, a copy and a reset are applied after the fight", function()
		truthy(C():SetProfileValues("tank", { ["alerts.cooldown"] = 20 }))
		local pull = Fight.new{ mobs = { { key = "boss", tokens = { "target" } } } }
		pull:at(0):start()
		pull:at(1):call(function()
			falsy(P().CopyFrom("tank"))
			eq(S("alerts.cooldown"), 8)
			eq(profile("damager").alerts.cooldown, 20)
		end)
		pull:at(2):stop()
		pull:finish()
		eq(S("alerts.cooldown"), 20)
	end)
end)

describe("read-only data (PR-07)", function()
	it("changes no profile and writes nothing", function()
		local ACCOUNT = { schema = 8, settings = { theme = "aurora" } }
		boot(function(M)
			M.features = ON
			M.player.role = "TANK"
			M.saved = { AzerothThreatwardenDB = ACCOUNT }
		end)
		truthy(C():IsReadOnly("account"))
		isNil(char().active, "the first choice waits for writable data")
		local ok, why = P().Switch("tank")
		falsy(ok)
		eq(why, "read-only")
		eq(select(2, P().SetAuto(false)), "read-only")
		eq(select(2, P().CopyFrom("healer")), "read-only")
		eq(select(2, P().ResetActive()), "read-only")
		Mock.Reload()
		deepEq(AzerothThreatwardenDB, ACCOUNT)
	end)
end)

describe("the demo", function()
	before_boot(function(M) M.features = { profiles = true, monitor = true } end)

	it("never changes the profile from the role; a choice by hand applies", function()
		local ATW = AzerothThreatwarden
		ATW.Demo.Start()
		role("TANK")
		eq(char().active, "damager")
		eq(P().pending.reason, "demo")
		ATW.Demo.Stop()
		eq(char().active, "tank")
		ATW.Demo.Start()
		truthy(P().Switch("healer"))
		eq(char().active, "healer")
		ATW.Demo.Stop()
	end)
end)

describe("the switch off (ADR 0014)", function()
	before_boot(function(M) M.features = { profiles = false } end)

	it("registers nothing, chooses nothing and copies nothing; the settings work as before", function()
		eq(Mock.Listeners("PLAYER_ROLES_ASSIGNED"), 0)
		falsy(P().Enabled())
		deepEq(char(), { auto = true })
		eq(S("monitor.pinSelf"), false, "the default of the setting, not a preset")
		role("TANK")
		isNil(char().active)
		truthy(C():Set("account.settings.alerts.cooldown", 15))
		deepEq(profile("damager"), C().PRESETS.damager)
		eq(select(2, P().Switch("tank")), "off")
		truthy(P().ResetSettings())
		eq(S("alerts.cooldown"), 8)
		local names = {}
		for _, section in ipairs(AzerothThreatwarden.debugSections) do names[section.title] = true end
		isNil(names.Profiles, "no section in /atw debug")
	end)

	it("is on in the mock when a test turns it on, with its game event", function()
		boot(function(M) M.features = ON end)
		eq(Mock.Listeners("PLAYER_ROLES_ASSIGNED"), 1)
		truthy(P().Enabled())
	end)
end)
