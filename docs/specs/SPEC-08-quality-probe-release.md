# SPEC-08: Qualità, probe e rilascio

> Fonte: [specifiche originali](source-specification.md) §8, §12, §13, §18.

## 1. Probe M0

Un addon usa e getta, `AzTw_Probe`, in `tools/probe/`, **mai distribuito**: ogni chiamata in `pcall`, nessun nome di
giocatore o gilda stampato o salvato (solo segnaposto `<player 1>`, conteggi e tipi), comandi `/atwp`, risultati in
`AzTw_ProbeDB` con un'esportazione testuale da copiare. Per ogni controllo il report dice: API presente o assente,
parametri accettati, valori restituiti (tipo, intervallo, segreto o no), quando restituisce `nil`, il test fatto, la
conclusione **supportato / parzialmente / non supportato**.

| # | Domanda | Contesti | Cambia |
|---|---|---|---|
| P1 | Versione del client, `GetBuildInfo`, progetto, interfaccia dichiarata | — | SPEC-01 §1, ADR 0002 |
| P2 | Presenza e firma di `UnitDetailedThreatSituation`, `UnitThreatSituation`, `UnitThreatPercentageOfLead`, `UnitThreatLeadSituation`; valori su un mob da solo | solo | SPEC-01 §2, SPEC-03 |
| P3 | **Valori segreti**: `ShouldUnitThreatValuesBeSecret`, `ShouldUnitThreatStateBeSecret`, `issecretvalue` sui risultati | solo, party, dungeon, raid, in e fuori combattimento | ADR 0004, tutto il piano |
| P4 | Il server calcola la threat in modo standard? (rapporti 110 % / 130 %, tank e DPS su un manichino o un mob) | party | SPEC-03 §2 |
| P5 | Unità interrogabili: membri del gruppo e loro target, `focus`, `mouseover`, `boss1–5`, `nameplateN`; mob non selezionati | party, dungeon | SPEC-07 |
| P6 | Eventi `UNIT_THREAT_LIST_UPDATE` e `UNIT_THREAT_SITUATION_UPDATE`: unità del payload, frequenza, ritardo | party, dungeon | ADR 0004 |
| P7 | Eventi di combattimento: `COMBAT_LOG_EVENT_UNFILTERED` è leggibile? `PLAYER_REGEN_*`, `UNIT_TARGET`, `ENCOUNTER_*`, morti, taunt (`UNIT_SPELLCAST_SUCCEEDED` sul gruppo) | party, dungeon, raid | SPEC-05 §1 |
| P8 | `C_DamageMeter`: disponibile? morti e durata delle sessioni utilizzabili? | dungeon | SPEC-05 |
| P9 | GUID e ruoli: `UnitGUID`, `UnitGroupRolesAssigned` segreti in istanza? stabilità del GUID di un mob | dungeon, raid | SPEC-02 |
| P10 | Costo del campionamento: ms per tick a 2, 5 e 10 Hz con 5, 10 e 40 unità; memoria per minuto di campioni | raid o simulato | ARC-08, Q14 |
| P11 | Restrizioni: blocchi o errori `ADDON_ACTION_BLOCKED`, limiti di frequenza, comportamento in combattimento e in campo di battaglia | tutti | SPEC-01 |
| P12 | `/reload` e logout durante un combattimento: cosa resta in `AzTw_ProbeDB` | solo | SPEC-05 §1 |

**Gate di progetto**: niente Threat Replay completo né multi-target promessi finché il probe non dimostra che i dati
sono ottenibili. M0.7 scrive `docs/spike/M0-results.md`, la matrice delle funzioni supportate e la decisione sul
perimetro, e aggiorna specifiche, ADR e roadmap.

## 2. Test offline

- **QA-01** MUST: `python -I -X utf8 tools/check_docs.py` passa sempre.
- **QA-02** MUST (da M1.3): `python -X utf8 Tests/run_tests.py` con lupa e il client finto
  ([ADR 0010](../adr/0010-offline-tests-with-lupa-and-a-mock-client.md)); ogni step aggiunge test per ciò che costruisce.
- **QA-03** MUST: scenari della fonte §13 come test con scontri scriptati: giocatore solo; party; raid; tank stabile;
  DPS che si avvicina alla soglia; cambio target; target che muore; più mob; taunt; morte del tank; morte di un DPS;
  fine combattimento; logout o reload durante e dopo una sessione; API che restituisce `nil`; unità non accessibile;
  GUID non disponibile; campioni mancanti; eventi doppi o fuori ordine; mob che scompare; target sostituito; valori
  segreti.

## 3. Test lunghi

`Tests/run_tests.py --long` (workflow *Long tests*): raid di 40 con molti mob per ore; storico vicino al limite;
sessioni lunghe; apertura e chiusura ripetuta del replay; misura delle allocazioni per tick.

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
