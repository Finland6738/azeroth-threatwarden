-- Data/Storage.lua (SPEC-05 §2, §6, §7 M4.3; SPEC-02 §3.7, §4.5; STO-01-STO-03, REC-04): the load with good, open and
-- interrupted sessions (with and without the X stamp, ENTERING_WORLD of a reload and of a login), damaged sessions in
-- every field of the fast check and of the deep one (into `corrupt` one by one, the others and the settings intact),
-- duplicate ids, pruning by number and by size (never the open session, at a change of the limits), the size estimate,
-- Delete and DeleteAll with their refusals, read-only data (nothing written), the switch off, Config:SetAside; and a
-- simulated /reload after each case (the SavedVariables serializer of the harness refuses what the client cannot save).

before_boot(function(M) M.features = { monitor = true, alerts = true, coach = true, recording = true } end)

local function St() return Mock.ns.Storage end
local function C() return Mock.ns.Config end
local function list() return AzerothThreatwardenDB.sessions end
local function saved() return Mock.savedText.AzerothThreatwardenDB end

local A = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
local function enc(n, w)
	local out = {}
	for i = w, 1, -1 do
		local d = n % 62
		out[i] = A:sub(d + 1, d + 1)
		n = math.floor(n / 62)
	end
	return table.concat(out)
end

-- The events "C 1" at 0 and "c" at `last`, 12 characters each (SPEC-02 §4.3).
local function events(last)
	return "000C0001----" .. enc(last, 3) .. "c000-----", 2
end

-- A closed session of `n` rows (one unit, one mob, codes 0 at 10.x %, every 0.5 s), as the recorder leaves it.
local function closed(id, started, n, opts)
	n = n or 4
	opts = opts or {}
	local t = {}
	for i = 1, n do t[i] = enc(opts.flat and 0 or i * 5, 3) end
	local ev, ne = events(opts.flat and 0 or n * 5)
	return {
		id = id, started = started, dur = n * 5, fight = n * 5, state = "complete", ended = "combat", stamp = false,
		group = "party", zone = "Test Zone", inst = "party", rec = { hz = 2, version = "v0.4.0" },
		units = { { name = opts.name or "Tankname", class = "WARRIOR", role = "TANK", token = "party1" } },
		mobs = { { name = "Hogger", class = "elite", npc = 448 } },
		n = n, cols = { t = table.concat(t), m = string.rep("1", n), u = string.rep("1", n), p = string.rep("1A", n),
			s = string.rep("0", n) },
		ne = ne, ev = ev, q = { v = { n }, s = { 0 }, x = { 0 } },
	}
end

