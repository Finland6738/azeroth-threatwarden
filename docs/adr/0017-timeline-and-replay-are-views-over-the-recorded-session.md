# 0017. Timeline and replay are views over the recorded session, drawn from bounded pools in a window of their own

- Status: Accepted (M5.1, before the M0 probe; to verify in the game: line regions, cost, keyboard)
- Date: 2026-11-26

## Context

M5 shows a recorded fight as a timeline and lets the player step through it (the owner's specification §5.3–§5.4).
A session holds only what the monitor read (ADR 0016): numbered rows for new readings, coded rows when a reading was
unknown, and the monitor's events. The probe has not run (owner decision D7), so a session may hold values, states
only, or nothing readable, and may change in the middle of a fight. Four questions had to be settled before the
modules are written:

1. **Where the timeline comes from.** It could be computed while recording (a second, coarser series saved next to
   the rows) or derived later from the rows and events.
2. **What a line means.** A line between two readings suggests values the client never gave; the specification asks
   for a visible difference between detected data and estimates, and ADR 0003 forbids presenting an estimate as data.
3. **How it is drawn.** A fight of 30 000 rows cannot become 30 000 regions; the dump of Forever has `CreateLine`
   (`SetStartPoint`, `SetEndPoint`, `SetThickness`), but it has never run in this client.
4. **Where the replay lives.** The main window has a compact layout for combat and a wide one for reading; a replay
   needs a wide chart, an event list and a detail panel at once.

## Decision

1. **Timeline and replay are read-only views over the session.** `Data/Timeline.lua` builds a model from
   `Storage.Decode` (in slices, like the report) with the same period, holder and crossing functions as
   `Data/Report.lua`; `Data/Replay.lua` moves a cursor over that model. Nothing is written into the session and the
   account schema does not change; nothing is read from the game.
2. **Every vertex is a reading; lines carry a category.** The model never averages or interpolates: to fit the width
   it keeps the first, last, lowest and highest reading of each column. Between two consecutive readings the segment is
   **solid** (detected) when they are no further apart than the recording's own gap rule (`max(3 / Hz, 1 s)`),
   **dashed** (estimated) when they are further apart with nothing unknown recorded in between (up to 10 s), and
   **absent** otherwise; a gap is drawn as a hatched band with its reason and is never crossed. The replay's detail
   shows an old reading as an estimate with its age, or says that there is no reading and why.
3. **Drawn from bounded pools.** `UI/Timeline.lua` draws segments with the client's `Line` regions and bands with
   textures, taken from pools capped at 3 000 lines and 1 200 textures; past a cap the columns get wider instead of
   data being dropped. Without `CreateLine` the chart falls back to points and min–max bars, never to rotated textures.
   Hover and drag use an `OnUpdate` only while the pointer is over the chart; playback is a named Scheduler tick at
   10 Hz, paused in combat. Colours come from six new series tokens per theme; the four state tokens stay for states.
4. **The replay has a window of its own**, `AzerothThreatwardenReplay`, opened from the Reports tab (which keeps the
   list of fights and the deletion of M4), from the report's timeline card and with `/atw replay`. Its position, size
   and speed are kept per character, so the character schema goes to 2.

The detailed rules are in [SPEC-05 §4–§5 and §9–§10](../specs/SPEC-05-recording-report-replay.md) and
[SPEC-02 §3.9](../specs/SPEC-02-data-model-storage.md#39-schema-2-del-personaggio-m5-la-finestra-del-replay) (Italian).

## Alternatives considered

- **A second, downsampled series saved while recording.** Faster to open, but it doubles what is stored, would need a
  new account schema and could disagree with the rows; the rows already allow random access (fixed width, ADR 0016).
- **Averaging or interpolating to fit the width** (or a smoothed line). Looks cleaner, but shows values no one read
  and hides peaks: a crossing could disappear when the chart is zoomed out.
- **Every segment dashed, or every segment solid.** All dashed makes the distinction meaningless; all solid presents
  the drawing between two sparse readings as data.
- **Lines from rotated textures or a step chart of plain textures.** Rotated textures need trigonometry per segment
  and look poor at fractional scales; a step chart claims the value held until the next reading.
- **The replay as a fourth tab of the main window.** One frame less, but the wide layout is sized for cards, and a tab
  would hide the monitor while a replay is open.

## Consequences

- Positive: timeline, replay and report cannot disagree, because they read the same rows with the same functions;
  missing data are always visible; the cost is bounded by the width of the chart, not by the length of the fight.
- Negative: opening a replay decodes the session again (one decoded session is cached); dashed segments will be rare
  with the default settings, so most of the visible difference is between lines and gaps; the line regions, the number
  of regions per frame and the keyboard of the replay window must be checked in the game (checklist M5.6).
