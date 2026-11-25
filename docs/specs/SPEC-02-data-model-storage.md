# SPEC-02: Modello dati e salvataggio

> Fonte: [specifiche originali](source-specification.md) §5.4, §7.3–§7.5. Impostazioni e schema 1 completati in
> **M1.1** (§3); modello della threat (§1–§2) e schema 2 (§3.5) in **M2.1**; registrazioni da completare in **M4.1**
> (§4).

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
    observedAt = 0,          -- GetTime() della lettura
    source = "detected",     -- detected | calculated | estimated | predicted | hypothesis | unknown
    confidence = "unknown",  -- high | medium | low | unknown
    reason = nil,            -- perché manca: "secret", "nil" (non è nella lista), "error", "missing", "no-unit", "stale"
    stale = false,           -- SPEC-03 §1.5
}
```

Per ogni unità osservata il modello (`Data/ThreatModel.lua`) tiene anche una **riga** derivata, riusata come il record:

```lua
ThreatRow = {
    record = ThreatRecord,   -- l'ultima lettura
    samples = { t = {}, p = {}, head = 0, count = 0 },  -- anello di 32 campioni (observedAt, scaledPercent), SPEC-03 §2.5
    trend = nil,             -- punti al secondo (stimato) o nil = "Insufficient data"
    trendConfidence = "unknown",
    trendSamples = 0,
    margin = nil,            -- punti (calcolato, §2), nil se non calcolabile
    overtakeIn = nil,        -- secondi (previsto), nil se le condizioni di SPEC-03 §2.5 non valgono
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
| `db.schema` | numero di versione dello schema | M1 (schema 1), M2 (schema 2, §3.5) |
| `db.settings` | lingua, aspetto, minimappa (M1); soglie, frequenza, quando mostrare la finestra, ordinamento (M2); avvisi e Coach (M3); limiti delle registrazioni (M4) | M1 → |
| `db.sessions` | registrazioni (§4) | M4 |
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

Fissato in **M2.1**, realizzato da **M2.6** (fino ad allora `ThreatState.DEFAULTS` e i predefiniti dello Scanner
valgono da soli). Lo schema dell'account passa a **2** con la tabella `settings.monitor`; quello del personaggio resta
1. La migrazione `Config.migrations.account[2]` non fa nulla (i predefiniti aggiungono le chiavi che mancano), ma
esiste e ha il suo test (DAT-20).

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

## 4. Sessioni registrate **[da completare in M4.1]**

```lua
Session = {
    id = "s-<time>-<n>", startedAt = 0, endedAt = nil, complete = false,
    zone = nil, instanceType = nil,          -- "none", "party", "raid"…
    mobs = { [mobKey] = { name, guid } },    -- mobKey stabile per sessione
    units = { [unitKey] = { name, role } },   -- nomi del gruppo, solo in locale (Q15)
    samples = { ... },                       -- colonne compatte: t, unitKey, mobKey, pct, situation, src
    events = { ... },                        -- t, tipo, dati: combat start/end, target change, death, threshold, tank change
    stats = { ... },                         -- riepilogo calcolato a fine scontro
}
```

- Timestamp relativi all'inizio dello scontro; identificativo univoco; nessun campione inventato per i buchi (i buchi
  sono registrati come tali).
- Limiti predefiniti proposti: 25 sessioni, circa 2 MB stimati in tutto, le più vecchie eliminate per prime (Q8).
- Sessioni incomplete (reload, disconnessione) chiuse al caricamento successivo e marcate `complete = false`.
- Eliminazione di una o di tutte le registrazioni dall'interfaccia.
