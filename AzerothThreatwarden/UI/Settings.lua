-- Settings: the Settings tab of the window and the panel of the game's own Settings window (SPEC-03 §4.4 and §5,
-- docs/specs/ui-style.md §2 and §3). Lua 5.1; no game API is named here (ARC-02): CreateFrame and Core/Compat.lua.
-- Adapted from Azeroth Accord (UI/Settings.lua and the panel of UI/SettingsModel.lua), same owner, GPL-3.0 (ADR 0012).
-- Changes: the cards are Threatwarden's own (Appearance, Language, Window, Monitor while the `monitor` switch is on,
-- Alerts while the `alerts` switch is on (SPEC-04 §4.2, its Coach switch with `coach`), Recording while the
-- `recording` switch is on (SPEC-05 §3.6), Reset); no model file, because every value
-- is a path of Core/Config.lua; the cards follow the width they get; the scale is saved when the slider is released.
--
-- Every control writes through Config:Set and the change applies at once through CONFIG_CHANGED (Theme, Motion,
-- Window, Launcher listen to it). Two exceptions, said on the card: the font is complete after the game restarts, and
-- the language after /reload.
--
--   Settings.Build(parent, opts) -> view   a page selector (Settings, Info) and the pages; one builder for the window's
--                                          Settings tab and for the game's panel. opts.onPage(id): the player chose a page.
--                                          view.pager, view:ShowPage(id), view:Layout(), view:Refresh(); the controls of
--                                          the Settings page are fields of view.settings, the parts of Info of view.info.
--   Settings.AddPage(id, def)              another page: def = { labelKey, order, build(holder, view) -> page }, where
--                                          page has :Layout(width) (UI/About.lua adds "about").
--   Settings.RegisterPanel()               adds the panel to the game's Settings window (once); false when the client
--                                          has none.
--
-- Bus: emits SETTINGS_CHANGED(key) after the player changes an option; listens CONFIG_LOADED, CONFIG_CHANGED,
-- THEME_CHANGED, DEMO_CHANGED, ENTERING_WORLD and, with the Recording card, SESSIONS_CHANGED, SESSION_STARTED and
-- SESSION_ENDED; ENTERING_WORLD (the game's own threat warning is read again) to repaint the pages
-- on screen.
local ADDON_NAME, ns = ...
ns = ns or {}
ns.modules = ns.modules or {}

local View = {}
ns.Settings, ns.modules.Settings = View, View

local L, Widgets, Theme, Compat = ns.L, ns.Widgets, ns.Theme, ns.Compat
local ipairs, type, max, min, floor = ipairs, type, math.max, math.min, math.floor

View.PAGE_WIDTH = 520        -- the widest a column of cards gets
View.CARD_PAD = 20           -- inside a card
View.CARD_GAP = 12           -- between cards
View.PAGER_HEIGHT = 44       -- the page selector
View.WHEEL_STEP = 40
View.CONFIRM_SECONDS = 8     -- how long "Click again to reset" waits
View.instances = {}          -- every view built (the window's tab, the game's panel): repainted together
View.pages = {}              -- { id, labelKey, order, build } in order

local function config() return ns.Config end
local function get(path) return config() and config():Get(path) end
local function monitorOn() return ns.Features ~= nil and ns.Features.On("monitor") end
local function alertsOn() return ns.Features ~= nil and ns.Features.On("alerts") end
local function coachOn() return ns.Features ~= nil and ns.Features.On("coach") end
local function recordingOn() return ns.Features ~= nil and ns.Features.On("recording") end
local function focusOn() return ns.Features ~= nil and ns.Features.On("multitarget") end

---------------------------------------------------------------------------------------------------------------------
-- Cards and rows (also used by UI/About.lua)
---------------------------------------------------------------------------------------------------------------------
-- A card whose items stack from the top. card:Add(region, gap, opts): `region` goes `gap` points under the previous one;
-- opts.stretch gives it the card's inner width (texts and rows), opts.indent moves it right. card:Layout(width) places
-- them (hidden ones take no room) and sets the card's size.
function View.StackCard(page)
	local c = Widgets.Card(page, { width = View.PAGE_WIDTH, height = 100 })
	c.items = {}
	function c:Add(region, gap, opts)
		opts = opts or {}
		self.items[#self.items + 1] = { region = region, gap = gap or 8, stretch = opts.stretch }
		return region
	end
	function c:Layout(width)
		local pad = View.CARD_PAD
		local inner = width - 2 * pad
		self:SetWidth(width)
		local y, first = pad, true
		for _, it in ipairs(self.items) do
			local r = it.region
			if r:IsShown() then
				if not first then y = y + it.gap end
				first = false
				if it.stretch then r:SetWidth(inner) end
				if r.Reflow then r:Reflow(inner) end
				r:ClearAllPoints()
				r:SetPoint("TOPLEFT", self, "TOPLEFT", pad, -y)
				local h
				if r:GetObjectType() == "FontString" then h = r:GetStringHeight() else h = r:GetHeight() end
				y = y + (h or 0)
			end
		end
		self:SetHeight(y + pad)
		return self:GetHeight()
	end
	return c
end

-- A wrapping text of a card, in font `font` and colour `token`.
function View.CardText(card, font, token, str, gap)
	local fs = Widgets.Text(card, font or "Body", token or "text-2", "LEFT")
	fs:SetWordWrap(true)
	fs:SetText(str or "")
	return card:Add(fs, gap, { stretch = true })
end

-- A scrolling column of cards inside `holder`: returns the page, { frame, scroll, cards = {} } with :Layout(width).
function View.Column(holder)
	local scroll = CreateFrame("ScrollFrame", nil, holder)
	scroll:SetAllPoints(holder)
	local frame = CreateFrame("Frame", nil, scroll)
	frame:SetSize(View.PAGE_WIDTH, 100)
	scroll:SetScrollChild(frame)
	scroll:EnableMouseWheel(true)
	local page = { frame = frame, scroll = scroll, cards = {}, height = 0 }
	local function range() return max(0, page.height - (scroll:GetHeight() or 0)) end
	scroll:SetScript("OnMouseWheel", function(self, delta)
		self:SetVerticalScroll(min(range(), max(0, (self:GetVerticalScroll() or 0) - delta * View.WHEEL_STEP)))
	end)
	function page:Layout(width)
		local y = 0
		for _, card in ipairs(self.cards) do
			if card:IsShown() then
				card:Layout(width)
				card:ClearAllPoints()
				card:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 0, -y)
				y = y + card:GetHeight() + View.CARD_GAP
			end
		end
		self.height = max(1, y - View.CARD_GAP + 8)
		self.frame:SetSize(width, self.height)
		if (self.scroll:GetVerticalScroll() or 0) > range() then self.scroll:SetVerticalScroll(range()) end
	end
	-- Scrolls so that `card` starts at the top (or as near as the end of the page allows).
	function page:ScrollTo(card)
		local y = 0
		for _, other in ipairs(self.cards) do
			if other == card then break end
			if other:IsShown() then y = y + other:GetHeight() + View.CARD_GAP end
		end
		self.scroll:SetVerticalScroll(min(range(), y))
	end
	return page
end

-- A line with a label at the left and `control` at the right.
local function controlRow(card, label, control, height)
	local row = CreateFrame("Frame", nil, card)
	row:SetHeight(height or 32)
	control:SetParent(row)
	control:ClearAllPoints()
	control:SetPoint("RIGHT", row, "RIGHT", 0, 0)
	row.label = Widgets.Text(row, "BodyMedium", "text-1", "LEFT")
	row.label:SetPoint("LEFT", row, "LEFT", 0, 0)
	row.label:SetPoint("RIGHT", control, "LEFT", -12, 0)
	row.label:SetText(label)
	row.control = control
	return row
end

---------------------------------------------------------------------------------------------------------------------
-- Writing a setting
---------------------------------------------------------------------------------------------------------------------
-- The line at the foot of a card: what happened, in `token` ("warn" for a refusal, "text-2" for news).
local function say(card, text, token)
	card.status:SetText(text or "")
	Theme.Text(card.status, token or "text-2")
end

-- Says how a write went, tells the others and puts the page back to the stored values. Returns ok.
local function wrote(view, card, key, ok, why)
	if ok then
		say(card, "")
		if ns.Bus then ns.Bus.Emit("SETTINGS_CHANGED", key) end
	else
		say(card, L["SET_NOT_SAVED"]:format(tostring(why)), "warn")
	end
	view:Refresh()
	return ok
end

-- Writes `path` and says why when it is refused. Returns ok.
local function write(view, card, path, value)
	if view.refreshing then return true end
	return wrote(view, card, path, config():Set(path, value))
end

local function statusLine(card)
	card.status = View.CardText(card, "Small", "warn", "", 8)
	card.status:Hide()
	return card.status
end

---------------------------------------------------------------------------------------------------------------------
-- The cards
---------------------------------------------------------------------------------------------------------------------
local function switch(view, card, path, label, invert)
	local sw = Widgets.Switch(card, { onChange = function(on)
		if invert then on = not on end
		write(view, card, path, on)
	end })
	return card:Add(controlRow(card, label, sw), 8, { stretch = true })
end

local function segment(view, card, path, label, items)
	local seg = Widgets.Segmented(card, items, function(id) write(view, card, path, id) end)
	return card:Add(controlRow(card, label, seg), 8, { stretch = true })
end

local function buildAppearance(view, f, page)
	local card = View.StackCard(page.frame)
	View.CardText(card, "H2", "text-1", L["SET_APPEARANCE"], 0)
	local themes = {}
	for i, id in ipairs(Theme.List()) do themes[i] = { id = id, text = L["THEME_" .. id:upper()] } end
	f.theme = segment(view, card, "account.settings.theme", L["SET_THEME"], themes)
	f.effects = switch(view, card, "account.settings.effects", L["SET_EFFECTS"])
	View.CardText(card, "Small", "text-3", L["SET_EFFECTS_NOTE"], 2)
	f.animations = switch(view, card, "account.settings.animations", L["SET_ANIMATIONS"])
	f.font = segment(view, card, "account.settings.font", L["SET_FONT"],
		{ { id = "addon", text = L["SET_FONT_ADDON"] }, { id = "game", text = L["SET_FONT_GAME"] } })
	f.fontNote = View.CardText(card, "Small", "text-3", L["SET_FONT_NOTE"], 2)
	statusLine(card)
	return card
end

local function buildLanguage(view, f, page)
	local card = View.StackCard(page.frame)
	View.CardText(card, "H2", "text-1", L["SET_LANGUAGE"], 0)
	local items = {}
	for i, code in ipairs(ns.Config.LANGUAGES) do items[i] = { id = code, text = L["LANGUAGE_" .. code:upper()] } end
	f.language = Widgets.Segmented(card, items, function(id) write(view, card, "account.settings.language", id) end)
	card:Add(f.language, 12)
	f.languageNote = View.CardText(card, "Small", "text-3", L["SET_LANGUAGE_NOTE"], 8)
	f.reload = Widgets.Button(card, { text = L["SET_RELOAD"], style = "primary", onClick = function() Compat.Reload() end })
	card:Add(f.reload, 12)
	statusLine(card)
	return card
end

-- A slider with its value at the right, saved when the thumb is released (a click or a key saves at once).
-- opts: min, max, step, format(v) -> text, commit(v), valueWidth (48). Returns the box: .slider, .value, .show(v), .dragging.
local function sliderBox(card, opts)
	local box = CreateFrame("Frame", nil, card)
	box:SetSize(240, 24)
	box.value = Widgets.Text(box, "Mono", "text-1", "RIGHT")
	box.value:SetPoint("RIGHT", box, "RIGHT", 0, 0)
	box.value:SetWidth(opts.valueWidth or 48)
	local function show(v) box.value:SetText(opts.format(floor(v + 0.5))) end
	box.slider = Widgets.Slider(box, { min = opts.min, max = opts.max, step = opts.step, width = 180, value = opts.min,
		onChange = function(v, user)
			show(v)
			if user and not box.dragging then opts.commit(v) end
		end })
	box.slider:SetPoint("RIGHT", box.value, "LEFT", -8, 0)
	box.slider:HookScript("OnMouseDown", function() box.dragging = true end)
	box.slider:HookScript("OnMouseUp", function(self)
		box.dragging = false
		opts.commit(self:GetValue())
	end)
	box.show = show
	-- the stored value, unless the player is moving the thumb
	function box:Update(v)
		if self.dragging then return end
		self.slider:Set(v)
		show(v)
	end
	return box
end

local function buildWindowCard(view, f, page)
	local card = View.StackCard(page.frame)
	View.CardText(card, "H2", "text-1", L["SET_WINDOW"], 0)
	f.lock = switch(view, card, "char.ui.locked", L["SET_LOCK"])

	-- the scale is saved when the thumb is released: the window scales under the mouse
	local scale = ns.Config.SCALE
	local box = sliderBox(card, { min = scale.min * 100, max = scale.max * 100, step = scale.step * 100,
		format = function(v) return L["SET_PERCENT"]:format(v) end,
		commit = function(v) write(view, card, "char.ui.scale", v / 100) end })
	f.scale = card:Add(controlRow(card, L["SET_SCALE"], box), 8, { stretch = true })
	f.scaleBox = box

	f.minimap = switch(view, card, "account.settings.minimap.hide", L["SET_MINIMAP"], true)
	f.resetWindow = Widgets.Button(card, { text = L["SET_RESET_WINDOW"], style = "secondary", onClick = function()
		local ok = ns.Window:Reset()
		say(card, L[ok and "CMD_RESET" or "CMD_READ_ONLY"], not ok and "warn" or nil)
		view:Refresh()
	end })
	card:Add(f.resetWindow, 12)
	statusLine(card)
	return card
end

local MONITOR = "account.settings.monitor."

-- Moving one threshold pushes the other when they would come closer than the gap (Core/Config.lua).
local function setThresholds(view, card, warning, danger)
	if view.refreshing then return true end
	return wrote(view, card, MONITOR .. "thresholds", config():SetThresholds(warning, danger))
end

local function buildMonitor(view, f, page)
	local Limits = ns.Config.MONITOR
	local card = View.StackCard(page.frame)
	View.CardText(card, "H2", "text-1", L["SET_MONITOR"], 0)
	local function percent(v) return L["SET_PERCENT"]:format(v) end
	local function row(label, box, gap)
		return card:Add(controlRow(card, label, box), gap or 8, { stretch = true })
	end

	-- warning stops at the highest value that leaves danger room above it
	local top = Limits.danger.max - Limits.gap
	f.warning = sliderBox(card, { min = Limits.warning.min, max = top, step = 1, format = percent, commit = function(v)
		v = min(floor(v + 0.5), top)
		setThresholds(view, card, v, max(get(MONITOR .. "danger"), v + Limits.gap))
	end })
	row(L["SET_WARNING"], f.warning, 12)
	f.danger = sliderBox(card, { min = Limits.danger.min, max = Limits.danger.max, step = 1, format = percent,
		commit = function(v)
			v = floor(v + 0.5)
			setThresholds(view, card, min(get(MONITOR .. "warning"), v - Limits.gap), v)
		end })
	row(L["SET_DANGER"], f.danger)
	View.CardText(card, "Small", "text-3", L["SET_THRESHOLDS_NOTE"]:format(Limits.gap), 2)

	local function number(key, label, format, note)
		f[key] = sliderBox(card, { min = Limits[key].min, max = Limits[key].max, step = 1, format = format,
			commit = function(v) write(view, card, MONITOR .. key, floor(v + 0.5)) end })
		row(label, f[key], 12)
		View.CardText(card, "Small", "text-3", note, 2)
	end
	number("rate", L["SET_RATE"], function(v) return L["SET_HERTZ"]:format(v) end, L["SET_RATE_NOTE"])
	number("maxUnits", L["SET_MAX_UNITS"], tostring, L["SET_MAX_UNITS_NOTE"])

	View.CardText(card, "BodyMedium", "text-1", L["SET_SHOW"], 12)
	local modes = {}
	for i, id in ipairs(ns.Config.SHOW_MODES) do modes[i] = { id = id, text = L["SHOW_" .. id:upper()] } end
	f.show = Widgets.Segmented(card, modes, function(id) write(view, card, MONITOR .. "show", id) end)
	card:Add(f.show, 8)
	View.CardText(card, "Small", "text-3", L["SET_SHOW_NOTE"]:format(ns.Window.AUTO_CLOSE), 8)

	local orders = {}
	for i, id in ipairs(ns.Config.SORTS) do orders[i] = { id = id, text = L["SORT_" .. id:upper()] } end
	f.sort = Widgets.Select(card, { width = 200, rows = #orders, choices = orders,
		onSelect = function(id) write(view, card, MONITOR .. "sort", id) end })
	row(L["SET_SORT"], f.sort, 12)
	f.pinSelf = switch(view, card, MONITOR .. "pinSelf", L["SET_PIN_SELF"])
	f.follow = switch(view, card, MONITOR .. "followTargetOfTarget", L["SET_FOLLOW"])
	View.CardText(card, "Small", "text-3", L["SET_FOLLOW_NOTE"], 2)

	View.CardText(card, "Small", "text-2", L["SET_DEMO_NOTE"], 12)
	f.demo = Widgets.Button(card, { text = L["SET_DEMO_START"], style = "secondary", width = 200, onClick = function()
		ns.Demo.Toggle()
		view:Refresh()
	end })
	card:Add(f.demo, 8)
	statusLine(card)
	return card
end

local function refreshMonitor(f)
	for _, key in ipairs({ "warning", "danger", "rate", "maxUnits" }) do f[key]:Update(get(MONITOR .. key)) end
	f.show:Select(get(MONITOR .. "show"))
	f.sort:Select(get(MONITOR .. "sort"), true)
	f.pinSelf.control:SetOn(get(MONITOR .. "pinSelf") == true, true)
	f.follow.control:SetOn(get(MONITOR .. "followTargetOfTarget") == true, true)
	f.demo:SetLabel(L[ns.Demo.IsActive() and "SET_DEMO_STOP" or "SET_DEMO_START"])
end

local MOBS = "account.settings.mobs."

-- The *Dungeon Focus* card (SPEC-07 §2.6), only with the `multitarget` switch on.
local function buildFocus(view, f, page)
	local Limits = ns.Config.MOBS.max
	local card = View.StackCard(page.frame)
	View.CardText(card, "H2", "text-1", L["SET_FOCUS"], 0)
	f.mobsEnabled = switch(view, card, MOBS .. "enabled", L["SET_FOCUS_ENABLED"])
	View.CardText(card, "Small", "text-3", L["SET_FOCUS_NOTE"], 2)
	f.mobsMax = sliderBox(card, { min = Limits.min, max = Limits.max, step = 1, format = tostring,
		commit = function(v) write(view, card, MOBS .. "max", floor(v + 0.5)) end })
	card:Add(controlRow(card, L["SET_FOCUS_MAX"], f.mobsMax), 12, { stretch = true })
	View.CardText(card, "Small", "text-3", L["SET_FOCUS_MAX_NOTE"], 2)
	f.mobsNameplates = switch(view, card, MOBS .. "nameplates", L["SET_FOCUS_NAMEPLATES"])
	View.CardText(card, "Small", "text-3", L["SET_FOCUS_NAMEPLATES_NOTE"], 2)
	statusLine(card)
	return card
end

local function refreshFocus(f)
	local defaults = ns.Config.MOBS_DEFAULTS
	local function value(key)
		local v = get(MOBS .. key)
		if v == nil then v = defaults[key] end
		return v
	end
	f.mobsEnabled.control:SetOn(value("enabled") == true, true)
	f.mobsMax:Update(value("max"))
	f.mobsNameplates.control:SetOn(value("nameplates") == true, true)
end

local ALERTS = "account.settings.alerts."

-- The *Alerts* card (SPEC-04 §4.2): the channels stay on screen but inactive while the alerts are off; the Coach's
-- switch is there with the `coach` switch, *Alerts about other mobs* with the `multitarget` switch. The thresholds are the monitor's, in one place: the card says them and links
-- to that card. The note about the game's own threat warning shows only while the client says it is on (ALR-03).
local function buildAlerts(view, f, page)
	local Limits = ns.Config.ALERTS.cooldown
	local card = View.StackCard(page.frame)
	View.CardText(card, "H2", "text-1", L["SET_ALERTS"], 0)
	f.alertsEnabled = switch(view, card, ALERTS .. "enabled", L["SET_ALERTS_ENABLED"])
	f.alertsWindow = switch(view, card, ALERTS .. "window", L["SET_ALERTS_WINDOW"])
	f.alertsVisual = switch(view, card, ALERTS .. "visual", L["SET_ALERTS_VISUAL"])
	f.alertsSound = switch(view, card, ALERTS .. "sound", L["SET_ALERTS_SOUND"])
	View.CardText(card, "Small", "text-3", L["SET_ALERTS_SOUND_NOTE"], 2)
	f.cooldown = sliderBox(card, { min = Limits.min, max = Limits.max, step = 1,
		format = function(v) return L["SET_SECONDS"]:format(v) end,
		commit = function(v) write(view, card, ALERTS .. "cooldown", floor(v + 0.5)) end })
	card:Add(controlRow(card, L["SET_ALERTS_COOLDOWN"], f.cooldown), 12, { stretch = true })
	View.CardText(card, "Small", "text-3", L["SET_ALERTS_COOLDOWN_NOTE"], 2)

	View.CardText(card, "BodyMedium", "text-1", L["SET_ALERTS_OTHERS"], 12)
	local choices = {}
	for i, id in ipairs(ns.Config.ALERT_OTHERS) do choices[i] = { id = id, text = L["SET_OTHERS_" .. id:upper()] } end
	f.others = Widgets.Segmented(card, choices, function(id) write(view, card, ALERTS .. "others", id) end)
	card:Add(f.others, 8)
	f.alertsPet = switch(view, card, ALERTS .. "pet", L["SET_ALERTS_PET"])
	if focusOn() then
		-- the setting says the opposite: "only the target" off is "about other mobs" on (SPEC-07 §2.6)
		f.alertsMobs = switch(view, card, ALERTS .. "onlyTarget", L["SET_ALERTS_MOBS"], true)
		View.CardText(card, "Small", "text-3", L["SET_ALERTS_MOBS_NOTE"], 2)
	end

	f.thresholds = View.CardText(card, "Small", "text-2", "", 12)
	if f.monitorCard then
		f.toMonitor = Widgets.Button(card, { text = L["SET_ALERTS_TO_MONITOR"], style = "secondary", width = 240,
			onClick = function() page:ScrollTo(f.monitorCard) end })
		card:Add(f.toMonitor, 8)
	end
	f.native = View.CardText(card, "Small", "warn", L["SET_ALERTS_NATIVE"], 12)
	f.native:Hide()
	if coachOn() then f.coach = switch(view, card, "account.settings.coach.enabled", L["SET_COACH"]) end
	statusLine(card)
	return card
end

local function refreshAlerts(f)
	local enabled = get(ALERTS .. "enabled") ~= false
	f.alertsEnabled.control:SetOn(enabled, true)
	for _, key in ipairs({ "window", "visual", "sound" }) do
		local row = f["alerts" .. key:sub(1, 1):upper() .. key:sub(2)]
		row.control:SetOn(get(ALERTS .. key) == true, true)
		row.control:SetEnabled(enabled)
	end
	f.cooldown:Update(get(ALERTS .. "cooldown") or ns.Config.ALERTS_DEFAULTS.cooldown)
	f.others:Select(get(ALERTS .. "others") or ns.Config.ALERTS_DEFAULTS.others)
	f.alertsPet.control:SetOn(get(ALERTS .. "pet") == true, true)
	if f.alertsMobs then
		f.alertsMobs.control:SetOn(get(ALERTS .. "onlyTarget") == false, true)
		f.alertsMobs.control:SetEnabled(enabled)
	end
	local defaults = ns.Config.MONITOR_DEFAULTS
	f.thresholds:SetText(L["SET_ALERTS_THRESHOLDS"]:format(get(MONITOR .. "warning") or defaults.warning,
		get(MONITOR .. "danger") or defaults.danger))
	f.native:SetShown(Compat.ThreatWarningEnabled() == true)
	if f.coach then f.coach.control:SetOn(get("account.settings.coach.enabled") ~= false, true) end
end

local RECORDING = "account.settings.recording."
local KB_STEP = 512      -- the size limit moves in steps of 0.5 MB

local function paintUsage(f)
	local Storage = ns.Storage
	f.usage:SetText(L["SET_RECORDING_USAGE"]:format(ns.Reports.UsageText(Storage.Usage())))
end

-- The *Recording* card (SPEC-05 §3.6): when and how often a fight is recorded, the limits (pruning applies at once),
-- the end-of-fight notice, the use of the store and *Delete all recordings*, which asks twice.
local function buildRecording(view, f, page)
	local Limits, defaults = ns.Config.RECORDING, ns.Config.RECORDING_DEFAULTS
	local card = View.StackCard(page.frame)
	View.CardText(card, "H2", "text-1", L["SET_RECORDING"], 0)
	f.recording = switch(view, card, RECORDING .. "enabled", L["SET_RECORDING_ENABLED"])

	View.CardText(card, "BodyMedium", "text-1", L["SET_RECORDING_WHEN"], 12)
	local choices = {}
	for i, id in ipairs(ns.Config.RECORD_WHEN) do choices[i] = { id = id, text = L["SET_WHEN_" .. id:upper()] } end
	f.when = Widgets.Segmented(card, choices, function(id) write(view, card, RECORDING .. "when", id) end)
	card:Add(f.when, 8)

	-- `field`: the name of the control in `f` (the Monitor card has a `rate` of its own)
	local function slider(key, label, min_, max_, step, format, note, field)
		field = field or key
		f[field] = sliderBox(card, { min = min_, max = max_, step = step, format = format, valueWidth = 60,
			commit = function(v) write(view, card, RECORDING .. key, floor(v / step + 0.5) * step) end })
		card:Add(controlRow(card, label, f[field]), 12, { stretch = true })
		if note then View.CardText(card, "Small", "text-3", note, 2) end
	end
	slider("rate", L["SET_RECORDING_RATE"], Limits.rate.min, Limits.rate.max, 1,
		function(v) return L["SET_HERTZ"]:format(v) end, L["SET_RECORDING_RATE_NOTE"], "recordingRate")
	slider("maxSessions", L["SET_RECORDING_SESSIONS"], Limits.maxSessions.min, Limits.maxSessions.max, 1, tostring)
	slider("maxKB", L["SET_RECORDING_SIZE"], Limits.maxKB.min, Limits.maxKB.max, KB_STEP,
		function(v) return ns.Reports.SizeText(floor(v / KB_STEP + 0.5) * KB_STEP) end, L["SET_RECORDING_LIMITS_NOTE"])

	f.notice = switch(view, card, RECORDING .. "notice", L["SET_RECORDING_NOTICE"])
	View.CardText(card, "Small", "text-3", L["SET_RECORDING_NOTICE_NOTE"], 2)
	f.usage = View.CardText(card, "Small", "text-2", "", 12)

	local armed = 0
	local function disarm()
		armed = armed + 1
		f.deleteAll.armed = false
		f.deleteAll:SetLabel(L["SET_RECORDING_DELETE"])
	end
	f.deleteAll = Widgets.Button(card, { text = L["SET_RECORDING_DELETE"], style = "secondary", width = 300,
		onClick = function()
			if not f.deleteAll.armed then
				disarm()
				f.deleteAll.armed = true
				f.deleteAll:SetLabel(L["SET_RECORDING_DELETE_CONFIRM"])
				local mine = armed
				Compat.After(View.CONFIRM_SECONDS, function() if mine == armed then disarm() end end)
				return
			end
			disarm()
			local ok, why = ns.Storage.DeleteAll()
			if ok then say(card, L["SET_RECORDING_DELETED"], nil)
			elseif why == "read-only" then say(card, L["CMD_READ_ONLY"], "warn")
			else say(card, L["SET_NOT_SAVED"]:format(tostring(why)), "warn") end
			view:Refresh()
		end })
	card:Add(f.deleteAll, 12)
	f.disarmDelete = disarm
	View.CardText(card, "Small", "text-3", L["SET_RECORDING_NAMES"], 12)
	statusLine(card)
	f.recordingDefaults = defaults

	-- the use of the store follows the recordings (registered once, only with the card there is to repaint)
	if ns.Bus and not View.listensSessions then
		View.listensSessions = true
		ns.Bus.On("SESSIONS_CHANGED", View.RefreshAll)
		ns.Bus.On("SESSION_STARTED", View.RefreshAll)
		ns.Bus.On("SESSION_ENDED", View.RefreshAll)
	end
	return card
end

local function refreshRecording(f)
	local function value(key)
		local v = get(RECORDING .. key)
		if v == nil then v = f.recordingDefaults[key] end
		return v
	end
	f.recording.control:SetOn(value("enabled") == true, true)
	f.when:Select(value("when"))
	f.recordingRate:Update(value("rate"))
	for _, key in ipairs({ "maxSessions", "maxKB" }) do f[key]:Update(value(key)) end
	f.notice.control:SetOn(value("notice") == true, true)
	paintUsage(f)
	f.deleteAll:SetEnabled(not config():IsReadOnly("account"))
end

-- "Reset settings" asks twice: the first click arms the button, a second one within CONFIRM_SECONDS resets.
local function buildReset(view, f, page)
	local card = View.StackCard(page.frame)
	View.CardText(card, "H2", "text-1", L["SET_RESET"], 0)
	local text = monitorOn() and "SET_RESET_TEXT_MONITOR" or "SET_RESET_TEXT"
	if alertsOn() then text = "SET_RESET_TEXT_ALERTS" end
	if recordingOn() then text = "SET_RESET_TEXT_RECORDING" end
	View.CardText(card, "Body", "text-2", L[text], 8)
	local armed = 0
	local function disarm()
		armed = armed + 1
		f.reset.armed = false
		f.reset:SetLabel(L["SET_RESET_BUTTON"])
	end
	f.reset = Widgets.Button(card, { text = L["SET_RESET_BUTTON"], style = "secondary", width = 240, onClick = function()
		if not f.reset.armed then
			disarm()
			f.reset.armed = true
			f.reset:SetLabel(L["SET_RESET_CONFIRM"])
			local mine = armed
			Compat.After(View.CONFIRM_SECONDS, function() if mine == armed then disarm() end end)
			return
		end
		disarm()
		local ok = config():ResetSettings()
		say(card, L[ok and "SET_RESET_DONE" or "CMD_READ_ONLY"], not ok and "warn" or nil)
		if ok and ns.Bus then ns.Bus.Emit("SETTINGS_CHANGED", "account.settings") end
		view:Refresh()
	end })
	card:Add(f.reset, 12)
	statusLine(card)
	f.disarmReset = disarm
	return card
end

-- The warning of saved data that is never rewritten (SPEC-02 §3.4).
local function buildReadOnly(f, page)
	local card = View.StackCard(page.frame)
	f.readOnly = View.CardText(card, "BodyMedium", "warn", "", 0)
	return card
end

local function refreshSettings(view, f)
	local theme = get("account.settings.theme")
	f.theme.control:Select(theme or Theme.DEFAULT)
	f.effects.control:SetOn(get("account.settings.effects") ~= false, true)
	f.animations.control:SetOn(get("account.settings.animations") ~= false, true)
	f.font.control:Select(get("account.settings.font") or "addon")
	local language = get("account.settings.language") or "auto"
	f.language:Select(language)
	-- Reload now helps only while the chosen language is not the one on screen
	f.reload:SetEnabled(ns.Locale.Resolve(language) ~= ns.Locale.Active())
	f.lock.control:SetOn(get("char.ui.locked") == true, true)
	f.scaleBox:Update((get("char.ui.scale") or 1) * 100)
	f.minimap.control:SetOn(get("account.settings.minimap.hide") ~= true, true)
	if f.warning then refreshMonitor(f) end
	if f.mobsMax then refreshFocus(f) end
	if f.cooldown then refreshAlerts(f) end
	if f.when then refreshRecording(f) end

	local cfg = config()
	local why = cfg and (cfg.readOnly.account or cfg.readOnly.char)
	f.readOnly:SetText(why and L[why == "newer" and "SET_READ_ONLY_NEWER" or "SET_READ_ONLY_MIGRATION"] or "")
	f.readOnlyCard:SetShown(why ~= nil)
	for _, card in ipairs(f.page.cards) do
		if card.status then card.status:SetShown((card.status:GetText() or "") ~= "") end
	end
end

local function buildSettingsPage(holder, view)
	local page = View.Column(holder)
	local f = { page = page }
	view.settings = f
	f.readOnlyCard = buildReadOnly(f, page)
	page.cards = { f.readOnlyCard, buildAppearance(view, f, page), buildLanguage(view, f, page),
		buildWindowCard(view, f, page) }
	if monitorOn() then
		f.monitorCard = buildMonitor(view, f, page)
		page.cards[#page.cards + 1] = f.monitorCard
	end
	if focusOn() then
		f.focusCard = buildFocus(view, f, page)
		page.cards[#page.cards + 1] = f.focusCard
	end
	if alertsOn() then
		f.alertsCard = buildAlerts(view, f, page)
		page.cards[#page.cards + 1] = f.alertsCard
	end
	if recordingOn() then
		f.recordingCard = buildRecording(view, f, page)
		page.cards[#page.cards + 1] = f.recordingCard
	end
	page.cards[#page.cards + 1] = buildReset(view, f, page)
	f.cards = page.cards
	function page:Refresh() refreshSettings(view, f) end
	return page
end

---------------------------------------------------------------------------------------------------------------------
-- The view: the page selector and the pages
---------------------------------------------------------------------------------------------------------------------
function View.AddPage(id, def)
	if type(id) ~= "string" or type(def) ~= "table" or type(def.build) ~= "function" then return false end
	for _, p in ipairs(View.pages) do if p.id == id then return false end end
	View.pages[#View.pages + 1] = { id = id, labelKey = def.labelKey, order = def.order or 100,
		build = def.build }
	table.sort(View.pages, function(a, b) return a.order < b.order end)
	return true
end

View.AddPage("settings", { labelKey = "PAGE_SETTINGS", order = 10, build = buildSettingsPage })

local function pageDef(id)
	for _, p in ipairs(View.pages) do if p.id == id then return p end end
end

-- Leaving the page cancels a first click on either of the buttons that ask twice.
local function disarmAll(f)
	f.disarmReset()
	if f.disarmDelete then f.disarmDelete() end
end

function View.Build(parent, opts)
	opts = opts or {}
	local view = CreateFrame("Frame", nil, parent)
	view:SetAllPoints(parent)
	view.holders, view.built = {}, {}

	local items = {}
	for i, p in ipairs(View.pages) do items[i] = { id = p.id, text = L[p.labelKey] } end

	function view:Width()
		local w = self.width or self:GetWidth()
		if not w or w <= 0 then return View.PAGE_WIDTH end
		return min(View.PAGE_WIDTH, w)
	end

	-- Places the cards of the page on screen at the width the view has now.
	function view:Layout()
		local page = self.pageId and self.built[self.pageId]
		if page then page:Layout(self:Width()) end
	end

	function view:Refresh()
		if self.refreshing then return end
		self.refreshing = true
		local page = self.pageId and self.built[self.pageId]
		if page and page.Refresh then page:Refresh() end
		self.refreshing = false
		self:Layout()
	end

	-- Shows page `id`, built the first time. False for a page that does not exist.
	function view:ShowPage(id)
		local def = pageDef(id)
		if not def then return false end
		if self.pageId and self.pageId ~= id and self.settings then disarmAll(self.settings) end
		self.pageId = id
		for other, holder in pairs(self.holders) do holder:SetShown(other == id) end
		if not self.holders[id] then
			local holder = CreateFrame("Frame", nil, self)
			holder:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -View.PAGER_HEIGHT)
			holder:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", 0, 0)
			self.holders[id] = holder
			self.built[id] = def.build(holder, self)
		end
		self.holders[id]:Show()
		if self.pager:Active() ~= id then
			self.selecting = true
			self.pager:Select(id)
			self.selecting = false
		end
		self:Refresh()
		return true
	end

	view.pager = Widgets.Segmented(view, items, function(id)
		if view.selecting then return end
		view:ShowPage(id)
		if opts.onPage then opts.onPage(id) end
	end)
	view.pager:SetPoint("TOPLEFT", view, "TOPLEFT", 0, 0)

	view:SetScript("OnSizeChanged", function(self, width) self.width = width; self:Layout() end)
	view:SetScript("OnShow", function(self) self:Refresh() end)
	view:SetScript("OnHide", function(self) if self.settings then disarmAll(self.settings) end end)
	View.instances[#View.instances + 1] = view
	view:ShowPage("settings")
	return view
end

-- Repaints the views on screen (a change made in one shows in the other); a hidden one repaints when it is shown.
function View.RefreshAll()
	for _, view in ipairs(View.instances) do
		if view:IsVisible() then view:Refresh() end
	end
end

---------------------------------------------------------------------------------------------------------------------
-- The panel of the game's Settings window (Options > AddOns)
---------------------------------------------------------------------------------------------------------------------
-- The canvas the game sizes itself: the same view on the theme's background, built the first time it is shown.
local function makePanel()
	local panel = CreateFrame("Frame", nil, Compat.UIParent())
	panel:Hide()
	panel.fill = panel:CreateTexture(nil, "BACKGROUND")
	panel.fill:SetAllPoints(panel)
	Theme.Fill(panel.fill, "bg")
	panel.title = Widgets.Text(panel, "DisplaySmall", "accent-text", "LEFT")
	panel.title:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -14)
	panel.title:SetText(L["ADDON_TITLE"])
	panel.body = CreateFrame("Frame", nil, panel)
	panel.body:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -44)
	panel.body:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -16, 8)
	panel:SetScript("OnShow", function(self)
		if not self.view then self.view = View.Build(self.body) end
	end)
	return panel
end

-- Registers the panel (once). Returns true, or false and why: "unavailable" or "failed".
function View.RegisterPanel()
	if View.panel then return true end
	if not Compat.HasSettingsPanel() then
		View.panelStatus = "unavailable"
		return false, "unavailable"
	end
	local panel = makePanel()
	local category, why = Compat.RegisterSettingsPanel(panel, L["ADDON_TITLE"])
	if not category then
		View.panelStatus = why
		return false, why
	end
	View.panel, View.category, View.panelStatus = panel, category, "registered"
	return true
end

-- The line of /atw debug (English, fixed words).
function View.DebugLines()
	return { "game settings panel: " .. (View.panelStatus or "not tried") }
end

if ns.Bus then
	ns.Bus.On("CONFIG_LOADED", View.RefreshAll)
	ns.Bus.On("CONFIG_CHANGED", View.RefreshAll)
	ns.Bus.On("THEME_CHANGED", View.RefreshAll)
	ns.Bus.On("DEMO_CHANGED", View.RefreshAll)
	ns.Bus.On("ENTERING_WORLD", View.RefreshAll)
end
if ns.OnEnable then ns.OnEnable(function() View.RegisterPanel() end) end
if ns.addon then
	ns.addon.Settings = View
	ns.addon:AddDebugSection("Settings", function() return View.DebugLines() end)
end
