-- ExportBox: the box of the export (SPEC-06 §4.6; ui-style §3.6; EXP-01, EXP-04, EXP-05, EXP-07; ADR 0001, 0018). Lua
-- 5.1; no game API (ARC-02): CreateFrame, and Core/Compat.lua through the widgets. Behind the `export` switch (with
-- `analytics` and `reports`): while it is off no frame is made and nothing is listened to.
-- Adapted from Azeroth Accord (UI/ExportBox.lua), same owner, GPL-3.0 (ADR 0012).
--
-- Data/Export.lua writes the text; this box only shows it, read-only and already selected (Widgets.CopyArea), under the
-- warning about names, for the player to copy with Ctrl+C. The text is never printed, logged, saved or sent: it lives in
-- the field until the box closes. The choices (content, format, names) stay in memory until a /reload.
--
--   ExportBox.Open("fight", id)       the export of a recorded session (also "events", "readings")
--   ExportBox.Open("compare", result) the export of a comparison of Data/Compare.lua
--   ExportBox:Hide(), :IsShown(), :GetText() (the text before "|" is doubled)
--
-- Bus (registered when the frame is made): SESSIONS_CHANGED empties the box of a deleted recording.
local ADDON_NAME, ns = ...
ns = ns or {}
ns.modules = ns.modules or {}

local Box = {}
ns.ExportBox, ns.modules.ExportBox = Box, Box

local L, Widgets, Theme = ns.L, ns.Widgets, ns.Theme
local ipairs, max = ipairs, math.max

Box.NAME = "AzerothThreatwardenExport"   -- a name, so that Esc closes it (UISpecialFrames)
Box.WIDTH, Box.HEIGHT = 640, 460
Box.content = "fight"       -- the last choice for a session, kept until a /reload
Box.format = "text"         -- the same for the format
Box.replace = nil           -- the names switch: nil is Export.ANONYMOUS_DEFAULT
Box.token = 0

local CONTENT_KEY = { fight = "EXPORT_CONTENT_FIGHT", events = "EXPORT_CONTENT_EVENTS",
	readings = "EXPORT_CONTENT_READINGS", compare = "EXPORT_CONTENT_COMPARE" }
local PROBLEM_KEY = { unknown = "EXPORT_DELETED", damaged = "REPORT_DAMAGED", recording = "REPORTS_RECORDING",
	empty = "ANALYTICS_NO_FIGHT" }

local function on() return ns.Export ~= nil and ns.Export.On() end

local function replaceNames()
	if Box.replace == nil then return ns.Export.ANONYMOUS_DEFAULT end
	return Box.replace
end

-- The content and the format shown now: a comparison has its own content; events and readings are CSV only.
local function content() if Box.kind == "compare" then return "compare" end return Box.content end
local function format() if ns.Export.CSV_ONLY[content()] then return "csv" end return Box.format end

-- The name of the enemy for the title (never part of the exported text).
local function enemyName()
	local id = Box.kind == "compare" and Box.result and Box.result.rows[1] and Box.result.rows[1].id or Box.id
	local s = id and ns.Storage.Get(id)
	local entry = s and type(s.sum) == "table" and s.mobs[s.sum.mob or 0]
	if entry and type(entry.name) == "string" and entry.name ~= "" then return entry.name end
	return L.MON_UNKNOWN_MOB
end

-- The recordings the box shows are still there.
local function present()
	if Box.kind == "compare" then
		for _, row in ipairs(Box.result and Box.result.rows or {}) do
			if row.status == "ok" and not ns.Storage.Get(row.id) then return false end
		end
		return true
	end
	return Box.id ~= nil and ns.Storage.Get(Box.id) ~= nil
end

local function say(text, token)
	local f = Box.frame
	f.status:SetText(text or "")
	Theme.Text(f.status, token or "text-3")
end

-- Empties the field and drops what was being built.
local function empty(message, token)
	Box.token = Box.token + 1
	ns.Export.Cancel()
	Box.text, Box.info = nil, nil
	Box.frame.field:Clear()
	say(message, token)
end

local function paint()
	local f = Box.frame
	local compare = Box.kind == "compare"
	local shown, chosen = content(), format()
	f.title:SetText(L.EXPORT_TITLE:format(L[CONTENT_KEY[shown]], enemyName()))
	Box.painting = true
	f.contents:SetShown(not compare)
	f.comparison:SetShown(compare)
	if compare then f.comparison:Select("compare") else f.contents:Select(shown) end
	f.formats:Select(chosen)
	Box.painting = false
	local csvOnly = ns.Export.CSV_ONLY[shown] == true
	local textButton = f.formats.buttons.text
	textButton:SetEnabled(not csvOnly)
	textButton:SetAlpha(csvOnly and 0.45 or 1)
	local replace = replaceNames()
	f.names:SetOn(replace, true)
	f.warning:SetText(replace and L.EXPORT_REPLACED or L.EXPORT_WARNING)
end

-- Builds the text of what is chosen and puts it in the field with one SetText, selected.
local function rebuild()
	local f = Box.frame
	paint()
	if not present() then empty(L.EXPORT_DELETED, "warn") return end
	empty(L.EXPORT_BUILDING)
	local mine = Box.token
	local request = { kind = content(), format = format(), id = Box.id, result = Box.result, replace = replaceNames() }
	ns.Export.Build(request, function(text, info)
		if mine ~= Box.token then return end
		if not text then
			say(L[PROBLEM_KEY[info or ""] or "EXPORT_FAILED"], "warn")
			return
		end
		Box.text, Box.info = text, info
		f.field:SetText(ns.Export.Display(text))
		local size = L.EXPORT_SIZE:format(ns.Reports.SizeText(max(1, info.bytes / 1024)))
		-- the rows left out are said here, never inside the exported text
		if info.left > 0 then
			local limit = ns.Reports.SizeText(ns.Export.MAX_TEXT / 1024)
			local left = info.left == 1 and L.EXPORT_LEFT_ONE:format(limit) or L.EXPORT_LEFT:format(info.left, limit)
			say(size .. " · " .. left, "warn")
		else
			say(size)
		end
		f.field:SelectAll()
	end)
