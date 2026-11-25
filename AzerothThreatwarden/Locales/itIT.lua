-- Italian strings (ADR 0009): exactly the keys of enUS.lua (tools/check_addon.py refuses anything else).
local ADDON_NAME, ns = ...

ns.Locale.Register("itIT", {
	ADDON_TITLE = "Azeroth Threatwarden",

	-- La finestra (SPEC-03 §4)
	WINDOW_TITLE = "AZEROTH THREATWARDEN",
	WINDOW_TITLE_COMPACT = "THREATWARDEN",
	WINDOW_CLOSE = "Chiudi",
	WINDOW_LOCK = "Blocca la finestra",
	WINDOW_UNLOCK = "Sblocca la finestra",
	WINDOW_RESIZE = "Trascina per ridimensionare",
	TAB_MONITOR = "Monitor",
	TAB_REPORTS = "Report",
	TAB_SETTINGS = "Impostazioni",
	MONITOR_COMING = "Il monitor della threat arriva nella v0.2.0",
	SETTINGS_COMING = "Le impostazioni arrivano con i prossimi passi di sviluppo.",
	ABOUT_COMING = "La pagina Info e i crediti arrivano con i prossimi passi di sviluppo.",

	-- Lo stato del monitor, nella barra del titolo e nei tooltip
	MODULE_OFF = "Spento",
	MODULE_IDLE = "In attesa",
	MODULE_LIVE = "In diretta",
	MODULE_STATE = "Solo stato",
	MODULE_UNAVAILABLE = "Non disponibile",
	MODULE_UNSUPPORTED = "Client non supportato",
	MODULE_TIP_OFF = "Il monitor della threat non fa ancora parte di questa versione.",
	MODULE_TIP_IDLE = "Nessun combattimento con un nemico monitorato.",
	MODULE_TIP_LIVE = "I valori di threat vengono letti dal gioco.",
	MODULE_TIP_STATE = "Il gioco fornisce solo lo stato della threat, non i valori.",
	MODULE_TIP_UNAVAILABLE = "Qui il gioco non fornisce dati di threat.",
	MODULE_TIP_UNSUPPORTED = "Questo client non è WoW Forever: nessun numero viene mostrato.",

	-- Pulsante della minimappa e Addon Compartment
	TOOLTIP_VERSION = "Versione %s",
	TOOLTIP_DEV = "Versione di sviluppo",
	TOOLTIP_STATE = "Monitor della threat: %s",
	TOOLTIP_LEFT = "Clic sinistro: mostra o nascondi",
	TOOLTIP_RIGHT = "Clic destro: impostazioni",
	COMING_SOON = "Questa parte arriva presto.",

	-- Comandi (/threatwarden, /atw)
	CMD_LOCKED = "Finestra bloccata.",
	CMD_UNLOCKED = "Finestra sbloccata.",
	CMD_RESET = "Posizione, dimensioni e scala della finestra ripristinate.",
	CMD_READ_ONLY = "Nulla è cambiato: i dati salvati sono in sola lettura (vedi /atw debug).",
	CMD_UNKNOWN = "Comando sconosciuto: %s. Scrivi /atw help.",
	CMD_LATER = "Arriva nella %s.",
	HELP_HEADER = "Comandi (/atw o /threatwarden):",
	HELP_TOGGLE = "mostra o nasconde la finestra",
	HELP_SHOW = "mostra la finestra",
	HELP_HIDE = "nasconde la finestra",
	HELP_LOCK = "blocca la finestra",
	HELP_UNLOCK = "sblocca la finestra",
	HELP_RESET = "ripristina posizione, dimensioni e scala della finestra",
	HELP_SETTINGS = "apre le impostazioni",
	HELP_ABOUT = "apre la pagina Info",
	HELP_DEBUG = "apre il rapporto diagnostico",
	HELP_HELP = "elenca i comandi",

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
