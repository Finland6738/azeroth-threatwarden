-- Window: the one window of the addon (SPEC-03 §4, ui-style 3.1). One frame, AzerothThreatwardenWindow, with two
-- layouts that remember their own size: compact (the Monitor tab, over the game) and wide (Settings, Reports). Title bar
-- with the logo, the module state, the lock and the close button; tabs; moved by the title bar, resized from the grip
-- in the corner, scaled, locked; position, size, scale, lock, tab and visibility per character in `char.ui`; Esc closes
-- it. Lua 5.1.
-- Adapted from Azeroth Accord (UI/Window.lua and the tab handling of UI/Shell.lua), same owner, GPL-3.0 (ADR 0012).
-- Changes: two layouts with the top-left corner kept still between them; the position is checked against the screen
-- with plain arithmetic (Window.Rect, Window.Clamp); the lock and the module state are Threatwarden's own.
--
-- Nothing here is protected: ordinary frames, no secure template, no Blizzard frame touched, so showing, hiding, moving
-- and resizing work in combat too. No game API is named (ARC-02): CreateFrame and Core/Compat.lua.
--
-- When it shows itself (SPEC-03 §5.1, `account.settings.monitor.show`, only while the `monitor` switch is on): "auto"
-- opens it at a fight's start and on joining a group, and closes it AUTO_CLOSE seconds after a fight outside a group;
-- "always" opens it at login; "manual" leaves it as the player left it. Showing or hiding by itself never writes
-- `char.ui.shown` or the tab, which stay the player's choice.
--
-- Bus: emits WINDOW_SHOWN(shown) and TAB_CHANGED(tabId); listens CONFIG_LOADED, CONFIG_CHANGED, DISPLAY_CHANGED,
-- COMBAT_STARTED, COMBAT_ENDED, GROUP_CHANGED, CAPABILITY_CHANGED, THREAT_MODE_CHANGED, TARGET_CHANGED and DEMO_CHANGED
-- (the pill), ALERT_RAISED (the effect on the border).
local ADDON_NAME, ns = ...
ns = ns or {}
ns.modules = ns.modules or {}

local Window = {}
ns.Window, ns.modules.Window = Window, Window

local L, Widgets, Theme, Assets, Compat = ns.L, ns.Widgets, ns.Theme, ns.Assets, ns.Compat
local type, ipairs, max, min, abs = type, ipairs, math.max, math.min, math.abs

Window.NAME = "AzerothThreatwardenWindow"
Window.DEFAULT_SIZE = { compact = { w = 300, h = 220 }, wide = { w = 560, h = 520 } }
Window.RADIUS = { compact = 8, wide = 12 }
Window.GRIP = 14
Window.PAGE_MARGIN = 20   -- around the Settings tab
Window.AUTO_CLOSE = 10    -- seconds after a fight outside a group before the window closes itself ("auto")
Window.EFFECT_HOLD = 1.5  -- seconds the border keeps the colour of an alert (SPEC-04 §3.2)
local SHOW_PATH = "account.settings.monitor.show"

-- The tabs, in order. `feature`: shown only while that switch of Core/Features.lua is on (ADR 0014).
Window.TABS = {
	{ id = "monitor", labelKey = "TAB_MONITOR", layout = "compact" },
	{ id = "reports", labelKey = "TAB_REPORTS", layout = "wide", feature = "reports" },   -- M4
	{ id = "settings", labelKey = "TAB_SETTINGS", layout = "wide" },
}
local tabById = {}
for _, t in ipairs(Window.TABS) do tabById[t.id] = t end

-- The module state of the title bar (SPEC-03 §4.3): always an icon and a word, never a colour alone.
Window.STATES = {
	off         = { labelKey = "MODULE_OFF",         tipKey = "MODULE_TIP_OFF",         icon = "minus", token = "text-3" },
	idle        = { labelKey = "MODULE_IDLE",        tipKey = "MODULE_TIP_IDLE",        icon = "clock", token = "text-3" },
	live        = { labelKey = "MODULE_LIVE",        tipKey = "MODULE_TIP_LIVE",        icon = "check", token = "ok" },
	state       = { labelKey = "MODULE_STATE",       tipKey = "MODULE_TIP_STATE",       icon = "warn",  token = "warn" },
	unavailable = { labelKey = "MODULE_UNAVAILABLE", tipKey = "MODULE_TIP_UNAVAILABLE", icon = "cross", token = "err" },
	unsupported = { labelKey = "MODULE_UNSUPPORTED", tipKey = "MODULE_TIP_UNSUPPORTED", icon = "warn",  token = "err" },
	demo        = { labelKey = "MODULE_DEMO",        tipKey = "MODULE_TIP_DEMO",        icon = "predict", token = "warn" },
}

