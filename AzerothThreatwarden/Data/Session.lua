-- Session: one recorded session in the compact form of SPEC-02 §4 (ADR 0016). Lua 5.1, no game API, no Bus event.
-- Threatwarden's own.
--
--   Session.New(header)                 a new open session (SPEC-02 §4.1), with empty columns, `parts` and `buf`
--   Session.AddUnit(s, entry, t)        an entry of `units` -> its index, or nil past LIMITS.units (event Z u, once)
--   Session.AddMob(s, entry, t)         an entry of `mobs` -> its index, or nil past LIMITS.mobs (event Z m, once)
--   Session.AddRow(s, t, m, u, p, code) a row of samples (t in tenths, p = scaled % x 10 or -1) -> true, or false once a
--                                       limit stopped the samples (trunc, event Z r / Z t)
--   Session.AddEvent(s, t, k, m, u, v, a, b, c, n)   an event record (SPEC-02 §4.3) -> true, or false (a duplicate in
--                                       the same tenth, or past LIMITS.events: the last one is Z e)
--   Session.Join(s)                     the close: the pieces and `buf` become one string per column; parts and buf go
--   Session.Decode(s)                   the rows and events of a session, open, interrupted or closed -> table, or nil
--                                       and why
--   Session.RowCode(rec, fresh)         the code of a read (SPEC-02 §4.2) and whether the row carries a number
--
-- While a session is open the rows and events wait in `buf` (arrays of numbers and one-character codes, reused: the
-- entries are cleared, never the tables); every CHUNK rows (or events) they are packed into one string per column,
-- added to `parts`. The session is already in `sessions`, so a /reload saves it as it is, with at most CHUNK - 1 rows
-- and events in the long form (SPEC-02 §4.4). Data/Storage.lua (M4.3) joins an interrupted one at the next load with
-- the same Session.Join. Session.LIMITS is the table SPEC-05 §1.7 calls `Storage.LIMITS`.
local ADDON_NAME, ns = ...
ns = ns or {}
ns.modules = ns.modules or {}

local Session = {}
ns.Session, ns.modules.Session = Session, Session

local type, floor, concat, setmetatable = type, math.floor, table.concat, setmetatable

Session.ALPHABET = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
Session.CHUNK = 256
-- SPEC-05 §1.7: rows and events of one session, entries of `units` and `mobs` (one character each), the shortest fight
-- kept (seconds of combat, with at least one row), the link of a session after a /reload in combat (seconds).
Session.LIMITS = { rows = 30000, events = 6000, units = 61, mobs = 61, minFight = 3, link = 120 }
Session.MAX_T = 62 * 62 * 62 - 1     -- 238 327 tenths: 6 h 37 min, the three characters of `t`
Session.MAX_N = 62 * 62 - 1          -- 3843: two characters
Session.WIDTH = { t = 3, m = 1, u = 1, p = 2, s = 1 }
Session.COLUMNS = { "t", "m", "u", "p", "s" }
Session.EVENT_WIDTH = 12
Session.EVENT_FIELDS = 9             -- t k m u v a b c n, one after the other in buf.ev

local DIGIT, VALUE = {}, {}
for i = 1, 62 do
	local ch = Session.ALPHABET:sub(i, i)
	DIGIT[i - 1], VALUE[ch] = ch, i - 1
end
Session.DIGIT, Session.VALUE = DIGIT, VALUE

-- The codes of SPEC-02 §4.2 and §4.3.
Session.ROW_CODES = { ["0"] = true, ["1"] = true, ["2"] = true, ["3"] = true, ["4"] = true, a = true, b = true,
	c = true, d = true, S = true, E = true, M = true, U = true, X = true, T = true }
Session.NUMBERED = { ["0"] = true, ["1"] = true, ["2"] = true, ["3"] = true, ["4"] = true }
Session.EVENT_KINDS = { C = true, c = true, T = true, S = true, A = true, M = true, D = true, L = true, H = true,
	N = true, G = true, X = true, Z = true }
local ROW_REASON = { secret = "S", error = "E", missing = "M", ["no-unit"] = "U" }
local STATE_SITUATION = { [0] = "a", [1] = "b", [2] = "c", [3] = "d" }
Session.STATE_CODE = { SAFE = "S", WARNING = "W", DANGER = "D", UNKNOWN = "U" }
Session.REASON_CODE = { predicted = "p", aggro = "a", ["lost-aggro"] = "l", behind = "b", alone = "o",
	["margin-unknown"] = "g", ["state-only"] = "s", secret = "S", missing = "M", error = "E", ["no-unit"] = "U",
	stale = "T" }
