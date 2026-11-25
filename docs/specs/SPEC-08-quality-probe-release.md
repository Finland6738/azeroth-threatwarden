# SPEC-08: Qualità, probe e rilascio

> Fonte: [specifiche originali](source-specification.md) §8, §12, §13, §18.

## 1. Probe M0

Un addon usa e getta, `AzTw_Probe`, in `tools/probe/`, **mai distribuito** (non entra in nessun pacchetto né rilascio),
che risponde nel client reale alle domande che il progetto non può risolvere offline (fonte §8). Installazione, comandi
`/atwp` e procedura in gioco per contesto: [docs/spike/README.md](../spike/README.md) (in inglese). Le firme qui sotto
vengono dal dump di Forever (build 70170, consultato il 2026-11-25); il comportamento lo dice solo il probe.

| # | Domanda | Contesti | Cambia | Step |
|---|---|---|---|---|
| P1 | Versione del client, `GetBuildInfo`, progetto, interfaccia dichiarata, restrizioni attive nella build | — | SPEC-01 §1, ADR 0002 | M0.3 |
| P2 | Presenza e firma di `UnitDetailedThreatSituation`, `UnitThreatSituation`, `UnitThreatPercentageOfLead`, `UnitThreatLeadSituation`; valori su un mob da solo | solo | SPEC-01 §2, SPEC-03 | M0.3 |
| P3 | **Valori segreti**: `C_Secrets.ShouldUnitThreatValuesBeSecret`, `C_Secrets.ShouldUnitThreatStateBeSecret`, `issecretvalue` sui risultati | solo, party, dungeon, raid, in e fuori combattimento | ADR 0004, tutto il piano | M0.3 |
| P4 | Il server calcola la threat in modo standard? (rapporti 110 % / 130 %, tank e DPS sullo stesso mob) | party | SPEC-03 §2, SPEC-04 | M0.3 |
| P5 | Unità interrogabili: membri del gruppo e loro target, `focus`, `mouseover`, `boss1–5`, `nameplateN`; mob non selezionati | party, dungeon | SPEC-07, SPEC-03 §1 | M0.4 |
| P6 | Eventi `UNIT_THREAT_LIST_UPDATE` e `UNIT_THREAT_SITUATION_UPDATE`: unità del payload, frequenza, ritardo | party, dungeon | ADR 0004 | M0.4 |
| P7 | Eventi di combattimento: `COMBAT_LOG_EVENT_UNFILTERED` è leggibile? `PLAYER_REGEN_*`, `UNIT_TARGET`, `ENCOUNTER_*`, morti, taunt (`UNIT_SPELLCAST_SUCCEEDED` sul gruppo) | party, dungeon, raid | SPEC-05 §1, SPEC-04 | M0.5 |
| P8 | `C_DamageMeter`: disponibile? morti e durata delle sessioni utilizzabili? | solo, dungeon | SPEC-05 | M0.5 |
| P9 | GUID e ruoli: `UnitGUID`, `UnitGroupRolesAssigned` segreti in istanza? stabilità del GUID di un mob | dungeon, raid | SPEC-02 | M0.4 |
| P10 | Costo del campionamento: ms per tick a 2, 5 e 10 Hz con 5, 10 e 40 unità; memoria per minuto di campioni | raid o simulato | ARC-08, Q14 | M0.6 |
| P11 | Restrizioni: blocchi o errori `ADDON_ACTION_BLOCKED`, limiti di frequenza, comportamento in combattimento e in campo di battaglia | tutti | SPEC-01 | M0.6 |
| P12 | `/reload` e logout durante un combattimento: cosa resta in `AzTw_ProbeDB` | solo | SPEC-05 §1 | M0.6 |

**Gate di progetto**: niente Threat Replay completo né multi-target promessi finché il probe non dimostra che i dati
sono ottenibili. M0.7 scrive `docs/spike/M0-results.md`, la matrice delle funzioni supportate e la decisione sul
perimetro, e aggiorna specifiche, ADR e roadmap.

### 1.1 Regole comuni del probe

- **PRB-01** MUST: ogni chiamata a un'API del gioco passa da un `pcall`; un errore è un risultato (`error` con il testo
  ripulito), mai un'interruzione del probe.
