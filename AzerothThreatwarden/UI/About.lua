-- About: the Info page of the Settings tab, opened by `/atw about` (SPEC-03 §4.4 and §5). Lua 5.1; no game API is
-- named here (ARC-02). Logo, version, what the addon is, who made it (Finland, with the Italian guild NEBULA, whose logo
-- follows the theme), the links, the licence. The game cannot open a web page, so every link is a copy box (click it,
-- Ctrl+C). Words come from locale keys; the names and the links are constants of this file.
-- Adapted from Azeroth Accord (UI/About.lua), same owner, GPL-3.0 (ADR 0012). Changes: it is a page of
-- Settings.AddPage built from the same cards; only the repository and Ko-fi are linked; no credits in the chat.
--
--   About.Lines()          the texts of the page: { title, version, purpose, purpose2, credits, permission, license,
--                          third, disclaimer }
--   About.Build(holder, view) -> page   draws the page; the parts are fields of view.info: .logo, .nebula (the logo of
--                          the theme), .links[id] (copy boxes), .cards
local ADDON_NAME, ns = ...
ns = ns or {}
ns.modules = ns.modules or {}

local About = {}
ns.About, ns.modules.About = About, About

local L, Widgets, Theme, Assets, Compat, Pages = ns.L, ns.Widgets, ns.Theme, ns.Assets, ns.Compat, ns.Settings
local ipairs = ipairs

About.AUTHOR = "Finland"
About.GUILD = "NEBULA"
About.LICENSE = "GPL-3.0"
-- The links in the order of the page; the label is the locale key ABOUT_LINK_<ID>.
About.LINKS = {
	{ id = "repo", labelKey = "ABOUT_LINK_REPO", url = "https://github.com/Finland6738/azeroth-threatwarden" },
	{ id = "kofi", labelKey = "ABOUT_LINK_KOFI", url = "https://ko-fi.com/finland6738" },
}

local LOGO, BADGE = 64, 64

-- "Version 0.1.0"; a copy from the repository has no packaged version.
local function version()
	local v = Compat.AddonVersion()
	if not v or v:find("@", 1, true) then return L["TOOLTIP_DEV"] end
	return L["TOOLTIP_VERSION"]:format(v)
end

function About.Lines()
	return {
		title = L["ADDON_TITLE"],
		version = version(),
		purpose = L["ABOUT_PURPOSE"],
		purpose2 = L["ABOUT_PURPOSE2"],
		credits = L["ABOUT_CREDITS_LINE"]:format(About.AUTHOR, About.GUILD),
		permission = L["ABOUT_PERMISSION"]:format(About.GUILD),
		license = L["ABOUT_LICENSE"]:format(About.LICENSE),
		third = L["ABOUT_THIRD"],
		disclaimer = L["ABOUT_DISCLAIMER"],
	}
end

-- A picture at the left and, right of it, texts that wrap in the width left. The row is as tall as the higher of the two.
local function pictureRow(card, size, texts)
	local row = CreateFrame("Frame", nil, card)
	row:SetHeight(size)
	row.picture = row:CreateTexture(nil, "ARTWORK")
	row.picture:SetSize(size, size)
	row.picture:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
	row.texts = {}
	for i, def in ipairs(texts) do
		local fs = Widgets.Text(row, def[1], def[2], "LEFT")
		fs:SetWordWrap(true)
		fs:SetText(def[3])
		if i == 1 then
			fs:SetPoint("TOPLEFT", row.picture, "TOPRIGHT", 16, -4)
		else
			fs:SetPoint("TOPLEFT", row.texts[i - 1], "BOTTOMLEFT", 0, -6)
		end
		row.texts[i] = fs
	end
	function row:Reflow(inner)
		local height = 4
		for i, fs in ipairs(self.texts) do
			fs:SetWidth(inner - size - 16)
			height = height + fs:GetStringHeight() + (i > 1 and 6 or 0)
		end
		self:SetHeight(height > size and height or size)
	end
	return row
end

-- A copy box: shows `url`, selects it when it gets the keyboard, and puts it back when the player types in it.
local function copyBox(card, url)
	local box = Widgets.EditBox(card, { height = 28 })
	box:SetText(url)
	box.url = url
	box.edit:HookScript("OnTextChanged", function(self, user)
		if user and self:GetText() ~= url then
			self:SetText(url)
			self:HighlightText()
		end
	end)
	box.edit:HookScript("OnEditFocusGained", function(self) self:HighlightText() end)
	return box
end

function About.Build(holder, view)
	local t = About.Lines()
	local page = Pages.Column(holder)
	local info = { page = page, links = {}, labels = {} }
	view.info = info

	-- 1. the addon: logo, name, version, what it does
	local c1 = Pages.StackCard(page.frame)
	local head = pictureRow(c1, LOGO, { { "DisplaySmall", "accent-text", t.title }, { "MonoSmall", "text-3", t.version } })
	head.picture:SetTexture(Assets.logos.logo_256.path)
	if head.picture.SetMaskTexture then head.picture:SetMaskTexture(Assets.textures.circle.path) end
	c1:Add(head, 0, { stretch = true })
	info.logo, info.title, info.version = head.picture, head.texts[1], head.texts[2]
	info.purpose = Pages.CardText(c1, "Body", "text-2", t.purpose, 12)
	info.purpose2 = Pages.CardText(c1, "Body", "text-2", t.purpose2, 6)

	-- 2. who made it
	local c2 = Pages.StackCard(page.frame)
	Pages.CardText(c2, "H2", "text-1", L["ABOUT_CREDITS"], 0)
	local row = pictureRow(c2, BADGE, { { "BodyMedium", "text-1", t.credits }, { "Small", "text-3", t.permission } })
	Theme.Call(row.picture, function(tex) tex:SetTexture(Assets.NebulaLogo(Theme.IsDark()).path) end)   -- by theme
	c2:Add(row, 12, { stretch = true })
	info.nebula, info.credits, info.permission = row.picture, row.texts[1], row.texts[2]

	-- 3. the links, in copy boxes
	local c3 = Pages.StackCard(page.frame)
	Pages.CardText(c3, "H2", "text-1", L["ABOUT_LINKS"], 0)
	info.linksHint = Pages.CardText(c3, "Small", "text-3", L["ABOUT_LINKS_HINT"], 4)
	for _, link in ipairs(About.LINKS) do
		info.labels[link.id] = Pages.CardText(c3, "Small", "text-2", L[link.labelKey], 12)
		info.links[link.id] = c3:Add(copyBox(c3, link.url), 4, { stretch = true })
	end

	-- 4. the licence and the notices
	local c4 = Pages.StackCard(page.frame)
	Pages.CardText(c4, "H2", "text-1", L["ABOUT_LEGAL"], 0)
	info.license = Pages.CardText(c4, "Body", "text-2", t.license, 8)
	info.third = Pages.CardText(c4, "Body", "text-2", t.third, 6)
	info.disclaimer = Pages.CardText(c4, "Small", "text-3", t.disclaimer, 12)

	page.cards = { c1, c2, c3, c4 }
	info.cards = page.cards
	return page
end

Pages.AddPage("about", { labelKey = "PAGE_ABOUT", order = 20, build = About.Build })
if ns.addon then ns.addon.About = About end
