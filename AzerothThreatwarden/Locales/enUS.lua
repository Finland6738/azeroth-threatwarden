-- English strings: the base language and the fallback (ADR 0009). Every visible string is a key of this table.
-- One key per line, KEY = "text", so that tools/check_addon.py reads them.
local ADDON_NAME, ns = ...

ns.Locale.Register("enUS", {
	ADDON_TITLE = "Azeroth Threatwarden",

	-- Addon Compartment
	COMPARTMENT_HINT = "The Threatwarden window arrives with the next development steps.",
	COMING_SOON = "This part is coming soon.",

	-- Commands (the full set arrives with the window, M1.7)
	COMMANDS_SOON = "More commands arrive with the next development steps. Type /atw debug for the diagnostic report.",

	-- /atw debug: the copy box (the report itself stays in English, ADR 0009)
	DIAG_TITLE = "Diagnostic report",
	DIAG_HINT = "The text is selected: press Ctrl+C to copy it, then paste it into your bug report. It has no player names.",
	DIAG_SELECT = "Select all",
	DIAG_CLOSE = "Close",
	DIAG_SIZE = "%d lines, %d characters",
})
