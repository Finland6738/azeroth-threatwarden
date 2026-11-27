# SPEC-06: Analytics ed esportazione

> Fonte: [specifiche originali](source-specification.md) §4.2, §5.5, §10, §13 (Milestone 4 della fonte: *Analytics*,
> con l'esportazione *se praticabile*). Completato in **M6.1**, prima del probe M0 come M2–M5 (decisione D7), con i
> moduli e i test per step in §5–§6 e la decisione di architettura in
> [ADR 0018](../adr/0018-analytics-and-export-are-computed-in-memory-and-leave-only-through-a-copy-box.md).

Fonte §5.5, metriche *solo se i dati raccolti sono sufficienti*: numero di superamenti di soglia; durata in
WARNING/DANGER; numero di cambi di target; giocatore con maggiore threat osservata; intervalli di threat più instabile;
frequenza di situazioni di rischio per scontro; confronto tra scontri registrati. Niente classifiche accusatorie
(*peggior DPS*): indicatori descrittivi, contestualizzati e verificabili. Fonte §13, criteri: ogni metrica è
riconducibile ai dati registrati; i dati insufficienti sono segnalati; nessuna causa non dimostrata.

## 0. Principi

- **Si legge soltanto.** Analytics ed esportazione leggono le sessioni registrate (SPEC-02 §4) con `Storage.Decode`,
  come il report e la timeline; non scrivono nulla nelle sessioni, non aggiungono chiavi né schemi (l'account resta
  allo schema 5, il personaggio allo schema 2) e non leggono nulla dal gioco. Ciò che calcolano sta in memoria e si
  butta quando la sessione non c'è più.
- **Le stesse definizioni del report.** Dove una metrica c'è già nel report (SPEC-05 §3.2) o nella timeline (SPEC-05
  §4), Analytics usa **le stesse funzioni** (`Report.Compute`, `Report.Walk` con i suoi richiami, `Report.Intervals`):
  superamenti, tempi in WARNING e DANGER, percentuale massima, prese dell'aggro, cambi di tank, qualità dei dati sono
  **gli stessi numeri** del report sulla stessa sessione (test). Analytics aggiunge soltanto ciò che il report non ha
  (§1.4) e una regola in più, ANA-02, che può dire *Insufficient data* dove il report mostra un limite inferiore: non è
  una contraddizione, è una soglia più severa per **descrivere e confrontare**, e il tooltip lo dice.
- **I tre esiti** ([SPEC-03 §1.1](SPEC-03-threat-monitor-ui.md#11-tre-esiti-del-probe-tre-modalità), SPEC-05 §0 e
  §4.6) valgono per sessione e per tratto di tempo:

| Esito | Metriche di Analytics | Confronto | Esportazione |
|---|---|---|---|
| **values** | tutte (§1.4), stati dalle soglie registrate | tutte le metriche, fra sessioni con le stesse soglie | tutto, con le categorie |
| **state only** | tutte tranne le percentuali (*Not available*, motivo `state-only`); superamenti, tempi, instabilità e rischio sugli **stati del gioco** (*game states*) | con le altre *state only* per stati e rischio; i cambi di chi tiene il mob con tutte | tutto, le percentuali vuote con lo stato `na` |
| **nothing readable** | il contesto (durata, nemico, combattimenti, morti, qualità dei dati con il motivo prevalente); ogni altra metrica *Not available* | solo il contesto; la sessione non entra negli aggregati della threat | il contesto e gli eventi; letture solo come righe sconosciute con il motivo |

- **Nessuna classifica, nessun verdetto** (ANA-01): Analytics non ordina mai le persone per una metrica, non dice
  *peggiore*, *migliore*, *colpa*, *bravo*, non dice che uno scontro è *andato meglio* di un altro; mostra numeri con
  il loro contesto (durata, campioni validi, soglie) e chi li legge giudica.
- **Esce dal gioco solo ciò che il giocatore copia** (ADR 0001): l'esportazione è un testo in una casella da copiare con
  Ctrl+C; nessun file, nessuna rete, nessun messaggio dell'addon, nulla in chat.

## 1. Metriche per sessione (`Data/Metrics.lua`, M6.2)

### 1.1 Regole

- **ANA-01** MUST: niente classifiche accusatorie né giudizi soggettivi (fonte §5.5): nessun elenco di persone ordinato
  per una metrica di Analytics (le unità seguono l'ordine del report: il giocatore, i tank designati, poi l'indice
  delle voci di `units`); nessuna parola di colpa o di merito; nessuna tendenza dichiarata fra scontri (*improving*,
  *getting worse*). Le parole (chiavi `ANALYTICS_*` ed `EXPORT_*`) passano la prova di SPEC-04 §2.4 (WR-01–WR-07, in
  particolare WR-05), estesa in M6.2 con l'elenco delle parole di merito vietate.
- **ANA-02** MUST: con meno del **50 %** di campioni validi (§1.2) una metrica si mostra come **Insufficient data**
  (*Dati insufficienti*), con la percentuale nel tooltip; lo stesso se il nemico è stato monitorato per meno del 50 %
  del tempo di combattimento.
- **ANA-03** MUST: ogni metrica si calcola **solo** dalle righe e dagli eventi della sessione (si può rifare con lo
  stesso risultato, come REC-10); dove il report ha la stessa metrica il valore è identico (test sulle stesse sessioni).
- **ANA-04** MUST: ogni valore porta la sua categoria (ADR 0003): *rilevata* per un conteggio di eventi o una lettura,
  *calcolata* per ciò che ne deriva, *stimata* (*at least* / *almeno*) quando i dati mancavano in parte; mai una
  previsione né un'ipotesi. *Not available*, *Insufficient data* e *Unknown* non sono mai 0.
- **ANA-05** MUST: Analytics non scrive nulla in `sessions` né altrove nelle SavedVariables; con la sessione eliminata
  il suo calcolo in memoria si butta (STO-03 resta vero: i nomi non restano da nessuna parte).

### 1.2 Basi: tempo di combattimento, tempo noto, campioni validi

Tutte dai periodi del report (SPEC-05 §3.3), con `Report.Walk`:

- **Combattimento** `combat` = l'unione dei periodi `C…c` (un `C` senza `c` fino all'ultimo record).
- **Monitorato** `watch` = l'unione dei periodi di mob monitorato dentro il combattimento (richiamo `watch`).
- **Sconosciuto del mob** = `watch ∩ (none ∪ gaps)`: i tratti con la modalità `none` e i buchi `G` del tick.
- **Tempo noto** `known` = `|watch| − |watch ∩ (none ∪ gaps)|`, in decimi.
- **Copertura** `coverage` = `known / |combat|` (in %, arrotondata); `nil` se `|combat| = 0`.
- **Campioni validi** dai contatori `q` della sessione (gli stessi della qualità dei dati del report): su tutte le unità
  `V = Σq.v`, `S = Σq.s`, `X = Σq.x`, `N = V + S + X`. Ci sono **due basi**, perché le metriche non chiedono gli stessi
  dati:
  - base **stato** (superamenti, tempi, cambi di chi tiene il mob, instabilità, rischio): `valid = (V + S) / N`;
  - base **valori** (percentuali): `valid = V / N`.
  Per una metrica di un'unità si usano i contatori di quell'unità (`q.v[i]`, `q.s[i]`, `q.x[i]`).
- Con `N = 0` (nessun tick: nessun mob monitorato mai) le metriche della threat sono *Insufficient data* con il motivo
  `no-ticks`, come la qualità dei dati del report.

### 1.3 Lo stato di una metrica

Ogni metrica è una **cella** come quelle del report (`{ key, category, status, value, reason, lower, basis,
truncated, until }`, SPEC-05 §6, *Realizzato in M4.4*). Lo stato si decide in quest'ordine, e il primo che vale vince:

