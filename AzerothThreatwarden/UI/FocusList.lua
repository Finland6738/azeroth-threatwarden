-- FocusList: the Dungeon Focus of the Monitor tab (SPEC-07 §2.1-§2.4; docs/specs/ui-style.md 3.7; ADR 0003, 0019).
-- Threatwarden's own. Lua 5.1; ordinary unprotected frames.
--
-- Two parts, both built by UI/ThreatList.lua like the Coach strip:
--   * the pull bar (20 pt, under the header of the monitored mob): "Pull · 5" and the riskiest mob other than the
--     monitored one (state badge and the word of its reason), "All safe", or, when the reach is reduced, what can be read
--     here; a click opens the list in place of the threat list, another closes it;
--   * the list: one 20 pt row per mob from a pool of 12, in the order of risk (Data/MobRisk.lua), recomputed at most once
--     a second and at once when a mob enters DANGER; the monitored mob is ringed, an unknown mob is dashed and says why,
--     and the rows that do not fit are summed up in "+N more". A click on a row pins that mob as the one the monitor
--     follows (Data/TargetTracker.lua, Pin) and closes the list; the game's target never changes (MT-06).
--
-- It reads the Data modules only (MobTracker, MobRisk, TargetTracker, ThreatScanner for "in combat" and the group): no
-- game API is named here (ARC-02). A mob that cannot be read never shows a number (ADR 0003): its state is UNKNOWN,
-- with the reason in the row and the tooltip. Redrawn on MOBS_UPDATED only while visible; a text is written only when it
-- changes. With the `multitarget` switch off, or the setting off, nothing of it is shown.
-- During the demo the sources are the invented ones (Core/Demo.lua) and a mob cannot be pinned.
local ADDON_NAME, ns = ...
ns = ns or {}
ns.modules = ns.modules or {}

local FocusList = {}
ns.FocusList, ns.modules.FocusList = FocusList, FocusList

local L, Widgets, Theme, Assets, Compat = ns.L, ns.Widgets, ns.Theme, ns.Assets, ns.Compat
local type, floor, max, min = type, math.floor, math.max, math.min

FocusList.BAR_HEIGHT, FocusList.ROW_HEIGHT = 20, 20
FocusList.POOL = 12
FocusList.RESORT = 1        -- seconds between two automatic orderings (as MON-13)

local MOBS_PREFIX = "account.settings.mobs."
local STATE_ID = { SAFE = "safe", WARNING = "warning", DANGER = "danger", UNKNOWN = "unknown" }
local CLASSIFICATION = {
	elite = "MON_CLASS_ELITE", rare = "MON_CLASS_RARE", rareelite = "MON_CLASS_RAREELITE",
	worldboss = "MON_CLASS_BOSS",
}
local SHORT_WHY = {
	secret = "FOCUS_SHORT_SECRET", ["no-token"] = "FOCUS_SHORT_NO_TOKEN", stale = "FOCUS_SHORT_STALE",
	pending = "FOCUS_SHORT_PENDING",
}
local WHY_REASON = {
	["no-guid"] = "FOCUS_REASON_NO_GUID", ["no-compare"] = "FOCUS_REASON_NO_COMPARE",
	secret = "FOCUS_REASON_SECRET", ["nameplates-off"] = "FOCUS_REASON_NAMEPLATES",
	["no-answer"] = "FOCUS_REASON_NO_ANSWER",
}
local REACH_SENTENCE = {
	["focus-boss"] = "FOCUS_REACH_BOSS", target = "FOCUS_REACH_TARGET", none = "FOCUS_REACH_NONE",
}
local REACH_SHORT = {
	all = "FOCUS_REACH_ALL", ["focus-boss"] = "FOCUS_REACH_SHORT_BOSS", target = "FOCUS_REACH_SHORT_TARGET",
	none = "FOCUS_REACH_SHORT_NONE", unknown = "FOCUS_REACH_SHORT_UNKNOWN",
}
local RISK_WHY = {
	aggro = "FOCUS_WHY_AGGRO", close = "FOCUS_WHY_CLOSE", ["no-tank"] = "FOCUS_WHY_NO_TANK", near = "FOCUS_WHY_NEAR",
}
local SOURCE_LABEL = {
	monitored = "FOCUS_SOURCE_MONITORED", focus = "FOCUS_SOURCE_FOCUS", boss = "FOCUS_SOURCE_BOSS",
	plate = "FOCUS_SOURCE_PLATE", group = "FOCUS_SOURCE_GROUP", lookup = "FOCUS_SOURCE_LOOKUP",
}
local CATEGORY_LABEL = { detected = "CAT_DETECTED", calculated = "CAT_CALCULATED" }
local MODE_LABEL = { values = "MODULE_LIVE", state = "MODULE_STATE", none = "MODULE_UNAVAILABLE" }

