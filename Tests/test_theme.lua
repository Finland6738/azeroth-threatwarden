-- UI/Theme.lua and UI/Motion.lua (docs/specs/ui-style.md 2 and 4; ADR 0015): the three themes with the same tokens,
-- the Warden values and the contrast table of the specification, the four state tokens (ST-01..ST-05), the change of
-- theme without /reload, the saved look, fonts, shapes and animations.

local function A() return AzerothThreatwarden end
local function Th() return A().Theme end
local function C() return Mock.ns.Config end
local function Mo() return A().Motion end

local THEMES = { "nebula", "aurora", "warden" }
local SURFACES = { "bg", "surface-1", "surface-2", "surface-3", "raised" }
local STATES = { "state-safe", "state-warning", "state-danger", "state-unknown" }

-- WCAG 2.x
local function luminance(token, theme)
	local r, g, b = Th().Color(token, theme)
	local function lin(c) if c <= 0.04045 then return c / 12.92 end return ((c + 0.055) / 1.055) ^ 2.4 end
	return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
end
local function contrast(a, b, theme)
	local l1, l2 = luminance(a, theme), luminance(b, theme)
	if l1 < l2 then l1, l2 = l2, l1 end
	return (l1 + 0.05) / (l2 + 0.05)
end
-- the worst contrast of the inks on the surfaces, rounded to two decimals as the specification writes it
local function worst(inks, surfaces, theme)
	local low
	for _, ink in ipairs(inks) do
		for _, surface in ipairs(surfaces) do
			local c = contrast(ink, surface, theme)
			low = low and math.min(low, c) or c
		end
	end
	return math.floor(low * 100 + 0.5) / 100
end

local function hexOf(token, theme)
	local r, g, b = Th().Color(token, theme)
	return string.format("#%02X%02X%02X", r * 255 + 0.5, g * 255 + 0.5, b * 255 + 0.5)
end

local function spec() return readFile("docs/specs/ui-style.md") end

local function near3(region, token, theme)
	local r, g, b = region:GetVertexColor()
	local er, eg, eb = Th().Color(token, theme)
	near(r, er, 1e-6, token); near(g, eg, 1e-6, token); near(b, eb, 1e-6, token)
end

