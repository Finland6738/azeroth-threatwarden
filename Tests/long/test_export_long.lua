-- What the export of a session at the limits may cost (run_tests.py --long, SPEC-06 §4.6-§4.7, M6.5): the readings of a
-- session at the row limit (30 000 rows: 40 units for 750 recording ticks) and the events of one at the event limit
-- (6 000), built with Export.Build in slices. Every frame is measured against the worst frame of the report built in
-- slices on the same kind of session (Report.Build: the report's budget, SPEC-05 §3.4); the text keeps whole rows under
-- 256 KB and says what was left out; once the build is done and the text dropped, the memory goes back.
--
-- Work is counted in Lua VM instructions (T.instructions), the same on every machine.

local UNITS, TICKS, STEP = 40, 750, 5

-- A frame of the export may cost at most this much more than the report's worst frame (which is Storage.Decode and a
-- first slice of the report's pass; the export's worst is Storage.Decode and a first slice of rows or events).
local FRAME_FACTOR = 1.5
-- What the first export may leave (the client's string table and buffers, which grew with the text, not the text
-- itself: measured about 380 KB), and what three more of it may add.
local LEFT_KB, REPEAT_KB = 768, 64

before_boot(function(M)
	M.features = { monitor = true, alerts = true, coach = true, recording = true, reports = true, timeline = true,
		analytics = true, export = true }
end)

local function readingsSession(k)
	local S = Mock.ns.Session
	local s = S.New{ id = "export-" .. k, started = 4000 + k, group = "raid", diff = 3,
		rec = { hz = 2, warning = 80, danger = 95, mode = "values" } }
	for u = 1, UNITS do
		S.AddUnit(s, { name = "Raider" .. u, token = "raid" .. u, me = u == 1 or nil,
			role = u <= 2 and "TANK" or "DAMAGER" }, 0)
	end
	S.AddMob(s, { name = "Boss", class = "worldboss", npc = 9001 }, 0)
	S.AddEvent(s, 0, "C", 0, 0, 0, "1")
	S.AddEvent(s, 0, "M", 0, 0, 0, "v")
	S.AddEvent(s, 0, "T", 1)
	for tick = 1, TICKS do
		local t = tick * STEP
		for u = 1, UNITS do
			local p = u == 2 and 1000 or ((tick * 7 + u * 13) % 1100)
			S.AddRow(s, t, 1, u, p, p >= 1000 and "3" or "0")
		end
	end
	for u = 1, UNITS do s.q.v[u] = TICKS end
	S.AddEvent(s, TICKS * STEP + 5, "c")
	S.Join(s)
	s.state, s.ended, s.dur, s.fight = "complete", "combat", TICKS * STEP + 5, TICKS * STEP + 5
	eq(s.n, S.LIMITS.rows)
	truthy(Mock.ns.Storage.Add(s))
	truthy(Mock.ns.Storage.Closed(s, true))
	return s
end

local function eventsSession()
	local S = Mock.ns.Session
	local s = S.New{ id = "export-events", started = 5000, group = "raid", diff = 3,
		rec = { hz = 2, warning = 80, danger = 95, mode = "values" } }
	for u = 1, UNITS do S.AddUnit(s, { name = "Raider" .. u, token = "raid" .. u, me = u == 1 or nil }, 0) end
	S.AddMob(s, { name = "Boss", class = "worldboss", npc = 9001 }, 0)
	S.AddEvent(s, 0, "C", 0, 0, 0, "1")
	S.AddEvent(s, 0, "T", 1)
	local t = 1
	while s.ne < S.LIMITS.events do
		local u = 1 + t % UNITS
		S.AddEvent(s, t, "L", 1, u, 1 + (u % UNITS), "w", "1", "0", "ch")
		t = t + 1
	end
	S.Join(s)
	s.state, s.ended, s.dur, s.fight = "complete", "combat", t, t
	eq(s.ne, S.LIMITS.events)
	truthy(Mock.ns.Storage.Add(s))
	truthy(Mock.ns.Storage.Closed(s, true))
	return s
end

-- Runs the frames of Compat.After one by one, each measured; returns the worst frame and the count.
local function pump(start)
	local Compat = Mock.ns.Compat
	local queue, after = {}, Compat.After
	Compat.After = function(_, fn) queue[#queue + 1] = fn return true end
	local worst, count = T.instructions(start, 1000), 1
	while #queue > 0 do
		local fn = table.remove(queue, 1)
		local work = T.instructions(fn, 1000)
		count = count + 1
		if work > worst then worst = work end
	end
	Compat.After = after
	return worst, count
end

-- Several cycles: Lua 5.1 halves its string table and its concatenation buffer once a cycle, and both grew with a
-- text of 256 KB.
local function kb()
	for _ = 1, 8 do collectgarbage("collect") end
	return collectgarbage("count")
end

describe("the cost of the export of a session at the limits (SPEC-06 §4.7)", function()
	it("keeps every frame within the report's budget, cuts at whole rows and leaves no memory behind", function()
		local Export, Report, Storage = Mock.ns.Export, Mock.ns.Report, Mock.ns.Storage
		truthy(Mock.ns.Config:Set("account.settings.recording.maxKB", Mock.ns.Config.RECORDING.maxKB.max))
		local report = readingsSession(1)
		local readings = readingsSession(2)
		local events = eventsSession()

		local reportWorst = pump(function() Report.Build(report.id, function(r) truthy(r) end) end)

		for _, case in ipairs({ { "readings", readings, readings.n }, { "events", events, events.ne } }) do
			local kind, s, total = case[1], case[2], case[3]
			-- forget the decoded session of the one before, so that each export decodes its own
			Storage.Decode(report.id)
			local before = kb()
			local text, info
			local worst, count = pump(function()
				Export.Build({ kind = kind, format = "csv", id = s.id }, function(a, b) text, info = a, b end)
			end)
			truthy(text, kind)
			truthy(#text <= Export.MAX_TEXT, kind .. " " .. #text)
			truthy(info.left > 0, kind .. " over 256 KB")
			eq(info.rows + info.left, total)
			local _, breaks = text:gsub("\n", "")
			eq(breaks, info.rows, "a header and whole rows")
			local peak = kb() - before
			text = nil
			Storage.Decode(report.id)
			local left = kb() - before
			-- three more of the same export add nothing: the text and the pieces go with the build
			for _ = 1, 3 do
				Export.Build({ kind = kind, format = "csv", id = s.id }, function() end)
				for _ = 1, 100 do Mock.Advance(0.05) end
			end
			Storage.Decode(report.id)
			local again = kb() - before - left
			T.log(("export %s: %d of %d rows, %d frames, worst %d instructions (report %d, ratio %.2f), "
				.. "text and decoded session %.0f KB, left %.0f KB, %.0f KB more after three more"):format(kind, info.rows,
				total, count, worst, reportWorst, worst / reportWorst, peak, left, again))
			truthy(count >= 2, kind .. " in slices: " .. count)
			truthy(worst <= reportWorst * FRAME_FACTOR, kind .. " worst frame " .. worst)
			truthy(left <= LEFT_KB, kind .. " left " .. left .. " KB")
			truthy(again <= REPEAT_KB, kind .. " kept " .. again .. " KB more")
		end
		eq(#Mock.errors, 0)
	end)
end)