Session.MODE_CODE = { values = "v", state = "s", none = "n" }
Session.CATEGORY_CODE = { detected = "d", calculated = "c", estimated = "e", predicted = "p", hypothesis = "h",
	unknown = "u" }
Session.CONFIDENCE_CODE = { high = "h", medium = "m", low = "l", unknown = "u" }
Session.ALERT_CODE = { warning = "w", danger = "d", aggro = "a", margin = "m", lost = "l", pet = "p", other = "o" }
Session.RULE_CODE = { T1 = "1", T2 = "2", T3 = "3", T4 = "4", T5 = "5", T6 = "6", T7 = "7", D1 = "8", D2 = "9",
	D3 = "A", D4 = "B", D5 = "C", A1 = "D" }

-- The code of a reason of S and M ("-" none, "X" any other).
function Session.Reason(reason)
	if reason == nil then return "-" end
	return Session.REASON_CODE[reason] or "X"
end

---------------------------------------------------------------------------------------------------------------------
-- Base 62, fixed width
---------------------------------------------------------------------------------------------------------------------
local ENC1 = DIGIT
local ENC2 = {}
for i = 0, Session.MAX_N do ENC2[i] = DIGIT[floor(i / 62)] .. DIGIT[i % 62] end

-- `n` (a whole number >= 0, clamped to the width) in `w` characters.
function Session.Encode(n, w)
	n = floor(n)
	if n < 0 then n = 0 end
	if w == 1 then return ENC1[n > 61 and 61 or n] end
	if w == 2 then return ENC2[n > Session.MAX_N and Session.MAX_N or n] end
	local out = {}
	for i = w, 1, -1 do
		out[i] = DIGIT[n % 62]
		n = floor(n / 62)
	end
	return concat(out)
end

-- The number in `str` from `pos`, `w` characters; nil when a character is not of the alphabet.
function Session.Read(str, pos, w)
	local n = 0
	for i = pos, pos + w - 1 do
		local v = VALUE[str:sub(i, i)]
		if v == nil then return nil end
		n = n * 62 + v
	end
	return n
end

---------------------------------------------------------------------------------------------------------------------
-- A new session; the runtime part (never saved) in a table with weak keys
---------------------------------------------------------------------------------------------------------------------
local live = setmetatable({}, { __mode = "k" })   -- session -> { lastRowT, lastEvT, stopped, z = {}, last = {9} }

local function newBuf()
	return { t = {}, m = {}, u = {}, p = {}, s = {}, ev = {} }
end

local function liveOf(s)
	local r = live[s]
	if not r then
		r = { lastRowT = 0, lastEvT = 0, stopped = false, z = {}, last = {}, nev = 0 }
		live[s] = r
	end
	return r
end

-- header: id, started, group, zone, inst, diff, rec, after.
function Session.New(header)
	local s = {
		id = header.id, started = header.started, dur = 0, fight = 0, state = "open", ended = nil, stamp = false,
		after = header.after, trunc = nil, group = header.group, zone = header.zone, inst = header.inst,
		diff = header.diff, rec = header.rec or {}, units = {}, mobs = {}, n = 0,
		cols = { t = "", m = "", u = "", p = "", s = "" }, ne = 0, ev = "", q = { v = {}, s = {}, x = {} },
		sum = nil, parts = { t = {}, m = {}, u = {}, p = {}, s = {}, ev = {} }, buf = newBuf(),
	}
	liveOf(s)
	return s
end

---------------------------------------------------------------------------------------------------------------------
-- Packing
---------------------------------------------------------------------------------------------------------------------
local WIDTH = Session.WIDTH