1. **`na`** (*Not available*) se la base non c'è mai stata nella sessione: base valori con `V = 0` e nessuna riga con un
   numero (motivo `state-only` se c'erano stati, altrimenti il motivo prevalente del report: `secret`…); base stato con
   nulla di leggibile (motivo prevalente).
2. Lo stato del report per la stessa metrica, se il report ce l'ha: `insufficient` con `few-rows`, `few-values`,
   `little-known`, `no-ticks`; `na` con il suo motivo.
3. **ANA-02**: `insufficient` con `low-valid` se `valid < Metrics.MIN_VALID` = **50** % sulla base della metrica (della
   sessione o dell'unità); con `little-monitored` se `coverage < Metrics.MIN_COVERAGE` = **50** % (solo per le metriche
   della sessione).
4. Il minimo della metrica (§1.4, colonna *Insufficient data quando*).
5. **`ok`**; poi il **limite inferiore**: la categoria diventa *stimata* e il valore dice *at least* quando il report
   segna il limite per quell'unità (`partial`: tempo sconosciuto o righe senza valore), quando la sessione ha tempo
   sconosciuto del mob (`|watch ∩ (none ∪ gaps)| > 0`) per una metrica della sessione, o quando gli eventi si sono
   fermati al loro limite (`Z e`) per una metrica dagli eventi.

Il tooltip di ogni cella dice: la categoria con le parole di M2.5, che cosa misura, la base (*thresholds 82 / 91* o
*game states*), i campioni validi e la copertura, il motivo di uno stato non `ok`, *at least* e perché, fin dove valgono
i dati (*Recorded until 2:31*, *Samples stopped at 3:10*).

### 1.4 Le metriche

Tempi in decimi, percentuali in decimi di % come la colonna `p` (SPEC-02 §4.2).

| Chiave | Che cosa | Come si calcola | Categoria | values | state only | nulla leggibile | *Insufficient data* quando |
|---|---|---|---|---|---|---|---|
| `context` | durata, tempo in combattimento e pull, nemico principale, incontro, gruppo, istanza, difficoltà, unità osservate, soglie e frequenza registrate (`rec`), esito (SPEC-05 §4.6), stato della sessione | le righe `duration` e `mob` del report e l'intestazione | rilevata (durata *at least* in una sessione interrotta, come il report) | sì | sì | sì | mai |
| `valid` | campioni validi e copertura | §1.2: *Values 82 % · State only 0 % · Unknown 18 %* (la qualità dei dati del report) e *Enemy monitored 96 % of combat* | calcolata | sì | sì | sì (*Unknown 100 %* con il motivo prevalente) | `N = 0` |
| `crossings` | **superamenti di soglia** di tutte le unità: entrate in WARNING e in DANGER, separate | `Σ warningCross`, `Σ dangerCross` sulle unità la cui cella del report (e ANA-02 dell'unità) è `ok`; le unità escluse si contano (*2 units with too little data not counted*) e rendono la somma un limite inferiore | calcolata (stimata con copertura parziale o unità escluse) | dalle soglie `rec` | stati del gioco | `na` | ANA-02 (base stato) o nessuna unità `ok` |
| `stateTime` | **tempo in WARNING e DANGER** con almeno un'unità nello stato: `warningAny` (WARNING o DANGER) e `dangerAny` (DANGER) | l'unione degli intervalli di stato del richiamo `state` di `Report.Walk` (già tagliati ai periodi di combattimento e di mob, SPEC-05 §3.3): `|∪ W ∪ D|` e `|∪ D|`; più, per unità, i `warningTime` e `dangerTime` del report | calcolata (stimata con tempo sconosciuto) | sì | *game states* | `na` | ANA-02; `known < Report.MIN_KNOWN` (1 s) |
| `holders` | **cambi di target del nemico**: le volte che un'altra unità ha preso il nemico da chi lo teneva | gli eventi `A` che il report conta (in combattimento, mob > 0, unità con una voce: nuovo richiamo `holder` di `Report.Walk`, §5) con il vecchio detentore noto (`v` con una voce): totale e divisi in *tank → tank* (`a = b = 1`, i *cambi di tank* del report), *verso un non tank* (`a = 0`, le *perdite dell'aggro* del report con *da chi*), *di nuovo a un tank* (`a = 1`, `b = 0`); il primo detentore di un periodo di mob non è un cambio. Più, come contesto, i cambi del **nemico monitorato** (eventi `T` verso un altro mob in combattimento) | rilevata (stimata con tempo sconosciuto o eventi fermi al limite) | sì | sì | `na` | ANA-02 (base stato) |
| `aggroTaken` | prese del nemico da parte di un **non tank** | il numero delle perdite dell'aggro del report (ogni `A` con `a = 0`, anche il primo detentore) | rilevata (stimata come sopra) | sì | sì | `na` | ANA-02 (base stato) |
| `maxPct` | **threat massima osservata**, per unità | la *percentuale massima registrata* del report (il massimo di `p` sulle righe con un numero, con l'ora e il nemico); `p = 3843` è *at least 384.3 %* | rilevata | sì | `na` (`state-only`) | `na` | report (meno di 3 righe con un numero); ANA-02 (base valori, dell'unità) |
| `maxNotHolding` | **la threat più vicina al tank**: la percentuale più alta registrata da un'unità che **non** teneva il nemico | il massimo di `p` sulle righe con codice `0` o `1` (la situazione dice che l'unità non lo teneva, SPEC-02 §4.2), con l'unità, l'ora e il nemico; le righe `4` (situazione illeggibile) non contano. È la *maggiore threat osservata* della fonte senza il detentore, che sta sempre a 100 % | rilevata (stimata a 3843) | sì | `na` (`state-only`) | `na` | meno di `Report.MIN_ROWS` = 3 righe `0`/`1`; ANA-02 (base valori) |
| `unstable` | **intervalli instabili**: tratti con molti cambi di stato o di chi tiene il nemico | §1.5: quanti, il tempo totale, i primi `Metrics.MAX_UNSTABLE` = **20** con inizio, fine, cambi di detentore e superamenti | calcolata (stimata con tempo sconosciuto) | sì | *game states* | `na` | ANA-02 (base stato e copertura) |
| `risk` | **frequenza delle situazioni di rischio** | `situations = Σ dangerCross + aggroTaken` (entrate in DANGER delle unità contate in `crossings` più le prese di un non tank); `perMinute = situations × 600 / known`, con un decimale | calcolata (stimata se una delle due parti è un limite inferiore) | sì | *game states* | `na` | ANA-02; `known < Metrics.MIN_RATE_TIME` = **300** decimi (30 s) |
| `deaths`, `alerts` | morti e avvisi, come contesto | le righe `deaths` e `alerts` del report; senza eventi *No death recorded* (mai *no deaths*, P7) | rilevata | sì | sì | morti sì, avvisi `na` | mai |

Per unità (`units[i]`, una per voce di `units`, nell'ordine del report): le celle del report (`warningCross`,
`dangerCross`, `warningTime`, `dangerTime`, `maxPct`, `aggro`, `quality`) con ANA-02 sui contatori dell'unità in più,
il ruolo, la classe, il nome (o il token) e `me`. Le unità non hanno metriche diverse da quelle del report: Analytics
le usa per il confronto del giocatore (§2) e per l'esportazione (§4).

Parole: *Threshold crossings* · *Time with a unit in Warning / Danger* · *Enemy changed hands* (*Cambi di chi tiene il
nemico*) · *Taken by a non-tank* · *Highest recorded percentage* · *Closest to the tank* (*Più vicino al tank*: la
percentuale più alta di chi non teneva il nemico) · *Unstable intervals* · *Risk situations* (*per minute of known
combat*). Nel testo inglese il mob è *enemy*, come nel report.

### 1.5 Intervalli instabili

1. I **cambi** di una sessione sono, in ordine di tempo: i cambi di detentore di `holders` (non il primo detentore) e i
   superamenti di `crossings` (il richiamo `cross` di `Report.Walk`: entrate in WARNING e DANGER con la regola del
   report), di tutte le unità.
2. Con `W = Metrics.UNSTABLE_WINDOW` = **100** decimi (10 s) e `K = Metrics.UNSTABLE_MIN` = **3** cambi: per ogni cambio
   `i`, se il cambio `i + K − 1` è nello **stesso periodo di combattimento** e `t[i + K − 1] − t[i] ≤ W`, l'intervallo
   `[t[i], t[i + K − 1]]` è instabile.
3. Gli intervalli che si toccano o si sovrappongono si uniscono. Ognuno ha `from`, `to`, i cambi di detentore e i
   superamenti che contiene; un intervallo con `from = to` (tre cambi nello stesso decimo) è un **momento** (*at 1:12*).
4. Il totale è il numero degli intervalli e la somma delle loro durate. Nessun intervallo: *No unstable interval
   recorded* (mai *stable*).
