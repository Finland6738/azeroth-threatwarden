-- The wording rules of SPEC-04 §2.4 (WR-01-WR-07, COA-04, COA-05) on every COACH_*, ALERT_* and REPORT_* key (the
-- report also shows no hypothesis, REC-11), in enUS and itIT (ADR 0009): no cause, no ability or class, no blame and no call to write to others, may / about for predictions and
-- never "will", short messages, the arguments of each key as Data/CoachRules.lua formats them, and a category for every
-- rule. The list of forbidden words lives here and grows when needed.

before_boot(function(M) M.features = { monitor = true, alerts = true, coach = true } end)

local LANGUAGES = { "enUS", "itIT" }

local function strings(code) return AzerothThreatwarden.Locale.Strings(code) end
local function rules() return Mock.ns.CoachRules end

-- Every COACH_*, ALERT_* and REPORT_* key of a language, sorted.
local function wordingKeys(code)
	local out = {}
	for key in pairs(strings(code)) do
		if key:find("^COACH_") or key:find("^ALERT_") or key:find("^REPORT_") then out[#out + 1] = key end
	end
	table.sort(out)
	return out
end

-- A whole word or phrase, case-insensitive, in a text (letters around it end the match).
local function has(text, phrase)
	local lower = text:lower()
	local pattern = "%f[%w]" .. phrase:lower():gsub("(%p)", "%%%1") .. "%f[%W]"
	return lower:find(pattern) ~= nil
end

-- WR-03 (COA-05): no cause.
local CAUSE = { "because", "due to", "caused by", "after your", "since you", "perché", "a causa di", "per colpa di",
	"dovuto a", "dopo il tuo" }
-- WR-04 (COA-04): no class, no ability, in either language.
local ABILITY = { "Warrior", "Rogue", "Hunter", "Mage", "Priest", "Warlock", "Paladin", "Druid", "Shaman", "Guerriero",
	"Ladro", "Cacciatore", "Mago", "Sacerdote", "Stregone", "Paladino", "Druido", "Sciamano", "Taunt", "Growl", "Feint",
	"Fade", "Cower", "Vanish", "Feign Death", "Soulshatter", "Salvation", "Mocking Blow", "Challenging Shout",
	"Challenging Roar", "Sunder Armor", "Shield Slam", "Righteous Fury", "Defensive Stance", "Bear Form", "Provocazione",
	"Ruggito", "Finta", "Svanire", "Sparizione", "Fingersi Morto", "Salvezza", "Postura Difensiva", "Forma d'Orso",
	"Furia Virtuosa" }
-- WR-05: no blame, no call to write or warn.
local BLAME = { "stole", "steal", "pulled", "fault", "blame", "chat", "tell", "warn them", "rubato", "colpa", "avvisa",
	"scrivi" }
-- WR-01: never a certainty about the future.
local CERTAIN = { "will", "is going to", "sta per", "succederà" }

-- The arguments of a text as the letters of CoachRules.KEYS: %s -> "s", %d -> "d", %.1f -> "f".
local function argsOf(text)
	local out = {}
	for p in text:gsub("%%%%", ""):gmatch("%%[%.%d]*[sdf]") do
		local kind = p:sub(-1)
		out[#out + 1] = kind == "f" and "f" or kind
	end
	return table.concat(out)
end

describe("the words of the Coach and of the alerts (SPEC-04 §2.4)", function()
	for _, code in ipairs(LANGUAGES) do
		it("never name a cause, an ability or a class, never blame (WR-03, WR-04, WR-05, " .. code .. ")", function()
			local keys = wordingKeys(code)
			truthy(#keys >= 49, "keys: " .. #keys)
			for _, key in ipairs(keys) do
				local text = strings(code)[key]
				for _, list in ipairs({ CAUSE, ABILITY, BLAME }) do
					for _, word in ipairs(list) do falsy(has(text, word), code .. " " .. key .. ": " .. word) end
				end
			end
		end)

		it("say may and about for predictions, never will (WR-01, " .. code .. ")", function()
			local may = code == "enUS" and { "may" } or { "potresti", "potrebbe" }
			local about = code == "enUS" and "about %d s" or "circa %d s"
			for _, key in ipairs(wordingKeys(code)) do
				local text = strings(code)[key]
				for _, word in ipairs(CERTAIN) do falsy(has(text, word), code .. " " .. key .. ": " .. word) end
				if text:find("%%d s%f[%A]") then contains(text, about, code .. " " .. key) end
			end
			for key in pairs(rules().PREDICTED) do
				local text, found = strings(code)[key], false
				for _, word in ipairs(may) do found = found or has(text, word) end
				-- a predicted rule says it in its message or its reason (D3's message is an invitation)
				if not found and key == "COACH_RISING" then
					text = strings(code).COACH_WHY_TREND
					for _, word in ipairs(may) do found = found or has(text, word) end
				end
				truthy(found, code .. " " .. key)
			end
			for _, key in ipairs({ "ALERT_WARNING_PREDICTED" }) do
				local text, found = strings(code)[key], false
				for _, word in ipairs(may) do found = found or has(text, word) end
				truthy(found, code .. " " .. key)
			end
		end)
	end

	it("keep the messages within 60 characters in English with the longest arguments (WR-06)", function()
		local L = strings("enUS")
		local keys = {}
		for _, key in ipairs(rules().MESSAGES) do keys[#keys + 1] = key end
		for _, key in ipairs(Mock.ns.Alerts.MESSAGES) do keys[#keys + 1] = key end
		for _, key in ipairs(keys) do
			local text = L[key]:gsub("%%s", "Abcdefghijkl"):gsub("%%d", "100"):gsub("%%%%", "%%")
			truthy(#text <= 60, key .. " is " .. #text .. " characters: " .. text)
		end
	end)

	it("have every key in both languages with the arguments CoachRules formats (ADR 0009)", function()
		local KEYS = rules().KEYS
		for _, code in ipairs(LANGUAGES) do
			local L = strings(code)
			for key, spec in pairs(KEYS) do
				local text = L[key]
				notNil(text, code .. " " .. key)
				eq(argsOf(text), spec:gsub("c", "s"), code .. " " .. key)
			end
			for _, key in ipairs(wordingKeys(code)) do
				if key:find("^COACH_") then notNil(KEYS[key], "a COACH_ key no rule formats: " .. key) end
			end
		end
		for _, key in ipairs(rules().MESSAGES) do notNil(KEYS[key], key) end
	end)

	it("give every rule a category and a priority, and only predictions a predicted base (WR-07)", function()
		local seen = {}
		for _, list in ipairs({ rules().TANK, rules().OTHER }) do
			local last = math.huge
			for _, rule in ipairs(list) do
				truthy(rule.priority < last, rule.id .. " in order of priority")
				last = rule.priority
				truthy(rule.base == "detected" or rule.base == "calculated" or rule.base == "estimated"
					or rule.base == "predicted", rule.id)
				truthy(rule.cooldown == 0 or rule.cooldown == 8 or rule.cooldown == 15, rule.id)
				seen[rule.id] = rule.base
			end
		end
		eq(seen.T4, "predicted")
		eq(seen.D3, "predicted")
		for id, base in pairs(seen) do
			if id ~= "T4" and id ~= "D3" then truthy(base ~= "predicted" and base ~= "hypothesis", id) end
		end
		eq(rules().A1.base, false)
		for _, code in ipairs(LANGUAGES) do
			for _, word in ipairs({ "CAT_DETECTED", "CAT_CALCULATED", "CAT_ESTIMATED", "CAT_PREDICTED", "CONF_HIGH",
				"CONF_MEDIUM" }) do
				notNil(strings(code)[word], code .. " " .. word)
			end
		end
	end)

	it("shows no hypothesis in the report (REC-11)", function()
		local HYPOTHESIS = { "probably", "likely", "maybe", "perhaps", "possibly", "seems", "forse", "probabilmente",
			"possibilmente", "sembra", "may", "might", "potrebbe", "potresti" }
		for _, code in ipairs(LANGUAGES) do
			local count = 0
			for key, text in pairs(strings(code)) do
				if key:find("^REPORT_") then
					count = count + 1
					for _, word in ipairs(HYPOTHESIS) do falsy(has(text, word), code .. " " .. key .. ": " .. word) end
				end
			end
			truthy(count > 80, code .. " REPORT_ keys: " .. count)
		end
	end)

	it("finds the forbidden words it looks for (the checks themselves)", function()
		truthy(has("Use Taunt now", "Taunt"))
		truthy(has("this happened because of you", "because"))
		truthy(has("You will take aggro", "will"))
		falsy(has("Willing", "will"))
		falsy(has("Image", "Mage"))
		eq(argsOf("%s is at %d %% (%.1f)"), "sdf")
	end)
end)