end

local function build()
	local f = Widgets.Dialog(nil, Box.NAME, { width = Box.WIDTH, height = Box.HEIGHT, veil = false })
	f.title = Widgets.Text(f, "H1", "text-1", "LEFT")
	f.title:SetPoint("TOPLEFT", f, "TOPLEFT", 20, -18)
	f.title:SetPoint("RIGHT", f, "RIGHT", -20, 0)

	local function chooseContent(id)
		if Box.painting or Box.kind == "compare" then return end
		Box.content = id
		rebuild()
	end
	f.contents = Widgets.Segmented(f, {
		{ id = "fight", text = L.EXPORT_CONTENT_FIGHT }, { id = "events", text = L.EXPORT_CONTENT_EVENTS },
		{ id = "readings", text = L.EXPORT_CONTENT_READINGS },
	}, chooseContent)
	f.contents:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -48)
	f.comparison = Widgets.Segmented(f, { { id = "compare", text = L.EXPORT_CONTENT_COMPARE } }, function() end)
	f.comparison:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -48)
	f.formats = Widgets.Segmented(f, {
		{ id = "text", text = L.EXPORT_FORMAT_TEXT }, { id = "csv", text = L.EXPORT_FORMAT_CSV },
	}, function(id)
		if Box.painting then return end
		Box.format = id
		rebuild()
	end)
	f.formats:SetPoint("TOPRIGHT", f, "TOPRIGHT", -16, -48)
	local textButton = f.formats.buttons.text
	if textButton.SetMotionScriptsWhileDisabled then textButton:SetMotionScriptsWhileDisabled(true) end
	Widgets.Tooltip.Attach(textButton, function()
		if ns.Export.CSV_ONLY[content()] then return L.EXPORT_CSV_ONLY end
		return nil
	end, "TOP")

	f.names = Widgets.Switch(f, { small = true, on = replaceNames(), onChange = function(v)
		Box.replace = v
		rebuild()
	end })
	f.names:SetPoint("TOPLEFT", f, "TOPLEFT", 20, -90)
	f.namesLabel = Widgets.Text(f, "Small", "text-2", "LEFT")
	f.namesLabel:SetPoint("LEFT", f.names, "RIGHT", 8, 0)
	f.namesLabel:SetText(L.EXPORT_REPLACE)

	-- the warning about names, always there (EXP-05)
	f.warningIcon = f:CreateTexture(nil, "ARTWORK")
	f.warningIcon:SetTexture(ns.Assets.textures.icons.path)
	f.warningIcon:SetTexCoord(ns.Assets.IconCoords("warn"))
	f.warningIcon:SetSize(14, 14)
	f.warningIcon:SetPoint("TOPLEFT", f, "TOPLEFT", 20, -116)
	Theme.Tint(f.warningIcon, "state-warning")
	f.warning = Widgets.Text(f, "Small", "text-2", "LEFT")
	f.warning:SetPoint("LEFT", f.warningIcon, "RIGHT", 6, 0)
	f.warning:SetPoint("RIGHT", f, "RIGHT", -20, 0)

	local field = Widgets.CopyArea(f, { width = Box.WIDTH - 48, onEscape = function() Box:Hide() end })
	field:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -138)
	field:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -16, 78)
	f.field, f.edit = field, field.edit

	f.status = Widgets.Text(f, "MonoSmall", "text-3", "LEFT")
	f.status:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 20, 56)
	f.status:SetPoint("RIGHT", f, "RIGHT", -20, 0)
	f.close = Widgets.Button(f, { text = L.EXPORT_CLOSE, width = 120, style = "primary",
		onClick = function() Box:Hide() end })
	f.close:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -16, 14)
	f.hint = Widgets.Text(f, "Small", "text-2", "LEFT")
	f.hint:SetWordWrap(true)
	f.hint:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 20, 22)
	f.hint:SetPoint("RIGHT", f.close, "LEFT", -12, 0)
	f.hint:SetText(L.EXPORT_HINT)

	f:HookScript("OnHide", function() Box:Forget() end)
	if ns.Bus then
		ns.Bus.On("SESSIONS_CHANGED", function()
			if Box:IsShown() and Box.kind and not present() then empty(L.EXPORT_DELETED, "warn") end
		end)
	end
	return f
end

function Box:Frame()
	if not self.frame then self.frame = build() end
	return self.frame
end

-- Opens the box on `kind` and `subject` (see the head of the file). Returns false while the export is off or without a
-- subject.
function Box.Open(kind, subject)
	if not on() or subject == nil then return false end
	local f = Box:Frame()
	if kind == "compare" then
		Box.kind, Box.result, Box.id = "compare", subject, nil
	else
		if kind == "events" or kind == "readings" then Box.content = kind end
		Box.kind, Box.result, Box.id = "session", nil, subject
	end
	f:Open()
	rebuild()
	return true
end

-- Nothing of the text stays after the box closes.
function Box:Forget()
	if not self.frame then return end
	empty("")
	Box.kind, Box.result, Box.id = nil, nil, nil
end

function Box:Hide() if self.frame then self.frame:Hide() end end
function Box:IsShown() return self.frame ~= nil and self.frame:IsShown() end
function Box:GetText() return self.text end

if ns.addon then ns.addon.ExportBox = Box end