local function config() return ns.Config end
local function get(path) return config() and config():Get(path) end
local function set(path, value)
	if not config() then return false, "not loaded" end
	return config():Set(path, value)
end
local function emit(event, ...)
	if ns.Bus then ns.Bus.Emit(event, ...) end
end
local function featureOn(name) return ns.Features ~= nil and ns.Features.On(name) end
local function demoOn() return ns.Demo ~= nil and ns.Demo.IsActive() end
local function inCombat() return ns.addon ~= nil and ns.addon.inCombat == true end
local function inGroup() return Compat.Group.InGroup() == true end

---------------------------------------------------------------------------------------------------------------------
-- Module state
---------------------------------------------------------------------------------------------------------------------
local function hidden(capability)
	local state = Compat.Capability(capability)
	return state == Compat.MISSING or state == Compat.RESTRICTED
end

-- "off", "demo", "idle", "live", "state", "unavailable" or "unsupported".
function Window.ModuleState()
	if ns.addon and ns.addon.isForever == false then return "unsupported" end
	if not featureOn("monitor") then return "off" end
	if demoOn() then return "demo" end
	if not (ns.addon and ns.addon.inCombat) then return "idle" end
	local Tracker, Scanner = ns.TargetTracker, ns.ThreatScanner
	if Tracker and Tracker.enabled and not Tracker.mobKey then return "idle" end
	-- the mode of the last scan says it, once a scan has answered something about somebody
	if Scanner and Scanner.active then
		local mode, reason = Scanner.mode, Scanner.modeReason
		if mode == "values" then return "live" end
		if mode == "state" then return "state" end
		if reason and reason ~= "nil" then return "unavailable" end
	end
	if hidden("threatValues") then
		if hidden("threatState") then return "unavailable" end
		return "state"
	end
	if Compat.Capability("threatValues") == Compat.AVAILABLE then return "live" end
	return "idle"
end

-- The lines of the pill's tooltip: the word and the reason.
function Window.ModuleTip()
	local def = Window.STATES[Window.ModuleState()]
	return { L[def.labelKey], L[def.tipKey] }
end

---------------------------------------------------------------------------------------------------------------------
-- Geometry: positions are { point, relativePoint, x, y } in the units of the window (before its scale)
---------------------------------------------------------------------------------------------------------------------
local function fractionX(point)
	if point:find("LEFT", 1, true) then return 0 end
	if point:find("RIGHT", 1, true) then return 1 end
	return 0.5
end
local function fractionY(point)   -- from the bottom of the screen
	if point:find("TOP", 1, true) then return 1 end
	if point:find("BOTTOM", 1, true) then return 0 end
	return 0.5
end

-- left, top (from the bottom left of the screen) of a w x h window at `pos` (nil: the centre) on a sw x sh screen.
function Window.Rect(pos, w, h, sw, sh)
	local point, rel, x, y = "CENTER", "CENTER", 0, 0
	if pos then point, rel, x, y = pos.point, pos.relativePoint, pos.x, pos.y end
	local left = fractionX(rel) * sw + x - fractionX(point) * w
	local top = fractionY(rel) * sh + y + (1 - fractionY(point)) * h
	return left, top
end

-- left, top brought inside the screen; a window larger than the screen keeps its top-left corner visible.
function Window.Clamp(left, top, w, h, sw, sh)
	left = max(0, min(left, sw - w))
	top = min(sh, max(top, h))
	return left, top
end

-- The size of the screen in the units of the window, nil when the client cannot say.
local function screenSize(f)
	local parent = Compat.UIParent()
	if not parent then return nil end
	local w, h, scale = parent:GetWidth(), parent:GetHeight(), f:GetScale()
	if not w or not h or w <= 0 or h <= 0 then return nil end
	if not scale or scale <= 0 then scale = 1 end
	return w / scale, h / scale
end

local function currentPos(f)
	local point, _, rel, x, y = f:GetPoint(1)
	if type(point) ~= "string" or type(x) ~= "number" or type(y) ~= "number" then return nil end
	return { point = point, relativePoint = type(rel) == "string" and rel or point, x = x, y = y }
end

local function anchor(f, pos)
	local parent = Compat.UIParent()
	f:ClearAllPoints()
	if pos then f:SetPoint(pos.point, parent, pos.relativePoint, pos.x, pos.y)
	else f:SetPoint("CENTER", parent, "CENTER", 0, 0) end
end

-- Writes without answering our own CONFIG_CHANGED.
local function save(path, value)
	Window.saving = true
	local ok, why = set(path, value)
	Window.saving = false
	return ok, why
end

