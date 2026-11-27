-- Data/MobRisk.lua (SPEC-07 §1.8, §2.1, M7.2): every rule of the state and reason of a mob in `values` and `state`,
-- with and without designated tanks, the hysteresis and the dwell of the monitor, MOB_STATE_CHANGED only for the shown
-- state of a mob other than the monitored one, the player's own state, and the order of the Dungeon Focus. The module
-- has no game API: the rows are written by hand, as Data/MobTracker.lua and the scanner leave them.

before_boot(function(M) M.features = { monitor = true, multitarget = true, recording = false } end)

local function R() return Mock.ns.MobRisk end
local function now() return Mock.ns.Compat.Now() end
local KEY = "mob:test"

-- A row read on KEY now: { p = scaled %, g = situation, l = lead situation, tank = isTanking, role, token, mode, reason }
local function row(t)
	return {
		mode = t.mode or (t.p ~= nil and "values" or (t.g ~= nil and "state" or "none")),
		reason = t.reason, isTanking = t.tank, situation = t.g, scaledPercent = t.p, leadSituation = t.l,
		role = t.role or "DAMAGER", unitToken = t.token or "party2", unitKey = t.key or ("unit:" .. (t.token or "party2")),
		observedAt = t.at or now(), interval = 0.5, mobKey = t.mobKey or KEY,
	}
end

local function entry(extra)
	local e = { key = KEY, n = 1, monitored = false, stateSince = 0 }
	for k, v in pairs(extra or {}) do e[k] = v end
	return e
end

