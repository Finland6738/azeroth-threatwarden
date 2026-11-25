-- Motion: the transitions of docs/specs/ui-style.md (FDCP): 120 ms for states, buttons and the threat bar, 200 ms for
-- tabs, 320 ms for panels, always the game's OUT curve (no spring: the engine has none). Lua 5.1.
-- Adapted from Azeroth Accord (UI/Motion.lua, itself from Finland Dragon Credit Points), same owner, GPL-3.0 (ADR 0012).
-- Changes: Motion.Tween (a value the engine cannot animate: the width and colour of a threat bar); no Pulse.
-- * Everything but Tween is an AnimationGroup of the game (Alpha, Scale, Translation, Rotation); the groups are made once
--   per region and reused, so a window that is drawn again creates none.
-- * "Animations: off" (account.settings.animations) makes every call finish at once: the end state is set directly and
--   no group is played.
-- * A region that is hidden while an animation runs is put in its end state by the group's OnFinished / OnHide.
local ADDON_NAME, ns = ...
ns = ns or {}

local Motion = {}
ns.Motion = Motion
if ns.addon then ns.addon.Motion = Motion end   -- also reachable from tests

local Theme = ns.Theme

Motion.FAST, Motion.BASE, Motion.SLOW = 0.12, 0.20, 0.32   -- seconds: states, tabs and chips, panels
Motion.PRESS = 0.97                                         -- a pressed button shrinks to this scale
Motion.SMOOTHING = "OUT"

function Motion.On() return Theme.AnimationsOn() end

-- The state of a region's animations: one table per region, kept out of the region itself.
local state = setmetatable({}, { __mode = "k" })
local function of(region)
	local s = state[region]
	if not s then s = {}; state[region] = s end
	return s
end

local function alphaOf(region)
	return (region.GetAlpha and region:GetAlpha()) or 1
end

-- Fades `region` to alpha `to` in `duration` seconds (BASE by default). `done` runs when it ends (at once when
-- animations are off). Returns true when an animation was started.
function Motion.Fade(region, to, duration, done)
	duration = duration or Motion.BASE
	local s = of(region)
	if s.fade then s.fade.group:Stop() end
	if not Motion.On() or duration <= 0 then
		region:SetAlpha(to)
		if done then done() end
		return false
	end
	if not s.fade then
		local group = region:CreateAnimationGroup()
		local anim = group:CreateAnimation("Alpha")
		anim:SetSmoothing(Motion.SMOOTHING)
		s.fade = { group = group, anim = anim }
		group:SetScript("OnFinished", function()
			region:SetAlpha(s.fade.to)
			local cb = s.fade.done
			s.fade.done = nil
			if cb then cb() end
		end)
	end
	s.fade.to, s.fade.done = to, done
	s.fade.anim:SetFromAlpha(alphaOf(region))
	s.fade.anim:SetToAlpha(to)
	s.fade.anim:SetDuration(duration)
	s.fade.group:Play()
	return true
end

-- Shows a hidden region with a fade from 0 to `to` (1 by default).
function Motion.FadeIn(region, duration, to)
	region:Show()
	if not Motion.On() then region:SetAlpha(to or 1); return false end
	region:SetAlpha(0)
	return Motion.Fade(region, to or 1, duration or Motion.BASE)
end

-- Fades a region out and hides it (it keeps its alpha for the next Show).
function Motion.FadeOut(region, duration)
	local keep = alphaOf(region)
	return Motion.Fade(region, 0, duration or Motion.BASE, function()
		region:Hide()
		region:SetAlpha(keep > 0 and keep or 1)
	end)
end

-- A panel enters: it rises `rise` points while it fades in (the dialog and the popup card, 320 ms). The frame must have
-- a point; it is moved down for the animation and put back at the end. Returns true when it animates.
function Motion.Rise(frame, rise, duration)
	duration = duration or Motion.SLOW
	rise = rise or 12
	frame:Show()
	if not Motion.On() or not frame.GetPoint then return false end
	local point, rel, relPoint, x, y = frame:GetPoint(1)
	if not point then return false end
	local s = of(frame)
	if s.rise then s.rise.group:Stop(); frame:ClearAllPoints(); frame:SetPoint(unpack(s.rise.origin)) end
	if not s.rise then
		local group = frame:CreateAnimationGroup()
		local fade = group:CreateAnimation("Alpha")
		fade:SetSmoothing(Motion.SMOOTHING)
		fade:SetFromAlpha(0); fade:SetToAlpha(1)
		local move = group:CreateAnimation("Translation")
		move:SetSmoothing(Motion.SMOOTHING)
		s.rise = { group = group, fade = fade, move = move }
		group:SetScript("OnFinished", function()
			local o = s.rise.origin
			frame:ClearAllPoints()
			frame:SetPoint(o[1], o[2], o[3], o[4], o[5])
			frame:SetAlpha(1)
		end)
	end
	s.rise.origin = { point, rel, relPoint, x or 0, y or 0 }
	s.rise.fade:SetDuration(duration); s.rise.move:SetDuration(duration)
	s.rise.move:SetOffset(0, rise)
	frame:ClearAllPoints()
	frame:SetPoint(point, rel, relPoint, x or 0, (y or 0) - rise)
	frame:SetAlpha(0)
	s.rise.group:Play()
	return true
end

