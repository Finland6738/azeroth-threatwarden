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
| `v0.7.0` | M7 Multi-target | più mob e dungeon focus; **go condizionato** prima del probe (D21): legge ciò che il client permette e si riduce a *focus e boss* o al solo target | SPEC-07 §0–2 |
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
  parole chiave come nella fonte §16, **senza promettere funzioni non verificate** né versioni diverse da quella
  provata. Bozza della pagina: [docs/curseforge.md](../curseforge.md) (il titolo per `v0.4.0` è in [Q17](SPEC-09-risks-open-questions.md)).

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
| D13 | Timeline e replay leggono solo la sessione registrata e non vi scrivono nulla: ogni vertice è una lettura, il riassunto per la larghezza sceglie letture (prima, ultima, minima, massima) e non le media; un tratto fra due letture è pieno (rilevato) al passo della registrazione, tratteggiato (stimato) fra letture rade senza nulla di sconosciuto in mezzo, assente su un buco, che resta visibile con il motivo | 2026-11-26 (M5.1, step) | [SPEC-05 §4.1–§4.4](SPEC-05-recording-report-replay.md#41-regole), [ADR 0017](../adr/0017-timeline-and-replay-are-views-over-the-recorded-session.md) |
| D14 | La timeline si disegna con regioni `Line` e texture da pool limitati (con il ripiego a soli punti senza `CreateLine`), il modello è in `Data/` senza frame e il replay ha una finestra sua, `AzerothThreatwardenReplay`, aperta dalla scheda Reports; lo schema del personaggio passa a 2 per la sua posizione | 2026-11-26 (M5.1, step) | [SPEC-05 §4.8, §5.5](SPEC-05-recording-report-replay.md#48-il-widget-uitimelinelua-m53), [SPEC-02 §3.9](SPEC-02-data-model-storage.md#39-schema-2-del-personaggio-m5-la-finestra-del-replay), [ADR 0017](../adr/0017-timeline-and-replay-are-views-over-the-recorded-session.md) |
| D15 | Nemmeno timeline e replay mostrano ipotesi o cause (come D9): solo fatti registrati e calcolati, con *Estimate* sui tratti tratteggiati e sulle letture vecchie; le parole del Coach non registrate non si ricostruiscono | 2026-11-26 (M5.1, step) | [SPEC-05 §4.1](SPEC-05-recording-report-replay.md#41-regole) (RPL-03) |
| D16 | L'elenco degli scontri con la durata e l'eliminazione (fonte §5.4) restano la scheda Reports di M4; il replay si apre da lì e non ha un secondo elenco | 2026-11-26 (M5.1, step) | [SPEC-05 §5](SPEC-05-recording-report-replay.md#5-threat-replay-datareplaylua-uireplaywindowlua-m54m55) |
| D17 | Analytics ed esportazione leggono soltanto le sessioni: le metriche si calcolano in memoria (al più 25 in una cache, buttate con la sessione), il confronto una sessione alla volta e in pausa in combattimento; nessuna chiave né schema nuovo | 2026-11-26 (M6.1, step) | [SPEC-06 §0, §1.7, §2.4](SPEC-06-analytics-export.md#0-principi), [ADR 0018](../adr/0018-analytics-and-export-are-computed-in-memory-and-leave-only-through-a-copy-box.md) |
| D18 | Le metriche che il report ha già sono le celle del report (stesse funzioni, stessi numeri); Analytics aggiunge solo ciò che manca e la regola ANA-02 (meno del 50 % di campioni validi, o nemico monitorato per meno del 50 % del combattimento: *Insufficient data*), più severa del report per descrivere e confrontare | 2026-11-26 (M6.1, step) | [SPEC-06 §1.3–§1.4](SPEC-06-analytics-export.md#13-lo-stato-di-una-metrica) |
| D19 | Si confrontano solo scontri con lo stesso nemico principale (numero della creatura, altrimenti nome e classificazione), di predefinito con lo stesso gruppo, difficoltà e ruolo; le metriche di stato solo con le stesse soglie registrate, le percentuali solo con valori; nessuna classifica di persone, nessuna tendenza dichiarata (come D9 e D15) | 2026-11-26 (M6.1, step) | [SPEC-06 §2](SPEC-06-analytics-export.md#2-confronto-e-aggregati-datacomparelua-m63) (ANA-01) |
| D20 | L'esportazione è testo (blocchi di codice in parti da 1 900 caratteri) o CSV (RFC 4180 con la protezione delle formule) in una casella di sola lettura che il giocatore copia: nessun file, nessuna rete, nulla in chat, `CopyToClipboard` non si usa; al più 256 KB a righe intere; l'avviso dei nomi è sempre visibile e i nomi si possono sostituire con *Player 1, Player 2…* | 2026-11-26 (M6.1, step) | [SPEC-06 §4](SPEC-06-analytics-export.md#4-esportazione-dataexportlua-uiexportboxlua-m65), [ADR 0018](../adr/0018-analytics-and-export-are-computed-in-memory-and-leave-only-through-a-copy-box.md), Q15 |
| D21 | **Go condizionato** per M7 prima del probe (P5, P6), per D7: il multi-target legge ciò che il client permette, lettura per lettura, e si riduce da solo a *focus e boss* e a *solo il target*, con il motivo su ogni mob e nella barra del pull. Il risultato del probe cambia soltanto `MobTracker.SOURCES` (le fonti accese), `MobTracker.RATE` e `READ_BUDGET` (P6, P10) e, se P5 dice *non supportato*, con il proprietario l'interruttore `multitarget` (Q25) | 2026-11-27 (M7.1, step) | [SPEC-07 §0](SPEC-07-multi-target-heatmap-profiles.md#0-il-gate-di-m7-go-condizionato), [M0.7](../roadmap/M0-probe.md#m07--results-and-decisions) |
| D22 | Il monitor resta su un solo mob; gli altri mob li legge `Data/MobTracker.lua` con un tick suo (2 Hz), al più 8 mob (2–12), 48 letture per tick e 10 unità per mob, a rotazione; si mostrano soltanto (nessun trend né previsione), non si registrano; quattro impostazioni nello schema 6 dell'account | 2026-11-27 (M7.1, step) | [SPEC-07 §1](SPEC-07-multi-target-heatmap-profiles.md#1-multi-target-m7), [ADR 0019](../adr/0019-other-mobs-are-read-by-a-separate-budgeted-rotation-and-only-shown.md), Q26 |
| D23 | Un mob è `mob:<GUID>`, la chiave del TargetTracker; senza GUID leggibile si usano solo `focus` e `boss1–5` (confrontati con `UnitIsUnit` se il client lo permette), altrimenti solo il target; `mouseover` non è una fonte | 2026-11-27 (M7.1, step) | [SPEC-07 §1.2–§1.4](SPEC-07-multi-target-heatmap-profiles.md#13-identità-e-chiavi) |
| D24 | Il Dungeon Focus ordina per stato (DANGER, WARNING, SAFE, UNKNOWN in fondo) e motivo (*mob sciolto* su un non tank, *vicino a strappare*, *senza tank*, *vicino*); un clic **fissa** il mob come mob del monitor senza toccare il target del gioco; gli avvisi sugli altri mob solo con `alerts.onlyTarget` spento (acceso di predefinito) e non registrati | 2026-11-27 (M7.1, step) | [SPEC-07 §2](SPEC-07-multi-target-heatmap-profiles.md#2-dungeon-focus-m7), Q26, Q27 |
