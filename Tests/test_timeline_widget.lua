-- UI/Timeline.lua (SPEC-05 §4.8, §9, §10 M5.3; ui-style 3.5; ADR 0003): the maths of the drawing; every element of the
-- chart with its look in the three themes; dashed estimates and gaps that never look like a solid line; the pools and
-- their caps; the fallback without Line regions; the tooltip with the category of every value; click, drag, right click
-- and the wheel; no colour outside the theme; nothing with the switch off.

local function ON() return { monitor = true, alerts = true, coach = true, recording = true, reports = true, timeline = true } end

before_boot(function(M) M.features = ON() end)

local function TL() return Mock.ns.Timeline end
local function S() return Mock.ns.Session end
local function Th() return Mock.ns.Theme end
local function L() return Mock.ns.L end
local function Tip() return Mock.ns.Widgets.Tooltip end

local counter = 0

-- A session built with the Session API (as in test_timeline.lua).
local function build(spec)
	counter = counter + 1
	local s = S().New{ id = "tw-" .. counter, started = 4000 + counter, group = "party",
		rec = spec.rec or { hz = 2, warning = 80, danger = 95, mode = "values" } }
	for _, u in ipairs(spec.units or {}) do S().AddUnit(s, u, 0) end
	for _, m in ipairs(spec.mobs or {}) do S().AddMob(s, m, 0) end
	for _, e in ipairs(spec.events or {}) do S().AddEvent(s, e[1], e[2], e[3], e[4], e[5], e[6], e[7], e[8], e[9]) end
	for _, r in ipairs(spec.rows or {}) do S().AddRow(s, r[1], r[2], r[3], r[4], r[5]) end
	S().Join(s)
	s.state, s.ended = spec.state or "complete", spec.ended or "combat"
	s.dur, s.fight, s.trunc = spec.dur or 0, spec.dur or 0, spec.trunc
	return s
end

local function model(spec)
	local s = build(spec)
	return TL().Compute(s, assert(S().Decode(s)))
end

local ME = { name = "Testchar", role = "DAMAGER", token = "player", me = true }
local TANK = { name = "Bram", class = "WARRIOR", role = "TANK", token = "party1" }
local KOR = { name = "Kor", class = "ROGUE", role = "DAMAGER", token = "party2" }
local BOSS = { name = "Gorrak", class = "elite", npc = 448 }
local ADD = { name = "Pup", class = "normal" }