-- Anchors the window by its top-left corner when it is not entirely on the screen. Returns true when it moved.
local function keepOnScreen(f)
	local sw, sh = screenSize(f)
	if not sw then return false end
	local w, h = f:GetWidth(), f:GetHeight()
	local left, top = Window.Rect(currentPos(f), w, h, sw, sh)
	local l, t = Window.Clamp(left, top, w, h, sw, sh)
	if abs(l - left) < 0.5 and abs(t - top) < 0.5 then return false end
	anchor(f, { point = "TOPLEFT", relativePoint = "BOTTOMLEFT", x = l, y = t })
	return true
end

-- The size of a layout: the saved one, else the default (Config keeps a saved one within the limits).
function Window.Size(layout)
	local saved = get("char.ui.size." .. layout)
	local size = saved or Window.DEFAULT_SIZE[layout]
	return size.w, size.h
end

local function applySize(f)
	local layout = f.layout
	local lim = ns.Config.SIZES[layout]
	if f.SetResizeBounds then f:SetResizeBounds(lim.minW, lim.minH, lim.maxW, lim.maxH) end
	f:SetSize(Window.Size(layout))
end

---------------------------------------------------------------------------------------------------------------------
-- Building
---------------------------------------------------------------------------------------------------------------------
local function icon(parent, name, size, token)
	local tex = parent:CreateTexture(nil, "OVERLAY")
	tex:SetTexture(Assets.textures.icons.path)
	tex:SetTexCoord(Assets.IconCoords(name))
	tex:SetSize(size, size)
	Theme.Tint(tex, token)
	return tex
end

-- The pill of the module state: icon and word. `filled` (compact bar) adds a soft background.
local function stateChip(parent, filled)
	local chip = CreateFrame("Frame", nil, parent)
	chip:SetHeight(filled and 18 or 14)
	if filled then
		chip.fill = Theme.Slice(chip, "rr_fill_8", "text-3", "BACKGROUND", 0.16)
		chip.fill:SetAllPoints(chip)
	end
	chip.pad = filled and 5 or 0
	chip.icon = icon(chip, "minus", 10, "text-3")
	chip.icon:SetPoint("LEFT", chip, "LEFT", chip.pad, 0)
	chip.label = Theme.NewText(chip, filled and "Th" or "MonoSmall", "text-3")
	chip.label:SetPoint("LEFT", chip.icon, "RIGHT", 4, 0)
	function chip:SetModuleState(id)
		local def = Window.STATES[id]
		self.state = id
		-- during the effect of an alert without a message in the window, the icon is the alert's state (SPEC-04 §3.2)
		local alert = self.alert and Theme.State(self.alert)
		self.icon:SetTexCoord(Assets.IconCoords(alert and alert.icon or def.icon))
		Theme.Tint(self.icon, alert and alert.token or def.token)
		Theme.Text(self.label, def.token)
		if self.fill then Theme.Tint(self.fill, def.token, 0.16) end
		self.label:SetText(L[def.labelKey])
		self:SetWidth(self.pad * 2 + 14 + self.label:GetStringWidth())
	end
	function chip:SetAlert(id)
		self.alert = id
		if self.state then self:SetModuleState(self.state) end
	end
	chip:EnableMouse(true)
	Widgets.Tooltip.Attach(chip, function() return Window.ModuleTip() end, "BOTTOM")
	return chip
end

local function lockButton(bar)
	local size = bar.compact and 18 or 28
	local b = CreateFrame("Button", nil, bar)
	b:SetSize(size, size)
	b:SetPoint("RIGHT", bar.close, "LEFT", bar.compact and -4 or -6, 0)
	b.bg = Theme.Slice(b, "rr_fill_8", "surface-3", "BACKGROUND", 0)
	b.bg:SetAllPoints(b)
	b.icon = icon(b, "unlock", bar.compact and 12 or 16, "text-2")
	b.icon:SetPoint("CENTER")
	b:SetScript("OnEnter", function(self) Theme.Tint(self.bg, "surface-3", 1) end)
	b:SetScript("OnLeave", function(self) Theme.Tint(self.bg, "surface-3", 0) end)
	b:SetScript("OnClick", function() Window:SetLocked(not Window:IsLocked()) end)
	Widgets.Tooltip.Attach(b, function() return L[Window:IsLocked() and "WINDOW_UNLOCK" or "WINDOW_LOCK"] end, "BOTTOM")
	return b
end

local function stopMoving(f)
	if not f.moving then return end
	f.moving = false
	f:StopMovingOrSizing()
	local pos = currentPos(f)
	if pos then save("char.ui.pos", pos) end
end