- **PRB-02** MUST: ogni valore restituito si controlla con `issecretvalue` **prima** di qualsiasi altra operazione. Un
  valore segreto si registra solo come `secret`: mai confrontato, sommato, formattato, concatenato, stampato o salvato.
  Nessun tentativo di aggirare la segretezza ([SPEC-01 §6](SPEC-01-platform-architecture.md#6-sicurezza-privacy-conformità-fonte-10)).
- **PRB-03** MUST: nessun nome di giocatore, gilda, personaggio o canale stampato o salvato, e nessun GUID di giocatore.
  I giocatori diventano `<player n>`, i mob `<mob n>` (numerati per GUID nella sessione del probe, confronto solo in
  memoria); dei mob si salvano il tipo del GUID (`Creature`, `Vehicle`, `Pet`…) e l'id della creatura, che non sono dati
  personali. Il testo degli errori e le note passano dall'helper di pulizia, che sostituisce i nomi del gruppo. I token
  di unità (`party2`, `nameplate7`) non sono nomi e si salvano.
- **PRB-04** MUST: nessuna rete, nessun messaggio di addon, nulla in chat tranne le righe del probe nella finestra del
  giocatore ([ADR 0001](../adr/0001-local-only-addon-no-network.md)); nessuna CVar o impostazione del giocatore cambiata.
- **PRB-05** MUST: le funzioni che il dump non elenca come globali (per esempio `CombatLogGetCurrentEventInfo`,
  `WOW_PROJECT_ID`, i valori di `Enum.AddOnRestrictionType` e `Enum.DamageMeterType`, che il dump non documenta) si
  cercano a runtime con `rawget`/`type`: "assente" è una risposta.
- **PRB-06** MUST: i risultati vanno in `AzTw_ProbeDB` come `{id, verdict, details, build, context, time}` più un log
  per controllo; `/atwp export` li mostra tutti come testo da copiare. Il verdetto lo propone il probe dove i criteri
  sono numerici; altrimenti resta `todo` e lo decide M0.7 leggendo il log e le note del proprietario.

### 1.2 Contesti e timbro di contesto

| Codice | Contesto | Come ci si arriva |
|---|---|---|
| `solo` | da soli nel mondo aperto, fuori dal combattimento | qualsiasi personaggio |
| `solo-combat` | da soli in combattimento con un mob ostile (o un manichino, se il client ne ha) | un mob del proprio livello o un élite con molti punti vita |
| `party` | gruppo di 2–5 nel mondo aperto, in combattimento | un altro giocatore, anche un secondo account |
| `dungeon` | istanza da 5: trash e boss (encounter attivo) | un dungeon qualsiasi |
| `raid` | gruppo raid, nel mondo aperto e, se possibile, in un'istanza raid durante un boss | un gruppo convertito in raid; l'istanza è facoltativa |
| `bg` | campo di battaglia | solo P11 e, per completezza, P3 |

Ogni lettura porta un **timbro di contesto** calcolato dal probe: `IsInInstance()` (tipo di istanza), `GetInstanceInfo()`
(difficultyID, maxPlayers, instanceID: mai il nome), gruppo (`IsInRaid`, `IsInGroup`, `GetNumGroupMembers`),
combattimento (`UnitAffectingCombat("player")`, `C_RestrictedActions.InCombatLockdown()`), encounter attivo (tra
`ENCOUNTER_START` ed `ENCOUNTER_END`), restrizioni attive (`C_RestrictedActions.IsAddOnRestrictionActive` per ogni
valore di `Enum.AddOnRestrictionType` trovato a runtime), più l'etichetta facoltativa data dal proprietario con
`/atwp ctx <label>`.

### 1.3 Campi registrati per lettura

Una **lettura** è una chiamata a un'API con i suoi argomenti: `t` (secondi dall'inizio del controllo, da `GetTime`),
timbro di contesto, unità interrogata (token), mob (`<mob n>`, tipo del GUID, id della creatura, `UnitClassification`),
previsioni di segretezza (`C_Secrets.Should…`), e per ogni valore restituito il **genere**: `nil`, `secret`, `boolean`,
`number` (con il valore arrotondato a 0,1 solo se non segreto) o `error` (testo ripulito); più il numero di valori
restituiti (`select("#", …)`). I riepiloghi contano letture, valori segreti, `nil` ed errori per contesto.

### 1.4 Verdetti

- **Supportato**: l'API esiste e risponde con valori leggibili e coerenti in tutti i contesti che servono all'MVP (solo,
  party, dungeon, raid in combattimento).
- **Parzialmente**: l'API esiste ma con limiti (segreta o `nil` in alcuni contesti, solo alcune unità, ritardi, forma
  degli argomenti diversa dal dump).
- **Non supportato**: assente, sempre in errore, oppure sempre segreta o `nil` dove serve.

Ogni controllo sotto dice la conseguenza di ciascun verdetto; M0.7 la applica a specifiche, ADR e milestone.

### P1 — Client e interfaccia

- **Chiamate**: `GetBuildInfo()` (sei valori: versione, build, data, interfaccia, versione localizzata, buildInfo);
  `WOW_PROJECT_ID` (non nel dump, cercato a runtime); `GetLocale()`; `C_Secrets.HasSecretRestrictions()` (se `false`,
  nessuna API di questa build restituisce segreti); `C_CombatLog.IsCombatLogRestricted()`; il censimento delle API che
  P2–P12 useranno (presente come funzione / assente).
- **Contesti**: `solo`, una volta per ogni build del client.
- **Registrato**: i sei valori di `GetBuildInfo`, `WOW_PROJECT_ID` o "assente", la lingua del client, i due booleani,
  la tabella del censimento.
- **Come**: dopo il login, `/atwp run P1`.

| Verdetto | Quando | Conseguenza |
|---|---|---|
| Supportato | build `1.60.1` (70170 o successiva) e interfaccia `16001` come il dump; il progetto si identifica | ADR 0002 confermato; SPEC-01 §1 scrive i valori che ARC-01 controlla all'avvio |
| Parzialmente | build o interfaccia diverse dal dump, API della threat presenti | nuovo `## Interface` nel TOC; ADR 0002 aggiornato con la build vista; i controlli che dipendono dalla differenza si ripetono |
| Non supportato | il client non si identifica (`GetBuildInfo` in errore, nessun progetto) | ARC-01 si basa solo sul censimento delle API; `/atw debug` mostra cosa manca invece della versione |

### P2 — API della threat sul target

- **Chiamate** (dal dump: il secondo argomento si chiama `mobGUID` ma è di tipo `UnitToken`):
  `UnitDetailedThreatSituation("player", "target")` → `isTanking, status, scaledPercentage, rawPercentage, rawThreat`;
  `UnitThreatSituation("player", "target")` e `UnitThreatSituation("player")` → `status` 0–3 o `nil`;
  `UnitThreatPercentageOfLead("player", "target")` → numero o `nil` (significato non documentato: si deduce
  confrontandolo con le altre letture dello stesso istante); `UnitThreatLeadSituation("player", "target")` → 0–3 o
  `nil` (3 se non si è primi). Per sapere quale forma accetta il client, le quattro funzioni si provano anche con il
  GUID del mob come secondo argomento. A margine: `GetThreatStatusColor(0…3)` e `IsThreatWarningEnabled()`.
