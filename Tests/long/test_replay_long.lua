-- The replay opened and closed again and again (run_tests.py --long, SPEC-05 §10 M5.5, source §13): sessions at the row
-- and event limits opened in the replay window, played, sought, zoomed, filtered and closed more than 200 times, also in
-- combat, over one another, and while the store prunes them away. After a warm-up the frames, the regions of the chart,
-- the rows of the list and the lines of the detail stop growing, and so does the memory of the Lua state. Offline
-- numbers on the mock client: what the game does is the probe's P10 and the checklist M5.

local UNITS, TICKS, STEP = 40, 750, 5      -- 30 000 rows, one tick every 5 tenths (2 Hz)
local CYCLES, WARM = 210, 42               -- WARM: every kind of cycle seen twice
local MEMORY_KB = 1024                     -- what the Lua state may still grow by after the warm-up

before_boot(function(M)
	M.features = { monitor = true, alerts = true, coach = true, recording = true, reports = true, timeline = true,
		replay = true }
end)

-- A session at the limits of rows and, nearly, of events.
local function fullSession(id, started)
	local S = Mock.ns.Session
	local s = S.New{ id = id, started = started, group = "raid", rec = { hz = 2, warning = 80, danger = 95,
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
	local state = {}
	for tick = 1, TICKS do
		local t = tick * STEP
		for u = 1, UNITS do
			local p = u == 2 and 1000 or ((tick * 7 + u * 13) % 1100)
			truthy(S.AddRow(s, t, 1, u, p, p >= 1000 and "3" or "0"))
		end
		for u = 3, 9 do                           -- state changes and deaths: a long event list
			local now = (tick + u) % 4 == 0 and "W" or "S"
			if state[u] ~= now and s.ne < 5900 then
				S.AddEvent(s, t, "S", 1, u, 0, now, state[u] or "S")
				state[u] = now
			end
		end
		if tick % 50 == 0 then S.AddEvent(s, t, "D", 0, 1 + tick % UNITS) end
	end
	S.AddEvent(s, TICKS * STEP + 5, "c")
	S.Join(s)
	s.state, s.ended, s.dur, s.fight = "complete", "combat", TICKS * STEP + 5, TICKS * STEP + 5
	return s
end

local function smallSession(id, started)
	local S = Mock.ns.Session
	local s = S.New{ id = id, started = started, group = "party", rec = { hz = 2, warning = 80, danger = 95 } }
	S.AddUnit(s, { name = "Testchar", token = "player", me = true }, 0)
	S.AddMob(s, { name = "Pup" }, 0)
	S.AddEvent(s, 0, "C", 0, 0, 0, "1")
	S.AddRow(s, 5, 1, 1, 500, "0")
	S.AddEvent(s, 100, "c")
	S.Join(s)
	s.state, s.ended, s.dur, s.fight = "complete", "combat", 100, 100
	return s
end

local function until_(what, ready)
	for _ = 1, 400 do
		if ready() then return end
		Mock.Advance(0.05, 0.05)
	end
	fail("never " .. what)
end

describe("the replay opened and closed again and again (source §13)", function()
	it("stops growing: frames, chart regions, rows, lines and memory", function()
		local ns = Mock.ns
		local RW, Rp, St, TL = ns.ReplayWindow, ns.Replay, ns.Storage, ns.Timeline
		truthy(ns.Config:Set("account.settings.recording.maxSessions", 5))
		truthy(ns.Config:Set("account.settings.recording.maxKB", 8192))
		local full = {}
		for i = 1, 3 do
			local s = fullSession("long-" .. i, 100000 + i)
			eq(s.n, ns.Session.LIMITS.rows)
			truthy(St.Add(s))
			truthy(St.Closed(s, true))
			full[i] = s.id
		end
		local started, pruned, small = Mock.RealClock(), 0, 0
		local counts

		local function openAndWait(id)
			truthy(RW.Open(id))
			until_("ready", function() return RW.mode == "ready" and Rp.state and Rp.state.id == id end)
		end

		local function use(cycle)
			local f = RW.frame
			local st = Rp.state
			local dur = st.model.dur
			Rp.SetSpeed(Rp.SPEEDS[cycle % 4 + 1])
			if cycle % 7 ~= 3 then
				truthy(Rp.Play())
				Mock.Advance(1, 0.05)
			end
			for k = 1, 6 do Rp.Seek((cycle * 397 + k * 613) % dur) end
			Rp.Step(1)
			Rp.Jump(-1)
			Rp.SetFilter(Rp.FILTERS[cycle % 3 + 1])
			Rp.NextEvent(1)
			local list = Rp.Events()
			if #list > 0 then Rp.Focus(list[(cycle * 31) % #list + 1]) end
			Mock.RunScript(f.events.area, "OnMouseWheel", -1)
			Rp.ToggleSeries(cycle % UNITS + 1)
			Rp.SetSelection(100, 900)
			Rp.SetView(100, 900)
			Rp.WholeFight()
			-- the narrow and the wide layout
			local w = cycle % 5 == 0 and 700 or cycle % 5 == 1 and 640 or 900
			f:SetSize(w, cycle % 5 == 1 and 420 or 600)
			Mock.RunScript(f, "OnSizeChanged", w, f:GetHeight())
		end

		for cycle = 1, CYCLES do
			local id = full[cycle % 3 + 1]
			openAndWait(id)
			if cycle % 6 == 0 then
				Mock.combat.Enter()
				falsy(Rp.Play())
				use(3)                       -- a cycle that does not play
				Mock.combat.Leave()
			end
			use(cycle)
			if cycle % 14 == 0 then
				-- a small recording older than the full ones, opened, then pruned away while it is open
				small = small + 1
				local s = smallSession("small-" .. small, small)
				truthy(St.Add(s))
				truthy(St.Closed(s, true))
				openAndWait(s.id)
				local before = St.stats.pruned
				for i = 1, 2 do                   -- one past maxSessions: only the oldest, the open one, goes
					local other = smallSession(("push-%d-%d"):format(small, i), 200000 + small * 10 + i)
					truthy(St.Add(other))
					truthy(St.Closed(other, true))
				end
				truthy(St.stats.pruned > before)
				pruned = pruned + St.stats.pruned - before
				eq(RW.mode, "unknown", "pruned while open")
				eq(RW.frame.message:GetText(), ns.L.REPLAY_MSG_DELETED)
				for i = 1, 2 do truthy(St.Delete(("push-%d-%d"):format(small, i))) end
				eq(St.Usage().count, 3, "the full ones stay")
			end
			if cycle % 4 ~= 2 then                -- else the next one opens over it
				RW.Close()
				isNil(Rp.state)
				falsy(ns.Scheduler.IsRunning("replay"))
			end
			if cycle == WARM or cycle == CYCLES then
				RW.Close()
				Mock.Advance(10, 0.5)
				Mock.ClearOutput()
				collectgarbage("collect")
				collectgarbage("collect")
				local f = RW.frame
				local now = { frames = #Mock.frames, lines = TL.regions.lines, textures = TL.regions.textures,
					rows = #f.rows, detail = #f.detail.lines.list, units = #f.detail.units.list,
					timers = Mock.PendingTimers(), kb = collectgarbage("count") }
				T.log(("after %d cycles: %d frames, %d lines, %d textures, %d rows, %d detail lines, %d unit rows, "
					.. "%d timers, %.0f KB"):format(cycle, now.frames, now.lines, now.textures, now.rows, now.detail,
					now.units, now.timers, now.kb))
				if cycle == WARM then
					counts = now
				else
					for _, key in ipairs({ "frames", "lines", "textures", "rows", "units", "timers" }) do
						truthy(now[key] <= counts[key], key .. " grew from " .. counts[key] .. " to " .. now[key])
					end
					-- a detail with one more reason line than any before may add a line or two
					truthy(now.detail <= counts.detail + 8, "detail lines grew from " .. counts.detail .. " to " .. now.detail)
					truthy(now.kb - counts.kb <= MEMORY_KB, ("memory grew by %.0f KB"):format(now.kb - counts.kb))
				end
			end
		end
		truthy(TL.regions.lines <= TL.MAX_LINES)
		truthy(TL.regions.textures <= TL.MAX_TEXTURES)
		eq(Mock.blocked, 0)
		eq(#Mock.errors, 0)
		T.log(("%d openings of %d-row sessions, %d pruned while open, %.1f s of CPU"):format(CYCLES,
			ns.Session.LIMITS.rows, pruned, Mock.RealClock() - started))
	end)
end)
