# SPEC-01: Piattaforma e architettura

> Fonte: [specifiche originali](source-specification.md) §1.3, §7, §9–§11. Completata in **M1.1** (2026-11-25)
> **prima** dell'esito del probe M0: ciò che dipende da una risposta del probe è marcato **[probe Pn]** e lo rivede
> M0.7 ([SPEC-08 §1](SPEC-08-quality-probe-release.md#1-probe-m0)). La panoramica in inglese, con i diagrammi, è
> [docs/ARCHITECTURE.md](../ARCHITECTURE.md).

## 1. Il client

| Fatto | Valore | Stato |
|---|---|---|
| Prodotto | World of Warcraft: Forever, build `1.60.1` (70170) | dal dump, [ADR 0002](../adr/0002-wow-forever-target-and-api-dump.md) |
| Interfaccia TOC | `## Interface: 16001` | dal dump |
| Lua | 5.1, motore client moderno (restrizioni degli addon, valori segreti) | dal dump |
| Comportamento della threat sul server | standard o personalizzato? | **[verificare]** P1, P3 |

**ARC-01** MUST: all'avvio l'addon controlla interfaccia e progetto; su un client diverso si carica in modalità
diagnostica e lo dice in `/atw debug` invece di dare numeri.

- Il controllo è quello di Accord: `WOW_PROJECT_ID == WOW_PROJECT_CAMELOT` quando il client ha le due costanti (non sono
  nel dump: si cercano a runtime), altrimenti il quarto valore di `GetBuildInfo()` fra 16001 e 19999. Il valore di
  `WOW_PROJECT_ID` su Forever lo dice P1 **[probe P1]**.
- In modalità diagnostica la finestra, le impostazioni, i crediti e `/atw debug` funzionano; il monitor (M2) resta
  spento e la barra del titolo dice *Unsupported client*.

## 2. API rilevanti dal dump (build 70170)

| API / evento | Firma nel dump | Uso | Stato |
|---|---|---|---|
| `UnitDetailedThreatSituation(unit, mob)` | → `isTanking, status, scaledPercentage, rawPercentage, rawThreat` | sorgente principale del monitor | **[verificare]** P2–P5 |
| `UnitThreatSituation(unit [, mob])` | → `status` 0–3, nilable | stato quando i valori sono segreti | **[verificare]** P2 |
| `UnitThreatPercentageOfLead(unit, mob)` | → numero, nilable | margine del tank sul secondo | **[verificare]** P2 |
| `UnitThreatLeadSituation(unit, mob)` | → 0–3, nilable | quanto il tank è sopra il secondo | **[verificare]** P2 |
| `GetThreatStatusColor(index)` | → r, g, b | solo confronto, i colori sono del tema | presente |
| `IsThreatWarningEnabled()` | → bool | rispettare l'avviso nativo, non duplicarlo | presente |
| `C_Secrets.ShouldUnitThreatValuesBeSecret(unit, mob)` / `C_Secrets.ShouldUnitThreatStateBeSecret(unit [, mob])` (nel namespace `C_Secrets`, non globali) | → bool | sapere **prima** se una lettura sarà segreta | **[verificare]** P3 |
| `issecretvalue(v)`, `issecrettable(t)` | → bool | non toccare mai un valore segreto | presente |
| `UNIT_THREAT_LIST_UPDATE`, `UNIT_THREAT_SITUATION_UPDATE` | evento con unità | aggiornamenti guidati da eventi | **[verificare]** P6 |
| `COMBAT_LOG_EVENT_UNFILTERED` | nessun payload documentato; **`CombatLogGetCurrentEventInfo` assente** | eventi di combattimento | **probabilmente non leggibile**, P7 |
| `C_DamageMeter` (sessioni, fonti, morti) | presente | possibile fonte di eventi (morti, durata) | **[verificare]** P8 |
| `UnitGUID`, `UnitGroupRolesAssigned`, `IsInGroup`, `IsInRaid`, `GetNumGroupMembers` | presenti | identità, ruolo, gruppo | **[verificare]** valori segreti in istanza, P5 |
| `PLAYER_REGEN_DISABLED/ENABLED`, `UNIT_TARGET`, `PLAYER_TARGET_CHANGED`, `ENCOUNTER_START/END` | presenti | inizio e fine combattimento, cambi di target | **[verificare]** P7 |

L'elenco completo delle API che l'addon usa, con lo stato nel dump, è la tabella delle capacità di Compat (§8).

**ARC-02** MUST: ogni chiamata passa da `Core/Compat.lua` (l'*API Adapter* della fonte §7.2), che dice per ogni
funzione `available`, `missing`, `restricted` (segreta) o `error`, normalizza i risultati e fa da unico punto di
ripiego. Nessun modulo di `UI/` chiama le API del gioco direttamente (un test lo verifica da M1.4).

## 3. Moduli

La struttura indicativa della fonte (§7) si adatta a quella di Azeroth Accord
([ADR 0012](../adr/0012-reuse-accord-and-unspoken-foundations.md)): `Core/` (infrastruttura), `Data/` (logica senza
grafica, testabile offline), `UI/` (viste), `Locales/`.

| Fonte §7 | File | Milestone |
|---|---|---|
| Bootstrap, Events, Scheduler | `Core/Init.lua`, `Core/Bus.lua` (eventi interni), `Core/Scheduler.lua` (tick limitati) | M1 |
| Compatibility, APIAdapter | `Core/Compat.lua` | M1 |
| Diagnostics | `Core/Diagnostics.lua`, `UI/DiagnosticsBox.lua` (`/atw debug`) | M1 |
| — | `Core/Config.lua` (SavedVariables, schema), `Core/Features.lua` (interruttori), `Core/Locale.lua` (lingua), `Core/Commands.lua` (comandi) | M1 |
| ThreatScanner, TargetTracker | `Data/ThreatScanner.lua`, `Data/TargetTracker.lua` | M2 |
| ThreatModel, ThreatCalculator, ThreatState | `Data/ThreatModel.lua`, `Data/ThreatCalc.lua`, `Data/ThreatState.lua` | M2 |
| Rules, Recommendations, AlertManager | `Data/CoachRules.lua`, `Data/Coach.lua`, `Data/Alerts.lua` | M3 |
| Recorder, Session, Storage | `Data/Recorder.lua`, `Data/Session.lua`, `Data/Storage.lua` | M4 |
| Replay | `Data/Replay.lua` | M5 |
| Metrics, Reports | `Data/Report.lua` (M4), `Data/Metrics.lua`, `Data/Export.lua` (M6) | M4, M6 |
| UI | `UI/Theme.lua`, `Assets.lua`, `Motion.lua`, `Widgets/`, `Window.lua`, `Launcher.lua`, `ThreatList.lua`, `Timeline.lua`, `ReplayWindow.lua`, `Settings.lua`, `About.lua` | M1… |
| Localization | `Locales/enUS.lua`, `Locales/itIT.lua` | M1 |

**ARC-03** MUST: i moduli comunicano con il Bus interno (`THREAT_UPDATED`, `STATE_CHANGED`, `COMBAT_STARTED`,
`COMBAT_ENDED`, `CONFIG_CHANGED`…, elenco completo in §3.3), non chiamandosi a vicenda dall'interfaccia ai dati.

**ARC-04** MUST: nessuna variabile globale tranne `AzerothThreatwarden`, le SavedVariables, le funzioni del
Compartment e i binding, più i frame con nome che il gioco richiede, tutti con il prefisso `AzerothThreatwarden`
(la finestra, per chiuderla con Esc; il tooltip dell'addon; gli oggetti font `AzerothThreatwardenFont<Id>`). Unica
eccezione senza prefisso: `SLASH_ACECONSOLE_ATW1` (e da M1.7 quello di `/threatwarden`), il nome che AceConsole dà al
comando e che il client usa per trovarlo (M1.4). Da M3.5 ci sono anche le due globali con cui il client legge i nomi
del binding, `BINDING_HEADER_AZEROTHTHREATWARDEN` e `BINDING_NAME_AZEROTHTHREATWARDEN_MUTE`, la funzione
`AzerothThreatwarden_ToggleMute` e il menu `AzerothThreatwardenMenu` (frame con nome per Esc, creato al primo uso).

### 3.1 I moduli di M1

Ogni file riceve `ADDON_NAME, ns = ...`; i moduli si appendono a `ns` (`ns.Compat`, `ns.Config`…) e, per i test,
all'oggetto dell'addon (`AzerothThreatwarden.Compat`…), come in Accord. Ordine di caricamento nel TOC: librerie
(`embeds.xml`), `Core/Bus.lua`, `Core/Compat.lua` (prima della lingua, perché `Locale` chiede la lingua del client
mentre si caricano i file di `Locales/`, M1.4), `Core/Locale.lua`, `Locales/enUS.lua`, `Locales/itIT.lua`,
`Core/Init.lua` (che aggancia Bus, Compat e Locale all'oggetto dell'addon), `Core/Features.lua`,
`Core/Scheduler.lua`, `Core/Config.lua`, `Core/Diagnostics.lua`, `Core/Commands.lua`, poi (da M2.2)
`Data/TargetTracker.lua`, `Data/ThreatScanner.lua`, poi `UI/Assets.lua`, `UI/Theme.lua`, `UI/Motion.lua`,
`UI/Widgets/*.lua`, `UI/DiagnosticsBox.lua`, `UI/Window.lua`, `UI/Launcher.lua`, `UI/Settings.lua`, `UI/About.lua`. Un modulo non usa un
altro modulo caricato dopo di lui al caricamento del file, solo nei suoi gestori.

| File | Responsabilità | Bus: emette / ascolta | Test | Step |
|---|---|---|---|---|
| `Core/Locale.lua` | tabelle delle lingue registrate dai file di `Locales/`; `ns.L`, una tabella che risponde nella lingua attiva con ripiego sull'inglese; `Locale.Apply(code)` al caricamento (§10) | — | `test_locales.lua`, `test_language.lua` | M1.2, M1.5 |
| `Core/Init.lua` | oggetto AceAddon `AzerothThreatwarden`; controllo Forever (ARC-01); ciclo di vita: `ADDON_LOADED` → `Config:Load`, `Locale.Apply`, `Compat:Probe`; `PLAYER_LOGIN` → interfaccia; `PLAYER_LOGOUT`; stato del combattimento da `PLAYER_REGEN_DISABLED/ENABLED`; cambi di schermo da `DISPLAY_SIZE_CHANGED` e `UI_SCALE_CHANGED`; registrazione dei comandi; sezioni di `/atw debug` (`AddDebugSection`) | emette `ADDON_READY`, `COMBAT_STARTED`, `COMBAT_ENDED`, `DISPLAY_CHANGED` | `test_init.lua` (avvio, client non Forever, `/reload`) | M1.2, M1.3 |
| `Core/Features.lua` | interruttori delle parti non finite (§3.4); `Features.On(name)` si chiede quando si agisce, mai una volta sola al caricamento | — | `test_features.lua` | M1.2 |
| `Core/Bus.lua` | publish/subscribe interno, copiato da Accord: `Bus.On`, `Bus.Off`, `Bus.Emit` (chiamate con il punto); un ascoltatore che solleva un errore non ferma gli altri (l'errore va nell'anello degli errori); un `Emit` non alloca (ARC-06) e non consegna un evento con un argomento segreto | — | `test_bus.lua` | M1.4 |
| `Core/Compat.lua` | unica porta verso le API del gioco: `Resolve`, `Call` sotto `pcall`, `IsSecret`/`Readable`, tabella delle API e delle capacità (§8), lettura normalizzata della threat (§8.3), timer, restrizioni | emette `CAPABILITY_CHANGED`; ascolta (dal gioco) `ADDON_RESTRICTION_STATE_CHANGED` | `test_compat.lua`, `test_api_boundary.lua` (nessun file di `UI/` chiama il gioco) | M1.4 |
| `Core/Scheduler.lua` | tick limitati con nome (ARC-09): avvio, arresto, frequenza, misura del costo | ascolta `COMBAT_ENDED` (ferma i tick legati al combattimento) | `test_scheduler.lua` | M1.4 |
| `Core/Config.lua` | SavedVariables, schema 1, regole tipizzate, predefiniti, migrazioni, sola lettura, `corrupt` ([SPEC-02 §3](SPEC-02-data-model-storage.md#3-savedvariables)); `Config:Get(path)`, `Config:Set(path, value)`, `Config:ResetSettings()`, `Config:ResetWindow()`, `Config:DebugLines()` (sezione *Saved data* di §9); `Config.LANGUAGES`, l'elenco delle lingue (§10) | emette `CONFIG_LOADED`, `CONFIG_CHANGED(path)` | `test_config.lua`, `test_language.lua` | M1.5 |
| `Core/Diagnostics.lua` | anello degli errori dell'addon (10, ripuliti dai percorsi), testo del rapporto (§9), mai nomi | — (legge Bus, Compat, Config, Scheduler) | `test_diagnostics.lua` | M1.4 |
| `Core/Commands.lua` | `/threatwarden` e `/atw` ([SPEC-03 §5](SPEC-03-threat-monitor-ui.md#5-comandi-e-configurazione)); un comando di una parte spenta in `Features` risponde *This arrives in vX* e non fa nulla | — (chiama le funzioni pubbliche di Window e Diagnostics) | `test_commands.lua` | M1.7 |
| `UI/Assets.lua` | tabella unica di texture e font dell'addon (`Media/`), come in Accord | — | `test_assets.lua` (ogni file in tabella, formato TGA, icone, licenze) | M1.6 |
| `UI/Theme.lua` | token di Nebula, Aurora e Warden e i token di stato ([ui-style](ui-style.md)); registro delle regioni tinte; oggetti font `AzerothThreatwardenFont<Id>`; `Px()`; forme 9-slice | emette `THEME_CHANGED(themeId)`; ascolta `CONFIG_LOADED`, `CONFIG_CHANGED` | `test_theme.lua` (parità dei token, contrasti, nessun colore fuori dal tema) | M1.6 |
| `UI/Motion.lua` | animazioni del tema (durate 120/200/320 ms), spente con `settings.animations` | — | `test_theme.lua` | M1.6 |
| `UI/Widgets/` | il kit di Accord (`Core.lua`: Button, Card, Badge, Tabs, Segmented, TitleBar, Dialog, EditBox, ChoiceList; `Controls.lua`: Switch, Slider, Select e, da M3.5, Menu (il menu di una riga); `ThinBar.lua`; `Tooltip.lua`), più `Threat.lua` con `ThreatBar`, `StateBadge` e `StateStripe` (vuoti di dati fino a M2) | — | `test_widgets.lua` | M1.6 |
| `UI/DiagnosticsBox.lua` | la finestra da cui copiare il rapporto di `/atw debug`: dal M1.6 un `Widgets.Dialog` senza velo, spostabile | — | `test_diagnostics.lua` | M1.4 |
| `UI/Window.lua` | finestra principale ([SPEC-03 §4](SPEC-03-threat-monitor-ui.md#4-finestra)): barra del titolo, schede, spostamento, blocco, ridimensionamento, scala, posizione per personaggio, Esc | emette `WINDOW_SHOWN(shown)`, `TAB_CHANGED(tabId)`; ascolta `CONFIG_LOADED`, `CONFIG_CHANGED`, `DISPLAY_CHANGED`, `COMBAT_STARTED`, `COMBAT_ENDED`, `CAPABILITY_CHANGED` (i colori li ridipinge il registro del tema) | `test_window.lua` | M1.7 |
| `UI/Launcher.lua` | pulsante della minimappa (LibDataBroker + LibDBIcon, nascondibile) e voce dell'Addon Compartment (le tre funzioni globali del TOC), con lo stesso tooltip | ascolta `CONFIG_CHANGED` (`settings.minimap.*`) | `test_launcher.lua` | M1.7 |
| `UI/Settings.lua` | selettore *Settings · Info* e pagina Settings (Aspetto, Lingua, Finestra, ripristino) nella scheda e nel pannello Impostazioni del gioco; `Settings.Build(parent, opts)`, `Settings.AddPage(id, def)`, `Settings.RegisterPanel()`; sezione *Settings* di `/atw debug` (stato del pannello) | emette `SETTINGS_CHANGED(key)`; ascolta `CONFIG_LOADED`, `CONFIG_CHANGED`, `THEME_CHANGED` | `test_settings.lua`, `test_ui_texts.lua` | M1.8 |
| `UI/About.lua` | pagina Info: logo, versione, crediti NEBULA, link da copiare, licenza | — | `test_about.lua` | M1.8 |

### 3.2 I moduli delle milestone successive (previsti)

| File | Responsabilità | Bus | Milestone |
|---|---|---|---|
| `Data/TargetTracker.lua` | mob monitorato (target o target del target), cambi, morte, scomparsa, cambio di GUID ([SPEC-03 §1.2](SPEC-03-threat-monitor-ui.md#12-il-mob-monitorato-datatargettrackerlua)) | emette `TARGET_CHANGED(mobKey)` (`nil` = nessun mob); ascolta `COMBAT_STARTED`, `COMBAT_ENDED`, `CONFIG_CHANGED`; dal gioco `PLAYER_TARGET_CHANGED`, `UNIT_TARGET` | M2.2 |
| `Data/ThreatScanner.lua` | unità osservate e limite, letture da eventi della threat più tick limitato in combattimento, consumatori (`Want`), record dal pool ([SPEC-03 §1.3–§1.4](SPEC-03-threat-monitor-ui.md#13-unità-osservate-e-limite-datathreatscannerlua)) | emette `THREAT_SCANNED(mobKey)`; ascolta `TARGET_CHANGED`, `COMBAT_STARTED`, `COMBAT_ENDED`, `WINDOW_SHOWN`, `TAB_CHANGED`, `CONFIG_CHANGED`; dal gioco `UNIT_THREAT_LIST_UPDATE`, `UNIT_THREAT_SITUATION_UPDATE`, `GROUP_ROSTER_UPDATE`, `UNIT_PET` | M2.2 |
| `Data/ThreatModel.lua`, `Data/ThreatCalc.lua` | `ThreatRecord` e `ThreatRow`, categorie, freschezza; margine, trend, tempo al superamento ([SPEC-02 §1–§2](SPEC-02-data-model-storage.md#1-threatrecord-in-memoria), [SPEC-03 §1.5, §2.5](SPEC-03-threat-monitor-ui.md#25-trend-e-tempo-al-superamento-datathreatcalclua)) | emette `THREAT_UPDATED(mobKey)`; ascolta `THREAT_SCANNED`, `TARGET_CHANGED`, `COMBAT_STARTED`, `COMBAT_ENDED` | M2.3 |
| `Data/ThreatState.lua` | SAFE / WARNING / DANGER / UNKNOWN con isteresi e permanenza; tank designati; modalità del monitor ([SPEC-03 §2](SPEC-03-threat-monitor-ui.md#2-stati-e-soglie)) | emette `STATE_CHANGED(unitKey, mobKey, old, new)`, `THREAT_MODE_CHANGED(mode, reason)`; ascolta `THREAT_UPDATED`, `CONFIG_CHANGED` | M2.4 |
| `Data/Alerts.lua`, `Data/Coach.lua`, `Data/CoachRules.lua`; `UI/CoachStrip.lua` | avvisi alle entrate di stato e di aggro, con cooldown per tipo e unità, canali e silenzio; regole del Coach con motivazione e confidenza; la striscia del Coach ([SPEC-04](SPEC-04-alerts-coach.md), moduli e test per step in §5–§6) | Alerts emette `ALERT_RAISED(alert)`, `MUTE_CHANGED(muted)`, ascolta `STATE_CHANGED`, `AGGRO_CHANGED`, `COMBAT_ENDED`, `CONFIG_LOADED`, `CONFIG_CHANGED`, `DEMO_CHANGED`; Coach emette `COACH_TIP(tip)`, ascolta `THREAT_UPDATED`, `COMBAT_ENDED`, `DEMO_CHANGED`, `CONFIG_LOADED`, `CONFIG_CHANGED` (M3.3); ThreatState emette `AGGRO_CHANGED(mobKey, unitKey, oldUnitKey)` (M3.2) | M3 |
| `Data/Recorder.lua`, `Data/Session.lua`, `Data/Storage.lua`, `Data/Report.lua`; `UI/Reports.lua` | sessioni con le letture del monitor in colonne compatte, eventi, reload e logout, limiti e potatura, sessioni danneggiate messe da parte, report con categorie e *Insufficient data*; la scheda Reports ([SPEC-05](SPEC-05-recording-report-replay.md), moduli e test per step in §6–§7, [ADR 0016](../adr/0016-recordings-are-the-monitors-readings-in-compact-columns.md)) | Recorder emette `SESSION_STARTED(id)`, `SESSION_ENDED(id, state)`, ascolta `COMBAT_*`, `TARGET_CHANGED`, `STATE_CHANGED`, `AGGRO_CHANGED`, `THREAT_MODE_CHANGED`, `ALERT_RAISED`, `COACH_TIP`, `DEMO_CHANGED`, `CONFIG_*`, `ENTERING_WORLD`; Storage emette `SESSIONS_CHANGED()` | M4 |
| `Data/Replay.lua`, `UI/Timeline.lua`, `UI/ReplayWindow.lua` | timeline e riproduzione | emette `REPLAY_POSITION(t)` | M5 |
| `Data/Metrics.lua`, `Data/Export.lua` | metriche descrittive, esportazione | — | M6 |
| `UI/ThreatList.lua` | elenco della threat nella scheda Monitor ([SPEC-03 §2.6, §3](SPEC-03-threat-monitor-ui.md#26-cosa-si-vede-in-ogni-stato)) | ascolta `THREAT_UPDATED`, `STATE_CHANGED`, `THREAT_MODE_CHANGED`, `TARGET_CHANGED`, `CONFIG_CHANGED`, `THEME_CHANGED` | M2.5 |

Ogni M<N>.1 completa la riga dei propri moduli (eventi esatti e test) come questa sezione fa per M1: le righe di M2
le ha completate M2.1, con i test per step in [SPEC-03 §6](SPEC-03-threat-monitor-ui.md#6-piano-di-m2-moduli-eventi-e-test-per-step).

### 3.3 Eventi del Bus

Gli eventi sono stringhe maiuscole; gli argomenti non contengono mai un valore segreto né un nome di giocatore
(per i dati della threat passano solo chiavi: `unitKey`, `mobKey`). `Core/Bus.lua` li elenca in testa al file, come in
Accord.

| Evento | Argomenti | Chi lo emette | Chi lo ascolta | Da |
|---|---|---|---|---|
| `ADDON_READY` | — | `Core/Init.lua`, dopo Config, Locale e Compat all'`ADDON_LOADED` | i moduli che preparano lo stato | M1.2 |
| `CONFIG_LOADED` | — | `Core/Config.lua`, dati caricati, migrati e ripuliti | Theme, Window, Settings | M1.5 |
| `CONFIG_CHANGED` | `path` (per esempio `"account.settings.theme"`) | `Config:Set` | Theme, Launcher, Window, Settings | M1.5 |
| `SETTINGS_CHANGED` | `key` | `UI/Settings.lua`, quando il giocatore cambia un'opzione | nessuno ancora (le viste seguono `CONFIG_CHANGED`) | M1.8 |
| `THEME_CHANGED` | `themeId` | `UI/Theme.lua` dopo `Theme.Apply` | Settings e le viste con elementi non registrati | M1.6 |
| `CAPABILITY_CHANGED` | `id`, `state` | `Core/Compat.lua` (`Compat:SetCapability`, cambio di una restrizione) | Window (stato del modulo), ThreatState (M2) | M1.4 |
| `COMBAT_STARTED` / `COMBAT_ENDED` | — | `Core/Init.lua` da `PLAYER_REGEN_DISABLED/ENABLED` | Scheduler, Window, Scanner (M2), Recorder (M4) | M1.2 |
| `DISPLAY_CHANGED` | — | `Core/Init.lua` da `DISPLAY_SIZE_CHANGED` e `UI_SCALE_CHANGED` | Window (torna nello schermo) | M1.7 |
| `ENTERING_WORLD` | — (da M4.2: `isInitialLogin`, `isReloadingUi`) | `Core/Init.lua` da `PLAYER_ENTERING_WORLD` | Settings (rilegge l'avviso della threat del gioco); Recorder e Storage (M4: com'è finita una sessione interrotta) | M3.5 |
| `WINDOW_SHOWN` | `shown` (bool) | `UI/Window.lua` | Scanner (M2: legge solo se serve) | M1.7 |
| `TAB_CHANGED` | `tabId` | `UI/Window.lua` | le schede | M1.7 |
| `TARGET_CHANGED`, `THREAT_SCANNED`, `THREAT_UPDATED`, `STATE_CHANGED`, `THREAT_MODE_CHANGED` | vedi §3.2 | `Data/` | UI, Alerts, Recorder | M2 |
| `AGGRO_CHANGED` | `mobKey`, `unitKey`, `oldUnitKey` (chi tiene il mob, prima e dopo; mai il motivo) | `Data/ThreatState.lua` | Alerts, Coach | M3.2 |
| `ALERT_RAISED`, `COACH_TIP`, `MUTE_CHANGED` | vedi §3.2 e [SPEC-04 §5](SPEC-04-alerts-coach.md#5-moduli-eventi-e-diagnostica) | `Data/` | Window, striscia del Coach, Recorder (M4) | M3 |
| `SESSION_STARTED`, `SESSION_ENDED`, `SESSIONS_CHANGED` | `id`; `id`, `state` (`complete`, `interrupted`, `dropped`); nessuno ([SPEC-05 §6](SPEC-05-recording-report-replay.md#6-moduli-eventi-interruttori-e-diagnostica-m4)) | `Data/Recorder.lua`, `Data/Storage.lua` | Reports, striscia del Coach (avviso di fine scontro), Report | M4 |

`/atw debug` mostra per ogni evento il numero di ascoltatori e gli ultimi errori degli ascoltatori.

### 3.4 Interruttori (`Core/Features.lua`)

Un interruttore per ogni parte di una milestone successiva ([ADR 0014](../adr/0014-one-version-per-milestone-and-feature-switches.md));
in `v0.1.0` erano tutti spenti, dalla `v0.2.0` (M2.R) è acceso `monitor`, dalla `v0.3.0` (M3.R) anche `alerts` e `coach`, e gli altri sono spenti. Spento vuol dire: nulla di visibile, nessun evento del gioco registrato, nessun dato
scritto; un comando di quella parte risponde che arriva in una versione successiva.

| Nome | Parte | Si accende in |
|---|---|---|
| `monitor` | lettura della threat, elenco, stati, `/atw demo` | M2.R |
| `alerts`, `coach` | avvisi; Threat Coach | M3.R |
| `recording`, `reports` | registrazione; report e scheda *Reports* | M4.R |
| `timeline`, `replay` | timeline; replay | M5.R |
| `analytics`, `export` | metriche e confronto; esportazione | M6.R |
| `multitarget` | più mob e dungeon focus (solo se P5 lo consente) | M7.R |
| `profiles`, `heatmap` | profili per ruolo; heatmap | M8.R |

## 4. Librerie

Incorporate, fissate in `.pkgmeta` e mai nel repository: LibStub, CallbackHandler, **AceAddon**, **AceEvent**,
**AceConsole** (comandi), LibDataBroker e LibDBIcon (pulsante della minimappa).
([ADR 0005](../adr/0005-embedded-ace3-savedvariables-and-schema-versions.md), aggiornamento di M1.1).

Non incorporate, come in Accord: AceComm (nessun messaggio, [ADR 0001](../adr/0001-local-only-addon-no-network.md));
AceDB (Config gestisce le tabelle salvate direttamente, per le regole di schema e di sola lettura); AceTimer (i timer
del client passano da Compat); AceConfig (Settings è una pagina nello stile dell'ecosistema). Nuovo rispetto ad Accord:
nemmeno **AceLocale**, perché la sua scelta della lingua è globale (la variabile `GAME_LOCALE` cambierebbe la lingua di
ogni addon Ace) e non permette l'impostazione *Language* ([ADR 0009](../adr/0009-interface-and-documentation-languages.md),
aggiornamento di M1.1; §10).

## 5. Prestazioni (fonte §9)

- **ARC-05** MUST: nessuna scansione completa a ogni frame; eventi dove esistono, campionamento solo in combattimento
  con frequenza configurabile e limite di unità e mob osservati.
- **ARC-06** MUST: nei percorsi frequenti nessuna allocazione ripetuta: tabelle riusate (pool), stringhe dell'interfaccia
  aggiornate solo quando cambiano.
- **ARC-07** MUST: analisi e serializzazioni pesanti fuori dal combattimento o spezzate su più frame.
- **ARC-08** SHOULD: la frequenza predefinita la decide la misura del probe (P10), non una scelta arbitraria
  ([Q14](SPEC-09-risks-open-questions.md)).
- **ARC-09** MUST: ogni lavoro periodico passa da `Core/Scheduler.lua`: tick con nome (`Scheduler.Start(name, hz, fn)`,
  `Stop(name)`), frequenza fra 1 e 10 Hz, un solo ticker del client per nome, ogni tick sotto `pcall` (un errore ferma
  quel tick e va nell'anello degli errori), tempo per tick misurato con `debugprofilestop` attraverso Compat (mediana e
  massimo degli ultimi 100, in `/atw debug`). Un tick legato al combattimento si ferma da solo a `COMBAT_ENDED`;
  nessun `OnUpdate` fisso. In M1 nessun tick è attivo.
- Target che scompaiono, muoiono o cambiano GUID, dati mancanti, ritardati o incoerenti: gestiti dal modello
  ([SPEC-02](SPEC-02-data-model-storage.md)) e coperti da test.

### 5.1 Il costo di un tick del monitor (misura offline di M2.7)

Un tick completo del monitor in un raid da 40: 40 letture, modello e calcoli, stati, elenco con la finestra aperta
(33 righe). Sono misure **offline** sul client finto, con funzioni del gioco a risposta costante: dicono come cambia il
costo fra una versione e l'altra, **non** quanto costa nel gioco. La frequenza predefinita resta **5 Hz provvisoria**
in attesa della misura nel client (P10, [Q14](SPEC-09-risks-open-questions.md)).

| Misura per tick | Misurato (M2.7) | Budget (il test fallisce oltre) |
|---|---|---|
| Lavoro (istruzioni della VM Lua) | 156 000 – 168 000 | 220 000 |
| Allocazioni | 14 – 27 byte | 48 byte |
| Tempo, in esecuzioni del ciclo di riferimento | 9 – 14 | 30 |
| Tempo sul PC di sviluppo (solo informativo) | circa 2 ms a macchina scarica, fino a 6 ms nelle ripetizioni più lente | nessuno |

| Frequenza | Tick al secondo × circa 2 ms |
|---|---|
| 2 Hz | circa 4 ms al secondo |
| 5 Hz (predefinito provvisorio) | circa 10 ms al secondo |
| 10 Hz | circa 20 ms al secondo |

- Dalla `v0.3.0` (M3.R) il test misura anche la configurazione pubblicata, con avvisi e Coach accesi: **39 – 113
  byte** per tick (la striscia scrive testi nuovi quando i suoi numeri cambiano, al più una volta al secondo, quindi a
  meno letture al secondo ogni tick pesa di più), budget **160 byte**; lavoro e tempo come con il solo monitor, a cui
  si riferisce la tabella qui sopra.
- Ripartizione del lavoro a 5 Hz: letture (con la segretezza controllata da Compat) circa metà, elenco circa 23 %,
  modello e calcoli circa 21 % (di più a 10 Hz, per i campioni della tendenza), stati circa 6 %. In *state only* un
  tick costa circa il 55 % di uno con i valori, con nulla di leggibile circa il 35 %.
- La lettura di **una sola unità** chiesta da `UNIT_THREAT_SITUATION_UPDATE` rifà modello, stati ed elenco: circa il
  40 % di un tick ciascuna. Una raffica di questi eventi conta più della frequenza del tick; se raggrupparli lo decide
  M0.7 con P6 e P10 (il comportamento di [MON-07](SPEC-03-threat-monitor-ui.md#14-quando-si-legge-eventi-e-tick) non
  cambia con M2.7).
- Il budget proposto per P10 (≤ 1 ms per tick al p95 e ≤ 5 ms al secondo,
  [SPEC-08](SPEC-08-quality-probe-release.md#p10--costo-del-campionamento)) offline **non** è rispettato a 40 unità e
  5 Hz sul PC di sviluppo: se P10 lo conferma nel client, si abbassa la frequenza o il limite di unità, o si riduce il
  lavoro di letture ed eventi.
- Il budget si controlla in `Tests/long/test_monitor_budget.lua` ([SPEC-08 §3](SPEC-08-quality-probe-release.md#3-test-lunghi)),
  per 2, 5 e 10 Hz, su un mob e con cambi di bersaglio. Un aumento voluto si misura, si spiega nella pull request e
  sposta i numeri nel test e in questa tabella.

## 6. Sicurezza, privacy, conformità (fonte §10)

Nessuna comunicazione di rete; nessuna credenziale o dato personale raccolto; dati solo nelle SavedVariables; funzione
per cancellare le registrazioni; nessun messaggio automatico in chat; solo API consentite; nessun tentativo di aggirare
le restrizioni (i valori segreti restano segreti); nessuna lettura della memoria del processo o strumento esterno.

## 7. Compatibilità e dipendenze (fonte §11)

L'addon funziona da solo; nessuna dipendenza obbligatoria. Con le UI personalizzate più comuni la finestra resta
utilizzabile (verifica nelle checklist). Nessuna integrazione con gli altri addon del proprietario (Q4).

## 8. Compat: API, capacità e lettura della threat

### 8.1 Stati e regole

All'`ADDON_LOADED` `Compat:Probe()` riempie due tabelle, come in Accord:

- **API**: per ogni voce di §8.2 `available`, `missing` (non esiste nel client), `restricted` (risponde con un valore
  segreto, o un errore che parla di restrizioni, o una restrizione è attiva) o `error` (un altro errore, testo
  ripulito). Le funzioni senza effetti collaterali e poco costose si **chiamano** una volta; le altre si controllano solo
  come esistenza.
- **Capacità** (§8.4): cosa l'addon può fare davvero, `available`, `missing`, `restricted` o `unknown`.

- **ARC-10** MUST: una voce mancante, in errore o segreta spegne la funzione che ne dipende, mai l'addon; nessun errore
  arriva al giocatore (`pcall` intorno a ogni chiamata).
- **ARC-11** MUST: un valore restituito si controlla con `Compat.IsSecret` (`issecretvalue`, `canaccessvalue`,
  `issecrettable`) **prima** di qualsiasi altra operazione; un valore segreto diventa `nil` con motivo `secret` e non è
  mai confrontato, sommato, formattato, concatenato, stampato o salvato (stesse regole del probe, PRB-02).
- **ARC-12** MUST: una capacità non si dà per buona finché un dato non la dimostra: resta `unknown` (la API c'è ma
  nessuna lettura l'ha ancora confermata) e i moduli la precisano con `Compat:SetCapability(id, state, detail)`, che
  emette `CAPABILITY_CHANGED`.
- Le funzioni dell'interfaccia del gioco che il dump non elenca (FrameXML: `Settings`, `SlashCmdList`, `UIParent`,
  `Enum`) si cercano a runtime con `Compat.Resolve`; "assente" è una risposta, come nel probe (PRB-05).
- Il confine (M1.4, `test_api_boundary.lua`): nessun file tranne `Core/Compat.lua` nomina un'API del gioco, né una
  funzione né una tabella né una costante (`GetTime`, `C_Timer`, `WOW_PROJECT_ID`, `print`…); i file di `UI/` possono
  solo creare frame (`CreateFrame`, `CreateFont`) e chiamare i metodi dei propri frame. Anche `GameTooltip`,
  `UIParent` e `UISpecialFrames` passano da Compat (`Compat.Tooltip`, `Compat.UIParent`, `Compat.CloseOnEscape`).
  Sono ammesse la libreria di Lua e le sue funzioni di comodo del client (`format`, `wipe`, `tinsert`…).
- `Compat.IsSecret(v)` passa il valore soltanto a `issecretvalue`, `canaccessvalue` e (per una tabella) a
  `issecrettable`, e ne chiede `type()`: non lo confronta, non lo indicizza, non lo concatena e non lo conserva.

### 8.2 Tabella delle API

Dal dump di Forever (build 70170, `../WoW-Addons/docs/api.json`, consultato il 2026-11-25; mai copiato,
[ADR 0002](../adr/0002-wow-forever-target-and-api-dump.md)). *Chiamata*: Probe la chiama all'avvio; *esistenza*: solo
controllata. *Dump*: **firma** (sistema documentato con argomenti e risultati), **globale** (nell'elenco dei globali
senza firma), **assente** (si cerca a runtime). In grassetto le voci il cui comportamento lo dice il probe.

| Id | Percorso | Probe | Dump | Uso | Da | Probe M0 |
|---|---|---|---|---|---|---|
| `client.GetBuildInfo` | `GetBuildInfo` | chiamata | firma (6 valori) | ARC-01, `/atw debug` | M1 | P1 |
| `client.GetLocale` | `GetLocale` | chiamata | firma | lingua `auto` (§10) | M1 | P1 |
| `client.ProjectID` | `WOW_PROJECT_ID`, `WOW_PROJECT_CAMELOT` | lettura | assente | ARC-01 | M1 | **P1** |
| `client.RealmName` | `GetRealmName` | esistenza | firma | solo per togliere il reame dagli errori del rapporto (§9), mai salvato | M1 | — |
| `secret.issecretvalue` | `issecretvalue` | esistenza | firma | ARC-11 | M1 | P3 |
| `secret.issecrettable` | `issecrettable` | esistenza | firma | ARC-11 | M1 | P3 |
| `secret.canaccessvalue` | `canaccessvalue` | esistenza | firma | ARC-11 | M1 | P3 |
| `secret.HasSecretRestrictions` | `C_Secrets.HasSecretRestrictions` | chiamata | firma | se `false`, nessun valore segreto in questa build | M1 | **P1, P3** |
| `secret.ThreatValues` | `C_Secrets.ShouldUnitThreatValuesBeSecret` | esistenza | firma `(unit, mobUnit)` | previsione prima della lettura (§8.3) | M1 | **P3** |
| `secret.ThreatState` | `C_Secrets.ShouldUnitThreatStateBeSecret` | esistenza | firma `(unit [, mobUnit])` | previsione prima della lettura | M1 | **P3** |
| `secret.Identity` | `C_Secrets.ShouldUnitIdentityBeSecret` | esistenza | firma | GUID e nomi in istanza | M2 | **P9** |
| `secret.Comparison` | `C_Secrets.ShouldUnitComparisonBeSecret` | esistenza | firma | `UnitIsUnit` in istanza | M2 | **P9** |
| `threat.Detailed` | `UnitDetailedThreatSituation` | esistenza | firma `(unit, mobGUID: UnitToken)` | valori del monitor | M1 (lettura M2) | **P2–P5** |
| `threat.Situation` | `UnitThreatSituation` | esistenza | firma, risultato nilable | modalità *state only* | M1 (lettura M2) | **P2, P3** |
| `threat.PercentageOfLead` | `UnitThreatPercentageOfLead` | esistenza | firma, nilable | margine del tank | M1 (lettura M2) | **P2** |
| `threat.LeadSituation` | `UnitThreatLeadSituation` | esistenza | firma, nilable | margine del tank (stato) | M1 (lettura M2) | **P2** |
| `threat.StatusColor` | `GetThreatStatusColor` | esistenza | firma | solo confronto, mai usato per disegnare | M1 | P2 |
| `threat.WarningEnabled` | `IsThreatWarningEnabled` | chiamata | firma | non duplicare l'avviso nativo (M3) | M1 | — |
| `unit.Exists` | `UnitExists` | esistenza | firma | target presente | M2 | P2 |
| `unit.GUID` | `UnitGUID` | chiamata (`"player"`) | firma, nilable, argomento `UnitTokenPvPRestrictedForAddOns` | chiavi di unità e mob | M2 | **P9** |
| `unit.TokenFromGUID` | `UnitTokenFromGUID` | esistenza | firma, nilable | ritrovare un mob | M7 | **P5, P9** |
| `unit.Name` | `UnitName` | esistenza | firma | nome mostrato (mai salvato fuori dalle sessioni) | M2 | P9 |
| `unit.Class` | `UnitClass` | esistenza | firma | colore di classe | M2 | — |
| `unit.Classification` | `UnitClassification` | esistenza | firma | élite, boss | M2 | P5 |
| `unit.CanAttack` | `UnitCanAttack` | esistenza | firma | mob ostile | M2 | P2 |
| `unit.IsDead` | `UnitIsDead` | esistenza | firma | mob morto | M2 | P7 |
| `unit.IsUnit` | `UnitIsUnit` | esistenza | firma | target del target, "me" | M2 | **P9** |
| `unit.AffectingCombat` | `UnitAffectingCombat` | chiamata (`"player"`) | firma | stato del combattimento | M1 | P7 |
| `unit.Role` | `UnitGroupRolesAssigned` | esistenza | firma | ruolo (tank) | M2 | **P9** |
| `group.InGroup` | `IsInGroup` | chiamata | globale | unità da leggere | M2 | P5 |
| `group.InRaid` | `IsInRaid` | chiamata | globale | unità da leggere | M2 | P5 |
| `group.Size` | `GetNumGroupMembers` | chiamata | globale | unità da leggere | M2 | P5 |
| `group.RaidIndex` | `UnitInRaid` | esistenza | firma, risultato nilable | l'indice `raidN` del giocatore, da saltare ([SPEC-03 §1.3](SPEC-03-threat-monitor-ui.md#13-unità-osservate-e-limite-datathreatscannerlua)) | M2 | P5 |
| `instance.InInstance` | `IsInInstance` | chiamata | firma | contesto in `/atw debug` e nelle sessioni | M1 | P3 |
| `instance.Info` | `GetInstanceInfo` | esistenza | firma | tipo e difficoltà delle sessioni (`Compat.InstanceInfo`, M4.2; mai il nome, che non si legge) | M4 | P3 |
| `zone.RealZoneText` | `GetRealZoneText` | esistenza | firma `(mapID?)` | la zona di una sessione (`Compat.ZoneText`, M4.2; solo nella sessione, [SPEC-02 §4.1](SPEC-02-data-model-storage.md#41-intestazione)); il numero della creatura di un mob lo dà `Compat.Unit.NpcID(guid)` dal GUID già letto, senza chiamate | M4 | — |
| `restriction.InCombatLockdown` | `C_RestrictedActions.InCombatLockdown` (o il globale `InCombatLockdown`) | chiamata | firma / globale | nessuna azione protetta in combattimento | M1 | P11 |
| `restriction.IsActive` | `C_RestrictedActions.IsAddOnRestrictionActive` | per ogni tipo | firma | restrizioni attive (una voce `restriction.<Tipo>`) | M1 | **P11** |
| `restriction.Types` | `Enum.AddOnRestrictionType` | lettura | assente (FrameXML) | i tipi di restrizione | M1 | **P11** |
| `combatlog.Restricted` | `C_CombatLog.IsCombatLogRestricted` | chiamata | firma | solo per il rapporto; il combat log non si usa ([ADR 0004](../adr/0004-threat-from-the-unit-threat-api-sampled-in-combat.md)) | M1 | **P7** |
| `damagemeter.Available` | `C_DamageMeter.IsDamageMeterAvailable` | chiamata | firma | morti e durata (forse, M4) | M4 | **P8** |
| `time.GetTime` | `GetTime` | chiamata | firma | tempo dei campioni | M1 | — |
| `time.ServerTime` | `GetServerTime` | chiamata | firma | data delle voci `corrupt` (M1.5) e delle sessioni | M1 | P12 |
| `time.After`, `time.NewTicker`, `time.NewTimer` | `C_Timer.After`, `NewTicker`, `NewTimer` | esistenza | firma | Scheduler | M1 | P11 |
| `time.ProfileStop` | `debugprofilestop` | esistenza | firma | costo dei tick (ARC-09) | M1 | P10 |
| `addon.Metadata` | `C_AddOns.GetAddOnMetadata` | chiamata | firma | versione nel rapporto e in Info | M1 | — |
| `addon.Memory` | `UpdateAddOnMemoryUsage`, `GetAddOnMemoryUsage` | esistenza | firma | memoria in `/atw debug` | M1 | P10 |
| `addon.Framerate` | `GetFramerate` | esistenza | firma | rapporto | M1 | P10 |
| `addon.ErrorHandler` | `geterrorhandler`, `seterrorhandler` | esistenza | globale | anello degli errori dell'addon (§9) | M1 | — |
| `ui.Reload` | `C_UI.Reload` (o il globale `ReloadUI`) | esistenza | firma / globale | pulsante "Reload now" dopo il cambio di lingua | M1 | — |
| `ui.CreateFrame`, `ui.CreateFont` | `CreateFrame`, `CreateFont` | esistenza | globale | tutta l'interfaccia (solo da `UI/` attraverso il kit e il tema) | M1 | — |
| `ui.CreateColor` | `CreateColor` | esistenza | globale | sfumature (`SetGradient`) del tema; senza, un colore semplice (M1.6) | M1 | — |
| `ui.ScreenSize` | `GetPhysicalScreenSize`, `GetScreenWidth`, `GetScreenHeight` | chiamata | firma | tenere la finestra nello schermo | M1 | — |
| `ui.SettingsPanel` | `Settings.RegisterCanvasLayoutCategory`, `Settings.RegisterAddOnCategory`, `Settings.OpenToCategory` | esistenza | assente (FrameXML) | voce nel pannello Impostazioni del gioco (M1.8, `Compat.HasSettingsPanel`, `Compat.RegisterSettingsPanel`; `OpenToCategory` non è ancora chiamata); se manca resta la scheda della finestra | M1 | da provare in gioco |
| `ui.SpecialFrames` | `UISpecialFrames` | esistenza | assente (FrameXML) | Esc chiude la finestra ([SPEC-03 §4.5](SPEC-03-threat-monitor-ui.md#45-comportamento)) | M1 | da provare in gioco |
| `ui.SlashCmdList` | `SlashCmdList` (attraverso AceConsole) | esistenza | assente (FrameXML) | comandi | M1 | da provare in gioco |
| `ui.ClassColor` | `C_ClassColor.GetClassColor` | esistenza | firma | colore di classe nell'elenco | M2 | — |
| `ui.PlaySound` | `PlaySound`, altrimenti `C_Sound.PlaySound` | esistenza | firma `(soundKitID, uiSoundSubType, …)` (sistema `Sound`); `Compat.PlaySound` (M3.2) | avviso sonoro (spento di predefinito, [SPEC-04 §1.4](SPEC-04-alerts-coach.md#14-canali)) | M3 | — |

Eventi del gioco (tutti nel dump con il loro payload), registrati solo attraverso `Core/Init.lua` e i moduli `Data/`
con AceEvent: `ADDON_LOADED`, `PLAYER_LOGIN`, `PLAYER_ENTERING_WORLD` (`isInitialLogin`, `isReloadingUi`),
`PLAYER_LOGOUT`, `PLAYER_REGEN_DISABLED`, `PLAYER_REGEN_ENABLED`, `ADDON_RESTRICTION_STATE_CHANGED` (`type`, `state`),
`UI_SCALE_CHANGED`, `DISPLAY_SIZE_CHANGED` (M1); `UNIT_THREAT_LIST_UPDATE`, `UNIT_THREAT_SITUATION_UPDATE`
(`unitTarget`), `PLAYER_TARGET_CHANGED`, `UNIT_TARGET`, `GROUP_ROSTER_UPDATE`, `UNIT_PET` (M2, **[probe P6, P7]**);
`ENCOUNTER_START`, `ENCOUNTER_END`, `UNIT_DIED` (`unitGUID`), `PLAYER_DEAD` (M4, **[probe P7]**), registrati da
`Data/Recorder.lua` con `PLAYER_LOGOUT` ([SPEC-05 §1.4, §1.6](SPEC-05-recording-report-replay.md#14-eventi)); in M4
`PLAYER_ENTERING_WORLD` passa `isInitialLogin` e `isReloadingUi` nell'evento `ENTERING_WORLD` del Bus.

### 8.3 Lettura normalizzata della threat (M1.4, usata da M2)

`Compat.Threat.Read(unit, mob, record)` riempie una tabella riusata (nessuna allocazione) con i campi di
[SPEC-02 §1](SPEC-02-data-model-storage.md#1-threatrecord-in-memoria) e restituisce la **modalità** della lettura:

1. Se `C_Secrets.ShouldUnitThreatStateBeSecret(unit, mob)` è vero → nessuna chiamata, modalità `none`, `reason =
   "secret"`.
2. Se `C_Secrets.ShouldUnitThreatValuesBeSecret(unit, mob)` è vero → solo `UnitThreatSituation(unit, mob)`, modalità
   `state` (*state only*, MON-02).
3. Altrimenti `UnitDetailedThreatSituation(unit, mob)` → modalità `values`; ogni valore passa da ARC-11 (un valore
   segreto inatteso diventa `nil` con `reason = "secret"` e la lettura scende a `state` o `none`).
4. Una funzione assente o in errore dà `reason = "missing"` o `"error"`; nessun risultato dà `reason = "nil"`.
   Se manca o fallisce `UnitDetailedThreatSituation`, la lettura scende a `UnitThreatSituation` (modalità `state`, il
   `reason` dice perché mancano i valori); se solo i numeri della risposta dettagliata sono segreti e lo stato no, si
   tiene lo stato senza una seconda chiamata. Un argomento che non è un token leggibile dà `reason = "no-unit"` senza
   chiamate. Una previsione `Should…` che fallisce o che è essa stessa segreta non conta (M1.4).

La lettura non alloca (riempie il record del chiamante, `pcall` senza tabelle, ARC-06) e conta gli esiti per
`/atw debug` (`Compat.Threat.stats`: numeri soltanto). `source` diventa `detected` (`values`, `state`) o `unknown`
(`none`); `confidence` la decide il modello (M2).

La forma degli argomenti (token del mob, come nel dump, o GUID) e quale previsione `Should…` è affidabile li dice il
probe **[probe P2, P3]**: cambiano in questa sola funzione. Se `C_Secrets` manca, la lettura procede e conta solo il
controllo dei valori (ARC-11).

`Compat.Threat.ReadLead(holder, mob, record)` (M2.2) riempie `leadPercent` (`UnitThreatPercentageOfLead`, non chiesto
se la previsione dice i valori segreti) e `leadSituation` (`UnitThreatLeadSituation`) per chi tiene il mob, una volta
per scansione, con `leadReason` se mancano; una `Read` dello stesso record li azzera. Per lo Scanner e il TargetTracker,
che leggono a ogni scansione, Compat ha anche letture senza allocazione: `Compat.Unit` (`Exists`, `IsDead`,
`CanAttack`, `IsUnit`, `AffectingCombat`, `GUID`, `Name`, `Class`, `Role`) e `Compat.Group` (`InGroup`, `InRaid`,
`Size`, `RaidIndex`), che rispondono il valore oppure `nil` e il motivo (`secret`, `missing`, `error`, `no-unit`).

### 8.4 Capacità

| Capacità | Significato | All'avvio (M1.4) | La precisa | Probe M0 |
|---|---|---|---|---|
| `threatValues` | percentuali e valori leggibili sul target in combattimento | `missing` se `UnitDetailedThreatSituation` manca, altrimenti `unknown` | Scanner alla prima lettura in combattimento (M2) | **P2, P3** |
| `threatState` | solo lo stato 0–3 leggibile | come sopra, con `UnitThreatSituation` | Scanner (M2) | **P2, P3** |
| `threatLead` | margine del tank (`UnitThreatPercentageOfLead`) | come sopra | Scanner (M2) | **P2** |
| `threatEvents` | gli eventi `UNIT_THREAT_*` arrivano | `unknown` | Scanner (M2) | **P6** |
| `groupThreat` | la threat dei membri del gruppo sul mob | `unknown` | Scanner in gruppo (M2) | **P5** |
| `otherMobs` | la threat su mob diversi dal target | `unknown` | M7 | **P5** |
| `mobIdentity` | GUID dei mob leggibili e stabili | `unknown` | TargetTracker (M2) | **P9** |
| `roles` | ruoli del gruppo leggibili | `unknown` | M2 | **P9** |
| `combatLog` | il combat log è leggibile da un addon | `missing` se `CombatLogGetCurrentEventInfo` manca (atteso) | — | **P7** |
| `damageMeter` | `C_DamageMeter` utilizzabile | dal suo `IsDamageMeterAvailable` | M4 | **P8** |
| `restricted.<Tipo>` | una restrizione del client è attiva ora | da `IsAddOnRestrictionActive` | `ADDON_RESTRICTION_STATE_CHANGED` | **P11** |

M0.7 sostituisce gli `unknown` con ciò che il probe ha dimostrato (per esempio `threatValues` `restricted` in istanza)
e scrive in questa tabella le conseguenze per contesto.

## 9. Diagnostica (`/atw debug`)

**ARC-13** MUST: il rapporto si apre in `UI/DiagnosticsBox.lua` già selezionato da copiare; è in inglese (si incolla
nelle segnalazioni, [ADR 0009](../adr/0009-interface-and-documentation-languages.md) regola 5); non contiene mai nomi di
giocatori, gilde, reami, GUID di giocatori o percorsi del computer.

Sezioni, in ordine: intestazione (addon, versione, build di sviluppo sì/no); client (versione, build, interfaccia,
Forever sì/no, lingua del client, lingua scelta e attiva); interruttori di `Features`; API di §8.2 con stato e
dettaglio; capacità di §8.4; restrizioni attive; dati salvati (schema per variabile, sola lettura, problemi corretti
all'ultimo caricamento, voci in `corrupt`, dimensione stimata in KB); memoria dell'addon; Bus (eventi con ascoltatori,
errori degli ascoltatori); Scheduler (tick attivi, ms per tick); poi le sezioni dei moduli, come *Look* di `UI/Theme.lua`
(tema, effetti, font caduti sul font del gioco, texture rifiutate dal client, M1.6); ultimi errori (fino a 10, ripuliti da
`Diagnostics.CleanError`). Un modulo aggiunge la sua sezione con `AddDebugSection(title, linesFn)`.

## 10. Lingue (`Core/Locale.lua`)

- **ARC-14** MUST: i file di `Locales/` registrano la loro tabella con `ns.Locale.Register(code, strings)` qualunque sia
  la lingua del client; `Locales/enUS.lua` è la base. All'`ADDON_LOADED`, letti i dati salvati, `Locale.Apply` sceglie
  la lingua attiva da `account.settings.language` ([SPEC-09 Q5](SPEC-09-risks-open-questions.md)): `auto` segue
  `GetLocale()` (`enGB` vale `enUS`; una lingua senza file vale inglese), `enUS` e `itIT` la forzano.
- `ns.L[key]` risponde nella lingua attiva, poi in inglese; una chiave che manca anche in inglese restituisce la chiave
  stessa (così si vede) e lo conta per `/atw debug`. I moduli tengono `local L = ns.L` al caricamento del file: la
  tabella è la stessa prima e dopo la scelta.
- Il cambio di lingua dalle impostazioni vale dopo `/reload`: Settings lo dice e offre *Reload now* (`ui.Reload`). Prima
  dell'`ADDON_LOADED` (nomi dei binding) vale la lingua del client.
- I test di [ADR 0009](../adr/0009-interface-and-documentation-languages.md) regola 3 leggono le stesse tabelle.

## 11. Test per modulo

Tutti offline con lupa e il client finto ([ADR 0010](../adr/0010-offline-tests-with-lupa-and-a-mock-client.md));
ogni file di test cita i requisiti che prova.

| File di test | Modulo | Cosa prova | Step |
|---|---|---|---|
| `test_init.lua` | Init | avvio nel mock, client non Forever (ARC-01), `/reload` simulato, `ADDON_READY`, combattimento | M1.3 |
| `test_features.lua` | Features | accesi solo quelli delle parti rilasciate (`monitor` dalla `v0.2.0`, `alerts` e `coach` dalla `v0.3.0`); una parte spenta non registra eventi, non legge la threat e non scrive nulla (i comandi di una parte spenta li prova `test_commands.lua`, M1.7) | M1.3 |
| `test_locales.lua` | Locales | ADR 0009 regola 3 (chiavi, segnaposti, stringhe vuote o uguali) | M1.3 |
| `test_bus.lua` | Bus | ordine, duplicati, `Off` durante un `Emit`, errori isolati | M1.4 |
| `test_compat.lua` | Compat | ogni voce di §8.2 `available`/`missing`/`restricted`/`error` nel mock; valori segreti mai letti; §8.3 con risposte scriptate (valori, solo stato, segreto, `nil`, errore) | M1.4 |
| `test_api_boundary.lua` | tutti i file dell'addon tranne Compat | nessuna chiamata diretta a un'API del gioco (ARC-02); `UI/` può solo creare frame | M1.4 |
| `test_scheduler.lua` | Scheduler | un ticker per nome, limiti di frequenza, arresto a `COMBAT_ENDED`, errore in un tick | M1.4 |
| `test_diagnostics.lua` | Diagnostics, DiagnosticsBox | sezioni del rapporto, nessun nome, errori ripuliti e contati | M1.4 |
| `test_config.lua` | Config | DAT-20–DAT-25 di [SPEC-02 §3](SPEC-02-data-model-storage.md#3-savedvariables) | M1.5 |
| `test_language.lua` | Locale | `auto`, `enUS`, `itIT`, lingua del client senza file, cambio dopo `/reload` | M1.5 |
| `test_theme.lua` | Theme, Motion | parità dei token, contrasti di [ui-style §4](ui-style.md#4-il-tema-warden-e-i-token-di-stato), token di stato (ST-01–ST-05), cambio di tema senza `/reload`, font, animazioni | M1.6 |
| `test_assets.lua` | Assets, `Media/` | ogni file in tabella esiste (TGA 32 bit, dimensioni), foglio di icone uguale a `tools/make_media.py`, font con licenza, `IconTexture` | M1.6 |
| `test_widgets.lua` | Widgets | componenti del kit, `ThreatBar` e `StateBadge` in ogni stato | M1.6 |
| `test_window.lua` | Window | posizione, dimensioni, scala, blocco dopo `/reload`; Esc; schermo più piccolo | M1.7 |
| `test_commands.lua` | Commands | ogni comando nelle due lingue, argomenti sbagliati | M1.7 |
| `test_launcher.lua` | Launcher | minimappa nascosta e mostrata, Compartment, tooltip | M1.7 |
| `test_settings.lua` | Settings | ogni impostazione si applica subito (tranne font e lingua) | M1.8 |
| `test_about.lua` | About | crediti, logo NEBULA per tema, link | M1.8 |
| `test_ui_texts.lua` | tutta `UI/` | nulla a schermo senza chiave di lingua; in italiano solo testi italiani | M1.8 |
| `test_target_tracker.lua` | TargetTracker | la regola del mob, cambi, morte, scomparsa, GUID nuovo senza evento, GUID segreto, `UNIT_TARGET`, interruttore spento ([SPEC-03 §6](SPEC-03-threat-monitor-ui.md#6-piano-di-m2-moduli-eventi-e-test-per-step)) | M2.2 |
| `test_scanner.lua` | ThreatScanner | nessuna lettura fuori dal combattimento, senza mob o senza consumatore; tick e arresto; eventi raccolti, duplicati, fuori ordine, persi; risposte `nil`, errore, mancanti, segrete; i tre esiti; limite e turno; famiglio; roster; `/reload` in combattimento; nessuna allocazione per scansione | M2.2 |

## 12. Cosa aspetta il probe

Questa specifica non legge la threat e vale qualunque sia l'esito del probe; cambiano soltanto le righe marcate
**[probe Pn]**: il valore di `WOW_PROJECT_ID` (P1), la forma degli argomenti e le previsioni di §8.3 (P2, P3), lo stato
iniziale delle capacità di §8.4 (P2–P9, P11), gli eventi di M2 (P6, P7), la frequenza dei tick (P10, ARC-08). M0.7
aggiorna queste righe; se P3 dice che anche lo stato è segreto in gruppo, la scheda Monitor e le capacità `threat*`
cambiano con la decisione del proprietario, non le fondamenta di M1.