---------------------------------------------------------------------------------------------------------------------
-- What there is to show
---------------------------------------------------------------------------------------------------------------------
local function switchOn() return ns.Features ~= nil and ns.Features.On("multitarget") end

local function tracker()
	if not switchOn() then return nil end
	local MT = ns.MobTracker
	if not MT or not MT.Enabled or not MT.Enabled() then return nil end
	return MT
end

local function demoOn() return ns.Demo ~= nil and ns.Demo.IsActive() end

local function inGroup()
	local Scanner = ns.ThreatScanner
	local records = Scanner and Scanner.records
	for i = 1, Scanner and Scanner.count or 0 do
		local token = records[i] and records[i].unitToken
		if token and (token:find("^party%d") or token:find("^raid%d")) then return true end
	end
	return false
end

-- true when what can be read is less than the whole pull, for a reason that can be said (SPEC-07 §1.4): a fight with a
-- single mob has no reason and is not a reduction.
function FocusList.Reduced()
	local MT = tracker()
	if not MT then return false end
	local reach, reason = MT.Reach()
	if reach == "none" then return true end
	return (reach == "target" or reach == "focus-boss") and reason ~= nil
end

-- Is there a pull bar? In combat (or the demo), with a mob other than the monitored one, or, in a group, with a reduced
-- reach (SPEC-07 §2.3).
function FocusList.Present()
	local MT = tracker()
	if not MT then return false end
	local Scanner = ns.ThreatScanner
	if not (Scanner and Scanner.inCombat) then return false end
	local list, n = MT.List()
	for i = 1, n do
		if not list[i].monitored then return true end
	end
	return FocusList.Reduced() and inGroup()
end

---------------------------------------------------------------------------------------------------------------------
-- Words
---------------------------------------------------------------------------------------------------------------------
local function mobName(key)
	local MT = ns.MobTracker
	local name, classification = MT.NameOf(key)
	return name or L.MON_UNKNOWN_MOB, classification
end

local function unitLabel(rec) return ns.ThreatList.UnitLabel(rec) end

local function round(v) return floor(v + 0.5) end

local function signed(v)
	local r = round(v)
	if r > 0 then return "+" .. r end
	return tostring(r)
end

-- Why a mob is unknown, in a few words (the row) and in a sentence (the tooltip).
local function shortWhy(reason) return L[SHORT_WHY[reason or ""] or "FOCUS_SHORT_OTHER"] end

local function longWhy(entry, now)
	local reason = entry.reason
	if reason == "secret" then return L.WHY_SECRET end
	if reason == "no-token" then return L.FOCUS_WHY_NO_TOKEN end
	if reason == "pending" then return L.FOCUS_WHY_PENDING end
	if reason == "stale" then return L.WHY_STALE:format(max(now - (entry.observedAt or now), 0)) end
	return ns.ThreatList.Why(reason)
end

-- Who holds the mob: the label, and the icon ("tank", "state-warning" or nil). With no watched holder, the name of its
-- target when the game gives it, "(not in the list)"; nil when nothing says.
local function holderOf(entry)
	local holder = entry.holder
	if holder then
		local tanks = (entry.designated or 0) > 0
		return unitLabel(holder), (not tanks or holder.role == "TANK") and "tank" or "state-warning"
	end
	local MT = ns.MobTracker
	local name = MT.TargetName and MT.TargetName(entry.key)
	if name then return L.FOCUS_OUTSIDE:format(name), nil end
	return nil, nil
end

-- The closest of the others: its name and the figure that goes with it ("87 %", "above the tank", nil).
local function closestOf(entry)
	local top = entry.top
	if not top then return nil, nil, nil end
	if entry.mode == "values" and entry.topPercent then
		return unitLabel(top), ("%d %%"):format(round(entry.topPercent)), nil
	end
	if entry.mode == "state" and entry.topSituation == 1 then return unitLabel(top), nil, L.FOCUS_ABOVE_TANK end
	return unitLabel(top), nil, nil
end

