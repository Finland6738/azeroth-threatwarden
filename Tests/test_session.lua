-- Data/Session.lua (SPEC-02 §4, SPEC-05 §1.7, ADR 0016): the base-62 alphabet and the fixed widths, the code of every
-- read and of every event, the packing every 256 rows and events and the join at the close, a decoding equal to what
-- was written (open, interrupted and closed), the limits (rows, events, units, mobs, time), and a session that the
-- SavedVariables serializer accepts as the client would write it.

-- recording off: these sessions are hand-made and Storage would check them at the load (test_storage.lua)
before_boot(function(M) M.features = { recording = false } end)

local function S() return Mock.ns.Session end

local function newSession()
	return S().New{ id = "1767225600-1", started = 1767225600, group = "party", zone = "Test Zone", inst = "none",
		rec = { hz = 2 } }
end

local function rec(mode, situation, percent, reason)
	return { mode = mode, situation = situation, scaledPercent = percent, reason = reason }
end

describe("the alphabet and the widths (SPEC-02 §4.2)", function()
	it("is base 62 with fixed width, the most significant digit first", function()
		eq(#S().ALPHABET, 62)
		eq(S().Encode(0, 3), "000")
		eq(S().Encode(61, 1), "z")
		eq(S().Encode(62, 2), "10")
		eq(S().Encode(S().MAX_T, 3), "zzz")
		eq(S().MAX_T, 238327)
		eq(S().Encode(S().MAX_N, 2), "zz")
		eq(S().Encode(5000, 2), "zz", "clamped to the width")
		eq(S().Encode(-4, 1), "0")
		for _, n in ipairs({ 0, 1, 61, 62, 3843, 100000, 238327 }) do
			eq(S().Read(S().Encode(n, 3), 1, 3), n, tostring(n))
		end
		isNil(S().Read("0-0", 1, 3), "a character outside the alphabet")
	end)

	it("gives every code of a read (SPEC-02 §4.2)", function()
		local cases = {
			{ rec("values", 0, 12.34), true, "0", 123, true },
			{ rec("values", 3, 100), true, "3", 1000, true },
			{ rec("values", nil, 55), true, "4", 550, true },
			{ rec("values", 2, 500), true, "2", 3843, true },
			{ rec("state", 0), true, "a", -1, false },
			{ rec("state", 3), true, "d", -1, false },
			{ rec("none", nil, nil, "secret"), true, "S", -1, false },
			{ rec("none", nil, nil, "error"), true, "E", -1, false },
			{ rec("none", nil, nil, "missing"), true, "M", -1, false },
			{ rec("none", nil, nil, "no-unit"), true, "U", -1, false },
			{ rec("none", nil, nil, "odd"), true, "X", -1, false },
			{ rec("values", 1, 40), false, "T", -1, false },
		}
		for i, case in ipairs(cases) do
			local code, p, numbered = S().RowCode(case[1], case[2])
			eq(code, case[3], "case " .. i)
			eq(p, case[4], "case " .. i)
			eq(numbered, case[5], "case " .. i)
		end
	end)

	it("has the codes of the events (SPEC-02 §4.3)", function()
		for _, k in ipairs({ "C", "c", "T", "S", "A", "M", "D", "L", "H", "N", "G", "X", "Z" }) do
			truthy(S().EVENT_KINDS[k], k)
		end
		eq(S().STATE_CODE.WARNING, "W")
		eq(S().Reason(nil), "-")
		eq(S().Reason("lost-aggro"), "l")
		eq(S().Reason("margin-unknown"), "g")
		eq(S().Reason("stale"), "T")
		eq(S().Reason("anything else"), "X")
		eq(S().RULE_CODE.T1, "1")
		eq(S().RULE_CODE.D5, "C")
		eq(S().RULE_CODE.A1, "D")
		eq(S().ALERT_CODE.margin, "m")
		eq(S().CATEGORY_CODE.calculated, "c")
		eq(S().CONFIDENCE_CODE.medium, "m")
	end)
end)

describe("rows and events", function()
	it("are written, joined and decoded back as they were", function()
		local s = newSession()
		eq(S().AddUnit(s, { name = "Testchar", token = "player", me = true }), 1)
		eq(S().AddMob(s, { name = "Boss", class = "worldboss", npc = 100 }), 1)
		truthy(S().AddEvent(s, 0, "C", 0, 0, 0, "1"))
		truthy(S().AddRow(s, 3, 1, 1, 123, "0"))
		truthy(S().AddRow(s, 5, 1, 1, -1, "b"))
		truthy(S().AddEvent(s, 5, "L", 1, 1, 0, "w", "1", "0", "dh"))
		truthy(S().AddEvent(s, 7, "N", 0, 0, 0, "s", "-", "-", 101))
		truthy(S().AddEvent(s, 9, "c"))
		local open = assert(S().Decode(s))
		S().Join(s)
		isNil(s.parts)
		isNil(s.buf)
		eq(s.cols.t, "003005")
		eq(s.cols.p, "1z--")
		eq(s.cols.s, "0b")
		eq(#s.ev, 12 * 4)
		eq(s.ev:sub(1, 12), "000C0001----")
		eq(s.ev:sub(13, 24), "005L110w10dh")
		local closed = assert(S().Decode(s))
		deepEq(closed.t, { 3, 5 })
		deepEq(closed.p, { 123, -1 })
		deepEq(closed.s, { "0", "b" })
		eq(closed.events[3].k, "N")
		eq(closed.events[3].n, 101)
		eq(closed.events[2].raw, "dh")
		deepEq(closed.t, open.t)
		eq(#closed.events, #open.events)
		for i, e in ipairs(closed.events) do
			for _, f in ipairs({ "t", "k", "m", "u", "v", "a", "b", "c", "n", "raw" }) do
				eq(e[f], open.events[i][f], i .. " " .. f)
			end
		end
	end)

	it("pack every 256 rows and events into pieces, and the join keeps the order (DAT-32)", function()
		local s = newSession()
		S().AddUnit(s, {})
		S().AddMob(s, {})
		for i = 1, 600 do S().AddRow(s, i, 1, 1, i % 1000, "1") end
		for i = 1, 300 do S().AddEvent(s, i, "G", 0, 0, 0, "t", "-", "-", i) end
		eq(#s.parts.t, 2)
		eq(#s.buf.t, 600 - 512)
		eq(#s.parts.ev, 1)
		eq(#s.buf.ev, (300 - 256) * S().EVENT_FIELDS)
		eq(#s.parts.t[1], 256 * 3)
		local before = assert(S().Decode(s))
		S().Join(s)
		eq(#s.cols.t, 3 * 600)
		eq(#s.cols.p, 2 * 600)
		eq(#s.cols.m, 600)
		eq(#s.cols.s, 600)
		eq(#s.ev, 12 * 300)
		falsy(s.cols.t:find("[^%w]"), "only the alphabet")
		local after = assert(S().Decode(s))
		deepEq(after.t, before.t)
		deepEq(after.p, before.p)
		for i = 2, 600 do truthy(after.t[i] >= after.t[i - 1]) end
		eq(after.events[300].n, 300)
	end)

	it("write the same characters as Session.Encode at every digit boundary of the time", function()
		local s = newSession()
		S().AddUnit(s, {})
		S().AddMob(s, {})
		local times = { 0, 1, 61, 62, 63, 3843, 3844, 3845, 7688, 100000, S().MAX_T - 1, S().MAX_T }
		local want, events = {}, {}
		for i, t in ipairs(times) do
			S().AddRow(s, t, 1, 1, i, "0")
			S().AddEvent(s, t, "G", 0, 0, 0, "t", "-", "-", i)
			want[i] = S().Encode(t, 3)
			events[i] = want[i] .. "G000t--" .. S().Encode(i, 2)
		end
		S().Join(s)
		eq(s.cols.t, table.concat(want))
		eq(s.ev, table.concat(events))
	end)

	it("pack 256 rows into little more than the packed strings (ARC-06, SPEC-05 §1.8)", function()
		local s = newSession()
		S().AddUnit(s, {})
		S().AddMob(s, {})
		local t = 0
		local function fill(n)
			for _ = 1, n do
				t = t + 7
				S().AddRow(s, t, 1, 1, t % 1000, "1")
			end
		end
		fill(3 * S().CHUNK + S().CHUNK - 1)     -- the buffers at their size, one row short of the fourth pack
		collectgarbage("collect")
		collectgarbage("collect")
		collectgarbage("stop")
		local before = collectgarbage("count")
		fill(1)
		local kb = collectgarbage("count") - before
		collectgarbage("restart")
		eq(#s.parts.t, 4)
		-- the five pieces are 2 KB; the buffers of table.concat double that or so. A table or a string per row: 50 KB
		truthy(kb < 12, ("one pack allocated %.1f KB"):format(kb))
	end)

	it("never go back in time, and a duplicate event in the same tenth is written once (REC-06, SPEC-05 §1.4)", function()
		local s = newSession()
		S().AddUnit(s, {})
		S().AddMob(s, {})
		S().AddRow(s, 10, 1, 1, 1, "0")
		S().AddRow(s, 8, 1, 1, 2, "0")
		truthy(S().AddEvent(s, 10, "N", 0, 0, 0, "s", "-", "-", 5))
		falsy(S().AddEvent(s, 10, "N", 0, 0, 0, "s", "-", "-", 5))
		truthy(S().AddEvent(s, 11, "N", 0, 0, 0, "s", "-", "-", 5))
		truthy(S().AddEvent(s, 9, "c"))
		local d = assert(S().Decode(s))
		deepEq(d.t, { 10, 10 })
		eq(d.ne, 3)
		eq(d.events[3].t, 11)
	end)

	it("survive the SavedVariables while open, with the waiting rows in the long form (SPEC-02 §4.4)", function()
		local s = newSession()
		S().AddUnit(s, { name = "Testchar" })
		S().AddMob(s, {})
		for i = 1, 300 do S().AddRow(s, i, 1, 1, -1, "S") end
		S().AddEvent(s, 1, "L", 1, 1, 0, "w", "1", "0", "dh")
		AzerothThreatwardenDB.sessions[1] = s
		Mock.Reload()
		local saved = AzerothThreatwardenDB.sessions[1]
		eq(#saved.buf.t, 300 - 256)
		local d = assert(S().Decode(saved))
		eq(d.n, 300)
		eq(d.events[1].raw, "dh")
		S().Join(saved)
		eq(#saved.cols.t, 900)
	end)

	it("say why a damaged session cannot be decoded", function()
		local s = newSession()
		S().AddUnit(s, {})
		S().AddMob(s, {})
		S().AddRow(s, 1, 1, 1, 5, "0")
		S().Join(s)
		s.cols.s = "?"
		local d, why = S().Decode(s)
		isNil(d)
		eq(why, "rows")
		s.cols.s = "0"
		s.n = 2
		eq(select(2, S().Decode(s)), "count")
		s.n = 1
		s.ev = "abc"
		eq(select(2, S().Decode(s)), "events")
	end)
end)

describe("the limits (SPEC-05 §1.7)", function()
	it("stop the samples at LIMITS.rows with trunc and Z r, and the events go on", function()
		local s = newSession()
		S().AddUnit(s, {})
		S().AddMob(s, {})
		for i = 1, S().LIMITS.rows do truthy(S().AddRow(s, math.floor(i / 10), 1, 1, 1, "0")) end
		falsy(S().AddRow(s, 3001, 1, 1, 1, "0"))
		eq(s.n, S().LIMITS.rows)
		eq(s.trunc, 3001)
		falsy(S().AddRow(s, 3002, 1, 1, 1, "0"))
		truthy(S().AddEvent(s, 3002, "c"))
		local d = assert(S().Decode(s))
		eq(d.events[1].k, "Z")
		eq(d.events[1].a, "r")
		eq(d.ne, 2)
	end)

	it("end the events with Z e as the last one", function()
		local s = newSession()
		for i = 1, S().LIMITS.events + 10 do S().AddEvent(s, i, "G", 0, 0, 0, "t", "-", "-", 1) end
		eq(s.ne, S().LIMITS.events)
		local d = assert(S().Decode(s))
		eq(d.events[S().LIMITS.events].k, "Z")
		eq(d.events[S().LIMITS.events].a, "e")
	end)

	it("refuse a unit or a mob past 61, with Z u and Z m once", function()
		local s = newSession()
		for i = 1, 61 do eq(S().AddUnit(s, {}), i) end
		for i = 1, 61 do eq(S().AddMob(s, {}), i) end
		isNil(S().AddUnit(s, {}, 5))
		isNil(S().AddUnit(s, {}, 6))
		isNil(S().AddMob(s, {}, 7))
		eq(#s.units, 61)
		eq(#s.q.v, 61)
		local d = assert(S().Decode(s))
		eq(d.ne, 2)
		eq(d.events[1].a, "u")
		eq(d.events[2].a, "m")
	end)

	it("stop the samples past 6 h 37 min with Z t", function()
		local s = newSession()
		S().AddUnit(s, {})
		S().AddMob(s, {})
		truthy(S().AddRow(s, S().MAX_T, 1, 1, 1, "0"))
		falsy(S().AddRow(s, S().MAX_T + 1, 1, 1, 1, "0"))
		eq(s.trunc, S().MAX_T)
		local d = assert(S().Decode(s))
		eq(d.events[1].a, "t")
		eq(d.events[1].t, S().MAX_T)
	end)
end)