-- Evaluates a fresh entry on `rows` with `designated` tanks: state, reason, entry.
local function judge(rows, designated, e)
	e = e or entry()
	R().Evaluate(e, rows, #rows, now(), nil, designated or 0, 1)
	return e.state, e.reason, e
end

-- Records MOB_STATE_CHANGED as "key old>new reason".
local function watch()
	local seen = {}
	Mock.ns.Bus.On("MOB_STATE_CHANGED", function(key, old, new, reason)
		seen[#seen + 1] = ("%s %s>%s %s"):format(key, tostring(old), tostring(new), tostring(reason))
	end)
	return seen
end

local TANK = { token = "party1", role = "TANK" }
local function tank(t) t.token, t.role = "party1", "TANK" return row(t) end

describe("the rules in values (SPEC-07 §1.8)", function()
	it("DANGER aggro: designated tanks and a holder that is not one of them", function()
		eq(select(2, judge({ tank{ p = 60 }, row{ p = 100, tank = true, g = 3 } }, 1)), "aggro")
		eq(judge({ tank{ p = 60 }, row{ p = 100, tank = true, g = 3 } }, 1), "DANGER")
	end)

	it("DANGER close: one that does not hold it reaches DANGER", function()
		local state, reason, e = judge({ tank{ p = 100, tank = true, g = 3 }, row{ p = 95 } }, 1)
		eq(state, "DANGER")
		eq(reason, "close")
		eq(e.margin, 5)
		eq(e.topPercent, 95)
		eq(e.mode, "values")
	end)

	it("WARNING no-tank: designated tanks, none on its list, and no watched unit holds it", function()
		local state, reason = judge({ tank{ mode = "none", reason = "nil" }, row{ p = 40 } }, 1)
		eq(state, "WARNING")
		eq(reason, "no-tank")
	end)

	it("WARNING near: one that does not hold it between WARNING and DANGER", function()
		local state, reason = judge({ tank{ p = 100, tank = true, g = 3 }, row{ p = 85 } }, 1)
		eq(state, "WARNING")
		eq(reason, "near")
	end)

	it("SAFE: the holder known and nobody else at WARNING; not-watched when no watched unit holds it", function()
		local state, reason = judge({ tank{ p = 100, tank = true, g = 3 }, row{ p = 40 } }, 1)
		eq(state, "SAFE")
		isNil(reason)
		state, reason = judge({ row{ p = 40 }, row{ token = "party3", p = 20 } }, 0)
		eq(state, "SAFE")
		eq(reason, "not-watched")
	end)

	it("without designated tanks the holder counts as the tank: no aggro and no no-tank", function()
		eq(judge({ row{ p = 100, tank = true, g = 3 }, row{ token = "party3", p = 30 } }, 0), "SAFE")
		local state, reason = judge({ row{ p = 100, tank = true, g = 3 }, row{ token = "party3", p = 93 } }, 0)
		eq(state, "DANGER")
		eq(reason, "close")
	end)

	it("the higher state wins, and on a tie the reason in the order of the table", function()
		eq(select(2, judge({ tank{ p = 70 }, row{ p = 100, tank = true, g = 3 }, row{ token = "party3", p = 95 } }, 1)),
			"aggro")
		local state, reason = judge({ tank{ mode = "none", reason = "nil" }, row{ p = 95 } }, 1)
		eq(state, "DANGER", "close beats no-tank")
		eq(reason, "close")
		eq(select(2, judge({ tank{ mode = "none", reason = "nil" }, row{ p = 85 } }, 1)), "no-tank", "no-tank before near")
	end)
end)

describe("the rules in state only (SPEC-07 §1.8)", function()
	it("DANGER aggro: a non tank with situation 2-3, with designated tanks", function()
		eq(select(2, judge({ tank{ g = 0 }, row{ g = 3 } }, 1)), "aggro")
	end)

	it("DANGER close: the holder at situation 2, or its lead 2-3", function()
		local state, reason, e = judge({ tank{ g = 2 }, row{ g = 1 } }, 1)
		eq(state, "DANGER")
		eq(reason, "close")
		eq(e.mode, "state")
		eq(select(2, judge({ tank{ g = 3, l = 2 }, row{ g = 0 } }, 1)), "close")
	end)

	it("WARNING near: another at situation 1, or the lead 1; WARNING no-tank as in values", function()
		eq(select(2, judge({ tank{ g = 3, l = 0 }, row{ g = 1 } }, 1)), "near")
		eq(select(2, judge({ tank{ g = 3, l = 1 }, row{ g = 0 } }, 1)), "near")
		eq(select(2, judge({ tank{ mode = "none", reason = "nil" }, row{ g = 0 } }, 1)), "no-tank")
	end)

	it("SAFE: the holder at 3 and lead 0; Margin unknown without a lead; not-watched without a holder", function()
		local state, reason = judge({ tank{ g = 3, l = 0 }, row{ g = 0 } }, 1)
		eq(state, "SAFE")
		isNil(reason)
		eq(select(2, judge({ tank{ g = 3 }, row{ g = 0 } }, 1)), "margin-unknown")
		eq(select(2, judge({ row{ g = 0 } }, 0)), "not-watched")
	end)
end)

describe("an unknown mob (SPEC-07 §1.5)", function()
	it("is UNKNOWN with the reason the tracker gives, or with the reason of its rows", function()
		local e = entry()
		R().Evaluate(e, { row{ p = 50 } }, 1, now(), "no-token", 1, 1)
		eq(e.state, "UNKNOWN")
		eq(e.reason, "no-token")
		eq(e.mode, "none")
		local state, reason = judge({ row{ mode = "none", reason = "secret" }, tank{ mode = "none", reason = "secret" } }, 1)
		eq(state, "UNKNOWN")
		eq(reason, "secret")
		eq(select(2, judge({}, 1)), "pending", "no row read yet")
		eq(select(2, judge({ row{ p = 50, mobKey = "mob:other" } }, 1)), "pending", "rows read on another mob do not count")
	end)

	it("does not use a row older than max(2 * interval, 1 s)", function()
		local old = now() - 1.5
		eq(select(2, judge({ row{ p = 95, at = old }, tank{ p = 100, tank = true, g = 3 } }, 1)), nil, "the old 95 % is gone")
		eq(judge({ row{ p = 95, at = now() - 0.9 }, tank{ p = 100, tank = true, g = 3 } }, 1), "DANGER")
	end)
end)

describe("hysteresis and dwell (MON-10, MON-12)", function()
	it("rise at once, fall only after the dwell and below the hysteresis", function()
		local e = entry()
		local holder = tank{ p = 100, tank = true, g = 3 }
		judge({ holder, row{ p = 40 } }, 1, e)
		eq(e.state, "SAFE")
		judge({ holder, row{ p = 92 } }, 1, e)
		eq(e.state, "DANGER", "a rise is immediate")
		Mock.Advance(0.3)
		holder.observedAt = now()
		judge({ holder, row{ p = 70 } }, 1, e)
		eq(e.state, "DANGER", "a fall waits for the dwell")
		Mock.Advance(1)
		holder.observedAt = now()
		judge({ holder, row{ p = 89 } }, 1, e)
		eq(e.state, "DANGER", "89 >= 91 - 3: still DANGER")
		judge({ holder, row{ p = 87 } }, 1, e)
		eq(e.state, "WARNING")
		eq(e.reason, "near")
		Mock.Advance(1.1)
		holder.observedAt = now()
		judge({ holder, row{ p = 80 } }, 1, e)
		eq(e.state, "WARNING", "80 >= 82 - 3")
		judge({ holder, row{ p = 78 } }, 1, e)
		eq(e.state, "SAFE")
	end)

	it("UNKNOWN is a fall: it waits for the dwell too; leaving it is a rise", function()
		local e = entry()
		judge({ tank{ p = 100, tank = true, g = 3 }, row{ p = 85 } }, 1, e)
		eq(e.state, "WARNING")
		R().Evaluate(e, {}, 0, now(), "stale", 1, 1)
		eq(e.state, "WARNING")
		Mock.Advance(1.05)
		R().Evaluate(e, {}, 0, now(), "stale", 1, 1)
		eq(e.state, "UNKNOWN")
		eq(e.reason, "stale")
		judge({ tank{ p = 100, tank = true, g = 3 }, row{ p = 10 } }, 1, e)
		eq(e.state, "SAFE", "out of UNKNOWN at once")
	end)
end)

describe("MOB_STATE_CHANGED (SPEC-07 §1.8)", function()
	it("is emitted for the shown state only, entering and leaving, never for the monitored mob", function()
		local seen = watch()
		local e = entry()
		local holder = tank{ p = 100, tank = true, g = 3 }
		judge({ holder, row{ p = 40 } }, 1, e)
		judge({ holder, row{ p = 45 } }, 1, e)
		judge({ holder, row{ p = 95 } }, 1, e)
		judge({ holder, row{ p = 60 } }, 1, e)   -- held by the dwell: nothing
		R().Leave(e)
		deepEq(seen, { "mob:test nil>SAFE nil", "mob:test SAFE>DANGER close", "mob:test DANGER>nil nil" })
		isNil(e.state)
		local mon = entry{ monitored = true }
		judge({ holder, row{ p = 95 } }, 1, mon)
		R().Leave(mon)
		eq(#seen, 3, "the monitored mob has the monitor's events")
		eq(R().changes, 3)
	end)
end)

describe("the player's own state on a mob (selfState, SPEC-07 §2.5)", function()
	it("follows the rules of a non tank", function()
		local holder = tank{ p = 100, tank = true, g = 3 }
		local _, _, e = judge({ holder, row{ token = "player", p = 93 } }, 1)
		eq(e.selfState, "DANGER")
		_, _, e = judge({ holder, row{ token = "player", p = 84 } }, 1)
		eq(e.selfState, "WARNING")
		_, _, e = judge({ row{ token = "player", p = 100, tank = true, g = 3 } }, 1)
		eq(e.selfState, "DANGER", "holding it")
		_, _, e = judge({ tank{ g = 3 }, row{ token = "player", g = 1 } }, 1)
		eq(e.selfState, "WARNING")
		_, _, e = judge({ holder }, 1)
		isNil(e.selfState, "not on its list")
		_, _, e = judge({ holder, row{ token = "player", mode = "none", reason = "secret" } }, 1)
		eq(e.selfState, "UNKNOWN")
	end)
end)

describe("the order of the Dungeon Focus (SPEC-07 §2.1, Q27)", function()
	it("REASON_ORDER is aggro, close, no-tank, near", function()
		deepEq(R().REASON_ORDER, { "aggro", "close", "no-tank", "near" })
		eq(R().ReasonRank("aggro"), 1)
		eq(R().ReasonRank("near"), 4)
		eq(R().ReasonRank("secret"), 5)
	end)

	it("state, reason, the smaller margin or the higher situation, the player's state, then discovery", function()
		local function e(name, n, state, reason, margin, topSituation, selfState)
			return { name = name, n = n, state = state, reason = reason, margin = margin, topSituation = topSituation,
				selfState = selfState }
		end
		local list = {
			e("unknown", 1, "UNKNOWN", "secret"),
			e("safe", 2, "SAFE", nil, 60),
			e("near", 3, "WARNING", "near", 15),
			e("noTank", 4, "WARNING", "no-tank", 50),
			e("close8", 5, "DANGER", "close", 8),
			e("close5", 6, "DANGER", "close", 5),
			e("aggro", 7, "DANGER", "aggro", 40),
			e("stateClose", 8, "DANGER", "close", nil, 2),
			e("safeSelfWarn", 9, "SAFE", nil, 60, nil, "WARNING"),
			e("safeLater", 10, "SAFE", nil, 60),
		}
		R().Order(list, #list)
		local names = {}
		for i, item in ipairs(list) do names[i] = item.name end
		deepEq(names, { "aggro", "close5", "close8", "stateClose", "noTank", "near", "safeSelfWarn", "safe", "safeLater",
			"unknown" })
	end)

	it("never looks at a name", function()
		local a = { n = 2, state = "SAFE", name = "A" }
		local b = { n = 1, state = "SAFE", name = "Z" }
		truthy(R().Before(b, a))
		falsy(R().Before(a, b))
	end)
end)