- **Casi**: (a) nessun target; (b) target amico (giocatore o PNG); (c) mob ostile non ingaggiato; (d) mob in
  combattimento con il giocatore che fa da tank; (e) mob ostile in combattimento con un altro (se capita); (f) mob morto.
- **Contesti**: `solo`, `solo-combat`.
- **Registrato**: per caso e funzione: numero di valori restituiti, genere di ognuno, valori leggibili, errore; il caso
  si riconosce da solo (`UnitExists`, `UnitCanAttack`, `UnitAffectingCombat`, `UnitIsDead` sul target).
- **Come**: `/atwp run P2` in ogni caso (a)–(c) e (f); durante il combattimento (d) le letture partono da sole ogni 0,5 s
  finché il controllo è attivo.

| Verdetto | Quando | Conseguenza |
|---|---|---|
| Supportato | le quattro funzioni esistono, accettano il token del mob e restituiscono i valori del dump (stato 0–3, scalata 0–100, raw ≥ 0); `nil` solo nei casi (a)–(c) e (f) | le righe di SPEC-01 §2 diventano "verificato"; ADR 0004 regge; M2 come previsto |
| Parzialmente | una funzione manca o restituisce `nil` anche in combattimento, oppure funziona solo con il GUID, oppure il numero di valori è diverso | Compat (M1.4) usa la forma e l'arità viste; SPEC-03 toglie ciò che manca (per esempio il margine del tank resta calcolato dalla lista o nascosto) |
| Non supportato | `UnitDetailedThreatSituation` e `UnitThreatSituation` assenti o sempre `nil`/errore | R1 si avvera: nessun monitor possibile; M0.7 ridefinisce il progetto con il proprietario |

### P3 — Valori segreti

- **Chiamate**: `C_Secrets.HasSecretRestrictions()`; per ogni coppia (unità, mob):
  `C_Secrets.ShouldUnitThreatValuesBeSecret(unit, mob)`, `C_Secrets.ShouldUnitThreatStateBeSecret(unit, mob)` e
  `C_Secrets.ShouldUnitThreatStateBeSecret(unit)` (nel dump queste funzioni stanno in `C_Secrets`, non sono globali);
  poi le quattro funzioni di P2 e, su ogni valore, `issecretvalue(v)` e `canaccessvalue(v)`. In ascolto:
  `ADDON_RESTRICTION_STATE_CHANGED` (tipo, stato), `ENCOUNTER_START/END`, `PLAYER_REGEN_DISABLED/ENABLED`.
- **Unità**: `player` sul `target`; in gruppo anche `party1–4` / `raid1–40` sullo stesso mob e `targettarget`.
- **Contesti**: `solo` (mob selezionato, fuori dal combattimento), `solo-combat`, `party`, `dungeon` (trash e boss),
  `raid` (in combattimento, boss se possibile), `bg` facoltativo.
- **Quando**: una lettura a `PLAYER_REGEN_DISABLED`, poi ogni secondo in combattimento, una a `ENCOUNTER_START`, una a
  `PLAYER_REGEN_ENABLED` e una 2 s dopo.
- **P3b, visualizzazione passante** (solo se qualcosa è segreto): un valore segreto passato, dentro `pcall`, a
  `StatusBar:SetValue` e `FontString:SetText` di una cornice nascosta del probe. Si registra solo riuscito o errore:
  dice se il client permette di **mostrare** un valore senza **leggerlo**.
- **Registrato**: per lettura le previsioni `Should…` e il genere di ogni valore; se la previsione era giusta; per
  contesto il numero di letture con valori segreti e con stato segreto; l'esito di P3b.
- **Come**: `/atwp watch on` una volta, poi giocare normalmente in ogni contesto con `/atwp ctx <label>` all'ingresso;
  `/atwp run P3` alla fine riassume.

| Verdetto | Quando | Conseguenza |
|---|---|---|
| Supportato | nessun valore segreto in nessun contesto (oppure `HasSecretRestrictions` è `false`) | ADR 0004 confermato; percentuali ovunque; R2 chiuso |
| Parzialmente | valori segreti in alcuni contesti (istanze, encounter, unità diverse da `player`) ma stato leggibile, e `Should…` lo prevede | modalità *state only* (MON-02) in quei contesti, scelta da Compat con `Should…` **prima** della chiamata; matrice per contesto in M0.7; SPEC-03 §2, SPEC-04 (avvisi sui cambi di stato), SPEC-05 (si registra lo stato) e SPEC-06 (metriche solo dove ci sono valori) aggiornate; uno step in M2 per la modalità; README e pagina CurseForge lo dicono. Se P3b riesce, barre "solo visualizzazione" possibili |
| Non supportato | valori **e** stato segreti in combattimento in party, dungeon o raid | R2 in pieno: il prodotto si ridimensiona. M0.7 chiede al proprietario (nuova domanda in SPEC-09) tra: strumento solo per il mondo aperto, visualizzazione passante senza avvisi né registrazione (se P3b riesce), o stop. ADR 0004 sostituito da un nuovo ADR; M2–M7 riscritte |

### P4 — Calcolo standard della threat

- **Chiamate**: `UnitDetailedThreatSituation` per il giocatore (DPS) e per il tank (`partyN`) sullo stesso mob, a
  10 Hz durante la prova, in un buffer circolare degli ultimi 3 s; il passaggio dell'aggro si riconosce da
  `isTanking` che cambia e da `UNIT_TARGET` sul mob (`targettarget` che diventa il giocatore).
- **Contesti**: `party` di 2 (un tank e il DPS con il probe), un solo mob con molti punti vita.
- **Registrato**: al passaggio dell'aggro, i campioni prima e dopo (`t`, `rawPercentage`, `scaledPercentage`,
  `status`, `isTanking`) del giocatore e, se leggibili, del tank; il tipo di prova dalla nota del proprietario
  (`melee` o `ranged`).
