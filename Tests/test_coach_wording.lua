-- The wording rules of SPEC-04 §2.4 (WR-01-WR-07, COA-04, COA-05) on every COACH_*, ALERT_*, REPORT_*, TIMELINE_*,
-- REPLAY_* and ANALYTICS_* key (report, timeline, replay and analytics also show no hypothesis, REC-11, RPL-03; analytics
-- no word of merit or ranking, ANA-01), in enUS and itIT (ADR 0009): no cause, no ability or class (the one advice
-- about spells is the generic "lower ranks", SPEC-09 Q7/Q11), no blame and no call to write to others, may / about for
-- predictions and
-- never "will", short messages, the arguments of each key as Data/CoachRules.lua formats them, and a category for every
-- rule. The list of forbidden words lives here and grows when needed.

before_boot(function(M) M.features = { monitor = true, alerts = true, coach = true } end)

local LANGUAGES = { "enUS", "itIT" }

local function strings(code) return AzerothThreatwarden.Locale.Strings(code) end
local function rules() return Mock.ns.CoachRules end

local PREFIXES = { "COACH_", "ALERT_", "REPORT_", "TIMELINE_", "REPLAY_", "ANALYTICS_" }

-- Every key of a language that the wording rules cover, sorted.
local function wordingKeys(code)
	local out = {}
	for key in pairs(strings(code)) do
		for _, prefix in ipairs(PREFIXES) do
			if key:sub(1, #prefix) == prefix then out[#out + 1] = key end
		end
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

	-- SPEC-09 Q7 and Q11, the owner's decision of 2026-11-26: the damage dealer and the healer are told what to do (ease
	-- off with fewer casts or lower ranks at Warning, stop for a moment at Danger); "lower ranks" is the one advice about
	-- spells WR-04 allows, generic: never a rank number, never a spell; a tank is never told to stop or ease off.
	local ACTION = {
		enUS = { ease = "ease off", ranks = "lower ranks", damage = "stop damage", healing = "stop healing" },
		itIT = { ease = "rallenta", ranks = "rank più bassi", damage = "smetti di fare danni", healing = "smetti di curare" },
	}
	-- A phrase in a text, ignoring the case of ASCII letters only (string.lower would change the bytes of "ù").
	local function says(text, phrase)
		local function low(x) return (x:gsub("[A-Z]", string.lower)) end
		return low(text):find(low(phrase), 1, true) ~= nil
	end
	local STOP = { "stop", "ease off", "pause", "smetti", "fermati", "rallenta", "interrompi" }
	local TANK_KEYS = { "ALERT_WARNING_TANK", "ALERT_DANGER_TANK", "ALERT_MARGIN_WARNING", "ALERT_MARGIN_WARNING_STATE",
		"ALERT_MARGIN_DANGER", "ALERT_MARGIN_DANGER_STATE", "ALERT_BEHIND", "ALERT_LOST" }

	for _, code in ipairs(LANGUAGES) do
		it("tell the damage dealer and the healer what to do at Warning and Danger (Q7, " .. code .. ")", function()
			local L, A = strings(code), ACTION[code]
			for _, key in ipairs({ "ALERT_WARNING", "COACH_WARNING", "COACH_WARNING_HEALER" }) do
				truthy(says(L[key], A.ease), code .. " " .. key)
				truthy(says(L[key], A.ranks), code .. " " .. key)
			end
			for _, key in ipairs({ "ALERT_DANGER", "COACH_DANGER" }) do truthy(says(L[key], A.damage), code .. " " .. key) end
			for _, key in ipairs({ "ALERT_DANGER_HEALER", "COACH_DANGER_HEALER" }) do
				truthy(says(L[key], A.healing), code .. " " .. key)
			end
			-- the state-only forms say what is known, without numbers
			for _, key in ipairs({ "ALERT_WARNING_STATE", "COACH_WARNING_STATE" }) do
				eq(argsOf(L[key]), "", code .. " " .. key)
			end
		end)

		it("speak of ranks only as generic lower ranks, never a number, and never tell a tank to stop (" .. code .. ")",
			function()
			local L, A = strings(code), ACTION[code]
			for _, key in ipairs(wordingKeys(code)) do
				local text = L[key]
				if has(text, "rank") or has(text, "ranks") then
					truthy(says(text, A.ranks), code .. " " .. key .. ": only generic lower ranks")
				end
				falsy(says(text, "rank %") or text:lower():find("ranks?%s*%d"), code .. " " .. key .. ": a rank number")
				falsy(has(text, "grado") or has(text, "gradi"), code .. " " .. key)
			end
			for _, key in ipairs(TANK_KEYS) do
				for _, word in ipairs(STOP) do falsy(has(L[key], word), code .. " " .. key .. ": " .. word) end
			end
			for key, text in pairs(L) do
				if key:find("^COACH_TANK_") then
					for _, word in ipairs(STOP) do falsy(has(text, word), code .. " " .. key .. ": " .. word) end
				end
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

	it("shows no hypothesis in the report, the timeline and the replay (REC-11, RPL-03)", function()
		local HYPOTHESIS = { "probably", "likely", "maybe", "perhaps", "possibly", "seems", "forse", "probabilmente",
			"possibilmente", "sembra", "may", "might", "potrebbe", "potresti" }
		local atLeast = { REPORT_ = 80, TIMELINE_ = 80, REPLAY_ = 40, ANALYTICS_ = 40 }
		for _, code in ipairs(LANGUAGES) do
			for prefix, minimum in pairs(atLeast) do
				local count = 0
				for key, text in pairs(strings(code)) do
					if key:sub(1, #prefix) == prefix then
						count = count + 1
						for _, word in ipairs(HYPOTHESIS) do falsy(has(text, word), code .. " " .. key .. ": " .. word) end
					end
				end
				truthy(count > minimum, code .. " " .. prefix .. " keys: " .. count)
			end
		end
	end)

	-- ANA-01 (SPEC-06 §1.1): Analytics describes, it never ranks people, judges or declares a trend between fights.
	local MERIT = { "best", "worst", "better", "worse", "good", "bad", "great", "poor", "excellent", "perfect",
		"improving", "improved", "getting worse", "well done", "mistake", "top", "ranking", "rank", "winner", "loser",
		"migliore", "peggiore", "meglio", "peggio", "bravo", "brava", "bene", "male", "ottimo", "pessimo", "perfetto",
		"migliorato", "peggiorato", "miglioramento", "peggioramento", "errore", "sbaglio", "classifica", "vincitore" }

	it("never rank, judge or declare a trend in the words of Analytics (ANA-01)", function()
		for _, code in ipairs(LANGUAGES) do
			local count = 0
			for key, text in pairs(strings(code)) do
				if key:sub(1, #"ANALYTICS_") == "ANALYTICS_" then
					count = count + 1
					for _, list in ipairs({ MERIT, BLAME }) do
						for _, word in ipairs(list) do falsy(has(text, word), code .. " " .. key .. ": " .. word) end
					end
				end
			end
			truthy(count >= 40, code .. " ANALYTICS_ keys: " .. count)
		end
		truthy(has("This was the best pull", "best"))
		falsy(has("Bestow", "best"))
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
