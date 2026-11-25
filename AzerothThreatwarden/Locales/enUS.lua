-- English strings: the base language and the fallback (ADR 0009). Every visible string is a key of this table.
-- One key per line, KEY = "text", so that tools/check_addon.py reads them.
local ADDON_NAME, ns = ...

ns.Locale.Register("enUS", {
	ADDON_TITLE = "Azeroth Threatwarden",

	-- The window (SPEC-03 §4)
	WINDOW_TITLE = "AZEROTH THREATWARDEN",
	WINDOW_TITLE_COMPACT = "THREATWARDEN",
	WINDOW_CLOSE = "Close",
	WINDOW_LOCK = "Lock the window",
	WINDOW_UNLOCK = "Unlock the window",
	WINDOW_RESIZE = "Drag to resize",
	TAB_MONITOR = "Monitor",
	TAB_REPORTS = "Reports",
	TAB_SETTINGS = "Settings",
	MONITOR_COMING = "Threat monitoring arrives in v0.2.0",
	SETTINGS_COMING = "Settings arrive with the next development steps.",
	ABOUT_COMING = "The Info page and the credits arrive with the next development steps.",

	-- The state of the threat monitor, in the title bar and in the tooltips
	MODULE_OFF = "Off",
	MODULE_IDLE = "Idle",
	MODULE_LIVE = "Live",
	MODULE_STATE = "State only",
	MODULE_UNAVAILABLE = "Unavailable",
	MODULE_UNSUPPORTED = "Unsupported client",
	MODULE_TIP_OFF = "Threat monitoring is not part of this version yet.",
	MODULE_TIP_IDLE = "No fight with a monitored enemy.",
	MODULE_TIP_LIVE = "The threat values are being read from the game.",
	MODULE_TIP_STATE = "The game gives only the threat state, not the values.",
	MODULE_TIP_UNAVAILABLE = "The game does not give threat data here.",
	MODULE_TIP_UNSUPPORTED = "This client is not WoW Forever: no numbers are shown.",

	-- Minimap button and Addon Compartment
	TOOLTIP_VERSION = "Version %s",
	TOOLTIP_DEV = "Development build",
	TOOLTIP_STATE = "Threat monitor: %s",
	TOOLTIP_LEFT = "Left-click: show or hide",
	TOOLTIP_RIGHT = "Right-click: settings",
	COMING_SOON = "This part is coming soon.",

	-- Commands (/threatwarden, /atw)
	CMD_LOCKED = "Window locked.",
	CMD_UNLOCKED = "Window unlocked.",
	CMD_RESET = "Window position, size and scale reset.",
	CMD_READ_ONLY = "Nothing was changed: your saved data is read-only (see /atw debug).",
	CMD_UNKNOWN = "Unknown command: %s. Type /atw help.",
	CMD_LATER = "This arrives in %s.",
	HELP_HEADER = "Commands (/atw or /threatwarden):",
	HELP_TOGGLE = "show or hide the window",
	HELP_SHOW = "show the window",
	HELP_HIDE = "hide the window",
	HELP_LOCK = "lock the window",
	HELP_UNLOCK = "unlock the window",
	HELP_RESET = "reset the window's position, size and scale",
	HELP_SETTINGS = "open the settings",
	HELP_ABOUT = "open the Info page",
	HELP_DEBUG = "open the diagnostic report",
	HELP_HELP = "list the commands",

	-- The four states of the threat: always shown with their icon (ui-style 4.2)
	STATE_SAFE = "SAFE",
	STATE_WARNING = "WARNING",
	STATE_DANGER = "DANGER",
	STATE_UNKNOWN = "UNKNOWN",

	-- /atw debug: the copy box (the report itself stays in English, ADR 0009)
	DIAG_TITLE = "Diagnostic report",
	DIAG_HINT = "The text is selected: press Ctrl+C to copy it, then paste it into your bug report. It has no player names.",
	DIAG_SELECT = "Select all",
	DIAG_CLOSE = "Close",
	DIAG_SIZE = "%d lines, %d characters",
})
