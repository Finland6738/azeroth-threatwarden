# SPEC-03: Threat Monitor e interfaccia

> Fonte: [specifiche originali](source-specification.md) §5.1, §6. Finestra e comandi (§4–§5) completati in **M1.1**;
> monitor (§1–§3, §6) completato in **M2.1** (2026-11-25) **prima** dell'esito del probe M0, per decisione del
> proprietario ([SPEC-00 §7](SPEC-00-vision-scope.md#7-registro-delle-decisioni) D7): vale per i tre esiti possibili
> (§1.1) e ciò che il probe può cambiare è marcato **[probe Pn]**; M0.7 lo rivede.

## 1. Cosa mostra il monitor

Il monitor mostra, per il **mob monitorato** (§1.2), chi è nella sua lista della threat fra le **unità osservate**
(§1.3): nome, percentuale, stato, trend, e chi lo tiene. Moduli: `Data/TargetTracker.lua`, `Data/ThreatScanner.lua`,
`Data/ThreatModel.lua`, `Data/ThreatCalc.lua`, `Data/ThreatState.lua` e la vista `UI/ThreatList.lua`
([SPEC-01 §3.2](SPEC-01-platform-architecture.md#32-i-moduli-delle-milestone-successive-previsti)); piano per step in
§6.

### 1.1 Tre esiti del probe, tre modalità

Il probe M0 (P2, P3) non ha ancora detto se un addon legge i valori della threat in gruppo e in istanza. Il monitor è
progettato per **tutti e tre gli esiti**, che `Compat.Threat.Read` dà già **per lettura**, cioè per coppia (unità, mob)
([SPEC-01 §8.3](SPEC-01-platform-architecture.md#83-lettura-normalizzata-della-threat-m14-usata-da-m2)):

| Modalità | Esito del probe | Cosa si legge (attraverso Compat) | Cosa mostra il monitor | Pastiglia (§4.3) |
|---|---|---|---|---|
| `values` | (a) valori leggibili | `UnitDetailedThreatSituation`: tank sì/no, stato 0–3, percentuale scalata e raw, threat raw; per chi tiene il mob anche `UnitThreatPercentageOfLead` e `UnitThreatLeadSituation` | tutto §1.6: percentuali e barre, margine, stati con le soglie (§2.2), trend e tempo al superamento (§2.5) | *Live* |
| `state` | (b) *state only*: valori segreti, stato leggibile | `UnitThreatSituation` (0–3) e, per chi tiene il mob, `UnitThreatLeadSituation` | chi tiene il mob e lo stato di ognuno dallo stato del gioco (§2.3); nessuna percentuale, margine numerico, trend né previsione; pastiglia e piede lo dicono (MON-02) | *State only* |
| `none` | (c) nulla di leggibile: stato segreto, API assente o in errore | nulla | UNKNOWN con il motivo (MON-01): nessun numero, nessuna barra piena | *Unavailable* |

- **MON-01** MUST: con dati segreti o assenti si vede UNKNOWN con il motivo nel tooltip, mai un numero.
- **MON-02** MUST: se l'API dà solo lo stato (`UnitThreatSituation`) e non i valori, il monitor mostra lo stato senza
  percentuale (modalità *state only*) e lo dice.
- **MON-03** SHOULD: indicatore di qualità dei dati nel piede della finestra (§1.5): ultimo aggiornamento, percentuale
  di letture valide negli ultimi 10 s.
- **MON-04** MUST: la modalità è **per riga**: nello stesso istante una riga può essere `values` e un'altra `state`
  (per esempio valori leggibili solo per `player`, **[probe P3, P5]**), e ognuna si disegna secondo la propria. La
  **modalità del monitor** (pastiglia, evento `THREAT_MODE_CHANGED(mode, reason)`) è la migliore fra le righe
  dell'ultima scansione completa (`values` > `state` > `none`); `reason` è quello della riga del giocatore, o della
  prima riga che manca se il giocatore non è nella lista.
- **MON-05** MUST: `reason = "nil"` (l'unità non è nella lista della threat del mob) **non** è UNKNOWN: la riga
  semplicemente non c'è. Danno UNKNOWN solo `secret`, `missing`, `error`, `no-unit` e `stale`.
- **MON-06** MUST: nessuna modalità è scritta nel codice per contesto (istanza, raid, encounter): la decide ogni
  lettura (previsioni `C_Secrets.Should…` prima della chiamata, poi `issecretvalue`, ARC-11). L'esito per contesto lo
  scrive M0.7 nella matrice delle funzioni ([SPEC-08 §1](SPEC-08-quality-probe-release.md#1-probe-m0)) e il monitor non
  cambia.
- Le capacità `threatValues`, `threatState` e `threatLead` ([SPEC-01 §8.4](SPEC-01-platform-architecture.md#84-capacità))
  le precisa lo Scanner con `Compat:SetCapability` quando cambia la modalità del monitor: `available` se una lettura
  l'ha dimostrata, `restricted` se la risposta era segreta, `missing` o `error` come la lettura. `groupThreat` diventa
  `available` alla prima lettura `values` o `state` di un membro del gruppo diverso da `player`; `mobIdentity` e
  `roles` le precisa il TargetTracker (§1.2) e lo Scanner (§1.3) quando leggono un GUID o un ruolo.

### 1.2 Il mob monitorato (`Data/TargetTracker.lua`)

Una sola regola, rivalutata a ogni `PLAYER_TARGET_CHANGED`, a ogni `UNIT_TARGET` con payload `target`, a
`COMBAT_STARTED` e `COMBAT_ENDED` (un mob che muore chiude spesso il combattimento) e quando una scansione trova il mob
cambiato (`TargetTracker.Check()`):

1. il **target** (`mobToken = "target"`) se esiste (`UnitExists`), è ostile (`UnitCanAttack("player", "target")`) e
   non è morto (`UnitIsDead`);
2. altrimenti, se l'opzione *Follow target of target* è accesa (predefinito, §5) e il target è un amico, il **target
   del target** (`mobToken = "targettarget"`) alle stesse condizioni: il guaritore che seleziona il tank vede il mob
   del tank;
3. altrimenti nessun mob: intestazione *No target*, elenco vuoto, nessuna lettura della threat.

**Identità** (`mobKey`, mai un nome): `"mob:" .. GUID` se `UnitGUID(mobToken)` è leggibile, altrimenti `"tgt:" .. n`
con `n` un contatore che cresce a ogni cambio visto **[probe P9]**. Il GUID leggibile e stabile rende `mobIdentity`
`available`; un GUID segreto la rende `restricted`.

| Cosa succede | Come si vede | Effetto |
|---|---|---|
| Nuovo mob (regola sopra) | `PLAYER_TARGET_CHANGED`, `UNIT_TARGET`; oppure, a una scansione, un GUID leggibile diverso dal `mobKey` (stessi token, creatura diversa, nessun evento) | `TARGET_CHANGED(mobKey)`; righe, campioni del trend e stati azzerati |
| Il mob muore | `UnitIsDead(mobToken)` vero a una scansione o a un evento | `TARGET_CHANGED(nil)`; intestazione *Target died*, elenco vuoto finché il target non cambia |
| Il mob scompare | `UnitExists(mobToken)` falso | `TARGET_CHANGED(nil)`; intestazione *Target lost* |
| Il target diventa amico o non attaccabile | regola sopra | target del target (passo 2) o *No target* |

Il perché manca un mob lo dice `TargetTracker.status`: `none` (nessun target ostile), `died`, `lost` (il token non
nomina più nessuno: il mob è sparito, o il giocatore ha tolto il target, che il client non distingue); `died` e `lost`
restano finché il target non cambia (M2.2). Con un GUID non leggibile un nuovo `tgt:n` nasce solo da un evento che
dice che l'unità del token è cambiata; senza evento si tiene la chiave.

Il TargetTracker legge solo esistenza, ostilità, morte e GUID, su eventi: non legge la threat e funziona anche fuori
dal combattimento (l'intestazione mostra il mob anche prima del pull). Un mob alla volta: i mob non selezionati e la
storia di un mob lasciato sono M7 ([SPEC-07](SPEC-07-multi-target-heatmap-profiles.md), **[probe P5]**).

### 1.3 Unità osservate e limite (`Data/ThreatScanner.lua`)

Le unità osservate, in quest'ordine (l'**ordine del roster**, usato anche per i pareggi di §3):

1. `player`;
2. `pet`, se esiste (da solo il famiglio spesso tiene il mob);
3. in gruppo `party1`–`party4`; in raid `raid1`–`raidN`, saltando l'indice del giocatore (`UnitInRaid("player")`,
   nel dump, una voce nuova `group.RaidIndex` della tabella di Compat).

I famigli degli altri membri non si osservano in M2; se il mob è tenuto da un'unità non osservata, l'intestazione dice
il nome del suo target (`UnitName(mobToken .. "target")`) con *(not in the list)*.

**Limite** `maxUnits` (impostazione, predefinito **40**, da 5 a 40, provvisorio come la frequenza, [Q14](SPEC-09-risks-open-questions.md)):
quante unità si leggono per scansione. Se il roster è più grande: `player`, `pet`, i tank designati (§2.1) e chi tiene
il mob si leggono sempre; i posti rimasti vanno **a turno** (round-robin) agli altri, nell'ordine del roster. Con il
predefinito un raid da 40 si legge tutto a ogni scansione e il turno non serve. Una riga letta a turno ha la sua
freschezza (§1.5): ogni record porta `interval`, l'intervallo atteso fra due letture (1 / `rate` per chi si legge
sempre, moltiplicato per i turni per gli altri). Chi tiene il mob è quello dell'ultima scansione: se non era fra le
righe lette, si scopre alla sua lettura a turno e da lì si legge sempre (M2.2).

Ruolo (`UnitGroupRolesAssigned`) e classe (`UnitClass`) si leggono a `GROUP_ROSTER_UPDATE` e a `COMBAT_STARTED`, non a
ogni scansione; un ruolo segreto o `NONE` vale "nessun ruolo" **[probe P9]**.

### 1.4 Quando si legge: eventi e tick

Lo Scanner è **attivo** solo se tutte queste condizioni valgono; altrimenti non legge, non ha tick e non tiene
registrati gli eventi della threat (ARC-05, M2.2 *Done when*):

- l'interruttore `monitor` è acceso e il client è riconosciuto (ARC-01);
- il giocatore è in combattimento (`COMBAT_STARTED` … `COMBAT_ENDED`);
- c'è un mob monitorato (§1.2);
- almeno un **consumatore** lo vuole: `ThreatScanner.Want(name, on)`. In M2 l'unico è la finestra, quando è aperta
  sulla scheda Monitor (`WINDOW_SHOWN`, `TAB_CHANGED`; prima del primo `TAB_CHANGED` vale `char.ui.lastTab`); gli
  avvisi (M3) e la registrazione (M4) si aggiungono senza cambiare lo Scanner.

| Fonte | Cosa fa |
|---|---|
| **Tick** | `Scheduler.Start("threat", rate, scan, { combat = true })`: una scansione completa (tutte le unità entro il limite) `rate` volte al secondo. `rate` = `settings.monitor.rate`, predefinito **5 Hz provvisorio** (Q14, ARC-08), da 2 a 10. Si ferma da solo a `COMBAT_ENDED` |
| `UNIT_THREAT_LIST_UPDATE(unit)` | se `unit` è il `mobToken` (o `UnitIsUnit(unit, mobToken)` è leggibile e vero, per `bossN` e `nameplateN`): chiede una scansione completa |
| `UNIT_THREAT_SITUATION_UPDATE(unit)` | se `unit` è un token osservato: chiede la lettura di quell'unità |
| `GROUP_ROSTER_UPDATE`, `UNIT_PET` | ricostruisce l'elenco delle unità (§1.3) |

- **MON-07** MUST: le richieste degli eventi si **raccolgono**: al massimo una scansione completa ogni 100 ms (quella in
  attesa parte alla fine dell'intervallo, con una sola funzione di richiamo creata una volta e al più un timer del
  client in attesa); la lettura di una sola unità si fonde
  con una scansione in attesa. Il tick non aspetta l'intervallo: una scansione in attesa che arriva meno di 100 ms dopo
  una del tick non si fa. Un evento duplicato costa al più una lettura in più, mai un dato sbagliato: ogni
  lettura legge lo stato **attuale** e porta il proprio `observedAt` (`GetTime`), e un campione più vecchio non
  sostituisce mai uno più nuovo. Un evento fuori ordine o per un'unità non osservata si ignora; un payload segreto si
  ignora (ARC-11).
- **MON-08** MUST: una scansione non alloca (ARC-06): un record del pool per unità osservata, riusato; l'elenco delle
  unità si ricostruisce solo a `GROUP_ROSTER_UPDATE` e `UNIT_PET`.
- Gli eventi rendono `threatEvents` `available` quando ne arriva uno per il mob monitorato in combattimento; la loro
  assenza non la rende `missing` (il tick basta da solo).
- **[probe P6]**: se gli eventi arrivano puntuali (ritardo ≤ un tick), M0.7 può abbassare il tick a rete di sicurezza
  (una costante, `ThreatScanner.SAFETY_HZ`); se arrivano radi o mai, resta il tick configurato. **[probe P10]** fissa il
  predefinito di `rate` e di `maxUnits`.
- **[probe P12]**: dopo un `/reload` in combattimento `Core/Init.lua` considerava il giocatore fuori combattimento
  finché non arrivava un `PLAYER_REGEN_*`; da M2.2 controlla `UnitAffectingCombat("player")` a
  `PLAYER_ENTERING_WORLD` ed emette `COMBAT_STARTED`, così il monitor riparte anche se il client non manda l'evento.
- A `COMBAT_ENDED` le righe restano com'erano, tutte `stale`, con l'intestazione *Combat ended*; si svuotano al
  `COMBAT_STARTED` successivo o al cambio di mob.

### 1.5 Freschezza e qualità

- Ogni riga ha un **intervallo atteso** `I` = 1 / `rate`, moltiplicato per il numero di turni se è letta a turno
  (§1.3). È **`stale`** quando `now − observedAt > max(2 · I, 0,5 s)` (DAT-12), e sempre dopo `COMBAT_ENDED`.
- Una riga `stale` diventa UNKNOWN con motivo `stale` (rispettando la permanenza di §2.4): barra tratteggiata, `?`,
  icona `stale` al posto del trend, tooltip *Stale: last read 1.4 s ago*. I suoi campioni non contano per il trend.
- **Indicatore di qualità** (MON-03), nel piede da 16 pt della compatta, in `RowMono` `text-3`:
  *Updated 0.2 s ago · 96 % valid (10 s)* (in modalità `state` la forma breve *State only · 0.2 s ago · 96 % valid*,
  perché stia in 300 pt; M2.5). `Updated` = tempo dall'ultima scansione completa; `valid` = letture in
  `values` o `state` diviso tutte le letture delle unità osservate negli ultimi 10 s (le `nil` non contano: non essere
  nella lista non è un errore), in un anello di dieci secchielli da 1 s (nessuna allocazione). Il testo passa al token
  `warn` quando le valide sono meno del 50 % o l'ultimo aggiornamento è più vecchio di `2 · I`. In modalità `state` il
  piede comincia con *State only ·*; fuori dal combattimento dice *Not in combat*. Le letture valide le conta lo
  Scanner (`ThreatScanner.Quality`, M2.5).

### 1.6 I campi, uno per uno

Ogni riga ha la sua API (sempre attraverso `Core/Compat.lua`, voci di
[SPEC-01 §8.2](SPEC-01-platform-architecture.md#82-tabella-delle-api)), la sua categoria
([ADR 0003](../adr/0003-data-reliability-categories.md)), cosa mostra nelle tre modalità e cosa mostra se manca.

| Campo | Fonte | Categoria | `values` | `state` | `none` / se manca | Probe |
|---|---|---|---|---|---|---|
| Mob: nome | `UnitName(mobToken)` | rilevata | nome nell'intestazione | uguale | *No target*; nome segreto → *Unknown mob* | P9 |
| Mob: classificazione | `UnitClassification(mobToken)` | rilevata | *Elite*, *Rare*, *Rare elite*, *Boss* (`worldboss`); nulla per `normal` e `minus` | uguale | nessuna etichetta | P5 |
| Nome del giocatore | `UnitName(unit)` | rilevata | nome | uguale | segreto o assente → etichetta del token: *Pet*, *Party 2*, *Raid 13* (mai vuoto) | P9 |
| Colore di classe | `UnitClass(unit)` → `C_ClassColor.GetClassColor` (`ui.ClassColor`) | rilevata | colore di classe del gioco sul nome | uguale | `text-1` | P9 |
| Icona del ruolo | `UnitGroupRolesAssigned(unit)` | rilevata | icona tank, healer o DPS | uguale | nessuna icona (`NONE` o segreto) | P9 |
| Percentuale scalata e barra | `UnitDetailedThreatSituation`, 3° valore (100 = prende l'aggro) | rilevata | barra larga `min(p, 100) %` e `87 %` | niente barra, `—` (tooltip *State only*) | barra tratteggiata, `?`, tooltip con il motivo | P2, P3, P4 |
| Percentuale raw, threat raw | 4° e 5° valore | rilevata | solo nel tooltip della riga; la threat raw come la dà il client (la sua scala la dice P2) | — | — | P2, P4 |
| Tiene il mob | 1° valore; in `state` lo stato 2–3 | rilevata | icona `tank` prima del nome | uguale | nessuna | P2, P3 |
| Margine | §2.2 (non tank: `100 − p`; tank: `100 − s`, `s` la percentuale del secondo) | calcolata | `+13` nel tooltip della riga e nell'intestazione per la propria riga | tank: fascia di `UnitThreatLeadSituation` (*Comfortable*, *Close*, *Very close*) senza numero; altri `—` | `—` | P2 |
| Vantaggio del tank | `UnitThreatPercentageOfLead(holder, mobToken)` | rilevata | solo nel tooltip del tank, con il suo valore grezzo (il significato lo dice P2) | — | — | P2 |
| Stato | §2 | calcolata in `values`, rilevata in `state` (lo stato del gioco) | distintivo (icona e parola) e striscia | uguale | UNKNOWN e motivo | P3, P4 |
| Trend | §2.5 | stimata | freccia `trend-up`, `-down`, `-flat`; valore e confidenza nel tooltip | nessuna freccia | nessuna; *Insufficient data* nel tooltip | P4 |
| Tempo al superamento | §2.5 | prevista | `~4 s` con l'icona `predict`, tooltip con *may* | — | — | P4 |
| Chi tiene il mob (tank attuale) | la riga che tiene il mob; se nessuna riga osservata, `UnitName(mobToken .. "target")` | rilevata | nome con l'icona `tank` nell'intestazione | uguale | *Unknown tank* | P2, P5, P9 |
| Qualità dei dati | §1.5 | calcolata | piede | piede con *State only ·* | piede | — |
| Modalità del monitor | §1.1 MON-04 | rilevata | *Live* | *State only* | *Unavailable* | P3 |

Il **tooltip di una riga** elenca, ognuno con la parola della sua categoria (*detected*, *calculated*, *estimated*,
*predicted*): stato e motivo, percentuale scalata e raw, threat raw, margine, trend (valore, confidenza, campioni),
previsione, età dell'ultima lettura, modalità. Ciò che manca si scrive (*Secret value*, *Not available*, *Insufficient
data*, *Stale*), mai si omette in silenzio.

## 2. Stati e soglie

Quattro stati per riga: **SAFE**, **WARNING**, **DANGER**, **UNKNOWN** (`Data/ThreatState.lua`). Soglie predefinite
**provvisorie** WARNING `W` = 80 %, DANGER `D` = 95 % della percentuale scalata, isteresi 3 punti (Q7: un solo punto,
`ThreatState.DEFAULTS`; il giocatore le cambia nella card *Monitor*, §5).

### 2.1 Chi è il tank

- **Tank designati**: le unità osservate con ruolo `TANK`. Se non ce n'è nessuno (da soli, ruoli `NONE` o segreti
  **[probe P9]**), chi tiene il mob è trattato da tank per la propria riga (da soli il giocatore che tiene il suo mob,
  o il suo famiglio).
- **MON-11** MUST: per il tank che tiene il mob lo stato misura il **margine** sul secondo, non la propria percentuale:
  poco margine = WARNING.
- Un tank designato che **non** tiene il mob: se lo tiene un altro tank designato (cambio di tank, taunt), la sua riga
  segue la regola dei non tank ma senza il DANGER per "tiene il mob"; se lo tiene un non tank, la sua riga è DANGER con
  motivo *Lost aggro*.
- **Tank sconosciuto** (*Unknown tank*): nessuna riga osservata tiene il mob. `ThreatState.tankReason` dice perché:
  `not-watched` (letture leggibili, ma lo tiene un'unità non osservata) o `unknown` (nulla di leggibile lo dice) (M2.4).

### 2.2 Modalità `values`

Riga di un **non tank**, `p` = sua percentuale scalata:

| Stato | Regola |
|---|---|
| SAFE | `p < W` |
| WARNING | `W ≤ p < D`, oppure la previsione di §2.5 dice che arriva a `D` entro 3 s con confidenza almeno media |
| DANGER | `p ≥ D`, oppure tiene il mob (`isTanking`, stato 2–3) |

Riga del **tank che tiene il mob**, `s` = la percentuale scalata più alta fra le altre righe in `values` (il secondo),
margine = `100 − s`:

| Stato | Regola |
|---|---|
| SAFE | `s < W` |
| WARNING | `W ≤ s < D` |
| DANGER | `s ≥ D`, oppure il suo stato è 2 (tiene il mob ma un altro ha più threat) |

- Nessun'altra riga nella lista: SAFE, tooltip *No one else on the threat list*. Altre righe ma nessuna in `values`:
  lo stato viene da `UnitThreatLeadSituation` come in §2.3; se manca anche quello, UNKNOWN con il motivo del secondo.
- `UnitThreatPercentageOfLead` si legge (una chiamata per scansione, solo per chi tiene il mob) e si mostra nel tooltip
  come valore rilevato; se P2 dimostra che è la percentuale sul secondo, M0.7 può usarla per il margine
  (`ThreatCalc.TankMargin`, un solo punto) **[probe P2]**.
- **[probe P4]**: se il server non passa l'aggro a 100 % di scalata (110 % / 130 % di raw), la WARNING prevista e il
  tempo al superamento si spengono (`Features`, come dice [SPEC-08 §1 P4](SPEC-08-quality-probe-release.md#p4--calcolo-standard-della-threat))
  e le soglie restano sulla percentuale scalata.

### 2.3 Modalità `state` (*state only*)

`g` = `UnitThreatSituation(unit, mobToken)`: 0 meno threat del tank; 1 più threat del tank ma ancora senza aggro;
2 tiene il mob ma un altro ha più threat; 3 tiene il mob con sicurezza (significati della documentazione retail,
**[probe P2]**). `l` = `UnitThreatLeadSituation(holder, mobToken)`: quanto chi tiene il mob è sopra il secondo, 0–3
(nessuno, giallo, arancio, rosso; 3 se non è primo), dalla documentazione del dump.

| Riga | SAFE | WARNING | DANGER |
|---|---|---|---|
| Non tank | `g = 0` | `g = 1` | `g` 2–3 (tiene il mob) |
| Tank che tiene il mob | `g = 3` e `l = 0` | `g = 3` e `l = 1` | `g = 2`, oppure `l` 2–3 |

- Senza `l` leggibile il tank con `g = 3` è SAFE con il tooltip *Margin unknown*.
- Le soglie del giocatore non valgono qui (sono quelle del gioco) e il tooltip lo dice: *From the game's threat state*.
- L'isteresi di punti non serve (stati interi); la permanenza di §2.4 sì.

### 2.4 Isteresi e permanenza

- **MON-10** MUST: isteresi di 3 punti: si **entra** in uno stato più alto alla soglia, si **torna** a quello più
  basso solo 3 punti sotto (WARNING → SAFE quando `p < W − 3`, DANGER → WARNING quando `p < D − 3`; per il tank lo
  stesso su `s`). La WARNING prevista finisce quando la previsione non vale più.
- **MON-12** MUST: una riga **sale** subito (SAFE → WARNING → DANGER; da UNKNOWN a uno stato noto), ma **scende** o
  diventa UNKNOWN solo se il cambio precedente ha almeno 1 s: niente lampeggi (mai più di un cambio al secondo per
  riga, salvo le salite, [ui-style §3.2](ui-style.md#32-la-barra-della-threat-widgetsthreatbar-m16-dati-da-m2)).
- `STATE_CHANGED(unitKey, mobKey, old, new)` si emette solo per lo stato **mostrato**, dopo isteresi e permanenza: gli
  avvisi di M3 non ereditano oscillazioni. `old = nil`: l'unità entra nella lista della threat; `new = nil`: ne esce
  (morte, `drop`); entrare e uscire non sono cambi di stato e non aspettano la permanenza. A un nuovo mob o a un nuovo
  combattimento gli stati ripartono senza evento per la coppia vecchia (M2.4).
- Una discesa trattenuta dalla permanenza si ricontrolla con un solo timer (`Compat.After`): avviene anche quando non
  arrivano più scansioni, per esempio a `COMBAT_ENDED` (righe `stale` → UNKNOWN) (M2.4).
- Il motivo dello stato (`row.stateReason`): nessuno per una soglia; `predicted`, `aggro` (un non tank tiene il mob),
  `lost-aggro`, `behind` (tank con stato 2), `alone`, `margin-unknown`, `state-only`; per UNKNOWN quello della lettura
  (`secret`, `missing`, `error`, `no-unit`, `stale`) o, per il tank, quello del secondo. `THREAT_MODE_CHANGED` si
  emette quando cambia la modalità o il suo motivo (M2.4).
- Lo **stato dell'intestazione** è quello della propria riga; se il giocatore non è nella lista l'intestazione non ha
  distintivo e dice *You are not on its threat list*.

### 2.5 Trend e tempo al superamento (`Data/ThreatCalc.lua`)

- **Campioni**: per riga un anello degli ultimi 32 campioni `(observedAt, p)`, solo da letture `values` non `stale`, in
  array creati una volta.
- **Si azzerano** al cambio di mob, al cambio di chi tiene il mob (le percentuali si misurano su un altro tank), dopo
  un buco di più di 1 s fra due campioni validi e quando la riga esce dalla lista.
- **Trend** (stimato): pendenza ai minimi quadrati, in punti al secondo, sui campioni degli ultimi **3 s**; servono
  almeno **3 campioni** su almeno 0,5 s, altrimenti *Insufficient data* (M2.3 *Done when*). Una serie costante ha
  pendenza 0 e vale come R² = 1.
- **Confidenza**: `high` con almeno 8 campioni e R² ≥ 0,8; `medium` con almeno 5 e R² ≥ 0,5; `low` altrimenti.
- **Freccia**: `trend-up` oltre +2 punti/s, `trend-down` sotto −2, `trend-flat` fra i due; in `text-2`, in `text-3`
  con confidenza `low`. Tooltip: *+6.2 %/s, estimated, medium confidence (9 samples in 3 s)*. La riga del tank che tiene
  il mob non ha freccia (la sua percentuale è sempre 100).
- **Tempo al superamento** (previsto), solo per un non tank: `t = (100 − p) / trend` se trend > 0, confidenza almeno
  `medium` e `p < 100`; si mostra solo se `t ≤ 10 s`, arrotondato per eccesso al secondo, come `~4 s` con l'icona
  `predict`; tooltip *May take aggro in about 4 s if the trend continues* (ADR 0003 punto 2).
- **WARNING prevista**: `(D − p) / trend ≤ 3 s` con confidenza almeno `medium`.

### 2.6 Cosa si vede in ogni stato

Le righe, alte 20 pt su `surface-1`: striscia di stato a sinistra, icona del ruolo, icona `tank` se tiene il mob, nome
(colore di classe), barra, numero (`RowMono`), cella del trend, distintivo
([ui-style §3.2–§3.3](ui-style.md#32-la-barra-della-threat-widgetsthreatbar-m16-dati-da-m2)). Mai il solo colore
(ST-02): ogni stato ha **icona e parola**.

| Stato della riga | Distintivo (icona, parola, chiave) | Token | Barra | Numero | Trend | Prima riga del tooltip |
|---|---|---|---|---|---|---|
| SAFE | `state-safe`, *SAFE* / *SICURO*, `STATE_SAFE` | `state-safe` | piena a `p` | `62 %` | freccia | — |
| WARNING | `state-warning`, *WARNING* / *ATTENZIONE*, `STATE_WARNING` | `state-warning` | piena a `p` | `84 %` | freccia (con `predict` se prevista) | *Predicted: may reach 95 % in 2 s* se prevista |
| DANGER | `state-danger`, *DANGER* / *PERICOLO*, `STATE_DANGER` | `state-danger` | piena a `p` | `97 %` | freccia | *You have aggro* / *Lost aggro* se è il motivo |
| UNKNOWN | `state-unknown`, *UNKNOWN* / *SCONOSCIUTO*, `STATE_UNKNOWN` | `state-unknown` | tratteggiata, vuota | `?` | `stale` se il motivo è `stale` | il motivo: *Secret value*, *Not available*, *Read error*, *Unit not accessible*, *Stale* |
| riga `state` | il distintivo dello stato di §2.3 | quello dello stato | nessuna barra | `—` | nessuna | *State only: the client hides threat values here* |

| Situazione della vista | Intestazione | Elenco | Piede | Pastiglia |
|---|---|---|---|---|
| Nessun mob | *No target* | *Target an enemy to see its threat* | — | *Idle* |
| Mob, fuori dal combattimento | nome e classificazione | *Not in combat* | *Not in combat* | *Idle* |
| `values` | nome, distintivo della propria riga, *Tank: nome*, margine | righe | qualità | *Live* |
| `state` | come sopra, margine come fascia | righe senza barre | *State only ·* qualità | *State only* |
| `none` | nome, distintivo UNKNOWN | una riga sola: *Threat data unavailable* e il motivo (non una riga UNKNOWN per membro) | qualità | *Unavailable* |
| Fine del combattimento | *Combat ended* | ultime righe, tutte `stale` | *Not in combat* | *Idle* |
| Mob morto / scomparso | *Target died* / *Target lost* | vuoto | — | *Idle* |

**Disposizione della riga (M2.5).** Nella finestra stretta spariscono prima la colonna del margine (c'è solo da 370 pt
di contenuto), poi l'icona del ruolo (sotto 250 pt), la cella del trend (sotto 230 pt) e il binario della barra
(restano numero e icona `predict`); il distintivo, con icona e parola, resta sempre. Quando c'è una previsione il `~4 s`
sta nella cella del trend al posto della freccia (che resta nel tooltip). Sul tema chiaro il colore di classe è un
segno di 2 pt accanto al nome. Fuori dal combattimento senza righe l'elenco dice *Not in combat*; con la lista vuota in
combattimento *No one is on its threat list yet*. A un nemico morto deselezionato il Tracker emette `TARGET_STATUS`.

Tutti i testi sono chiavi di lingua in `enUS` e `itIT`; le chiavi nuove le aggiunge M2.5 (le proposte italiane si
fissano lì, come i distintivi di [ui-style §4.2](ui-style.md#42-i-quattro-token-di-stato)). Icone nuove del foglio
(M2.5, `tools/make_media.py`): `role-tank`, `role-healer`, `role-dps` per il ruolo (l'icona `tank` resta per chi
tiene il mob).

## 3. Ordinamenti

| Ordinamento | Chiave | Note |
|---|---|---|
| `relative` (predefinito) | percentuale scalata, decrescente (chi tiene il mob, a 100, in cima); in `state` lo stato del gioco 3, 2, 1, 0 | — |
| `absolute` | threat raw, decrescente | solo dove c'è; le righe senza vengono dopo, in `relative`; se nessuna riga ce l'ha vale `relative` e il menu dice *Needs threat values* |
| `risk` | DANGER, WARNING, SAFE, poi la percentuale o lo stato del gioco | — |
| `change` | trend, decrescente | *Insufficient data* dopo |

- Le righe UNKNOWN stanno sempre in fondo; i pareggi seguono l'ordine del roster (§1.3), mai i nomi (possono essere
  segreti).
- La propria riga è sempre evidenziata (anello `accent`); *Pin me on top* (`settings.monitor.pinSelf`, spento) la
  mette prima di tutte.
- **MON-13** MUST: l'ordine si ricalcola al massimo una volta al secondo, e subito quando una riga entra in DANGER; in
  mezzo le righe restano al loro posto mentre i valori cambiano.
- Le righe visibili sono quante ne entrano (20 pt ciascuna); le altre si riassumono nell'ultima come *+N more*. La
  propria riga è sempre visibile: se cadrebbe sotto, prende l'ultimo posto visibile.
- L'ordinamento si sceglie dalla card *Monitor* (§5) e cliccando l'intestazione dell'elenco (passa al successivo); si
  salva in `settings.monitor.sort`. Nella stessa intestazione il pulsante *Me on top: on/off* cambia `pinSelf`. Fino
  allo schema 2 (M2.6) le due scelte valgono per la sessione (M2.5).

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
| Barra del titolo | 28 pt: logo 18 pt, `THREATWARDEN` (Orbitron, 12 pt), stato del modulo, blocco, chiusura | 52 pt (come il kit di M1.6): logo 24 pt, `AZEROTH THREATWARDEN` (Orbitron, font `Display`), stato del modulo come sottotitolo mono, blocco, chiusura |
| Schede | 24 pt, solo testo, indicatore da 2 pt | 36 pt, indicatore da 2 pt (come Accord) |
| Contenuto | intestazione del mob, righe da 20 pt, piede da 16 pt con la qualità dei dati (M2) | colonna di card larga fino a 520 pt, con il selettore a pillole *Settings · Info* in Settings |

- Passando da una disposizione all'altra l'angolo in alto a sinistra resta fermo e la finestra resta nello schermo.
- Se nella compatta nome e stato non ci stanno insieme (finestra stretta, parola lunga), sparisce il nome: resta il
  logo, e lo stato non perde la parola.
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

Il tooltip della pastiglia dice il motivo (dalle capacità di Compat). Si controlla prima *Unsupported client*, poi
l'interruttore `monitor`, poi le capacità. Quali di questi stati compaiono davvero in gruppo
e in istanza lo dice il probe **[probe P3]**. Pulsanti a destra: **blocco** (lucchetto aperto o chiuso; con la finestra
bloccata non si sposta né si ridimensiona), **chiusura** (croce). La barra del titolo trascina la finestra quando non è
bloccata.

### 4.4 Schede

| Scheda | Disposizione | Contenuto | Da |
|---|---|---|---|
| **Monitor** | compatta | in M1 solo il testo *Threat monitoring arrives in v0.2.0* sotto il logo attenuato; da M2 il monitor (§1) | M1.7, M2 |
| **Reports** | ampia | sessioni registrate e report; non compare finché l'interruttore `reports` è spento | M4 |
| **Settings** | ampia | pagina *Settings* (card Aspetto, Lingua, Finestra, ripristino) e pagina *Info* (logo, versione, crediti, link) | M1.8 |

La scheda e la pagina aperte per ultime si ricordano per personaggio (`char.ui.lastTab`, `lastPage`). La scheda
Settings si costruisce la prima volta che si mostra; il pannello del gioco ha lo stesso contenuto e non cambia la
pagina ricordata. Le card si restringono con la finestra (al massimo 520 pt) e la pagina scorre con la rotella.

### 4.5 Comportamento

| Cosa | Regola |
|---|---|
| Apertura al login | secondo `char.ui.shown` (vero la prima volta); da M2.6 con `settings.monitor.show` ([Q13](SPEC-09-risks-open-questions.md), §5.1) |
| Spostamento | trascinando la barra del titolo; la finestra resta nello schermo (`SetClampedToScreen`) e torna dentro a `DISPLAY_SIZE_CHANGED` e `UI_SCALE_CHANGED` |
| Posizione | per personaggio (`char.ui.pos`), salvata al rilascio e quando il cambio di disposizione ancora l'angolo in alto a sinistra; `nil` = al centro. Il client non la salva per conto suo (`SetDontSavePosition`) |
| Schermo più piccolo | la finestra torna dentro senza riscrivere la posizione salvata, che torna valida con lo schermo di prima |
| Scala | `char.ui.scale` 50–200 % dalla card Finestra; si somma alla scala dell'interfaccia del gioco; al cambio gli scostamenti salvati sono convertiti, così la finestra resta dov'è |
| Blocco | `char.ui.locked`, dal lucchetto, da `/atw lock` e `/atw unlock`, dalla card Finestra |
| Esc | chiude la finestra (frame in `UISpecialFrames` attraverso Compat), anche in combattimento |
| Livello | strato `MEDIUM`, sopra le finestre normali quando si clicca (`SetToplevel`) |
| `/reload` | posizione, dimensioni, scala, blocco, scheda e apertura tornano come erano (DAT-23) |
| Dati in sola lettura | la finestra si apre, si chiude, si sposta e cambia scheda, senza scrivere nulla; `lock`, `unlock` e `reset` dicono che nulla è cambiato |

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

`/threatwarden` e `/atw` (Q1), con AceConsole (`Core/Commands.lua`; conta solo la prima parola, in qualsiasi
maiuscola). `show`, `hide`, `settings`, `about` e `debug` rispondono aprendo o chiudendo ciò che nominano; `lock`,
`unlock`, `reset` e `help` scrivono anche una riga. Le risposte vanno solo nella finestra di chat del giocatore (mai in un
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
| **Window** | blocco (interruttore), scala (cursore 50–200 %, salvata al rilascio perché la finestra si scala sotto il mouse), *Show minimap button* (interruttore), *Reset window* | `char.ui.locked`, `scale`, `account.settings.minimap.hide` | M1.8 |
| **Reset** | *Reset settings* con conferma: un secondo clic entro 8 s, o la prima è annullata anche cambiando pagina (riporta ai predefiniti `account.settings`, [SPEC-02 §3.4](SPEC-02-data-model-storage.md#34-caricamento-migrazioni-e-dati-danneggiati)) | — | M1.8 |
| **Monitor** | soglie (cursori *Warning* 50–99 % e *Danger* 60–100 %, `danger ≥ warning + 5`), frequenza (cursore 2–10 Hz), unità massime (cursore 5–40), quando mostrare la finestra (segmentato *In group or combat · Always · Manually*), ordinamento (§3), *Pin me on top*, *Follow target of target* | `account.settings.monitor.*`, schema 2 ([SPEC-02 §3.5](SPEC-02-data-model-storage.md#35-schema-2-m2-le-impostazioni-del-monitor)) | M2.6 |
| **Alerts** | canali, cooldown, silenzio | M3.1 | M3 |
| **Recording** | durata e limite delle registrazioni | M4.1 | M4 |

*Reload now* è attivo solo quando la lingua scelta è diversa da quella a schermo. Con dati in sola lettura la pagina
mostra un avviso (versione più nuova, o migrazione fallita), i controlli tornano al valore salvato e la card dice
*Not saved*. La stessa pagina compare nel pannello Impostazioni del gioco (*Options → AddOns*), se il client lo
permette (M1.8).

La pagina **Info** mostra logo, nome e versione, i crediti *Created and designed by Finland. Made with the Italian guild
NEBULA.* con il logo NEBULA del tema (scuro in Nebula e Warden, chiaro in Aurora), le caselle da copiare con il
repository e Ko-fi, licenza, `docs/third-party.md` e l'avviso di progetto fan. `/atw about` la apre.

### 5.1 Quando si mostra la finestra (Q13, M2.6)

`settings.monitor.show`, proposta di [Q13](SPEC-09-risks-open-questions.md) finché il proprietario non decide:

| Valore | Regola |
|---|---|
| `auto` (predefinito, *In group or combat*) | la finestra si apre da sola a `COMBAT_STARTED` e entrando in un gruppo; si chiude da sola 10 s dopo `COMBAT_ENDED` se il giocatore non è in un gruppo. Se il giocatore la chiude durante un combattimento, non si riapre da sola fino al combattimento successivo |
| `always` | aperta al login e dopo ogni `/reload`; si chiude solo a mano |
| `manual` | il comportamento di M1: `char.ui.shown`, comandi, minimappa |

Le aperture e chiusure automatiche non scrivono `char.ui.shown`, che resta la scelta a mano; con dati in sola lettura
le regole sono le stesse. *Compact in combat* (nascondere le schede in combattimento, §4.2) resta
un'opzione prevista, non in M2.

## 6. Piano di M2: moduli, eventi e test per step

Ogni test di M2.2–M2.5 che legge la threat gira **sui tre esiti** del probe (`Fight.OUTCOMES`, [SPEC-08
§2](SPEC-08-quality-probe-release.md#2-test-offline)): lo stesso scontro scriptato con `outcome("values")`,
`outcome("state")` e `outcome("none")`, con le risposte attese di §1.1 e §2 per ciascuno. Le righe delle fonti del
mock sono **ipotesi** fino al probe (SPEC-08 §2), come i significati di §2.3.

| Step | File | Bus | Test e casi |
|---|---|---|---|
| **M2.2** | `Data/TargetTracker.lua`, `Data/ThreatScanner.lua`; in Compat le voci `group.RaidIndex` (`UnitInRaid`) e la lettura di `UnitThreatPercentageOfLead` e `UnitThreatLeadSituation` per chi tiene il mob; in `Core/Init.lua` il controllo di `UnitAffectingCombat` a `PLAYER_ENTERING_WORLD` | emette `TARGET_CHANGED(mobKey)`, `THREAT_SCANNED(mobKey)`; ascolta `COMBAT_STARTED`, `COMBAT_ENDED`, `WINDOW_SHOWN`, `TAB_CHANGED`, `CONFIG_CHANGED`; dal gioco `PLAYER_TARGET_CHANGED`, `UNIT_TARGET`, `UNIT_THREAT_LIST_UPDATE`, `UNIT_THREAT_SITUATION_UPDATE`, `GROUP_ROSTER_UPDATE`, `UNIT_PET` | `test_target_tracker.lua`: target ostile, target amico → target del target (e con l'opzione spenta), nessun target, mob morto, mob scomparso, GUID cambiato senza evento (`newGUID`), GUID segreto → `tgt:n`, `UNIT_TARGET`, capacità `mobIdentity`. `test_scanner.lua`: nessuna lettura fuori dal combattimento, senza mob o senza consumatore (`Mock.threat.calls`); tick alla frequenza e arresto a `COMBAT_ENDED`; eventi raccolti (al massimo una scansione ogni 100 ms), duplicati e fuori ordine, eventi persi (`silent`) → basta il tick; risposte `nil` (riga assente), errore, funzione mancante, segreto; i tre esiti e il cambio di esito a metà combattimento (`THREAT_MODE_CHANGED` lo fa M2.4, qui le modalità dei record); limite e turno in un raid da 40 con `maxUnits = 10`; famiglio; roster che cambia; `/reload` in combattimento; nessuna allocazione per tick dopo il riscaldamento; capacità `threat*`, `groupThreat`, `threatEvents` |
| **M2.3** | `Data/ThreatModel.lua`, `Data/ThreatCalc.lua` | ascolta `THREAT_SCANNED`, `TARGET_CHANGED`, `COMBAT_STARTED`, `COMBAT_ENDED`; emette `THREAT_UPDATED(mobKey)` | `test_threat_model.lua`: categoria e `reason` di ogni campo di §1.6 nelle tre modalità; `stale` secondo frequenza e turni, e a `COMBAT_ENDED`; pool riusato; nessun valore segreto conservato. `test_threat_calc.lua`: serie lineari note (pendenza esatta), rumore (confidenza `high`, `medium`, `low`), meno di 3 campioni o meno di 0,5 s → *Insufficient data*, buchi > 1 s e cambio di chi tiene il mob azzerano, serie costante; margine del non tank e del tank (secondo, nessun altro, nessun altro leggibile); tempo al superamento (condizioni, ≤ 10 s, arrotondamento); WARNING prevista |
| **M2.4** | `Data/ThreatState.lua` (`DEFAULTS` = Q7) | ascolta `THREAT_UPDATED`, `CONFIG_CHANGED`; emette `STATE_CHANGED(unitKey, mobKey, old, new)`, `THREAT_MODE_CHANGED(mode, reason)` | `test_threat_state.lua`: §2.2 e §2.3 riga per riga (non tank, tank, tank designato che perde il mob, cambio fra due tank, da soli con il famiglio); isteresi su una serie che oscilla di ±2 punti attorno a 80 e a 95 (nessun cambio); permanenza di 1 s per le discese e salite immediate; UNKNOWN per motivo; `THREAT_MODE_CHANGED` a ogni cambio di esito; gli scenari di QA-03 sugli stati (tank stabile, DPS che si avvicina, taunt, morte del tank, morte di un DPS, cambio target, valori segreti) |
| **M2.5** | `UI/ThreatList.lua`; chiavi di lingua di §2.6; icone `role-*`; pagina wiki *Threat Monitor* nelle due lingue; anteprime (sotto) | ascolta `THREAT_UPDATED`, `STATE_CHANGED`, `THREAT_MODE_CHANGED`, `TARGET_CHANGED`, `CONFIG_CHANGED`, `THEME_CHANGED` | `test_threat_list.lua`: ogni riga di §2.6 (icona e parola sempre, barra tratteggiata con il motivo nel tooltip, riga `state` senza barra, una riga sola in `none`); ogni situazione della vista; i quattro ordinamenti, *Pin me on top*, stabilità (MON-13); la propria riga sempre visibile; *+N more*; testi nelle due lingue; nessuna API del gioco (`test_api_boundary.lua`) |
| **M2.6** | card *Monitor* in `UI/Settings.lua`; schema 2 in `Core/Config.lua`; §5.1 in `UI/Window.lua`; `/atw demo` | — | `test_config.lua` (migrazione 1 → 2, regole di §3.5 di SPEC-02, `danger < warning + 5`); `test_settings.lua` (la card); `test_window.lua` (§5.1); `test_demo.lua` (nessuna lettura del gioco, nessuna scrittura dei dati salvati, si ferma a un combattimento vero) |
| **M2.7** | `Tests/long/test_monitor_raid.lua` | — | raid da 40 con cinque mob e cambi di target per due ore di tick a 10 Hz, nei tre esiti; tempo per tick nel mock e allocazioni (zero dopo il riscaldamento) entro il budget di P10; il predefinito della frequenza in Q14 |

**Anteprime** (M2.5, `tools/make_mockups.py`, in inglese e italiano, tema Nebula più uno chiaro e uno Warden per la
prima): `monitor-values` (party, un DPS in WARNING con la previsione e uno in DANGER), `monitor-state` (*state only*),
`monitor-unknown` (`none`, *Threat data unavailable*), `monitor-no-target`, `monitor-tank` (la vista del tank con il
margine). Non si fanno in M2.1: le scene si costruiscono dalle chiavi di lingua e dalla vista, che arrivano con M2.5.
