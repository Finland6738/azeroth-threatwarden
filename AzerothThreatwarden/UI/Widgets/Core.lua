-- Widget kit, part 1: Button (primary, secondary, ghost, neon), Card, Badge, Tabs (underline with the moving indicator),
-- Segmented, TitleBar (wide and compact), Dialog, EditBox, ChoiceList and RowHover: the components of
-- docs/specs/ui-style.md sections 0 and 3. The rest of the kit is in Controls.lua, ThinBar.lua, Tooltip.lua and
-- Threat.lua (ThreatBar, StateBadge). Lua 5.1.
-- Adapted from Azeroth Accord (UI/Widgets/Core.lua, itself from Finland Dragon Credit Points), same owner, GPL-3.0
-- (ADR 0012). Changes: the compact sizes of Threatwarden (title bar 28 pt, tabs 24 pt); Dialog may have no veil and be
-- moved; the tabs have no counts and no overflow menu; no chips and no class colours (M2.5 adds what it needs).
-- * Namespace: `ns.Widgets` (also `AzerothThreatwarden.Widgets` for tests).
-- * Every widget is made of ordinary frames and white textures tinted through UI/Theme.lua: a colour is a token, never a
--   value, and the theme follows Theme.Apply without /reload. The only colour written here is the white of the hover layer.
-- * Text comes in already translated by the caller (L[...]): a widget never contains a sentence. Unprotected frames only.
-- * No game API is named here (ARC-02): CreateFrame, and Core/Compat.lua for the rest.
local ADDON_NAME, ns = ...
ns = ns or {}

local Widgets = ns.Widgets or {}
ns.Widgets = Widgets
ns.modules = ns.modules or {}
ns.modules.Widgets = Widgets
if ns.addon then ns.addon.Widgets = Widgets end   -- also reachable from tests

local Theme, Assets, Motion, Compat = ns.Theme, ns.Assets, ns.Motion, ns.Compat
local max, min, ipairs, pairs = math.max, math.min, ipairs, pairs

local function gradientColor(token)
	return Compat.CreateColor(Theme.Color(token))
end

-- Registers the named frame so that Esc closes it (UISpecialFrames, through Compat).
function Widgets.CloseOnEscape(name)
	return Compat.CloseOnEscape(name)
end

-- --- Button -----------------------------------------------------------------------------------------------------------

-- Button styles: fill token, text token, and what else the style adds.
local BUTTON_STYLES = {
	primary   = { fill = "accent",    ink = "on-accent", gradient = true, glow = "accent", glowAlpha = 0.3 },
	secondary = { fill = "surface-3", ink = "text-1",    ring = "border" },
	ghost     = { fill = nil,         ink = "text-2",    ring = nil },
	neon      = { fill = "surface-1", ink = "text-1",    ring = "neon", glow = "neon", glowAlpha = 0.5 },
}
Widgets.BUTTON_STYLES = BUTTON_STYLES
Widgets.HOVER, Widgets.PRESSED = 0.08, 0.12   -- the white layers of the states (FDCP)

