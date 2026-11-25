# SPEC-03: Threat Monitor e interfaccia

> Fonte: [specifiche originali](source-specification.md) §5.1, §6. Finestra e comandi (§4–§5) completati in **M1.1**;
> monitor (§1–§3) da completare in **M2.1**, con l'esito del probe.

## 1. Cosa mostra il monitor

Per ogni unità osservata sul mob monitorato (di predefinito il target del giocatore; se non è un nemico, il target del
target):

| Campo | Categoria | Se manca |
|---|---|---|
| Nome del giocatore (colore di classe, icona del ruolo) | rilevata | `?` |
| Percentuale scalata (100 % = prende l'aggro) e barra | rilevata | barra vuota tratteggiata, "Unknown" |
| Margine rispetto al tank | calcolata | "—" |
| Stato SAFE / WARNING / DANGER / UNKNOWN | calcolata | UNKNOWN |
| Trend (freccia e valore) | stimata | nessuna freccia, "Insufficient data" |
| Tank attuale (chi ha `isTanking`) | rilevata | "Unknown tank" |
| Mob monitorato (nome, classificazione) | rilevata | "No target" |

- **MON-01** MUST: con dati segreti o assenti si vede UNKNOWN con il motivo nel tooltip, mai un numero.
- **MON-02** MUST: se l'API dà solo lo stato (`UnitThreatSituation`) e non i valori, il monitor mostra lo stato senza
  percentuale (modalità *state only*) e lo dice.
- **MON-03** SHOULD: indicatore di qualità dei dati nella barra del titolo: ultimo aggiornamento, percentuale di letture
  valide negli ultimi 10 s.

## 2. Stati e soglie

| Stato | Regola (predefinita provvisoria, Q7) |
|---|---|
| SAFE | `scaledPercent` < soglia WARNING |
| WARNING | soglia WARNING ≤ `scaledPercent` < soglia DANGER, oppure trend previsto oltre DANGER entro 3 s |
| DANGER | `scaledPercent` ≥ soglia DANGER, oppure situazione 2–3 per un non-tank |
| UNKNOWN | dati insufficienti, segreti o non disponibili |

- Soglie predefinite **provvisorie**: WARNING 80 %, DANGER 95 % (da tarare con le prove di M2, Q7).
- **MON-10** MUST: isteresi di 3 punti per non far lampeggiare lo stato attorno alla soglia.
- **MON-11** MUST: per il tank lo stato misura il **margine** sul secondo (`UnitThreatPercentageOfLead` o il massimo
  degli altri): poco margine = WARNING.

## 3. Ordinamenti

Per threat assoluta (se disponibile), percentuale rispetto al tank (predefinito), livello di rischio, variazione
recente. Il giocatore stesso è sempre evidenziato; opzione "fissa me in cima".

## 4. Finestra

Elementi (fonte §6.2): titolo e stato del modulo; target monitorato; stato sintetico; margine o percentuale; elenco dei
giocatori; trend; indicatore di qualità dei dati. Completato in M1.1: lo realizzano M1.7 (finestra, schede, comandi,
minimappa) e M1.8 (Settings e Info); il contenuto della scheda Monitor arriva in M2 (§1–§3). L'aspetto (token, font,
forme, la barra della threat e il distintivo di stato) è in [ui-style.md](ui-style.md).

### 4.1 Principi

- Pannello compatto e ridimensionabile; si sposta, si blocca, si scala; posizione per personaggio.
- Nessun blocco dell'interfaccia di gioco; nessuna azione protetta in combattimento: frame normali, nessun template
  sicuro, nessun frame di Blizzard ridisegnato. Mostrare, nascondere, spostare e ridimensionare funzionano anche in
  combattimento.
- Barra del titolo e schede nello stile dell'ecosistema ([ADR 0015](../adr/0015-interface-follows-the-ecosystem-style.md)):
  *Monitor*, *Reports* (da M4), *Settings*; Info e crediti in Settings.