local function stopSizing(f)
	if not f.sizing then return end
	f.sizing = false
	f:StopMovingOrSizing()
	local pos = currentPos(f)
	save("char.ui.size." .. f.layout, { w = f:GetWidth(), h = f:GetHeight() })
	-- Config brings the size within the limits; a read-only character keeps the size just given
	local saved = get("char.ui.size." .. f.layout)
	if saved and not (config() and config():IsReadOnly("char")) then f:SetSize(saved.w, saved.h) end
	if pos then save("char.ui.pos", pos) end
	Window:LayoutTitle()
end

local function titleBar(f, compact)
	local bar = Widgets.TitleBar(f, { compact = compact, title = L[compact and "WINDOW_TITLE_COMPACT" or "WINDOW_TITLE"],
		closeLabel = L["WINDOW_CLOSE"], onClose = function() Window:Close() end })
	bar:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
	bar:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
	bar:EnableMouse(true)
	bar:RegisterForDrag("LeftButton")
	bar:SetScript("OnDragStart", function()
		if Window:IsLocked() then return end
		f.moving = true
		f:StartMoving()
	end)
	bar:SetScript("OnDragStop", function() stopMoving(f) end)
	bar.lock = lockButton(bar)
	bar.chip = stateChip(bar, compact)
	if compact then
		bar.chip:SetPoint("RIGHT", bar.lock, "LEFT", -6, 0)
	else
		bar.subtitle:SetText("")
		bar.chip:SetPoint("TOPLEFT", bar.title, "BOTTOMLEFT", 0, -3)
	end
	return bar
end

-- A centred line of text and, above it, the dimmed logo (the Monitor tab while the monitor is off).
local function placeholder(page, key)
	page.logo = page:CreateTexture(nil, "ARTWORK")
	page.logo:SetTexture(Assets.logos.logo_64.path)
	page.logo:SetSize(32, 32)
	page.logo:SetPoint("CENTER", page, "CENTER", 0, 16)
	page.logo:SetAlpha(0.35)
	if page.logo.SetMaskTexture then page.logo:SetMaskTexture(Assets.textures.circle.path) end
	page.text = Theme.NewText(page, "BodyMedium", "text-2")
	page.text:SetJustifyH("CENTER")
	if page.text.SetWordWrap then page.text:SetWordWrap(true) end
	page.text:SetPoint("TOP", page.logo, "BOTTOM", 0, -8)
	page.text:SetPoint("LEFT", page, "LEFT", 12, 0)
	page.text:SetPoint("RIGHT", page, "RIGHT", -12, 0)
	page.text:SetText(L[key])
end

local function buildPages(f)
	f.pages = {}
	for _, t in ipairs(Window.TABS) do
		local page = CreateFrame("Frame", nil, f)
		local top = t.layout == "compact" and (Widgets.TITLE_HEIGHT_COMPACT + Widgets.TAB_HEIGHT_COMPACT)
			or (Widgets.TITLE_HEIGHT + Widgets.TAB_HEIGHT)
		page:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -top)
		page:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
		page:Hide()
		f.pages[t.id] = page
	end
	placeholder(f.pages.monitor, "MONITOR_COMING")   -- shown while the `monitor` switch is off (paintMonitor)
end

local function buildGrip(f)
	local grip = CreateFrame("Button", nil, f)
	grip:SetSize(Window.GRIP, Window.GRIP)
	grip:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -3, 3)
	grip:SetFrameLevel((f:GetFrameLevel() or 1) + 30)   -- over the views in the body
	grip.icon = icon(grip, "dashed", Window.GRIP, "text-3")
	grip.icon:SetAllPoints(grip)
	grip:SetScript("OnEnter", function(self) Theme.Tint(self.icon, "accent-text") end)
	grip:SetScript("OnLeave", function(self) Theme.Tint(self.icon, "text-3") end)
	Widgets.Tooltip.Attach(grip, L["WINDOW_RESIZE"], "TOP")
	grip:SetScript("OnMouseDown", function()
		if Window:IsLocked() then return end
		f.sizing = true
		f:StartSizing("BOTTOMRIGHT")
	end)
	grip:SetScript("OnMouseUp", function() stopSizing(f) end)
	f.grip = grip
end

-- The ring over the window that takes the colour of an alert's state, one per layout (the radius differs).
local function buildEffect(f)
	local flash = CreateFrame("Frame", nil, f)
	flash:SetAllPoints(f)
	flash:SetFrameLevel((f:GetFrameLevel() or 1) + 40)
	flash:EnableMouse(false)
	flash.rings = {}
	for layout, radius in pairs(Window.RADIUS) do
		local ring = Theme.Slice(flash, "rr_ring_" .. radius, "state-warning", "OVERLAY")
		ring:SetAllPoints(flash)
		ring:Hide()
		flash.rings[layout] = ring
	end
	flash:Hide()
	f.flash = flash
end