-- opts: text, style ("primary" | "secondary" | "ghost" | "neon"), width (without it the button fits its text), height,
-- onClick. The primary button has the glow of the accent (dark themes, "Neon effects"), the neon one a ring and a glow in
-- the neon colour; hover lays 8 % white over the shape and pressed 12 % (faded in 120 ms), a press shrinks the button to
-- 0.97 (Motion.Press). :SetLabel(text), :GetLabel(), :SetEnabled(bool).
function Widgets.Button(parent, opts)
	opts = opts or {}
	local style = BUTTON_STYLES[opts.style or "secondary"] or BUTTON_STYLES.secondary
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(opts.width or 120, opts.height or 32)
	b.style = opts.style or "secondary"
	if style.glow then
		b.glow = Theme.Glow(b, "glow_s", style.glow, { alpha = style.glowAlpha or 0.5 })
		b.glow:SetPoint("TOPLEFT", b, "TOPLEFT", -18, 18)
		b.glow:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 18, -18)
	end
	if style.fill then
		b.fill = Theme.Slice(b, "rr_fill_8", style.fill, "BACKGROUND")
		b.fill:SetAllPoints(b)
		if style.gradient then
			Theme.Call(b.fill, function(region)   -- accent -> accent-2, two colours (the spec: SetGradient)
				if region.SetGradient then region:SetGradient("HORIZONTAL", gradientColor("accent"), gradientColor("accent-2")) end
			end)
		end
	end
	if style.ring then
		b.ring = Theme.Slice(b, "rr_ring_8", style.ring, "BORDER")
		b.ring:SetAllPoints(b)
	end
	-- hover 8 % and pressed 12 % white over the shape (a white texture whose alpha is faded)
	b.over = Theme.Slice(b, "rr_fill_8", nil, "ARTWORK")
	b.over:SetAllPoints(b)
	b.over:SetVertexColor(1, 1, 1, 1)   -- theme-ok: the white of the hover and pressed layers
	b.over:SetAlpha(0)
	b.label = Theme.NewText(b, "Button", style.ink)
	b.label:SetPoint("CENTER", b, "CENTER", 0, 0)
	b.fit = opts.width == nil
	function b:SetLabel(text)
		self.label:SetText(text or "")
		if self.fit then self:SetWidth(max(64, self.label:GetStringWidth() + 32)) end
	end
	function b:GetLabel() return self.label:GetText() end
	b:SetLabel(opts.text)
	if opts.width == nil then b:SetWidth(max(64, b.label:GetStringWidth() + 32)) end
	local function layer(self)
		if not self:IsEnabled() then return 0 end
		if self.pressed then return Widgets.PRESSED end
		return self.hot and Widgets.HOVER or 0
	end
	local function paint(self) Motion.Fade(self.over, layer(self), Motion.FAST) end
	b:SetScript("OnEnter", function(self) self.hot = true; paint(self) end)
	b:SetScript("OnLeave", function(self) self.hot, self.pressed = false, false; paint(self) end)
	b:SetScript("OnMouseDown", function(self) self.pressed = true; paint(self) end)
	b:SetScript("OnMouseUp", function(self) self.pressed = false; paint(self) end)
	local setEnabled = b.SetEnabled
	function b:SetEnabled(enabled)
		setEnabled(self, enabled and true or false)
		self:SetAlpha(enabled and 1 or 0.45)
		if not enabled then self.hot, self.pressed = false, false end
		paint(self)
	end
	Motion.Press(b)
	if opts.onClick then b:SetScript("OnClick", opts.onClick) end
	return b
end

-- --- Card -------------------------------------------------------------------------------------------------------------

-- A card: surface-1 fill, subtle ring (strong on hover when `hover`), the light line of the dark themes along its top edge,
-- radius 18, optional shadow. Four regions at most. opts: width, height, fill (token), shadow, hover.
function Widgets.Card(parent, opts)
	opts = opts or {}
	local c = CreateFrame("Frame", nil, parent)
	c:SetSize(opts.width or 200, opts.height or 100)
	c.parts = Theme.Panel(c, { radius = 18, fill = opts.fill or "surface-1", border = "border-subtle", shadow = opts.shadow, highlight = true })
	if opts.hover then
		c:EnableMouse(true)
		c:SetScript("OnEnter", function(self) Theme.Tint(self.parts.ring, "border-strong") end)
		c:SetScript("OnLeave", function(self) Theme.Tint(self.parts.ring, "border-subtle") end)
	end
	return c
end

-- --- Badge ------------------------------------------------------------------------------------------------------------

local BADGE_TONES = { accent = "accent-text", ok = "ok", warn = "warn", err = "err", neutral = "text-2" }
Widgets.BADGE_TONES = BADGE_TONES

