-- Widget kit, part 5: StateBadge, StateStripe and ThreatBar (docs/specs/ui-style.md 3.2, 3.3 and 4.2). New in
-- Threatwarden. They draw what they are given and read nothing: the threat data come with M2. Lua 5.1; unprotected.
-- Rules: a state is always an icon and a word together, never a colour alone (ST-02); the state colours are the tokens
-- of Theme.STATE, the same in every theme; an unknown value is drawn as unknown, never as an empty bar that looks like
-- 0 % (ADR 0003). `bar:Set` does nothing when it is given what it already shows (up to 40 rows a tick, M2.5).
local ADDON_NAME, ns = ...
ns = ns or {}
local Widgets, Theme, Motion, Assets, L = ns.Widgets, ns.Theme, ns.Motion, ns.Assets, ns.L
local type, max, min = type, math.max, math.min

local function stateIcon(parent, size, token)
	local icon = parent:CreateTexture(nil, "ARTWORK")
	icon:SetTexture(Assets.textures.icons.path)
	icon:SetSize(size, size)
	Theme.Tint(icon, token)
	return icon
end

-- --- StateBadge -------------------------------------------------------------------------------------------------------

Widgets.BADGE_HEIGHT, Widgets.BADGE_HEIGHT_LARGE = 14, 18   -- in a row; in the header of the mob

-- A pill filled with the state colour, with the icon and the word of the state in `on-state`. opts: large, state.
-- :SetState("safe" | "warning" | "danger" | "unknown"; anything else is unknown), :GetState().
function Widgets.StateBadge(parent, opts)
	opts = opts or {}
	local height = opts.large and Widgets.BADGE_HEIGHT_LARGE or Widgets.BADGE_HEIGHT
	local f = CreateFrame("Frame", nil, parent)
	f:SetHeight(height)
	f.fill = Theme.Slice(f, "rr_fill_8", "state-unknown", "BACKGROUND")
	f.fill:SetAllPoints(f)
	f.icon = stateIcon(f, 10, "on-state")
	f.icon:SetPoint("LEFT", f, "LEFT", 5, 0)
	f.label = Theme.NewText(f, "Badge", "on-state")
	f.label:SetPoint("LEFT", f.icon, "RIGHT", 3, 0)
	function f:SetState(id)
		local def = Theme.State(id)
		id = Theme.STATES[id] and id or "unknown"
		if self.state == id then return end
		self.state = id
		Theme.Tint(self.fill, def.token)
		self.icon:SetTexCoord(Assets.IconCoords(def.icon))
		self.label:SetText(L[def.labelKey])
		self:SetWidth(max(height * 2, self.label:GetStringWidth() + 5 + 10 + 3 + 7))
	end
	function f:GetState() return self.state end
	f:SetState(opts.state)
	return f
end

-- --- StateStripe ------------------------------------------------------------------------------------------------------

-- The 3 pt strip on the left edge of a row that repeats the colour of its state (ui-style 3.3).
-- :SetState(id), :GetState().
function Widgets.StateStripe(row)
	local f = CreateFrame("Frame", nil, row)
	f:SetWidth(3)
	f:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
	f:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
	f.fill = f:CreateTexture(nil, "ARTWORK")
	f.fill:SetAllPoints(f)
	function f:SetState(id)
		id = Theme.STATES[id] and id or "unknown"
		if self.state == id then return end
		self.state = id
		Theme.Fill(self.fill, Theme.State(id).token)
	end
	function f:GetState() return self.state end
	f:SetState("unknown")
	return f
end

-- --- ThreatBar --------------------------------------------------------------------------------------------------------

Widgets.BAR_HEIGHT, Widgets.BAR_NUMBER_WIDTH, Widgets.BAR_ICON = 10, 40, 10

-- A finite number, not negative; anything else is not a value.
local function isPercent(v) return type(v) == "number" and v >= 0 and v < math.huge end

local function dashedEdge(track, from, to)
	local tex = track:CreateTexture(nil, "OVERLAY")
	tex:SetTexture(Assets.textures.dash.path, "REPEAT", "CLAMP")
	if tex.SetHorizTile then tex:SetHorizTile(true) end
	Theme.Tint(tex, "state-unknown")
	tex:SetPoint(from, track, from, 0, 0)
	tex:SetPoint(to, track, to, 0, 0)
	tex:SetHeight(1)
	return tex
