-- The language setting (SPEC-09 Q5, SPEC-01 §10 ARC-14, ADR 0009 and its update): `account.settings.language` of
-- Core/Config.lua is the one place; Core/Locale.lua applies it at ADDON_LOADED. `auto` follows GetLocale() (enGB is
-- English, a language without a file is English), `enUS` and `itIT` force it, a change takes effect after /reload.

local function Locale() return Mock.ns.Locale end
local function L() return Mock.ns.L end
local function Config() return Mock.ns.Config end

local function language(code)
	return function(M) M.saved = { AzerothThreatwardenDB = { schema = 1, settings = { language = code } } } end
end
local function client(code)
	return function(M) M.player.locale = code end
end

-- Two strings that differ between the two tables: English and Italian.
local EN, IT = "This part is coming soon.", "Questa parte arriva presto."

describe("auto follows the client", function()
	it("English client: English", function()
		eq(Config():Get("account.settings.language"), "auto")
		eq(Locale().Active(), "enUS")
		eq(L().COMING_SOON, EN)
	end)

	it("Italian client: Italian", function()
		boot(client("itIT"))
		eq(Locale().Active(), "itIT")
		eq(L().COMING_SOON, IT)
	end)

	it("enGB is English, a client language without a file falls back to English", function()
		for _, code in ipairs({ "enGB", "deDE", "frFR", "zhCN" }) do
			boot(client(code))
			eq(Locale().Active(), "enUS", code)
			eq(L().COMING_SOON, EN, code)
		end
	end)
end)

describe("enUS and itIT force the language", function()
	it("English on an Italian client", function()
		boot(function(M) client("itIT")(M); language("enUS")(M) end)
		eq(Locale().Active(), "enUS")
		eq(L().COMING_SOON, EN)
	end)

	it("Italian on an English or a German client", function()
		for _, code in ipairs({ "enUS", "deDE" }) do
			boot(function(M) client(code)(M); language("itIT")(M) end)
			eq(Locale().Active(), "itIT", code)
			eq(L().COMING_SOON, IT, code)
		end
	end)

	it("a key Italian lacks still answers in English", function()
		boot(language("itIT"))
		Locale().Strings("itIT").COMING_SOON = nil
		eq(L().COMING_SOON, EN)
	end)

	it("a saved language that is not allowed goes back to auto (DAT-22)", function()
		boot(function(M) client("itIT")(M); language("deDE")(M) end)
		eq(Config():Get("account.settings.language"), "auto")
		eq(Locale().Active(), "itIT")
		contains(table.concat(Config().issues, "\n"), "account.settings.language: reset (not an allowed value)")
	end)
end)

describe("a change in the settings", function()
	it("takes effect after /reload, not before", function()
		truthy(Config():Set("account.settings.language", "itIT"))
		eq(Locale().Active(), "enUS", "the interface does not change under the player's eyes")
		eq(L().COMING_SOON, EN)
		Mock.Reload()
		eq(Locale().Active(), "itIT")
		eq(L().COMING_SOON, IT)
		truthy(Config():Set("account.settings.language", "auto"))
		Mock.Reload()
		eq(Locale().Active(), "enUS")
	end)

	it("survives a logout too", function()
		truthy(Config():Set("account.settings.language", "itIT"))
		Mock.Relog(600)
		eq(Locale().Active(), "itIT")
	end)

	it("keeps the same L table for the modules that hold it", function()
		boot(language("itIT"))
		eq(Mock.ns.addon.L, L())
		eq(L().COMING_SOON, IT)
	end)

	it("is shown in /atw debug", function()
		boot(function(M) client("itIT")(M); language("enUS")(M) end)
		local text = Mock.ns.Diagnostics.Report()
		contains(text, "client language: itIT")
		contains(text, "language: setting enUS, active enUS")
	end)

	it("of a read-only account still picks the language it holds", function()
		boot(function(M) M.saved = { AzerothThreatwardenDB = { schema = 7, settings = { language = "itIT" } } } end)
		truthy(Config():IsReadOnly("account"))
		eq(Locale().Active(), "itIT")
	end)
end)

describe("the list of languages", function()
	it("is the same in Config and in Locales/: every choice but auto has its file, every file is a choice", function()
		local choices = {}
		for _, code in ipairs(Config().LANGUAGES) do
			choices[code] = true
			if code ~= "auto" then notNil(Locale().Strings(code), code) end
		end
		eq(Config().LANGUAGES[1], "auto")
		local files = 0
		for _, name in ipairs(Mock.loadedFiles) do
			local code = name:match("^AzerothThreatwarden/Locales/(%a+)%.lua$")
			if code then
				files = files + 1
				truthy(choices[code], code .. " is in Config.LANGUAGES")
			end
		end
		eq(files, #Config().LANGUAGES - 1)
	end)
end)