5. Con tempo sconosciuto del mob (§1.3 punto 5) la metrica è un limite inferiore: un cambio poteva mancare. Un clic su un
   intervallo (con l'interruttore `replay`) apre il replay al suo inizio (`REPLAY_REQUESTED(id, from)`).

`W` e `K` sono una proposta ([Q22](SPEC-09-risks-open-questions.md)): in un raid l'ingresso di molti DPS in WARNING
all'inizio basta a fare un intervallo; è ciò che la fonte chiede (*molti cambi di stato*) e la riga dice quanti sono
superamenti e quanti cambi di detentore.

### 1.6 Sessioni interrotte, troncate, collegate, miste

- **Interrotta** (`state = "interrupted"`): ogni metrica vale fino all'ultimo record, come il report (*Recorded until
  m:ss*); la durata è *at least*; i conteggi e i tempi sono quelli registrati e nel **confronto** diventano limiti
  inferiori dello scontro (stimati, *at least*), mentre `risk.perMinute` e le percentuali restano come sono (sono per
  tempo noto o letture).
- **Troncata** (`trunc`): le metriche dai campioni (`maxPct`, `maxNotHolding`, campioni validi) valgono fino a `trunc` e
  lo dicono (*Samples stopped at 3:10*); quelle dagli eventi continuano fino al limite degli eventi. Con `Z e` le metriche
  dagli eventi sono limiti inferiori.
- **Collegata** (`after`, un `/reload` in combattimento): due sessioni restano **due** (nessuna unione); la seconda ha il
  distintivo *Continues* e il collegamento, come nel report ([Q23](SPEC-09-risks-open-questions.md)).
- **Mista** (la modalità cambia a metà): le metriche di stato hanno la base `mixed` (*thresholds and game states*); le
  percentuali contano solo i tratti `values`, con la base valori di §1.2.
- **Danneggiata**: `Metrics.Build` risponde `damaged`, come il report.

### 1.7 Il modello e la costruzione

```lua
metrics = {
    id = "1764100000-1", key = "npc:448",     -- la chiave del confronto (§2.1), nil se il nemico non si riconosce
    outcome = "values",                       -- values | state | none | mixed (le regole di SPEC-05 §4.6)
    state = "complete", ended = "combat", after = nil, trunc = nil,
    group = "party", inst = "party", diff = 1, role = "DAMAGER",   -- il ruolo del giocatore (`me`), nil se non c'è
    rec = { hz = 2, warning = 82, danger = 91, mode = "values" },
    combat = 1020, known = 980, coverage = 96, valid = { state = 100, values = 82 },
    cells = { context = c, valid = c, crossings = c, stateTime = c, holders = c, aggroTaken = c,
              maxNotHolding = c, unstable = c, risk = c, deaths = c, alerts = c },
    units = { { index = 1, me = true, role = "DAMAGER", cells = { … } }, … },
}
```

- `Metrics.Compute(s, d, step)`: `Report.Compute(s, d, step)` per le celle del report, poi `Report.Walk(s, d, step,
  hooks)` con i richiami `state`, `hold`, `cross`, `watch` e `holder`, poi un passaggio sulle righe per `maxNotHolding`.
  Due passaggi sugli eventi (al più 6 000) e due sulle righe: il costo resta vicino a quello del report.
- `Metrics.Build(id, done)` come `Report.Build`: `Storage.Decode`, poi `Compute` a **fette** di `Metrics.SLICE` =
  5 000 righe o eventi per frame (`Compat.After(0)`), dentro o fuori dal combattimento; `done(metrics)` o
  `done(nil, motivo)` con `off`, `unknown` (anche eliminata durante la costruzione), `recording`, `damaged`, `error`. Il
  risultato a fette è uguale a quello di un'unica passata (test).
- **Cache in memoria** di al più `Metrics.CACHE` = **25** sessioni (la meno usata esce), per `id` e per tabella della
  sessione (`Storage.Get(id)` deve essere la stessa tabella); si butta a `SESSIONS_CHANGED` per le sessioni che non ci
  sono più. Mai salvata.
- `Metrics.Text(metrics, cell)`, `Metrics.Tooltip(…)` danno le parole (chiavi `ANALYTICS_*`).

**Realizzato in M6.2** (`Data/Metrics.lua`, il cambio di `Data/Report.lua`), con queste precisazioni:

- `Report.Walk` ha un quinto richiamo facoltativo, `holder(u, m, t, evento)`, chiamato dove il report conta un `A` (in
  combattimento, mob > 0, unità con una voce); `Report.Compute` non lo passa e i risultati del report non cambiano.
  `Metrics.Compute` usa i richiami `state`, `cross`, `watch` e `holder` (`hold` non serve: il tempo tenuto è già nel
  report). Oltre ai due passaggi di §1.7 fa un **passaggio breve sugli eventi** per il pull di ogni cambio (§1.5) e per
  le bande della modalità, con le quali l'esito (`values`, `state`, `none`, `mixed`) è quello della timeline (SPEC-05
  §4.6) sulla stessa sessione (test).
- ANA-02 confronta **senza arrotondare**: 49,6 % è sotto il 50 %; le percentuali mostrate (`valid`, `coverage`) sono
  arrotondate. Ogni cella della sessione porta `valid` (sulla sua base) e `coverage` per il tooltip.
- Motivi nuovi, oltre a quelli del report: `low-valid`, `little-monitored`, `no-units` (nessuna unità `ok` per
  `crossings`), `few-not-holding` (meno di 3 righe `0`/`1`), `short-known` (meno di `MIN_RATE_TIME` noti per `risk`).
  `risk` prende lo stato non `ok` di `crossings` o di `aggroTaken`, se ce n'è uno.
- Il limite inferiore dice perché in `lowerBy`: `unknown` (tempo sconosciuto del mob), `events` (`Z e`), `units`
  (unità escluse da `crossings`), `partial` (una cella del report già limite inferiore), `cap` (`p = 3843`).
- `holders.value` è `{ total, tankToTank, toOther, backToTank, other, targets }`: `other` conta i cambi con il segno del
  tank sconosciuto (`-`), `targets` i cambi del nemico monitorato nello stesso combattimento. `aggroTaken` è il numero
  delle perdite dell'aggro del report, quindi conta anche una presa con il vecchio detentore sconosciuto.
- `unstable.value` è `{ count, total, list, changes }` (`total` è il tempo in decimi); `stateTime.value` è
  `{ warningAny, dangerAny, unknownTime }`; `risk.value` è `{ situations, perMinute, known }`.
- Le unità (`units`) hanno le celle del report copiate, con ANA-02 sui contatori dell'unità (`no-ticks` senza
  contatori); `quality` resta quella del report. L'ordine è il giocatore, i tank designati, poi l'indice.
- `Metrics.Key(s, mob)` dà la chiave di §2.1 (per M6.3); `Metrics.Cached(id)` il calcolo in memoria;
  `Metrics.ReasonText(cell)` il motivo breve; `Metrics.IntervalText(iv)` un intervallo instabile. Morti e avvisi hanno
  le parole del report (`Report.CellText`).
- La sezione *Analytics and export* di `/atw debug` si aggiunge al `PLAYER_LOGIN`, dopo *Timeline and replay*, con gli
  interruttori, la cache (sessioni su `CACHE`) e l'ultima costruzione (millisecondi, frame, costruzioni); M6.3 e M6.5
  aggiungono le loro righe. L'ascoltatore di `SESSIONS_CHANGED` si registra alla prima costruzione con l'interruttore
  acceso.

## 2. Confronto e aggregati (`Data/Compare.lua`, M6.3)

### 2.1 Che cosa si può confrontare onestamente

- **Lo stesso nemico.** La **chiave** di una sessione è il suo nemico principale (la riga `mob` del report): `npc:<n>`
  se `mobs[i].npc` c'è (il numero della creatura dal GUID, **[probe P9]**), altrimenti `name:<nome>:<classificazione>`
  se il nome è leggibile, altrimenti nessuna (*Unknown enemy: cannot be compared*). L'incontro (`N`) non è nella chiave:
  è nel contesto.
- **Filtri**, accesi di predefinito ([Q23](SPEC-09-risks-open-questions.md)): *Same group size* (`group`: `party` con
  `party`, `raid` con `raid`, `solo` con `solo`), *Same difficulty* (`diff` uguale; una sessione con `diff` sconosciuto
  passa e lo dice), *Same role* (il ruolo registrato del giocatore, `units[me].role`: acceso, entrano solo gli scontri con il
  ruolo dello scontro più recente; spento, entrano tutti, e le colonne del giocatore dicono *Not comparable: another
  role* negli scontri con un altro ruolo).
