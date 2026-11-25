-- UI/Assets.lua and Media/ (docs/specs/ui-style.md 1, 3.4, 5): every file of the table exists and is what the table
-- says, the icon sheet matches tools/make_media.py, the fonts travel with their licences and the TOC shows the logo.

local function A() return AzerothThreatwarden.Assets end

local PREFIX = "Interface\\AddOns\\AzerothThreatwarden\\"

local function repoPath(path)
	eq(path:sub(1, #PREFIX), PREFIX, path)
	return "AzerothThreatwarden/" .. path:sub(#PREFIX + 1):gsub("\\", "/")
end

local function bytes(path)
	local data = readFile(repoPath(path))
	notNil(data, "missing file " .. path)
	return data
end

-- width, height, image type, bits per pixel and the descriptor of a TGA header
local function tga(data)
	local function u16(at) return data:byte(at) + data:byte(at + 1) * 256 end
	return u16(13), u16(15), data:byte(3), data:byte(17), data:byte(18)
end

local function powerOfTwo(n)
	while n % 2 == 0 do n = n / 2 end
	return n == 1
end

describe("the textures and logos", function()
	it("every one is an uncompressed 32-bit TGA with the size of the table, powers of two", function()
		local n = 0
		for _, group in ipairs({ A().textures, A().logos }) do
			for key, t in pairs(group) do
				local w, h, kind, bits = tga(bytes(t.path))
				eq(w, t.w, key); eq(h, t.h, key)
				eq(kind, 2, key .. " uncompressed true colour"); eq(bits, 32, key)
				truthy(powerOfTwo(w) and powerOfTwo(h), key)
				n = n + 1
			end
		end
		eq(n, 20)
	end)

	it("a 9-slice margin fits twice in its texture (the pill slices left and right)", function()
		for key, t in pairs(A().textures) do
			if t.slice then truthy(t.slice * 2 <= t.w, key) end
		end
		for _, r in ipairs({ 4, 8, 12, 18 }) do
			eq(A().textures["rr_fill_" .. r].slice, r)
			eq(A().textures["rr_ring_" .. r].slice, r)
		end
	end)

	it("the NEBULA logo follows the surface: the dark one on Nebula and Warden, the light one on Aurora", function()
		local Th = AzerothThreatwarden.Theme
		for id, expected in pairs({ nebula = "nebula_dark", warden = "nebula_dark", aurora = "nebula_light" }) do
			Th.Apply(id)
			eq(A().NebulaLogo(Th.IsDark()), A().logos[expected], id)
		end
	end)

	it("the TOC shows the addon's logo as its icon", function()
		eq(Mock.ns.addon and C_AddOns.GetAddOnMetadata("AzerothThreatwarden", "IconTexture"),
			(A().logos.logo_64.path:gsub("%.tga$", "")))
	end)

	it("the client accepts every texture of the table", function()
		eq(AzerothThreatwarden.Theme.Probes().texturesRefused, 0)
		Mock.missingTextures[A().textures.circle.path] = true
		eq(AzerothThreatwarden.Theme.Probes().texturesRefused, 1)
	end)

	it("AllPaths lists every texture, logo and font once", function()
		local seen = {}
		for _, p in ipairs(A().AllPaths()) do
			falsy(seen[p], p); seen[p] = true
			bytes(p)
		end
		eq(#A().AllPaths(), 26)
		eq(#A().TexturePaths(), 20)
	end)
end)

describe("the fonts", function()
	it("every font file is a TrueType font and its family has its OFL text", function()
		local n = 0
		for key, f in pairs(A().fonts) do
			local data = bytes(f.path)
			eq(data:sub(1, 4), "\0\1\0\0", key)
			truthy(f.fallback == "FRIZQT" or f.fallback == "STANDARD", key)
			local family = f.path:match("([^\\]+)%-[^\\]+%.ttf$")
			local licence = readFile("AzerothThreatwarden/Media/Fonts/" .. family .. "-OFL.txt")
			notNil(licence, family)
			contains(licence:upper(), "SIL OPEN FONT LICENSE", family)
			n = n + 1
		end
		eq(n, 6)
	end)
end)

describe("the icon sheet", function()
	local function names()
		local source = readFile("tools/make_media.py")
		local list = source:match("ICON_NAMES = (%b[])")
		notNil(list)
		local out = {}
		for name in list:gmatch('"([%w_%-]+)"') do out[#out + 1] = name end
		return out
	end

	it("has the names of tools/make_media.py, in the same order", function()
		deepEq(A().icons, names())
	end)

	it("has the icons of ui-style 3.4", function()
		for _, name in ipairs({ "state-safe", "state-warning", "state-danger", "state-unknown", "lock", "unlock", "tank",
			"trend-up", "trend-down", "trend-flat", "predict", "stale", "cross", "check", "chevron" }) do
			notNil(A().IconCoords(name), name)
		end
		isNil(A().IconCoords("nope"))
		eq(A().IconText("nope"), "")
		contains(A().IconText("tank", 10), "Media\\icons.tga:10:10")
	end)

	-- the alpha of one cell of the sheet, as a string, whatever the row order of the file
	local function cell(data, name)
		local sheet = A().textures.icons
		local l, _, t = A().IconCoords(name)
		local x0, y0 = l * sheet.w, t * sheet.h
		local _, _, _, _, descriptor = tga(data)
		local topDown = math.floor(descriptor / 32) % 2 == 1
		local out = {}
		for y = y0, y0 + sheet.cell - 1 do
			local row = topDown and y or (sheet.h - 1 - y)
			local at = 18 + data:byte(1) + (row * sheet.w + x0) * 4
			for x = 0, sheet.cell - 1 do out[#out + 1] = data:sub(at + x * 4 + 4, at + x * 4 + 4) end
		end
		return table.concat(out)
	end

	it("every icon is drawn, and the four state icons are four different shapes (ST-04)", function()
		local data = bytes(A().textures.icons.path)
		local blank = string.rep("\0", 256)
		for _, name in ipairs(A().icons) do ne(cell(data, name), blank, name) end
		local shapes = {}
		for _, name in ipairs({ "state-safe", "state-warning", "state-danger", "state-unknown" }) do
			local c = cell(data, name)
			for other, o in pairs(shapes) do
				local differ = 0
				for i = 1, #c do
					if math.abs(c:byte(i) - o:byte(i)) > 127 then differ = differ + 1 end
				end
				truthy(differ >= 30, name .. " and " .. other .. " differ in " .. differ .. " pixels")
			end
			shapes[name] = c
		end
	end)
end)