- Modalità solo testo e solo icone per le righe del monitor (M2); contrasto sufficiente; stato mai affidato al solo
  colore (icona e parola, [ui-style §4](ui-style.md#4-il-tema-warden-e-i-token-di-stato)).
- Pulsante nel Compartment degli addon e icona della minimappa (LibDBIcon, nascondibile).

### 4.2 Due disposizioni, una finestra

Un solo frame, `AzerothThreatwardenWindow` (il nome serve a chiuderlo con Esc, ARC-04), con due disposizioni che
ricordano ciascuna la propria dimensione (`char.ui.size.compact` e `.wide`, [SPEC-02 §3.3](SPEC-02-data-model-storage.md#33-schema-1-personaggio-azeroththreatwardenchardb)):

| | **Compatta** (scheda Monitor) | **Ampia** (Settings, Info; Reports da M4) |
|---|---|---|
| Scopo | sovrapposta al gioco durante il combattimento | leggere e configurare fuori dal combattimento |
| Dimensione predefinita | 300 × 220 pt | 560 × 520 pt |
| Minimo / massimo | 220 × 140 / 600 × 800 | 480 × 420 / 900 × 900 |
| Barra del titolo | 28 pt: logo 18 pt, `THREATWARDEN` (Orbitron, 12 pt), stato del modulo, blocco, chiusura | 44 pt: logo 24 pt, `AZEROTH THREATWARDEN` (Orbitron, 16 pt), stato del modulo come sottotitolo mono, blocco, chiusura |
| Schede | 24 pt, solo testo, indicatore da 2 pt | 36 pt, indicatore da 2 pt (come Accord) |
| Contenuto | intestazione del mob, righe da 20 pt, piede da 16 pt con la qualità dei dati (M2) | colonna di card larga fino a 520 pt, con il selettore a pillole *Settings · Info* in Settings |

- Passando da una disposizione all'altra l'angolo in alto a sinistra resta fermo e la finestra resta nello schermo.
- La dimensione si cambia dalla maniglia in basso a destra (icona `dashed`, come Accord), dentro i limiti della
  disposizione; si salva al rilascio.
- In combattimento la finestra resta com'è; l'opzione di M2 *Compact in combat* (nascondere le schede in
  combattimento) è prevista con il monitor.

### 4.3 Barra del titolo e stato del modulo

Lo **stato del modulo** è una pastiglia con icona e parola (mai solo colore), che il giocatore vede sempre:

| Stato | Quando | Parola (`enUS`) | Token |
|---|---|---|---|
| `off` | la parte `monitor` è spenta in `Features` (tutta M1) | *Off* | `text-3` |
| `idle` | nessun combattimento o nessun mob monitorato (M2) | *Idle* | `text-3` |
| `live` | lettura dei valori (modalità `values`, [SPEC-01 §8.3](SPEC-01-platform-architecture.md#83-lettura-normalizzata-della-threat-m14-usata-da-m2)) | *Live* | `ok` |
| `state` | solo lo stato (MON-02, modalità `state`) | *State only* | `warn` |
| `unavailable` | API mancanti o segrete (`none`) | *Unavailable* | `err` |
| `unsupported` | client non riconosciuto (ARC-01) | *Unsupported client* | `err` |

Il tooltip della pastiglia dice il motivo (dalle capacità di Compat). Quali di questi stati compaiono davvero in gruppo
e in istanza lo dice il probe **[probe P3]**. Pulsanti a destra: **blocco** (lucchetto aperto o chiuso; con la finestra
bloccata non si sposta né si ridimensiona), **chiusura** (croce). La barra del titolo trascina la finestra quando non è
bloccata.

### 4.4 Schede

| Scheda | Disposizione | Contenuto | Da |
|---|---|---|---|
| **Monitor** | compatta | in M1 solo il testo *Threat monitoring arrives in v0.2.0* sotto il logo attenuato; da M2 il monitor (§1) | M1.7, M2 |
| **Reports** | ampia | sessioni registrate e report; non compare finché l'interruttore `reports` è spento | M4 |
| **Settings** | ampia | pagina *Settings* (card Aspetto, Lingua, Finestra, ripristino) e pagina *Info* (logo, versione, crediti, link) | M1.8 |

La scheda e la pagina aperte per ultime si ricordano per personaggio (`char.ui.lastTab`, `lastPage`).

### 4.5 Comportamento

| Cosa | Regola |
|---|---|
| Apertura al login | secondo `char.ui.shown` (vero la prima volta); le regole di [Q13](SPEC-09-risks-open-questions.md) arrivano con il monitor in M2 |
| Spostamento | trascinando la barra del titolo; la finestra resta nello schermo (`SetClampedToScreen`) e torna dentro a `DISPLAY_SIZE_CHANGED` e `UI_SCALE_CHANGED` |
| Posizione | per personaggio (`char.ui.pos`), salvata al rilascio; `nil` = al centro |
| Scala | `char.ui.scale` 50–200 % dalla card Finestra; si somma alla scala dell'interfaccia del gioco |
| Blocco | `char.ui.locked`, dal lucchetto, da `/atw lock` e `/atw unlock`, dalla card Finestra |
| Esc | chiude la finestra (frame in `UISpecialFrames` attraverso Compat), anche in combattimento |
| Livello | strato `MEDIUM`, sopra le finestre normali quando si clicca (`SetToplevel`) |
| `/reload` | posizione, dimensioni, scala, blocco, scheda e apertura tornano come erano (DAT-23) |

### 4.6 Minimappa e Addon Compartment

- **Minimappa** (`UI/Launcher.lua`): un oggetto LibDataBroker di tipo `launcher` con il logo (`logo_64`), mostrato da
  LibDBIcon con `account.settings.minimap`; clic sinistro apre o chiude la finestra, clic destro apre Settings; si
  nasconde dalla card Finestra (*Show minimap button*).
- **Addon Compartment**: le righe del TOC `## AddonCompartmentFunc`, `AddonCompartmentFuncOnEnter`,
  `AddonCompartmentFuncOnLeave` con le funzioni globali `AzerothThreatwarden_OnAddonCompartmentClick`, `…Enter`,
  `…Leave` e `## IconTexture` col logo; clic sinistro e destro come la minimappa.
- Tooltip (lo stesso nei due): nome dell'addon, versione, stato del modulo, *Left-click: show or hide*, *Right-click:
  settings*.
- Il Compartment e il pannello Impostazioni del gioco non sono nel dump: si cercano a runtime e, se mancano, resta la
  minimappa e la scheda Settings **[da provare in gioco]**.

## 5. Comandi e configurazione

`/threatwarden` e `/atw` (Q1), con AceConsole. Le risposte vanno solo nella finestra di chat del giocatore (mai in un
canale, [ADR 0001](../adr/0001-local-only-addon-no-network.md)), nella lingua attiva; il rapporto di `debug` è in
inglese.

| Comando | Effetto | Da |
|---|---|---|
| *(nessuno)* | apre o chiude la finestra | M1 |
| `show` / `hide` | apre / chiude la finestra | M1 |
| `lock` / `unlock` | blocca / sblocca la finestra | M1 |
| `reset` | riporta posizione, dimensioni e scala della finestra ai predefiniti e la mostra al centro (non tocca le impostazioni) | M1 |
| `settings` | apre la scheda Settings | M1 |
| `about` | apre la pagina Info | M1 |
| `debug` | apre il rapporto diagnostico da copiare ([SPEC-01 §9](SPEC-01-platform-architecture.md#9-diagnostica-atw-debug)) | M1 |
| `help` | elenca i comandi disponibili, con una riga ciascuno | M1 |
| `demo` | combattimento inventato per provare il monitor | M2 |
| `mute` | silenzia gli avvisi fino alla fine del combattimento | M3 |
| `reports` | apre la scheda Reports | M4 |

Un comando sconosciuto risponde *Unknown command: <x>. Type /atw help.*; un comando di una parte spenta in `Features`
risponde *This arrives in v0.N.0.* e non fa nulla.

Configurazione (fonte §6.4): moduli accesi o spenti; dimensione e posizione; soglie; frequenza di aggiornamento; durata
e limite delle registrazioni; notifiche; profili per ruolo (M8); lingua (Q5); aspetto (tema, effetti, animazioni,
font); reset delle impostazioni.

La pagina *Settings* è una colonna di card ([ui-style §3](ui-style.md#3-finestra-compatta-barre-e-stati)); ogni modifica
si applica subito, tranne il font (al riavvio del client) e la lingua (dopo `/reload`), e la card lo dice:

| Card | Controlli | Chiavi | Da |
|---|---|---|---|
| **Appearance** | tema (segmentato *Nebula · Aurora · Warden*), effetti (interruttore), animazioni (interruttore), font (segmentato *Addon font · Game font*) | `account.settings.theme`, `effects`, `animations`, `font` | M1.8 |
| **Language** | *Automatic · English · Italiano*, nota e pulsante *Reload now* | `account.settings.language` | M1.8 |
| **Window** | blocco (interruttore), scala (cursore 50–200 %), *Show minimap button* (interruttore), *Reset window* | `char.ui.locked`, `scale`, `account.settings.minimap.hide` | M1.8 |
| **Reset** | *Reset settings* con conferma (riporta ai predefiniti `account.settings`, [SPEC-02 §3.4](SPEC-02-data-model-storage.md#34-caricamento-migrazioni-e-dati-danneggiati)) | — | M1.8 |
| **Monitor** | soglie, frequenza, unità massime, quando mostrare la finestra | M2.1 le fissa | M2 |
| **Alerts** | canali, cooldown, silenzio | M3.1 | M3 |
| **Recording** | durata e limite delle registrazioni | M4.1 | M4 |

La stessa pagina compare nel pannello Impostazioni del gioco (*Options → AddOns*), se il client lo permette (M1.8).
