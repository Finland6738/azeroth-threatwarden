-- Widget kit, part 2: Switch, Slider and Select (a dropdown without UIDropDownMenu, which taints).
-- Adapted from Azeroth Accord (UI/Widgets/Controls.lua, itself from Finland Dragon Credit Points), same owner, GPL-3.0
-- (ADR 0012); its snackbar, skeleton, class mark and menu are not needed here. Ordinary unprotected frames; every colour
-- is a theme token; text comes in already translated. Lua 5.1.
local ADDON_NAME, ns = ...
ns = ns or {}
local Widgets, Theme, Motion, Assets, Compat = ns.Widgets, ns.Theme, ns.Motion, ns.Assets, ns.Compat
local max, min, floor = math.max, math.min, math.floor

-- --- Switch -----------------------------------------------------------------------------------------------------------

-- A 44 x 26 pill: the track is surface-3 (accent when on), the thumb a circle that slides in 200 ms. opts: on (bool),
-- onChange(on) after a click or :SetOn(v) without `silent`. :IsOn(), :SetOn(v, silent), :SetEnabled(bool).
function Widgets.Switch(parent, opts)
	opts = opts or {}
	local b = CreateFrame("CheckButton", nil, parent)
	b:SetSize(44, 26)
	b.track = Theme.Slice(b, "rr_fill_12", "surface-3", "BACKGROUND")
	b.track:SetAllPoints(b)
	b.ring = Theme.Slice(b, "rr_ring_12", "border", "BORDER")
	b.ring:SetAllPoints(b)
	b.thumb = b:CreateTexture(nil, "ARTWORK")
	b.thumb:SetTexture(Assets.textures.circle.path)
	b.thumb:SetSize(18, 18)
	Theme.Tint(b.thumb, "text-2")
	b.on = false
	local function thumbAt(x)
		b.thumb:ClearAllPoints()
		b.thumb:SetPoint("LEFT", b, "LEFT", x, 0)
	end
	thumbAt(4)
	local function paint()
		if b.on then
			Theme.Tint(b.track, "accent"); Theme.Tint(b.ring, "accent"); Theme.Tint(b.thumb, "on-accent")
		else
			Theme.Tint(b.track, "surface-3"); Theme.Tint(b.ring, "border"); Theme.Tint(b.thumb, "text-2")
		end
	end
	function b:IsOn() return self.on end
	function b:SetOn(v, silent)
		v = v and true or false
		if v == self.on then return end
		self.on = v
		paint()
		local to, from = v and 22 or 4, v and 4 or 22
		Motion.Slide(self.thumb, to - from, 0, Motion.BASE, function() thumbAt(to) end)
		if not silent and opts.onChange then opts.onChange(v) end
	end
	local setEnabled = b.SetEnabled
	function b:SetEnabled(enabled)
		setEnabled(self, enabled and true or false)
		self:SetAlpha(enabled and 1 or 0.45)
	end
	b:SetScript("OnClick", function(self)
		if self:IsEnabled() then self:SetOn(not self.on) end
	end)
	if opts.on then b.on = true; paint(); thumbAt(22) else paint() end
	return b
end

-- --- Slider -----------------------------------------------------------------------------------------------------------

-- A horizontal slider on a 4 pt track with the theme gradient and a round thumb. opts: min, max, step, value, width,
-- onChange(value, user). :Set(v) (silent), :GetValue(). The value is rounded to the step.
function Widgets.Slider(parent, opts)
	opts = opts or {}
	local lo, hi, step = opts.min or 0, opts.max or 100, opts.step or 1
	local s = CreateFrame("Slider", nil, parent)
	s:SetSize(opts.width or 200, 20)
	s:SetOrientation("HORIZONTAL")
	s:SetMinMaxValues(lo, hi)
	s:SetValueStep(step)
	s:SetObeyStepOnDrag(true)
	s.track = s:CreateTexture(nil, "BACKGROUND")
	Theme.Fill(s.track, "border")
	s.track:SetPoint("LEFT", s, "LEFT", 0, 0)
	s.track:SetPoint("RIGHT", s, "RIGHT", 0, 0)
	s.track:SetHeight(4)
	s.fill = s:CreateTexture(nil, "ARTWORK")
	Theme.Fill(s.fill, "accent")
	Theme.Call(s.fill, function(region)
		if region.SetGradient then
			local r1, g1, b1 = Theme.Color("accent")
			local r2, g2, b2 = Theme.Color("accent-2")
			region:SetGradient("HORIZONTAL", Compat.CreateColor(r1, g1, b1, 1), Compat.CreateColor(r2, g2, b2, 1))
		end
	end)
	s.fill:SetPoint("LEFT", s, "LEFT", 0, 0)
	s.fill:SetHeight(4)
	s:SetThumbTexture(Assets.textures.circle.path)
	s.thumb = s:GetThumbTexture()
	if s.thumb then
		s.thumb:SetSize(16, 16)
		Theme.Tint(s.thumb, "text-1")
	end
	local function refresh()
		local v = s:GetValue()
		local span = hi - lo
		local f = span > 0 and (v - lo) / span or 0
		s.fill:SetWidth(max((s:GetWidth() or opts.width or 200) * f, 1))
	end
	function s:Set(v)   -- silent
		v = min(max(tonumber(v) or lo, lo), hi)
		if step > 0 then v = lo + floor((v - lo) / step + 0.5) * step end
		self:SetValue(v)
		refresh()
	end
	s:SetScript("OnValueChanged", function(self, value, user)
		refresh()
		if opts.onChange then opts.onChange(value, user and true or false) end
	end)
	s:SetScript("OnSizeChanged", refresh)
	s:Set(opts.value or lo)
	return s