local function encodeRows(buf, column, from, to)
	local out, values = {}, buf[column]
	if column == "s" then
		for i = from, to do out[#out + 1] = values[i] end
	elseif column == "p" then
		for i = from, to do
			local p = values[i]
			out[#out + 1] = (type(p) == "number" and p >= 0) and ENC2[p > Session.MAX_N and Session.MAX_N or floor(p)]
				or "--"
		end
	else
		local w = WIDTH[column]
		for i = from, to do out[#out + 1] = Session.Encode(values[i], w) end
	end
	return concat(out)
end

local function encodeEvent(ev, i)
	local n = ev[i + 8]
	local nn
	if type(n) == "string" and #n == 2 then nn = n
	elseif type(n) == "number" and n >= 0 then nn = ENC2[n > Session.MAX_N and Session.MAX_N or floor(n)]
	else nn = "--" end
	return Session.Encode(ev[i], 3) .. ev[i + 1] .. ENC1[ev[i + 2]] .. ENC1[ev[i + 3]] .. ENC1[ev[i + 4]]
		.. ev[i + 5] .. ev[i + 6] .. ev[i + 7] .. nn
end

local function encodeEvents(ev)
	local out, F = {}, Session.EVENT_FIELDS
	for i = 1, #ev, F do out[#out + 1] = encodeEvent(ev, i) end
	return concat(out)
end

local function clear(list)
	for i = #list, 1, -1 do list[i] = nil end
end

-- The rows waiting in buf become one piece per column.
function Session.PackRows(s)
	local buf, parts = s.buf, s.parts
	if not buf or #buf.t == 0 then return end
	local count = #buf.t
	for _, column in ipairs(Session.COLUMNS) do
		local list = parts[column]
		list[#list + 1] = encodeRows(buf, column, 1, count)
	end
	for _, column in ipairs(Session.COLUMNS) do clear(buf[column]) end
end

function Session.PackEvents(s)
	local buf, parts = s.buf, s.parts
	if not buf or #buf.ev == 0 then return end
	parts.ev[#parts.ev + 1] = encodeEvents(buf.ev)
	clear(buf.ev)
end

-- The close (SPEC-02 §4.4): pieces and buf joined into one string per column; `parts` and `buf` go. Works on a session
-- read back from the saved data too (Storage, M4.3). Returns the session.
function Session.Join(s)
	local parts, buf = s.parts, s.buf
	if type(parts) ~= "table" or type(buf) ~= "table" then
		s.parts, s.buf = nil, nil
		return s
	end
	local cols = s.cols or {}
	for _, column in ipairs(Session.COLUMNS) do
		local pieces = { cols[column] or "" }
		for _, piece in ipairs(parts[column] or {}) do pieces[#pieces + 1] = piece end
		if type(buf[column]) == "table" and #buf[column] > 0 then
			pieces[#pieces + 1] = encodeRows(buf, column, 1, #buf[column])
		end
		cols[column] = concat(pieces)
	end
	s.cols = cols
	local pieces = { s.ev or "" }
	for _, piece in ipairs(parts.ev or {}) do pieces[#pieces + 1] = piece end
	if type(buf.ev) == "table" and #buf.ev > 0 then pieces[#pieces + 1] = encodeEvents(buf.ev) end
	s.ev = concat(pieces)
	s.parts, s.buf = nil, nil
	return s
end

---------------------------------------------------------------------------------------------------------------------
-- Writing
---------------------------------------------------------------------------------------------------------------------
local F = Session.EVENT_FIELDS

-- Writes an event record without the checks of AddEvent (the limit events Z themselves).
local function push(s, r, t, k, m, u, v, a, b, c, n)
	local ev = s.buf.ev
	local i = #ev
	ev[i + 1], ev[i + 2], ev[i + 3], ev[i + 4], ev[i + 5] = t, k, m or 0, u or 0, v or 0
	ev[i + 6], ev[i + 7], ev[i + 8], ev[i + 9] = a or "-", b or "-", c or "-", n or -1
	local last = r.last
	last[1], last[2], last[3], last[4], last[5] = t, k, m or 0, u or 0, v or 0
	last[6], last[7], last[8], last[9] = a or "-", b or "-", c or "-", n or -1
	s.ne = s.ne + 1
	r.lastEvT = t
	if (i + F) / F >= Session.CHUNK then Session.PackEvents(s) end
end

local function sameAsLast(r, t, k, m, u, v, a, b, c, n)
	local last = r.last
	return last[1] == t and last[2] == k and last[3] == (m or 0) and last[4] == (u or 0) and last[5] == (v or 0)
		and last[6] == (a or "-") and last[7] == (b or "-") and last[8] == (c or "-") and last[9] == (n or -1)
end

local function tenthOf(r, t, lastKey)
	t = floor(t)
	if t < r[lastKey] then t = r[lastKey] end   -- never smaller than the one before (REC-06)
	return t
end

-- A limit event Z with `a`, at most once per kind; stops the events when it is the last one allowed.
local function limit(s, r, t, a)
	if r.z[a] or r.stopped then return end
	r.z[a] = true
	if t > Session.MAX_T then t = Session.MAX_T end
	if t < r.lastEvT then t = r.lastEvT end
	push(s, r, t, "Z", 0, 0, 0, a)
	if s.ne >= Session.LIMITS.events then r.stopped = true end
end

function Session.AddEvent(s, t, k, m, u, v, a, b, c, n)
	local r = liveOf(s)
	if r.stopped or not s.buf then return false end
	t = tenthOf(r, t, "lastEvT")
	if t > Session.MAX_T then
		limit(s, r, Session.MAX_T, "t")
		return false
	end
	if s.ne > 0 and sameAsLast(r, t, k, m, u, v, a, b, c, n) then return false end
	if s.ne >= Session.LIMITS.events - 1 then
		limit(s, r, t, "e")
		r.stopped = true
		return false
	end
	push(s, r, t, k, m, u, v, a, b, c, n)
	return true
end

function Session.AddRow(s, t, m, u, p, code)
	if s.trunc or not s.buf then return false end
	local r = liveOf(s)
	t = tenthOf(r, t, "lastRowT")
	if t > Session.MAX_T then
		s.trunc = Session.MAX_T
		limit(s, r, Session.MAX_T, "t")
		return false
	end
	if s.n >= Session.LIMITS.rows then
		s.trunc = t
		limit(s, r, t, "r")
		return false
	end
	local buf = s.buf
	local i = #buf.t + 1
	buf.t[i], buf.m[i], buf.u[i], buf.p[i], buf.s[i] = t, m, u, p or -1, code
	s.n = s.n + 1
	r.lastRowT = t
	if i >= Session.CHUNK then Session.PackRows(s) end
	return true
end

local function addEntry(s, list, max, zcode, entry, t)
	if #list >= max then
		local r = liveOf(s)
		limit(s, r, tenthOf(r, t or r.lastEvT, "lastEvT"), zcode)
		return nil
	end
	list[#list + 1] = entry
	return #list
end

function Session.AddUnit(s, entry, t)
	local index = addEntry(s, s.units, Session.LIMITS.units, "u", entry, t)
	if index then s.q.v[index], s.q.s[index], s.q.x[index] = 0, 0, 0 end
	return index
end

function Session.AddMob(s, entry, t)
	return addEntry(s, s.mobs, Session.LIMITS.mobs, "m", entry, t)
end

-- The pieces and rows of an open session, for /atw debug.
function Session.Pieces(s)
	if type(s.parts) ~= "table" then return 0 end
	return #(s.parts.t or {}) + #(s.parts.ev or {})
end

---------------------------------------------------------------------------------------------------------------------
-- The code of a read (SPEC-02 §4.2)
---------------------------------------------------------------------------------------------------------------------
-- rec: a record of the scanner (mode, situation, scaledPercent, reason); fresh: not stale (ThreatModel.IsStale).
-- Returns the code, the value of `p` (scaled % x 10 rounded, -1 none) and true when the row carries a number.
function Session.RowCode(rec, fresh)
	if not fresh then return "T", -1, false end
	local mode, situation = rec.mode, rec.situation
	if type(situation) ~= "number" or situation ~= floor(situation) or situation < 0 or situation > 3 then
		situation = nil
	end
	if mode == "values" and type(rec.scaledPercent) == "number" and rec.scaledPercent == rec.scaledPercent then
		local p = floor(rec.scaledPercent * 10 + 0.5)
		if p < 0 then p = 0 elseif p > Session.MAX_N then p = Session.MAX_N end
		return situation ~= nil and DIGIT[situation] or "4", p, true
	end
	if (mode == "values" or mode == "state") and situation ~= nil then return STATE_SITUATION[situation], -1, false end
	return ROW_REASON[rec.reason] or "X", -1, false
end

---------------------------------------------------------------------------------------------------------------------
-- Decoding
---------------------------------------------------------------------------------------------------------------------
local function decodeColumn(str, w, count, out, column)
	if type(str) ~= "string" or #str ~= w * count then return false end
	for i = 1, count do
		local pos = (i - 1) * w + 1
		if column == "s" then
			local ch = str:sub(pos, pos)
			if not Session.ROW_CODES[ch] then return false end
			out[#out + 1] = ch
		elseif column == "p" and str:sub(pos, pos + 1) == "--" then
			out[#out + 1] = -1
		else
			local n = Session.Read(str, pos, w)
			if n == nil then return false end
			out[#out + 1] = n
		end
	end
	return true
end

local function decodeEvents(str, out)
	if type(str) ~= "string" or #str % 12 ~= 0 then return false end
	for pos = 1, #str, 12 do
		local t = Session.Read(str, pos, 3)
		local k = str:sub(pos + 3, pos + 3)
		local m, u, v = Session.Read(str, pos + 4, 1), Session.Read(str, pos + 5, 1), Session.Read(str, pos + 6, 1)
		if t == nil or not Session.EVENT_KINDS[k] or m == nil or u == nil or v == nil then return false end
		local raw = str:sub(pos + 10, pos + 11)
		out[#out + 1] = { t = t, k = k, m = m, u = u, v = v, a = str:sub(pos + 7, pos + 7),
			b = str:sub(pos + 8, pos + 8), c = str:sub(pos + 9, pos + 9),
			n = raw == "--" and -1 or (Session.Read(raw, 1, 2) or -1), raw = raw }
	end
	return true
end

-- The rows and events of `s` (closed: from the columns; open or interrupted: the columns, the pieces and buf):
-- { n, t = {}, m = {}, u = {}, p = {} (-1 none), s = {}, ne, events = { { t, k, m, u, v, a, b, c, n } } }, or nil and
-- why ("rows", "events", "count"). The checks of the deep check of Storage (M4.3) build on it.
function Session.Decode(s)
	if type(s) ~= "table" then return nil, "session" end
	local out = { t = {}, m = {}, u = {}, p = {}, s = {}, events = {} }
	local cols = type(s.cols) == "table" and s.cols or {}
	local parts = type(s.parts) == "table" and s.parts or {}
	local buf = type(s.buf) == "table" and s.buf or {}
	-- how many rows each source holds, from the length of `t`
	local function rowsIn(str) return type(str) == "string" and #str / 3 or -1 end
	local sources = { { cols = cols } }
	for i = 1, #(parts.t or {}) do sources[#sources + 1] = { piece = i } end
	for _, source in ipairs(sources) do
		local count
		if source.cols then count = rowsIn(cols.t) else count = rowsIn(parts.t[source.piece]) end
		if count < 0 or count ~= floor(count) then return nil, "rows" end
		for _, column in ipairs(Session.COLUMNS) do
			local str
			if source.cols then str = cols[column] else str = (parts[column] or {})[source.piece] end
			if not decodeColumn(str, WIDTH[column], count, out[column], column) then return nil, "rows" end
		end
	end
	local waiting = type(buf.t) == "table" and #buf.t or 0
	for _, column in ipairs(Session.COLUMNS) do
		local list = buf[column]
		if waiting > 0 and (type(list) ~= "table" or #list ~= waiting) then return nil, "rows" end
		for i = 1, waiting do out[column][#out[column] + 1] = list[i] end
	end
	if not decodeEvents(s.ev or "", out.events) then return nil, "events" end
	for _, piece in ipairs(parts.ev or {}) do
		if not decodeEvents(piece, out.events) then return nil, "events" end
	end
	local ev = type(buf.ev) == "table" and buf.ev or {}
	if #ev % F ~= 0 then return nil, "events" end
	for i = 1, #ev, F do
		local n = ev[i + 8]
		local raw
		if type(n) == "string" and #n == 2 then raw = n
		elseif type(n) == "number" and n >= 0 then raw = ENC2[n > Session.MAX_N and Session.MAX_N or floor(n)]
		else raw = "--" end
		out.events[#out.events + 1] = { t = ev[i], k = ev[i + 1], m = ev[i + 2], u = ev[i + 3], v = ev[i + 4],
			a = ev[i + 5], b = ev[i + 6], c = ev[i + 7], n = raw == "--" and -1 or (Session.Read(raw, 1, 2) or -1),
			raw = raw }
	end
	out.n, out.ne = #out.t, #out.events
	if out.n ~= s.n or out.ne ~= s.ne then return nil, "count" end
	return out
end

if ns.addon then ns.addon.Session = Session end