-- The size of the Reports tab inside the window. Declared before build(), whose OnSizeChanged calls it.
local function layoutReports(f)
	local view = f.pages.reports.view
	if not view then return end
	view:Layout(f:GetWidth() - 2 * Window.PAGE_MARGIN,
		f:GetHeight() - Widgets.TITLE_HEIGHT - Widgets.TAB_HEIGHT - 10 - Window.PAGE_MARGIN)
end

local function build()
	local f = CreateFrame("Frame", Window.NAME, Compat.UIParent())
	f:Hide()
	f:SetFrameStrata("MEDIUM")
	f:SetToplevel(true)
	f:SetClampedToScreen(true)
	f:SetMovable(true)
	f:SetResizable(true)
	if f.SetDontSavePosition then f:SetDontSavePosition(true) end   -- the place is kept in char.ui, not by the client
	f:EnableMouse(true)   -- clicks on the window do not fall through to the world

	-- one background per layout (radius and shadow differ), behind everything else
	f.skins = {}
	for layout, radius in pairs(Window.RADIUS) do
		local skin = CreateFrame("Frame", nil, f)
		skin:SetAllPoints(f)
		skin:SetFrameLevel(f:GetFrameLevel() or 1)
		skin.parts = Theme.Panel(skin, { radius = radius, fill = layout == "wide" and "bg" or "surface-1",
			border = "border", shadow = true, shadowAlpha = layout == "wide" and 0.6 or 0.35, highlight = true })
		skin:Hide()
		f.skins[layout] = skin
	end

	f.titles = { compact = titleBar(f, true), wide = titleBar(f, false) }

	local items = {}
	for _, t in ipairs(Window.TABS) do items[#items + 1] = { id = t.id, text = L[t.labelKey] } end
	f.tabs = {}
	for layout, bar in pairs(f.titles) do
		local tabs = Widgets.Tabs(f, items, function(id) Window:SelectTab(id) end, { compact = layout == "compact" })
		tabs:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, 0)
		tabs:SetPoint("TOPRIGHT", bar, "BOTTOMRIGHT", 0, 0)
		f.tabs[layout] = tabs
	end

	buildPages(f)
	buildGrip(f)
	buildEffect(f)
	Widgets.CloseOnEscape(Window.NAME)

	f:SetScript("OnSizeChanged", function()
		Window:LayoutTitle()
		if f.layout == "wide" then layoutReports(f) end
		local view = f.pages.monitor.view
		if view and f.layout == "compact" and featureOn("monitor") then
			view:Layout(f:GetWidth(), f:GetHeight() - Widgets.TITLE_HEIGHT_COMPACT - Widgets.TAB_HEIGHT_COMPACT)
		end
	end)
	f:SetScript("OnShow", function() Window:Refresh() emit("WINDOW_SHOWN", true) end)
	f:SetScript("OnHide", function(self)
		stopMoving(self)
		stopSizing(self)
		Window:EndEffect()
		-- hidden with the whole interface (Alt+Z, a cinematic) the window is still "shown": nothing to remember
		if not self:IsShown() then
			Window:CancelAutoClose()
			if not Window.autoHiding then
				-- closed by the player: during a fight it stays closed until the next one (SPEC-03 §5.1)
				if inCombat() then Window.dismissed = true end
				save("char.ui.shown", false)
			end
			emit("WINDOW_SHOWN", false)
		end
	end)
	return f
end

---------------------------------------------------------------------------------------------------------------------
-- State of the frame
---------------------------------------------------------------------------------------------------------------------
-- Shows the parts of the layout of tab `id`.
local function showTab(f, id)
	local layout = tabById[id].layout
	f.tab, f.layout = id, layout
	for name, skin in pairs(f.skins) do skin:SetShown(name == layout) end
	for name, bar in pairs(f.titles) do bar:SetShown(name == layout) end
	for name, tabs in pairs(f.tabs) do tabs:SetShown(name == layout) end
	for pageId, page in pairs(f.pages) do page:SetShown(pageId == id) end
	for name, ring in pairs(f.flash.rings) do ring:SetShown(name == layout) end
	for _, tabs in pairs(f.tabs) do tabs:Select(id) end
end

local function tabAvailable(id)
	local t = tabById[id]
	return t ~= nil and (t.feature == nil or featureOn(t.feature))
end

local function applyTabSwitches(f)
	for _, t in ipairs(Window.TABS) do
		if t.feature then
			for _, tabs in pairs(f.tabs) do tabs:SetTabShown(t.id, featureOn(t.feature)) end
		end
	end
end

