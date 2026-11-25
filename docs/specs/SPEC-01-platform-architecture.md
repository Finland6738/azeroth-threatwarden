# SPEC-01: Piattaforma e architettura

> Fonte: [specifiche originali](source-specification.md) §1.3, §7, §9–§11. Da completare in **M1.1** con l'esito del
> probe M0.

## 1. Il client

| Fatto | Valore | Stato |
|---|---|---|
| Prodotto | World of Warcraft: Forever, build `1.60.1` (70170) | dal dump, [ADR 0002](../adr/0002-wow-forever-target-and-api-dump.md) |
| Interfaccia TOC | `## Interface: 16001` | dal dump |
| Lua | 5.1, motore client moderno (restrizioni degli addon, valori segreti) | dal dump |
| Comportamento della threat sul server | standard o personalizzato? | **[verificare]** P1, P3 |

**ARC-01** MUST: all'avvio l'addon controlla interfaccia e progetto; su un client diverso si carica in modalità
diagnostica e lo dice in `/atw debug` invece di dare numeri.

## 2. API rilevanti dal dump (build 70170)

| API / evento | Firma nel dump | Uso | Stato |
|---|---|---|---|
| `UnitDetailedThreatSituation(unit, mob)` | → `isTanking, status, scaledPercentage, rawPercentage, rawThreat` | sorgente principale del monitor | **[verificare]** P2–P5 |
| `UnitThreatSituation(unit [, mob])` | → `status` 0–3, nilable | stato quando i valori sono segreti | **[verificare]** P2 |
| `UnitThreatPercentageOfLead(unit, mob)` | → numero, nilable | margine del tank sul secondo | **[verificare]** P2 |
| `UnitThreatLeadSituation(unit, mob)` | → 0–3, nilable | quanto il tank è sopra il secondo | **[verificare]** P2 |
| `GetThreatStatusColor(index)` | → r, g, b | solo confronto, i colori sono del tema | presente |
| `IsThreatWarningEnabled()` | → bool | rispettare l'avviso nativo, non duplicarlo | presente |
| `ShouldUnitThreatValuesBeSecret(unit, mob)` / `ShouldUnitThreatStateBeSecret(unit [, mob])` | → bool | sapere **prima** se una lettura sarà segreta | **[verificare]** P3 |
| `issecretvalue(v)`, `issecrettable(t)` | → bool | non toccare mai un valore segreto | presente |
| `UNIT_THREAT_LIST_UPDATE`, `UNIT_THREAT_SITUATION_UPDATE` | evento con unità | aggiornamenti guidati da eventi | **[verificare]** P6 |
| `COMBAT_LOG_EVENT_UNFILTERED` | nessun payload documentato; **`CombatLogGetCurrentEventInfo` assente** | eventi di combattimento | **probabilmente non leggibile**, P7 |
| `C_DamageMeter` (sessioni, fonti, morti) | presente | possibile fonte di eventi (morti, durata) | **[verificare]** P8 |
| `UnitGUID`, `UnitGroupRolesAssigned`, `IsInGroup`, `IsInRaid`, `GetNumGroupMembers` | presenti | identità, ruolo, gruppo | **[verificare]** valori segreti in istanza, P5 |
| `PLAYER_REGEN_DISABLED/ENABLED`, `UNIT_TARGET`, `PLAYER_TARGET_CHANGED`, `ENCOUNTER_START/END` | presenti | inizio e fine combattimento, cambi di target | **[verificare]** P7 |

