-- Diagnostics box: `/atw debug` opens the report of Core/Diagnostics.lua in a read-only multi-line edit box, already
-- selected, so the player presses Ctrl+C and pastes it into a bug report (addons cannot reach the clipboard). Esc
-- closes it (SPEC-01 §9, ARC-13). Lua 5.1.
-- Adapted from Azeroth Accord (UI/DiagnosticsBox.lua), same owner, GPL-3.0 (ADR 0012). Since M1.6 it is a
-- Widgets.Dialog without a veil (it can be moved) in the look of the addon; since M6.5 its read-only field is
-- Widgets.CopyArea, shared with the export box.
-- No game API is called from here (ARC-02, Tests/test_api_boundary.lua): frames are made with CreateFrame, everything
-- else of the client comes through Core/Compat.lua.
local ADDON_NAME, ns = ...
ns = ns or {}
ns.modules = ns.modules or {}

local Box = {}
ns.DiagnosticsBox, ns.modules.DiagnosticsBox = Box, Box

local L = ns.L
Box.NAME = "AzerothThreatwardenDiagnosticsBox"   -- a name, so that Esc closes it (UISpecialFrames)
Box.WIDTH, Box.HEIGHT = 640, 460

local function build()
	local Widgets, Theme = ns.Widgets, ns.Theme
	local f = Widgets.Dialog(nil, Box.NAME, { width = Box.WIDTH, height = Box.HEIGHT, veil = false })

	f.title = Theme.NewText(f, "H1", "text-1")
	f.title:SetJustifyH("LEFT")
	f.title:SetPoint("TOPLEFT", f, "TOPLEFT", 20, -18)
	f.title:SetText(L["DIAG_TITLE"])
	f.hint = Theme.NewText(f, "Small", "text-2")
	f.hint:SetJustifyH("LEFT")
	f.hint:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -6)
	f.hint:SetPoint("RIGHT", f, "RIGHT", -20, 0)
	f.hint:SetText(L["DIAG_HINT"])

	-- the report: the read-only field of Widgets.CopyArea
	local field = Widgets.CopyArea(f, { width = Box.WIDTH - 48, onEscape = function() Box:Hide() end })
	field:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -60)
	field:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -16, 56)
	f.field, f.scroll, f.edit = field, field.scroll, field.edit

	f.selectAll = Widgets.Button(f, { text = L["DIAG_SELECT"], width = 140, onClick = function() Box:SelectAll() end })
	f.selectAll:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 16, 14)
	f.size = Theme.NewText(f, "Small", "text-3")
	f.size:SetPoint("BOTTOM", f, "BOTTOM", 0, 24)
	f.close = Widgets.Button(f, { text = L["DIAG_CLOSE"], width = 120, style = "primary", onClick = function() Box:Hide() end })
	f.close:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -16, 14)
	return f
end

function Box:Frame()
	if not self.frame then self.frame = build() end
	return self.frame
end

-- Opens the box with `text` (a fresh report when nil), selected, ready for Ctrl+C. Returns the text.
function Box:Open(text)
	local f = self:Frame()
	text = text or ns.Diagnostics.Report()
	f.text = text
	local lines = select(2, text:gsub("\n", "")) + 1
	f.size:SetText(L["DIAG_SIZE"]:format(lines, #text))
	f.field:SetText(text)
	f:Open()
	self:SelectAll()
	return text
end

function Box:SelectAll()
	local f = self.frame
	if f then f.field:SelectAll() end
end

function Box:Hide() if self.frame then self.frame:Hide() end end
function Box:IsShown() return self.frame ~= nil and self.frame:IsShown() end
function Box:GetText() return self.frame and self.frame.text or nil end

if ns.addon then ns.addon.DiagnosticsBox = Box end
