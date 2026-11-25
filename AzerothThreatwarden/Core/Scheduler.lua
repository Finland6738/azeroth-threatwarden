-- Scheduler: every periodic job of the addon, as named and bounded ticks (SPEC-01 §5, ARC-05, ARC-06, ARC-09). Lua 5.1.
-- Threatwarden's own (Accord has no scheduler); the client timers come through Core/Compat.lua.
--
--   Scheduler.Start(name, hz, fn, { combat = true })   one client ticker per name (a second Start replaces the first);
--                                                     hz between MIN_HZ and MAX_HZ; combat = true stops it at
--                                                     COMBAT_ENDED (the threat tick of M2)
--   Scheduler.Stop(name), Scheduler.StopAll(), Scheduler.IsRunning(name), Scheduler.Rate(name), Scheduler.Active()
--   Scheduler.Cost(name) -> median and maximum ms per tick over the last SAMPLES ticks, ticks run, errors
--
-- Nothing runs while nothing is needed: no fixed OnUpdate, and in M1 no tick is started at all. A tick runs under
-- pcall: an error stops that tick (it would fail again on every tick) and goes into the error ring of
-- Core/Diagnostics.lua, never to the player. A tick allocates nothing (ARC-06): the closure is made once by Start and
-- the cost of the last SAMPLES ticks lives in a ring of numbers.
local ADDON_NAME, ns = ...
ns = ns or {}
ns.modules = ns.modules or {}

local Scheduler = {}
ns.Scheduler, ns.modules.Scheduler = Scheduler, Scheduler

local Compat = ns.Compat
local type, pcall, pairs, tostring = type, pcall, pairs, tostring

Scheduler.MIN_HZ, Scheduler.MAX_HZ = 1, 10
Scheduler.SAMPLES = 100

local jobs = {}   -- name -> { name, hz, fn, combat, ticker, run, samples = { ms... }, next, count, ticks, errors, max }

local function clampRate(hz)
	if type(hz) ~= "number" or hz ~= hz then return nil end
	if hz < Scheduler.MIN_HZ then return Scheduler.MIN_HZ end
	if hz > Scheduler.MAX_HZ then return Scheduler.MAX_HZ end
	return hz
end

local function cancel(job)
	if job.ticker then
		Compat.CancelTicker(job.ticker)
		job.ticker = nil
	end
end

local function remember(job, ms)
	local samples = job.samples
	job.next = job.next % Scheduler.SAMPLES + 1
	samples[job.next] = ms
	if job.count < Scheduler.SAMPLES then job.count = job.count + 1 end
	if ms > job.max then job.max = ms end
end

-- The function the client ticker calls: made once per Start.
local function makeRun(job)
	return function()
		if jobs[job.name] ~= job or not job.ticker then return end
		local started = Compat.ProfileMs()
		local ok, err = pcall(job.fn)
		local ended = Compat.ProfileMs()
		job.ticks = job.ticks + 1
		if started and ended then remember(job, ended - started) end
		if not ok then
			job.errors = job.errors + 1
			cancel(job)
			jobs[job.name] = nil
			if ns.Diagnostics then ns.Diagnostics.Record("tick " .. job.name .. " stopped: " .. tostring(err)) end
		end
	end
end

-- Starts (or restarts) the tick `name`: fn() every 1/hz seconds. Returns true when the client ticker runs; false for a
-- bad name, rate or function, or a client without timers.
function Scheduler.Start(name, hz, fn, opts)
	hz = clampRate(hz)
	if type(name) ~= "string" or name == "" or not hz or type(fn) ~= "function" then return false end
	Scheduler.Stop(name)
	local job = { name = name, hz = hz, fn = fn, combat = opts and opts.combat == true or false, samples = {},
		next = 0, count = 0, ticks = 0, errors = 0, max = 0 }
	for i = 1, Scheduler.SAMPLES do job.samples[i] = 0 end   -- the ring is full size from the start: no growth per tick
	job.run = makeRun(job)
	job.ticker = Compat.NewTicker(1 / hz, job.run)
	if not job.ticker then return false end
	jobs[name] = job
	return true
end

-- Stops the tick `name`; true when one was running.
function Scheduler.Stop(name)
	local job = jobs[name]
	if not job then return false end
	cancel(job)
	jobs[name] = nil
	return true
end

function Scheduler.StopAll()
	for name in pairs(jobs) do Scheduler.Stop(name) end
end

function Scheduler.IsRunning(name)
	return jobs[name] ~= nil
end

-- The rate of a running tick, nil when it does not run.
function Scheduler.Rate(name)
	local job = jobs[name]
	return job and job.hz or nil
end

-- The names of the running ticks, sorted.
function Scheduler.Active()
	local names = {}
	for name in pairs(jobs) do names[#names + 1] = name end
	table.sort(names)
	return names
end

-- median ms, max ms (nil before the first measured tick), ticks run, errors of the running tick `name`.
function Scheduler.Cost(name)
	local job = jobs[name]
	if not job then return nil end
	if job.count == 0 then return nil, nil, job.ticks, job.errors end
	local sorted = {}
	for i = 1, job.count do sorted[i] = job.samples[i] end
	table.sort(sorted)
	local mid = math.floor((job.count + 1) / 2)
	local median = job.count % 2 == 1 and sorted[mid] or (sorted[mid] + sorted[mid + 1]) / 2
	return median, job.max, job.ticks, job.errors
end

-- The ticks bound to combat stop when it ends.
local function onCombatEnded()
	for name, job in pairs(jobs) do
		if job.combat then Scheduler.Stop(name) end
	end
end
if ns.Bus then ns.Bus.On("COMBAT_ENDED", onCombatEnded) end

function Scheduler.DebugLines()
	local names = Scheduler.Active()
	if #names == 0 then return { "no tick running" } end
	local lines = {}
	for _, name in ipairs(names) do
		local job = jobs[name]
		local median, max, ticks = Scheduler.Cost(name)
		lines[#lines + 1] = ("%s: %g Hz%s, %d ticks, %s ms median, %s ms max"):format(name, job.hz,
			job.combat and " (combat)" or "", ticks, median and ("%.3f"):format(median) or "?",
			max and ("%.3f"):format(max) or "?")
	end
	return lines
end

if ns.addon then ns.addon.Scheduler = Scheduler end
