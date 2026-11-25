-- Diagnostics box: `/atw debug` opens the report of Core/Diagnostics.lua in a read-only multi-line edit box, already
-- selected, so the player presses Ctrl+C and pastes it into a bug report (addons cannot reach the clipboard). Esc
-- closes it (SPEC-01 §9, ARC-13). Lua 5.1.
-- Adapted from Azeroth Accord (UI/DiagnosticsBox.lua and the read-only field of UI/CopyBox.lua), same owner, GPL-3.0
-- (ADR 0012). Since M1.6 it is a Widgets.Dialog without a veil (it can be moved) in the look of the addon.
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
Box.WHEEL_STEP = 40

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

	-- the report: a multi-line edit box in a frame that scrolls with the wheel
	local field = CreateFrame("Frame", nil, f)
	field:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -60)
	field:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -16, 56)
	f.field = field
	f.fieldParts = Theme.Panel(field, { radius = 8, fill = "surface-2", border = "border" })
	local scroll = CreateFrame("ScrollFrame", nil, field)
	scroll:SetPoint("TOPLEFT", field, "TOPLEFT", 8, -8)
	scroll:SetPoint("BOTTOMRIGHT", field, "BOTTOMRIGHT", -8, 8)
	scroll:EnableMouseWheel(true)
	scroll:SetScript("OnMouseWheel", function(self, delta)
		local range = self.GetVerticalScrollRange and self:GetVerticalScrollRange() or 0
		local current = self.GetVerticalScroll and self:GetVerticalScroll() or 0
		self:SetVerticalScroll(math.min(range, math.max(0, current - delta * Box.WHEEL_STEP)))
	end)
	local edit = CreateFrame("EditBox", nil, scroll)
	edit:SetMultiLine(true)
	edit:SetAutoFocus(false)
	edit:SetMaxLetters(0)
	edit:SetFontObject(Theme.Font("MonoSmall"))
	Theme.Text(edit, "text-1")
	edit:SetWidth(Box.WIDTH - 48)
	scroll:SetScrollChild(edit)
	f.scroll, f.edit = scroll, edit

	-- read-only: typing is undone at once and the text stays selected
	edit:SetScript("OnTextChanged", function(self, userInput)
		if userInput and self:GetText() ~= f.text then
			self:SetText(f.text or "")
			self:HighlightText()
		end
	end)
	edit:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
	edit:SetScript("OnEscapePressed", function(self)
		self:ClearFocus()
		Box:Hide()
	end)

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
	f.edit:SetText(text)
	f.edit:SetCursorPosition(0)
	f.scroll:SetVerticalScroll(0)
	f:Open()
	self:SelectAll()
	return text
end

function Box:SelectAll()
	local f = self.frame
	if not f then return end
	f.edit:SetFocus()
	f.edit:HighlightText()
end

function Box:Hide() if self.frame then self.frame:Hide() end end
function Box:IsShown() return self.frame ~= nil and self.frame:IsShown() end
function Box:GetText() return self.frame and self.frame.text or nil end

if ns.addon then ns.addon.DiagnosticsBox = Box end
