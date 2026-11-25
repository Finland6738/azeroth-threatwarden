-- Adapted from Azeroth Accord (Tests/mock/25_frames_more.lua and 26_ui_textures.lua), same owner, GPL-3.0 (ADR 0012).
-- Mock client, part 4b: the texture methods of the themed UI, colour objects, the screen size, and Show / Hide that run
-- the hooked scripts and reach the shown children, added to the generic widget of 20_frames.lua.
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

-- Moving is instant: the mock records that the frame is being moved.
function Widget:StartMoving() self._moving = true end
function Widget:StopMovingOrSizing() self._moving = false end

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
