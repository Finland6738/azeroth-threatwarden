-- Thirty minutes of a raid of 40 with 40 enemy nameplates and 12 mobs in the pull (run_tests.py --long, SPEC-07 §2.8,
-- SPEC-01 §5.1, M7.4): mobs that become unreachable and come back, secrets in the middle of the fight, GUIDs that change
-- on the same nameplate, nameplates reshuffled, a player who changes target and focus, with the other mobs shown in the
-- window and alerted about (`alerts.onlyTarget` off, `others` always). It checks that
--   * a tick of the mobs never reads more than the budget (counted at the client, not only in the tracker's own stats);
--   * a tick of the mobs costs at most a tick of the monitor with 40 units, in Lua VM instructions (the same on every
--     machine), on average and at the worst;
--   * the memory does not grow;
--   * no listed mob shows numbers older than its staleness limit (DAT-12), or a state it can no longer stand on;
--   * every `mob` alert is about another mob than the monitored one, one that can be read, once per transition and
--     per cooldown.
-- Everything is a function of the time: no random number, no real clock. These are offline numbers on the mock client:
-- the cost in the game is the probe's P10.

before_boot(function(M)
	M.features = { monitor = true, alerts = true, coach = false, recording = false, multitarget = true }
end)

local sin, floor, max = math.sin, math.floor, math.max

local UNITS = 40          -- 39 raidN and the player
local MOBS = 12           -- the pull
local PLATES = 40         -- all taken: the pull's and units that are not fighting
local SECONDS = 1800
local STEP = 0.1          -- the world's step; the monitor reads every 2nd (5 Hz), the mobs every 5th (2 Hz)
local WARMUP = 300        -- seconds before the memory is first measured
local EVERY = 300         -- and then every so often
local GROWTH_KB = 64      -- how much the Lua state may grow between the first and the last measure
local TANKS = { 1, 2 }    -- raid1, raid2

-- The mobs' tokens, each string made once.
local PLATE, TARGET_OF = {}, {}
for k = 1, PLATES do PLATE[k] = "nameplate" .. k end
for i = 1, UNITS - 1 do TARGET_OF[i] = "raid" .. i .. "target" end

local INDEX = Raid.INDEX

-- The world: which mob (1..MOBS, or an idle unit MOBS+1..PLATES) each token names now (false: nothing), the mobs' GUIDs,
-- secrecy, plates. Every table is filled once: changing it allocates nothing but the new GUIDs.
local function newWorld()
	local w = { t = 0, names = {}, guid = {}, plate = {}, mode = {}, away = {}, outcome = "values", serial = 0 }
	for m = 1, PLATES do
		w.guid[m] = "Creature-0-1-0-1-100-" .. m .. "-0"
		w.plate[m] = m
		w.names[PLATE[m]] = m
	end
	for m = 1, MOBS do w.mode[m], w.away[m] = "values", false end
	w.names.target, w.names.boss1, w.names.focus = 1, 1, 2
	for i = 1, UNITS - 1 do w.names[TARGET_OF[i]] = (i % MOBS) + 1 end
	return w
end

-- The holder of mob m at time t: a tank, now and then a damage dealer for a few seconds; mob 7 is sometimes held by a
-- unit outside the group with the tanks off its list (0).
local function holderOf(w, m)
	local t = floor(w.t)
	if m == 7 and t % 90 < 30 then return 0 end
	local period = 23 + m
	if (t + m * 5) % period < 4 then return 9 + (t + m) % 31 end
	return TANKS[(m % 2) + 1]
end

local function onList(w, u, m, holder)
	if u == holder then return true end
	if holder == 0 and (u == 1 or u == 2) then return false end
	if u == 1 or u == 2 or u == 40 then return true end
	return (u + m) % 13 ~= 0
end

-- The scaled % of unit u on mob m: a wave that now and then passes the thresholds.
local function scaledOf(w, u, m)
	local base = 20 + (u * 7 + m * 11) % 72
	local p = base + 8 * sin(w.t / (3 + (u + m) % 9) + u + m)
	if p < 0 then p = 0 elseif p > 99 then p = 99 end
	return p
end

local function install(w)
	local names = w.names
	local origExists, origGUID, origDead, origAttack, origCombat, origName, origClass = UnitExists, UnitGUID, UnitIsDead,
		UnitCanAttack, UnitAffectingCombat, UnitName, UnitClassification
	UnitExists = function(u)
		local m = names[u]
		if m == nil then return origExists(u) end
		return m ~= false
	end
	UnitGUID = function(u)
		local m = names[u]
		if m == nil then return origGUID(u) end
		return m and w.guid[m] or nil
	end
	UnitIsDead = function(u)
		if names[u] == nil then return origDead(u) end
		return false
	end
	UnitCanAttack = function(a, u)
		local m = names[u]
		if m == nil then return origAttack(a, u) end
		return m ~= false
	end
	UnitAffectingCombat = function(u)
		local m = names[u]
		if m == nil then return origCombat(u) end
		return m ~= false and m <= MOBS
	end
	UnitName = function(u)
		local m = names[u]
		if m == nil then return origName(u) end
		return m and "Mob" or nil
	end
	UnitClassification = function(u)
		if names[u] == nil then return origClass(u) end
		return "elite"
	end
	UnitIsUnit = function(a, b)
		local ma, mb = names[a], names[b]
		if ma == nil or mb == nil then return a == b end
		return ma ~= false and ma == mb
	end
	UnitTokenFromGUID = function(guid)
		for m = 1, MOBS do
			if w.guid[m] == guid and not w.away[m] then return PLATE[w.plate[m]] end
		end
		return nil
	end
	local function modeOf(mob)
		local m = names[mob]
		local mode = w.outcome
		if m and m <= MOBS and w.mode[m] ~= "values" and mode ~= "none" then mode = w.mode[m] end
		return mode
	end
	C_Secrets.ShouldUnitThreatStateBeSecret = function(_, mob) return modeOf(mob) == "none" end
	C_Secrets.ShouldUnitThreatValuesBeSecret = function(_, mob) return modeOf(mob) ~= "values" end
	local function lookUp(unit, mobToken)
		local u, m = INDEX[unit], names[mobToken]
		if not u or not m or m > MOBS then return nil end
		local holder = holderOf(w, m)
		if not onList(w, u, m, holder) then return nil end
		return u, m, holder
	end
	UnitDetailedThreatSituation = function(unit, mobToken)
		local u, m, holder = lookUp(unit, mobToken)
		if not u then return nil end
		if u == holder then return true, 3, 100, 100, 100000 end
		local p = scaledOf(w, u, m)
		return false, 0, p, p * 1.1, p * 1100
	end
	UnitThreatSituation = function(unit, mobToken)
		local u, _, holder = lookUp(unit, mobToken)
		if not u then return nil end
		return u == holder and 3 or 0
	end
	UnitThreatPercentageOfLead = function(unit, mobToken)
		local u, _, holder = lookUp(unit, mobToken)
		if u and u == holder then return 130 end
		return nil
	end
	UnitThreatLeadSituation = function(unit, mobToken)
		local u, _, holder = lookUp(unit, mobToken)
		if not u then return nil end
		return u == holder and 0 or 3
	end
end

local function setPlate(w, k, m)
	local old = w.names[PLATE[k]]
	if old == m then return end
	if old then Mock.Fire("NAME_PLATE_UNIT_REMOVED", PLATE[k]) end
	w.names[PLATE[k]] = m
	if m then Mock.Fire("NAME_PLATE_UNIT_ADDED", PLATE[k]) end
end

local function reachable(w, from)
	for j = 0, MOBS - 1 do
		local m = (from + j) % MOBS + 1
		if not w.away[m] then return m end
	end
	return 1
end

-- What happens in second `s`.
local function events(w, s)
	-- the raid changes who it targets
	if s % 3 == 0 then
		for i = 1, UNITS - 1 do
			local m = (i + s / 3) % MOBS + 1
			w.names[TARGET_OF[i]] = reachable(w, m - 1)
		end
		for i = 3, 39, 6 do Mock.Fire("UNIT_TARGET", "raid" .. i) end
	end
	-- two nameplates swap their mobs
	if s % 7 == 0 then
		local a, b = reachable(w, s % MOBS), reachable(w, (s * 5 + 3) % MOBS)
		if a ~= b then
			local ka, kb = w.plate[a], w.plate[b]
			setPlate(w, ka, false)
			setPlate(w, kb, false)
			w.plate[a], w.plate[b] = kb, ka
			setPlate(w, kb, a)
			setPlate(w, ka, b)
		end
	end
	-- a mob out of reach: no nameplate, nobody targets it, no token names it; back 6 or 16 seconds later
	if s % 23 == 0 then
		local m = reachable(w, (s / 23) % MOBS)
		if m ~= 1 then
			w.away[m] = (s % 46 == 0) and s + 16 or s + 6
			setPlate(w, w.plate[m], false)
			for token, named in pairs(w.names) do
				if named == m then w.names[token] = false end
			end
		end
	end
	for m = 1, MOBS do
		if w.away[m] and s >= w.away[m] then
			w.away[m] = false
			setPlate(w, w.plate[m], m)
		end
	end
	-- the threat of one mob turns secret for a while; now and then the whole fight does
	if s % 31 == 0 then w.mode[(s / 31) % MOBS + 1] = (s % 62 == 0) and "none" or "state" end
	if s % 31 == 20 then
		for m = 1, MOBS do w.mode[m] = "values" end
	end
	if s % 400 == 200 then w.outcome = "state" elseif s % 400 == 220 then w.outcome = "none"
	elseif s % 400 == 240 then w.outcome = "values" end
	-- a mob dies and another comes on the same nameplate
	if s % 37 == 0 then
		local m = reachable(w, (s / 37 * 5) % MOBS)
		local k = w.plate[m]
		setPlate(w, k, false)
		for token, named in pairs(w.names) do
			if named == m then w.names[token] = false end
		end
		w.serial = w.serial + 1
		w.guid[m] = "Creature-0-1-0-1-100-" .. m .. "-" .. w.serial
		setPlate(w, k, m)
	end
	-- the player's target and focus
	if s % 45 == 0 then
		w.names.target = reachable(w, s / 45)
		Mock.Fire("PLAYER_TARGET_CHANGED")
	elseif not w.names.target then
		w.names.target = reachable(w, 0)
		Mock.Fire("PLAYER_TARGET_CHANGED")
	end
	if s % 60 == 30 then
		w.names.focus = (s % 180 == 30) and false or reachable(w, s / 60 + 3)
		Mock.Fire("PLAYER_FOCUS_CHANGED")
	end
	w.names.boss1 = (not w.away[1]) and 1 or false
	Mock.Fire("UNIT_THREAT_LIST_UPDATE", PLATE[w.plate[reachable(w, s % MOBS)]])
end

local function newRaid()
	local members = {
		{ key = "r1", class = "WARRIOR", role = "TANK" }, { key = "r2", class = "DRUID", role = "TANK" },
	}
	for i = 3, 8 do members[i] = { key = "r" .. i, class = "PRIEST", role = "HEALER" } end
	for i = 9, UNITS - 1 do members[i] = { key = "r" .. i, class = "ROGUE", role = "DAMAGER" } end
	return Fight.new{ player = { class = "MAGE", role = "DAMAGER", ranged = true }, raid = true, party = members,
		mobs = { { key = "boss", tokens = { "target" } } } }
end

-- The setters of the mock widgets the two ticks call, writing into place instead of making a table (as
-- test_monitor_budget.lua): what grows is then the addon's.
local function noop() end
local function quietWidgets()
	local widget = getmetatable(Mock.ns.ThreatList.view).__index
	local function colour(field)
		return function(self, r, g, b, a)
			local c = rawget(self, field)
			if not c then
				c = {}
				self[field] = c
			end
			c[1], c[2], c[3], c[4] = r, g, b, a or 1
		end
	end
	widget.SetVertexColor, widget.SetColorTexture, widget.SetTextColor =
		colour("_vertex"), colour("_texture"), colour("_textColor")
	widget.SetTexCoord, widget.SetPoint, widget.ClearAllPoints = noop, noop, noop
	widget.Show = function(self) self._shown = true end
	widget.Hide = function(self) self._shown = false end
end

local function stats() return { n = 0, total = 0, worst = 0 } end
local function add(s, v)
	s.n, s.total = s.n + 1, s.total + v
	if v > s.worst then s.worst = v end
end
local function mean(s) return s.total / max(s.n, 1) end

describe("thirty minutes of a raid with 40 nameplates and 12 mobs (SPEC-07 §2.8)", function()
	it("stays inside the read budget and the monitor's cost, keeps its memory and shows nothing stale", function()
		local ns = Mock.ns
		local Config, MT, Scanner, Alerts, Focus = ns.Config, ns.MobTracker, ns.ThreatScanner, ns.Alerts, ns.FocusList
		truthy(Config:Set("account.settings.monitor.show", "manual"))
		truthy(Config:Set("account.settings.alerts.onlyTarget", false))
		truthy(Config:Set("account.settings.alerts.others", "always"))
		truthy(Config:Set("account.settings.alerts.cooldown", 5))
		truthy(Config:Set("account.settings.mobs.max", MOBS))
		ns.Window:Open()
		ns.Window:SelectTab("monitor")
		ns.ThreatList.view:Layout(560, 760)
		local pull = newRaid()
		pull:at(0):start()
		local w = newWorld()
		install(w)
		pull:to(0.5)
		quietWidgets()
		ns.Scheduler.Stop("threat")
		ns.Scheduler.Stop("mobs")
		truthy(MT.ticking, "the window wants the other mobs")

		-- reads counted at the client: each Threat.Read and ReadLead asks the prediction of the state once
		local counting, reads = false, 0
		local predict = C_Secrets.ShouldUnitThreatStateBeSecret
		C_Secrets.ShouldUnitThreatStateBeSecret = function(unit, mob)
			if counting then reads = reads + 1 end
			return predict(unit, mob)
		end

		-- the alerts about other mobs: checked as they come
		local raised = { total = 0 }
		local lastFor, rememberedAlerts = {}, 0
		ns.Bus.On("ALERT_RAISED", function(a)
			if a.kind ~= "mob" then return end
			raised.total = raised.total + 1
			raised[a.message] = (raised[a.message] or 0) + 1
			local entry = MT.Get(a.mobKey)
			truthy(entry, "an alert about a mob the tracker knows")
			falsy(entry.monitored, "never about the monitored mob")
			truthy(entry.state ~= "UNKNOWN", "never about an unreadable mob")
			local now = ns.Compat.Now()
			local last = lastFor[a.mobKey]
			truthy(not last or now - last >= 5 - 1e-6, "twice inside the cooldown of a mob")
			if not last then rememberedAlerts = rememberedAlerts + 1 end
			lastFor[a.mobKey] = now
		end)

		local seen = { secret = 0, ["no-token"] = 0, pending = 0, stale = 0, DANGER = 0, WARNING = 0, SAFE = 0 }
		local function checkList(now)
			local list, n = MT.List()
			truthy(n <= MOBS, "listed: " .. n)
			for i = 1, n do
				local e = list[i]
				local state = e.state
				if state == "UNKNOWN" then
					if seen[e.reason] then seen[e.reason] = seen[e.reason] + 1 end
				elseif state then
					seen[state] = seen[state] + 1
					local floorOf = e.monitored and 0.5 or 1
					for _, field in ipairs({ "holder", "top", "selfRec" }) do
						local rec = e[field]
						if rec then
							local limit = max(floorOf, 2 * (rec.interval or 0))
							if rec.mobKey ~= e.key or now - rec.observedAt > limit + 1e-6 then
								T.fail(("a mob shows the %s read %.2f s ago (limit %.2f)"):format(field,
									now - rec.observedAt, limit))
							end
						end
					end
					if not e.monitored then
						-- a state falls to UNKNOWN only after the dwell (1 s, MON-12)
						local limit = max(1, 2 * (e.interval or 0))
						if now - e.observedAt > limit + 1 + 1e-6 then
							T.fail(("a mob read %.2f s ago still says %s"):format(now - e.observedAt, state))
						end
					end
				end
			end
		end

		local monitorCost, mobsCost, listCost = stats(), stats(), stats()
		local mostReads, mobTicks, known = 0, 0, 0
		local memory = {}
		local s = 0
		for step = 1, floor(SECONDS / STEP) do
			w.t = step * STEP
			if step % 10 == 0 then
				s = step / 10
				events(w, s)
				-- the focus list in and out of the window, so that both views are measured
				if s % 120 == 60 then Focus.SetOpen(true) elseif s % 120 == 0 then Focus.SetOpen(false) end
				if s % EVERY == 0 and s >= WARMUP then
					collectgarbage("collect")
					collectgarbage("collect")
					memory[#memory + 1] = collectgarbage("count")
				end
				-- nothing of the harness grows with the fight
				if rememberedAlerts > 64 then
					for key, at in pairs(lastFor) do
						if ns.Compat.Now() - at > 30 then
							lastFor[key] = nil
							rememberedAlerts = rememberedAlerts - 1
						end
					end
				end
			end
			Mock.Advance(STEP, STEP)
			if step % 2 == 0 then
				local cost = T.instructions(Scanner.Scan)
				if not Focus.IsOpen() then add(monitorCost, cost) end
			end
			if step % 5 == 0 then
				reads, counting = 0, true
				local cost = T.instructions(MT.Tick)
				counting = false
				mobTicks = mobTicks + 1
				add(Focus.IsOpen() and listCost or mobsCost, cost)
				if reads > mostReads then mostReads = reads end
				truthy(reads <= MT.READ_BUDGET, ("a tick read %d times, the budget is %d"):format(reads, MT.READ_BUDGET))
				truthy(MT.stats.lastReads <= MT.READ_BUDGET)
				if MT.count > known then known = MT.count end
				checkList(ns.Compat.Now())
			end
			if step % 300 == 0 then
				falsy(ns.Scheduler.IsRunning("mobs"), "the ticks are the test's own")
				eq(#Mock.errors, 0)
				eq(ns.Bus.errorCount, 0)
			end
		end

		-- the scenario really happened
		truthy(MT.stats.ticks >= SECONDS * 2 - 5, "ticks: " .. MT.stats.ticks)
		eq(mobTicks, SECONDS * 2)
		eq(Scanner.count, UNITS)
		eq(MT.Reach(), "all")
		for what, count in pairs(seen) do
			if what ~= "stale" then truthy(count > 0, "never seen: " .. what) end
		end
		truthy(w.serial >= 40, "GUID changes: " .. w.serial)
		truthy(raised.total >= 100, "mob alerts: " .. raised.total)
		for _, key in ipairs({ "ALERT_MOB_AGGRO", "ALERT_MOB_CLOSE", "ALERT_MOB_NO_TANK", "ALERT_MOB_SELF" }) do
			truthy((raised[key] or 0) > 0, "never raised: " .. key)
		end
		truthy(known <= 2 * MOBS, "mobs known at once: " .. known)
		eq(#Mock.errors, 0)
		eq(ns.Bus.errorCount, 0)

		local series = {}
		for i, kb in ipairs(memory) do series[i] = ("%.0f"):format(kb) end
		T.log(("monitor tick (40 units): %.0f instructions on average, at most %.0f"):format(mean(monitorCost),
			monitorCost.worst))
		T.log(("mobs tick with the pull bar: %.0f, at most %.0f; with the list: %.0f, at most %.0f"):format(
			mean(mobsCost), mobsCost.worst, mean(listCost), listCost.worst))
		T.log(("reads per tick: at most %d of %d, %.1f on average; mobs known at most %d; %d mob alerts"):format(
			mostReads, MT.READ_BUDGET, MT.stats.reads / MT.stats.ticks, known, raised.total))
		T.log("memory (KB) every " .. EVERY .. " s from " .. WARMUP .. " s: " .. table.concat(series, " "))

		-- the cost of a mobs tick against the monitor's (SPEC-01 §5.1)
		for _, cost in ipairs({ mobsCost, listCost }) do
			truthy(mean(cost) <= mean(monitorCost),
				("a mobs tick costs %.0f instructions, a monitor tick %.0f"):format(mean(cost), mean(monitorCost)))
			truthy(cost.worst <= monitorCost.worst,
				("the worst mobs tick costs %.0f instructions, the worst monitor tick %.0f"):format(cost.worst,
					monitorCost.worst))
		end
		truthy(#memory >= 5)
		local growth = memory[#memory] - memory[1]
		truthy(growth <= GROWTH_KB, ("the memory grew by %.0f KB"):format(growth))
	end)
end)
