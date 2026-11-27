# M7 — Multi-target and Dungeon Focus

**Goal:** follow several mobs at once and show where the group is closest to losing aggro
([SPEC-07 §0–§2](../specs/SPEC-07-multi-target-heatmap-profiles.md)).

**Gate:** this milestone runs **only if** the probe (P5, P6) shows that the threat of mobs other than the target can be
read. Otherwise M0.7 replaces it (for example with a *focus* and *boss* only version) and records why.

> **Conditional go before M0.7** (owner's decision D7, recorded for M7 as D21 in
> [SPEC-00 §7](../specs/SPEC-00-vision-scope.md#7-registro-delle-decisioni), 2026-11-27). The probe has not been run,
> so the gate is answered *conditionally*: M7 is built for every outcome of P5 and P3. The tracker reads what the client
> allows, reading by reading, and its **reach** drops by itself to *focus and boss only* and to *the target only* when
> other mobs cannot be queried or their threat is secret; every mob row says why it is unknown (ADR 0003). The monitor
> keeps one mob and nothing of the list is recorded
> ([ADR 0019](../adr/0019-other-mobs-are-read-by-a-separate-budgeted-rotation-and-only-shown.md)). What the probe will
> change, and where, is in [SPEC-07 §0](../specs/SPEC-07-multi-target-heatmap-profiles.md#0-il-gate-di-m7-go-condizionato)
> and in the notes of [M0.7](M0-probe.md#m07--results-and-decisions); the release with the switch on is SPEC-09 Q25.

**Exit criterion:** in a dungeon pull, the focus list shows the mobs at risk and degrades cleanly on mobs that cannot be
queried. Released as `v0.7.0`.

| Step | Model | Effort |
|---|---|---|
| M7.1 Specification with the go / no-go from M0 | Opus | high |
| M7.2 Multi-mob tracker | Opus | medium |
| M7.3 Dungeon focus view | Sonnet | medium |
| M7.4 Degradation, alerts and performance with many mobs | Sonnet | high |
| M7.5 In-game checklist M7 | Sonnet | low |
| M7.R Release preparation `v0.7.0` | Sonnet | medium |

**Switch.** `multitarget` in `Core/Features.lua` (`Data/MobTracker.lua`, `Data/MobRisk.lua`, the pin of the
TargetTracker, the pull bar and the list, the *Dungeon Focus* card, `/atw focus`, the `mob` alerts) stays **off** until
M7.R and is switched on there (SPEC-09 Q25); every step is built and tested behind it (SPEC-07 §2.7), and tests that
need it on set it to `true` in `M.features`. Off, nothing of M7 is visible, no game event is registered by the tracker
and `alerts.onlyTarget` counts as on. The account schema goes to **6** in M7.2 (four settings, a no-op migration) even
with the switch off; the character schema stays 2 and the sessions do not change.

### M7.1 — Specification with the go / no-go from M0
- Branch: `step/m7-1-spec`
- Spec: SPEC-07 §1–§2, SPEC-03 §1, SPEC-04 §1.1, SPEC-08 §1 P5 P6, SPEC-09, SPEC-00 D7
- Scope: the gate answered as a conditional go (SPEC-07 §0) with what each probe result changes and where; SPEC-07
  §1–§2 made implementable and testable (principles MT-01–MT-07; the sources of mobs and their tokens, checked against
  the dump; keys from GUIDs and the three levels of identity; the reach and its reason; the three outcomes per mob and
  the reasons of an unknown mob; the rotation, the slots and the read budget (MT-02); the life cycle; the state and
  reason of a mob; the settings; the risk order; what a row shows; the pull bar and the list; the pinned mob; the alerts
  with `alerts.onlyTarget`; card, command, demo, `/atw debug`; modules, events, switch; tests per step; what waits for the
  probe and the game); a new ADR; decisions in SPEC-00 §7; open questions in SPEC-09; SPEC-02 §3.10 (schema 6);
  ui-style §3.7; the steps below detailed.
- Done when:
  - [x] SPEC-07 says, for every source, key, outcome and reason, what the tracker does and what the player sees in
    each reach; the go / no-go and what the probe changes are recorded in SPEC-07, SPEC-00 and M0.7; `check_docs.py`
    passes.
- *Done (2026-11-27, before M0.7): SPEC-07 §0 (conditional go, D21: the table of what P5, P6, P9, P3 and P10 change and
  the one place of each), §1 (MT-01–MT-07; sources `focus`, `boss1–5`, the members' targets and `nameplate1–40` with
  their events, `mouseover` left out; `mob:<GUID>` keys, only `focus` and `boss` without GUIDs, only the target without
  a comparison; the reach `all`, `focus-boss`, `target`, `none` with its reason and the capability `otherMobs`; values,
  state only and unknown per mob with `pending`, `stale`, `no-token`, `secret` and a retry; a 2 Hz tick, 8 slots, 48
  reads per tick, 10 units per mob in turn, events moving a mob forward; the life cycle; `Data/MobRisk.lua` with
  `aggro`, `close`, `no-tank`, `near`; schema 6), §2 (the risk order, the row, the pull bar and the list in the Monitor
  tab, the pinned mob through `TargetTracker.Pin`, the `mob` alerts with `alerts.onlyTarget` off, card, `/atw focus`,
  demo, `/atw debug`, modules, switch, tests per step, probe and game); new
  [ADR 0019](../adr/0019-other-mobs-are-read-by-a-separate-budgeted-rotation-and-only-shown.md); SPEC-00 D21–D24;
  SPEC-09 Q25–Q27, R4 revised and R13; SPEC-01, SPEC-02 §3.10, SPEC-03 §1.2, SPEC-04 §1.1, SPEC-05 REC-02, ui-style §3.7,
  ARCHITECTURE and the M0.7 notes. Nothing changes in the addon.*

### M7.2 — Multi-mob tracker
- Branch: `step/m7-2-multi-mob`
- Depends on: M7.1
- Spec: SPEC-07 §0–§1, §2.4, §2.6 (`/atw debug`), §2.7, §2.8; SPEC-02 §3.10; ADR 0019
- Scope: behind `multitarget` (off): `Core/Compat.lua` `Unit.TokenFromGUID` and `Unit.CanCompare` with the API entries
  `unit.TokenFromGUID` and `secret.CanCompare`; `Core/Config.lua` schema 6 (`Config.MOBS_DEFAULTS`, `Config.MOBS`,
  `ALERTS_DEFAULTS.onlyTarget`, the no-op migration `account[6]`); `Data/MobRisk.lua` (the rules of §1.8 in `values`
  and `state`, without designated tanks, hysteresis and dwell from `ThreatState.DEFAULTS`, `MOB_STATE_CHANGED`, the
  order of §2.1 with `MobRisk.REASON_ORDER`); `Data/MobTracker.lua` (`SOURCES`, candidates, the sweep, keys and the
  three levels of identity, tokens checked against the GUID and found again with `UnitTokenFromGUID`, slots, `RATE`,
  `READ_BUDGET`, `UNITS_PER_MOB`, the per-mob cursor, events moving a mob forward, `RETRY`, `FORGET`, the life cycle,
  the reach and its reason, the capability `otherMobs`, the monitored mob's row from the monitor's rows, `Want`,
  `TokenOf`, `List`, `MOBS_UPDATED`); the pin in `Data/TargetTracker.lua` (rule 0, `Pin`, `Pinned`, release on a new
  hostile target, death, loss, `COMBAT_ENDED`, `PIN_CHANGED`); the *Mobs* section of `/atw debug`; the TOC.
- Done when:
  - [x] Known pulls give known mob lists, keys, reaches and states in the three outcomes per mob and the three levels of
    identity; the same mob never appears twice; a reassigned nameplate keeps its mob; reads per tick never exceed the
    budget and a tick allocates nothing after the warm-up; the monitored mob is never read by the tracker; the pin
    follows its rules; with the switch or the setting off nothing is registered or read.
- Tests: `test_multi_mob.lua`, `test_mob_risk.lua` (SPEC-07 §2.8); additions to `test_target_tracker.lua`,
  `test_config.lua` (schema 6), `test_compat.lua`, `test_api_boundary.lua`; the monitor's tests unchanged and passing.
- Real client: which sources answer (P5), whether `UnitTokenFromGUID` finds a mob again, whether the GUIDs and the
  comparison of tokens are readable in instances (P9); the events for nameplates and bosses (P6).
- *Done (2026-11-27, before M0.7): behind `multitarget` (off). `Core/Compat.lua` `Unit.TokenFromGUID`,
  `Unit.CanCompare` and the API entry `secret.CanCompare`; account schema 6 (`Config.MOBS_DEFAULTS`, `Config.MOBS`,
  `ALERTS_DEFAULTS.onlyTarget`, the no-op step `account[6]`); `Data/MobRisk.lua` (the rules of §1.8, hysteresis and
  dwell of the monitor, `MOB_STATE_CHANGED`, `REASON_ORDER`, `Before`, `Order`); `Data/MobTracker.lua` (`SOURCES`,
  the sweep, `mob:` and `tok:` keys with the three levels of identity, tokens checked against the GUID and found again
  with `UnitTokenFromGUID`, slots, `RATE` 2, `READ_BUDGET` 48, `UNITS_PER_MOB` 10, a cursor per slot, events moving a
  mob forward, `RETRY` 5, `FORGET` 10, the life cycle, the reach and its reason, `otherMobs`, the monitored mob from
  the monitor's records, `Want`, `TokenOf`, `Get`, `Rows`, `List`, `MOBS_UPDATED`, a tick that only sweeps while no
  other mob is known); the pin (rule 0, `Pin`, `Pinned`, `PIN_CHANGED`); the *Mobs* section of `/atw debug`; the TOC.
  Tests: `test_multi_mob.lua` (44), `test_mob_risk.lua` (20), additions to `test_target_tracker.lua`,
  `test_config.lua`, `test_compat.lua`, `test_api_boundary.lua`; the monitor's tests unchanged. Notes *M7.2* in
  SPEC-07 §1.2, §1.6, §1.7, §2.4.*

### M7.3 — Dungeon focus view
- Branch: `step/m7-3-focus-view`
- Depends on: M7.2
- Spec: SPEC-07 §2.1–§2.4, §2.6, §2.7; ui-style §3.4, §3.7
- Scope: behind `multitarget`: `UI/FocusList.lua` (the pull bar with the count, the riskiest other mob, *All safe* and
  the reduced reach with its reason; the list in place of the threat list with the fields of §2.2, the monitored mob
  ringed, UNKNOWN rows with their reason, *+N more*, the footer; the order at most once a second and at once on DANGER;
  a click pinning a mob and closing the list, rows that cannot be pinned) built by `UI/ThreatList.lua`, with the `pin`
  icon in the monitor's header that releases it; the icons `pull` and `pin` (`tools/make_media.py`); the *Dungeon
  Focus* card in `UI/Settings.lua` (after *Monitor*); `/atw focus` in `Core/Commands.lua`; the invented pull of five
  mobs in `Data/Demo.lua` and the invented tracker in `Core/Demo.lua`; the `FOCUS_*` keys in both languages; the wiki
  page *Dungeon Focus* (`docs/wiki/Dungeon-Focus.md` and `Dungeon-Focus-it.md`, linked from *Threat Monitor* and the
  sidebar, saying what depends on the probe) and the *Settings* and *Commands* pages; previews `focus-bar`, `focus-list`
  (also in Aurora and Warden).
- Done when:
  - [ ] The bar and the list show every situation of SPEC-07 §2.3 in the three outcomes and the four reaches; an unknown
    mob never looks like a number and always says why; a click pins and the header releases; nothing shows with the
    switch off; the wiki page exists in both languages.
- Tests: `test_focus_list.lua` (SPEC-07 §2.8); additions to `test_settings.lua`, `test_commands.lua`, `test_demo.lua`,
  `test_ui_texts.lua`, `test_threat_list.lua`.
- Real client: the readability of the bar and the list in combat, at small sizes and in Italian; whether the click is
  quick enough in a pull.

### M7.4 — Degradation, alerts and performance with many mobs
- Branch: `step/m7-4-performance`
- Depends on: M7.3
- Spec: SPEC-07 §1.6, §2.5, §2.6, §2.8; SPEC-04 §1; SPEC-01 §5
- Scope: behind `multitarget`: the `mob` kind in `Data/Alerts.lua` (`ALERT_MOB_AGGRO`, `ALERT_MOB_CLOSE`,
  `ALERT_MOB_NO_TANK`, `ALERT_MOB_SELF`; entries only, the cooldown per mob, `others`, exclusions, mute, sound from
  severity 2; only with `alerts.onlyTarget` off), the *Alerts about other mobs* switch in the *Alerts* card, the
  Recorder ignoring `mob` alerts, the alert lines of `/atw debug`; the long test with 40 units, 40 nameplates and 12
  mobs for 30 minutes (mobs becoming unreachable, secrets in the middle of a fight, GUID changes, nameplates
  reshuffled), the offline cost of a mobs tick against the monitor's tick (SPEC-01 §5.1) and the constants of Q26
  adjusted if the measure says so; the wiki pages *Alerts and Coach* and *Dungeon Focus* for the alerts.
- Done when:
  - [ ] Every `mob` alert enters once per transition and never with `alerts.onlyTarget` on or the switch off; nothing of
    them is recorded or posted; in the long test the reads per tick stay within the budget, the cost of a mobs tick is
    at most that of a monitor tick with 40 units, the memory does not grow and no mob is shown with numbers older than
    its staleness limit.
- Tests: additions to `test_alerts.lua`, `test_recorder.lua`, `test_coach_wording.lua` (the `ALERT_MOB_*` keys);
  `Tests/long/test_multi_mob_long.lua` (SPEC-07 §2.8).
- Real client: the FPS with 40 nameplates in a raid (P10); whether the `mob` alerts help a tank or are noise (Q26).

### M7.5 — In-game checklist M7
- Branch: `step/m7-5-checklist`
- Depends on: M7.4
- Scope: `docs/checklists/M7.md` (the switch on in the installed copy while it is off, backup of the saved data; a
  dungeon pull of 3–6 mobs with the enemy nameplates shown and hidden, with and without a focus; a mob loose on a DPS
  and one the tank has not picked up; the reach in a party, a dungeon and a raid, with the reason when reduced; secret
  mobs; the click that pins a mob, the release by a new target and by the header; `/atw focus`; the `mob` alerts with
  `alerts.onlyTarget` off; the FPS with 40 nameplates; the bar and the list at small sizes and in Italian; Q25–Q27
  tuning notes); the checklists index; README status.
- Done when:
  - [ ] The checklist covers every "Real client" line of M7.2–M7.4 and the exit criterion.

### M7.R — Release preparation `v0.7.0`
- Branch: `chore/release-v0.7.0`
- Depends on: M7.5
- Scope: the `multitarget` switch on (SPEC-09 Q25), `SHIPPED_ON` in `test_features.lua` updated; changelog promoted;
  READMEs and wiki status; `docs/curseforge.md` (features list with the Dungeon Focus, saying that it depends on what
  the client allows and is not verified in the game; nothing promised beyond what is tested); Release workflow dry run
  (with `--long`), then the tag ([ADR 0014](../adr/0014-one-version-per-milestone-and-feature-switches.md));
  CurseForge only if the owner has set up the project and `CF_API_KEY` (SPEC-09 Q6).
- Done when:
  - [ ] The `multitarget` switch is on, `profiles` and `heatmap` off; changelog promoted, status updated; the checks are
    green (quick and long).
  - [ ] The dry run is green, and the tag `v0.7.0` and its GitHub Release (changelog section as notes, zip with only
    the addon) exist.
