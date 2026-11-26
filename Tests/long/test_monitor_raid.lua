-- The long scenarios of the threat monitor (run_tests.py --long, SPEC-03 §6 M2.7, SPEC-08 §3): hours of combat ticks in
-- a raid of 40 through the whole pipeline, scanner -> model -> calc -> states -> list, with the window drawing every
-- update. One mob at 2, 5 and 10 Hz; a boss and four adds at 10 Hz with a new target every few seconds, tank and mob
-- deaths and the three probe outcomes; states oscillating around the thresholds. Throughout: no error, the states
-- follow their rules on every tick, a fall never sooner than the dwell, the pools and the frames stop growing and the
-- memory stays flat. The simulated raid is Tests/lib/raid.lua; its numbers are assumptions until the M0 probe. What one
-- tick may cost is the other file, test_monitor_budget.lua.

before_boot(function(M) M.features = { monitor = true } end)

local MINUTE = 60
local LEVEL = { SAFE = 1, WARNING = 2, DANGER = 3 }
local MEMORY_KB = 256        -- how much the Lua state may grow after the first checkpoint

-- The window large enough for most of the raid, opened by hand so that nothing closes it.
local function bigWindow(rate)
	local ns = Mock.ns
	truthy(ns.Config:Set("account.settings.monitor.show", "manual"))
	truthy(ns.Config:Set("account.settings.monitor.rate", rate))
	ns.Window:Open()
	ns.Window:SelectTab("monitor")
	ns.ThreatList.view:Layout(560, 760)
end

-- Listens for the state changes and checks MON-12: a fall (to a lower level or to UNKNOWN) never comes sooner than the
-- dwell after the last change of that unit on that mob. Returns the counters.
local function watchStates()
	local seen = { changes = 0, falls = 0, targets = 0, byUnit = {} }
	local last = {}
	Mock.ns.Bus.On("TARGET_CHANGED", function()
		last = {}
		seen.targets = seen.targets + 1
	end)
	Mock.ns.Bus.On("STATE_CHANGED", function(unitKey, _, old, new)
		seen.changes = seen.changes + 1
		seen.byUnit[unitKey] = (seen.byUnit[unitKey] or 0) + 1
		local now = GetTime()
		if old and new then
			local fall = new == "UNKNOWN" or (old ~= "UNKNOWN" and LEVEL[new] < LEVEL[old])
			if fall and last[unitKey] then
				seen.falls = seen.falls + 1
				if now - last[unitKey] < 1 - 1e-6 then
					error(("a fall %s -> %s after %.3f s"):format(old, new, now - last[unitKey]), 0)
				end
			end
		end
		last[unitKey] = new and now or nil
	end)
	return seen
end

-- The rules every row follows right after an update (SPEC-03 §2): a rise is immediate, a state above what the value
-- asks for is only a fall the dwell still holds. `grace` is the dwell plus the time between two updates.
local function checkRows(raid, grace)
	local ns = Mock.ns
	local Model, State, Scanner = ns.ThreatModel, ns.ThreatState, ns.ThreatScanner
	local warning, danger = State.Thresholds()
	local now = GetTime()
	local holder = Model.holder
	for i = 1, Model.count do
		local row = Model.rows[i]
		local rec = row.record
		if not row.present then
			isNil(row.state, "an absent row has no state")
		else
			local state, level = row.state, LEVEL[row.state]
			truthy(state == "UNKNOWN" or level, "a present row has a state")
			local held = now - row.stateSince < grace
			if not row.stale and rec.mode == "none" then
				truthy(state == "UNKNOWN" or held, "unreadable is UNKNOWN: " .. state)
			elseif not row.stale then
				local holds = rec.isTanking == true or (rec.situation or 0) >= 2
				if row.isHolder then
					truthy(state, "the holder has a state")
				elseif row.isTank and holder and not holder.isTank then
					eq(state, "DANGER", "a tank that lost the mob")
				elseif holds then
					eq(state, "DANGER", "a non tank with the aggro")
				elseif rec.mode == "values" and not row.isTank then
					local p = rec.scaledPercent
					if p >= danger then
						eq(state, "DANGER", p .. " %")
					elseif p >= warning then
						truthy(level and level >= 2, p .. " % is at least WARNING, not " .. state)
					end
					local atMost = p >= danger - 3 and 3 or (p >= warning - 3 and 2 or 1)
					if level and level > atMost and row.stateReason ~= "predicted" then
						truthy(held, state .. " held too long at " .. p .. " %")
					end
				elseif rec.mode == "state" and rec.situation == 0 and not row.isTank then
					truthy(state == "SAFE" or held, "state only 0 is SAFE: " .. state)
				end
			end
		end
	end
	-- whoever the raid says holds the mob holds it in the model, when this update read it
	local own = raid.holder and Scanner.RecordOf(Raid.TOKEN[raid.holder])
	if own and raid.mode == "values" and Scanner.lastScanAt == now and own.observedAt == now then
		truthy(holder, "somebody holds the mob")
		eq(holder.record.unitToken, Raid.TOKEN[raid.holder], "the holder")
	end
