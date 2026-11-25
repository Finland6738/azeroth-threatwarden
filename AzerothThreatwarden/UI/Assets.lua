-- Assets: the one table of every texture, logo and font file of the addon (docs/specs/ui-style.md sections 1 and 3).
-- Lua 5.1.
-- Adapted from Azeroth Accord (UI/Assets.lua, itself from Finland Dragon Credit Points), same owner, GPL-3.0 (ADR 0012).
-- * tools/check_addon.py reads this file: every path below exists in Media/ and every file of Media/ but the font
--   licences is listed here (so each path is written out in full, not built from the addon name); the sizes are those of
--   the TGA headers (Tests/test_assets.lua checks them).
-- * All textures are white: the theme tints them (UI/Theme.lua). `slice` is the 9-slice margin in texels.
local ADDON_NAME, ns = ...
ns = ns or {}

local Assets = {}
ns.Assets = Assets
if ns.addon then ns.addon.Assets = Assets end   -- also reachable from tests

Assets.textures = {
	rr_fill_4   = { path = "Interface\\AddOns\\AzerothThreatwarden\\Media\\rr_fill_4.tga",   w = 64,  h = 64,  slice = 4 },
	rr_fill_8   = { path = "Interface\\AddOns\\AzerothThreatwarden\\Media\\rr_fill_8.tga",   w = 64,  h = 64,  slice = 8 },
	rr_fill_12  = { path = "Interface\\AddOns\\AzerothThreatwarden\\Media\\rr_fill_12.tga",  w = 64,  h = 64,  slice = 12 },
	rr_fill_18  = { path = "Interface\\AddOns\\AzerothThreatwarden\\Media\\rr_fill_18.tga",  w = 64,  h = 64,  slice = 18 },
	rr_ring_4   = { path = "Interface\\AddOns\\AzerothThreatwarden\\Media\\rr_ring_4.tga",   w = 64,  h = 64,  slice = 4 },
	rr_ring_8   = { path = "Interface\\AddOns\\AzerothThreatwarden\\Media\\rr_ring_8.tga",   w = 64,  h = 64,  slice = 8 },
	rr_ring_12  = { path = "Interface\\AddOns\\AzerothThreatwarden\\Media\\rr_ring_12.tga",  w = 64,  h = 64,  slice = 12 },
	rr_ring_18  = { path = "Interface\\AddOns\\AzerothThreatwarden\\Media\\rr_ring_18.tga",  w = 64,  h = 64,  slice = 18 },
	shadow      = { path = "Interface\\AddOns\\AzerothThreatwarden\\Media\\shadow.tga",      w = 128, h = 128, slice = 48 },
	glow_s      = { path = "Interface\\AddOns\\AzerothThreatwarden\\Media\\glow_s.tga",      w = 128, h = 128, slice = 48 },
	glow_l      = { path = "Interface\\AddOns\\AzerothThreatwarden\\Media\\glow_l.tga",      w = 128, h = 128, slice = 56 },
	pill        = { path = "Interface\\AddOns\\AzerothThreatwarden\\Media\\pill.tga",        w = 64,  h = 32,  slice = 16 },
	circle      = { path = "Interface\\AddOns\\AzerothThreatwarden\\Media\\circle.tga",      w = 64,  h = 64 },
	blob_radial = { path = "Interface\\AddOns\\AzerothThreatwarden\\Media\\blob_radial.tga", w = 128, h = 128 },
	dash        = { path = "Interface\\AddOns\\AzerothThreatwarden\\Media\\dash.tga",        w = 8,   h = 8 },
	icons       = { path = "Interface\\AddOns\\AzerothThreatwarden\\Media\\icons.tga",       w = 256, h = 256, cell = 16 },
}

