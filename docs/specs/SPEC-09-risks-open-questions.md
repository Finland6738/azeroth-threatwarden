# SPEC-09: Rischi e domande aperte

> Fonte: [specifiche originali](source-specification.md) §17, §19. Il codice applica la **risposta proposta** di ogni
> domanda finché il proprietario non decide, e ogni risposta si cambia in un solo punto (indicato nella riga).

## 1. Rischi

| # | Rischio | Probabilità | Impatto | Risposta |
|---|---|---|---|---|
| R1 | API threat assenti o limitate su Forever | bassa (presenti nel dump) | molto alto | probe M0 prima di tutto (P2) |
| R2 | **Valori di threat segreti** (`ShouldUnitThreatValuesBeSecret`) in istanza o in combattimento: l'addon non può leggere le percentuali dove servono di più | **media-alta** | molto alto | P3; il monitor di M2 è progettato per i tre esiti, per riga ([SPEC-03 §1.1](SPEC-03-threat-monitor-ui.md#11-tre-esiti-del-probe-tre-modalità)): valori, *state only* (MON-02) o UNKNOWN con il motivo; se anche lo stato è segreto, il prodotto si ridimensiona e M0.7 lo decide con il proprietario |
| R3 | Combat log non leggibile dagli addon (`CombatLogGetCurrentEventInfo` assente) | alta | medio | nessuna dipendenza dal combat log ([ADR 0004](../adr/0004-threat-from-the-unit-threat-api-sampled-in-combat.md)); eventi da `UNIT_*`, `PLAYER_REGEN_*`, eventualmente `C_DamageMeter` (P7, P8) |
| R4 | Threat non interrogabile su più mob | media | alto | MVP sul target accessibile (o il target del target, [SPEC-03 §1.2](SPEC-03-threat-monitor-ui.md#12-il-mob-monitorato-datatargettrackerlua)); M7 solo se P5 lo consente |
| R5 | Dati storici incompleti | alta | alto | registrazione continua durante lo scontro, buchi registrati come tali |
| R6 | Falsi positivi nelle previsioni | media-alta | medio | soglie configurabili, isteresi, confidenza, cooldown |
| R7 | Consumo di CPU o SavedVariables troppo grandi | media | medio | campionamento e limiti configurabili, misura in P10 e nei test lunghi |
| R8 | Differenze tra client (aggiornamenti di Forever) | alta | alto | Compat e prove sulla build target; `/atw debug` mostra cosa manca |
| R9 | Confusione tra correlazione e causa | alta | alto | categorie dei dati ([ADR 0003](../adr/0003-data-reliability-categories.md)), ipotesi etichettate |
| R10 | Il server implementa la threat in modo personalizzato | bassa | medio | P4; soglie tarate nelle prove di M2 |

## 2. Domande aperte per il proprietario

| # | Domanda | Proposta / risposta |
|---|---|---|
| Q1 | Nomi tecnici: cartella `AzerothThreatwarden`, SavedVariables `AzerothThreatwardenDB` e `AzerothThreatwardenCharDB`, comandi `/threatwarden` e un alias corto | **Risposta del proprietario (2026-11-25)**: come proposto, alias **`/atw`** |
| Q2 | Licenza di documentazione e testi (messaggi del Coach, wiki, mockup) | **Risposta del proprietario (2026-11-25)**: GPL-3.0 per tutto, come Accord ([ADR 0011](../adr/0011-license-gpl-3.md)) |
| Q3 | Perimetro dell'MVP | **Risposta del proprietario (2026-11-25)**: MVP = M1–M4 (monitor, avvisi, Coach di base, registrazione e report); poi M5 Timeline e Replay, M6 Analytics, M7 multi-target se il client lo consente, M8 rifinitura e `v1.0.0` |
| Q4 | Integrazioni con gli altri addon (Accord, FDCP, Unspoken) e identità | **Risposta del proprietario (2026-11-25)**: addon autonomo, nessuna integrazione in gioco; crediti e loghi NEBULA nella pagina Info, come Accord. Logo definitivo fornito dal proprietario (`assets/logo-source.webp`) |
| Q5 | Lingua dell'interfaccia: inglese predefinito e italiano (richiesta del proprietario). Serve anche un'opzione per sceglierla a mano? | segue il client; un'impostazione *Language: Automatic / English / Italiano* la forza (utile a chi gioca col client inglese ma preferisce l'italiano); il cambio vale dopo `/reload` ([SPEC-01 §10](SPEC-01-platform-architecture.md#10-lingue-corelocalelua)). Un solo punto: `Config` chiave `settings.language` (M1.5) |
| Q6 | Dove si distribuisce: GitHub Releases e CurseForge (e Wago, WoWInterface)? | GitHub Releases da `v0.1.0`; CurseForge dall'MVP `v0.4.0`, predisposto ma spento finché il proprietario non crea il progetto e il segreto `CF_API_KEY` |
| Q7 | Soglie predefinite (fonte §5.1: "da stabilire dopo i test") | provvisorie WARNING 80 %, DANGER 95 % della percentuale scalata, isteresi 3 punti, permanenza 1 s per le discese ([SPEC-03 §2](SPEC-03-threat-monitor-ui.md#2-stati-e-soglie)); si tarano con la checklist di M2. Un solo punto: `ThreatState.DEFAULTS` (M2.4), che le impostazioni `settings.monitor.warning` e `danger` (M2.6) sovrascrivono |
| Q8 | Quanto deve durare lo storico locale? (fonte Q5) | 25 sessioni, circa 2 MB stimati, le più vecchie eliminate per prime; tutto configurabile. Un solo punto: `Storage.LIMITS` (M4.3) |
| Q9 | Il replay è solo locale o esportabile? (fonte Q6) | locale; esportazione in testo e CSV da copiare in M6 |
| Q10 | Interfaccia autonoma o integrata in una UI esistente? (fonte Q7) | finestra autonoma nello stile dell'ecosistema, che convive con le UI personalizzate senza integrarsi |
| Q11 | Quali classi e ruoli coprono i primi suggerimenti? (fonte Q8) | tre ruoli (tank, DPS, healer), messaggi per ruolo, nessun consiglio di classe o di abilità finché non è verificabile (COA-04) |
| Q12 | Canali di avviso predefiniti | messaggio nella finestra ed effetto visivo accesi, suono spento, mai chat ([SPEC-04 §1](SPEC-04-alerts-coach.md#1-avvisi)) |
| Q13 | Quando si mostra la finestra | solo in gruppo o in combattimento (predefinito), sempre, o a mano; fuori dal gruppo si chiude da sola 10 s dopo il combattimento ([SPEC-03 §5.1](SPEC-03-threat-monitor-ui.md#51-quando-si-mostra-la-finestra-q13-m26)). Un solo punto: il predefinito di `settings.monitor.show` (M2.6) |
| Q14 | Frequenza di campionamento | la decide la misura P10; provvisoria 5 Hz (ogni 0,2 s) solo in combattimento, configurabile da 2 a 10 Hz; al massimo 40 unità per scansione (5–40), a turno oltre il limite ([SPEC-03 §1.3–§1.4](SPEC-03-threat-monitor-ui.md#14-quando-si-legge-eventi-e-tick)). Un solo punto: i predefiniti di `settings.monitor.rate` e `maxUnits` (M2.6); M2.7 scrive qui il valore misurato |
| Q15 | Nomi dei compagni nelle registrazioni | salvati solo in locale (servono al report); l'esportazione mostra un avviso e può sostituirli con *Player 1, Player 2…* |
