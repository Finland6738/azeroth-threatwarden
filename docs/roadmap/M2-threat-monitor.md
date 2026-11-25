# M2 — Threat Monitor

**Goal:** a reliable, readable threat monitor on the selected target: who threatens which mob, the tank, the scaled
percentage, the margin, the state and the trend, with honest UNKNOWN and *state only* modes
([SPEC-03](../specs/SPEC-03-threat-monitor-ui.md)).

> **Started before M0.7 (owner's decision, 2026-11-25: "Parti con M2").** M2 is built on the specification's
> assumptions while the owner has not yet run the M0 probe in game, as Azeroth Accord did with its M1. The monitor is
> designed for every probe outcome (values readable, *state only*, nothing readable: SPEC-03 §1.1), so no step waits
> for the probe; M0.7 revises M2 where the results contradict it ([SPEC-00 §7](../specs/SPEC-00-vision-scope.md#7-registro-delle-decisioni) D7).

**Exit criterion:** in a party in game, the list shows the tank and every member's percentage on the target, a DPS
closing on the tank goes WARNING then DANGER, and a target with no data shows UNKNOWN with its reason. Released as
`v0.2.0`.

| Step | Model | Effort |
|---|---|---|
| M2.1 Specification of the monitor (with the M0 results) | Opus | high |
| M2.2 Threat scanner and target tracker | Opus | medium |
| M2.3 Threat model and calculator (margin, trend) | Opus | medium |
| M2.4 Threat states, thresholds and tank detection | Opus | medium |
| M2.5 The threat list view | Sonnet | medium |
| M2.6 Monitor settings and demo mode | Sonnet | medium |
| M2.7 Performance and long tests | Sonnet | high |
| M2.8 In-game checklist M2 | Sonnet | low |
| M2.R Release preparation `v0.2.0` | Sonnet | medium |

### M2.1 — Specification of the monitor
- Branch: `step/m2-1-spec`
- Depends on: M0.7 when available; started before it by the owner's decision of 2026-11-25
- Spec: SPEC-03 §1–§3, SPEC-02 §1–§2
- Scope: SPEC-03 completed with the probe results (values or state only per context, units watched, events vs ticks,
  freshness, hysteresis, tank margin), the fight-script format for tests, previews of every state.
- Done when:
  - [x] Every row of SPEC-03 §1 says its source API, category and fallback; `check_docs.py` passes.
- *Done (2026-11-25, before M0.7): SPEC-03 §1–§3 for the three probe outcomes (per-row modes `values`, `state`,
  `none`), monitored mob, units watched and cap, events vs the 5 Hz tick, freshness, hysteresis and 1 s dwell, tank
  margin, trend and time to overtake, sorting, what each state looks like; §5.1 (Q13) and §6 (modules, Bus events and
  tests per step M2.2–M2.7); SPEC-02 §1–§2 (`ThreatRecord`, `ThreatRow`) and §3.5 (schema 2); SPEC-08 §2.1 fight
  scripts with the new verbs (`outcome`, `role`, `secrets`, `answer`, `silent`, `event`). Previews moved to M2.5 (they
  need its locale keys and view).*

### M2.2 — Threat scanner and target tracker
- Branch: `step/m2-2-scanner`
- Depends on: M2.1
- Spec: SPEC-01 ARC-05/06, ADR 0004
- Scope: `Data/TargetTracker.lua` (monitored mob from target or target of target, changes, death, disappearance, GUID
  change), `Data/ThreatScanner.lua` (threat events plus a bounded combat tick, unit list from the group, pooled records,
  stops out of combat).
- Done when:
  - [x] No reads out of combat or with no monitored mob; no allocation per tick after warm-up.
- Tests: `test_target_tracker.lua`, `test_scanner.lua` on fight scripts (target change, mob dies, mob vanishes, secret
  values, nil answers, duplicate and out-of-order events).
- *Done (2026-11-25, before M0.7): `Data/TargetTracker.lua` and `Data/ThreatScanner.lua` behind the `monitor` switch;
  `Compat.Unit`, `Compat.Group` (new entry `group.RaidIndex`), `Compat.Threat.ReadLead`; the combat check at
  `PLAYER_ENTERING_WORLD` in `Core/Init.lua`; `test_target_tracker.lua` (14 tests) and `test_scanner.lua` (35, the
  three probe outcomes included), plus Compat cases. Events and tick in a real party wait for M2.8 and the probe
  (P2–P6, P9, P10, P12).*
- Real client: events and tick in a party.

### M2.3 — Threat model and calculator
- Branch: `step/m2-3-model`
- Depends on: M2.2
- Spec: SPEC-02 §1–§2, ADR 0003
- Scope: `Data/ThreatModel.lua` (`ThreatRecord`, categories, `reason`, staleness), `Data/ThreatCalc.lua` (margin,
  trend over N valid samples with confidence, time to overtake as a prediction).
- Done when:
  - [x] Every value has its category; a trend with fewer than 3 valid samples is "Insufficient data".
- Tests: `test_threat_model.lua`, `test_threat_calc.lua` (known series, gaps, noise).
- *Done (2026-11-25, before M0.7): `Data/ThreatCalc.lua` (margin, tank margin, least-squares trend with confidence,
  time to overtake, predicted WARNING, freshness) and `Data/ThreatModel.lua` (one pooled row per watched unit, with the
  category and reason of every value, staleness, samples reset at a new mob, combat or holder; `THREAT_UPDATED`) behind
  the `monitor` switch; `test_threat_calc.lua` (29 tests) and `test_threat_model.lua` (22, the three probe outcomes
  included). The meaning of `UnitThreatPercentageOfLead` (`ThreatCalc.USE_LEAD`, P2) and the 110 %/130 % rule (P4)
  wait for the probe.*

### M2.4 — Threat states, thresholds and tank detection
- Branch: `step/m2-4-states`
- Depends on: M2.3
- Spec: SPEC-03 §2, SPEC-09 Q7
- Scope: `Data/ThreatState.lua` (SAFE, WARNING, DANGER, UNKNOWN; `DEFAULTS` 80/95; hysteresis; tank margin rule;
  `STATE_CHANGED` on the Bus), tank from `isTanking` and the assigned role.
- Done when:
  - [x] States do not flicker on a series that oscillates around a threshold.
- Tests: `test_threat_state.lua` (all scenarios of SPEC-08 QA-03 that concern states).
- *Done (2026-11-25, before M0.7): `Data/ThreatState.lua` behind the `monitor` switch: the rules of SPEC-03 §2.2–§2.3
  for non tanks, the tank holding the mob (margin over the second), designated tanks losing the mob, a tank swap and
  the pet alone; hysteresis 3 points and a 1 s dwell for falls with one timer, so a held fall happens after the fight
  too; the predicted WARNING; UNKNOWN with its reason; the Unknown tank; `STATE_CHANGED` (old or new `nil` when the unit
  enters or leaves the list) and `THREAT_MODE_CHANGED`; `DEFAULTS` 80/95 overridden by `settings.monitor.warning` and
  `.danger` when M2.6 adds them. `test_threat_state.lua` (55 tests). The game's situation and lead meanings (P2), the
  110 %/130 % rule (P4) and the roles (P9) wait for the probe.*

### M2.5 — The threat list view
- Branch: `step/m2-5-threat-list`
- Depends on: M2.4
- Spec: SPEC-03 §1, §3
- Scope: `UI/ThreatList.lua` (rows with class colour, role icon, bar, percentage, margin, state icon and word, trend
  arrow, estimate marker, quality indicator, sorting, "pin me on top"), empty, no-target and UNKNOWN states; wiki page
  *Threat Monitor* (both languages) with previews.
- Done when:
  - [x] No state is shown by colour alone; every unknown value has a tooltip with its reason.
- Tests: `test_threat_list.lua`.
- *Done (2026-11-25, before M0.7): `UI/ThreatList.lua` in the Monitor tab behind the `monitor` switch (the M1 text stays
  while it is off), with header, rows, every view of SPEC-03 §2.6, tooltips with categories and reasons, the four orders
  with *Me on top* (kept for the session until schema 2, M2.6), the quality footer and bounded redraws; role icons,
  locale keys in both languages, previews `monitor-*`, wiki page *Threat Monitor*; `test_threat_list.lua` (44 tests).
  Readability in combat and at small sizes waits for M2.8.*
- Real client: readability in combat, at small sizes.

### M2.6 — Monitor settings and demo mode
- Branch: `step/m2-6-settings-demo`
- Depends on: M2.5
- Spec: SPEC-03 §5, SPEC-09 Q13–Q14
- Scope: settings for thresholds, rate, max units, when to show the window; `/atw demo` plays an invented fight (no
  game reads) for previews and for trying the settings; previews of all states.
- Done when:
  - [x] Demo mode never writes to saved data and stops on any real combat.
- Tests: `test_demo.lua`, settings cases.
- *Done (2026-11-25, before M0.7): account schema 2 with `settings.monitor` (defaults in one place,
  `Config.MONITOR_DEFAULTS`; migration and its test), the *Monitor* card of Settings (thresholds kept 5 points apart,
  rate, units, when the window shows, order, pin, target of target, demo button), the window rules of SPEC-03 §5.1,
  `Core/Demo.lua` and `Data/Demo.lua` (`/atw demo`, SPEC-03 §5.2), previews `monitor-demo` and `settings-monitor`, wiki
  pages; `test_demo.lua` and cases in `test_config.lua`, `test_settings.lua`, `test_window.lua`. The window's own
  opening and closing and the card in the game wait for M2.8.*

### M2.7 — Performance and long tests
- Branch: `step/m2-7-performance`
- Depends on: M2.6
- Spec: SPEC-01 §5, SPEC-08 §3
- Scope: long scenarios (40-player raid, hours of ticks), a per-tick time and allocation budget in the mock, the
  rate proposed by P10 as default.
- Done when:
  - [x] The long scenario stays inside its budget; the default rate is recorded in SPEC-09 Q14.
- *Done (2026-11-25, before M0.7): `Tests/lib/raid.lua` (a simulated raid of 40 whose answers do not allocate);
  `test_monitor_raid.lua` (one mob for 30 minutes at 2, 5 and 10 Hz, a boss and four adds for two hours at 10 Hz
  through the three outcomes, oscillating states) and `test_monitor_budget.lua` (work, allocation and time per tick at
  2, 5 and 10 Hz) in `Tests/long/`; three allocations per tick removed (`Config:Get`, the colour registry of
  `UI/Theme.lua`, class colours in the list); the *Long tests* workflow also runs on `UI/` changes. The default stays
  **5 Hz, provisional**: the probe P10 has not run, so no rate comes from it yet; the offline cost is in SPEC-01 §5.1
  and SPEC-09 Q14. The cost in the game and the cost of bursts of threat events wait for P6, P10 and M2.8.*

### M2.8 — In-game checklist M2
- Branch: `step/m2-8-checklist`
- Scope: `docs/checklists/M2.md` (solo, party, dungeon, raid; tank and DPS; target changes and deaths; thresholds to
  tune Q7; CPU); README status.

### M2.R — Release preparation `v0.2.0`
- Branch: `chore/release-v0.2.0`
- Scope: as M1.R, for `v0.2.0`.
