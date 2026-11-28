# SPEC-07: Multi-target, heatmap e profili

> Fonte: [specifiche originali](source-specification.md) §5.6, §5.7, §4.2, §6.1, §6.4. §0–§2 completati in **M7.1** (2026-11-27)
> **prima** dell'esito del probe M0, per decisione del proprietario ([SPEC-00 §7](SPEC-00-vision-scope.md#7-registro-delle-decisioni)
> D7, come M2–M6): il go / no-go di M7 è **condizionato** (§0) e il tracker legge ciò che il client permette, lettura
> per lettura; ciò che il probe può cambiare è marcato **[probe Pn]**, ciò che solo il gioco può dire **[da provare in
> gioco]**. §3–§7 (heatmap, profili, accessibilità) completati in **M8.1** (2026-11-28), anch'essi prima del
> probe; moduli, eventi e test per step di M7 in §2.7–§2.8, di M8 in §6.
> §1 e §2.4 realizzati in **M7.2** (`Data/MobRisk.lua`, `Data/MobTracker.lua`, la regola 0 di `Data/TargetTracker.lua`,
> lo schema 6) dietro l'interruttore `multitarget`, spento fino a M7.R (acceso dalla `v0.7.0`); le note *M7.2* dicono come il codice ha letto i punti
> lasciati aperti.
> **Gate** (fonte §8): niente promesse di multi-target finché il probe non dimostra che i dati sono ottenibili (P5, P6):
> la pagina del manuale e le note della versione dicono che cosa dipende dal probe.

## 0. Il gate di M7: go condizionato

Il gate di [M7](../roadmap/M7-multi-target.md) chiede che il probe (P5, P6) mostri che la threat di mob diversi dal
target si può leggere. Il probe non è ancora stato fatto. Per D7 la milestone non si ferma: **go condizionato**
(decisione D21, 2026-11-27). Vuol dire:

- M7 si costruisce e si prova offline sui tre esiti di P5 (tutti i mob, *focus e boss*, *solo il target*) e sui tre
  esiti di P3 per ogni mob (valori, *state only*, nulla), con il client finto (SPEC-08 §2);
- il codice non sceglie nulla per contesto (MON-06): ogni lettura dice se un mob risponde, e la **portata** del tracker
  (§1.4) si riduce da sola a *focus e boss* e a *solo il target* quando gli altri mob non si possono interrogare o la
  loro threat è segreta; ogni riga di un mob dice perché è sconosciuta (MT-01, [ADR 0003](../adr/0003-data-reliability-categories.md));
- l'interruttore `multitarget` è rimasto spento fino a M7.R ed è **acceso** dalla `v0.7.0`, secondo la risposta proposta di
  [Q25](SPEC-09-risks-open-questions.md), come M2–M6, con la pagina del manuale e le note della versione che dicono che nulla è
  stato provato nel gioco.

**Che cosa cambierà il risultato del probe e dove.** M0.7 legge i risultati e cambia soltanto queste righe; il resto
della specifica vale per ogni esito.

| Esito | Che cosa fa già il codice | Che cosa cambia M0.7 | Dove (un solo punto) |
|---|---|---|---|
| P5 *supportato*: ogni membro risponde su ogni mob con un token | portata `all` | nulla | — |
| P5 *parzialmente*: solo alcuni token (per esempio target, focus e boss, non le targhe), o solo il giocatore sugli altri mob | i mob delle fonti mute restano UNKNOWN con il motivo e poi escono (§1.7); portata `focus-boss` o `target` | spegne le fonti che non rispondono mai, così non consumano letture; il manuale dice quali | `MobTracker.SOURCES` |
| P5 *non supportato*: risponde solo `player` sul `target` | la barra del pull dice *Only your target can be read here* e nessun altro mob compare | con il proprietario (Q25): `multitarget` spento, M7 sostituita come dice il gate, e il codice resta spento | `Core/Features.lua`, `multitarget` |
| P6: gli eventi arrivano per gli altri mob, puntuali | un evento anticipa il mob al tick seguente (§1.6) | frequenza del tick più bassa | `MobTracker.RATE` |
| P6: gli eventi non arrivano | solo la rotazione | nulla | — |
| P9: GUID dei mob segreti | portata al più `focus-boss` (§1.3) | nulla | — |
| P3: valori o stato segreti sugli altri mob | righe *state only* o UNKNOWN `secret` per mob (§1.5) | nulla | — |
| P10: costo | budget del tick (§1.6) | frequenza e letture per tick | `MobTracker.RATE`, `MobTracker.READ_BUDGET` |

## 1. Multi-target (M7)

Per ogni mob tracciabile (fonte §5.6): identificativo stabile nello scontro; nome; target corrente, se disponibile (chi
lo tiene); threat relativa dei membri osservati; stato SAFE / WARNING / DANGER (o UNKNOWN con il motivo); ultimo
aggiornamento.

### 1.1 Principi

- **MT-01** MUST: degrado pulito. Un mob che non si può interrogare resta UNKNOWN con il motivo (§1.5) o non compare
  (§1.7), senza errori e senza numeri vecchi presentati come attuali; quando nessun altro mob si può leggere la barra
  del pull lo dice con la portata (§1.4).
- **MT-02** MUST: limite di mob osservati (impostazione `settings.mobs.max`, predefinito **8**, da 2 a 12, compreso il
  mob monitorato) e lettura a rotazione con un budget di letture per tick (§1.6).
