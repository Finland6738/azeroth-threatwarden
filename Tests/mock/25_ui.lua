-- Adapted from Azeroth Accord (Tests/mock/25_frames_more.lua and 26_ui_textures.lua), same owner, GPL-3.0 (ADR 0012).
-- Mock client, part 4b: the texture methods of the themed UI, colour objects, the screen size, Line regions, the
-- pointer, and Show / Hide that run the hooked scripts and reach the shown children, added to the generic widget of
-- 20_frames.lua.
--
-- Imitates (dump: ../WoW-Addons/docs/api.json, Texture / TextureBase and ScriptRegion API): SetTextureSliceMargins,
-- GetTextureSliceMargins, SetTextureSliceMode, SetSnapToPixelGrid, SetTexelSnappingBias, and the globals CreateColor,
-- GetPhysicalScreenSize, GetScreenWidth, GetScreenHeight. Enum.UITextureSliceMode is part of the interface code.
-- The mock stores what the addon asked for, so tests can check the 9-slice margins and the pixel snapping of a region.
local Mock, H = ...

local Widget = getmetatable(UIParent).__index

function Widget:SetTextureSliceMargins(l, t, r, b) self._slice = { l, t, r, b } end
function Widget:GetTextureSliceMargins() if self._slice then return unpack(self._slice) end return 0, 0, 0, 0 end
function Widget:SetTextureSliceMode(mode) self._sliceMode = mode end
function Widget:SetSnapToPixelGrid(v) self._snap = v and true or false end
function Widget:IsSnappingToPixelGrid() return self._snap ~= false end
function Widget:SetTexelSnappingBias(v) self._texelBias = v end
function Widget:GetTexelSnappingBias() return self._texelBias or 0 end
function Widget:SetHorizTile(v) self._horizTile = v and true or false end
function Widget:SetFormattedText(format, ...) self:SetText(string.format(format, ...)) end

Enum.UITextureSliceMode = { Stretched = 1, Tiled = 0 }

-- Line regions (dump: SimpleFrameAPI:CreateLine, SimpleLineAPI SetStartPoint / SetEndPoint / SetThickness; a Line is
-- coloured like a texture). The mock keeps the points as the addon gave them. A setup may set `Widget.CreateLine = nil`
-- (getmetatable(UIParent).__index) to imitate a client without them.
function Widget:CreateLine(name, layer)
	local l = self:CreateTexture(name, layer)
	l._type = "Line"
	return l
end
function Widget:SetStartPoint(relativePoint, relativeTo, x, y) self._start = { relativePoint, relativeTo, x or 0, y or 0 } end
function Widget:GetStartPoint() if self._start then return unpack(self._start) end end
function Widget:SetEndPoint(relativePoint, relativeTo, x, y) self._end = { relativePoint, relativeTo, x or 0, y or 0 } end
function Widget:GetEndPoint() if self._end then return unpack(self._end) end end
function Widget:SetThickness(t) self._thickness = t end
function Widget:GetThickness() return self._thickness end
function Widget:SetDrawLayer(layer, sub) self._layer, self._sublevel = layer, sub end

-- The pointer in screen pixels (dump: Input.GetCursorPosition); a test moves it by writing Mock.cursor.
Mock.cursor = { x = 0, y = 0 }
function GetCursorPosition() return Mock.cursor.x, Mock.cursor.y end

-- The modifier keys (dump: Input.IsShiftKeyDown, IsControlKeyDown, IsAltKeyDown); a test writes Mock.modifiers.
Mock.modifiers = {}
function IsShiftKeyDown() return Mock.modifiers.shift == true end
function IsControlKeyDown() return Mock.modifiers.ctrl == true end
function IsAltKeyDown() return Mock.modifiers.alt == true end