end

-- --- Select (a dropdown without UIDropDownMenu) -------------------------------------------------------------------------

-- A field that shows the chosen text; a click opens a list below it (a ChoiceList on the DIALOG strata) and a click
-- outside closes it. choices = { { id, text, token? } }. opts: width, rows (6), choices, value, onSelect(id), placeholder.
-- :SetChoices(list), :Select(id, silent), :Selected(), :Open(), :Close(), :IsOpen().
function Widgets.Select(parent, opts)
	opts = opts or {}
	local width, rows = opts.width or 200, opts.rows or 6
	local sel = CreateFrame("Button", nil, parent)
	sel:SetSize(width, 28)
	sel.fill = Theme.Slice(sel, "rr_fill_8", "surface-2", "BACKGROUND")
	sel.fill:SetAllPoints(sel)
	sel.ring = Theme.Slice(sel, "rr_ring_8", "border", "BORDER")
	sel.ring:SetAllPoints(sel)
	sel.label = Theme.NewText(sel, "Body", "text-1")
	sel.label:SetPoint("LEFT", sel, "LEFT", 10, 0)
	sel.label:SetPoint("RIGHT", sel, "RIGHT", -26, 0)
	sel.label:SetJustifyH("LEFT")
	sel.arrow = sel:CreateTexture(nil, "OVERLAY")
	sel.arrow:SetTexture(Assets.textures.icons.path)
	sel.arrow:SetTexCoord(Assets.IconCoords("chevron"))
	sel.arrow:SetSize(14, 14)
	sel.arrow:SetPoint("RIGHT", sel, "RIGHT", -8, 0)
	Theme.Tint(sel.arrow, "text-3")
	Motion.Rotate(sel.arrow, -math.pi / 2, 0)   -- the chevron points right in the sheet: down while closed
	sel.choices = opts.choices or {}

	-- the popup: a catcher over the screen (a click outside closes) and the list under the field
	sel.popup = CreateFrame("Frame", nil, sel)
	sel.popup:SetFrameStrata("DIALOG")
	sel.popup:SetToplevel(true)
	sel.popup:SetPoint("TOPLEFT", sel, "BOTTOMLEFT", 0, -4)
	sel.popup:Hide()
	sel.catcher = CreateFrame("Button", nil, sel.popup)
	sel.catcher:SetFrameStrata("DIALOG")
	sel.catcher:SetAllPoints(Compat.UIParent())
	sel.catcher:SetFrameLevel(sel.popup:GetFrameLevel() - 1)
	sel.catcher:SetScript("OnClick", function() sel:Close() end)
	sel.list = Widgets.ChoiceList(sel.popup, { rows = rows, rowHeight = 24, width = width, onSelect = function(id) sel:Select(id) end })
	sel.list:SetPoint("TOPLEFT", sel.popup, "TOPLEFT", 0, 0)
	sel.popup:SetSize(width, rows * 24 + 8)
	Theme.Tint(sel.list.ring, "border-strong")

	local function textOf(id)
		for _, c in ipairs(sel.choices) do if c.id == id then return c.text end end
	end
	local function paint()
		local text = sel.value ~= nil and textOf(sel.value) or nil
		sel.label:SetText(text or opts.placeholder or "")
		Theme.Text(sel.label, text and "text-1" or "text-3")
	end
	function sel:SetChoices(list)
		self.choices = list or {}
		self.list:SetChoices(self.choices)
		if self.value ~= nil and textOf(self.value) == nil then self.value = nil end
		if self.value ~= nil then self.list:Select(self.value) end
		paint()
	end
	function sel:Select(id, silent)
		if textOf(id) == nil then return false end
		local changed = self.value ~= id
		self.value = id
		self.list:Select(id)
		paint()
		self:Close()
		if changed and not silent and opts.onSelect then opts.onSelect(id) end
		return true
	end
	function sel:Selected() return self.value end
	function sel:IsOpen() return self.popup:IsShown() end
	function sel:Open()
		if not self:IsEnabled() or #self.choices == 0 or self:IsOpen() then return end
		self.popup:Show()
		Motion.FadeIn(self.popup, Motion.BASE)
		Motion.Rotate(self.arrow, math.pi / 2, Motion.BASE)   -- up while open
		Theme.Tint(self.ring, "accent")
	end
	function sel:Close()
		if not self.popup:IsShown() then return end
		self.popup:Hide()
		Motion.Rotate(self.arrow, -math.pi / 2, Motion.BASE)
		Theme.Tint(self.ring, "border")
	end
	sel:SetScript("OnClick", function(self) if self:IsOpen() then self:Close() else self:Open() end end)
	sel:SetScript("OnHide", function(self) self:Close() end)
	sel:SetChoices(sel.choices)
	if opts.value ~= nil then sel:Select(opts.value, true) end
	return sel
end
