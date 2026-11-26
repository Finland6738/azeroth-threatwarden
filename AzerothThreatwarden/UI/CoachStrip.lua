-- CoachStrip: the strip of the compact view that shows the alerts and the Coach's tip (SPEC-04 §3.1; ui-style 3.1,
-- 3.3, 3.4, 4.2; ADR 0003, 0014). Threatwarden's own. Lua 5.1; an ordinary unprotected frame; only the notice takes a click.
--
-- It reads the Data modules only (Data/Alerts.lua, Data/Coach.lua): no game API is named here (ARC-02). The view of
-- UI/ThreatList.lua builds it, places it between the header of the mob and the list header and gives it its width.
--
-- Present (a fixed place, so the rows do not jump) when the `coach` switch is on and the Coach is enabled, or the
-- `alerts` switch is on with the alerts and their window message enabled, or while a notice is held. What it says,
-- first that applies:
--   1. "Alerts muted" / "Alerts back on" for NOTE_HOLD seconds after a change of the mute;
--   2. an alert for Alerts.HOLD seconds (a new one of the same or a higher severity replaces it, a lower one does not
--      cover it): the 3 pt stripe in the state colour and the state badge (icon and word, ST-02);
--   3. the end-of-fight notice for NOTICE_HOLD seconds (SPEC-05 §3.5, the `reports` switch and
--      settings.recording.notice, off by default): "Fight recorded · 1:42 · 3 threshold crossings" with "Open report" at
--      the right; a click opens the Reports tab and emits REPORT_REQUESTED(id). Never chat, a sound or the window opened;
--   4. the Coach's tip: the stripe in `accent` and the `coach` icon;
--   5. out of combat with the Coach on, "Advice appears during combat"; else nothing (the place stays).
-- A predicted basis adds the `predict` icon, an estimated or predicted one a confidence pill; `mute` at the right while
-- the alerts are muted. The tooltip says the whole text, why, the category and the confidence, and since when.
--
-- An alert is kept only while the strip can show it (an old alert is of no use, SPEC-04 §1.4). Redrawn on its own
-- events only, never per tick; the texts are written only when they change.
local ADDON_NAME, ns = ...
ns = ns or {}
ns.modules = ns.modules or {}

local CoachStrip = {}
ns.CoachStrip, ns.modules.CoachStrip = CoachStrip, CoachStrip

local L, Widgets, Theme, Assets, Compat = ns.L, ns.Widgets, ns.Theme, ns.Assets, ns.Compat
local type, max, floor = type, math.max, math.floor

CoachStrip.HEIGHT = 18
CoachStrip.NOTE_HOLD = 2
CoachStrip.NOTICE_HOLD = 8

local ALERTS_PREFIX, COACH_PREFIX = "account.settings.alerts.", "account.settings.coach."
local NOTICE_PATH = "account.settings.recording.notice"
local CATEGORY_LABEL = {
	detected = "CAT_DETECTED", calculated = "CAT_CALCULATED", estimated = "CAT_ESTIMATED", predicted = "CAT_PREDICTED",
}
local CONFIDENCE_LABEL = { high = "CONF_HIGH", medium = "CONF_MEDIUM", low = "CONF_LOW" }
local PILL_LABEL = { high = "CONF_PILL_HIGH", medium = "CONF_PILL_MEDIUM", low = "CONF_PILL_LOW" }
local STATE_ID = { WARNING = "warning", DANGER = "danger" }

