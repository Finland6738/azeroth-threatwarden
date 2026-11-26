-- The long scenarios of recording (run_tests.py --long, SPEC-05 §1, §2, §7 M4.6, SPEC-08 §3): a raid of 40 through the
-- whole pipeline, scanner -> model -> states -> recorder -> storage -> report, with the window closed except for the
-- last scenario. An hour of fights with chained pulls, deaths and the three probe outcomes; the limits of one session
-- reached; the store kept at its limits by number and by size over many closes; many /reload in combat; the Reports
-- tab and its reports opened and closed many times. Throughout: no error, and the memory, the packed pieces, the store
-- and the pooled widgets stop growing at their limits. The simulated raid is Tests/lib/raid.lua; its numbers are
-- assumptions until the M0 probe. What one tick may cost is test_monitor_budget.lua.

before_boot(function(M)
	M.features = { monitor = true, alerts = true, coach = true, recording = true, reports = true }
end)

local DT = 0.2               -- one step of the raid: the monitor's default rate (5 Hz)
local RAID = 40

local function rec() return Mock.ns.Recorder end
local function store() return Mock.ns.Storage end
local function list() return AzerothThreatwardenDB.sessions end

local function set(key, value)
	truthy(Mock.ns.Config:Set("account.settings.recording." .. key, value), "setting " .. key)
end

-- The Lua state after full collections until it stops shrinking: Lua 5.1 halves its string table and its buffer only
-- once per collection.
local function memoryKB()
	local before, now = math.huge, nil
	for _ = 1, 20 do
		collectgarbage("collect")
		now = collectgarbage("count")
		if before - now < 1 then break end
		before = now
	end
	return now
end

