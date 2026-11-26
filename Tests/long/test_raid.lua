-- Long scenarios (run_tests.py --long, ADR 0010, SPEC-08 §3). For now one: ten minutes of a 40-player raid on five
-- mobs on the mock client alone, with the addon loaded and /reload in the middle. It proves the long run works and
-- keeps the mock honest at that size; the scanner (M2) and the recorder (M4) add theirs.

local PLAYERS, MOBS, SECONDS = 39, 5, 600   -- the others in the raid; the player makes 40

describe("a long raid fight", function()
	it("stays consistent for ten minutes of threat changes with a /reload in the middle", function()
		local party, mobs = {}, {}
		for i = 1, PLAYERS do party[i] = { key = "raider" .. i, role = i <= 2 and "TANK" or "DAMAGER" } end
		for i = 1, MOBS do mobs[i] = { key = "mob" .. i, tokens = { "nameplate" .. i } } end
		local pull = Fight.new{ raid = true, party = party, mobs = mobs }
		pull:start():target("player", "mob1")

		local units = { "player" }
		for i = 1, PLAYERS do units[#units + 1] = "raider" .. i end
		for second = 1, SECONDS do
			pull:at(second):call(function()
				for m = 1, MOBS do
					local mob = "mob" .. m
					pull:add(mob, "raider1", 1000)
					-- each second a different slice of the raid does damage
					for k = 1, 8 do
						local unit = units[(second * 7 + k * 5 + m) % #units + 1]
						if unit ~= "raider1" then pull:add(mob, unit, 40 + k) end
					end
				end
				if second % 60 == 0 then pull:taunt("mob1", second % 120 == 0 and "raider1" or "raider2") end
			end)
		end

		local reads, t0 = 0, Mock.RealClock()
		for second = 10, SECONDS, 10 do
			pull:to(second)
			if second == SECONDS / 2 then
				Mock.Reload()
				truthy(InCombatLockdown())
			end
			for m = 1, MOBS do
				local mobToken, holders = "nameplate" .. m, 0
				for i = 1, PLAYERS + 1 do
					local isTanking, status, scaled = UnitDetailedThreatSituation("raid" .. i, mobToken)
					reads = reads + 1
					if status then
						truthy(scaled >= 0 and scaled <= 100, "scaled percentage")
						if isTanking then holders = holders + 1 end
					end
				end
				eq(holders, 1, "one holder on " .. mobToken .. " at second " .. second)
			end
		end
		pull:stop()
		eq(#Mock.threat.Mobs(), 0)
		-- the monitor may still hold a state that falls after the fight (1 s dwell) and the recorder, on since v0.4.0,
		-- keeps its session open for END_DELAY after it
		Mock.Advance(Mock.ns.Recorder.END_DELAY + 2)
		eq(Mock.PendingTimers(), 0)
		eq(reads, (SECONDS / 10) * MOBS * (PLAYERS + 1))
		T.log(string.format("%d simulated seconds, %d readings, %.1f s of CPU", SECONDS, reads, Mock.RealClock() - t0))
	end)
end)
