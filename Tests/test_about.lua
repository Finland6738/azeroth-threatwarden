-- UI/About.lua (SPEC-03 §4.4): the Info page, opened by /atw about: logo, version, the NEBULA credits with the logo of
-- the theme, the links in copy boxes, the licence.

local function W() return AzerothThreatwarden.Window end
local function Theme() return AzerothThreatwarden.Theme end

local function open()
	W():OpenPage("about")
	local view = W():Frame().pages.settings.view
	return view.info, view
end

local ASSETS = "Interface\\AddOns\\AzerothThreatwarden\\Media\\"

describe("the Info page", function()
	it("opens with /atw about", function()
		W():Close()
		truthy(Mock.Slash("/atw about"))
		truthy(W():IsShown())
		eq(W():Tab(), "settings")
		local view = W():Frame().pages.settings.view
		eq(view.pageId, "about")
		eq(view.pager:Active(), "about")
		eq(#Mock.errors, 0)
	end)

	it("shows the logo, the name and the version of the copy", function()
		local info = open()
		eq(info.logo:GetTexture(), ASSETS .. "logo_256.tga")
		eq(info.title:GetText(), "Azeroth Threatwarden")
		eq(info.version:GetText(), "Development build")
	end)

	it("names who made it and with whom", function()
		local info = open()
		eq(info.credits:GetText(), "Created and designed by Finland. Made with the Italian guild NEBULA.")
		eq(info.permission:GetText(), "The NEBULA logo is used with the guild's permission.")
	end)

	it("shows the NEBULA logo of the theme, and follows the theme", function()
		local info = open()
		eq(info.nebula:GetTexture(), ASSETS .. "nebula_dark_256.tga")
		AzerothThreatwarden.Config:Set("account.settings.theme", "aurora")
		eq(info.nebula:GetTexture(), ASSETS .. "nebula_light_256.tga")
		AzerothThreatwarden.Config:Set("account.settings.theme", "warden")
		eq(info.nebula:GetTexture(), ASSETS .. "nebula_dark_256.tga")
		eq(Theme().Current(), "warden")
	end)

	it("links the repository and Ko-fi in copy boxes", function()
		local info = open()
		eq(info.links.repo:GetText(), "https://github.com/Finland6738/azeroth-threatwarden")
		eq(info.links.kofi:GetText(), "https://ko-fi.com/finland6738")
		eq(info.labels.kofi:GetText(), "Support the project (Ko-fi)")
	end)

	it("keeps a link as it is when the player types in its box, and selects it", function()
		local info = open()
		local edit = info.links.repo.edit
		Mock.TypeInto(edit, "something else")
		eq(edit:GetText(), "https://github.com/Finland6738/azeroth-threatwarden")
		truthy(edit._highlighted)
	end)

	it("says the licence, where the notices are and that it is a fan project", function()
		local info = open()
		eq(info.license:GetText(), "Free software under the GPL-3.0 licence.")
		contains(info.third:GetText(), "docs/third-party.md")
		contains(info.disclaimer:GetText(), "not affiliated with")
	end)

	it("has no link or name that differs from the TOC", function()
		eq(C_AddOns.GetAddOnMetadata("AzerothThreatwarden", "X-Website"), AzerothThreatwarden.About.LINKS[1].url)
		eq(C_AddOns.GetAddOnMetadata("AzerothThreatwarden", "X-License"), AzerothThreatwarden.About.LICENSE)
		contains(C_AddOns.GetAddOnMetadata("AzerothThreatwarden", "X-Credits"),
			AzerothThreatwarden.About.Lines().credits)
	end)

	it("posts nothing in the chat", function()
		Mock.ClearOutput()
		local sent = 0
		SendChatMessage = function() sent = sent + 1 end
		open()
		eq(sent, 0)
		eq(Mock.PlainOutput(), "")
	end)
end)

describe("the Info page of a release", function()
	before_boot(function(M)
		M.OnFilesLoaded(function()
			local get = C_AddOns.GetAddOnMetadata
			C_AddOns.GetAddOnMetadata = function(name, field)
				if field == "Version" then return "0.1.0" end
				return get(name, field)
			end
		end)
	end)

	it("shows its version number", function()
		eq(open().version:GetText(), "Version 0.1.0")
	end)
end)

describe("the Info page in Italian", function()
	before_boot(function(M) M.player.locale = "itIT" end)

	it("credits in Italian", function()
		local info = open()
		eq(info.credits:GetText(), "Creato e progettato da Finland. Realizzato con la gilda italiana NEBULA.")
		eq(info.version:GetText(), "Versione di sviluppo")
	end)
end)