- **Le metriche si confrontano solo con la stessa base**: superamenti, tempi, instabilità e rischio fra sessioni con le
  **stesse soglie** registrate (`rec.warning`, `rec.danger`) o tutte con gli stati del gioco; altrimenti la cella dice
  *Not comparable: thresholds 82 / 91 and 80 / 95* (o *game states*, *mixed*) e non entra negli aggregati. Le percentuali
  solo fra sessioni con valori. I cambi di detentore e il contesto con tutte. La frequenza di registrazione diversa
  (`rec.hz`) si dice nel tooltip delle percentuali (più letture al secondo colgono picchi più alti), senza escludere.
- **Al più `Compare.MAX_FIGHTS` = 20** sessioni, le più recenti della chiave dopo i filtri; le altre si contano (*12
  older fights not included*). La registrazione aperta non c'è mai.

### 2.2 Aggregati

Per ogni metrica confrontabile, sulle sessioni dove è `ok` (le altre si contano: *4 of 5 fights*):

| Aggregato | Formula | Categoria |
|---|---|---|
| totale | `Σ` dei valori | calcolata; **stimata** (*at least*) se un valore è un limite inferiore |
| mediana | il valore di mezzo dei valori ordinati; con un numero pari la media dei due di mezzo, con un decimale | calcolata; stimata come sopra (*~*) |
| minimo, massimo | con la data dello scontro | come la metrica di quello scontro |
| frequenza del rischio | `Σ situations × 600 / Σ known` (pesata sul tempo noto, non la media delle frequenze) | calcolata; stimata come sopra |
| campioni validi | mediana, minimo e massimo di `valid` | calcolata |

- **`Compare.MIN_FIGHTS` = 2**: con meno di due sessioni `ok` un aggregato è *Insufficient data* (*Only one comparable
  fight*).
- Nessun aggregato dice una tendenza (ANA-01): l'elenco degli scontri va dal più recente al più vecchio, con la data; chi
  legge vede l'andamento.

### 2.3 Panoramica per nemico

Senza decodificare nulla, dalle intestazioni (`Storage.List`, e per il nemico `Storage.Get(id).mobs[sum.mob]`): una riga
per chiave con il nome e la classificazione, il gruppo, quante registrazioni, il tempo in combattimento totale (`fight`;
*at least* se una sessione interrotta ha `fight = 0`), la data dell'ultima, i campioni validi da `sum.valid` (minimo e
massimo; *unknown* se `sum` manca); le sessioni senza chiave in un'unica riga *Unknown enemies (not comparable)*. Ordine:
l'ultima registrazione prima (mai per rischio o per numeri della threat). Un clic apre il confronto di quella chiave.

### 2.4 Costruzione

- `Compare.Set(key, filters)` → l'elenco delle sessioni (dalle intestazioni) e le escluse con il motivo;
  `Compare.Build(key, filters, progress, done)` costruisce con `Metrics.Build` **una sessione alla volta**, in coda,
  usando la cache; `progress(i, n)` per *Building 4 of 9…*; `done(result)` con le righe e gli aggregati.
- **In combattimento la coda si ferma** (`Compare.PAUSE_IN_COMBAT` = vero, come il replay: il monitor ha la priorità,
  P10) e riparte a `COMBAT_ENDED`; il confronto mostra *Paused during combat*. Il calcolo di una sola sessione (la card
  del report) non si ferma, come il report.
- `SESSIONS_CHANGED`: le sessioni eliminate escono dall'insieme e dagli aggregati, una sessione danneggiata si mostra
  con *damaged* e non conta. Una nuova sessione della chiave entra solo con un nuovo `Build` (il confronto aperto dice
  *1 new fight: Refresh*).
- **Costo**: una sessione al limite (30 000 righe) costa come un report più due passaggi brevi; M6.3 misura venti
  sessioni al limite in una prova lunga (`Tests/long/test_compare_long.lua`): frame per fetta entro il budget del report,
  memoria che non cresce oltre la cache.

**Realizzato in M6.3** (`Data/Compare.lua`, l'aggiunta a `Storage.List`), con queste precisazioni:

- **Intestazioni**: `Storage.List()` dà anche `enemy` (`{ name, class, npc }` del mob `sum.mob`) e `role` (il ruolo
  dell'unità `me`), senza decodificare nulla; `Compare.HeaderKey(h)` ne fa la chiave con `Compare.KEY` =
  `Metrics.Key`, la stessa di `metrics.key` sulla stessa sessione (test). Una sessione senza `sum` non ha ancora un
  nemico noto dalle intestazioni: sta nella riga *Unknown enemies* della panoramica e in nessun insieme finché il
  riepilogo non c'è (Storage lo calcola fuori dal combattimento).
- **Riferimento dei filtri**: lo scontro più recente della chiave dà gruppo e ruolo; la difficoltà è quella del più
  recente con una difficoltà nota. `Compare.Set` dà `fights` (al più `MAX_FIGHTS`), `excluded` con il motivo (`group`,
  `diff`, `role`), `older` e `total`; con i filtri spenti (`{ group = false, … }`) entrano tutti.
- **Base di riferimento**: la base delle metriche di stato dello scontro più recente che ne ha una (`thresholds:80/95`,
  `game`, `mixed:80/95`); una sessione *mista* si confronta solo con altre miste con le stesse soglie. Le metriche dello
  scontro (contesto, cambi di detentore, prese, morti, campioni validi) si confrontano con tutti; quelle del giocatore
  (`my*`) solo con lo stesso ruolo, quelle di stato anche con la stessa base.
- **Misure** (`Compare.MEASURES`): tempo in combattimento, campioni validi (stato e valori), entrate in WARNING e in
  DANGER, i due tempi di stato, cambi di detentore, prese di un non tank, la più vicina al tank, intervalli instabili
  (numero e tempo), frequenza del rischio, morti; del giocatore entrate, tempi, percentuale massima e prese. Il totale
  c'è solo per conteggi e tempi; per le percentuali e le frequenze no. Minimo e massimo portano lo scontro (`id`,
  `started`); a parità vince il più recente. La mediana pari ha un decimale (2,5).
- **Limiti inferiori**: un valore è *at least* se la cella lo è o se lo scontro è interrotto (solo conteggi e tempi);
  un aggregato con uno di questi è *stimato* (*at least* per totale, minimo e massimo, *~* per la mediana); la frequenza
  pesata è stimata se una cella `risk` lo è. Frequenze di registrazione diverse (`rec.hz`) si segnano sulle percentuali
  (`hz`) senza escludere.
- **Memoria**: una riga tiene solo i valori delle misure e poche voci dell'intestazione; il modello delle metriche resta
  soltanto nella cache di `Data/Metrics.lua`, così la memoria segue la cache e non l'insieme (prova lunga: con
  `CACHE` = 5 restano circa 1 MB, con le 20 sessioni in cache circa 3,5 MB).
- **Coda**: una sessione alla volta, la successiva al frame dopo (dalla cache nello stesso frame); la pausa in
  combattimento vale **fra** una sessione e l'altra: quella in costruzione finisce le sue fette (al più 7 frame per una
  sessione al limite), come il calcolo della card del report. Un nuovo `Build` annulla quello in corso
  (`done(nil, "cancelled")`). Una sessione eliminata prima del suo turno o dopo esce (`gone`), una danneggiata resta
  con lo stato `damaged` e non conta. A `SESSIONS_CHANGED` l'ultimo confronto (`Compare.Current()`) perde le sessioni
  eliminate, ricalcola gli aggregati e conta le nuove della chiave (`newFights`), con `Compare.OnChange(fn)` per la
  pagina di M6.4.
- **Costo** (prova lunga, 20 sessioni da 30 000 righe e 40 unità): il frame peggiore del confronto è quello del report
  (circa 10 milioni di istruzioni: `Storage.Decode` e la prima fetta, rapporto 1,00), in circa 260 frame; lo stesso
  confronto dalla cache in un frame.
- **Parole**: chiavi `ANALYTICS_M_*` (le misure), `ANALYTICS_FILTER_*`, `ANALYTICS_AGG_*`, *Not comparable* con le basi,
  *Only one comparable fight*, *Building 4 of 9…*, *Paused during combat*, le note degli scontri lasciati fuori,
  eliminati, danneggiati e nuovi; `Compare.CellText`, `AggregateText`, `AggregateTip`, `NoteLines`, `RowNotes`,
  `OverviewName`. `/atw debug` aggiunge alla sezione *Analytics and export* l'ultimo insieme, la coda e le costruzioni,
  solo numeri.