- **Come**: il tank ingaggia e accumula threat per circa 10 s; il DPS esegue `/atwp note P4 melee` e fa danno finché
  non prende l'aggro; tre volte in mischia e tre a distanza (`/atwp note P4 ranged`); poi `/atwp run P4`.

| Verdetto | Quando | Conseguenza |
|---|---|---|
| Supportato | l'aggro passa con `rawPercentage` ≈ 110 in mischia e ≈ 130 a distanza (± 2 punti per il campionamento) e `scaledPercentage` arriva a 100 al passaggio | le soglie di SPEC-03 §2 sulla percentuale scalata restano; R10 chiuso; il Coach (SPEC-04) può citare 110 % / 130 % |
| Parzialmente | rapporti costanti ma diversi, oppure la scalata è coerente e la raw no | soglie solo sulla percentuale scalata (che contiene già la regola); il Coach non cita i rapporti; SPEC-03 §2 scrive i rapporti misurati |
| Non supportato | il passaggio non ha relazione costante con i valori (la scalata non è 100 al passaggio) | il monitor mostra stato e valori rilevati ma niente previsioni: il trend verso DANGER di SPEC-03 §2 e COA-02 di SPEC-04 restano spenti in `Core/Features.lua`; R10 si avvera |

Se P3 rende i valori segreti in `party`, P4 si ripete in `solo-combat` con un compagno PNG o un famiglio, oppure resta
senza verdetto e M0.7 lo dice.

### P5 — Unità e mob interrogabili

- **Chiamate**: per ogni mob M tra `target`, `focus`, `mouseover`, `targettarget`, `boss1–5`, `nameplate1–40`,
  `party1–4target`, `raid1–40target`, `pettarget` e ogni unità U tra `player`, `pet`, `party1–4`, `raid1–40`:
  `UnitExists(M)`, `UnitCanAttack("player", M)`, poi `UnitDetailedThreatSituation(U, M)` e `UnitThreatSituation(U, M)`.
  I mob si deduplicano per GUID (confronto in memoria). A margine: `UnitTokenFromGUID(guid)` (un mob senza token ne
  ottiene uno?), `C_Secrets.CanCompareUnitTokens(M1, M2)`; le targhe da `NAME_PLATE_UNIT_ADDED/REMOVED`.
- **Mob non selezionati**: un ingaggio di 3 o più mob in cui almeno uno non è il target di nessuno; lo stesso con le
  targhe nemiche visibili e nascoste (le cambia il proprietario con il tasto del gioco, il probe non tocca CVar).
- **Contesti**: `party`, `dungeon`; `raid` facoltativo.
- **Registrato**: una matrice per genere di token del mob × genere di unità: quante letture con numero, stato,
  segreto, `nil`, errore; mob distinti raggiungibili con un token qualsiasi contro mob visti dalle targhe; se un mob
  visibile solo dalla targa risponde; se la threat degli altri membri su un mob risponde.
- **Come**: `/atwp watch on`, ingaggi da 3 o più mob, poi `/atwp run P5`.

| Verdetto | Quando | Conseguenza |
|---|---|---|
| Supportato | la threat di ogni membro risponde su ogni mob che ha un token (target, targa, boss, target dei membri) | M7 come previsto (SPEC-07 §1–2, limite MT-02); lista completa del gruppo in M2 |
| Parzialmente | solo alcuni token (per esempio target, focus e boss ma non le targhe), oppure solo la threat del giocatore sugli altri mob | SPEC-07 ridotta ai mob con un token che risponde; perimetro di M7 ridotto; la lista di SPEC-03 §1 mostra solo i membri che rispondono |
| Non supportato | risponde solo `player` sul `target` | niente multi-target: M7 tolta o sostituita (M0.7), SPEC-07 §1–2 non realizzabili, R4 si avvera; il monitor di M2 mostra il solo giocatore e lo dice |

### P6 — Eventi della threat

- **Chiamate**: registrazione di `UNIT_THREAT_LIST_UPDATE` e `UNIT_THREAT_SITUATION_UPDATE` (payload `unitTarget`);
  per ogni evento il genere del token e `GetTime()`; in parallelo un campionamento a 10 Hz del `target` per misurare il
  ritardo.
- **Contesti**: `party`, `dungeon`.
- **Registrato**: conteggi per evento e per genere di token del payload (`target`, `nameplateN`, `player`, `partyN`…),
  eventi al secondo (media e massimo), ritardo in ms tra un cambio visto dal campionamento e l'evento successivo
  (mediana e massimo), eventi senza alcun cambio, cambi senza evento entro 1 s.
- **Come**: `/atwp watch on`, almeno tre combattimenti per contesto, poi `/atwp run P6`.

| Verdetto | Quando | Conseguenza |
|---|---|---|
| Supportato | i due eventi arrivano per i mob e le unità del payload con ritardo ≤ un tick di campionamento (200 ms) | lettura guidata dagli eventi, campionamento lento come rete di sicurezza (ADR 0004 punto 2, ARC-05) |
| Parzialmente | arrivano ma radi, in ritardo o solo per `player` | il campionamento è la fonte principale; gli eventi forzano solo una lettura immediata; la frequenza la decide P10 |
| Non supportato | non arrivano mai (o il payload è segreto) | solo campionamento; ADR 0004 punto 2 aggiornato; P10 decide il costo |

### P7 — Eventi di combattimento

