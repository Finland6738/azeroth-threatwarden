-- Italian strings (ADR 0009): exactly the keys of enUS.lua (tools/check_addon.py refuses anything else).
local ADDON_NAME, ns = ...

ns.Locale.Register("itIT", {
	ADDON_TITLE = "Azeroth Threatwarden",

	-- Addon Compartment
	COMPARTMENT_HINT = "La finestra di Threatwarden arriva con i prossimi passi di sviluppo.",
	COMING_SOON = "Questa parte arriva presto.",

	-- Comandi (l'insieme completo arriva con la finestra, M1.7)
	COMMANDS_SOON = "Altri comandi arrivano con i prossimi passi di sviluppo. Scrivi /atw debug per il rapporto diagnostico.",

	STATE_SAFE = "SICURO",
	STATE_WARNING = "ATTENZIONE",
	STATE_DANGER = "PERICOLO",
	STATE_UNKNOWN = "SCONOSCIUTO",

	-- /atw debug: la finestra da cui copiare (il rapporto resta in inglese, ADR 0009)
	DIAG_TITLE = "Rapporto diagnostico",
	DIAG_HINT = "Il testo è già selezionato: premi Ctrl+C per copiarlo, poi incollalo nella segnalazione. Non contiene nomi di giocatori.",
	DIAG_SELECT = "Seleziona tutto",
	DIAG_CLOSE = "Chiudi",
	DIAG_SIZE = "%d righe, %d caratteri",
})
