-- What a view of the Threat Timeline may cost (run_tests.py --long, SPEC-05 §4.7, M5.2): Timeline.View over a whole
-- session at the row limit (30 000 rows: 40 units for 750 recording ticks, every unit read at every tick), with the
-- six default series and with all 40 units as series (every row passed), at the widest 400 columns. The view is
-- synchronous (it runs when the chart is drawn, zoomed or dragged), so its work is bounded here; the build of the model
-- is in slices (SPEC-05 §4.2) and its work is only logged. Offline numbers on the mock client: the cost in the game is
-- the probe's P10.
--
-- Work is counted in Lua VM instructions (T.instructions), the same on every machine; allocation is the growth of the
-- Lua state with the collector stopped, after a warm-up view of the same width.

local UNITS, TICKS, STEP = 40, 750, 5     -- 30 000 rows, one tick every 5 tenths (2 Hz)

-- SPEC-05 §4.7 proposed 2 000 000 instructions for a view of the whole session at 30 000 rows. M5.2 measured about
-- 132 000 with the six default series and 884 000 with all 40 units, 0 bytes once warm; computing the model of such a
-- session is about 2.5 million, in slices. The budget stays the proposal.
local BUDGET = { instructions = 2000000, bytes = 512 }

before_boot(function(M)
	M.features = { monitor = true, alerts = true, coach = true, recording = true, reports = true, timeline = true }
end)

-- A session at the row limit, made with the Session API: the tank holds the mob, the others climb and fall.
local function fullSession()
	local S = Mock.ns.Session
	local s = S.New{ id = "budget-1", started = 3000, group = "raid", rec = { hz = 2, warning = 80, danger = 95,
		mode = "values" } }
	for u = 1, UNITS do
		S.AddUnit(s, { name = "Raider" .. u, token = "raid" .. u, me = u == 1 or nil, role = u <= 2 and "TANK" or nil }, 0)
	end
	S.AddMob(s, { name = "Boss" }, 0)
	S.AddEvent(s, 0, "C", 0, 0, 0, "1")
	S.AddEvent(s, 0, "M", 0, 0, 0, "v")
	S.AddEvent(s, 0, "T", 1)
	S.AddEvent(s, 0, "A", 1, 2, 0, "1")
	for u = 1, UNITS do S.AddEvent(s, 0, "S", 1, u, 0, "S", "-") end
	for tick = 1, TICKS do
		local t = tick * STEP
		for u = 1, UNITS do
			local p = u == 2 and 1000 or ((tick * 7 + u * 13) % 1100)
			truthy(S.AddRow(s, t, 1, u, p, p >= 1000 and "3" or "0"))
		end
	end
	S.AddEvent(s, TICKS * STEP + 5, "c")
	S.Join(s)
	s.state, s.ended, s.dur, s.fight = "complete", "combat", TICKS * STEP + 5, TICKS * STEP + 5
	eq(s.n, Mock.ns.Session.LIMITS.rows)
	return s
end

