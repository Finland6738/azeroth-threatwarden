-- English strings: the base language and the fallback (ADR 0009). Every visible string is a key of this table.
-- One key per line, KEY = "text", so that tools/check_addon.py reads them.
local ADDON_NAME, ns = ...

ns.Locale.Register("enUS", {
	ADDON_TITLE = "Azeroth Threatwarden",

	-- Addon Compartment
	COMPARTMENT_HINT = "The Threatwarden window arrives with the next development steps.",
	COMING_SOON = "This part is coming soon.",
})
