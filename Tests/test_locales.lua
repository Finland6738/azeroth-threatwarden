-- Adapted from Azeroth Accord (Tests/test_locales.lua), same owner, GPL-3.0 (ADR 0012).
-- ADR 0009 rule 3: this file fails when a key exists in one language table only, a string is empty, placeholders differ
-- in kind or order, a key used in the code is missing in English, or a string is identical in both languages without
-- being on the short list of intended ones (SAME below). Every file of Locales/ that the TOC loads is checked against
-- English, so a new language needs no change here but its own intended identical strings.

local ADDON = "AzerothThreatwarden/"

-- Strings that are the same as English on purpose (names, loanwords, bare numbers), per language.
local SAME = {
	itIT = { ADDON_TITLE = true, WINDOW_TITLE = true, WINDOW_TITLE_COMPACT = true, TAB_MONITOR = true,
		PAGE_ABOUT = true, THEME_NEBULA = true, THEME_AURORA = true, THEME_WARDEN = true, LANGUAGE_ENUS = true,
		LANGUAGE_ITIT = true, SET_PERCENT = true, MON_CLASS_BOSS = true, MON_DASH = true, MON_TANK = true,
		MON_TIME = true, ROLE_TANK = true, TIP_TAGGED = true, TIP_THREAT = true, MODULE_DEMO = true, SET_MONITOR = true, SET_HERTZ = true,
		SET_SECONDS = true, SET_COACH = true, REPORT_TANK_CHANGE = true, REPORT_WITH_POINTS = true,
		REPORT_ALERT_KIND = true, REPORT_ALERT_AGGRO = true, REPORTS_KB = true, REPORTS_MB = true,
		REPORTS_MB_WHOLE = true, REPORTS_TIP_LINE = true, TIMELINE_STATE = true, TIMELINE_WITH = true,
		TIMELINE_PERCENT = true, TIMELINE_GROUP = true, REPLAY_SPEED_ITEM = true, REPLAY_TIME = true,
		REPORTS_REPLAY = true, ANALYTICS_PCT_WHOLE = true, ANALYTICS_APPROX = true },
}