describe("the cost of a timeline view (SPEC-05 §4.7)", function()
	it("keeps a whole-session view at 30 000 rows within the budget, and makes nothing once warm", function()
		local TL = Mock.ns.Timeline
		local s = fullSession()
		local d = assert(Mock.ns.Session.Decode(s))
		local m
		local build = T.instructions(function() m = TL.Compute(s, d) end, 1000)
		T.log(("compute: %d instructions for %d rows and %d events (in slices of %d in the game)"):format(build,
			d.n, d.ne, TL.SLICE))
		eq(#m.series, TL.MAX_SERIES)
		local all = {}
		for u = 1, UNITS do all[u] = u end
		for _, case in ipairs({ { "the default series", m.series }, { "all 40 units", all } }) do
			local out = TL.View(m, 0, m.dur, TL.MAX_BUCKETS, case[2], {})   -- warm-up: the tables of the columns
			local work = T.instructions(function() TL.View(m, 0, m.dur, TL.MAX_BUCKETS, case[2], out) end)
			collectgarbage("collect")
			collectgarbage("collect")
			collectgarbage("stop")
			local before = collectgarbage("count")
			TL.View(m, 0, m.dur, TL.MAX_BUCKETS, case[2], out)
			local bytes = (collectgarbage("count") - before) * 1024
			collectgarbage("restart")
			T.log(("view with %s: %d instructions, %d bytes"):format(case[1], work, bytes))
			truthy(work <= BUDGET.instructions, ("work: %d instructions, budget %d"):format(work, BUDGET.instructions))
			truthy(bytes <= BUDGET.bytes, ("allocation: %d bytes, budget %d"):format(bytes, BUDGET.bytes))
			-- every row of the series is in a column
			local seen = 0
			for j = 1, out.n do
				for c = 1, out.buckets do
					if out[j].first[c] > 0 then seen = seen + out[j].last[c] - out[j].first[c] + 1 end
				end
			end
			eq(seen, #case[2] * TICKS)
		end
	end)
end)

-- The Threat Replay over the same session (SPEC-05 §5.2, M5.4). The tick moves the cursor and, when it passes a
-- recorded moment, finds it by binary search: its work does not grow with the session. M5.2 proposed nothing for the
-- detail; M5.4 measures it and bounds it, because the window reads it again at every recorded moment.
local TICK_BUDGET = { instructions = 2000, bytes = 64 }
local DETAIL_BUDGET = { instructions = 60000, bytes = 64 }

describe("the cost of a replay at the row limit (SPEC-05 §5.2, ARC-06)", function()
	before_boot(function(M)
		M.features = { monitor = true, alerts = true, coach = true, recording = true, reports = true, timeline = true,
			replay = true }
	end)

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

	it("keeps the tick at 8x within 2 000 instructions and the detail bounded, making nothing", function()
		local Replay, Storage, Scheduler = Mock.ns.Replay, Mock.ns.Storage, Mock.ns.Scheduler
		local s = fullSession()
		truthy(Storage.Add(s))
		truthy(Storage.Closed(s, true))
		local opened
		Replay.Open(s.id, nil, function(ok) opened = ok end)
		for _ = 1, 700 do Mock.Advance(0.05) end
		truthy(opened)
		Replay.OnChange(function() end)
		Replay.SetSpeed(8)
		local tick
		local start = Scheduler.Start
		Scheduler.Start = function(name, hz, fn, opts) tick = fn return start(name, hz, fn, opts) end
		truthy(Replay.Play())
		Scheduler.Start = start
		local function step() Mock.StepClock(0.1) tick() end
		for _ = 1, 20 do step() end
		local worst = 0
		for _ = 1, 100 do
			local work = T.instructions(step, 1)
			if work > worst then worst = work end
		end
		local bytes = allocated(function() for _ = 1, 50 do step() end end)
		truthy(Replay.state.playing)
		T.log(("replay tick: at most %d instructions, %d bytes in 50 ticks"):format(worst, bytes))
		truthy(worst <= TICK_BUDGET.instructions, "instructions in a tick: " .. worst)
		truthy(bytes <= TICK_BUDGET.bytes, "allocated in 50 ticks: " .. bytes)

		local snap = Replay.Snapshot(0)
		local times = { 5, 900, 1800, 2700, Replay.state.model.dur }
		for _, t in ipairs(times) do Replay.Snapshot(t, snap) end
		eq(snap.nunits, UNITS)
		local most = 0
		for _, t in ipairs(times) do
			local work = T.instructions(function() Replay.Snapshot(t, snap) end, 10)
			if work > most then most = work end
		end
		bytes = allocated(function() for _, t in ipairs(times) do Replay.Snapshot(t, snap) end end)
		T.log(("detail of %d units: at most %d instructions, %d bytes"):format(UNITS, most, bytes))
		truthy(most <= DETAIL_BUDGET.instructions, "instructions in a detail: " .. most)
		truthy(bytes <= DETAIL_BUDGET.bytes, "allocated: " .. bytes)
		local focus = T.instructions(function() Replay.EventDetail(1) end, 100)
		T.log(("an event with its missing data: %d instructions"):format(focus))
		-- with the model in memory, opening makes the replay's indexes at once, in one frame
		Replay.Close()
		local reopened
		local work = T.instructions(function() Replay.Open(s.id, nil, function(ok) reopened = ok end) end, 100)
		truthy(reopened)
		T.log(("opening over a model in memory: %d instructions"):format(work))
		truthy(work <= BUDGET.instructions, "instructions to open: " .. work)
	end)
end)