end

-- What is on screen: every shown row has a state word (ST-02), never more rows than fit, the player's own among them.
local function checkView()
	local List, view, Model = Mock.ns.ThreatList, Mock.ns.ThreatList.view, Mock.ns.ThreatModel
	truthy(view:IsVisible(), "the view is on screen")
	local height = view.contentHeight - view.headerHeight - List.LISTHEAD_HEIGHT - List.FOOTER_HEIGHT
	truthy(view.shownRows <= math.floor(height / List.ROW_HEIGHT), "rows that fit: " .. view.shownRows)
	local mine, onList = false, Model.mobKey ~= nil and Mock.ns.ThreatState.self ~= nil
	for i = 1, view.shownRows do
		local w = view.widgets[i]
		truthy(w:IsShown() and w.data, "row " .. i)
		truthy(w.badge.label:GetText() ~= "", "a state is a word")
		if w.data.record and w.data.record.unitToken == "player" then mine = true end
	end
	if onList and view.shownRows > 0 and view.situation == "list" then truthy(mine, "your row is visible") end
end

local function sizes()
	local ns = Mock.ns
	return { records = #ns.ThreatScanner.records, rows = #ns.ThreatModel.rows, widgets = #ns.ThreatList.view.widgets,
		frames = #Mock.frames, colours = ns.Theme.Count() }
end

local function memoryKB()
	collectgarbage("collect")
	collectgarbage("collect")
	return collectgarbage("count")
end

-- Plays `seconds` of the raid at `rate` Hz. `script(second)` runs once at the start of every second. Checks the rows on
-- every tick, the view every 5 s and, every 10 minutes, that nothing grows any more.
local function play(raid, rate, seconds, script)
	local ns = Mock.ns
	local dt, grace = 1 / rate, 1 + 1.5 / rate
	local first, firstSizes
	local scans0, t0 = ns.ThreatScanner.scans, Mock.RealClock()
	for second = 0, seconds - 1 do
		if script then script(second) end
		for _ = 1, rate do
			raid:advance(dt)
			checkRows(raid, grace)
		end
		if second % 5 == 4 then
			checkView()
			eq(#Mock.errors, 0)
			eq(ns.Bus.errorCount, 0, ns.Bus.errors[1] and ns.Bus.errors[1].message)
		end
		if second % (10 * MINUTE) == 10 * MINUTE - 1 then
			local kb, now = memoryKB(), sizes()
			if not first then
				first, firstSizes = kb, now
			else
				truthy(kb - first < MEMORY_KB, ("memory grew from %.0f to %.0f KB"):format(first, kb))
				deepEq(now, firstSizes, "pools, frames and theme registry stop growing")
			end
		end
	end
	local scans = ns.ThreatScanner.scans - scans0
	-- the tick, plus at most one gathered event scan per tick of the raid
	truthy(scans >= seconds * rate * 0.98, "ticks missed: " .. scans)
	truthy(scans <= seconds * rate * 2 + 100, "too many scans: " .. scans)
	eq(ns.ThreatScanner.count, 40)
	return scans, Mock.RealClock() - t0, first, memoryKB()
end

describe("a raid of 40 on one mob", function()
	for _, rate in ipairs({ 2, 5, 10 }) do
		it("keeps its rules and its size for 30 minutes at " .. rate .. " Hz, tanks dying", function()
			local raid = Raid.new()
			bigWindow(rate)
			local seen = watchStates()
			raid:advance(1)
			eq(Mock.ns.Scheduler.Rate("threat"), rate)
			local deaths = 0
			local scans, cpu, first, final = play(raid, rate, 30 * MINUTE, function(second)
				-- every 4 minutes a tank dies for half a minute, every other time both
				local phase, round = second % 240, math.floor(second / 240)
				if phase == 100 then
					raid:kill(1)
					if round % 2 == 1 then raid:kill(2) end
					deaths = deaths + 1
				elseif phase == 130 then
					raid:revive(1)
					raid:revive(2)
				end
			end)
			truthy(deaths >= 7)
			truthy(seen.changes > 1000, "state changes: " .. seen.changes)
			truthy(seen.falls > 500, "falls: " .. seen.falls)
			eq(Mock.ns.ThreatModel.count, 40)
			T.log(("%d Hz: %d scans, %d state changes, %.0f -> %.0f KB, %.0f s of CPU"):format(rate, scans, seen.changes,
				first, final, cpu))
		end)
	end
end)

describe("a raid of 40 on a boss and its adds", function()
	it("follows two hours at 10 Hz: new targets, deaths, the three outcomes", function()
		local raid = Raid.new{ adds = 4 }
		bigWindow(10)
		local seen = watchStates()
		raid:advance(1)
		local outcomes, mobDeaths, dead = {}, 0, nil
		local scans, cpu, first, final = play(raid, 10, 120 * MINUTE, function(second)
			-- the probe outcome changes every 10 minutes
			if second % (10 * MINUTE) == 0 then
				local name = Fight.OUTCOMES[math.floor(second / (10 * MINUTE)) % 3 + 1]
				raid:outcome(name)
				outcomes[name] = true
			end
			-- a new target every 3 to 7 seconds, never the dead add
			if second % 7 == 3 or second % 11 == 6 then
				local key = raid.mobs[(second * 3 + math.floor(second / 11)) % #raid.mobs + 1]
				if key ~= dead then raid:target(key) end
			end
			-- a tank dies every 3 minutes and is back 20 s later
			if second % 180 == 90 then raid:kill(1 + math.floor(second / 180) % 2) end
			if second % 180 == 110 then
				raid:revive(1)
				raid:revive(2)
			end
			-- an add dies while it is the target, and comes back as another creature a minute later
			if second % 150 == 75 then
				dead = "add" .. (math.floor(second / 150) % 4 + 1)
				raid:target(dead)
				raid.pull:die(dead)
				mobDeaths = mobDeaths + 1
			elseif second % 150 == 77 then
				raid:target("boss")
			elseif second % 150 == 135 and dead then
				Mock.units.Get(dead).dead = false
				raid.pull:newGUID(dead)
				dead = nil
			end
		end)
		truthy(outcomes.values and outcomes.state and outcomes.none)
		truthy(seen.targets > 1000, "targets: " .. seen.targets)
		truthy(mobDeaths >= 40)
		truthy(seen.changes > 5000, "state changes: " .. seen.changes)
		truthy(Mock.ns.ThreatScanner.active)
		T.log(("boss and adds: %d scans, %d targets, %d state changes, %.0f -> %.0f KB, %.0f s of CPU"):format(scans,
			seen.targets, seen.changes, first, final, cpu))
		-- the fight ends: nothing is read any more and the rows stay, all stale
		raid.pull:stop()
		local n = Mock.ns.ThreatScanner.reads
		Mock.Advance(30)
		eq(Mock.ns.ThreatScanner.reads, n)
		falsy(Mock.ns.Scheduler.IsRunning("threat"))
	end)
end)

describe("states oscillating around the thresholds", function()
	for _, rate in ipairs({ 2, 5, 10 }) do
		it("do not flicker for 10 minutes at " .. rate .. " Hz", function()
			local raid = Raid.new()
			bigWindow(rate)
			-- the holder never changes, and every damage dealer has a steady 40 % except these four
			raid.pullFor, raid.tankSwap = 0, 1e9
			for u = 9, 40 do raid.wave[u] = { base = 40, amplitude = 0, period = 10 } end
			raid.wave[9] = { base = 80, amplitude = 1.4, period = 1.3 }    -- inside the hysteresis of WARNING
			raid.wave[10] = { base = 95, amplitude = 1.4, period = 1.7 }   -- inside the hysteresis of DANGER
			raid.wave[12] = { base = 80, amplitude = 8, period = 20 }      -- slowly across WARNING
			raid.wave[13] = { base = 80, amplitude = 8, period = 0.7 }     -- faster than the dwell
			local seen = watchStates()
			raid:advance(1)
			play(raid, rate, 10 * MINUTE)
			local function changes(u)
				local key = Mock.ns.ThreatScanner.RecordOf(Raid.TOKEN[u]).unitKey
				return seen.byUnit[key] or 0
			end
			-- inside the hysteresis a state is entered and then kept (entering the list is the first change)
			truthy(changes(9) <= 2, "80 +- 1.4: " .. changes(9))
			truthy(changes(10) <= 2, "95 +- 1.4: " .. changes(10))
			-- one rise and one fall per period of 20 s, give or take a predicted WARNING
			truthy(changes(12) >= 30 and changes(12) <= 90, "slow crossing: " .. changes(12))
			-- at most one fall a second, and one rise for each
			truthy(changes(13) <= 2 * 10 * MINUTE + 2, "fast crossing: " .. changes(13))
			truthy(changes(14) <= 1, "a steady unit: " .. changes(14))
		end)
	end
end)
