# SPEC-08: Qualità, probe e rilascio

> Fonte: [specifiche originali](source-specification.md) §8, §12, §13, §18.
> §5.1 e §6–§10 (Definition of Done voce per voce, `v0.8.0` e `v1.0.0`, traduzioni, prestazioni, CurseForge e
> limiti, checklist di rilascio) completati in **M8.1** (2026-11-28).

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
Ogni voce arriva con il modulo che prova.

| File | Da | Cosa prova |
|---|---|---|
| `test_raid.lua` | M1.3 | il client finto da solo: dieci minuti di raid da 40 con cinque mob e un `/reload` a metà |
| `test_monitor_raid.lua` | M2.7 | la pipeline intera (Scanner → Model → Calc → State → elenco, con la finestra) in un raid da 40: un mob per 30 minuti a 2, 5 e 10 Hz con morti dei tank; boss e quattro add per due ore a 10 Hz con un nuovo bersaglio ogni pochi secondi, morti di tank e add e i tre esiti del probe; stati che oscillano attorno alle soglie. A ogni tick le regole di SPEC-03 §2 (salite immediate, discese trattenute), mai una discesa prima di 1 s; pool, frame, registro dei colori e memoria che smettono di crescere |
| `test_monitor_budget.lua` | M2.7, M4.6 | il costo di un tick con 40 unità e la finestra, a 2, 5 e 10 Hz, su un mob e con cambi di bersaglio, con tre insiemi di interruttori (monitor solo; con avvisi e Coach; da M4.6 anche con la registrazione aperta): tre misure deterministiche con un budget ciascuna. Da M4.6 anche il tick di registrazione da solo nei tre esiti: istruzioni in media (36 000) e nel tick peggiore (90 000), byte per tick (1 024 con i valori, 48 altrimenti) ([SPEC-01 §5.1](SPEC-01-platform-architecture.md#51-il-costo-di-un-tick-del-monitor-misura-offline-di-m27)) |
| `test_recorder_raid.lua` | M4.6 | la registrazione in un raid da 40 con la finestra chiusa: un'ora di combattimenti con pull a catena, morti e i tre esiti, con lo storico al limite; i limiti di una sessione raggiunti (righe, eventi, unità, mob, tempo) e nulla che cresca dopo; 150 chiusure ai limiti di numero, di dimensione e di entrambi; 40 `/reload` (in combattimento e durante `END_DELAY`); la scheda Reports e i report di 38 unità aperti e chiusi più di 150 volte, anche in combattimento con la potatura. Sempre: nessun errore; pezzi, storico, righe e card riusate e memoria che smettono di crescere |

Il raid simulato è `Tests/lib/raid.lua` (globale `Raid`): costruisce il raid con uno script di combattimento e
sostituisce le funzioni della threat con risposte calcolate una volta per passo, senza allocazioni, così che si misuri
l'addon; le regole restano **ipotesi** fino al probe. Le tre misure del budget: **lavoro**, istruzioni della VM per
tick (`T.instructions`, uguale su ogni macchina); **allocazioni**, crescita dello stato Lua per tick con il garbage
collector fermo, il minimo di tre blocchi dopo una raccolta completa e un riscaldamento (i setter dei widget del mock
che allocano scrivono sul posto); **tempo**, `os.clock` per tick in rapporto a un ciclo di riferimento fisso eseguito
a turno, la mediana di sette blocchi.

## 4. Prove nel client

Ogni milestone finisce con `docs/checklists/M<N>.md`, eseguita dal proprietario: interfaccia (risoluzioni, scale,
movimento, combattimento, UI personalizzate), prestazioni in party e raid, scenari funzionali. I risultati si
riportano con il modulo *In-game test report*.
M8 ne ha due: `docs/checklists/M8.md` e `docs/checklists/release.md`, il controllo completo prima della `v1.0.0`
(§10).

## 5. Definition of Done dell'MVP (fonte §18)

Stato voce per voce (fatta, aperta o in attesa del proprietario), aggiornato in M4.7:
[checklist M4 §12](../checklists/M4.md#12-mvp-check). Le caselle qui sotto si spuntano quando la voce è chiusa.

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

### 5.1 Come si chiude ogni voce (M8.1)

Fissato in **M8.1** (2026-11-28) per la `v1.0.0` (§6.2). Una voce si spunta solo quando **tutte** le sue prove sono
fatte; *offline* vuol dire i test con il client finto, *nel gioco* il probe o una checklist eseguiti dal proprietario.
Stato al 2026-11-28: il probe M0 e le checklist M1–M7 **non sono stati eseguiti**, quindi nessuna voce che chiede il
gioco è chiusa.

| Voce | Offline (chi la chiude) | Nel gioco (chi la chiude) | Stato al 2026-11-28 |
|---|---|---|---|
| Client target identificato e documentato | ADR 0002, SPEC-01 §1 dal dump (build 70170, interfaccia 16001) | P1 del probe; `docs/spike/M0-results.md` (M0.7) | **aperta**: solo il dump |
| Probe API completato | lo strumento esiste (`tools/probe/`, M0.2–M0.6) | P1–P12 eseguiti e M0.7 | **aperta** (in attesa del proprietario) |
| API usate verificate sul client | ogni API controllata sul dump (`test_api_boundary.lua`, Compat) | P1–P12, `/atw debug` nella checklist di rilascio §10 | **aperta** |
| Threat Monitor funzionante in condizioni reali | `test_threat_*`, test lunghi | checklist M2 e la sezione *Monitor* di `release.md` | **aperta** |
| Stati UNKNOWN e dati insufficienti gestiti | i tre esiti in ogni test (`Fight.OUTCOMES`), report e analytics | P3 e le checklist M2, M4, M6 | **offline fatta**, nel gioco aperta |
| Avvisi configurabili e non invasivi | `test_alerts.lua`, `test_settings.lua` | checklist M3 | **offline fatta**, nel gioco aperta |
| Nessun errore Lua nei test previsti | ogni test (`run_tests.py`, anche `--long`) senza errori, CI | checklist di rilascio: errori del gioco visibili e l'anello di `/atw debug` vuoto dopo ogni sezione | **offline fatta**, nel gioco aperta |
| Prestazioni accettabili in party e raid | budget offline (§8, SPEC-01 §5.1) | P10, checklist M2, M4, M7, M8 | **aperta**: solo stime offline |
| SavedVariables versionate e gestite | schemi, migrazioni con test (DAT-20), dati danneggiati, sola lettura | checklist di rilascio: aggiornamento da un salvataggio vecchio | **offline fatta**, nel gioco aperta |
| Configurazione che sopravvive a logout e reload | l'harness simula `/reload` e nuovo accesso | checklist M1, M4 (P12) | **offline fatta**, nel gioco aperta |
| Documentazione con limiti e compatibilità | pagina del manuale *Limits and Compatibility* e README (M8.7, §9) | — (la scrive M8.7; il proprietario la rilegge dopo il probe) | aperta fino a M8.7 |
| Pagina CurseForge che non promette funzioni non verificate | `docs/curseforge.md` (M8.7, §9) | il proprietario la pubblica dopo il probe e le checklist | aperta fino a M8.7; pubblicazione del proprietario |

## 6. Rilascio

Una versione per milestone, preparazione prima di ogni tag, interruttori per le parti non finite
([ADR 0014](../adr/0014-one-version-per-milestone-and-feature-switches.md)); procedura in `docs/RELEASING.md` (da M1).

### 6.1 `v0.8.0` (M8.R, prima parte)

Branch `chore/release-v0.8.0`, come M2.R–M7.R: interruttori `profiles`, `heatmap` e `accessibility` accesi (Q28–Q30),
`SHIPPED_ON` di `test_features.lua` aggiornato, changelog promosso a `0.8.0`, stato di README e manuale, bozza
CurseForge (§9), prova a vuoto del workflow *Release* (anche `--long`), poi il tag annotato `v0.8.0` (approvazione
permanente del proprietario per i tag di milestone) e la GitHub Release. CurseForge solo con il progetto e il segreto
del proprietario (Q6). Le note della versione dicono che nulla è stato provato nel gioco.

### 6.2 `v1.0.0` (M8.R, seconda parte)

Che cosa chiede la `v1.0.0`:

1. **ADR 0014 punto 3**: ogni milestone del piano fatta e il **controllo di rilascio completo** passato
   (`docs/checklists/release.md`, §10). Il controllo completo è in gran parte nel gioco.
2. **§5**: le dodici voci della Definition of Done chiuse; otto chiedono il gioco (§5.1).
3. **RELEASING**: `v1.0.0` non è un tag di milestone `v0.<N>.0`, quindi non ha l'approvazione permanente: si chiede
   prima al proprietario.
4. Nulla nel piano oltre a M8; le idee del proprietario per dopo la `v1.0.0` restano fuori (non sono nel piano).

**Se il probe e le checklist non sono stati eseguiti** quando M8.R arriva (com'è oggi), la `v1.0.0` direbbe *pronta*
per un addon che nessuno ha provato nel client vero. È una scelta del proprietario: domanda
[Q31](SPEC-09-risks-open-questions.md), con la risposta proposta che il piano applica finché non decide:

- M8.R rilascia la `v0.8.0` e **prepara** la `v1.0.0` in `chore/release-v1.0.0` (changelog `1.0.0` pronto, stato,
  manuale e bozza CurseForge con l'elenco esplicito di ciò che **non è verificato nel gioco**, la checklist di rilascio
  con l'esito *not run*), ne fa la prova a vuoto, **non** crea il tag e lascia la pull request aperta con la domanda
  (`tools/ship_step.py --no-merge`: `main` non dice `1.0.0` senza il tag);
- il tag `v1.0.0` si crea quando il proprietario risponde: dopo aver eseguito almeno il probe (P1–P12) e la checklist
  di rilascio, oppure dicendo di rilasciarla lo stesso con le note *not verified in the game*;
- nel frattempo M8 è finita nel codice e la `v0.8.0` è l'ultima versione; eventuali correzioni sono `v0.8.1`…

**Cosa resta esplicitamente *non verificato nel gioco*** se il proprietario sceglie di rilasciare senza prove (va nelle
note della versione, nel README, nella pagina *Limits and Compatibility* e nella bozza CurseForge): tutte le voci di
§5.1 con *nel gioco aperta*; le domande del probe P1–P12 e ciò che cambiano (SPEC-07 §0, SPEC-03 §1.1); le soglie
82/91 tarate a occhio dal proprietario ma non misurate con il client (P4); i costi (P10); le ipotesi del client finto
(il calcolo della threat, i valori segreti, i riquadri del raid); il taint della sovrapposizione (SPEC-07 §3.3).

## 7. Traduzioni e controlli delle lingue (M8.5)

Fissato in **M8.1**; vale [ADR 0009](../adr/0009-interface-and-documentation-languages.md) (inglese predefinito,
italiano completo, una lingua per file).

- **LOC-01** MUST: una lingua nuova è **un file** `Locales/<codice>.lua` (`ns.Locale.Register("<codice>", { … })`) più
  **una riga** nel TOC; nient'altro da toccare. Per questo M8.5 fa derivare l'elenco delle lingue che si possono scegliere
  (`Config.LANGUAGES`) dalle tabelle registrate (più `auto`), e ogni file porta il nome della sua lingua nella sua
  lingua (chiave `LANGUAGE_NAME`, per esempio *Deutsch*) che la card *Language* mostra.
- **LOC-02** MUST: `enUS` è la base e `itIT` è **completo** (gli stessi tasti, come oggi); una lingua aggiunta da un
  traduttore può essere **parziale**: le chiavi che mancano cadono sull'inglese (come già fa `ns.L`), e
  `tools/check_addon.py` le conta come avviso, non come errore.
- **LOC-03** MUST (`tools/check_addon.py`): in ogni traduzione gli stessi segnaposto della stringa inglese, nello
  stesso ordine (`%s`, `%d`, `%.1f`, `%%`…); nessuna chiave che l'inglese non ha; nessun codice di colore (`|c`, `|r`)
  né di texture (`|T`) dentro le stringhe (i colori sono di `UI/Theme.lua`); nessuna stringa vuota.
- **LOC-04** MUST (`Tests/test_ui_texts.lua`, `test_coach_wording.lua`): per ogni lingua presente, le parole dei
  distintivi di stato, delle schede compatte e dei segni (SPEC-07 §5.3) entrano alla dimensione minima; le regole di
  scrittura del Coach (COA-04: nessun nome di classe o di abilità, solo il generico *rank più bassi*) valgono in ogni
  lingua per le chiavi `COACH_*` e `ALERT_*`.
- **La guida** `docs/wiki/Translating.md` e `Translating-it.md` (bilingue come ogni pagina): dove sono le stringhe,
  come si copia `enUS.lua`, i segnaposto, il tono (SPEC-00 §6) e le regole del Coach, le parole del gioco da tenere come
  le scrive il client della lingua (*Threat*, *Aggro* possono restare), come si provano i controlli
  (`python -I -X utf8 tools/check_addon.py`, `python -X utf8 Tests/run_tests.py test_ui_texts`), come si prova nel
  gioco (*Language* nella card, `/reload`), come si propone (pull request con il DCO, nessun dato personale, licenza
  GPL-3.0); che il manuale resta in inglese e italiano.

## 8. Passata finale di prestazioni e memoria (M8.6)

Fissato in **M8.1**. Le misure sono **offline** (istruzioni della VM, allocazioni, tempo relativo; §3) e dicono se una
versione costa più dell'altra, non quanto costa nel gioco; il budget nel gioco resta quello proposto per P10 (≤ 1 ms
per tick al p95, ≤ 5 ms al secondo in totale, Q14). M8.6 rimisura tutto con gli interruttori di M8 accesi e scrive i
numeri in SPEC-01 §5.1.

| Misura (offline) | Budget | Da |
|---|---|---|
| Tick del monitor, 40 unità, finestra aperta: lavoro | ≤ 220 000 istruzioni | SPEC-01 §5.1 |
| — allocazioni: solo monitor / con avvisi e Coach / con la registrazione | ≤ 48 / 160 / 1 200 byte | SPEC-01 §5.1 |
| — tempo | ≤ 30 cicli di riferimento | SPEC-01 §5.1 |
| Lo stesso con il calore delle righe e la sovrapposizione accesi (M8.3) | gli stessi budget; il calore aggiunge al più **8 000** istruzioni per tick (circa il 5 %), la sovrapposizione al più **15 000** e **0** byte dopo il riscaldamento | nuovo (M8.1) |
| Tick di registrazione (40 unità) | 36 000 in media, 90 000 nel peggiore, 1 024 byte con i valori, 48 altrimenti | SPEC-01 §5.1 |
| Tick dei mob con la lista | non oltre il tick del monitor con 40 unità; M8.6 cerca di riportare il margine ad almeno il **5 %** (oggi circa il 2 %) senza cambiare le costanti di Q26 | ADR 0019, M7.4 |
| Lavoro in un solo frame fuori dai tick (clic, apertura di un report o di un replay) | ≤ **1 000 000** istruzioni per frame: oltre si spezza su più frame (ARC-07). Oggi la decodifica di una registrazione al limite (30 000 righe, circa 6 milioni) non regge: M8.6 la spezza | nuovo (M8.1) |
| Memoria | nei test lunghi (raid da 40 per due ore, replay aperto e chiuso, export, Dungeon Focus) la memoria Lua dopo il riscaldamento non cresce (pool, registro dei colori, cache); M8.6 scrive la memoria dell'addon dopo il caricamento e con 25 sessioni | §3 |
| SavedVariables | la stima di `Config.EstimateSize` resta sotto `maxKB` (2 MB) con lo storico pieno, profili compresi | Q8 |

- Un numero oltre il budget fa fallire il test; M8.6 non alza un budget senza scriverlo qui e in SPEC-01 §5.1 con il
  perché.
- **[da provare in gioco]** P10 e la checklist di rilascio (§10): FPS e `/atw debug` (tempo per tick misurato da
  `Scheduler`) in party e in un raid da 40, con e senza la sovrapposizione dei riquadri.

## 9. Pagina CurseForge e documentazione dei limiti (M8.7)

Fissato in **M8.1**; vale la fonte §16 e §18 (*non dichiarare compatibilità con versioni diverse da quella
effettivamente testata*; *la pagina non promette funzioni non verificate*).

- **`docs/curseforge.md`** per la `v0.8.0` e la `v1.0.0`: titolo (Q17), sommario, l'elenco delle funzioni con i
  profili, la heatmap e l'accessibilità, ognuna con ciò che dipende dal gioco; *Limits*; la tabella *What is verified*
  onesta (oggi: offline sì, nel gioco **not yet** per ogni riga, il probe **not run**); *Privacy*; nessuno screenshot
  che non venga dal gioco (le anteprime del repository non sono screenshot, ADR 0013); le caselle *Before publishing*
  per il proprietario (progetto, `CF_API_KEY`, versione del gioco **WoW Forever** fra le scelte, probe e checklist).
- **Pagina del manuale *Limits and Compatibility*** (`docs/wiki/Limits-and-Compatibility.md` e `-it.md`, nella barra
  laterale): il client (WoW Forever, interfaccia 16001, la build del dump; nessun'altra versione dichiarata), che
  cosa l'addon legge e che cosa no (valori segreti, *state only*, il target soltanto), che cosa dipende dal probe
  (P1–P12 in parole semplici), che cosa non è verificato nel gioco (la tabella di §5.1), gli altri addon (autonomo;
  la sovrapposizione disegna solo sui riquadri di Blizzard, SPEC-07 §3.3), le prestazioni (solo stime offline),
  privacy e dati (rimando a *Privacy and Data*).
- **README** (`README.md`, `README.it.md`): stato e limiti in breve con il rimando alla pagina.
- Nessuna frase dice *tested*, *works in raids*, *compatible with* senza una checklist eseguita che lo provi;
  `tools/check_docs.py` non può controllarlo: lo controlla chi rivede la pull request.

## 10. Checklist M8 e checklist di rilascio completa (M8.8)

Fissato in **M8.1**. Due file, scritti da M8.8 e eseguiti dal proprietario:

- **`docs/checklists/M8.md`**, la checklist della milestone come M1–M7: interruttori accesi nella copia installata
  mentre sono spenti, salvataggio di sicurezza; profili (ruolo dal cercatore, gruppo a mano con `NONE`, cambio in
  combattimento che arriva dopo, scelta a mano che resta, copia e reset, aggiornamento da un salvataggio della
  `v0.7.0`); heatmap delle righe nei tre temi e nelle tre tavolozze; la sovrapposizione dei riquadri del raid in party e
  in un raid da 40, alle scale comuni, dopo un cambio del roster, con `/console taintLog 1` acceso dal proprietario e il
  file `Logs/taint.log` letto dopo, e gli `ADDON_ACTION_BLOCKED` di `/atw debug`; le modalità dei segni alla
  dimensione minima e in italiano; una lingua di prova (un file parziale) per la guida delle traduzioni; le note per
  Q28–Q30.
- **`docs/checklists/release.md`**, il controllo completo prima della `v1.0.0` (ADR 0014 punto 3): lo zip della
  GitHub Release installato in una cartella pulita (solo `AzerothThreatwarden/`, `## Version`, nessuna riga di
  sviluppo); dati nuovi e dati vecchi (un salvataggio di una versione precedente, con una copia di sicurezza) che
  migrano allo schema 7 e 3; il probe P1–P12 eseguito (o scritto *not run*); le checklist M1–M8 eseguite, con i
  risultati nel modulo *In-game test report*; le dodici voci di §5.1 una per una, con la prova che le chiude; le
  prestazioni (P10) in party e raid; nessun errore Lua (gli errori del gioco visibili, l'anello di `/atw debug`);
  il taint; le due lingue; la pagina CurseForge e *Limits and Compatibility* rilette contro ciò che le checklist hanno
  mostrato; l'esito: **go** o **no-go** per la `v1.0.0`, che risponde a Q31.
