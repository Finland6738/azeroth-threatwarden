# M5 — Threat Timeline and Threat Replay

**Goal:** see how threat evolved in a recorded fight and step through it
([SPEC-05 §4–§5](../specs/SPEC-05-recording-report-replay.md)).

> **Started before M0.7, like M2–M4** (owner's decision D7, [SPEC-00 §7](../specs/SPEC-00-vision-scope.md#7-registro-delle-decisioni)).
> Timeline and replay are read-only views over a recorded session
> ([ADR 0017](../adr/0017-timeline-and-replay-are-views-over-the-recorded-session.md)): they show what the monitor read,
> as values, *state only* or nothing readable (SPEC-05 §4.6), and never fill a gap. The source specification's gate
> (§8: no promise of a complete replay before the probe) holds: the wiki and the release notes say what depends on the
> probe (P3, P10) and nothing is promised beyond what a session holds.

**Exit criterion:** a recorded fight opens as a timeline with its events; play, pause, seek and step work; estimates and
gaps are visibly different from detected samples. Released as `v0.5.0`.

| Step | Model | Effort |
|---|---|---|
| M5.1 Specification of timeline and replay | Opus | high |
| M5.2 Timeline model (series, downsampling, markers) | Opus | medium |
| M5.3 Timeline widget | Sonnet | high |
| M5.4 Replay controller and event list | Sonnet | high |
| M5.5 Replay window, wiki and previews | Sonnet | medium |
| M5.6 In-game checklist M5 | Sonnet | low |
| M5.R Release preparation `v0.5.0` | Sonnet | medium |

**Switches.** `timeline` (the model, the chart widget, the report's *Timeline* card) and `replay` (the controller, the
replay window, the *Replay* button, `/atw replay`) in `Core/Features.lua` stay **off** until M5.R; the replay needs
both. Every step works and is tested behind them (SPEC-05 §9); tests that need them set them to `true` in
`M.features`. Character schema 2 (`ui.replay`) is written even with the switches off, as the defaults of M4 were before
M4.R. Nothing is added to the sessions and the account schema stays 5.

### M5.1 — Specification of timeline and replay
- Branch: `step/m5-1-spec`
- Spec: SPEC-05 §4–§5, SPEC-02 §4, SPEC-03 §4, ui-style, SPEC-09
- Scope: SPEC-05 §4–§5 and §8–§10 completed (the timeline model: series of real readings, solid, dashed and absent
  segments, gaps with their reason, markers, the three outcomes over time, default series, downsampling for the width;
  the widget: layout, bounded pools of line regions and textures, dashes, colours, hover, click, drag, the report's
  timeline card; the replay controller: cursor, playback, steps, ±5 s, detail, missing data, event list, combat; the
  replay window: where it opens from, layout, keys, every empty and unknown state); SPEC-02 §3.9 (character schema 2);
  ui-style §3.5; decisions in SPEC-00 §7; open questions in SPEC-09; the steps below detailed.
- Done when:
  - [x] SPEC-05 says, for every element of the timeline and every state of the replay, its source, its category and
    what happens in *state only*, with nothing readable and in an interrupted or truncated session; `check_docs.py`
    passes.
- *Done (2026-11-26, before M0.7): SPEC-05 §4 (rules RPL-01–RPL-05; the model built in slices with the report's own
  period functions; a segment is solid within the recording's gap rule `max(3 / Hz, 1 s)`, dashed as an estimate up to
  10 s with nothing unknown in between, absent otherwise; six kinds of gap; markers for every event kind, grouped under
  8 px; values / state only / nothing readable / mixed; at most 6 series; first, last, lowest and highest reading per
  2 px column, never an average; the widget with `Line` regions and pools capped at 3 000 lines and 1 200 textures, a
  points-only fallback, six series tokens per theme, hover, click, drag, wheel, interval summary, and the *Timeline*
  card of the report), §5 (RPL-06–RPL-08; the controller with a 10 Hz `replay` tick paused in combat, speeds 1–8×,
  steps to recorded moments, 5 s jumps, ±5 s around an event, the detail with the three categories, missing data, the
  event list with three filters; the window `AzerothThreatwardenReplay` opened from Reports, the timeline card and
  `/atw replay [n]`, its layout, keys out of combat only, and the table of states), §8–§10 (game checks, modules,
  switches, `/atw debug`, `REPLAY_REQUESTED`, tests per step); SPEC-02 §3.9 (character schema 2 with `ui.replay`); new
  [ADR 0017](../adr/0017-timeline-and-replay-are-views-over-the-recorded-session.md); SPEC-00 D13–D16; SPEC-09
  Q18–Q20 new, Q17 and R11; SPEC-01, SPEC-03, ui-style §3.5 and ARCHITECTURE for the new modules, event, frame and
  Compat entries. Nothing changes in the addon.*

### M5.2 — Timeline model
- Branch: `step/m5-2-timeline-model`
- Depends on: M5.1
- Spec: SPEC-05 §4.1–§4.7, §9, §10; ADR 0017
- Scope: `Data/Timeline.lua` behind the `timeline` switch: `Timeline.Build(id, done)` in slices of `SLICE` with the
  in-memory cache dropped at `SESSIONS_CHANGED`, `Timeline.Compute(s, d, step)`, the model of §4.2 (periods, mob and
  mode bands, gaps, series with readings, states, holds, unknown and presence intervals, maximum, crossings, outcome,
  default series and lanes), the segments of §4.3 (`join`, `ESTIMATE_MAX`, every break), the gaps of §4.4 and the
  markers of §4.5 with their grouping rule as a pure function, `Timeline.View` (first, last, lowest, highest reading per
  column, `MIN_VIEW`, `BUCKET_PX`, `MAX_BUCKETS`, reused output) and `Timeline.Summary`; `Data/Report.lua` exposes its
  period, holder and crossing functions for the timeline (the report's results and tests unchanged); the `TIMELINE_*`
  locale keys of markers, gaps and outcomes in both languages; the model lines of the *Timeline and replay* section of
  `/atw debug`; `Data/Timeline.lua` in the TOC after `Data/Report.lua`.
- Done when:
  - [ ] Known sessions give known models in the three outcomes and in a mixed, an interrupted and a truncated one; every
    segment kind and every gap kind of §4.3–§4.4 is produced with its category and reason; crossings equal the
    report's; `View` equals a brute-force pass and keeps every peak; the build in slices equals the one-pass build;
    nothing is built with the switch off.
- Tests: `test_timeline.lua` (SPEC-05 §10, sessions from the real recorder in the three `Fight.OUTCOMES` and hand-made
  ones for exact cases); the report tests unchanged; the budget of `View` over 30 000 rows in a long test.
- Real client: how long `Timeline.Build` takes on a real raid session (P10); which outcome real groups give (P3).

### M5.3 — Timeline widget
- Branch: `step/m5-3-timeline-widget`
- Depends on: M5.2
- Spec: SPEC-05 §4.8, §9; ui-style §3.5; SPEC-01 §8.2
- Scope: `UI/Timeline.lua` behind `timeline` (`Timeline.Widget`: legend, chart, lanes, event track, time axis; lines
  from `Line` regions and bands from textures in pools capped at `MAX_LINES` and `MAX_TEXTURES` with the doubling of
  `BUCKET_PX`; dashes; gaps with the `dash` texture; grouped markers; the points-only fallback without `CreateLine`;
  hover with an `OnUpdate` only while the pointer is over the chart, click, drag selection, right-click, wheel zoom;
  the interval summary); the tokens `series-1`…`series-6` in every theme of `UI/Theme.lua`, with their contrasts in
  ui-style §3.5 and `lines` in `Theme.Probes()`; `Compat.CursorPosition` (checked against the dump); the *Timeline*
  card in the report of `UI/Reports.lua` (built after the report, click → `REPLAY_REQUESTED(id, t)` only with the
  `replay` switch); `Line` regions and `GetCursorPosition` in the mock client (from the dump); the pool lines of
  `/atw debug`.
- Done when:
  - [ ] The chart draws every element of SPEC-05 §4.2–§4.5 with its look of ui-style §3.5 in the three themes; dashed
    and gap elements never look like a solid line; the pools stop at their caps without dropping data; the tooltip
    names the category of every value; nothing shows with the switch off.
- Tests: `test_timeline_widget.lua` (the layout maths, the tooltip in each category, click and drag, caps and fallback,
  no colour outside the theme), `test_theme.lua` (series tokens and contrasts), `test_reports.lua` (the card),
  `test_compat.lua` (`CursorPosition`).
- Real client: `Line` regions on Forever (thickness, edges at fractional scales, 4 px dashes); how many regions the
  chart can hold before the frame rate drops; `GetCursorPosition` against the UI and window scale; the six series
  colours on screen.

### M5.4 — Replay controller and event list
- Branch: `step/m5-4-replay`
- Depends on: M5.3
- Spec: SPEC-05 §5.1–§5.4, §9, §10; SPEC-09 Q18, Q19
- Scope: `Data/Replay.lua` behind `replay` (and `timeline`): `Replay.state`, `Open`, `Close`, `Play`, `Pause`,
  `Toggle`, the 10 Hz `replay` Scheduler tick with the clamped time step, `Seek`, `Step` to recorded moments, `Jump`,
  `NextEvent`, `Focus` with the ±5 s window, `SetSpeed` (`SPEEDS`), `SetView`, `WholeFight`, `SetSeries`, `SetFilter`,
  `Snapshot` (the three categories and the missing-reading texts of §5.3), `Missing`, `Events` with the three filters,
  `OnChange`; pause and refusal in combat (`PAUSE_IN_COMBAT`, Q18); closing when the session is deleted; the
  `REPLAY_*` locale keys of the detail, the missing data and the event list in both languages; the wording test
  extended to `TIMELINE_*` and `REPLAY_*`; the replay lines of `/atw debug`.
- Done when:
  - [ ] Play, pause, seek, step, jump and event focus move the cursor as SPEC-05 §5.2 says at every speed; the detail
    gives every value its category and says why a value is missing; ±5 s lists the missing data or *No missing data in
    this window*; playback pauses in combat; the tick allocates nothing; nothing runs with the switches off.
- Tests: `test_replay.lua` (SPEC-05 §10), `test_coach_wording.lua` extended.
- Real client: whether pausing in combat is the right default (Q18); the tick's cost out of combat (P10).

### M5.5 — Replay window, wiki and previews
- Branch: `step/m5-5-replay-window`
- Depends on: M5.4
- Spec: SPEC-05 §5.5–§5.6, §9, §10; SPEC-02 §3.9; SPEC-03 §4.4; ui-style §3.5
- Scope: `UI/ReplayWindow.lua` behind `replay` (the frame `AzerothThreatwardenReplay`: title bar with the session line
  and badges, the timeline with lanes, the controls and the speed, the event list in a pooled scroll with the filters,
  the detail with the ±5 s missing data, the single-panel layout under 760 pt, the table of states, keys out of combat
  only with the other keys passed to the game, Esc, position, size and speed per character); character schema 2 in
  `Core/Config.lua` (`ui.replay`, migration 1 → 2 and its test); the *Replay* button in the report's head card;
  `/atw replay [n]` in `Core/Commands.lua`; `Compat.ModifierDown`; the icons `play`, `pause`, `step-back`,
  `step-forward`, `skip-back`, `skip-forward` (`tools/make_media.py`, `UI/Assets.lua`); `Tests/long/test_replay_long.lua`;
  the previews `replay-values`, `replay-state`, `replay-unknown`, `replay-event`, `report-timeline`
  (`tools/make_mockups.py`); the wiki page *Threat Replay* and the updates of *Combat Reports*, *Commands* and the
  sidebar, in both languages.
- Done when:
  - [ ] A recording opens in the replay window from the button, the timeline card and `/atw replay`; every state of
    the table of SPEC-05 §5.5 shows its text; the keys work only out of combat and over the window; position, size and
    speed survive a `/reload`; opening and closing the replay many times does not grow memory or pools; nothing shows
    with the switches off.
- Tests: `test_replay_window.lua`, `test_config.lua` (character schema 2), `test_commands.lua` (`/atw replay`),
  `Tests/long/test_replay_long.lua` (source §13: repeated opening and closing of the replay).
- Real client: `SetPropagateKeyboardInput` out of combat and conflicts with the game's key bindings; the window at
  640 × 420 pt and at common UI scales; readability of the event list and the detail.

### M5.6 — In-game checklist M5
- Branch: `step/m5-6-checklist`
- Depends on: M5.5
- Scope: `docs/checklists/M5.md` (switches on in the installed copy while they are off, backup of the saved data; a
  recorded fight in a party, a dungeon and a raid opened as a timeline and a replay; the three outcomes and a mixed
  fight; an interrupted and a truncated recording; play, pause, seek, step, jump, event focus with ±5 s and missing
  data; combat while the replay is open (Q18); the keys and Esc (Q19); dashed segments and gaps (Q20); the report's
  timeline card; the line regions, the frame rate and the series colours in the three themes; the window at small sizes
  and scales; position and speed after a `/reload`); the checklists index; README status.
- Done when:
  - [ ] The checklist covers every "Real client" line of M5.2–M5.5 and the exit criterion.

### M5.R — Release preparation `v0.5.0`
- Branch: `chore/release-v0.5.0`
- Depends on: M5.6
- Scope: switches `timeline` and `replay` on, `SHIPPED_ON` in `test_features.lua` updated; changelog promoted; READMEs
  and wiki status; `docs/curseforge.md` with the title *… & Combat Replay* and the keyword *combat replay* (SPEC-09
  Q17); Release workflow dry run (with `--long`), then the tag
  ([ADR 0014](../adr/0014-one-version-per-milestone-and-feature-switches.md)); CurseForge only if the owner has set up
  the project and `CF_API_KEY` (SPEC-09 Q6).
- Done when:
  - [ ] The `timeline` and `replay` switches are on, the later ones off; changelog promoted, status updated; the checks
    are green (quick and long).
  - [ ] The dry run is green, and the tag `v0.5.0` and its GitHub Release (changelog section as notes, zip with only
    the addon) exist.
