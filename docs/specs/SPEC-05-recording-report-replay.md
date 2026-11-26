# SPEC-05: Registrazione, report, timeline e replay

> Fonte: [specifiche originali](source-specification.md) §5.3, §5.4, §7.4, §7.5, §9, §10, §13. §1–§3 completati in
> **M4.1** (prima del probe M0, come M2 e M3: decisione D7), con il formato dei dati in
> [SPEC-02 §3.7 e §4](SPEC-02-data-model-storage.md#4-sessioni-registrate-schema-4-m4) e la decisione di architettura
> in [ADR 0016](../adr/0016-recordings-are-the-monitors-readings-in-compact-columns.md); §4–§5 da completare in **M5.1**.

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
- Budget proposto (misurato in M4.6 con `Tests/long/test_monitor_budget.lua`, una terza configurazione con la
  registrazione): il tick di registrazione a 40 unità sotto il **10 %** del lavoro di un tick del monitor (circa 22 000
  istruzioni), nessuna crescita di memoria per tick oltre ai pezzi; il numero esatto lo fissa M4.6 in SPEC-01 §5.1.
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

`Storage.List()` (intestazioni, la più recente prima, mai le colonne), `Storage.Get(id)`, `Storage.Usage()`
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

## 4. Timeline (M5)

Rappresenta nel tempo: threat del tank, giocatori più vicini alla soglia, percentuale relativa, cambi di target,
eventi, momenti di superamento. Supporta selezione di un intervallo, pausa e riproduzione, salto avanti e indietro,
dettaglio del campione, **distinzione visiva tra dati rilevati e stime** (linea piena e tratteggiata) e buchi visibili.

## 5. Replay (M5)

Elenco degli ultimi scontri con durata; timeline; eventi in ordine cronologico; selezione di un evento per vedere i
dati attorno (±5 s); indicazione dei dati mancanti; eliminazione delle registrazioni.

## 6. Moduli, eventi, interruttori e diagnostica (M4)

| File | Responsabilità | Bus | Step |
|---|---|---|---|
| `Data/Session.lua` | la sessione di SPEC-02 §4: creazione, voci di `units` e `mobs`, alfabeto e codici, righe ed eventi in `buf`, impacchettamento a pezzi, unione alla chiusura, decodifica; nessuna API del gioco, nessun evento | — | M4.2 |
| `Data/Recorder.lua` | condizioni (§1.1), ciclo di vita (§1.2), tick (§1.3), eventi (§1.4), reload e logout (§1.6), consumatore `recorder` dello Scanner | ascolta `COMBAT_STARTED`, `COMBAT_ENDED`, `TARGET_CHANGED`, `STATE_CHANGED`, `AGGRO_CHANGED`, `THREAT_MODE_CHANGED`, `ALERT_RAISED`, `COACH_TIP`, `DEMO_CHANGED`, `CONFIG_LOADED`, `CONFIG_CHANGED`, `ENTERING_WORLD`; dal gioco `PLAYER_LOGOUT`, `UNIT_DIED`, `PLAYER_DEAD`, `ENCOUNTER_START`, `ENCOUNTER_END`; emette `SESSION_STARTED(id)`, `SESSION_ENDED(id, state)` | M4.2 |
| `Data/Storage.lua` | caricamento e controlli (§2.2), sessioni messe da parte, potatura e stima (§2.4), eliminazione (§2.5), sola lettura (§2.6), interfaccia (§2.7) | ascolta `CONFIG_LOADED`, `CONFIG_CHANGED`, `ENTERING_WORLD`, `COMBAT_ENDED`; emette `SESSIONS_CHANGED()` | M4.3 |
| `Data/Report.lua` | metriche (§3.2–§3.3), costruzione a fette e riepilogo (§3.4) | ascolta `SESSIONS_CHANGED` | M4.4 |
| `UI/CoachStrip.lua` (cambio) | l'avviso di fine scontro (§3.5) | ascolta `SESSION_ENDED` | M4.4 |
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

- **Interruttori** (`Core/Features.lua`, ADR 0014): `recording` (recorder, Storage, card *Recording*) e `reports`
  (report, scheda, avviso, `/atw reports`) restano **spenti** fino a M4.R. Spento vuol dire: nessun ascoltatore e nessun
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