- **Chiamate**: registrazione (in `pcall`, su un frame del probe dedicato) di `COMBAT_LOG_EVENT_UNFILTERED`,
  `COMBAT_LOG_EVENT` e `COMBAT_LOG_EVENT_INTERNAL_UNFILTERED` e conteggio delle consegne, con gli
  `ADDON_ACTION_BLOCKED`/`FORBIDDEN` che ne seguono; ricerca a runtime di `CombatLogGetCurrentEventInfo` (assente dal
  dump), `C_CombatLogInternal.GetCurrentEventInfo` e `C_CombatLogSecure.GetCurrentEventInfo` (namespace che il dump non
  elenca tra i globali), chiamate solo sulle prime consegne e una volta per combattimento, e
  `C_CombatLog.IsCombatLogRestricted()`; degli argomenti dell'evento e dei valori restituiti solo numero e genere, mai
  il contenuto. Poi: `PLAYER_REGEN_DISABLED/ENABLED` confrontati
  con `UnitAffectingCombat("player")`; `UNIT_TARGET` per `target`, `nameplateN` e `bossN`; `PLAYER_TARGET_CHANGED`;
  `ENCOUNTER_START/END` (si salvano encounterID, difficoltà, dimensione del gruppo, esito; il nome no); morti da
  `UNIT_HEALTH`, `UNIT_FLAGS`, `UnitIsDead`/`UnitIsDeadOrGhost` su membri e mob, con `issecretvalue` su
  `UnitHealth`/`UnitHealthMax`, più `UNIT_DIED` e `PARTY_KILL` (dal GUID del payload solo il genere e il tipo, confronto
  solo in memoria), `PLAYER_DEAD` e un controllo ogni secondo; taunt da `UNIT_SPELLCAST_SUCCEEDED` su `player`, `party1–4`, `raid1–40`
  (`issecretvalue` sullo `spellID`; si salvano gli id degli incantesimi, che non sono dati personali, e se il target del
  mob cambia entro 0,5 s).
- **Contesti**: `party`, `dungeon` (con un boss), `raid`.
- **Registrato**: conteggi per evento e per genere di unità; consegne di `COMBAT_LOG_EVENT_UNFILTERED` e genere degli
  argomenti; ritardo tra `PLAYER_REGEN_*` e `UnitAffectingCombat`; morti viste e da quale fonte; incantesimi seguiti da
  un cambio del target del mob.
- **Come**: `/atwp watch on`; in party e in dungeon il tank usa almeno una volta il suo taunt (e lo annota con
  `/atwp note P7 taunt`); poi `/atwp run P7`.

| Verdetto | Quando | Conseguenza |
|---|---|---|
| Supportato | il combat log è leggibile da un addon (con qualche funzione) e gli eventi di unità funzionano | il combat log non serve comunque per la threat (ADR 0004); il recorder (REC-03) può segnare taunt e morti anche da lì; R3 chiuso |
| Parzialmente | combat log non leggibile, eventi di unità funzionanti (caso atteso) | gli eventi di SPEC-05 §1 sono: inizio e fine da `PLAYER_REGEN_*`, cambi di target da `UNIT_TARGET`, morti da `UnitIsDead`/`UNIT_HEALTH`, taunt solo dai lanci dei membri del gruppo, encounter |
| Non supportato | anche gli eventi di unità mancano o sono segreti in istanza (per esempio `spellID` segreto, `UNIT_TARGET` assente) | il recorder salva solo campioni, inizio e fine; le regole del Coach che servono eventi (taunt, morte del tank) restano spente; SPEC-04, SPEC-05 e il perimetro di M4 rivisti |

### P8 — `C_DamageMeter`

- **Chiamate**: `C_DamageMeter.IsDamageMeterAvailable()` (`isAvailable`, `failureReason`);
  `GetAvailableCombatSessions()` (quante e `durationSeconds`); `GetSessionDurationSeconds(sessionType)` e
  `GetCombatSessionFromType(sessionType, type)` per ogni valore di `Enum.DamageMeterSessionType` e
  `Enum.DamageMeterType` trovati a runtime (si salvano i nomi dei valori: se esistesse un tipo per la threat, cambierebbe
  molto); delle fonti solo i conteggi (`deathTimeSeconds` e `deathRecapID` non zero, `isLocalPlayer`) e il genere di
  ogni campo, mai `name` né `sourceGUID`. Eventi `DAMAGE_METER_COMBAT_SESSION_UPDATED`,
  `DAMAGE_METER_CURRENT_SESSION_UPDATED`, `DAMAGE_METER_RESET` con il ritardo rispetto a `PLAYER_REGEN_*`.
- **Contesti**: `solo-combat`, `dungeon`.
- **Registrato**: disponibilità e motivo, valori degli enum, sessioni e durate contro la durata misurata del
  combattimento, morti viste, campi segreti.
- **Come**: `/atwp run P8` dopo alcuni combattimenti in ogni contesto.

| Verdetto | Quando | Conseguenza |
|---|---|---|
| Supportato | disponibile, sessioni allineate ai combattimenti (± 1 s), morti leggibili | il recorder (SPEC-05) può usare durata e morti come eventi rilevati; un eventuale tipo "threat" diventa un nuovo ADR |
| Parzialmente | disponibile ma con campi segreti in istanza o solo dati propri | solo confronto fuori dalle istanze o per la propria morte |
| Non supportato | non disponibile (`failureReason` salvato) | non si usa; SPEC-05 si basa solo su P7; la riga di `C_DamageMeter` esce da SPEC-01 §2 |

### P9 — GUID e ruoli