-- A pill (24 high, the module state of the title bar and counts) whose width follows its text; the fill is the tone's colour at low alpha, the text the tone's.
-- :SetBadge(text, tone).
function Widgets.Badge(parent, text, tone)
	local token = BADGE_TONES[tone or "neutral"] or BADGE_TONES.neutral
	local f = CreateFrame("Frame", nil, parent)
	f.fill = Theme.Slice(f, "rr_fill_12", token, "BACKGROUND", 0.16)
	f.fill:SetAllPoints(f)
	f.label = Theme.NewText(f, "Th", token)
	f.label:SetPoint("CENTER", f, "CENTER", 0, 0)
	function f:SetBadge(newText, newTone)
		tone = newTone or tone   -- a badge keeps the tone it last had
		local t = BADGE_TONES[tone or "neutral"] or BADGE_TONES.neutral
		Theme.Tint(self.fill, t, 0.16)
		Theme.Text(self.label, t)
		self.label:SetText(newText or "")
		self:SetSize(max(24, self.label:GetStringWidth() + 20), 24)
	end
	f:SetBadge(text, tone)
	return f
end

-- --- Tabs (underline) -------------------------------------------------------------------------------------------------

Widgets.TAB_HEIGHT, Widgets.TAB_HEIGHT_COMPACT = 36, 24   -- the wide and the compact layout (ui-style 3.1)

