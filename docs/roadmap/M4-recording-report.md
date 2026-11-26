# M4 — Recording and combat report (MVP)

**Goal:** record every fight while it happens and show an essential, honest report at the end
([SPEC-05 §1–§3](../specs/SPEC-05-recording-report-replay.md)). This completes the **MVP**.

> **Started before M0.7, like M2 and M3** (owner's decision D7, [SPEC-00 §7](../specs/SPEC-00-vision-scope.md#7-registro-delle-decisioni)).
> The recorder stores only what the monitor read ([ADR 0016](../adr/0016-recordings-are-the-monitors-readings-in-compact-columns.md)),
> so it works for every probe outcome (values, *state only*, nothing readable: SPEC-05 §0); M0.7 revises it where the
> results contradict the specification (`[probe Pn]` marks: P7 deaths and encounters, P9 keys and roles, P10 cost, P12
> `/reload` in combat).

**Exit criterion:** in game, fights become separate sessions that survive `/reload`; the report of each shows duration,
threshold crossings, time in WARNING and DANGER and tank changes, and says "Insufficient data" where it must; storage
limits hold. Released as `v0.4.0`, the first CurseForge candidate (SPEC-09 Q6).

| Step | Model | Effort |
|---|---|---|
| M4.1 Specification of recorder, storage and report | Opus | high |
| M4.2 Recorder and sessions | Opus | medium |
| M4.3 Storage, schema 4 and limits | Opus | high |
| M4.4 Combat report | Sonnet | medium |
| M4.5 Reports tab: sessions list and report view | Sonnet | medium |
| M4.6 Long tests of recording | Sonnet | high |
| M4.7 In-game checklist M4 and MVP check | Sonnet | low |
| M4.R Release preparation `v0.4.0` | Sonnet | medium |

**Switches.** `recording` (recorder, storage, the *Recording* card) and `reports` (report, Reports tab, end-of-fight
notice, `/atw reports`) in `Core/Features.lua` stay **off** until M4.R; every step works and is tested behind them
(SPEC-05 §6). Tests that need them set them to `true` in `M.features`. The defaults of account schema 4
(`settings.recording`, `sessions = {}`) are written even with the switches off, as those of M3 were.

### M4.1 — Specification of recorder, storage and report
- Branch: `step/m4-1-spec`
- Spec: SPEC-05 §1–§3, SPEC-02 §4, SPEC-09 Q8, Q15
- Scope: SPEC-05 §0–§3 and §6–§8 completed (when a session starts and ends, samples and events, gaps, duplicates,
  reload and logout in combat; storage, limits, pruning, size, damaged sessions, deletion; every report metric with
  its category and its "Insufficient data" rule in the three probe outcomes); the data format in SPEC-02 §3.7 and §4;
  decisions in SPEC-00 §7; Q8, Q15 and the new Q16 in SPEC-09; the steps below detailed.
- Done when:
  - [x] SPEC-05 says, for every session event, sample, limit and report metric, its source, its category and what
    happens in *state only* and with nothing readable; `check_docs.py` passes.
- *Done (2026-11-26, before M0.7): SPEC-05 §0 (the recorder stores only what the monitor read; the three outcomes),
  §1 (conditions with `when`; open at `COMBAT_STARTED`, chained pulls within 5 s, close and discard under 3 s; a 1–5 Hz
  tick over the Model's rows, rows only for new reads and, without a number, only when the code changes; 13 event
  kinds; gaps, duplicates and order; `/reload`, logout and disconnection with the `X` stamp and the linked session;
  per-session limits; cost), §2 (load checks, interrupted sessions completed, damaged ones set aside one by one in
  `corrupt`, account schema **4** with migration 3 → 4 — the plan said "schema 2" before M2 and M3 used 2 and 3 —,
  pruning by number and estimated size, delete one or all, read-only), §3 (eleven metrics with category and the three
  outcomes, *Not available* / *Insufficient data* / lower bounds, no hypothesis in M4, build in slices, end-of-fight
  notice, Reports tab and *Recording* card), §6–§8 (modules, events, switches, debug, tests per step, probe); SPEC-02
  §3.7 and §4 (header, base-62 fixed-width columns, 12-character events, codes); new
  [ADR 0016](../adr/0016-recordings-are-the-monitors-readings-in-compact-columns.md) and an update of ADR 0005;
  SPEC-00 D8–D11; SPEC-09 Q8, Q15 refined, Q16 new, R5, R7; SPEC-01, SPEC-03 and ARCHITECTURE for the new modules,
  events and APIs.*

### M4.2 — Recorder and sessions
- Branch: `step/m4-2-recorder`
- Depends on: M4.1
- Spec: SPEC-05 §1, §6; SPEC-02 §3.7, §4
- Scope: `Data/Session.lua` (the session of SPEC-02 §4: alphabet and codes, `units` and `mobs` entries, `buf`, pieces
  every 256 rows, join at close, decode); `Data/Recorder.lua` behind the `recording` switch (conditions of §1.1,
  life cycle and chained pulls of §1.2 with `END_DELAY`, the `record` tick of §1.3, the events of §1.4, `PLAYER_LOGOUT`
  and the linked session of §1.6, the Scanner consumer `recorder`, `SESSION_STARTED`, `SESSION_ENDED`); account schema
  4 (`Config.RECORDING_DEFAULTS`, `RECORDING`, `RECORD_WHEN`, the rule of `sessions`, migration 3 → 4 and its test;
  `TABS` with `reports`); `ENTERING_WORLD(isInitialLogin, isReloadingUi)` in `Core/Init.lua`; `ThreatModel.IsStale`;
  Compat `zone.RealZoneText`, `instance.Info` read, the NPC id from a GUID, the game events `UNIT_DIED`, `PLAYER_DEAD`,
  `PLAYER_LOGOUT`, `ENCOUNTER_*` (checked against the dump); the *Recording* section of `/atw debug` (recorder part).
  Until M4.3 a closed session is only added and not pruned (behind the switch).
- Done when:
  - [x] A fight in a group gives one session with rows and events as SPEC-05 §1.3–§1.4; chained pulls within 5 s stay
    one session; a fight under 3 s is dropped; a `/reload` in combat leaves the session with the `X` stamp; no session
    in demo, read-only or with the switch off; the three outcomes give the rows of SPEC-02 §4.2.
- *Done (2026-11-26, before M0.7): `Data/Session.lua` (base 62, codes, `units`/`mobs`, `buf` packed every 256 rows and
  events, join, decode, the limits as `Session.LIMITS`) and `Data/Recorder.lua` behind `recording` (conditions,
  END_DELAY and chained pulls, the `record` tick, the events of §1.4, logout and the linked session, the Scanner
  consumer, `SESSION_STARTED`/`SESSION_ENDED`/`SESSIONS_CHANGED`, the *Recording* section of `/atw debug`); account
  schema 4 with migration 3 → 4 and `TABS` with `reports`; `ENTERING_WORLD(isInitialLogin, isReloadingUi)`;
  `ThreatModel.IsStale`; `Compat.ZoneText`, `Compat.InstanceInfo`, `Compat.Unit.NpcID`, `zone.RealZoneText`. Tests:
  `test_session.lua`, `test_recorder.lua`, schema 4 in `test_config.lua`, `test_compat.lua`, `test_init.lua`.*
- Tests: `test_session.lua`, `test_recorder.lua` (every scenario of SPEC-08 QA-03 that ends in a session, SPEC-05 §7),
  schema 4 in `test_config.lua`, the new Compat entries in `test_compat.lua`, `ENTERING_WORLD` in `test_init.lua`.
- Real client: `UNIT_DIED` and `ENCOUNTER_*` payloads (P7), `PLAYER_LOGOUT` at `/reload` and what is saved (P12), GUIDs
  of group members and mobs in instances (P9).

### M4.3 — Storage, schema 4 and limits
- Branch: `step/m4-3-storage`
- Depends on: M4.2
- Spec: SPEC-05 §2, §6; SPEC-02 §3.4, §3.7, §4.5
- Scope: `Data/Storage.lua` behind the `recording` switch (the load of §2.2 with the fast and the deep check,
  interrupted sessions completed with `ended` from `ENTERING_WORLD`, duplicate ids, damaged sessions set aside one by
  one; `Storage.LIMITS`; pruning by `maxSessions` and `maxKB`, never the open session; the size estimate; `Delete`,
  `DeleteAll` with their refusals; read-only; `List`, `Get`, `Usage`, `Decode`, `Add`, `Closed`; `SESSIONS_CHANGED`);
  `Config:SetAside(path, value)`; the storage part of the *Recording* section of `/atw debug`.
- Done when:
  - [x] After every close and load both limits hold (the open session aside); a damaged session goes to `corrupt`
    without touching the others or the settings; an interrupted session is never left `open`; deleted sessions and
    their names are gone after a `/reload`; nothing is written while read-only.
- *Done (2026-11-26, before M0.7): `Data/Storage.lua` behind `recording` (the load at `CONFIG_LOADED` with the fast
  check, sessions with pieces joined and recounted, `ended` from the first `ENTERING_WORLD`, interrupted ones without
  rows dropped, duplicate ids with `-b`, `-c`…, damaged ones set aside one by one with their header only; the deep
  check at `Storage.Decode`, set aside out of combat; pruning by `maxSessions` and `maxKB` after every close, at load
  and at a change of the limits, never the open session; the size per session with `Config.EstimateSize`; `Delete`,
  `DeleteAll` with `off`, `read-only`, `unknown`, `recording`; read-only hides and counts; `List`, `Get`, `Usage`,
  `Decode`, `Add`, `Closed`, `Prune`; `SESSIONS_CHANGED`); the recorder uses `Storage.Add` and `Storage.Closed`;
  `Config:SetAside(path, value, kind)` and `Config.AddIssue`; the storage lines of the *Recording* section of
  `/atw debug`. Tests: `test_storage.lua` (59 cases, a simulated `/reload` in each), `test_recorder.lua` updated (an
  interrupted session is joined at the next load).*
- Tests: `test_storage.lua` (migration from schema 3 data with and without `sessions`, every check, limits, pruning,
  corruption, duplicates, interrupted sessions, delete, read-only, a simulated `/reload` after each case).
- Real client: the real size of the SavedVariables file against the estimate; a `/reload` and a logout during and after
  a fight (P12).

### M4.4 — Combat report
- Branch: `step/m4-4-report`
- Depends on: M4.3
- Spec: SPEC-05 §3.1–§3.5, §6
- Scope: `Data/Report.lua` behind the `reports` switch (the metrics of §3.2 with the periods of §3.3, categories,
  *Not available*, *Insufficient data* under `MIN_ROWS`, lower bounds with partial coverage, interrupted and truncated
  sessions; `Report.Build` in slices of `SLICE`, the in-memory cache; `Report.Summary` for `sum`, called by Storage and
  the recorder at close); the `REPORT_*` locale keys in both languages (wording rules of SPEC-04 §2.4, no hypothesis);
  the end-of-fight notice of §3.5 in `UI/CoachStrip.lua` with `settings.recording.notice`.
- Done when:
  - [ ] Every metric of a known session gives the known answer in the three outcomes and in a mixed session; under 3
    useful rows it says *Insufficient data*; with unknown time it shows a lower bound; the build in slices equals the
    one-pass build; no `REPORT_*` text names a cause or an ability.
- Tests: `test_report.lua`, `test_coach_wording.lua` extended to `REPORT_*`, the notice in `test_coach_strip.lua`.
- Real client: whether the report helps after a real wipe (the exit criterion); how long a report of a long raid fight
  takes to build (P10).

### M4.5 — Reports tab: sessions list and report view
- Branch: `step/m4-5-reports-tab`
- Depends on: M4.4
- Spec: SPEC-05 §3.6; SPEC-03 §4.4, §5; ui-style
- Scope: `UI/Reports.lua` (the *Reports* tab in the wide layout behind the `reports` switch: header with usage, list
  newest first with badges, report view with categories and reasons in tooltips, *Building report…*, delete with
  confirmation, the empty state with its reason, read-only); the *Recording* card in `UI/Settings.lua` behind the
  `recording` switch (SPEC-03 §5, SPEC-05 §3.6); `/atw reports` in `Core/Commands.lua`; the previews `reports-list`,
  `report-values`, `report-state`, `report-unknown`, `settings-recording`; wiki page *Combat Reports* and the *Settings*
  and *Commands* pages, in both languages.
- Done when:
  - [ ] The list and the report show every metric with its category marker and reason; delete needs a second click and
    survives a `/reload`; the card changes the limits at once (pruning applies); nothing of the tab or the card shows
    while the switches are off.
- Tests: `test_reports.lua`, `test_settings.lua` (the card), `test_commands.lua` (`/atw reports`).
- Real client: readability of the list and the report at small sizes and scales; the tab in combat.

### M4.6 — Long tests of recording
- Branch: `step/m4-6-long-tests`
- Depends on: M4.5
- Spec: SPEC-05 §1.8, §7; SPEC-08 §3; SPEC-01 §5.1
- Scope: `Tests/long/test_recorder_raid.lua` (a raid of 40 for an hour of fights with chained pulls, deaths and the
  three outcomes; per-session limits reached; the store near its limits by number and size over many closes; repeated
  `/reload` in combat; the tab and reports opened and closed many times); the third configuration of
  `Tests/long/test_monitor_budget.lua` with recording on, and its budget written into SPEC-01 §5.1 and SPEC-08 §3.
- Done when:
  - [ ] Memory, pieces and the store stop growing at their limits; the budget of the recording tick is measured,
    justified and enforced by the test.
- Real client: CPU of the recording tick and of the Scanner with the window closed, in a party and a raid (P10).

### M4.7 — In-game checklist M4 and MVP check
- Branch: `step/m4-7-checklist`
- Depends on: M4.6
- Scope: `docs/checklists/M4.md` (fights in a party, a dungeon and a raid; chained pulls; a fight under 3 s; `/reload`
  and logout during and after a fight; the three outcomes; the report after a wipe; limits, pruning and deletion; the
  size of the SavedVariables file; the *Recording* card and `when`; the notice; Q8, Q15, Q16); the MVP Definition of
  Done of SPEC-08 §5 walked through; CurseForge page draft for the owner (title and description of SPEC-00 §6, limits
  stated); README status.
- Done when:
  - [ ] The checklist covers every "Real client" line of M4.2–M4.6 and the exit criterion; every item of SPEC-08 §5 is
    marked done, open (with the step that closes it) or waiting for the owner.

### M4.R — Release preparation `v0.4.0`
- Branch: `chore/release-v0.4.0`
- Depends on: M4.7
- Scope: switches `recording` and `reports` on, `SHIPPED_ON` in `test_features.lua` updated; changelog promoted;
  READMEs and wiki status; Release workflow dry run (with `--long`), then the tag
  ([ADR 0014](../adr/0014-one-version-per-milestone-and-feature-switches.md)); CurseForge only if the owner has set up
  the project and `CF_API_KEY` (SPEC-09 Q6).
- Done when:
  - [ ] The `recording` and `reports` switches are on, the later ones off; changelog promoted, status updated; the
    checks are green (quick and long).
  - [ ] The dry run is green, and the tag `v0.4.0` and its GitHub Release (changelog section as notes, zip with only the
    addon) exist.