local function tagged(value, category) return L.TIP_TAGGED:format(value, L[CATEGORY_LABEL[category]]) end

-- The last values of a mob that is unknown now, from its rows, with their age (they never go in the row).
local function lastValues(entry, now)
	local rows, count = ns.MobTracker.Rows(entry.key)
	local best, at = nil, 0
	for i = 1, count or 0 do
		local row = rows[i]
		if row and row.mobKey == entry.key and row.mode == "values" and type(row.scaledPercent) == "number"
			and row.isTanking ~= true and (not best or row.scaledPercent > best.scaledPercent) then
			best, at = row, row.observedAt or 0
		end
	end
	if not best or at <= 0 then return nil end
	return L.FOCUS_TIP_LAST:format(max(now - at, 0), unitLabel(best), round(best.scaledPercent))
end

-- What a click on the row does (SPEC-07 §2.4).
local function clickHint(entry)
	local Tracker = ns.TargetTracker
	if Tracker.Pinned and Tracker.Pinned() == entry.key then return L.FOCUS_CLICK_UNPIN end
	if entry.monitored then return L.FOCUS_CLICK_MONITORED end
	if demoOn() then return L.FOCUS_CANNOT_DEMO end
	if not Tracker.CanPin(entry.key) then return L.FOCUS_CANNOT_IDENTITY end
	if entry.reason == "no-token" then return L.FOCUS_CANNOT_NO_TOKEN end
	return L.FOCUS_CLICK_PIN
end