-- tabs: { { id = "monitor", text = "Monitor" }, ... }. The active tab is text-1 with a 2 pt accent bar under it that
-- slides to the next one in 200 ms; the others text-3 (text-2 on hover). opts: compact (24 pt, font TabCompact).
-- :Select(id), :Active(), :SetTabShown(id, bool), :SetTabText(id, text), :Layout(). onSelect(id) runs after a change.
function Widgets.Tabs(parent, tabs, onSelect, opts)
	opts = opts or {}
	local height = opts.compact and Widgets.TAB_HEIGHT_COMPACT or Widgets.TAB_HEIGHT
	local font = opts.compact and "TabCompact" or "Tab"
	local pad = opts.compact and 8 or 16
	local bar = CreateFrame("Frame", nil, parent)
	bar:SetHeight(height)
	bar.buttons, bar.order, bar.hidden = {}, {}, {}
	bar.line = bar:CreateTexture(nil, "BORDER")
	Theme.Fill(bar.line, "border-subtle")
	bar.line:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 0, 0)
	bar.line:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, 0)
	bar.line:SetHeight(Theme.Px(1))
	bar.indicator = bar:CreateTexture(nil, "ARTWORK")
	Theme.Fill(bar.indicator, "accent")
	bar.indicator:SetHeight(2)
	bar.indicator:Hide()

	-- the width of a tab is its text and `pad` points each side
	local function layout()
		local x = 0
		for _, id in ipairs(bar.order) do
			local b = bar.buttons[id]
			if bar.hidden[id] then
				b:Hide()
			else
				local w = max(48, b.label:GetStringWidth() + 2 * pad)
				b:SetWidth(w)
				b:ClearAllPoints()
				b:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", x, 0)
				b:Show()
				b.x, b.w = x, w
				x = x + w + 4
			end
		end
	end

	-- puts the indicator under the active tab; from `fromX` (its old place) it slides there, otherwise it appears
	local function place(fromX, fromW, changed)
		local ind = bar.indicator
		local b = bar.active and bar.buttons[bar.active]
		if not b or bar.hidden[bar.active] or not b.x then
			ind:Hide(); bar.ix, bar.iw = nil, nil
			return
		end
		local x, w = b.x + 4, b.w - 8
		local function put(px, pw)
			ind:ClearAllPoints()
			ind:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", px, 0)
			ind:SetWidth(pw)
			bar.ix, bar.iw = px, pw
		end
		if fromX and ind:IsShown() and changed then
			put(fromX, fromW or w)
			Motion.Slide(ind, x - fromX, 0, Motion.BASE, function() put(x, w) end)   -- 200 ms
		else
			put(x, w)
			local wasShown = ind:IsShown()
			ind:Show()
			if changed and not wasShown then Motion.FadeIn(ind, Motion.BASE) end
		end
	end

	local function paint()
		for id, b in pairs(bar.buttons) do Theme.Text(b.label, id == bar.active and "text-1" or "text-3") end
	end

	function bar:Select(id)
		if not self.buttons[id] or self.hidden[id] then return false end
		local changed = self.active ~= id
		local fromX, fromW = self.ix, self.iw
		self.active = id
		paint(); layout(); place(fromX, fromW, changed)
		if changed and onSelect then onSelect(id) end
		return true
	end
	function bar:Active() return self.active end
	function bar:Layout() layout(); place(nil, nil, false) end
	function bar:SetTabShown(id, shown)
		if not self.buttons[id] then return false end
		self.hidden[id] = not shown or nil
		if not shown and self.active == id then
			for _, other in ipairs(self.order) do
				if not self.hidden[other] then self:Select(other) break end
			end
		end
		self:Layout()
		return true
	end
	function bar:SetTabText(id, text)
		local b = self.buttons[id]
		if not b then return false end
		b.label:SetText(text or "")
		self:Layout()
		return true
	end

	for _, t in ipairs(tabs) do
		local b = CreateFrame("Button", nil, bar)
		b.id = t.id
		b:SetHeight(height)
		b.label = Theme.NewText(b, font, "text-3")
		b.label:SetPoint("CENTER", b, "CENTER", 0, 1)
		b.label:SetText(t.text or "")
		b:SetScript("OnClick", function() bar:Select(t.id) end)
		b:SetScript("OnEnter", function(self) if bar.active ~= self.id then Theme.Text(self.label, "text-2") end end)
		b:SetScript("OnLeave", function(self) if bar.active ~= self.id then Theme.Text(self.label, "text-3") end end)
		bar.buttons[t.id] = b
		bar.order[#bar.order + 1] = t.id
	end
	layout()
	return bar
end

-- --- Segmented (pill selector) ----------------------------------------------------------------------------------------

-- items: { { id, text } }. A surface-2 pill with the selected segment raised. :Select(id), :Active(), :Clear(),
-- :SetEnabled(bool), :SetItemText(id, text). onSelect(id) runs after a change.
function Widgets.Segmented(parent, items, onSelect)
	local seg = CreateFrame("Frame", nil, parent)
	seg:SetHeight(32)
	seg.fill = Theme.Slice(seg, "rr_fill_12", "surface-2", "BACKGROUND")
	seg.fill:SetAllPoints(seg)
	seg.ring = Theme.Slice(seg, "rr_ring_12", "border", "BORDER")
	seg.ring:SetAllPoints(seg)
	seg.thumb = Theme.Slice(seg, "rr_fill_12", "raised", "ARTWORK")
	seg.thumb:Hide()
	seg.buttons, seg.order = {}, {}

	function seg:Select(id)
		local b = self.buttons[id]
		if not b then return false end
		local changed = self.active ~= id
		self.active = id
		self.thumb:ClearAllPoints()
		self.thumb:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
		self.thumb:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 0)
		self.thumb:Show()
		for other, ob in pairs(self.buttons) do Theme.Text(ob.label, other == id and "text-1" or "text-3") end
		if changed and onSelect then onSelect(id) end
		return true
	end
	function seg:Active() return self.active end
	-- No segment selected (the thumb goes away).
	function seg:Clear()
		self.active = nil
		self.thumb:Hide()
		for _, ob in pairs(self.buttons) do Theme.Text(ob.label, "text-3") end
	end
	-- Locked: the segments stop answering clicks and dim; the selection stays visible.
	function seg:SetEnabled(enabled)
		self.enabled = enabled ~= false
		self:SetAlpha(self.enabled and 1 or 0.55)
		for _, ob in pairs(self.buttons) do ob:SetEnabled(self.enabled) end
	end

	local x = 4
	for _, item in ipairs(items) do
		local b = CreateFrame("Button", nil, seg)
		b.label = Theme.NewText(b, "BodyMedium", "text-3")
		b.label:SetPoint("CENTER", b, "CENTER", 0, 0)
		b.label:SetText(item.text or "")
		b:SetSize(max(48, b.label:GetStringWidth() + 24), 24)
		b:SetPoint("LEFT", seg, "LEFT", x, 0)
		x = x + b:GetWidth() + 2
		b:SetScript("OnClick", function() seg:Select(item.id) end)
		seg.buttons[item.id] = b
		seg.order[#seg.order + 1] = item.id
	end
	seg:SetWidth(x + 2)
	-- A new text for a segment (a count on a page's name): the segments move to make room.
	function seg:SetItemText(id, text)
		local b = self.buttons[id]
		if not b then return false end
		b.label:SetText(text or "")
		b:SetWidth(max(48, b.label:GetStringWidth() + 24))
		local at = 4
		for _, other in ipairs(self.order) do
			local ob = self.buttons[other]
			ob:ClearAllPoints()
			ob:SetPoint("LEFT", self, "LEFT", at, 0)
			at = at + ob:GetWidth() + 2
		end
		self:SetWidth(at + 2)
		return true
	end
	return seg
end

-- --- TitleBar ---------------------------------------------------------------------------------------------------------

Widgets.TITLE_HEIGHT, Widgets.TITLE_HEIGHT_COMPACT = 52, 28

-- The window's title bar on surface-1: the logo, the title in the display face and the close button (`.close`: the
-- caller anchors its own things, like the pill of the module state, to the left of it). Wide: 52 pt, logo 24 pt, a mono
-- subtitle, the glow behind the logo and the title (the one neon element of the view). Compact: 28 pt, logo 18 pt, the
-- title in DisplaySmall and no glow, nothing to distract from the fight (ui-style 3.1, 5).
-- opts: compact, title, subtitle (wide only), closeLabel (the tooltip of the close button, translated), onClose.
function Widgets.TitleBar(parent, opts)
	opts = opts or {}
	local compact = opts.compact and true or false
	local logoSize, left = compact and 18 or 24, compact and 8 or 20
	local bar = CreateFrame("Frame", nil, parent)
	bar.compact = compact
	bar:SetHeight(compact and Widgets.TITLE_HEIGHT_COMPACT or Widgets.TITLE_HEIGHT)
	bar.fill = Theme.Slice(bar, compact and "rr_fill_8" or "rr_fill_12", "surface-1", "BACKGROUND")
	bar.fill:SetAllPoints(bar)
	bar.line = bar:CreateTexture(nil, "BORDER")
	Theme.Fill(bar.line, "border-subtle")
	bar.line:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", compact and 8 or 12, 0)
	bar.line:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", compact and -8 or -12, 0)
	bar.line:SetHeight(Theme.Px(1))

	if not compact then
		bar.logoGlow = Theme.Glow(bar, "glow_s", "neon", { layer = "ARTWORK", alpha = 0.35 })
		bar.logoGlow:SetSize(56, 56)
		bar.logoGlow:SetPoint("LEFT", bar, "LEFT", left - 16, 0)
	end
	bar.logo = bar:CreateTexture(nil, "OVERLAY")
	bar.logo:SetTexture(Assets.logos.logo_64.path)
	bar.logo:SetSize(logoSize, logoSize)
	bar.logo:SetPoint("LEFT", bar, "LEFT", left, 0)
	if bar.logo.SetMaskTexture then bar.logo:SetMaskTexture(Assets.textures.circle.path) end

	bar.title = Theme.NewText(bar, compact and "DisplaySmall" or "Display", "text-1")
	bar.title:SetText(opts.title or "")
	local textLeft = left + logoSize + (compact and 6 or 12)
	if compact then
		bar.title:SetPoint("LEFT", bar, "LEFT", textLeft, 0)
	else
		bar.title:SetPoint("TOPLEFT", bar, "TOPLEFT", textLeft, -9)
		Theme.TextGlow(bar.title, "neon")
		bar.subtitle = Theme.NewText(bar, "MonoSmall", "text-3")
		bar.subtitle:SetPoint("TOPLEFT", bar.title, "BOTTOMLEFT", 0, -3)
		bar.subtitle:SetText(opts.subtitle or "")
	end

	local size = compact and 18 or 28
	bar.close = CreateFrame("Button", nil, bar)
	bar.close:SetSize(size, size)
	bar.close:SetPoint("RIGHT", bar, "RIGHT", compact and -6 or -14, 0)
	bar.close.bg = Theme.Slice(bar.close, "rr_fill_8", "surface-3", "BACKGROUND", 0)
	bar.close.bg:SetAllPoints(bar.close)
	bar.close.icon = bar.close:CreateTexture(nil, "OVERLAY")
	bar.close.icon:SetTexture(Assets.textures.icons.path)
	bar.close.icon:SetTexCoord(Assets.IconCoords("cross"))
	bar.close.icon:SetSize(compact and 12 or 16, compact and 12 or 16)
	bar.close.icon:SetPoint("CENTER")
	Theme.Tint(bar.close.icon, "text-2")
	bar.close:SetScript("OnEnter", function(self) Theme.Tint(self.bg, "surface-3", 1) end)
	bar.close:SetScript("OnLeave", function(self) Theme.Tint(self.bg, "surface-3", 0) end)
	if opts.onClose then bar.close:SetScript("OnClick", opts.onClose) end
	if opts.closeLabel and Widgets.Tooltip then Widgets.Tooltip.Attach(bar.close, opts.closeLabel, "BOTTOM") end
	return bar
end

-- --- Dialog -----------------------------------------------------------------------------------------------------------

-- A card on the DIALOG strata that enters with Motion.Rise (alpha and a 16 pt rise, 320 ms). By default modal: a dark
-- veil over `parent` (no blur: the engine cannot) with the card in the centre. With opts.veil = false there is no veil:
-- the frame is the card itself, in the centre, and the player can drag it. Esc closes it (UISpecialFrames, `name`).
-- opts: width (420), height (220), veil. :Open(), :Close(), .card, .content (the caller adds its children there).
function Widgets.Dialog(parent, name, opts)
	opts = opts or {}
	local veil = opts.veil ~= false
	parent = parent or Compat.UIParent()
	local width, height = opts.width or 420, opts.height or 220
	local d = CreateFrame("Frame", name, parent)
	d:Hide()
	d:SetFrameStrata("DIALOG")
	d:SetToplevel(true)
	d:EnableMouse(true)   -- the veil swallows clicks
	if veil then
		d:SetAllPoints(parent)
		d.veil = d:CreateTexture(nil, "BACKGROUND")
		Theme.Fill(d.veil, "scrim")
		d.veil:SetAllPoints(d)
		d.card = CreateFrame("Frame", nil, d)
		d.card:SetSize(width, height)
		d.card:SetPoint("CENTER", d, "CENTER", 0, 0)
	else
		d:SetSize(width, height)
		d:SetPoint("CENTER", parent, "CENTER", 0, 0)
		d:SetClampedToScreen(true)
		d:SetMovable(true)
		d:RegisterForDrag("LeftButton")
		d:SetScript("OnDragStart", function(self) self:StartMoving() end)
		d:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
		d.card = d
	end
	d.card.parts = Theme.Panel(d.card, { radius = 12, fill = "surface-1", border = "border", shadow = true, highlight = true })
	d.content = d.card
	Widgets.CloseOnEscape(name)
	-- the veil fades in 200 ms while the card rises and fades in 320 ms (a card the player moved is not moved back)
	function d:Open()
		self:Show()
		if self.veil then
			Motion.FadeIn(self.veil, Motion.BASE)
			Motion.Rise(self.card, 16, Motion.SLOW)
		else
			Motion.FadeIn(self, Motion.BASE)
		end
	end
	function d:Close() self:Hide() end
	return d
end

-- --- EditBox ----------------------------------------------------------------------------------------------------------

-- A one-line field: surface-2 fill, 1 pt ring (accent while it has the keyboard). opts: width, height, maxLetters,
-- placeholder (text-3, shown while the field is empty and not focused), onChange(text, user) after every edit,
-- onEnter(text). :GetText(), :SetText(text), :Clear(), :SetPlaceholder(text), :SetFocus(), :ClearFocus(). The edit box
-- itself is `.edit`.
function Widgets.EditBox(parent, opts)
	opts = opts or {}
	local f = CreateFrame("Frame", nil, parent)
	f:SetSize(opts.width or 120, opts.height or 28)
	f.fill = Theme.Slice(f, "rr_fill_8", "surface-2", "BACKGROUND")
	f.fill:SetAllPoints(f)
	f.ring = Theme.Slice(f, "rr_ring_8", "border", "BORDER")
	f.ring:SetAllPoints(f)
	local e = CreateFrame("EditBox", nil, f)
	e:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -2)
	e:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -10, 2)
	e:SetAutoFocus(false)
	if Theme.fontObjects.Body then e:SetFontObject(Theme.fontObjects.Body) end
	if opts.maxLetters then e:SetMaxLetters(opts.maxLetters) end
	Theme.Text(e, "text-1")
	f.placeholder = Theme.NewText(f, "Body", "text-3")
	f.placeholder:SetPoint("LEFT", f, "LEFT", 10, 0)
	f.placeholder:SetPoint("RIGHT", f, "RIGHT", -10, 0)
	f.placeholder:SetJustifyH("LEFT")
	f.placeholder:SetText(opts.placeholder or "")
	local function hint()
		local empty = (e:GetText() or "") == "" and not f.focused
		f.placeholder:SetShown(empty and (f.placeholder:GetText() or "") ~= "")
	end
	e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	e:SetScript("OnEnterPressed", function(self)
		self:ClearFocus()
		if opts.onEnter then opts.onEnter(self:GetText()) end
	end)
	e:SetScript("OnEditFocusGained", function() f.focused = true; Theme.Tint(f.ring, "accent"); hint() end)
	e:SetScript("OnEditFocusLost", function() f.focused = false; Theme.Tint(f.ring, "border"); hint() end)
	e:SetScript("OnTextChanged", function(self, user)
		hint()
		if opts.onChange then opts.onChange(self:GetText(), user) end
	end)
	f.edit = e
	function f:GetText() return self.edit:GetText() end
	function f:SetText(text) self.edit:SetText(text or ""); hint() end
	function f:Clear() self.edit:SetText(""); hint() end
	function f:SetPlaceholder(text)
		self.placeholder:SetText(text or "")
		hint()
	end
	function f:SetFocus() self.edit:SetFocus() end
	function f:ClearFocus() self.edit:ClearFocus() end
	hint()
	return f
