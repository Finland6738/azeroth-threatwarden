# Roadmap

This page is the short version and the rules every step follows. **The development steps of each milestone are in
[docs/roadmap/](docs/roadmap/README.md)**, one file per milestone, with the model and effort of the session that runs
each step; the checks behind the plan are in [SPEC-08](docs/specs/SPEC-08-quality-probe-release.md) (Italian).

## Milestones

| Milestone | Branch prefix | Content | Exit criterion | Release |
|---|---|---|---|---|
| **[M0 – Probe](docs/roadmap/M0-probe.md)** | `step/m0-…` | A probe addon (never distributed) answers P1–P12 in the real client: threat APIs, **secret values**, units and mobs, events, combat log, cost | `docs/spike/M0-results.md`, support matrix, specs and ADRs updated | — |
| **[M1 – Foundations](docs/roadmap/M1-foundations.md)** | `step/m1-…` | Skeleton (TOC 16001, Ace3), offline tests with a mock client, Compat, Config with schema, English and Italian, the ecosystem look (Nebula, Aurora, Warden), window, settings, credits, `/atw debug` | loads with no error, window and settings work in both languages | `v0.1.0` |
| **[M2 – Threat Monitor](docs/roadmap/M2-threat-monitor.md)** | `step/m2-…` | Threat on the target, tank, scaled percentage, margin, trend, SAFE / WARNING / DANGER / UNKNOWN, sorting, demo mode | a DPS nearing the tank goes WARNING then DANGER in game | `v0.2.0` |
| **[M3 – Alerts and Coach](docs/roadmap/M3-alerts-coach.md)** | `step/m3-…` | Thresholds, alert channels, cooldowns, quick mute, rule-based Coach with reason and confidence | one alert per transition, never in chat | `v0.3.0` |
| **[M4 – Recording and report](docs/roadmap/M4-recording-report.md)** | `step/m4-…` | Recorder, sessions, storage limits, combat report — **the MVP** | sessions survive `/reload`, honest reports | `v0.4.0` |
| **[M5 – Timeline and Replay](docs/roadmap/M5-timeline-replay.md)** | `step/m5-…` | Threat over time, play, pause, seek, events | a fight replays with estimates and gaps visible | `v0.5.0` |
| **[M6 – Analytics and export](docs/roadmap/M6-analytics-export.md)** | `step/m6-…` | Descriptive metrics, comparison, text and CSV export | every metric traceable to samples | `v0.6.0` |
| **[M7 – Multi-target](docs/roadmap/M7-multi-target.md)** | `step/m7-…` | Several mobs, dungeon focus — **only if M0 allows it** | clean degradation on unreachable mobs | `v0.7.0` |
| **[M8 – Profiles and polish](docs/roadmap/M8-profiles-polish.md)** | `step/m8-…` | Role profiles, heatmap, accessibility, translator guide, CurseForge page | full release checklist | `v0.8.0`, `v1.0.0` |

**Status (2026-11-26):** M1–M4 are complete in code and released as `v0.1.0`–`v0.4.0` (the MVP). M0 waits for the
owner's runs in the real client (M0.7), as do the in-game checklists M1–M4; their exit criteria and the
[MVP check](docs/checklists/M4.md#12-mvp-check) are open. Next: M5.

**Versions** ([ADR 0014](docs/adr/0014-one-version-per-milestone-and-feature-switches.md)): every milestone N is
released as `v0.N.0` after its release preparation `M<N>.R`; fixes raise only the last number; `v1.0.0` follows M8.
Unfinished parts of later milestones are switched off in `Core/Features.lua`: a release never carries half a feature.

## Rules for every step

1. Take the first unticked step of the current milestone file; branch from an up-to-date `main`
   (`step/m<N>-<k>-<name>`).
2. Keep the step small; open an issue for anything outside it.
3. Update in the same branch: `CHANGELOG.md`, the affected specs and ADRs, `README.md` and `README.it.md` when features
   or status change, and **`docs/wiki/` in both languages for anything a user can see**; tick the step with a *Done*
   note.
4. Run `python -I -X utf8 tools/check_docs.py` and, from M1.3, `python -X utf8 Tests/run_tests.py`.
5. Ship: `python -I -X utf8 tools/ship_step.py --title "M<N>: <summary>" --body-file <pr.md> --commit "<message>"`
   squashes the step into one noreply commit, pushes, opens the pull request, waits for CI and fast-forwards `main`
   ([ADR 0006](docs/adr/0006-git-flow-and-automated-shipping.md)). The wiki is published automatically after the merge.
6. The pull request says honestly what was **not** verified in the real client.
