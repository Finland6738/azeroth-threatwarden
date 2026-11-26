-- Replay: the controller of the Threat Replay of a recorded session (SPEC-05 §5.1–§5.4, §9; RPL-06–RPL-08; SPEC-09
-- Q18, Q19; ADR 0003, 0017). Lua 5.1, no frame and no game API (the client clock and the player's combat flag through
-- Core/Compat.lua), nothing written into the session. Behind the `replay` and `timeline` switches (ADR 0014): with
-- either off, Open answers "off" and nothing is listened to or ticks. Threatwarden's own.
--
-- It moves a cursor over the model of Data/Timeline.lua and says what was recorded at that time: every value with its
-- category, and a missing one with why and since when. A number that is not of that moment is never shown as such.
--
--   Replay.Open(id, t, done)      the model (Timeline.Build), the cursor at t or at the first combat, paused;
--                                 done(true) or done(false, "off" / "unknown" / "recording" / "damaged" / "error" /
--                                 "replaced" / "closed"); a second Open replaces the first
--   Replay.Close()                stops the tick and forgets the state
--   Replay.Play / Pause / Toggle  the 10 Hz `replay` tick (Core/Scheduler.lua); in combat Play answers false, "combat"
--   Replay.Seek(t), Step(dir), Jump(dir), NextEvent(dir), Focus(i)      the cursor
--   Replay.SetSpeed(x), SetView(a, b), WholeFight(), SetSeries(list), ToggleSeries(u), SetFilter(f)
--   Replay.Events(filter), LastRow()          the event list: indexes into model.events, and the last one passed
--   Replay.Snapshot(t, out)       the detail at a time (§5.3), written into `out` (reused: no table once warm)
--   Replay.EventDetail(i, out)    an event with the readings around it and the missing data of its window
--   Replay.Missing(a, b, out)     the missing data of an interval
--   Replay.OnChange(fn)           one listener: fn(what, why) with what = cursor, play, view, focus, series, filter,
--                                 model, closed
--
-- The tick calls no game function but the client clock and makes no table or string: the cursor moves, and
-- `state.moment` goes up only when it passes something recorded (a row, an event, a gap, a reading growing old), so a
-- window reads the detail again only then.
local ADDON_NAME, ns = ...
ns = ns or {}
ns.modules = ns.modules or {}

local Replay = {}
ns.Replay, ns.modules.Replay = Replay, Replay

local Timeline, Session, Storage, Scheduler, Compat = ns.Timeline, ns.Session, ns.Storage, ns.Scheduler, ns.Compat
local type, pairs, ipairs, pcall, tostring, floor, max, min, sort = type, pairs, ipairs, pcall, tostring, math.floor,
	math.max, math.min, table.sort

Replay.HZ = 10                       -- ticks a second while playing (§5.2)
Replay.MAX_STEP = 0.5                -- seconds: a client that stood still does not make the cursor jump
Replay.SPEEDS = { 1, 2, 4, 8 }       -- Q19
Replay.JUMP = 50                     -- tenths: 5 s (Q19)
Replay.WINDOW = 50                   -- tenths before and after a focused event (§5.3, source §5.4)
Replay.FOCUS_ZOOM = 200              -- tenths: only a longer session zooms to the window of a focused event
Replay.PAUSE_IN_COMBAT = true        -- Q18
Replay.MAX_UNITS = 40                -- units listed in the detail
Replay.FILTERS = { "key", "alerts", "all" }
Replay.SPEED_PATH = "char.ui.replay.speed"    -- kept from the character schema 2 (SPEC-02 §3.9, M5.5)

Replay.state = nil

local TICK = "replay"
local EPSILON = 0.000001
local NUMBERED = Session.NUMBERED
local SITUATION = { a = 0, b = 1, c = 2, d = 3 }
local ROW_REASON = { S = "secret", E = "error", M = "missing", U = "no-unit", X = "other", T = "stale" }

local session                        -- the session of the open replay
local data                           -- its indexes, made at Open (see index below)
local building                       -- the id being built, nil otherwise
local generation = 0                 -- of Open and Close: a build of an older one is ignored
local opened = 0                     -- the generation of the last Open
local listener
local listening = false
local lastTick = 0
local chosenSpeed                    -- the speed set since this load
local cost = nil                     -- the last measured cost of the tick: { median, max, ticks }

local function noop() end

local function on()
	local F = ns.Features
	return F ~= nil and F.On("replay") and F.On("timeline")
end

local function notify(what, why)
	if not listener then return end
	local ok, err = pcall(listener, what, why)
	if not ok and ns.Diagnostics then ns.Diagnostics.Record("replay listener (" .. what .. "): " .. tostring(err)) end
end

local function inCombat()
	if ns.addon and ns.addon.inCombat then return true end
	return Compat.Unit.AffectingCombat("player") == true
end

---------------------------------------------------------------------------------------------------------------------
-- Searches (binary: nothing made)
---------------------------------------------------------------------------------------------------------------------
-- How many of list[1 .. n] (numbers, not decreasing) are <= x; with `strict`, < x.
local function countTimes(list, n, x, strict)
	local lo, hi = 1, n
	while lo <= hi do
		local mid = floor((lo + hi) / 2)
		local v = list[mid]
		if v < x or (not strict and v == x) then lo = mid + 1 else hi = mid - 1 end
	end
	return hi
end