- **Chiamate**: `UnitGUID(u)` per `player`, `party1–4`, `raid1–40`, `target`, `nameplateN`, `bossN` (dal dump: argomento
  `UnitTokenPvPRestrictedForAddOns`, risultato `nil` possibile); `C_Secrets.ShouldUnitIdentityBeSecret(u)`;
  `issecretvalue` sul GUID; dai GUID leggibili dei mob, tipo e id della creatura (`strsplit("-")`); la stabilità di un
  mob si verifica confrontando il suo GUID in memoria all'inizio, a ogni lettura, alla fine e dopo un cambio di target;
  andata e ritorno con `UnitTokenFromGUID`. `UnitGroupRolesAssigned(u)` per ogni membro (`TANK`, `HEALER`, `DAMAGER`,
  `NONE` o segreto). `C_Secrets.ShouldUnitComparisonBeSecret` e `UnitIsUnit("target", "party1target")`.
- **Contesti**: `dungeon` (gruppo dal cercatore e gruppo fatto a mano, se possibile), `raid`.
- **Registrato**: per contesto e genere di unità quanti GUID leggibili, segreti, `nil`; tipi di GUID; id delle creature;
  stabilità sì/no per `<mob n>`; ruoli contati per valore e quanti segreti. Mai un GUID di giocatore.
- **Come**: `/atwp run P9` entrando nell'istanza, dopo un ingaggio e dopo un boss.

| Verdetto | Quando | Conseguenza |
|---|---|---|
| Supportato | GUID leggibili e stabili, ruoli leggibili | `ThreatRecord` di SPEC-02 indicizzato per GUID; il ruolo guida Coach e profili (SPEC-04, M8) |
| Parzialmente | GUID segreti per i giocatori ma leggibili per i mob (o il contrario), oppure ruoli `NONE` fuori dal cercatore | chiave per token di unità più un id locale di sessione (SPEC-02); ruolo da un'impostazione manuale (nuova domanda in SPEC-09) |
| Non supportato | GUID dei mob segreti o instabili | nessuna identità tra un target e l'altro: SPEC-02 per token soltanto, il report di SPEC-05 per "target del momento", M7 spenta |

### P10 — Costo del campionamento

- **Chiamate**: `debugprofilestop()` prima e dopo un tick che legge N unità × M mob con `UnitDetailedThreatSituation`,
  lo stato e le previsioni di segretezza; tick da `C_Timer.NewTicker` a 2, 5 e 10 Hz, 30 s per configurazione; N = 5,
  10, 40; `UpdateAddOnMemoryUsage()` e `GetAddOnMemoryUsage("AzTw_Probe")` ogni minuto mentre si salvano campioni
  compatti (array di numeri); `collectgarbage("count")`; `GetFramerate()` prima e durante.
- **Contesti**: `raid` in combattimento; altrimenti simulato (le unità disponibili lette a rotazione fino a N chiamate,
  segnato `simulato` nel risultato), dentro e fuori dal combattimento.
- **Registrato**: per configurazione ms per tick (mediana, p95, massimo), ms al secondo in totale, KB al minuto di
  campioni, FPS prima e durante.
- **Budget proposto** (vale finché il proprietario non decide, Q14): ≤ 1 ms per tick al p95 e ≤ 5 ms al secondo in
  totale; la memoria si misura e la soglia la fissa M4.1 con Q8.
- **Come**: `/atwp perf` (tutte le configurazioni) o `/atwp perf <hz> <unità> [mob]`; `/atwp perf stop` interrompe; si
  gioca normalmente durante la misura. La misura parte solo su richiesta, si ferma da sola e non riprende dopo un
  `/reload`. `/atwp run P10` riassume soltanto.
- **Misura**: per default M = 1 mob (il `target`); prima di ogni configurazione 3 s di pausa (FPS "prima"). La memoria
  **trattenuta** dai campioni si ottiene con una garbage collection completa alla fine della configurazione, con e senza
  i campioni (un breve scatto, fuori dai tick misurati); quella **lorda** è la differenza senza pulizia. I campioni
  restano in memoria: si salvano solo i numeri. Una configurazione è "in raid" solo se ogni tick ha letto unità distinte
  in combattimento in raid, altrimenti è `simulato`; quelle interrotte non contano per il verdetto.

| Verdetto | Quando | Conseguenza |
|---|---|---|
| Supportato | 40 unità a 5 Hz entro il budget | 5 Hz resta il predefinito (Q14 risolta, ARC-08); limiti di REC-02 e MT-02 confermati |
| Parzialmente | entro il budget solo a frequenze o con unità minori | predefinito abbassato (per esempio 2 Hz) o limite di unità fissato dai numeri; Q14 aggiornata |
| Non supportato | anche 2 Hz su 5 unità supera il budget | lettura solo da eventi (se P6 lo consente) e campionamento del solo target; ADR 0004 punto 2 rivisto |

### P11 — Restrizioni