end

local function sideDash(track, corner, y)
	local tex = track:CreateTexture(nil, "OVERLAY")
	Theme.Fill(tex, "state-unknown")
	tex:SetSize(1, 3)
	tex:SetPoint(corner, track, corner, 0, y)
	return tex
end

-- The bar of one row: a 10 pt track in surface-3 with the fill in the colour of the state, min(percent, 100) % wide; past
-- 100 % the track is full and a 2 pt mark in text-1 says so; 1 pt ticks at the thresholds; the number at the right,
-- never on the bar. An estimated value is "~87 %" in text-2; a predicted one shows the `predict` icon. Unknown: no
-- fill, a dashed outline, "?" and the caller's reason in the tooltip.
-- opts: width (180, the number included), numberWidth (40), thresholds ({ warning, danger } in percent), anchor (of the
-- tooltip, "TOP").
-- :Set(percent, state, estimated, predicted, tooltip) -- percent nil (or not a number) or state "unknown" is unknown;
--   the tooltip is a Widgets.Tooltip content, already translated (the reason of an unknown value, "may" of a prediction).
-- :SetThresholds(warning, danger), :SetWidth(w), :GetState(), :GetPercent() (nil when unknown).
function Widgets.ThreatBar(parent, opts)
	opts = opts or {}
	local numberWidth = opts.numberWidth or Widgets.BAR_NUMBER_WIDTH
	local bar = CreateFrame("Frame", nil, parent)
	bar:SetSize(opts.width or 180, Widgets.BAR_HEIGHT + 4)

	bar.number = Theme.NewText(bar, "RowMono", "text-1")
	bar.number:SetPoint("RIGHT", bar, "RIGHT", 0, 0)
	bar.number:SetWidth(numberWidth)
	bar.number:SetJustifyH("RIGHT")
	bar.predict = stateIcon(bar, Widgets.BAR_ICON, "text-2")
	bar.predict:SetTexCoord(Assets.IconCoords("predict"))
	bar.predict:SetPoint("RIGHT", bar, "RIGHT", -numberWidth - 2, 0)
	bar.predict:Hide()

	local track = CreateFrame("Frame", nil, bar)
	track:SetHeight(Widgets.BAR_HEIGHT)
	track:SetPoint("LEFT", bar, "LEFT", 0, 0)
	track:SetPoint("RIGHT", bar, "RIGHT", -(numberWidth + Widgets.BAR_ICON + 4), 0)
	bar.track = track
	track.fill = Theme.Slice(track, "rr_fill_4", "surface-3", "BACKGROUND")
	track.fill:SetAllPoints(track)
	bar.fill = Theme.Slice(track, "rr_fill_4", "state-unknown", "ARTWORK")
	bar.fill:SetPoint("TOPLEFT", track, "TOPLEFT", 0, 0)
	bar.fill:SetPoint("BOTTOMLEFT", track, "BOTTOMLEFT", 0, 0)
	bar.fill:Hide()
	bar.over = track:CreateTexture(nil, "OVERLAY")
	Theme.Fill(bar.over, "text-1")
	bar.over:SetWidth(2)
	bar.over:SetPoint("TOPRIGHT", track, "TOPRIGHT", 0, 0)
	bar.over:SetPoint("BOTTOMRIGHT", track, "BOTTOMRIGHT", 0, 0)
	bar.over:Hide()
	bar.ticks = {}
	for i = 1, 2 do
		local tick = track:CreateTexture(nil, "OVERLAY")
		Theme.Fill(tick, "border-strong")
		tick:SetWidth(Theme.Px(1))
		tick:Hide()
		bar.ticks[i] = tick
	end
	bar.dashes = {
		dashedEdge(track, "TOPLEFT", "TOPRIGHT"), dashedEdge(track, "BOTTOMLEFT", "BOTTOMRIGHT"),
		sideDash(track, "TOPLEFT", -1), sideDash(track, "TOPLEFT", -6),
		sideDash(track, "TOPRIGHT", -1), sideDash(track, "TOPRIGHT", -6),
	}

	local shown, from, to = 0, 0, 0   -- the width fraction drawn; the ends of the tween
	local fromR, fromG, fromB, toR, toG, toB = 0, 0, 0, 0, 0, 0
	local thresholds = {}

	local function trackWidth()
		local w = track:GetWidth() or 0
		if w <= 1 then w = (bar:GetWidth() or 0) - numberWidth - Widgets.BAR_ICON - 4 end
		return max(w, 1)
	end
	local function drawWidth(f)
		shown = f
		if f <= 0 then
			bar.fill:Hide()
		else
			bar.fill:SetWidth(max(trackWidth() * f, 1))
			bar.fill:Show()
		end
	end
	local function step(_, f)   -- one function for every tween of this bar
		drawWidth(from + (to - from) * f)
		bar.fill:SetVertexColor(fromR + (toR - fromR) * f, fromG + (toG - fromG) * f, fromB + (toB - fromB) * f, 1)
	end
	local function layoutTicks()
		for i = 1, 2 do
			local tick, at = bar.ticks[i], thresholds[i]
			if at and at > 0 and at < 100 then
				local x = trackWidth() * at / 100
				tick:ClearAllPoints()
				tick:SetPoint("TOPLEFT", track, "TOPLEFT", x, 0)
				tick:SetPoint("BOTTOMLEFT", track, "BOTTOMLEFT", x, 0)
				tick:Show()
			else
				tick:Hide()
			end
		end
	end
	local function showUnknown(unknown)
		for i = 1, #bar.dashes do bar.dashes[i]:SetShown(unknown) end
	end

	function bar:SetThresholds(warning, danger)
		thresholds[1], thresholds[2] = warning, danger
		layoutTicks()
	end

	function bar:Set(percent, state, estimated, predicted, tooltip)
		local unknown = not isPercent(percent) or state == "unknown" or not Theme.STATES[state]
		if unknown then state, percent = "unknown", nil end
		estimated, predicted = estimated == true, predicted == true
		if self.state == state and self.percent == percent and self.estimated == estimated and self.predicted == predicted
			and self.tooltip == tooltip then
			return
		end
		local changedState = self.state ~= state
		local previous = self.state
		self.estimated, self.predicted = estimated, predicted
		self.state, self.percent, self.tooltip = state, percent, tooltip
		if unknown then
			self.number:SetText("?")
			if changedState then Theme.Text(self.number, "text-2") end
		else
			self.number:SetFormattedText(estimated and "~%d %%" or "%d %%", percent + 0.5)
		end
		local ink = (unknown or estimated) and "text-2" or "text-1"
		if self.ink ~= ink then self.ink = ink; Theme.Text(self.number, ink) end
		self.predict:SetShown(not unknown and predicted)
		self.over:SetShown(not unknown and percent > 100)
		showUnknown(unknown)

		local fraction = unknown and 0 or min(percent, 100) / 100
		local oldR, oldG, oldB = self.fill:GetVertexColor()   -- before the tint: where the colour fades from
		if changedState then Theme.Tint(self.fill, Theme.State(state).token) end
		if unknown then
			Motion.StopTween(self)   -- at once: an unknown value leaves no trace of the old one
			from, to = 0, 0
			drawWidth(0)
		else
			local r, g, b = Theme.Color(Theme.State(state).token)
			if previous and previous ~= "unknown" then
				fromR, fromG, fromB = oldR, oldG, oldB
			else
				fromR, fromG, fromB = r, g, b
			end
			from, to, toR, toG, toB = shown, fraction, r, g, b
			Motion.Tween(self, Motion.FAST, step, self)
		end
		if Widgets.Tooltip.Owner() == self then
			if tooltip then Widgets.Tooltip.Show(self, tooltip, opts.anchor or "TOP") else Widgets.Tooltip.Hide() end
		end
	end
	function bar:GetState() return self.state end
	function bar:GetPercent() return self.percent end

	bar:SetScript("OnSizeChanged", function()
		drawWidth(shown)
		layoutTicks()
	end)
	bar:EnableMouse(true)
	Widgets.Tooltip.Attach(bar, function(self) return self.tooltip end, opts.anchor or "TOP")
	if opts.thresholds then bar:SetThresholds(opts.thresholds[1], opts.thresholds[2]) end
	bar:Set(nil, "unknown")
	return bar
end
