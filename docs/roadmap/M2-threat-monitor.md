# M2 — Threat Monitor

**Goal:** a reliable, readable threat monitor on the selected target: who threatens which mob, the tank, the scaled
percentage, the margin, the state and the trend, with honest UNKNOWN and *state only* modes
([SPEC-03](../specs/SPEC-03-threat-monitor-ui.md)).

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
- Depends on: M0.7
- Spec: SPEC-03 §1–§3, SPEC-02 §1–§2
- Scope: SPEC-03 completed with the probe results (values or state only per context, units watched, events vs ticks,
  freshness, hysteresis, tank margin), the fight-script format for tests, previews of every state.
- Done when:
  - [ ] Every row of SPEC-03 §1 says its source API, category and fallback; `check_docs.py` passes.

### M2.2 — Threat scanner and target tracker
- Branch: `step/m2-2-scanner`
- Depends on: M2.1
- Spec: SPEC-01 ARC-05/06, ADR 0004
- Scope: `Data/TargetTracker.lua` (monitored mob from target or target of target, changes, death, disappearance, GUID
  change), `Data/ThreatScanner.lua` (threat events plus a bounded combat tick, unit list from the group, pooled records,
  stops out of combat).
- Done when:
  - [ ] No reads out of combat or with no monitored mob; no allocation per tick after warm-up.
- Tests: `test_target_tracker.lua`, `test_scanner.lua` on fight scripts (target change, mob dies, mob vanishes, secret
  values, nil answers, duplicate and out-of-order events).
- Real client: events and tick in a party.

### M2.3 — Threat model and calculator
- Branch: `step/m2-3-model`
- Depends on: M2.2
- Spec: SPEC-02 §1–§2, ADR 0003
- Scope: `Data/ThreatModel.lua` (`ThreatRecord`, categories, `reason`, staleness), `Data/ThreatCalc.lua` (margin,
  trend over N valid samples with confidence, time to overtake as a prediction).
- Done when:
  - [ ] Every value has its category; a trend with fewer than 3 valid samples is "Insufficient data".
- Tests: `test_threat_model.lua`, `test_threat_calc.lua` (known series, gaps, noise).

### M2.4 — Threat states, thresholds and tank detection
- Branch: `step/m2-4-states`
- Depends on: M2.3
- Spec: SPEC-03 §2, SPEC-09 Q7
- Scope: `Data/ThreatState.lua` (SAFE, WARNING, DANGER, UNKNOWN; `DEFAULTS` 80/95; hysteresis; tank margin rule;
  `STATE_CHANGED` on the Bus), tank from `isTanking` and the assigned role.
- Done when:
  - [ ] States do not flicker on a series that oscillates around a threshold.
- Tests: `test_threat_state.lua` (all scenarios of SPEC-08 QA-03 that concern states).

### M2.5 — The threat list view
- Branch: `step/m2-5-threat-list`
- Depends on: M2.4
- Spec: SPEC-03 §1, §3
- Scope: `UI/ThreatList.lua` (rows with class colour, role icon, bar, percentage, margin, state icon and word, trend
  arrow, estimate marker, quality indicator, sorting, "pin me on top"), empty, no-target and UNKNOWN states; wiki page
  *Threat Monitor* (both languages) with previews.
- Done when:
  - [ ] No state is shown by colour alone; every unknown value has a tooltip with its reason.
- Tests: `test_threat_list.lua`.
- Real client: readability in combat, at small sizes.

### M2.6 — Monitor settings and demo mode
- Branch: `step/m2-6-settings-demo`
- Depends on: M2.5
- Spec: SPEC-03 §5, SPEC-09 Q13–Q14
- Scope: settings for thresholds, rate, max units, when to show the window; `/atw demo` plays an invented fight (no
  game reads) for previews and for trying the settings; previews of all states.
- Done when:
  - [ ] Demo mode never writes to saved data and stops on any real combat.
- Tests: `test_demo.lua`, settings cases.

### M2.7 — Performance and long tests
- Branch: `step/m2-7-performance`
- Depends on: M2.6
- Spec: SPEC-01 §5, SPEC-08 §3
- Scope: long scenarios (40-player raid, hours of ticks), a per-tick time and allocation budget in the mock, the
  rate proposed by P10 as default.
- Done when:
  - [ ] The long scenario stays inside its budget; the default rate is recorded in SPEC-09 Q14.

### M2.8 — In-game checklist M2
- Branch: `step/m2-8-checklist`
- Scope: `docs/checklists/M2.md` (solo, party, dungeon, raid; tank and DPS; target changes and deaths; thresholds to
  tune Q7; CPU); README status.

### M2.R — Release preparation `v0.2.0`
- Branch: `chore/release-v0.2.0`
- Scope: as M1.R, for `v0.2.0`.
