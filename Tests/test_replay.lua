-- Data/Replay.lua (SPEC-05 §5.1–§5.4, §10 M5.4; RPL-06–RPL-08; SPEC-09 Q18, Q19; ADR 0003, 0017): open and close;
-- playback with the client's time at every speed, the pause at the end of the view and a client that stood still; steps
-- over recorded moments, 5 s jumps, the next and previous event with the filters, the focus window cut at the ends;
-- seeking in and out of the view; the detail with the three categories and the reasons in the three outcomes; the
-- missing data, also none; the pause and the refusal in combat; a session deleted while open; the switches off; a tick
-- and a warm detail that make nothing.

before_boot(function(M)
	M.features = { monitor = true, alerts = true, coach = true, recording = true, reports = true, timeline = true,
		replay = true }
end)

local function Rp() return Mock.ns.Replay end
local function TL() return Mock.ns.Timeline end
local function S() return Mock.ns.Session end
local function St() return Mock.ns.Storage end
local function Sch() return Mock.ns.Scheduler end

local counter = 0

-- A session built with the Session API (as in test_timeline.lua), stored.
local function build(spec)
	counter = counter + 1
	local s = S().New{ id = "rp-" .. counter, started = 5000 + counter, group = "party",
		rec = spec.rec or { hz = 2, warning = 80, danger = 95, mode = "values" } }
	for _, u in ipairs(spec.units or {}) do S().AddUnit(s, u, 0) end
	for _, m in ipairs(spec.mobs or {}) do S().AddMob(s, m, 0) end
	for _, e in ipairs(spec.events or {}) do S().AddEvent(s, e[1], e[2], e[3], e[4], e[5], e[6], e[7], e[8], e[9]) end
	for _, r in ipairs(spec.rows or {}) do S().AddRow(s, r[1], r[2], r[3], r[4], r[5]) end
	S().Join(s)
	s.state, s.ended = spec.state or "complete", spec.ended or "combat"
	s.dur, s.fight, s.trunc = spec.dur or 0, spec.dur or 0, spec.trunc
	truthy(St().Add(s))
	truthy(St().Closed(s, true))
	return s
end

local ME = { name = "Testchar", role = "DAMAGER", token = "player", me = true }
local TANK = { name = "Bram", class = "WARRIOR", role = "TANK", token = "party1" }
local KOR = { name = "Kor", class = "ROGUE", role = "DAMAGER", token = "party2" }
local BOSS = { name = "Gorrak", class = "elite", npc = 448 }
local ADD = { name = "Pup", class = "normal" }

local function sorted(rows)
	table.sort(rows, function(a, b) if a[1] ~= b[1] then return a[1] < b[1] end return a[3] < b[3] end)
	return rows
end

