-- Widget kit, part 4: the addon's own Tooltip (FDCP: "inverted, own frame"): a surface of `text-1` with the text in
-- `bg`, one frame for the whole addon, 13 pt body. It shows lines the caller already translated.
-- Adapted from Azeroth Accord (UI/Widgets/Tooltip.lua), same owner, GPL-3.0 (ADR 0012); the game's item tooltip is not
-- needed here. Lua 5.1; one unprotected frame made on first use.
--   Widgets.Tooltip.Show(owner, content, anchor)   content: "text" | { "title", "line", { text = "...", token = "ok" } ... },
--                                                  at most MAX_LINES lines (content.maxLines for more)
--   Widgets.Tooltip.Hide()
--   Widgets.Tooltip.Attach(frame, source, anchor)  source: content | function(owner) -> content (nil shows nothing)
-- anchor: "BOTTOM" (default, under the owner), "TOP", "RIGHT", "LEFT". The first line is the title (medium weight).
local ADDON_NAME, ns = ...
ns = ns or {}
local Widgets, Theme = ns.Widgets, ns.Theme
local type, ipairs, tostring, max, min = type, ipairs, tostring, math.max, math.min

local Tooltip = {}
Widgets.Tooltip = Tooltip

Tooltip.MAX_WIDTH, Tooltip.MAX_LINES = 280, 16
local PAD_X, PAD_Y, GAP, OFFSET = 10, 8, 2, 6

local frame   -- made on first use

local function build()
	local f = CreateFrame("Frame", "AzerothThreatwardenTooltip", ns.Compat.UIParent())
	f:SetFrameStrata("TOOLTIP")
	f:SetClampedToScreen(true)
	f:EnableMouse(false)   -- it never takes a click: the pointer goes through to what is under it
	f.parts = Theme.Panel(f, { radius = 8, fill = "text-1", border = false, shadow = true })
	f.lines = {}
	f:Hide()
	return f
end

local function line(f, i)
	local fs = f.lines[i]
	if not fs then
		fs = Theme.NewText(f, i == 1 and "BodyMedium" or "Body", "bg")
		fs:SetJustifyH("LEFT")
		if fs.SetWordWrap then fs:SetWordWrap(true) end
		f.lines[i] = fs
	end
	return fs
end

local function normalise(content)
	local list = {}
	if type(content) == "table" and content.text == nil then
		-- a content may ask for more lines than the default (the comparison of Analytics, one line per measure)
		for i = 1, min(#content, content.maxLines or Tooltip.MAX_LINES) do list[i] = content[i] end
	elseif content ~= nil then
		list[1] = content
	end
	return list
end

local function textOf(entry) return type(entry) == "table" and tostring(entry.text or "") or tostring(entry) end

-- Shows `content` next to `owner`. Returns the frame, or nil when there is nothing to show.
function Tooltip.Show(owner, content, anchor)
	local list = normalise(content)
	if #list == 0 then Tooltip.Hide(); return nil end
	frame = frame or build()
	local f = frame
	local widest = 0
	for i, entry in ipairs(list) do
		local fs = line(f, i)
		fs:SetWidth(0)   -- natural width first
		fs:SetText(textOf(entry))
		Theme.Text(fs, type(entry) == "table" and entry.token or "bg")
		widest = max(widest, fs:GetStringWidth() or 0)
	end
	for i = #list + 1, #f.lines do f.lines[i]:SetText(""); f.lines[i]:Hide() end
	local width = min(max(widest, 40), Tooltip.MAX_WIDTH)
	local y = PAD_Y
	for i = 1, #list do
		local fs = f.lines[i]
		fs:ClearAllPoints()
		fs:SetWidth(width)
		fs:SetPoint("TOPLEFT", f, "TOPLEFT", PAD_X, -y)
		fs:Show()
		y = y + (fs:GetStringHeight() or 14) + GAP
	end
	f:SetSize(width + PAD_X * 2, y - GAP + PAD_Y)
	f.owner = owner
	f:ClearAllPoints()
	anchor = anchor or "BOTTOM"
	if anchor == "TOP" then f:SetPoint("BOTTOM", owner, "TOP", 0, OFFSET)
	elseif anchor == "RIGHT" then f:SetPoint("LEFT", owner, "RIGHT", OFFSET, 0)
	elseif anchor == "LEFT" then f:SetPoint("RIGHT", owner, "LEFT", -OFFSET, 0)
	else f:SetPoint("TOP", owner, "BOTTOM", 0, -OFFSET) end
	f:Show()
	return f
end

function Tooltip.Hide()
	if frame then frame.owner = nil; frame:Hide() end
end

function Tooltip.IsShown() return frame ~= nil and frame:IsShown() end
function Tooltip.Owner() return frame and frame.owner end
function Tooltip.Frame() return frame end
function Tooltip.Lines()
	local out = {}
	if frame then
		for _, fs in ipairs(frame.lines) do if fs:IsShown() then out[#out + 1] = fs:GetText() end end
	end
	return out
end

-- Shows the tooltip while the mouse is over `frame` (a hook: the frame keeps its own scripts). `source` is a content or
-- a function(owner) returning one.
function Tooltip.Attach(target, source, anchor)
	target:HookScript("OnEnter", function(self)
		local content = source
		if type(source) == "function" then content = source(self) end   -- nil: nothing to show (not `and/or`: it would fall back)
		if content ~= nil then Tooltip.Show(self, content, anchor) end
	end)
	target:HookScript("OnLeave", function() Tooltip.Hide() end)
	target:HookScript("OnHide", function(self) if Tooltip.Owner() == self then Tooltip.Hide() end end)
end