end

-- --- ChoiceList -------------------------------------------------------------------------------------------------------

-- A list of single-choice rows (a radio list: no UIDropDownMenu, which taints, FDCP) inside a
-- surface-2 field. choices = { { id, text, token? } }; `rows` rows show at once and the mouse wheel scrolls the rest.
-- opts: rows (6), rowHeight (24), width, onSelect(id). :SetChoices(list), :Select(id), :Selected(), :Clear(), :Count(),
-- :Scroll(delta).
function Widgets.ChoiceList(parent, opts)
	opts = opts or {}
	local rows, rowH = opts.rows or 6, opts.rowHeight or 24
	local f = CreateFrame("Frame", nil, parent)
	f:SetSize(opts.width or 240, rows * rowH + 8)
	f.fill = Theme.Slice(f, "rr_fill_8", "surface-2", "BACKGROUND")
	f.fill:SetAllPoints(f)
	f.ring = Theme.Slice(f, "rr_ring_8", "border", "BORDER")
	f.ring:SetAllPoints(f)
	f.choices, f.offset, f.rowH, f.rowsShown = {}, 0, rowH, rows
	f:EnableMouseWheel(true)
	f.rows = {}
	for i = 1, rows do
		local b = CreateFrame("Button", nil, f)
		b:SetHeight(rowH)
		b:SetPoint("TOPLEFT", f, "TOPLEFT", 4, -4 - (i - 1) * rowH)
		b:SetPoint("TOPRIGHT", f, "TOPRIGHT", -4, -4 - (i - 1) * rowH)
		b.mark = b:CreateTexture(nil, "BACKGROUND")
		Theme.Fill(b.mark, "raised", 0)
		b.mark:SetAllPoints(b)
		b.dot = b:CreateTexture(nil, "ARTWORK")
		Theme.Fill(b.dot, "accent", 0)
		b.dot:SetSize(6, 6)
		b.dot:SetPoint("LEFT", b, "LEFT", 8, 0)
		b.label = Theme.NewText(b, "Body", "text-2")
		b.label:SetPoint("LEFT", b, "LEFT", 22, 0)
		b.label:SetPoint("RIGHT", b, "RIGHT", -6, 0)
		b.label:SetJustifyH("LEFT")
		b:SetScript("OnClick", function(self) if self.choice then f:Select(self.choice.id) end end)
		b:Hide()
		f.rows[i] = b
	end
	local function paint()
		for i, b in ipairs(f.rows) do
			local c = f.choices[f.offset + i]
			b.choice = c
			if c then
				local on = f.selected ~= nil and c.id == f.selected
				b.label:SetText(c.text or "")
				Theme.Text(b.label, on and "text-1" or c.token or "text-2")
				Theme.Fill(b.mark, "raised", on and 1 or 0)
				Theme.Fill(b.dot, "accent", on and 1 or 0)
				b:Show()
			else
				b:Hide()
			end
		end
	end
	local function has(id)
		for _, c in ipairs(f.choices) do if c.id == id then return true end end
		return false
	end
	function f:SetChoices(list)
		self.choices = list or {}
		self.offset = 0
		if self.selected ~= nil and not has(self.selected) then self.selected = nil end
		paint()
	end
	function f:Select(id)
		if not has(id) then return false end
		local changed = self.selected ~= id
		self.selected = id
		paint()
		if changed and opts.onSelect then opts.onSelect(id) end
		return true
	end
	function f:Selected() return self.selected end
	function f:Clear() self.selected = nil; paint() end
	function f:Count() return #self.choices end
	function f:Scroll(delta)
		self.offset = min(max(self.offset + delta, 0), max(#self.choices - rows, 0))
		paint()
	end
	f:SetScript("OnMouseWheel", function(self, delta) self:Scroll(-delta * 2) end)
	return f
end

-- --- Small helpers for the views ------------------------------------------------------------------------------

-- A FontString in font `id` (a Theme font id) and colour `token`, justified `justify` ("LEFT" | "CENTER" | "RIGHT").
function Widgets.Text(parent, id, token, justify, layer)
	local fs = Theme.NewText(parent, id or "Body", token or "text-1", layer)
	if justify then fs:SetJustifyH(justify) end
	return fs
end

-- The hover of a list row: a surface-2 layer under the row's texts, shown while the mouse is over it (M2.5).
-- Hooked, so the row keeps its own OnEnter / OnLeave (a tooltip). Returns the texture (`row.hover`).
function Widgets.RowHover(row)
	row.hover = row:CreateTexture(nil, "BACKGROUND")
	Theme.Fill(row.hover, "surface-2", 0)
	row.hover:SetAllPoints(row)
	row:HookScript("OnEnter", function(self) Theme.Fill(self.hover, "surface-2", 1) end)
	row:HookScript("OnLeave", function(self) Theme.Fill(self.hover, "surface-2", 0) end)
	return row.hover
end
