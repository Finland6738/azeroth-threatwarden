-- Timeline (view): the widget of the Threat Timeline (SPEC-05 §4.8; ui-style 3.5; ADR 0003, 0017). Lua 5.1; no game API
-- is named here (ARC-02): CreateFrame, and Core/Compat.lua for the pointer. Behind the `timeline` switch (ADR 0014).
-- Threatwarden's own. The model is Data/Timeline.lua's: this file only draws it.
--
--   Timeline.Widget(parent, opts)  a frame, nil with the switch off. opts: legend, lanes (the state lanes of the series),
--                                  zoom (false: the wheel is left to the page), height (of Reflow), onSeek(t),
--                                  onSelect(a, b) (nil, nil: cleared), onHover(t) (nil: left), onView(a, b) (wheel zoom).
--     :SetModel(model), :SetView(a, b), :View(), :SetSeries(list), :SetCursor(t), :SetSelection(a, b)
--     :Layout(width, height) -> the height used (it grows when the lanes do not fit), :Reflow(width)
--   Pure parts (tests, the replay): X, T, YMax, Y, TickStep, Ticks, Dashes, Plan, MergeBands, LanePieces, SeriesTokens,
--   TimeText, PercentText, Icon, Info (the hover tooltip), SummaryLines, PoolLines (/atw debug).
--
-- What a line means: a segment is a Line region, solid (two readings taken at the recording's pace) or cut in dashes (an
-- estimate); where the model has no segment nothing is drawn, and the next piece starts at least BREAK_PX further. Gaps
-- are dashed bands, never a solid line. Regions come from pools that grow up to MAX_LINES and MAX_TEXTURES and never
-- shrink; a drawing that would pass a cap is made again with columns twice as wide, so nothing is left out. Without
-- Line regions the readings show as dots and bars, estimates as sparse dots. Nothing is drawn again unless the model,
-- the view, the series or the size changed; the only OnUpdate runs while the pointer is over the chart or dragging.
local ADDON_NAME, ns = ...
ns = ns or {}

local Timeline = ns.Timeline
local L, Widgets, Theme, Assets, Compat = ns.L, ns.Widgets, ns.Theme, ns.Assets, ns.Compat
local Session, Report = ns.Session, ns.Report
local type, pairs, ipairs, floor, ceil, max, min, abs, sqrt, sort, concat = type, pairs, ipairs, math.floor, math.ceil,
	math.max, math.min, math.abs, math.sqrt, table.sort, table.concat

Timeline.MAX_LINES = 3000
Timeline.MAX_TEXTURES = 1200
Timeline.DASH = { 4, 3 }        -- a dash and the space after it, in pixels
Timeline.DASH_MAX = 24          -- dashes of a segment at most: a longer one has longer dashes
Timeline.DASH_MIN = 3           -- a shorter estimate is left as a hole: one dash that short would read as solid
Timeline.BREAK_PX = 3           -- between the ends of two pieces that nothing joins
Timeline.HOVER_PX = 4           -- the nearest reading the tooltip takes
Timeline.DRAG_PX = 3            -- further than this a click is a selection
Timeline.SELECT_MIN = 10        -- tenths: the shortest selection
Timeline.Y_MIN, Timeline.Y_MAX = 110, 150
Timeline.TICK_STEPS = { 10, 20, 50, 100, 150, 300, 600, 1200, 3000, 6000 }   -- tenths
Timeline.TICK_PX = 60           -- at least this far apart
Timeline.LABEL_PX = 40          -- a name is written where this much is free
Timeline.CARD_HEIGHT = 140
Timeline.MARGIN, Timeline.RIGHT_PAD = 28, 4
Timeline.LEGEND_ROW, Timeline.CHART_MIN, Timeline.NOTE_MIN = 16, 80, 40
Timeline.HOLDER_HEIGHT, Timeline.LANE_HEIGHT, Timeline.LANE_GAP = 10, 6, 2
Timeline.TRACK_HEIGHT, Timeline.AXIS_HEIGHT = 16, 14
Timeline.ICON = 10
Timeline.NARROW_BAND = 8        -- a narrower dashed band shows one stripe in the middle (the texture would look solid)

-- Pool counts of every widget, for /atw debug.
Timeline.regions = { lines = 0, textures = 0, widened = 0 }

local CATEGORY_KEYS = { detected = "CAT_DETECTED", calculated = "CAT_CALCULATED", estimated = "CAT_ESTIMATED",
	predicted = "CAT_PREDICTED", unknown = "CAT_UNKNOWN" }
local CONFIDENCE_KEYS = { high = "CONF_HIGH", medium = "CONF_MEDIUM", low = "CONF_LOW" }
local STATE_TOKEN = { S = "state-safe", W = "state-warning", D = "state-danger" }
local STATE_PRIO = { S = 1, W = 2, U = 3, D = 4 }
local KIND_KEYS = { { "C", "TIMELINE_KIND_COMBAT" }, { "c", "TIMELINE_KIND_END" }, { "T", "TIMELINE_KIND_TARGET" },
	{ "S", "TIMELINE_KIND_STATE" }, { "A", "TIMELINE_KIND_HOLDER" }, { "M", "TIMELINE_KIND_MODE" },
	{ "G", "TIMELINE_KIND_PAUSE" }, { "D", "TIMELINE_KIND_DEATH" }, { "L", "TIMELINE_KIND_ALERT" },
	{ "H", "TIMELINE_KIND_COACH" }, { "N", "TIMELINE_KIND_ENCOUNTER" }, { "X", "TIMELINE_KIND_INTERRUPTED" },
	{ "Z", "TIMELINE_KIND_LIMIT" } }

local function on()
	local F = ns.Features
	return F ~= nil and F.On("timeline")
end

---------------------------------------------------------------------------------------------------------------------
-- The maths of the drawing
---------------------------------------------------------------------------------------------------------------------
-- The pixel of time `t` in a view [a, b] `width` pixels wide, and the time of a pixel.
function Timeline.X(t, a, b, width) return (t - a) * width / max(b - a, 1) end
function Timeline.T(x, a, b, width) return a + x * max(b - a, 1) / max(width, 1) end

-- The top of the percentage axis for the highest value in view: at least 110, the next ten, at most 150.
function Timeline.YMax(highest)
	return min(Timeline.Y_MAX, max(Timeline.Y_MIN, ceil((highest or 0) / 10) * 10))
end

-- Height above the bottom of the chart; a value past the top stays on the edge.
function Timeline.Y(percent, ymax, height) return min(max(percent, 0), ymax) * height / ymax end

