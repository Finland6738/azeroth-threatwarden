-- The long scenario of the alerts (run_tests.py --long, SPEC-04 §6 M3.2): 30 minutes in a raid of 40 with
-- `others = always` and the sound on, the window closed so that the alerts themselves ask for the readings. The player
-- crosses both thresholds, damage dealers pull the mob, the tanks swap and die. Throughout: no error, the alerts of
-- every minute within the limits of §1.3 (a cooldown per kind and unit, one alert about others and one sound every 3 s),
-- and the memory flat. The simulated raid is Tests/lib/raid.lua; its numbers are assumptions until the M0 probe.

before_boot(function(M) M.features = { monitor = true, alerts = true, recording = false } end)

local MINUTE = 60
local MINUTES = 30
local RATE = 5
local COOLDOWN = 8
local GAP = 3
local MEMORY_KB = 256        -- how much the Lua state may grow after the first checkpoint

local function memoryKB()
	collectgarbage("collect")
	collectgarbage("collect")
	return collectgarbage("count")
end

describe("a raid of 40 with alerts about everybody", function()
	it("keeps the alerts of every minute within their limits for 30 minutes, without growing", function()
		local ns = Mock.ns
		local P = "account.settings.alerts."
		truthy(ns.Config:Set("account.settings.monitor.show", "manual"))
		truthy(ns.Config:Set(P .. "others", "always"))
		truthy(ns.Config:Set(P .. "sound", true))
		local raid = Raid.new()
		raid.wave[40] = { base = 82, amplitude = 17, period = 13 }    -- the player, across Warning and Danger
		for u = 9, 20 do raid.wave[u] = { base = 80 + u % 7, amplitude = 18, period = 5 + u % 11 } end
		ns.Window:Close()
		-- the alerts of the running minute, and what may never happen
		local minute, kinds = { total = 0, other = 0, own = 0 }, {}
		local last, lastOther, lastSound = {}, -math.huge, -math.huge
		local total, sounds = 0, 0
		ns.Bus.On("ALERT_RAISED", function(a)
			total = total + 1
			minute.total = minute.total + 1
			kinds[a.kind] = (kinds[a.kind] or 0) + 1
			if a.kind == "other" then
				minute.other = minute.other + 1
				truthy(a.at - lastOther >= GAP - 1e-6, "others after " .. (a.at - lastOther))
				lastOther = a.at
			else
				minute.own = minute.own + 1
			end
			local key = a.kind .. " " .. a.unitKey
			truthy(not last[key] or a.at - last[key] >= COOLDOWN - 1e-6, "cooldown: " .. key)
			last[key] = a.at
			if a.sound then
				sounds = sounds + 1
				truthy(a.severity >= 2, "no sound for a Warning")
				truthy(a.at - lastSound >= GAP - 1e-6, "sounds after " .. (a.at - lastSound))
				lastSound = a.at
			end
		end)
		raid:advance(1)
		truthy(ns.ThreatScanner.active, "the alerts want the readings with the window closed")

		local dt, first, firstCooled = 1 / RATE, nil, nil
		for second = 0, MINUTES * MINUTE - 1 do
			-- a tank dies every 4 minutes for half a minute
			local phase = second % 240
			if phase == 100 then raid:kill(1) elseif phase == 130 then raid:revive(1) end
			for _ = 1, RATE do raid:advance(dt) end
			if second % MINUTE == MINUTE - 1 then
				eq(#Mock.errors, 0)
				eq(ns.Bus.errorCount, 0, ns.Bus.errors[1] and ns.Bus.errors[1].message)
				-- others: one every 3 s; the player and the pet: five kinds of its own, one per cooldown each
				truthy(minute.other <= MINUTE / GAP + 1, "others in a minute: " .. minute.other)
				truthy(minute.own <= 5 * (math.floor(MINUTE / COOLDOWN) + 1), "own in a minute: " .. minute.own)
				minute.total, minute.other, minute.own = 0, 0, 0
			end
			if second % (10 * MINUTE) == 10 * MINUTE - 1 then
				local kb = memoryKB()
				if not first then
					first, firstCooled = kb, ns.Alerts.stats.cooled
				else
					truthy(kb - first < MEMORY_KB, ("memory grew from %.0f to %.0f KB"):format(first, kb))
				end
			end
		end

		truthy(total > 100, "alerts: " .. total)
		truthy((kinds.other or 0) > 100, "others: " .. tostring(kinds.other))
		truthy((kinds.warning or 0) > 20, "warnings: " .. tostring(kinds.warning))
		truthy((kinds.danger or 0) > 20, "dangers: " .. tostring(kinds.danger))
		truthy(sounds > 100, "sounds: " .. sounds)
		eq(#Mock.sound.calls, sounds)
		truthy(ns.Alerts.stats.cooled > firstCooled, "the cooldown held some back")
		truthy(ns.Alerts.stats.dropped > 0, "the gap between others dropped some")
		T.log(("%d alerts (%d others, %d sounds), %d in cooldown, %d dropped, %.0f -> %.0f KB"):format(total,
			kinds.other or 0, sounds, ns.Alerts.stats.cooled, ns.Alerts.stats.dropped, first, memoryKB()))
		-- the fight ends: nothing is read any more, the mute is off
		ns.Alerts.ToggleMute()
		raid.pull:stop()
		local reads = ns.ThreatScanner.reads
		Mock.Advance(30)
		eq(ns.ThreatScanner.reads, reads)
		falsy(ns.Alerts.IsMuted())
	end)
end)