## 3. La vista Analytics nella scheda Reports (`UI/Analytics.lua`, M6.4)

### 3.1 Dove si vede

- **Scheda Reports** (disposizione ampia, SPEC-03 §4.4), con l'interruttore `analytics`: in testa un
  `Widgets.Segmented` *Recordings · Analytics*. *Recordings* è la scheda di M4.5 com'è; *Analytics* è la pagina di §3.2.
  `/atw reports` apre *Recordings*. La pagina scelta si ricorda fino al `/reload` (in memoria: nessun dato nuovo).
- **Card *Analytics* nel report** di una sessione, dopo la card *Timeline* (§3.3).
- Nessuna finestra nuova e nessuna scheda nuova: Analytics è un modo di leggere le registrazioni che stanno in Reports.

### 3.2 La pagina Analytics

```
┌ Recordings | Analytics ─────────────────────────────── 12 recordings · 4 enemies ┐
│ ┌ Enemies ───────────────────────────────────────────────────────────────────┐ │
│ │ Hogger (elite) · party    5 fights · 8:12 in combat · 26 Nov 21:14 · 62–100 % │ │
│ │ Unknown enemies (not comparable)   2 fights                                   │ │
│ └──────────────────────────────────────────────────────────────────────────────┘ │
│ ┌ Compare fights · Hogger ─────────────────────────────────────── [Export] ──┐ │
│ │ [x] Same group size  [x] Same difficulty  [x] Same role (Damage)              │ │
│ │ 5 fights · median 1:42 · readable 62–100 %                                    │ │
│ │ Date          Length  Readable  Crossings W/D  Danger  Changed hands  Unstable │ │
│ │ All fights    1:42    94 %      3 / 1 (1–6)    0:06    2              1       │ │
│ │ 26 Nov 21:14  1:42    98 %      4 / 1          0:06    2              1 · 0:08 │ │
│ │ 26 Nov 20:51  ≥ 2:31  62 %      Insufficient data …                           │ │
│ └──────────────────────────────────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────────────────────────────┘
```

- **Enemies**: la panoramica di §2.3, righe da 32 pt in un pool che scorre; la riga scelta si evidenzia.
- **Compare fights**: i filtri (`Widgets.Switch` piccoli), la riga di contesto, poi una **tabella**: la prima riga
  *All fights* (gli aggregati di §2.2: la mediana, con totale, minimo e massimo nel tooltip), poi una riga per scontro,
  il più recente prima. Colonne, in ordine di priorità (sotto una larghezza le ultime spariscono e restano nel tooltip
  della riga): *Date*, *Length*, *Readable*, *Crossings W/D*, *Time in Danger* (`dangerAny`), *Changed hands*,
  *Unstable*, *Risk / min*, *Your highest* (`maxPct` del giocatore), *Closest to the tank*. Numeri in `MonoSmall`; ogni
  cella con l'indicatore della categoria come la scheda Reports (stimata nel colore `warn` con *at least* o `~`,
  sconosciuta e *Insufficient data* in `text-3`); *Not comparable* in `text-3` con il motivo nel tooltip.
- Un clic su una riga apre il suo report nella pagina *Recordings*; *Export* apre la casella di §4 con il confronto.
- Righe da pool (al più `Compare.MAX_FIGHTS` + 1), nulla di nuovo per una chiave già mostrata.

### 3.3 La card *Analytics* del report

Dopo la card *Timeline* (o dopo la card di testa senza timeline), con l'interruttore `analytics`; si costruisce dopo il
report (e dopo la timeline) con *Building analytics…*, a fette. Righe, ognuna con l'indicatore della categoria e il
tooltip di §1.3:

| Riga | Esempio |
|---|---|
| Campioni validi | *Values 82 % · State only 0 % · Unknown 18 % · enemy monitored 96 % of combat* |
| Superamenti | *Threshold crossings: 7 Warning · 2 Danger* (*thresholds 82 / 91*) |
| Tempo con un'unità in WARNING o DANGER | *0:24 in Warning or Danger · 0:06 in Danger* |
| Cambi di chi tiene il nemico | *3 times: 1 tank to tank · 1 to a non-tank · 1 back to a tank* |
| Prese di un non tank | *1* |
| Intervalli instabili | *2 intervals, 0:14 in all* e i primi tre con l'ora (*0:12–0:19 · 3 changes*); un clic apre il replay lì |
| Situazioni di rischio | *3 · 1.8 per minute of known combat* |
| Più vicino al tank | *Ana 96.4 % at 1:12 (not holding the enemy)* |
| Confronto | *Compare with 4 other fights against Hogger* (con almeno un'altra sessione della chiave): apre la pagina Analytics su quella chiave |

Con una metrica non `ok` la riga dice *Not available* o *Insufficient data* con il motivo breve accanto (*fewer than
half the samples readable: 38 %*). Con nulla di leggibile la card ha la sola riga dei campioni validi e la nota *Nothing
was readable in this fight: only the context can be described.*

### 3.4 Stati

| Situazione | Pagina Analytics | Card del report |
|---|---|---|
| nessuna registrazione | *No recordings yet* (come Recordings) | — |
| costruzione | *Building 4 of 9…* nella card del confronto | *Building analytics…* |
| in combattimento | la coda in pausa: *Paused during combat* | si costruisce |
| registrazione in corso | non c'è nell'elenco né nel confronto | non c'è (il report non si apre) |
| danneggiata | riga *This recording is damaged* che non conta | *This recording is damaged and was set aside.* |
| eliminata durante la costruzione | esce; gli aggregati si rifanno | la card si chiude con il report |
| un solo scontro della chiave | la tabella con una riga, aggregati *Only one comparable fight* | nessuna riga *Compare* |
| dati in sola lettura | uguale: Analytics legge soltanto | uguale |
| interruttori spenti | nessun segmentato, nessuna card | nessuna card |

### 3.5 Anteprime e manuale

- **Anteprime** (ADR 0013, dati inventati, `tools/make_mockups.py`): `analytics-overview`, `analytics-compare`,
  `report-analytics` e (M6.5) `export-box`, in inglese e in italiano; `analytics-compare` anche in Aurora e Warden.
- **Manuale**: la pagina *Threat Analytics* (`docs/wiki/Threat-Analytics.md` e `Threat-Analytics-it.md`) con le
  anteprime: che cosa vuol dire ogni metrica e da dove viene, perché *Insufficient data* sotto il 50 %, che cosa si
  confronta e che cosa no, nessuna classifica; M6.5 aggiunge la sezione *Export* (formati, nomi, limiti, niente rete né
  chat). *Combat Reports* rimanda alla card *Analytics*; *Privacy and Data* dice che cosa può uscire con
  l'esportazione e che lo copia solo il giocatore.

### 3.6 Realizzato in M6.4

`UI/Analytics.lua` (la pagina e la card) e il cambio di `UI/Reports.lua`, con queste precisazioni:

- **Selettore**: a sinistra della riga d'uso; se la finestra è stretta la riga d'uso va sotto. Sulla pagina Analytics
  la riga dice *12 recordings · 4 enemies* (i nemici sconosciuti non contano) senza l'indicatore *estimated*.
  `Reports.ShowPage` (da `/atw reports`) e `REPORT_REQUESTED` aprono *Recordings*.
- **Pagina**: nessun nemico scelto all'apertura (*Click an enemy to compare its fights*); la riga *Unknown enemies* si
  può cliccare e dice che non si confrontano. Il confronto in corso mostra *Building …* o *Paused during combat* al
  posto della tabella; *Refresh* compare con le sessioni nuove. Se tutte le registrazioni del nemico scelto spariscono,
  la scelta si azzera.
- **Tabella**: l'indicatore della categoria è una lettera accanto al valore (*D / C / E*, in italiano *R / C / S*) con
  la legenda sotto; *stimata* anche nel colore `warn`. Le colonne e i loro dati (la prima misura è quella mostrata, due
  per i superamenti e per gli intervalli instabili): durata e morti; campioni validi (stato e valori); superamenti;
  tempo in Danger e in Warning o Danger; cambi di detentore e prese di un non tank; intervalli instabili e il loro
  tempo; rischio; il giocatore (percentuale massima, superamenti, tempi, prese); la più vicina al tank. Il tooltip di
  una cella dice ogni sua misura con categoria, base, campioni validi, motivo; quello della riga *All fights* dà
  mediana, totale, minimo e massimo (con la data), la frequenza pesata, la categoria e quanti scontri. Le colonne che
  non ci stanno tolgono posto dalla fine e vanno nel tooltip della riga (fino a `Analytics.TIP_LINES` = 32 righe).
- **Card**: le righe di §3.3; con una metrica non `ok` *Not available* o *Insufficient data* con il motivo accanto;
  contesto, percentuale massima per unità, morti e avvisi restano nelle card del report (stessi numeri, ANA-03). Sotto
  gli intervalli instabili *Click an interval to replay it* con `replay`, e *N more intervals* oltre i primi tre.
- **Modifiche collegate**: le righe di `Compare` tengono anche `valid`, `coverage` e `lowerBy` di una misura (per i
  tooltip); `Metrics.LowerLines`; `Widgets.Switch{small}`; `content.maxLines` dei tooltip.
- Il pulsante *Export* è arrivato con M6.5 (§4.8).

## 4. Esportazione (`Data/Export.lua`, `UI/ExportBox.lua`, M6.5)

Fonte §4.2: *esportazione testuale/CSV, se supportata*. Gli addon non scrivono file e non raggiungono gli appunti del
sistema: l'esportazione è un testo **già selezionato** in una casella di sola lettura, che il giocatore copia con
Ctrl+C e incolla dove vuole. È la stessa scelta di Azeroth Accord (SPEC-12 §6 di Accord: colonne, escape, parti per
Discord, limite), da cui M6.5 copia `Data/Export.lua` e il lettore CSV dei test (ADR 0012).

### 4.1 Regole

- **EXP-01** MUST (ADR 0001): nulla esce dal gioco se non il testo che il giocatore copia: nessun file, nessuna rete,
  nessun messaggio dell'addon, nulla in chat, nessun suono. `CopyToClipboard` (nel dump, sistema `Os`) **non** si usa:
  la copia è un gesto del giocatore. Nessun GUID, nessun valore segreto, nessuna impostazione e nessuna riga di `/atw
  debug` nell'esportazione (DAT-33).
- **EXP-02** MUST (CSV, come EXP-02 di Accord): RFC 4180 con il separatore `,` e righe separate da `\n` (la casella del
  gioco non tiene `\r`); un valore che contiene `,`, `"`, un a capo o spazi agli estremi va fra virgolette, con ogni `"`
  raddoppiato; UTF-8 senza BOM; intestazione in inglese, fissa.
- **EXP-03** MUST (formule, come EXP-03 di Accord): un valore di **testo** che comincia con `=`, `+`, `-`, `@`, una
  tabulazione o `\r` prende davanti un apostrofo `'` (prima delle virgolette); i numeri non si toccano.
- **EXP-04** MUST (il carattere `|`, come EXP-04 di Accord): nella casella `|` si scrive `||`, che il client mostra e
  copia come uno solo **[da provare in gioco]**; i test leggono il testo logico, prima di questo passo.
- **EXP-05** MUST (nomi, [Q15](SPEC-09-risks-open-questions.md)): sopra la casella c'è **sempre** l'avviso dei nomi;
  l'opzione *Replace names* sostituisce ogni nome di un'unità (§4.5) e il test cerca nell'esportazione ogni nome della
  sessione senza trovarlo.
- **EXP-06** MUST (categorie, ANA-04): ogni valore esportato porta la sua categoria e il suo stato (colonne nel CSV,
  segni e parole nel testo); *Not available* e *Insufficient data* non diventano mai 0 né una cella vuota senza stato.
- **EXP-07** MUST (limite): al più `Export.MAX_TEXT` = **262 144** byte (256 KB, come Accord); oltre, si tengono solo
  righe intere (e parti intere nel testo) e la casella dice, **fuori dal testo esportato**, *2 140 rows left out (limit
  256 KB)*.

### 4.2 Che cosa si esporta

| Contenuto | Da dove | Formati | Che cosa contiene |
|---|---|---|---|
| **This fight** (`fight`) | *Export* nella card di testa del report | testo, CSV | il contesto, le righe del report e le metriche di §1.4 della sessione, una riga per unità |
| **Events** (`events`) | lo stesso, scelta *Events* | CSV | ogni evento della sessione in ordine di tempo, con le parole di SPEC-05 §4.5 come codici inglesi |
| **Readings** (`readings`) | lo stesso, scelta *Readings* | CSV | ogni riga della sessione (letture e righe sconosciute con il motivo), tagliata a EXP-07 |
| **Comparison** (`compare`) | *Export* nella card *Compare fights* | testo, CSV | le righe del confronto con i filtri in vigore e, nel testo, gli aggregati |

La casella si apre sul formato e sul contenuto scelti l'ultima volta fino al `/reload` (testo e *This fight* la prima
volta); *Events* e *Readings* hanno solo il CSV (il testo è spento con il tooltip *CSV only: too long to read as text*).

### 4.3 CSV: colonne e valori

Valori: numeri con il punto decimale; tempi in **secondi** con un decimale (`12.4`), percentuali con un decimale
(`84.2`), conteggi interi; una cella senza valore è vuota **e** ha il suo stato nella colonna di stato; date in UTC
`AAAA-MM-GG HH:MM` (`started_utc`, da `started`, `date("!…")` attraverso Compat); `category` è `detected`, `calculated`,
`estimated` o `unknown`; `status` è `ok`, `na`, `insufficient` o `unknown`; `reason` è il codice inglese del motivo
(`secret`, `state-only`, `low-valid`, `little-monitored`, `few-rows`, `little-known`, `no-ticks`, `not-comparable`…);
`at_least` è `yes` o vuoto; `basis` è `thresholds`, `game` o `mixed`; `class` è il `classFile` (`MAGE`), `role` il
ruolo del gioco (`TANK`, `HEALER`, `DAMAGER`, vuoto).

| Contenuto | Colonne, in ordine |
|---|---|
| `fight` (formato lungo: una riga per metrica, per la sessione e per ogni unità) | `session`, `started_utc`, `zone`, `enemy`, `unit`, `role`, `class`, `metric`, `value`, `category`, `status`, `reason`, `at_least`, `basis` |
| `compare` (una riga per scontro, il più recente prima) | `session`, `started_utc`, `enemy`, `group`, `difficulty`, `player_role`, `state`, `outcome`, `duration_s`, `combat_s`, `valid_pct`, `coverage_pct`, `warning_crossings`, `danger_crossings`, `warning_any_s`, `danger_any_s`, `holder_changes`, `taken_by_non_tank`, `unstable_intervals`, `unstable_s`, `risk_situations`, `risk_per_min`, `player_max_pct`, `closest_to_tank_pct`, `at_least`, `not_available`, `insufficient`, `not_comparable`, `detected`, `calculated` |
| `events` | `t_s`, `event`, `enemy`, `unit`, `other_unit`, `detail`, `category` |
| `readings` | `t_s`, `enemy`, `unit`, `percent`, `reading`, `situation`, `reason`, `category`, `at_least` |

- `fight`: le metriche hanno nomi fissi (`duration_s`, `combat_s`, `pulls`, `warning_threshold`, `danger_threshold`,
  `valid_values_pct`, `valid_state_pct`, `unknown_pct`, `coverage_pct`, `warning_crossings`, `danger_crossings`,
  `warning_time_s`, `danger_time_s`, `warning_any_s`, `danger_any_s`, `max_pct`, `closest_to_tank_pct`,
  `holder_changes`, `tank_to_tank`, `to_non_tank`, `back_to_tank`, `taken_by_non_tank`, `unstable_intervals`,
  `unstable_s`, `risk_situations`, `risk_per_min`, `deaths`, `alerts`); `unit` è vuota per le metriche della sessione.
- `compare`: `at_least`, `not_available`, `insufficient`, `not_comparable`, `detected` e `calculated` elencano i nomi
  delle metriche (le colonne) in quello stato o di quella categoria, separati da `;`. Ogni metrica sta in **una sola**:
  vuota in `not_available`, `insufficient` o `not_comparable`; con un valore in `at_least` (stimata), `detected` o
  `calculated`. `detected` e `calculated` sono aggiunte di M6.5: senza, il confronto non diceva la categoria di ogni
  valore (EXP-06).
