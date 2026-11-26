# SPEC-02: Modello dati e salvataggio

> Fonte: [specifiche originali](source-specification.md) §5.4, §7.3–§7.5. Impostazioni e schema 1 completati in
> **M1.1** (§3); modello della threat (§1–§2) e schema 2 (§3.5) in **M2.1**; schema 3 (§3.6) in **M3.1**; schema 4 e sessioni
> registrate (§3.7, §4) in **M4.1**.

## 1. `ThreatRecord` (in memoria)

Il modello normalizzato di una lettura, per coppia (unità osservata, mob). I campi della lettura li riempie
`Compat.Threat.Read` ([SPEC-01 §8.3](SPEC-01-platform-architecture.md#83-lettura-normalizzata-della-threat-m14-usata-da-m2));
quelli di identità lo Scanner; completato in **M2.1** per i tre esiti del probe
([SPEC-03 §1.1](SPEC-03-threat-monitor-ui.md#11-tre-esiti-del-probe-tre-modalità)):

```lua
ThreatRecord = {
    -- identità (Scanner, SPEC-03 §1.2–§1.3)
    unitToken = nil,         -- token letto: "player", "pet", "party2", "raid13"
    unitKey = nil,           -- "unit:" .. GUID se leggibile, altrimenti "tok:" .. unitToken; mai un nome
    mobToken = nil,          -- "target" o "targettarget"
    mobKey = nil,            -- "mob:" .. GUID se leggibile, altrimenti "tgt:" .. n (SPEC-03 §1.2)
    unitName = nil,          -- nome mostrato; nil se segreto (la vista usa l'etichetta del token); mai salvato fuori dalle sessioni (§3)
    classFile = nil,         -- "WARRIOR"…, nil se segreto o assente
    role = nil,              -- "TANK", "HEALER", "DAMAGER"; nil per NONE o segreto
    -- lettura (Compat.Threat.Read)
    mode = "none",           -- values | state | none (SPEC-03 §1.1)
    isTanking = nil,         -- bool o nil
    situation = nil,         -- 0..3 (UnitThreatSituation o il 2° valore della lettura dettagliata) o nil
    scaledPercent = nil,     -- 0..100+: 100 = prende l'aggro; nil se segreto
    rawPercent = nil,
    rawThreat = nil,
    leadPercent = nil,       -- UnitThreatPercentageOfLead, solo per chi tiene il mob (significato [probe P2])
    leadSituation = nil,     -- UnitThreatLeadSituation 0..3, solo per chi tiene il mob
    leadReason = nil,        -- perché manca la percentuale (o la situazione) del vantaggio: "secret", "nil", "missing"…
    observedAt = 0,          -- GetTime() della lettura
    source = "detected",     -- detected | calculated | estimated | predicted | hypothesis | unknown
    confidence = "unknown",  -- high | medium | low | unknown: il modello (M2.3) mette high a una lettura fresca
                             -- values o state, low se stale, unknown in none
    reason = nil,            -- perché manca: "secret", "nil" (non è nella lista), "error", "missing", "no-unit", "stale"
    stale = false,           -- SPEC-03 §1.5; lo Scanner lo mette a true a COMBAT_ENDED
    interval = 0.2,          -- intervallo atteso fra due letture (Scanner, SPEC-03 §1.3); nil se la riga non ha posto
}
```

Per ogni unità osservata il modello (`Data/ThreatModel.lua`) tiene anche una **riga** derivata, riusata come il record:

```lua
ThreatRow = {
    record = ThreatRecord,   -- l'ultima lettura
    samples = { t = {}, p = {}, head = 0, count = 0 },  -- anello di 32 campioni (observedAt, scaledPercent), SPEC-03 §2.5
    present = false,         -- letta e nella lista del mob (reason ~= "nil", MON-05: altrimenti la riga non c'è)
    stale = false,           -- DAT-12: lettura più vecchia di max(2 · I, 0,5 s), o fine del combattimento
    reason = nil,            -- perché i valori non si mostrano: il reason del record, oppure "stale"
    isHolder = false,        -- è il record che tiene il mob (ThreatScanner.holder)
    trend = nil,             -- punti al secondo (stimato) o nil = "Insufficient data"
    trendConfidence = "unknown",
    trendSamples = 0,
    trendReason = "insufficient",  -- perché trend è nil: "insufficient", "state-only" o il reason della riga
    margin = nil,            -- punti (calcolato, §2), nil se non calcolabile
    marginReason = nil,      -- "alone" (nessun altro nella lista), "state-only", "missing" o il reason della riga
    overtakeIn = nil,        -- secondi interi, per eccesso (previsto), nil se le condizioni di SPEC-03 §2.5 non valgono
    overtakeReason = nil,    -- "insufficient", "not-rising", "low-confidence", "beyond" (> 10 s), "has-aggro", "holder"…
    isTank = false,          -- tank designato o trattato da tank (SPEC-03 §2.1)
    state = "UNKNOWN",       -- SAFE | WARNING | DANGER | UNKNOWN, mostrato (dopo isteresi e permanenza)
    stateReason = nil,       -- "lost-aggro", "has-aggro", "predicted", "margin-unknown" o il reason del record
    stateSince = 0,          -- GetTime() dell'ultimo cambio mostrato (MON-12)
}
```

- **DAT-10** MUST: un campo segreto o assente resta `nil` con `reason`; mai `0` al posto di "sconosciuto".
- **DAT-11** MUST: i record e le righe sono riusati da un pool ([SPEC-01](SPEC-01-platform-architecture.md) ARC-06):
  uno per unità osservata, creati quando l'elenco delle unità cresce, mai a ogni scansione.
- **DAT-12** MUST: una lettura più vecchia della soglia di freschezza (`max(2 · I, 0,5 s)`, con `I` l'intervallo atteso
  della riga, [SPEC-03 §1.5](SPEC-03-threat-monitor-ui.md#15-freschezza-e-qualità)) diventa `stale` e l'interfaccia lo
  mostra.
- **DAT-13** MUST: chiavi e campi del record non contengono mai un valore segreto: un GUID, un nome o una classe
  segreti restano `nil` e la chiave passa al token.

La categoria di ogni campo è fissa (`ThreatModel.CATEGORY`): rilevata per i campi della lettura, calcolata per il
margine, stimata per il trend, prevista per il tempo al superamento; `ThreatModel.Category(row, field)` la dà, oppure
`unknown` se il valore è `nil`, e `ThreatModel.Reason(row, field)` dice perché manca (`not-holder` per il vantaggio di
chi non tiene il mob). Il modello si aggiorna a `THREAT_SCANNED`, `TARGET_CHANGED`, `COMBAT_STARTED` e `COMBAT_ENDED` ed
emette `THREAT_UPDATED(mobKey)`; un nuovo mob o un nuovo combattimento azzerano i campioni anche quando lo Scanner
legge dentro il proprio gestore dello stesso evento (M2.3).

## 2. Valori calcolati

| Valore | Formula | Categoria |
|---|---|---|
| Percentuale rispetto al tank | `scaledPercent` dell'unità (il client già considera la regola del 110 % / 130 %, **[probe P4]**) | rilevata |
| Margine di un non tank | `100 − scaledPercent`, in punti percentuali | calcolata |
| Margine del tank che tiene il mob | `100 − s`, con `s` la `scaledPercent` più alta fra le altre righe in `values`; `UnitThreatPercentageOfLead` solo se P2 ne dimostra il significato (`ThreatCalc.TankMargin`) | calcolata |
| Trend | pendenza ai minimi quadrati di `scaledPercent` sui campioni validi degli ultimi 3 s (N ≥ 3, su almeno 0,5 s); confidenza da N e R² | stimata |
| Tempo al superamento | `(100 − scaledPercent) / trend`, solo per un non tank, se trend > 0, confidenza ≥ media e risultato ≤ 10 s | prevista |
| Stato | regole di [SPEC-03 §2](SPEC-03-threat-monitor-ui.md#2-stati-e-soglie) | calcolata (`values`) o rilevata (`state`) |
| Qualità dei dati | letture `values` o `state` / letture delle unità osservate negli ultimi 10 s | calcolata |

Dettagli, soglie e casi limite in [SPEC-03 §1–§2](SPEC-03-threat-monitor-ui.md) e [SPEC-04](SPEC-04-alerts-coach.md).

## 3. SavedVariables

`AzerothThreatwardenDB` (account) e `AzerothThreatwardenCharDB` (personaggio), ciascuna con `schema`
([ADR 0005](../adr/0005-embedded-ace3-savedvariables-and-schema-versions.md)). `Core/Config.lua` le gestisce
direttamente, senza AceDB, come Accord ([SPEC-01 §4](SPEC-01-platform-architecture.md#4-librerie)). Completato in M1.1:
lo **schema 1** qui sotto è quello che M1.5 realizza; nessuna chiave dipende dal probe.

### 3.1 Panoramica

| Chiave | Contenuto | Da |
|---|---|---|
| `db.schema` | numero di versione dello schema | M1 (schema 1), M2 (schema 2, §3.5), M3 (schema 3, §3.6), M4 (schema 4, §3.7) |
| `db.settings` | lingua, aspetto, minimappa (M1); soglie, frequenza, quando mostrare la finestra, ordinamento (M2); avvisi e Coach (M3, §3.6); registrazione e suoi limiti (M4, §3.7) | M1 → |
| `db.sessions` | registrazioni (§4), la più vecchia prima; il contenuto lo controlla `Data/Storage.lua` | M4 (schema 4, §3.7) |
| `db.profiles` | preset per ruolo | M8 |
| `db.corrupt` | tabelle danneggiate messe da parte (§3.4) | M1 |
| `char.schema`, `char.ui` | finestra: aperta, blocco, scala, posizione, dimensioni, ultima scheda | M1 (schema 1) |

Ogni milestone che cambia la forma dei dati alza lo schema di uno con una migrazione (DAT-20); il numero esatto lo
fissa lo step di specifica di quella milestone (M2.1, M3.1, M4.1, M8.1). Le impostazioni dell'aspetto e la lingua sono
per **account** (gusti della persona, come in Accord); la finestra è per **personaggio**.

### 3.2 Schema 1: account (`AzerothThreatwardenDB`)

| Percorso | Tipo | Predefinito | Regola | Uso |
|---|---|---|---|---|
| `schema` | intero ≥ 0 | `1` | — | versione |
| `settings` | tabella | `{}` | — | |
| `settings.language` | stringa | `"auto"` | enum `Config.LANGUAGES` = `auto`, `enUS`, `itIT` | lingua dell'interfaccia ([SPEC-09 Q5](SPEC-09-risks-open-questions.md), [SPEC-01 §10](SPEC-01-platform-architecture.md#10-lingue-corelocalelua)); vale dopo `/reload` |
| `settings.theme` | stringa | `"nebula"` | enum `Config.THEMES` = `nebula`, `aurora`, `warden` | tema ([ui-style §2](ui-style.md#2-impostazioni-dellaspetto)) |
| `settings.effects` | booleano | `true` | — | bagliori e testo neon |
| `settings.animations` | booleano | `true` | — | movimento di `UI/Motion.lua` |
| `settings.font` | stringa | `"addon"` | enum `Config.FONT_SOURCES` = `addon`, `game` | font dell'addon o del gioco; vale al riavvio del client |
| `settings.minimap` | tabella | `{ hide = false, minimapPos = 200 }` | — | consegnata a LibDBIcon; le chiavi che la libreria aggiunge (per esempio `lock`) restano come sono |
| `settings.minimap.hide` | booleano | `false` | — | pulsante della minimappa nascosto |
| `settings.minimap.minimapPos` | numero | `200` | 0–360 | angolo del pulsante (lo scrive LibDBIcon) |
| `corrupt` | array | `{}` | al massimo 5 voci (§3.4) | dati danneggiati messi da parte |

### 3.3 Schema 1: personaggio (`AzerothThreatwardenCharDB`)

| Percorso | Tipo | Predefinito | Regola | Uso |
|---|---|---|---|---|
| `schema` | intero ≥ 0 | `1` | — | versione |
| `ui` | tabella | `{}` | — | |
| `ui.shown` | booleano | `true` | — | finestra aperta al login (la prima volta il giocatore vede l'addon); le regole automatiche di [Q13](SPEC-09-risks-open-questions.md) arrivano in M2 |
| `ui.locked` | booleano | `false` | — | finestra bloccata: non si sposta né si ridimensiona |
| `ui.scale` | numero | `1.0` | 0,5–2,0, arrotondato a 0,05 | scala propria della finestra |
| `ui.pos` | tabella, facoltativa | `nil` (al centro) | `{ point, relativePoint, x, y }`: i due punti fra i nove ancoraggi del gioco (`TOPLEFT`… `CENTER`), `x` e `y` numeri finiti | posizione rispetto a `UIParent` |
| `ui.size` | tabella | `{}` | `compact` e `wide`, ciascuna facoltativa `{ w, h }` dentro i limiti di [SPEC-03 §4](SPEC-03-threat-monitor-ui.md#4-finestra) | dimensioni della disposizione compatta (Monitor) e ampia (Settings, Info, Reports) |
| `ui.lastTab` | stringa | `"monitor"` | enum `Config.TABS` = `monitor`, `settings` (`reports` da M4) | scheda aperta per ultima |
| `ui.lastPage` | stringa | `"settings"` | enum `settings`, `about` | pagina della scheda Settings (selettore a pillole) |

Nessun nome di giocatore, gilda o reame nelle impostazioni: i nomi stanno solo nelle sessioni registrate (M4,
[Q15](SPEC-09-risks-open-questions.md)).

### 3.4 Caricamento, migrazioni e dati danneggiati

All'`ADDON_LOADED` `Config:Load()` tratta ogni variabile così (l'algoritmo è quello di Accord, `Core/Config.lua`):

1. **Assente** → tabella nuova con i predefiniti, nessun problema segnalato. **Non è una tabella** (una stringa, un
   numero) → voce in `corrupt` con il solo tipo trovato (`path` = `account` o `char`), poi tabella nuova.
2. **`schema` assente o non valido** (non intero, negativo) → vale 0; se la tabella non è vuota il problema si annota.
3. **`schema` più vecchio** → le migrazioni da `schema + 1` alla versione conosciuta girano su una **copia**; se riescono
   la copia sostituisce il contenuto della tabella salvata (che resta la stessa tabella); se un passo fallisce o
   **manca**, la variabile resta intatta e quella parte dell'addon va in **sola lettura** (lavora su una copia).
4. **`schema` più nuovo** di quello conosciuto (si è tornati a una versione precedente dell'addon) → sola lettura:
   l'addon lavora su una copia e non riscrive mai la variabile; Settings mostra *Saved data comes from a newer version:
   changes are not saved* e `/atw debug` lo dice.
5. **Predefiniti**: si aggiungono solo le chiavi che mancano, mai sopra un valore presente.
6. **Regole** per percorso, dal genitore al figlio: una tabella attesa che ha un altro tipo, o che una regola rifiuta
   per intero, va in `corrupt` (copia limitata a 3 livelli e 50 chiavi, solo valori semplici, testi tagliati a 200
   caratteri) e torna al predefinito; un valore semplice sbagliato (tipo, intervallo, enumerazione, numero non finito)
   torna al predefinito; le dimensioni della finestra fuori dai limiti si **riportano** nei limiti e la scala si
   **arrotonda** a 0,05 invece di tornare al predefinito. Della posizione Config controlla solo la forma: riportarla
   dentro lo schermo è compito della finestra (M1.7, [SPEC-03 §4](SPEC-03-threat-monitor-ui.md#4-finestra)), perché
   solo lei conosce lo schermo. Ogni correzione si annota (`Config.issues`, percorso e parole fisse, mai valori o
   nomi; al massimo 50 per caricamento).
7. **Chiavi sconosciute** restano come sono: Config non cancella mai ciò che non conosce.

`corrupt` è un array di `{ scope, path, at, kind, data }` (`scope` `account` o `char`, `at` da `GetServerTime`,
`kind` il tipo trovato); al massimo **5** voci, la più vecchia esce per prima; l'addon non le rilegge mai, servono
solo a una segnalazione (`/atw debug` le conta). Si svuota con *Reset settings*.

Scrittura: `Config:Set(path, value)` controlla la regola del percorso e rifiuta un valore non valido (restituisce
`false` e il motivo), un percorso sconosciuto, una tabella contenitore intera (`settings`, `minimap`, `ui`, `size`,
`corrupt`: si scrivono le foglie) o una variabile in sola lettura; dimensioni e scala si correggono come al
caricamento; conserva una copia del valore ed emette `CONFIG_CHANGED(path)` solo se il valore cambia. `Config:Load()`
emette `CONFIG_LOADED`. *Reset settings* (Settings, `Config:ResetSettings()`) riporta ai predefiniti le chiavi
conosciute di `account.settings` (quelle sconosciute, per esempio `minimap.lock` di LibDBIcon, restano) e svuota
`corrupt`; `/atw reset` (`Config:ResetWindow()`) riporta ai predefiniti solo posizione, dimensioni e scala della
finestra (`char.ui`). Nessuno dei due tocca registrazioni e profili; in sola lettura rifiutano.

Migrazioni: `Config.migrations.account[n]` e `Config.migrations.char[n]` portano i dati da `n − 1` a `n`; il passo 1
non fa nulla (dati senza versione = 0, servono solo predefiniti e regole). `/atw debug` riporta, per variabile, lo
schema trovato (`none`, `damaged` o il numero), quello attuale, la dimensione stimata in KB e la sola lettura con il
motivo; poi le voci di `corrupt` (percorso e tipo, mai il contenuto) e i problemi corretti
(`Config:DebugLines()`, [SPEC-01 §9](SPEC-01-platform-architecture.md#9-diagnostica-atw-debug)).

- **DAT-20** MUST: una migrazione per versione, idempotente, provata con un test che parte dai dati della versione
  precedente.
- **DAT-21** MUST: uno schema più nuovo di quello conosciuto lascia i dati intatti e l'addon in sola lettura.
- **DAT-22** MUST: un valore di impostazione sbagliato torna al predefinito senza errori.
- **DAT-23** MUST: la configurazione sopravvive a logout e `/reload` (test con la simulazione di `/reload`).
- **DAT-24** MUST: una tabella danneggiata non blocca mai l'addon: va in `corrupt` (al massimo 5 voci) e torna al
  predefinito; una migrazione che fallisce lascia i dati intatti e la variabile in sola lettura.
- **DAT-25** MUST: `Config` non cancella mai una chiave che non conosce e non scrive mai una variabile in sola lettura.


### 3.5 Schema 2 (M2): le impostazioni del monitor

Fissato in **M2.1**, realizzato da **M2.6**. I predefiniti hanno un solo posto, `Config.MONITOR_DEFAULTS` (gli
intervalli `Config.MONITOR`); i moduli `Data/` e la vista li prendono da lì. Lo schema dell'account passa a **2** con la tabella `settings.monitor`; quello del personaggio resta
1. La migrazione `Config.migrations.account[2]` non fa nulla (i predefiniti aggiungono le chiavi che mancano), ma
esiste e ha il suo test (DAT-20). `Config.SCHEMAS` tiene lo schema di ogni variabile. La coppia di soglie si controlla
dopo le singole regole: se viola lo scarto, entrambe tornano ai predefiniti al caricamento; `Config:Set` su una sola
rifiuta un valore che la violerebbe e `Config:SetThresholds(warning, danger)` le scrive insieme, emettendo
`CONFIG_CHANGED` per ciascuna quando entrambe sono scritte.

| Percorso | Tipo | Predefinito | Regola | Uso |
|---|---|---|---|---|
| `settings.monitor` | tabella | `{}` | — | |
| `settings.monitor.warning` | intero | `80` | 50–99 | soglia WARNING ([Q7](SPEC-09-risks-open-questions.md)) |
| `settings.monitor.danger` | intero | `95` | 60–100 e almeno `warning + 5`; se no, le due tornano ai predefiniti | soglia DANGER (Q7) |
| `settings.monitor.rate` | intero | `5` | 2–10 (Hz) | frequenza del tick ([Q14](SPEC-09-risks-open-questions.md)) |
| `settings.monitor.maxUnits` | intero | `40` | 5–40 | unità lette per scansione (Q14) |
| `settings.monitor.show` | stringa | `"auto"` | enum `auto`, `always`, `manual` | quando si mostra la finestra ([Q13](SPEC-09-risks-open-questions.md), [SPEC-03 §5.1](SPEC-03-threat-monitor-ui.md#51-quando-si-mostra-la-finestra-q13-m26)) |
| `settings.monitor.sort` | stringa | `"relative"` | enum `relative`, `absolute`, `risk`, `change` | ordinamento ([SPEC-03 §3](SPEC-03-threat-monitor-ui.md#3-ordinamenti)) |
| `settings.monitor.pinSelf` | booleano | `false` | — | *Pin me on top* |
| `settings.monitor.followTargetOfTarget` | booleano | `true` | — | target del target ([SPEC-03 §1.2](SPEC-03-threat-monitor-ui.md#12-il-mob-monitorato-datatargettrackerlua)) |

Sono per **account** come l'aspetto: i profili per ruolo (M8) le renderanno per personaggio o per ruolo con una
migrazione propria.

### 3.6 Schema 3 (M3): avvisi e Coach

Fissato in **M3.1**, realizzato da **M3.2** (`settings.alerts`, la migrazione) e **M3.3** (`settings.coach`); la card è
di M3.5 ([SPEC-04 §4](SPEC-04-alerts-coach.md#4-configurazione-e-interruttori)). Lo schema dell'account passa a **3**;
quello del personaggio resta 1. La migrazione `Config.migrations.account[3]` non fa nulla (i predefiniti aggiungono le
chiavi che mancano), ma esiste e ha il suo test (DAT-20), che parte dai dati dello schema 2. I predefiniti hanno un
solo posto, `Config.ALERTS_DEFAULTS` e `Config.COACH_DEFAULTS` (intervalli `Config.ALERTS`, enumerazione
`Config.ALERT_OTHERS`): sono le risposte proposte di [Q12](SPEC-09-risks-open-questions.md) e
[Q11](SPEC-09-risks-open-questions.md).

| Percorso | Tipo | Predefinito | Regola | Uso |
|---|---|---|---|---|
| `settings.alerts` | tabella | `{}` | — | |
| `settings.alerts.enabled` | booleano | `true` | — | avvisi accesi; spento = *nessun avviso* ([SPEC-04 §1.4](SPEC-04-alerts-coach.md#14-canali)) |
| `settings.alerts.window` | booleano | `true` | — | messaggio nella striscia del Coach |
| `settings.alerts.visual` | booleano | `true` | — | effetto del bordo |
| `settings.alerts.sound` | booleano | `false` | — | suono del gioco per DANGER e aggro |
| `settings.alerts.cooldown` | intero | `8` | 3–30 (s) | cooldown per tipo e unità ([SPEC-04 §1.3](SPEC-04-alerts-coach.md#13-cooldown-e-raffiche)) |
| `settings.alerts.others` | stringa | `"tank"` | enum `tank`, `always`, `never` | avvisi su altre unità ([SPEC-04 §1.5](SPEC-04-alerts-coach.md#15-opzioni-esclusioni-e-silenzio)) |
| `settings.alerts.pet` | booleano | `true` | — | avviso quando il proprio famiglio prende il mob |
| `settings.coach` | tabella | `{}` | — | |
| `settings.coach.enabled` | booleano | `true` | — | Threat Coach acceso |

Il silenzio di `/atw mute`, l'esclusione di un'unità per la sessione e i cooldown in corso **non** si salvano; nessun
nome di giocatore nelle impostazioni (§3.3): l'esclusione per sessione si tiene in memoria per `unitKey`.

### 3.7 Schema 4 (M4): registrazione e sessioni

Fissato in **M4.1**, realizzato da **M4.2** (le chiavi, la migrazione, `sessions`) e **M4.3** (le regole del contenuto di
`sessions`, che controlla `Data/Storage.lua`); la card *Recording* è di M4.5
([SPEC-05 §3.6](SPEC-05-recording-report-replay.md#36-la-scheda-reports-e-la-card-recording-m45)). Lo schema
dell'account passa a **4** con la tabella `settings.recording` e la tabella `sessions` alla radice; quello del
personaggio resta 1 (l'enumerazione `Config.TABS` guadagna `reports`, il che non cambia la forma dei dati: una versione
precedente dell'addon che legge `reports` lo riporta al predefinito come qualsiasi valore sconosciuto). La migrazione
`Config.migrations.account[4]` non fa nulla (i predefiniti aggiungono `settings.recording` e `sessions = {}`), ma esiste
e ha il suo test, che parte dai dati dello schema 3 (DAT-20). I predefiniti hanno un solo posto,
`Config.RECORDING_DEFAULTS` (intervalli `Config.RECORDING`, enumerazione `Config.RECORD_WHEN`): sono le risposte
proposte di [Q8](SPEC-09-risks-open-questions.md) (numero e dimensione) e [Q16](SPEC-09-risks-open-questions.md) (quando,
frequenza, avviso).

| Percorso | Tipo | Predefinito | Regola | Uso |
|---|---|---|---|---|
| `settings.recording` | tabella | `{}` | — | |
| `settings.recording.enabled` | booleano | `true` | — | registrazione accesa ([SPEC-05 §1.1](SPEC-05-recording-report-replay.md#11-quando-si-registra)) |
| `settings.recording.when` | stringa | `"group"` | enum `group`, `instance`, `always` | in gruppo o in istanza; solo in istanza; sempre (Q16) |
| `settings.recording.rate` | intero | `2` | 1–5 (Hz) | frequenza del tick di registrazione ([SPEC-05 §1.3](SPEC-05-recording-report-replay.md#13-campioni-il-tick-di-registrazione)) |
| `settings.recording.maxSessions` | intero | `25` | 5–100 | sessioni tenute (Q8) |
| `settings.recording.maxKB` | intero | `2048` | 512–8192 (KB) | dimensione stimata massima di tutte le sessioni (Q8) |
| `settings.recording.notice` | booleano | `false` | — | avviso di fine scontro nella finestra ([SPEC-05 §3.5](SPEC-05-recording-report-replay.md#35-avviso-di-fine-scontro)) |
| `sessions` | array | `{}` | tabella; il contenuto lo controlla `Storage` (§4.6) | le sessioni registrate, la più vecchia prima |

`Config` controlla di `sessions` solo che sia una tabella (altrimenti voce in `corrupt` con il solo tipo e tabella
nuova); ogni sessione la controlla `Data/Storage.lua` al caricamento e una sessione danneggiata va in `corrupt` da sola
(§4.6), senza toccare le altre né le impostazioni. Per questo `Config` offre `Config:SetAside(path, value, kind)` (la stessa
copia limitata di §3.4, M4.3). *Reset settings* non tocca `sessions` (§3.4); le sessioni si eliminano solo da Reports o
dalla card *Recording* ([SPEC-05 §2.5](SPEC-05-recording-report-replay.md#25-eliminare-una-o-tutte-le-registrazioni)).

## 4. Sessioni registrate (schema 4, M4)

Fissato in **M4.1** ([ADR 0016](../adr/0016-recordings-are-the-monitors-readings-in-compact-columns.md)). Una sessione
è ciò che il monitor **ha letto** durante uno scontro (o una catena di pull), nel formato che la scrive il recorder
(M4.2) e la controlla lo storage (M4.3); il comportamento (quando si apre, che cosa si scrive, limiti, eliminazione) è
in [SPEC-05 §1–§2](SPEC-05-recording-report-replay.md). Tutti i tempi sono in **decimi di secondo** dall'inizio della
sessione (`GetTime()` al primo `COMBAT_STARTED`); la data dell'elenco è `GetServerTime()`.

### 4.1 Intestazione

```lua
Session = {
    id = "1764100000-1",     -- GetServerTime() all'apertura, "-", contatore delle sessioni aperte da questo caricamento;
                             -- unico nell'account (Storage aggiunge "-b", "-c"… a un doppione, §4.6)
    started = 1764100000,    -- GetServerTime() all'apertura: la data mostrata nell'elenco
    dur = 0,                 -- decimi: dal primo evento C all'ultimo c; in una sessione interrotta all'ultimo t scritto
    fight = 0,               -- decimi in combattimento: la somma dei periodi C…c (i pull a catena tolgono le pause)
    state = "open",          -- open (solo mentre si registra) | complete | interrupted
    ended = nil,             -- combat (finita normalmente) | reload | login | unknown (interrotta, SPEC-05 §1.6)
    stamp = false,           -- true: l'evento X è stato scritto a PLAYER_LOGOUT
    after = nil,             -- id della sessione interrotta che questa continua (reload in combattimento)
    trunc = nil,             -- t dal quale i campioni si sono fermati per un limite (evento Z)
    group = "solo",          -- solo | party | raid all'apertura
    zone = nil,              -- GetRealZoneText() all'apertura; nil se assente, vuoto o segreto
    inst = "none",           -- tipo d'istanza (GetInstanceInfo / IsInInstance): none, party, raid, pvp, arena, scenario
    diff = nil,              -- difficultyID di GetInstanceInfo, nil se non leggibile
    rec = {                  -- le condizioni della registrazione all'apertura, perché il report le dica
        hz = 2, monitorHz = 5, maxUnits = 40,   -- frequenza di registrazione e del monitor, unità per scansione
        warning = 80, danger = 95,              -- soglie in vigore (gli stati di values dipendono da loro)
        mode = "values",                        -- modalità del monitor all'apertura (MON-04)
        version = "v0.4.0",                     -- versione dell'addon che ha registrato
    },
    units = { { name = "Thrall", class = "SHAMAN", role = "TANK", token = "party1", me = nil, pet = nil }, … },
    mobs = { { name = "Hogger", class = "elite", npc = 448 }, … },
    n = 0,                   -- righe di campioni
    cols = { t = "", m = "", u = "", p = "", s = "" },   -- §4.2: stringhe in una sessione chiusa
    ne = 0,                  -- eventi
    ev = "",                 -- §4.3: una stringa in una sessione chiusa
    q = { v = {}, s = {}, x = {} },   -- per indice di unità: tick con valori, con il solo stato, sconosciuti (SPEC-05 §1.3)
    sum = nil,               -- riepilogo per l'elenco, calcolato alla chiusura (SPEC-05 §3.4); nil finché manca
    -- solo mentre la sessione è aperta (o interrotta e non ancora finita da Storage, SPEC-05 §2.2):
    parts = { t = {}, m = {}, u = {}, p = {}, s = {}, ev = {} },   -- pezzi già impacchettati (stringhe)
    buf = { t = {}, m = {}, u = {}, p = {}, s = {}, ev = {} },     -- al più CHUNK righe ed eventi non ancora impacchettati
}
```

- `units[i]`: il nome (`nil` se segreto o assente), `classFile`, il ruolo (`TANK`, `HEALER`, `DAMAGER`, `nil`), il token
  della prima lettura (`player`, `pet`, `party2`, `raid13`: l'etichetta quando il nome manca), `me = true` per il
  giocatore e `pet = true` per il suo famiglio. Le voci si aggiungono alla prima riga o al primo evento dell'unità, in
  quell'ordine; al più **61** (`Storage.LIMITS.units`). Nessun GUID di un giocatore si salva: `unitKey` resta in memoria
  (DAT-13), e i nomi stanno solo qui ([Q15](SPEC-09-risks-open-questions.md)).
- `mobs[i]`: il nome (`nil` se segreto), la classificazione (`UnitClassification`) e `npc`, il numero della creatura
  letto dal sesto campo di un GUID leggibile `Creature-…` o `Vehicle-…` (`nil` altrimenti); mai il GUID intero. Un
  `mobKey` nuovo (anche lo stesso mob ritrovato come `tgt:n` senza GUID) è una voce nuova; al più **61**.
- `q.v[i]`, `q.s[i]`, `q.x[i]`: interi ≥ 0, uno per unità; danno la qualità dei dati del report (SPEC-05 §3.2).
- `sum`: `{ mob, worst, cross, aggro, valid }` (indice del mob principale, stato peggiore del giocatore `S W D U` o
  `nil`, salite a WARNING e DANGER di tutte le unità, prese dell'aggro da parte di un non tank, percentuale di tick con
  dati leggibili): solo per l'elenco; il report lo ricalcola sempre dalle colonne.
- Chiavi sconosciute di una sessione restano come sono (DAT-25).

### 4.2 Colonne compatte dei campioni

Ogni colonna è **una stringa** di campi a larghezza fissa nell'alfabeto in base 62
`0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz` (cifra = posizione − 1, la più significativa prima);
`-` riempie un campo senza valore. La riga `i` di una colonna larga `w` sta ai caratteri `(i − 1)·w + 1 … i·w`: si
legge senza decodificare il resto (M5 cerca un tempo con una ricerca binaria su `t`). Solo caratteri alfanumerici e `-`:
il client li salva senza sequenze di escape.

| Colonna | Larghezza | Contenuto | Intervallo |
|---|---|---|---|
| `t` | 3 | tempo della **lettura** (`observedAt`), in decimi dall'inizio, mai minore del precedente | 0–238 327 (6 h 37 min) |
| `m` | 1 | indice in `mobs` | 1–61 |
| `u` | 1 | indice in `units` | 1–61 |
| `p` | 2 | `scaledPercent` × 10 arrotondato, fra 0 e 3843 (oltre: 3843); `--` senza valore | 0–384,3 % |
| `s` | 1 | codice della lettura (tabella sotto) | |

| Codice `s` | Lettura | `p` | Categoria |
|---|---|---|---|
| `0` `1` `2` `3` | `values`, situazione 0–3 (2 e 3: tiene il mob) | il valore | rilevata |
| `4` | `values`, percentuale leggibile ma situazione no | il valore | rilevata |
| `a` `b` `c` `d` | `state` (*state only*), situazione 0–3 | `--` | rilevata |
| `S` `E` `M` `U` `X` | sconosciuta: `secret`, `error`, `missing`, `no-unit`, altro motivo | `--` | sconosciuta |
| `T` | la lettura è diventata vecchia (`stale`, DAT-12) | `--` | sconosciuta |

Un'unità **assente** dalla lista del mob (motivo `nil`, MON-05) non ha righe: la sua entrata e la sua uscita sono negli
eventi `S` (§4.3). Margine, trend e tempo al superamento **non** si salvano: il report li ricalcola dai valori rilevati,
come calcolati o stimati (DAT-04). Una riga costa 8 caratteri: 30 000 righe (il limite di una sessione) sono circa
240 KB.

### 4.3 Eventi

`ev` è una stringa di record da **12** caratteri, uno per evento, nello stesso alfabeto:

| Campo | Larghezza | Contenuto |
|---|---|---|
| `t` | 3 | tempo dell'evento (`GetTime()` quando l'addon lo riceve), in decimi, mai minore del precedente |
| `k` | 1 | tipo (tabella sotto) |
| `m`, `u`, `v` | 1 ciascuno | mob, unità, seconda unità: indici, `0` = nessuno |
| `a`, `b`, `c` | 1 ciascuno | codici del tipo, `-` = nessuno |
| `n` | 2 | numero in base 62 (0–3843) o due codici, `--` = nessuno |

| `k` | Evento | `m` | `u` | `v` | `a` | `b` | `c` | `n` | Da | Categoria |
|---|---|---|---|---|---|---|---|---|---|---|
| `C` | combattimento iniziato | — | — | — | `1` primo, `2` pull a catena, `r` dopo un reload in combattimento | — | — | — | `COMBAT_STARTED` | rilevata |
| `c` | combattimento finito | — | — | — | — | — | — | — | `COMBAT_ENDED` | rilevata |
| `T` | mob monitorato cambiato | nuovo, `0` nessuno | — | — | senza mob: `n` nessuno, `d` morto, `l` perso; `-` con un mob | — | — | — | `TARGET_CHANGED`, `TargetTracker.status` | rilevata |
| `S` | stato mostrato | mob | unità | — | nuovo `S` `W` `D` `U`, `-` uscita dalla lista | vecchio, `-` entrata | motivo (tabella dei motivi) | — | `STATE_CHANGED`, `row.stateReason` | calcolata in `values`, rilevata in `state` (dalla modalità in vigore, evento `M`) |
| `A` | chi tiene il mob | mob | nuovo | vecchio, `0` il primo | `1` il nuovo è trattato da tank, `0` no | lo stesso per il vecchio | — | — | `AGGRO_CHANGED`, `row.isTank` | rilevata |
| `M` | modalità del monitor | — | — | — | `v` values, `s` state, `n` none | motivo | — | — | `THREAT_MODE_CHANGED` | rilevata |
| `D` | morte | il mob (se è il mob) | l'unità, `0` se è il mob | — | `g` `UNIT_DIED`, `p` `PLAYER_DEAD`, `t` TargetTracker | — | — | — | **[probe P7]** | rilevata |
| `L` | avviso | mob | soggetto | altra unità | tipo `w d a m l p o` (`warning`, `danger`, `aggro`, `margin`, `lost`, `pet`, `other`) | gravità `1`–`3` | `1` silenziato, `0` | categoria e confidenza dell'avviso (codici) | `ALERT_RAISED` | quella dell'avviso |
| `H` | consiglio del Coach | — | giocatore | — | regola: `1`–`7` T1–T7, `8`–`C` D1–D5, `D` A1 | categoria (codice) | confidenza (codice) | — | `COACH_TIP`, solo quando la regola cambia | quella del consiglio |
| `N` | incontro | — | — | — | `s` inizio, `e` fine | `1` riuscito, `0` no (fine) | — | `encounterID` se ≤ 3843 | `ENCOUNTER_START`, `ENCOUNTER_END` **[probe P7]** | rilevata |
| `G` | buco del tick di registrazione | — | — | — | `t` | — | — | durata in decimi (al più 3843) | Recorder | rilevata |
| `X` | sessione interrotta | — | — | — | `o` `PLAYER_LOGOUT` | — | — | — | Recorder | rilevata |
| `Z` | limite raggiunto | — | — | — | `r` righe, `u` unità, `m` mob, `t` tempo, `e` eventi | — | — | — | Recorder | — |

Codici comuni: **categoria** `d` rilevata, `c` calcolata, `e` stimata, `p` prevista, `h` ipotesi, `u` sconosciuta;
**confidenza** `h` alta, `m` media, `l` bassa, `u` sconosciuta. **Motivi** (di `S` e `M`): `-` nessuno, `p` predicted,
`a` aggro, `l` lost-aggro, `b` behind, `o` alone, `g` margin-unknown, `s` state-only, `S` secret, `M` missing, `E`
error, `U` no-unit, `T` stale, `X` altro. Gli stati di `S` sono quelli **mostrati**, dopo isteresi e permanenza
(SPEC-03 §2.4), gli stessi che vedono il monitor e gli avvisi. Taunt e abilità **non** si registrano in M4 (REC-03:
nessun modo affidabile prima di P7). Un evento costa 12 caratteri: 6 000 eventi (il limite) sono circa 72 KB.

### 4.4 Mentre la sessione è aperta

Il recorder scrive righe ed eventi in `buf` (array di numeri e di codici, riusati: `buf.t`, `buf.m`, `buf.u`, `buf.p`
con `-1` per nessun valore, `buf.s`; in `buf.ev` nove posti per evento, `t k m u v a b c n`); ogni **256** righe (`CHUNK`) le
impacchetta in un pezzo per colonna, aggiunto a `parts`, e svuota `buf` (lo stesso per gli eventi). La sessione aperta
sta **già** in `sessions`, quindi un `/reload` o un logout la salvano com'è, con al più 255 righe in forma estesa
(**[probe P12]**). Alla chiusura i pezzi e `buf` diventano una stringa per colonna e `parts` e `buf` spariscono; per una
sessione interrotta lo fa Storage al caricamento seguente (SPEC-05 §2.2).

### 4.5 Requisiti

- **DAT-30** MUST: ogni riga e ogni evento sono ricavati da una lettura o da un evento avvenuti durante lo scontro;
  nessun campione è inventato, interpolato o ricostruito dopo ([ADR 0004](../adr/0004-threat-from-the-unit-threat-api-sampled-in-combat.md)
  punto 4).
- **DAT-31** MUST: un valore sconosciuto si salva come codice con il motivo, mai come numero; un'unità assente dalla
  lista non ha righe.
- **DAT-32** MUST: in una sessione chiusa `#cols.t = 3n`, `#cols.p = 2n`, `#cols.m = #cols.u = #cols.s = n`,
  `#ev = 12·ne`, solo caratteri dell'alfabeto e `-`, `t` non decrescente, indici dentro `units` e `mobs`.
- **DAT-33** MUST: nessun GUID di un giocatore, nessun valore segreto, nessun testo che non sia un nome di unità, di mob
  o di zona; i nomi solo nelle sessioni.

### 4.6 Riferimenti

Controlli al caricamento, sessioni danneggiate, limiti e potatura, stima della dimensione ed eliminazione:
[SPEC-05 §2](SPEC-05-recording-report-replay.md#2-storage-datastoragelua-m43). Come si calcola il report da queste
colonne: [SPEC-05 §3](SPEC-05-recording-report-replay.md#3-report-di-fine-combattimento-datareportlua-m44).