-- A session saved during a recording (SPEC-02 §4.4): one packed piece of `piece` rows and `waiting` rows in buf.
local function recording(id, started, state, stamp, piece, waiting)
	piece, waiting = piece or 2, waiting or 3
	local s = closed(id, started, 0)
	s.state, s.ended, s.stamp, s.dur, s.fight = state, nil, stamp, stamp and 70 or 0, stamp and 70 or 0
	s.cols = { t = "", m = "", u = "", p = "", s = "" }
	s.ev, s.ne, s.n = "", 0, piece + waiting
	local t = {}
	for i = 1, piece do t[i] = enc(i * 5, 3) end
	s.parts = { t = { table.concat(t) }, m = { string.rep("1", piece) }, u = { string.rep("1", piece) },
		p = { string.rep("1A", piece) }, s = { string.rep("0", piece) }, ev = { "000C0001----" } }
	s.buf = { t = {}, m = {}, u = {}, p = {}, s = {}, ev = { 60, "M", 0, 0, 0, "v", "-", "-", -1 } }
	for i = 1, waiting do
		local k = piece + i
		s.buf.t[i], s.buf.m[i], s.buf.u[i], s.buf.p[i], s.buf.s[i] = k * 5, 1, 1, -1, "a"
	end
	s.ne = 2
	if stamp then
		local ev = s.buf.ev
		for _, v in ipairs({ 70, "X", 0, 0, 0, "o", "-", "-", -1 }) do ev[#ev + 1] = v end
		s.ne = 3
	end
	return s
end

-- Boots with these sessions on disk (and the recording settings `rec`); `schema` 5 unless given.
local function bootWith(sessions, rec, schema)
	T.boot(function(M)
		M.saved = { AzerothThreatwardenDB = { schema = schema or 5,
			settings = { theme = "aurora", recording = rec }, sessions = sessions } }
	end)
end

local function ids()
	local out = {}
	for i, s in ipairs(list()) do out[i] = s.id end
	return table.concat(out, " ")
end

local function bus(event)
	local seen = {}
	Mock.ns.Bus.On(event, function(...) seen[#seen + 1] = { ... } end)
	return seen
end

local function corruptSessions()
	local out = {}
	for _, entry in ipairs(AzerothThreatwardenDB.corrupt) do
		if entry.path == "account.sessions" then out[#out + 1] = entry end
	end
	return out
end

-- A party fight, as in test_recorder.lua: the tank holds the boss, the player at 40 %.
local function partyFight(seconds)
	local pull = Fight.new{
		player = { class = "MAGE", role = "DAMAGER", ranged = true },
		party = { { key = "tank", role = "TANK" }, { key = "rogue", class = "ROGUE", role = "DAMAGER" } },
		mobs = { { key = "boss", tokens = { "target", "boss1" }, classification = "worldboss", npcID = 448 } },
	}
	pull:at(0):start():threat("boss", "tank", 1000):threat("boss", "player", { raw = 500, scaled = 40 })
	pull:at(seconds):stop()
	return pull
end

describe("the load of good sessions (SPEC-05 §2.2)", function()
	it("keeps them as they are, says SESSIONS_CHANGED, and the same after a /reload", function()
		bootWith({ closed("100-1", 100), closed("200-1", 200, 8) })
		truthy(St().loaded)
		eq(ids(), "100-1 200-1")
		eq(list()[2].n, 8)
		eq(#corruptSessions(), 0)
		eq(#C().issues, 0)
		Mock.Reload()
		local first = saved()
		eq(ids(), "100-1 200-1")
		Mock.Reload()
		eq(saved(), first, "a load of clean data writes the same")
		eq(AzerothThreatwardenDB.settings.theme, "aurora")
	end)

	it("lists the headers newest first, never the columns", function()
		bootWith({ closed("300-1", 300), closed("100-1", 100), closed("200-1", 200) })
		local headers = St().List()
		eq(#headers, 3)
		eq(headers[1].id, "300-1")
		eq(headers[2].id, "200-1")
		eq(headers[3].id, "100-1")
		eq(headers[1].units, 1)
		eq(headers[1].n, 4)
		isNil(headers[1].cols)
		isNil(headers[1].ev)
		eq(St().Get("200-1"), list()[3])
		isNil(St().Get("nope"))
		Mock.Reload()
		eq(St().List()[1].id, "300-1")
	end)

	it("migrates data of schema 3 with and without `sessions` (SPEC-05 §2.3)", function()
		bootWith(nil, nil, 3)
		eq(AzerothThreatwardenDB.schema, 6)
		deepEq(list(), {})
		truthy(St().loaded)
		Mock.Reload()
		deepEq(list(), {})
		bootWith({ closed("100-1", 100), "not a session" }, nil, 3)
		eq(AzerothThreatwardenDB.schema, 6)
		eq(ids(), "100-1")
		eq(#corruptSessions(), 1, "the damaged one set aside by Storage, not by the migration")
		Mock.Reload()
		eq(ids(), "100-1")
		eq(#corruptSessions(), 1)
	end)

	it("decodes a session after the deep check, one in memory at a time", function()
		bootWith({ closed("100-1", 100, 6) })
		local out = assert(St().Decode("100-1"))
		eq(out.n, 6)
		eq(out.t[6], 30)
		eq(out.p[1], 72)
		eq(#out.events, 2)
		eq(St().Decode("100-1"), out, "kept while nothing changed")
		eq(select(2, St().Decode("nope")), "unknown")
		Mock.Reload()
		eq(St().Decode("100-1").n, 6)
	end)
end)

describe("interrupted sessions (SPEC-05 §1.6, §2.2 point 2, REC-04)", function()
	it("an open one without the stamp (a crash) becomes interrupted with ended unknown", function()
		bootWith({ recording("100-1", 100, "open", false) })
		local s = list()[1]
		eq(s.state, "interrupted")
		eq(s.ended, "unknown")
		isNil(s.parts)
		isNil(s.buf)
		eq(s.n, 5)
		eq(s.ne, 2)
		eq(#s.cols.t, 15)
		eq(s.cols.s, "00aaa")
		eq(s.dur, 60, "the last t written")
		truthy(St().Decode("100-1"))
		Mock.Reload()
		eq(list()[1].state, "interrupted")
		eq(list()[1].ended, "unknown", "a later reload does not change it")
		eq(list()[1].n, 5)
	end)

	it("an interrupted one with the stamp ends with reload after a /reload, with login after a login", function()
		bootWith({ recording("100-1", 100, "interrupted", true) })
		eq(list()[1].ended, "login", "T.boot logs in")
		eq(list()[1].ne, 3)
		T.boot(function(M)
			M.saved = { AzerothThreatwardenDB = { schema = 4, sessions = { recording("100-1", 100, "interrupted", true) } } }
		end)
		Mock.Reload()
		eq(list()[1].ended, "login", "completed at the first load, which was a login")
		-- the session saved during the fight, read back at a /reload
		T.boot()
		local pull = partyFight(30)
		pull:to(8)
		Mock.Reload()
		local old = list()[1]
		eq(old.state, "interrupted")
		eq(old.ended, "reload")
		isNil(old.buf)
		truthy(St().Decode(old.id))
		eq(list()[2].after, old.id, "the new session is linked")
		pull:finish()
		Mock.Advance(6)
		Mock.Reload()
		eq(list()[1].ended, "reload")
		eq(list()[2].state, "complete")
		eq(#Mock.errors, 0)
	end)

	it("ENTERING_WORLD without the flags leaves ended unknown", function()
		T.boot()
		list()[1] = recording("100-1", 100, "interrupted", true)
		St().Load()
		eq(list()[1].ended, "unknown")
		Mock.Fire("PLAYER_ENTERING_WORLD")
		eq(list()[1].ended, "unknown")
		Mock.Reload()
		eq(list()[1].ended, "unknown")
	end)

	it("an interrupted one without rows goes; a complete one with pieces (logout in END_DELAY) is joined", function()
		local empty = recording("100-1", 100, "interrupted", true, 0, 0)
		empty.parts = { t = {}, m = {}, u = {}, p = {}, s = {}, ev = {} }
		local delayed = recording("200-1", 200, "complete", false)
		delayed.ended = "combat"
		bootWith({ empty, delayed })
		eq(ids(), "200-1")
		eq(list()[1].state, "complete")
		eq(list()[1].ended, "combat")
		isNil(list()[1].buf)
		eq(St().Usage().dropped, 1)
		eq(#corruptSessions(), 0, "dropped, not damaged")
		Mock.Reload()
		eq(ids(), "200-1")
	end)

	it("never touches the open session of the recorder at a second load", function()
		T.boot()
		local pull = partyFight(20)
		pull:to(5)
		local open = Mock.ns.Recorder.current
		notNil(open.buf)
		St().Load()
		eq(list()[1], open)
		notNil(open.buf, "not joined")
		eq(open.state, "open")
		pull:finish()
		Mock.Advance(6)
		eq(open.state, "complete")
		Mock.Reload()
		eq(list()[1].state, "complete")
	end)
end)

describe("damaged sessions (SPEC-05 §2.2 point 4, STO-01)", function()
	-- Each case breaks one field of the fast check in the middle session of three.
	local CASES = {
		{ "not a table", function() return "broken" end },
		{ "no id", function(s) s.id = nil end },
		{ "an id too long", function(s) s.id = string.rep("x", 41) end },
		{ "an id not a string", function(s) s.id = 12 end },
		{ "started not a number", function(s) s.started = "yesterday" end },
		{ "an unknown state", function(s) s.state = "paused" end },
		{ "units not a table", function(s) s.units = "x" end },
		{ "a unit not a table", function(s) s.units[2] = "x" end },
		{ "more than 61 units", function(s) for i = 1, 62 do s.units[i] = {} end end },
		{ "mobs with a hole", function(s) s.mobs[3] = {} end },
		{ "units with a hole", function(s) s.units = { {}, nil, {}, {} } end },
		{ "n not whole", function(s) s.n = 3.5 end },
		{ "n over the limit", function(s) s.n = 30001 end },
		{ "ne negative", function(s) s.ne = -1 end },
		{ "no columns", function(s) s.cols = nil end },
		{ "a column too short", function(s) s.cols.t = s.cols.t:sub(4) end },
		{ "a character outside the alphabet", function(s) s.cols.p = "!" .. s.cols.p:sub(2) end },
		{ "ev too long", function(s) s.ev = s.ev .. "0" end },
		{ "ev with a space", function(s) s.ev = " " .. s.ev:sub(2) end },
		{ "pieces without buf", function(s) s.parts = {} end },
		{ "buf with a word for a time", function(s) s.parts, s.buf = {}, { t = { "soon" }, m = { 1 }, u = { 1 },
			p = { -1 }, s = { "a" } } end },
		{ "buf with columns of different lengths", function(s) s.parts, s.buf = {}, { t = { 1, 2 }, m = { 1 },
			u = { 1 }, p = { -1 }, s = { "a" } } end },
		{ "buf.ev not in nines", function(s) s.parts, s.buf = {}, { ev = { 1, "C", 0 } } end },
		{ "a piece with a bad character", function(s) s.state, s.parts, s.buf = "open", { t = { "0 0" } }, {} end },
		{ "pieces that do not add up", function(s) s.state, s.parts, s.buf = "open", { t = { "005" } }, {} end },
	}
	for _, case in ipairs(CASES) do
		it("sets aside the one with " .. case[1] .. ", the others and the settings intact", function()
			local bad = closed("200-1", 200, 4, { name = "Brokenname" })
			bad = case[2](bad) or bad
			bootWith({ closed("100-1", 100), bad, closed("300-1", 300) }, { maxKB = 4096 })
			eq(ids(), "100-1 300-1")
			eq(list()[1].n, 4)
			eq(C():Get("account.settings.recording.maxKB"), 4096)
			eq(AzerothThreatwardenDB.settings.theme, "aurora")
			local entries = corruptSessions()
			eq(#entries, 1)
			eq(entries[1].kind, "session")
			local data = entries[1].data
			isNil(data.cols, "never the columns")
			isNil(data.ev)
			isNil(data.units, "never the units and their names")
			isNil(data.parts)
			isNil(data.buf)
			contains(table.concat(C().issues, "\n"), "account.sessions: one recording was damaged and set aside")
			eq(St().Usage().damaged, 1)
			Mock.Reload()
			eq(ids(), "100-1 300-1")
			eq(#corruptSessions(), 1)
			falsy(saved():find("Brokenname"), "no name of the damaged session is kept")
			eq(#Mock.errors, 0)
		end)
	end

	it("keeps at most 5 entries in `corrupt`, the oldest going first", function()
		local all = {}
		for i = 1, 7 do all[i] = "broken " .. i end
		all[8] = closed("100-1", 100)
		bootWith(all)
		eq(ids(), "100-1")
		eq(#AzerothThreatwardenDB.corrupt, 5)
		Mock.Reload()
		eq(#AzerothThreatwardenDB.corrupt, 5)
	end)

	local DEEP = {
		{ "a time that goes back", function(s) s.cols.t = "00A005" .. s.cols.t:sub(7) end },
		{ "a mob index outside `mobs`", function(s) s.cols.m = "2" .. s.cols.m:sub(2) end },
		{ "a unit index of 0", function(s) s.cols.u = "0" .. s.cols.u:sub(2) end },
		{ "an unknown row code", function(s) s.cols.s = "Q" .. s.cols.s:sub(2) end },
		{ "a number on an unknown read", function(s) s.cols.s = "S" .. s.cols.s:sub(2) end },
		{ "no number on a read with values", function(s) s.cols.p = "--" .. s.cols.p:sub(3) end },
		{ "an event of an unknown kind", function(s) s.ev = "000Q0001----" .. s.ev:sub(13) end },
		{ "an event with a unit outside `units`", function(s) s.ev = "000C0201----" .. s.ev:sub(13) end },
	}
	for _, case in ipairs(DEEP) do
		it("finds " .. case[1] .. " at decode and sets it aside out of combat", function()
			local bad = closed("200-1", 200)
			case[2](bad)
			bootWith({ closed("100-1", 100), bad })
			eq(ids(), "100-1 200-1", "the fast check lets it through")
			local changed = bus("SESSIONS_CHANGED")
			local out, why = St().Decode("200-1")
			isNil(out)
			eq(why, "damaged")
			eq(ids(), "100-1")
			eq(#changed, 1)
			eq(corruptSessions()[1].kind, "session")
			eq(corruptSessions()[1].data.why ~= nil, true)
			Mock.Reload()
			eq(ids(), "100-1")
			eq(#corruptSessions(), 1)
		end)
	end

	it("waits for the end of the fight before setting a session aside found damaged in combat", function()
		local bad = closed("200-1", 200)
		bad.cols.m = "2" .. bad.cols.m:sub(2)
		bootWith({ closed("100-1", 100), bad })
		local pull = partyFight(10)
		pull:to(4)
		eq(select(2, St().Decode("200-1")), "damaged")
		eq(#list(), 3, "still there in combat")
		isNil(St().Get("200-1"), "but hidden")
		pull:finish()
		eq(#corruptSessions(), 1)
		isNil(St().Get("200-1"))
		Mock.Advance(6)
		Mock.Reload()
		eq(#corruptSessions(), 1)
		eq(ids(), "100-1 " .. list()[2].id)
		eq(#list(), 2)
	end)
end)

describe("duplicate ids (SPEC-05 §2.2 point 3)", function()
	it("gives the second and the third a suffix, kept after a /reload", function()
		bootWith({ closed("100-1", 100), closed("100-1", 101), closed("100-1", 102), closed("100-1-b", 103) })
		eq(ids(), "100-1 100-1-b 100-1-c 100-1-b-b")
		eq(St().Usage().count, 4)
		Mock.Reload()
		eq(ids(), "100-1 100-1-b 100-1-c 100-1-b-b")
	end)
end)

describe("limits and pruning (SPEC-05 §2.4, STO-02)", function()
	it("keeps at most maxSessions at load, the oldest by `started` going first", function()
		local all = {}
		for i, started in ipairs({ 500, 100, 700, 300, 200, 800, 600, 400 }) do all[i] = closed(started .. "-1", started) end
		bootWith(all, { maxSessions = 5 })
		eq(ids(), "500-1 700-1 800-1 600-1 400-1")
		eq(St().Usage().pruned, 3)
		Mock.Reload()
		eq(#list(), 5)
		eq(St().Usage().pruned, 0)
	end)

	it("keeps the estimated size under maxKB at load", function()
		local all = {}
		for i = 1, 3 do all[i] = closed(i .. "00-1", i * 100, 30000, { flat = true }) end
		bootWith(all, { maxKB = 512 })
		eq(ids(), "200-1 300-1")
		local usage = St().Usage()
		truthy(usage.bytes <= 512 * 1024, "within the limit")
		truthy(usage.bytes > 400 * 1024)
		eq(usage.maxKB, 512)
		Mock.Reload()
		eq(ids(), "200-1 300-1")
		truthy(#saved() < 600 * 1024)
	end)

	it("estimates the size of each session with Config.EstimateSize", function()
		bootWith({ closed("100-1", 100, 10), closed("200-1", 200, 300) })
		local sum = C().EstimateSize(list()[1]) + C().EstimateSize(list()[2])
		eq(St().Usage().bytes, sum)
		eq(St().List()[1].bytes, C().EstimateSize(list()[2]))
		truthy(sum > 300 * 8)
		Mock.Reload()
		eq(St().Usage().bytes, sum)
	end)

	it("prunes when the limits change, says SESSIONS_CHANGED, and never the open session", function()
		local all = {}
		for i = 1, 6 do all[i] = closed(i .. "00-1", i * 100) end
		bootWith(all)
		local pull = partyFight(10)
		pull:to(4)
		local open = Mock.ns.Recorder.current
		eq(#list(), 7)
		local changed = bus("SESSIONS_CHANGED")
		truthy(C():Set("account.settings.recording.maxSessions", 5))
		eq(#list(), 5, "the open one counts")
		eq(list()[5], open, "and stays")
		eq(ids():sub(1, 23), "300-1 400-1 500-1 600-1")
		eq(#changed, 1)
		pull:finish()
		Mock.Advance(6)
		eq(#list(), 5, "after the close too")
		eq(list()[5], open)
		Mock.Reload()
		eq(#list(), 5)
		eq(list()[5].state, "complete")
	end)

	it("prunes after every close", function()
		local all = {}
		for i = 1, 5 do all[i] = closed(i .. "00-1", i * 100) end
		bootWith(all, { maxSessions = 5 })
		partyFight(6):finish()
		Mock.Advance(6)
		eq(#list(), 5)
		eq(list()[1].id, "200-1")
		eq(St().Usage().pruned, 1)
		Mock.Reload()
		eq(#list(), 5)
	end)

	it("never prunes the open session, even when it alone is over the number", function()
		local all = {}
		for i = 1, 5 do all[i] = closed(i .. "00-1", i * 100) end
		bootWith(all, { maxSessions = 5 })
		local pull = partyFight(30)
		pull:to(4)
		local open = Mock.ns.Recorder.current
		eq(St().Prune(), 1)
		eq(St().Prune(), 0)
		St().DeleteAll()
		eq(#list(), 1)
		eq(list()[1], open)
		eq(St().Prune(), 0)
		eq(list()[1], open)
		pull:finish()
		Mock.Advance(6)
		Mock.Reload()
		eq(#list(), 1)
	end)
end)

describe("deleting (SPEC-05 §2.5, STO-03)", function()
	it("deletes one session; it and its names are gone after a /reload", function()
		bootWith({ closed("100-1", 100), closed("200-1", 200, 4, { name = "Deletedname" }) })
		local changed = bus("SESSIONS_CHANGED")
		truthy(St().Delete("200-1"))
		eq(ids(), "100-1")
		eq(#changed, 1)
		eq(select(2, St().Delete("200-1")), "unknown")
		eq(select(2, St().Delete(nil)), "unknown")
		Mock.Reload()
		eq(ids(), "100-1")
		falsy(saved():find("Deletedname"), "the name is not in the SavedVariables")
		contains(saved(), "Tankname")
	end)

	it("refuses the open session; DeleteAll keeps it and removes the others", function()
		bootWith({ closed("100-1", 100, 4, { name = "Deletedname" }), closed("200-1", 200) })
		local pull = partyFight(10)
		pull:to(4)
		local open = Mock.ns.Recorder.current
		eq(select(2, St().Delete(open.id)), "recording")
		local ok, count = St().DeleteAll()
		truthy(ok)
		eq(count, 2)
		eq(#list(), 1)
		eq(list()[1], open)
		pull:finish()
		Mock.Advance(6)
		eq(#list(), 1)
		truthy(St().Delete(open.id))
		deepEq(list(), {})
		Mock.Reload()
		deepEq(list(), {})
		falsy(saved():find("Deletedname"))
		falsy(saved():find("Hogger"))
	end)

	it("Reset settings does not touch the sessions", function()
		bootWith({ closed("100-1", 100) }, { maxKB = 4096 })
		truthy(C():ResetSettings())
		eq(ids(), "100-1")
		Mock.Reload()
		eq(ids(), "100-1")
	end)
end)

describe("read-only data (SPEC-05 §2.6)", function()
	local function bootNewer()
		local bad = closed("200-1", 200)
		bad.cols.t = "x"
		local all = { closed("100-1", 100), bad, recording("300-1", 300, "interrupted", true),
			closed("100-1", 400) }
		for i = 1, 30 do all[#all + 1] = closed("x" .. i, 1000 + i) end
		bootWith(all, { maxSessions = 5 }, 7)
	end

	it("completes, sets aside, prunes and deletes nothing; hides and counts the damaged ones", function()
		bootNewer()
		truthy(C():IsReadOnly("account"))
		eq(#list(), 34, "nothing pruned")
		notNil(list()[3].buf, "nothing completed")
		eq(list()[4].id, "100-1", "nothing renamed")
		eq(St().Usage().count, 33)
		eq(St().Usage().damaged, 1)
		isNil(St().Get("200-1"))
		eq(#St().List(), 33)
		eq(select(2, St().Delete("100-1")), "read-only")
		eq(select(2, St().DeleteAll()), "read-only")
		eq(St().Prune(), 0)
		eq(select(2, C():SetAside("account.sessions", {}, "session")), "read-only")
		eq(#C().db.account.corrupt, 0)
		isNil(AzerothThreatwardenDB.corrupt, "the saved table is never written")
		contains(table.concat(St().DebugLines(), "\n"), "READ-ONLY")
	end)

	it("writes nothing over two /reloads", function()
		bootNewer()
		Mock.Reload()
		local first = saved()
		Mock.Reload()
		eq(saved(), first)
		contains(first, '["buf"]', "the interrupted one stays as it was")
		contains(first, '["schema"]=7')
		eq(#Mock.errors, 0)
	end)
end)

describe("the switch off (ADR 0014)", function()
	before_boot(function(M) M.features = { monitor = true, recording = false } end)

	it("checks nothing, writes nothing and refuses to delete", function()
		local bad = closed("200-1", 200)
		bad.cols.t = "x"
		bootWith({ closed("100-1", 100), bad, recording("300-1", 300, "open", false), closed("100-1", 400) })
		falsy(St().loaded)
		eq(#list(), 4)
		deepEq(St().List(), {})
		eq(select(2, St().Delete("100-1")), "off")
		eq(select(2, St().DeleteAll()), "off")
		Mock.Reload()
		local first = saved()
		Mock.Reload()
		eq(saved(), first)
		eq(#list(), 4)
		notNil(list()[3].parts)
		eq(#AzerothThreatwardenDB.corrupt, 0)
	end)
end)

describe("Config:SetAside (SPEC-02 §3.7)", function()
	it("adds a bounded copy with its kind, at most 5 entries", function()
		T.boot()
		truthy(C():SetAside("account.sessions", { id = "a", long = string.rep("x", 500) }, "session"))
		local entry = AzerothThreatwardenDB.corrupt[1]
		eq(entry.scope, "account")
		eq(entry.path, "account.sessions")
		eq(entry.kind, "session")
		eq(#entry.data.long, 200)
		truthy(C():SetAside("account.sessions", "text"))
		eq(AzerothThreatwardenDB.corrupt[2].kind, "string")
		isNil(AzerothThreatwardenDB.corrupt[2].data)
		for i = 1, 6 do C():SetAside("account.sessions", { i = i }) end
		eq(#AzerothThreatwardenDB.corrupt, 5)
		eq(AzerothThreatwardenDB.corrupt[5].data.i, 6)
		eq(select(2, C():SetAside(nil, {})), "unknown path")
		Mock.Reload()
		eq(#AzerothThreatwardenDB.corrupt, 5)
	end)
end)

describe("/atw debug, the storage part of Recording", function()
	it("counts kept, pruned, damaged and deleted sessions, never a name", function()
		local bad = closed("300-1", 300, 4, { name = "Brokenname" })
		bad.n = -2
		bootWith({ closed("100-1", 100), closed("200-1", 200), bad }, { maxSessions = 5 })
		St().Delete("100-1")
		local text = table.concat(Mock.ns.Recorder.DebugLines(), "\n")
		contains(text, "sessions kept: 1")
		contains(text, "of at most 2048 KB and 5 sessions")
		contains(text, "1 damaged (1 set aside, 0 hidden), 1 deleted")
		falsy(text:find("Tankname"))
		falsy(text:find("Brokenname"))
		falsy(text:find("Hogger"))
		falsy(text:find("Test Zone"))
		Mock.Reload()
		contains(table.concat(Mock.ns.Recorder.DebugLines(), "\n"), "sessions kept: 1")
	end)
end)