- `events`: `event` è uno fra `combat_start`, `combat_end`, `target`, `state`, `holder`, `mode`, `death`, `alert`,
  `coach_tip`, `encounter`, `recording_paused`, `interrupted`, `limit`; `detail` è un elenco `chiave=valore` separato da
  `;` (`new=warning;old=safe;reason=predicted`, `kind=to_non_tank`, `rule=T1;category=predicted;confidence=medium`,
  `pull=2`, `seconds=2.4`); `category` quella dell'evento (SPEC-02 §4.3).
- `readings`: `reading` è `value`, `state_only` o `unknown`; `situation` 0–3 o vuota; `percent` solo per `value`
  (`384.3` con `at_least=yes` e `category=estimated` al tetto); `reason` per `unknown` (`secret`, `stale`…).

### 4.4 Testo

Per incollarlo in una chat esterna o in un forum (come il *testo per Discord* di Accord, EXP-05 di Accord):

- nella **lingua dell'interfaccia** (il CSV resta in inglese); dentro un **blocco di codice** (tre apici inversi), così
  Discord non interpreta il markdown e non manda menzioni; gli apici inversi nei valori diventano `'`;
- una riga di titolo *Threatwarden · Hogger · 26 Nov 2026 21:14 · The Deadmines*, poi le righe del report e di
  Analytics con le stesse parole dell'interfaccia (*at least*, `~` per una stima, *Not available*, *Insufficient data*
  con il motivo breve), poi una tabella delle unità a colonne allineate con spazi (nome tagliato a 18 caratteri con `…`),
  e in fondo la riga della legenda (*~ estimate · at least: data were missing · Insufficient data: fewer than half the
  samples readable*);
- il confronto: la riga dei filtri, gli aggregati, poi una riga per scontro;
- **parti** di al più `Export.PART_MAX` = **1 900** caratteri (un messaggio di Discord ne prende 2 000), ognuna un blocco
  di codice completo con `(1/3)` nel titolo, senza spezzare una riga; una riga vuota separa le parti nella casella.

### 4.5 Nomi (Q15)

- **Avviso**, sempre sopra la casella (icona `warn`, `Small` `text-2`): *This text contains the names of your group.
  Share it only with people who agree.* Con la sostituzione accesa: *Names are replaced. Enemy and zone names stay.*
- **Replace names with Player 1, Player 2…** (`Widgets.Switch`), **spento** di predefinito; la scelta vale fino al
  `/reload` e non si salva ([Q15](SPEC-09-risks-open-questions.md)).
- Con la sostituzione: il giocatore è *You* / *Tu*; il suo famiglio (`pet = true`) *Your pet*; un'unità con un token da
  famiglio (`partypet1`, `raidpet3`…) *Pet 1, Pet 2…*; ogni altra unità *Player 1, Player 2…* nell'ordine in cui compare
  nell'esportazione. Lo stesso nome ha lo stesso numero in tutta l'esportazione (anche fra le sessioni di un confronto);
  un'unità senza nome (segreto: si mostrava il token) ha un numero suo per sessione. Si sostituisce anche un nome con il
  reame (`Nome-Reame`). Restano i nomi dei nemici e della zona, la classe e il ruolo (non sono dati personali; la
  composizione del gruppo resta leggibile, e il manuale lo dice).
- Le sessioni nelle SavedVariables non cambiano: la sostituzione vale solo per il testo esportato.

### 4.6 La casella (`UI/ExportBox.lua`)

- Un `Widgets.Dialog` `AzerothThreatwardenExport` (con il nome per Esc, ARC-04), **640 × 460** pt come la casella di
  `/atw debug`, spostabile. Dall'alto: il titolo (*Export · This fight · Hogger*), i selettori (`Widgets.Segmented`)
  *This fight · Events · Readings* (o *Comparison*) e *Text · CSV*, l'interruttore dei nomi, l'avviso, il campo, la riga
  di stato (*about 18 KB* · *2 140 rows left out (limit 256 KB)*), il suggerimento *Press Ctrl+C to copy. Threatwarden
  never posts or sends it.* e *Close*.
- **Il campo** è quello della casella di `/atw debug`: un `EditBox` a più righe dentro uno `ScrollFrame`, `MonoSmall`,
  `SetMaxLetters(0)`, di **sola lettura** (ciò che si scrive si annulla subito e il testo torna selezionato), tutto
  selezionato all'apertura e quando prende il fuoco; Esc chiude. M6.5 sposta quel campo in una funzione comune
  (`Widgets.CopyArea`, come `CopyBox.Area` di Accord) usata dalle due caselle.
- **Costruzione** del testo a fette di `Export.SLICE` = **2 000** righe o eventi per frame, con *Building export…*;
  un cambio di formato, contenuto o nomi ricostruisce. Il testo si dà al campo con **un** `SetText`.
- **Limiti della casella del client** **[da provare in gioco]**: quanto tempo prende `SetText` con 256 KB, se lo
  scorrimento e Ctrl+A / Ctrl+C reggono tutto il testo, se `||` si copia come `|`. Se il client regge meno, cambia solo
  `Export.MAX_TEXT` (un punto) e la riga di stato lo dice. `SetVisibleTextByteLimit` (nel dump) non si usa finché la
  prova non mostra un bisogno.
- Funziona anche in combattimento (nessuna funzione protetta), con la costruzione a fette; una registrazione eliminata
  mentre la casella è aperta la svuota con *This recording was deleted.*

### 4.7 Costo e dimensioni

- `fight` di un raid da 40 unità: circa 40 × 7 metriche più 30 righe, sotto i 20 KB; `compare` di 20 scontri sotto i
  5 KB; `events` di 6 000 eventi circa 250–300 KB (può superare il limite di poco: si taglia); `readings` di 30 000 righe
  circa 1 MB, quindi in una sessione lunga resta solo l'inizio (circa 6 000 righe, §4.8) e la riga di stato lo dice
  ([Q24](SPEC-09-risks-open-questions.md)).
- La memoria di picco è circa due volte il testo (i pezzi e la stringa unita), solo mentre la casella è aperta; chiusa,
  il testo si dimentica.

### 4.8 Realizzato in M6.5

`Data/Export.lua` (da Accord, ADR 0012), `UI/ExportBox.lua`, `Widgets.CopyArea` (spostata da `UI/DiagnosticsBox.lua`) e i
pulsanti *Export*, con queste precisazioni:

- **Chiamata**: `Export.Build({ kind, format, id | result, replace }, done)`; il formato si chiama `text` o `csv`;
  `done(testo, info)` con `rows`, `left`, `bytes`, `replaced`, `parts`, oppure `done(nil, motivo)`. Eventi e letture si
  costruiscono a fette di `SLICE` record per frame; *This fight* usa `Report.Build` e `Metrics.Build` (a fette loro) e
  poi compone in un frame; il confronto si compone subito dal risultato di `Compare.Current()`. Un nuovo `Build` o
  `Export.Cancel` lascia cadere quello in corso. La data UTC usa `Compat.DateText("!%Y-%m-%d %H:%M", …)`: nessun cambio
  a `Core/Compat.lua`. Le righe del confronto tengono anche `dur` e `coverage`.
- **CSV**: le righe di *This fight* sono le 25 metriche della sessione (con `warning_threshold` e `danger_threshold`
  *rilevate*), poi 9 per unità (con `taken_by_non_tank` e i campioni validi). `deaths` e `alerts` contano gli eventi
  registrati. Negli eventi `detail` ha anche `continued=reload`, `first=yes`, `source=…` per le morti e `reason=…` per il
  nemico perso; la categoria di `Z` è `detected`; quelle di avvisi e consigli possono essere `predicted` o
  `hypothesis`.
- **Testo**: dopo l'etichetta di ogni riga la categoria fra parentesi; *at least* per un limite inferiore e `~` per una
  stima che non lo dice già (le mediane); nelle tabelle la lettera *D* o *C* accanto al valore. L'intestazione di una
  tabella si ripete nelle parti che la tabella attraversa. Gli intervalli instabili elencati sono al più
  `Metrics.MAX_UNSTABLE`.
- **Nomi**: un nemico con lo stesso nome di un'unità della sessione (un compagno rivoltato contro il gruppo) si
  sostituisce come quell'unità. Il confronto non esporta nomi di unità.
- **Casella**: *Replace names*, formato e contenuto restano fino al `/reload`; il segmento *Text* è spento con *CSV
  only* per eventi e letture. La casella si svuota con *This recording was deleted.* anche per un confronto che ne
  perde una.
- **Pulsanti**: nella card di testa del report i pulsanti vanno su due righe in una card stretta; *Export* è spento per
  una registrazione aperta o danneggiata. Nella card del confronto compare con una tabella.