-- How many events of `events` have t <= x; with `strict`, t < x.
local function countEvents(events, x, strict)
	local lo, hi = 1, #events
	while lo <= hi do
		local mid = floor((lo + hi) / 2)
		local v = events[mid].t
		if v < x or (not strict and v == x) then lo = mid + 1 else hi = mid - 1 end
	end
	return hi
end

-- How many of the rows `list` (indexes into d, in order of time) have d.t <= x.
local function countRows(list, n, dt, x, strict)
	local lo, hi = 1, n
	while lo <= hi do
		local mid = floor((lo + hi) / 2)
		local v = dt[list[mid]]
		if v < x or (not strict and v == x) then lo = mid + 1 else hi = mid - 1 end
	end
	return hi
end

-- The last interval of `list` ({ from, to, ... }, in order of `from`, not overlapping) that starts at or before t and
-- holds it. [from, to), and the end of the axis belongs to what ends there.
local function holding(list, t, dur)
	local lo, hi = 1, #list
	while lo <= hi do
		local mid = floor((lo + hi) / 2)
		if list[mid][1] <= t then lo = mid + 1 else hi = mid - 1 end
	end
	local i = list[hi]
	if i and (t < i[2] or (t == i[2] and i[2] >= dur)) then return i, hi end
	return nil
end

---------------------------------------------------------------------------------------------------------------------
-- The indexes of an open replay (made once: the detail then makes nothing)
---------------------------------------------------------------------------------------------------------------------
-- Why an event ends what a reading said, for a row with a number and for a state-only one (which goes on in state
-- only); nil when it does not.
local function breaks(mk)
	local k = mk.k
	if k == "T" then return "target", "target" end
	if k == "c" then return "combat", "combat" end
	if k == "G" then return "tick", "tick" end
	if k == "M" then
		if mk.mode == "none" then return mk.reason or "other", mk.reason or "other" end
		if mk.mode == "state" then return "state-only", nil end
	end
	if k == "Z" and (mk.a == "r" or mk.a == "t") then return "limit", "limit" end
	return nil, nil
end

