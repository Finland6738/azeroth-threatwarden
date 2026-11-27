-- Nothing on screen without a locale key (ADR 0009, SPEC-01 §12): before the interface is built, every string of the
-- language table is replaced by a marker that keeps its placeholders. Whatever a widget of the addon then shows must
-- be made of markers; the only other texts are the proper names, numbers and addresses listed here. The same screens
-- are walked in Italian, where no English sentence may remain.

local MARK = "\194\171"   -- « opens a marker, » closes it
local END = "\194\187"

-- Replaces each string of `code` by «KEY», followed by its placeholders so that string.format still works.
local function mark(code)
	local strings = AzerothThreatwarden.Locale.Strings(code)
	for key, text in pairs(strings) do
		local holders = {}
		for p in text:gsub("%%%%", ""):gmatch("%%[%-%+ #0]*%d*%.?%d*[cdiouxXeEfgGqs]") do holders[#holders + 1] = " " .. p end
		strings[key] = MARK .. key .. table.concat(holders) .. END
	end
end

-- Texts that are not language: addresses and what the theme or the client gives.
local PLAIN = {
	["https://github.com/Finland6738/azeroth-threatwarden"] = true,
	["https://ko-fi.com/finland6738"] = true,
}

-- Every window of the addon, opened on every page.
local function build()
	local ATW = AzerothThreatwarden
	local W = ATW.Window
	W:Open()
	W:SelectTab("settings")
	W:OpenPage("about")
	W:OpenPage("settings")
	ATW.Settings.panel:Show()
	ATW.Settings.panel.view:ShowPage("about")
	ATW.Settings.panel.view:ShowPage("settings")
	ATW.Diagnostics.Show()
	-- the states a click brings on
	local f = W:Frame().pages.settings.view.settings
	f.reset:Click()
	return { W:Frame(), ATW.Settings.panel }
end

-- Every widget under `root`: its children and regions.
local function walk(root, out)
	out[#out + 1] = root
	for _, child in ipairs({ root:GetChildren() }) do walk(child, out) end
	for _, region in ipairs({ root:GetRegions() }) do walk(region, out) end
	return out
end

-- The texts shown by the widgets under the roots, and by the diagnostic box's own parts (not its report).
local function texts(roots)
	local out = {}
	for _, root in ipairs(roots) do
		for _, widget in ipairs(walk(root, {})) do
			local kind = widget:GetObjectType()
			if (kind == "FontString" or kind == "EditBox") and type(widget:GetText()) == "string" then
				local text = widget:GetText()
				if text ~= "" then out[#out + 1] = text end
			end
		end
	end
	return out
end

-- What is left of a text once markers, numbers, punctuation and game codes are taken out.
local function leftover(text)
	if PLAIN[text] then return "" end
	local rest = text:gsub("|T.-|t", ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
	rest = rest:gsub(MARK, "{"):gsub(END, "}")
	local removed = 1   -- a marker may hold another (a state inside "Threat monitor: %s"): innermost first
	while removed > 0 do rest, removed = rest:gsub("{[^{}]*}", "") end
	return (rest:gsub("[%d%p%s]", ""))
end

describe("nothing on screen without a locale key", function()
	before_boot(function(M) M.OnFilesLoaded(function() mark("enUS") end) end)

	it("in the window, its pages and the game's panel", function()
		local roots = build()
		local shown, bad = texts(roots), {}
		for _, text in ipairs(shown) do
			if leftover(text) ~= "" then bad[#bad + 1] = text end
		end
		deepEq(bad, {})
		truthy(#shown > 40, "the screens were really read: " .. #shown)
		eq(#Mock.errors, 0)
	end)

	it("in the diagnostic box, besides the report (English by rule)", function()
		AzerothThreatwarden.Diagnostics.Show()
		local box = AzerothThreatwarden.DiagnosticsBox
		local shown = 0
		for _, widget in ipairs(walk(box.frame, {})) do
			if widget:GetObjectType() == "FontString" and widget:GetText() ~= "" then
				shown = shown + 1
				eq(leftover(widget:GetText()), "", widget:GetText())
			end
		end
		truthy(shown >= 3)
	end)

	it("in the tooltips of the minimap button", function()
		AzerothThreatwarden_OnAddonCompartmentEnter("AzerothThreatwarden")
		local lines = Mock.TooltipLines()
		truthy(#lines >= 5)
		for _, line in ipairs(lines) do eq(leftover(line), "", line) end
	end)

	it("and the check itself finds a literal text", function()
		eq(leftover("Hello"), "Hello")
		eq(leftover(MARK .. "KEY" .. END .. " 100%"), "")
	end)
end)

describe("nothing on screen without a locale key, with Analytics on", function()
	before_boot(function(M)
		M.features = { monitor = true, recording = true, reports = true, analytics = true, replay = true,
			timeline = true, export = true }
		M.OnFilesLoaded(function() mark("enUS") end)
	end)

	it("in the Analytics page, the report's card and the export box", function()
		local S, St = Mock.ns.Session, Mock.ns.Storage
		for i = 1, 2 do
			local s = S.New{ id = "txt-" .. i, started = 1767225600 + i, group = "party", diff = 1,
				rec = { hz = 2, warning = 80, danger = 95 } }
			S.AddUnit(s, { name = "Testchar", role = "DAMAGER", token = "player", me = true }, 0)
			S.AddMob(s, { name = "Gorrak", class = "elite", npc = 448 }, 0)
			for _, e in ipairs({ { 0, "C", 0, 0, 0, "1" }, { 0, "M", 0, 0, 0, "v" }, { 0, "T", 1 },
				{ 0, "S", 1, 1, 0, "S", "-" }, { 400, "c" } }) do
				S.AddEvent(s, e[1], e[2], e[3], e[4], e[5], e[6], e[7])
			end
			S.AddRow(s, 50, 1, 1, 400, "0")
			s.q.v[1] = 100
			S.Join(s)
			s.state, s.ended, s.dur, s.fight = "complete", "combat", 400, 400
			St.Add(s)
			St.Closed(s, true)
		end
		local W = AzerothThreatwarden.Window
		W:Open()
		W:SelectTab("reports")
		local view = W:Frame().pages.reports.view
		view:Layout(900, 600)
		view:Select("txt-1")
		for _ = 1, 100 do Mock.Advance(0.05) end
		local roots = { W:Frame() }
		local function check()
			local shown, bad = texts(roots), {}
			for _, text in ipairs(shown) do
				-- invented names of the fight, dates and numbers are not language
				local plain = text:gsub("Gorrak", ""):gsub("Testchar", ""):gsub("·", ""):gsub("–", ""):gsub("…", "")
				local rest = leftover(plain)
				if rest ~= "" then bad[#bad + 1] = text end
			end
			deepEq(bad, {})
		end
		check()
		view.segmented.buttons.analytics:Click()
		view.analyticsPage.rows[1]:Click()
		for _ = 1, 100 do Mock.Advance(0.05) end
		truthy(view.analyticsPage.compare.table:IsShown())
		check()
		-- the export box: every label of it (the field holds the export itself, in the words of the keys)
		for _, open in ipairs({ view.analyticsPage.compare.buttons.export, "txt-1" }) do
			if type(open) == "string" then truthy(Mock.ns.ExportBox.Open("fight", open)) else open:Click() end
			for _ = 1, 100 do Mock.Advance(0.05) end
			local box = Mock.ns.ExportBox.frame
			local shown = 0
			for _, widget in ipairs(walk(box, {})) do
				if widget:GetObjectType() == "FontString" and (widget:GetText() or "") ~= "" then
					local plain = widget:GetText():gsub("Gorrak", ""):gsub("·", ""):gsub("…", "")
					shown = shown + 1
					eq(leftover(plain), "", widget:GetText())
				end
			end
			truthy(shown >= 8, "the box was really read: " .. shown)
		end
		eq(#Mock.errors, 0)
	end)
end)

describe("the screens in Italian", function()
	before_boot(function(M) M.player.locale = "itIT" end)

	it("show no English text that has an Italian one", function()
		local ATW = AzerothThreatwarden
		local en, it_ = ATW.Locale.Strings("enUS"), ATW.Locale.Strings("itIT")
		local translated = {}
		for key, text in pairs(en) do
			if it_[key] ~= text then translated[text] = key end
		end
		local found = {}
		for _, text in ipairs(texts(build())) do
			if translated[text] then found[#found + 1] = translated[text] .. ": " .. text end
		end
		deepEq(found, {})
	end)
end)

describe("nothing on screen without a locale key, with the Dungeon Focus", function()
	before_boot(function(M)
		M.features = { monitor = true, multitarget = true, recording = false }
		M.OnFilesLoaded(function() mark("enUS") end)
	end)

	it("in the pull bar, the list, their tooltips and the Settings card", function()
		local ATW = AzerothThreatwarden
		ATW.Window:Open()
		ATW.Demo.Start()
		Mock.Advance(0.3)
		truthy(ATW.FocusList.SetOpen(true))
		local view = ATW.ThreatList.view
		view:Layout(420, 320)
		local shown = texts({ view })
		local function tooltipOf(widget)
			Mock.RunScript(widget, "OnEnter")
			for _, line in ipairs(ATW.Widgets.Tooltip.Lines()) do shown[#shown + 1] = line end
		end
		tooltipOf(view.focus.bar)
		for _, w in ipairs(view.focus.rows) do
			if w:IsShown() then tooltipOf(w) end
		end
		ATW.Window:SelectTab("settings")
		for _, text in ipairs(texts({ ATW.Window.frame.pages.settings })) do shown[#shown + 1] = text end
		local bad = {}
		for _, text in ipairs(shown) do
			-- the invented names of the demo's units are not language
			local plain = text:gsub("Brannok", ""):gsub("Sela", ""):gsub("Kor", ""):gsub("·", ""):gsub("—", "")
				:gsub("…", "")
			if leftover(plain) ~= "" then bad[#bad + 1] = text end
		end
		deepEq(bad, {})
		truthy(#shown > 40, "the screens were really read: " .. #shown)
		eq(#Mock.errors, 0)
	end)
end)