local function healthy()
	eq(#Mock.errors, 0, Mock.errors[1] and Mock.errors[1].message)
	eq(Mock.ns.Bus.errorCount, 0, Mock.ns.Bus.errors[1] and Mock.ns.Bus.errors[1].message)
end

-- What an open session holds in the long form: fewer than CHUNK rows and events wait, the rest is packed, one piece
-- per column for every CHUNK rows.
local function checkOpen(s)
	local S = Mock.ns.Session
	local waiting, events = #s.buf.t, #s.buf.ev / S.EVENT_FIELDS
	truthy(waiting < S.CHUNK, "rows waiting: " .. waiting)
	truthy(events < S.CHUNK, "events waiting: " .. events)
	local packed = (s.n - waiting) / S.CHUNK
	for _, column in ipairs(S.COLUMNS) do eq(#s.parts[column], packed, "pieces of " .. column) end
	eq(#s.parts.ev, (s.ne - events) / S.CHUNK, "pieces of ev")
	truthy(s.n <= S.LIMITS.rows and s.ne <= S.LIMITS.events)
end

-- STO-02: after a close the two limits hold (the open session counts and never goes).
local function checkStore()
	local usage = store().Usage()
	truthy(usage.count <= usage.maxSessions, ("sessions: %d of %d"):format(usage.count, usage.maxSessions))
	truthy(usage.bytes <= usage.maxKB * 1024, ("size: %.0f of %d KB"):format(usage.bytes / 1024, usage.maxKB))
	eq(#list(), usage.count, "nothing hidden")
	return usage
end

local function seconds(raid, n, dt)
	dt = dt or DT
	for _ = 1, math.floor(n / dt + 0.5) do raid:advance(dt) end
end

-- Out of combat: the client's clock and timers only (the threat of the raid does not move).
local function rest(n) Mock.Advance(n, 0.5) end

local function eventsBy(d, kind, a)
	local count = 0
	for _, e in ipairs(d.events) do
		if e.k == kind and (a == nil or e.a == a) then count = count + 1 end
	end
	return count
end

-- The rows a mode writes (SPEC-02 §4.2); a stale read (T) and a unit not read yet may come in any mode.
local CODES = {
	values = { ["0"] = true, ["1"] = true, ["2"] = true, ["3"] = true, ["4"] = true },
	state = { a = true, b = true, c = true, d = true },
	none = { S = true },
}

-- A raider dies (UNIT_DIED with its GUID) and comes back `n` seconds later.
local function death(raid, u, n)
	local key = "r" .. u
	raid:kill(u)
	raid.pull:die(key)
	seconds(raid, n)
	local unit = Mock.units.Get(key)
	unit.dead, unit.combat = false, true
	raid:revive(u)
	Mock.Fire("UNIT_FLAGS", "raid" .. u)
end

-- The content of one fight of the hour. A function of its own: the decoded rows (some 1.5 MB for a fight with values)
-- must be gone when the memory is measured. Session.Decode keeps nothing; Storage's deep check comes at the end.
local function checkFight(s, outcome, fights, length)
	local d = assert(Mock.ns.Session.Decode(s))
	local chained = fights % 3 == 0
	local expected = length + (chained and 40 or 0)
	truthy(math.abs(s.fight / 10 - expected) < 2, ("fight %.1f s, expected %d"):format(s.fight / 10, expected))
	eq(eventsBy(d, "C", "1"), 1)
	eq(eventsBy(d, "C", "2"), chained and 1 or 0)
	truthy(eventsBy(d, "D", "g") >= 1, "the tank's death by GUID")
	eq(eventsBy(d, "D", "p"), fights % 4 == 0 and 1 or 0)
	local mine, other = 0, 0
	for i = 1, d.n do
		if CODES[outcome][d.s[i]] then mine = mine + 1 elseif d.s[i] ~= "T" then other = other + 1 end
	end
	truthy(mine >= 1 and other <= mine * 0.2 + RAID, ("%s: %d rows of the mode, %d others"):format(outcome, mine, other))
	if outcome == "values" then truthy(d.n > length * 2 * 25, "rows: " .. d.n) end
end

describe("an hour of fights in a raid of 40", function()
	it("records every pull, chained ones too, with deaths and the three outcomes, inside the store's limits", function()
		local ns = Mock.ns
		set("maxKB", 512)                      -- the smallest the card allows, and few sessions: both limits bind
		set("maxSessions", 15)
		local raid = Raid.new()
		raid.pull:stop()
		rest(10)
		local started = GetTime()
		local fights, chained, deaths, kept, first, firstUsage = 0, 0, 0, {}, nil, nil
		local peak, most, t0 = 0, 0, Mock.RealClock()
		while GetTime() - started < 3600 do
			fights = fights + 1
			local outcome = Fight.OUTCOMES[(fights - 1) % 3 + 1]
			raid:outcome(outcome)
			raid.pull:start()
			local s = rec().current
			notNil(s, "a session opens at every pull: " .. tostring(rec().stats.lastSkip))
			local length = 90 + (fights % 4) * 30
			seconds(raid, 30)
			death(raid, 1, 20)                  -- the first tank
			deaths = deaths + 1
			if fights % 4 == 0 then
				Mock.Fire("PLAYER_DEAD")
				deaths = deaths + 1
			end
			seconds(raid, length - 50)
			checkOpen(s)
			truthy(ns.Scheduler.IsRunning("record"), "the recording tick runs")
			raid.pull:stop()
			falsy(ns.Scheduler.IsRunning("record"))
			if fights % 3 == 0 then             -- a chained pull: inside END_DELAY, the same session
				rest(2)
				raid.pull:start()
				eq(rec().current, s)
				chained = chained + 1
				seconds(raid, 40)
				raid.pull:stop()
			end
			rest(20)
			isNil(rec().current)
			healthy()
			local usage = checkStore()
			eq(s.state, "complete")
			eq(list()[#list()], s, "the newest is kept")
			isNil(s.parts)
			isNil(s.buf)
			notNil(s.sum, "the summary at the close")
			checkFight(s, outcome, fights, length)
			kept[#kept + 1] = s.id
			peak = math.max(peak, usage.bytes)
			if usage.pruned > 0 then
				local kb = memoryKB()
				if not first then first, firstUsage = kb, usage end
				most = math.max(most, kb)
			end
		end
		local usage = checkStore()
		truthy(fights >= 18, "fights: " .. fights)
		truthy(chained >= 5 and deaths >= fights)
		eq(rec().stats.kept, fights)
		eq(usage.pruned, fights - usage.count, "the oldest went")
		for i = 1, usage.count do eq(list()[i].id, kept[fights - usage.count + i], "the newest stay, in order") end
		notNil(first, "the store reached its limit")
		-- the store holds a few sessions more or less according to their size: the margin is two of the largest
		truthy(most - first < 256, ("memory grew from %.0f to %.0f KB after the first pruning"):format(first, most))
		for _, s in ipairs(list()) do
			local d, why = store().Decode(s.id)
			notNil(d, why)
		end
		T.log(("%d fights (%d chained), %d kept, %.0f KB at the first pruning (%d kept), peak %.0f KB, memory %.0f KB at the first pruning, at most %.0f after it, %.0f s of CPU")
			:format(fights, chained, usage.count, firstUsage.bytes / 1024, firstUsage.count, peak / 1024, first, most,
				Mock.RealClock() - t0))
	end)
end)

describe("the limits of one session", function()
	it("stop the rows, the events, the units and the mobs, and nothing grows after them", function()
		local ns = Mock.ns
		local S = ns.Session
		set("rate", 5)
		truthy(ns.Config:Set("account.settings.monitor.rate", 10))
		local raid = Raid.new{ adds = 4 }
		local s = rec().current
		notNil(s)
		raid:target("add1")                    -- an add that keeps its entry for the rest of the test
		seconds(raid, 1, 0.1)
		raid:target("boss")
		-- more than 61 mobs: a new creature behind the target every second
		for _ = 1, 70 do
			raid.pull:newGUID("boss")
			seconds(raid, 1, 0.1)
		end
		eq(#s.mobs, S.LIMITS.mobs)
		raid:target("add1")
		-- more than 61 units: 30 raiders replaced by others
		for u = 9, 38 do raid.pull:newGUID("r" .. u) end
		Mock.Fire("GROUP_ROSTER_UPDATE")
		seconds(raid, 5, 0.1)
		eq(#s.units, S.LIMITS.units)
		checkOpen(s)
		-- the rows
		local guard = 0
		while not s.trunc do
			seconds(raid, 10)
			guard = guard + 10
			truthy(guard < 900, "the rows never stopped: " .. s.n)
		end
		eq(s.n, S.LIMITS.rows)
		local trunc = s.trunc
		truthy(s.ne < S.LIMITS.events, "events still go on: " .. s.ne)
		-- the events: every unit crossing the thresholds all the time
		for u = 9, RAID do raid.wave[u] = { base = 87, amplitude = 14, period = 2 + u % 3 } end
		local counters = {}
		for i = 1, #s.units do counters[i] = { s.q.v[i], s.q.s[i], s.q.x[i] } end
		guard = 0
		while s.ne < S.LIMITS.events do
			seconds(raid, 10, 0.1)
			guard = guard + 10
			truthy(guard < 900, "the events never stopped: " .. s.ne)
		end
		eq(s.ne, S.LIMITS.events)
		checkOpen(s)
		local pieces, bytes, first = S.Pieces(s), ns.Config.EstimateSize(s), memoryKB()
		-- ten more minutes of the same: nothing is added
		for minute = 1, 10 do
			seconds(raid, 60)
			eq(s.n, S.LIMITS.rows)
			eq(s.ne, S.LIMITS.events)
			eq(S.Pieces(s), pieces, "pieces at minute " .. minute)
			healthy()
		end
		eq(ns.Config.EstimateSize(s), bytes, "the session stopped growing")
		for i = 1, #s.units do deepEq({ s.q.v[i], s.q.s[i], s.q.x[i] }, counters[i], "the counters stopped too") end
		local final = memoryKB()
		truthy(final - first < 256, ("memory grew from %.0f to %.0f KB past the limits"):format(first, final))
		raid.pull:stop()
		rest(10)
		healthy()
		eq(s.state, "complete")
		eq(s.trunc, trunc)
		local size = ns.Config.EstimateSize(s)
		truthy(size < 400 * 1024, ("one session: %.0f KB"):format(size / 1024))
		checkStore()
		local d, why = store().Decode(s.id)
		notNil(d, why)
		eq(d.n, S.LIMITS.rows)
		eq(d.ne, S.LIMITS.events)
		for _, a in ipairs({ "r", "e", "u", "m" }) do eq(eventsBy(d, "Z", a), 1, "one Z " .. a) end
		eq(d.events[d.ne].k, "Z")
		eq(d.events[d.ne].a, "e", "the last event says the events stopped")
		local report, problem
		ns.Report.Build(s.id, function(r, w) report, problem = r, w end)
		rest(5)
		notNil(report, problem)
		eq(report.truncated, trunc)
		truthy(report.eventsCut)
		T.log(("limits: rows at %.0f s, %d units, %d mobs, %.0f KB estimated, memory %.0f -> %.0f KB"):format(trunc / 10,
			#s.units, #s.mobs, size / 1024, first, final))
	end)

	it("stop the rows when the time runs out of its three characters", function()
		local S = Mock.ns.Session
		S.MAX_T = 600                          -- 60 s instead of 6 h 37 min
		local raid = Raid.new()
		local s = rec().current
		seconds(raid, 90)
		eq(s.trunc, 600)
		local n = s.n
		seconds(raid, 30)
		eq(s.n, n)
		raid.pull:stop()
		rest(10)
		healthy()
		local d, why = store().Decode(s.id)
		notNil(d, why)
		eq(eventsBy(d, "Z", "t"), 1)
	end)
end)

describe("the store near its limits over many closes", function()
	local function run(raid, count, check)
		for i = 1, count do
			raid.pull:start()
			local s = rec().current
			notNil(s)
			seconds(raid, 6 + i % 5 * 2)
			raid.pull:stop()
			rest(6)
			eq(list()[#list()], s)
			check(i, checkStore())
		end
		healthy()
	end

	for _, case in ipairs({
		{ name = "by size", maxSessions = 100, maxKB = 512 },
		{ name = "by number", maxSessions = 5, maxKB = 8192 },
		{ name = "by number and size", maxSessions = 38, maxKB = 512 },
	}) do
		it("keeps 150 closes " .. case.name .. " and stops growing", function()
			set("maxSessions", case.maxSessions)
			set("maxKB", case.maxKB)
			local raid = Raid.new()
			raid.pull:stop()
			rest(10)
			local first, atFirst, most, least = nil, nil, 0, math.huge
			run(raid, 150, function(i, usage)
				if i > 60 then
					most, least = math.max(most, usage.count), math.min(least, usage.count)
				end
				if i == 60 then first, atFirst = memoryKB(), usage end
			end)
			local usage, final = checkStore(), memoryKB()
			truthy(atFirst.pruned > 0, "pruning before the 60th close")
			truthy(usage.pruned > 80, "pruned: " .. usage.pruned)
			eq(usage.count + usage.pruned, 150)
			if case.name == "by number" then
				eq(most, 5)
				eq(least, 5)
			else
				truthy(usage.bytes > case.maxKB * 1024 * 0.8, "the store stays near its limit")
				truthy(most <= case.maxSessions, "sessions kept: " .. most)
			end
			truthy(final - first < 300, ("memory grew from %.0f to %.0f KB"):format(first, final))
			-- a smaller limit at once takes the oldest, never more than needed
			set("maxSessions", 5)
			eq(checkStore().count, 5)
			T.log(("%s: %d kept (%d..%d after the 60th), %d pruned, %.0f KB estimated, memory %.0f -> %.0f KB"):format(
				case.name, usage.count, least, most, usage.pruned, usage.bytes / 1024, first, final))
		end)
	end
end)

describe("many /reload in combat", function()
	it("keeps every interrupted recording linked and complete, inside the store's limits", function()
		set("maxSessions", 8)
		set("maxKB", 512)
		local raid = Raid.new()
		local first, later, previous = 0, 0, nil
		local RELOADS = 40
		for i = 1, RELOADS do
			seconds(raid, 12 + i % 4 * 5)
			local s = rec().current
			notNil(s, "recording before reload " .. i)
			local id = s.id
			if i % 10 == 0 then                 -- one during END_DELAY: closed, joined at the next load
				raid.pull:stop()
				rest(1)
				Mock.Reload()
				raid:install()
				healthy()
				local done = store().Get(id)
				eq(done.state, "complete")
				isNil(done.parts)
				raid.pull:start()
				isNil(rec().current.after, "a fight of its own")
			else
				Mock.Reload()
				raid:install()
				healthy()
				local old = store().Get(id)
				notNil(old, "kept after reload " .. i)
				eq(old.state, "interrupted")
				eq(old.ended, "reload")
				isNil(old.parts)
				isNil(old.buf)
				local now = rec().current
				notNil(now, "recording again after reload " .. i)
				eq(now.after, id, "linked to the one it continues")
			end
			ne(rec().current.id, previous)
			previous = rec().current.id
			-- the open session is the last; no other one is open
			for k, other in ipairs(list()) do
				if k < #list() then ne(other.state, "open") end
			end
			-- pruned at the load, then the new session opened on top of the kept ones (STO-02: the next close prunes)
			local usage = store().Usage()
			truthy(usage.count <= usage.maxSessions + 1, "sessions: " .. usage.count)
			truthy(usage.bytes <= usage.maxKB * 1024 + 64 * 1024, "size: " .. usage.bytes)
			eq(usage.damaged, 0)
			-- the memory just after a reload, the new recording still empty: the store has been full since the 10th, and
			-- the later half of the reloads must not hold more than the earlier one
			if i % 10 ~= 0 and i > 12 then
				local kb = memoryKB()
				if i <= 26 then first = math.max(first, kb) else later = math.max(later, kb) end
			end
		end
		raid.pull:stop()
		rest(10)
		healthy()
		checkStore()
		for _, s in ipairs(list()) do
			local d, why = store().Decode(s.id)
			notNil(d, why)
			notNil(s.sum, "every summary computed out of combat")
		end
		truthy(later - first < 200, ("memory grew from %.0f to %.0f KB"):format(first, later))
		T.log(("%d reloads: %d sessions, %.0f KB estimated, at most %.0f KB of Lua after the 13th..26th, %.0f after the later ones")
			:format(RELOADS, #list(), store().Usage().bytes / 1024, first, later))
	end)
end)

describe("the Reports tab opened and closed many times", function()
	it("shows the reports of 40 units again and again without growing", function()
		local ns = Mock.ns
		local raid = Raid.new()
		raid.pull:stop()
		rest(10)
		-- eight recordings of different lengths, the first one long: more than one slice of work
		for i = 1, 8 do
			raid.pull:start()
			seconds(raid, i == 1 and 240 or 15 + i * 3)
			raid.pull:stop()
			rest(10)
		end
		local ids = {}
		for _, h in ipairs(store().List()) do ids[#ids + 1] = h.id end
		eq(#ids, 8)
		local long = list()[1]
		truthy(long.n + long.ne > ns.Report.SLICE, "built in slices: " .. long.n + long.ne)
		local Window = AzerothThreatwarden.Window
		local view

		local function open(id)
			view:Select(id)
			local guard = 0
			while view.building == id do
				Mock.Advance(0.1)
				guard = guard + 1
				truthy(guard < 100, "the report is built")
			end
			notNil(view.data, "report " .. tostring(view.problem))
			eq(view.data.id, id)
			local shown = 0
			for _, card in ipairs(view.units) do if card:IsShown() then shown = shown + 1 end end
			eq(shown, #view.data.units)
		end
		local function cycle(i)
			Window:Open()
			truthy(Window:SelectTab("reports"))
			view = ns.Window:Frame().pages.reports.view
			view:Layout(700, 600)
			open(ids[(i - 1) % #ids + 1])
			if i % 3 == 0 then open(ids[i % #ids + 1]) end
			view:Select(nil)
			falsy(view.report:IsShown())
			if i % 2 == 0 then Window:SelectTab("monitor") end
			Window:Close()
			rest(1)
		end

		for i = 1, #ids do cycle(i) end
		-- the memory with the same report kept (one report and one decoded recording stay in memory, SPEC-05 §3.4)
		local function settled()
			Window:Open()
			truthy(Window:SelectTab("reports"))
			open(ids[#ids])
			view:Select(nil)
			Window:Close()
			rest(1)
			return memoryKB()
		end
		local function sizes()
			return { frames = #Mock.frames, rows = #view.rows, units = #view.units, colours = ns.Theme.Count(),
				listeners = ns.Bus.Count and ns.Bus.Count() or 0 }
		end
		local first, firstSizes = settled(), sizes()
		for i = 1, 150 do cycle(i) end
		healthy()
		deepEq(sizes(), firstSizes, "rows, unit cards, frames and listeners stop growing")
		truthy(#view.units >= RAID - 2, "a card for every unit on a list: " .. #view.units)
		local final = settled()
		truthy(final - first < 100, ("memory grew from %.0f to %.0f KB"):format(first, final))

		-- in combat, with the tab open on a report, new recordings coming and the old ones going
		Window:Open()
		truthy(Window:SelectTab("reports"))
		view:Layout(700, 600)
		local function oldest()
			local headers = store().List()
			return headers[#headers].id
		end
		open(oldest())
		local pruned, closedByPruning = store().Usage().pruned, 0
		set("maxSessions", 9)
		for _ = 1, 20 do
			raid.pull:start()
			seconds(raid, 8)
			truthy(store().Usage().count <= 10, "the open one on top of at most 9")
			raid.pull:stop()
			rest(6)
			truthy(store().Usage().count <= 9)
			if not view.selected then           -- the report shown was pruned: it closed
				closedByPruning = closedByPruning + 1
				falsy(view.report:IsShown())
				open(oldest())
			end
		end
		healthy()
		truthy(store().Usage().pruned > pruned)
		truthy(closedByPruning >= 2, "reports closed by pruning: " .. closedByPruning)
		eq(sizes().units, firstSizes.units)
		truthy(sizes().rows <= 10, "list rows: " .. sizes().rows)
		-- what one repaint of a report of 40 units costs (every SESSIONS_CHANGED while the tab is visible), and the work
		-- of the longest recording, which Report.Build decodes in the frame of the click
		open(oldest())
		local repaint = T.instructions(function() view:Refresh() end)
		local decode = T.instructions(function() assert(ns.Session.Decode(long)) end)
		local d = ns.Session.Decode(long)
		local compute = T.instructions(function() ns.Report.Compute(long, d) end)
		T.log(("tab: memory %.0f -> %.0f KB, %d frames; a repaint with %d units %.0f instructions; %d rows and %d events: decoding %.0f, computing %.0f")
			:format(first, final, firstSizes.frames, #view.data.units, repaint, long.n, long.ne, decode, compute))
	end)
end)