**ARC-02** MUST: ogni chiamata passa da `Core/Compat.lua` (l'*API Adapter* della fonte §7.2), che dice per ogni
funzione `available`, `missing`, `restricted` (segreta) o `error`, normalizza i risultati e fa da unico punto di
ripiego. Nessun modulo di `UI/` chiama le API del gioco direttamente (un test lo verifica da M1.4).

## 3. Moduli

La struttura indicativa della fonte (§7) si adatta a quella di Azeroth Accord
([ADR 0012](../adr/0012-reuse-accord-and-unspoken-foundations.md)): `Core/` (infrastruttura), `Data/` (logica senza
grafica, testabile offline), `UI/` (viste), `Locales/`.

| Fonte §7 | File | Milestone |
|---|---|---|
| Bootstrap, Events, Scheduler | `Core/Init.lua`, `Core/Bus.lua` (eventi interni), `Core/Scheduler.lua` (tick limitati) | M1 |
| Compatibility, APIAdapter | `Core/Compat.lua` | M1 |
| Diagnostics | `Core/Diagnostics.lua`, `UI/DiagnosticsBox.lua` (`/atw debug`) | M1 |
| — | `Core/Config.lua` (SavedVariables, schema), `Core/Features.lua` (interruttori) | M1 |
| ThreatScanner, TargetTracker | `Data/ThreatScanner.lua`, `Data/TargetTracker.lua` | M2 |
| ThreatModel, ThreatCalculator, ThreatState | `Data/ThreatModel.lua`, `Data/ThreatCalc.lua`, `Data/ThreatState.lua` | M2 |
| Rules, Recommendations, AlertManager | `Data/CoachRules.lua`, `Data/Coach.lua`, `Data/Alerts.lua` | M3 |
| Recorder, Session, Storage | `Data/Recorder.lua`, `Data/Session.lua`, `Data/Storage.lua` | M4 |
| Replay | `Data/Replay.lua` | M5 |
| Metrics, Reports | `Data/Report.lua` (M4), `Data/Metrics.lua`, `Data/Export.lua` (M6) | M4, M6 |
| UI | `UI/Theme.lua`, `Assets.lua`, `Motion.lua`, `Widgets/`, `Window.lua`, `ThreatList.lua`, `Timeline.lua`, `ReplayWindow.lua`, `Settings.lua`, `About.lua` | M1… |
| Localization | `Locales/enUS.lua`, `Locales/itIT.lua` | M1 |

**ARC-03** MUST: i moduli comunicano con il Bus interno (`THREAT_UPDATED`, `STATE_CHANGED`, `COMBAT_STARTED`,
`COMBAT_ENDED`, `CONFIG_CHANGED`…), non chiamandosi a vicenda dall'interfaccia ai dati.

**ARC-04** MUST: nessuna variabile globale tranne `AzerothThreatwarden`, le SavedVariables, le funzioni del
Compartment e i binding.

## 4. Librerie

Ace3 incorporato (AceAddon, AceEvent, AceTimer, AceConsole, AceLocale, AceDB, AceConfig), LibDataBroker e LibDBIcon,
fissati in `.pkgmeta` e mai nel repository ([ADR 0005](../adr/0005-embedded-ace3-savedvariables-and-schema-versions.md)).
Niente AceComm ([ADR 0001](../adr/0001-local-only-addon-no-network.md)).

## 5. Prestazioni (fonte §9)

- **ARC-05** MUST: nessuna scansione completa a ogni frame; eventi dove esistono, campionamento solo in combattimento
  con frequenza configurabile e limite di unità e mob osservati.
- **ARC-06** MUST: nei percorsi frequenti nessuna allocazione ripetuta: tabelle riusate (pool), stringhe dell'interfaccia
  aggiornate solo quando cambiano.
- **ARC-07** MUST: analisi e serializzazioni pesanti fuori dal combattimento o spezzate su più frame.
- **ARC-08** SHOULD: la frequenza predefinita la decide la misura del probe (P10), non una scelta arbitraria
  ([Q14](SPEC-09-risks-open-questions.md)).
- Target che scompaiono, muoiono o cambiano GUID, dati mancanti, ritardati o incoerenti: gestiti dal modello
  ([SPEC-02](SPEC-02-data-model-storage.md)) e coperti da test.

## 6. Sicurezza, privacy, conformità (fonte §10)

Nessuna comunicazione di rete; nessuna credenziale o dato personale raccolto; dati solo nelle SavedVariables; funzione
per cancellare le registrazioni; nessun messaggio automatico in chat; solo API consentite; nessun tentativo di aggirare
le restrizioni (i valori segreti restano segreti); nessuna lettura della memoria del processo o strumento esterno.

## 7. Compatibilità e dipendenze (fonte §11)

L'addon funziona da solo; nessuna dipendenza obbligatoria. Con le UI personalizzate più comuni la finestra resta
utilizzabile (verifica nelle checklist). Nessuna integrazione con gli altri addon del proprietario (Q4).