- **Misure** (prova lunga, sessione di 40 unità al limite): delle 30 000 righe di letture ne entrano **6 140** in 256 KB
  (4 frame); di 6 000 avvisi, il caso più lungo, 2 299 eventi; il frame peggiore è quello del report (decodifica e prima
  fetta); la memoria non cresce ripetendo l'esportazione.

## 5. Moduli, interruttori, diagnostica (M6)

| File | Responsabilità | Bus | Step |
|---|---|---|---|
| `Data/Report.lua` (cambio) | il richiamo `holder(u, m, t, e)` di `Report.Walk`, chiamato dove il report conta un `A`; i risultati del report non cambiano | — | M6.2 |
| `Data/Metrics.lua` | le metriche di §1 (`Compute`, `Build` a fette, cache, celle, parole) | ascolta `SESSIONS_CHANGED` | M6.2 |
| `Data/Compare.lua` | chiavi, filtri, insiemi, aggregati, panoramica, coda in pausa in combattimento (§2) | ascolta `SESSIONS_CHANGED`, `COMBAT_STARTED`, `COMBAT_ENDED` | M6.3 |
| `UI/Analytics.lua`, `UI/Reports.lua` (cambio) | il segmentato *Recordings · Analytics*, la pagina di §3.2, la card *Analytics* del report (§3.3) | ascolta `SESSIONS_CHANGED`, `COMBAT_*`; emette `REPLAY_REQUESTED(id, t)` (clic su un intervallo instabile) | M6.4 |
| `Data/Export.lua` | CSV, testo, escape, parti, nomi, limite (§4.1–§4.5, §4.7), costruzione a fette; copiato da Accord e adattato | — | M6.5 |
| `UI/ExportBox.lua`, `UI/Widgets` (cambio), `UI/DiagnosticsBox.lua` (cambio) | la casella di §4.6; `Widgets.CopyArea` comune alle due caselle | ascolta `SESSIONS_CHANGED` | M6.5 |
| `Core/Compat.lua` (cambio, se serve) | la data UTC (`date("!%Y-%m-%d %H:%M", t)`) per `started_utc`, accanto a `Compat.DateText` | — | M6.5 |

- **Interruttori** (`Core/Features.lua`, ADR 0014): `analytics` (Metrics, Compare, la pagina e la card) ed `export`
  (Export, la casella, i pulsanti *Export*) restano **spenti** fino a M6.R; l'esportazione chiede tutti e due (il
  contenuto `fight` e `compare` usa le metriche), oltre a `reports`. Spento vuol dire: nessun ascoltatore, nessun frame,
  `Metrics.Build` e `Compare.Build` rispondono `off`, nessun segmentato, card o pulsante. I test che li vogliono accesi li
  mettono a `true` in `M.features`.
- **Nessun dato nuovo**: nessuna chiave nelle sessioni, nessuno schema nuovo; le scelte della pagina e della casella
  (pagina, chiave, filtri, formato, contenuto, nomi) stanno in memoria fino al `/reload`.
- **`/atw debug`**, sezione *Analytics and export*: interruttori; la cache delle metriche (sessioni, millisecondi e
  frame dell'ultima costruzione); il confronto (insieme, in coda, in pausa); l'ultima esportazione (contenuto, formato,
  byte, righe lasciate fuori, nomi sostituiti sì o no). Mai nomi, zone o nemici.
- **Eventi del Bus**: nessuno nuovo. La card del report apre la pagina Analytics con una chiamata diretta
  (`Analytics.Show(key)`); i pulsanti aprono la casella con `ExportBox.Open(kind, ids)`.
- **Parole**: chiavi `ANALYTICS_*` ed `EXPORT_*` in `enUS` e `itIT`; la prova delle parole (ANA-01) le copre.

## 6. Piano di M6: test per step

Le sessioni dei test si scrivono con il recorder vero da uno scontro scriptato (`Fight`, nei tre esiti di
`Fight.OUTCOMES`) o si costruiscono a mano con `Data/Session.lua` per un caso esatto, come in M5.

| Step | Test e casi |
|---|---|
| **M6.2** | `test_metrics.lua`: sessioni note con risposte note per ogni metrica di §1.4 nei tre esiti, in una mista, interrotta, troncata, con `Z e`, con `after`; uguaglianza con le celle del report sulle stesse sessioni (superamenti, tempi, percentuale massima, prese, cambi di tank) e con i superamenti della timeline; i cambi di detentore divisi (tank → tank, verso un non tank, di nuovo a un tank, mai il primo detentore); ANA-02 a 49 % e a 50 % su ognuna delle due basi e sulla copertura; `maxNotHolding` senza le righe `2`, `3`, `4`, con `p = 3843`; instabilità ai bordi di `W` e `K`, attraverso una pausa fra due pull (non si unisce), un momento con `from = to`; rischio sotto e sopra 30 s noti; costruzione a fette uguale a quella intera; cache e `SESSIONS_CHANGED`; la sessione identica prima e dopo (nulla scritto); interruttore spento. `test_coach_wording.lua` esteso alle chiavi `ANALYTICS_*` con le parole di merito vietate |
| **M6.3** | `test_compare.lua`: chiavi (`npc`, nome e classificazione, nessuna), filtri (gruppo, difficoltà sconosciuta, ruolo), soglie diverse, *game states* contro soglie, *mixed*, percentuali solo fra sessioni con valori; aggregati (mediana pari e dispari, totale, minimo, massimo, frequenza pesata), *at least* che passa agli aggregati, `MIN_FIGHTS`, `MAX_FIGHTS` con le escluse contate; interrotte e collegate; panoramica dalle sole intestazioni (nessuna decodifica); coda in pausa in combattimento e ripresa; sessione eliminata o danneggiata durante la costruzione. `Tests/long/test_compare_long.lua`: venti sessioni al limite, frame e memoria |
| **M6.4** | `test_analytics_view.lua`: segmentato e pagine, panoramica, confronto con filtri, aggregati, *Not comparable*, *Insufficient data*, clic su una riga, card del report in ogni esito, clic su un intervallo instabile con e senza `replay`, *Compare with…*, ogni riga della tabella degli stati di §3.4, sola lettura, interruttori spenti; nessun colore fuori dal tema. Manuale *Threat Analytics* nelle due lingue con le anteprime |
| **M6.5** | `test_export.lua`: ogni contenuto e formato; andata e ritorno con un lettore CSV RFC 4180 dei test (`Tests/lib/csv.lua`, da Accord) con virgole, virgolette, a capo, `=`, `-`, `@`, accenti, nomi con il reame; `|` raddoppiato; parti del testo entro 1 900 caratteri, blocchi completi, nessuna riga spezzata; nomi sostituiti (nessun nome della sessione nel testo, numeri stabili fra sessioni, *You*, famigli); stato e categoria per ogni valore (EXP-06); limite con righe intere e il conteggio fuori dal testo; nessun GUID né riga di debug. `test_export_box.lua`: sola lettura, tutto selezionato, Esc, avviso sempre presente, selettori, *CSV only*, registrazione eliminata, interruttori spenti. `Tests/long/test_export_long.lua`: `readings` ed `events` di una sessione al limite (tempo a fette, memoria) |
| **M6.6** | `docs/checklists/M6.md`: ogni riga *Real client* di M6.2–M6.5 e il criterio di uscita |

## 7. Cosa aspetta il probe e il gioco

- **[probe P3]**: quale esito danno i gruppi veri, quindi quante metriche saranno *Not available* o *Insufficient data*;
  se la maggior parte delle sessioni in istanza è *state only*, Analytics descrive stati e detentori, non percentuali.
- **[probe P9]**: il numero della creatura dal GUID (la chiave del confronto); senza, il confronto usa nome e
  classificazione, e due nemici con lo stesso nome finiscono insieme.
- **[probe P7]**: morti e incontri nel contesto.
- **[probe P10]**: il costo di `Metrics.Build` e della coda del confronto fuori dal combattimento.
- **[da provare in gioco]** (checklist M6.6): la casella con 256 KB (tempo di `SetText`, scorrimento, Ctrl+A e Ctrl+C,
  `||`); il testo incollato in Discord (blocchi, parti, accenti) e il CSV aperto in un foglio di calcolo (virgole,
  apostrofo davanti alle formule, UTF-8); la leggibilità della tabella del confronto alle larghezze piccole e in
  italiano; le soglie di ANA-02 e di instabilità (Q22) su scontri veri.