describe("the themes", function()
	it("are Nebula (default), Aurora and Warden, the ones Config accepts", function()
		deepEq(Th().List(), THEMES)
		deepEq(Mock.ns.Config.THEMES, THEMES)
		eq(Th().DEFAULT, "nebula")
		eq(Th().Name("warden"), "Warden")
		falsy(Th().Has("accord"))
		truthy(Th().themes.nebula.dark); truthy(Th().themes.warden.dark); falsy(Th().themes.aurora.dark)
	end)

	it("define every token, and nothing else", function()
		local allowed = { name = true, dark = true }
		for _, token in ipairs(Th().TOKENS) do allowed[token] = true end
		for _, id in ipairs(THEMES) do
			for _, token in ipairs(Th().TOKENS) do
				local c = Th().themes[id][token]
				notNil(c, id .. " " .. token)
				for i = 1, 4 do truthy(c[i] >= 0 and c[i] <= 1, id .. " " .. token) end
			end
			for key in pairs(Th().themes[id]) do truthy(allowed[key], id .. " has the extra key " .. key) end
		end
	end)

	it("an unknown token is magenta, so a typo shows", function()
		deepEq({ Th().Color("nope") }, { 1, 0, 1, 1 })
	end)

	it("Warden has exactly the values of the table of ui-style 4.1", function()
		local section = spec():match("### 4%.1.-\n### 4%.2")
		notNil(section)
		local found = 0
		for token, value in section:gmatch("\n| `([%w%-]+)` | `(#%x%x%x%x%x%x)` |") do
			eq(hexOf(token, "warden"), value, token); found = found + 1
		end
		for token, r, g, b, a in section:gmatch("\n| `([%w%-]+)` | `rgba%((%d+),(%d+),(%d+),([%.%d]+)%)` |") do
			local cr, cg, cb, ca = Th().Color(token, "warden")
			near(cr, r / 255, 1e-6, token); near(cg, g / 255, 1e-6, token); near(cb, b / 255, 1e-6, token)
			near(ca, tonumber(a), 1e-6, token); found = found + 1
		end
		eq(found, 15, "one row for each single token")
		-- the rows that name several tokens
		for token, value in pairs({ ["text-1"] = "#EFE8D8", ["text-2"] = "#CFC5AE", ["text-3"] = "#9F9A86",
			neon = "#9BEBC0", ["neon-core"] = "#4FA37C", ok = "#5CCB8D", warn = "#F2B33D", err = "#FF6B5E",
			["grad-1"] = "#D9B57A", ["grad-2"] = "#A8D9A0", ["grad-3"] = "#5FAE86", ["grad-4"] = "#1F6B5C" }) do
			eq(hexOf(token, "warden"), value, token)
		end
	end)

	it("meet the contrast rules of ui-style 4.3 in Warden, with the numbers the specification writes", function()
		local text = { "text-1", "text-2" }
		eq(worst(text, SURFACES, "warden"), 7.00)
		eq(worst({ "text-1" }, SURFACES, "warden"), 9.83)
		eq(worst({ "text-3" }, { "bg", "surface-1", "surface-2" }, "warden"), 5.52)
		eq(worst({ "accent-text" }, { "bg", "surface-1", "surface-2" }, "warden"), 8.04)
		eq(worst({ "on-accent" }, { "accent" }, "warden"), 6.99)
		eq(worst({ "on-accent" }, { "accent-hover" }, "warden"), 9.31)
		eq(worst({ "err" }, { "surface-1" }, "warden"), 6.20)
		eq(worst({ "ok" }, { "surface-1" }, "warden"), 8.56)
		eq(worst({ "warn" }, { "surface-1" }, "warden"), 9.31)
		eq(worst({ "err" }, { "raised" }, "warden"), 4.29)
		eq(worst({ "ok" }, { "raised" }, "warden"), 5.93)
		eq(worst({ "warn" }, { "raised" }, "warden"), 6.45)
		eq(worst({ "accent" }, { "bg" }, "warden"), 7.38)
	end)

	it("are readable in every theme: text 4.5:1, muted text and non-text 3:1", function()
		for _, id in ipairs(THEMES) do
			truthy(worst({ "text-1", "text-2" }, SURFACES, id) >= 4.5, id)
			truthy(worst({ "text-3" }, { "bg", "surface-1", "surface-2" }, id) >= 3, id)
			truthy(worst({ "accent-text" }, { "bg", "surface-1", "surface-2" }, id) >= 4.5, id)
			truthy(worst({ "on-accent" }, { "accent" }, id) >= 4.5, id)
			truthy(worst({ "accent" }, { "bg" }, id) >= 3, id)
		end
	end)
end)

describe("the four state tokens (ui-style 4.2)", function()
	it("are green, amber, red and grey-blue, with a dark ink", function()
		eq(hexOf("state-safe"), "#299159"); eq(hexOf("state-warning"), "#B07309")
		eq(hexOf("state-danger"), "#E5473C"); eq(hexOf("state-unknown"), "#6F819A")
		eq(hexOf("on-state"), "#0A0F14")
	end)

	it("live outside the themes and are the same in every theme (ST-01)", function()
		for _, token in ipairs({ "state-safe", "state-warning", "state-danger", "state-unknown", "on-state" }) do
			notNil(Th().STATE[token], token)
			local first
			for _, id in ipairs(THEMES) do
				isNil(Th().themes[id][token], id .. " must not define " .. token)
				first = first or hexOf(token, id)
				eq(hexOf(token, id), first, id)
			end
		end
	end)

	it("each state has its own icon and word (ST-02), anything else is unknown", function()
		deepEq(Th().STATE_ORDER, { "safe", "warning", "danger", "unknown" })
		local icons, words = {}, {}
		for _, id in ipairs(Th().STATE_ORDER) do
			local def = Th().State(id)
			notNil(A().Assets.IconCoords(def.icon), id)
			falsy(icons[def.icon]); icons[def.icon] = true
			local word = A().L[def.labelKey]
			ne(word, def.labelKey); falsy(words[word]); words[word] = true
		end
		eq(Th().State("panic"), Th().STATES.unknown)
		eq(Th().State(nil), Th().STATES.unknown)
	end)

	it("the word reads on its fill in every state: 4.5:1, with the numbers of the specification", function()
		local expected = { 4.85, 4.86, 4.85, 4.84 }
		for i, token in ipairs(STATES) do eq(worst({ "on-state" }, { token }), expected[i], token) end
	end)

	it("the fills show on every surface of every theme: 3:1 (ST-03), with the numbers of the specification", function()
		local expected = {
			nebula = { 3.95, 3.96, 3.96, 3.95 }, aurora = { 3.23, 3.23, 3.23, 3.24 }, warden = { 3.02, 3.03, 3.03, 3.02 },
		}
		for _, id in ipairs(THEMES) do
			for i, token in ipairs(STATES) do
				local c = worst({ token }, SURFACES, id)
				truthy(c >= 3, id .. " " .. token)
				eq(c, expected[id][i], id .. " " .. token)
			end
		end
	end)

	it("have about the same luminance, so shape and word carry the meaning (ST-04)", function()
		for _, token in ipairs(STATES) do near(luminance(token), 0.215, 0.003, token) end
	end)

	it("never use the colours of the game's threat status to draw (ST-05)", function()
		for _, name in ipairs(Mock.loadedFiles) do
			if name:find("^AzerothThreatwarden/UI/") then
				falsy(Mock.ReadSource(name):find("GetThreatStatusColor", 1, true), name)
				falsy(Mock.ReadSource(name):find("StatusColor", 1, true), name)
			end
		end
	end)
end)