-- The Monitor tab (UI/ThreatList.lua) while the `monitor` switch is on; the M1 placeholder while it is off.
local function paintMonitor(f)
	local page = f.pages.monitor
	local on = featureOn("monitor") and ns.ThreatList ~= nil and not (ns.addon and ns.addon.isForever == false)
	page.logo:SetShown(not on)
	page.text:SetShown(not on)
	if on and not page.view then page.view = ns.ThreatList.Build(page) end
	if page.view then
		page.view:SetShown(on)
		if on and f.layout == "compact" then
			page.view:Layout(f:GetWidth(), f:GetHeight() - Widgets.TITLE_HEIGHT_COMPACT - Widgets.TAB_HEIGHT_COMPACT)
		end
	end
end

-- The Settings tab (UI/Settings.lua), built the first time it is shown, on the page opened last (`char.ui.lastPage`;
-- Window.page wins while the character's data cannot be written).
local function paintPage(f)
	if f.tab ~= "settings" or not ns.Settings then return end
	local page = f.pages.settings
	if not page.view then
		local holder = CreateFrame("Frame", nil, page)
		holder:SetPoint("TOPLEFT", page, "TOPLEFT", Window.PAGE_MARGIN, -10)
		holder:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -Window.PAGE_MARGIN, Window.PAGE_MARGIN)
		page.view = ns.Settings.Build(holder, { onPage = function(id)
			Window.page = id
			save("char.ui.lastPage", id)
		end })
	end
	page.view.width = f:GetWidth() - 2 * Window.PAGE_MARGIN
	page.view:ShowPage(Window.page or get("char.ui.lastPage") or "settings")
end

-- The Reports tab (UI/Reports.lua), built the first time it is shown, only while the `reports` switch is on (the tab
-- cannot be selected without it).
local function paintReports(f)
	if f.tab ~= "reports" or not featureOn("reports") or not ns.Reports then return end
	local page = f.pages.reports
	if not page.view then
		local holder = CreateFrame("Frame", nil, page)
		holder:SetPoint("TOPLEFT", page, "TOPLEFT", Window.PAGE_MARGIN, -10)
		holder:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -Window.PAGE_MARGIN, Window.PAGE_MARGIN)
		page.view = ns.Reports.Build(holder)
	end
	layoutReports(f)
	page.view:Refresh()
end

-- The compact bar gives up its title before the state loses its word.
function Window:LayoutTitle()
	local f = self.frame
	if not f then return end
	local bar = f.titles.compact
	local free = f:GetWidth() - 32 - 54   -- the logo on the left, the lock and the close button on the right
	bar.title:SetShown(bar.title:GetStringWidth() + 8 + bar.chip:GetWidth() <= free)
end

function Window:RefreshState()
	local f = self.frame
	if not f then return end
	local id = Window.ModuleState()
	for _, bar in pairs(f.titles) do bar.chip:SetModuleState(id) end
	self:LayoutTitle()
end

local function refreshLock(f)
	local locked = Window:IsLocked()
	for _, bar in pairs(f.titles) do bar.lock.icon:SetTexCoord(Assets.IconCoords(locked and "lock" or "unlock")) end
	f.grip:SetShown(not locked)
end

function Window:Refresh()
	local f = self.frame
	if not f then return end
	applyTabSwitches(f)
	refreshLock(f)
	paintPage(f)
	paintReports(f)
	paintMonitor(f)
	self:RefreshState()
end

-- Scale, size and position from `char.ui`.
local function place(f)
	f.scale = get("char.ui.scale") or 1
	f:SetScale(f.scale)
	applySize(f)
	anchor(f, get("char.ui.pos"))
	keepOnScreen(f)
	Window:LayoutTitle()
end

function Window:Frame()
	if not self.frame then
		local f = build()
		self.frame = f
		self.locked = nil
		local tab = get("char.ui.lastTab")
		if not tabAvailable(tab) then tab = "monitor" end
		applyTabSwitches(f)
		showTab(f, tab)
		place(f)
		self:Refresh()
	end
	return self.frame
end

---------------------------------------------------------------------------------------------------------------------
-- Public functions (commands, launcher, Settings)
---------------------------------------------------------------------------------------------------------------------
function Window:IsShown() return self.frame ~= nil and self.frame:IsShown() end
function Window:Tab() return self.frame and self.frame.tab or nil end
function Window:Layout() return self.frame and self.frame.layout or nil end
function Window:IsLocked() return get("char.ui.locked") == true end

function Window:Open()
	self.dismissed = false
	self:CancelAutoClose()
	local f = self:Frame()
	if not f:IsShown() then f:Show() end
	if f.Raise then f:Raise() end
	save("char.ui.shown", true)
	return f
end

function Window:Close()
	if self:IsShown() then self.frame:Hide()
	else save("char.ui.shown", false) end
end