-- What is held: the alert (a copy, the module's table is reused) and the note of the mute.
local alert = { on = false }
local note = nil          -- a locale key
local notice = { on = false }   -- the end-of-fight notice: id, text
local alertToken, noteToken, noticeToken = 0, 0, 0
local settings = { enabled = true, window = true }

local function on(name) return ns.Features ~= nil and ns.Features.On(name) end

local function setting(path, default)
	local value = ns.Config and ns.Config.Get and ns.Config:Get(path)
	if type(value) ~= "boolean" then return default end
	return value
end

local function readSettings()
	local defaults = ns.Config.ALERTS_DEFAULTS
	settings.enabled = setting(ALERTS_PREFIX .. "enabled", defaults.enabled)
	settings.window = setting(ALERTS_PREFIX .. "window", defaults.window)
end

local function coachOn() return on("coach") and ns.Coach ~= nil and ns.Coach.Enabled() end
local function alertsOn() return on("alerts") and settings.enabled and settings.window end
local function muted() return on("alerts") and ns.Alerts ~= nil and ns.Alerts.IsMuted() end

local function noticeOn() return on("reports") and setting(NOTICE_PATH, false) end

-- Is there a strip at all?
function CoachStrip.Present() return coachOn() or alertsOn() or notice.on end

-- The name of a unit as the list writes it: its name, or the label of its token.
local function nameOf(unitKey)
	local Model = ns.ThreatModel
	for i = 1, Model.count do
		local rec = Model.rows[i].record
		if rec and rec.unitKey == unitKey then return ns.ThreatList.UnitLabel(rec) end
	end
	return nil
end

---------------------------------------------------------------------------------------------------------------------
-- The widget
---------------------------------------------------------------------------------------------------------------------
local Strip = {}

local function icon(parent, name, size, token)
	local tex = parent:CreateTexture(nil, "ARTWORK")
	tex:SetTexture(Assets.textures.icons.path)
	tex:SetTexCoord(Assets.IconCoords(name))
	tex:SetSize(size, size)
	Theme.Tint(tex, token)
	tex:Hide()
	return tex
end

local function setShown(region, shown)
	if region:IsShown() ~= shown then region:SetShown(shown) end
end

local function atRight(self, region, offset)
	region:ClearAllPoints()
	region:SetPoint("RIGHT", self, "RIGHT", -offset, 0)
end

-- Writes the parts: kind "note", "alert", "notice", "tip", "idle" or "empty"; the others from what is given.
function Strip:Draw(kind, text, state, category, confidence)
	local isAlert, isTip = kind == "alert", kind == "tip"
	local isNotice = kind == "notice"
	setShown(self.stripe, isAlert or isTip)
	if isAlert or isTip then
		local token = isTip and "accent" or Theme.State(state).token
		if self.stripeToken ~= token then
			self.stripeToken = token
			Theme.Fill(self.stripe, token)
		end
	end
	setShown(self.badge, isAlert)
	if isAlert then self.badge:SetState(state) end
	setShown(self.coachIcon, isTip)

	local ink = (kind == "idle") and "text-3" or (kind == "note" and "text-2" or "text-1")
	if self.ink ~= ink then
		self.ink = ink
		Theme.Text(self.text, ink)
	end
	if self.shownText ~= text then
		self.shownText = text
		self.text:SetText(text)
		self.writes = self.writes + 1
	end

	local right = 4
	setShown(self.openLabel, isNotice)
	if isNotice then
		self.openLabel:SetText(L.REPORT_OPEN)
		atRight(self, self.openLabel, right)
		right = right + self.openLabel:GetStringWidth() + 8
	end
	local isMuted = muted()
	setShown(self.muteIcon, isMuted)
	if isMuted then
		atRight(self, self.muteIcon, right)
		right = right + 14
	end
	local pill = (isAlert or isTip) and (category == "estimated" or category == "predicted")
		and PILL_LABEL[confidence or ""] or nil
	setShown(self.pill, pill ~= nil)
	if pill then
		self.pill.label:SetText(L[pill])
		self.pill:SetWidth(self.pill.label:GetStringWidth() + 10)
		atRight(self, self.pill, right)
		right = right + self.pill:GetWidth() + 4
	end
	local predicted = (isAlert or isTip) and category == "predicted"
	setShown(self.predictIcon, predicted)
	if predicted then
		atRight(self, self.predictIcon, right)
		right = right + 14
	end

	local left = 8
	if isAlert then left = left + self.badge:GetWidth() + 4 end
	if isTip then left = left + 16 end
	self.text:ClearAllPoints()
	self.text:SetPoint("LEFT", self, "LEFT", left, 0)
	self.text:SetWidth(max(10, (self.contentWidth or self:GetWidth()) - left - right))
	self.kind = kind
end

-- The strip drawn from the held alert, the note and the Coach.
function Strip:Update()
	if not CoachStrip.Present() or not self:IsVisible() then return end
	if note then
		self.tip = nil
		self:Draw("note", L[note])
	elseif alert.on then
		self:Draw("alert", alert.message, alert.state, alert.category, alert.confidence)
	elseif notice.on then
		self.tip = nil
		self:Draw("notice", notice.text)
	else
		local tip = ns.Coach and coachOn() and ns.Coach.Current() or nil
		if tip then
			local message, reason = ns.Coach.Text(tip, nameOf)
			self.tip = self.tip or {}
			local held = self.tip
			held.message, held.reason, held.category = message, reason, tip.category
			held.confidence, held.since, held.demo = tip.confidence, tip.since, tip.demo
			self:Draw("tip", message, nil, tip.category, tip.confidence)
		else
			self.tip = nil
			local scanner = ns.ThreatScanner
			if coachOn() and not (scanner and scanner.inCombat == true) then
				self:Draw("idle", L.STRIP_IDLE)
			else
				self:Draw("empty", "")
			end
		end
	end
	if Widgets.Tooltip.Owner() == self then
		local lines = self:TooltipLines()
		if lines then Widgets.Tooltip.Show(self, lines, "BOTTOM") else Widgets.Tooltip.Hide() end
	end
end

-- The whole text, why, the category and the confidence, the kind, since when, the demo and the mute.
function Strip:TooltipLines()
	local lines = {}
	local held = nil
	if self.kind == "alert" then held = alert elseif self.kind == "tip" then held = self.tip end
	if self.kind == "notice" then
		lines[#lines + 1] = notice.text
		lines[#lines + 1] = L.REPORT_OPEN
	end
	if held then
		lines[#lines + 1] = held.message
		lines[#lines + 1] = L.STRIP_WHY:format(held.reason)
		local category = CATEGORY_LABEL[held.category or ""]
		local confidence = CONFIDENCE_LABEL[held.confidence or ""]
		if category and confidence then lines[#lines + 1] = L.STRIP_BASIS:format(L[category], L[confidence]) end
		lines[#lines + 1] = self.kind == "alert" and L.STRIP_ALERT or L.STRIP_ADVICE
		local since = self.kind == "alert" and held.at or held.since
		lines[#lines + 1] = L.STRIP_SINCE:format(floor(max(Compat.Now() - since, 0)))
		if held.demo then lines[#lines + 1] = L.MON_DEMO_TIP end
	end
	if muted() then
		lines[#lines + 1] = (ns.addon and ns.addon.inCombat) and L.STRIP_TIP_MUTED or L.STRIP_TIP_MUTED_NEXT
	end
	if #lines == 0 then return nil end
	return lines
end

-- Builds the strip in `parent`; the caller anchors it and shows it while Present().
function CoachStrip.Build(parent)
	local f = CreateFrame("Frame", nil, parent)
	for name, fn in pairs(Strip) do f[name] = fn end
	f.writes = 0
	f:SetHeight(CoachStrip.HEIGHT)
	f.fill = Theme.Slice(f, "rr_fill_4", "surface-2", "BACKGROUND")
	f.fill:SetAllPoints(f)
	f.stripe = f:CreateTexture(nil, "ARTWORK")
	f.stripe:SetWidth(3)
	f.stripe:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
	f.stripe:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)
	f.stripe:Hide()
	f.badge = Widgets.StateBadge(f)
	f.badge:SetPoint("LEFT", f, "LEFT", 8, 0)
	f.badge:Hide()
	f.coachIcon = icon(f, "coach", 12, "accent-text")
	f.coachIcon:SetPoint("LEFT", f, "LEFT", 8, 0)
	f.muteIcon = icon(f, "mute", 10, "text-2")
	f.predictIcon = icon(f, "predict", 10, "text-2")
	f.text = Theme.NewText(f, "Row", "text-1")
	f.text:SetJustifyH("LEFT")
	if f.text.SetWordWrap then f.text:SetWordWrap(false) end
	f.pill = CreateFrame("Frame", nil, f)
	f.pill:SetHeight(Widgets.BADGE_HEIGHT)
	f.pill.fill = Theme.Slice(f.pill, "rr_fill_8", "surface-3", "BACKGROUND")
	f.pill.fill:SetAllPoints(f.pill)
	f.pill.label = Theme.NewText(f.pill, "Badge", "text-2")
	f.pill.label:SetPoint("CENTER", f.pill, "CENTER", 0, 0)
	f.pill:Hide()
	f.openLabel = Theme.NewText(f, "Row", "accent-text")
	f.openLabel:Hide()
	f:EnableMouse(true)
	f:SetScript("OnMouseUp", function(self, button)
		if self.kind == "notice" and button ~= "RightButton" then CoachStrip.OpenReport() end
	end)
	Widgets.Tooltip.Attach(f, function(self) return self:TooltipLines() end, "BOTTOM")
	f:SetScript("OnShow", function(self) self:Update() end)
	f:Hide()
	CoachStrip.frame = f
	return f
end

---------------------------------------------------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------------------------------------------------
local function update()
	if CoachStrip.frame then CoachStrip.frame:Update() end
end

local function dropAlert()
	alert.on = false
	alertToken = alertToken + 1
end

local function dropNote()
	note = nil
	noteToken = noteToken + 1
end

local redrawView

local function dropNotice()
	if not notice.on then return end
	notice.on = false
	noticeToken = noticeToken + 1
end

-- The click on the notice: the Reports tab, on the session of the notice.
function CoachStrip.OpenReport()
	if not notice.on then return false end
	local id = notice.id
	dropNotice()
	local window = ns.Window
	if window then
		window:Open()
		window:SelectTab("reports")
	end
	if ns.Bus then ns.Bus.Emit("REPORT_REQUESTED", id) end
	redrawView()
	return true
end

-- A session closed complete and kept: the notice, if the setting asks for it and the window shows the Monitor tab.
local function onSessionEnded(id, state)
	if state ~= "complete" or not noticeOn() or (ns.addon and ns.addon.inCombat) then return end
	if ns.Demo and ns.Demo.IsActive() then return end
	local f = CoachStrip.frame
	if not f or not f:GetParent():IsVisible() then return end
	local s = ns.Storage and ns.Storage.Get(id)
	if not s then return end
	local length = ns.Report.Time(s.dur)
	local cross = type(s.sum) == "table" and s.sum.cross or nil
	notice.on, notice.id = true, id
	if cross == 1 then notice.text = L.REPORT_NOTICE_ONE:format(length)
	elseif cross then notice.text = L.REPORT_NOTICE:format(length, cross)
	else notice.text = L.REPORT_NOTICE_PLAIN:format(length) end
	noticeToken = noticeToken + 1
	local mine = noticeToken
	Compat.After(CoachStrip.NOTICE_HOLD, function()
		if mine ~= noticeToken then return end
		notice.on = false
		redrawView()
	end)
	redrawView()
end

-- An alert with the window channel: taken while the strip can show it.
local function onAlert(raised)
	if not alertsOn() or not raised.window then return end
	local f = CoachStrip.frame
	if not f or not f:IsVisible() then return end
	if alert.on and raised.severity < alert.severity then return end
	local message, reason = ns.Alerts.Text(raised, nameOf)
	if not message then return end
	dropNote()
	alert.on = true
	alert.message, alert.reason, alert.severity = message, reason, raised.severity
	alert.state = STATE_ID[raised.state] or "unknown"
	alert.category, alert.confidence = raised.category, raised.confidence
	alert.at, alert.demo = raised.at, raised.demo
	alertToken = alertToken + 1
	local mine = alertToken
	Compat.After(ns.Alerts.HOLD, function()
		if mine ~= alertToken then return end
		alert.on = false
		update()
	end)
	update()
end

local function onMute(value)
	if not CoachStrip.Present() then return end
	dropAlert()
	note = value and "STRIP_MUTED" or "STRIP_UNMUTED"
	noteToken = noteToken + 1
	local mine = noteToken
	Compat.After(CoachStrip.NOTE_HOLD, function()
		if mine ~= noteToken then return end
		note = nil
		update()
	end)
	update()
end

function redrawView()
	local view = ns.ThreatList and ns.ThreatList.view
	if view then view:Redraw() end
	update()
end

if ns.Bus then
	local Bus = ns.Bus
	Bus.On("ALERT_RAISED", onAlert)
	Bus.On("COACH_TIP", update)
	Bus.On("MUTE_CHANGED", onMute)
	Bus.On("COMBAT_STARTED", function()
		if notice.on then
			dropNotice()
			redrawView()
		else
			update()
		end
	end)
	Bus.On("SESSION_ENDED", onSessionEnded)
	Bus.On("COMBAT_ENDED", update)
	Bus.On("THEME_CHANGED", update)
	-- the demo starts or ends: nothing of the other fight stays
	Bus.On("DEMO_CHANGED", function(active)
		if alert.on and alert.demo ~= (active == true) then dropAlert() end
		if active then dropNotice() end
		redrawView()
	end)
	Bus.On("CONFIG_LOADED", function()
		readSettings()
		redrawView()
	end)
	Bus.On("CONFIG_CHANGED", function(path)
		if type(path) ~= "string" then return end
		if path == NOTICE_PATH and not noticeOn() and notice.on then
			dropNotice()
			redrawView()
		end
		local alerts = path:sub(1, #ALERTS_PREFIX) == ALERTS_PREFIX
		if not alerts and path:sub(1, #COACH_PREFIX) ~= COACH_PREFIX then return end
		readSettings()
		if alerts and not alertsOn() then
			dropAlert()
			dropNote()
		end
		redrawView()
	end)
end

if ns.addon then ns.addon.CoachStrip = CoachStrip end