- **MT-03** MUST: il monitor resta su **un** mob ([SPEC-03 §1.2](SPEC-03-threat-monitor-ui.md#12-il-mob-monitorato-datatargettrackerlua)):
  il multi-target non cambia le sue righe, i suoi stati, il Coach, gli avvisi del mob monitorato né la registrazione.
  Gli altri mob si leggono con un tick loro, più lento e con un budget, e si mostrano soltanto
  ([ADR 0019](../adr/0019-other-mobs-are-read-by-a-separate-budgeted-rotation-and-only-shown.md)).
- **MT-04** MUST: nessuna regola scritta per contesto (MON-06): fonti, portata e modalità di ogni mob le decidono le
  letture; le previsioni `C_Secrets` e `issecretvalue` come in [SPEC-01 §8.3](SPEC-01-platform-architecture.md#83-lettura-normalizzata-della-threat-m14-usata-da-m2).
- **MT-05** MUST: nulla si salva della lista (né nelle sessioni né nelle impostazioni, oltre alle quattro chiavi di
  §1.9); nessun nome né GUID negli eventi del Bus e in `/atw debug` (solo chiavi e conteggi).
- **MT-06** MUST: nessuna funzione protetta. Un clic su un mob non cambia il target né il focus del gioco
  (`TargetUnit`, `SetFocus` sono protette): sceglie soltanto il mob del monitor (§2.4).
- **MT-07** MUST: niente trend né previsioni sugli altri mob: letti a rotazione hanno troppo pochi campioni (le
  categorie `estimated` e `predicted` restano del mob monitorato, SPEC-03 §2.5).

### 1.2 Fonti dei mob (`Data/MobTracker.lua`)

Ogni API e ogni token sono quelli del dump (build 70170, consultato il 2026-11-27): `UnitExists`, `UnitCanAttack`,
`UnitIsDead`, `UnitAffectingCombat`, `UnitGUID`, `UnitTokenFromGUID` (risultato *nilable*), `UnitIsUnit`,
`C_Secrets.CanCompareUnitTokens(unit1, unit2)`, `UnitDetailedThreatSituation(unit, mob)`,
`UnitThreatSituation(unit, mob)`, `UnitThreatLeadSituation`, gli eventi `NAME_PLATE_UNIT_ADDED(unitToken)`,
`NAME_PLATE_UNIT_REMOVED(unitToken)`, `PLAYER_FOCUS_CHANGED`, `INSTANCE_ENCOUNTER_ENGAGE_UNIT`, `UNIT_TARGET(unitTarget)`,
`UNIT_THREAT_LIST_UPDATE(unitTarget)`. Tutto passa da `Core/Compat.lua` (ARC-02); `C_NamePlate` non serve (bastano
i token e i due eventi).

| Fonte (`kind`) | Token | Scoperta | Priorità | Note | Probe |
|---|---|---|---|---|---|
| `monitored` | il `mobToken` del TargetTracker (target, target del target o il mob fissato, §2.4) | `TARGET_CHANGED` | 1 | **non** lo legge il tracker: la sua riga viene dalle righe del monitor (§1.6) | — |
| `focus` | `focus` | `PLAYER_FOCUS_CHANGED` | 2 | stabile; lo sceglie il giocatore | **P5** |
| `boss` | `boss1`–`boss5` | `INSTANCE_ENCOUNTER_ENGAGE_UNIT` | 3 | stabili; solo negli incontri | **P5** |
| `group` | `pettarget`, `party1target`–`party4target`, `raid1target`–`raid40target` (le unità osservate dello Scanner, senza il giocatore) | `UNIT_TARGET(unit)` di un'unità osservata | 4 | cambiano spesso; un mob che più membri hanno come target viene prima | **P5** |
| `plate` | `nameplate1`–`nameplate40` | `NAME_PLATE_UNIT_ADDED`, `NAME_PLATE_UNIT_REMOVED` | 5 | ci sono solo con le targhe nemiche mostrate (tasto del gioco: l'addon non tocca mai i CVar) e con `settings.mobs.nameplates` | **P5** |

- **Non sono fonti**: `mouseover` (cambia con il puntatore e riempirebbe e svuoterebbe la lista; resta una domanda del
  probe), `targettarget` del giocatore (è già la regola 2 del TargetTracker), `arena1`… (campi di battaglia e arene
  sono fuori dal perimetro).
- `MobTracker.SOURCES` è la tabella delle fonti in quest'ordine, con `on` per ognuna (tutte accese fino a M0.7, §0):
  l'unico punto che il probe cambia.
- **Candidato**: un token è un candidato quando `UnitExists` e `UnitCanAttack("player", token)` sono veri,
  `UnitIsDead` non lo è e `UnitAffectingCombat(token)` non è falso (vero, oppure segreto o in errore: allora decide la
  prima lettura, §1.7). Un mob fuori dal combattimento non entra.
- **Spazzata**: oltre agli eventi, ogni tick controlla a turno `SWEEP` (**12**) token delle fonti accese
  (`UnitExists`, `UnitGUID`), così un mob compare anche se il suo evento non è arrivato **[probe P5, P6]**.
  *M7.2*: la lista della spazzata è `focus`, `boss1`–`boss5`, i target dei membri e `nameplate1`–`nameplate40`; un
  giro intero dura circa 2 s in un party (51 token) e 4 s in un raid da 40 (85 token). Un token che nomina ancora lo
  stesso GUID costa `UnitExists` e `UnitGUID` (e `UnitIsDead`); un token nuovo passa per tutte le domande del
  candidato.

### 1.3 Identità e chiavi

- **GUID leggibile**: chiave `"mob:" .. GUID`, la stessa del TargetTracker, così il mob monitorato e la sua riga nella
  lista coincidono. Un mob ha una voce sola, con l'elenco dei token che ora lo nominano (aggiornato agli eventi e alla
  spazzata); si legge con il primo nell'ordine `focus`, `bossN`, `nameplateN`, target dei membri. Prima di ogni lettura
  `UnitGUID(token) == guid` (un confronto fra stringhe, nessuna allocazione); se il token non lo nomina più,
  `UnitTokenFromGUID(guid)` ne dà un altro, o nessuno (`no-token`, §1.5). Un token il cui GUID cambia passa al nuovo
  mob.
- **GUID non leggibile** (segreto o `nil`, **[probe P9]**): restano solo i token stabili `focus` e `boss1`–`boss5`, con
  chiave `"tok:" .. token .. ":" .. n` (`n` cresce a ogni evento di scoperta di quel token). Due token si confrontano
  con `UnitIsUnit` solo se `C_Secrets.CanCompareUnitTokens` risponde `true` e la risposta non è segreta; un token
  stabile che non si distingue dal mob monitorato **non** compare (potrebbe essere lo stesso mob due volte). Targhe e
  target dei membri senza GUID non si usano: non si possono seguire quando l'indice cambia né distinguere fra loro.
- Da qui i **tre livelli di identità**: GUID → tutte le fonti; nessun GUID ma confronto permesso → *focus e boss*;
  nessuno dei due → *solo il target*. Il GUID leggibile rende `mobIdentity` `available`, uno segreto `restricted`, come
  il TargetTracker.
- Nome e classificazione (`UnitName`, `UnitClassification`) si leggono quando il mob entra e, per le righe visibili, al
  più una volta al secondo; un nome segreto è *Unknown mob*. Mai negli eventi o in `/atw debug`.

### 1.4 La portata (`MobTracker.reach`)

| Portata | Quando | Che cosa dice la barra del pull |
|---|---|---|
| `unknown` | all'inizio di un combattimento, prima di una lettura decisiva | *Reading the pull…* |
| `all` | un mob di una targa o di un target dei membri ha risposto con `values` o `state` in questo combattimento | il numero dei mob e il rischio (§2.3) |
| `focus-boss` | hanno risposto solo mob di `focus` o `bossN` | *Focus and boss only* e il motivo |
| `target` | nessun altro mob ha risposto, ma il mob monitorato sì (il monitor non è in `none`) | *Only your target can be read here* e il motivo |
| `none` | nemmeno il mob monitorato si legge | *Threat cannot be read here* e il motivo |

- La portata è la migliore vista in questo combattimento, limitata dal livello di identità (§1.3); riparte da
  `unknown` a `COMBAT_STARTED`. Non sale mai senza una lettura che lo dimostri (ARC-12).
- Il **motivo** (`MobTracker.reachReason`): `no-guid` (GUID segreti), `no-compare` (anche il confronto è vietato),
  `secret` (la threat degli altri mob è segreta), `nameplates-off` (targhe spente nell'impostazione, o nessuna targa
  vista: il tooltip ricorda il tasto del gioco), `no-answer` (i mob ci sono ma non rispondono: errore o API mancante).
  Un combattimento con un solo mob non è una riduzione: la barra non si mostra (§2.3).
- La capacità `otherMobs` ([SPEC-01 §8.4](SPEC-01-platform-architecture.md#84-capacità)) diventa `available` con la
  portata `all` o `focus-boss`, `restricted` quando gli altri mob rispondono solo segreti, `missing` con le API della
  threat mancanti; il dettaglio è la portata.

### 1.5 Le tre risposte per mob

Una lettura di un mob è `Compat.Threat.Read(unit, mobToken, rec)` per le unità di §1.6, più `Compat.Threat.ReadLead`
per chi lo tiene; come nel monitor ogni coppia (unità, mob) ha la sua modalità e la **modalità del mob** è la migliore
fra le sue righe (`values` > `state` > `none`, MON-04). Una riga con motivo `nil` vuol dire che l'unità non è nella
lista della threat del mob (MON-05).

| Modalità del mob | Che cosa ha la riga del mob | Categoria |
|---|---|---|
| `values` | chi lo tiene (`holderKey`, tank sì/no); chi gli è più vicino fra gli altri (`topKey`) con la percentuale scalata; il margine `100 − p` del più vicino; la percentuale del giocatore su quel mob | rilevata (chi lo tiene, percentuali), calcolata (margine, stato) |
| `state` | chi lo tiene (stato 2–3), chi è sopra il tank (stato 1), lo stato del gioco del giocatore; nessuna percentuale | rilevata |
| `none` | nulla: UNKNOWN con il motivo | — |

Motivi di un mob UNKNOWN: `secret` (threat segreta, previsione o valore), `no-token` (nessun token lo nomina ora: fuori
dalla portata delle targhe e nessuno lo ha come target), `stale` (l'ultima lettura è troppo vecchia), `pending` (non
ancora letto), `missing`, `error`, `no-unit`. Ogni motivo ha la sua frase nel tooltip (*Secret value*, *No unit names
this mob now*, *Stale: last read 3.2 s ago*, *Waiting for a read*, *Not available*).

- **Freschezza**: ogni mob ha il suo intervallo atteso `I` (il tempo fra due letture, dalla rotazione di §1.6); è
  `stale` quando `now − observedAt > max(2 · I, 1 s)` (DAT-12) e sempre dopo `COMBAT_ENDED`. Una riga `stale` mostra
  UNKNOWN con il motivo: gli ultimi valori restano solo nel tooltip con la loro età, mai nella riga.
- **Segreti**: un mob la cui ultima lettura è stata tutta `none` con motivo `secret` si rilegge solo dopo `RETRY`
  (**5 s**), non al suo turno: resta UNKNOWN `secret` e non consuma il budget.
- Il mob monitorato ha la riga costruita dalle righe di `Data/ThreatModel.lua` e `Data/ThreatState.lua` dopo ogni
  `THREAT_UPDATED`: stessi valori, stessa modalità, stesso stato del monitor.

### 1.6 Lettura, rotazione e limite (MT-02)

- **Tick** `"mobs"` attraverso `Core/Scheduler.lua` a `MobTracker.RATE` (**2 Hz**, una costante, Q26 **[probe P10]**),
  solo in combattimento (`{ combat = true }`). È **attivo** solo se l'interruttore `multitarget` è acceso, il client è
  riconosciuto (ARC-01), `settings.mobs.enabled` è vero, il giocatore è in combattimento, c'è almeno un candidato oltre
  al mob monitorato e almeno un consumatore lo vuole (`MobTracker.Want(name, on)`: la barra del pull o la lista
  visibili, cioè la finestra aperta sulla scheda Monitor; gli avvisi con `alerts.onlyTarget` spento, §2.5). Altrimenti
  non legge, non ha tick e non tiene registrati gli eventi della threat (ARC-05); gli eventi di scoperta restano
  registrati in combattimento finché l'interruttore e l'impostazione sono accesi.
- **Posti**: `settings.mobs.max` (8) compreso il mob monitorato. A ogni tick i candidati si ordinano per: fonte
  migliore del mob (tabella di §1.2), stato dell'ultima lettura (DANGER, WARNING, SAFE, poi UNKNOWN), leggibili prima
  dei `secret`, ordine di scoperta; i primi prendono i posti. Un mob che perde il posto non tiene nulla.
- **Budget**: al più `READ_BUDGET` (**40**, M7.4; erano 48) letture per tick (ogni `Threat.Read` e ogni `ReadLead`
  contano una lettura). Una lettura di un mob legge al più `UNITS_PER_MOB` (**10**) unità del roster dello Scanner (le sue
  `ThreatScanner.units`, nello stesso ordine, entro `maxUnits`): `player`, `pet`, i tank designati e chi lo teneva
  all'ultima lettura sempre; gli altri posti a turno, con un cursore per mob. In un party (fino a 6 unità con il
  famiglio) ogni lettura legge tutti.
- **Ordine dei mob in un tick**: prima quelli segnati da un evento (`UNIT_THREAT_LIST_UPDATE` con uno dei loro token),
  poi quelli in DANGER, poi a turno dopo l'ultimo letto; ci si ferma quando la lettura del mob seguente non entra nel
  budget, ma almeno un mob per tick. Un evento non fa mai una lettura fuori dal tick: il costo resta nel budget
  (come MON-07). Con eventi puntuali M0.7 può abbassare `RATE` **[probe P6]**.
- **Costo atteso**: in un party ogni mob costa 6 unità e la lettura di chi lo tiene (7): 5 mob per tick (35 letture,
  70 al secondo; il monitor a 5 Hz con 6 unità ne fa 30), i 7 mob oltre a quello monitorato riletti ogni secondo; in
  un raid ogni mob costa 10 unità e la lettura di chi lo tiene (11): 3 mob per tick, con 8 posti ogni mob riletto ogni
  1,5 s circa (con 12 posti ogni 2 s), sempre dentro il suo limite di freschezza (`2 · I`).
- *M7.4* **Budget misurato**: il test lungo ([SPEC-01 §5.1](SPEC-01-platform-architecture.md#51-il-costo-di-un-tick-del-monitor-misura-offline-di-m27))
  ha trovato che con 48 letture (circa 42 per tick) un tick dei mob in un raid costa più di un tick del monitor con 40
  unità (165 000 contro 153 000 istruzioni di media con la barra del pull, 174 000 con la lista); con **40** costa meno
  (138 000 e 149 000, al peggio 184 000 contro 191 000). Fra 33 e 43 letture un raid legge gli stessi 3 mob per tick;
  il resto è margine per i party. Il budget vero lo dà P10 (Q26).
- **Allocazioni**: record e righe dei mob vengono da pool fatti una volta per posto e per indice del roster
  (DAT-11), il tick non alloca dopo il riscaldamento (ARC-06); una chiave si costruisce solo quando un mob entra.
- *M7.2* **Solo spazzata**: quando il tick ha le condizioni sopra ma nessun mob è noto oltre a quello monitorato, il
  tick gira lo stesso e fa **soltanto** la spazzata (nessuna lettura della threat, `UNIT_THREAT_LIST_UPDATE` non
  registrato); altrimenti, senza eventi di scoperta (P6), nessun mob comparirebbe mai. Appena c'è un altro mob il tick
  legge e registra l'evento; `/atw debug` dice *sweeping* o *reading*.
- *M7.2* **Intervallo atteso**: un mob letto in questo tick ha `I = (1 / RATE) · giri`, dove i giri sono i mob con un
  posto diviso i mob letti nel tick (arrotondato in su); una riga letta a turno dentro il mob ha `I` per i giri del
  suo cursore. Il costo stimato di un mob prima di leggerlo è le sue unità più la lettura di chi lo tiene
  (`ReadLead`).

### 1.7 Ciclo di vita di un mob

| Che cosa succede | Come si vede | Effetto |
|---|---|---|
| Nuovo candidato | evento di scoperta o spazzata | voce `pending`; `MOBS_UPDATED()` |
| Nessuna unità osservata nella sua lista | tutte le letture `nil` per `FORGET` (**10 s**) | esce: non è il combattimento del gruppo |
| Il mob muore | `UnitIsDead` vero a una lettura, alla spazzata o a un evento | esce subito |
| Nessun token lo nomina | `UnitTokenFromGUID` senza risposta | UNKNOWN `no-token`; esce dopo `FORGET` senza un token |
| Il token nomina un altro mob | GUID diverso | il token passa al nuovo mob; il vecchio resta con gli altri suoi token, o `no-token` |
| Il mob diventa il mob monitorato (o smette di esserlo) | `TARGET_CHANGED` | la sua riga viene dal monitor (o torna alla rotazione) |
| Cambio del roster | `GROUP_ROSTER_UPDATE`, `UNIT_PET` (lo Scanner ricostruisce le unità) | cursori per mob azzerati, letture tenute |
| Fine del combattimento | `COMBAT_ENDED` | lista vuota, tick fermo, portata conservata come `lastReach`; `MOBS_UPDATED()` |
| Inizio del combattimento | `COMBAT_STARTED` | si riparte da capo, portata `unknown` |

*M7.2*: `MOBS_UPDATED()` si emette alla fine di ogni tick (anche di sola spazzata) e a `COMBAT_ENDED`: un mob nuovo
entra nella lista al tick seguente, entro mezzo secondo. Senza tick (nessun consumatore) gli eventi di scoperta restano
registrati in combattimento, ma un mob che nessun token nomina più esce subito, così la memoria non cresce in un
combattimento che nessuno guarda. Un mob che perde il posto (o lo cede al mob monitorato) esce dalla lista con
`MOB_STATE_CHANGED(mobKey, old, nil)` e ci rientra `pending` con le righe pulite.

### 1.8 Stato e rischio di un mob (`Data/MobRisk.lua`)

Un modulo senza API del gioco: prende le righe di un mob e dà il suo **stato** e il suo **motivo**. Le soglie `W` e
`D`, l'isteresi e la permanenza sono quelle del monitor (`ThreatState.DEFAULTS` e le impostazioni di
[SPEC-03 §2](SPEC-03-threat-monitor-ui.md#2-stati-e-soglie)); *tank designati* e *tank sconosciuto* come in
[SPEC-03 §2.1](SPEC-03-threat-monitor-ui.md#21-chi-è-il-tank).

| Stato e motivo | In `values` | In `state` |
|---|---|---|
| DANGER `aggro` (*mob sciolto*) | ci sono tank designati e chi lo tiene non è uno di loro | un non tank ha lo stato 2–3, con tank designati |
| DANGER `close` | un'unità che non lo tiene ha `p ≥ D` | chi lo tiene ha lo stato 2, o `l` 2–3 |
| WARNING `no-tank` (*mob senza tank*) | ci sono tank designati, nessuno di loro è nella sua lista, e chi lo tiene non è fra le unità osservate | uguale |
| WARNING `near` | un'unità che non lo tiene ha `W ≤ p < D` | un'unità che non lo tiene ha lo stato 1, o `l = 1` |
| SAFE | chi lo tiene è noto e nessun altro arriva a `W` | chi lo tiene ha lo stato 3 e `l = 0` (senza `l`: SAFE, *Margin unknown*) |
| UNKNOWN e il motivo di §1.5 | modalità del mob `none` | uguale |

- Senza tank designati (da soli, ruoli `NONE` o segreti, **[probe P9]**) chi tiene il mob vale da tank, quindi `aggro`
  e `no-tank` non ci sono: restano `close` e `near`. Un mob senza nessuno che lo tiene fra le unità osservate e senza
  tank designati è SAFE con il tooltip *Held by a unit not in the list*, se nessuno arriva a `W`.
- Fra due regole vale lo stato più alto; a parità di stato il motivo nell'ordine della tabella.
- **Isteresi** (`values`): uno stato si lascia solo `hysteresis` punti sotto la sua soglia (MON-10). **Permanenza**:
  uno stato sale subito, scende o diventa UNKNOWN solo dopo `dwell` secondi dall'ultimo cambio (MON-12).
- `MOB_STATE_CHANGED(mobKey, old, new, reason)` si emette solo per lo stato mostrato, dopo isteresi e permanenza;
  `old` `nil` = il mob è entrato, `new` `nil` = è uscito. Il mob monitorato non lo emette (ha già gli eventi del
  monitor).
- Ogni riga di un mob ha anche `selfState`, lo stato del giocatore su quel mob con le regole dei non tank di
  SPEC-03 §2.2–§2.3 (per §2.5), e `age`, l'età della lettura.

### 1.9 Impostazioni (schema 6 dell'account)

Dettaglio in [SPEC-02 §3.10](SPEC-02-data-model-storage.md#310-schema-6-m7-più-mob-e-avvisi-sugli-altri-mob); i
predefiniti hanno un solo posto, `Config.MOBS_DEFAULTS` (intervalli `Config.MOBS`) e `Config.ALERTS_DEFAULTS.onlyTarget`,
le risposte proposte di [Q26](SPEC-09-risks-open-questions.md).

| Percorso | Tipo | Predefinito | Regola | Uso |
|---|---|---|---|---|
| `settings.mobs.enabled` | booleano | `true` | — | segue gli altri mob (spento: nessun tick, nessuna barra) |
| `settings.mobs.max` | intero | `8` | 2–12 | mob osservati, compreso il mob monitorato (MT-02) |
| `settings.mobs.nameplates` | booleano | `true` | — | usa le targhe nemiche come fonte |
| `settings.alerts.onlyTarget` | booleano | `true` | — | avvisi solo sul mob monitorato (§2.5) |

## 2. Dungeon Focus (M7)

Fonte §5.6: *identificare i mob sui quali il gruppo rischia maggiormente di perdere aggro*. Un elenco dei mob con il
rischio più alto per il gruppo (un DPS vicino a strappare, un mob senza tank), ordinato per rischio; clic per
monitorare quel mob.

### 2.1 Ordine per rischio

Gli stessi mob di §1 (al più `settings.mobs.max`), compreso il mob monitorato, in quest'ordine:

1. lo stato: DANGER, WARNING, SAFE; gli UNKNOWN sempre in fondo (come le righe del monitor, SPEC-03 §3);
2. a parità di stato, il motivo: `aggro`, `close`, `no-tank`, `near` (`MobRisk.REASON_ORDER`, Q27);
3. poi il margine più piccolo (in `values`) o lo stato del gioco più alto di chi è più vicino (in `state`);
4. poi lo stato del giocatore su quel mob (`selfState`), più alto prima;
5. i pareggi nell'ordine di scoperta, mai per nome (può essere segreto).

L'ordine si ricalcola al più una volta al secondo, e subito quando un mob entra in DANGER (come MON-13); in mezzo le
righe restano al loro posto mentre i valori cambiano.

### 2.2 Che cosa si vede di un mob

| Campo | Fonte | Categoria | `values` | `state` | `none` |
|---|---|---|---|---|---|
| Stato | §1.8 | calcolata in `values`, rilevata in `state` | distintivo (icona e parola) | uguale | UNKNOWN e motivo |
| Nome e classificazione | `UnitName`, `UnitClassification` | rilevata | nome, *Elite*, *Boss*… | uguale | uguale; segreto → *Unknown mob* |
| Chi lo tiene | la riga che lo tiene | rilevata | nome con l'icona `tank`, o con `state-warning` se non è un tank | uguale | `—` |
| Il più vicino | §1.5 | rilevata | nome e `87 %` | nome e *above the tank* (stato 1) | `—` |
| Margine | `100 − p` del più vicino | calcolata | `+13` | — | — |
| Età | `now − observedAt` | rilevata | nel tooltip; nella riga solo oltre 1 s | uguale | uguale |
| Fonte | §1.2 | rilevata | nel tooltip (*Focus*, *Boss*, *Nameplate*, *Group target*, *Your target*) | uguale | uguale |

Il tooltip di una riga dà ogni valore con la parola della sua categoria, l'età, la fonte, la modalità e, se c'è, il
motivo; ciò che manca si scrive (*Secret value*, *No unit names this mob now*…), mai si omette.

### 2.3 La barra del pull e la lista (`UI/FocusList.lua`)

Nella scheda **Monitor** (compatta), costruite da `UI/ThreatList.lua` come la striscia del Coach; aspetto in
[ui-style §3.7](ui-style.md#37-dungeon-focus-m7).

- **Barra del pull** (20 pt, fra l'intestazione del mob e l'intestazione dell'elenco): c'è quando l'interruttore è
  acceso, `settings.mobs.enabled` è vero, il giocatore è in combattimento (o nella demo) e il tracker ha almeno un mob
  oltre a quello monitorato, oppure, in un gruppo, la portata è ridotta (`focus-boss`, `target`, `none`). Dice
  *Pull · 5* (i mob seguiti), poi il distintivo del mob più a rischio **diverso da quello monitorato** con la parola del
  motivo (*On Mage*, *Close*, *No tank*), oppure *All safe*; con la portata ridotta, la frase di §1.4 in `text-3` con
  il motivo nel tooltip. Un clic apre la lista al posto dell'elenco della threat; un altro clic la chiude.
- **Lista** (al posto dell'elenco della threat, stessa altezza): una riga da 20 pt per mob, da un pool di 12, nei campi
  di §2.2; il mob monitorato con l'anello `accent`; le righe UNKNOWN tratteggiate con `?`; le righe che non entrano si
  riassumono nell'ultima come *+N more* (le meno a rischio). Piede: *Reach: all · 6 of 8 · 0.4 s ago* (portata, mob
  seguiti sul limite, età dell'ultimo tick), in `warn` quando la portata è ridotta.
- La vista legge solo `MobTracker`, `MobRisk` e `TargetTracker` (nessuna API del gioco, ARC-02); si ridisegna a
  `MOBS_UPDATED` solo se è visibile, e scrive un testo solo quando cambia.
- Senza mob (fuori dal combattimento, o un solo mob) la barra non c'è e la lista, se era aperta, torna all'elenco.
- *M7.3* **La barra, ordine delle frasi**: (1) il mob più a rischio diverso dal monitorato in DANGER o WARNING, con il
  motivo (`near`: *Getting close*); (2) con portata `unknown`, *Reading the pull…*; (3) con la portata ridotta, la frase
  di §1.4 (mai *All safe* quando non tutto si può leggere); (4) se tutti gli altri sono UNKNOWN, il distintivo UNKNOWN
  e il motivo breve; (5) se qualcuno è UNKNOWN, *All safe · N unknown* con il distintivo UNKNOWN; (6) *All safe*. La
  **portata è ridotta** per `none` sempre, per `focus-boss` e `target` solo se c'è un motivo (così un combattimento con
  un solo mob non è una riduzione). *In un gruppo* vuol dire che le unità dello Scanner hanno un membro `party` o
  `raid`.
- *M7.3* La lista mostra le righe che entrano nell'altezza (al più 12); in una finestra di 300 × 220 ne entrano tre e
  *+N more*. In una finestra stretta restano distintivo, nome, icona di chi lo tiene, percentuale e, per un mob
  UNKNOWN, il motivo breve nella riga. Chi lo tiene, quando nessuna unità osservata lo tiene, è il bersaglio del mob
  (`MobTracker.TargetName`, *… (not in the list)*). L'ordine nasce nella vista (`Focus:Order`); nomi e classificazioni
  da `MobTracker.NameOf`, al più una volta al secondo.

### 2.4 Clic per monitorare: il mob fissato (`TargetTracker.Pin`)

- Un clic su una riga della lista **fissa** quel mob: `TargetTracker.Pin(mobKey)` (nuovo in M7.2, solo con
  l'interruttore acceso) aggiunge una regola **0** prima delle tre di SPEC-03 §1.2: il mob fissato, finché il tracker
  ha un token che lo nomina (`MobTracker.TokenOf(mobKey)`), attaccabile e non morto. `mobToken` è quel token, chiesto
  di nuovo al tracker a ogni `Check()` (l'indice di una targa può cambiare). La lista si chiude e il monitor mostra il
  mob fissato, con l'icona `pin` nell'intestazione.
- Si fissa solo un mob con una chiave che si può seguire: `mob:` (GUID) o `tok:focus` / `tok:bossN`; il mob già
  monitorato non si fissa (il clic chiude la lista); una riga che non si può fissare lo dice nel tooltip (*Cannot be
  followed: no stable identity*).
- **Il mob fissato si lascia** (`TargetTracker.Pin(nil)`) con un clic sull'icona `pin` dell'intestazione o sulla sua
  riga, quando il giocatore sceglie un nuovo target ostile diverso (`PLAYER_TARGET_CHANGED`, Q27), quando il mob muore
  o nessun token lo nomina più (stato `died` o `lost` come oggi, poi le regole 1–3), a `COMBAT_ENDED`, con l'interruttore
  o l'impostazione spenti. Non si salva.
- Fissare o lasciare emette `TARGET_CHANGED(mobKey)` (il monitor riparte su quel mob come per un cambio di target) e
  `PIN_CHANGED(mobKey)` (`nil` = nessuno). Avvisi, Coach e registrazione seguono il mob monitorato, quindi anche quello
  fissato: la registrazione resta com'è (REC-02).
- Il nome di chi lo tiene, quando nessuna unità osservata lo tiene, è `UnitName(mobToken .. "target")` (`focustarget`,
  `boss1target`, `nameplate3target`) **[probe P5]**.
- *M7.2*: `TargetTracker.Pin(mobKey)` risponde `true`, oppure `false` e il motivo: `off` (interruttore spento),
  `no-identity` (una chiave che non si segue, per esempio `tgt:` o `tok:nameplate…`), `monitored` (il mob già
  monitorato), `no-token` (nessun token lo nomina ora); `Pin(nil)` dice se c'era un mob da lasciare.
  `MobTracker.TokenOf(mobKey)` dà il token, oppure `nil` e `dead` o `lost`: un mob fissato morto lascia lo stato
  `died`, uno scomparso `lost`. Un nuovo target ostile lascia il mob fissato se il suo GUID è diverso (o non si legge);
  per una chiave `tok:` solo se `UnitIsUnit` non dice che è lo stesso mob. Per la vista (M7.3) ci sono anche
  `MobTracker.Get(mobKey)` (la voce, in sola lettura) e `MobTracker.Rows(mobKey)` (le righe del suo posto, o i record
  del monitor per il mob monitorato).

### 2.5 Avvisi con più mob (`alerts.onlyTarget`)

[SPEC-04 §1.1](SPEC-04-alerts-coach.md#11-quando-scatta-un-avviso) diceva che l'impostazione arriva con M7. Con
`alerts.onlyTarget` **acceso** (predefinito, Q26) nulla cambia: gli avvisi valgono solo per il mob monitorato. **Spento**
(*Alerts about other mobs* nella card *Alerts*), Alerts ascolta anche `MOB_STATE_CHANGED` per i mob diversi da quello
monitorato, con un tipo nuovo, `mob`:

| Messaggio (chiave, proposta `enUS`) | Quando entra | Soggetto | Gravità | Chi lo riceve |
|---|---|---|---|---|
| `ALERT_MOB_AGGRO` *A mob is on %s.* | DANGER `aggro` (`%s` chi lo tiene) | altra unità | 3 | come `alerts.others` (di predefinito solo il tank) |
| `ALERT_MOB_CLOSE` *%s is about to pull a mob.* | DANGER `close` (`%s` il più vicino) | altra unità | 2 | come `alerts.others` |
| `ALERT_MOB_NO_TANK` *A mob is not on the tank.* | WARNING `no-tank` | — | 1 | come `alerts.others` |
| `ALERT_MOB_SELF` *Your threat on another mob is very high* (M7.4: vero sia quando si è vicini sia quando lo si tiene) | `selfState` del giocatore entra in DANGER su un altro mob | il giocatore | 2 | il giocatore che non fa il tank (mai al tank, D12) |

- Valgono le regole di SPEC-04: solo le **entrate** (ALR-01, da UNKNOWN solo sopra l'ultimo stato noto), il cooldown
  `alerts.cooldown` per tipo `mob` e **per mob** (non per unità), `OTHER_GAP` fra due avvisi sulle altre unità, il
  silenzio, le esclusioni per sessione (un `%s` escluso non avvisa), il suono solo dalla gravità 2. Mai in chat.
- Il Coach resta sul mob monitorato. Gli avvisi `mob` **non** si registrano: il mob non è nella sessione (Recorder li
  ignora, nessun codice nuovo in SPEC-02 §4.3).
- Con l'interruttore `multitarget` spento `alerts.onlyTarget` non conta (vale acceso).

*M7.4*, come è stato realizzato (`Data/Alerts.lua`):

- Alerts guarda la lista dopo ogni `MOBS_UPDATED` (non solo `MOB_STATE_CHANGED`): anche un cambio di motivo (`close` →
  `aggro`) o dello stato del giocatore è un'entrata. Tiene per ogni chiave di mob l'ultima condizione conosciuta
  (`aggro` > `close` > `no-tank` > `near` > SAFE) e l'ultimo stato del giocatore: avvisa solo ciò che **sale**; un mob
  UNKNOWN, o che non si legge ora anche se mostra ancora l'ultimo stato per la permanenza, non aggiorna nulla (da
  UNKNOWN solo sopra l'ultimo noto). La memoria si aggiorna anche per il mob monitorato e con `alerts.onlyTarget`
  acceso, così chi cambia target o accende l'impostazione a metà combattimento non riceve avvisi su condizioni già in
  corso; si svuota quando il mob esce dal tracker e a fine combattimento.
- **Un avviso per mob a ogni aggiornamento**, prima quello sul giocatore: se sale `selfState` e il giocatore non fa il
  tank (ruolo `TANK`, o chi tiene il mob monitorato senza tank designati; senza tank designati chi tiene *quel* mob è
  il suo tank) esce `ALERT_MOB_SELF`; altrimenti l'avviso sul mob. Gli avvisi sul mob non nominano mai il giocatore
  (c'è `ALERT_MOB_SELF`); `ALERT_MOB_CLOSE` non esce se il più vicino è un tank (cambio di tank) o è escluso;
  `ALERT_MOB_AGGRO` non esce per il proprio famiglio con `alerts.pet` spento. Senza un più vicino noto `ALERT_MOB_CLOSE`
  dice *Unknown*.
- Gli avvisi che escono nello stesso aggiornamento partono dal più grave (`aggro`, poi quello sul giocatore, poi
  `close`, poi `no-tank`): l'intervallo `OTHER_GAP` ne lascia passare uno sugli altri, il resto si conta e non si
  ripete. Il cooldown è per mob (tipo `mob`), con le chiavi vecchie dimenticate oltre `MOB_PRUNE_AT` (64).
- Con il suono acceso (avvisi accesi, non silenziati, `alerts.onlyTarget` spento) Alerts vuole il tracker
  (`MobTracker.Want("alerts")`), così il suono funziona a finestra chiusa; senza suono lo vuole solo la finestra, come
  per lo Scanner (SPEC-04 §1.4). Nella demo non escono avvisi `mob`.
- Categorie: `detected`, `no-tank` `calculated`; il testo dice su quali dati poggia (`ALERT_WHY_MOB`,
  `ALERT_WHY_MOB_NO_TANK`; per `aggro` `ALERT_WHY_HOLDER`).

### 2.6 Impostazioni, comandi, demo e diagnostica

- **Card *Dungeon Focus*** (M7.3; solo con l'interruttore, dopo *Monitor* e prima di *Alerts*): *Track other mobs*
  (`settings.mobs.enabled`), *Mobs followed* (cursore 2–12, salvato al rilascio), *Use enemy nameplates* con la nota
  *Shows mobs only while the game's enemy nameplates are on.* Nella card *Alerts* (M7.4) l'interruttore *Alerts about
  other mobs* (`alerts.onlyTarget` al contrario). Con dati in sola lettura come le altre card (*Not saved*).
- **`/atw focus`** (M7.3): apre la finestra sulla scheda Monitor con la lista aperta; di nuovo la chiude. Con
  l'interruttore spento *This arrives in v0.7.0.*; con l'impostazione spenta *Other mobs are off in Settings.*
  *M7.3*: quando non c'è la barra (fuori dal combattimento, un solo mob) apre la finestra e risponde *No other mobs to
  show right now.*
- **Demo** (M7.3): `Data/Demo.lua` aggiunge un pull inventato di cinque mob (uno sciolto su un DPS, uno vicino a
  strappare, uno senza tank, uno segreto, uno senza token), con la portata `all`; `Core/Demo.lua` mette un tracker
  inventato in `ns.MobTracker` come fa con lo Scanner. Nulla letto, nulla salvato. *M7.3*: i cinque mob si aggiungono
  al golem monitorato (*Pull · 6*); nella demo un mob non si fissa (il tooltip lo dice).
- **`/atw debug`**, sezione *Mobs* (M7.2, gli avvisi M7.4): interruttore e impostazioni, attivo o no, portata e motivo,
  posti usati sul limite, letture dell'ultimo tick e media, turni, mob `secret`, `no-token` e `pending`, eventi per
  genere di token, letture per fonte e modalità, mob fissato sì o no, avvisi `mob` emessi. Mai nomi né GUID.

### 2.7 Moduli, eventi e interruttori

| File | Responsabilità | Bus | Step |
|---|---|---|---|
| `Core/Compat.lua` (cambio) | `Unit.TokenFromGUID`, `Unit.CanCompare` (`C_Secrets.CanCompareUnitTokens`), le voci `unit.TokenFromGUID`, `secret.CanCompare` della tabella delle API ([SPEC-01 §8.2](SPEC-01-platform-architecture.md#82-tabella-delle-api)) | — | M7.2 |
| `Core/Config.lua` (cambio) | schema 6, `Config.MOBS_DEFAULTS`, `Config.MOBS`, `ALERTS_DEFAULTS.onlyTarget` | — | M7.2 |
| `Data/MobRisk.lua` | stato, motivo, isteresi e permanenza di un mob (§1.8); ordine di §2.1 | emette `MOB_STATE_CHANGED(mobKey, old, new, reason)` | M7.2 |
| `Data/MobTracker.lua` | fonti, chiavi, posti, rotazione, budget, letture, portata, ciclo di vita (§1.2–§1.7); `Want`, `TokenOf`, `List` | emette `MOBS_UPDATED()`; ascolta `COMBAT_STARTED`, `COMBAT_ENDED`, `TARGET_CHANGED`, `THREAT_UPDATED`, `WINDOW_SHOWN`, `TAB_CHANGED`, `CONFIG_LOADED`, `CONFIG_CHANGED`, `DEMO_CHANGED`; dal gioco `NAME_PLATE_UNIT_ADDED`, `NAME_PLATE_UNIT_REMOVED`, `PLAYER_FOCUS_CHANGED`, `INSTANCE_ENCOUNTER_ENGAGE_UNIT`, `UNIT_TARGET`, `UNIT_THREAT_LIST_UPDATE` | M7.2 |
| `Data/TargetTracker.lua` (cambio) | la regola 0, `Pin`, `Pinned` (§2.4) | emette `PIN_CHANGED(mobKey)`, `TARGET_CHANGED` | M7.2 |
| `UI/FocusList.lua`, `UI/ThreatList.lua` (cambio), `UI/Settings.lua`, `Core/Commands.lua`, `Data/Demo.lua`, `Core/Demo.lua` | barra del pull, lista, clic, icona `pin` nell'intestazione, card *Dungeon Focus*, `/atw focus`, demo | ascolta `MOBS_UPDATED`, `PIN_CHANGED`, `TARGET_CHANGED`, `COMBAT_*`, `CONFIG_CHANGED`, `THEME_CHANGED`, `DEMO_CHANGED` | M7.3 |
| `Data/Alerts.lua`, `Data/Recorder.lua` (cambi) | il tipo `mob` e `alerts.onlyTarget` (§2.5); il Recorder ignora `mob`; l'interruttore nella card *Alerts* | ascolta `MOBS_UPDATED` | M7.4 |

- Nel TOC `Data/MobRisk.lua` e `Data/MobTracker.lua` dopo `Data/ThreatState.lua` (prima di `Data/Alerts.lua`),
  `UI/FocusList.lua` prima di `UI/ThreatList.lua` (come `UI/CoachStrip.lua`).
- **Interruttore** `multitarget` ([ADR 0014](../adr/0014-one-version-per-milestone-and-feature-switches.md)): spento
  fino a M7.R, acceso dalla `v0.7.0`. Spento vuol dire: nessun evento del gioco registrato da `MobTracker`, nessun tick, `Pin` non fa nulla,
  nessuna barra, lista, card o interruttore *Alerts about other mobs*, `alerts.onlyTarget` vale acceso, `/atw focus`
  risponde *This arrives in v0.7.0.*, nessuna sezione *Mobs* in `/atw debug`. Lo schema 6 e la sua migrazione ci sono
  comunque (come lo schema 3 con gli avvisi spenti). I test che lo vogliono spento lo mettono a `false` in `M.features`.

### 2.8 Test per step

Ogni test che passa per le letture gira sui tre esiti per mob (`Fight.OUTCOMES`) e sulle tre portate (GUID, solo
confronto, nessuno dei due), con il client finto (che ha già targhe, focus, boss, `UnitTokenFromGUID`,
`CanCompareUnitTokens` e i segreti per coppia, [SPEC-08 §2](SPEC-08-quality-probe-release.md#2-test-offline)).

| Step | Test e casi |
|---|---|
| **M7.2** | `test_multi_mob.lua`: ogni fonte di §1.2 con i suoi eventi e la spazzata; candidati (ostile, vivo, in combattimento, `UnitAffectingCombat` segreto); chiavi con GUID, senza GUID con e senza confronto, un token stabile che non si distingue dal target escluso; lo stesso mob su più token una volta sola; l'indice di una targa che cambia (`REMOVED` e `ADDED` con lo stesso GUID su un altro indice); `UnitTokenFromGUID`; posti e priorità (`max` 2 e 12); budget e rotazione (party, raid da 40, almeno un mob per tick, cursore per mob); eventi `UNIT_THREAT_LIST_UPDATE` che anticipano senza letture fuori dal tick; i tre esiti per mob e i motivi di §1.5 (`pending`, `stale`, `no-token`, `secret` con `RETRY`); il ciclo di vita di §1.7 (morte, scomparsa, `FORGET`, GUID cambiato, fine e inizio del combattimento, roster); la portata e il suo motivo, la capacità `otherMobs`; il mob monitorato dalle righe del monitor e mai letto dal tracker; consumatori; nessuna allocazione per tick dopo il riscaldamento; interruttore e impostazione spenti (nessun evento registrato). `test_mob_risk.lua`: ogni riga di §1.8 in `values` e `state`, senza tank designati, isteresi e permanenza, `MOB_STATE_CHANGED` solo per lo stato mostrato, l'ordine di §2.1. In `test_target_tracker.lua` la regola 0 e ogni modo di lasciare il mob fissato; in `test_config.lua` lo schema 6 (DAT-20); in `test_compat.lua` le due funzioni nuove; in `test_api_boundary.lua` i moduli nuovi |
| **M7.3** | `test_focus_list.lua`: barra e lista in ogni situazione di §2.3 (portate, *All safe*, *+N more*, UNKNOWN con il motivo, demo), ordine e ricalcolo al più una volta al secondo, clic che fissa e chiude, righe che non si fissano, icona `pin` e clic che lascia, tooltip con categorie, età e fonte, testi nelle due lingue, nessuna API del gioco; in `test_settings.lua` la card; in `test_commands.lua` `/atw focus`; in `test_demo.lua` il pull inventato; in `test_ui_texts.lua` le chiavi nuove. Pagina del manuale *Dungeon Focus* nelle due lingue con le anteprime `focus-bar`, `focus-list` (anche in Aurora e Warden) |
| **M7.4** | in `test_alerts.lua` il tipo `mob`: ogni messaggio di §2.5, entrate e non discese, cooldown per mob, `others`, esclusioni, silenzio, `onlyTarget` acceso (nulla) e spento, interruttore spento; in `test_recorder.lua` gli avvisi `mob` non scritti; in `test_coach_wording.lua` le chiavi `ALERT_MOB_*`. Test lunghi `Tests/long/test_multi_mob_long.lua`: un raid da 40 con 40 targhe e 12 mob per 30 minuti, mob che diventano irraggiungibili, segreti a metà combattimento, GUID che cambiano, targhe che si rimescolano; il costo di un tick dei mob (istruzioni nel client finto) non supera quello di un tick del monitor con 40 unità (SPEC-01 §5.1), le letture per tick restano nel budget, la memoria non cresce |

### 2.9 Cosa aspetta il probe e il gioco

- **[probe P5]** quali fonti rispondono (le righe di §0), se un mob visto solo da una targa risponde, se la threat dei
  membri risponde sugli altri mob, se `UnitTokenFromGUID` ritrova un mob, `focustarget` e `nameplateNtarget`;
  **[probe P6]** se `UNIT_THREAT_LIST_UPDATE` arriva per le targhe e i boss e con che ritardo; **[probe P9]** GUID e
  confronto in istanza (la portata massima); **[probe P3]** la modalità degli altri mob; **[probe P10]** `RATE`,
  `READ_BUDGET`, `UNITS_PER_MOB`.
- **[da provare in gioco]** (checklist M7.5): un pull di dungeon da 3–6 mob con e senza targhe; un mob sciolto su un
  DPS e uno che il tank non ha preso; il clic che fissa un mob e il ritorno al target; la leggibilità della barra e
  della lista in combattimento e in italiano; il costo (FPS) con 40 targhe in un raid; gli avvisi `mob` con
  `onlyTarget` spento.

## 3. Heatmap (M8.3)

Fonte §5.7: *funzionalità opzionale: colorazione delle righe del Threat Monitor; integrazione con raid frame solo se
tecnicamente e legalmente compatibile; nessuna dipendenza obbligatoria da addon esterni; colori configurabili e
alternative non basate soltanto sul colore*. Completato in **M8.1** (2026-11-28) prima del probe, come M2–M7 (D7);
decisione D27 e [ADR 0021](../adr/0021-raid-frames-are-only-overlaid-never-touched.md), risposte proposte in
[Q29](SPEC-09-risks-open-questions.md).

### 3.1 Principi

- **HM-01** MUST: la heatmap ripete ciò che la riga dice già, non lo sostituisce: ogni riga tiene distintivo, icona e
  parola (ST-02) e il calore non è mai l'unico segno di uno stato. Uno stato UNKNOWN non ha calore (nessun colore che
  sembri un numero).
- **HM-02** MUST: i colori sono solo i token di stato della tavolozza scelta (§5.2), con le trasparenze di §3.2; nessun
  colore libero (Q30), nessun colore fuori da `UI/Theme.lua`.
- **HM-03** MUST: i riquadri del raid di Blizzard **non si toccano mai**: nessun `hooksecurefunc` sulle loro funzioni,
  nessun `SetPoint`, `SetParent` o `SetFrameLevel` riferito a loro, nessun campo scritto nelle loro tabelle, nessuna
  texture creata su di loro, nessun metodo chiamato su di loro tranne le letture di §3.3, e quelle solo fuori dal
  combattimento ([ADR 0021](../adr/0021-raid-frames-are-only-overlaid-never-touched.md)). Il dump elenca
  `hooksecurefunc` e le funzioni `CompactUnitFrame_*` (per esempio `CompactUnitFrame_UpdateAll`,
  `CompactUnitFrame_UpdateAggroHighlight`): non si usano.
- **HM-04** MUST: nessuna dipendenza da altri addon; con riquadri di un altro addon (che sostituisce quelli di Blizzard)
  la sovrapposizione non trova nulla e non disegna nulla, e la card lo dice.
- **HM-05** MUST: nulla si salva oltre alle due impostazioni di §3.4; con l'interruttore `heatmap` spento o con le due
  impostazioni spente nessun evento del gioco è registrato per la heatmap e nessun frame è creato.
- **HM-06** MUST: costo limitato (SPEC-08 §8): una riga si ridipinge solo quando cambia il suo passo di calore; la
  sovrapposizione si aggiorna solo dopo `THREAT_UPDATED` e solo per i segni che cambiano; nessuna allocazione per tick
  dopo il riscaldamento.

### 3.2 Le righe del monitor (`UI/ThreatList.lua`)

Ogni riga del monitor ha una texture di calore (`w.heat`) sotto il contenuto, larga quanto la riga, sopra il fondo
`surface-1` e sotto l'evidenziazione del passaggio del mouse; l'anello `accent` della propria riga resta sopra. Il
colore è il token di stato della riga (`state-safe`, `state-warning`, `state-danger` della tavolozza attiva), la
trasparenza viene dal **passo**:

| Passo | Quando (`values`) | Quando (`state`) | Trasparenza (`Heatmap.ALPHA`) |
|---|---|---|---|
| 0 | UNKNOWN; SAFE sotto il 50 % (la scalata; per il tank il secondo sotto il 50 % del tank) | UNKNOWN, SAFE | 0 (nessun calore) |
| 1 | SAFE dal 50 % | — | 0,06 |
| 2 | WARNING sotto la metà fra le soglie, `(W + D) / 2` | WARNING | 0,10 |
| 3 | WARNING dalla metà fra le soglie | — | 0,14 |
| 4 | DANGER, e la riga di chi tiene il mob senza essere un tank | DANGER | 0,18 |

- Lo stato è quello mostrato dalla riga (dopo isteresi e permanenza, SPEC-03 §2.4): il calore non sale né scende per
  conto suo. Dentro lo stesso stato i confini del 50 % e della metà fra le soglie hanno un'isteresi di **2 punti**
  (`Heatmap.HYSTERESIS`), così il passo non oscilla; una riga cambia passo al più una volta al secondo, tranne
  l'entrata in DANGER, che è subito (come MON-13).
- Il passo cambia la trasparenza con una dissolvenza di 120 ms se le animazioni sono accese; **nessun lampeggio**.
- **Contrasto**: `Tests/test_theme.lua` mescola il token di stato al passo 4 sopra `surface-1` e `surface-2` (il
  passaggio del mouse) in ogni tema e in ogni tavolozza, e controlla `text-1` e `text-2` ≥ 4,5:1, `text-3` ≥ 3:1,
  `accent-text` ≥ 4,5:1 e la barra della riga (il riempimento di stato sul fondo mescolato) ≥ 3:1. Se una combinazione
  non regge, si abbassa `Heatmap.ALPHA[4]` (un solo punto) e ui-style §3.8 scrive il valore.
- Le righe del **Dungeon Focus** (§2.3) **non** hanno calore in M8: il margine del tick dei mob sul tick del monitor è
  di circa il 2 % (M7.4); M8.6 può aggiungerlo se la misura lo permette, con una nota qui.
- La demo (`/atw demo`) mostra il calore sulle righe inventate.

### 3.3 I riquadri del raid di Blizzard (`UI/RaidOverlay.lua`)

**Che cosa.** Sopra ogni riquadro compatto del gruppo o del raid di Blizzard (quelli del gioco, *Compact Raid Frames*)
di un membro che è nella lista del mob monitorato, un **segno** dell'addon: un bordo di 2 px nel token di stato e, in
alto, un piccolo distintivo con icona e parola (`Badge`, come ST-02). Il segno compare **solo** per WARNING, DANGER e
per chi tiene il mob senza essere un tank; SAFE e UNKNOWN non mostrano nulla (nessuna affermazione dove non c'è
rischio o non c'è un dato). Il segno non copre il centro del riquadro (nome e vita) e non prende il mouse
(`EnableMouse(false)`): clic, menu e clic con incantesimo restano del riquadro del gioco. Si spegne nella demo (stati
inventati su riquadri veri sarebbero falsi).

**Come, senza toccare i riquadri** (HM-03, ADR 0021). Una sovrapposizione **staccata**:

1. Un frame dell'addon, `AzerothThreatwardenRaidOverlay`, figlio di `UIParent`, mai protetto, con un pool di 40 segni
   creati la prima volta che servono. Nessun segno è ancorato a un riquadro del gioco: ogni segno è ancorato a
   `UIParent` in coordinate assolute.
2. **Fuori dal combattimento** (`InCombatLockdown()` falso, attraverso Compat) `Compat.RaidFrames.Collect(out)` cerca a
   runtime, con `rawget` su `_G` come PRB-05 (il dump elenca le funzioni `CompactUnitFrame_*` ma nessun frame per
   nome), i riquadri visibili `CompactPartyFrameMember1–5`, `CompactRaidFrame1–40` e `CompactRaidGroup1–8Member1–5`,
   e di ognuno **legge** soltanto il campo `unit` (o `displayedUnit`), `IsVisible()`, `GetRect()` e
   `GetEffectiveScale()`; restituisce `{ unit, left, bottom, width, height }` in coordinate di `UIParent` in una
   tabella riusata. Nessun'altra chiamata, nessuna scrittura. Un valore segreto o un errore (`pcall`) vale come
   riquadro assente.
3. Le posizioni si copiano: a `COMBAT_ENDED`, a `GROUP_CHANGED` e al cambio del roster fuori dal combattimento, a
   `DISPLAY_CHANGED`, quando l'impostazione si accende, e ogni **2 s** fuori dal combattimento finché l'impostazione è
   accesa e il giocatore è in un gruppo (la disposizione dei riquadri può cambiare senza un evento che il dump
   documenti; `COMPACT_UNIT_FRAME_PROFILES_LOADED` è l'unico evento dei riquadri nel dump e si ascolta anche quello).
4. **In combattimento** le posizioni restano quelle copiate; cambiano soltanto colore, trasparenza e parola dei segni
   (metodi delle texture e dei testi dell'addon, che non sono protetti). Se il roster cambia in combattimento
   (`GROUP_ROSTER_UPDATE`), i riquadri si sono forse spostati: **tutti** i segni si nascondono fino alla fine del
   combattimento e `/atw debug` lo conta.
5. Il segno di un membro si sceglie dal suo token (`unit` del riquadro) e dalle righe del monitor (il token di ogni
   riga, dallo Scanner); un riquadro con un token che non è nella lista non ha segno.

**Il rischio di taint, detto com'è.** Il taint nasce quando codice di un addon **scrive** qualcosa che poi il codice
protetto del gioco legge (un campo di un riquadro, una funzione agganciata, un ancoraggio), e da lì le azioni
protette del gioco vengono bloccate (`ADDON_ACTION_BLOCKED`) o i riquadri si rompono in combattimento. La
sovrapposizione staccata non scrive nulla nei riquadri e non aggancia nulla, quindi **non dovrebbe** causare taint. I
rischi che restano, **[da provare in gioco]** e nella checklist di rilascio (SPEC-08 §10):

- che su Forever leggere un campo o la geometria di un riquadro protetto non sia innocuo come nel client standard, o
  che il client lo neghi (valori segreti o `nil`: la sovrapposizione non disegna e la card dice *The game's raid
  frames cannot be read here.*);
- che i riquadri abbiano altri nomi su Forever (nessun riquadro trovato: come sopra);
- che i riquadri si spostino in combattimento senza un cambio del roster (segni fuori posto fino alla fine del
  combattimento);
- che le UI personalizzate nascondano i riquadri di Blizzard (nessun segno, HM-04).

Se il controllo nel gioco (il registro del taint acceso dal proprietario, gli `ADDON_ACTION_BLOCKED` e
`ADDON_ACTION_FORBIDDEN` contati da `Core/Diagnostics.lua`) attribuisce anche **un** blocco o un taint alla
sovrapposizione, la risposta proposta di Q29 è toglierla: l'impostazione sparisce, la heatmap resta sulle righe del
monitor, il manuale lo dice. **Alternativa scartata**: agganciare `CompactUnitFrame_UpdateAll` o
`CompactUnitFrame_UpdateHealthColor` e cambiare il colore della barra della vita o creare texture sui riquadri del
gioco: è il modo comune negli altri client, ma scrive nei riquadri (rischio di taint) e litiga con l'evidenziazione
dell'aggro che i riquadri di Blizzard hanno già (`CompactUnitFrame_UpdateAggroHighlight`, che usa la threat del
gioco).

**Capacità** `raidFrames` di Compat ([SPEC-01 §8.4](SPEC-01-platform-architecture.md#84-capacità)): `available` dopo
una raccolta con almeno un riquadro letto, `missing` quando nessun nome esiste, `restricted` quando le letture sono
segrete o in errore, `unknown` prima della prima raccolta (ARC-12).

### 3.4 Impostazioni (schema 7 dell'account)

| Percorso | Tipo | Predefinito | Uso |
|---|---|---|---|
| `settings.heatmap.rows` | booleano | `true` | calore sulle righe del monitor (§3.2) |
| `settings.heatmap.raidFrames` | booleano | `false` | segni sopra i riquadri del raid di Blizzard (§3.3); spento per il rischio detto sopra |

Le due chiavi sono anche nei profili (§4.2). Dettaglio in [SPEC-02 §3.11](SPEC-02-data-model-storage.md#311-schema-7-dellaccount-e-schema-3-del-personaggio-m8);
predefiniti in un solo posto, `Config.HEATMAP_DEFAULTS` (Q29).

### 3.5 Card, diagnostica e demo

- **Card *Heatmap*** (dopo *Dungeon Focus*, prima di *Alerts*; solo con l'interruttore): *Colour the monitor rows*
  (`heatmap.rows`), *Mark the game's raid frames* (`heatmap.raidFrames`) con la nota *Draws on top of the game's own
  party and raid frames, without changing them. Turn it off if the game reports a problem with an addon.* e, sotto, lo
  stato: *Raid frames found: 25*, *The game's raid frames are not shown* (riquadri di Blizzard nascosti o di un altro
  addon), *The game's raid frames cannot be read here.* (capacità `restricted`).
- **`/atw debug`**, sezione *Heatmap*: interruttore e impostazioni, capacità `raidFrames`, riquadri trovati per nome
  (`party`, `raid`, `group`), segni mostrati, età delle posizioni, segni nascosti per un cambio del roster in
  combattimento (sì o no e quante volte), `ADDON_ACTION_BLOCKED` e `ADDON_ACTION_FORBIDDEN` visti da quando la
  sovrapposizione è accesa. Mai nomi.
- **Demo**: righe con il calore, nessun segno sui riquadri.

## 4. Profili e preset (M8.2)

Fonte §4.2 e §6.4: *configurazioni per tank, DPS e healer*, *profili per ruolo*. Completato in **M8.1**; decisioni
D25–D26 e [ADR 0020](../adr/0020-role-profiles-are-copies-of-chosen-settings-applied-onto-the-live-settings.md),
risposte proposte in [Q28](SPEC-09-risks-open-questions.md).

### 4.1 Principi

- **PR-01** MUST: un profilo è un insieme di valori per un elenco **fisso** di impostazioni (`Config.PROFILE_KEYS`,
  §4.2). I moduli continuano a leggere `account.settings` con `Config:Get`: cambiare profilo **scrive** i valori del
  profilo nelle impostazioni, e una modifica fatta in una card **si copia** nel profilo attivo
  ([ADR 0020](../adr/0020-role-profiles-are-copies-of-chosen-settings-applied-onto-the-live-settings.md)). Nessun
  modulo deve sapere che i profili esistono.
- **PR-02** MUST: tre profili, uno per ruolo del gioco: `tank`, `healer`, `damager` (le parole di
  `UnitGroupRolesAssigned`). Nessun profilo creato dal giocatore in M8 (Q28).
- **PR-03** MUST: i profili sono per **account** (uno stesso tank su due personaggi usa le stesse soglie); il profilo
  attivo e la scelta automatica sono per **personaggio**.
- **PR-04** MUST: un profilo non cambia mai in combattimento: un cambio chiesto in combattimento (dal ruolo o dal
  giocatore) aspetta `COMBAT_ENDED`, e la card lo dice (*Applies after combat*). Così le soglie di uno scontro restano
  quelle registrate nella sua sessione (SPEC-05 §2, SPEC-06 §2).
- **PR-05** MUST: il ruolo letto è un dato **rilevato** (ADR 0003): la card dice da dove viene il profilo attivo
  (*from your group role*, *chosen by you*) e, quando il ruolo non si legge, perché.
- **PR-06** MUST: nessun nome nei profili, nei loro eventi e in `/atw debug`.
- **PR-07** MUST: sui dati in sola lettura (schema più nuovo, SPEC-02 §3.4) il profilo non cambia e la card dice
  perché, come le altre card (*Not saved*).
- **PR-08** MUST: il Coach e gli avvisi non cambiano: il loro ruolo resta quello di `UnitGroupRolesAssigned` riga per
  riga (SPEC-04 §2.1); il profilo cambia solo le impostazioni.

### 4.2 Che cosa sta in un profilo e i preset

`Config.PROFILE_KEYS`, con il preset di ogni ruolo (`Config.PRESETS`, la risposta proposta di Q28). Le soglie restano
quelle del proprietario per tutti i ruoli (D12): il tank le usa sul secondo, come oggi.

| Chiave (`account.settings.`) | `tank` | `healer` | `damager` | Perché |
|---|---|---|---|---|
| `monitor.warning`, `monitor.danger` | 82, 91 | 82, 91 | 82, 91 | D12, Q7; si scrivono insieme con `Config:SetThresholds` |
| `monitor.sort` | `relative` | `relative` | `relative` | |
| `monitor.pinSelf` | `false` | `true` | `true` | chi non fa il tank cerca la propria riga |
| `alerts.enabled`, `alerts.window`, `alerts.visual` | `true` | `true` | `true` | |
| `alerts.sound` | `false` | `false` | `false` | Q12 |
| `alerts.cooldown` | 8 | 8 | 8 | |
| `alerts.others` | `tank` | `tank` | `tank` | gli avvisi sugli altri contano già solo per il tank |
| `alerts.pet` | `true` | `true` | `true` | |
| `alerts.onlyTarget` | `false` | `true` | `true` | il tank vuole sapere dei mob sciolti (l'alternativa di Q26) |
| `coach.enabled` | `true` | `true` | `true` | |
| `mobs.enabled` | `true` | `true` | `true` | |
| `heatmap.rows`, `heatmap.raidFrames` | `true`, `false` | `true`, `false` | `true`, `false` | Q29 |

- **Non** stanno nei profili (sono della persona o del computer, non del ruolo): lingua, tema, effetti, animazioni,
  font, tavolozza e segni (§5), minimappa, finestra, `monitor.rate`, `monitor.maxUnits`, `monitor.show`,
  `monitor.followTargetOfTarget`, `mobs.max`, `mobs.nameplates`, la registrazione.
- *Colonne* (fonte §4.2): il monitor non ha colonne da scegliere (si nascondono da sole con la larghezza, SPEC-03
  §2.6); il profilo ne tiene l'ordine e *pin me on top*. Un selettore di colonne non è in M8 (Q28).

### 4.3 La scelta automatica dal ruolo

Con `char.profile.auto` acceso (predefinito), il profilo segue il ruolo **assegnato al giocatore**,
`Compat.Unit.Role("player")` (`UnitGroupRolesAssigned`, **[probe P9]**):

| Risposta | Profilo |
|---|---|
| `TANK`, `HEALER`, `DAMAGER` | `tank`, `healer`, `damager` |
| `nil` con il motivo `none` (`NONE`: da soli, o un gruppo fatto a mano senza ruoli) | **invariato**; la card dice *No group role: using Damage* (il profilo attivo) |
| `nil` con il motivo `secret`, `missing`, `error` | **invariato**; la card dice *Your group role cannot be read here* |

- Si legge a `ENTERING_WORLD`, a `GROUP_CHANGED`, a `PLAYER_ROLES_ASSIGNED` (nel dump, `PartyInfo`) e a
  `COMBAT_ENDED` (per applicare un cambio in attesa); mai in un tick.
- Il profilo cambia solo quando il ruolo letto è **diverso** dall'ultimo ruolo che ha scelto un profilo
  (`char.profile.role`, salvato): così una scelta fatta a mano resta finché il gruppo non assegna un ruolo diverso,
  anche dopo un `/reload` o un nuovo accesso; un ruolo uguale non annulla la scelta a mano. `NONE` e un ruolo segreto
  non cambiano `char.profile.role`.
- Con `auto` spento il profilo cambia solo a mano.
- **Niente ruolo dalla specializzazione**: il dump ha `GetSpecializationRole` e `C_SpecializationInfo`, ma il probe non
  li prova e un personaggio può fare un ruolo diverso da quello della specializzazione; restano fuori (alternativa di
  Q28, una funzione di `Data/Profiles.lua`).
- **Prima volta** (nessun `char.profile.active`): il ruolo letto, altrimenti `damager`.
- *M8.2*: una scelta **a mano** (card, `/atw profile`) salva come `char.profile.role` il ruolo letto in quel momento
  (se si legge): così un cambio del ruolo rimasto in attesa durante uno scontro non riprende il profilo che il giocatore
  ha scelto dopo. Un ruolo `nil` con un motivo diverso da quelli della tabella (`nil`: il client non risponde con una
  stringa) vale come *non si legge*. Con `auto` riacceso (card o `/atw profile auto`) il profilo segue subito il ruolo
  letto, se si legge. La riga *da dove viene* ha tre casi: *from your group role* (il ruolo che lo ha scelto è ancora
  quello del profilo), *chosen by you*, e *the first profile* (`damager` senza ruolo, finché il giocatore non sceglie da
  quando l'addon è caricato; ciò che ha fatto l'ultimo cambio non si salva).

### 4.4 Scrittura, cambio, copia e reset (`Data/Profiles.lua`)

- **Cambio** (`Profiles.Switch(id, why)`, `why` = `role` o `manual`): fuori dal combattimento e con dati scrivibili,
  scrive in `account.settings` ogni chiave di `PROFILE_KEYS` con il valore del profilo (le soglie con
  `Config:SetThresholds`), con un indicatore *applying* che impedisce la copia all'indietro, salva
  `char.profile.active`, emette **una** volta `PROFILE_CHANGED(id, old, why)` dopo i `CONFIG_CHANGED` delle chiavi
  cambiate. Un valore del profilo che non passa la regola della sua chiave torna al preset e va in `Config.issues`.
- **Copia all'indietro**: a `CONFIG_CHANGED(path)` di una chiave di `PROFILE_KEYS`, fuori da *applying*, il valore si
  scrive in `account.profiles.<attivo>.<chiave>`. Così ciò che il giocatore cambia nelle card resta nel profilo attivo.
- **Copia** (*Copy from…*): i valori di un altro profilo diventano quelli dell'attivo (e si applicano); chiede conferma.
- **Reset** (*Reset to preset*): il profilo attivo torna al suo preset (e si applica); chiede conferma. Il pulsante
  *Reset settings* della card *Reset* (SPEC-03 §5) riporta ai predefiniti le impostazioni fuori dai profili e il profilo
  attivo al suo preset; gli altri due profili non cambiano.
- **Interruttore `profiles` spento**: `Data/Profiles.lua` non registra eventi né copia nulla; le impostazioni si usano
  come oggi. Gli schemi 7 e 3 e le loro migrazioni ci sono comunque (come lo schema 6 con `multitarget` spento).
- *M8.2*: `why` di `PROFILE_CHANGED` vale anche `copy` e `reset` (copia e reset si applicano come un cambio; in
  combattimento i valori entrano subito nel profilo e la scrittura sulle impostazioni aspetta `COMBAT_ENDED`). Durante
  la demo aspetta solo un cambio **del ruolo** (fino a `DEMO_CHANGED(false)`); un cambio a mano vale subito, come ogni
  altra impostazione cambiata durante la demo. La copia all'indietro scrive le due soglie insieme. I valori di un profilo
  si scrivono con `Config:SetProfileValues(id, values)` (regole delle impostazioni, coppia delle soglie, nessun
  `CONFIG_CHANGED`: nessun modulo legge i profili); *Reset settings* passa a `Config:ResetSettings(keep)` le chiavi dei
  profili da lasciare, poi riporta il profilo attivo al preset.

### 4.5 Dati salvati

Dettaglio in [SPEC-02 §3.11](SPEC-02-data-model-storage.md#311-schema-7-dellaccount-e-schema-3-del-personaggio-m8):
`account.profiles.tank`, `.healer`, `.damager` (le chiavi di §4.2, con la stessa forma di `settings`);
`char.profile = { active, auto, role }`. La migrazione dell'account **copia le impostazioni di oggi in tutti e tre i
profili**, così chi aggiorna non vede cambiare nulla; un'installazione nuova parte dai preset.

### 4.6 Card, comando e diagnostica

- **Card *Profile*** (la prima dopo *Appearance* e *Language*, solo con l'interruttore): un selettore a pillole *Tank ·
  Healer · Damage* (icone di ruolo e parole), *Follow my group role* (`char.profile.auto`), la riga del ruolo (*Group
  role: Tank (detected)*, *No group role*, *Your group role cannot be read here*), *Copy from…* (un menu con gli altri
  due), *Reset to preset*, e la nota *Changes in the cards below are kept in this profile.* In combattimento: *Applies
  after combat.*
- **`/atw profile [tank|healer|dps|auto]`**: senza argomento risponde con il profilo attivo e da dove viene; con un
  ruolo lo sceglie a mano; `auto` riaccende la scelta dal ruolo. Con l'interruttore spento *This arrives in v0.8.0.*
- **`/atw debug`**, sezione *Profiles*: interruttore, profilo attivo, `auto`, ultimo ruolo letto e motivo, cambio in
  attesa sì o no, cambi per ruolo e a mano da quando l'addon è caricato, valori riportati al preset. Mai nomi.
- **Demo**: il profilo non cambia durante la demo (dal ruolo; vedi §4.4).
- *M8.2*: la card mostra il profilo attivo con le icone di ruolo `role-tank`, `role-healer`, `role-dps` e le parole
  `ROLE_*`; *Copy from…* apre un menu con gli altri due profili e copia al secondo clic entro 8 s, *Reset to preset*
  chiede un secondo clic; sui dati in sola lettura i controlli sono spenti e la card dice *Profiles do not change while
  your saved data is read-only.*; un cambio del ruolo in attesa per la demo dice *Applies when the demo ends.* Con
  l'interruttore acceso la card *Reset* dice che il profilo attivo torna al preset. La sezione *Profiles* di `/atw debug`
  c'è solo con l'interruttore acceso. `/atw profile` accetta anche `heal`, `damage` e `damager`.

## 5. Accessibilità (M8.4)

Fonte §6.1: *supporto a modalità solo testo/solo icone, ove utile; contrasto sufficiente e opzioni per daltonismo*.
Completato in **M8.1**; decisione D28, valori in [ui-style §4.4](ui-style.md#44-tavolozze-per-il-daltonismo-e-segni-m8),
risposte proposte in [Q30](SPEC-09-risks-open-questions.md).

### 5.1 Principi

- **AC-01** MUST: in ogni tavolozza e in ogni modalità uno stato si mostra **sempre con icona e parola** insieme
  (ST-02); il distintivo di stato non cambia con le modalità di §5.3.
- **AC-02** MUST: una tavolozza cambia **solo** le quattro tinte di stato (`state-safe`, `state-warning`,
  `state-danger`, `state-unknown`); temi, `on-state`, colori delle serie della timeline e colori di classe non
  cambiano. I token di stato restano fuori dai temi (ST-01).
- **AC-03** MUST: ogni tavolozza rispetta ST-02 e ST-03 con gli stessi minimi (`on-state` sul riempimento ≥ 4,5:1, il
  riempimento ≥ 3:1 su ogni superficie di ogni tema) e la regola del calore di §3.2: `Tests/test_theme.lua` ricalcola
  tutto per ogni tavolozza.
- **AC-04** SHOULD: nella visione simulata a cui è destinata (Machado, Oliveira e Fernandes 2009, gravità piena) le tinte
  di SAFE, WARNING e DANGER di una tavolozza distano almeno **ΔE 15** (CIE76, in CIELAB) l'una dall'altra (Q30); il
  test misura e scrive le distanze di ogni tavolozza in ogni simulazione, e il valore raggiunto finisce in ui-style
  §4.4. UNKNOWN si distingue per l'icona vuota e il tratteggio, non per il colore.
- **AC-05** MUST: nessun colore libero scelto dal giocatore: un selettore di colori non garantirebbe AC-03 (Q30).
- **AC-06** MUST: nessun lampeggio né movimento necessario per capire uno stato (già ui-style §3.2); con le animazioni
  spente nulla si muove.

### 5.2 Tavolozze (`settings.palette`)

| Valore | Nome nella card (`enUS`) | Per | Tinte proposte (M8.4 le fissa con il test) |
|---|---|---|---|
| `standard` (predefinito) | *Standard* | tutti | quelle di oggi (ui-style §4.2) |
| `redgreen` | *Red-green friendly* | deuteranopia e protanopia | SAFE blu, WARNING giallo-ambra, DANGER arancio-vermiglio, UNKNOWN grigio neutro |
| `blueyellow` | *Blue-yellow friendly* | tritanopia | SAFE verde-acqua, WARNING rosa, DANGER rosso, UNKNOWN grigio neutro |

- Il cambio vale subito (`Theme` ridipinge ed emette `THEME_CHANGED`), senza `/reload`.
- **Limite detto com'è**: per reggere insieme i temi scuri e quello chiaro un riempimento di stato deve stare in una
  fascia stretta di luminanza (circa 0,20–0,27, ui-style §4.3), quindi per chi vede un solo asse di colore le quattro
  tinte non possono distinguersi molto; per questo la garanzia vera è AC-01 (forma dell'icona e parola), e la tavolozza
  allarga la distanza fra SAFE e DANGER, la coppia che conta di più.

### 5.3 Segni: icone e parole (`settings.marks`)

Riguarda i **segni secondari** della disposizione compatta, non il distintivo di stato (AC-01):

| Segno | `both` (predefinito) | `text` (solo testo) | `icons` (solo icone) |
|---|---|---|---|
| chi tiene il mob, ruolo (`tank`, `role-*`) | icona | parola breve (*Tank*, *Heal*, *DPS*) | icona |
| trend e previsione (`trend-*`, `predict`) | icona e `~4 s` | `+`, `−`, `=` e `~4 s` | icona e `~4 s` |
| dato vecchio (`stale`) | icona | *old* | icona |
| barra del pull (`pull`) | icona e *Pull · 5* | *Pull · 5* | icona e `5` |
| mob fissato (`pin`), Coach (`coach`), silenzio (`mute`) | icona | parola breve | icona |
| piede (qualità dei dati) | parole | parole | icona `stale` o niente, e il testo nel tooltip |

- Le parole brevi sono chiavi di lingua (`MARK_*`) nelle due lingue; `test_ui_texts.lua` controlla che stiano nella
  loro cella alla larghezza minima (220 pt) in inglese e in italiano; dove non stanno, la cella si nasconde come le
  colonne della finestra stretta (SPEC-03 §2.6) e il tooltip dice tutto.
- `icons` non toglie mai un'informazione: ciò che non è più scritto resta nel tooltip.

### 5.4 Impostazioni e card

`settings.palette` (enum `Config.PALETTES`, predefinito `standard`) e `settings.marks` (enum `Config.MARKS`,
predefinito `both`), per **account** come l'aspetto (ui-style §2), nello schema 7 (SPEC-02 §3.11); non stanno nei
profili. Nella card *Appearance*, sotto il tema: *Colours* (le tre tavolozze, con un'anteprima dei quattro distintivi)
e *Marks* (*Icons and words*, *Words only*, *Icons only*). L'interruttore `accessibility` (§6) li nasconde finché è
spento, e allora valgono `standard` e `both`.

## 6. Moduli, eventi, interruttori e test per step (M8.2–M8.4)

| File | Responsabilità | Bus | Step |
|---|---|---|---|
| `Core/Config.lua` (cambio) | schema 7 dell'account e 3 del personaggio, `Config.PROFILE_KEYS`, `Config.PRESETS`, `Config.HEATMAP_DEFAULTS`, `Config.PALETTES`, `Config.MARKS`, le regole dei profili generate da quelle delle impostazioni, le migrazioni `account[7]` e `char[3]` | — | M8.2 (tutto lo schema, anche le chiavi di M8.3 e M8.4) |
| `Data/Profiles.lua` | profilo attivo, scelta dal ruolo, cambio fuori dal combattimento, copia all'indietro, copia e reset (§4) | emette `PROFILE_CHANGED(id, old, why)` e `PROFILE_ROLE_READ(role, reason)`; ascolta `CONFIG_LOADED`, `CONFIG_CHANGED`, `ENTERING_WORLD`, `GROUP_CHANGED`, `COMBAT_ENDED`, `DEMO_CHANGED` (se c'è un combattimento lo chiede a `Core/Init.lua`, quindi non ascolta `COMBAT_STARTED`); dal gioco `PLAYER_ROLES_ASSIGNED` | M8.2 |
| `UI/Settings.lua`, `Core/Commands.lua` (cambi) | card *Profile*, `/atw profile`; la sezione *Profiles* la aggiunge `Data/Profiles.lua` con `AddDebugSection` (nessun cambio di `Core/Diagnostics.lua`) | ascolta `PROFILE_CHANGED`, `PROFILE_ROLE_READ` | M8.2 |
| `Core/Compat.lua` (cambio) | `Compat.RaidFrames.Collect`, la lettura di `InCombatLockdown`, la voce `frames.Raid` della tabella delle API, la capacità `raidFrames` | emette `CAPABILITY_CHANGED` | M8.3 |
| `UI/ThreatList.lua` (cambio), `UI/RaidOverlay.lua` | calore delle righe (§3.2), sovrapposizione staccata (§3.3) | ascolta `THREAT_UPDATED`, `STATE_CHANGED`, `COMBAT_*`, `GROUP_CHANGED`, `DISPLAY_CHANGED`, `CONFIG_CHANGED`, `THEME_CHANGED`, `DEMO_CHANGED`; dal gioco `GROUP_ROSTER_UPDATE`, `COMPACT_UNIT_FRAME_PROFILES_LOADED` | M8.3 |
| `UI/Settings.lua`, `Core/Diagnostics.lua` (cambi) | card *Heatmap*, sezione *Heatmap*; i blocchi `ADDON_ACTION_BLOCKED` e `ADDON_ACTION_FORBIDDEN` contati | — | M8.3 |
| `UI/Theme.lua`, `UI/Widgets/Threat.lua`, `UI/ThreatList.lua`, `UI/FocusList.lua`, `UI/CoachStrip.lua`, `UI/Settings.lua` (cambi) | `Theme.STATE_PALETTES` e `Theme.SetPalette`, `Theme.Mark(id)` per i segni di §5.3, i controlli della card *Appearance* | emette `THEME_CHANGED` | M8.4 |

- Nel TOC `Data/Profiles.lua` dopo `Data/ThreatState.lua` e prima di `Data/Alerts.lua`; `UI/RaidOverlay.lua` dopo
  `UI/ThreatList.lua`.
- **Interruttori** ([ADR 0014](../adr/0014-one-version-per-milestone-and-feature-switches.md)), tutti spenti fino a
  M8.R e accesi dalla `v0.8.0` (Q28–Q30): `profiles` (Profiles, card, comando, sezione), `heatmap` (calore delle righe,
  sovrapposizione, card, sezione), **`accessibility`** (nuovo, M8.4: tavolozze e segni; spento valgono `standard` e
  `both`; un interruttore anche qui perché una correzione `v0.7.x` fatta da `main` non porti tinte di stato non ancora
  rilasciate). Spento vuol dire: nulla di visibile, nessun evento del gioco registrato, nessun dato scritto oltre agli
  schemi. I test che li vogliono spenti li mettono a `false` in `M.features`; `SHIPPED_ON` di `test_features.lua` li
  aggiunge in M8.R.

| Step | Test e casi |
|---|---|
| **M8.2** | `test_profiles.lua`: preset di un'installazione nuova; migrazione dallo schema 6 (le impostazioni di oggi copiate nei tre profili, nulla che cambi a schermo) e dallo schema 6 con valori fuori regola (preset), dallo schema 2 del personaggio; idempotenza; la scelta di §4.3 per ogni risposta del ruolo (`TANK`, `HEALER`, `DAMAGER`, `NONE`, segreto, assente, errore) con `Fight` e `role(unit, role)`; la scelta a mano che resta fino a un ruolo diverso, anche dopo `/reload` (harness); `auto` spento; un cambio in combattimento che aspetta `COMBAT_ENDED`; la copia all'indietro e nessuna copia durante *applying*; soglie scritte in coppia; copia e reset; *Reset settings*; dati in sola lettura; `PROFILE_CHANGED` una volta per cambio; demo; interruttore spento (nessun evento registrato, impostazioni come oggi). In `test_config.lua` gli schemi 7 e 3 (DAT-20); in `test_settings.lua` la card; in `test_commands.lua` `/atw profile`; in `test_diagnostics.lua` la sezione; in `test_ui_texts.lua` le chiavi nuove |
| **M8.3** | `test_heatmap.lua`: il passo di §3.2 per ogni stato e modalità, il tank, chi tiene il mob senza essere un tank, l'isteresi dei confini, al più un cambio al secondo tranne DANGER, nessun calore su UNKNOWN; la sovrapposizione con riquadri finti nel client finto (`Tests/mock/` aggiunge `CompactPartyFrameMember1–5`, `CompactRaidFrame1–40` con `unit`, `GetRect`, `GetEffectiveScale`, `IsVisible` e un registro di **ogni** scrittura o chiamata che non sia una lettura permessa: il test fallisce se l'addon ne fa una), posizioni copiate solo fuori dal combattimento, segni solo per WARNING, DANGER e l'aggro di un non tank, segni nascosti per un cambio del roster in combattimento, nessun riquadro, riquadri segreti o in errore (capacità `restricted`), mouse mai preso, demo, impostazioni e interruttore spenti; in `test_theme.lua` il contrasto del calore (§3.2) in ogni tema; in `test_compat.lua` `RaidFrames.Collect`; in `test_api_boundary.lua` il modulo nuovo; nel test del costo (`Tests/long/test_monitor_budget.lua`) il tick del monitor con il calore e la sovrapposizione accesi entro i budget di SPEC-08 §8 |
| **M8.4** | in `test_theme.lua` le tre tavolozze: ST-01–ST-03 e il calore per ognuna, le distanze di AC-04 nelle tre simulazioni (scritte nel risultato del test), `SetPalette` senza `/reload`; `test_marks.lua`: ogni segno di §5.3 nelle tre modalità, il distintivo uguale in tutte, nessuna informazione persa (il tooltip), le larghezze alla dimensione minima nelle due lingue; in `test_settings.lua` i controlli della card *Appearance*; interruttore spento. Anteprime `settings-appearance` e `monitor` con le tavolozze (ADR 0013) |

## 7. Cosa aspetta il probe e il gioco

- **[probe P9]** se `UnitGroupRolesAssigned("player")` risponde in un gruppo dal cercatore, in un gruppo fatto a mano e
  in un raid, o se è `NONE` o segreto (la scelta automatica di §4.3 funziona solo nel primo caso); **[probe P11]** se
  leggere i riquadri del raid in un'istanza o in combattimento dà blocchi o errori.
- **[da provare in gioco]** (checklist M8, SPEC-08 §10): il profilo che cambia entrando in un gruppo con un ruolo e che
  resta con `NONE`; un cambio chiesto in combattimento che arriva dopo; il calore delle righe in combattimento
  (leggibile? troppo?) nei tre temi; i segni sui riquadri del raid: posizione giusta alle scale comuni, dopo un cambio
  del roster, con il registro del taint acceso dal proprietario (`/console taintLog 1`) e nessun `ADDON_ACTION_BLOCKED`;
  le tavolozze guardate da chi è daltonico (o con un simulatore di schermo); le modalità dei segni alla dimensione
  minima e in italiano.
