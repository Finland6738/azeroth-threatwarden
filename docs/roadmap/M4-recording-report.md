# M4 — Recording and combat report (MVP)

**Goal:** record every fight while it happens and show an essential, honest report at the end
([SPEC-05 §1–§3](../specs/SPEC-05-recording-report-replay.md)). This completes the **MVP**.

**Exit criterion:** in game, fights become separate sessions that survive `/reload`; the report of each shows duration,
threshold crossings, time in WARNING and DANGER and tank changes, and says "Insufficient data" where it must; storage
limits hold. Released as `v0.4.0`, the first CurseForge candidate (SPEC-09 Q6).

| Step | Model | Effort |
|---|---|---|
| M4.1 Specification of recorder, storage and report | Opus | high |
| M4.2 Recorder and sessions | Opus | medium |
| M4.3 Storage, schema 2 and limits | Opus | high |
| M4.4 Combat report | Sonnet | medium |
| M4.5 Reports tab: sessions list and report view | Sonnet | medium |
| M4.6 Long tests of recording | Sonnet | high |
| M4.7 In-game checklist M4 and MVP check | Sonnet | low |
| M4.R Release preparation `v0.4.0` | Sonnet | medium |

### M4.1 — Specification of recorder, storage and report
- Branch: `step/m4-1-spec`
- Spec: SPEC-05 §1–§3, SPEC-02 §4, SPEC-09 Q8, Q15

### M4.2 — Recorder and sessions
- Branch: `step/m4-2-recorder`
- Scope: `Data/Recorder.lua`, `Data/Session.lua` (start and end, samples, events, gaps, duplicates, reload and logout).
- Tests: `test_recorder.lua` (every scenario of SPEC-08 QA-03 that ends in a session).

### M4.3 — Storage, schema 2 and limits
- Branch: `step/m4-3-storage`
- Scope: `Data/Storage.lua` (compact columns, `LIMITS`, pruning, size estimate, damaged sessions set aside), migration
  1 → 2, delete one or all.
- Tests: `test_storage.lua` (migration from schema 1 data, limits, corruption, reload).

### M4.4 — Combat report
- Branch: `step/m4-4-report`
- Scope: `Data/Report.lua` (metrics of SPEC-05 §3 with categories and "Insufficient data"); optional end-of-fight
  notice.
- Tests: `test_report.lua` (known sessions, known answers).

### M4.5 — Reports tab
- Branch: `step/m4-5-reports-tab`
- Scope: *Reports* tab (sessions list, report view, delete), `/atw reports`; wiki page *Combat Reports*; previews.

### M4.6 — Long tests of recording
- Branch: `step/m4-6-long-tests`
- Scope: long sessions, storage near the limit, reload in combat, repeated open and close.

### M4.7 — In-game checklist M4 and MVP check
- Branch: `step/m4-7-checklist`
- Scope: `docs/checklists/M4.md`; the MVP Definition of Done of SPEC-08 §5 walked through; CurseForge page draft for
  the owner (title and description of SPEC-00 §6, limits stated).

### M4.R — Release preparation `v0.4.0`
- Branch: `chore/release-v0.4.0`
