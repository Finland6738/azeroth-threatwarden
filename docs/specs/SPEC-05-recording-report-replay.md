# SPEC-05: Registrazione, report, timeline e replay

> Fonte: [specifiche originali](source-specification.md) §5.3, §5.4, §7.4, §7.5, §9, §10, §13. §1–§3 completati in
> **M4.1** (prima del probe M0, come M2 e M3: decisione D7), con il formato dei dati in
> [SPEC-02 §3.7 e §4](SPEC-02-data-model-storage.md#4-sessioni-registrate-schema-4-m4) e la decisione di architettura
> in [ADR 0016](../adr/0016-recordings-are-the-monitors-readings-in-compact-columns.md); §4–§5 (timeline e replay)
> completati in **M5.1**, con i moduli e i test per step in §9–§10 e la decisione di architettura in
> [ADR 0017](../adr/0017-timeline-and-replay-are-views-over-the-recorded-session.md).

## 0. Principi

- **Si registra ciò che il monitor ha letto.** Il recorder non chiama le funzioni della threat: legge le righe di
  `Data/ThreatModel.lua` e ascolta gli eventi del Bus (`STATE_CHANGED`, `AGGRO_CHANGED`, `TARGET_CHANGED`…); le sole
  funzioni del gioco che usa attraverso Compat sono la zona, il tipo d'istanza, i nomi e le morti. Quindi una sessione
  dice esattamente quello che il giocatore ha visto, con le stesse categorie (ADR 0003), e nulla che il monitor non
  sapesse.
- **Nulla si ricostruisce dopo** (REC-05, ADR 0004): un buco resta un buco, con il suo motivo.
- **I tre esiti del probe** ([SPEC-03 §1.1](SPEC-03-threat-monitor-ui.md#11-tre-esiti-del-probe-tre-modalità)) valgono
  anche qui, per riga e nel tempo (la modalità può cambiare a metà scontro, evento `M`):

| Esito | Che cosa si registra | Che cosa dice il report |
|---|---|---|
| **values** | percentuali, situazioni, stati calcolati dalle soglie, chi tiene il mob, avvisi | tutte le metriche di §3.2 |
| **state only** | situazioni 0–3 senza percentuali, stati del gioco, chi tiene il mob | tutto tranne le percentuali (*Not available*); stati e salite sono quelli del gioco, senza soglie |
| **nothing readable** | inizio e fine, mob, morti, avvisi assenti, righe con il motivo (`secret`…) solo quando il motivo cambia | durata, mob, combattimenti, morti, qualità dei dati; ogni metrica della threat *Not available* con il motivo |

## 1. Recorder (`Data/Recorder.lua`, `Data/Session.lua`, M4.2)

### 1.1 Quando si registra

Una sessione si apre a `COMBAT_STARTED` solo se **tutte** queste condizioni valgono in quel momento; altrimenti non si
registra quel combattimento, e `/atw debug` dice il primo motivo che manca:

| # | Condizione | Motivo in `/atw debug` |
|---|---|---|
| 1 | gli interruttori `monitor` e `recording` sono accesi (`Core/Features.lua`) | `switch` |
| 2 | il client è riconosciuto (ARC-01: non in modalità diagnostica) | `client` |
| 3 | `settings.recording.enabled` è vero | `off` |
| 4 | `settings.recording.when`: `group` = in un gruppo (`IsInGroup`) **o** in un'istanza (tipo diverso da `none`); `instance` = in un'istanza; `always` = sempre ([Q16](SPEC-09-risks-open-questions.md)) | `when` |
| 5 | la demo non è attiva (`Demo.IsActive()`, [SPEC-03 §5.2](SPEC-03-threat-monitor-ui.md#52-modalità-demo-atw-demo-m26)) | `demo` |
| 6 | i dati dell'account non sono in sola lettura (`Config:IsReadOnly("account")`, §2.6) | `read-only` |

Le condizioni si guardano **all'apertura**: entrare in un gruppo a metà scontro non apre una sessione, uscirne non la
chiude; la demo avviata a metà chiude la sessione aperta come una fine del combattimento (§1.2). Cambiare
`settings.recording.enabled` a falso durante una sessione la chiude allo stesso modo. Con l'interruttore `recording`
spento il recorder non registra ascoltatori né eventi del gioco e non scrive nulla (ADR 0014).

- **REC-01** MUST: una sessione si apre a `COMBAT_STARTED` (da `PLAYER_REGEN_DISABLED`, o dal giocatore già in
  combattimento a `PLAYER_ENTERING_WORLD` dopo un `/reload`, **[probe P12]**) quando valgono le condizioni di §1.1, e si
  chiude a fine combattimento più `END_DELAY` (§1.2).

### 1.2 Inizio, pull a catena e fine

1. **Apertura** a `COMBAT_STARTED`: nuova `Session` (SPEC-02 §4.1) con `started`, `id`, `group`, `zone`, `inst`,
   `diff` e `rec` letti in quel momento; la sessione si aggiunge **subito** in fondo a `sessions` con `state = "open"`
   (così un `/reload` la salva, §1.6); evento `C` con `a = 1`; il tick di registrazione parte (§1.3); il recorder si
   dichiara consumatore dello Scanner (`ThreatScanner.Want("recorder", true)`), così la threat si legge anche con la
   finestra chiusa; se c'è già un mob monitorato, evento `T` con il mob. `SESSION_STARTED(id)` sul Bus.
2. **Fine del combattimento** a `COMBAT_ENDED`: evento `c`, il tick si ferma (si ferma da solo: `combat = true`), il
   consumatore si toglie, parte un timer di `Recorder.END_DELAY` = **5 s**.
3. **Pull a catena**: un `COMBAT_STARTED` prima della fine del timer **continua** la stessa sessione: evento `C` con
   `a = 2`, il tick e il consumatore riprendono. La pausa resta visibile come la distanza fra `c` e `C` (non è un buco:
   fuori dal combattimento non si legge nulla).
4. **Chiusura** allo scadere del timer: `dur` (dal primo `C` all'ultimo `c`), `fight` (somma dei periodi `C…c`), le
   colonne si uniscono (SPEC-02 §4.4), `state = "complete"`, `ended = "combat"`, il riepilogo `sum` (§3.4); poi la
   sessione si tiene solo se `fight ≥ LIMITS.minFight` (**3 s**) **e** ha almeno una riga di campioni; altrimenti si
   toglie da `sessions` (contata come *scartata* in `/atw debug`, nessun avviso). Poi la potatura (§2.4).
   `SESSION_ENDED(id, state)` con `state` = `complete` o `dropped`, e `SESSIONS_CHANGED()` se l'elenco è cambiato.
5. **Chiusura anticipata**, come al punto 4 senza aspettare il timer: la demo si avvia, `settings.recording.enabled`
   diventa falso, l'interruttore viene spento da un test. In combattimento prima si scrive l'evento `c`.

- **REC-04** MUST (doppioni): al più **una** sessione aperta (`Recorder.current`); un `COMBAT_STARTED` con la sessione
  aperta e il combattimento in corso non fa nulla; un `COMBAT_ENDED` senza combattimento in corso non fa nulla; un `id`
  già presente in `sessions` riceve un suffisso (`-b`, `-c`…).

### 1.3 Campioni: il tick di registrazione

`Scheduler.Start("record", hz, tick, { combat = true })` con `hz = settings.recording.rate` (1–5, **2** proposto,
[Q16](SPEC-09-risks-open-questions.md)). Una frequenza più alta di quella del monitor non aggiunge nulla (le letture
nuove arrivano solo al ritmo dello Scanner) e non scrive doppioni. A ogni tick, all'istante `now`:

1. **Buco del tick**: se dal tick precedente della stessa sessione sono passati più di `max(3 / hz, 1 s)` in
   combattimento (un caricamento, un blocco del client), evento `G` con la durata.
2. **Senza mob monitorato** (`ThreatModel.mobKey == nil`): nessuna riga, nessun contatore (l'evento `T` lo dice già).
3. Per ogni riga presente del modello (`row.present`, nell'ordine delle righe, al più le unità che lo Scanner legge):
   - l'indice `u` dell'unità (una voce nuova in `units` alla prima volta; oltre 61 la riga si salta e l'evento `Z`
     con `a = u` si scrive una volta);
   - la lettura è **fresca** se non è vecchia secondo la regola di DAT-12 (`ThreatModel.IsStale(record, now)`, la stessa
     funzione del modello, nuova in M4.2); il **codice** `s` viene dalla modalità, dalla situazione e dal motivo del
     record (SPEC-02 §4.2), `T` se non è fresca;
   - **contatori** (`q`): fresca in `values` → `q.v[u] + 1`; fresca in `state` → `q.s[u] + 1`; altrimenti
     `q.x[u] + 1`. Un tick conta ogni unità presente una volta: è la base della qualità dei dati (§3.2);
   - **riga**: una riga con un numero (codici `0`–`4`) si scrive per ogni **lettura nuova** (`observedAt` maggiore
     dell'ultimo scritto per quell'unità), con `t` = `observedAt`; una riga senza numero (codici `a`–`d`, `S`, `E`, `M`,
     `U`, `X`, `T`) si scrive **solo quando il codice cambia** rispetto all'ultima riga dell'unità sullo stesso mob, con
     `t` = `observedAt` (o `now` per `T`). Una riga ripetuta non direbbe nulla di nuovo: il tempo lo danno i contatori e
     gli eventi.
4. **Limite delle righe**: alla riga numero `LIMITS.rows` (**30 000**) campioni e contatori si fermano, `trunc = t` ed
   evento `Z` con `a = r`; gli eventi continuano fino al loro limite. Lo stesso se `t` supererebbe 238 327 (`a = t`).

- **REC-02** MUST: campioni solo in combattimento, alla frequenza della registrazione, sulle unità che il monitor legge
  (al più 40, `maxUnits`) e sul mob monitorato (uno in M4; M7 ne aggiungerà se P5 lo consente), con i limiti di §1.7.
- **REC-06** MUST: una lettura già scritta non si scrive di nuovo (stesso `observedAt`); una lettura più vecchia
  dell'ultima scritta per l'unità si ignora (fuori ordine); `t` non decresce mai.

### 1.4 Eventi

Il recorder traduce in record di SPEC-02 §4.3 gli eventi del Bus e pochi eventi del gioco, con `t` = `Compat.Now()` alla
ricezione (mai minore del precedente). Solo mentre una sessione è aperta, e per `S`, `A`, `T`, `L` solo durante un
periodo di combattimento:

| Fonte | Evento | Note |
|---|---|---|
| `COMBAT_STARTED`, `COMBAT_ENDED` (Bus) | `C`, `c` | §1.2 |
| `TARGET_CHANGED(mobKey)` (Bus) | `T` | con il mob: una voce in `mobs` alla prima volta (nome e classificazione da `Compat.Unit` sul token del mob, `npc` dal GUID letto da TargetTracker); senza: lo stato di `TargetTracker.status` (`none`, `died`, `lost`) |
| `STATE_CHANGED(unitKey, mobKey, old, new)` (Bus) | `S` | con `row.stateReason` della riga; un'unità che non ha ancora una voce la riceve |
| `AGGRO_CHANGED(mobKey, unitKey, oldUnitKey)` (Bus) | `A` | con `row.isTank` delle due righe |
| `THREAT_MODE_CHANGED(mode, reason)` (Bus) | `M` | anche all'apertura, con la modalità in vigore |
| `ALERT_RAISED(alert)` (Bus) | `L` | si copia subito (l'avviso viene da un anello riusato, SPEC-04 §5); demo esclusa (non si registra in demo) |
| `COACH_TIP(tip)` (Bus) | `H` | solo quando l'`id` della regola cambia (non quando cambiano solo i numeri); `nil` non si scrive |
| `UNIT_DIED(unitGUID)` (gioco) | `D` con `a = g` | solo se il GUID è leggibile e corrisponde a un'unità osservata (`"unit:" .. GUID`) o al mob monitorato **[probe P7]** |
| `PLAYER_DEAD` (gioco) | `D` con `a = p` | il giocatore |
| `TargetTracker.status = "died"` | `D` con `a = t` | il mob, insieme a `T` con `a = d` |
| `ENCOUNTER_START`, `ENCOUNTER_END` (gioco) | `N` | id e riuscita; mai il nome **[probe P7]** |
| `PLAYER_LOGOUT` (gioco) | `X` | §1.6 |

Due eventi uguali (stesso tipo e stessi campi) nello stesso decimo di secondo si scrivono una volta. Taunt, abilità e il
combat log non si usano (REC-03, [ADR 0004](../adr/0004-threat-from-the-unit-threat-api-sampled-in-combat.md)): se P7
dimostrerà un modo affidabile, M0.7 aggiungerà un tipo di evento con un nuovo schema.

- **REC-03** MUST: gli eventi della tabella, quando l'addon li riceve; nessun taunt né abilità in M4; un evento che non
  arriva (P7) semplicemente manca, e il report non dice mai *nessuno* senza dire *registrato* (§3.2).

### 1.5 Buchi, doppioni, ordine

- Un **buco** è sempre uno di questi, e nessuno si riempie: righe `T` (lettura vecchia) e righe con un motivo (lettura
  sconosciuta), per unità; eventi `M` verso `none` (nulla di leggibile), per tutto il mob; eventi `T` senza mob
  (nessun mob monitorato); eventi `G` (il tick non è girato). Il report li somma come tempo sconosciuto (§3.3).
- Doppioni di letture: REC-06. Doppioni di eventi: §1.4. Doppioni di sessioni: REC-04.
- Eventi fuori ordine (un `STATE_CHANGED` che arriva dopo il `TARGET_CHANGED` di un altro mob): il record porta il
  `mobKey` dell'evento, non quello corrente, quindi va al mob giusto; un mob senza voce ne riceve una.
- Il mob che scompare (`lost`), che muore (`died`), il target sostituito: eventi `T` (e `D`); le righe di prima
  restano del mob di prima.
- Un'unità che cambia chiave a metà scontro (GUID prima segreto e poi leggibile, `tok:` → `unit:`) riceve una seconda
  voce: due righe nel report con lo stesso nome (**[probe P9]**).

### 1.6 Reload, logout e disconnessione

| Momento | Che cosa fa il recorder | Che cosa trova Storage al caricamento (§2.2) |
|---|---|---|
| `PLAYER_LOGOUT` in combattimento (anche al `/reload`, **[probe P12]**) | evento `X`, `stamp = true`, `state = "interrupted"`; nient'altro (nessun lavoro pesante al logout) | la sessione interrotta: la completa (unisce i pezzi), `ended` = `reload` o `login` da `PLAYER_ENTERING_WORLD` (`isReloadingUi`, `isInitialLogin`), `unknown` se nessuno dei due |
| `PLAYER_LOGOUT` durante `END_DELAY` | la sessione è chiusa come al §1.2 punto 4 ma senza unire i pezzi (`state = "complete"`, `ended = "combat"`) | la completa (unisce i pezzi, calcola `sum`) |
| Disconnessione o crash | nulla (il client non salva) | niente, o l'ultima versione salvata: una sessione `open` senza `stamp` diventa `interrupted` con `ended = "unknown"` |
| `/reload` in combattimento, dopo | — | se il giocatore è ancora in combattimento, Init emette `COMBAT_STARTED` (P12) e si apre una **nuova** sessione con `C` `a = r` e `after` = l'`id` della sessione interrotta più recente, se finita da meno di `LIMITS.link` (**120 s** di `GetServerTime`) |

- **REC-04** MUST (incomplete): logout, `/reload` e disconnessione non lasciano mai una sessione `open` dopo il
  caricamento; una sessione interrotta si tiene se ha almeno una riga, con il motivo; nulla si afferma dopo l'ultimo
  record scritto (il report dice *Recorded until m:ss*).
- Se P12 dimostra che le SavedVariables non si scrivono al `/reload` in combattimento, la sessione in corso si perde:
  la pagina del manuale *Combat Reports* lo dice e REC-04 resta vero per ciò che si salva.

### 1.7 Limiti di una sessione (`Storage.LIMITS`)

| Limite | Valore | Dopo |
|---|---|---|
| `rows` | 30 000 righe (circa 240 KB; 2 Hz × 40 unità per oltre 6 minuti) | campioni e contatori si fermano, `Z r` |
| `events` | 6 000 eventi (circa 72 KB) | l'evento numero 6 000 è `Z e`, poi nessun altro |
| `units`, `mobs` | 61 ciascuno (l'alfabeto di un carattere) | l'unità o il mob nuovi non si registrano, `Z u` / `Z m` una volta |
| `minFight` | 3 s di combattimento e almeno una riga | sotto: la sessione si scarta alla chiusura |
| `link` | 120 s | il collegamento `after` di §1.6 |
| `CHUNK` | 256 righe o eventi | impacchettamento (SPEC-02 §4.4) |
| durata | 6 h 37 min (`t` a 3 caratteri) | `Z t` |

In M4.2 la tabella è `Session.LIMITS` di `Data/Session.lua` (il recorder ne ha bisogno prima di Storage); il
`Storage.LIMITS` di M4.3 è la stessa tabella, con un solo posto. Una sessione non supera quindi circa **320 KB** stimati, sotto il minimo di `maxKB` (512 KB): la potatura (§2.4) può
sempre farle posto.

### 1.8 Costo

- Il tick di registrazione non chiama funzioni del gioco e non alloca dopo il riscaldamento (ARC-06): scrive numeri in
  `buf`, riusato; alloca solo una voce di `units` o `mobs` nuova e, ogni 256 righe, i cinque pezzi di stringa (circa
  2 KB). Gli eventi del Bus allocano solo all'impacchettamento.
- **Costo indiretto**: con la registrazione accesa lo Scanner legge in ogni combattimento registrato anche a finestra
  chiusa (consumatore `recorder`), quindi il costo del monitor di [SPEC-01 §5.1](SPEC-01-platform-architecture.md#51-il-costo-di-un-tick-del-monitor-misura-offline-di-m27)
  vale anche lì. **[probe P10]**: se il budget non regge, la registrazione segue la frequenza del monitor e non il
  contrario.
- **Budget** (fissato in M4.6, [SPEC-01 §5.1](SPEC-01-platform-architecture.md#51-il-costo-di-un-tick-del-monitor-misura-offline-di-m27),
  controllato da `Tests/long/test_monitor_budget.lua`): il tick di registrazione a 40 unità entro 36 000 istruzioni in
  media e 90 000 nel tick che impacchetta, entro 1 024 byte con i valori e 48 altrimenti. La proposta di M4.1 (10 % di
  un tick del monitor) è sostituita: al secondo, a 2 Hz, il tick pesa circa il 7 % del monitor a 5 Hz.
- L'impacchettamento (M4.6) passa da una sola tabella riusata e dalle stringhe già pronte di una e due cifre: alloca
  solo le stringhe unite (prima circa 60 KB a pacco, ora circa 3 KB).
- Unire le colonne alla chiusura, controllare le sessioni al caricamento e costruire un report sono lavori fuori dal
  tick: la chiusura avviene sempre fuori dal combattimento (dopo `END_DELAY`), il report si costruisce a fette (§3.4)
  (ARC-07).

## 2. Storage (`Data/Storage.lua`, M4.3)

### 2.1 Dove e come

Le sessioni stanno in `AzerothThreatwardenDB.sessions` (schema 4 dell'account, [SPEC-02 §3.7](SPEC-02-data-model-storage.md#37-schema-4-m4-registrazione-e-sessioni)),
in colonne compatte (SPEC-02 §4), la più vecchia prima. Storage ne è l'unico padrone dopo il caricamento di Config:
nessun altro modulo scrive in `sessions` tranne il recorder sulla sessione aperta.

### 2.2 Caricamento

A `CONFIG_LOADED`, con l'interruttore `recording` acceso, Storage passa ogni voce di `sessions`, nell'ordine:

1. **Controllo veloce** (con le funzioni di stringa del client, senza decodificare): è una tabella; `id` è una stringa
   (al più 40 caratteri), `started` un numero, `state` uno di `open`, `complete`, `interrupted`; `units` e `mobs` array
   di tabelle (al più 61); `n` e `ne` interi entro i limiti; le colonne e `ev` sono stringhe della lunghezza di DAT-32
   con i soli caratteri dell'alfabeto, oppure — per una sessione `open` o `interrupted` non ancora completata — `parts`
   e `buf` hanno la forma di SPEC-02 §4.4. Chi non passa è **danneggiata** (punto 4).
2. **Sessione `open` o interrotta da completare**: pezzi e `buf` si uniscono in una stringa per colonna (`buf` ha al più
   255 righe), `n` e `ne` si ricontano, `state = "interrupted"`, `ended` resta da assegnare a `ENTERING_WORLD`
   (`reload` o `login`; `unknown` se l'evento non lo dice o se `stamp` è falso); senza righe si toglie. `sum` si calcola
   (§3.4) appena il giocatore è fuori dal combattimento.
3. **Doppioni** di `id`: la seconda riceve il suffisso (REC-04).
4. **Danneggiata**: si toglie da `sessions` e si mette da parte con `Config:SetAside("account.sessions", value)` (una
   voce di `corrupt` con il tipo `session` e la sola intestazione nella copia limitata di SPEC-02 §3.4: mai le colonne);
   le altre sessioni e le impostazioni non cambiano. Si annota in `Config.issues` (*one recording was damaged and set
   aside*, senza nomi) e `/atw debug` la conta.
5. **Potatura** (§2.4), poi `SESSIONS_CHANGED()`.

Il controllo **profondo** (`t` non decrescente, indici dentro `units` e `mobs`, codici validi) avviene alla
decodifica (§3.4): una sessione che lo fallisce si mette da parte come al punto 4 appena fuori dal combattimento, e il
report dice *This recording is damaged*.

- **STO-01** MUST: una sessione danneggiata non blocca mai l'addon né le altre sessioni (fonte §7.5); va in `corrupt`
  (al più 5 voci, la più vecchia esce) senza colonne né nomi oltre a quelli dell'intestazione copiata.

### 2.3 Schema 4 e migrazione 3 → 4

Lo schema dell'account passa da 3 a **4** ([SPEC-02 §3.7](SPEC-02-data-model-storage.md#37-schema-4-m4-registrazione-e-sessioni)):
il passo `Config.migrations.account[4]` non fa nulla, perché i predefiniti aggiungono `settings.recording` e
`sessions = {}`; ha il suo test che parte dai dati dello schema 3 (con e senza una chiave `sessions` già presente, che
resta com'è e la controlla Storage). Le migrazioni girano su una copia (SPEC-02 §3.4): le colonne sono stringhe, che Lua
copia per riferimento, quindi copiare 2 MB di sessioni costa poco. Un passo futuro che cambia il formato di una
sessione (M5 o M6) è un nuovo schema con la sua migrazione, che converte le sessioni o le mette da parte, mai in
silenzio.

### 2.4 Limiti, potatura e stima della dimensione

- **Stima** di una sessione: `Config.EstimateSize(session)` (le stringhe contano la loro lunghezza, quindi la stima non
  attraversa le colonne), tenuta in memoria e rifatta alla chiusura e al caricamento; il totale è la somma. È una
  **stima** (categoria stimata, ADR 0003): il file scritto dal client è un po' più grande per i rientri e le chiavi, e
  una sessione aperta con `buf` pesa di più nel file. Si mostra *about 640 KB*.
- **Potatura** dopo ogni chiusura, al caricamento e quando `maxSessions` o `maxKB` cambiano: finché il numero delle
  sessioni supera `settings.recording.maxSessions` (**25**) o il totale stimato supera `settings.recording.maxKB`
  (**2048 KB**), si toglie la sessione chiusa più vecchia (per `started`, poi per posizione). La sessione aperta conta
  nel totale ma non si toglie mai. Ogni sessione tolta si conta (*pruned*) in `/atw debug`.
- **STO-02** MUST: dopo ogni chiusura e ogni caricamento valgono i due limiti, salvo la sessione aperta; le più vecchie
  escono per prime (ADR 0005 punto 4, [Q8](SPEC-09-risks-open-questions.md)).

### 2.5 Eliminare una o tutte le registrazioni

`Storage.Delete(id)` e `Storage.DeleteAll()`: tolgono una sessione chiusa o tutte quelle chiuse; rifiutano (restituendo
`false` e il motivo) la sessione aperta (`recording`), un `id` sconosciuto (`unknown`) e i dati in sola lettura
(`read-only`); emettono `SESSIONS_CHANGED()`. L'eliminazione è definitiva: l'interfaccia chiede una conferma (un secondo
clic entro 8 s, come *Reset settings*) e il manuale lo dice. *Reset settings* e `/atw reset` non toccano le sessioni.

- **STO-03** MUST: dopo `Delete` o `DeleteAll` e un `/reload` le sessioni eliminate non ci sono più e i loro nomi non
  sono più nelle SavedVariables (fonte §10: funzione per cancellare le registrazioni).

### 2.6 Sola lettura

Con l'account in sola lettura (schema più nuovo, o migrazione fallita: SPEC-02 §3.4) il recorder non apre sessioni
(motivo `read-only`), Storage non completa, non mette da parte, non pota e non elimina; la scheda Reports mostra le
sessioni che riesce a leggere (quelle che non passano il controllo veloce si nascondono e si contano, senza toglierle)
e dice *Saved data comes from a newer version: recordings are read-only*.

### 2.7 Interfaccia di Storage

`Storage.List()` (intestazioni, la più recente prima, mai le colonne; da M6.3 con `enemy`, il nemico principale di `sum` come `{ name, class, npc }`, e `role`, il ruolo registrato del giocatore, per il confronto di [SPEC-06 §2](SPEC-06-analytics-export.md#2-confronto-e-aggregati-datacomparelua-m63)), `Storage.Get(id)`, `Storage.Usage()`
(`count`, `bytes`, `maxSessions`, `maxKB`, `pruned`, `damaged`, `dropped`), `Storage.Delete(id)`, `Storage.DeleteAll()`,
`Storage.Decode(id)` (le colonne di una sessione come array di numeri e codici, per il report e per M5; una alla volta
in memoria). Il recorder usa `Storage.Add(session)` all'apertura e `Storage.Closed(session)` alla chiusura (potatura e
`SESSIONS_CHANGED`).

## 3. Report di fine combattimento (`Data/Report.lua`, M4.4)

### 3.1 Regole

- **REC-10** MUST: ogni metrica è calcolata **solo** dalle righe e dagli eventi della sessione (si può rifare dagli
  stessi dati con lo stesso risultato) e porta la sua categoria (ADR 0003, DAT-04). Quando non si può dire, la riga
  dice uno di questi tre, sempre con il motivo nel tooltip:
  - **Not available** (*Non disponibile*): il client non l'ha mai dato in questa sessione (percentuali in *state only*;
    tutto ciò che riguarda la threat quando nulla era leggibile);
  - **Insufficient data** (*Dati insufficienti*): il dato c'era ma troppo poco: meno di `Report.MIN_ROWS` = **3** righe
    utili per una metrica di unità, o meno di 1 s di stato noto;
  - **Unknown** (*Sconosciuto*): un nome o un mob non leggibile (si mostra il token o *Unknown mob*).
- **REC-11** MUST: il report non attribuisce cause e in M4 **non mostra ipotesi**: accanto a una perdita dell'aggro c'è
  al più un fatto calcolato (*+24 points in the 3 s before*), mai *because*, *caused by* o il nome di un'abilità. Le
  parole si provano con la stessa prova di SPEC-04 §2.4 (WR-01–WR-07) sulle chiavi `REPORT_*`.
- **Copertura**: quando un'unità ha avuto tempo sconosciuto (righe con un motivo, `T`, modalità `none`, `G`) mentre era
  nella lista, i suoi conteggi e i suoi tempi sono **limiti inferiori**: categoria stimata, prefisso `≥` e il tempo
  sconosciuto accanto (*≥ 12 s in Warning · 8 s unknown*).
- **Sessione interrotta**: ogni metrica vale fino all'ultimo record; la testata dice *Interrupted (reload)* e
  *Recorded until m:ss*; la durata è *≥ m:ss*. **Sessione troncata**: le metriche dai campioni valgono fino a `trunc`
  e lo dicono; quelle dagli eventi fino al limite degli eventi.

### 3.2 Metriche

Ogni metrica nelle tre modalità (§0). *Detected* = letta (o fatto dell'addon), *calculated* = derivata da dati letti.

| Metrica | Come si calcola | Categoria | values | state only | nulla leggibile |
|---|---|---|---|---|---|
| **Durata** | `dur` (dal primo `C` all'ultimo `c`); *in combat* = `fight`, con il numero dei pull se più di uno | rilevata | sì | sì | sì |
| **Mob principale** | il mob con più righe (a parità, il primo monitorato); poi *+N other mobs*; la classificazione; il risultato dell'incontro se c'è `N` | rilevata | sì | sì | il mob con più tempo monitorato (dagli eventi `T`), il nome se leggibile |
| **Tank osservati** | le unità che hanno tenuto il mob (eventi `A`) con il tempo in cui l'hanno tenuto nei periodi di combattimento, segnando i tank designati (`role = TANK`) | rilevata (chi), calcolata (tempo) | sì | sì | *Not available* (*Unknown tank*) |
| **Cambi di tank** | eventi `A` con il vecchio e il nuovo trattati da tank (`a = b = 1`): elenco con l'ora | rilevata | sì | sì | *Not available* |
| **Perdite dell'aggro** | eventi `A` con il nuovo **non** tank (`a = 0`): chi l'ha preso, da chi, l'ora; in `values`, se l'unità ha almeno 2 righe con un numero nei 3 s prima, *+N points in the 3 s before* (calcolato) | rilevata | sì | sì, senza i punti | *Not available* |
| **Superamenti di soglia** per unità | eventi `S` che **entrano** in WARNING o DANGER: da SAFE, da WARNING (a DANGER), dall'ingresso nella lista, da UNKNOWN solo sopra l'ultimo stato noto (la regola degli avvisi, SPEC-04 §1.1); conteggi separati WARNING e DANGER | calcolata (stimata con copertura parziale) | dalle soglie `rec.warning` e `rec.danger`, che il report scrive | gli stati del gioco, e la riga lo dice (*game states*) | *Not available* |
| **Tempo in WARNING e DANGER** per unità | somma degli intervalli fra un `S` e il successivo della stessa unità e dello stesso mob, dentro i periodi di combattimento e finché il mob è quello (§3.3); il tempo UNKNOWN a parte | calcolata (stimata con copertura parziale) | sì | sì (*game states*) | *Not available* |
| **Percentuale massima osservata** per unità | il massimo di `p` sulle righe con un numero, con l'ora e il mob: *highest recorded*, perché fra due letture poteva essere più alta | rilevata | sì, *Insufficient data* sotto 3 righe con un numero | *Not available* | *Not available* |
| **Qualità dei dati** (*percentuale di campioni validi*) | dai contatori: `Σq.v`, `Σq.s`, `Σq.x` sul totale dei tick (*Values 82 % · State only 0 % · Unknown 18 %*), per la sessione e per unità; poi i buchi: tempo con modalità `none`, senza mob, eventi `G` | calcolata | sì | sì | sì (*Unknown 100 %* con il motivo prevalente: *secret*…) |
| **Morti** | eventi `D`, con l'ora; senza eventi *No death recorded* (mai *no deaths*) **[probe P7]** | rilevata | sì | sì | sì |
| **Avvisi** | eventi `L`: quanti per tipo e quanti silenziati | rilevata | sì | sì | nessuno (gli avvisi non scattano senza stati) |

Il **riepilogo per unità** (una riga per voce di `units`, prima il giocatore, poi i tank designati, poi per numero di
superamenti) mostra: ruolo, superamenti WARNING e DANGER, tempo in WARNING e DANGER, percentuale massima, prese
dell'aggro, qualità dei dati. Un'unità con meno di 3 righe utili mostra *Insufficient data* nella riga intera.

### 3.3 Periodi e intervalli

- **Periodi di combattimento**: da ogni `C` al `c` seguente; un `C` senza `c` (sessione interrotta) fino all'ultimo
  record. Fuori dai periodi non si conta nulla.
- **Periodi di mob**: da un `T` con il mob al `T` seguente. Uno stato vale dal suo `S` fino al primo fra: l'`S`
  seguente della stessa unità sullo stesso mob, la fine del periodo di mob, la fine del periodo di combattimento.
- **Tempo sconosciuto** di un'unità: stato UNKNOWN, più il tempo in cui la modalità era `none` mentre l'unità era
  nella lista, più i buchi `G`. Un tick salta un'unità solo con un buco: non si stima mai uno stato fra due eventi.
- **Chi tiene il mob**: dal suo `A` all'`A` seguente dello stesso mob, nei periodi di combattimento.

### 3.4 Costruzione, riepilogo e cache

- `Report.Build(id, done)` decodifica la sessione (`Storage.Decode`, con il controllo profondo di §2.2) e calcola a
  **fette** di `Report.SLICE` = 5 000 righe o eventi per frame (`Compat.After(0)`), dentro o fuori dal combattimento;
  `done(report)` riceve una tabella di righe `{ key, value, category, reason, args }` per l'interfaccia; il risultato
  di un'unica passata e quello a fette sono uguali (test). Il report si tiene in memoria per l'ultima sessione aperta
  nella scheda, mai salvato; si butta a `SESSIONS_CHANGED` se quella sessione non c'è più.
- `Report.Summary(session)` calcola `sum` (SPEC-02 §4.1) alla chiusura e al completamento di una sessione interrotta,
  sempre fuori dal combattimento, con le stesse funzioni del report.

### 3.5 Avviso di fine scontro

Con `settings.recording.notice` acceso (spento di predefinito, [Q16](SPEC-09-risks-open-questions.md)) e l'interruttore
`reports`: quando una sessione si chiude come `complete` e si tiene, se la finestra è visibile la striscia del Coach
mostra per 8 s *Fight recorded · 1:42 · 3 threshold crossings* con *Open report* (un clic apre la scheda Reports su
quella sessione). Mai chat, mai un suono, mai la finestra aperta da sola; una sessione scartata o interrotta non dà
avviso.

### 3.6 La scheda Reports e la card Recording (M4.5)

- **Scheda Reports** (disposizione ampia, [SPEC-03 §4.4](SPEC-03-threat-monitor-ui.md#44-schede); solo con
  l'interruttore `reports`): testata *12 recordings · about 640 KB of 2 MB*; l'elenco, la più recente prima, con data e
  ora, zona, mob principale, durata, i distintivi *Interrupted*, *Limit reached*, *Continues* (`after`) e lo stato peggiore
  del giocatore da `sum`; un clic apre il report sotto o accanto (§3.2), che si costruisce a fette con *Building
  report…*; *Delete* con conferma. Vuota: *No recordings yet* e, se la registrazione è spenta o non scatta, il motivo
  (*Recording is off*, *Recording only in a group or an instance*, *read-only*). `/atw reports` apre la scheda.
- **Card Recording** (Settings, dopo *Alerts* e prima di *Reset*; solo con l'interruttore `recording`): *Record fights*
  (interruttore), *When* (segmentato *In a group or instance · In instances · Always*), *Recording rate* (cursore
  1–5 Hz), *Keep at most* (cursore 5–100 sessioni), *Size limit* (cursore 0,5–8 MB, a passi di 0,5), *Notice after a
  fight* (interruttore), la riga d'uso con la stima, *Delete all recordings* con conferma; i cursori si salvano al
  rilascio; in sola lettura come le altre card (*Not saved*). Una nota dice che i nomi dei compagni restano solo su
  questo computer ([Q15](SPEC-09-risks-open-questions.md)).
- **Anteprime** (ADR 0013, dati inventati): `reports-list`, `report-values`, `report-state`, `report-unknown`,
  `settings-recording`.

**Realizzato in M4.5** (`UI/Reports.lua`, la card in `UI/Settings.lua`, `/atw reports`):

- Il report si apre **sotto** l'elenco: con un report aperto l'elenco tiene tre righe e scorre, il resto è del report
  (card di testa con *Delete recording* e *Close report*, card *Fight*, una card per unità; un'unità senza dati ha una
  nota con il motivo e la sola qualità). Un solo punto: `Reports.ROWS_WITH_REPORT`.
- Ogni metrica ha un indicatore con la categoria (*stimato* nel colore di avviso, *sconosciuto* attenuato); il tooltip
  dice categoria, che cosa vuol dire, motivo, *limite inferiore*, soglie o stati del gioco, categoria del tempo dei
  tank, campioni fermi al limite. Il tooltip di una riga dell'elenco dà durata, mob principale e stato peggiore con la
  loro categoria e il motivo. La testata ha l'indicatore *stimato*.
- La registrazione aperta compare nell'elenco con *Recording* e non si elimina né si apre; il report si costruisce quando
  finisce. Una registrazione eliminata mentre il report si costruisce lo chiude; una danneggiata tiene il messaggio.
- La data è scritta con `Compat.DateText` (`date`), con il formato della lingua; senza orario, *Unknown date*.
- La scheda registra i suoi ascoltatori quando si costruisce (la prima volta che si mostra); la card *Recording* quando
  si costruisce. Con gli interruttori spenti non c'è nulla.

## 4. Threat Timeline (`Data/Timeline.lua`, `UI/Timeline.lua`, M5.2–M5.3)

> Completato in **M5.1**, prima del probe M0 come M2–M4 (decisione D7). La timeline e il replay **leggono** una
> sessione registrata (SPEC-02 §4) e non scrivono nulla: nessuna chiave nuova nelle sessioni, nessuno schema nuovo
> dell'account; l'unico dato nuovo è la posizione della finestra del replay (schema 2 del personaggio,
> [SPEC-02 §3.9](SPEC-02-data-model-storage.md#39-schema-2-del-personaggio-m5-la-finestra-del-replay)). La decisione di
> architettura è in [ADR 0017](../adr/0017-timeline-and-replay-are-views-over-the-recorded-session.md).

Fonte §5.3: threat del tank, giocatori più vicini alla soglia, percentuale relativa, cambi di target, eventi registrati,
superamenti di soglia; selezione di un intervallo, pausa e riproduzione, salto avanti e indietro, dettaglio del
campione, distinzione visiva fra dati rilevati e stime. Qui la timeline è il **grafico** (modello e widget); pausa,
riproduzione e salti sono del replay (§5), che la usa.

### 4.1 Regole

- **RPL-01** MUST: ciò che timeline e replay mostrano viene **solo** dalle righe e dagli eventi della sessione
  (`Storage.Decode`), con i periodi di §3.3 (combattimento, mob, detentore): gli stessi dati danno la stessa figura
  (test). Nessun valore si interpola, si media o si ricostruisce (DAT-30, ADR 0004 punto 4): **ogni vertice di una
  linea è una lettura registrata**, e il riassunto per la larghezza (§4.7) sceglie letture, non le calcola.
- **RPL-02** MUST: ogni elemento disegnato ha la sua categoria (ADR 0003) e il suo tooltip la dice:

| Elemento | Da | Categoria | Come si vede |
|---|---|---|---|
| **vertice** | riga con un numero (codici `0`–`4`) | rilevata | punto della linea; il tooltip dà numero e ora della lettura |
| **tratto pieno** | due letture consecutive vicine (§4.3) | rilevata: unisce due letture prese al passo della registrazione | linea piena |
| **tratto tratteggiato** | due letture consecutive lontane, senza nulla di sconosciuto in mezzo (§4.3) | **stimata**: approssimazione su campioni incompleti | linea tratteggiata; il tooltip dice *Estimate* e le due letture, mai un numero in mezzo |
| **buco** | §4.4 | sconosciuta, con il motivo | nessuna linea; banda tratteggiata `state-unknown` con il motivo |
| **stato** di un'unità | eventi `S` | calcolata in `values` (soglie `rec.warning`, `rec.danger`), rilevata in `state` (stati del gioco) | corsia nel token di stato, icona di stato alle entrate in WARNING e DANGER |
| **detentore** | eventi `A` | rilevata | corsia del detentore, icona `tank` ai cambi |
| **marcatori** | eventi (§4.5) | quella dell'evento (`L` e `H` la loro categoria e confidenza) | icone sulla traccia degli eventi |
| **riepilogo di un intervallo** | §4.8 | calcolata; stimata (*at least*) se l'intervallo ha tempo sconosciuto, come il report (§3.1) | card o tooltip |

- **RPL-03** MUST: nessuna ipotesi, nessuna causa (D9 vale anche qui, D15): i testi (chiavi `TIMELINE_*` e
  `REPLAY_*`) passano la prova delle parole di SPEC-04 §2.4 (WR-01–WR-07), estesa in M5.4.
- **RPL-04** MUST: i tre esiti (§0) si mostrano per tratto di tempo (§4.6); un grafico vuoto non sembra mai 0 %: dove
  non potevano esserci percentuali la timeline lo scrive.
- **RPL-05** MUST: un buco non si riempie e non si attraversa con una linea; il suo motivo è nel tooltip e, se la banda è
  larga almeno 40 px, scritto dentro.

### 4.2 Il modello (`Data/Timeline.lua`, M5.2)

`Timeline.Build(id, done)` fa come `Report.Build` (§3.4): `Storage.Decode`, poi `Timeline.Compute(s, d, step)` a
**fette** di `Timeline.SLICE` = 5 000 righe o eventi per frame (`Compat.After(0)`), dentro o fuori dal combattimento;
`done(model)` o `done(nil, motivo)` con `off` (interruttore `timeline` spento), `unknown` (anche se la sessione si
elimina durante la costruzione), `recording` (la sessione aperta), `damaged` o `error`. Il risultato a fette e quello
di un'unica passata sono uguali (test). Si tiene in memoria **un** modello, l'ultimo costruito, mai salvato; si butta a
`SESSIONS_CHANGED` se la sessione non c'è più. Periodi, crossing e detentore si calcolano con le **stesse funzioni** del
report (M5.2 le espone da `Data/Report.lua` invece di copiarle), così report e timeline non possono dire cose diverse.

```lua
model = {
    id = "1764100000-1",
    dur = 1840,              -- decimi: fine dell'asse, il maggiore fra `dur` e l'ultimo t scritto (righe ed eventi)
    state = "complete", ended = "combat", after = nil, trunc = nil,   -- dall'intestazione (SPEC-02 §4.1)
    hz = 2, join = 15,       -- s.rec.hz (2 se manca); il limite del tratto pieno in decimi (§4.3)
    warning = 82, danger = 91,                         -- s.rec; nil se mancano (allora niente linee di soglia)
    combat = { { 0, 1203 }, { 1240, 1840 } },          -- periodi di combattimento (§3.3)
    mobs = { { 0, 1840, 1 } },                         -- periodi di mob: { from, to, m }
    modes = { { 0, 1840, "values" } },                 -- da M (prima del primo M: rec.mode): { from, to, mode, reason }
    gaps = { { 812, 836, "tick" } },                   -- buchi del mob intero (§4.4): { from, to, kind, reason }
    units = { [1] = Series, … },                       -- per indice di `units`
    events = { … },                                    -- i marcatori (§4.5), in ordine di tempo
    outcome = "values",      -- values | state | none | mixed (§4.6)
    series = { 3, 1, 5 },    -- le serie mostrate di predefinito (§4.7)
}
Series = {
    rows = { … },            -- indici (in `d`) delle righe con un numero dell'unità, in ordine di t
    states = { { from, to, "W", m }, … },   -- dagli S, tagliati ai periodi (§3.3)
    holds = { { from, to, m }, … },         -- da A: quando l'unità teneva il mob
    unknown = { { from, to, reason }, … },  -- buchi dell'unità (§4.4)
    present = { { from, to, m }, … },       -- nella lista del mob: dall'S di entrata all'S di uscita
    maxP = 912, maxT = 640, readings = 210, -- percentuale massima registrata (decimi di %) e quando; letture con un numero
    crossings = { { t, "W" }, … },          -- entrate in WARNING e DANGER con la regola del report (§3.2)
}
```

### 4.3 Serie e tratti

Una **serie** sono le letture con un numero di un'unità, in ordine di tempo. Fra due letture consecutive `r1` e `r2`
della stessa unità (`t1 ≤ t2`) il tratto è, nell'ordine:

1. **nessuno** (buco o interruzione) se `r1` e `r2` sono su mob diversi o c'è un evento `T` fra loro; se fra loro c'è
   una riga **senza numero** della stessa unità (`a`–`d`, `S`, `E`, `M`, `U`, `X`, `T`); se fra loro c'è un evento `G`,
   un `M` verso `state` o `none`, un `c` (fine di un periodo di combattimento), l'`S` di uscita dell'unità dalla lista o
   lo `Z` dei campioni; oppure se `t2 − t1 > Timeline.ESTIMATE_MAX` = **100** decimi (10 s);
2. **pieno** (rilevato) se `t2 − t1 ≤ join`, con `join = max(30 / hz, 10)` decimi (1,5 s a 2 Hz): lo stesso limite
   del buco del tick (§1.3), cioè due letture prese al passo del registratore;
3. **tratteggiato** (stimato) altrimenti: letture rade senza nulla di sconosciuto registrato in mezzo. Succede con le
   unità lette a turno oltre `maxUnits` (SPEC-03 §1.3: la loro freschezza ha un intervallo più lungo, quindi restano
   fresche senza righe nuove) o con un client lento. Con i predefiniti (40 unità, monitor a 5 Hz, registrazione a 2 Hz)
   è raro; la distinzione che si vedrà più spesso è fra linea e buco ([Q20](SPEC-09-risks-open-questions.md)).

Valori e assi:

- Il valore di un vertice è `p / 10` % (la colonna `p` di SPEC-02 §4.2). `p = 3843`, il massimo della colonna, è un
  **limite inferiore**: il tooltip dice *at least 384.3 %* (stimata).
- Asse y da 0 a `max(110, la percentuale più alta nella vista arrotondata alla decina superiore)`, al più **150 %**: un
  vertice più alto sta sul bordo con l'icona `arrow_up` e il suo numero nel tooltip.
- Linea di riferimento **100 %** (`border-strong`): in `values` chi tiene il mob sta a 100 %, quindi la sua serie è la
  *threat del tank* della fonte (la percentuale è relativa al detentore, SPEC-03 §2.2). Le soglie `rec.warning` e
  `rec.danger` della sessione sono linee orizzontali da 1 px nei token `state-warning` e `state-danger` (elementi non
  testuali, ST-03) con la loro etichetta (*82 %*) in `text-3`; senza `rec` non si disegnano.
- In *state only* un'unità non ha vertici: ha la sua corsia degli stati (§4.6).

### 4.4 Buchi

| Buco (`kind`) | Comincia a | Finisce a | Ambito | Testo (tooltip e banda) |
|---|---|---|---|---|
| `unknown` | una riga con un motivo (`S`, `E`, `M`, `U`, `X`) | la riga seguente dell'unità sullo stesso mob, la fine del periodo di mob o di combattimento | l'unità (la sua serie e la sua corsia) | *No reading: secret value* (`missing`, `error`, `no unit`, `other`) |
| `stale` | una riga `T` | come sopra | l'unità | *Reading too old* |
| `mode` | un `M` verso `none` | l'`M` seguente | tutto il grafico | *Nothing readable: secret value* (il motivo dell'`M`) |
| `nomob` | un `T` senza mob (`a` = `n`, `d`, `l`) | il `T` seguente con un mob | tutto | *No monitored mob* · *Target died* · *Target lost* |
| `tick` | `t − n` di un evento `G` (`n` è la durata) | `t` del `G` | tutto | *Recording paused for 2.4 s* |
| `limit` | `trunc` (evento `Z` `r` o `t`) | la fine dell'asse | le serie e le corsie; gli eventi continuano | *Samples stopped: limit reached* |

- Il **fuori combattimento** fra un `c` e il `C` seguente (pull a catena) non è un buco (§1.2: fuori dal combattimento
  non si legge nulla): banda `surface-2` *Out of combat*, senza tratteggio.
- Un'unità **fuori dalla lista** (fra un `S` di uscita e uno di entrata, o prima della prima entrata) non ha buco: la
  sua linea si ferma e il tooltip dice *Not on the threat list*.
- La **fine di una sessione interrotta** è la fine dell'asse (l'ultimo record, §3.1): l'ultimo marcatore è `X`
  (*Recording interrupted (reload)*) e nulla si disegna dopo; la timeline non dice mai che cosa è successo dopo.

### 4.5 Marcatori degli eventi

| Evento | Marcatore | Dove | Testo |
|---|---|---|---|
| `C` | icona `flag` | traccia degli eventi | *Combat started* (`a = 1`) · *Next pull* (`2`) · *Combat continued after a reload* (`r`) |
| `c` | inizio della banda fuori combattimento | grafico | *Combat ended* |
| `T` con un mob | linea verticale `border-strong` su tutta l'altezza, il nome del mob in alto se c'è posto | grafico | *Target: Hogger* (*Unknown mob* senza nome) |
| `T` senza mob | inizio del buco `nomob` | grafico | come §4.4 |
| `S` che **entra** in WARNING o DANGER (la regola dei superamenti di §3.2) | icona di stato da 10 px sulla serie, all'altezza della lettura più vicina entro `join` (altrimenti sulla corsia) | serie e corsia | *Thrall: Warning* e, in `values`, *thresholds 82 / 91*; in `state` *game state* |
| ogni altro `S` (discesa, UNKNOWN, entrata o uscita dalla lista) | solo il colore della corsia | corsia | elenco degli eventi, filtro *All* (§5.4) |
| `A`, nuovo tank (`a = 1`) | icona `tank` `text-2` | corsia del detentore | *Thrall holds the mob* |
| `A`, nuovo **non** tank (`a = 0`) | icona `warn` in `state-danger` | corsia del detentore e traccia | *Ana took the mob from Thrall* (senza *da chi* se era il primo) |
| `D` | icona `skull` `text-1` | traccia | *Thrall died* · *The target died* · *You died* |
| `L` | icona `bell` (`mute` se silenziato), nel token di stato della gravità (`warning` → `state-warning`; `danger`, `aggro`, `lost` → `state-danger`; gli altri `text-2`) | traccia | *Alert: Warning* (*muted*), con categoria e confidenza dell'avviso |
| `H` | icona `coach` `text-2` | traccia | *Coach tip* con il titolo breve della regola (`T1`–`T7`, `D1`–`D5`, `A1`), categoria e confidenza: le parole del consiglio non sono registrate e non si ricostruiscono |
| `N` | icona `star` `text-2` | traccia | *Encounter started* · *Encounter ended: success / not successful* |
| `M` | inizio della banda di modalità | grafico | *Threat values readable* · *State only: values are secret* · *Nothing readable* (con il motivo) |
| `G` | il buco `tick` | grafico | come §4.4 |
| `X` | icona `cross` `text-2` alla fine dell'asse | traccia | *Recording interrupted (logout or reload)* |
| `Z` | icona `warn` `text-2` | traccia | *Limit reached: samples · events · units · mobs · time* |

- **Raggruppamento**: i marcatori della traccia a meno di `Timeline.MARKER_PX` = **8** px si uniscono in uno con il
  numero (*×3*), con l'icona del più importante (`D`, poi `A` non tank, `C`/`c`, `T`, `N`, `L`, `H`, gli altri); il
  tooltip li elenca in ordine di tempo, al più 8, poi *and 4 more*.

### 4.6 I tre esiti nel tempo

L'**esito** di una sessione si calcola dalle righe: `values` se ha righe con un numero e nessuna `a`–`d`; `state` se
ha righe `a`–`d` e nessuna con un numero; `none` se non ha né le une né le altre; `mixed` altrimenti (o se le bande di
modalità cambiano dentro il combattimento). Una banda `none` **prima** della prima banda leggibile non rende la sessione
`mixed` (precisazione di M5.2): il recorder si apre con la modalità in vigore, che è `none` per il decimo prima della
prima lettura del monitor; quel decimo resta un buco `mode` con il suo motivo.

| Esito | Grafico delle percentuali | Corsie | Testo al posto del grafico |
|---|---|---|---|
| **values** | le serie (§4.3), le soglie, la linea 100 % | detentore e gli stati delle serie mostrate | — |
| **state** (*state only*) | nessuno | detentore e una corsia degli stati per unità (al più `Timeline.MAX_LANES` = **10**, §4.7) | *Percentages were not available in this fight (state only): states and who held the mob are shown.* |
| **none** (nulla di leggibile) | nessuno | nessuna | *Nothing was readable in this fight (secret value): only the events are shown.*, con il motivo prevalente come la qualità dei dati del report (§3.2) |
| **mixed** | le serie nei tratti `values`; altrove la banda della modalità sopra il grafico (*State only from 1:12*, tratteggiata se `none`) | come `values`, più le corsie di chi ha solo stati | — |

### 4.7 Serie mostrate, riassunto per la larghezza e vista

- **Serie mostrate di predefinito** (`Timeline.MAX_SERIES` = **6**, [Q20](SPEC-09-risks-open-questions.md)): il
  giocatore (`me`) se ha letture; chi ha tenuto il mob, per tempo tenuto; poi le altre unità per percentuale massima
  registrata, decrescente; a pari valore l'indice. Un'unità senza letture con un numero non è mai una serie. Le corsie
  di *state only* seguono lo stesso ordine con il tempo in WARNING e DANGER al posto della percentuale. Il replay
  permette di cambiare le serie mostrate (§5.4), sempre al più 6.
- **Vista**: un intervallo `[a, b]` in decimi, tutta la sessione all'apertura, almeno `Timeline.MIN_VIEW` = **50**
  decimi (5 s). Il grafico largo `W` px si divide in `buckets = min(floor(W / Timeline.BUCKET_PX), Timeline.MAX_BUCKETS)`
  colonne di tempo uguale, con `BUCKET_PX` = **2** e `MAX_BUCKETS` = **400**.
- **Riassunto per la larghezza** (*downsampling*): `Timeline.View(model, a, b, buckets, series, out)` dà per ogni serie
  e colonna le letture **prima**, **ultima**, **minima** e **massima** (indici di riga, mai una media). Il widget
  disegna in ogni colonna con più letture una barra verticale dalla minima alla massima (i picchi restano: un
  superamento non sparisce rimpicciolendo) e, fra l'ultima lettura di una colonna e la prima della colonna seguente che
  ne ha, il tratto di §4.3 calcolato **su quelle due letture vere**, che sono consecutive. Se dentro una colonna c'è un
  buco della serie, la colonna si disegna come due corse separate e il buco resta largo almeno 1 px. Con la vista
  stretta abbastanza (una lettura per colonna) il disegno è la linea esatta delle letture.
- **Costo**: `View` cerca `a` con una ricerca binaria sulla colonna `t` (larghezza fissa, SPEC-02 §4.2) e passa solo le
  righe della vista; scrive in `out`, riusato (nessuna allocazione dopo il riscaldamento per una vista della stessa
  larghezza). È sincrona; M5.2 ne fissa il budget con una prova lunga (`Tests/long/test_timeline_budget.lua`): una vista
  dell'intera sessione a 30 000 righe (40 unità per 750 tick) entro **2 000 000** di istruzioni della VM e 512 byte. M5.2
  ha misurato circa 132 000 istruzioni con le 6 serie predefinite e 884 000 con tutte le 40 unità come serie (ogni riga
  passata), 0 byte dopo il riscaldamento: non serve farla a fette. Costruire il modello di quella sessione costa circa
  2,5 milioni di istruzioni, a fette di `SLICE`.
- **Zoom**: *Zoom to selection* (§4.8) e la rotella sopra il grafico (×2 avanti o indietro intorno al puntatore, entro
  `MIN_VIEW` e la sessione intera); *Whole fight* torna alla sessione intera.

### 4.8 Il widget (`UI/Timeline.lua`, M5.3)

`Timeline.Widget(parent, opts)` → un oggetto con `:SetModel(model)`, `:SetView(a, b)`, `:SetSeries(list)`,
`:SetCursor(t)`, `:SetSelection(a, b)`, `:Layout(w, h)` e le richiamate `opts.onSeek(t)`, `opts.onSelect(a, b)`,
`opts.onHover(t)`. `opts.lanes` (vero nel replay) e `opts.legend` scelgono le parti.

**Disposizione**, dall'alto (punti):

| Parte | Altezza | Contenuto |
|---|---|---|
| Legenda | 16 | per ogni serie: un trattino del colore della serie (12 × 2), il nome (o il token, *Unknown*) in `Small` `text-1`, la percentuale massima registrata in `MonoSmall`; l'icona `tank` per chi ha tenuto il mob |
| Grafico | il resto, almeno 80 | margine sinistro di 28 pt con le etichette dell'asse y (`MonoSmall` `text-3`) a 0, 50 e 100 %; righe della griglia `border-subtle`; soglie, linea 100 %, serie, buchi, linee dei cambi di mob, banda fuori combattimento, cursore (`accent`, 1 px su tutta l'altezza), selezione (`accent` al 15 %) |
| Corsie | 10 il detentore, 6 per serie (`opts.lanes`) | il detentore nel colore della sua serie (`text-3` se non è una serie mostrata) con le icone dei cambi; gli stati nei token di stato, UNKNOWN tratteggiato |
| Traccia degli eventi | 16 | i marcatori di §4.5 |
| Asse del tempo | 14 | tacche a passo rotondo (1, 2, 5, 10, 15, 30 s; 1, 2, 5, 10 min) distanti almeno 60 px, etichette `m:ss` in `MonoSmall` `text-3` |

**Disegno, dentro i limiti del client**:

- Linee con le regioni `Line` del client (`frame:CreateLine`, `SetStartPoint`, `SetEndPoint`, `SetThickness`, nel
  dump); bande, corsie e griglia con texture (`CreateTexture` + `Theme.Fill` / `Theme.Tint`); icone dal foglio di
  `UI/Assets.lua`. Spessore 2 px (`Theme.Px`) per la serie del giocatore, 1,5 px per le altre, 1 px le barre min–max.
- Un tratto **tratteggiato** è fatto di trattini da 4 px con spazi da 3 px (`Timeline.DASH`), ognuno una `Line`, al più
  24 per tratto (un tratto più lungo allunga i trattini). I buchi usano la texture `dash` ripetuta, tinta
  `state-unknown` al 50 % sopra `surface-2`.
- **Pool**: le regioni si prendono da pool che crescono fino a `Timeline.MAX_LINES` = **3 000** linee e
  `Timeline.MAX_TEXTURES` = **1 200** texture e non si restringono; se un disegno supererebbe un limite, il widget
  raddoppia `BUCKET_PX` e ridisegna (mai dati tolti in silenzio); `/atw debug` lo conta.
- **Senza `CreateLine`** (`Theme.Probes()` aggiunge `lines`): il grafico mostra le letture come punti da 2 px e le barre
  min–max, senza tratti; le stime diventano punti radi e il tooltip lo dice. Nessuna linea inventata con texture ruotate.
- **Colori**: solo token di `UI/Theme.lua`. Le serie hanno sei token nuovi `series-1`…`series-6`, definiti **in ogni
  tema** (più chiari nei temi scuri, più scuri in Aurora) con contrasto ≥ 3:1 su `bg` e `surface-1` e tinte lontane dai
  quattro token di stato, che restano per stati e marcatori; M5.3 sceglie i valori, li scrive in
  [ui-style §3.5](ui-style.md#35-timeline-e-replay-m5) e `test_theme.lua` li controlla. Il giocatore è sempre
  `series-1`. Un'unità non si riconosce mai dal solo colore: la legenda, il nome alla fine della linea quando c'è posto
  (almeno 40 px liberi) e il tooltip la nominano.

**Interazione** (frame normali, quindi anche in combattimento):

- **Passaggio del mouse**: `OnEnter` mette un `OnUpdate` sul grafico (tolto a `OnLeave`) che lavora solo quando la x del
  puntatore (`Compat.CursorPosition()`) cambia di almeno 1 px: una linea verticale sottile e il tooltip al tempo sotto
  il puntatore: ora (*1:12.4*), mob, modalità; per ogni serie mostrata la lettura più vicina entro
  `Timeline.HOVER_PX` = 4 px (*62.4 % at 1:12.3*, rilevata), oppure su un tratto tratteggiato *Estimate: between 58.0 %
  (1:10.0) and 66.5 % (1:14.5)*, oppure in un buco *No reading: secret value*; lo stato in quel momento (con *thresholds
  82 / 91* o *game state*) e chi tiene il mob; i marcatori sotto il puntatore.
- **Clic** (premuto e rilasciato entro 3 px): `onSeek(t)`.
- **Trascinamento** (oltre 3 px): selezione dell'intervallo, con l'ombra che segue il puntatore (l'`OnUpdate` gira solo
  durante il trascinamento); al rilascio `onSelect(a, b)` se `b − a ≥ 10` decimi, altrimenti vale come clic. Il clic
  destro toglie la selezione.
- **Riepilogo dell'intervallo** (`Timeline.Summary(model, a, b, out)`, calcolato): durata; per serie mostrata la lettura
  più alta (rilevata, con l'ora), quante letture, superamenti verso WARNING e DANGER, tempo in WARNING e DANGER (*at
  least* e il tempo sconosciuto quando l'intervallo ne ha, come il report), tempo sconosciuto; eventi per tipo.
- **Card *Timeline* nel report** (scheda Reports, interruttore `timeline`): dopo la card di testa, il widget largo come
  la card e alto 140 pt, sulla sessione intera con le serie predefinite, la corsia del detentore e la traccia degli
  eventi, senza legenda (i nomi sono nel tooltip); si costruisce dopo il report, a fette, con *Building timeline…*. Un
  clic apre il replay a quel tempo (`REPLAY_REQUESTED(id, t)`, solo con l'interruttore `replay`); in *state only* e con
  nulla di leggibile la card mostra le corsie o la nota di §4.6.

## 5. Threat Replay (`Data/Replay.lua`, `UI/ReplayWindow.lua`, M5.4–M5.5)

Fonte §5.4: elenco degli ultimi scontri con la durata; timeline; eventi in ordine cronologico; selezione di un evento
per vedere i dati attorno; indicazione dei dati mancanti; eliminazione delle registrazioni. L'**elenco** con la durata
e l'**eliminazione** sono la scheda Reports (§3.6, M4.5), da cui il replay si apre; il replay aggiunge la timeline con
il cursore, gli eventi e il dettaglio.

### 5.1 Regole

- **RPL-06** MUST: il replay muove un **cursore** sulla sessione registrata e mostra ciò che era registrato a quel
  tempo; non legge nulla dal gioco, non scrive nulla nella sessione, non cambia ciò che il report calcola.
- **RPL-07** MUST: al tempo del cursore ogni valore mostrato porta la sua categoria; un valore che manca dice perché e
  da quando (*No reading since 1:10.2: secret value*), e un numero vecchio non si mostra mai come se fosse di quel
  momento (§5.3).
- **RPL-08** MUST: selezionare un evento mostra i dati da 5 s prima a 5 s dopo (fonte §5.4) e l'elenco dei dati mancanti
  in quella finestra, anche quando non manca nulla (*No missing data in this window*).

### 5.2 Il controllore (`Data/Replay.lua`, M5.4)

Nessun frame; un solo replay alla volta, in `Replay.state`:

```lua
Replay.state = {
    id = "1764100000-1", model = model,   -- il modello di Timeline.Build
    cursor = 0,                           -- decimi
    playing = false, speed = 1,
    view = { 0, 1840 },                   -- la vista della timeline (§4.7)
    selection = nil,                      -- { a, b } o nil
    focus = nil,                          -- indice dell'evento selezionato (§5.4) o nil
    filter = "key",                       -- filtro dell'elenco degli eventi (§5.4)
    series = { 3, 1, 5 },                 -- serie mostrate (al più Timeline.MAX_SERIES)
}
```

| Funzione | Effetto |
|---|---|
| `Replay.Open(id, t, done)` | costruisce il modello (`Timeline.Build`); `cursor` = `t` o l'inizio del primo periodo di combattimento; in pausa; `speed` da `char.ui.replay.speed`; `done(true)` o `done(false, motivo)` con i motivi di `Timeline.Build`. Un `Open` mentre un altro replay è aperto lo sostituisce |
| `Replay.Close()` | ferma il tick e dimentica lo stato (il modello resta nella cache di Timeline) |
| `Replay.Play()` | se il cursore è alla fine della vista riparte dall'inizio della vista; `Scheduler.Start("replay", Replay.HZ, tick)` con `Replay.HZ` = **10** (senza `combat`); in combattimento risponde `false, "combat"` ([Q18](SPEC-09-risks-open-questions.md)) |
| `Replay.Pause()`, `Replay.Toggle()` | ferma il tick; alterna |
| il tick | `cursor += speed × min(max(now − last, 0), 0,5 s) × 10` (`Compat.Now()`: un client fermo non fa saltare il cursore); alla fine della vista il cursore si ferma lì e il replay va in pausa |
| `Replay.Seek(t)` | il cursore a `t`, entro `[0, dur]`; se esce dalla vista, la vista scorre e tiene la sua larghezza |
| `Replay.Step(dir)` | pausa; il cursore al **momento registrato** seguente (`dir = 1`) o precedente: il tempo di una riga di una serie mostrata o di un evento del filtro *All*, strettamente dopo o prima del cursore; se non ce n'è, la fine o l'inizio |
| `Replay.Jump(dir)` | il cursore `± Replay.JUMP` = **50** decimi (5 s), senza fermare la riproduzione |
| `Replay.NextEvent(dir)` | il cursore all'evento seguente o precedente del filtro in vigore, che diventa il `focus` |
| `Replay.Focus(i)` | l'evento `i`: cursore al suo tempo, pausa, `focus = i`, la **finestra** `[t − 50, t + 50]` tagliata a `[0, dur]` diventa la selezione e, se la sessione è più lunga di 20 s, la vista (*Whole fight* torna indietro) |
| `Replay.SetSpeed(x)` | `x` fra `Replay.SPEEDS` = **{ 1, 2, 4, 8 }** ([Q19](SPEC-09-risks-open-questions.md)); salvata in `char.ui.replay.speed` |
| `Replay.SetView(a, b)`, `Replay.WholeFight()` | la vista, almeno `Timeline.MIN_VIEW` |
| `Replay.SetSeries(list)`, `Replay.SetFilter(f)` | serie mostrate (al più 6); filtro dell'elenco |
| `Replay.Snapshot(t, out)` | §5.3 |
| `Replay.Missing(a, b, out)` | i buchi (§4.4) che toccano `[a, b]`: tipo, da, a, motivo, unità o tutto il mob; e le unità della lista senza letture nell'intervallo |
| `Replay.Events(filter)` | l'elenco degli eventi (§5.4) |
| `Replay.OnChange(fn)` | un solo ascoltatore, la finestra: `fn(what)` con `what` = `cursor`, `play`, `view`, `focus`, `series`, `filter`, `model`, `closed`; `cursor` al più una volta per tick |

- **Combattimento** ([Q18](SPEC-09-risks-open-questions.md), `Replay.PAUSE_IN_COMBAT` = vero): a `COMBAT_STARTED` la
  riproduzione va in pausa e `Play` rifiuta fino a `COMBAT_ENDED` (il monitor ha la priorità, il costo del tick resta
  fuori dal combattimento: P10); cercare, passare a un evento e leggere il dettaglio funzionano anche in combattimento.
- **Sessione eliminata** (`SESSIONS_CHANGED` senza la sessione): `Close` e `OnChange("closed")` con `unknown`.
- **Costo del tick**: nessuna funzione del gioco, nessuna allocazione; il cursore muove una regione e il dettaglio si
  ricalcola solo quando il cursore passa un momento registrato (puntatori per serie che avanzano durante la
  riproduzione). Budget (fissato in M5.4): **2 000 istruzioni per tick** e nessuna allocazione; misurate su una
  sessione al limite delle righe al più 870 istruzioni a 8×.
- Con l'interruttore `replay` (o `timeline`) spento `Open` risponde `off` e nulla si registra (ADR 0014).

### 5.3 Il dettaglio al tempo del cursore

`Replay.Snapshot(t, out)` riempie `out` (riusato, nessuna allocazione durante la riproduzione):

| Campo | Da | Categoria | Che cosa si mostra |
|---|---|---|---|
| tempo | il cursore | — | *1:12.4* |
| combattimento | periodi di combattimento | rilevata | *In combat (pull 2)* · *Out of combat* |
| mob | periodo di mob, `mobs` | rilevata; sconosciuta senza nome | *Hogger* · *Unknown mob* · *No monitored mob* |
| modalità | bande di modalità | rilevata | *Values* · *State only* · *Nothing readable: secret value* |
| buco del mob | `gaps` | sconosciuta | *Recording paused (2.4 s)* e simili (§4.4) |
| detentore | `holds` | rilevata | *Thrall holds the mob (tank)*; sconosciuto se nessun `A` dice chi |
| per unità nella lista in quel momento (prima le serie mostrate, poi le altre, al più 40): stato | `states` | calcolata in `values`, rilevata in `state` | distintivo di stato (icona e parola, ST-02) |
| per unità: lettura | l'ultima riga con un numero dell'unità sullo stesso mob con `tr ≤ t` | rilevata se `t − tr ≤ join`; **stimata** se `join < t − tr ≤ ESTIMATE_MAX` senza buchi fra `tr` e `t`; altrimenti sconosciuta | *62.4 %* · *~62.4 % · 1.8 s before* (tooltip *Estimate: the last reading, 1.8 s before*) · *No reading since 1:10.2: secret value* |
| per unità in *state only* | l'ultima riga `a`–`d` | rilevata | la situazione con le parole della modalità `state` del monitor (SPEC-03 §2.3) |

Il **dettaglio dell'evento** (con un `focus`): l'evento con i suoi campi (unità, mob, categoria, confidenza), le letture
delle unità coinvolte nella finestra ±5 s (la prima, l'ultima, la più alta, quante) e i **dati mancanti** di
`Replay.Missing` nella finestra: *Thrall: no readings 0:42.1–0:45.0 (secret value)*, *Nothing readable 0:40.0–0:47.3*,
*Recording paused 0:44.0–0:46.4*, *Samples stopped at 3:10 (limit reached)*, oppure *No missing data in this window*.

### 5.4 L'elenco degli eventi

- Una riga per evento di `model.events`, in ordine di tempo: ora (*0:12.4*, `MonoSmall`), icona e testo di §4.5,
  l'indicatore della categoria come nella scheda Reports (stimata nel colore `warn`, sconosciuta `text-3`).
- **Filtri** (`Widgets.Segmented`): *Key events* (predefinito: `C`, `c`, `T`, `A`, entrate in WARNING e DANGER, `D`, `N`,
  `M`, `G` di almeno 1 s, `X`, `Z`), *Alerts & tips* (`L`, `H`), *All* (anche ogni altro `S` e ogni `G`).
- Righe da 20 pt in un pool che scorre (al più le righe visibili più due, anche con 6 000 eventi). Durante la
  riproduzione la riga dell'ultimo evento passato si evidenzia e l'elenco la tiene in vista, salvo per 3 s dopo che il
  giocatore l'ha fatto scorrere.
- Clic: `Replay.Focus(i)` (nella disposizione a pannello unico passa a *Details*). Tooltip: categoria, campi, e per `L` e
  `H` la categoria e la confidenza registrate.
- Un elenco con soli `C` e `c` dice *Only the start and the end of combat were recorded.*
- **Serie**: nel dettaglio un clic sul nome di un'unità la mostra o la toglie dal grafico (al più 6: la settima prende il
  posto dell'ultima scelta in automatico).

### 5.5 La finestra del replay (`UI/ReplayWindow.lua`, M5.5)

- Frame `AzerothThreatwardenReplay` (con il nome per Esc, ARC-04), **separato** dalla finestra principale, che resta
  com'è: strato `MEDIUM`, `SetToplevel`, nello schermo (`SetClampedToScreen`), spostato dalla barra del titolo,
  ridimensionato dalla maniglia `dashed`; lo stile della disposizione ampia (barra del titolo da 52 pt con il logo da
  24 pt, card su `bg`, raggio 12, ombra); la scala di `char.ui.scale`, come la finestra principale.
- Dimensione predefinita **820 × 520** pt, minima **640 × 420**, massima **1400 × 1000**; posizione, dimensione e
  velocità per personaggio in `char.ui.replay` ([SPEC-02 §3.9](SPEC-02-data-model-storage.md#39-schema-2-del-personaggio-m5-la-finestra-del-replay)),
  salvate al rilascio; senza posizione, al centro.
- **Si apre da**: il pulsante *Replay* della card di testa del report (interruttore `replay`; spento con il tooltip per
  la registrazione in corso o danneggiata); un clic sulla card *Timeline* del report (a quel tempo);
  `/atw replay` (la registrazione chiusa più recente) e `/atw replay <n>` (la `n`-esima dell'elenco, 1 = la più
  recente). Tutti passano da `REPLAY_REQUESTED(id, t)`. L'avviso di fine scontro (§3.5) resta *Open report*.

```
┌ logo · THREAT REPLAY · 26 Nov 21:14 · Deadmines · Hogger · 3:40 · Interrupted ──────────────── ✕ ┐
│ ── You 91 %  ── Thrall 100 %  ── Ana 88 %                                                          │
│ [grafico: soglie, 100 %, serie piene e tratteggiate, buchi, cambi di mob, cursore, selezione]       │
│ [corsie: detentore, stati]   [traccia degli eventi]   [asse del tempo]                     (~55 %) │
│ |◀  ◀◀  ◀  ▶/❚❚  ▶  ▶▶  ▶|    1× 2× 4× 8×     1:12.4 / 3:40      Zoom to selection · Whole fight   │
│ ┌ Events  [Key events | Alerts & tips | All] ┐ ┌ At 1:12.4 ─────────────────────────────────────┐ │
│ │ 0:00.0  ⚑ Combat started                   │ │ Hogger · Values · In combat                     │ │
│ │ 0:12.4  ▲ Ana: Warning                     │ │ Thrall holds the mob (tank)                     │ │
│ │ 0:31.0  ☠ Thrall died                      │ │ You     WARNING  84.2 %                         │ │
│ │ …                                          │ │ Ana     SAFE     ~61.0 % · 1.8 s before         │ │
│ └────────────────────────────────────────────┘ │ Missing in ±5 s: none                           │ │
│                                                └─────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────────────────────────────────────── grip ┘
```

- Sotto i 760 pt di larghezza i due pannelli in basso diventano uno con il selettore *Events · Details*.
- **Comandi**: all'inizio, evento precedente, passo indietro, riproduci o pausa, passo avanti, evento seguente, alla fine;
  la velocità (`Widgets.Segmented`); il tempo del cursore e la durata; *Zoom to selection* e *Whole fight*. Ogni
  pulsante ha il tooltip con il suo tasto. M5.5 aggiunge al foglio delle icone `play`, `pause`, `step-back`,
  `step-forward`, `skip-back`, `skip-forward` (forme originali, `tools/make_media.py`).
- **Tasti** (`Replay.KEYS`, [Q19](SPEC-09-risks-open-questions.md)), solo **fuori dal combattimento** e mentre il
  puntatore è sopra la finestra: Spazio riproduci o pausa; Sinistra e Destra un passo; Maiuscolo + Sinistra o Destra
  ±5 s; Su e Giù evento precedente o seguente; Home e Fine inizio e fine; 1–4 la velocità. La finestra prende la tastiera
  con `EnableKeyboard(true)` e lascia passare al gioco ogni altro tasto (`SetPropagateKeyboardInput(true)`); in
  combattimento non prende tasti. Esc chiude la finestra, anche in combattimento (`UISpecialFrames`).

| Situazione | Che cosa mostra |
|---|---|
| costruzione | *Building timeline…*; comandi spenti |
| registrazione danneggiata | *This recording is damaged and was set aside.* |
| registrazione in corso | *This fight is still being recorded: the replay opens when it ends.* |
| registrazione eliminata (anche mentre è aperta) | *This recording was deleted.* |
| *state only* | la nota di §4.6, le corsie, il dettaglio con gli stati |
| nulla di leggibile | la nota di §4.6, gli eventi e il dettaglio (mob, combattimento, morti, modalità con il motivo) |
| interrotta | il distintivo *Interrupted (reload)* nella barra del titolo; l'asse finisce all'ultimo record con il marcatore `X`; *Continued from…* / *Continues in…* aprono la sessione collegata da `after` |
| troncata | la banda `limit`; nel dettaglio *Samples stopped at 3:10 (limit reached)* |
| dati in sola lettura | uguale: il replay legge soltanto |
| in combattimento | riproduzione in pausa, *Play* spento con il tooltip *Playback pauses during combat*; cercare, passare e leggere funzionano; nessun tasto |
| interruttori spenti | la finestra non si costruisce; `/atw replay` risponde *This arrives in v0.5.0.* |

- La finestra si costruisce alla prima apertura (pool di righe, regioni del grafico) e si nasconde alla chiusura;
  chiudendola il replay si chiude (`Replay.Close`). Il tema si ridipinge con il registro di `UI/Theme.lua`.

### 5.6 Anteprime e manuale

- **Anteprime** (ADR 0013, dati inventati, `tools/make_mockups.py`): `replay-values`, `replay-state`, `replay-unknown`,
  `replay-event` (un evento selezionato con la finestra ±5 s e i dati mancanti) e `report-timeline` (la card del
  report), in inglese e in italiano; `replay-values` anche in Aurora e Warden.
- **Manuale**: la pagina *Threat Replay* (`docs/wiki/Threat-Replay.md` e `Threat-Replay-it.md`) con le anteprime: come si
  apre, che cosa vogliono dire linea piena, tratteggiata e banda tratteggiata, i tasti, il combattimento, e i limiti (nulla
  si ricostruisce, nessuna causa, che cosa dipende dal probe); *Combat Reports* rimanda alla card *Timeline*.

## 6. Moduli, eventi, interruttori e diagnostica (M4)

| File | Responsabilità | Bus | Step |
|---|---|---|---|
| `Data/Session.lua` | la sessione di SPEC-02 §4: creazione, voci di `units` e `mobs`, alfabeto e codici, righe ed eventi in `buf`, impacchettamento a pezzi, unione alla chiusura, decodifica; nessuna API del gioco, nessun evento | — | M4.2 |
| `Data/Recorder.lua` | condizioni (§1.1), ciclo di vita (§1.2), tick (§1.3), eventi (§1.4), reload e logout (§1.6), consumatore `recorder` dello Scanner | ascolta `COMBAT_STARTED`, `COMBAT_ENDED`, `TARGET_CHANGED`, `STATE_CHANGED`, `AGGRO_CHANGED`, `THREAT_MODE_CHANGED`, `ALERT_RAISED`, `COACH_TIP`, `DEMO_CHANGED`, `CONFIG_LOADED`, `CONFIG_CHANGED`, `ENTERING_WORLD`; dal gioco `PLAYER_LOGOUT`, `UNIT_DIED`, `PLAYER_DEAD`, `ENCOUNTER_START`, `ENCOUNTER_END`; emette `SESSION_STARTED(id)`, `SESSION_ENDED(id, state)` | M4.2 |
| `Data/Storage.lua` | caricamento e controlli (§2.2), sessioni messe da parte, potatura e stima (§2.4), eliminazione (§2.5), sola lettura (§2.6), interfaccia (§2.7) | ascolta `CONFIG_LOADED`, `CONFIG_CHANGED`, `ENTERING_WORLD`, `COMBAT_ENDED`; emette `SESSIONS_CHANGED()` | M4.3 |
| `Data/Report.lua` | metriche (§3.2–§3.3), costruzione a fette e riepilogo (§3.4) | ascolta `SESSIONS_CHANGED` | M4.4 |
| `UI/CoachStrip.lua` (cambio) | l'avviso di fine scontro (§3.5) | ascolta `SESSION_ENDED`; emette `REPORT_REQUESTED(id)` | M4.4 |
| `UI/Reports.lua`, `UI/Settings.lua` (card), `Core/Commands.lua` | la scheda, la card *Recording*, `/atw reports` | ascolta `SESSIONS_CHANGED`, `SESSION_STARTED`, `SESSION_ENDED` | M4.5 |
| `Core/Init.lua` (cambio) | `ENTERING_WORLD(isInitialLogin, isReloadingUi)` con gli argomenti dell'evento del gioco | — | M4.2 |
| `Data/ThreatModel.lua` (cambio) | `ThreatModel.IsStale(record, now)`: la regola di DAT-12 in una funzione | — | M4.2 |
| `Core/Config.lua` (cambio) | schema 4 (`RECORDING_DEFAULTS`, `RECORDING`, `RECORD_WHEN`, la regola di `sessions`, la migrazione), `Config:SetAside(path, value, kind)`, `TABS` con `reports` | — | M4.2, M4.3 |
| `Core/Compat.lua` (cambio) | `zone.RealZoneText` (`GetRealZoneText`), lettura di `instance.Info` (tipo e difficoltà), `Unit.NpcID` dal GUID; gli eventi `UNIT_DIED`, `PLAYER_DEAD`, `PLAYER_LOGOUT`, `ENCOUNTER_START`, `ENCOUNTER_END` nella tabella di SPEC-01 §8.2 | — | M4.2 |

**Realizzato in M4.2** (`Data/Session.lua`, `Data/Recorder.lua`), con queste precisazioni:

- Il recorder registra i suoi ascoltatori del Bus e gli eventi del gioco al login (`PLAYER_LOGIN`) solo se gli
  interruttori `monitor` e `recording` sono accesi; legge le impostazioni quando servono, quindi non ascolta
  `CONFIG_LOADED`. Un interruttore spento dopo il login chiude la sessione al tick seguente.
- `SESSIONS_CHANGED()` si emette all'apertura (una sessione nuova in `sessions`) e a ogni chiusura (tenuta o tolta).
- La demo non parte in combattimento (SPEC-03 §5.2): chiude quindi la sessione solo durante `END_DELAY`.
- `inst` è `nil` quando né `GetInstanceInfo` né `IsInInstance` lo dicono (sconosciuto, non `none`).
- `COACH_TIP(nil)` non si scrive ma dimentica la regola: un consiglio che torna dopo è di nuovo un evento `H`.
- In `buf.ev` un evento occupa **9** posti consecutivi (`t k m u v a b c n`: numeri e codici di un carattere; `n` è un
  numero, due codici o `-1`); in `buf.p` `-1` vuol dire nessun valore. Sono i soli valori che si salvano a un
  `/reload`.
- Il collegamento `after` guarda la sessione interrotta (o aperta e mai finita) più recente: la sua fine è
  `started + dur / 10`.

**Realizzato in M4.3** (`Data/Storage.lua`), con queste precisazioni:

- Storage ascolta `CONFIG_LOADED` dal caricamento del file e fa i controlli solo con l'interruttore `recording` acceso;
  solo allora registra `CONFIG_CHANGED`, `ENTERING_WORLD` e `COMBAT_ENDED`. Con l'interruttore spento non controlla,
  non scrive e non toglie nulla, e `Delete`/`DeleteAll` rispondono `off`.
- Il controllo veloce rifiuta anche `units` e `mobs` con buchi e, in `buf`, i valori che `Session.Join` non saprebbe
  codificare (tempi, indici, codici, la forma di `buf.ev`); una sessione con pezzi si unisce, si riconta e si controlla
  di nuovo come chiusa. Anche una sessione `complete` con pezzi (logout durante `END_DELAY`) si unisce e resta
  `complete`.
- `ended` vale `unknown` dal caricamento; al primo `ENTERING_WORLD` diventa `reload` o `login` per le sole sessioni con
  `stamp`. `dur` diventa l'ultimo `t` scritto (righe ed eventi) se quello salvato è minore; `fight` resta quello salvato
  (0 dopo un crash: sconosciuto, mai inventato).
- La voce di `corrupt` di una sessione danneggiata ha il tipo `session` e, come `data`, i soli campi semplici
  dell'intestazione (`id`, `started`, `dur`, `fight`, `state`, `ended`, `stamp`, `after`, `trunc`, `group`, `zone`,
  `inst`, `diff`, `n`, `ne`) con `found` (il tipo trovato) e `why` (il primo campo che non passa); mai le colonne,
  `units`, `mobs`, `q` o `rec`. `Config:SetAside(path, value, kind)` ha il terzo argomento facoltativo per il tipo (il
  tipo trovato se manca) e rifiuta in sola lettura; `Config.AddIssue(text)` annota il problema in `Config.issues`.
- Una sessione che fallisce il controllo profondo in combattimento si nasconde subito (`Get`, `List`) e si mette da
  parte a `COMBAT_ENDED`; in sola lettura si nasconde e si conta soltanto.
- Il recorder chiama `Storage.Add(session)` all'apertura e `Storage.Closed(session, kept)` alla chiusura, prima di
  `SESSION_ENDED`: toglie la sessione scartata, stima di nuovo la dimensione, pota ed emette `SESSIONS_CHANGED`, che da
  M4.3 emette solo Storage. `Storage.Prune()` restituisce quante sessioni sono uscite; `Storage.Check(s)` è il controllo
  veloce di una voce.
- `sum` resta `nil` finché non c'è `Report.Summary` (M4.4): Storage lo chiama fuori dal combattimento al caricamento,
  alla chiusura e a `COMBAT_ENDED`.
- `/atw debug`, sezione *Recording*: le righe *sessions kept* (numero, stima, limiti, sola lettura) e *storage this
  load* (completate, rinominate, scartate, potate, danneggiate, messe da parte, nascoste, eliminate).

**Realizzato in M4.4** (`Data/Report.lua`, l'avviso in `UI/CoachStrip.lua`), con queste precisazioni:

- Ogni valore è una *cella* `{ key, category, status (ok, na, insufficient, unknown), value, reason, lower,
  unknownTime, basis, truncated }`; il report ha le celle della sessione (`rows`) e una voce per unità (`cells`).
  `Report.CellText`, `ReasonText`, `BasisText` e `Headlines` danno le parole (chiavi `REPORT_*`) alla scheda di M4.5.
- **Righe utili** di un'unità (la soglia `MIN_ROWS`): le righe con un numero più, per lo stato soltanto, il maggiore fra
  `q.s` e le righe `a`–`d` (in *state only* una riga si scrive solo quando il codice cambia, quindi le sole righe non
  basterebbero). `Report.MIN_KNOWN` = 1 s di stato noto vale per superamenti e tempi; la percentuale massima chiede 3
  righe con un numero. Senza nulla di leggibile le celle della threat di un'unità dicono *Not available* e resta la
  qualità dei dati.
- Il limite inferiore di un'unità si segna se ha tempo sconosciuto o almeno una riga senza valore. Si scrive
  **«at least» / «almeno»** invece di `≥`: i caratteri inclusi nell'addon non hanno quel segno.
- **Chi tiene il mob** si conta dal suo `A` fino all'`A` seguente, alla fine del periodo di combattimento **o del periodo
  di mob** (di un mob non più monitorato non si sa chi lo tenga: precisazione di §3.3).
- Perdite dell'aggro: ogni `A` con `a = 0`, anche il primo detentore (senza *da chi*); i punti si scrivono solo se
  positivi. Due eventi `D` della stessa unità o dello stesso mob a meno di 3 s sono una morte.
- `Report.Build` risponde `done(nil, motivo)` con `off`, `unknown` (anche se la sessione si elimina durante la
  costruzione), `recording` (la sessione aperta), `damaged` o `error`; la prima fetta gira subito.
- `Report.Summary` restituisce `nil` con l'interruttore `reports` spento (`sum` si calcola al primo caricamento con
  l'interruttore acceso); senza nulla di leggibile `cross` e `aggro` sono `nil`, e `valid` è `nil` senza tick.
- L'avviso di fine scontro tiene presente la striscia anche con Coach e avvisi spenti, non compare in combattimento né
  in demo, sparisce a un nuovo combattimento; il clic (o *Open report*) apre la scheda Reports ed emette
  `REPORT_REQUESTED(id)` per M4.5.

- **Interruttori** (`Core/Features.lua`, ADR 0014): `recording` (recorder, Storage, card *Recording*) e `reports`
  (report, scheda, avviso, `/atw reports`) sono rimasti **spenti** fino a M4.R e sono **accesi** dalla `v0.4.0`. Spento vuol dire: nessun ascoltatore e nessun
  evento del gioco registrati, nessun consumatore dello Scanner, nulla scritto in `sessions`, nessuna card né scheda;
  `/atw reports` risponde *This arrives in v0.4.0.* I predefiniti dello schema 4 (`settings.recording`, `sessions =
  {}`) si scrivono comunque, come quelli di M3 prima di M3.R. Con `recording` acceso e `reports` spento (non
  pubblicato) si registra senza mostrare nulla.
- **`/atw debug`**, sezione *Recording*: interruttori e impostazioni; se una sessione è aperta, da quanto, righe,
  eventi, unità, mob, pezzi; altrimenti il motivo per cui l'ultimo combattimento non si è registrato (§1.1); sessioni
  tenute, stima totale e limiti; scartate, potate, danneggiate e messe da parte; il tempo dell'ultimo tick di
  registrazione (`Scheduler.Cost("record")`). Mai nomi, zone o mob.
- **Eventi del Bus**: `SESSION_STARTED(id)`, `SESSION_ENDED(id, state)` (`complete`, `interrupted`, `dropped`),
  `SESSIONS_CHANGED()`; nessun nome negli argomenti.

## 7. Piano di M4: test per step

Ogni test che passa per il monitor gira sui tre esiti (`Fight.OUTCOMES`, [SPEC-08 §2](SPEC-08-quality-probe-release.md#2-test-offline)).

| Step | Test e casi |
|---|---|
| **M4.2** | `test_session.lua`: alfabeto e larghezze, codici di ogni riga e di ogni evento, impacchettamento a 256 e unione, decodifica uguale a ciò che si è scritto, limiti (righe, eventi, unità, mob, tempo). `test_recorder.lua`, i casi di SPEC-08 QA-03 che finiscono in una sessione: giocatore solo (con `when` nelle tre scelte), party, raid, tank stabile, DPS che si avvicina alla soglia (eventi `S` e `L`), cambio di target, target che muore (`T d`, `D t`), più mob, morte del tank e di un DPS (`UNIT_DIED` leggibile e segreto), fine del combattimento e pull a catena entro e oltre 5 s, scontro sotto 3 s scartato, `/reload` e logout durante e dopo una sessione (`X`, `stamp`, la sessione nuova con `after`), API che restituisce `nil`, unità non accessibile, GUID non disponibile, campioni mancanti (`silent`), eventi doppi o fuori ordine, mob che scompare, target sostituito, valori segreti (righe solo al cambio del codice); demo e sola lettura senza sessioni; interruttore spento (nulla). In `test_config.lua` lo schema 4 e la migrazione da dati dello schema 3 |
| **M4.3** | `test_storage.lua`: caricamento con sessioni buone, aperte, interrotte (con e senza `stamp`, `ENTERING_WORLD` di reload e di login), danneggiate in ogni campo del controllo veloce e in quello profondo (in `corrupt`, le altre intatte), doppioni di `id`; potatura per numero e per dimensione, mai la sessione aperta, al cambio dei limiti; stima; `Delete` e `DeleteAll` con i rifiuti; sola lettura (nulla scritto); `/reload` simulato dopo ogni caso (la simulazione di SPEC-08 §2 rifiuta ciò che il client non salva) |
| **M4.4** | `test_report.lua`: sessioni note con risposte note per ogni metrica di §3.2 nelle tre modalità e in una sessione mista (`M` a metà), interrotta, troncata, senza mob leggibile; *Insufficient data* sotto 3 righe; limiti inferiori con copertura parziale; costruzione a fette uguale a quella intera; `sum`. `test_coach_wording.lua` esteso alle chiavi `REPORT_*`. L'avviso di fine scontro in `test_coach_strip.lua` |
| **M4.5** | `test_reports.lua` (la scheda: elenco, selezione, report, vuota con ogni motivo, eliminazione con conferma, sola lettura, in combattimento), `test_settings.lua` (la card *Recording*), `test_commands.lua` (`/atw reports`); pagina del manuale *Combat Reports* nelle due lingue con le anteprime |
| **M4.6** | `Tests/long/test_recorder_raid.lua`: raid da 40 per un'ora di combattimenti con pull a catena, morti e i tre esiti, limiti per sessione raggiunti; storico vicino ai limiti per numero e per dimensione per molte chiusure; `/reload` in combattimento ripetuti; apertura e chiusura ripetuta della scheda e dei report; memoria e pezzi che non crescono oltre i limiti; la terza configurazione di `test_monitor_budget.lua` |

## 8. Cosa aspetta il probe e il gioco

- **[probe P7]** morti (`UNIT_DIED` con un GUID leggibile, `PLAYER_DEAD`), incontri (`ENCOUNTER_*`); taunt fuori da M4.
- **[probe P9]** GUID leggibili (chiavi stabili delle unità e numero della creatura dei mob), ruoli (tank designati nel
  report).
- **[probe P10]** il costo del tick di registrazione e dello Scanner a finestra chiusa (§1.8).
- **[probe P12]** se `PLAYER_LOGOUT` arriva anche al `/reload`, se le SavedVariables si scrivono in combattimento, se
  `PLAYER_ENTERING_WORLD` dice `isReloadingUi` (§1.6).
- **[da provare in gioco]** (checklist M4.7): la dimensione vera del file delle SavedVariables con 25 sessioni contro la
  stima; che la scheda e il report si leggano a dimensioni piccole; i limiti di Q8 e le scelte di Q16 su un raid vero.
- **[da provare in gioco]** (checklist M5.6): le regioni `Line` del client su Forever (spessore, bordi a scale
  frazionarie, trattini da 4 px) e quante regioni reggono senza far calare i frame; `GetCursorPosition` con la scala
  dell'interfaccia e della finestra; l'`OnUpdate` solo durante il passaggio del mouse; se `SetPropagateKeyboardInput`
  è permesso fuori dal combattimento e se i tasti del replay disturbano quelli del gioco; la leggibilità del grafico a
  640 × 420 pt e dei sei colori delle serie nei tre temi; la durata di `Timeline.Build` su una sessione di un raid vero.
- **[probe P3]**: quale dei tre esiti di §4.6 mostra davvero la timeline in gruppo, in istanza e in raid.
- **[probe P10]**: il costo di `Timeline.View` e del tick del replay (fuori dal combattimento) sul client vero.

## 9. Moduli, eventi, interruttori e diagnostica (M5)

| File | Responsabilità | Bus | Step |
|---|---|---|---|
| `Data/Timeline.lua` | il modello di §4.2–§4.7 (`Build` a fette, `Compute`, `View`, `Summary`, serie predefinite, esito), con i periodi e i superamenti presi da `Data/Report.lua` | ascolta `SESSIONS_CHANGED` | M5.2 |
| `Data/Report.lua` (cambio) | espone le funzioni dei periodi (combattimento, mob, modalità, detentore, stati) e dei superamenti, che il report e la timeline usano insieme; il report non cambia | — | M5.2 |
| `UI/Timeline.lua` | il widget di §4.8: disposizione, pool di linee e texture, riassunto per la larghezza, tratteggio, buchi, marcatori raggruppati, tooltip, clic, trascinamento, rotella; la card *Timeline* nel report | emette `REPLAY_REQUESTED(id, t)` (clic sulla card) | M5.3 |
| `UI/Reports.lua` (cambio) | la card *Timeline* (interruttore `timeline`) e il pulsante *Replay* della card di testa (interruttore `replay`) | emette `REPLAY_REQUESTED(id, nil)` | M5.3, M5.5 |
| `UI/Theme.lua` (cambio) | i token `series-1`…`series-6` in ogni tema; `Theme.Probes()` con `lines` (`CreateLine`) | — | M5.3 |
| `Data/Replay.lua` | il controllore di §5.2–§5.4: cursore, riproduzione con il tick `replay`, passi, salti, eventi, finestra ±5 s, dettaglio, dati mancanti, filtri, serie | ascolta `COMBAT_STARTED`, `COMBAT_ENDED`, `SESSIONS_CHANGED` | M5.4 |
| `UI/ReplayWindow.lua` | la finestra di §5.5: barra del titolo, timeline, comandi, elenco degli eventi, dettaglio, stati, tasti, posizione e dimensione | ascolta `REPLAY_REQUESTED`, `COMBAT_STARTED`, `COMBAT_ENDED`, `CONFIG_LOADED`, `CONFIG_CHANGED`, `DISPLAY_CHANGED`, `SESSIONS_CHANGED`, `SESSION_ENDED` | M5.5 |
| `Core/Commands.lua` (cambio) | `/atw replay [n]` (interruttore `replay`, *This arrives in v0.5.0.* da spento) | emette `REPLAY_REQUESTED(id, nil)` | M5.5 |
| `Core/Config.lua` (cambio) | schema **2** del personaggio: `ui.replay` (`pos`, `size`, `speed`), la migrazione 1 → 2 e il suo test | — | M5.5 |
| `Core/Compat.lua` (cambio) | `Compat.CursorPosition()` (`GetCursorPosition`), `Compat.ModifierDown(name)` (`IsShiftKeyDown`, `IsControlKeyDown`, `IsAltKeyDown`): tutte nel dump, nella tabella di SPEC-01 §8.2 | — | M5.3, M5.5 |
| `UI/Assets.lua`, `tools/make_media.py` (cambio) | le icone `play`, `pause`, `step-back`, `step-forward`, `skip-back`, `skip-forward` | — | M5.5 |

- **Interruttori** (`Core/Features.lua`, ADR 0014): `timeline` (il modello, il widget, la card *Timeline* del report) e
  `replay` (il controllore, la finestra, il pulsante *Replay*, `/atw replay`) sono rimasti **spenti** fino a M5.R e sono
  **accesi** dalla `v0.5.0`; il replay
  chiede tutti e due (senza la timeline non ha grafico). Spento vuol dire: nessun ascoltatore e nessuna regione,
  `Timeline.Build` e `Replay.Open` rispondono `off`, nessuna card né pulsante, `/atw replay` risponde *This arrives in
  v0.5.0.* Lo schema 2 del personaggio si scrive comunque, come i predefiniti di M4 prima di M4.R. I test che li
  vogliono spenti li mettono a `false` in `M.features`.
- **`/atw debug`**, sezione *Timeline and replay*: interruttori; il modello in memoria (righe, eventi, serie, esito,
  millisecondi della costruzione); le regioni dei pool (linee, texture, quante volte si è raggiunto il limite e si è
  raddoppiato `BUCKET_PX`, `lines` di `Theme.Probes`); il replay (aperto, in riproduzione, velocità) e
  `Scheduler.Cost("replay")`. Mai nomi, zone o mob.
- **Eventi del Bus**: `REPLAY_REQUESTED(id, t)` (`t` facoltativo, in decimi); nessun evento a ogni tick (la finestra
  ascolta il controllore con `Replay.OnChange`); nessun nome negli argomenti. Prende il posto del `REPLAY_POSITION(t)`
  previsto in SPEC-01 §3.2.

**Realizzato in M5.2** (`Data/Timeline.lua`, il cambio di `Data/Report.lua`), con queste precisazioni:

- `Report.Walk(s, d, step, hooks)` è il passaggio sugli eventi del report, esposto con quattro richiami facoltativi:
  `state(u, m, stato, from, to)` a ogni intervallo di stato chiuso, `hold(u, m, from, to)` a ogni detentore,
  `cross(u, m, t, stato, evento)` a ogni superamento contato dal report, `watch(m, from, to)` a ogni periodo di mob
  monitorato in combattimento. `Report.Compute` non li passa: le celle e i test del report non cambiano.
  `Report.Intervals` (`add`, `merge`, `intersect`, `length`) e `Report.Prevailing` sono le funzioni del report sugli
  intervalli e sul motivo prevalente, usate anche dalla timeline.
- Il **tratto** si tiene sulla lettura dove finisce: per la `k`-esima lettura di una serie `segs[k]` è `solid`, `dashed`
  o `none` (dalla lettura `k − 1`) e `why[k]` il motivo di `none`: `first`, `mob`, `row`, `target`, `tick`, `mode`,
  `combat`, `limit`, `exit`, `far`. Le categorie sono in `Timeline.SEGMENT_CATEGORY` (rilevata, stimata, sconosciuta).
  Un evento rompe il tratto se cade **strettamente** fra le due letture; un `G` vale ai suoi due estremi.
- Un **buco** è `{ from, to, kind, reason }` (categoria sconosciuta, `Timeline.GAP_CATEGORY`); quelli di un'unità
  (`unknown`, `stale`) sono in `units[u].unknown`, quelli del grafico intero (`mode`, `nomob`, `tick`, `limit`) in
  `gaps`; `mode` e `nomob` si tagliano ai periodi di combattimento. Il buco di un'unità finisce alla riga seguente sullo
  stesso mob o alla fine del suo periodo di mob (o di combattimento).
- Un **marcatore** è uno per evento: `{ t, k, kind, place (track, chart, series, lane), category, confidence, prio, … }`;
  `Timeline.Group(markers, a, b, width, out)` raggruppa quelli della traccia a meno di `MARKER_PX` dal primo del
  gruppo, con in `top` il più importante (a pari importanza il primo). Le parole sono le chiavi `TIMELINE_*`
  (`MarkerText`, `GapText`, `OutcomeText`, `ModeText`, `GroupLines`); il consiglio del Coach si nomina con l'id della
  regola (*Coach tip (rule T1)*), perché le parole non sono registrate. Nel testo inglese il mob è *enemy*, come nel
  report.
- `Timeline.View` scrive per ogni serie le colonne `first`, `last`, `lo`, `hi` (posizioni nelle letture della serie,
  `0` senza letture; a pari valore la prima) e `cut` (un tratto assente dentro la colonna); la vista si allarga a
  `MIN_VIEW` (`Timeline.Clamp`) e le colonne vanno da 1 a `MAX_BUCKETS` (`Timeline.Buckets(larghezza)`).
  `Timeline.Reading` dà valore, ora e categoria di una lettura (`3843`: stimata, limite inferiore).
- `Timeline.Summary(model, a, b, out, serie)` dà, per serie, letture, la più alta con la sua categoria, superamenti,
  tempo in WARNING e DANGER, tempo sconosciuto (stati UNKNOWN, buchi dell'unità, modalità `none` e buchi del tick mentre
  era nella lista) con `lower` e la categoria stimata quando ce n'è; gli eventi per tipo.
- Serie predefinite e corsie: il giocatore, poi chi ha tenuto il mob per tempo tenuto, poi le altre per percentuale
  massima (le corsie: per tempo in WARNING e DANGER), a parità l'indice; una corsia solo per chi ha stati noti.
- `Timeline.Build` registra l'ascoltatore di `SESSIONS_CHANGED` alla prima costruzione con l'interruttore acceso; la
  sezione *Timeline and replay* di `/atw debug` si aggiunge al `PLAYER_LOGIN`, dopo *Recording*, con gli interruttori e
  il modello in memoria (righe, eventi, serie, corsie, esito, millisecondi e frame della costruzione); M5.3 e M5.4
  aggiungono le loro righe.

**Realizzato in M5.3** (`UI/Timeline.lua`, la card in `UI/Reports.lua`), con queste precisazioni:

- `UI/Timeline.lua` completa la tabella `Timeline` di `Data/Timeline.lua`; `Timeline.Widget` risponde `nil` con
  l'interruttore `timeline` spento. Il widget ha anche `:View()` e `opts.onView(a, b)` (lo zoom della rotella, per il
  replay), `opts.zoom = false` e `opts.height`; `:Layout(w, h)` restituisce l'altezza usata, **maggiore** di `h` quando
  le corsie lascerebbero al grafico meno di 80 pt.
- L'area del puntatore copre grafico, corsie e traccia degli eventi. Il **riepilogo** di una selezione è il tooltip
  mentre il puntatore è dentro la selezione (e appena la si traccia), con *Right-click to clear the selection*; ogni sua
  parte dice la categoria. Un trascinamento più corto di 1 s vale come clic.
- Il tooltip ha al più le 16 righe del tooltip dell'addon: ora, mob, modalità, chi lo tiene, una riga per serie (lettura
  e stato, ognuno con la categoria) e per corsia, i marcatori, poi *and N more*. Fra due letture di un tratto pieno più
  distanti di 4 px dice *Between … and …* (rilevata), mai un numero in mezzo.
- **Tratti**: fra due pezzi non uniti da un tratto pieno restano almeno `Timeline.BREAK_PX` = 3 px (le estremità
  disegnate si spostano di al più 1,5 px). Una colonna con un buco o una stima al suo interno si divide in **due** pezzi
  (`Timeline.View` aggiunge `dash` a `cut`): la prima corsa di tratti pieni sul bordo sinistro, tutto il resto sul
  destro, ognuno con la sua barra minima–massima. Mai più di due, così colonne più larghe danno sempre meno regioni. Un tratteggio ha sempre uno spazio
  alle due estremità; sotto i 7 px è un solo trattino lungo metà del tratto, sotto `Timeline.DASH_MIN` = 3 px resta un
  vuoto (un trattino così corto sembrerebbe pieno). Una lettura senza tratti pieni accanto è un punto; i tratti che
  entrano o escono dalla vista si tagliano al bordo.
- **Bande e corsie** hanno la risoluzione di mezza colonna: bande di buco più vicine si uniscono e ognuna è larga almeno
  quanto la risoluzione; sotto gli 8 px la banda mostra una sola striscia con uno spazio ai lati, perché la texture
  `dash` sembrerebbe piena. In una corsia resta un pezzo per mezza colonna, vince DANGER, poi UNKNOWN, WARNING, SAFE;
  buchi dell'unità e di tutto il grafico (tranne *nessun mob*) si disegnano tratteggiati sopra. Allargando le colonne al
  limite dei pool anche bande, corsie e icone si diradano, senza che sparisca nessun intervallo.
- La banda *state only* di una sessione mista è `surface-3`. Nella card di una sessione mista compaiono anche le corsie
  delle unità che hanno solo stati. Un superamento senza lettura entro `join` e senza corsia (nella card) sta in fondo al
  grafico.
- La card *Timeline* del report non ha lo zoom (la rotella scorre il report); il clic chiede `REPLAY_REQUESTED(id, t)`
  solo con l'interruttore `replay`, che mostra anche la riga *Click to open the replay at that time*.
- `Theme.Paint(region, "fill" | "tint", token, alpha)` dà il solo colore di una regione di un pool riusata. Le serie
  seguono [ui-style §3.5](ui-style.md#35-timeline-e-replay-m5). `/atw debug` aggiunge la riga dei pool (regioni create,
  limiti, quante volte si sono allargate le colonne, `lines`).

**Realizzato in M5.4** (`Data/Replay.lua`), con queste precisazioni:

- **Apertura**: `Replay.Open` butta subito il replay aperto; una costruzione superata risponde `false, "replaced"`
  (un altro `Open`) o `false, "closed"` (`Close`); `Replay.Building()` dice l'`id` in costruzione. La velocità si scrive
  in `char.ui.replay.speed` (`Replay.SPEED_PATH`): finché lo schema 2 del personaggio non c'è (M5.5), o con i dati in
  sola lettura, `Config` la rifiuta e la scelta vale fino al `/reload`.
- **Riproduzione**: `Play` riparte dall'inizio della vista anche quando il cursore è **prima** della vista;
  `Replay.CanPlay()` dice se partirebbe (`closed`, `combat`; `Play` senza timer risponde `no-timer`). Una vista nuova che
  lascia fuori il cursore mentre si riproduce mette in pausa. Uno spostamento fuori dalla vista la fa scorrere **con il
  cursore al centro** (entro la sessione). A `COMBAT_STARTED` e `COMBAT_ENDED` parte `OnChange("play")`.
- **Focus**: resta finché il cursore è nella finestra dell'evento (`[t − 50, t + 50]`); uscendone (passo, salto, ricerca
  o riproduzione) cadono focus e selezione. `NextEvent` fa il `Focus` dell'evento trovato e, fra eventi dello stesso
  decimo, li percorre uno per uno. `Replay.ToggleSeries(u)` è il clic sul nome di §5.4; `Replay.LastRow()` la riga
  dell'ultimo evento passato; `Replay.ListNote(list)` il testo di un elenco: *Only the start and the end of combat were
  recorded.* quando la sessione ha solo `C` e `c` e l'elenco del filtro ha righe, *No event in this filter.* quando è
  vuoto.
- **Dettaglio**: decide **l'ultima riga dell'unità sul mob monitorato**. Una riga senza numero più recente di una
  lettura la sostituisce (con il suo motivo); una lettura non passa mai oltre un'interruzione registrata dopo di lei
  (cambio di target, fine del combattimento, pausa della registrazione anche mentre è in corso, modalità `none` o
  `state`, limite dei campioni, uscita dalla lista): il motivo è la prima. La situazione di *state only* vale finché
  nulla la interrompe (le righe senza numero si scrivono solo al cambio, §1.3). *Since* è l'ultima lettura con un numero
  su quel mob, altrimenti l'inizio del tratto senza numeri; senza righe, *No reading recorded: not read yet*. Fuori dal
  combattimento il dettaglio non ha mob, modalità, detentore né unità; la fine dell'asse appartiene a ciò che finisce lì.
- **`state.moment`** sale solo quando il cursore passa qualcosa di registrato (una riga, un evento, il bordo di un
  buco, una lettura che supera `join` o `ESTIMATE_MAX`): la finestra rilegge il dettaglio solo allora (l'età di una stima
  la ricalcola dal cursore). `Replay.Snapshot` riusa la sua tabella e non alloca.
- **Dati mancanti**: i tratti *state only* sono una voce del mob intero (*State only, no percentages A–B*), non una per
  unità; *nessuna lettura in questa finestra* vale per le unità che erano nella lista mentre i valori erano leggibili,
  senza letture e senza un buco proprio nella finestra. `Replay.EventDetail(i)` dà l'evento, le letture delle unità che
  nomina (per `A` anche chi teneva il mob prima) e i dati mancanti della finestra; le parole del dettaglio, dei dati
  mancanti e degli elenchi sono le chiavi `REPLAY_*`.
- **Costo** (prova lunga, 30 000 righe e 40 unità): tick al più 870 istruzioni e 0 byte; dettaglio di 40 unità circa
  26 000 istruzioni e 0 byte (budget 60 000); aprire con il modello già in memoria circa 690 000 istruzioni in un frame
  (gli indici del replay; budget 2 000 000, come la vista della timeline).
- `Timeline.TimeText` e `Timeline.PercentText` passano da `UI/Timeline.lua` a `Data/Timeline.lua`; `/atw debug` aggiunge
  alla sezione *Timeline and replay* lo stato del replay e il costo misurato del tick.

**Realizzato in M5.5** (`UI/ReplayWindow.lua`, schema 2 del personaggio), con queste precisazioni:

- **Interfaccia**: `ReplayWindow.Open(id, t)` (falso con un interruttore spento), `ReplayWindow.Close()`; gli stati sono
  `building`, `ready`, `damaged`, `recording`, `unknown` (eliminata) e `failed` (*The timeline could not be built.*). Chiedere
  di nuovo la registrazione aperta muove solo il cursore. Gli ascoltatori si registrano al `PLAYER_LOGIN` con gli
  interruttori accesi; la finestra e il controllore si legano al primo `Open`.
- **Chiusura**: chiuderla (✕, Esc) chiude il replay e lascia il modello; nascosta con tutta l'interfaccia (Alt+Z) tiene il
  replay e lo mette in pausa. In `recording` la finestra si riapre sulla registrazione quando finisce
  (`SESSIONS_CHANGED`, `SESSION_ENDED`).
- **Tastiera**: `EnableKeyboard(true)` solo fuori dal combattimento e dopo `SetPropagateKeyboardInput(true)`; a
  `COMBAT_STARTED` solo `EnableKeyboard(false)`, così nessuna funzione della tastiera si chiama in lockdown. Un client
  senza `SetPropagateKeyboardInput` non ascolta mai (si prenderebbe ogni tasto). «Il puntatore sopra la finestra» è
  `IsMouseOver()` del frame al momento del tasto. Le azioni dei tasti e dei pulsanti sono le stesse
  (`Replay.KeyAction`, `Replay.Do`); `Replay.SetSelection(a, b)` tiene l'intervallo trascinato sul grafico, che toglie il
  focus.
- **Comandi**: gli eventi precedente e seguente sono due frecce dello stesso foglio (`step-back`, `step-forward`)
  affiancate. Quando i testi di *Zoom to selection* e *Whole fight* non stanno nella riga diventano i pulsanti con le icone
  `search` e `refresh` (testo nel tooltip), e solo se non stanno neanche quelli vanno a capo.
- **Disposizione**: nel pannello unico il filtro sta sulla riga del selettore *Events · Details*; il titolo *Events* si
  mostra se c'è posto accanto al filtro. Il grafico prende il 55 % sotto la barra del titolo (di più quando le corsie lo
  chiedono) e si restringe per lasciare alla parte bassa almeno 92 pt: a 640 × 420 restano almeno due righe di eventi.
  I collegamenti *Continued from…* e *Continues in…* hanno una riga sotto il titolo; l'intestazione di una sessione
  troncata non ha un distintivo (la banda sul grafico e la riga del dettaglio lo dicono).
- **Dettaglio**: righe di testo e righe delle unità da due pool; la categoria di ogni riga è nel suo tooltip, le stime nel
  colore `warn` e gli sconosciuti `text-3`. Con un focus l'evento (letture intorno e dati mancanti) sta sopra *At …*. Si
  rilegge solo quando cambiano `state.moment` o il focus; fra l'uno e l'altro si aggiornano l'ora e l'età delle stime.
- **Salvataggi**: schema 2 del personaggio ([SPEC-02 §3.9](SPEC-02-data-model-storage.md#39-schema-2-del-personaggio-m5-la-finestra-del-replay));
  `/atw reset` non tocca posizione e dimensione del replay ([Q21](SPEC-09-risks-open-questions.md)).
- **Comando**: `/atw replay` senza numero salta la registrazione in corso (e lo dice se è l'unica); `/atw replay n` con un
  numero che non c'è risponde *No recording number n: the list has m.*
- **Prova lunga** (`Tests/long/test_replay_long.lua`): 210 aperture di sessioni a 30 000 righe, 15 eliminate dalla
  potatura mentre erano aperte; dopo il riscaldamento frame, regioni del grafico, righe e memoria dello stato Lua non
  crescono.

## 10. Piano di M5: test per step

Le sessioni dei test si scrivono con il recorder vero da uno scontro scriptato (`Fight`, nei tre esiti di
`Fight.OUTCOMES`) o si costruiscono a mano con `Data/Session.lua` quando serve un caso esatto (un buco di un tipo,
`p = 3843`, `trunc`).

| Step | Test e casi |
|---|---|
| **M5.2** | `test_timeline.lua`: sessioni note con modelli noti: ogni tipo di tratto (pieno a `join`, tratteggiato oltre, nessuno per ogni causa di §4.3 e oltre `ESTIMATE_MAX`), ogni buco di §4.4 con il motivo, ogni marcatore di §4.5, superamenti uguali a quelli del report, esito (`values`, `state`, `none`, `mixed`), sessione interrotta, troncata, con `after`, `p = 3843`; serie predefinite e corsie nell'ordine di §4.7; `View` uguale a una ricerca per forza bruta su sessioni a caso (prima, ultima, minima, massima per colonna), viste strette e larghe, nessuna allocazione dopo il riscaldamento; costruzione a fette uguale a quella intera; stessa sessione, stesso modello (RPL-01); interruttore spento. In `Tests/long/test_monitor_budget.lua` (o un file lungo nuovo) il budget di `View` a 30 000 righe |
| **M5.3** | `test_timeline_widget.lua`: la matematica del disegno (tempo ↔ x, scala y e tetto a 150 %, tacche dell'asse, colonne, trattini per tratto, raggruppamento dei marcatori, limite dei pool e raddoppio di `BUCKET_PX`, il ripiego senza `CreateLine`), la lettura più vicina del tooltip in ogni categoria, clic contro trascinamento, rotella, riepilogo dell'intervallo; nessun colore fuori dal tema. `test_theme.lua`: i token `series-*` in ogni tema con i contrasti. `test_reports.lua`: la card *Timeline* (costruzione, esiti, clic con e senza `replay`). Il client finto aggiunge le regioni `Line` (`CreateLine`, `SetStartPoint`, `SetEndPoint`, `SetThickness`, dal dump) e `GetCursorPosition` |
| **M5.4** | `test_replay.lua`: aprire e chiudere; riproduzione con il tempo finto a ogni velocità, pausa alla fine, salti del client fermo; passi sui momenti registrati; ±5 s; evento seguente e precedente con i filtri; `Focus` con la finestra tagliata ai bordi; `Seek` dentro e fuori dalla vista; dettaglio con le tre categorie e i motivi nei tre esiti; dati mancanti (anche *nessuno*); pausa e rifiuto in combattimento; sessione eliminata mentre è aperta; interruttori spenti; il tick non alloca. `test_coach_wording.lua` esteso alle chiavi `TIMELINE_*` e `REPLAY_*` |
| **M5.5** | `test_replay_window.lua`: apertura dal pulsante, dalla card, da `/atw replay [n]` e da `REPLAY_REQUESTED`; disposizione larga e a pannello unico; ogni riga della tabella degli stati di §5.5; tasti solo fuori dal combattimento e con il puntatore sopra, gli altri tasti lasciati al gioco; Esc; posizione, dimensione e velocità per personaggio dopo un `/reload`; sola lettura; il tema. `test_config.lua`: lo schema 2 del personaggio e la migrazione da dati dello schema 1. `test_commands.lua`: `/atw replay`. `Tests/long/test_replay_long.lua` (fonte §13, *apertura e chiusura ripetuta del replay*): sessioni ai limiti aperte, riprodotte, cercate e chiuse più di 200 volte, anche in combattimento e con la potatura; pool, righe, regioni e memoria che smettono di crescere. Manuale *Threat Replay* nelle due lingue con le anteprime |
| **M5.6** | `docs/checklists/M5.md`: ogni riga *Real client* di M5.2–M5.5 e il criterio di uscita |