-- Every reading of unit `u` from `from` to `to`, one every `step` tenths (solid at 2 Hz), values from `value(t)`.
local function readings(rows, u, from, to, step, value)
	for t = from, to, step do rows[#rows + 1] = { t, 1, u, value(t), "0" } end
end

local function sorted(rows)
	table.sort(rows, function(a, b) if a[1] ~= b[1] then return a[1] < b[1] end return a[3] < b[3] end)
	return rows
end

-- A fight of 100 s in values with a bit of everything: a solid stretch, an estimate (30.0 to 36.0), a break (a target
-- change at 50.0), a recording pause (70.0 to 74.0), combat from 0 to 90 and a second pull from 94, a tank change,
-- crossings, a death, alerts and a coach tip.
local function rich()
	local rows = {}
	readings(rows, 1, 10, 300, 5, function(t) return 400 + t end)
	readings(rows, 1, 360, 490, 5, function() return 700 end)
	readings(rows, 1, 520, 650, 5, function(t) return t % 10 == 0 and 900 or 500 end)
	readings(rows, 1, 750, 890, 5, function() return 600 end)
	readings(rows, 2, 10, 890, 5, function() return 1000 end)
	return model{
		units = { ME, TANK, KOR }, mobs = { BOSS, ADD }, dur = 1000,
		events = {
			{ 0, "C", 0, 0, 0, "1" }, { 0, "M", 0, 0, 0, "v" }, { 0, "T", 1 }, { 0, "A", 1, 2, 0, "1" },
			{ 0, "S", 1, 2, 0, "S", "-" }, { 0, "S", 1, 1, 0, "S", "-" },
			{ 200, "S", 1, 1, 0, "W", "S" }, { 280, "S", 1, 1, 0, "D", "W" },
			{ 400, "S", 1, 1, 0, "S", "D" }, { 450, "A", 1, 1, 2, "0", "1" },
			{ 500, "T", 2 }, { 505, "T", 1 }, { 505, "S", 1, 2, 0, "S", "-" }, { 505, "S", 1, 1, 0, "S", "-" },
			{ 600, "L", 1, 1, 0, "w", "1", "0", "ch" }, { 602, "H", 1, 1, 0, "a", "c", "h" },
			{ 604, "D", 0, 2, 0, "g" }, { 740, "G", 0, 0, 0, "t", "-", "-", 40 },
			{ 900, "c" }, { 940, "C", 0, 0, 0, "2" }, { 1000, "c" },
		},
		rows = sorted(rows),
	}
end

-- A widget of `width` x `height` showing `m`; the plot is 32 narrower than the widget.
local function widget(m, opts, width, height)
	local w = TL().Widget(CreateFrame("Frame", nil, UIParent), opts or { legend = true, lanes = true })
	w:SetModel(m)
	w:Layout(width or 532, height or 260)
	return w
end

local function shown(pool, kind)
	local out = {}
	for i = 1, pool.used do
		local r = pool.list[i]
		if r:IsShown() and (not kind or r.kind == kind) then out[#out + 1] = r end
	end
	return out
end
local function textures(w, kind) return shown(w.textures, kind) end
local function lines(w, kind) return shown(w.lines, kind) end
local function texts(w, kind)
	local out = {}
	for _, fs in ipairs(shown(w.texts, kind)) do out[#out + 1] = fs:GetText() end
	return out
end

-- { x1, y1, x2, y2 } of a line, from the top left corner of the widget (y downwards).
local function ends(l)
	local _, _, x1, y1 = l:GetStartPoint()
	local _, _, x2, y2 = l:GetEndPoint()
	return x1, -y1, x2, -y2
end
local function xOf(t) local _, _, _, x = t:GetPoint(1); return x end
local function yOf(t) local _, _, _, _, y = t:GetPoint(1); return -y end

-- The pointer over time `t` of the widget.
local function pointAt(w, t)
	Mock.cursor.x = TL().X(t, w.a, w.b, w.plot.width)
	Mock.cursor.y = 10
end
local function script(w, name, ...) Mock.RunScript(w.hit, name, ...) end
local function hover(w, t)
	pointAt(w, t)
	script(w, "OnEnter")
	local out = table.concat(Tip().Lines(), "\n")
	script(w, "OnLeave")
	return out
end

describe("the maths of the drawing", function()
	it("maps time to x and back, and values to heights with a top between 110 and 150 %", function()
		eq(TL().X(500, 0, 1000, 500), 250)
		eq(TL().T(250, 0, 1000, 500), 500)
		eq(TL().X(100, 100, 100, 500), 0, "an empty span does not divide by zero")
		eq(TL().YMax(0), 110)
		eq(TL().YMax(96), 110)
		eq(TL().YMax(123), 130)
		eq(TL().YMax(130), 130)
		eq(TL().YMax(384.3), 150)
		eq(TL().Y(55, 110, 100), 50)
		eq(TL().Y(200, 150, 100), 100, "past the top stays on the edge")
		eq(TL().Y(-1, 110, 100), 0)
	end)

	it("puts round ticks at least 60 px apart", function()
		eq(TL().TickStep(100, 600), 10)
		eq(TL().TickStep(600, 500), 100)
		eq(TL().TickStep(1840, 500), 300)
		eq(TL().TickStep(18000, 500), 3000)
		eq(TL().TickStep(10000000, 500), 6000)
		local ticks = TL().Ticks(120, 740, 500, {})
		deepEq({ ticks.step, ticks.n, ticks[1], ticks[ticks.n] }, { 100, 6, 200, 700 })
	end)

	it("cuts an estimate into dashes of 4 px with a space at both ends, at most 24", function()
		local out = {}
		eq(TL().Dashes(2.9, out), 0, "too short to be told from a line: left as a hole")
		eq(TL().Dashes(5, out), 1)
		deepEq({ out[1], out[2] }, { 1.25, 3.75 })
		for _, length in ipairs({ 7, 9, 11, 25, 60, 171, 172, 400, 1200 }) do
			local n = TL().Dashes(length, out)
			truthy(n >= 1 and n <= 24, tostring(length))
			local last = 0
			for i = 1, n do
				truthy(out[2 * i - 1] - last > 1, "a space before every dash of " .. length)
				truthy(out[2 * i] > out[2 * i - 1])
				last = out[2 * i]
			end
			truthy(length - last > 1, "a space after the last dash of " .. length)
		end
		eq(TL().Dashes(60, out), 8)
		near(out[2] - out[1], 4, 1e-9)
		eq(TL().Dashes(1200, out), 24)
		truthy(out[2] - out[1] > 4, "a longer segment has longer dashes")
	end)

	it("merges bands closer than the resolution, each at least that wide", function()
		local out = TL().MergeBands({ { 10, 10.2, "a" }, { 10.5, 11, "b" }, { 20, 30, "c" } }, 1, {})
		eq(out.n, 2)
		deepEq({ out[1][1], out[1][2], out[1][3], out[1][4] }, { 10, 11.5, "a", 2 })
		deepEq({ out[2][1], out[2][2], out[2][4] }, { 20, 30, 1 })
		eq(TL().MergeBands({ { 10, 11 }, { 14, 15 }, { 18, 19 } }, 8, {}).n, 1)
	end)

	it("keeps one piece per pixel in a lane, the more urgent state winning", function()
		local out = TL().LanePieces({ { 0, 10, "S", 1 }, { 10, 10.1, "D", 4 }, { 10.1, 20, "S", 1 } }, 1, {})
		deepEq({ out.n, out[1][3], out[2][3], out[3][3] }, { 3, "S", "D", "S" })
		eq(out[2][2] - out[2][1], 1, "a short Danger stays a pixel wide")
		eq(out[3][1], out[2][2], "and no two overlap")
		out = TL().LanePieces({ { 0, 10, "S", 1 }, { 10.2, 20, "S", 1 } }, 1, {})
		eq(out.n, 1, "equal neighbours are one")
	end)

	it("gives the player series-1 and the others the rest", function()
		local m = rich()
		deepEq(TL().SeriesTokens(m, { 1, 2 }), { "series-1", "series-2" })
		deepEq(TL().SeriesTokens(m, { 2, 1 }), { "series-2", "series-1" })
		deepEq(TL().SeriesTokens(m, { 2, 3 }), { "series-2", "series-3" })
		local six = { info = { {}, { me = true }, {}, {}, {}, {} } }
		deepEq(TL().SeriesTokens(six, { 1, 2, 3, 4, 5, 6 }),
			{ "series-2", "series-1", "series-3", "series-4", "series-5", "series-6" })
		six.info[2].me = nil
		deepEq(TL().SeriesTokens(six, { 1, 2, 3, 4, 5, 6 }),
			{ "series-2", "series-3", "series-4", "series-5", "series-6", "series-1" })
	end)

	it("writes times with tenths and a lower bound as at least", function()
		eq(TL().TimeText(724), "1:12.4")
		eq(TL().TimeText(0), "0:00.0")
		eq(TL().PercentText(624), "62.4 %")
		eq(TL().PercentText(3843), "at least 384.3 %")
	end)
end)

describe("the chart of a fight in values (§4.2–§4.5)", function()
	it("draws the series as lines in the series colours, the player thicker", function()
		local w = widget(rich())
		local me, tank = 0, 0
		for _, l in ipairs(lines(w, "solid")) do
			if l.u == 1 then
				me = me + 1
				eq(l.token, "series-1")
				near(l:GetThickness(), Th().Px(2, w), 1e-9)
			else
				tank = tank + 1
				eq(l.token, "series-2")
				near(l:GetThickness(), Th().Px(1.5, w), 1e-9)
			end
		end
		truthy(me > 40 and tank > 40, me .. " " .. tank)
		truthy(#lines(widget(rich(), nil, 232), "bar") > 0, "a column with two values has its lowest-highest bar")
		eq(#Mock.errors, 0)
	end)

	it("draws an estimate in dashes only, and nothing across a break", function()
		local w = widget(rich(), { lanes = false })
		local plot = w.plot
		local function x(t) return plot.left + TL().X(t, 0, 1000, plot.width) end
		local dashesSeen = 0
		for _, l in ipairs(lines(w)) do
			if l.u == 1 then
				local x1, _, x2 = ends(l)
				-- the estimate between 30.0 and 36.0
				if x1 >= x(300) - 0.01 and x2 <= x(360) + 0.01 and x2 > x1 + 0.01 then
					eq(l.kind, "dash")
					dashesSeen = dashesSeen + 1
					truthy(x2 - x1 <= 4.01, "no dash longer than 4 px")
				else
					falsy(x1 < x(320) and x2 > x(340), "no solid line over the estimate")
				end
				-- the target change at 50.0 (no reading from 49.0 to 52.0) and the pause from 70.0 to 74.0
				falsy(x1 < x(505) - 1 and x2 > x(505) + 1, "nothing crosses the change of target")
				falsy(x1 < x(700) - 1 and x2 > x(700) + 1, "nothing crosses the pause")
			end
		end
		eq(dashesSeen, TL().Dashes(x(360) - x(300), {}), "every dash of the 6 s estimate, and nothing else there")
		eq(dashesSeen, 3)
		local list = lines(w, "dash")
		for i = 2, #list do
			local _, _, px2 = ends(list[i - 1])
			local nx1 = ends(list[i])
			truthy(nx1 - px2 > 1, "a space between two dashes")
		end
	end)

	it("draws the gaps as dashed bands with their reason, and out of combat as a plain band", function()
		local w = widget(rich())
		local plot = w.plot
		local gaps = textures(w, "gap")
		truthy(#gaps >= 1)
		for _, t in ipairs(gaps) do
			eq(t.token, "state-unknown")
			eq(t:GetTexture(), Mock.ns.Assets.textures.dash.path)
			near((select(4, t:GetVertexColor())), 0.5, 1e-9)
		end
		for _, t in ipairs(textures(w, "gap-back")) do eq(t.token, "surface-2") end
		local out = textures(w, "out")
		eq(#out, 1, "from 90.0 to 94.0")
		eq(out[1].token, "surface-2")
		near(xOf(out[1]), plot.left + TL().X(900, 0, 1000, plot.width), 0.01)
		-- a wide one writes its reason inside
		local big = widget(rich(), nil, 1200)
		contains(table.concat(texts(big, "band"), "\n"), "Recording paused for")
	end)

	it("shows a narrow gap as one stripe with a space on each side, never a solid block", function()
		local m = model{ units = { ME }, mobs = { BOSS }, dur = 6000,
			events = { { 0, "C", 0, 0, 0, "1" }, { 0, "M", 0, 0, 0, "v" }, { 0, "T", 1 },
				{ 3000, "G", 0, 0, 0, "t", "-", "-", 30 }, { 6000, "c" } },
			rows = { { 10, 1, 1, 500, "0" } } }
		local w = widget(m)
		local stripe, back = textures(w, "gap")[1], textures(w, "gap-back")[1]
		truthy(back:GetWidth() < TL().NARROW_BAND)
		truthy(stripe:GetWidth() < back:GetWidth())
		truthy(xOf(stripe) > xOf(back) and xOf(stripe) + stripe:GetWidth() < xOf(back) + back:GetWidth())
		isNil(stripe._horizTile and true or nil)
	end)

	it("draws the grid, the 100 % line and the recorded thresholds", function()
		local w = widget(rich())
		local grid = textures(w, "grid")
		eq(#grid, 3)
		deepEq({ grid[1].token, grid[2].token, grid[3].token }, { "border-subtle", "border-subtle", "border-strong" })
		local th = textures(w, "threshold")
		deepEq({ th[1].token, th[2].token }, { "state-warning", "state-danger" })
		truthy(yOf(th[2]) < yOf(th[1]), "95 % above 80 %")
		truthy(yOf(grid[3]) < yOf(th[2]), "100 % above both")
		deepEq(texts(w, "y-axis"), { "0%", "50%", "100%" })
		deepEq(texts(w, "threshold-label"), { "80%", "95%" })
		local none = model{ units = { ME }, mobs = { BOSS }, dur = 100, rec = { hz = 2 },
			events = { { 0, "C", 0, 0, 0, "1" }, { 0, "T", 1 } }, rows = { { 10, 1, 1, 500, "0" } } }
		eq(#textures(widget(none), "threshold"), 0, "no thresholds without the recording's")
	end)

	it("draws the changes of mob with their names, the series names and the time axis", function()
		local w = widget(rich(), nil, 900)
		local mobs = textures(w, "mob")
		eq(#mobs, 3)
		for _, t in ipairs(mobs) do eq(t.token, "border-strong") end
		contains(texts(w, "mob-name"), "Gorrak")
		deepEq(texts(w, "name"), { "Testchar", "Bram" }, "95 px are free after their last readings")
		deepEq(texts(widget(rich(), nil, 332), "name"), {}, "and none where less than 40 px are")
		local axis = texts(w, "x-axis")
		eq(axis[1], "0:00")
		truthy(#axis >= 5)
		local short = model{ units = { ME }, mobs = { BOSS }, dur = 1000,
			events = { { 0, "C", 0, 0, 0, "1" }, { 0, "T", 1 } }, rows = { { 10, 1, 1, 500, "0" } } }
		deepEq(texts(widget(short), "name"), { "Testchar" })
	end)

	it("shows the legend with the highest reading and who held the mob", function()
		local w = widget(rich())
		deepEq(texts(w, "legend"), { "Testchar", "Bram" }, "the series, in their order")
		contains(texts(w, "legend-max"), "100.0 %")
		eq(#textures(w, "legend-tank"), 2, "both held the mob")
		local marks = textures(w, "legend-mark")
		eq(#marks, 2)
		eq(#textures(widget(rich(), {}), "legend-mark"), 0, "no legend unless asked")
	end)

	it("puts the crossings on the series, the holder on its lane and the events on the track", function()
		local w = widget(rich(), nil, 900)
		local cross = textures(w, "cross")
		eq(#cross, 2)
		deepEq({ cross[1].icon, cross[2].icon }, { "state-warning", "state-danger" })
		eq(cross[1].token, "state-warning")
		local holder = textures(w, "holder")
		eq(holder[1].token, "series-2")
		eq(holder[#holder].token, "series-1")
		local icons = textures(w, "holder-icon")
		deepEq({ icons[1].icon, icons[2].icon }, { "tank", "warn" })
		eq(icons[2].token, "state-danger")
		local names = {}
		for _, t in ipairs(textures(w, "marker")) do names[#names + 1] = t.icon end
		contains(names, "flag")
		contains(names, "warn")
		contains(texts(w, "count"), "×3")   -- the alert, the tip and the death, grouped: the death leads
		contains(names, "skull")
	end)

	it("colours the markers by their kind and severity (§4.5)", function()
		local function icon(mk) return { TL().Icon(mk) } end
		deepEq(icon{ k = "L", a = "w" }, { "bell", "state-warning" })
		deepEq(icon{ k = "L", a = "d", c = "1" }, { "mute", "state-danger" })
		deepEq(icon{ k = "L", a = "l" }, { "bell", "state-danger" })
		deepEq(icon{ k = "L", a = "m" }, { "bell", "text-2" })
		deepEq(icon{ k = "D" }, { "skull", "text-1" })
		deepEq(icon{ k = "H" }, { "coach", "text-2" })
		deepEq(icon{ k = "N" }, { "star", "text-2" })
		deepEq(icon{ k = "X" }, { "cross", "text-2" })
		deepEq(icon{ k = "Z" }, { "warn", "text-2" })
		for _, name in ipairs({ "flag", "tank", "warn", "skull", "bell", "mute", "coach", "star", "cross" }) do
			notNil(Mock.ns.Assets.IconCoords(name), name)
		end
	end)

	it("draws the state lanes only when asked, dashed where the state is unknown", function()
		local m = rich()
		local w = widget(m)
		local lanes = textures(w, "lane")
		truthy(#lanes >= 4)
		local tokens = {}
		for _, t in ipairs(lanes) do tokens[t.token] = true end
		truthy(tokens["state-safe"] and tokens["state-warning"] and tokens["state-danger"])
		truthy(#textures(w, "lane-gap") >= 1, "the pause is dashed on the lanes")
		eq(#textures(widget(m, {}), "lane"), 0)
		local unknown = model{ units = { ME }, mobs = { BOSS }, dur = 400,
			events = { { 0, "C", 0, 0, 0, "1" }, { 0, "T", 1 }, { 0, "S", 1, 1, 0, "S", "-" },
				{ 100, "S", 1, 1, 0, "U", "S" }, { 400, "c" } }, rows = { { 10, 1, 1, 500, "0" } } }
		local u = widget(unknown)
		eq(#textures(u, "lane-unknown"), 1)
		eq(textures(u, "lane-unknown")[1]:GetTexture(), Mock.ns.Assets.textures.dash.path)
	end)

	it("keeps a reading alone between two breaks visible, and splits a column around a break", function()
		local m = model{ units = { ME }, mobs = { BOSS }, dur = 6000,
			events = { { 0, "C", 0, 0, 0, "1" }, { 0, "T", 1 }, { 3002, "G", 0, 0, 0, "t", "-", "-", 1 }, { 6000, "c" } },
			rows = { { 1000, 1, 1, 500, "0" }, { 3000, 1, 1, 300, "0" }, { 3005, 1, 1, 800, "0" } } }
		local w = widget(m)
		local dots = textures(w, "dot")
		eq(#dots, 3, "the lone reading, and the two of the split column")
		truthy(xOf(dots[3]) - (xOf(dots[2]) + dots[2]:GetWidth()) >= 1, "a hole of a pixel at least")
		eq(#lines(w, "solid"), 0)
		eq(#lines(w, "bar"), 0, "no bar spans the break")
	end)

	it("keeps a value past the top on the edge, with an arrow", function()
		local m = model{ units = { ME }, mobs = { BOSS }, dur = 100,
			events = { { 0, "C", 0, 0, 0, "1" }, { 0, "T", 1 } },
			rows = { { 10, 1, 1, 500, "0" }, { 15, 1, 1, 3843, "0" } } }
		local w = widget(m)
		local arrows = textures(w, "above")
		eq(#arrows, 1)
		eq(arrows[1].icon, "arrow_up")
		eq(w.geometry.ymax, 150)
		for _, l in ipairs(lines(w)) do
			local _, y1, _, y2 = ends(l)
			truthy(y1 >= w.plot.top - 0.01 and y2 >= w.plot.top - 0.01)
		end
	end)

	it("draws the segments that cross the edges of a zoomed view, clipped to it", function()
		local w = widget(rich(), { lanes = false })
		w:SetView(320, 340)   -- inside the estimate: no reading in view
		truthy(#lines(w, "dash") > 0)
		for _, l in ipairs(lines(w)) do
			local x1, _, x2 = ends(l)
			truthy(x1 >= w.plot.left - 0.01 and x2 <= w.plot.left + w.plot.width + 0.01)
		end
		w:SetView(102, 172)
		truthy(#lines(w, "solid") > 0)
		local x1 = ends(lines(w, "solid")[1])
		near(x1, w.plot.left, 0.01, "the segment that enters the view starts at its edge")
	end)

	it("only draws again when something changed", function()
		local w = widget(rich())
		local before = w.lines.used
		w.lines.used = -1
		w:Layout(532, 260)
		w:SetView(w:View())
		eq(w.lines.used, -1)
		w:Layout(533, 260)
		truthy(w.lines.used >= before - 10)
		w:SetSeries({ 1 })
		for _, l in ipairs(lines(w)) do eq(l.u, 1) end
		w:SetSeries({ 3 })
		eq(#w.shown, 0, "a unit without readings is no series")
	end)

	it("grows when the lanes would leave the chart less than 80 pt", function()
		local w = widget(rich(), { legend = true, lanes = true }, 532, 100)
		truthy(w:GetHeight() > 100)
		eq(w.geometry.height, 80)
		local card = widget(rich(), {}, 488, 140)
		eq(card:GetHeight(), 140)
	end)
end)

describe("the three outcomes (§4.6)", function()
	local function stateOnly()
		return model{ units = { ME, TANK }, mobs = { BOSS }, dur = 400, rec = { hz = 2, mode = "state" },
			events = { { 0, "C", 0, 0, 0, "1" }, { 0, "M", 0, 0, 0, "s", "s" }, { 0, "T", 1 }, { 0, "A", 1, 2, 0, "1" },
				{ 0, "S", 1, 1, 0, "S", "-" }, { 0, "S", 1, 2, 0, "D", "-" }, { 100, "S", 1, 1, 0, "W", "S" }, { 400, "c" } },
			rows = { { 10, 1, 1, 0, "a" }, { 10, 1, 2, 0, "d" } } }
	end

	it("state only: the note, the holder and a lane per unit, no percentage", function()
		local m = stateOnly()
		eq(m.outcome, "state")
		local w = widget(m, { legend = true })
		truthy(w.note:IsShown())
		eq(w.note:GetText(), L().TIMELINE_OUTCOME_STATE)
		eq(#lines(w), 0)
		eq(#textures(w, "grid"), 0)
		truthy(#textures(w, "holder") >= 1)
		local units = {}
		for _, t in ipairs(textures(w, "lane")) do units[t.u] = true end
		truthy(units[1] and units[2], "the lanes show even in the card")
		truthy(#textures(w, "cross") >= 1, "the crossing sits on the lane")
		local tip = hover(w, 150)
		contains(tip, "Testchar: Warning · game state (detected)")
		contains(tip, "Bram: Danger · game state (detected)")
		contains(tip, L().TIMELINE_MODE_STATE .. " (detected)")
	end)

	it("nothing readable: the note with the reason and only the events", function()
		local m = model{ units = { ME }, mobs = { BOSS }, dur = 400, rec = { hz = 2, mode = "none" },
			events = { { 0, "C", 0, 0, 0, "1" }, { 0, "M", 0, 0, 0, "n", "S" }, { 0, "T", 1 },
				{ 200, "D", 0, 1, 0, "g" }, { 400, "c" } },
			rows = { { 10, 1, 1, 0, "S" } } }
		eq(m.outcome, "none")
		local w = widget(m, { legend = true, lanes = true })
		contains(w.note:GetText(), "Nothing was readable")
		contains(w.note:GetText(), "secret value")
		eq(#lines(w), 0)
		eq(#textures(w, "holder"), 0)
		eq(#textures(w, "lane"), 0)
		eq(#textures(w, "gap"), 0)
		truthy(#textures(w, "marker") >= 2)
		contains(hover(w, 200), "You died")
	end)

	it("mixed: lines where there were values, the state band elsewhere", function()
		local m = model{ units = { ME, TANK }, mobs = { BOSS }, dur = 1000,
			events = { { 0, "C", 0, 0, 0, "1" }, { 0, "M", 0, 0, 0, "v" }, { 0, "T", 1 }, { 0, "S", 1, 1, 0, "S", "-" },
				{ 0, "S", 1, 2, 0, "S", "-" }, { 500, "M", 0, 0, 0, "s", "s" }, { 1000, "c" } },
			rows = { { 10, 1, 1, 500, "0" }, { 15, 1, 1, 520, "0" }, { 520, 1, 1, 0, "a" }, { 520, 1, 2, 0, "b" } } }
		eq(m.outcome, "mixed")
		local w = widget(m, {})
		falsy(w.note:IsShown())
		truthy(#lines(w, "solid") >= 1)
		local band = textures(w, "state-band")
		eq(#band, 1)
		eq(band[1].token, "surface-3")
		contains(texts(w, "band"), "State only from 0:50")
		local units = {}
		for _, t in ipairs(textures(w, "lane")) do units[t.u] = true end
		truthy(units[2], "a unit with states only keeps its lane, also in the card")
		isNil(units[1])
	end)
end)

describe("colours (ui-style 3.5, ADR 0015)", function()
	it("every region shows the token it says, in the three themes", function()
		local w = widget(rich())
		for _, theme in ipairs({ "nebula", "aurora", "warden" }) do
			truthy(Th().Apply(theme))
			local checked = 0
			for _, pool in ipairs({ w.textures, w.lines }) do
				for i = 1, pool.used do
					local r = pool.list[i]
					notNil(r.token, r.kind)
					local er, eg, eb = Th().Color(r.token, theme)
					local cr, cg, cb
					if type(r._texture) == "table" then cr, cg, cb = r._texture[1], r._texture[2], r._texture[3]
					else cr, cg, cb = r:GetVertexColor() end
					near(cr, er, 1e-6, theme .. " " .. r.kind)
					near(cg, eg, 1e-6, theme .. " " .. r.kind)
					near(cb, eb, 1e-6, theme .. " " .. r.kind)
					checked = checked + 1
				end
			end
			truthy(checked > 150, tostring(checked))
			for _, overlay in ipairs({ w.cursor, w.selected, w.hover }) do
				near(overlay._texture[1], (Th().Color(overlay.token, theme)), 1e-6)
			end
		end
		-- a region reused for something else takes its new colour, and the old one does not come back
		w:SetSeries({ 1 })
		w:SetView(0, 300)
		w:SetView(0, 1000)
		truthy(Th().Apply("aurora"))
		for i = 1, w.textures.used do
			local r = w.textures.list[i]
			local er = Th().Color(r.token, "aurora")
			local cr = type(r._texture) == "table" and r._texture[1] or r:GetVertexColor()
			near(cr, er, 1e-6, r.kind)
		end
	end)

	it("no colour is written in the widget", function()
		local source = Mock.ReadSource("AzerothThreatwarden/UI/Timeline.lua")
		notNil(source)
		isNil(source:find("SetColorTexture", 1, true))
		isNil(source:find("SetVertexColor", 1, true))
		isNil(source:find("SetTextColor", 1, true))
		isNil(source:find("#%x%x%x%x%x%x"))
		isNil(source:find("CreateColor", 1, true))
	end)
end)

describe("the pools (§4.8)", function()
	-- 6 series over 20 minutes at 2 Hz, never flat: far more than a small cap.
	local function busy()
		local units, rows, events = {}, {}, { { 0, "C", 0, 0, 0, "1" }, { 0, "M", 0, 0, 0, "v" }, { 0, "T", 1 } }
		for u = 1, 6 do
			units[u] = { name = "Unit" .. u, token = "raid" .. u }
			events[#events + 1] = { 0, "S", 1, u, 0, "S", "-" }
		end
		for t = 5, 3000, 5 do
			for u = 1, 6 do rows[#rows + 1] = { t, 1, u, (t * 7 + u * 131) % 1000, "0" } end
		end
		rows[#rows + 1] = { 3005, 1, 1, 1090, "0" }
		events[#events + 1] = { 3010, "c" }
		return model{ units = units, mobs = { BOSS }, events = events, rows = rows, dur = 3010 }
	end

	it("never shrink, and a second drawing of the same data makes nothing new", function()
		local w = widget(rich())
		local made, linesMade = #w.textures.list, #w.lines.list
		w:SetView(0, 300)
		w:SetView(0, 1000)
		truthy(#w.textures.list >= made and #w.lines.list >= linesMade)
		made, linesMade = #w.textures.list, #w.lines.list
		w:SetView(0, 300)
		w:SetView(0, 1000)
		eq(#w.textures.list, made)
		eq(#w.lines.list, linesMade)
		w:SetModel(nil)
		eq(#textures(w), 0)
		eq(#w.textures.list, made)
	end)

	it("stop at the cap of lines by widening the columns, and keep the highest peak", function()
		TL().MAX_LINES = 600
		local w = widget(busy())
		truthy(w.bucket > TL().BUCKET_PX, tostring(w.bucket))
		truthy(#w.lines.list <= 600, tostring(#w.lines.list))
		falsy(w.over, "the final drawing fits")
		truthy(TL().regions.widened >= 1)
		local top = w.plot.top + w.geometry.height - TL().Y(109, w.geometry.ymax, w.geometry.height)
		local reached = false
		for _, l in ipairs(lines(w)) do
			local _, y1, _, y2 = ends(l)
			if math.min(y1, y2) <= top + 0.01 then reached = true end
		end
		truthy(reached, "the peak of 109 % is still drawn")
		local units = {}
		for _, l in ipairs(lines(w)) do units[l.u] = true end
		for u = 1, 6 do truthy(units[u], "every series is drawn") end
	end)

	it("stop at the cap of textures the same way, merging gaps rather than dropping them", function()
		local events = { { 0, "C", 0, 0, 0, "1" }, { 0, "T", 1 }, { 0, "S", 1, 1, 0, "S", "-" } }
		for t = 20, 4990, 25 do events[#events + 1] = { t, "G", 0, 0, 0, "t", "-", "-", 5 } end
		events[#events + 1] = { 5000, "c" }
		local m = model{ units = { ME }, mobs = { BOSS }, events = events, rows = { { 2, 1, 1, 500, "0" } }, dur = 5000 }
		eq(#textures(widget(m, {}), "gap"), 199, "one band per pause when they fit")
		TL().MAX_TEXTURES = 300
		local w = widget(m, {})
		truthy(#w.textures.list <= 300, tostring(#w.textures.list))
		falsy(w.over)
		truthy(w.bucket > TL().BUCKET_PX)
		local gaps = textures(w, "gap-back")
		truthy(#gaps >= 1)
		local first, last = gaps[1], gaps[#gaps]
		near(xOf(first), w.plot.left + TL().X(15, 0, 5000, w.plot.width), 0.01)
		truthy(xOf(last) + last:GetWidth() >= w.plot.left + TL().X(4970, 0, 5000, w.plot.width), "up to the last pause")
		truthy(#texts(w, "x-axis") >= 1, "drawn down to the axis")
	end)

	it("fit dense estimates too: wider columns, every series up to its last reading, the peak kept", function()
		local units, rows, events = {}, {}, { { 0, "C", 0, 0, 0, "1" }, { 0, "T", 1 } }
		for u = 1, 6 do
			units[u] = { name = "Unit" .. u, token = "raid" .. u }
			events[#events + 1] = { 0, "S", 1, u, 0, "S", "-" }
		end
		for t = 20, 6000, 20 do   -- 2 s apart at 2 Hz: every segment an estimate
			for u = 1, 6 do rows[#rows + 1] = { t, 1, u, (t == 3000 and u == 3) and 1090 or (u * 100), "0" } end
		end
		events[#events + 1] = { 6000, "c" }
		local w = widget(model{ units = units, mobs = { BOSS }, events = events, rows = rows, dur = 6000 })
		falsy(w.over, "bucket " .. tostring(w.bucket))
		truthy(w.bucket > TL().BUCKET_PX)
		truthy(#w.textures.list <= TL().MAX_TEXTURES and #w.lines.list <= TL().MAX_LINES)
		eq(#lines(w, "solid"), 0, "an estimate never turns solid in wider columns")
		local right = {}
		for _, t in ipairs(textures(w, "dot")) do right[t.u] = math.max(right[t.u] or 0, xOf(t)) end
		for u = 1, 6 do truthy((right[u] or 0) > w.plot.left + w.plot.width - 2 * w.bucket, "series " .. u) end
		local top = w.plot.top + w.geometry.height - TL().Y(109, w.geometry.ymax, w.geometry.height)
		local reached = false
		for _, l in ipairs(lines(w, "bar")) do
			local _, y1, _, y2 = ends(l)
			if math.min(y1, y2) <= top + 0.01 then reached = true end
		end
		for _, t in ipairs(textures(w, "dot")) do if yOf(t) <= top then reached = true end end
		truthy(reached, "the peak is still there")
	end)

	it("are the caps of the specification, counted in /atw debug", function()
		eq(TL().MAX_LINES, 3000)
		eq(TL().MAX_TEXTURES, 1200)
		local w = widget(busy(), nil, 900)
		truthy(#w.lines.list <= 3000 and #w.textures.list <= 1200)
		local text = table.concat(TL().DebugLines(), "\n")
		matches(text, "pools: %d+ lines, %d+ textures made %(caps 3000 and 1200 per chart%), columns widened %d+ times")
		contains(text, "line regions yes")
		isNil(text:find("Unit1", 1, true), "no name")
		contains(Mock.ns.addon.Diagnostics.Report(), "pools:")
	end)
end)

describe("without Line regions", function()
	before_boot(function(M)
		M.features = ON()
		getmetatable(UIParent).__index.CreateLine = nil
	end)

	it("shows dots and bars, estimates as sparse dots, and says so", function()
		local w = widget(rich(), nil, 232)
		falsy(w.useLines)
		eq(#w.lines.list, 0)
		truthy(#textures(w, "dot") > 20)
		truthy(#textures(w, "bar") > 0)
		local estimates = textures(w, "estimate")
		truthy(#estimates >= 1)
		for _, t in ipairs(estimates) do truthy(t:GetWidth() <= 1) end
		table.sort(estimates, function(a, b) return xOf(a) < xOf(b) end)
		for i = 2, #estimates do truthy(xOf(estimates[i]) - xOf(estimates[i - 1]) > 2, "sparse") end
		contains(hover(w, 330), L().TIMELINE_NO_LINES)
		falsy(Th().Probes().lines)
		contains(table.concat(TL().DebugLines(), "\n"), "line regions no")
	end)
end)

describe("the tooltip (ADR 0003: every value with its category)", function()
	it("gives the nearest reading as detected, with the state as calculated from the recorded thresholds", function()
		local w = widget(rich())
		local tip = hover(w, 281)
		contains(tip, "At 0:28.1")
		contains(tip, "Gorrak (detected)")
		contains(tip, L().TIMELINE_MODE_VALUES .. " (detected)")
		contains(tip, "Bram holds the enemy (detected)")
		contains(tip, "Testchar: 68.0 % at 0:28.0 (detected) · Danger · thresholds 80 / 95 (calculated)")
		contains(tip, "Bram: 100.0 % at 0:28.0 (detected)")
		contains(tip, "Testchar: Danger · thresholds 80 / 95 (calculated)")
	end)

	it("says estimate between the two readings on a dashed segment, never a number in between", function()
		local w = widget(rich())
		contains(hover(w, 330), "Testchar: Estimate: between 70.0 % (0:30.0) and 70.0 % (0:36.0) (estimated)")
		local big = widget(rich(), nil, 4032)   -- 4 px a tenth: further than 4 px from any reading
		contains(hover(big, 252.5), "Testchar: Between 65.0 % (0:25.0) and 65.5 % (0:25.5) (detected)")
	end)

	it("says why there is nothing in a gap, as unknown", function()
		local w = widget(rich())
		contains(hover(w, 720), "Testchar: Recording paused for 4.0 s (unknown)")
		contains(hover(w, 920), L().TIMELINE_OUT_OF_COMBAT .. " (detected)")
		local m = model{ units = { ME, KOR }, mobs = { BOSS }, dur = 1000,
			events = { { 0, "C", 0, 0, 0, "1" }, { 0, "T", 1 }, { 0, "S", 1, 1, 0, "S", "-" }, { 1000, "c" } },
			rows = { { 10, 1, 1, 500, "0" }, { 10, 1, 2, 200, "0" }, { 200, 1, 1, 0, "S" } } }
		local tip = hover(widget(m), 500)
		contains(tip, "Testchar: No reading: secret value (unknown)")
		contains(tip, "Kor: " .. L().TIMELINE_NOT_LISTED .. " (detected)")
		contains(tip, L().TIMELINE_HOLDER_UNKNOWN .. " (unknown)")
	end)

	it("writes a value at the top of the column as a lower bound, estimated", function()
		local m = model{ units = { ME }, mobs = { BOSS }, dur = 100,
			events = { { 0, "C", 0, 0, 0, "1" }, { 0, "T", 1 } }, rows = { { 10, 1, 1, 3843, "0" } } }
		contains(hover(widget(m), 10), "at least 384.3 % at 0:01.0 (estimated)")
	end)

	it("lists the markers under the pointer with their category and confidence", function()
		local w = widget(rich())
		local tip = hover(w, 600)
		contains(tip, "Alert: Warning (calculated, confidence: high)")
		contains(tip, "(calculated, confidence: high)")
		contains(tip, "Bram died (detected)")
		contains(hover(w, 450), "Testchar took the enemy from Bram (detected)")
		contains(hover(w, 500), "Target: Pup (detected)")
	end)

	it("names the category in every line with a value, and stays within the tooltip", function()
		local w = widget(rich())
		for t = 0, 1000, 25 do
			pointAt(w, t)
			script(w, "OnEnter")
			local list = Tip().Lines()
			truthy(#list <= Tip().MAX_LINES)
			for i = 2, #list do
				local ok = list[i]:find("detected") or list[i]:find("calculated") or list[i]:find("estimated")
					or list[i]:find("unknown") or list[i]:find("and %d+ more")
				truthy(ok, "at " .. t .. ": " .. list[i])
			end
			script(w, "OnLeave")
		end
	end)

	it("keeps within the tooltip with six series and many events", function()
		local units, rows, events = {}, {}, { { 0, "C", 0, 0, 0, "1" }, { 0, "T", 1 } }
		for u = 1, 6 do
			units[u] = { name = "Unit" .. u, token = "raid" .. u }
			events[#events + 1] = { 0, "S", 1, u, 0, "S", "-" }
			rows[#rows + 1] = { 100, 1, u, 100 * u, "0" }
		end
		for i = 1, 20 do events[#events + 1] = { 100, "D", 0, i % 6 + 1, 0, "g" } end
		local w = widget(model{ units = units, mobs = { BOSS }, events = events, rows = rows, dur = 400 })
		pointAt(w, 100)
		script(w, "OnEnter")
		local list = Tip().Lines()
		truthy(#list <= Tip().MAX_LINES, tostring(#list))
		matches(list[#list], "and %d+ more")
	end)

	it("summarises a selection, calculated, estimated with unknown time", function()
		local m = rich()
		local lines_ = TL().SummaryLines(m, TL().Summary(m, 200, 800, {}))
		local text = table.concat(lines_, "\n")
		contains(lines_[1], "Selection 0:20.0 to 1:20.0")
		contains(text, "Testchar: highest 90.0 % at 0:52.0 (detected)")
		contains(text, "readings ")
		contains(text, "(calculated)")
		contains(text, "at least")
		contains(text, "(estimated)")
		contains(lines_[#lines_], "Events: ")
		contains(lines_[#lines_], "deaths 1")
		contains(lines_[#lines_], "(calculated)")
		local quiet = TL().SummaryLines(m, TL().Summary(m, 910, 930, {}))
		contains(table.concat(quiet, "\n"), "no readings (unknown)")
		contains(quiet[#quiet], "No events")
	end)
end)

describe("the pointer (§4.8)", function()
	local function events(m)
		local got = {}
		local w = widget(m or rich(), {
			onSeek = function(t) got[#got + 1] = { "seek", t } end,
			onSelect = function(a, b) got[#got + 1] = { "select", a, b } end,
			onHover = function(t) got[#got + 1] = { "hover", t } end,
		})
		return w, got
	end
	local function of(got, kind)
		local out = {}
		for _, e in ipairs(got) do if e[1] == kind then out[#out + 1] = e end end
		return out
	end

	it("runs an OnUpdate only while the pointer is over the chart, and only for a move of a pixel", function()
		local w, got = events()
		isNil(w.hit:GetScript("OnUpdate"))
		pointAt(w, 200)
		script(w, "OnEnter")
		notNil(w.hit:GetScript("OnUpdate"))
		truthy(w.hover:IsShown())
		truthy(Tip().IsShown())
		eq(#of(got, "hover"), 1)
		Mock.cursor.x = Mock.cursor.x + 0.4
		script(w, "OnUpdate")
		eq(#of(got, "hover"), 1)
		Mock.cursor.x = Mock.cursor.x + 5
		script(w, "OnUpdate")
		eq(#of(got, "hover"), 2)
		script(w, "OnLeave")
		isNil(w.hit:GetScript("OnUpdate"))
		falsy(w.hover:IsShown())
		falsy(Tip().IsShown())
		isNil(of(got, "hover")[3] and of(got, "hover")[3][2])
		Mock.Advance(1)
		eq(#Mock.errors, 0)
	end)

	it("follows the effective scale of the chart", function()
		local w, got = events()
		w.hit.GetEffectiveScale = function() return 0.5 end
		w.hit.GetLeft = function() return 100 end
		Mock.cursor.x = (100 + TL().X(400, 0, 1000, w.plot.width)) * 0.5
		script(w, "OnEnter")
		eq(of(got, "hover")[1][2], 400)
	end)

	it("seeks on a click, also one that moved up to 3 px", function()
		local w, got = events()
		pointAt(w, 300)
		script(w, "OnEnter")
		script(w, "OnMouseDown", "LeftButton")
		Mock.cursor.x = Mock.cursor.x + 3
		script(w, "OnUpdate")
		script(w, "OnMouseUp", "LeftButton")
		deepEq(of(got, "seek"), { { "seek", 306 } })
		eq(#of(got, "select"), 0)
		isNil(w.selection)
	end)

	it("selects by dragging, with the shadow following, and clears with the right button", function()
		local w, got = events()
		pointAt(w, 200)
		script(w, "OnEnter")
		script(w, "OnMouseDown", "LeftButton")
		pointAt(w, 600)
		script(w, "OnUpdate")
		truthy(w.selected:IsShown(), "the shadow while dragging")
		falsy(Tip().IsShown())
		pointAt(w, 800)
		script(w, "OnUpdate")
		near(w.selected:GetWidth(), TL().X(800, 200, 1200, w.plot.width), 0.01)
		script(w, "OnMouseUp", "LeftButton")
		deepEq(of(got, "select"), { { "select", 200, 800 } })
		eq(#of(got, "seek"), 0)
		deepEq(w.selection, { 200, 800 })
		eq(select(2, w.selected:GetVertexColor()) and w.selected._texture[4], 0.15)
		contains(table.concat(Tip().Lines(), "\n"), "Selection 0:20.0 to 1:20.0")
		contains(table.concat(Tip().Lines(), "\n"), L().TIMELINE_CLEAR_HINT)
		script(w, "OnMouseUp", "RightButton")
		isNil(w.selection)
		falsy(w.selected:IsShown())
		eq(#of(got, "select"), 2)
		isNil(of(got, "select")[2][2])
		contains(table.concat(Tip().Lines(), "\n"), "At 1:20.0")
	end)

	it("takes a selection shorter than a second as a click", function()
		local w, got = events()
		w:SetView(0, 100)
		pointAt(w, 20)
		script(w, "OnEnter")
		script(w, "OnMouseDown", "LeftButton")
		pointAt(w, 27)
		script(w, "OnUpdate")
		script(w, "OnMouseUp", "LeftButton")
		deepEq(of(got, "seek"), { { "seek", 27 } })
		isNil(w.selection)
		falsy(w.selected:IsShown())
	end)

	it("finishes a drag that ends outside the chart, then stops the OnUpdate", function()
		local w, got = events()
		pointAt(w, 700)
		script(w, "OnEnter")
		script(w, "OnMouseDown", "LeftButton")
		script(w, "OnLeave")
		notNil(w.hit:GetScript("OnUpdate"), "still dragging")
		Mock.cursor.x = -500
		script(w, "OnUpdate")
		script(w, "OnMouseUp", "LeftButton")
		deepEq(of(got, "select"), { { "select", 0, 700 } })
		isNil(w.hit:GetScript("OnUpdate"))
		falsy(Tip().IsShown())
	end)

	it("stops when hidden and ignores a client without a pointer", function()
		local w = events()
		pointAt(w, 200)
		script(w, "OnEnter")
		w:Hide()
		isNil(w.hit:GetScript("OnUpdate"))
		falsy(Tip().IsShown())
		w:Show()
		GetCursorPosition = nil
		script(w, "OnEnter")
		script(w, "OnMouseDown", "LeftButton")
		script(w, "OnMouseUp", "LeftButton")
		script(w, "OnMouseWheel", 1)
		script(w, "OnLeave")
		eq(#Mock.errors, 0)
	end)

	it("zooms by 2 around the pointer, between 5 s and the whole fight", function()
		local views = {}
		local w = widget(rich(), { onView = function(a, b) views[#views + 1] = { a, b } end })
		pointAt(w, 250)
		script(w, "OnMouseWheel", 1)
		deepEq({ w:View() }, { 125, 625 })
		deepEq(views[1], { 125, 625 })
		for _ = 1, 10 do script(w, "OnMouseWheel", 1) end
		local a, b = w:View()
		eq(b - a, TL().MIN_VIEW)
		for _ = 1, 10 do script(w, "OnMouseWheel", -1) end
		deepEq({ w:View() }, { 0, 1000 })
		w:SetView(990, 995)
		deepEq({ w:View() }, { 950, 1000 })
		falsy(widget(rich(), { zoom = false }).hit:IsMouseWheelEnabled())
	end)

	it("places the cursor and the selection in the view", function()
		local w = widget(rich(), {})
		w:SetCursor(500)
		truthy(w.cursor:IsShown())
		eq(w.cursor.token, "accent")
		near(xOf(w.cursor), TL().X(500, 0, 1000, w.plot.width), 0.01)
		near(w.cursor:GetHeight(), w.plot.bottom - w.plot.top, 0.01)
		w:SetView(0, 300)
		falsy(w.cursor:IsShown(), "outside the view")
		w:SetSelection(250, 600)
		near(w.selected:GetWidth(), TL().X(300, 250, 550, w.plot.width), 0.01)
		w:SetCursor(nil)
		w:SetSelection(nil)
		falsy(w.selected:IsShown())
	end)
end)

describe("in Italian", function()
	before_boot(function(M) M.features = ON() M.player.locale = "itIT" end)

	it("writes the tooltip, the summary and the notes in Italian", function()
		local m = rich()
		local w = widget(m)
		local tip = hover(w, 330)
		contains(tip, "Stima: tra")
		contains(tip, "(stimato)")
		contains(table.concat(TL().SummaryLines(m, TL().Summary(m, 0, 900, {})), "\n"), "massimo")
		deepEq(Mock.ns.Locale.MissingKeys(), {})
	end)
end)

describe("with the `timeline` switch off", function()
	before_boot(function(M) M.features = { monitor = true, recording = true, reports = true, timeline = false } end)

	it("makes no widget at all", function()
		isNil(TL().Widget(CreateFrame("Frame", nil, UIParent), {}))
		eq(TL().regions.textures, 0)
		eq(#Mock.errors, 0)
	end)
end)