-- The checks, as functions that return a list of problems: the group at the end proves they find them. -----------
local function sortedKeys(t)
	local out = {}
	for k in pairs(t) do out[#out + 1] = tostring(k) end
	table.sort(out)
	return out
end

-- "%d of %s" -> "%d %s", in order (a literal %% is not a placeholder).
local function placeholders(s)
	local out = {}
	for p in s:gsub("%%%%", ""):gmatch("%%[%-%+ #0]*%d*%.?%d*[cdiouxXeEfgGqs]") do out[#out + 1] = p end
	return table.concat(out, " ")
end

-- The colour, texture, link and line-break codes of the client, in order.
local function codes(s)
	local out = {}
	for c in s:gmatch("|[cCrTtHhnAa]") do out[#out + 1] = c:lower() end
	for _ in s:gmatch("\n") do out[#out + 1] = "newline" end
	return table.concat(out, " ")
end

-- Every string of one table: an upper-case key, a non-empty text with no space at either end.
local function badStrings(name, strings)
	local problems = {}
	for _, key in ipairs(sortedKeys(strings)) do
		local text = strings[key]
		if not key:match("^[A-Z][A-Z0-9_]*$") then problems[#problems + 1] = name .. ": bad key " .. key end
		if type(text) ~= "string" then
			problems[#problems + 1] = name .. ": " .. key .. " is not a string"
		elseif text:match("^%s*$") then
			problems[#problems + 1] = name .. ": " .. key .. " is empty"
		elseif text:find("^%s") or text:find("%s$") then
			problems[#problems + 1] = name .. ": " .. key .. " has a space at an end"
		end
	end
	return problems
end

-- A translation against English.
local function differences(name, base, other, same)
	local problems = {}
	local function add(text) problems[#problems + 1] = name .. ": " .. text end
	for _, key in ipairs(sortedKeys(base)) do
		local en, text = base[key], other[key]
		if text == nil then
			add(key .. " is missing")
		elseif type(en) == "string" and type(text) == "string" then
			if placeholders(text) ~= placeholders(en) then add(key .. " has other placeholders than English") end
			if codes(text) ~= codes(en) then add(key .. " has other codes than English") end
			if text == en and not (same and same[key]) then add(key .. " is identical to English") end
		end
	end
	for _, key in ipairs(sortedKeys(other)) do
		if base[key] == nil then add(key .. " is not an English key") end
	end
	for _, key in ipairs(sortedKeys(same or {})) do
		if base[key] == nil then
			add("the intended identical list names " .. key .. ", which does not exist")
		elseif other[key] ~= base[key] then
			add("the intended identical list names " .. key .. ", which is translated")
		end
	end
	return problems
end

-- The keys a source reads: L["KEY"], L.KEY, ns.L.KEY and labelKey = "KEY"; comments do not count.
local function usedKeys(source)
	local keys = {}
	for line in (source .. "\n"):gmatch("(.-)\n") do
		local code = line:gsub("%-%-.*$", "")
		code = " " .. code
		for key in code:gmatch("[^%w_]L%[%s*\"([%w_]+)\"%s*%]") do keys[key] = true end
		for key in code:gmatch("[^%w_]L%[%s*'([%w_]+)'%s*%]") do keys[key] = true end
		for key in code:gmatch("[^%w_]L%.([A-Z][A-Z0-9_]*)") do keys[key] = true end
		for key in code:gmatch("labelKey%s*=%s*\"([%w_]+)\"") do keys[key] = true end
	end
	return sortedKeys(keys)
end

-- The tests ------------------------------------------------------------------------------------------------------
local function strings(code) return AzerothThreatwarden.Locale.Strings(code) end

-- The language codes of the files of Locales/ the TOC loads.
local function languages()
	local out = {}
	for _, name in ipairs(Mock.loadedFiles) do
		local code = name:match("^" .. ADDON .. "Locales/(%a+)%.lua$")
		if code then out[#out + 1] = code end
	end
	table.sort(out)
	return out
end

describe("the language tables (ADR 0009 rule 3)", function()
	it("include English and Italian, each registered under its file name", function()
		local codes_ = languages()
		contains(codes_, "enUS")
		contains(codes_, "itIT")
		for _, code in ipairs(codes_) do notNil(strings(code), code .. " is registered") end
	end)

	it("hold only non-empty strings under upper-case keys, with no stray space", function()
		for _, code in ipairs(languages()) do
			deepEq(badStrings(code, strings(code)), {})
		end
		truthy(#sortedKeys(strings("enUS")) >= 3, "the table was really read")
	end)

	it("have the same keys, placeholders and codes, and nothing untranslated by accident", function()
		for _, code in ipairs(languages()) do
			if code ~= "enUS" then
				deepEq(differences(code, strings("enUS"), strings(code), SAME[code]), {})
			end
		end
	end)

	it("format with sample arguments", function()
		for _, code in ipairs(languages()) do
			for key, text in pairs(strings(code)) do
				local args = {}
				for p in text:gsub("%%%%", ""):gmatch("%%[%-%+ #0]*%d*%.?%d*([cdiouxXeEfgGqs])") do
					args[#args + 1] = (p == "s" or p == "q") and "x" or 7
				end
				local ok, err = pcall(string.format, text, unpack(args))
				truthy(ok, code .. " " .. key .. " does not format: " .. tostring(err))
			end
		end
	end)

	it("hold every key the code reads (a missing one would show the key itself)", function()
		local en, missing, seen = strings("enUS"), {}, 0
		for _, name in ipairs(Mock.loadedFiles) do
			if name:find("^" .. ADDON) and not name:find("/Libs/", 1, true) and not name:find("/Locales/", 1, true) then
				local source = Mock.ReadSource(name)
				if source then
					for _, key in ipairs(usedKeys(source)) do
						seen = seen + 1
						if en[key] == nil then missing[#missing + 1] = name .. ": " .. key end
					end
				end
			end
		end
		truthy(seen >= 3, "the sources were really scanned")
		deepEq(missing, {})
	end)

	it("were asked for no missing key while the addon loaded", function()
		deepEq(AzerothThreatwarden.Locale.MissingKeys(), {})
	end)

	it("hold the Notes of the TOC in each language", function()
		notNil(C_AddOns.GetAddOnMetadata("AzerothThreatwarden", "Notes"))
		for _, code in ipairs(languages()) do
			if code ~= "enUS" then notNil(C_AddOns.GetAddOnMetadata("AzerothThreatwarden", "Notes-" .. code), code) end
		end
	end)
end)

describe("an Italian client", function()
	before_boot(function(M) M.player.locale = "itIT" end)

	it("answers in Italian without a Lua error", function()
		eq(AzerothThreatwarden.Locale.Active(), "itIT")
		AzerothThreatwarden_OnAddonCompartmentClick()
		AzerothThreatwarden_OnAddonCompartmentEnter("AzerothThreatwarden")
		contains(Mock.TooltipLines(), "Clic destro: impostazioni")
		Mock.Reload()
		eq(AzerothThreatwarden.Locale.Active(), "itIT")
		eq(#Mock.errors, 0)
	end)
end)

describe("a client in a language with no file", function()
	before_boot(function(M) M.player.locale = "frFR" end)

	it("answers in English", function()
		eq(AzerothThreatwarden.Locale.Active(), "enUS")
		eq(AzerothThreatwarden.L.COMING_SOON, "This part is coming soon.")
	end)
end)

describe("the checks themselves find", function()
	local en = { ADDON_TITLE = "Name", COUNT = "%d of %s", COLOR = "|cff000000x|r", HELLO = "Hello" }
	local good = { ADDON_TITLE = "Name", COUNT = "%d di %s", COLOR = "|cff000000y|r", HELLO = "Ciao" }
	local same = { ADDON_TITLE = true }

	local function with(key, value)
		local t = {}
		for k, v in pairs(good) do t[k] = v end
		t[key] = value
		return t
	end

	local function found(other, text, list)
		local problems = differences("xx", en, other, list or same)
		eq(#problems, 1, table.concat(problems, "; "))
		contains(problems[1], text)
	end

	it("nothing in a good table", function()
		deepEq(differences("xx", en, good, same), {})
		deepEq(badStrings("xx", good), {})
	end)

	it("a key that exists in one table only", function()
		found(with("HELLO", nil), "HELLO is missing")
		found(with("EXTRA", "Extra"), "EXTRA is not an English key")
	end)

	it("placeholders that differ in kind, order or number", function()
		found(with("COUNT", "%s di %s"), "COUNT has other placeholders")
		found(with("COUNT", "%s di %d"), "COUNT has other placeholders")
		found(with("COUNT", "%d di"), "COUNT has other placeholders")
	end)

	it("a lost colour code", function()
		found(with("COLOR", "y"), "COLOR has other codes")
	end)

	it("an untranslated string, and a stale or useless entry of the intended list", function()
		found(with("HELLO", "Hello"), "HELLO is identical to English")
		found(good, "GONE, which does not exist", { ADDON_TITLE = true, GONE = true })
		found(good, "HELLO, which is translated", { ADDON_TITLE = true, HELLO = true })
	end)

	it("empty strings, stray spaces and bad keys", function()
		local problems = badStrings("xx", { A = "", B = "  ", C = "end ", lower = "x" })
		eq(#problems, 4, table.concat(problems, "; "))
	end)

	it("the keys a source reads, and not those of comments or of other tables", function()
		deepEq(usedKeys([[
print(L["ONE"], L.TWO, ns.L["THREE"], L['FOUR'])
local tab = { labelKey = "FIVE" }
-- L["COMMENT"]
local x = URL["NOT"] .. XL.NEITHER
]]), { "FIVE", "FOUR", "ONE", "THREE", "TWO" })
	end)
end)
