# SPEC-07: Multi-target, heatmap e profili

> Fonte: [specifiche originali](source-specification.md) §5.6, §5.7, §4.2. §0–§2 completati in **M7.1** (2026-11-27)
> **prima** dell'esito del probe M0, per decisione del proprietario ([SPEC-00 §7](SPEC-00-vision-scope.md#7-registro-delle-decisioni)
> D7, come M2–M6): il go / no-go di M7 è **condizionato** (§0) e il tracker legge ciò che il client permette, lettura
> per lettura; ciò che il probe può cambiare è marcato **[probe Pn]**, ciò che solo il gioco può dire **[da provare in
> gioco]**. §3–§4 da completare in **M8.1**. Moduli, eventi e test per step in §2.7–§2.8.
> §1 e §2.4 realizzati in **M7.2** (`Data/MobRisk.lua`, `Data/MobTracker.lua`, la regola 0 di `Data/TargetTracker.lua`,
> lo schema 6) dietro l'interruttore `multitarget`, spento; le note *M7.2* dicono come il codice ha letto i punti
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
- l'interruttore `multitarget` resta spento fino a M7.R e la risposta proposta di [Q25](SPEC-09-risks-open-questions.md)
  lo accende nella `v0.7.0` come M2–M6, con la pagina del manuale e le note della versione che dicono che nulla è
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
- **Budget**: al più `READ_BUDGET` (**48**) letture per tick (ogni `Threat.Read` e ogni `ReadLead` contano una
  lettura). Una lettura di un mob legge al più `UNITS_PER_MOB` (**10**) unità del roster dello Scanner (le sue
  `ThreatScanner.units`, nello stesso ordine, entro `maxUnits`): `player`, `pet`, i tank designati e chi lo teneva
  all'ultima lettura sempre; gli altri posti a turno, con un cursore per mob. In un party (fino a 6 unità con il
  famiglio) ogni lettura legge tutti.
- **Ordine dei mob in un tick**: prima quelli segnati da un evento (`UNIT_THREAT_LIST_UPDATE` con uno dei loro token),
  poi quelli in DANGER, poi a turno dopo l'ultimo letto; ci si ferma quando la lettura del mob seguente non entra nel
  budget, ma almeno un mob per tick. Un evento non fa mai una lettura fuori dal tick: il costo resta nel budget
  (come MON-07). Con eventi puntuali M0.7 può abbassare `RATE` **[probe P6]**.
- **Costo atteso**: in un party 8 mob × 6 unità ≈ 48 letture per tick, ≈ 96 al secondo (il monitor a 5 Hz con 6 unità
  ne fa 30); in un raid 4 mob per tick con 10 unità ciascuno, ogni mob riletto circa ogni secondo con 8 posti. M7.4 lo
  misura nel client finto (§2.8); il budget vero lo dà P10.
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
| `ALERT_MOB_SELF` *You are close to pulling another mob.* | `selfState` del giocatore entra in DANGER su un altro mob | il giocatore | 2 | il giocatore che non fa il tank (mai al tank, D12) |

- Valgono le regole di SPEC-04: solo le **entrate** (ALR-01, da UNKNOWN solo sopra l'ultimo stato noto), il cooldown
  `alerts.cooldown` per tipo `mob` e **per mob** (non per unità), `OTHER_GAP` fra due avvisi sulle altre unità, il
  silenzio, le esclusioni per sessione (un `%s` escluso non avvisa), il suono solo dalla gravità 2. Mai in chat.
- Il Coach resta sul mob monitorato. Gli avvisi `mob` **non** si registrano: il mob non è nella sessione (Recorder li
  ignora, nessun codice nuovo in SPEC-02 §4.3).
- Con l'interruttore `multitarget` spento `alerts.onlyTarget` non conta (vale acceso).

### 2.6 Impostazioni, comandi, demo e diagnostica

- **Card *Dungeon Focus*** (M7.3; solo con l'interruttore, dopo *Monitor* e prima di *Alerts*): *Track other mobs*
  (`settings.mobs.enabled`), *Mobs followed* (cursore 2–12, salvato al rilascio), *Use enemy nameplates* con la nota
  *Shows mobs only while the game's enemy nameplates are on.* Nella card *Alerts* (M7.4) l'interruttore *Alerts about
  other mobs* (`alerts.onlyTarget` al contrario). Con dati in sola lettura come le altre card (*Not saved*).
- **`/atw focus`** (M7.3): apre la finestra sulla scheda Monitor con la lista aperta; di nuovo la chiude. Con
  l'interruttore spento *This arrives in v0.7.0.*; con l'impostazione spenta *Other mobs are off in Settings.*
- **Demo** (M7.3): `Data/Demo.lua` aggiunge un pull inventato di cinque mob (uno sciolto su un DPS, uno vicino a
  strappare, uno senza tank, uno segreto, uno senza token), con la portata `all`; `Core/Demo.lua` mette un tracker
  inventato in `ns.MobTracker` come fa con lo Scanner. Nulla letto, nulla salvato.
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
| `Data/Alerts.lua`, `Data/Recorder.lua` (cambi) | il tipo `mob` e `alerts.onlyTarget` (§2.5); il Recorder ignora `mob`; l'interruttore nella card *Alerts* | ascolta `MOB_STATE_CHANGED` | M7.4 |

- Nel TOC `Data/MobRisk.lua` e `Data/MobTracker.lua` dopo `Data/ThreatState.lua` (prima di `Data/Alerts.lua`),
  `UI/FocusList.lua` prima di `UI/ThreatList.lua` (come `UI/CoachStrip.lua`).
- **Interruttore** `multitarget` ([ADR 0014](../adr/0014-one-version-per-milestone-and-feature-switches.md)): spento
  fino a M7.R. Spento vuol dire: nessun evento del gioco registrato da `MobTracker`, nessun tick, `Pin` non fa nulla,
  nessuna barra, lista, card o interruttore *Alerts about other mobs*, `alerts.onlyTarget` vale acceso, `/atw focus`
  risponde *This arrives in v0.7.0.*, nessuna sezione *Mobs* in `/atw debug`. Lo schema 6 e la sua migrazione ci sono
  comunque (come lo schema 3 con gli avvisi spenti). I test che lo vogliono acceso lo mettono a `true` in `M.features`.

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

## 3. Heatmap (M8)

Colorazione delle righe del monitor; integrazione con i riquadri del raid di Blizzard **solo** se non causa taint
**[verificare]**; nessuna dipendenza da addon esterni; colori configurabili e alternative non basate sul colore.

## 4. Profili e preset (M8)

Profili per tank, DPS e healer (soglie, canali, colonne); scelta automatica dal ruolo assegnato, se rilevabile;
copia e reset di un profilo.