-- 60 s in values, two pulls: me read every 0.5 s from 1.0 to 20.0, then a secret row at 21.0, back at 24.0 to 30.0, an
-- estimate (30.0 to 34.0), a recording pause (40.0 to 42.4), the end of the first pull at 50.0 and a second one from
-- 52.0 to 60.0; the tank holds the mob, Kor takes it at 45.0.
local function fight()
	local rows = {}
	for t = 10, 200, 5 do rows[#rows + 1] = { t, 1, 1, 400 + t, "0" } end
	rows[#rows + 1] = { 210, 1, 1, -1, "S" }
	for t = 240, 300, 5 do rows[#rows + 1] = { t, 1, 1, 850, "1" } end
	for t = 340, 395, 5 do rows[#rows + 1] = { t, 1, 1, 600, "0" } end
	for t = 424, 495, 5 do rows[#rows + 1] = { t, 1, 1, 700, "0" } end
	for t = 525, 595, 5 do rows[#rows + 1] = { t, 1, 1, 300, "0" } end
	for t = 10, 495, 5 do rows[#rows + 1] = { t, 1, 2, 1000, "3" } end
	for t = 525, 595, 5 do rows[#rows + 1] = { t, 1, 2, 1000, "3" } end
	return build{
		units = { ME, TANK, KOR }, mobs = { BOSS, ADD }, dur = 600,
		events = {
			{ 0, "C", 0, 0, 0, "1" }, { 0, "M", 0, 0, 0, "v" }, { 0, "T", 1 }, { 0, "A", 1, 2, 0, "1" },
			{ 0, "S", 1, 2, 0, "S", "-" }, { 0, "S", 1, 1, 0, "S", "-" },
			{ 100, "S", 1, 1, 0, "W", "S" }, { 150, "S", 1, 1, 0, "S", "W" },
			{ 200, "L", 1, 1, 0, "w", "1", "0", "ch" }, { 205, "H", 0, 1, 0, "1", "d", "h" },
			{ 300, "S", 1, 1, 0, "D", "S" }, { 424, "G", 0, 0, 0, "t", "-", "-", 24 },
			{ 429, "G", 0, 0, 0, "t", "-", "-", 4 },
			{ 450, "A", 1, 3, 2, "0", "1" }, { 500, "c" }, { 520, "C", 0, 0, 0, "2" }, { 520, "S", 1, 2, 0, "S", "-" },
			{ 520, "S", 1, 1, 0, "S", "-" }, { 600, "c" },
		},
		rows = sorted(rows),
	}
end

-- A quiet session: nothing missing around the middle.
local function calm(dur)
	local rows = {}
	for t = 0, dur, 5 do rows[#rows + 1] = { t, 1, 1, 500, "0" } end
	return build{ units = { ME }, mobs = { BOSS }, dur = dur,
		events = { { 0, "C", 0, 0, 0, "1" }, { 0, "M", 0, 0, 0, "v" }, { 0, "T", 1 }, { 0, "S", 1, 1, 0, "S", "-" },
			{ dur, "c" } }, rows = rows }
end

local function open(s, t)
	local ok, why
	Rp().Open(s.id, t, function(o, w) ok, why = o, w end)
	Mock.Advance(0.2)
	truthy(ok, tostring(why))
	return Rp().state
end

local changes
local function watch()
	changes = {}
	Rp().OnChange(function(what, why) changes[#changes + 1] = why and (what .. ":" .. why) or what end)
end

local function seen(what)
	local n = 0
	for _, c in ipairs(changes) do if c == what then n = n + 1 end end
	return n
end

-- The unit row of unit u in a snapshot.
local function rowOf(snap, u)
	for i = 1, snap.nunits do
		if snap.units[i].u == u then return snap.units[i] end
	end
	return nil
end

describe("opening and closing (SPEC-05 §5.2)", function()
	it("opens paused on the first combat, with the whole view, the default series and the key events", function()
		local s = fight()
		watch()
		local st = open(s)
		eq(st.id, s.id)
		eq(st.cursor, 0)
		eq(st.playing, false)
		eq(st.speed, 1)
		deepEq(st.view, { 0, 600 })
		isNil(st.selection)
		isNil(st.focus)
		eq(st.filter, "key")
		deepEq(st.series, st.model.series)
		ne(st.series, st.model.series, "its own list")
		eq(seen("model"), 1)
		truthy(Rp().Listening())
		eq(Sch().IsRunning("replay"), false, "nothing ticks while paused")
		truthy(Rp().Close())
		isNil(Rp().state)
		eq(seen("closed"), 1)
		falsy(Rp().Close())
		falsy(Rp().Play())
		falsy(Rp().Seek(10))
		isNil(Rp().Snapshot())
		isNil(Rp().Events())
		eq(#Mock.errors, 0)
	end)

	it("opens at the time asked, kept inside the session", function()
		local s = fight()
		eq(open(s, 215).cursor, 215)
		eq(open(s, 9000).cursor, 600)
		eq(open(s, -3).cursor, 0)
	end)

	it("starts at the first combat when that is not the start", function()
		local s = build{ units = { ME }, mobs = { BOSS }, dur = 100,
			events = { { 30, "C", 0, 0, 0, "1" }, { 100, "c" } }, rows = { { 40, 1, 1, 100, "0" } } }
		eq(open(s).cursor, 30)
	end)

	it("says why it cannot open, and keeps nothing", function()
		local why
		local function done(ok, reason) eq(ok, false) why = reason end
		Rp().Open("nothing", nil, done)
		eq(why, "unknown")
		local bad = fight()
		bad.cols.s = string.rep("?", bad.n)
		Rp().Open(bad.id, nil, done)
		eq(why, "damaged")
		local live = fight()
		live.state = "open"
		Rp().Open(live.id, nil, done)
		eq(why, "recording")
		isNil(Rp().state)
	end)

	it("replaces the replay open before, and a build overtaken answers replaced or closed", function()
		local a, b = fight(), fight()
		open(a)
		Rp().Play()
		open(b)
		eq(Rp().state.id, b.id)
		eq(Sch().IsRunning("replay"), false)
		TL().SLICE = 3
		local first, second
		Rp().Open(a.id, nil, function(_, w) first = w end)
		eq(Rp().Building(), a.id)
		isNil(Rp().state, "the one before is gone at once")
		Rp().Open(b.id, nil, function(ok) second = ok end)
		for _ = 1, 200 do Mock.Advance(0.05) end
		eq(first, "replaced")
		eq(second, true)
		eq(Rp().state.id, b.id)
		local third
		Rp().Open(fight().id, nil, function(_, w) third = w end)
		Rp().Close()
		for _ = 1, 200 do Mock.Advance(0.05) end
		eq(third, "closed")
		isNil(Rp().state)
		isNil(Rp().Building())
	end)

	it("closes when its session is deleted, and only then", function()
		local a, b = fight(), fight()
		open(a)
		watch()
		Rp().Play()
		truthy(St().Delete(b.id))
		notNil(Rp().state)
		truthy(St().Delete(a.id))
		isNil(Rp().state)
		eq(seen("closed:unknown"), 1)
		eq(Sch().IsRunning("replay"), false)
		eq(#Mock.errors, 0)
	end)
end)

describe("playback (SPEC-05 §5.2)", function()
	for _, speed in ipairs({ 1, 2, 4, 8 }) do
		it("moves the cursor by the client's time at " .. speed .. "x", function()
			open(calm(3000))
			truthy(Rp().SetSpeed(speed))
			eq(Rp().state.speed, speed)
			watch()
			truthy(Rp().Play())
			eq(Sch().Rate("replay"), 10)
			Mock.Advance(2.05, 0.05)
			near(Rp().state.cursor, speed * 20, 0.001)
			truthy(seen("cursor") >= 19 and seen("cursor") <= 20, "at most once a tick")
			truthy(Rp().Pause())
			eq(Sch().IsRunning("replay"), false)
			Mock.Advance(1)
			near(Rp().state.cursor, speed * 20, 0.001)
			eq(#Mock.errors, 0)
		end)
	end

	it("offers 1, 2, 4 and 8 only, and keeps the speed for the next replay", function()
		deepEq(Rp().SPEEDS, { 1, 2, 4, 8 })
		eq(Rp().JUMP, 50)
		open(calm(100))
		falsy(Rp().SetSpeed(3))
		falsy(Rp().SetSpeed("2"))
		eq(Rp().state.speed, 1)
		Rp().SetSpeed(4)
		Rp().Close()
		eq(open(calm(100)).speed, 4)
	end)

	it("reads the speed saved for the character", function()
		Mock.ns.Config.db.char.ui.replay = { speed = 8 }
		eq(open(calm(100)).speed, 8)
		Mock.ns.Config.db.char.ui.replay = { speed = 5 }
		eq(Rp().Speed(), 1, "not one of the speeds")
	end)

	it("does not jump when the client stood still", function()
		open(calm(3000))
		Rp().SetSpeed(2)
		Rp().Play()
		Mock.Advance(30, 30)
		near(Rp().state.cursor, 10, 0.001, "half a second at 2x")
	end)

	it("stops at the end of the view, pauses, and starts that view again", function()
		open(calm(300))
		Rp().SetView(100, 160)
		Rp().Seek(150)
		watch()
		Rp().Play()
		Mock.Advance(3)
		eq(Rp().state.cursor, 160)
		eq(Rp().state.playing, false)
		eq(Sch().IsRunning("replay"), false)
		truthy(seen("play") >= 2)
		truthy(Rp().Play())
		eq(Rp().state.cursor, 100)
		truthy(Rp().Pause())
		Rp().WholeFight()
		Rp().Seek(300)
		Rp().Toggle()
		eq(Rp().state.cursor, 0, "from the end of the whole fight to its start")
		eq(Rp().state.playing, true)
		Rp().Toggle()
		eq(Rp().state.playing, false)
	end)

	it("pauses when the view leaves the cursor behind", function()
		open(calm(300))
		Rp().Play()
		Mock.Advance(1)
		Rp().SetView(200, 280)
		eq(Rp().state.playing, false)
		Rp().Play()
		eq(Rp().state.cursor, 200)
	end)

	it("pauses in combat and refuses to play until it ends (Q18)", function()
		eq(Rp().PAUSE_IN_COMBAT, true)
		open(calm(3000))
		watch()
		Rp().Play()
		Mock.combat.Enter()
		eq(Rp().state.playing, false)
		eq(Sch().IsRunning("replay"), false)
		local ok, why = Rp().Play()
		eq(ok, false)
		eq(why, "combat")
		local can, reason = Rp().CanPlay()
		eq(can, false)
		eq(reason, "combat")
		-- seeking, events and the detail go on
		truthy(Rp().Seek(500))
		truthy(Rp().Step(1))
		truthy(Rp().Focus(1))
		notNil(Rp().Snapshot())
		local before = seen("play")
		Mock.combat.Leave()
		truthy(seen("play") > before, "the window hears that Play is back")
		truthy(Rp().Play())
		eq(#Mock.errors, 0)
	end)

	it("keeps playing when a listener fails, and records the error", function()
		open(calm(3000))
		Rp().OnChange(function() error("broken window") end)
		Rp().Play()
		Mock.Advance(1.05, 0.05)
		near(Rp().state.cursor, 10, 0.001)
		contains(Mock.ns.Diagnostics.Errors()[1].text, "broken window")
		Mock.ns.Diagnostics.ClearErrors()
	end)
end)

describe("moving the cursor (SPEC-05 §5.2)", function()
	it("steps to the next and previous recorded moment: a reading of a shown series or an event", function()
		open(fight())
		Rp().SetSeries({ 1 })
		Rp().Play()
		Rp().Pause()
		Rp().Seek(0)
		local got = {}
		for _ = 1, 3 do Rp().Step(1) got[#got + 1] = Rp().state.cursor end
		deepEq(got, { 10, 15, 20 })
		Rp().Seek(200)
		Rp().Step(1)
		eq(Rp().state.cursor, 205, "the Coach tip, an event; the secret row at 210 is no reading")
		Rp().Step(1)
		eq(Rp().state.cursor, 240)
		Rp().Step(-1)
		eq(Rp().state.cursor, 205)
		Rp().Seek(599)
		Rp().Step(1)
		eq(Rp().state.cursor, 600)
		Rp().Step(1)
		eq(Rp().state.cursor, 600, "the end")
		Rp().Seek(5)
		Rp().Step(-1)
		eq(Rp().state.cursor, 0)
		Rp().Step(-1)
		eq(Rp().state.cursor, 0, "the start")
		Rp().SetSeries({})
		Rp().Seek(0)
		Rp().Step(1)
		eq(Rp().state.cursor, 100, "without a series, the events alone")
		Rp().Seek(1)
		Rp().Play()
		Rp().Step(1)
		eq(Rp().state.playing, false, "a step pauses")
	end)

	it("jumps 5 s either way and keeps playing", function()
		open(fight())
		Rp().Seek(100)
		Rp().Play()
		Rp().Jump(1)
		eq(Rp().state.cursor, 150)
		eq(Rp().state.playing, true)
		Rp().Jump(-1)
		Rp().Jump(-1)
		eq(Rp().state.cursor, 50)
		Rp().Jump(-1)
		Rp().Jump(-1)
		eq(Rp().state.cursor, 0)
		Rp().Seek(590)
		Rp().Jump(1)
		eq(Rp().state.cursor, 600)
		falsy(Rp().Jump(0))
		falsy(Rp().Step(0))
	end)

	it("seeks inside the view without moving it, and scrolls it keeping its width", function()
		open(fight())
		Rp().SetView(100, 200)
		watch()
		Rp().Seek(150)
		deepEq(Rp().state.view, { 100, 200 })
		eq(seen("view"), 0)
		Rp().Seek(400)
		deepEq(Rp().state.view, { 350, 450 })
		eq(seen("view"), 1)
		Rp().Seek(600)
		deepEq(Rp().state.view, { 500, 600 })
		Rp().Seek(10)
		deepEq(Rp().state.view, { 0, 100 })
		falsy(Rp().Seek("x"))
		falsy(Rp().Seek(0 / 0))
	end)

	it("keeps the view at least 5 s and inside the session", function()
		open(fight())
		Rp().SetView(300, 310)
		deepEq(Rp().state.view, { 300, 350 })
		Rp().SetView(590, 600)
		deepEq(Rp().state.view, { 550, 600 })
		Rp().SetView(200, 100)
		deepEq(Rp().state.view, { 100, 200 })
		Rp().WholeFight()
		deepEq(Rp().state.view, { 0, 600 })
		open(calm(30))
		deepEq(Rp().state.view, { 0, 50 })
		Rp().Play()
		Mock.Advance(5)
		eq(Rp().state.cursor, 30, "never past the end of the session")
	end)
end)

describe("events (SPEC-05 §5.4)", function()
	local function kinds(list)
		local m, out = Rp().state.model, {}
		for _, i in ipairs(list) do
			local mk = m.events[i]
			out[#out + 1] = mk.k .. "@" .. mk.t
		end
		return out
	end

	it("lists the key events, the alerts and tips, and all of them", function()
		open(fight())
		deepEq(kinds(Rp().Events()), { "C@0", "M@0", "T@0", "A@0", "S@100", "S@300", "G@424", "A@450", "c@500",
			"C@520", "c@600" }, "only crossings among the states, and pauses of 1 s or more")
		deepEq(kinds(Rp().Events("alerts")), { "L@200", "H@205" })
		eq(#Rp().Events("all"), #Rp().state.model.events)
		eq(Rp().Events("key"), Rp().Events(), "made once")
		isNil(Rp().Events("nope"))
		watch()
		truthy(Rp().SetFilter("alerts"))
		eq(seen("filter"), 1)
		deepEq(kinds(Rp().Events()), { "L@200", "H@205" })
		falsy(Rp().SetFilter("nope"))
		eq(Rp().state.filter, "alerts")
		isNil(Rp().ListNote(Rp().Events()))
	end)

	it("says when only the start and the end of combat were recorded, and when a filter has nothing", function()
		open(build{ units = { ME }, mobs = { BOSS }, dur = 100, events = { { 0, "C", 0, 0, 0, "1" }, { 100, "c" } },
			rows = { { 10, 1, 1, 100, "0" } } })
		eq(Rp().ListNote(Rp().Events()), "Only the start and the end of combat were recorded.")
		eq(Rp().ListNote(Rp().Events("alerts")), "No event in this filter.")
		open(calm(100))
		eq(Rp().ListNote(Rp().Events("alerts")), "No event in this filter.")
	end)

	it("moves to the next and previous event of the filter, one by one at a shared time", function()
		open(fight())
		Rp().Seek(0)
		Rp().SetFilter("alerts")
		truthy(Rp().NextEvent(1))
		eq(Rp().state.cursor, 200)
		eq(Rp().state.model.events[Rp().state.focus].k, "L")
		truthy(Rp().NextEvent(1))
		eq(Rp().state.cursor, 205)
		falsy(Rp().NextEvent(1), "no event after it")
		eq(Rp().state.cursor, 205)
		truthy(Rp().NextEvent(-1))
		eq(Rp().state.cursor, 200)
		falsy(Rp().NextEvent(-1))
		Rp().SetFilter("key")
		Rp().Seek(600)
		truthy(Rp().NextEvent(-1))
		eq(Rp().state.cursor, 520)
		Rp().Focus(1)
		local order = { Rp().state.focus }
		for _ = 1, 4 do
			Rp().NextEvent(1)
			order[#order + 1] = Rp().state.focus
		end
		deepEq(order, { 1, 2, 3, 4, 7 }, "the four events at 0, then the first crossing")
		Rp().Play()
		Rp().NextEvent(1)
		eq(Rp().state.playing, false)
	end)

	it("gives the row of the last event passed", function()
		open(fight())
		eq(Rp().LastRow(), 4, "the four events at 0")
		Rp().Seek(299)
		eq(Rp().LastRow(), 5)
		Rp().SetFilter("alerts")
		Rp().Seek(0)
		eq(Rp().LastRow(), 0)
		Rp().Seek(600)
		eq(Rp().LastRow(), 2)
	end)

	it("focuses an event: cursor, pause, the window of 5 s selected and, on a long session, in view", function()
		open(fight())
		Rp().Play()
		watch()
		local list = Rp().Events("alerts")
		truthy(Rp().Focus(list[1]))
		local st = Rp().state
		eq(st.playing, false)
		eq(st.cursor, 200)
		eq(st.focus, list[1])
		deepEq(st.selection, { 150, 250 })
		deepEq(st.view, { 150, 250 })
		eq(seen("focus"), 1)
		Rp().WholeFight()
		deepEq(st.view, { 0, 600 })
		eq(st.focus, list[1])
		falsy(Rp().Focus(999))
		falsy(Rp().Focus(0))
	end)

	it("cuts the window at the ends of the session", function()
		open(fight())
		Rp().Focus(1)
		deepEq(Rp().state.selection, { 0, 50 })
		deepEq(Rp().state.view, { 0, 50 })
		Rp().Focus(#Rp().state.model.events)
		deepEq(Rp().state.selection, { 550, 600 })
		deepEq(Rp().state.view, { 550, 600 })
	end)

	it("keeps the view of a session of 20 s or less", function()
		open(calm(200))
		Rp().Focus(#Rp().state.model.events)
		deepEq(Rp().state.view, { 0, 200 })
		deepEq(Rp().state.selection, { 150, 200 })
	end)

	it("keeps the focus while the cursor stays in its window, and drops it with the selection outside", function()
		open(fight())
		local list = Rp().Events("alerts")
		Rp().Focus(list[1])
		Rp().Seek(240)
		eq(Rp().state.focus, list[1])
		Rp().Jump(1)
		isNil(Rp().state.focus)
		isNil(Rp().state.selection)
		Rp().Focus(list[1])
		watch()
		Rp().Play()
		eq(Rp().state.focus, list[1])
		Mock.Advance(7)
		eq(Rp().state.cursor, 250, "playback ends with the view of the window")
		eq(Rp().state.focus, list[1])
		Rp().WholeFight()
		Rp().Play()
		Mock.Advance(0.5)
		isNil(Rp().state.focus)
		eq(seen("focus"), 1)
	end)
end)

describe("the series (SPEC-05 §5.4)", function()
	local function many()
		local units, events, rows = {}, { { 0, "C", 0, 0, 0, "1" }, { 0, "T", 1 } }, {}
		for u = 1, 9 do
			units[u] = { name = "U" .. u, token = "raid" .. u, me = u == 1 or nil }
			events[#events + 1] = { 0, "S", 1, u, 0, "S", "-" }
			rows[#rows + 1] = { 10, 1, u, 900 - u, "0" }
		end
		events[#events + 1] = { 100, "c" }
		return build{ units = units, mobs = { BOSS }, dur = 100, events = events, rows = rows }
	end

	it("shows at most 6, and a seventh takes the place of the last one not chosen", function()
		local st = open(many())
		deepEq(st.series, { 1, 2, 3, 4, 5, 6 })
		watch()
		truthy(Rp().ToggleSeries(7))
		deepEq(st.series, { 1, 2, 3, 4, 5, 7 })
		truthy(Rp().ToggleSeries(8))
		deepEq(st.series, { 1, 2, 3, 4, 8, 7 }, "7 was chosen: the one before it goes")
		truthy(Rp().ToggleSeries(2))
		deepEq(st.series, { 1, 3, 4, 8, 7 })
		truthy(Rp().ToggleSeries(9))
		deepEq(st.series, { 1, 3, 4, 8, 7, 9 })
		eq(seen("series"), 4)
		falsy(Rp().ToggleSeries(10))
		truthy(Rp().SetSeries({ 9, 8, 7, 6, 5, 4, 3, 99, 9 }))
		deepEq(st.series, { 9, 8, 7, 6, 5, 4 })
		truthy(Rp().ToggleSeries(1))
		deepEq(st.series, { 9, 8, 7, 6, 5, 1 }, "all chosen: the last one goes")
		falsy(Rp().SetSeries("x"))
	end)

	it("lists the units of the detail with the shown series first", function()
		local st = open(many())
		Rp().SetSeries({ 8, 2 })
		local snap = Rp().Snapshot(10)
		eq(snap.nunits, 9)
		local order, shown = {}, {}
		for i = 1, snap.nunits do order[i], shown[i] = snap.units[i].u, snap.units[i].shown end
		deepEq(order, { 8, 2, 1, 3, 4, 5, 6, 7, 9 })
		deepEq({ shown[1], shown[2], shown[3] }, { true, true, false })
		Rp().MAX_UNITS = 4
		snap = Rp().Snapshot(10, snap)
		eq(snap.nunits, 4)
		eq(snap.more, 5)
		eq(st.model, Rp().state.model)
	end)
end)

describe("the detail (SPEC-05 §5.3)", function()
	it("gives every value its category: detected, estimated with its age, unknown with why and since when", function()
		open(fight())
		local m = Rp().state.model
		local snap = Rp().Snapshot(105)
		eq(snap.combat, true)
		eq(snap.pull, 1)
		eq(snap.pulls, 2)
		eq(snap.combatCategory, "detected")
		eq(Rp().CombatText(snap), "In combat (pull 1)")
		eq(snap.mob, 1)
		eq(snap.mobCategory, "detected")
		eq(Rp().MobText(m, snap), "Gorrak")
		eq(snap.mode, "values")
		eq(Rp().ModeText(snap), "Values")
		eq(snap.holder, 2)
		eq(snap.holderCategory, "detected")
		eq(Rp().HolderText(m, snap), "Bram holds the enemy (tank)")
		eq(snap.ngaps, 0)
		local me = rowOf(snap, 1)
		eq(me.state, "W")
		eq(me.stateCategory, "calculated")
		eq(Rp().StateText(me), "Warning")
		eq(me.kind, "value")
		eq(me.category, "detected")
		eq(me.readingT, 105)
		eq(Rp().ReadingText(me), "50.5 %")
		isNil(Rp().ReadingTip(me))

		-- 1.5 s after the last reading: still detected (join); 1.8 s: an estimate with its age
		me = rowOf(Rp().Snapshot(318), 1)
		eq(me.readingT, 300)
		eq(me.kind, "estimate")
		eq(me.category, "estimated")
		eq(Rp().ReadingText(me), "~85.0 % · 1.8 s before")
		eq(Rp().ReadingTip(me), "Estimate: the last reading, 1.8 s before")
		eq(rowOf(Rp().Snapshot(315), 1).kind, "value")

		-- the secret row: unknown from the last reading, with why
		me = rowOf(Rp().Snapshot(212), 1)
		eq(me.kind, "unknown")
		eq(me.category, "unknown")
		eq(me.reason, "secret")
		eq(me.since, 200)
		isNil(me.p)
		eq(Rp().ReadingText(me), "No reading since 0:20.0: secret value")

		-- older than 10 s: never shown as of this moment
		local s = build{ units = { ME }, mobs = { BOSS }, dur = 500,
			events = { { 0, "C", 0, 0, 0, "1" }, { 0, "T", 1 }, { 0, "S", 1, 1, 0, "S", "-" }, { 500, "c" } },
			rows = { { 100, 1, 1, 700, "0" } } }
		open(s)
		me = rowOf(Rp().Snapshot(200), 1)
		eq(me.kind, "estimate", "10 s exactly")
		me = rowOf(Rp().Snapshot(201), 1)
		eq(me.kind, "unknown")
		eq(Rp().ReadingText(me), "No reading since 0:10.0: reading too old")
		me = rowOf(Rp().Snapshot(50), 1)
		eq(me.kind, "unknown")
		eq(me.reason, "not-read")
		eq(Rp().ReadingText(me), "No reading recorded: not read yet")
	end)

	it("never carries a reading over a break: the reason is the first thing recorded after it", function()
		local function at(events, t)
			local list = { { 0, "C", 0, 0, 0, "1" }, { 0, "M", 0, 0, 0, "v" }, { 0, "T", 1 }, { 0, "S", 1, 1, 0, "S", "-" } }
			for _, e in ipairs(events) do list[#list + 1] = e end
			list[#list + 1] = { 500, "c" }
			open(build{ units = { ME }, mobs = { BOSS, ADD }, dur = 500, events = list, rows = { { 100, 1, 1, 700, "0" } } })
			return rowOf(Rp().Snapshot(t), 1)
		end
		local function why(row) return row and (row.kind .. "/" .. tostring(row.reason)) end
		eq(why(at({ { 105, "M", 0, 0, 0, "s", "s" } }, 108)), "unknown/state-only")
		eq(why(at({ { 105, "M", 0, 0, 0, "n", "S" } }, 108)), "unknown/secret")
		eq(why(at({ { 105, "M", 0, 0, 0, "v" } }, 108)), "value/nil")
		local back = { 106, "S", 1, 1, 0, "S", "-" }       -- the unit listed again on the mob
		eq(why(at({ { 105, "T", 2 }, { 106, "T", 1 }, back }, 108)), "unknown/target")
		eq(why(at({ { 108, "G", 0, 0, 0, "t", "-", "-", 5 } }, 105)), "unknown/tick", "inside the pause")
		eq(why(at({ { 108, "G", 0, 0, 0, "t", "-", "-", 5 } }, 102)), "value/nil", "before it")
		eq(why(at({ { 105, "Z", 0, 0, 0, "r" } }, 108)), "unknown/limit")
		eq(why(at({ { 105, "Z", 0, 0, 0, "e" } }, 108)), "value/nil", "the events' limit breaks no reading")
		eq(why(at({ { 105, "c" }, { 106, "C", 0, 0, 0, "2" }, back }, 108)), "unknown/combat")
		eq(why(at({ { 105, "S", 1, 1, 0, "-", "S" }, { 107, "S", 1, 1, 0, "S", "-" } }, 108)), "unknown/exit")
		eq(why(at({ { 105, "M", 0, 0, 0, "s", "s" }, { 105, "T", 2 }, { 106, "T", 1 }, back }, 108)), "unknown/state-only")
		isNil(at({ { 105, "S", 1, 1, 0, "-", "S" } }, 108), "off the list: not listed")
		eq(Rp().WhyText("exit"), "off the threat list")
	end)

	it("takes the last reading on the mob monitored then", function()
		open(build{ units = { ME }, mobs = { BOSS, ADD }, dur = 300,
			events = { { 0, "C", 0, 0, 0, "1" }, { 0, "T", 1 }, { 0, "S", 1, 1, 0, "S", "-" }, { 100, "T", 2 },
				{ 100, "S", 2, 1, 0, "S", "-" }, { 200, "T", 1 }, { 200, "S", 1, 1, 0, "S", "-" }, { 300, "c" } },
			rows = { { 90, 1, 1, 500, "0" }, { 110, 2, 1, 200, "0" }, { 190, 2, 1, 300, "0" } } })
		local me = rowOf(Rp().Snapshot(111), 1)
		eq(me.p, 200)
		me = rowOf(Rp().Snapshot(205), 1)
		eq(me.kind, "unknown")
		eq(me.reason, "target")
		eq(me.since, 90, "the last reading on this mob, not the one on the other")
	end)

	it("shows a lower bound at the top of the column", function()
		open(build{ units = { ME }, mobs = { BOSS }, dur = 100,
			events = { { 0, "C", 0, 0, 0, "1" }, { 0, "T", 1 }, { 0, "S", 1, 1, 0, "S", "-" }, { 100, "c" } },
			rows = { { 10, 1, 1, 3843, "1" } } })
		local me = rowOf(Rp().Snapshot(10), 1)
		eq(me.category, "estimated")
		eq(me.lower, true)
		eq(Rp().ReadingText(me), "at least 384.3 %")
	end)

	it("says out of combat, the paused recording, no monitored mob and the unknown holder", function()
		open(fight())
		local m = Rp().state.model
		local snap = Rp().Snapshot(510)
		eq(snap.combat, false)
		eq(Rp().CombatText(snap), "Out of combat")
		eq(snap.nunits, 0)
		isNil(Rp().MobText(m, snap))
		isNil(Rp().ModeText(snap))
		isNil(Rp().HolderText(m, snap))
		eq(Rp().Snapshot(550, snap).pull, 2)
		snap = Rp().Snapshot(410, snap)
		eq(snap.ngaps, 1)
		eq(snap.gaps[1][3], "tick")
		snap = Rp().Snapshot(600, snap)
		eq(snap.combat, true, "the end of the axis belongs to what ends there")
		eq(rowOf(snap, 1).kind, "value")

		open(build{ units = { ME }, mobs = { {} }, dur = 300, rec = { hz = 2 },
			events = { { 0, "C", 0, 0, 0, "1" }, { 0, "T", 1 }, { 0, "S", 1, 1, 0, "S", "-" }, { 100, "T", 0, 0, 0, "d" },
				{ 200, "T", 1 }, { 300, "c" } }, rows = { { 10, 1, 1, 100, "0" } } })
		m = Rp().state.model
		snap = Rp().Snapshot(10)
		eq(snap.mobCategory, "unknown")
		eq(Rp().MobText(m, snap), "Unknown mob")
		eq(Rp().HolderText(m, snap), "Who holds the enemy is not known")
		eq(snap.holderCategory, "unknown")
		eq(Rp().ModeText(snap), "Reading mode unknown")
		snap = Rp().Snapshot(150)
		isNil(snap.mob)
		eq(Rp().MobText(m, snap), "Target died")
		eq(snap.mobCategory, "detected")
		eq(snap.nunits, 0)
	end)

	it("takes the cursor's time by default and clamps any time", function()
		open(fight(), 105)
		eq(Rp().Snapshot().t, 105)
		eq(Rp().Snapshot(-5).t, 0)
		eq(Rp().Snapshot(9999).t, 600)
	end)

	it("shows the game's situation in state only, with the monitor's meaning of it", function()
		open(build{ units = { ME, TANK }, mobs = { BOSS }, dur = 600, rec = { hz = 2, mode = "state" },
			events = { { 0, "C", 0, 0, 0, "1" }, { 0, "M", 0, 0, 0, "s", "s" }, { 0, "T", 1 }, { 0, "A", 1, 2, 0, "1" },
				{ 0, "S", 1, 1, 0, "W", "-" }, { 0, "S", 1, 2, 0, "S", "-" }, { 400, "T", 0, 0, 0, "l" },
				{ 450, "T", 1 }, { 450, "S", 1, 1, 0, "W", "-" }, { 600, "c" } },
			rows = { { 10, 1, 1, -1, "b" }, { 10, 1, 2, -1, "d" } } })
		local m = Rp().state.model
		local snap = Rp().Snapshot(300)
		eq(Rp().ModeText(snap), "State only")
		local me, tank = rowOf(snap, 1), rowOf(snap, 2)
		eq(me.state, "W")
		eq(me.stateCategory, "detected", "the game's own state")
		eq(me.kind, "situation")
		eq(me.category, "detected")
		eq(me.situation, 1)
		isNil(me.p)
		eq(Rp().ReadingText(me), "More threat than the tank, no aggro yet")
		eq(Rp().ReadingText(tank), "Holds the enemy securely")
		-- after the target was lost the old situation is not carried over
		me = rowOf(Rp().Snapshot(500), 1)
		eq(me.kind, "unknown")
		eq(me.reason, "target")
		eq(Rp().ReadingText(me), "No reading since 0:01.0: enemy changed")
		truthy(Rp().HolderText(m, Rp().Snapshot(300)):find("Bram", 1, true))
	end)

	for _, outcome in ipairs(Fight.OUTCOMES) do
		it("gives a party fight of the real recorder in " .. outcome .. ": categories and reasons", function()
			local pull = Fight.new{
				player = { class = "MAGE", role = "DAMAGER", ranged = true },
				party = { { key = "tank", role = "TANK", name = "Bram" } },
				mobs = { { key = "boss", tokens = { "target", "boss1" }, classification = "worldboss", name = "Gorrak" } },
			}
			pull:outcome(outcome)
			pull:at(0):start():threat("boss", "tank", 1000):threat("boss", "player", { raw = 500, scaled = 40 })
			pull:at(5):threat("boss", "player", { raw = 900, scaled = 85 })
			pull:at(10):threat("boss", "player", { raw = 1200, scaled = 120 }):aggro("boss", "player")
			pull:at(20):stop()
			pull:finish()
			Mock.Advance(7)
			local st = open(St().Get(St().List()[1].id))
			local m = st.model
			eq(m.outcome, outcome)
			local me
			for u, info in ipairs(m.info) do if info.me then me = u end end
			-- every tenth of the session: every value has a category, a missing one a reason in words
			local snap
			local kinds = {}
			for t = 0, m.dur do
				snap = Rp().Snapshot(t, snap)
				truthy(Rp().CombatText(snap))
				for i = 1, snap.nunits do
					local row = snap.units[i]
					truthy(row.category == "detected" or row.category == "estimated" or row.category == "unknown")
					truthy(row.stateCategory == "detected" or row.stateCategory == "calculated"
						or row.stateCategory == "unknown")
					truthy(#Rp().ReadingText(row) > 0)
					if row.kind == "unknown" then
						notNil(row.reason)
						eq(row.category, "unknown")
						isNil(row.p)
					elseif row.kind == "value" then
						truthy(snap.t - row.readingT <= m.join + 0.01)
					end
					if row.u == me then kinds[row.kind] = true end
				end
			end
			if outcome == "values" then
				truthy(kinds.value)
				falsy(kinds.situation)
			elseif outcome == "state" then
				truthy(kinds.situation)
				falsy(kinds.value)
				falsy(kinds.estimate)
			else
				falsy(kinds.value)
				falsy(kinds.situation)
				snap = Rp().Snapshot(100, snap)
				eq(Rp().ModeText(snap), "Nothing readable: secret value")
				eq(snap.modeCategory, "unknown")
			end
			for i = 1, #Rp().Events("all") do
				local detail = Rp().EventDetail(Rp().Events("all")[i])
				truthy(#Rp().MissingLines(m, detail.missing) >= 1)
				for _, r in ipairs(detail.units) do truthy(#Rp().EventReadingText(m, r) > 0) end
			end
			eq(#Mock.errors, 0)
		end)
	end
end)

describe("missing data around an event (SPEC-05 §5.3, RPL-08)", function()
	local function lines(a, b)
		local m = Rp().state.model
		return Rp().MissingLines(m, Rp().Missing(a, b))
	end

	it("says when nothing is missing", function()
		open(calm(400))
		deepEq(lines(150, 250), { "No missing data in this window" })
		eq(#Rp().Missing(150, 250), 0)
	end)

	it("lists unit gaps, the paused recording and the units without a reading, cut to the window", function()
		open(fight())
		deepEq(lines(170, 270), { "Testchar: no readings 0:21.0–0:24.0 (secret value)" })
		deepEq(lines(380, 400), { "No missing data in this window" })
		deepEq(lines(390, 430), { "Recording paused 0:40.0–0:42.4", "Recording paused 0:42.5–0:42.9" })
		deepEq(lines(497, 523), { "Testchar: no readings in this window", "Bram: no readings in this window" },
			"out of combat is not missing; the readings of the second pull start at 0:52.5")
	end)

	it("lists nothing readable, state only, no monitored mob, stale readings and the sample limit", function()
		local s = build{ units = { ME }, mobs = { BOSS }, dur = 600, trunc = 500,
			events = { { 0, "C", 0, 0, 0, "1" }, { 0, "M", 0, 0, 0, "v" }, { 0, "T", 1 }, { 0, "S", 1, 1, 0, "S", "-" },
				{ 100, "M", 0, 0, 0, "n", "S" }, { 173, "M", 0, 0, 0, "v" }, { 200, "T", 0, 0, 0, "d" }, { 220, "T", 1 },
				{ 250, "T", 0, 0, 0, "l" }, { 260, "T", 1 }, { 300, "M", 0, 0, 0, "s", "s" }, { 330, "M", 0, 0, 0, "v" },
				{ 360, "T", 0, 0, 0, "n" }, { 370, "T", 1 }, { 500, "Z", 0, 0, 0, "r" }, { 600, "c" } },
			rows = { { 380, 1, 1, -1, "T" }, { 390, 1, 1, 300, "0" } } }
		open(s)
		local function has(a, b, text) contains(lines(a, b), text) end
		has(90, 200, "Nothing readable 0:10.0–0:17.3 (secret value)")
		has(180, 240, "Target died, nothing monitored 0:20.0–0:22.0")
		has(240, 270, "Target lost, nothing monitored 0:25.0–0:26.0")
		has(290, 340, "State only, no percentages 0:30.0–0:33.0")
		has(350, 380, "No monitored enemy 0:36.0–0:37.0")
		has(370, 400, "Testchar: no readings 0:38.0–0:39.0 (reading too old)")
		has(450, 550, "Samples stopped at 0:50.0 (limit reached)")
		-- in state only the units are not listed one by one
		deepEq(lines(305, 325), { "State only, no percentages 0:30.5–0:32.5" })
		-- in order of time
		local missing = Rp().Missing(0, 600)
		for i = 2, #missing do truthy(missing[i - 1].from <= missing[i].from) end
		eq(Rp().Missing(0, 600, missing), missing, "written into the table given")
	end)

	it("details an event: its fields, the readings of its units and the missing data of its window", function()
		open(fight())
		local st = Rp().state
		local took
		for i, mk in ipairs(st.model.events) do if mk.kind == "took" then took = i end end
		local detail = Rp().EventDetail(took)
		eq(detail.index, took)
		eq(detail.t, 450)
		eq(detail.category, "detected")
		isNil(detail.confidence)
		isNil(Rp().ConfidenceText(detail))
		eq(detail.a, 400)
		eq(detail.b, 500)
		eq(#detail.units, 2, "Kor, who took it, and Bram, who held it")
		local texts = {}
		for i, r in ipairs(detail.units) do texts[i] = Rp().EventReadingText(st.model, r) end
		deepEq(texts, { "Kor: no readings in this window",
			"Bram: 20 readings, first 100.0 %, last 100.0 %, highest 100.0 %" })
		contains(Rp().MissingLines(st.model, detail.missing), "Recording paused 0:40.0–0:42.4")
		local alert = Rp().EventDetail(Rp().Events("alerts")[1])
		eq(alert.confidence, "high")
		eq(Rp().ConfidenceText(alert), "Confidence: high")
		eq(alert.units[1].u, 1)
		eq(alert.units[1].count, 14, "150 to 200 every 5 tenths, then 240 to 250")
		eq(alert.units[1].firstP, 550)
		eq(alert.units[1].lastP, 850)
		eq(alert.units[1].maxP, 850)
		eq(alert.units[1].maxT, 240)
		local one = Rp().EventReadingText(st.model, { u = 1, count = 1, firstP = 555, firstT = 155 })
		eq(one, "Testchar: 1 reading, 55.5 % at 0:15.5")
		isNil(Rp().EventDetail(999))
	end)
end)

describe("the words of the replay", function()
	it("are there in both languages", function()
		open(fight())
		local m = Rp().state.model
		for _, code in ipairs({ "enUS", "itIT" }) do
			Mock.ns.Locale.Apply(code)
			local snap
			for t = 0, 600, 7 do
				snap = Rp().Snapshot(t, snap)
				truthy(#Rp().CombatText(snap) > 0)
				for i = 1, snap.nunits do truthy(#Rp().ReadingText(snap.units[i]) > 0) end
			end
			for _, line in ipairs(Rp().MissingLines(m, Rp().Missing(0, 600))) do truthy(#line > 0) end
			for _, reason in ipairs({ "secret", "missing", "error", "no-unit", "other", "stale", "state-only", "target",
				"tick", "limit", "combat", "exit", "not-read" }) do
				truthy(#Rp().WhyText(reason) > 0, reason)
			end
		end
		eq(Rp().MissingLines(m, {})[1], "Nessun dato mancante in questa finestra")
		Mock.ns.Locale.Apply("enUS")
		eq(#Mock.errors, 0)
	end)
end)

describe("the cost of the replay (SPEC-05 §5.2, ARC-06)", function()
	-- The function the replay's ticker calls.
	local function capture()
		local fn
		local start = Sch().Start
		Sch().Start = function(name, hz, f, opts)
			if name == "replay" then fn = f end
			return start(name, hz, f, opts)
		end
		truthy(Rp().Play())
		Sch().Start = start
		return fn
	end

	local function allocated(fn)
		local grown = math.huge
		for _ = 1, 3 do
			collectgarbage("collect")
			collectgarbage("collect")
			collectgarbage("stop")
			local before = collectgarbage("count")
			fn()
			grown = math.min(grown, (collectgarbage("count") - before) * 1024)
			collectgarbage("restart")
		end
		return grown
	end

	it("makes nothing on a tick, passing recorded moments or not, and stays within 2 000 instructions", function()
		open(fight())
		Rp().OnChange(function() end)
		Rp().SetSpeed(2)
		local tick = capture()
		local function step() Mock.StepClock(0.1) tick() end
		for _ = 1, 20 do step() end
		local cursor, moment = Rp().state.cursor, Rp().state.moment
		local grown = allocated(function() for _ = 1, 50 do step() end end)
		truthy(Rp().state.cursor > cursor + 100, "the ticks really ran")
		truthy(Rp().state.moment > moment, "past recorded moments")
		truthy(grown <= 64, "allocated " .. grown .. " bytes in 50 ticks")
		local worst = 0
		for _ = 1, 40 do
			local work = T.instructions(step, 1)
			if work > worst then worst = work end
		end
		truthy(worst <= 2000, "instructions in a tick: " .. worst)
	end)

	it("changes `moment` only when the cursor passes something recorded", function()
		open(calm(3000))
		Rp().Seek(1)
		local st = Rp().state
		local m = st.moment
		Rp().Seek(2)
		eq(st.moment, m, "between two readings")
		Rp().Seek(5)
		eq(st.moment, m + 1, "a reading")
		Rp().Seek(5)
		eq(st.moment, m + 1)
		Rp().Seek(3)
		eq(st.moment, m + 2, "back over it")
		-- a reading growing old: detected up to 1.5 s, then estimated
		open(build{ units = { ME }, mobs = { BOSS }, dur = 500,
			events = { { 0, "C", 0, 0, 0, "1" }, { 0, "T", 1 }, { 0, "S", 1, 1, 0, "S", "-" }, { 500, "c" } },
			rows = { { 100, 1, 1, 700, "0" } } })
		st = Rp().state
		Rp().Seek(115)
		m = st.moment
		Rp().Seek(116)
		eq(st.moment, m + 1, "now an estimate")
		Rp().Seek(200)
		eq(st.moment, m + 1)
		Rp().Seek(201)
		eq(st.moment, m + 2, "now unknown")
	end)

	it("makes no table or string for a detail once warm", function()
		open(fight())
		local snap = {}
		for t = 0, 600, 3 do Rp().Snapshot(t, snap) end
		local grown = allocated(function()
			for t = 0, 600, 3 do Rp().Snapshot(t, snap) end
		end)
		truthy(grown <= 64, "allocated " .. grown .. " bytes")
	end)
end)

describe("/atw debug (SPEC-05 §9)", function()
	it("says whether the replay is open and playing, its speed and the cost of its tick, never a name", function()
		local text = Mock.ns.Diagnostics.Report()
		contains(text, "replay: closed")
		contains(text, "replay tick: not measured")
		open(fight())
		contains(Mock.ns.Diagnostics.Report(), "replay: open, paused, speed 1x")
		Rp().SetSpeed(4)
		Rp().Play()
		Mock.Advance(1)
		contains(Mock.ns.Diagnostics.Report(), "replay: open, playing, speed 4x")
		Rp().Pause()
		text = Mock.ns.Diagnostics.Report()
		matches(text, "replay tick: %d+ ticks, %d+%.%d+ ms median")
		falsy(text:find("Gorrak", 1, true), "no mob name")
		falsy(text:find("Bram", 1, true), "no unit name")
	end)
end)

for _, switches in ipairs({ { timeline = true, replay = false }, { timeline = false, replay = true },
	{ timeline = false, replay = false } }) do
	describe(("with timeline %s and replay %s (ADR 0014)"):format(tostring(switches.timeline),
		tostring(switches.replay)), function()
		before_boot(function(M)
			M.features = { monitor = true, alerts = true, coach = true, recording = true, reports = true,
				timeline = switches.timeline, replay = switches.replay }
		end)

		it("opens nothing, listens to nothing and ticks nothing", function()
			local s = fight()
			local ok, why
			Rp().Open(s.id, nil, function(o, w) ok, why = o, w end)
			Mock.Advance(1)
			eq(ok, false)
			eq(why, "off")
			isNil(Rp().state)
			falsy(Rp().Listening())
			falsy(Rp().Play())
			eq(Sch().IsRunning("replay"), false)
			contains(Mock.ns.Diagnostics.Report(), "replay: off")
		end)
	end)
end

describe("the keys, the actions and a selection (SPEC-05 §5.5, Q19)", function()
	it("maps the keys of Q19, and leaves the rest to the game", function()
		local A = function(...) return Rp().KeyAction(...) end
		eq(A("SPACE"), "toggle")
		eq(A("LEFT"), "back")
		eq(A("RIGHT"), "forward")
		eq(A("LEFT", true), "jumpBack")
		eq(A("RIGHT", true), "jumpForward")
		eq(A("UP"), "prevEvent")
		eq(A("DOWN"), "nextEvent")
		eq(A("HOME"), "start")
		eq(A("END"), "finish")
		eq(A("4"), "speed4")
		for _, args in ipairs({ { "5" }, { "W" }, { "ESCAPE" }, { "SPACE", true }, { "HOME", true }, { "SPACE", false, true },
			{ "1", false, false, true }, {} }) do
			isNil(A(unpack(args)), tostring(args[1]))
		end
	end)

	it("does each action, and nothing without a replay", function()
		falsy(Rp().Do("toggle"))
		falsy(Rp().SetSelection(1, 2))
		open(calm(300))
		truthy(Rp().Do("finish"))
		eq(Rp().state.cursor, 300)
		truthy(Rp().Do("jumpBack"))
		eq(Rp().state.cursor, 250)
		truthy(Rp().Do("jumpForward"))
		truthy(Rp().Do("start"))
		eq(Rp().state.cursor, 0)
		truthy(Rp().Do("speed3"))
		eq(Rp().state.speed, 4)
		falsy(Rp().Do("speed9"))
		falsy(Rp().Do("dance"))
		falsy(Rp().Do(nil))
	end)

	it("keeps a selection inside the session, in order, and drops the focus", function()
		open(calm(300))
		Rp().Focus(1)
		watch()
		truthy(Rp().SetSelection(400, 20))
		deepEq(Rp().state.selection, { 20, 300 })
		isNil(Rp().state.focus)
		eq(seen("focus"), 1)
		Rp().SetSelection(50, 50)
		isNil(Rp().state.selection)
		Rp().SetSelection(10, 60)
		Rp().SetSelection(nil)
		isNil(Rp().state.selection)
	end)
end)

