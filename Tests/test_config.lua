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
	it("creates both variables with schema 1 and every default, with no problem", function()
		eq(AzerothThreatwardenDB.schema, 1)
		eq(AzerothThreatwardenCharDB.schema, 1)
		deepEq(AzerothThreatwardenDB.settings, { language = "auto", theme = "nebula", effects = true, animations = true,
			font = "addon", minimap = { hide = false, minimapPos = 200 } })
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
		deepEq(C().TABS, { "monitor", "settings" })
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
			AzerothThreatwardenCharDB = { schema = 1, ui = { shown = "no", locked = 0, scale = 7, lastTab = "reports",
				lastPage = "x", pos = { point = "MIDDLE", relativePoint = "CENTER", x = 1, y = 2 },
				size = { compact = { w = 10, h = 5000 }, wide = { w = "a", h = 1 } } } },
		}
	end)

	it("go back to their defaults without a Lua error", function()
		eq(#Mock.errors, 0)
		deepEq(AzerothThreatwardenDB.settings, { language = "auto", theme = "nebula", effects = true, animations = true,
			font = "addon", minimap = { hide = false, minimapPos = 200 } })
		local ui = AzerothThreatwardenCharDB.ui
		eq(ui.shown, true)
		eq(ui.locked, false)
		eq(ui.scale, 1.0)
		eq(ui.lastTab, "monitor", "reports is not a tab before M4")
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
			{ "char.ui.lastTab", "reports", "not an allowed value" },
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
		eq(AzerothThreatwardenDB.schema, 1)
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
			eq(AzerothThreatwardenDB.schema, 1)
		end
	end)
end)

describe("migrations (DAT-20)", function()
	it("have one step per version for both variables", function()
		for _, scope in ipairs({ "account", "char" }) do
			for n = 1, C().SCHEMA do eq(type(C().migrations[scope][n]), "function", scope .. " " .. n) end
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
		eq(AzerothThreatwardenDB.schema, 1)
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
			Config.SCHEMA = 3
			for n, fn in pairs(steps) do Config.migrations.account[n] = fn end
		end)
	end

	it("run in order from the stored version; the saved table keeps its identity", function()
		calls = {}
		boot(function(M)
			M.saved = { AzerothThreatwardenDB = { schema = 1, settings = { oldTheme = "aurora" } } }
			laterSchema(M, {
				[2] = function(db)
					calls[#calls + 1] = 2
					if db.settings.oldTheme ~= nil then db.settings.theme, db.settings.oldTheme = db.settings.oldTheme, nil end
				end,
				[3] = function(db) calls[#calls + 1] = 3 end,
			})
		end)
		deepEq(calls, { 2, 3 })
		eq(AzerothThreatwardenDB.schema, 3)
		eq(AzerothThreatwardenDB.settings.theme, "aurora")
		isNil(AzerothThreatwardenDB.settings.oldTheme)
		eq(C().db.account, AzerothThreatwardenDB)
		falsy(C():IsReadOnly("account"))
		C():Load()
		deepEq(calls, { 2, 3 }, "a second load runs no step")
	end)

	it("a step that fails leaves the saved data untouched and the variable read-only", function()
		boot(function(M)
			M.saved = { AzerothThreatwardenDB = { schema = 1, settings = { effects = false } } }
			laterSchema(M, {
				[2] = function(db) db.settings.effects = true end,
				[3] = function(db) db.settings.theme = "aurora"; error("boom") end,
			})
		end)
		eq(AzerothThreatwardenDB.schema, 1)
		eq(AzerothThreatwardenDB.settings.effects, false)
		isNil(AzerothThreatwardenDB.settings.theme)
		truthy(C():IsReadOnly("account"))
		falsy(C():IsReadOnly("char"))
		contains(issues(), "AzerothThreatwardenDB: migration step 3 failed, read-only")
		eq(select(2, C():Set("account.settings.theme", "warden")), "read-only")
		eq(#Mock.errors, 0)
		Mock.Reload()
		matches(Mock.savedText.AzerothThreatwardenDB, '%["effects"%]=false')
		matches(Mock.savedText.AzerothThreatwardenDB, '%["schema"%]=1')
	end)

	it("a step that is missing fails the same way", function()
		boot(function(M)
			M.saved = { AzerothThreatwardenDB = { schema = 1, settings = { theme = "aurora" } } }
			laterSchema(M, { [2] = function() end })
		end)
		truthy(C():IsReadOnly("account"))
		contains(issues(), "migration step 3 missing")
		eq(AzerothThreatwardenDB.schema, 1)
	end)
end)

describe("a newer schema (DAT-21, DAT-25)", function()
	local ACCOUNT = { schema = 2, settings = { language = "itIT", theme = "future", minimap = "x" }, future = { keep = true } }
	local CHAR = { schema = 5, ui = { lastTab = "reports", newKey = 1 } }
	before_boot(function(M) M.saved = { AzerothThreatwardenDB = ACCOUNT, AzerothThreatwardenCharDB = CHAR } end)

	it("is never rewritten: the saved tables stay as they were", function()
		truthy(C():IsReadOnly("account"))
		truthy(C():IsReadOnly("char"))
		deepEq(AzerothThreatwardenDB, ACCOUNT)
		deepEq(AzerothThreatwardenCharDB, CHAR)
		contains(issues(), "AzerothThreatwardenDB: schema 2 is newer than 1, read-only")
		contains(issues(), "AzerothThreatwardenCharDB: schema 5 is newer than 1, read-only")
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
		contains(text, "AzerothThreatwardenDB: schema found 2, current 1, about ")
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
		matches(report(), "AzerothThreatwardenDB: schema found none, current 1, about 0%.%d KB\n")
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
