# M5 — Threat Timeline and Threat Replay

**Goal:** see how threat evolved in a recorded fight and step through it
([SPEC-05 §4–§5](../specs/SPEC-05-recording-report-replay.md)).

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

### M5.1 — Specification — Branch `step/m5-1-spec`
### M5.2 — Timeline model — Branch `step/m5-2-timeline-model`
- Scope: `Data/Timeline.lua`: series per unit from samples, downsampling for the width, threshold and event markers,
  detected vs estimated segments, gaps. Tests: `test_timeline.lua`.
### M5.3 — Timeline widget — Branch `step/m5-3-timeline-widget`
- Scope: `UI/Timeline.lua` (lines from textures, interval selection, sample tooltip, dashed estimates). Tests on the
  layout maths.
### M5.4 — Replay controller and event list — Branch `step/m5-4-replay`
- Scope: `Data/Replay.lua` (play, pause, step, seek, event ±5 s window, missing data). Tests: `test_replay.lua`.
### M5.5 — Replay window — Branch `step/m5-5-replay-window`
- Scope: `UI/ReplayWindow.lua`, wiki page *Threat Replay* (both languages), previews.
### M5.6 — In-game checklist M5 — Branch `step/m5-6-checklist`
### M5.R — Release preparation `v0.5.0` — Branch `chore/release-v0.5.0`