-- The tooltip of a row (SPEC-07 §2.2): every value with its category, everything missing with its reason.
function FocusList.RowTooltip(entry, now)
	if not entry or not entry.key then return nil end
	now = now or Compat.Now()
	local name, classification = mobName(entry.key)
	local kind = classification and CLASSIFICATION[classification]
	local lines = { kind and (name .. " · " .. L[kind]) or name }
	if demoOn() then lines[#lines + 1] = L.MON_DEMO_TIP end
	local state = entry.state or "UNKNOWN"
	local unknown = state == "UNKNOWN"
	local def = Theme.State(STATE_ID[state])
	if unknown then
		lines[#lines + 1] = L.TIP_STATE_UNKNOWN:format(L[def.labelKey])
		lines[#lines + 1] = longWhy(entry, now)
		local last = lastValues(entry, now)
		if last then lines[#lines + 1] = last end
	else
		local category = entry.mode == "state" and "detected" or "calculated"
		lines[#lines + 1] = L.TIP_STATE:format(L[def.labelKey], L[CATEGORY_LABEL[category]])
		if RISK_WHY[entry.reason or ""] then lines[#lines + 1] = L[RISK_WHY[entry.reason]] end
		if entry.reason == "margin-unknown" then lines[#lines + 1] = L.FOCUS_TIP_MARGIN_UNKNOWN end
		if entry.mode == "state" then lines[#lines + 1] = L.TIP_STATE_ONLY end
		local holder = holderOf(entry)
		if holder then lines[#lines + 1] = L.FOCUS_TIP_HOLDER:format(tagged(holder, "detected"))
		else lines[#lines + 1] = L.FOCUS_TIP_HOLDER_UNWATCHED end
		local closest, percent, above = closestOf(entry)
		if closest then
			local text = closest
			if percent then text = closest .. ", " .. percent elseif above then text = closest .. ", " .. above end
			lines[#lines + 1] = L.FOCUS_TIP_CLOSEST:format(tagged(text, "detected"))
		else
			lines[#lines + 1] = L.FOCUS_TIP_NOBODY_CLOSE
		end
		if entry.margin then
			lines[#lines + 1] = L.FOCUS_TIP_MARGIN:format(tagged(signed(entry.margin), "calculated"))
		else
			lines[#lines + 1] = L.FOCUS_TIP_MARGIN:format(ns.ThreatList.Why(entry.mode == "state" and "state-only" or nil))
		end
		if entry.selfState then
			lines[#lines + 1] = L.FOCUS_TIP_SELF:format(L[Theme.State(STATE_ID[entry.selfState]).labelKey])
		end
	end
	local at = entry.observedAt or 0
	if at > 0 then lines[#lines + 1] = L.TIP_READ:format(max(now - at, 0)) end
	local source = entry.monitored and "monitored" or entry.source
	if SOURCE_LABEL[source or ""] then lines[#lines + 1] = L.FOCUS_TIP_SOURCE:format(L[SOURCE_LABEL[source]]) end
	lines[#lines + 1] = L.TIP_MODE:format(L[MODE_LABEL[entry.mode or "none"] or "MODULE_UNAVAILABLE"])
	lines[#lines + 1] = clickHint(entry)
	return lines
end

---------------------------------------------------------------------------------------------------------------------
-- Widgets
---------------------------------------------------------------------------------------------------------------------
local Focus = {}

local function setText(self, fs, text)
	if fs.shownText ~= text then
		fs.shownText = text
		fs:SetText(text)
		self.writes = self.writes + 1
	end
end

local function ink(fs, token)
	if fs.token ~= token then
		fs.token = token
		Theme.Text(fs, token)
	end
end

local function show(region, shown)
	if region:IsShown() ~= shown then region:SetShown(shown) end
end

local function line(parent, font, token, justify)
	local fs = Theme.NewText(parent, font, token)
	fs.token = token
	fs:SetJustifyH(justify or "LEFT")
	if fs.SetWordWrap then fs:SetWordWrap(false) end
	return fs
end

local function iconTexture(parent, name, size, token)
	local tex = parent:CreateTexture(nil, "ARTWORK")
	tex:SetTexture(Assets.textures.icons.path)
	tex:SetSize(size, size)
	tex:SetTexCoord(Assets.IconCoords(name))
	tex.name, tex.token = name, token
	Theme.Tint(tex, token)
	return tex
end

local function setIcon(tex, name, token)
	if tex.name ~= name then
		tex.name = name
		tex:SetTexCoord(Assets.IconCoords(name))
	end
	if token and tex.token ~= token then
		tex.token = token
		Theme.Tint(tex, token)
	end
end

local function setBadge(badge, id, width)
	if badge:GetState() ~= id then
		badge:SetState(id)
		if width then badge:SetWidth(width) end
	end
end

local function place(region, parent, x, width)
	region:ClearAllPoints()
	region:SetPoint("LEFT", parent, "LEFT", x, 0)
	if width then region:SetWidth(width) end
end

local function dash(w, from, to)
	local tex = w:CreateTexture(nil, "OVERLAY")
	tex:SetTexture(Assets.textures.dash.path, "REPEAT", "CLAMP")
	if tex.SetHorizTile then tex:SetHorizTile(true) end
	Theme.Tint(tex, "state-unknown")
	tex:SetPoint(from, w, from, 4, 0)
	tex:SetPoint(to, w, to, -4, 0)
	tex:SetHeight(1)
	tex:Hide()
	return tex
end

-- --- the pull bar ------------------------------------------------------------------------------------------------------

local function barTooltip(focus)
	local MT = tracker()
	if not MT then return nil end
	local lines = { focus.barTitle or L.FOCUS_PULL_ONLY }
	if demoOn() then lines[#lines + 1] = L.MON_DEMO_TIP end
	local reach, reason = MT.Reach()
	if FocusList.Reduced() and REACH_SENTENCE[reach] then lines[#lines + 1] = L[REACH_SENTENCE[reach]] end
	if FocusList.Reduced() and WHY_REASON[reason or ""] then lines[#lines + 1] = L[WHY_REASON[reason]] end
	local top = focus.top
	if top and top.key then
		lines[#lines + 1] = (mobName(top.key))
		if top.state == "UNKNOWN" then
			lines[#lines + 1] = longWhy(top, Compat.Now())
		elseif RISK_WHY[top.reason or ""] then
			lines[#lines + 1] = L[RISK_WHY[top.reason]]
		end
	end
	lines[#lines + 1] = L[focus.open and "FOCUS_BAR_CLOSE" or "FOCUS_BAR_OPEN"]
	return lines
end

-- The riskiest mob other than the monitored one, how many others are known and how many of them are unknown.
local function riskiest(list, n)
	local top, others, unknown = nil, 0, 0
	local Before = ns.MobRisk.Before
	for i = 1, n do
		local entry = list[i]
		if not entry.monitored then
			others = others + 1
			if (entry.state or "UNKNOWN") == "UNKNOWN" then unknown = unknown + 1 end
			if not top or Before(entry, top) then top = entry end
		end
	end
	return top, others, unknown
end

local function badgeWord(entry)
	if entry.reason == "aggro" then
		return L.FOCUS_BADGE_AGGRO:format(entry.holder and unitLabel(entry.holder) or L.MON_UNWATCHED)
	end
	if entry.reason == "close" then return L.FOCUS_BADGE_CLOSE end
	if entry.reason == "no-tank" then return L.FOCUS_BADGE_NO_TANK end
	if entry.reason == "near" then return L.FOCUS_BADGE_NEAR end
	return nil
end

function Focus:DrawBar(MT)
	local list, n = MT.List()
	local top, others, unknown = riskiest(list, n)
	self.top = top
	local title = n >= 2 and L.FOCUS_PULL:format(n) or L.FOCUS_PULL_ONLY
	self.barTitle = title
	setText(self, self.barLabel, title)

	local reach = MT.Reach()
	local state = top and (top.state or "UNKNOWN")
	local badge, word, token = nil, "", "text-1"
	if state == "DANGER" or state == "WARNING" then
		badge, word = STATE_ID[state], badgeWord(top) or ""
	elseif reach == "unknown" then
		word, token = L.FOCUS_READING, "text-3"
	elseif FocusList.Reduced() and REACH_SENTENCE[reach] then
		word, token = L[REACH_SENTENCE[reach]], "text-3"   -- never "All safe" when the pull cannot all be read
	elseif not top then
		word, token = L.FOCUS_READING, "text-3"
	elseif unknown == others then
		badge, word = "unknown", shortWhy(top.reason)
	elseif unknown > 0 then
		badge, word = "unknown", L.FOCUS_ALL_SAFE_UNKNOWN:format(unknown)
	else
		badge, word = "safe", L.FOCUS_ALL_SAFE
	end

	show(self.barBadge, badge ~= nil)
	if badge then setBadge(self.barBadge, badge) end
	local x = 18 + (self.barLabel:GetStringWidth() or 0) + 8
	if badge then
		place(self.barBadge, self.bar, x)
		x = x + (self.barBadge:GetWidth() or 0) + 6
	end
	ink(self.barWord, token)
	setText(self, self.barWord, word)
	place(self.barWord, self.bar, x, max(10, (self.contentWidth or 0) - x - 18))
	setIcon(self.barChevron, self.open and "arrow_down" or "chevron")
end

-- --- the list ---------------------------------------------------------------------------------------------------------

function Focus:Columns(width)
	local badge = self.badgeWidth
	local c = { badge = badge, showMargin = width >= 250 }
	c.nameX = 6 + badge + 4
	local right = 36 + 4                       -- the percentage
	if c.showMargin then right = right + 30 end
	local rest = max(40, width - c.nameX - right - 2)
	c.name = max(36, floor(rest * 0.4))
	c.middle = max(14, rest - c.name - 4)
	c.middleX = c.nameX + c.name + 4
	c.showHolderName = c.middle >= 70
	c.holderName = c.showHolderName and floor((c.middle - 14) / 2) or 0
	c.closestX = c.middleX + 14 + (c.showHolderName and c.holderName + 4 or 0)
	c.closest = max(0, c.middleX + c.middle - c.closestX)
	c.percentX = width - right + 2
	c.marginX = width - 32
	-- an unknown mob says why in the room of the holder, the closest and the figures
	c.unknownName = max(36, floor(rest * 0.4))
	c.whyX = c.nameX + c.unknownName + 4
	c.why = max(20, width - c.whyX - 16)
	return c
end

function Focus:Click(w)
	local key = w.key
	if not key then return end
	local Tracker = ns.TargetTracker
	Widgets.Tooltip.Hide()
	if Tracker.Pinned and Tracker.Pinned() == key then
		self.open = false
		Tracker.Pin(nil)
	else
		local entry = ns.MobTracker.Get(key)
		if entry and not entry.monitored then
			if not Tracker.Pin(key) then return end   -- the tooltip says why it cannot be followed
		end
		self.open = false
	end
	self.view:Redraw()
end

function Focus:NewRow(i)
	local focus = self
	local w = CreateFrame("Frame", nil, self.list)
	w:SetHeight(FocusList.ROW_HEIGHT)
	w:SetPoint("TOPLEFT", self.list, "TOPLEFT", 0, -(i - 1) * FocusList.ROW_HEIGHT)
	w:SetPoint("TOPRIGHT", self.list, "TOPRIGHT", 0, -(i - 1) * FocusList.ROW_HEIGHT)
	w.ring = Theme.Slice(w, "rr_ring_4", "accent", "BORDER")
	w.ring:SetAllPoints(w)
	w.ring:Hide()
	w.dashes = { dash(w, "TOPLEFT", "TOPRIGHT"), dash(w, "BOTTOMLEFT", "BOTTOMRIGHT") }
	w.stripe = Widgets.StateStripe(w)
	w.badge = Widgets.StateBadge(w)
	w.badge:SetPoint("LEFT", w, "LEFT", 6, 0)
	w.name = line(w, "Row", "text-1")
	w.sub = line(w, "Small", "text-3")
	w.holderIcon = iconTexture(w, "tank", 10, "text-2")
	w.holder = line(w, "Small", "text-2")
	w.closest = line(w, "Small", "text-2")
	w.percent = line(w, "RowMono", "text-1", "RIGHT")
	w.margin = line(w, "RowMono", "text-3", "RIGHT")
	w.why = line(w, "Small", "text-3")
	w:EnableMouse(true)
	Widgets.Tooltip.Attach(w, function(row)
		local entry = row.key and ns.MobTracker.Get(row.key)
		return entry and FocusList.RowTooltip(entry)
	end, "TOP")
	w:SetScript("OnMouseUp", function(row, button)
		if button == "LeftButton" then focus:Click(row) end
	end)
	self.rows[i] = w
	return w
end

function Focus:LayoutRow(w, unknown)
	local c = self.columns
	if not c or (w.layoutVersion == self.layoutVersion and w.unknownLayout == unknown) then return end
	w.layoutVersion, w.unknownLayout = self.layoutVersion, unknown
	w.badge:SetWidth(c.badge)
	w.nameWidth = unknown and c.unknownName or c.name
	place(w.holderIcon, w, c.middleX)
	place(w.holder, w, c.middleX + 14, max(1, c.holderName))
	place(w.closest, w, c.closestX, max(1, c.closest))
	place(w.percent, w, unknown and (self.contentWidth - 14) or c.percentX, unknown and 12 or 34)
	place(w.margin, w, c.marginX, 30)
	place(w.why, w, c.whyX, c.why)
	w.nameKey = nil
end

function Focus:FillRow(w, entry, now)
	local c = self.columns
	local state = entry.state or "UNKNOWN"
	local id = STATE_ID[state]
	local unknown = state == "UNKNOWN"
	w.key = entry.key
	self:LayoutRow(w, unknown)
	w.stripe:SetState(id)
	setBadge(w.badge, id, c.badge)
	show(w.ring, entry.monitored == true)
	show(w.dashes[1], unknown)
	show(w.dashes[2], unknown)

	local name, classification = mobName(entry.key)
	local sub = classification and CLASSIFICATION[classification] and L[CLASSIFICATION[classification]] or nil
	local age = (entry.observedAt or 0) > 0 and now - entry.observedAt or 0
	if not unknown and age > 1 then sub = L.FOCUS_SHORT_AGE:format(age) end
	ink(w.name, unknown and "text-3" or "text-1")
	setText(self, w.name, name)
	local withSub = sub ~= nil and not unknown and w.nameWidth >= 80
	show(w.sub, withSub)
	if withSub then setText(self, w.sub, sub) end
	local key = name .. (withSub and sub or "")
	if w.nameKey ~= key then
		w.nameKey = key
		local width = w.nameWidth
		if withSub then width = max(30, width - (w.sub:GetStringWidth() or 0) - 4) end
		place(w.name, w, c.nameX, 0)
		w.name:SetWidth(min((w.name:GetStringWidth() or 0) + 1, width))
		if withSub then place(w.sub, w, c.nameX + w.name:GetWidth() + 4) end
	end

	show(w.why, unknown)
	local holder, icon, closest, percent, above = nil, nil, nil, nil, nil
	if unknown then
		setText(self, w.why, shortWhy(entry.reason))
	else
		holder, icon = holderOf(entry)
		closest, percent, above = closestOf(entry)
	end
	show(w.holderIcon, not unknown and icon ~= nil)
	if icon then setIcon(w.holderIcon, icon, icon == "state-warning" and "state-warning" or "text-2") end
	show(w.holder, not unknown and c.showHolderName)
	if not unknown and c.showHolderName then setText(self, w.holder, holder or L.MON_DASH) end
	local closestText = closest and (above and (closest .. " · " .. above) or closest) or L.MON_DASH
	show(w.closest, not unknown and c.closest >= 20)
	if not unknown then setText(self, w.closest, closestText) end
	show(w.percent, true)
	ink(w.percent, unknown and "text-3" or "text-1")
	setText(self, w.percent, unknown and L.FOCUS_UNKNOWN_MARK or percent or L.MON_DASH)
	show(w.margin, c.showMargin and not unknown)
	if c.showMargin and not unknown then
		setText(self, w.margin, entry.margin and signed(entry.margin) or L.MON_DASH)
	end
	if Widgets.Tooltip.Owner() == w then
		Widgets.Tooltip.Show(w, FocusList.RowTooltip(entry, now), "TOP")
	end
end

-- Brings the order of the keys up to date (SPEC-07 §2.1): at once when a mob enters DANGER, else once a second; in
-- between the rows keep their places, the ones that left go and the new ones join at the end.
function Focus:Order(MT, now)
	local list, n = MT.List()
	local byKey, order = self.byKey, self.order
	for k in pairs(byKey) do byKey[k] = nil end
	local resort = self.forceSort or now - self.sortedAt >= FocusList.RESORT - 1e-6
	for i = 1, n do
		local entry = list[i]
		byKey[entry.key] = entry
		local danger = entry.state == "DANGER"
		if danger and not self.dangers[entry.key] then resort = true end
	end
	for k in pairs(self.dangers) do self.dangers[k] = nil end
	local kept = 0
	for i = 1, #order do
		local key = order[i]
		if byKey[key] then
			kept = kept + 1
			order[kept] = key
		end
	end
	for i = #order, kept + 1, -1 do order[i] = nil end
	local member = self.member
	for k in pairs(member) do member[k] = nil end
	for i = 1, kept do member[order[i]] = true end
	for i = 1, n do
		local entry = list[i]
		if entry.state == "DANGER" then self.dangers[entry.key] = true end
		if not member[entry.key] then order[#order + 1] = entry.key end
	end
	if resort or kept == 0 then
		local sorted = self.sorted
		for i = 1, n do sorted[i] = list[i] end
		for i = #sorted, n + 1, -1 do sorted[i] = nil end
		ns.MobRisk.Order(sorted, n)
		for i = 1, n do order[i] = sorted[i].key end
		self.sortedAt, self.forceSort = now, false
		self.sorts = self.sorts + 1
	end
	return order
end

function Focus:DrawList(MT)
	local now = Compat.Now()
	local order = self:Order(MT, now)
	local total = #order
	local places = max(1, min(FocusList.POOL, floor((self.listHeight or 0) / FocusList.ROW_HEIGHT)))
	local used, hidden = min(total, places), 0
	if total > places then
		used = places > 1 and places - 1 or places
		hidden = total - used
	end
	for i = 1, used do
		local w = self.rows[i] or self:NewRow(i)
		self:FillRow(w, self.byKey[order[i]], now)
		show(w, true)
	end
	for i = used + 1, #self.rows do
		self.rows[i].key = nil
		show(self.rows[i], false)
	end
	self.shownRows = used
	local more = hidden > 0 and places > 1
	show(self.more, more)
	if more then
		setText(self, self.more, L.MON_MORE:format(hidden))
		if self.moreAt ~= used then
			self.moreAt = used
			self.more:ClearAllPoints()
			self.more:SetPoint("TOPLEFT", self.list, "TOPLEFT", 8, -used * FocusList.ROW_HEIGHT - 4)
		end
	end
end

-- Draws the bar and, while it is open, the list. The view has checked that the bar is present.
function Focus:Draw()
	local MT = tracker()
	if not MT or not self.columns then return end
	self:DrawBar(MT)
	if self.open then self:DrawList(MT) end
	local owner = Widgets.Tooltip.Owner()
	if owner == self.bar then Widgets.Tooltip.Show(self.bar, barTooltip(self), "BOTTOM") end
end

-- The footer of the view while the list is open: "Reach: all · 6 of 8 · 0.4 s ago", in `warn` when reduced.
function Focus:Footer()
	local MT = tracker()
	if not MT then return "", "text-3" end
	local reach = MT.Reach()
	local _, n = MT.List()
	local word = L[REACH_SHORT[reach] or "FOCUS_REACH_SHORT_UNKNOWN"]
	local at = MT.lastTickAt
	local text
	if at then text = L.FOCUS_FOOTER:format(word, n, MT.Max(), max(Compat.Now() - at, 0))
	else text = L.FOCUS_FOOTER_NO_AGE:format(word, n, MT.Max()) end
	return text, FocusList.Reduced() and "warn" or "text-3"
end

-- Called by the view with its content width and the height the list gets.
function Focus:Layout(width, height)
	if width ~= self.contentWidth then
		self.contentWidth = width
		self.columns = self:Columns(width)
		self.layoutVersion = self.layoutVersion + 1
	end
	self.listHeight = height
end

-- Builds the bar and the list in `view` (UI/ThreatList.lua places and shows them).
function FocusList.Build(view)
	local f = { view = view, writes = 0, sorts = 0, layoutVersion = 0, open = false, sortedAt = -math.huge,
		forceSort = true, order = {}, sorted = {}, byKey = {}, member = {}, dangers = {}, rows = {}, shownRows = 0 }
	for name, fn in pairs(Focus) do f[name] = fn end
	local measure = Widgets.StateBadge(view)
	local widest = 0
	for _, id in ipairs(Theme.STATE_ORDER) do
		measure:SetState(id)
		widest = max(widest, measure:GetWidth())
	end
	measure:Hide()
	f.badgeWidth = widest

	local bar = CreateFrame("Frame", nil, view)
	bar:SetHeight(FocusList.BAR_HEIGHT)
	bar.fill = Theme.Slice(bar, "rr_fill_4", "surface-2", "BACKGROUND")
	bar.fill:SetAllPoints(bar)
	local icon = iconTexture(bar, "pull", 12, "text-2")
	icon:SetPoint("LEFT", bar, "LEFT", 4, 0)
	f.barIcon = icon
	f.barLabel = line(bar, "Small", "text-2")
	f.barLabel:SetPoint("LEFT", bar, "LEFT", 20, 0)
	f.barBadge = Widgets.StateBadge(bar)
	f.barBadge:Hide()
	f.barWord = line(bar, "Small", "text-1")
	f.barChevron = iconTexture(bar, "chevron", 10, "text-2")
	f.barChevron:SetPoint("RIGHT", bar, "RIGHT", -4, 0)
	bar:EnableMouse(true)
	bar:SetScript("OnMouseUp", function(_, button)
		if button ~= "LeftButton" then return end
		FocusList.SetOpen(not f.open)
	end)
	Widgets.Tooltip.Attach(bar, function() return barTooltip(f) end, "BOTTOM")
	bar:Hide()
	f.bar = bar

	local list = CreateFrame("Frame", nil, view)
	list:Hide()
	f.list = list
	f.more = line(list, "Row", "text-3")
	f.more:Hide()
	return f
end

-- Opens or closes the list of the view. Returns false when there is no pull bar to open it from.
function FocusList.SetOpen(open)
	local view = ns.ThreatList and ns.ThreatList.view
	local f = view and view.focus
	if not f then return false end
	if open and not FocusList.Present() then return false end
	if f.open ~= (open == true) then
		f.open = open == true
		f.forceSort = true
		Widgets.Tooltip.Hide()
		view:Redraw()
	end
	return true
end

function FocusList.IsOpen()
	local view = ns.ThreatList and ns.ThreatList.view
	return view ~= nil and view.focus ~= nil and view.focus.open == true
end

---------------------------------------------------------------------------------------------------------------------
-- Events (before UI/ThreatList.lua's, TOC order)
---------------------------------------------------------------------------------------------------------------------
if ns.Bus then
	local Bus = ns.Bus
	local function view() return ns.ThreatList and ns.ThreatList.view end
	Bus.On("MOBS_UPDATED", function()
		local v = view()
		if v and v.focus and switchOn() then v:MobsUpdated() end
	end)
	Bus.On("PIN_CHANGED", function()
		local v = view()
		if v and v.focus then v:Redraw() end
	end)
	-- another fight (or the demo's): nothing of the order or the list stays
	local function reset()
		local v = view()
		local f = v and v.focus
		if not f then return end
		f.open, f.forceSort = false, true
		for k in pairs(f.dangers) do f.dangers[k] = nil end
		for i = #f.order, 1, -1 do f.order[i] = nil end
	end
	Bus.On("COMBAT_STARTED", reset)
	Bus.On("DEMO_CHANGED", reset)
	Bus.On("CONFIG_CHANGED", function(path)
		if type(path) ~= "string" or path:sub(1, #MOBS_PREFIX) ~= MOBS_PREFIX then return end
		local v = view()
		if v and v.focus then v:Redraw() end
	end)
end

if ns.addon then ns.addon.FocusList = FocusList end