describe("changing theme without /reload", function()
	it("recolours every registered region at once", function()
		local f = CreateFrame("Frame")
		local tinted, solid, text = f:CreateTexture(), f:CreateTexture(), f:CreateFontString()
		Th().Tint(tinted, "accent"); Th().Fill(solid, "bg"); Th().Text(text, "text-1")
		local state = f:CreateTexture()
		Th().Tint(state, "state-danger")
		for _, id in ipairs({ "aurora", "warden", "nebula" }) do
			truthy(Th().Apply(id))
			near3(tinted, "accent", id)
			near(solid._texture[1], (Th().Color("bg", id)), 1e-6, id)
			near((text:GetTextColor()), (Th().Color("text-1", id)), 1e-6, id)
			near3(state, "state-danger", "nebula")
		end
	end)

	it("an unknown theme changes nothing", function()
		falsy(Th().Apply("nope"))
		eq(Th().Current(), "nebula")
	end)

	it("registering a region again replaces its token, and a class colour survives the change", function()
		local tex = CreateFrame("Frame"):CreateTexture()
		Th().Tint(tex, "ok"); Th().Tint(tex, "err")
		near3(tex, "err")
		local fs = CreateFrame("Frame"):CreateFontString()
		Th().Text(fs, "text-2"); Th().ClassText(fs, 0.2, 0.4, 0.6)
		Th().Apply("warden")
		near((fs:GetTextColor()), 0.2, 1e-6)
		Th().Apply("aurora")
		near((fs:GetTextColor()), (Th().Color("text-1")), 1e-6, "only the square is coloured on a light theme")
	end)

	it("recolouring a registered region allocates nothing, and Apply paints the last colour (ARC-06)", function()
		local paint = function() end
		local region = { SetVertexColor = paint, SetColorTexture = paint, SetTextColor = paint }
		local text = CreateFrame("Frame"):CreateFontString()
		Th().Tint(region, "ok")
		Th().Text(text, "text-2")
		local grown = math.huge
		for _ = 1, 3 do
			collectgarbage("collect")
			collectgarbage("stop")
			local before = collectgarbage("count")
			for i = 1, 1000 do
				Th().Tint(region, i % 2 == 0 and "ok" or "err")
				Th().Fill(region, "accent")
			end
			grown = math.min(grown, collectgarbage("count") - before)
			collectgarbage("restart")
		end
		truthy(grown < 4, "grew by " .. grown .. " KB")
		-- a class colour written over a token, and a token over the class colour, leave one colour each
		Th().ClassText(text, 0.2, 0.4, 0.6)
		Th().Text(text, "text-3")
		Th().Apply("aurora")
		near((text:GetTextColor()), (Th().Color("text-3", "aurora")), 1e-6)
		Th().TextRGB(text, 0.7, 0.1, 0.1)
		Th().Apply("warden")
		near((text:GetTextColor()), 0.7, 1e-6)
	end)

	it("Call runs now and on every Apply, and THEME_CHANGED goes on the Bus", function()
		local seen, heard = {}, {}
		Mock.ns.Bus.On("THEME_CHANGED", function(id) heard[#heard + 1] = id end)
		Th().Call({}, function(_, id) seen[#seen + 1] = id end)
		Th().Apply("warden")
		deepEq(seen, { "nebula", "warden" }); deepEq(heard, { "warden" })
	end)

	it("a region that fails to repaint does not stop the others", function()
		local armed = false
		local broken = { SetVertexColor = function() if armed then error("boom") end end }
		Th().Tint(broken, "ok")
		local good = CreateFrame("Frame"):CreateTexture()
		Th().Tint(good, "accent")
		armed = true
		truthy(Th().Apply("aurora"))
		near3(good, "accent", "aurora")
		eq(Th().applyFailures, 1)
		contains(table.concat(Th().DebugLines(), "\n"), "repaint failures: 1 (last:")
	end)

	it("the registry holds its regions weakly", function()
		collectgarbage(); collectgarbage()
		local n0 = Th().Count()
		do Th().Tint({ SetVertexColor = function() end }, "ok"); eq(Th().Count(), n0 + 1) end
		collectgarbage(); collectgarbage()
		eq(Th().Count(), n0)
	end)
end)

describe("the saved look", function()
	it("is per account, with its defaults, applied at load", function()
		local s = AzerothThreatwardenDB.settings
		eq(s.theme, "nebula"); eq(s.effects, true); eq(s.animations, true); eq(s.font, "addon")
		eq(Th().Current(), "nebula")
		truthy(Th().EffectsOn()); truthy(Th().AnimationsOn())
		isNil(AzerothThreatwardenCharDB.theme)
	end)

	it("Theme.Set saves, applies and survives /reload", function()
		truthy(Th().Set("warden"))
		eq(C():Get("account.settings.theme"), "warden")
		Mock.Reload()
		eq(Th().Current(), "warden")
	end)

	it("a theme chosen through Config is applied at once", function()
		truthy(C():Set("account.settings.theme", "aurora"))
		eq(Th().Current(), "aurora")
		C():ResetSettings()
		eq(Th().Current(), "nebula")
	end)

	it("an unknown theme is refused and a damaged saved one falls back to Nebula", function()
		local ok, why = Th().Set("nope")
		falsy(ok); eq(why, "bad value")
		AzerothThreatwardenDB.settings.theme = "mauve"
		Mock.Reload()
		eq(Th().Current(), "nebula")
	end)

	it("data of a newer schema is not rewritten: the theme is not saved", function()
		T.boot(function(M) M.saved = { AzerothThreatwardenDB = { schema = 9, settings = { theme = "warden" } } } end)
		eq(Th().Current(), "warden", "the read-only data is read")
		local ok, why = Th().Set("aurora")
		falsy(ok); eq(why, "read-only")
		eq(AzerothThreatwardenDB.settings.theme, "warden")
		eq(Th().Current(), "warden")
	end)

	it("/atw debug has a Look section with the look and the client's answers", function()
		local text = table.concat(Th().DebugLines(), "\n")
		contains(text, "theme nebula, effects on, animations on, font source addon")
		contains(text, "font objects: 18, using the game's font: 0")
		contains(text, "client: 9-slice yes")
		contains(text, "textures the client refused: 0")
		contains(Mock.ns.Diagnostics.Report(), "== Look ==")
	end)
end)

describe("fonts", function()
	it("every object is named AzerothThreatwardenFont<Id>, uses a file of the addon and has the compact ids", function()
		eq(Th().SetupFonts("addon"), 0)
		for id, size in pairs({ DisplaySmall = 12, Tab = 14, TabCompact = 11, Row = 11, RowMono = 11, Badge = 9,
			Display = 22, Body = 13 }) do
			eq(Th().fontSpecs[id][2], size, id)
		end
		for id, s in pairs(Th().fontSpecs) do
			eq(Th().FontName(id), "AzerothThreatwardenFont" .. id)
			notNil(_G["AzerothThreatwardenFont" .. id], id)
			contains(Th().Font(id):GetFont(), "Media\\Fonts\\")
			truthy(s[2] >= 9, id)
		end
	end)

	it("falls back to the game font when a file does not load", function()
		Mock.missingFonts[A().Assets.fonts.display.path] = true
		eq(Th().SetupFonts("addon"), 2, "Display and DisplaySmall")
		eq(Th().fontStatus.Display, "game"); eq(Th().fontStatus.Body, "addon")
		falsy(Th().Font("Display"):GetFont():find("Media", 1, true))
	end)

	it("the saved setting chooses the game's fonts", function()
		truthy(C():Set("account.settings.font", "game"))
		for id in pairs(Th().fontSpecs) do eq(Th().fontStatus[id], "game", id) end
		truthy(C():Set("account.settings.font", "addon"))
		eq(Th().fontStatus.Body, "addon")
	end)

	it("a text of the theme takes its font object and its token", function()
		local fs = Th().NewText(CreateFrame("Frame"), "H1", "accent-text")
		eq(fs:GetFontObject(), Th().Font("H1"))
		Th().Apply("warden")
		near((fs:GetTextColor()), 0xD9 / 255, 1e-6)
	end)
end)

describe("pixels, shapes and glows", function()
	it("Px gives one physical pixel in UI units, and works without a screen size", function()
		Mock.screen.height = 1080
		UIParent:SetScale(0.5)
		near(Th().Px(1), (768 / 1080) / 0.5, 1e-9)
		GetPhysicalScreenSize = nil
		UIParent:SetScale(1)
		near(Th().Px(2), 2, 1e-9)
	end)

	it("every sliced texture gets the margin of the table, no pixel snapping and its token", function()
		local f = CreateFrame("Frame")
		for key, a in pairs(A().Assets.textures) do
			if a.slice then
				local tex = Th().Slice(f, key, "surface-1")
				deepEq({ tex:GetTextureSliceMargins() }, { a.slice, a.slice, a.slice, a.slice }, key)
				falsy(tex:IsSnappingToPixelGrid(), key)
				near3(tex, "surface-1")
			end
		end
	end)

	it("effects off hide glows and shadows; the light theme draws glows without additive light", function()
		local f = CreateFrame("Frame")
		local glow = Th().Glow(f, "glow_s", "neon")
		local panel = Th().Panel(f, { shadow = true, highlight = true, radius = 8 })
		truthy(glow:IsShown()); truthy(panel.shadow:IsShown()); truthy(glow._additive)
		C():Set("account.settings.effects", false)
		falsy(glow:IsShown()); falsy(panel.shadow:IsShown())
		C():Set("account.settings.effects", true)
		truthy(glow:IsShown())
		Th().Apply("aurora")
		falsy(glow._additive)
		Th().GlowShow(glow, false)
		falsy(glow:IsShown())
	end)
end)

describe("motion", function()
	it("uses the three durations of the ecosystem", function()
		eq(Mo().FAST, 0.12); eq(Mo().BASE, 0.2); eq(Mo().SLOW, 0.32)
	end)

	it("a fade plays on the OUT curve and ends at its alpha", function()
		local f, done = CreateFrame("Frame"), false
		truthy(Mo().Fade(f, 0.5, nil, function() done = true end))
		Mock.FinishAnimations()
		eq(f:GetAlpha(), 0.5); truthy(done)
	end)

	it("with Animations off everything ends at once", function()
		C():Set("account.settings.animations", false)
		falsy(Mo().On())
		local f, done = CreateFrame("Frame"), false
		falsy(Mo().Fade(f, 0.25, nil, function() done = true end))
		eq(f:GetAlpha(), 0.25); truthy(done)
		local seen = {}
		falsy(Mo().Tween(f, 0.12, function(_, v) seen[#seen + 1] = v end))
		deepEq(seen, { 1 })
		isNil(f:GetScript("OnUpdate"))
	end)

	it("a tween runs from 0 to 1 on the frame's updates and then lets them go", function()
		local f, seen = CreateFrame("Frame"), {}
		truthy(Mo().Tween(f, 0.12, function(_, v) seen[#seen + 1] = v end))
		Mock.RunScript(f, "OnUpdate", 0.06)
		Mock.RunScript(f, "OnUpdate", 0.07)
		eq(seen[1], 0); near(seen[2], 0.75, 1e-9, "OUT: three quarters of the way at half the time"); eq(seen[3], 1)
		isNil(f:GetScript("OnUpdate"))
	end)

	it("a frame hidden in the middle of a tween is put in its end state", function()
		local f, last = CreateFrame("Frame"), nil
		Mo().Tween(f, 0.12, function(_, v) last = v end)
		f:Hide()
		eq(last, 1); isNil(f:GetScript("OnUpdate"))
		last = nil
		Mo().Tween(f, 0.12, function(_, v) last = v end)
		eq(last, 1, "a hidden frame does not animate")
	end)
end)
