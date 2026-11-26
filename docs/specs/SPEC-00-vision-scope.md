# SPEC-00: Visione, ambito e affidabilità dei dati

> Fonte: [specifiche originali](source-specification.md) §1–§4, §14–§16, §20.

## 1. Visione

Azeroth Threatwarden aiuta a **capire, monitorare e gestire la threat** in WoW Forever durante combattimenti, dungeon
e raid. Non è un clone di Omen: trasforma i dati di threat in **informazioni operative**.

- mostra chi genera threat e su quale unità;
- avvisa **prima** che un giocatore rischi di prendere l'aggro;
- spiega, quando i dati lo consentono, come si è arrivati a una perdita di aggro, senza inventare cause;
- registra gli scontri per rivederli dopo il combattimento;
- produce report comprensibili per DPS, tank e raid leader.

**Promessa:** *Know your threat. Understand your mistakes. Prevent aggro loss.*

**Principio guida:** mostrare chiaramente ciò che è noto, distinguendolo da stime, previsioni e ipotesi (§4).

## 2. Pubblico

| Chi | Cosa cerca |
|---|---|
| Tank | stabilità della threat, margine sui DPS, chi sta per strappare il mob |
| DPS | quanto può spingere prima di superare il tank |
| Healer e support | capire i cambi di target e la threat da cure |
| Raid leader e ufficiali | analizzare wipe e problemi ricorrenti, senza classifiche accusatorie |
| Gruppi di dungeon | pull con più mob ([SPEC-07](SPEC-07-multi-target-heatmap-profiles.md), se il client lo consente) |

## 3. Obiettivi e non-obiettivi

**Obiettivi** (§2.1 della fonte): monitor live leggibile e configurabile; rischio di aggro con soglie e avvisi
contestuali; registrazione di campioni ed eventi; revisione degli scontri; statistiche senza cause non dimostrate;
interfaccia leggera adatta al combattimento; compatibilità con il client di Forever senza API non verificate.

**Non-obiettivi della prima versione** (§2.2): sostituire il combat log; ricostruire ogni punto di threat se il client
non lo espone; rotazioni o consigli di classe completi; analisi automatica delle meccaniche dei boss; servizi esterni,
account o backend; invio di dati a server remoti ([ADR 0001](../adr/0001-local-only-addon-no-network.md)); replicare
WeakAuras.

## 4. Affidabilità dei dati (vincolante)

Ogni informazione mostrata, registrata o riportata appartiene a una categoria
([ADR 0003](../adr/0003-data-reliability-categories.md)):

| Categoria | Codice (`source`) | Significato | Esempio | Come si mostra |
|---|---|---|---|---|
| Rilevata | `detected` | letta da API o evento | il target corrente è il boss | valore pieno |
| Calcolata | `calculated` | derivata da dati rilevati | percentuale rispetto al tank | valore pieno |
| Stimata | `estimated` | approssimazione da campioni incompleti | trend negli ultimi secondi | prefisso `~`, tooltip "Estimate" |
| Prevista | `predicted` | proiezione del trend, non certezza | possibile superamento tra 3 s | icona di previsione, testo "may" |
| Ipotesi | `hypothesis` | interpretazione non dimostrabile | burst probabilmente legato all'aumento | testo "probably", mai come causa |

- **DAT-01** MUST: nessuna stima o ipotesi è presentata come dato certo.
- **DAT-02** MUST: se una funzione non è supportata o i dati mancano, si mostra uno stato esplicito: **Unknown**
  (*Sconosciuto*), **Not available** (*Non disponibile*), **Insufficient data** (*Dati insufficienti*). Mai un valore
  inventato.
- **DAT-03** MUST: un **valore segreto** del client (`issecretvalue`) è trattato come *non disponibile* e conta come
  tale in registrazioni e statistiche.
- **DAT-04** MUST: ogni valore conserva la propria categoria anche nelle registrazioni e nei report
  ([SPEC-02](SPEC-02-data-model-storage.md)).

## 5. Funzioni per versione

L'MVP è **M1–M4** (risposta del proprietario a [Q3](SPEC-09-risks-open-questions.md), 2026-11-25). Una versione per
milestone ([ADR 0014](../adr/0014-one-version-per-milestone-and-feature-switches.md)); il dettaglio degli step è in
[docs/roadmap](../roadmap/README.md).

| Versione | Milestone | Contenuto | Spec |
|---|---|---|---|
| — | M0 Probe | verifica delle API nel client vero, matrice delle funzioni supportate | SPEC-08 §1 |
| `v0.1.0` | M1 Fondamenta | scheletro, test, Compat, Config, lingue, stile dell'ecosistema, finestra, impostazioni, crediti, `/atw debug` | SPEC-01, 02, 03 §4 |
| `v0.2.0` | M2 Threat Monitor | threat sul target, tank, percentuali, stati, trend, ordinamenti | SPEC-03 |
| `v0.3.0` | M3 Avvisi e Coach | soglie, canali, cooldown, regole con motivazione e confidenza | SPEC-04 |
| `v0.4.0` | M4 Registrazione e report (**MVP**) | sessioni, campioni, eventi, limiti, report di fine combattimento | SPEC-05 §1–3 |
| `v0.5.0` | M5 Timeline e Replay | grafico nel tempo, riproduzione, eventi | SPEC-05 §4–5 |
| `v0.6.0` | M6 Analytics ed export | metriche, confronto, esportazione | SPEC-06 |
| `v0.7.0` | M7 Multi-target | più mob e dungeon focus, **solo se M0 lo consente** | SPEC-07 §1–2 |
| `v0.8.0` → `v1.0.0` | M8 Profili, heatmap, rifinitura | preset per ruolo, heatmap, accessibilità, traduzioni, pagina CurseForge | SPEC-07 §3–4 |

