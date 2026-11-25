-- Widget kit, part 3: ThinBar, the 4 pt bar of the ecosystem (progress, timers): a subtle track and a fill with the
-- gradient accent -> accent-2. The threat bar is another widget (Threat.lua).
-- Adapted from Azeroth Accord (UI/Widgets/ThinBar.lua, itself from Finland Dragon Credit Points), same owner, GPL-3.0
-- (ADR 0012). Lua 5.1.
--   bar = Widgets.ThinBar(parent, { height = 4, width = 200 }); bar:SetFraction(0..1); bar:GetFraction()
local ADDON_NAME, ns = ...
ns = ns or {}
local Widgets, Theme = ns.Widgets, ns.Theme

local function color(token)
	return ns.Compat.CreateColor(Theme.Color(token))
end

function Widgets.ThinBar(parent, opts)
	opts = opts or {}
	local bar = CreateFrame("Frame", nil, parent)
	bar:SetHeight(opts.height or 4)
	if opts.width then bar:SetWidth(opts.width) end
	bar.track = bar:CreateTexture(nil, "BACKGROUND")
	Theme.Fill(bar.track, "border-subtle")
	bar.track:SetAllPoints(bar)
	bar.fill = bar:CreateTexture(nil, "ARTWORK")
	Theme.Fill(bar.fill, "accent")
	Theme.Call(bar.fill, function(region)
		if region.SetGradient then region:SetGradient("HORIZONTAL", color("accent"), color("accent-2")) end
	end)
	bar.fill:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
	bar.fill:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 0, 0)
	bar.fraction = 0

	local function paint()
		local w = bar:GetWidth() or 0
		if w <= 1 then w = opts.width or 200 end
		if bar.fraction <= 0 then bar.fill:Hide() else
			bar.fill:SetWidth(math.max(w * bar.fraction, 1))
			bar.fill:Show()
		end
	end
	function bar:SetFraction(f)
		f = tonumber(f) or 0
		self.fraction = math.min(math.max(f, 0), 1)
		paint()
	end
	function bar:GetFraction() return self.fraction end
	bar:SetScript("OnSizeChanged", paint)
	paint()
	return bar
end