-- The keyboard of a frame (dump: SimpleFrameAPI EnableKeyboard, SetPropagateKeyboardInput; ScriptRegion IsMouseOver).
-- A frame starts without keys and without propagation, as in the client; a test puts the pointer over it by setting
-- Mock.mouseOver. SetPropagateKeyboardInput in combat lockdown is refused by the client: counted in Mock.blocked.
-- Mock.PressKey(frame, key) is a key pressed: true when it reaches the game (the frame did not take it).
Mock.mouseOver, Mock.blocked = nil, 0
function Widget:EnableKeyboard(v) self._keyboard = v and true or false end
function Widget:IsKeyboardEnabled() return self._keyboard == true end
function Widget:SetPropagateKeyboardInput(v)
	if InCombatLockdown() then
		Mock.blocked = Mock.blocked + 1
		error("SetPropagateKeyboardInput: blocked in combat", 2)
	end
	self._propagate = v and true or false
end
function Widget:IsMouseOver() return Mock.mouseOver == self end
function Mock.PressKey(frame, key)
	if not (frame._keyboard and frame:IsVisible()) then return true end
	Mock.RunScript(frame, "OnKeyDown", key)
	return frame._propagate == true
end

-- A scroll frame keeps the offset the addon gave it.
function Widget:SetVerticalScroll(v) self._vscroll = v end
function Widget:GetVerticalScroll() return self._vscroll or 0 end

-- The game's Settings window (interface code, not in the dump): the mock keeps what was registered in
-- Mock.settingsCategories. A setup may set `Settings = nil` to imitate a client without it.
Mock.settingsCategories = {}
Settings = {
	RegisterCanvasLayoutCategory = function(frame, name) return { frame = frame, name = name } end,
	RegisterAddOnCategory = function(category) Mock.settingsCategories[#Mock.settingsCategories + 1] = category end,
	OpenToCategory = function() end,
}

-- /reload as the client does it: counted in Mock.reloads (the harness's own Mock.Reload rebuilds the Lua state).
Mock.reloads = 0
C_UI = { Reload = function() Mock.reloads = Mock.reloads + 1 end }

-- Moving is instant: the mock records that the frame is being moved.
function Widget:StartMoving() self._moving = true end
function Widget:StartSizing(point) self._sizing = point end
function Widget:StopMovingOrSizing() self._moving, self._sizing = false, nil end

function CreateColor(r, g, b, a) return { r = r, g = g, b = b, a = a or 1 } end

-- The physical screen and the UI size; a test may change Mock.screen.
Mock.screen = { width = 1920, height = 1080 }
function GetPhysicalScreenSize() return Mock.screen.width, Mock.screen.height end
function GetScreenWidth() return UIParent:GetWidth() end
function GetScreenHeight() return UIParent:GetHeight() end

-- Show and Hide run the OnShow / OnHide script AND the functions added with HookScript, as the client does (the generic
-- widget ran only the script), and only when visibility changes: a frame under a hidden parent runs nothing. The shown
-- children of a frame that appears or disappears run theirs too.
local function cascade(widget, script)
	for _, child in ipairs(widget._children) do
		if child._shown then
			Mock.RunScript(child, script)
			cascade(child, script)
		end
	end
end
local function parentVisible(widget)
	local p = widget._parent
	return not p or p:IsVisible()
end
function Widget:Show()
	if not self._shown then
		self._shown = true
		if parentVisible(self) then
			Mock.RunScript(self, "OnShow")
			cascade(self, "OnShow")
		end
	end
end
function Widget:Hide()
	if self._shown then
		self._shown = false
		if parentVisible(self) then
			Mock.RunScript(self, "OnHide")
			cascade(self, "OnHide")
		end
	end
end

-- The slider tells its script about a value that changed, as the client does (user = false for the addon's own writes).
local setValue = Widget.SetValue
function Widget:SetValue(v)
	local changed = self._value ~= v
	setValue(self, v)
	if changed and self._type == "Slider" then Mock.RunScript(self, "OnValueChanged", v, false) end
end