- **Chiamate**: registrazione di `ADDON_ACTION_BLOCKED` e `ADDON_ACTION_FORBIDDEN` (si salvano la funzione e se
  l'addon è il probe), `ADDON_RESTRICTION_STATE_CHANGED` (tipo e stato), `C_RestrictedActions.IsAddOnRestrictionActive`
  per ogni tipo, `C_RestrictedActions.InCombatLockdown()`; gli errori dei `pcall` del probe (conteggio e testo ripulito);
  una raffica di 1000 chiamate di `UnitDetailedThreatSituation` nello stesso frame per vedere se le risposte degradano
  (`nil`, errori); registrazione e cancellazione degli eventi della threat durante il combattimento; un ticker di
  `C_Timer` che continua in combattimento.
- **Contesti**: tutti: `solo`, `solo-combat`, `party`, `dungeon`, `raid`, `bg`.
- **Registrato**: per contesto blocchi, divieti, stati di restrizione, errori, esito della raffica, esito di
  registrazione e ticker.
- **Come**: il registro è sempre acceso dal login; `/atwp run P11` in ogni contesto, durante un combattimento con un mob
  ostile selezionato (la raffica solo fuori da un boss); il ticker di prova dura 10 s e si ferma da solo.
- **Proposta del verdetto**: contano per "non supportato" le chiamate e le registrazioni della threat bloccate o in
  errore nella raffica (i blocchi di altri addon e il rifiuto del combat log di P7 si contano soltanto); errori delle
  funzioni della threat visti da altri controlli (P2 prova anche il GUID) lasciano `todo` per M0.7; "supportato" richiede
  una raffica con risposte in combattimento da soli, in party, in dungeon e in raid.

| Verdetto | Quando | Conseguenza |
|---|---|---|
| Supportato | nessun blocco, divieto, limite o restrizione che tocchi le chiamate | SPEC-01 e ARC-05–ARC-07 invariati |
| Parzialmente | restrizioni attive in alcuni contesti (campi di battaglia, encounter) ma le chiamate rispondono `nil` o segreto senza errori | Compat le segna `restricted` (ARC-02) e il monitor mostra UNKNOWN (MON-01); i contesti vanno nella wiki |
| Non supportato | le chiamate sono bloccate o danno errori nei contesti che contano | Compat le evita in quei contesti (spente per contesto); perimetro per contesto nella matrice di M0.7 |

### P12 — `/reload` e logout durante un combattimento

- **Chiamate**: in combattimento il probe scrive ogni secondo in `AzTw_ProbeDB.p12` un campione compatto con un contatore
  crescente e `GetServerTime()`; a `PLAYER_LOGOUT` un timbro finale; al caricamento successivo (`ADDON_LOADED`,
  `PLAYER_LOGIN`) confronta: ultimo campione, numero di campioni, presenza del timbro finale, `UnitAffectingCombat` e
  `InCombatLockdown` appena dopo, se `PLAYER_REGEN_DISABLED` arriva di nuovo, se la lettura della threat sul target
  riprende subito.
- **Contesti**: `solo-combat`.
- **Registrato**: campioni scritti prima e trovati dopo, distanza tra l'ultimo campione e il ricaricamento, timbro
  finale sì/no, stato del combattimento e della lettura dopo.
- **Come**: `/atwp run P12` (arma il buffer), ingaggiare un mob, `/reload` a metà combattimento, poi dopo 10 s
  `/atwp run P12` di nuovo (riporta la prova; il lancio seguente ne arma un'altra); la stessa prova con un logout (se il
  client lo permette in combattimento, altrimenti appena finito). Se le SavedVariables non sono state scritte il probe
  non può accorgersene (dopo il ricaricamento arma un buffer nuovo): il proprietario lo segnala con
  `/atwp note P12 lost`. Il buffer tiene al massimo 600 campioni; `/atwp reset` non toglie un buffer armato.

| Verdetto | Quando | Conseguenza |
|---|---|---|
| Supportato | tutto fino all'ultimo tick sopravvive (`PLAYER_LOGOUT` arriva anche al `/reload`) e il combattimento è leggibile dopo | REC-04: il recorder chiude la sessione a `PLAYER_LOGOUT` come "interrotta" e dopo il ricaricamento ne apre una nuova collegata |
| Parzialmente | si perdono gli ultimi campioni o il timbro finale (per esempio al logout in combattimento) | REC-04 segna la sessione "incompleta" dall'ultimo timbro; niente si afferma dopo |
| Non supportato | le SavedVariables non si scrivono al `/reload` in combattimento | la sessione in corso si perde: SPEC-05 e la wiki lo dicono, REC-04 cambia di conseguenza |

## 2. Test offline

- **QA-01** MUST: `python -I -X utf8 tools/check_docs.py` passa sempre.
- **QA-02** MUST (da M1.3): `python -X utf8 Tests/run_tests.py` con lupa e il client finto
  ([ADR 0010](../adr/0010-offline-tests-with-lupa-and-a-mock-client.md)); ogni step aggiunge test per ciò che costruisce.
- **QA-03** MUST: scenari della fonte §13 come test con scontri scriptati: giocatore solo; party; raid; tank stabile;
  DPS che si avvicina alla soglia; cambio target; target che muore; più mob; taunt; morte del tank; morte di un DPS;
  fine combattimento; logout o reload durante e dopo una sessione; API che restituisce `nil`; unità non accessibile;
  GUID non disponibile; campioni mancanti; eventi doppi o fuori ordine; mob che scompare; target sostituito; valori
  segreti.

Com'è fatto il banco di prova (M1.3, in `Tests/`, mai nel pacchetto):

- `run_tests.py` carica nell'ordine del TOC le librerie vere e l'addon, ogni test su un client nuovo; filtro per nome,
  `-v`, `--long` (o `AZTW_LONG=1`). Il dump delle API, se c'è, serve a rifiutare i nomi di evento inesistenti
  (`AZTW_API_DUMP`; in CI non c'è).
- `lib/harness.lua` simula `/reload` e nuovo accesso: scrive e rilegge le SavedVariables dichiarate nel TOC e rifiuta
  ciò che il client non salva, valori segreti compresi; il mondo finto (tempo, unità, combattimento, threat) resta.
- `mock/`: un file per area, ognuno con le voci del dump che imita. I valori segreti del mock sono **più severi del
  client** (qualsiasi uso solleva un errore, ARC-11); `type()` ne restituisce il tipo rappresentato (**[verificare]**
  P3). Il mock non può intercettare `==` con un valore normale né un valore segreto usato come condizione.
- I numeri della threat calcolati dal mock (stato, percentuali, 110 %/130 %, margine) sono **ipotesi** fino al probe
  (P2–P6); le risposte si possono scriptare (valori, `nil`, nessun valore, segreto, errore). Il mock non decide chi fa
  da tank: lo dice lo script del combattimento (`lib/fight.lua`: threat, aggro, taunt, morti, mob che spariscono o
  cambiano GUID, secondo il tempo del client).


### 2.1 Gli script dei combattimenti (`Tests/lib/fight.lua`)

Il linguaggio di [ADR 0010](../adr/0010-offline-tests-with-lupa-and-a-mock-client.md) punto 4, costruito in M1.3 ed
esteso in M2.1 per i test del monitor ([SPEC-03 §6](SPEC-03-threat-monitor-ui.md#6-piano-di-m2-moduli-eventi-e-test-per-step)).
Un test lo vede come la globale `Fight`; guida solo il client finto.

```lua
local pull = Fight.new{
  player = { class = "MAGE", role = "DAMAGER", ranged = true },
  party  = { { key = "tank", class = "WARRIOR", role = "TANK" }, { key = "healer", class = "PRIEST" } },
  mobs   = { { key = "boss", tokens = { "target", "boss1" }, classification = "worldboss" } },
  raid   = false,
}
pull:at(0):outcome("state"):start():threat("boss", "tank", 1000)
pull:at(1.5):add("boss", "player", 400)
pull:to(1)       -- suona fino al secondo 1 (i timer del client girano nel frattempo)
pull:finish()    -- suona il resto
```

| Verbo | Effetto | Da |
|---|---|---|
| `start()`, `stop()` | inizio del combattimento; fine con le liste della threat svuotate | M1.3 |
| `threat(mob, unit, raw)`, `add(mob, unit, delta)`, `drop(mob, unit)` | threat raw di un'unità (o una tabella che fissa ogni valore restituito), aggiunta, uscita dalla lista; la prima unità con threat tiene il mob | M1.3 |
| `aggro(mob, unit)`, `taunt(mob, unit)` | il mob si gira; taunt = almeno la threat più alta, poi aggro | M1.3 |
| `die(key)`, `vanish(mob)`, `newGUID(mob [, guid])` | morte (lista svuotata o uscita dalle liste, `UNIT_DIED`); mob che scompare; stessa creatura dietro altri token senza evento | M1.3 |
| `token(token, key)`, `target(unit, key)` | token che nomina un'unità (`nameplate2`, `focus`, `boss2`); chi seleziona chi | M1.3 |
| `role(unit, role)` | ruolo assegnato (`TANK`, `HEALER`, `DAMAGER`, `NONE`) | M2.1 |
| `outcome(name)` | l'esito del probe da quel momento: `values` (nulla segreto), `state` (valori segreti, stato leggibile), `none` (anche lo stato segreto) | M2.1 |
| `secrets(changes)` | segretezza più fine (`Mock.secrets.Set`: per unità, previsioni che sbagliano, identità, confronti) | M2.1 |
| `answer(api, unit, mob, a)`, `clearAnswers()` | risposta scriptata di una funzione della threat (`Mock.threat.NIL`, `NOTHING`, `SECRET`, `ERROR`, `Returns(...)`); ritorno alle risposte calcolate | M2.1 |
| `silent(on)` | gli eventi della threat smettono di arrivare (eventi persi) o riprendono | M2.1 |
| `event(name, ...)` | un evento del gioco a mano: duplicato, in ritardo, fuori ordine | M2.1 |
| `call(fn)` | qualsiasi altra cosa, `fn(pull)` | M1.3 |

- `pull:at(t)` registra i passi (anche fuori ordine nel testo: si suonano in ordine di tempo, a pari tempo
  nell'ordine scritto); un tempo nel passato o un verbo sconosciuto sollevano un errore. Ogni verbo vale anche
  subito, senza `at`.
- `Fight.OUTCOMES` = `{ "values", "state", "none" }`: un test del monitor che deve valere qualunque sia l'esito del
  probe gira in un ciclo su questa lista e comincia lo scontro con `outcome(name)`; le risposte attese per esito sono
  in [SPEC-03 §1.1 e §2](SPEC-03-threat-monitor-ui.md#11-tre-esiti-del-probe-tre-modalità).
- Le regole del "server" sono quelle dello script e del mock (`Tests/mock/70_threat.lua`), **ipotesi** fino al probe.

## 3. Test lunghi

`Tests/run_tests.py --long` (workflow *Long tests*, scenari in `Tests/long/`): raid di 40 con molti mob per ore;
storico vicino al limite; sessioni lunghe; apertura e chiusura ripetuta del replay; misura delle allocazioni per tick.
Ogni voce arriva con il modulo che prova; M1.3 ne ha una sola, sul client finto: dieci minuti di raid da 40 con cinque
mob e un `/reload` a metà.

## 4. Prove nel client

Ogni milestone finisce con `docs/checklists/M<N>.md`, eseguita dal proprietario: interfaccia (risoluzioni, scale,
movimento, combattimento, UI personalizzate), prestazioni in party e raid, scenari funzionali. I risultati si
riportano con il modulo *In-game test report*.

## 5. Definition of Done dell'MVP (fonte §18)

- [ ] Client target identificato e documentato.
- [ ] Probe API completato.
- [ ] API usate verificate sul client.
- [ ] Threat Monitor funzionante in condizioni reali.
- [ ] Stati UNKNOWN e dati insufficienti gestiti.
- [ ] Avvisi configurabili e non invasivi.
- [ ] Nessun errore Lua nei test previsti.
- [ ] Prestazioni accettabili in party e raid.
- [ ] SavedVariables versionate e gestite.
- [ ] Configurazione che sopravvive a logout e reload.
- [ ] Documentazione con limiti e compatibilità.
- [ ] Pagina CurseForge che non promette funzioni non verificate.

## 6. Rilascio

Una versione per milestone, preparazione prima di ogni tag, interruttori per le parti non finite
([ADR 0014](../adr/0014-one-version-per-milestone-and-feature-switches.md)); procedura in `docs/RELEASING.md` (da M1).