-- The addon's logo (the AddOn Compartment icon is the TOC's `## IconTexture`, logo_64) and the logos of the Italian
-- guild NEBULA for the credits (used with the guild's permission, docs/third-party.md): the dark one on the dark themes
-- (Nebula, Warden), the light one on Aurora.
Assets.logos = {
	logo_256     = { path = "Interface\\AddOns\\AzerothThreatwarden\\Media\\logo_256.tga",         w = 256, h = 256 },
	logo_64      = { path = "Interface\\AddOns\\AzerothThreatwarden\\Media\\logo_64.tga",          w = 64,  h = 64 },
	nebula_dark  = { path = "Interface\\AddOns\\AzerothThreatwarden\\Media\\nebula_dark_256.tga",  w = 256, h = 256 },
	nebula_light = { path = "Interface\\AddOns\\AzerothThreatwarden\\Media\\nebula_light_256.tga", w = 256, h = 256 },
}

-- Cells of the icon sheet, in the order of tools/make_media.py (ICON_NAMES, 16 per row), all drawn for this addon.
Assets.icons = { "chevron", "check", "cross", "dashed", "skull", "shield", "heal", "sword", "star", "gear", "arrow_up",
	"arrow_down", "lock", "eye", "dot", "plus",
	"info", "warn", "search", "filter", "copy", "trash", "edit", "calendar", "clock", "user", "users", "crown",
	"coin", "refresh", "download", "upload",
	"bell", "flag", "minus", "gem", "bag", "book", "link", "arrow_left",
	"state-safe", "state-warning", "state-danger", "state-unknown", "unlock", "tank", "trend-up", "trend-down",
	"trend-flat", "predict", "stale" }

-- Fonts (docs/third-party.md). Orbitron ships whole (it declares a Reserved Font Name): it is used for the title only, in
-- capitals, and has no middle dot or arrow. `fallback` is the game font used when SetFont fails or the player chose the
-- game's fonts ("FRIZQT" for the display face, "STANDARD" for the others).
Assets.fonts = {
	display      = { path = "Interface\\AddOns\\AzerothThreatwarden\\Media\\Fonts\\Orbitron-Bold.ttf",         fallback = "FRIZQT" },
	text         = { path = "Interface\\AddOns\\AzerothThreatwarden\\Media\\Fonts\\Outfit-Regular.ttf",        fallback = "STANDARD" },
	textMedium   = { path = "Interface\\AddOns\\AzerothThreatwarden\\Media\\Fonts\\Outfit-Medium.ttf",         fallback = "STANDARD" },
	textSemiBold = { path = "Interface\\AddOns\\AzerothThreatwarden\\Media\\Fonts\\Outfit-SemiBold.ttf",       fallback = "STANDARD" },
	mono         = { path = "Interface\\AddOns\\AzerothThreatwarden\\Media\\Fonts\\JetBrainsMono-Regular.ttf", fallback = "STANDARD" },
	monoMedium   = { path = "Interface\\AddOns\\AzerothThreatwarden\\Media\\Fonts\\JetBrainsMono-Medium.ttf",  fallback = "STANDARD" },
}

-- The logo that goes with a theme's credits: the NEBULA logo for a dark or a light surface.
function Assets.NebulaLogo(dark)
	return dark and Assets.logos.nebula_dark or Assets.logos.nebula_light
end

-- Every file path of the tables, sorted: for the offline check and the probes.
function Assets.AllPaths()
	local out = {}
	for _, group in ipairs({ Assets.textures, Assets.logos, Assets.fonts }) do
		for _, t in pairs(group) do out[#out + 1] = t.path end
	end
	table.sort(out)
	return out
end

-- Every texture file (textures and logos, not fonts): what the probes ask the client to load.
function Assets.TexturePaths()
	local out = {}
	for _, group in ipairs({ Assets.textures, Assets.logos }) do
		for _, t in pairs(group) do out[#out + 1] = t.path end
	end
	table.sort(out)
	return out
end

-- An icon of the sheet as an inline texture escape for a text ("|T...|t"), `size` points high (default 12); "" for an unknown name.
function Assets.IconText(name, size)
	local l, r, t, b = Assets.IconCoords(name)
	if not l then return "" end
	local sheet = Assets.textures.icons
	size = size or 12
	return ("|T%s:%d:%d:0:0:%d:%d:%d:%d:%d:%d|t"):format(sheet.path, size, size, sheet.w, sheet.h,
		l * sheet.w, r * sheet.w, t * sheet.h, b * sheet.h)
end

-- Texture coordinates of an icon of the sheet: left, right, top, bottom.
function Assets.IconCoords(name)
	for i, n in ipairs(Assets.icons) do
		if n == name then
			local sheet = Assets.textures.icons
			local per = sheet.w / sheet.cell
			local col, row = (i - 1) % per, math.floor((i - 1) / per)
			local s = sheet.cell / sheet.w
			return col * s, (col + 1) * s, row * s, (row + 1) * s
		end
	end
end