function Timeline.TickStep(span, width)
	for _, step in ipairs(Timeline.TICK_STEPS) do
		if step * width / max(span, 1) >= Timeline.TICK_PX then return step end
	end
	return Timeline.TICK_STEPS[#Timeline.TICK_STEPS]
end

-- The times of the axis ticks of a view: out[1 .. out.n].
function Timeline.Ticks(a, b, width, out)
	out = out or {}
	local step = Timeline.TickStep(b - a, width)
	local n = 0
	for t = ceil(a / step) * step, b, step do
		n = n + 1
		out[n] = t
	end
	out.n, out.step = n, step
	return out
end

-- The dashes of a segment `length` pixels long, as pairs of distances from its start (out[2i-1], out[2i]); returns how
-- many. There is always a space at both ends, so a dashed segment never reads as solid.
function Timeline.Dashes(length, out)
	local dash, gap = Timeline.DASH[1], Timeline.DASH[2]
	if length < Timeline.DASH_MIN then return 0 end
	if length < dash + gap then
		out[1], out[2] = length * 0.25, length * 0.75
		return 1
	end
	local n = max(1, floor((length - gap) / (dash + gap)))
	if n > Timeline.DASH_MAX then
		n = Timeline.DASH_MAX
		dash = length * dash / (n * (dash + gap) + gap)
	end
	local space = (length - n * dash) / (n + 1)
	for i = 1, n do
		local from = i * space + (i - 1) * dash
		out[2 * i - 1], out[2 * i] = from, from + dash
	end
	return n
end

-- Merges the pixel intervals { x1, x2, item } (in order of x1) closer than `res`, each at least `res` wide:
-- out[1 .. out.n] = { x1, x2, item (the first), count }.
function Timeline.MergeBands(list, res, out)
	out = out or {}
	res = max(res or 1, 1)
	local n = 0
	for i = 1, list.n or #list do
		local it = list[i]
		local x1, x2 = it[1], max(it[2], it[1] + res)
		local band = out[n]
		if n > 0 and x1 - band[2] < res then
			band[2] = max(band[2], x2)
			band[4] = band[4] + 1
		else
			n = n + 1
			band = out[n]
			if not band then band = {} out[n] = band end
			band[1], band[2], band[3], band[4] = x1, x2, it[3], 1
		end
	end
	out.n = n
	return out
end

-- The pieces of a lane from intervals { x1, x2, key, prio } in order of x1: no two overlap, equal neighbours are one,
-- each at least `res` wide; where two share a pixel the higher `prio` keeps it. out[1 .. out.n] = { x1, x2, key, prio }.
function Timeline.LanePieces(list, res, out)
	out = out or {}
	res = max(res or 1, 1)
	local n = 0
	for i = 1, list.n or #list do
		local it = list[i]
		local x1, x2, key, prio = it[1], max(it[2], it[1] + res), it[3], it[4]
		local last = out[n]
		if n > 0 and last[3] == key and x1 - last[2] < res then
			last[2] = max(last[2], x2)
		else
			if n > 0 and x1 < last[2] then
				if prio > last[4] then
					last[2] = x1
					if last[2] - last[1] < res / 2 then n = n - 1 end
				else
					x1 = last[2]
				end
			end
			if x2 - x1 >= res / 2 then
				n = n + 1
				local piece = out[n]
				if not piece then piece = {} out[n] = piece end
				piece[1], piece[2], piece[3], piece[4] = x1, x2, key, prio
			end
		end
	end
	out.n = n
	return out
end

-- The colour of each series shown: the player is series-1, the others take the rest in order.
function Timeline.SeriesTokens(model, series)
	local out, tokens, hasMe = {}, Theme.SERIES, false
	for _, u in ipairs(series) do
		if model.info[u] and model.info[u].me then hasMe = true end
	end
	local nextToken = 2
	for j, u in ipairs(series) do
		if model.info[u] and model.info[u].me then
			out[j] = tokens[1]
		else
			out[j] = tokens[(nextToken - 1) % #tokens + 1]
			nextToken = nextToken + 1
			if hasMe and nextToken > #tokens then nextToken = 2 end
		end
	end
	return out
end

local function hasStates(se) return se ~= nil and #se.states > 0 end

-- What a widget shows of `model`, from its outcome (§4.6): chart (percentages) or note; lanes = { { holder = true },
-- { u = 3 }, ... }.
function Timeline.Plan(model, series, withLanes)
	local outcome = model.outcome
	local plan = { chart = outcome == "values" or outcome == "mixed", lanes = {} }
	if outcome == "none" then return plan end
	plan.lanes[1] = { holder = true }
	local taken, n = {}, 0
	local function add(u)
		if not taken[u] and n < Timeline.MAX_LANES and hasStates(model.units[u]) then
			taken[u], n = true, n + 1
			plan.lanes[#plan.lanes + 1] = { u = u }
		end
	end
	if outcome == "state" then
		for _, u in ipairs(model.lanes) do add(u) end
	else
		if withLanes then
			for _, u in ipairs(series) do add(u) end
		end
		if outcome == "mixed" then
			for _, u in ipairs(model.lanes) do
				if model.units[u].readings == 0 then add(u) end
			end
		end
	end
	return plan
end

---------------------------------------------------------------------------------------------------------------------
-- Words of the tooltip (ADR 0003: every value with its category)
---------------------------------------------------------------------------------------------------------------------
-- "1:12.4"
function Timeline.TimeText(t)
	t = floor((t or 0) + 0.5)
	local seconds = floor(t / 10)
	return ("%d:%02d.%d"):format(floor(seconds / 60), seconds % 60, t % 10)
end

-- A value of the column (tenths of a percent); its top is a lower bound.
function Timeline.PercentText(p)
	local text = L.TIMELINE_PERCENT:format(p / 10)
	if p >= Session.MAX_N then return L.REPORT_AT_LEAST:format(text) end
	return text
end

local function categoryName(category) return L[CATEGORY_KEYS[category] or "CAT_UNKNOWN"] end
local function tagged(text, category) return L.TIP_TAGGED:format(text, categoryName(category)) end

-- The icon of a marker and its token (§4.5); nil for a marker drawn as a line or a band.
function Timeline.Icon(mk)
	local k = mk.k
	if k == "C" then return "flag", "text-2" end
	if k == "A" then
		if mk.kind == "took" then return "warn", "state-danger" end
		return "tank", "text-2"
	end
	if k == "S" then
		if mk.state == "D" then return "state-danger", "state-danger" end
		if mk.state == "W" then return "state-warning", "state-warning" end
		return nil
	end
	if k == "D" then return "skull", "text-1" end
	if k == "L" then
		local token = "text-2"
		if mk.a == "w" then token = "state-warning"
		elseif mk.a == "d" or mk.a == "a" or mk.a == "l" then token = "state-danger" end
		return mk.c == "1" and "mute" or "bell", token
	end
	if k == "H" then return "coach", "text-2" end
	if k == "N" then return "star", "text-2" end
	if k == "X" then return "cross", "text-2" end
	if k == "Z" then return "warn", "text-2" end
	return nil
end

local function markerLine(model, mk)
	local text = Timeline.MarkerText(model, mk)
	if mk.confidence then
		return L.TIMELINE_TAGGED_CONFIDENCE:format(text, categoryName(mk.category),
			L[CONFIDENCE_KEYS[mk.confidence] or "CAT_UNKNOWN"])
	end
	return tagged(text, mk.category)
end

-- The interval of `list` ({ from, to, ... }) that holds `t`.
local function at(list, t)
	for _, i in ipairs(list) do
		if t >= i[1] and t < i[2] then return i end
	end
	return nil
end

-- The last reading of a series not after `t` (0: none).
local function lastAtOrBefore(se, dt, t)
	local lo, hi = 1, se.readings
	while lo <= hi do
		local mid = floor((lo + hi) / 2)
		if dt[se.rows[mid]] <= t then lo = mid + 1 else hi = mid - 1 end
	end
	return hi
end
Timeline.LastAtOrBefore = lastAtOrBefore

-- What a unit's series shows at `t`: a reading near it, the segment around it, or why there is none.
local function readingText(model, u, t, tolerance)
	local se, dt, dp = model.units[u], model.d.t, model.d.p
	local k = lastAtOrBefore(se, dt, t)
	local best, distance
	for _, c in ipairs({ k, k + 1 }) do
		if c >= 1 and c <= se.readings then
			local d = abs(dt[se.rows[c]] - t)
			if d <= tolerance and (not distance or d < distance) then best, distance = c, d end
		end
	end
	if best then
		local _, when, category = Timeline.Reading(model, u, best)
		return tagged(L.TIMELINE_READING:format(Timeline.PercentText(dp[se.rows[best]]), Timeline.TimeText(when)), category)
	end
	if k >= 1 and k < se.readings then
		local kind = se.segs[k + 1]
		if kind == "solid" or kind == "dashed" then
			local i, j = se.rows[k], se.rows[k + 1]
			local key = kind == "dashed" and "TIMELINE_ESTIMATE" or "TIMELINE_BETWEEN"
			return tagged(L[key]:format(Timeline.PercentText(dp[i]), Timeline.TimeText(dt[i]), Timeline.PercentText(dp[j]),
				Timeline.TimeText(dt[j])), Timeline.SEGMENT_CATEGORY[kind])
		end
	end
	local whole = at(model.gaps, t)
	if whole and whole[3] ~= "nomob" then return tagged(Timeline.GapText(whole), "unknown") end
	if not at(model.combat, t) then return tagged(L.TIMELINE_OUT_OF_COMBAT, "detected") end
	if whole then return tagged(Timeline.GapText(whole), "unknown") end
	local gap = at(se.unknown, t)
	if gap then return tagged(Timeline.GapText(gap), "unknown") end
	if not at(se.present, t) then return tagged(L.TIMELINE_NOT_LISTED, "detected") end
	local mode = at(model.modes, t)
	if mode and mode[3] == "state" then return tagged(L.TIMELINE_MODE_STATE, "detected") end
	return tagged(L.TIMELINE_NO_READING_HERE, "unknown")
end

-- The state of a unit at `t` with its basis; nil when it has none then.
local function stateText(model, u, t)
	local st = at(model.units[u].states, t)
	if not st then return nil end
	local word = L[Timeline.STATE_KEYS[st[3]] or "TIMELINE_STATE_UNKNOWN"]
	if st[3] == "U" then return tagged(word, "unknown") end
	local mode = at(model.modes, t)
	if mode and mode[3] == "state" then
		return tagged(L.TIMELINE_WITH:format(word, L.TIMELINE_GAME_STATE), "detected")
	end
	if model.warning and model.danger then
		word = L.TIMELINE_WITH:format(word, L.TIMELINE_THRESHOLDS:format(model.warning, model.danger))
	end
	return tagged(word, "calculated")
end

-- The hover tooltip at time q.t (§4.8): q = { t, a, b, width (of the plot), series, lanes, noLines }. At most as many
-- lines as the addon's tooltip shows.
function Timeline.Info(model, q)
	local a, b, width = q.a, q.b, max(q.width or 1, 1)
	local perPixel = max(b - a, 1) / width
	local limit = Widgets.Tooltip.MAX_LINES - (q.noLines and 1 or 0)
	local lines = { L.TIMELINE_AT:format(Timeline.TimeText(q.t)) }
	-- the last tenth of the axis belongs to what ends there
	local t = min(q.t, max(model.dur - 0.01, 0))

	if not at(model.combat, t) then
		lines[#lines + 1] = tagged(L.TIMELINE_OUT_OF_COMBAT, "detected")
	else
		local period, mode = at(model.mobs, t), at(model.modes, t)
		local mob
		if not period then
			local gap
			for _, g in ipairs(model.gaps) do
				if g[3] == "nomob" and t >= g[1] and t < g[2] then gap = g end
			end
			mob = tagged(gap and Timeline.GapText(gap) or L.TIMELINE_GAP_NOMOB, "unknown")
		else
			local named = model.mobInfo[period[3]] and model.mobInfo[period[3]].name
			mob = tagged(Timeline.MobName(model, period[3]), named and "detected" or "unknown")
		end
		lines[#lines + 1] = mob
		if mode then
			local mk = { k = "M", mode = mode[3], reason = mode[4] }
			lines[#lines + 1] = tagged(Timeline.MarkerText(model, mk), mode[3] == "none" and "unknown" or "detected")
		end
		if period then
			local holder
			for u, se in ipairs(model.units) do
				if at(se.holds, t) then holder = u break end
			end
			lines[#lines + 1] = holder
				and tagged(L.TIMELINE_HOLDS:format(Timeline.UnitName(model, holder)), "detected")
				or tagged(L.TIMELINE_HOLDER_UNKNOWN, "unknown")
		end
	end

	local seen, units = {}, {}
	for _, u in ipairs(q.series or {}) do
		if not seen[u] then seen[u], units[#units + 1] = true, { u, true } end
	end
	for _, lane in ipairs(q.lanes or {}) do
		if lane.u and not seen[lane.u] then seen[lane.u], units[#units + 1] = true, { lane.u, false } end
	end
	for i, entry in ipairs(units) do
		if #lines >= limit - 1 and i < #units then
			lines[#lines + 1] = L.TIMELINE_MORE:format(#units - i + 1)
			break
		end
		local u, series = entry[1], entry[2]
		local parts = {}
		if series then parts[1] = readingText(model, u, t, Timeline.HOVER_PX * perPixel) end
		local state = stateText(model, u, t)
		if state then parts[#parts + 1] = state end
		if #parts == 0 then parts[1] = tagged(L.TIMELINE_NOT_LISTED, "detected") end
		lines[#lines + 1] = L.TIMELINE_STATE:format(Timeline.UnitName(model, u), concat(parts, " · "))
	end

	local near = {}
	local groups = Timeline.Group(model.events, a, b, width)
	local px = Timeline.X(t, a, b, width)
	for i = 1, groups.n do
		local g = groups[i]
		if abs(g.x - px) <= Timeline.MARKER_PX / 2 + 1 then
			for j = 1, g.count do near[#near + 1] = g.items[j] end
		end
	end
	for _, mk in ipairs(model.events) do
		local shown = mk.place == "chart" or mk.kind == "holder" or (mk.kind == "cross" and seen[mk.u])
		if shown and abs(mk.t - t) <= Timeline.HOVER_PX * perPixel then near[#near + 1] = mk end
	end
	sort(near, function(x, y) return x.t < y.t end)
	local room = limit - #lines
	for i, mk in ipairs(near) do
		if i >= room and i < #near then
			if room > 0 then lines[#lines + 1] = L.TIMELINE_MORE:format(#near - i + 1) end
			break
		end
		if i > room then break end
		lines[#lines + 1] = markerLine(model, mk)
	end
	if q.noLines then lines[#lines + 1] = L.TIMELINE_NO_LINES end
	return lines
end

-- The words of Timeline.Summary: the interval, one line per series, the events by kind.
function Timeline.SummaryLines(model, summary)
	local lines = { L.TIMELINE_SELECTION:format(Timeline.TimeText(summary.a), Timeline.TimeText(summary.b),
		Report.Seconds(summary.dur)) }
	for j = 1, summary.n do
		local r = summary.series[j]
		local peak = r.maxP and tagged(L.TIMELINE_SUMMARY_PEAK:format(Timeline.PercentText(r.maxP),
			Timeline.TimeText(r.maxT)), r.maxCategory) or tagged(L.TIMELINE_SUMMARY_NO_READING, "unknown")
		local counts = tagged(L.TIMELINE_SUMMARY_COUNTS:format(r.readings, r.warningCross, r.dangerCross), "calculated")
		local function seconds(v)
			local text = Report.Seconds(v)
			if r.lower then return L.REPORT_AT_LEAST:format(text) end
			return text
		end
		local times = tagged(L.TIMELINE_SUMMARY_TIMES:format(seconds(r.warningTime), seconds(r.dangerTime),
			Report.Seconds(r.unknownTime)), r.category)
		lines[#lines + 1] = L.TIMELINE_STATE:format(Timeline.UnitName(model, r.u), concat({ peak, counts, times }, " · "))
	end
	local kinds = {}
	for _, kind in ipairs(KIND_KEYS) do
		local n = summary.events[kind[1]] or 0
		if n > 0 then kinds[#kinds + 1] = L[kind[2]]:format(n) end
	end
	lines[#lines + 1] = kinds[1] and tagged(L.TIMELINE_SUMMARY_EVENTS:format(concat(kinds, ", ")), "calculated")
		or tagged(L.TIMELINE_SUMMARY_NO_EVENTS, "calculated")
	return lines
end

---------------------------------------------------------------------------------------------------------------------
-- The pools (§4.8): regions of the widget itself, placed from its top left corner (y grows downwards)
---------------------------------------------------------------------------------------------------------------------
local Chart = {}

local function take(self, pool, cap, create, counter)
	local i = pool.used + 1
	local region = pool.list[i]
	if not region then
		if i > cap then
			self.over = true
			return nil
		end
		region = create(self)
		pool.list[i] = region
		Timeline.regions[counter] = Timeline.regions[counter] + 1
	end
	pool.used = i
	region:ClearAllPoints()
	region:Show()
	return region
end

local function newTexture(self) return Theme.Crisp(self:CreateTexture(nil, "ARTWORK")) end
local function newLine(self) return self:CreateLine(nil, "ARTWORK") end

local function texture(self, kind, layer, sub)
	local t = take(self, self.textures, Timeline.MAX_TEXTURES, newTexture, "textures")
	if not t then return nil end
	t:SetDrawLayer(layer, sub or 0)
	t.kind, t.u = kind, nil
	return t
end

local function place(self, t, x, y, w, h)
	t:SetPoint("TOPLEFT", self, "TOPLEFT", x, -y)
	t:SetSize(max(w, 0.5), max(h, 0.5))
end

-- A solid rectangle.
local function rect(self, kind, x, y, w, h, token, alpha, layer, sub)
	local t = texture(self, kind, layer or "ARTWORK", sub)
	if not t then return nil end
	t:SetHorizTile(false)
	t:SetTexCoord(0, 1, 0, 1)
	Theme.Paint(t, "fill", token, alpha)
	t.token = token
	place(self, t, x, y, w, h)
	return t
end

-- A dashed band (§3.5): surface-2 with the `dash` texture tinted state-unknown at half strength; a narrow one shows a
-- single stripe with a space on each side.
local function dashed(self, kind, x, y, w, h, layer, sub)
	rect(self, kind .. "-back", x, y, w, h, "surface-2", 1, layer, sub)
	if w < Timeline.NARROW_BAND then
		local stripe = w / 2
		return rect(self, kind, x + (w - stripe) / 2, y, stripe, h, "state-unknown", 0.5, layer, (sub or 0) + 1)
	end
	local t = texture(self, kind, layer, (sub or 0) + 1)
	if not t then return nil end
	t:SetTexture(Assets.textures.dash.path, "REPEAT", "REPEAT")
	t:SetHorizTile(true)
	t:SetTexCoord(0, 1, 0, 1)
	Theme.Paint(t, "tint", "state-unknown", 0.5)
	t.token = "state-unknown"
	place(self, t, x, y, w, h)
	return t
end

local function icon(self, kind, name, x, y, token, size)
	local t = texture(self, kind, "OVERLAY", 1)
	if not t then return nil end
	t:SetHorizTile(false)
	t:SetTexture(Assets.textures.icons.path)
	t:SetTexCoord(Assets.IconCoords(name))
	Theme.Paint(t, "tint", token)
	t.token, t.icon = token, name
	size = size or Timeline.ICON
	t:SetPoint("CENTER", self, "TOPLEFT", x, -y)
	t:SetSize(size, size)
	return t
end

local function line(self, kind, x1, y1, x2, y2, token, thickness, sub)
	local l = take(self, self.lines, Timeline.MAX_LINES, newLine, "lines")
	if not l then return nil end
	l:SetDrawLayer("ARTWORK", sub or 0)
	Theme.Paint(l, "fill", token)
	l.kind, l.token, l.u = kind, token, nil
	l:SetThickness(thickness)
	l:SetStartPoint("TOPLEFT", self, x1, -y1)
	l:SetEndPoint("TOPLEFT", self, x2, -y2)
	return l
end

-- A text; `width` cuts it, nil leaves it its own width.
local function label(self, kind, font, token, str, x, y, width, point)
	local pool = self.texts
	local i = pool.used + 1
	local fs = pool.list[i]
	if not fs then
		fs = Theme.NewText(self, font, token)
		fs:SetWordWrap(false)
		pool.list[i] = fs
	end
	pool.used = i
	fs:SetFontObject(Theme.Font(font))
	Theme.Text(fs, token)
	fs.kind, fs.token = kind, token
	fs:SetJustifyH(point == "TOPRIGHT" and "RIGHT" or point == "TOP" and "CENTER" or "LEFT")
	fs:SetWordWrap(false)
	fs:SetWidth(0)
	fs:SetText(str)
	if width then fs:SetWidth(width) end
	fs:ClearAllPoints()
	fs:SetPoint(point or "TOPLEFT", self, "TOPLEFT", x, -y)
	fs:Show()
	return fs
end

local function release(pool)
	for i = pool.used + 1, #pool.list do pool.list[i]:Hide() end
end

---------------------------------------------------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------------------------------------------------
local BAND_TEXT = 16   -- where a band writes its reason: under the names of the mobs at the top
local THRESHOLD_ROOM = 30
local dashes = {}

-- A segment between two points, clipped to the plot, solid or in dashes; without Line regions only an estimate shows,
-- as sparse dots.
local function segment(self, g, u, kind, x1, y1, x2, y2, token, thickness, sub)
	if x2 < x1 or x2 < g.left or x1 > g.right then return end
	if x1 < g.left then
		if x2 > x1 then y1 = y1 + (y2 - y1) * (g.left - x1) / (x2 - x1) end
		x1 = g.left
	end
	if x2 > g.right then
		if x2 > x1 then y2 = y1 + (y2 - y1) * (g.right - x1) / (x2 - x1) end
		x2 = g.right
	end
	local dx, dy = x2 - x1, y2 - y1
	local length = sqrt(dx * dx + dy * dy)
	if length <= 0 then return end
	if not self.useLines then
		if kind ~= "dashed" or length < Timeline.DASH_MIN then return end
		local n = min(Timeline.DASH_MAX, max(1, floor(length / (Timeline.DASH[1] + Timeline.DASH[2]))))
		for i = 1, n do
			local f = i / (n + 1)
			local t = rect(self, "estimate", x1 + dx * f - 0.5, y1 + dy * f - 0.5, 1, 1, token, 1, "ARTWORK", sub)
			if t then t.u = u end
		end
		return
	end
	if kind == "solid" then
		local l = line(self, "solid", x1, y1, x2, y2, token, thickness, sub)
		if l then l.u = u end
		return
	end
	for i = 1, Timeline.Dashes(length, dashes) do
		local from, to = dashes[2 * i - 1] / length, dashes[2 * i] / length
		local l = line(self, "dash", x1 + dx * from, y1 + dy * from, x1 + dx * to, y1 + dy * to, token, thickness, sub)
		if l then l.u = u end
	end
end

local function dot(self, u, x, y, token, size, sub)
	local t = rect(self, "dot", x - size / 2, y - size / 2, size, size, token, 1, "ARTWORK", sub)
	if t then t.u = u end
end

local function fillPiece(p, f, l, lo, hi, xin, xout, bar)
	p.f, p.l, p.lo, p.hi, p.xin, p.xout, p.bar = f, l, lo, hi, xin, xout, bar
	return p
end

-- One piece of a series: a bar from its lowest to its highest reading, a flat run, or a lone reading as a dot.
local function drawPiece(self, g, s, p, joinIn, joinOut)
	local dp, rows = self.model.d.p, s.se.rows
	local low, high = dp[rows[p.lo]], dp[rows[p.hi]]
	local ylow, yhigh = g.y(low), g.y(high)
	local alone = joinIn ~= "solid" and joinOut ~= "solid"
	local bar = min(max(p.bar, g.left), g.right)
	if high ~= low then
		if self.useLines then
			local l = line(self, "bar", bar, ylow, bar, yhigh, s.token, g.px, s.sub)
			if l then l.u = s.u end
		else
			local t = rect(self, "bar", bar - g.px / 2, yhigh, g.px, ylow - yhigh, s.token, 1, "ARTWORK", s.sub)
			if t then t.u = s.u end
		end
	elseif not self.useLines then
		dot(self, s.u, bar, ylow, s.token, 2, s.sub)
	elseif p.l > p.f and p.xout - p.xin >= 1 then
		segment(self, g, s.u, "solid", p.xin, ylow, p.xout, ylow, s.token, s.thickness, s.sub)
	elseif alone then
		dot(self, s.u, bar, ylow, s.token, 2, s.sub)
	end
	if high > g.ymax * 10 then
		local column = floor(bar - g.left)
		if not g.arrows[column] then
			g.arrows[column] = true
			icon(self, "above", "arrow_up", bar, g.top + 4, "text-1", 8)
		end
	end
end

local pieceA, pieceB = {}, {}

-- The lowest and highest of the readings from..to.
local function extremes(dp, rows, from, to)
	local lo, hi = from, from
	for k = from + 1, to do
		if dp[rows[k]] < dp[rows[lo]] then lo = k end
		if dp[rows[k]] > dp[rows[hi]] then hi = k end
	end
	return lo, hi
end

local function drawSeries(self, g, s, col)
	local se, d = s.se, self.model.d
	local dt, dp, rows, segs = d.t, d.p, se.rows, se.segs
	local function px(k) return g.left + Timeline.X(dt[rows[k]], g.a, g.b, g.width) end
	local function py(k) return g.y(dp[rows[k]]) end
	local held, heldJoin, spare = nil, "none", pieceA

	-- The piece `p` follows the one held: the segment between them, then the held piece itself.
	local function push(p)
		local join = segs[p.f]
		if held then
			if join ~= "solid" and p.xin - held.xout < Timeline.BREAK_PX then
				local mid, half = (held.xout + p.xin) / 2, Timeline.BREAK_PX / 2
				held.xout, held.bar = min(held.xout, mid - half), min(held.bar, mid - half)
				p.xin, p.bar = max(p.xin, mid + half), max(p.bar, mid + half)
				p.xout = max(p.xout, p.xin)
			end
			if join ~= "none" then
				segment(self, g, s.u, join, held.xout, py(held.l), p.xin, py(p.f), s.token, s.thickness, s.sub)
			end
			drawPiece(self, g, s, held, heldJoin, join)
		elseif p.f > 1 and join ~= "none" then   -- the segment that enters the view
			segment(self, g, s.u, join, px(p.f - 1), py(p.f - 1), p.xin, py(p.f), s.token, s.thickness, s.sub)
		end
		held, heldJoin = p, join
		spare = p == pieceA and pieceB or pieceA
	end

	local buckets = self.viewOut.buckets
	local columnWidth = g.width / buckets
	local lastShown = nil
	for c = 1, buckets do
		local first, last = col.first[c], col.last[c]
		if first ~= 0 then
			lastShown = last
			local x0 = g.left + (c - 1) * columnWidth
			if col.cut[c] or col.dash[c] then
				-- Two pieces: the solid run the column starts with at its left edge, the rest at its right edge. Never
				-- more, so that wider columns always mean fewer regions; the lowest and highest of both are kept.
				local second = first + 1
				while second <= last and segs[second] == "solid" do second = second + 1 end
				local lo, hi = extremes(dp, rows, first, second - 1)
				push(fillPiece(spare, first, second - 1, lo, hi, x0, x0, x0))
				lo, hi = extremes(dp, rows, second, last)
				local x = x0 + columnWidth
				push(fillPiece(spare, second, last, lo, hi, x, x, x))
			elseif first == last then
				local x = px(first)
				push(fillPiece(spare, first, last, first, first, x, x, x))
			else
				push(fillPiece(spare, first, last, col.lo[c], col.hi[c], px(first), px(last), x0 + columnWidth / 2))
			end
		end
	end

	if held then
		local after = held.l + 1
		local join = after <= se.readings and segs[after] or "none"
		if join ~= "none" then   -- the segment that leaves the view
			segment(self, g, s.u, join, held.xout, py(held.l), px(after), py(after), s.token, s.thickness, s.sub)
		end
		drawPiece(self, g, s, held, heldJoin, join)
	else                         -- no reading in view: the segment that crosses it
		local k = lastAtOrBefore(se, dt, g.a) + 1
		if k > 1 and k <= se.readings and segs[k] ~= "none" then
			segment(self, g, s.u, segs[k], px(k - 1), py(k - 1), px(k), py(k), s.token, s.thickness, s.sub)
		end
	end

	-- the name at the end of the line, where there is room
	if lastShown then
		local x, y = px(lastShown), py(lastShown)
		local top = min(max(y - 6, g.top), g.top + g.height - 12)
		local limit = g.right
		for _, other in ipairs(g.thresholds) do   -- the threshold labels keep their place at the right end
			if abs(other - top) < 12 then limit = g.right - THRESHOLD_ROOM end
		end
		if limit - x >= Timeline.LABEL_PX + 4 then
			for _, other in ipairs(g.names) do
				if abs(other - y) < 11 then return end
			end
			g.names[#g.names + 1] = y
			label(self, "name", "Small", "text-2", Timeline.UnitName(self.model, s.u), x + 4, top, limit - x - 4)
		end
	end
end

local items, bands, pieces = {}, {}, {}

local function addItem(x1, x2, key, prio)
	local n = items.n + 1
	local it = items[n]
	if not it then it = {} items[n] = it end
	it[1], it[2], it[3], it[4] = x1, x2, key, prio
	items.n = n
end

-- Adds the part of [from, to] inside the view to `items`, in pixels.
local function addInView(g, from, to, key, prio)
	if to <= g.a or from >= g.b then return end
	addItem(g.left + Timeline.X(max(from, g.a), g.a, g.b, g.width), g.left + Timeline.X(min(to, g.b), g.a, g.b, g.width),
		key, prio)
end

local function sortItems()
	for i = #items, items.n + 1, -1 do items[i] = nil end
	sort(items, function(x, y)
		if x[1] ~= y[1] then return x[1] < y[1] end
		return x[2] < y[2]
	end)
end

local function drawLegend(self, width)
	local model = self.model
	local x, y = 0, 0
	for j, u in ipairs(self.shown) do
		local se = model.units[u]
		local name = label(self, "legend", "Small", "text-1", Timeline.UnitName(model, u), 0, 0)
		local peak = label(self, "legend-max", "MonoSmall", "text-2",
			se.maxP and Timeline.PercentText(se.maxP) or L.REPORT_UNKNOWN, 0, 0)
		local nameWidth, peakWidth = name:GetStringWidth(), peak:GetStringWidth()
		local held = se.held > 0
		local need = 16 + nameWidth + 4 + peakWidth + (held and 14 or 0)
		if x > 0 and x + need > width then x, y = 0, y + Timeline.LEGEND_ROW end
		local mark = rect(self, "legend-mark", x, y + 7, 12, 2, self.tokens[j])
		if mark then mark.u = u end
		local nx = x + 16
		if held then
			icon(self, "legend-tank", "tank", nx + 5, y + 8, "text-2")
			nx = nx + 14
		end
		name:ClearAllPoints()
		name:SetPoint("TOPLEFT", self, "TOPLEFT", nx, -(y + 2))
		peak:ClearAllPoints()
		peak:SetPoint("TOPLEFT", self, "TOPLEFT", nx + nameWidth + 4, -(y + 2))
		x = x + need + 12
	end
	return #self.shown > 0 and y + Timeline.LEGEND_ROW or 0
end

local function drawChart(self, g, res, buckets)
	local model = self.model

	-- the readings per column, and with them the top of the axis
	Timeline.View(model, g.a, g.b, buckets, self.shown, self.viewOut)
	local highest = 0
	for j, u in ipairs(self.shown) do
		local col, se = self.viewOut[j], model.units[u]
		for c = 1, self.viewOut.buckets do
			local hi = col.hi[c]
			if hi ~= 0 then highest = max(highest, model.d.p[se.rows[hi]]) end
		end
	end
	g.ymax = Timeline.YMax(highest / 10)

	-- out of combat: a plain band, no gap
	items.n = 0
	local from = 0
	for _, p in ipairs(model.combat) do
		addInView(g, from, p[1], "out", 1)
		from = p[2]
	end
	addInView(g, from, model.dur, "out", 1)
	sortItems()
	Timeline.MergeBands(items, res, bands)
	for i = 1, bands.n do
		local band = bands[i]
		local w = min(band[2], g.right) - band[1]
		rect(self, "out", band[1], g.top, w, g.height, "surface-2", 1, "BACKGROUND", 1)
		if w >= Timeline.LABEL_PX then
			label(self, "band", "Small", "text-3", L.TIMELINE_OUT_OF_COMBAT, band[1] + 2, g.top + BAND_TEXT, w - 4)
		end
	end

	-- the bands of a mixed fight: state only
	if model.outcome == "mixed" then
		items.n = 0
		for _, mode in ipairs(model.modes) do
			if mode[3] == "state" then
				for _, p in ipairs(model.combat) do
					local m1, m2 = max(mode[1], p[1]), min(mode[2], p[2])
					if m2 > m1 then addInView(g, m1, m2, mode, 1) end
				end
			end
		end
		sortItems()
		Timeline.MergeBands(items, res, bands)
		for i = 1, bands.n do
			local band = bands[i]
			local w = min(band[2], g.right) - band[1]
			rect(self, "state-band", band[1], g.top, w, g.height, "surface-3", 1, "BACKGROUND", 2)
			if w >= Timeline.LABEL_PX and band[4] == 1 then
				label(self, "band", "Small", "text-2", Timeline.ModeText(band[3]), band[1] + 2, g.top + BAND_TEXT, w - 4)
			end
		end
	end

	-- the gaps of the whole chart: dashed bands with their reason
	items.n = 0
	for _, gap in ipairs(model.gaps) do addInView(g, gap[1], gap[2], gap, 1) end
	sortItems()
	Timeline.MergeBands(items, res, bands)
	for i = 1, bands.n do
		local band = bands[i]
		local w = min(band[2], g.right) - band[1]
		dashed(self, "gap", band[1], g.top, w, g.height, "BACKGROUND", 3)
		if w >= Timeline.LABEL_PX and band[4] == 1 then
			label(self, "band", "Small", "text-2", Timeline.GapText(band[3]), band[1] + 2, g.top + BAND_TEXT, w - 4)
		end
	end

	-- grid, the 100 % line and the thresholds the session recorded
	for _, percent in ipairs({ 0, 50, 100 }) do
		local y = g.y(percent * 10)
		rect(self, "grid", g.left, y, g.width, g.px, percent == 100 and "border-strong" or "border-subtle", 1, "BORDER", 1)
		label(self, "y-axis", "MonoSmall", "text-3", L.SET_PERCENT:format(percent), g.left - 2, y - 6, nil, "TOPRIGHT")
	end
	if model.warning and model.danger then
		for _, entry in ipairs({ { model.warning, "state-warning", 1 }, { model.danger, "state-danger", -12 } }) do
			local y = g.y(entry[1] * 10)
			rect(self, "threshold", g.left, y, g.width, g.px, entry[2], 1, "BORDER", 2)
			g.thresholds[#g.thresholds + 1] = y + entry[3]
			label(self, "threshold-label", "MonoSmall", "text-3", L.SET_PERCENT:format(entry[1]), g.right, y + entry[3], nil,
				"TOPRIGHT")
		end
	end

	-- the changes of mob, with the name where there is room
	items.n = 0
	for _, mk in ipairs(model.events) do
		if mk.k == "T" and mk.m > 0 and mk.t >= g.a and mk.t <= g.b then
			addItem(g.left + Timeline.X(mk.t, g.a, g.b, g.width), 0, mk.m, 1)
		end
	end
	local lastX
	for i = 1, items.n do
		local x, m = items[i][1], items[i][3]
		if not lastX or x - lastX >= res then
			rect(self, "mob", x, g.top, g.px, g.height, "border-strong", 1, "BORDER", 3)
			lastX = x
		end
		local room = (i < items.n and items[i + 1][1] or g.right) - x
		if room >= Timeline.LABEL_PX then
			label(self, "mob-name", "Small", "text-3", Timeline.MobName(model, m), x + 2, g.top + 2, room - 4)
		end
	end
end

-- The icons of the crossings (§4.5): on the series at the nearest reading within `join`, else on the unit's lane.
local function drawCrossings(self, g, res, laneY)
	local model = self.model
	local shown = {}
	for _, u in ipairs(self.shown) do shown[u] = true end
	local lastAt = {}
	local spacing = max(Timeline.MARKER_PX, res * 2)
	for _, mk in ipairs(model.events) do
		if mk.kind == "cross" and mk.t >= g.a and mk.t <= g.b then
			local u = mk.u
			local se = model.units[u]
			local x, y = g.left + Timeline.X(mk.t, g.a, g.b, g.width), nil
			if se and g.y and shown[u] then
				local k = lastAtOrBefore(se, model.d.t, mk.t)
				local best, distance
				for _, c in ipairs({ k, k + 1 }) do
					if c >= 1 and c <= se.readings then
						local t = model.d.t[se.rows[c]]
						if abs(t - mk.t) <= model.join and t >= g.a and t <= g.b and (not distance or abs(t - mk.t) < distance) then
							best, distance = c, abs(t - mk.t)
						end
					end
				end
				if best then
					x, y = g.left + Timeline.X(model.d.t[se.rows[best]], g.a, g.b, g.width), g.y(model.d.p[se.rows[best]])
				end
			end
			if not y then y = laneY[u] end
			if not y and g.y and shown[u] then y = g.top + g.height - Timeline.ICON / 2 end
			if y and (not lastAt[u] or x - lastAt[u] >= spacing) then
				local name, token = Timeline.Icon(mk)
				if name then
					local t = icon(self, "cross", name, x, y, token)
					if t then t.u = u end
					lastAt[u] = x
				end
			end
		end
	end
end

local function drawLanes(self, g, res, lanes, top)
	local model, laneY = self.model, {}
	local tokenOf = {}
	for j, u in ipairs(self.shown) do tokenOf[u] = self.tokens[j] end
	local y = top
	for _, lane in ipairs(lanes) do
		local height = lane.holder and Timeline.HOLDER_HEIGHT or Timeline.LANE_HEIGHT
		items.n = 0
		if lane.holder then
			for u, se in ipairs(model.units) do
				for _, h in ipairs(se.holds) do addInView(g, h[1], h[2], u, 1) end
			end
		else
			laneY[lane.u] = y + height / 2
			for _, st in ipairs(model.units[lane.u].states) do
				addInView(g, st[1], st[2], st[3], STATE_PRIO[st[3]] or 3)
			end
		end
		sortItems()
		Timeline.LanePieces(items, res, pieces)
		for i = 1, pieces.n do
			local p = pieces[i]
			local w = min(p[2], g.right) - p[1]
			if lane.holder then
				local t = rect(self, "holder", p[1], y, w, height, tokenOf[p[3]] or "text-3", 1, "ARTWORK", 0)
				if t then t.u = p[3] end
			elseif STATE_TOKEN[p[3]] then
				local t = rect(self, "lane", p[1], y, w, height, STATE_TOKEN[p[3]], 1, "ARTWORK", 0)
				if t then t.u = lane.u end
			else
				local t = dashed(self, "lane-unknown", p[1], y, w, height, "ARTWORK", 1)
				if t then t.u = lane.u end
			end
		end
		-- what is not known is drawn over it, dashed: the unit's gaps and the gaps of the whole chart
		items.n = 0
		for _, gap in ipairs(model.gaps) do
			if gap[3] ~= "nomob" then addInView(g, gap[1], gap[2], gap, 1) end
		end
		if lane.u then
			for _, gap in ipairs(model.units[lane.u].unknown) do addInView(g, gap[1], gap[2], gap, 1) end
		end
		sortItems()
		Timeline.MergeBands(items, res, bands)
		for i = 1, bands.n do
			local band = bands[i]
			local t = dashed(self, "lane-gap", band[1], y, min(band[2], g.right) - band[1], height, "ARTWORK", 3)
			if t then t.u = lane.u end
		end
		if lane.holder then
			local lastAt
			for _, mk in ipairs(model.events) do
				if mk.k == "A" and mk.t >= g.a and mk.t <= g.b then
					local x = g.left + Timeline.X(mk.t, g.a, g.b, g.width)
					if not lastAt or x - lastAt >= max(Timeline.ICON, res * 2) then
						local name, token = Timeline.Icon(mk)
						icon(self, "holder-icon", name, x, y + height / 2, token)
						lastAt = x
					end
				end
			end
		end
		y = y + height + Timeline.LANE_GAP
	end
	return laneY
end

local function drawTrack(self, g, top)
	local groups = Timeline.Group(self.model.events, g.a, g.b, g.width, self.groups)
	for i = 1, groups.n do
		local group = groups[i]
		local name, token = Timeline.Icon(group.top)
		if name then
			local x = min(max(g.left + group.x, g.left + Timeline.ICON / 2), g.right - Timeline.ICON / 2)
			icon(self, "marker", name, x, top + Timeline.TRACK_HEIGHT / 2, token)
			if group.count > 1 then
				label(self, "count", "Badge", "text-2", L.TIMELINE_GROUP:format(group.count), x + 5, top)
			end
		end
	end
end

local ticks = {}

local function drawAxis(self, g, top)
	Timeline.Ticks(g.a, g.b, g.width, ticks)
	for i = 1, ticks.n do
		local x = g.left + Timeline.X(ticks[i], g.a, g.b, g.width)
		rect(self, "tick", x, top, g.px, 3, "border-strong", 1, "BORDER", 1)
		local centred = x > g.left + 14 and x < g.right - 14
		label(self, "x-axis", "MonoSmall", "text-3", Report.Time(ticks[i]), x, top + 3, nil,
			centred and "TOP" or x <= g.left + 14 and "TOPLEFT" or "TOPRIGHT")
	end
end

-- One drawing with columns `bucket` pixels wide. Sets self.over when a pool reached its cap.
local function drawOnce(self, bucket)
	self.over = false
	self.textures.used, self.lines.used, self.texts.used = 0, 0, 0
	local model, width = self.model, self.width
	local left, right = Timeline.MARGIN, max(Timeline.MARGIN + 20, width - Timeline.RIGHT_PAD)
	local plot = right - left
	local plan = Timeline.Plan(model, self.shown, self.opts.lanes)
	local res = bucket / 2
	local top = 0
	if self.opts.legend and plan.chart then top = drawLegend(self, width) + 2 end

	local lanesHeight = 0
	for _, lane in ipairs(plan.lanes) do
		lanesHeight = lanesHeight + (lane.holder and Timeline.HOLDER_HEIGHT or Timeline.LANE_HEIGHT) + Timeline.LANE_GAP
	end
	local fixed = top + lanesHeight + Timeline.TRACK_HEIGHT + Timeline.AXIS_HEIGHT + 2
	local chartHeight = max(plan.chart and Timeline.CHART_MIN or Timeline.NOTE_MIN, (self.wanted or 0) - fixed)
	local g = { a = self.a, b = self.b, left = left, right = right, width = plot, top = top, height = chartHeight,
		px = Theme.Px(1, self), arrows = {}, names = {}, thresholds = {}, ymax = Timeline.Y_MIN }
	local buckets = min(max(floor(plot / bucket), 1), Timeline.MAX_BUCKETS)

	if plan.chart then
		-- tenths of a percent -> pixels from the top of the widget
		g.y = function(p) return g.top + g.height - Timeline.Y(p / 10, g.ymax, g.height) end
		drawChart(self, g, res, buckets)
		for j, u in ipairs(self.shown) do
			local me = model.info[u] and model.info[u].me
			if not self.over then
				drawSeries(self, g, { u = u, se = model.units[u], token = self.tokens[j], sub = me and 2 or 1,
					thickness = Theme.Px(me and 2 or 1.5, self) }, self.viewOut[j])
			end
		end
		self.note:Hide()
	else
		self.note:ClearAllPoints()
		self.note:SetPoint("TOPLEFT", self, "TOPLEFT", left, -(top + 4))
		self.note:SetWidth(plot)
		self.note:SetText(Timeline.OutcomeText(model) or "")
		self.note:Show()
		chartHeight = max(chartHeight, (self.note:GetStringHeight() or 14) + 8)
		g.height = chartHeight
	end

	local lanesTop = top + chartHeight + 2
	local laneY = {}
	if not self.over then laneY = drawLanes(self, g, res, plan.lanes, lanesTop) end
	if not self.over then drawCrossings(self, g, res, laneY) end
	local trackTop = lanesTop + lanesHeight
	if not self.over then drawTrack(self, g, trackTop) end
	local axisTop = trackTop + Timeline.TRACK_HEIGHT
	if not self.over then drawAxis(self, g, axisTop) end

	self.plan, self.geometry = plan, g
	self.plot = { left = left, width = plot, top = top, bottom = axisTop }
	self.bucket, self.buckets = bucket, buckets
	return axisTop + Timeline.AXIS_HEIGHT
end

---------------------------------------------------------------------------------------------------------------------
-- Pointer (§4.8): hover, click, drag, right click and the wheel
---------------------------------------------------------------------------------------------------------------------
-- The pointer's x inside the plot, nil when the client cannot say.
local function pointer(self)
	local x = Compat.CursorPosition()
	if not x or not self.plot then return nil end
	local hit = self.hit
	local scale, left = hit:GetEffectiveScale(), hit:GetLeft()
	if not left or not scale or scale <= 0 then return nil end
	return min(max(x / scale - left, 0), self.plot.width)
end

local function timeAt(self, x)
	return min(max(floor(Timeline.T(x, self.a, self.b, self.plot.width) + 0.5), 0), self.model.dur)
end

local function placeRange(self, tex, a, b)
	local plot = self.plot
	if not plot or not a or b <= self.a or a >= self.b then tex:Hide() return end
	local x1 = Timeline.X(max(a, self.a), self.a, self.b, plot.width)
	local x2 = Timeline.X(min(b, self.b), self.a, self.b, plot.width)
	tex:ClearAllPoints()
	tex:SetPoint("TOPLEFT", self.hit, "TOPLEFT", x1, 0)
	tex:SetSize(max(x2 - x1, 1), plot.bottom - plot.top)
	tex:Show()
end

local function placeAt(self, tex, t)
	local plot = self.plot
	if not plot or not t or t < self.a or t > self.b then tex:Hide() return end
	tex:ClearAllPoints()
	tex:SetPoint("TOPLEFT", self.hit, "TOPLEFT", Timeline.X(t, self.a, self.b, plot.width), 0)
	tex:SetSize(Theme.Px(1, self), plot.bottom - plot.top)
	tex:Show()
end

local function showTip(self, x)
	local t = timeAt(self, x)
	local sel = self.selection
	local lines
	if sel and t >= sel[1] and t <= sel[2] then
		self.summary = Timeline.Summary(self.model, sel[1], sel[2], self.summary, self.shown)
		lines = Timeline.SummaryLines(self.model, self.summary)
		lines[#lines + 1] = L.TIMELINE_CLEAR_HINT
	else
		lines = Timeline.Info(self.model, { t = t, a = self.a, b = self.b, width = self.plot.width, series = self.shown,
			lanes = self.plan.lanes, noLines = not self.useLines and self.plan.chart })
	end
	Widgets.Tooltip.Show(self.hit, lines, "TOP")
end

local update

local function stop(self)
	self.hit:SetScript("OnUpdate", nil)
end

update = function(hit)
	local self = hit.widget
	if not self.model then return end
	local x = pointer(self)
	if not x or (self.lastX and abs(x - self.lastX) < 1) then return end
	self.lastX = x
	if self.downX then
		if not self.dragging and abs(x - self.downX) > Timeline.DRAG_PX then
			self.dragging = true
			self.hover:Hide()
			Widgets.Tooltip.Hide()
		end
		if self.dragging then
			local t1, t2 = timeAt(self, self.downX), timeAt(self, x)
			placeRange(self, self.selected, min(t1, t2), max(t1, t2))
			return
		end
	end
	if self.hovering then
		placeAt(self, self.hover, timeAt(self, x))
		showTip(self, x)
		if self.opts.onHover then self.opts.onHover(timeAt(self, x)) end
	end
end

local function endPointer(self)
	self.downX, self.dragging, self.lastX = nil, false, nil
end

local function onEnter(hit)
	local self = hit.widget
	self.hovering, self.lastX = true, nil
	hit:SetScript("OnUpdate", update)
	update(hit)
end

local function onLeave(hit)
	local self = hit.widget
	self.hovering = false
	self.hover:Hide()
	Widgets.Tooltip.Hide()
	if not self.downX then
		self.lastX = nil
		stop(self)
	end
	if self.opts.onHover then self.opts.onHover(nil) end
end

local function onDown(hit, button)
	local self = hit.widget
	if button ~= "LeftButton" or not self.model then return end
	local x = pointer(self)
	if not x then return end
	self.downX, self.dragging, self.lastX = x, false, nil
	hit:SetScript("OnUpdate", update)
end

local function onUp(hit, button)
	local self = hit.widget
	if not self.model then return end
	if button == "RightButton" then
		if self.selection then
			self:SetSelection(nil)
			if self.opts.onSelect then self.opts.onSelect(nil, nil) end
			self.lastX = nil
			if self.hovering then update(hit) end
		end
		return
	end
	if button ~= "LeftButton" or not self.downX then return end
	local down = self.downX
	local x = pointer(self) or self.lastX or down
	endPointer(self)
	local select = abs(x - down) > Timeline.DRAG_PX
	local t1, t2 = timeAt(self, down), timeAt(self, x)
	local a, b = min(t1, t2), max(t1, t2)
	if select and b - a >= Timeline.SELECT_MIN then
		self:SetSelection(a, b)
		if self.hovering then showTip(self, x) end
		if self.opts.onSelect then self.opts.onSelect(a, b) end
	else
		placeRange(self, self.selected, self.selection and self.selection[1], self.selection and self.selection[2])
		if self.opts.onSeek then self.opts.onSeek(t2) end
	end
	if not self.hovering then stop(self) end
end

-- Zooms by 2 around the time under the pointer (§4.7), between MIN_VIEW and the whole session.
local function onWheel(hit, delta)
	local self = hit.widget
	if not self.model or not self.plot then return end
	local x = pointer(self) or self.plot.width / 2
	local t = Timeline.T(x, self.a, self.b, self.plot.width)
	local span = self.b - self.a
	local whole = max(self.model.dur, Timeline.MIN_VIEW)
	local wanted = min(max(delta > 0 and span / 2 or span * 2, Timeline.MIN_VIEW), whole)
	local a = floor(t - (t - self.a) * wanted / span + 0.5)
	a = min(max(a, 0), floor(whole - wanted))
	self:SetView(a, a + floor(wanted + 0.5))
	self.lastX = nil
	if self.hovering then update(hit) end
	if self.opts.onView then self.opts.onView(self.a, self.b) end
end

---------------------------------------------------------------------------------------------------------------------
-- The widget
---------------------------------------------------------------------------------------------------------------------
-- Draws again when something that shows changed.
function Chart:Redraw()
	if not self.dirty or not self.model or not self.width then return end
	self.dirty = false
	self.tokens = Timeline.SeriesTokens(self.model, self.shown)
	local bucket, height = Timeline.BUCKET_PX, nil
	for _ = 1, 16 do
		height = drawOnce(self, bucket)
		if not self.over then break end
		bucket = bucket * 2            -- a cap would be passed: columns twice as wide, never data left out
		Timeline.regions.widened = Timeline.regions.widened + 1
	end
	release(self.textures)
	release(self.lines)
	release(self.texts)
	self:SetSize(self.width, height)
	self.used = height
	self.hit:ClearAllPoints()
	self.hit:SetPoint("TOPLEFT", self, "TOPLEFT", self.plot.left, -self.plot.top)
	self.hit:SetSize(self.plot.width, self.plot.bottom - self.plot.top)
	placeAt(self, self.cursor, self.cursorAt)
	placeRange(self, self.selected, self.selection and self.selection[1], self.selection and self.selection[2])
end

local function setShown(self, list)
	local shown = {}
	for _, u in ipairs(list) do
		local se = self.model.units[u]
		if se and se.readings > 0 and #shown < Timeline.MAX_SERIES then shown[#shown + 1] = u end
	end
	self.shown = shown
end

function Chart:SetModel(model)
	endPointer(self)
	self.model, self.cursorAt, self.selection = model, nil, nil
	self.cursor:Hide()
	self.selected:Hide()
	self.hover:Hide()
	if Widgets.Tooltip.Owner() == self.hit then Widgets.Tooltip.Hide() end
	if not model then
		self.textures.used, self.lines.used, self.texts.used = 0, 0, 0
		release(self.textures)
		release(self.lines)
		release(self.texts)
		self.note:Hide()
		return
	end
	setShown(self, model.series)
	self.a, self.b = Timeline.Clamp(model, 0, model.dur)
	self.dirty = true
	self:Redraw()
end

-- The view, widened to MIN_VIEW and kept inside the session.
function Chart:SetView(a, b)
	if not self.model then return end
	a, b = Timeline.Clamp(self.model, a, b)
	local whole = max(self.model.dur, Timeline.MIN_VIEW)
	if b > whole then a, b = max(0, a - (b - whole)), whole end
	if a == self.a and b == self.b then return end
	self.a, self.b = a, b
	self.dirty = true
	self:Redraw()
end

function Chart:View() return self.a, self.b end

function Chart:SetSeries(list)
	if not self.model then return end
	setShown(self, list)
	self.dirty = true
	self:Redraw()
end

function Chart:SetCursor(t)
	self.cursorAt = t
	placeAt(self, self.cursor, t)
end

function Chart:SetSelection(a, b)
	self.selection = (a and b) and { a, b } or nil
	placeRange(self, self.selected, a, b)
end

-- The size wanted; returns the height used (more when the lanes do not leave the chart its smallest height).
function Chart:Layout(width, height)
	width = width or self.width
	height = height or self.wanted
	if width ~= self.width or height ~= self.wanted then
		self.width, self.wanted = width, height
		self.dirty = true
	end
	self:Redraw()
	if self.model and self.used then self:SetSize(self.width, self.used) end
	return self.used or self.wanted
end

-- For a card of the Settings kit (StackCard).
function Chart:Reflow(width) self:Layout(width, self.opts.height or Timeline.CARD_HEIGHT) end

function Timeline.Widget(parent, opts)
	if not on() then return nil end
	opts = opts or {}
	local f = CreateFrame("Frame", nil, parent)
	for name, method in pairs(Chart) do f[name] = method end
	f.opts, f.shown = opts, {}
	f.useLines = type(f.CreateLine) == "function"
	f.textures, f.lines, f.texts = { list = {}, used = 0 }, { list = {}, used = 0 }, { list = {}, used = 0 }
	f.viewOut, f.groups = {}, {}
	f.note = Theme.NewText(f, "Small", "text-2")
	f.note:SetWordWrap(true)
	f.note:SetJustifyH("CENTER")
	f.note:Hide()

	local hit = CreateFrame("Frame", nil, f)
	f.hit, hit.widget = hit, f
	hit:EnableMouse(true)
	local function over(token, alpha, sub)
		local t = hit:CreateTexture(nil, "OVERLAY", nil, sub)
		Theme.Crisp(t)
		Theme.Fill(t, token, alpha)
		t.token = token
		t:Hide()
		return t
	end
	f.selected = over("accent", 0.15, 0)
	f.hover = over("border-strong", 1, 1)
	f.cursor = over("accent", 1, 2)
	hit:SetScript("OnEnter", onEnter)
	hit:SetScript("OnLeave", onLeave)
	hit:SetScript("OnMouseDown", onDown)
	hit:SetScript("OnMouseUp", onUp)
	if opts.zoom ~= false then
		hit:EnableMouseWheel(true)
		hit:SetScript("OnMouseWheel", onWheel)
	end
	f:SetScript("OnHide", function(self)
		endPointer(self)
		self.hovering = false
		self.hover:Hide()
		stop(self)
		if Widgets.Tooltip.Owner() == self.hit then Widgets.Tooltip.Hide() end
		placeRange(self, self.selected, self.selection and self.selection[1], self.selection and self.selection[2])
	end)
	return f
end

---------------------------------------------------------------------------------------------------------------------
-- /atw debug (SPEC-05 §9): the pools, never a name
---------------------------------------------------------------------------------------------------------------------
function Timeline.PoolLines(out)
	local r = Timeline.regions
	out[#out + 1] = ("pools: %d lines, %d textures made (caps %d and %d per chart), columns widened %d times, line regions %s")
		:format(r.lines, r.textures, Timeline.MAX_LINES, Timeline.MAX_TEXTURES, r.widened,
			Theme.Probes().lines and "yes" or "no")
	return out
end
