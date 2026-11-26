-- Core/Config.lua (SPEC-02 §3, DAT-20–DAT-25; ADR 0005): defaults, rules, wrong values back to their defaults, the
-- migrations from hand-written older data, read-only on a newer schema, damaged tables under `corrupt`, Set and
-- CONFIG_CHANGED, the resets, the saved-data lines of /atw debug, and the survival across /reload and logout.
-- Adapted from Azeroth Accord (Tests/test_config.lua), same owner, GPL-3.0 (ADR 0012).
-- Saved data is written in before_boot / boot setups (Mock.saved): the harness serializes it and restores it before
-- ADDON_LOADED, like the client. Mock.OnFilesLoaded changes Config (a later schema, a migration) before ADDON_LOADED.

local function C() return Mock.ns.Config end
local function issues() return table.concat(C().issues, "\n") end
local function report() return Mock.ns.Diagnostics.Report() end

-- Records the CONFIG_CHANGED paths from now on.
local function changes()
	local seen = {}
	Mock.ns.Bus.On("CONFIG_CHANGED", function(path) seen[#seen + 1] = path end)
	return seen
end

describe("defaults (SPEC-02 §3.2, §3.3)", function()
	it("creates both variables, account schema 5 and character schema 1, with every default, with no problem", function()
		eq(AzerothThreatwardenDB.schema, 5)
		eq(AzerothThreatwardenCharDB.schema, 1)
		deepEq(AzerothThreatwardenDB.settings, { language = "auto", theme = "nebula", effects = true, animations = true,
			font = "addon", minimap = { hide = false, minimapPos = 200 },
			monitor = Mock.ns.Config.MONITOR_DEFAULTS, alerts = Mock.ns.Config.ALERTS_DEFAULTS,
			coach = Mock.ns.Config.COACH_DEFAULTS, recording = Mock.ns.Config.RECORDING_DEFAULTS })
		deepEq(AzerothThreatwardenDB.corrupt, {})
		deepEq(AzerothThreatwardenCharDB.ui, { shown = true, locked = false, scale = 1.0, size = {}, lastTab = "monitor",
			lastPage = "settings" })
		isNil(C():Get("char.ui.pos"), "the window starts at the centre")
		eq(#C().issues, 0)
		falsy(C():IsReadOnly())
		eq(C().found.account, "none")
		eq(C().db.account, AzerothThreatwardenDB, "the addon works on the saved table itself")
		eq(AzerothThreatwarden.Config, C())
		eq(C().DEV, true, "a checkout is a development build (the packager turns it off)")
	end)

	it("has the enumerations of the specification", function()
		deepEq(C().LANGUAGES, { "auto", "enUS", "itIT" })
		deepEq(C().THEMES, { "nebula", "aurora", "warden" })
		deepEq(C().FONT_SOURCES, { "addon", "game" })
		deepEq(C().TABS, { "monitor", "settings", "reports" })
		deepEq(C().PAGES, { "settings", "about" })
		eq(#C().POINTS, 9)
		eq(C().MAX_CORRUPT, 5)
	end)

	it("emits CONFIG_LOADED once at ADDON_LOADED, and no CONFIG_CHANGED", function()
		local seen = {}
		boot(function(M)
			M.OnFilesLoaded(function()
				M.ns.Bus.On("CONFIG_LOADED", function() seen[#seen + 1] = "loaded" end)
				M.ns.Bus.On("CONFIG_CHANGED", function(path) seen[#seen + 1] = path end)
			end)
		end)
		deepEq(seen, { "loaded" })
	end)
end)

describe("existing data", function()
	before_boot(function(M)
		M.saved = {
			AzerothThreatwardenDB = { schema = 1, settings = { theme = "aurora", minimap = { lock = true } },
				sessions = { { kept = true } } },
			AzerothThreatwardenCharDB = { schema = 1, ui = { scale = 1.5, unknown = "x",
				pos = { point = "TOPLEFT", relativePoint = "BOTTOMLEFT", x = 12.5, y = -3 } } },
		}
	end)

	it("gets what is missing and keeps every value, known or not (DAT-25)", function()
		eq(C():Get("account.settings.theme"), "aurora")
		eq(C():Get("account.settings.language"), "auto")
		eq(AzerothThreatwardenDB.settings.minimap.lock, true, "a key LibDBIcon adds stays")
		eq(AzerothThreatwardenDB.settings.minimap.minimapPos, 200)
		deepEq(AzerothThreatwardenDB.sessions, { { kept = true } }, "an unknown key stays")
		eq(C():Get("char.ui.scale"), 1.5)
		eq(AzerothThreatwardenCharDB.ui.unknown, "x")
		deepEq(C():Get("char.ui.pos"), { point = "TOPLEFT", relativePoint = "BOTTOMLEFT", x = 12.5, y = -3 })
		eq(C().found.account, 1)
		eq(#C().issues, 0)
	end)
end)

describe("wrong values (DAT-22)", function()
	before_boot(function(M)
		M.saved = {
			AzerothThreatwardenDB = { schema = 1, settings = { language = "deDE", theme = 3, effects = "yes",
				font = "serif", minimap = { hide = 1, minimapPos = 400 } } },
			AzerothThreatwardenCharDB = { schema = 1, ui = { shown = "no", locked = 0, scale = 7, lastTab = "timeline",
				lastPage = "x", pos = { point = "MIDDLE", relativePoint = "CENTER", x = 1, y = 2 },
				size = { compact = { w = 10, h = 5000 }, wide = { w = "a", h = 1 } } } },
		}
	end)

	it("go back to their defaults without a Lua error", function()
		eq(#Mock.errors, 0)
		deepEq(AzerothThreatwardenDB.settings, { language = "auto", theme = "nebula", effects = true, animations = true,
			font = "addon", minimap = { hide = false, minimapPos = 200 },
			monitor = Mock.ns.Config.MONITOR_DEFAULTS, alerts = Mock.ns.Config.ALERTS_DEFAULTS,
			coach = Mock.ns.Config.COACH_DEFAULTS, recording = Mock.ns.Config.RECORDING_DEFAULTS })
		local ui = AzerothThreatwardenCharDB.ui
		eq(ui.shown, true)
		eq(ui.locked, false)
		eq(ui.scale, 1.0)
		eq(ui.lastTab, "monitor", "timeline is not a tab before M5")
		eq(ui.lastPage, "settings")
		isNil(ui.pos)
		isNil(ui.size.wide)
		falsy(C():IsReadOnly())
	end)

	it("bring a size back within the limits of its layout instead of resetting it", function()
		deepEq(AzerothThreatwardenCharDB.ui.size.compact, { w = 220, h = 800 })
	end)

	it("are listed by path, without the values", function()
		local text = issues()
		for _, path in ipairs({ "account.settings.language", "account.settings.theme", "account.settings.effects",
			"account.settings.font", "account.settings.minimap.hide", "account.settings.minimap.minimapPos",
			"char.ui.shown", "char.ui.locked", "char.ui.scale", "char.ui.lastTab", "char.ui.lastPage", "char.ui.pos",
			"char.ui.size.wide" }) do
			contains(text, path .. ": reset (", path)
		end
		contains(text, "char.ui.size.compact: brought within the limits")
		contains(text, "account.settings.minimap.minimapPos: reset (above 360)")
		falsy(text:find("deDE", 1, true))
	end)

	it("of a table set the table aside in `corrupt`; plain values are only reset", function()
		local corrupt = AzerothThreatwardenDB.corrupt
		eq(#corrupt, 2)
		eq(corrupt[1].scope, "char")
		eq(corrupt[1].path, "char.ui.pos")
		eq(corrupt[1].kind, "table")
		eq(corrupt[1].at, GetServerTime())
		deepEq(corrupt[1].data, { point = "MIDDLE", relativePoint = "CENTER", x = 1, y = 2 })
		eq(corrupt[2].path, "char.ui.size.wide")
	end)

	it("are fixed once: the next load finds nothing", function()
		Mock.Reload()
		eq(#C().issues, 0)
		eq(#AzerothThreatwardenDB.corrupt, 2)
	end)
end)

describe("numbers the file cannot hold, written by the addon itself", function()
	it("are reset too: not a finite number, a scale off its step", function()
		boot(function(M)
			M.OnFilesLoaded(function()
				AzerothThreatwardenDB = { schema = 1, settings = { minimap = { minimapPos = 0 / 0 } } }
				AzerothThreatwardenCharDB = { schema = 1, ui = { scale = 1.23, size = { wide = { w = math.huge, h = 500 } } } }
			end)
		end)
		eq(AzerothThreatwardenDB.settings.minimap.minimapPos, 200)
		near(AzerothThreatwardenCharDB.ui.scale, 1.25, 1e-9)
		isNil(AzerothThreatwardenCharDB.ui.size.wide)
		contains(issues(), "minimapPos: reset (not a finite number)")
		contains(issues(), "char.ui.scale: rounded to 0.05")
		Mock.Reload()   -- and the file can be written
		eq(#C().issues, 0)
	end)
end)

describe("Set and Get (SPEC-02 §3.4)", function()
	it("store a valid value and emit CONFIG_CHANGED(path) only when it changes", function()
		local seen = changes()
		truthy(C():Set("account.settings.theme", "warden"))
		truthy(C():Set("account.settings.theme", "warden"))
		truthy(C():Set("char.ui.locked", true))
		truthy(C():Set("account.settings.minimap.hide", true))
		deepEq(seen, { "account.settings.theme", "char.ui.locked", "account.settings.minimap.hide" })
		eq(AzerothThreatwardenDB.settings.theme, "warden")
		eq(C():Get("char.ui.locked"), true)
	end)

	it("refuse a wrong value with the reason, and keep the old one", function()
		local seen = changes()
		local cases = {
			{ "account.settings.language", "deDE", "not an allowed value" },
			{ "account.settings.effects", "no", "expected boolean, got string" },
			{ "account.settings.minimap.minimapPos", -1, "below 0" },
			{ "char.ui.scale", 3, "above 2" },
			{ "char.ui.scale", 0 / 0, "not a finite number" },
			{ "char.ui.lastTab", "timeline", "not an allowed value" },
			{ "char.ui.pos", { point = "TOP", relativePoint = "TOP", x = math.huge, y = 0 }, "bad shape" },
			{ "char.ui.size.compact", { w = 300 }, "bad shape" },
			{ "char.ui.shown", nil, "missing" },
		}
		for _, case in ipairs(cases) do
			local ok, why = C():Set(case[1], case[2])
			falsy(ok, case[1])
			eq(why, case[3], case[1])
		end
		eq(C():Get("account.settings.language"), "auto")
		eq(C():Get("char.ui.scale"), 1.0)
		deepEq(seen, {})
	end)

	it("refuse an unknown path and a whole container", function()
		eq(select(2, C():Set("account.nothing", 1)), "unknown path")
		eq(select(2, C():Set("account.schema", 2)), "unknown path")
		eq(select(2, C():Set("other.ui.scale", 1)), "unknown path")
		eq(select(2, C():Set("account.settings", {})), "not a value")
		eq(select(2, C():Set("account.corrupt", {})), "not a value")
		eq(select(2, C():Set("char.ui", {})), "not a value")
	end)

	it("round the scale, bring a size within its limits and accept nil for an optional value", function()
		truthy(C():Set("char.ui.scale", 1.32))
		near(C():Get("char.ui.scale"), 1.3, 1e-9)
		truthy(C():Set("char.ui.size.wide", { w = 2000, h = 100 }))
		deepEq(C():Get("char.ui.size.wide"), { w = 900, h = 420 })
		local pos = { point = "TOP", relativePoint = "BOTTOM", x = 1, y = 2 }
		truthy(C():Set("char.ui.pos", pos))
		pos.x = 99
		eq(C():Get("char.ui.pos").x, 1, "Set keeps a copy")
		truthy(C():Set("char.ui.pos", nil))
		isNil(AzerothThreatwardenCharDB.ui.pos)
	end)

	it("Get answers nil for a path that does not exist", function()
		isNil(C():Get("account.settings.nothing.deeper"))
		isNil(C():Get("nowhere.at.all"))
	end)

	it("Get allocates nothing after the first call of a path, and follows the stored value (ARC-06)", function()
		eq(C():Get("account.settings.animations"), true)
		local grown = math.huge
		for _ = 1, 3 do   -- the smallest of three batches under 4 KB, as the other allocation tests
			collectgarbage("collect")
			collectgarbage("stop")
			local before = collectgarbage("count")
			for _ = 1, 1000 do C():Get("account.settings.animations") end
			grown = math.min(grown, collectgarbage("count") - before)
			collectgarbage("restart")
		end
		truthy(grown < 4, "grew by " .. grown .. " KB")
		truthy(C():Set("account.settings.animations", false))
		eq(C():Get("account.settings.animations"), false)
		eq(C().db.account.settings, C():Get("account.settings"), "a table is the live one")
	end)
end)

describe("damaged data (DAT-24)", function()
	it("a variable that is not a table becomes a new one; only its type goes into `corrupt`", function()
		boot(function(M) M.saved = { AzerothThreatwardenDB = "garbage", AzerothThreatwardenCharDB = 12 } end)
		eq(type(AzerothThreatwardenDB), "table")
		eq(AzerothThreatwardenCharDB.schema, 1)
		eq(AzerothThreatwardenDB.settings.language, "auto")
		local corrupt = AzerothThreatwardenDB.corrupt
		eq(#corrupt, 2)
		deepEq(corrupt[1], { scope = "account", path = "account", kind = "string", at = GetServerTime() })
		deepEq(corrupt[2], { scope = "char", path = "char", kind = "number", at = GetServerTime() })
		contains(issues(), "AzerothThreatwardenDB: not a table, replaced by the defaults")
		eq(C().found.char, "damaged")
		eq(#Mock.errors, 0)
	end)

	it("a table of the wrong type goes back to its default, and the addon goes on", function()
		boot(function(M)
			M.saved = { AzerothThreatwardenDB = { schema = 1, settings = "x" },
				AzerothThreatwardenCharDB = { schema = 1, ui = { size = 4 } } }
		end)
		eq(C():Get("account.settings.theme"), "nebula")
		deepEq(AzerothThreatwardenCharDB.ui.size, {})
		eq(AzerothThreatwardenDB.corrupt[1].path, "account.settings")
		eq(AzerothThreatwardenDB.corrupt[1].kind, "string")
		eq(AzerothThreatwardenDB.corrupt[2].path, "char.ui.size")
		truthy(C():Set("account.settings.theme", "aurora"), "writes work")
	end)

	it("the copy in `corrupt` keeps 3 levels and 50 keys", function()
		local big = { point = "X", deep = { a = { b = { c = 1 } } } }
		for i = 1, 80 do big["k" .. i] = i end
		boot(function(M)
			M.saved = { AzerothThreatwardenCharDB = { schema = 1, ui = { pos = { deep = { a = { b = { c = 1 } } } },
				size = { wide = big } } } }
		end)
		deepEq(AzerothThreatwardenDB.corrupt[1].data, { deep = { a = { b = "<table>" } } }, "the fourth level is not copied")
		local data = AzerothThreatwardenDB.corrupt[2].data
		local count = 0
		local function walk(t) for _, v in pairs(t) do count = count + 1 if type(v) == "table" then walk(v) end end end
		walk(data)
		eq(count, 50)
	end)

	it("keeps at most 5 entries, the oldest goes first", function()
		local old = {}
		for i = 1, 4 do old[i] = { scope = "account", path = "old" .. i, at = i, kind = "table" } end
		boot(function(M)
			M.saved = { AzerothThreatwardenDB = { schema = 1, corrupt = old },
				AzerothThreatwardenCharDB = { schema = 1, ui = { pos = 1, size = "s" } } }
		end)
		local corrupt = AzerothThreatwardenDB.corrupt
		eq(#corrupt, 5)
		eq(corrupt[1].path, "old2")
		eq(corrupt[4].path, "char.ui.pos")
		eq(corrupt[5].path, "char.ui.size")
	end)

	it("a `corrupt` list too long is cut, a damaged one is emptied without an entry of its own", function()
		local many = {}
		for i = 1, 8 do many[i] = { path = "p" .. i } end
		boot(function(M) M.saved = { AzerothThreatwardenDB = { schema = 1, corrupt = many } } end)
		eq(#AzerothThreatwardenDB.corrupt, 5)
		eq(AzerothThreatwardenDB.corrupt[1].path, "p4")
		boot(function(M) M.saved = { AzerothThreatwardenDB = { schema = 1, corrupt = { a = 1, "x" } } } end)
		deepEq(AzerothThreatwardenDB.corrupt, {})
		contains(issues(), "account.corrupt: reset (bad shape)")
	end)

	it("a missing or damaged schema is 0: the data is migrated and kept", function()
		boot(function(M)
			M.saved = { AzerothThreatwardenDB = { settings = { theme = "aurora" } },
				AzerothThreatwardenCharDB = { schema = "two", ui = { locked = true } } }
		end)
		eq(AzerothThreatwardenDB.schema, 5)
		eq(AzerothThreatwardenDB.settings.theme, "aurora")
		eq(AzerothThreatwardenCharDB.schema, 1)
		eq(AzerothThreatwardenCharDB.ui.locked, true)
		eq(C().found.account, "none")
		eq(C().found.char, "damaged")
		contains(issues(), "AzerothThreatwardenDB: schema missing, treated as 0")
		contains(issues(), "AzerothThreatwardenCharDB: damaged schema, treated as 0")
		falsy(C():IsReadOnly())
		for _, bad in ipairs({ -3, 1.5 }) do
			boot(function(M) M.saved = { AzerothThreatwardenDB = { schema = bad } } end)
			eq(C().found.account, "damaged", tostring(bad))
			eq(AzerothThreatwardenDB.schema, 5)
		end
	end)
end)

describe("migrations (DAT-20)", function()
	it("have one step per version for both variables", function()
		for _, scope in ipairs({ "account", "char" }) do
			for n = 1, C().SCHEMAS[scope] do eq(type(C().migrations[scope][n]), "function", scope .. " " .. n) end
		end
	end)

	it("step 1 is idempotent on hand-written data of version 0", function()
		local data = { settings = { language = "itIT", minimap = { hide = true } }, extra = { 1, 2 } }
		local once = C().Copy(data)
		truthy(C().Migrate("account", once, 0, 1))
		local twice = C().Copy(once)
		C().migrations.account[1](twice)
		deepEq(twice, once)
		eq(once.schema, 1)
		eq(once.settings.language, "itIT")
		local char = { ui = { scale = 0.75 } }
		truthy(C().Migrate("char", char, 0, 1))
		deepEq(char, { schema = 1, ui = { scale = 0.75 } })
	end)

	it("data of version 0 written by hand becomes schema 1 and keeps its values", function()
		boot(function(M)
			M.saved = {
				AzerothThreatwardenDB = { settings = { language = "itIT", theme = "warden", effects = false } },
				AzerothThreatwardenCharDB = { ui = { shown = false, lastTab = "settings", scale = 0.8 } },
			}
		end)
		eq(AzerothThreatwardenDB.schema, 5)
		eq(C():Get("account.settings.language"), "itIT")
		eq(C():Get("account.settings.theme"), "warden")
		eq(C():Get("account.settings.effects"), false)
		eq(C():Get("char.ui.shown"), false)
		eq(C():Get("char.ui.lastTab"), "settings")
		eq(C():Get("char.ui.scale"), 0.8)
		falsy(C():IsReadOnly())
	end)

	-- A later schema, as the step of a future milestone will add it: the framework runs the steps in order on a copy.
	local calls
	local function laterSchema(M, steps)
		M.OnFilesLoaded(function()
			local Config = M.ns.Config
			Config.SCHEMAS.account = 6
			for n, fn in pairs(steps) do Config.migrations.account[n] = fn end
		end)
	end

	it("run in order from the stored version; the saved table keeps its identity", function()
		calls = {}
		boot(function(M)
			M.saved = { AzerothThreatwardenDB = { schema = 4, settings = { oldTheme = "aurora" } } }
			laterSchema(M, {
				[5] = function(db)
					calls[#calls + 1] = 5
					if db.settings.oldTheme ~= nil then db.settings.theme, db.settings.oldTheme = db.settings.oldTheme, nil end
				end,
				[6] = function(db) calls[#calls + 1] = 6 end,
			})
		end)
		deepEq(calls, { 5, 6 })
		eq(AzerothThreatwardenDB.schema, 6)
		eq(AzerothThreatwardenDB.settings.theme, "aurora")
		isNil(AzerothThreatwardenDB.settings.oldTheme)
		eq(C().db.account, AzerothThreatwardenDB)
		falsy(C():IsReadOnly("account"))
		C():Load()
		deepEq(calls, { 5, 6 }, "a second load runs no step")
	end)

	it("a step that fails leaves the saved data untouched and the variable read-only", function()
		boot(function(M)
			M.saved = { AzerothThreatwardenDB = { schema = 4, settings = { effects = false } } }
			laterSchema(M, {
				[5] = function(db) db.settings.effects = true end,
				[6] = function(db) db.settings.theme = "aurora"; error("boom") end,
			})
		end)
		eq(AzerothThreatwardenDB.schema, 4)
		eq(AzerothThreatwardenDB.settings.effects, false)
		isNil(AzerothThreatwardenDB.settings.theme)
		truthy(C():IsReadOnly("account"))
		falsy(C():IsReadOnly("char"))
		contains(issues(), "AzerothThreatwardenDB: migration step 6 failed, read-only")
		eq(select(2, C():Set("account.settings.theme", "warden")), "read-only")
		eq(#Mock.errors, 0)
		Mock.Reload()
		matches(Mock.savedText.AzerothThreatwardenDB, '%["effects"%]=false')
		matches(Mock.savedText.AzerothThreatwardenDB, '%["schema"%]=4')
	end)

	it("a step that is missing fails the same way", function()
		boot(function(M)
			M.saved = { AzerothThreatwardenDB = { schema = 4, settings = { theme = "aurora" } } }
			laterSchema(M, { [5] = function() end })
		end)
		truthy(C():IsReadOnly("account"))
		contains(issues(), "migration step 6 missing")
		eq(AzerothThreatwardenDB.schema, 4)
	end)
end)

describe("a newer schema (DAT-21, DAT-25)", function()
	local ACCOUNT = { schema = 6, settings = { language = "itIT", theme = "future", minimap = "x" }, future = { keep = true } }
	local CHAR = { schema = 6, ui = { lastTab = "timeline", newKey = 1 } }
	before_boot(function(M) M.saved = { AzerothThreatwardenDB = ACCOUNT, AzerothThreatwardenCharDB = CHAR } end)

	it("is never rewritten: the saved tables stay as they were", function()
		truthy(C():IsReadOnly("account"))
		truthy(C():IsReadOnly("char"))
		deepEq(AzerothThreatwardenDB, ACCOUNT)
		deepEq(AzerothThreatwardenCharDB, CHAR)
		contains(issues(), "AzerothThreatwardenDB: schema 6 is newer than 5, read-only")
		contains(issues(), "AzerothThreatwardenCharDB: schema 6 is newer than 1, read-only")
	end)

	it("the addon works on a clean copy, with its corrections and `corrupt` only in memory", function()
		ne(C().db.account, AzerothThreatwardenDB)
		eq(C():Get("account.settings.theme"), "nebula")
		eq(C():Get("account.settings.language"), "itIT", "a valid value of the newer data is used")
		eq(C():Get("char.ui.lastTab"), "monitor")
		eq(C().db.account.corrupt[1].path, "account.settings.minimap")
		isNil(AzerothThreatwardenDB.corrupt)
		eq(Mock.ns.Locale.Active(), "itIT")
	end)

	it("refuses every write", function()
		local seen = changes()
		eq(select(2, C():Set("account.settings.theme", "aurora")), "read-only")
		eq(select(2, C():Set("char.ui.locked", true)), "read-only")
		eq(select(2, C():ResetSettings()), "read-only")
		eq(select(2, C():ResetWindow()), "read-only")
		deepEq(seen, {})
	end)

	it("survives /reload and logout unchanged, and /atw debug says so", function()
		Mock.Reload()
		deepEq(AzerothThreatwardenDB, ACCOUNT)
		Mock.Relog(3600)
		deepEq(AzerothThreatwardenCharDB, CHAR)
		local text = report()
		contains(text, "AzerothThreatwardenDB: schema found 6, current 5, about ")
		contains(text, "READ-ONLY: saved by a newer version, never rewritten")
	end)
end)

describe("reload and logout (DAT-23)", function()
	it("keep every value written through Set", function()
		truthy(C():Set("account.settings.language", "itIT"))
		truthy(C():Set("account.settings.theme", "aurora"))
		truthy(C():Set("account.settings.minimap.minimapPos", 45.5))
		truthy(C():Set("char.ui.scale", 1.5))
		truthy(C():Set("char.ui.pos", { point = "TOPLEFT", relativePoint = "TOPLEFT", x = 100, y = -200 }))
		truthy(C():Set("char.ui.size.compact", { w = 320, h = 240 }))
		truthy(C():Set("char.ui.lastPage", "about"))
		Mock.Reload()
		eq(C():Get("account.settings.language"), "itIT")
		eq(C():Get("account.settings.theme"), "aurora")
		eq(C():Get("account.settings.minimap.minimapPos"), 45.5)
		eq(C():Get("char.ui.scale"), 1.5)
		deepEq(C():Get("char.ui.pos"), { point = "TOPLEFT", relativePoint = "TOPLEFT", x = 100, y = -200 })
		deepEq(C():Get("char.ui.size.compact"), { w = 320, h = 240 })
		Mock.Relog(86400)
		eq(C():Get("char.ui.lastPage"), "about")
		eq(C():Get("account.settings.theme"), "aurora")
		eq(#C().issues, 0)
	end)

	it("change nothing on clean data: two round trips write the same text", function()
		Mock.Reload()
		local account, char = Mock.savedText.AzerothThreatwardenDB, Mock.savedText.AzerothThreatwardenCharDB
		Mock.Reload()
		eq(Mock.savedText.AzerothThreatwardenDB, account)
		eq(Mock.savedText.AzerothThreatwardenCharDB, char)
		eq(#C().issues, 0)
	end)
end)

describe("the resets", function()
	it("Reset settings puts account.settings back, empties `corrupt` and keeps unknown keys", function()
		boot(function(M)
			M.saved = { AzerothThreatwardenDB = { schema = 1, corrupt = { { path = "p" } },
				settings = { theme = "aurora", language = "itIT", minimap = { hide = true, lock = true } } } }
		end)
		local seen = changes()
		truthy(C():ResetSettings())
		eq(C():Get("account.settings.theme"), "nebula")
		eq(C():Get("account.settings.language"), "auto")
		eq(C():Get("account.settings.minimap.hide"), false)
		eq(AzerothThreatwardenDB.settings.minimap.lock, true)
		deepEq(AzerothThreatwardenDB.corrupt, {})
		table.sort(seen)
		deepEq(seen, { "account.settings.language", "account.settings.minimap.hide", "account.settings.theme" })
	end)

	it("/atw reset's ResetWindow puts back position, sizes and scale only", function()
		truthy(C():Set("char.ui.pos", { point = "TOP", relativePoint = "TOP", x = 1, y = 1 }))
		truthy(C():Set("char.ui.size.wide", { w = 600, h = 600 }))
		truthy(C():Set("char.ui.scale", 1.2))
		truthy(C():Set("char.ui.locked", true))
		truthy(C():Set("char.ui.lastTab", "settings"))
		truthy(C():ResetWindow())
		isNil(C():Get("char.ui.pos"))
		isNil(C():Get("char.ui.size.wide"))
		eq(C():Get("char.ui.scale"), 1.0)
		eq(C():Get("char.ui.locked"), true)
		eq(C():Get("char.ui.lastTab"), "settings")
	end)
end)

describe("the saved data in /atw debug (SPEC-01 §9)", function()
	it("estimates the size of what is saved", function()
		eq(C().EstimateSize("abc"), 6)
		eq(C().EstimateSize(true), 8)
		truthy(C().EstimateSize({ a = 1, b = { "x" } }) > 20)
		local loop = {}
		loop.self = loop
		truthy(C().EstimateSize(loop) > 0, "a circular table ends")
		matches(report(), "AzerothThreatwardenDB: schema found none, current 5, about 0%.%d KB\n")
	end)

	it("lists the `corrupt` entries by path and type, never their content or a name", function()
		boot(function(M)
			M.player.name = "Uniquehero"
			M.saved = { AzerothThreatwardenCharDB = { schema = 1, ui = { pos = { point = "Uniquehero" } } } }
		end)
		local text = report()
		contains(text, "corrupt entries: 1 (at most 5 kept)\n  char.ui.pos: table found")
		contains(text, "problems corrected at load: 1\n  char.ui.pos: reset (bad shape)")
		falsy(text:find("Uniquehero", 1, true))
	end)
end)

describe("schema 2: the monitor settings (SPEC-02 §3.5)", function()
	local P = "account.settings.monitor."
	local DEFAULTS = { warning = 82, danger = 91, rate = 5, maxUnits = 40, show = "auto", sort = "relative",
		pinSelf = false, followTargetOfTarget = true }

	it("are added with their defaults, which are the one place of Q7, Q13 and Q14", function()
		deepEq(C():Get("account.settings.monitor"), DEFAULTS)
		deepEq(C().MONITOR_DEFAULTS, DEFAULTS)
		eq(Mock.ns.ThreatState.DEFAULTS.warning, 82)
		eq(Mock.ns.ThreatState.DEFAULTS.danger, 91)
		eq(Mock.ns.ThreatScanner.DEFAULTS.rate, 5)
		eq(Mock.ns.ThreatScanner.DEFAULTS.maxUnits, 40)
	end)

	it("migrate data of schema 1 (1 -> 2), keeping every value, once", function()
		boot(function(M)
			M.saved = { AzerothThreatwardenDB = { schema = 1, future = 7,
				settings = { theme = "aurora", language = "itIT", minimap = { hide = true } } } }
		end)
		eq(AzerothThreatwardenDB.schema, 5)
		eq(C().found.account, 1)
		eq(AzerothThreatwardenDB.settings.theme, "aurora")
		eq(AzerothThreatwardenDB.settings.language, "itIT")
		eq(AzerothThreatwardenDB.settings.minimap.hide, true)
		eq(AzerothThreatwardenDB.future, 7)
		deepEq(AzerothThreatwardenDB.settings.monitor, DEFAULTS)
		falsy(C():IsReadOnly())
		eq(#C().issues, 0)
		Mock.Reload()
		eq(C().found.account, 5)
		deepEq(AzerothThreatwardenDB.settings.monitor, DEFAULTS)
	end)

	it("step 2 is idempotent on data that already has the settings", function()
		local data = { schema = 1, settings = { monitor = { warning = 60 } } }
		truthy(C().Migrate("account", data, 1, 2))
		local twice = C().Copy(data)
		C().migrations.account[2](twice)
		deepEq(twice, data)
		eq(data.settings.monitor.warning, 60)
		eq(data.schema, 2)
	end)

	it("leave the character's schema at 1", function()
		eq(AzerothThreatwardenCharDB.schema, 1)
		eq(C().SCHEMAS.char, 1)
	end)

	it("accept the values within their ranges and refuse the others", function()
		local cases = {
			{ "rate", { 2, 10 }, { 1, 11, 2.5, "5" } },
			{ "maxUnits", { 5, 40 }, { 4, 41, 7.5, false } },
			{ "show", { "auto", "always", "manual" }, { "never", 1 } },
			{ "sort", { "relative", "absolute", "risk", "change" }, { "name", true } },
			{ "pinSelf", { true, false }, { "yes", 1 } },
			{ "followTargetOfTarget", { false, true }, { "no", 0 } },
			{ "warning", { 50, 86 }, { 49, 100, 80.5, "80" } },
			{ "danger", { 100, 95 }, { 59, 101, 95.5, nil } },
		}
		for _, case in ipairs(cases) do
			local key, good, bad = case[1], case[2], case[3]
			for _, value in ipairs(good) do
				truthy(C():Set(P .. key, value), key .. " " .. tostring(value))
				eq(C():Get(P .. key), value)
			end
			for _, value in pairs(bad) do
				local stored = C():Get(P .. key)
				falsy(C():Set(P .. key, value), key .. " " .. tostring(value))
				eq(C():Get(P .. key), stored)
			end
		end
		eq(select(2, C():Set("account.settings.monitor", {})), "not a value")
	end)

	it("keep danger at least 5 above warning in Set and SetThresholds", function()
		eq(select(2, C():Set(P .. "warning", 91)), "danger less than 5 above warning")
		eq(select(2, C():Set(P .. "danger", 84)), "danger less than 5 above warning")
		truthy(C():Set(P .. "warning", 86))
		local seen = {}
		Mock.ns.Bus.On("CONFIG_CHANGED", function(path)
			seen[#seen + 1] = path
			eq(C():Get(P .. "warning"), 60, "both stored before anyone hears")
			eq(C():Get(P .. "danger"), 65)
		end)
		truthy(C():SetThresholds(60, 65))
		deepEq(seen, { P .. "warning", P .. "danger" })
		truthy(C():SetThresholds(60, 65))
		eq(#seen, 2, "nothing changed, nothing said")
		falsy(C():SetThresholds(60, 64))
		falsy(C():SetThresholds(45, 90))
		falsy(C():SetThresholds(97, 102))
		eq(C():Get(P .. "warning"), 60)
		eq(#Mock.errors, 0)
	end)

	it("go back to the defaults at load when wrong, the thresholds together", function()
		boot(function(M)
			M.saved = { AzerothThreatwardenDB = { schema = 2, settings = { monitor = { warning = 90, danger = 92,
				rate = 30, maxUnits = 2, show = "never", sort = 3, pinSelf = "x", followTargetOfTarget = 0,
				other = 1 } } } }
		end)
		local want = C().Copy(DEFAULTS)
		want.other = 1
		deepEq(AzerothThreatwardenDB.settings.monitor, want)
		contains(issues(), "account.settings.monitor: thresholds reset")
		boot(function(M)
			M.saved = { AzerothThreatwardenDB = { schema = 2, settings = { monitor = { warning = 70, danger = 59 } } } }
		end)
		eq(C():Get(P .. "warning"), 70)
		eq(C():Get(P .. "danger"), 91, "a single wrong threshold keeps the other")
		boot(function(M) M.saved = { AzerothThreatwardenDB = { schema = 2, settings = { monitor = "x" } } } end)
		deepEq(AzerothThreatwardenDB.settings.monitor, DEFAULTS)
		eq(AzerothThreatwardenDB.corrupt[1].path, "account.settings.monitor")
	end)

	it("come back with Reset settings", function()
		truthy(C():SetThresholds(60, 70))
		truthy(C():Set(P .. "show", "manual"))
		truthy(C():ResetSettings())
		deepEq(C():Get("account.settings.monitor"), DEFAULTS)
	end)

	it("are refused on read-only data", function()
		boot(function(M) M.saved = { AzerothThreatwardenDB = { schema = 6 } } end)
		eq(select(2, C():SetThresholds(60, 70)), "read-only")
		eq(select(2, C():Set(P .. "rate", 3)), "read-only")
	end)

	it("survive a /reload and reach the monitor", function()
		truthy(C():SetThresholds(70, 90))
		truthy(C():Set(P .. "rate", 8))
		truthy(C():Set(P .. "maxUnits", 12))
		Mock.Reload()
		deepEq({ Mock.ns.ThreatState.Thresholds() }, { 70, 90 })
		boot(function(M)
			M.features = { monitor = true }
			M.saved = { AzerothThreatwardenDB = { schema = 2, settings = { monitor = { rate = 8, maxUnits = 12 } } } }
		end)
		eq(Mock.ns.ThreatScanner.Rate(), 8)
		eq(Mock.ns.ThreatScanner.MaxUnits(), 12)
	end)
end)

describe("schema 3: the alert settings (SPEC-02 §3.6, SPEC-04 §4.1)", function()
	local P = "account.settings.alerts."
	local DEFAULTS = { enabled = true, window = true, visual = true, sound = false, cooldown = 8, others = "tank",
		pet = true }

	it("are added with their defaults, which are the one place of Q12", function()
		deepEq(C():Get("account.settings.alerts"), DEFAULTS)
		deepEq(C().ALERTS_DEFAULTS, DEFAULTS)
		eq(Mock.ns.Alerts.Cooldown(), 8)
		deepEq(C():Get("account.settings.coach"), { enabled = true }, "the Coach's, M3.3")
		deepEq(C().COACH_DEFAULTS, { enabled = true })
	end)

	it("migrate data of schema 2 (2 -> 3), keeping every value, once", function()
		boot(function(M)
			M.saved = { AzerothThreatwardenDB = { schema = 2, future = 7,
				settings = { theme = "aurora", monitor = { warning = 70, show = "manual" } } } }
		end)
		eq(AzerothThreatwardenDB.schema, 5)
		eq(C().found.account, 2)
		eq(AzerothThreatwardenDB.settings.theme, "aurora")
		eq(AzerothThreatwardenDB.settings.monitor.warning, 70)
		eq(AzerothThreatwardenDB.settings.monitor.show, "manual")
		eq(AzerothThreatwardenDB.future, 7)
		deepEq(AzerothThreatwardenDB.settings.alerts, DEFAULTS)
		falsy(C():IsReadOnly())
		eq(#C().issues, 0)
		Mock.Reload()
		eq(C().found.account, 5)
		deepEq(AzerothThreatwardenDB.settings.alerts, DEFAULTS)
	end)

	it("step 3 is idempotent on data that already has the settings", function()
		local data = { schema = 2, settings = { alerts = { sound = true } } }
		truthy(C().Migrate("account", data, 2, 3))
		local twice = C().Copy(data)
		C().migrations.account[3](twice)
		deepEq(twice, data)
		eq(data.settings.alerts.sound, true)
		eq(data.schema, 3)
	end)

	it("leave the character's schema at 1", function()
		eq(AzerothThreatwardenCharDB.schema, 1)
		eq(C().SCHEMAS.char, 1)
	end)

	it("accept the values within their ranges and refuse the others", function()
		local cases = {
			{ "enabled", { false, true }, { "no", 0 } },
			{ "window", { false, true }, { "yes", 1 } },
			{ "visual", { false, true }, { "yes" } },
			{ "sound", { true, false }, { 1 } },
			{ "cooldown", { 3, 30 }, { 2, 31, 5.5, "8" } },
			{ "others", { "tank", "always", "never" }, { "sometimes", true } },
			{ "pet", { false, true }, { "no" } },
		}
		for _, case in ipairs(cases) do
			local key, good, bad = case[1], case[2], case[3]
			for _, value in ipairs(good) do
				truthy(C():Set(P .. key, value), key .. " " .. tostring(value))
				eq(C():Get(P .. key), value)
			end
			for _, value in ipairs(bad) do
				local stored = C():Get(P .. key)
				falsy(C():Set(P .. key, value), key .. " " .. tostring(value))
				eq(C():Get(P .. key), stored)
			end
		end
		eq(select(2, C():Set("account.settings.alerts", {})), "not a value")
	end)

	it("go back to the defaults at load when wrong, and with Reset settings", function()
		boot(function(M)
			M.saved = { AzerothThreatwardenDB = { schema = 3, settings = { alerts = { enabled = "x", cooldown = 1,
				others = "x", other = 2 } } } }
		end)
		local want = C().Copy(DEFAULTS)
		want.other = 2
		deepEq(AzerothThreatwardenDB.settings.alerts, want)
		boot(function(M) M.saved = { AzerothThreatwardenDB = { schema = 3, settings = { alerts = 3 } } } end)
		deepEq(AzerothThreatwardenDB.settings.alerts, DEFAULTS)
		truthy(C():Set(P .. "sound", true))
		truthy(C():Set(P .. "cooldown", 12))
		truthy(C():ResetSettings())
		deepEq(C():Get("account.settings.alerts"), DEFAULTS)
	end)

	it("survive a /reload and reach the alerts", function()
		truthy(C():Set(P .. "cooldown", 20))
		Mock.Reload()
		eq(C():Get(P .. "cooldown"), 20)
		eq(Mock.ns.Alerts.Cooldown(), 20)
	end)
end)

describe("schema 3: the Coach settings (SPEC-02 §3.6, SPEC-04 §4.1)", function()
	before_boot(function(M) M.features = { monitor = true, coach = true } end)
	local PATH = "account.settings.coach.enabled"

	it("are added with their default, migrated from schema 2 and kept through a /reload", function()
		eq(C():Get(PATH), true)
		eq(Mock.ns.Coach.Enabled(), true)
		boot(function(M)
			M.features = { monitor = true, coach = true }
			M.saved = { AzerothThreatwardenDB = { schema = 2, settings = { theme = "aurora" } } }
		end)
		eq(AzerothThreatwardenDB.schema, 5)
		deepEq(AzerothThreatwardenDB.settings.coach, { enabled = true })
		eq(#C().issues, 0)
		truthy(C():Set(PATH, false))
		eq(Mock.ns.Coach.Enabled(), false)
		Mock.Reload()
		eq(C():Get(PATH), false)
		eq(Mock.ns.Coach.Enabled(), false)
	end)

	it("refuse a wrong value, and go back to the default at load and with Reset settings", function()
		falsy(C():Set(PATH, "no"))
		falsy(C():Set(PATH, 0))
		eq(C():Get(PATH), true)
		eq(select(2, C():Set("account.settings.coach", {})), "not a value")
		boot(function(M)
			M.saved = { AzerothThreatwardenDB = { schema = 3, settings = { coach = { enabled = "x", other = 1 } } } }
		end)
		deepEq(AzerothThreatwardenDB.settings.coach, { enabled = true, other = 1 })
		boot(function(M) M.saved = { AzerothThreatwardenDB = { schema = 3, settings = { coach = 5 } } } end)
		deepEq(AzerothThreatwardenDB.settings.coach, { enabled = true })
		truthy(C():Set(PATH, false))
		truthy(C():ResetSettings())
		eq(C():Get(PATH), true)
	end)
end)

describe("schema 5: the thresholds decided by the owner (SPEC-09 Q7, 2026-11-26)", function()
	local P = "account.settings.monitor."

	it("are 82 / 91 for a new player, and the old defaults are 80 / 95", function()
		eq(C():Get(P .. "warning"), 82)
		eq(C():Get(P .. "danger"), 91)
		deepEq(C().OLD_THRESHOLDS, { warning = 80, danger = 95 })
		eq(C().SCHEMAS.account, 5)
		eq(#C().issues, 0)
	end)

	it("move the old defaults 80 / 95 that schema 4 saved to 82 / 91, keeping every other value, once", function()
		boot(function(M)
			M.saved = { AzerothThreatwardenDB = { schema = 4, future = 7, settings = { theme = "aurora",
				monitor = { warning = 80, danger = 95, rate = 8, sort = "risk" } } } }
		end)
		eq(AzerothThreatwardenDB.schema, 5)
		eq(C().found.account, 4)
		eq(C():Get(P .. "warning"), 82)
		eq(C():Get(P .. "danger"), 91)
		eq(C():Get(P .. "rate"), 8)
		eq(C():Get(P .. "sort"), "risk")
		eq(AzerothThreatwardenDB.settings.theme, "aurora")
		eq(AzerothThreatwardenDB.future, 7)
		eq(#C().issues, 0)
		eq(Mock.ns.ThreatState.Thresholds(), 82)
		Mock.Reload()
		eq(C().found.account, 5)
		eq(C():Get(P .. "warning"), 82)
	end)

	it("never touch thresholds the player chose, even one of the two", function()
		for _, pair in ipairs({ { 80, 90 }, { 75, 95 }, { 70, 85 }, { 82, 91 }, { 90, 95 } }) do
			boot(function(M)
				M.saved = { AzerothThreatwardenDB = { schema = 4,
					settings = { monitor = { warning = pair[1], danger = pair[2] } } } }
			end)
			eq(C():Get(P .. "warning"), pair[1], pair[1] .. "/" .. pair[2])
			eq(C():Get(P .. "danger"), pair[2], pair[1] .. "/" .. pair[2])
			eq(#C().issues, 0)
		end
	end)

	it("a 80 / 95 chosen again after the move stays: the step runs once", function()
		truthy(C():SetThresholds(80, 95))
		Mock.Reload()
		eq(C():Get(P .. "warning"), 80)
		eq(C():Get(P .. "danger"), 95)
	end)

	it("give the new defaults to data of older schemas, which never saved thresholds or saved the old ones", function()
		boot(function(M) M.saved = { AzerothThreatwardenDB = { schema = 1, settings = { theme = "warden" } } } end)
		eq(C():Get(P .. "warning"), 82)
		eq(C():Get(P .. "danger"), 91)
		boot(function(M)
			M.saved = { AzerothThreatwardenDB = { schema = 2, settings = { monitor = { warning = 80, danger = 95 } } } }
		end)
		eq(C():Get(P .. "warning"), 82)
		eq(C():Get(P .. "danger"), 91)
	end)

	it("step 5 is idempotent and safe on data without settings", function()
		local data = { schema = 4, settings = { monitor = { warning = 80, danger = 95, rate = 3 } } }
		truthy(C().Migrate("account", data, 4, 5))
		deepEq(data.settings.monitor, { warning = 82, danger = 91, rate = 3 })
		eq(data.schema, 5)
		local twice = C().Copy(data)
		C().migrations.account[5](twice)
		deepEq(twice, data)
		for _, odd in ipairs({ {}, { settings = "x" }, { settings = { monitor = 3 } } }) do
			truthy(C().Migrate("account", odd, 4, 5))
		end
	end)

	it("never rewrite data of a newer schema", function()
		boot(function(M)
			M.saved = { AzerothThreatwardenDB = { schema = 6, settings = { monitor = { warning = 80, danger = 95 } } } }
		end)
		truthy(C():IsReadOnly("account"))
		eq(AzerothThreatwardenDB.settings.monitor.warning, 80)
		eq(AzerothThreatwardenDB.settings.monitor.danger, 95)
	end)
end)

describe("schema 4: recording and sessions (SPEC-02 §3.7, SPEC-05 §2.3)", function()
	local P = "account.settings.recording."
	local DEFAULTS = { enabled = true, when = "group", rate = 2, maxSessions = 25, maxKB = 2048, notice = false }

	it("are added with their defaults, which are the one place of Q8 and Q16", function()
		deepEq(C():Get("account.settings.recording"), DEFAULTS)
		deepEq(C().RECORDING_DEFAULTS, DEFAULTS)
		deepEq(AzerothThreatwardenDB.sessions, {})
		deepEq(C().RECORD_WHEN, { "group", "instance", "always" })
		eq(C().SCHEMAS.account, 5)
		eq(C().SCHEMAS.char, 1)
	end)

	it("migrate data of schema 3 (3 -> 4) without sessions, keeping every value, once", function()
		boot(function(M)
			M.saved = { AzerothThreatwardenDB = { schema = 3, future = 7,
				settings = { theme = "aurora", alerts = { cooldown = 12 }, coach = { enabled = false } } } }
		end)
		eq(AzerothThreatwardenDB.schema, 5)
		eq(C().found.account, 3)
		eq(AzerothThreatwardenDB.settings.theme, "aurora")
		eq(AzerothThreatwardenDB.settings.alerts.cooldown, 12)
		eq(AzerothThreatwardenDB.settings.coach.enabled, false)
		eq(AzerothThreatwardenDB.future, 7)
		deepEq(AzerothThreatwardenDB.settings.recording, DEFAULTS)
		deepEq(AzerothThreatwardenDB.sessions, {})
		eq(#C().issues, 0)
		Mock.Reload()
		eq(C().found.account, 5)
		deepEq(AzerothThreatwardenDB.sessions, {})
	end)

	it("migrate data of schema 3 that already has `sessions`, which stays as it is (Storage checks it)", function()
		local old = { { id = "1-1", state = "complete", odd = true }, "not a session" }
		boot(function(M) M.saved = { AzerothThreatwardenDB = { schema = 3, sessions = old } } end)
		eq(AzerothThreatwardenDB.schema, 5)
		deepEq(AzerothThreatwardenDB.sessions, old)
		eq(#C().issues, 0)
	end)

	it("step 4 is idempotent", function()
		local data = { schema = 3, settings = { recording = { rate = 4 } }, sessions = { { id = "x" } } }
		truthy(C().Migrate("account", data, 3, 4))
		local twice = C().Copy(data)
		C().migrations.account[4](twice)
		deepEq(twice, data)
		eq(data.schema, 4)
	end)

	it("set `sessions` that is not a table aside with its type only, and start a new one", function()
		boot(function(M) M.saved = { AzerothThreatwardenDB = { schema = 4, sessions = "broken" } } end)
		deepEq(AzerothThreatwardenDB.sessions, {})
		local entry = AzerothThreatwardenDB.corrupt[1]
		eq(entry.path, "account.sessions")
		eq(entry.kind, "string")
		isNil(entry.data)
		contains(issues(), "account.sessions: reset (expected table, got string)")
	end)

	it("accept the values within their ranges and refuse the others", function()
		local cases = {
			{ "enabled", { false, true }, { "no", 0 } },
			{ "when", { "instance", "always", "group" }, { "raid", 1 } },
			{ "rate", { 1, 5 }, { 0, 6, 2.5 } },
			{ "maxSessions", { 5, 100 }, { 4, 101 } },
			{ "maxKB", { 512, 8192 }, { 511, 8193 } },
			{ "notice", { true, false }, { "yes" } },
		}
		for _, case in ipairs(cases) do
			local key, good, bad = case[1], case[2], case[3]
			for _, value in ipairs(good) do
				truthy(C():Set(P .. key, value), key .. " " .. tostring(value))
				eq(C():Get(P .. key), value)
			end
			for _, value in ipairs(bad) do
				local stored = C():Get(P .. key)
				falsy(C():Set(P .. key, value), key .. " " .. tostring(value))
				eq(C():Get(P .. key), stored)
			end
		end
		eq(select(2, C():Set("account.settings.recording", {})), "not a value")
		eq(select(2, C():Set("account.sessions", {})), "not a value")
	end)

	it("go back to the defaults at load when wrong, and with Reset settings, which keeps the sessions", function()
		boot(function(M)
			M.saved = { AzerothThreatwardenDB = { schema = 4, settings = { recording = { rate = 9, when = "x" } },
				sessions = { { id = "keep" } } } }
		end)
		deepEq(AzerothThreatwardenDB.settings.recording, DEFAULTS)
		truthy(C():Set(P .. "maxKB", 4096))
		truthy(C():ResetSettings())
		deepEq(C():Get("account.settings.recording"), DEFAULTS)
		eq(AzerothThreatwardenDB.sessions[1].id, "keep")
	end)

	it("accept the Reports tab as the last tab (M4)", function()
		truthy(C():Set("char.ui.lastTab", "reports"))
		Mock.Reload()
		eq(C():Get("char.ui.lastTab"), "reports")
	end)
end)
