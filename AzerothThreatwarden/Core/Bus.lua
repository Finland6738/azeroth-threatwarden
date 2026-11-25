-- Bus: the internal publish/subscribe of the addon (SPEC-01 §3, ARC-03). Lua 5.1, no game API.
-- Adapted from Azeroth Accord (Core/Bus.lua), same owner, GPL-3.0 (ADR 0012). Changes: the functions are called with a
-- dot (Bus.Emit(event, ...), as Core/Init.lua does); an emit allocates nothing (a listener removed while its event is
-- delivered is marked and the list compacted afterwards, ARC-06), because THREAT_UPDATED is emitted on every tick from
-- M2; an argument that is a secret value is refused (SPEC-01 §3.3); a listener error goes into the error ring of
-- Core/Diagnostics.lua too.
--
-- A listener that raises never stops the others: the error is caught with pcall, kept for /atw debug and never shown to
-- the player (ARC-10). Event arguments never hold a secret value or a player name: threat events pass keys.
--
-- Events (arguments in order; the table is SPEC-01 §3.3):
--   ADDON_READY()                   Core/Init.lua, after Config, Locale and Compat at ADDON_LOADED.
--   CONFIG_LOADED()                 Core/Config.lua (M1.5); the saved data are loaded, migrated and cleaned.
--   CONFIG_CHANGED(path)            Core/Config.lua (M1.5); Config:Set stored a value ("account.settings.theme").
--   SETTINGS_CHANGED(key)           UI/Settings.lua (M1.8); the player changed an option.
--   THEME_CHANGED(themeId)          UI/Theme.lua (M1.6); the theme was applied.
--   CAPABILITY_CHANGED(id, state)   Core/Compat.lua; Compat:SetCapability or a client restriction changed a capability.
--   COMBAT_STARTED(), COMBAT_ENDED() Core/Init.lua, from PLAYER_REGEN_DISABLED / PLAYER_REGEN_ENABLED.
--   WINDOW_SHOWN(shown)             UI/Window.lua (M1.7).
--   TAB_CHANGED(tabId)              UI/Window.lua (M1.7).
--   TARGET_CHANGED, THREAT_SCANNED, THREAT_UPDATED, STATE_CHANGED, THREAT_MODE_CHANGED     Data/ (M2)
--   ALERT_RAISED, COACH_TIP                                                                Data/ (M3)
--   SESSION_STARTED, SESSION_ENDED, SESSIONS_CHANGED                                       Data/ (M4)
local ADDON_NAME, ns = ...
ns = ns or {}
ns.modules = ns.modules or {}

local Bus = {}
ns.Bus, ns.modules.Bus = Bus, Bus

local pcall, type, tostring, select, pairs = pcall, type, tostring, select, pairs

Bus.MAX_ERRORS = 10
Bus.MAX_LENGTH = 160

local listeners = {}   -- event -> array of functions (false: removed while the event was being delivered)
local emitting = {}    -- event -> how many Emit calls of it are running (nested emits)
local dirty = {}       -- event -> true when its list has removed entries to compact
Bus.errors = {}        -- the last MAX_ERRORS: { event = , message = }
Bus.errorCount = 0

local function compact(event)
	local list = listeners[event]
	dirty[event] = nil
	if not list then return end
	local j = 0
	for i = 1, #list do
		local fn = list[i]
		if fn then
			j = j + 1
			list[j] = fn
		end
	end
	for i = #list, j + 1, -1 do list[i] = nil end
	if j == 0 then listeners[event] = nil end
end

-- Subscribes `fn` to `event`; the same function is registered once per event. Returns true when added. A listener
-- added while its event is delivered runs from the next Emit.
function Bus.On(event, fn)
	if type(event) ~= "string" or type(fn) ~= "function" then return false end
	local list = listeners[event]
	if not list then
		list = {}
		listeners[event] = list
	end
	for i = 1, #list do
		if list[i] == fn then return false end
	end
	list[#list + 1] = fn
	return true
end

-- Unsubscribes `fn`, or every listener of `event` when `fn` is nil. Returns true when something was removed. A
-- listener removed while its event is delivered does not run any more, in this Emit either.
function Bus.Off(event, fn)
	local list = listeners[event]
	if not list then return false end
	local removed = false
	for i = 1, #list do
		if list[i] and (fn == nil or list[i] == fn) then
			list[i] = false
			removed = true
			if fn ~= nil then break end
		end
	end
	if removed then
		if emitting[event] then dirty[event] = true else compact(event) end
	end
	return removed
end

local function record(event, message)
	local Diag = ns.Diagnostics
	local text = Diag and Diag.CleanError and Diag.CleanError(message) or tostring(message)
	if #text > Bus.MAX_LENGTH then text = text:sub(1, Bus.MAX_LENGTH - 3) .. "..." end
	Bus.errorCount = Bus.errorCount + 1
	local errors = Bus.errors
	errors[#errors + 1] = { event = event, message = text }
	if #errors > Bus.MAX_ERRORS then table.remove(errors, 1) end
	if Diag and Diag.Record then Diag.Record("Bus " .. tostring(event) .. ": " .. text) end
end

local function hasSecret(...)
	local Compat = ns.Compat
	if not (Compat and Compat.IsSecret) then return false end
	for i = 1, select("#", ...) do
		if Compat.IsSecret((select(i, ...))) then return true end
	end
	return false
end

-- Calls every listener of `event` in subscription order; returns how many ran without an error. Nothing is delivered
-- when an argument is a secret value (it is a bug of the emitter, recorded for /atw debug).
function Bus.Emit(event, ...)
	local list = listeners[event]
	if not list then return 0 end
	if hasSecret(...) then
		record(event, "a secret value was passed as an event argument; the event was not delivered")
		return 0
	end
	emitting[event] = (emitting[event] or 0) + 1
	local ok, n = 0, #list
	for i = 1, n do
		local fn = list[i]
		if fn then
			local success, err = pcall(fn, ...)
			if success then ok = ok + 1 else record(event, err) end
		end
	end
	local depth = emitting[event] - 1
	emitting[event] = depth > 0 and depth or nil
	if depth == 0 and dirty[event] then compact(event) end
	return ok
end

function Bus.ListenerCount(event)
	local list = listeners[event]
	if not list then return 0 end
	local n = 0
	for i = 1, #list do
		if list[i] then n = n + 1 end
	end
	return n
end

-- The /atw debug lines: the events with listeners and the last listener errors.
function Bus.DebugLines()
	local lines, events = {}, 0
	for event in pairs(listeners) do
		local n = Bus.ListenerCount(event)
		if n > 0 then
			events = events + 1
			lines[#lines + 1] = ("%s: %d listener(s)"):format(event, n)
		end
	end
	table.sort(lines)
	table.insert(lines, 1, ("events with listeners: %d, listener errors: %d"):format(events, Bus.errorCount))
	for _, e in ipairs(Bus.errors) do lines[#lines + 1] = ("error in %s: %s"):format(e.event, e.message) end
	return lines
end
