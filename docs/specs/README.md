# Azeroth Threatwarden: specifiche di progetto

Addon **non ufficiale** per **WoW: Forever** che aiuta a capire, monitorare e gestire la threat: chi genera threat su
quale mob, quanto manca a prendere l'aggro, avvisi prima che succeda, registrazione dei combattimenti e report che
distinguono ciò che è rilevato da ciò che è stimato.

- Stato: **Bozza 1** (2026-11-25), da rivedere dopo il probe M0; SPEC-01, SPEC-02 §3, SPEC-03 §4–§5 e `ui-style.md`
  completati in M1.1; SPEC-03 in M2.1; SPEC-04 in M3.1; SPEC-02 §3.7–§4 e SPEC-05 §1–§3 in M4.1; SPEC-05 §4–§5 e
  SPEC-02 §3.9 in M5.1; SPEC-06 in M6.1; SPEC-07 §0–§2 e SPEC-02 §3.10 in M7.1; SPEC-07 §3–§7, SPEC-08 §5–§10 e SPEC-02 §3.11 in M8.1 (le righe che aspettano il probe sono marcate **[probe Pn]**)
- Architettura in inglese, con i diagrammi: [docs/ARCHITECTURE.md](../ARCHITECTURE.md)
- Fonte: le [specifiche originali del proprietario](source-specification.md), che restano la fonte di verità su
  **cosa** fa l'addon; questi file le dettagliano e le collegano a roadmap e ADR
- Client di riferimento: WoW Forever `1.60.1`, `## Interface: 16001` ([ADR 0002](../adr/0002-wow-forever-target-and-api-dump.md))
- Distribuzione: GitHub Releases da `v0.1.0`, CurseForge dall'MVP `v0.4.0` ([ADR 0014](../adr/0014-one-version-per-milestone-and-feature-switches.md))
- Lingua dell'addon: inglese (predefinita) e italiano dalla `v0.1.0` ([ADR 0009](../adr/0009-interface-and-documentation-languages.md))
- Lingua di questi documenti: italiano; nomi di codice, API e testi dell'interfaccia in inglese

## Indice

| # | Documento | Contenuto | Milestone |
|---|---|---|---|
| 00 | [Visione, ambito e affidabilità dei dati](SPEC-00-vision-scope.md) | obiettivi e non-obiettivi, pubblico, categorie dei dati, funzioni per versione, registro delle decisioni | tutte |
| 01 | [Piattaforma e architettura](SPEC-01-platform-architecture.md) | vincoli del client, API dal dump, moduli con eventi e test, Bus, interruttori, librerie, Compat (API, capacità, lettura della threat), diagnostica, lingue | M1 |
| 02 | [Modello dati e salvataggio](SPEC-02-data-model-storage.md) | `ThreatRecord`, campioni, sessioni in colonne compatte, SavedVariables (schemi 1–7 dell'account e 1–3 del personaggio, con chiavi, tipi e predefiniti), migrazioni, dati danneggiati, limiti | M1–M4 |
| 03 | [Threat Monitor e interfaccia](SPEC-03-threat-monitor-ui.md) | stati SAFE/WARNING/DANGER/UNKNOWN, soglie, ordinamenti, finestra (disposizioni compatta e ampia), minimappa e Compartment, comandi, pagina Settings | M1, M2 |
| 04 | [Avvisi e Threat Coach](SPEC-04-alerts-coach.md) | canali, cooldown, regole, motivazione e confidenza | M3 |
| 05 | [Registrazione, report, timeline e replay](SPEC-05-recording-report-replay.md) | recorder, sessioni, report di fine combattimento, timeline, replay | M4, M5 |
| 06 | [Analytics ed esportazione](SPEC-06-analytics-export.md) | metriche descrittive per scontro (con le definizioni del report e ANA-02), confronto fra scontri con lo stesso nemico e aggregati, vista Analytics nella scheda Reports, esportazione testo e CSV in una casella da copiare, nomi sostituibili | M6 |
| 07 | [Multi-target, heatmap e profili](SPEC-07-multi-target-heatmap-profiles.md) | go condizionato di M7 prima del probe, altri mob letti a rotazione con un budget e chiavi dai GUID, portata che si riduce a *focus e boss* o al solo target, stato e rischio di ogni mob, barra del pull e lista del Dungeon Focus, clic che fissa il mob del monitor, avvisi sugli altri mob; heatmap delle righe e sovrapposizione staccata dei riquadri del raid, profili per ruolo copiati sulle impostazioni, tavolozze per il daltonismo e modalità dei segni (M8) | M7, M8 |
| 08 | [Qualità, probe e rilascio](SPEC-08-quality-probe-release.md) | probe M0 (P1–P12), test offline e lunghi, prove nel client, Definition of Done voce per voce, `v0.8.0` e `v1.0.0`, traduzioni, budget finali, pagina CurseForge e limiti, checklist di rilascio | M0, tutte |
| 09 | [Rischi e domande aperte](SPEC-09-risks-open-questions.md) | rischi R1…, domande per il proprietario Q1… con risposta proposta | tutte |
| — | [Stile dell'interfaccia](ui-style.md) | differenze da Accord: nomi, finestra compatta, barre della threat, token di stato, tema Warden con i contrasti | M1, M2 |
| — | [Anteprime di progetto](mockups/README.md) | immagini dell'interfaccia (non screenshot), generate da `tools/make_mockups.py` | M1 → |
| — | [Specifiche originali](source-specification.md) | il documento del proprietario, invariato | — |

Ogni milestone dalla M1 si apre con uno step di specifica (`M<N>.1`) che completa le sezioni marcate **[da
completare in M<N>.1]** e aggiunge, quando serve, `ui-style.md` e i mockup.

## Convenzioni

- **MUST / SHOULD / MAY**: obbligatorio / raccomandato / facoltativo.
- Le API marcate **[verificare]** non compaiono nel dump oppure il loro comportamento su Forever non è ancora stato
  osservato: le conferma il probe M0 ([SPEC-08 §1](SPEC-08-quality-probe-release.md#1-probe-m0)).
- Ogni requisito ha un identificativo (`DAT-xx`, `ARC-xx`, `MON-xx`, `ALR-xx`, `COA-xx`, `REC-xx`, `RPL-xx`, `ANA-xx`,
  `MT-xx`, `QA-xx`, `PRB-xx` per il probe) da citare in issue, PR e test.
- Ogni dato mostrato appartiene a una categoria (rilevato, calcolato, stimato, previsto, ipotesi):
  [SPEC-00 §4](SPEC-00-vision-scope.md#4-affidabilità-dei-dati-vincolante), [ADR 0003](../adr/0003-data-reliability-categories.md).
- Le decisioni definitive si registrano come ADR in [`docs/adr/`](../adr/README.md); le domande aperte in
  [SPEC-09](SPEC-09-risks-open-questions.md).
