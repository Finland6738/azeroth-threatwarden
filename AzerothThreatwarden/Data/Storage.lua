-- Storage: the recorded sessions of `AzerothThreatwardenDB.sessions` after the load of Config (SPEC-05 §2, §6;
-- SPEC-02 §3.7, §4.5; STO-01-STO-03, REC-04; ADR 0005, 0016). Lua 5.1, no game API but the player's combat flag
-- through Core/Compat.lua. Threatwarden's own.
--
-- At CONFIG_LOADED, with the `recording` switch on, every entry of `sessions` goes through the fast check of §2.2 (the
-- string functions of the client, nothing decoded): a session `open` or with pieces left (a /reload or a logout during
-- a recording) is completed with Session.Join, recounted and checked again as a closed one; `ended` of an interrupted
-- session with the X stamp comes from ENTERING_WORLD (reload, login, else unknown); an interrupted session without rows
-- goes; a duplicate `id` gets a suffix ("-b", "-c"...); a damaged entry goes out of `sessions` and into `corrupt` on its
-- own with Config:SetAside (its header only, never the columns), the other sessions and the settings untouched. Then
-- pruning (§2.4) and SESSIONS_CHANGED. The deep check (time not decreasing, indexes inside `units` and `mobs`, valid
-- codes) runs at Storage.Decode: a session that fails it is set aside as soon as the player is out of combat.
--
-- Pruning after every close (Storage.Closed), at load and when maxSessions or maxKB change: while there are more
-- sessions than settings.recording.maxSessions or their estimated size is over settings.recording.maxKB, the oldest
-- closed session goes (by `started`, then by position). The open session counts but never goes. The size is
-- Config.EstimateSize of each session (an estimate, ADR 0003), kept per closed session and made again at close and load.
--
-- Read-only account data (SPEC-02 §3.4, §2.6): nothing is completed, set aside, pruned or deleted; the sessions that
-- fail the fast check are hidden and counted, never taken out. Deleting happens only on the player's action (Delete,
-- DeleteAll), never at load. While the switch is off at CONFIG_LOADED nothing is listened to, checked or written.
--
--   Storage.List()          the headers, newest first, never the columns (with the main enemy of `sum` and the
--                           player's role, for the comparison of SPEC-06 §2)
--   Storage.Get(id)         the session (the live table: change it only through Storage), nil when unknown or hidden
--   Storage.Usage()         { count, bytes, maxSessions, maxKB, pruned, damaged, dropped }
--   Storage.Decode(id)      rows and events (Session.Decode) after the deep check, or nil and "unknown" / "damaged";
--                           one decoded session kept in memory at a time
--   Storage.Delete(id)      true, or false and "off", "read-only", "unknown", "recording" (the open session)
--   Storage.DeleteAll()     true and how many went (the open session stays), or false and "off" / "read-only"
--   Storage.Add(s)          the recorder at the opening: the session appended, SESSIONS_CHANGED
--   Storage.Closed(s, kept) the recorder at the close: a dropped one taken out, the size, pruning, SESSIONS_CHANGED
--   Storage.Prune()         how many sessions went
local ADDON_NAME, ns = ...
ns = ns or {}
ns.modules = ns.modules or {}

local Storage = {}
ns.Storage, ns.modules.Storage = Storage, Storage

local Config, Session, Compat = ns.Config, ns.Session, ns.Compat
local type, pairs, ipairs, pcall, tostring, floor, sort = type, pairs, ipairs, pcall, tostring, math.floor, table.sort

-- SPEC-05 §1.7: one table, the one of Data/Session.lua (the recorder needs it before Storage).
Storage.LIMITS = Session.LIMITS
Storage.MAX_ID = 40
Storage.STATES = { open = true, complete = true, interrupted = true }
Storage.PATH = "account.sessions"
-- The header copied into `corrupt` for a damaged session: plain values only, never the columns, `units` or `mobs`.
Storage.HEADER = { "id", "started", "dur", "fight", "state", "ended", "stamp", "after", "trunc", "group", "zone", "inst",
	"diff", "n", "ne" }
local PREFIX = "account.settings.recording."
local LIMIT_PATHS = { [PREFIX .. "maxSessions"] = true, [PREFIX .. "maxKB"] = true }

Storage.loaded = false        -- the last CONFIG_LOADED ran the checks (switch on)
Storage.stats = { completed = 0, renamed = 0, dropped = 0, pruned = 0, damaged = 0, setAside = 0, hidden = 0,
	deleted = 0 }

local size = setmetatable({}, { __mode = "k" })     -- closed session -> estimated bytes
local hidden = setmetatable({}, { __mode = "k" })   -- session -> true: damaged, not shown (read-only, or waiting)
local waitingEnded = {}       -- sessions completed at this load whose `ended` comes from ENTERING_WORLD
local waitingSum = {}         -- sessions without `sum`: Report.Summary out of combat (M4.4)
local damagedLater = {}       -- sessions that failed the deep check in combat: set aside at COMBAT_ENDED
local decoded = { s = nil, out = nil }   -- the last decoded session (one at a time in memory)
local listening = false

local function emit(event, ...)
	if ns.Bus then ns.Bus.Emit(event, ...) end
end

local function on()
	local F = ns.Features
	return F ~= nil and F.On("recording")
end

local function sessions()
	local list = Config:Get(Storage.PATH)
	if type(list) == "table" then return list end
	return nil
end

local function readOnly() return Config:IsReadOnly("account") end

local function current() return ns.Recorder and ns.Recorder.current or nil end

local function inCombat()
	if ns.addon and ns.addon.inCombat then return true end
	return Compat.Unit.AffectingCombat("player") == true
end

local function setting(key)
	local value = Config:Get(PREFIX .. key)
	if type(value) ~= "number" or value ~= value then value = Config.RECORDING_DEFAULTS[key] end
	return value
end

local function clear(list)
	for i = #list, 1, -1 do list[i] = nil end
end

local function forget(s)
	size[s], hidden[s], damagedLater[s] = nil, nil, nil
	if decoded.s == s then decoded.s, decoded.out = nil, nil end
end

---------------------------------------------------------------------------------------------------------------------
-- The fast check (SPEC-05 §2.2 point 1): types, ranges and the lengths and characters of the strings, nothing decoded
---------------------------------------------------------------------------------------------------------------------
local BAD = "[^0-9A-Za-z%-]"
local WIDTH, COLUMNS, F = Session.WIDTH, Session.COLUMNS, Session.EVENT_FIELDS

local function isInt(v, lo, hi)
	return type(v) == "number" and v == v and v == floor(v) and v >= lo and v <= hi
end

local function isFinite(v)
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function goodString(str, len)
	return type(str) == "string" and (len == nil or #str == len) and not str:find(BAD)
end

local function code(v) return type(v) == "string" and #v == 1 and not v:find(BAD) end

-- An array of tables, at most `max`, with no other key.
local function entries(list, max)
	if type(list) ~= "table" then return false end
	local count = #list
	if count > max then return false end
	local seen = 0
	for k, v in pairs(list) do
		if not isInt(k, 1, count) or type(v) ~= "table" then return false end
		seen = seen + 1
	end
	return seen == count                      -- no hole
end

local function strings(list)
	if type(list) ~= "table" then return false end
	for k, v in pairs(list) do
		if type(k) ~= "number" or not goodString(v) then return false end
	end
	return true
end

-- The columns and `ev` of a closed session: the lengths of DAT-32, the alphabet only.
local function closedForm(s)
	local cols = s.cols
	if type(cols) ~= "table" then return "cols" end
	for _, column in ipairs(COLUMNS) do
		if not goodString(cols[column], WIDTH[column] * s.n) then return "cols" end
	end
	if not goodString(s.ev, Session.EVENT_WIDTH * s.ne) then return "ev" end
	return nil
end

-- The pieces and `buf` of a session not completed yet (SPEC-02 §4.4): enough for Session.Join to encode them.
local function openForm(s)
	local parts, buf, cols = s.parts, s.buf, s.cols
	if type(parts) ~= "table" or type(buf) ~= "table" then return "parts" end
	if cols ~= nil then
		if type(cols) ~= "table" then return "cols" end
		for _, column in ipairs(COLUMNS) do
			if cols[column] ~= nil and not goodString(cols[column]) then return "cols" end
		end
	end
	if s.ev ~= nil and not goodString(s.ev) then return "ev" end
	for _, column in ipairs(COLUMNS) do
		if parts[column] ~= nil and not strings(parts[column]) then return "parts" end
	end
	if parts.ev ~= nil and not strings(parts.ev) then return "parts" end
	local waiting = type(buf.t) == "table" and #buf.t or 0
	if waiting >= Session.CHUNK then return "buf" end
	local nu, nm = #s.units, #s.mobs
	for _, column in ipairs(COLUMNS) do
		local list = buf[column]
		if waiting > 0 and (type(list) ~= "table" or #list ~= waiting) then return "buf" end
	end
	for i = 1, waiting do
		if not isInt(buf.t[i], 0, Session.MAX_T) or not isInt(buf.m[i], 1, nm) or not isInt(buf.u[i], 1, nu)
			or not isFinite(buf.p[i]) or not Session.ROW_CODES[buf.s[i]] then
			return "buf"
		end
	end
	local ev = buf.ev
	if ev ~= nil then
		if type(ev) ~= "table" or #ev % F ~= 0 or #ev >= Session.CHUNK * F then return "buf" end
		for i = 1, #ev, F do
			local n = ev[i + 8]
			if not isInt(ev[i], 0, Session.MAX_T) or not Session.EVENT_KINDS[ev[i + 1]]
				or not isInt(ev[i + 2], 0, 61) or not isInt(ev[i + 3], 0, 61) or not isInt(ev[i + 4], 0, 61)
				or not code(ev[i + 5]) or not code(ev[i + 6]) or not code(ev[i + 7])
				or not (isFinite(n) or goodString(n, 2)) then
				return "buf"
			end
		end
	end
	return nil
end

-- nil when `s` passes the fast check, else the first field that fails. `pieces` true: it still has to be completed.
function Storage.Check(s)
	if type(s) ~= "table" then return "type" end
	if type(s.id) ~= "string" or #s.id < 1 or #s.id > Storage.MAX_ID then return "id" end
	if not isFinite(s.started) then return "started" end
	if not Storage.STATES[s.state] then return "state" end
	local L = Storage.LIMITS
	if not entries(s.units, L.units) then return "units" end
	if not entries(s.mobs, L.mobs) then return "mobs" end
	if not isInt(s.n, 0, L.rows) then return "n" end
	if not isInt(s.ne, 0, L.events) then return "ne" end
	if s.parts ~= nil or s.buf ~= nil then return openForm(s), true end
	return closedForm(s), s.state == "open"
end

---------------------------------------------------------------------------------------------------------------------
-- The deep check (SPEC-05 §2.2, at decode): time not decreasing, indexes inside `units` and `mobs`, valid codes
---------------------------------------------------------------------------------------------------------------------
local NUMBERED, ROW_CODES, KINDS = Session.NUMBERED, Session.ROW_CODES, Session.EVENT_KINDS

local function deepCheck(s, out)
	local nu, nm = #s.units, #s.mobs
	local last = 0
	for i = 1, out.n do
		local t, m, u, p, c = out.t[i], out.m[i], out.u[i], out.p[i], out.s[i]
		if not isInt(t, last, Session.MAX_T) then return "time" end
		last = t
		if not isInt(m, 1, nm) or not isInt(u, 1, nu) then return "index" end
		if not ROW_CODES[c] then return "code" end
		if NUMBERED[c] then
			if not isInt(p, 0, Session.MAX_N) then return "value" end
		elseif p ~= -1 then
			return "value"                   -- DAT-31: an unknown read is a code, never a number
		end
	end
	last = 0
	for _, e in ipairs(out.events) do
		if not isInt(e.t, last, Session.MAX_T) then return "time" end
		last = e.t
		if not KINDS[e.k] then return "code" end
		if not isInt(e.m, 0, nm) or not isInt(e.u, 0, nu) or not isInt(e.v, 0, nu) then return "index" end
	end
	return nil
end

---------------------------------------------------------------------------------------------------------------------
-- Damaged sessions set aside (SPEC-05 §2.2 point 4, STO-01)
---------------------------------------------------------------------------------------------------------------------
local function header(s, why)
	local out = { found = type(s), why = why }
	if type(s) ~= "table" then return out end
	for _, key in ipairs(Storage.HEADER) do
		local v = s[key]
		local t = type(v)
		if t == "string" or t == "boolean" or (t == "number" and isFinite(v)) then out[key] = v end
	end
	return out
end

local function setAside(s, why)
	Config:SetAside(Storage.PATH, header(s, why), "session")
	Config.AddIssue("account.sessions: one recording was damaged and set aside")
	Storage.stats.damaged = Storage.stats.damaged + 1
	Storage.stats.setAside = Storage.stats.setAside + 1
end

-- A session taken out of `sessions` (same table, the others in their order).
local function remove(list, s)
	for i = #list, 1, -1 do
		if list[i] == s then
			table.remove(list, i)
			forget(s)
			return true
		end
	end
	return false
end

-- A session that failed the deep check: out of `sessions` and into `corrupt` now, or at COMBAT_ENDED; hidden while it
-- waits, and only hidden while the data is read-only.
local function damagedAtDecode(s, why)
	if s == current() then return end
	if hidden[s] then return end
	hidden[s] = true
	if readOnly() then
		Storage.stats.damaged, Storage.stats.hidden = Storage.stats.damaged + 1, Storage.stats.hidden + 1
		return
	end
	if inCombat() then
		damagedLater[s] = why or "deep"
		return
	end
	local list = sessions()
	if list and remove(list, s) then
		setAside(s, why or "deep")
		emit("SESSIONS_CHANGED")
	end
end

local function setAsideLater()
	local list = sessions()
	if not list or readOnly() then return end
	local changed = false
	for s, why in pairs(damagedLater) do
		damagedLater[s] = nil
		if remove(list, s) then
			setAside(s, why)
			changed = true
		end
	end
	if changed then emit("SESSIONS_CHANGED") end
end

---------------------------------------------------------------------------------------------------------------------
-- Sizes, the summary and pruning (SPEC-05 §2.4, STO-02)
---------------------------------------------------------------------------------------------------------------------
local function sizeOf(s)
	if s == current() then return Config.EstimateSize(s) end   -- the open session grows: estimated each time
	local bytes = size[s]
	if not bytes then
		bytes = Config.EstimateSize(s)
		size[s] = bytes
	end
	return bytes
end

local function total(list)
	local bytes = 0
	for _, s in ipairs(list) do
		if not hidden[s] then bytes = bytes + sizeOf(s) end
	end
	return bytes
end

-- `sum` for the list (SPEC-05 §3.4) by Data/Report.lua (M4.4), out of combat; until it exists `sum` stays nil.
local function summarize()
	if #waitingSum == 0 or readOnly() or inCombat() then return end
	local Report = ns.Report
	if Report and type(Report.Summary) == "function" then
		for _, s in ipairs(waitingSum) do
			if s.sum == nil and not hidden[s] then
				local ok, sum = pcall(Report.Summary, s)
				if ok and type(sum) == "table" then
					s.sum = sum
					size[s] = nil   -- the summary is part of what is saved: estimated again
				end
			end
		end
	end
	clear(waitingSum)
end

local function needsSum(s)
	if s.sum == nil and s.state ~= "open" then waitingSum[#waitingSum + 1] = s end
end

function Storage.Prune()
	if not on() or readOnly() then return 0 end
	local list = sessions()
	if not list then return 0 end
	local maxSessions, maxBytes = setting("maxSessions"), setting("maxKB") * 1024
	local open = current()
	local bytes = total(list)
	local removed = 0
	while #list > maxSessions or bytes > maxBytes do
		local pick
		for i, s in ipairs(list) do
			if s ~= open and (pick == nil or s.started < list[pick].started) then pick = i end
		end
		if not pick then break end
		local s = table.remove(list, pick)
		bytes = bytes - (hidden[s] and 0 or sizeOf(s))
		forget(s)
		removed = removed + 1
	end
	Storage.stats.pruned = Storage.stats.pruned + removed
	return removed
end

---------------------------------------------------------------------------------------------------------------------
-- The load (SPEC-05 §2.2)
---------------------------------------------------------------------------------------------------------------------
-- The last t written (rows and events) of a closed session: the end of an interrupted one (SPEC-02 §4.1).
local function lastT(s)
	local last = 0
	if s.n > 0 then last = Session.Read(s.cols.t, (s.n - 1) * 3 + 1, 3) or 0 end
	if s.ne > 0 then
		local t = Session.Read(s.ev, (s.ne - 1) * 12 + 1, 3) or 0
		if t > last then last = t end
	end
	return last
end

-- Joins the pieces of a session saved during a recording, recounts it and checks it again as a closed one.
local function complete(s)
	local ok = pcall(Session.Join, s)
	if not ok or type(s.cols) ~= "table" or type(s.cols.t) ~= "string" or type(s.ev) ~= "string" then
		return "join"
	end
	local n, ne = #s.cols.t / 3, #s.ev / 12
	if n ~= floor(n) or ne ~= floor(ne) or n > Storage.LIMITS.rows or ne > Storage.LIMITS.events then return "count" end
	s.n, s.ne = n, ne
	return closedForm(s)
end

local function uniqueId(taken, id)
	if not taken[id] then return id end
	for i = 2, 26 do
		local candidate = id .. "-" .. string.char(96 + i)
		if not taken[candidate] then return candidate end
	end
	local i = 27
	while taken[id .. "-" .. i] do i = i + 1 end
	return id .. "-" .. i
end

-- The integer keys of `sessions`, in order (a hole never hides the entries after it).
local function positions(list)
	local keys = {}
	for k in pairs(list) do
		if isInt(k, 1, math.huge) then keys[#keys + 1] = k end
	end
	sort(keys)
	return keys
end

local function loadReadOnly(list)
	for _, k in ipairs(positions(list)) do
		local s = list[k]
		if Storage.Check(s) ~= nil then
			if type(s) == "table" then hidden[s] = true end
			Storage.stats.damaged, Storage.stats.hidden = Storage.stats.damaged + 1, Storage.stats.hidden + 1
			Config.AddIssue("account.sessions: one recording is damaged and hidden (read-only)")
		end
	end
end

local function loadWritable(list)
	local open = current()
	local kept, taken = {}, {}
	local st = Storage.stats
	for _, k in ipairs(positions(list)) do
		local s = list[k]
		local keep = true
		if s ~= open then
			local why, pieces = Storage.Check(s)
			if why == nil and pieces then
				why = complete(s)
				if why == nil then
					st.completed = st.completed + 1
					if s.state ~= "complete" then
						s.state = "interrupted"
						if s.stamp == true then waitingEnded[#waitingEnded + 1] = s end
						s.ended = "unknown"
					end
				end
			end
			if why ~= nil then
				setAside(s, why)
				keep = false
			elseif s.state == "interrupted" then
				if s.ended == nil then s.ended = "unknown" end
				local last = lastT(s)
				if type(s.dur) ~= "number" or s.dur < last then s.dur = last end
				if s.n < 1 then                        -- REC-04: an interrupted session is kept with one row
					keep = false
					st.dropped = st.dropped + 1
				end
			end
		end
		if keep and type(s) == "table" and type(s.id) == "string" then
			if taken[s.id] and s ~= open then
				s.id = uniqueId(taken, s.id)
				st.renamed = st.renamed + 1
			end
			taken[s.id] = true
			kept[#kept + 1] = s
			if s ~= open then
				size[s] = Config.EstimateSize(s)
				needsSum(s)
			end
		end
	end
	for _, k in ipairs(positions(list)) do list[k] = nil end
	for i, s in ipairs(kept) do list[i] = s end
end

local onConfigChanged, onEnteringWorld, onCombatEnded

local function listen()
	if listening or not ns.Bus then return end
	listening = true
	ns.Bus.On("CONFIG_CHANGED", onConfigChanged)
	ns.Bus.On("ENTERING_WORLD", onEnteringWorld)
	ns.Bus.On("COMBAT_ENDED", onCombatEnded)
end

-- CONFIG_LOADED: the checks of §2.2, then pruning and SESSIONS_CHANGED. Safe to run again (an open session is kept).
function Storage.Load()
	Storage.loaded = false
	if not on() then return false end
	local list = sessions()
	if not list then return false end
	for key in pairs(Storage.stats) do Storage.stats[key] = 0 end
	for s in pairs(size) do size[s] = nil end
	for s in pairs(hidden) do hidden[s] = nil end
	for s in pairs(damagedLater) do damagedLater[s] = nil end
	decoded.s, decoded.out = nil, nil
	clear(waitingEnded)
	clear(waitingSum)
	listen()
	if readOnly() then
		loadReadOnly(list)
	else
		loadWritable(list)
		Storage.Prune()
		summarize()
	end
	Storage.loaded = true
	emit("SESSIONS_CHANGED")
	return true
end

---------------------------------------------------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------------------------------------------------
-- The first PLAYER_ENTERING_WORLD after the load says why the stamped sessions were interrupted (SPEC-05 §1.6).
function onEnteringWorld(isInitialLogin, isReloadingUi)
	if #waitingEnded == 0 then return end
	if not readOnly() then
		local ended = (isReloadingUi == true and "reload") or (isInitialLogin == true and "login") or "unknown"
		for _, s in ipairs(waitingEnded) do
			if s.state == "interrupted" then s.ended = ended end
		end
	end
	clear(waitingEnded)
end

function onConfigChanged(path)
	if not LIMIT_PATHS[path] or not Storage.loaded then return end
	if Storage.Prune() > 0 then emit("SESSIONS_CHANGED") end
end

function onCombatEnded()
	if not Storage.loaded then return end
	setAsideLater()
	summarize()
end

---------------------------------------------------------------------------------------------------------------------
-- The recorder's side (SPEC-05 §2.7)
---------------------------------------------------------------------------------------------------------------------
-- The opening: the session appended to `sessions` at once (a /reload saves it), SESSIONS_CHANGED.
function Storage.Add(s)
	local list = sessions()
	if not list or readOnly() or type(s) ~= "table" then return false end
	list[#list + 1] = s
	emit("SESSIONS_CHANGED")
	return true
end

-- The close: `kept` false takes a dropped session out; else its size is estimated again; then pruning and
-- SESSIONS_CHANGED.
function Storage.Closed(s, kept)
	local list = sessions()
	if not list or type(s) ~= "table" then return false end
	if not kept then
		if remove(list, s) then Storage.stats.dropped = Storage.stats.dropped + 1 end
	else
		size[s] = Config.EstimateSize(s)
		if decoded.s == s then decoded.s, decoded.out = nil, nil end
		needsSum(s)
		summarize()
	end
	Storage.Prune()
	emit("SESSIONS_CHANGED")
	return true
end

---------------------------------------------------------------------------------------------------------------------
-- Reading (SPEC-05 §2.7)
---------------------------------------------------------------------------------------------------------------------
local function visible()
	local out = {}
	if not Storage.loaded then return out end
	local list = sessions()
	if not list then return out end
	for _, s in ipairs(list) do
		if type(s) == "table" and not hidden[s] then out[#out + 1] = s end
	end
	return out
end

local function find(id)
	if type(id) ~= "string" then return nil end
	for _, s in ipairs(visible()) do
		if s.id == id then return s end
	end
	return nil
end

function Storage.Get(id) return find(id) end

-- The headers, newest first (by `started`, then by position): plain values, `sum` and `rec`, never the columns.
function Storage.List()
	local list, out = visible(), {}
	local open = current()
	for i, s in ipairs(list) do
		local h = { position = i, units = #s.units, mobs = #s.mobs, open = s == open or nil,
			bytes = sizeOf(s), sum = s.sum, rec = s.rec }
		for _, key in ipairs(Storage.HEADER) do h[key] = s[key] end
		-- the main enemy of `sum` and the player's recorded role, for the comparison (SPEC-06 §2): nothing decoded
		local mob = type(s.sum) == "table" and s.mobs[s.sum.mob or 0]
		if type(mob) == "table" then h.enemy = { name = mob.name, class = mob.class, npc = mob.npc } end
		for _, u in ipairs(s.units) do
			if type(u) == "table" and u.me then h.role = u.role break end
		end
		out[#out + 1] = h
	end
	sort(out, function(a, b)
		if a.started ~= b.started then return a.started > b.started end
		return a.position > b.position
	end)
	return out
end

function Storage.Usage()
	local list = visible()
	local st = Storage.stats
	return { count = #list, bytes = total(list), maxSessions = setting("maxSessions"), maxKB = setting("maxKB"),
		pruned = st.pruned, damaged = st.damaged, dropped = st.dropped }
end

function Storage.Decode(id)
	local s = find(id)
	if not s then return nil, "unknown" end
	if decoded.s == s then return decoded.out end
	local out, why = Session.Decode(s)
	if out then why = deepCheck(s, out) end
	if not out or why then
		damagedAtDecode(s, why or "decode")
		return nil, "damaged"
	end
	if s ~= current() then decoded.s, decoded.out = s, out end
	return out
end

---------------------------------------------------------------------------------------------------------------------
-- Deleting (SPEC-05 §2.5, STO-03): only on the player's action
---------------------------------------------------------------------------------------------------------------------
function Storage.Delete(id)
	if not on() or not Storage.loaded then return false, "off" end
	if readOnly() then return false, "read-only" end
	local s = find(id)
	if not s then return false, "unknown" end
	if s == current() then return false, "recording" end
	remove(sessions(), s)
	Storage.stats.deleted = Storage.stats.deleted + 1
	emit("SESSIONS_CHANGED")
	return true
end

function Storage.DeleteAll()
	if not on() or not Storage.loaded then return false, "off" end
	if readOnly() then return false, "read-only" end
	local list = sessions()
	local open = current()
	local count = 0
	for i = #list, 1, -1 do
		local s = list[i]
		if s ~= open then
			table.remove(list, i)
			forget(s)
			count = count + 1
		end
	end
	Storage.stats.deleted = Storage.stats.deleted + count
	if count > 0 then emit("SESSIONS_CHANGED") end
	return true, count
end

---------------------------------------------------------------------------------------------------------------------
-- /atw debug, the storage part of the section Recording (SPEC-05 §6): counts only, never a name
---------------------------------------------------------------------------------------------------------------------
function Storage.DebugLines()
	if not Storage.loaded then return { "storage: not loaded (switch off or no sessions table)" } end
	local u = Storage.Usage()
	local st = Storage.stats
	return {
		("sessions kept: %d, about %.1f KB (estimated) of at most %d KB and %d sessions%s"):format(u.count,
			u.bytes / 1024, u.maxKB, u.maxSessions, readOnly() and "; READ-ONLY: nothing completed, pruned or deleted"
			or ""),
		("storage this load: %d completed, %d renamed, %d dropped, %d pruned, %d damaged (%d set aside, %d hidden), %d deleted"):format(
			st.completed, st.renamed, st.dropped, st.pruned, st.damaged, st.setAside, st.hidden, st.deleted),
	}
end

-- The checks wait for CONFIG_LOADED (ADDON_LOADED); the other listeners are registered then, with the switch on.
if ns.Bus then ns.Bus.On("CONFIG_LOADED", function() Storage.Load() end) end

if ns.addon then ns.addon.Storage = Storage end