function Window:Toggle()
	if self:IsShown() then self:Close() return false end
	self:Open()
	return true
end

-- Switches tab; between the two layouts the top-left corner stays where it is and the window stays on the screen.
-- `quiet`: the window does it by itself, so neither the tab nor the place is saved. Returns true when the tab exists
-- and its part is on.
function Window:SelectTab(id, quiet)
	local f = self:Frame()
	if not tabAvailable(id) then return false end
	if f.tab == id or self.selecting then return true end
	self.selecting = true
	local oldLayout, sw, sh = f.layout, screenSize(f)
	local left, top
	if sw then left, top = Window.Rect(currentPos(f), f:GetWidth(), f:GetHeight(), sw, sh) end
	stopMoving(f)
	stopSizing(f)
	showTab(f, id)
	if f.layout ~= oldLayout then
		applySize(f)
		if left then
			left, top = Window.Clamp(left, top, f:GetWidth(), f:GetHeight(), sw, sh)
			local pos = { point = "TOPLEFT", relativePoint = "BOTTOMLEFT", x = left, y = top }
			anchor(f, pos)
			if not quiet then save("char.ui.pos", pos) end
		end
	end
	if not quiet then save("char.ui.lastTab", id) end
	self.selecting = false
	self:Refresh()
	emit("TAB_CHANGED", id)
	return true
end