## 6. Nome, tono e identità

- Nome: **Azeroth Threatwarden**; cartella `AzerothThreatwarden`; comandi `/threatwarden` e `/atw` (Q1).
- Tono: fantasy, autorevole, chiaro, non troppo tecnico. Termini dell'interfaccia: *Threat, Aggro, Safe, Warning,
  Danger, Threat Margin, Threat Replay, Combat Report*.
- Logo: lo scudo runico con il bagliore verde menta fornito dal proprietario (`assets/logo-source.webp`); colori di
  stato verde (SAFE), ambra (WARNING), rosso (DANGER), grigio-blu (UNKNOWN) ([ADR 0015](../adr/0015-interface-follows-the-ecosystem-style.md)).
- Crediti: *Created and designed by Finland. Made with the Italian guild NEBULA.* con i loghi NEBULA (Q4).
- Nessun asset copiato da Omen o da altri addon.
- Titolo CurseForge proposto: **Azeroth Threatwarden — Threat Meter, Coach & Combat Replay**; descrizione breve e
  parole chiave come nella fonte §16, **senza promettere funzioni non verificate** né versioni diverse da quella provata.

## 7. Registro delle decisioni

| # | Decisione | Data | Dove |
|---|---|---|---|
| D1 | Nomi tecnici `AzerothThreatwarden`, `/threatwarden`, `/atw` | 2026-11-25 | Q1 |
| D2 | GPL-3.0 per codice e documentazione, nessuna licenza separata dei contenuti | 2026-11-25 | Q2, [ADR 0011](../adr/0011-license-gpl-3.md) |
| D3 | MVP = M1–M4 (monitor, avvisi, Coach di base, registrazione e report) | 2026-11-25 | Q3 |
| D4 | Addon autonomo, nessuna integrazione in gioco con gli altri addon; crediti NEBULA | 2026-11-25 | Q4, [ADR 0012](../adr/0012-reuse-accord-and-unspoken-foundations.md) |
| D5 | Interfaccia multilingua: inglese predefinito, italiano dalla prima versione | 2026-11-25 | [ADR 0009](../adr/0009-interface-and-documentation-languages.md) |
| D6 | Logo definitivo fornito dal proprietario | 2026-11-25 | §6 |
| D7 | M2 (Threat Monitor) parte **prima** di M0.7, sulle ipotesi della specifica e progettato per i tre esiti del probe; M0.7 rivede M2 dove i risultati lo contraddicono (*"Parti con M2"*) | 2026-11-25 | [M2](../roadmap/M2-threat-monitor.md), [SPEC-03 §1.1](SPEC-03-threat-monitor-ui.md#11-tre-esiti-del-probe-tre-modalità) |
| D8 | La registrazione salva solo ciò che il monitor ha letto, in colonne compatte dentro `AzerothThreatwardenDB.sessions` (schema 4); nessuna terza SavedVariable | 2026-11-26 (M4.1, step) | [ADR 0016](../adr/0016-recordings-are-the-monitors-readings-in-compact-columns.md), [SPEC-02 §4](SPEC-02-data-model-storage.md#4-sessioni-registrate-schema-4-m4) |
| D9 | Il report di M4 non mostra ipotesi né cause: solo fatti rilevati e calcolati, con *Not available*, *Insufficient data* e i limiti inferiori dove i dati mancano | 2026-11-26 (M4.1, step) | [SPEC-05 §3.1](SPEC-05-recording-report-replay.md#31-regole) (REC-11) |
| D10 | Nessun evento di taunt o di abilità in M4: si aggiungono solo se il probe P7 trova un modo affidabile | 2026-11-26 (M4.1, step) | [SPEC-05 §1.4](SPEC-05-recording-report-replay.md#14-eventi) (REC-03) |
| D11 | Lo schema dell'account di M4 è il **4** (migrazione 3 → 4): il piano scriveva "schema 2" prima che M2 e M3 usassero il 2 e il 3 | 2026-11-26 (M4.1, step) | [SPEC-02 §3.7](SPEC-02-data-model-storage.md#37-schema-4-m4-registrazione-e-sessioni) |
| D12 | Soglie predefinite WARNING **82 %** (ridurre lo spam di abilità: meno danni o cure, o rank più bassi) e DANGER **91 %** (chi fa danni o cura si ferma per un attimo); avvisi e Coach lo dicono a DPS e healer, mai al tank; l'unico consiglio sugli incantesimi ammesso è il generico *rank più bassi*. Schema dell'account 5: i vecchi predefiniti 80/95 diventano 82/91, le soglie scelte dal giocatore restano | 2026-11-26 (proprietario) | Q7, Q11, [SPEC-02 §3.8](SPEC-02-data-model-storage.md#38-schema-5-correzione-q7-le-soglie-decise-dal-proprietario), [SPEC-04 §2.4](SPEC-04-alerts-coach.md#24-regole-di-scrittura) |