-- Turns a texture to `radians` in `duration` seconds (the accordion arrow, 320 ms); the end angle is set when it ends.
function Motion.Rotate(texture, radians, duration)
	duration = duration or Motion.SLOW
	local s = of(texture)
	local from = s.angle or 0
	if s.rotate then s.rotate.group:Stop() end
	s.angle = radians
	if not Motion.On() or duration <= 0 or from == radians then
		texture:SetRotation(radians)
		return false
	end
	if not s.rotate then
		local group = texture:CreateAnimationGroup()
		local anim = group:CreateAnimation("Rotation")
		anim:SetSmoothing(Motion.SMOOTHING)
		anim:SetOrigin("CENTER", 0, 0)
		s.rotate = { group = group, anim = anim }
		group:SetScript("OnFinished", function() texture:SetRotation(s.angle) end)
	end
	texture:SetRotation(from)
	s.rotate.anim:SetRadians(radians - from)
	s.rotate.anim:SetDuration(duration)
	s.rotate.group:Play()
	return true
end

-- Slides a texture or frame by (dx, dy) in `duration` seconds and leaves it at its new anchor (the switch thumb, the
-- tab indicator). `place(dx, dy)` sets the end position (the caller knows the anchors); without animations it runs at once.
function Motion.Slide(region, dx, dy, duration, place)
	duration = duration or Motion.BASE
	local s = of(region)
	if s.slide then s.slide.group:Stop() end
	if not Motion.On() or duration <= 0 then
		place(dx, dy)
		return false
	end
	if not s.slide then
		local group = region:CreateAnimationGroup()
		local anim = group:CreateAnimation("Translation")
		anim:SetSmoothing(Motion.SMOOTHING)
		s.slide = { group = group, anim = anim }
		group:SetScript("OnFinished", function()
			local f = s.slide.place
			if f then f(s.slide.dx, s.slide.dy) end
		end)
	end
	s.slide.place, s.slide.dx, s.slide.dy = place, dx, dy
	s.slide.anim:SetOffset(dx, dy)
	s.slide.anim:SetDuration(duration)
	s.slide.group:Play()
	return true
end

-- The press of a button: down shrinks it to 0.97 in 120 ms and holds, up returns it in 120 ms. Hooks the mouse scripts, so
-- a widget that sets its own keeps them. Does nothing with animations off.
function Motion.Press(button, scale)
	scale = scale or Motion.PRESS
	local down = button:CreateAnimationGroup()
	local shrink = down:CreateAnimation("Scale")
	shrink:SetScaleFrom(1, 1); shrink:SetScaleTo(scale, scale); shrink:SetDuration(Motion.FAST)
	shrink:SetSmoothing(Motion.SMOOTHING); shrink:SetOrigin("CENTER", 0, 0); shrink:SetOrder(1)
	local hold = down:CreateAnimation("Scale")   -- stays at the pressed size until the mouse is released
	hold:SetScaleFrom(scale, scale); hold:SetScaleTo(scale, scale); hold:SetDuration(30); hold:SetOrder(2)
	hold:SetOrigin("CENTER", 0, 0)
	local up = button:CreateAnimationGroup()
	local grow = up:CreateAnimation("Scale")
	grow:SetScaleFrom(scale, scale); grow:SetScaleTo(1, 1); grow:SetDuration(Motion.FAST)
	grow:SetSmoothing(Motion.SMOOTHING); grow:SetOrigin("CENTER", 0, 0)
	local s = of(button)
	s.press = { down = down, up = up }
	local function release()
		if down:IsPlaying() then
			down:Stop()
			if Motion.On() then up:Play() end
		end
	end
	button:HookScript("OnMouseDown", function(self)
		if Motion.On() and self:IsEnabled() then up:Stop(); down:Play() end
	end)
	button:HookScript("OnMouseUp", release)
	button:HookScript("OnHide", function() down:Stop(); up:Stop() end)
	return s.press
end

-- Calls apply(target, f) with f going from 0 to 1 over `duration` seconds on the OUT curve, driven by the OnUpdate of
-- `frame` (which the tween takes over). For what the engine's animations cannot move: the width and the colour of the
-- threat bar. One state per frame, reused: a tween allocates nothing after the first (ARC-06), so `apply` must be a
-- function made once. A frame hidden in the middle, or animations off, jumps to f = 1. Returns true when it animates.
local function easeOut(t) return 1 - (1 - t) * (1 - t) end
Motion.Ease = easeOut

-- Drops a running tween without applying anything more.
function Motion.StopTween(frame)
	local t = of(frame).tween
	if t and t.running then t.running = false; frame:SetScript("OnUpdate", nil) end
end

local function finishTween(s, frame)
	if not s.running then return end
	s.running = false
	frame:SetScript("OnUpdate", nil)
	s.apply(s.target, 1)
end

function Motion.Tween(frame, duration, apply, target)
	duration = duration or Motion.FAST
	local s = of(frame)
	local t = s.tween
	if not Motion.On() or duration <= 0 or not frame:IsVisible() then
		Motion.StopTween(frame)
		apply(target, 1)
		return false
	end
	if not t then
		t = {}
		t.step = function(_, elapsed)
			t.elapsed = t.elapsed + (elapsed or 0)
			if t.elapsed >= t.duration then
				finishTween(t, frame)
			else
				t.apply(t.target, easeOut(t.elapsed / t.duration))
			end
		end
		s.tween = t
		frame:HookScript("OnHide", function() finishTween(t, frame) end)
	end
	t.elapsed, t.duration, t.apply, t.target, t.running = 0, duration, apply, target, true
	apply(target, 0)
	frame:SetScript("OnUpdate", t.step)
	return true
end