-- Shows the window on the Monitor tab without saving anything (the window's own rules, the demo).
function Window:ShowMonitor()
	self:CancelAutoClose()
	local f = self:Frame()
	self:SelectTab("monitor", true)
	if not f:IsShown() then f:Show() end
	if f.Raise then f:Raise() end
	return f
end

-- When the window shows itself: "auto", "always" or "manual" (always "manual" while the monitor is off).
function Window.ShowMode()
	if not featureOn("monitor") or (ns.addon and ns.addon.isForever == false) then return "manual" end
	return get(SHOW_PATH) or "manual"
end

local function openByItself()
	if not Window:IsShown() then Window:ShowMonitor() end
end

function Window:CancelAutoClose()
	self.closeToken = (self.closeToken or 0) + 1
end

-- "auto", after a fight outside a group: the window closes AUTO_CLOSE seconds later, unless by then another fight
-- started, a group was joined, the player went to another tab or a demo runs.
local function closeLater()
	Window:CancelAutoClose()
	local mine = Window.closeToken
	Compat.After(Window.AUTO_CLOSE, function()
		if mine ~= Window.closeToken or Window.ShowMode() ~= "auto" or not Window:IsShown() then return end
		if inCombat() or inGroup() or demoOn() or Window:Tab() ~= "monitor" then return end
		Window.autoHiding = true
		Window.frame:Hide()
		Window.autoHiding = false
	end)
end

-- Opens the window on a page of the Settings tab: "settings" or "about".
function Window:OpenPage(page)
	page = page == "about" and "about" or "settings"
	self.page = page            -- shown also when the character's data cannot be written
	save("char.ui.lastPage", page)
	self:Open()
	self:SelectTab("settings")
	paintPage(self.frame)
end

-- Returns true, or false and the reason ("read-only").
function Window:SetLocked(locked)
	local f = self.frame
	if f and locked then stopMoving(f) stopSizing(f) end
	local ok, why = set("char.ui.locked", locked and true or false)
	if f then refreshLock(f) end
	return ok, why
end

-- Position, sizes and scale back to the defaults, the window shown in the centre. Returns true, or false and the
-- reason; the window is shown either way.
function Window:Reset()
	local ok, why
	if config() then
		self.saving = true
		ok, why = config():ResetWindow()
		self.saving = false
	end
	local f = self:Frame()
	if ok then place(f) end
	self:Open()
	return ok, why
end

function Window:DebugLines()
	local f = self.frame
	local pos = get("char.ui.pos")
	local w, h = 0, 0
	if f then w, h = f:GetWidth(), f:GetHeight() end
	return {
		("created %s, shown %s, tab %s, module state %s"):format(f and "yes" or "no", self:IsShown() and "yes" or "no",
			(f and f.tab) or tostring(get("char.ui.lastTab")), Window.ModuleState()),
		("layout %s, size %d x %d, scale %.2f, locked %s, position %s"):format((f and f.layout) or "-", w, h,
			get("char.ui.scale") or 1, self:IsLocked() and "yes" or "no",
			pos and ("%s %.0f %.0f"):format(pos.point, pos.x, pos.y) or "centre"),
	}
end

---------------------------------------------------------------------------------------------------------------------
-- The effect of an alert on the border (SPEC-04 §3.2): once per alert, never flashing, never a glow
---------------------------------------------------------------------------------------------------------------------
local function setChipAlert(f, id)
	for _, bar in pairs(f.titles) do bar.chip:SetAlert(id) end
	Window:LayoutTitle()
end

function Window:EndEffect()
	local f = self.frame
	self.effectToken = (self.effectToken or 0) + 1
	if not self.effect then return end
	self.effect = nil
	if f then
		f.flash:Hide()
		setChipAlert(f, nil)
	end
end

-- The border takes the colour of the alert's state: it fades in (120 ms), stays EFFECT_HOLD seconds and fades out
-- (320 ms); with the animations off it only stays. An alert of a higher severity restarts it, another one does not.
-- Without a message in the window the title bar's pill shows the state's icon too (never a colour alone, ST-02).
function Window:AlertEffect(alert)
	if not alert.visual or not self:IsShown() then return end
	if self.effect and alert.severity <= self.effect then return end
	local f = self.frame
	self:EndEffect()
	self.effect = alert.severity
	local id = alert.state == "DANGER" and "danger" or "warning"
	for _, ring in pairs(f.flash.rings) do Theme.Tint(ring, Theme.State(id).token) end
	if not alert.window then setChipAlert(f, id) end
	f.flash:Show()
	f.flash:SetAlpha(0)
	local Motion = ns.Motion
	Motion.Fade(f.flash, 1, Motion.FAST)
	local mine = self.effectToken
	local lead = Motion.On() and Motion.FAST or 0
	local tail = Motion.On() and Motion.SLOW or 0
	Compat.After(lead + Window.EFFECT_HOLD, function()
		if mine ~= self.effectToken then return end
		if tail == 0 then self:EndEffect() return end
		Motion.Fade(f.flash, 0, Motion.SLOW)
		Compat.After(tail, function()
			if mine == self.effectToken then self:EndEffect() end
		end)
	end)
end

---------------------------------------------------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------------------------------------------------
local function onConfigChanged(path)
	if path == SHOW_PATH then
		Window:CancelAutoClose()
		if Window.ShowMode() == "always" then openByItself() end
		return
	end
	local f = Window.frame
	if not f or Window.saving or type(path) ~= "string" then return end
	if path == "char.ui.locked" then
		refreshLock(f)
	elseif path == "char.ui.scale" then
		-- the saved offsets are in the units of the window: converted, so that the window stays where it is
		local old, new = f.scale or 1, get("char.ui.scale") or 1
		local pos = get("char.ui.pos")
		if pos then
			save("char.ui.pos", { point = pos.point, relativePoint = pos.relativePoint, x = pos.x * old / new,
				y = pos.y * old / new })
		end
		place(f)
	elseif path == "char.ui.pos" or path:find("^char%.ui%.size%.") then
		place(f)
	end
end

if ns.Bus then
	ns.Bus.On("CONFIG_LOADED", function() if Window.frame then place(Window.frame) Window:Refresh() end end)
	ns.Bus.On("CONFIG_CHANGED", onConfigChanged)
	ns.Bus.On("ALERT_RAISED", function(alert) Window:AlertEffect(alert) end)
	ns.Bus.On("DISPLAY_CHANGED", function() if Window.frame then keepOnScreen(Window.frame) end end)
	local function state() Window:RefreshState() end
	ns.Bus.On("COMBAT_STARTED", function()
		Window.dismissed = false
		Window:CancelAutoClose()
		if Window.ShowMode() == "auto" then openByItself() end
		state()
	end)
	ns.Bus.On("COMBAT_ENDED", function()
		if Window.ShowMode() == "auto" and Window:IsShown() and not inGroup() then closeLater() end
		state()
	end)
	ns.Bus.On("GROUP_CHANGED", function(grouped)
		local was = Window.grouped
		Window.grouped = grouped
		if not grouped then return end
		Window:CancelAutoClose()
		if not was and not Window.dismissed and Window.ShowMode() == "auto" then openByItself() end
	end)
	ns.Bus.On("DEMO_CHANGED", state)
	ns.Bus.On("CAPABILITY_CHANGED", state)
	ns.Bus.On("THREAT_MODE_CHANGED", state)
	ns.Bus.On("TARGET_CHANGED", state)
end

-- At login the window is shown as the character left it (shown the first time); "always" shows it anyway, "auto" also
-- in a group (a fight at login arrives as COMBAT_STARTED).
if ns.OnEnable then
	ns.OnEnable(function()
		local mode = Window.ShowMode()
		Window.grouped = mode ~= "manual" and inGroup()
		if get("char.ui.shown") then Window:Open()
		elseif mode == "always" or (mode == "auto" and Window.grouped) then openByItself() end
	end)
end

if ns.addon then
	ns.addon.Window = Window
	ns.addon:AddDebugSection("Window", function() return Window:DebugLines() end)
end