-- A list of { t, why, order } as two arrays in order of time.
local function breakList(entries)
	sort(entries, function(x, y)
		if x[1] ~= y[1] then return x[1] < y[1] end
		return x[3] < y[3]
	end)
	local times, why = {}, {}
	for i, e in ipairs(entries) do times[i], why[i] = e[1], e[2] end
	return { t = times, why = why, n = #entries }
end

-- Per unit all its rows (the model's series keep only the ones with a number) and, for each, the first of its run on
-- the same mob; the breaks of a reading and of a state-only row, and each unit's exits from the list; the ends of the
-- gaps of the whole chart (a paused recording starts at no event).
local function index(model)
	local d = model.d
	local rows, run, exits, marks = {}, {}, {}, {}
	for u = 1, #model.units do rows[u], run[u], exits[u] = {}, {}, {} end
	for i = 1, d.n do
		local u = d.u[i]
		local list = rows[u]
		if list then
			local k = #list + 1
			list[k] = i
			run[u][k] = (k > 1 and d.m[list[k - 1]] == d.m[i]) and run[u][k - 1] or k
		end
	end
	local numbered, situation, order = {}, {}, 0
	local function add(list, t, why)
		if why then
			order = order + 1
			list[#list + 1] = { t, why, order }
		end
	end
	for _, mk in ipairs(model.events) do
		local a, b = breaks(mk)
		add(numbered, mk.t, a)
		add(situation, mk.t, b)
		if mk.k == "S" and mk.kind == "leave" and exits[mk.u] then
			local list = exits[mk.u]
			list[#list + 1] = mk.t
		end
	end
	for _, g in ipairs(model.gaps) do
		marks[#marks + 1] = g[1]
		marks[#marks + 1] = g[2]
		if g[3] == "tick" then
			add(numbered, g[1], "tick")
			add(situation, g[1], "tick")
		end
	end
	sort(marks)
	return { rows = rows, run = run, exits = exits, numbered = breakList(numbered), situation = breakList(situation),
		marks = marks, events = {} }
end

-- How much recorded the cursor has passed: every part only grows with the time, so the sum changes exactly when one
-- of them does.
local function passed(model, t)
	local d = model.d
	return countEvents(model.events, t) + countTimes(d.t, d.n, t) + countTimes(d.t, d.n, t - model.join - EPSILON, true)
		+ countTimes(d.t, d.n, t - Timeline.ESTIMATE_MAX - EPSILON, true) + countTimes(data.marks, #data.marks, t)
end

local function updateMoment(st)
	local n = passed(st.model, st.cursor)
	if n ~= data.passed then
		data.passed = n
		st.moment = st.moment + 1
	end
end

-- The focused event stays while the cursor is inside its window; leaving it drops focus and selection.
local function dropFocus(st)
	local i = st.focus
	if not i then return end
	local t = st.model.events[i].t
	if st.cursor >= t - Replay.WINDOW and st.cursor <= t + Replay.WINDOW then return end
	st.focus, st.selection = nil, nil
	notify("focus")
end

---------------------------------------------------------------------------------------------------------------------
-- Opening and closing (§5.2)
---------------------------------------------------------------------------------------------------------------------
local function remember()
	local median, highest, ticks = Scheduler.Cost(TICK)
	if ticks then cost = { median = median, max = highest, ticks = ticks } end
end

local function stopTick()
	if Scheduler.IsRunning(TICK) then
		remember()
		Scheduler.Stop(TICK)
	end
end

local function drop()
	stopTick()
	Replay.state, session, data = nil, nil, nil
end

function Replay.Close()
	generation = generation + 1
	building = nil
	if not Replay.state then return false end
	drop()
	notify("closed")
	return true
end

local function validSpeed(x)
	for _, s in ipairs(Replay.SPEEDS) do
		if s == x then return true end
	end
	return false
end

function Replay.Speed()
	if chosenSpeed then return chosenSpeed end
	local saved = ns.Config and ns.Config:Get(Replay.SPEED_PATH)
	if validSpeed(saved) then return saved end
	return Replay.SPEEDS[1]
end

local function onCombatStarted()
	local st = Replay.state
	if not st then return end
	if Replay.PAUSE_IN_COMBAT and st.playing then Replay.Pause() else notify("play") end
end

local function onCombatEnded()
	if Replay.state then notify("play") end
end

local function onSessionsChanged()
	local st = Replay.state
	if not st or Storage.Get(st.id) == session then return end
	generation = generation + 1
	drop()
	notify("closed", "unknown")
end

local function listen()
	if listening or not ns.Bus then return end
	listening = true
	ns.Bus.On("COMBAT_STARTED", onCombatStarted)
	ns.Bus.On("COMBAT_ENDED", onCombatEnded)
	ns.Bus.On("SESSIONS_CHANGED", onSessionsChanged)
end

function Replay.Listening() return listening end

local function setUp(model, s, t)
	session, data = s, index(model)
	local first = model.combat[1] and model.combat[1][1] or 0
	local cursor = (type(t) == "number" and t == t) and t or first
	local a, b = Timeline.Clamp(model, 0, model.dur)
	local series = {}
	for i, u in ipairs(model.series) do series[i] = u end
	Replay.state = {
		id = s.id, model = model, cursor = max(0, min(cursor, model.dur)), playing = false, speed = Replay.Speed(),
		view = { a, b }, selection = nil, focus = nil, filter = "key", series = series, moment = 1,
		manual = {},                -- the series the player chose (the others came by themselves)
	}
	data.passed = passed(model, Replay.state.cursor)
end

function Replay.Open(id, t, done)
	done = done or noop
	if not on() then done(false, "off") return end
	listen()
	drop()
	generation = generation + 1
	local mine = generation
	opened = mine
	building = id
	Timeline.Build(id, function(model, why)
		if mine ~= generation then
			done(false, opened > mine and "replaced" or "closed")
			return
		end
		building = nil
		if not model then done(false, why) return end
		local s = Storage.Get(id)
		if not s then done(false, "unknown") return end
		setUp(model, s, t)
		notify("model")
		done(true)
	end)
end

function Replay.Building() return building end

function Replay.OnChange(fn)
	listener = type(fn) == "function" and fn or nil
end

---------------------------------------------------------------------------------------------------------------------
-- The cursor and the playback (§5.2)
---------------------------------------------------------------------------------------------------------------------
-- The time playback stops at: the end of the view, never past the end of the session.
local function endOfView(st)
	return min(st.view[2], st.model.dur)
end

-- The view moved, keeping its width, so that it holds the cursor.
local function follow(st)
	local view, t = st.view, st.cursor
	if t >= view[1] and t <= view[2] then return end
	local width = view[2] - view[1]
	local a = max(0, min(floor(t - width / 2 + 0.5), st.model.dur - width))
	view[1], view[2] = a, a + width
	notify("view")
end

local function moveTo(st, t)
	st.cursor = max(0, min(t, st.model.dur))
	follow(st)
	dropFocus(st)
	updateMoment(st)
	notify("cursor")
end

local function tick()
	local st = Replay.state
	if not st or not st.playing then
		Scheduler.Stop(TICK)
		return
	end
	local now = Compat.Now()
	local elapsed = now - lastTick
	lastTick = now
	if elapsed < 0 then elapsed = 0 elseif elapsed > Replay.MAX_STEP then elapsed = Replay.MAX_STEP end
	local stop = endOfView(st)
	-- kept to a thousandth of a second, so that the steps of the clock do not add up an error
	local t = floor((st.cursor + st.speed * elapsed * 10) * 100 + 0.5) / 100
	local ended = t >= stop
	if ended then t = stop end
	if t ~= st.cursor then
		st.cursor = t
		dropFocus(st)
		updateMoment(st)
		notify("cursor")
	end
	if ended and Replay.state == st then Replay.Pause() end
end

-- True when Play would start, else false and why ("closed", "combat").
function Replay.CanPlay()
	if not Replay.state then return false, "closed" end
	if Replay.PAUSE_IN_COMBAT and inCombat() then return false, "combat" end
	return true
end

function Replay.Play()
	local ok, why = Replay.CanPlay()
	if not ok then return false, why end
	local st = Replay.state
	if st.playing then return true end
	if st.cursor >= endOfView(st) or st.cursor < st.view[1] then moveTo(st, st.view[1]) end
	lastTick = Compat.Now()
	if not Scheduler.Start(TICK, Replay.HZ, tick) then return false, "no-timer" end
	st.playing = true
	notify("play")
	return true
end

function Replay.Pause()
	local st = Replay.state
	if not st then return false end
	if not st.playing then return true end
	st.playing = false
	stopTick()
	notify("play")
	return true
end

function Replay.Toggle()
	local st = Replay.state
	if not st then return false, "closed" end
	if st.playing then return Replay.Pause() end
	return Replay.Play()
end

function Replay.Seek(t)
	local st = Replay.state
	if not st or type(t) ~= "number" or t ~= t then return false end
	moveTo(st, t)
	return true
end

-- The next (dir > 0) or previous recorded moment after the cursor: a reading of a shown series or an event; else the
-- end or the start. Playback stops.
function Replay.Step(dir)
	local st = Replay.state
	if not st or type(dir) ~= "number" or dir == 0 then return false end
	Replay.Pause()
	local model, t = st.model, st.cursor
	local dt, events = model.d.t, model.events
	local forward = dir > 0
	local best = forward and model.dur or 0
	local function consider(v)
		if forward then
			if v > t and v < best then best = v end
		elseif v < t and v > best then
			best = v
		end
	end
	for _, u in ipairs(st.series) do
		local se = model.units[u]
		local k = countRows(se.rows, se.readings, dt, t, not forward)
		local i = se.rows[forward and k + 1 or k]
		if i then consider(dt[i]) end
	end
	local k = countEvents(events, t, not forward)
	local e = events[forward and k + 1 or k]
	if e then consider(e.t) end
	moveTo(st, best)
	return true
end

function Replay.Jump(dir)
	local st = Replay.state
	if not st or type(dir) ~= "number" or dir == 0 then return false end
	moveTo(st, st.cursor + (dir > 0 and Replay.JUMP or -Replay.JUMP))
	return true
end

---------------------------------------------------------------------------------------------------------------------
-- The view, the speed, the series and the filter (§5.2, §5.4)
---------------------------------------------------------------------------------------------------------------------
function Replay.SetSpeed(x)
	if not validSpeed(x) then return false end
	chosenSpeed = x
	-- refused while the character data have no key for it (schema 1) or are read-only: the choice stays for this load
	if ns.Config then ns.Config:Set(Replay.SPEED_PATH, x) end
	local st = Replay.state
	if st then
		st.speed = x
		notify("play")
	end
	return true
end

local function setView(st, a, b)
	a, b = Timeline.Clamp(st.model, a, b)
	local limit = max(st.model.dur, Timeline.MIN_VIEW)
	if b > limit then
		a = max(0, a - (b - limit))
		b = limit
	end
	st.view[1], st.view[2] = a, b
	if st.playing and (st.cursor < a or st.cursor >= b) then Replay.Pause() end
	notify("view")
end

function Replay.SetView(a, b)
	local st = Replay.state
	if not st or type(a) ~= "number" or type(b) ~= "number" or a ~= a or b ~= b then return false end
	if b < a then a, b = b, a end
	setView(st, a, b)
	return true
end

function Replay.WholeFight()
	local st = Replay.state
	if not st then return false end
	setView(st, 0, st.model.dur)
	return true
end

local function validUnit(model, u)
	return type(u) == "number" and model.units[u] ~= nil
end

function Replay.SetSeries(list)
	local st = Replay.state
	if not st or type(list) ~= "table" then return false end
	local series, manual = {}, {}
	for _, u in ipairs(list) do
		if #series >= Timeline.MAX_SERIES then break end
		if validUnit(st.model, u) and not manual[u] then
			series[#series + 1] = u
			manual[u] = true
		end
	end
	st.series, st.manual = series, manual
	notify("series")
	return true
end

-- A click on a unit's name (§5.4): shown or taken off; with MAX_SERIES shown, it takes the place of the last one that
-- was not chosen by the player (of the last one when they chose all).
function Replay.ToggleSeries(u)
	local st = Replay.state
	if not st or not validUnit(st.model, u) then return false end
	local series = st.series
	for j = 1, #series do
		if series[j] == u then
			table.remove(series, j)
			st.manual[u] = nil
			notify("series")
			return true
		end
	end
	if #series < Timeline.MAX_SERIES then
		series[#series + 1] = u
	else
		local place = #series
		for j = #series, 1, -1 do
			if not st.manual[series[j]] then
				place = j
				break
			end
		end
		st.manual[series[place]] = nil
		series[place] = u
	end
	st.manual[u] = true
	notify("series")
	return true
end

function Replay.SetFilter(f)
	local st = Replay.state
	if not st or (f ~= "key" and f ~= "alerts" and f ~= "all") then return false end
	if st.filter ~= f then
		st.filter = f
		notify("filter")
	end
	return true
end

---------------------------------------------------------------------------------------------------------------------
-- The event list (§5.4)
---------------------------------------------------------------------------------------------------------------------
local KEY_KINDS = { C = true, c = true, T = true, A = true, D = true, N = true, M = true, X = true, Z = true }
Replay.KEY_PAUSE = 10                -- tenths: a shorter recording pause is not a key event

local function matches(mk, filter)
	if filter == "all" then return true end
	if filter == "alerts" then return mk.k == "L" or mk.k == "H" end
	if mk.k == "S" then return mk.kind == "cross" end
	if mk.k == "G" then return (mk.n or 0) >= Replay.KEY_PAUSE end
	return KEY_KINDS[mk.k] == true
end

-- The events of a filter (default the one in force), in order of time: { indexes into model.events, onlyCombat = true
-- when the recording has nothing but the start and the end of combat }. Made once per filter and replay.
function Replay.Events(filter)
	local st = Replay.state
	if not st then return nil end
	filter = filter or st.filter
	if filter ~= "key" and filter ~= "alerts" and filter ~= "all" then return nil end
	local list = data.events[filter]
	if not list then
		list = { onlyCombat = true }
		for i, mk in ipairs(st.model.events) do
			if mk.k ~= "C" and mk.k ~= "c" then list.onlyCombat = false end
			if matches(mk, filter) then list[#list + 1] = i end
		end
		data.events[filter] = list
	end
	return list
end

-- The position in the list in force of the last event at or before the cursor (0: none), for the highlighted row.
function Replay.LastRow()
	local st = Replay.state
	if not st then return 0 end
	local list, events, t = Replay.Events(), st.model.events, st.cursor
	local lo, hi = 1, #list
	while lo <= hi do
		local mid = floor((lo + hi) / 2)
		if events[list[mid]].t <= t then lo = mid + 1 else hi = mid - 1 end
	end
	return hi
end

-- The event `i` of model.events: cursor at its time, paused, its window selected and, on a longer session, in view.
function Replay.Focus(i)
	local st = Replay.state
	local mk = st and st.model.events[i]
	if not mk then return false end
	Replay.Pause()
	local dur = st.model.dur
	local a, b = max(mk.t - Replay.WINDOW, 0), min(mk.t + Replay.WINDOW, dur)
	st.cursor = max(0, min(mk.t, dur))
	st.focus = i
	st.selection = { a, b }
	if dur > Replay.FOCUS_ZOOM then setView(st, a, b) else follow(st) end
	updateMoment(st)
	notify("cursor")
	notify("focus")
	return true
end

-- The next (dir > 0) or previous event of the filter in force, focused. From the focused event the list goes on one by
-- one (several events share a time); else the first after, or the last before, the cursor.
function Replay.NextEvent(dir)
	local st = Replay.state
	if not st or type(dir) ~= "number" or dir == 0 then return false end
	local list, events, t = Replay.Events(), st.model.events, st.cursor
	local forward = dir > 0
	local focus = st.focus
	local found
	if focus and events[focus].t == t then
		if forward then
			for j = 1, #list do
				if list[j] > focus then found = list[j] break end
			end
		else
			for j = #list, 1, -1 do
				if list[j] < focus then found = list[j] break end
			end
		end
	elseif forward then
		for j = 1, #list do
			if events[list[j]].t > t then found = list[j] break end
		end
	else
		for j = #list, 1, -1 do
			if events[list[j]].t < t then found = list[j] break end
		end
	end
	if not found then return false end
	return Replay.Focus(found)
end

---------------------------------------------------------------------------------------------------------------------
-- The detail at a time (§5.3)
---------------------------------------------------------------------------------------------------------------------
-- The first thing recorded in (from, to] that ends what unit u's row at `from` said: nil, or why. With `numbered` a
-- change to state only breaks too (the percentage is gone). What ends at the end of the axis does not count there.
local function broken(model, u, from, to, numbered)
	to = min(to, model.dur - EPSILON)
	local list = numbered and data.numbered or data.situation
	local k = countTimes(list.t, list.n, from) + 1
	local at, why = list.t[k], list.why[k]
	if at and at > to then at, why = nil, nil end
	local exits = data.exits[u]
	local x = exits[countTimes(exits, #exits, from) + 1]
	if x and x <= to and (not at or x < at) then return "exit" end
	return why
end

-- The last row with a number of unit u on mob m at or before its k-th row (the position in its rows); nil for none.
local function lastNumbered(model, u, m, k)
	local list, run, d = data.rows[u], data.run[u], model.d
	while k >= 1 do
		local i = list[k]
		if d.m[i] ~= m then
			k = run[k] - 1                  -- the whole run on another mob
		elseif NUMBERED[d.s[i]] then
			return k
		else
			k = k - 1
		end
	end
	return nil
end

-- What was readable of unit u on mob m at time t, written into `row`.
local function reading(model, row, u, m, t)
	local d = model.d
	local list = data.rows[u]
	row.kind, row.category, row.p, row.readingT, row.age, row.lower = "unknown", "unknown", nil, nil, nil, false
	row.situation, row.reason, row.since = nil, "not-read", nil
	local k = countRows(list, #list, d.t, t)
	while k >= 1 and d.m[list[k]] ~= m do k = data.run[u][k] - 1 end
	if k < 1 then return end
	local i = list[k]
	local code, tr = d.s[i], d.t[i]
	if NUMBERED[code] then
		local why = broken(model, u, tr, t, true)
		local age = t - tr
		if not why and age > Timeline.ESTIMATE_MAX + EPSILON then why = "stale" end
		if why then
			row.reason, row.since = why, tr
			return
		end
		local p = d.p[i]
		row.p, row.readingT, row.age, row.reason = p, tr, age, nil
		row.lower = p >= Session.MAX_N
		if age <= model.join + EPSILON then
			row.kind, row.category = "value", row.lower and "estimated" or "detected"
		else
			row.kind, row.category = "estimate", "estimated"
		end
		return
	end
	local situation = SITUATION[code]
	local why
	if situation then
		why = broken(model, u, tr, t, false)
		if not why then
			row.kind, row.category, row.reason = "situation", "detected", nil
			row.situation, row.readingT = situation, tr
			return
		end
	else
		why = ROW_REASON[code] or "other"
	end
	row.reason = why
	local n = lastNumbered(model, u, m, k)
	if n then
		row.since = d.t[list[n]]
	else
		-- never a number on this mob: missing since the first row of this stretch
		row.since = d.t[list[data.run[u][k]]]
	end
end

local function unitRow(model, out, u, m, t, shown)
	local se = model.units[u]
	local present = holding(se.present, t, model.dur)
	if not present or present[3] ~= m then return end
	if out.nunits >= Replay.MAX_UNITS then
		out.more = out.more + 1
		return
	end
	local n = out.nunits + 1
	out.nunits = n
	local row = out.units[n]
	if not row then
		row = {}
		out.units[n] = row
	end
	row.u, row.shown = u, shown
	local st = holding(se.states, t, model.dur)
	if st and st[4] == m then
		row.state = st[3]
		if st[3] == "U" then
			row.stateCategory = "unknown"
		else
			row.stateCategory = out.mode == "state" and "detected" or "calculated"
		end
	else
		row.state, row.stateCategory = nil, "unknown"
	end
	reading(model, row, u, m, t)
end

-- The detail at time t (default the cursor), nil without an open replay. out = { t, combat, pull, pulls,
-- combatCategory, mob, mobCategory, nomob, mode, modeReason, modeCategory, gaps (ngaps), holder, holderTank,
-- holderCategory, units (nunits rows: the shown series first), more }. Out of combat nothing was read: no mob, no
-- mode, no holder, no unit.
function Replay.Snapshot(t, out)
	local st = Replay.state
	if not st then return nil end
	local model = st.model
	local dur = model.dur
	t = max(0, min(type(t) == "number" and t or st.cursor, dur))
	out = out or {}
	out.gaps = out.gaps or {}
	out.units = out.units or {}
	out.t, out.ngaps, out.nunits, out.more = t, 0, 0, 0

	local period, pull = holding(model.combat, t, dur)
	out.combat, out.pull, out.pulls, out.combatCategory = period ~= nil, pull, #model.combat, "detected"
	out.mob, out.mobCategory, out.nomob = nil, "unknown", nil
	out.mode, out.modeReason, out.modeCategory = nil, nil, "unknown"
	out.holder, out.holderTank, out.holderCategory = nil, false, "unknown"
	if not period then return out end

	local gaps = model.gaps
	for j = 1, #gaps do
		local g = gaps[j]
		if g[1] > t then break end
		if t < g[2] or (t == g[2] and g[2] >= dur) then
			if g[3] == "nomob" then
				out.nomob = g
			end
			out.ngaps = out.ngaps + 1
			out.gaps[out.ngaps] = g
		end
	end

	local watched = holding(model.mobs, t, dur)
	local m = watched and watched[3]
	if m then
		out.mob = m
		local info = model.mobInfo[m]
		out.mobCategory = (info and info.name) and "detected" or "unknown"
	elseif out.nomob then
		out.mobCategory = "detected"
	end

	local band = holding(model.modes, t, dur)
	if band then
		out.mode, out.modeReason = band[3], band[4]
		out.modeCategory = band[3] == "none" and "unknown" or "detected"
	end
	if not m then return out end

	for u = 1, #model.units do
		local held = holding(model.units[u].holds, t, dur)
		if held and held[3] == m then
			out.holder, out.holderCategory = u, "detected"
			out.holderTank = model.info[u].role == "TANK"
			break
		end
	end

	local series = st.series
	for j = 1, #series do unitRow(model, out, series[j], m, t, true) end
	for u = 1, #model.units do
		local shown = false
		for j = 1, #series do
			if series[j] == u then shown = true break end
		end
		if not shown then unitRow(model, out, u, m, t, false) end
	end
	return out
end

---------------------------------------------------------------------------------------------------------------------
-- Missing data and the detail of an event (§5.3, RPL-08)
---------------------------------------------------------------------------------------------------------------------
-- The times of [from, to] inside combat, as pairs, passed to fn.
local function inPeriods(model, from, to, fn)
	for _, p in ipairs(model.combat) do
		local x, y = max(from, p[1]), min(to, p[2])
		if y > x then fn(x, y) end
	end
end

-- True when unit u was on the list while values were readable somewhere in [a, b]; and that first time.
local function listedWithValues(model, u, a, b)
	local first, last
	for _, p in ipairs(model.units[u].present) do
		local x, y = max(p[1], a), min(p[2], b)
		if y > x then
			for _, band in ipairs(model.modes) do
				if band[3] == "values" then
					local from, to = max(x, band[1]), min(y, band[2])
					if to > from then
						inPeriods(model, from, to, function(s, e)
							first = first and min(first, s) or s
							last = last and max(last, e) or e
						end)
					end
				end
			end
		end
	end
	return first, last
end

-- What is missing in [a, b]: { a, b, [i] = { kind, from, to, reason, unit } } in order of time, cut to the interval:
-- the gaps of the whole chart (mode, nomob, tick, limit), the stretches in state only (no percentages), the gaps of
-- each unit (unknown, stale) and the units listed while values were readable without a single reading (noreading).
-- A table with nothing in it: nothing is missing.
function Replay.Missing(a, b, out)
	local st = Replay.state
	if not st then return nil end
	local model = st.model
	out = out or {}
	for i = #out, 1, -1 do out[i] = nil end
	a, b = max(0, a or 0), min(b or model.dur, model.dur)
	out.a, out.b = a, b
	local function add(kind, from, to, reason, unit, whole)
		from, to = max(from, a), min(to, b)
		if to > from then
			out[#out + 1] = { kind = kind, from = from, to = to, reason = reason, unit = unit, start = whole }
		end
	end
	for _, g in ipairs(model.gaps) do add(g[3], g[1], g[2], g[4], nil, g[1]) end
	for _, band in ipairs(model.modes) do
		if band[3] == "state" then
			inPeriods(model, band[1], band[2], function(x, y) add("state", x, y, "state-only") end)
		end
	end
	for u, se in ipairs(model.units) do
		local before = #out
		for _, g in ipairs(se.unknown) do add(g[3], g[1], g[2], g[4], u) end
		if #out == before then
			local from, to = listedWithValues(model, u, a, b)
			if from then
				local k = countRows(se.rows, se.readings, model.d.t, a, true) + 1
				local i = se.rows[k]
				if not i or model.d.t[i] > b then add("noreading", from, to, nil, u) end
			end
		end
	end
	sort(out, function(x, y)
		if x.from ~= y.from then return x.from < y.from end
		if (x.unit or 0) ~= (y.unit or 0) then return (x.unit or 0) < (y.unit or 0) end
		return x.kind < y.kind
	end)
	return out
end

-- The detail of event `i`: { index, event, t, category, confidence, a, b (its window), units = { { u, count, firstP,
-- firstT, lastP, lastT, maxP, maxT } } for the units it names, missing = Missing(a, b) }.
function Replay.EventDetail(i, out)
	local st = Replay.state
	local mk = st and st.model.events[i]
	if not mk then return nil end
	local model = st.model
	out = out or {}
	local a, b = max(mk.t - Replay.WINDOW, 0), min(mk.t + Replay.WINDOW, model.dur)
	out.index, out.event, out.t, out.category, out.confidence = i, mk, mk.t, mk.category, mk.confidence
	out.a, out.b = a, b
	out.units = {}
	local dt, dp = model.d.t, model.d.p
	local function involve(u)
		local se = u and model.units[u]
		if not se then return end
		for _, seen in ipairs(out.units) do
			if seen.u == u then return end
		end
		local r = { u = u, count = 0 }
		for k = countRows(se.rows, se.readings, dt, a, true) + 1, se.readings do
			local row = se.rows[k]
			local t = dt[row]
			if t > b then break end
			local p = dp[row]
			r.count = r.count + 1
			if r.count == 1 then r.firstP, r.firstT = p, t end
			r.lastP, r.lastT = p, t
			if not r.maxP or p > r.maxP then r.maxP, r.maxT = p, t end
		end
		out.units[#out.units + 1] = r
	end
	involve(mk.u)
	if mk.k == "A" then involve(mk.v) end
	out.missing = Replay.Missing(a, b, out.missing)
	return out
end

---------------------------------------------------------------------------------------------------------------------
-- Words (ADR 0009; RPL-03: no cause, no hypothesis; RPL-07: a missing value says why and since when)
---------------------------------------------------------------------------------------------------------------------
Replay.WHY_KEYS = {
	["state-only"] = "REPLAY_WHY_STATE_ONLY", target = "REPLAY_WHY_TARGET", tick = "REPLAY_WHY_TICK",
	limit = "REPLAY_WHY_LIMIT", combat = "REPLAY_WHY_COMBAT", exit = "REPLAY_WHY_EXIT",
	["not-read"] = "REPLAY_WHY_NOT_READ",
}
Replay.SITUATION_KEYS = { [0] = "REPLAY_SITUATION_0", [1] = "REPLAY_SITUATION_1", [2] = "REPLAY_SITUATION_2",
	[3] = "REPLAY_SITUATION_3" }
Replay.FILTER_KEYS = { key = "REPLAY_FILTER_KEY", alerts = "REPLAY_FILTER_ALERTS", all = "REPLAY_FILTER_ALL" }
local NOMOB_MISSING = { none = "REPLAY_MISSING_NOMOB", died = "REPLAY_MISSING_DIED", lost = "REPLAY_MISSING_LOST" }
local CONFIDENCE_KEYS = { high = "CONF_HIGH", medium = "CONF_MEDIUM", low = "CONF_LOW" }

local TimeText = Timeline.TimeText

function Replay.WhyText(reason)
	local key = Replay.WHY_KEYS[reason or ""]
	if key then return ns.L[key] end
	return Timeline.ReasonText(reason)
end

function Replay.CombatText(snap)
	local L = ns.L
	if not snap.combat then return L.REPLAY_OUT_OF_COMBAT end
	if snap.pulls > 1 then return L.REPLAY_COMBAT_PULL:format(snap.pull) end
	return L.REPLAY_COMBAT
end

-- The mob, or why there is none; nil out of combat.
function Replay.MobText(model, snap)
	if not snap.combat then return nil end
	if snap.mob then return Timeline.MobName(model, snap.mob) end
	if snap.nomob then return Timeline.GapText(snap.nomob) end
	return ns.L.TIMELINE_GAP_NOMOB
end

function Replay.ModeText(snap)
	local L = ns.L
	if not snap.combat then return nil end
	if snap.mode == "values" then return L.REPLAY_MODE_VALUES end
	if snap.mode == "state" then return L.REPLAY_MODE_STATE end
	if snap.mode == "none" then return L.REPLAY_MODE_NONE:format(Timeline.ReasonText(snap.modeReason)) end
	return L.REPLAY_MODE_UNKNOWN
end

function Replay.HolderText(model, snap)
	local L = ns.L
	if not snap.mob then return nil end
	if not snap.holder then return L.REPLAY_HOLDER_UNKNOWN end
	local key = snap.holderTank and "REPLAY_HOLDS_TANK" or "REPLAY_HOLDS"
	return L[key]:format(Timeline.UnitName(model, snap.holder))
end

-- The state word of a unit's row; nil without a state.
function Replay.StateText(row)
	local key = Timeline.STATE_KEYS[row.state or ""]
	return key and ns.L[key] or nil
end

-- What a unit's row shows: "62.4 %", "~62.4 % · 1.8 s before", the game's situation, or "No reading since ...".
function Replay.ReadingText(row)
	local L = ns.L
	if row.kind == "value" then return Timeline.PercentText(row.p) end
	if row.kind == "estimate" then return L.REPLAY_ESTIMATE:format(Timeline.PercentText(row.p), row.age / 10) end
	if row.kind == "situation" then return L[Replay.SITUATION_KEYS[row.situation]] end
	if row.since then return L.REPLAY_SINCE:format(TimeText(row.since), Replay.WhyText(row.reason)) end
	return L.REPLAY_NONE_RECORDED:format(Replay.WhyText(row.reason))
end

-- The tooltip's explanation of an estimate; nil for the others.
function Replay.ReadingTip(row)
	if row.kind ~= "estimate" then return nil end
	return ns.L.REPLAY_ESTIMATE_TIP:format(row.age / 10)
end

function Replay.MissingText(model, entry)
	local L, kind = ns.L, entry.kind
	local from, to = TimeText(entry.from), TimeText(entry.to)
	if kind == "noreading" then
		return L.REPLAY_MISSING_UNIT_WINDOW:format(Timeline.UnitName(model, entry.unit))
	end
	if entry.unit then
		return L.REPLAY_MISSING_UNIT:format(Timeline.UnitName(model, entry.unit), from, to,
			Timeline.ReasonText(entry.reason))
	end
	if kind == "mode" then return L.REPLAY_MISSING_MODE:format(from, to, Timeline.ReasonText(entry.reason)) end
	if kind == "state" then return L.REPLAY_MISSING_STATE:format(from, to) end
	if kind == "nomob" then return L[NOMOB_MISSING[entry.reason or ""] or "REPLAY_MISSING_NOMOB"]:format(from, to) end
	if kind == "tick" then return L.REPLAY_MISSING_TICK:format(from, to) end
	return L.REPLAY_MISSING_LIMIT:format(TimeText(entry.start or entry.from))
end

-- The lines of a Missing result: its entries, or "No missing data in this window".
function Replay.MissingLines(model, missing)
	local lines = {}
	for i = 1, #missing do lines[i] = Replay.MissingText(model, missing[i]) end
	if #lines == 0 then lines[1] = ns.L.REPLAY_MISSING_NONE end
	return lines
end

-- The readings of a unit around an event (EventDetail).
function Replay.EventReadingText(model, r)
	local L, name = ns.L, Timeline.UnitName(model, r.u)
	if r.count == 0 then return L.REPLAY_MISSING_UNIT_WINDOW:format(name) end
	if r.count == 1 then
		return L.REPLAY_EVENT_ONE:format(name, Timeline.PercentText(r.firstP), TimeText(r.firstT))
	end
	return L.REPLAY_EVENT_READINGS:format(name, r.count, Timeline.PercentText(r.firstP),
		Timeline.PercentText(r.lastP), Timeline.PercentText(r.maxP))
end

-- The recorded confidence of an alert or a Coach tip; nil for the other events.
function Replay.ConfidenceText(detail)
	if not detail.confidence then return nil end
	return ns.L.REPLAY_CONFIDENCE:format(ns.L[CONFIDENCE_KEYS[detail.confidence] or "CAT_UNKNOWN"])
end

-- The note of an event list; nil when it has rows to show and more than the start and the end of combat.
function Replay.ListNote(list)
	if list.onlyCombat and #list > 0 then return ns.L.REPLAY_ONLY_COMBAT end
	if #list == 0 then return ns.L.REPLAY_NO_EVENTS end
	return nil
end

---------------------------------------------------------------------------------------------------------------------
-- /atw debug, in the section Timeline and replay (SPEC-05 §9): switches, counts and costs, never a name
---------------------------------------------------------------------------------------------------------------------
function Replay.DebugLines(lines)
	lines = lines or {}
	if not on() then
		lines[#lines + 1] = "replay: off"
		return lines
	end
	local st = Replay.state
	if not st then
		lines[#lines + 1] = building and "replay: opening" or "replay: closed"
	else
		lines[#lines + 1] = ("replay: open, %s, speed %dx"):format(st.playing and "playing" or "paused", st.speed)
	end
	if Scheduler.IsRunning(TICK) then remember() end
	if cost and cost.median then
		lines[#lines + 1] = ("replay tick: %d ticks, %.3f ms median, %.3f ms max"):format(cost.ticks, cost.median,
			cost.max)
	else
		lines[#lines + 1] = "replay tick: not measured"
	end
	return lines
end

if ns.addon then ns.addon.Replay = Replay end
