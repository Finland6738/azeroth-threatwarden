# Azeroth Threatwarden: specifiche di progetto

Addon **non ufficiale** per **WoW: Forever** che aiuta a capire, monitorare e gestire la threat: chi genera threat su
quale mob, quanto manca a prendere l'aggro, avvisi prima che succeda, registrazione dei combattimenti e report che
distinguono ciò che è rilevato da ciò che è stimato.

- Stato: **Bozza 1** (2026-11-25), da rivedere dopo il probe M0
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
| 01 | [Piattaforma e architettura](SPEC-01-platform-architecture.md) | vincoli del client, API dal dump, moduli, librerie, Compat, prestazioni, privacy | M1 |
| 02 | [Modello dati e salvataggio](SPEC-02-data-model-storage.md) | `ThreatRecord`, campioni, sessioni, SavedVariables, schema e migrazioni, limiti | M1, M4 |
| 03 | [Threat Monitor e interfaccia](SPEC-03-threat-monitor-ui.md) | stati SAFE/WARNING/DANGER/UNKNOWN, soglie, ordinamenti, finestra, configurazione | M1, M2 |
| 04 | [Avvisi e Threat Coach](SPEC-04-alerts-coach.md) | canali, cooldown, regole, motivazione e confidenza | M3 |
| 05 | [Registrazione, report, timeline e replay](SPEC-05-recording-report-replay.md) | recorder, sessioni, report di fine combattimento, timeline, replay | M4, M5 |
| 06 | [Analytics ed esportazione](SPEC-06-analytics-export.md) | metriche descrittive, confronto tra scontri, esportazione testo e CSV | M6 |
| 07 | [Multi-target, heatmap e profili](SPEC-07-multi-target-heatmap-profiles.md) | più mob, dungeon focus, heatmap, profili per ruolo | M7, M8 |
| 08 | [Qualità, probe e rilascio](SPEC-08-quality-probe-release.md) | probe M0 (P1–P12), test offline e lunghi, prove nel client, Definition of Done | M0, tutte |
| 09 | [Rischi e domande aperte](SPEC-09-risks-open-questions.md) | rischi R1…, domande per il proprietario Q1… con risposta proposta | tutte |
| — | [Specifiche originali](source-specification.md) | il documento del proprietario, invariato | — |

Ogni milestone dalla M1 si apre con uno step di specifica (`M<N>.1`) che completa le sezioni marcate **[da
completare in M<N>.1]** e aggiunge, quando serve, `ui-style.md` e i mockup.

## Convenzioni

- **MUST / SHOULD / MAY**: obbligatorio / raccomandato / facoltativo.
- Le API marcate **[verificare]** non compaiono nel dump oppure il loro comportamento su Forever non è ancora stato
  osservato: le conferma il probe M0 ([SPEC-08 §1](SPEC-08-quality-probe-release.md#1-probe-m0)).
- Ogni requisito ha un identificativo (`DAT-xx`, `ARC-xx`, `MON-xx`, `ALR-xx`, `COA-xx`, `REC-xx`, `RPL-xx`, `ANA-xx`,
  `MT-xx`, `QA-xx`) da citare in issue, PR e test.
- Ogni dato mostrato appartiene a una categoria (rilevato, calcolato, stimato, previsto, ipotesi):
  [SPEC-00 §4](SPEC-00-vision-scope.md#4-affidabilità-dei-dati-vincolante), [ADR 0003](../adr/0003-data-reliability-categories.md).
- Le decisioni definitive si registrano come ADR in [`docs/adr/`](../adr/README.md); le domande aperte in
  [SPEC-09](SPEC-09-risks-open-questions.md).
