# 0018. Analytics and export are computed in memory from the sessions, and leave the game only through a copy box

- Status: Accepted (M6.1, before the M0 probe; to verify in the game: the copy box with large texts)
- Date: 2026-11-26

## Context

M6 adds Threat Analytics (descriptive metrics per fight and across fights) and an export as text and CSV (the owner's
specification §4.2, §5.5). A session holds only what the monitor read (ADR 0016), in values, *state only* or nothing
readable; the report (M4) and the timeline (M5) already compute crossings, times, holders and data quality from it with
shared functions (ADR 0017). Four questions had to be settled before the modules are written:

1. **Where the metrics live.** They could be computed at the end of each fight and saved next to the session (fast to
   compare, a new account schema), or computed again from the rows when they are needed.
2. **How they relate to the report.** A second implementation of crossings or times could give numbers that disagree
   with the report on the same fight.
3. **What can be compared.** Fights against different enemies, with different thresholds or with different readable
   data give numbers that look comparable and are not.
4. **How data leave the game.** Addons cannot write files; the dump lists `CopyToClipboard`, which has never run on
   Forever and would move data without the player's gesture; ADR 0001 keeps everything local.

## Decision

1. **Analytics are computed in memory, never saved.** `Data/Metrics.lua` computes the metrics of one session from
   `Storage.Decode`, in slices, and keeps at most 25 in a cache dropped with the session; `Data/Compare.lua` builds a
   comparison one session at a time, paused in combat. No key is added to a session and no schema changes; the overview
   of the enemies uses only the headers and `sum` that M4 already saves.
2. **The report's functions, plus one stricter rule.** Where a metric exists in the report, Analytics takes the
   report's own cell (`Report.Compute`) or its pass over the events (`Report.Walk`, with one new `holder` hook), so the
   numbers are identical. Analytics adds only what the report lacks (time with a unit in Warning or Danger, changes of
   the enemy's holder, the threat closest to the tank, unstable intervals, risk situations per minute) and the
   specification's rule that a metric with fewer than half the samples readable, or an enemy monitored for less than
   half the fight, is *Insufficient data*.
3. **Only like with like.** A comparison groups fights by the main enemy (creature number, else name and
   classification), with the same group size, difficulty and player role by default; a state metric is compared only
   between fights with the same recorded thresholds (or all on game states), a percentage only between fights with
   values. Aggregates are totals, medians and ranges with their category; nothing ranks people or declares a trend.
4. **The export is text in a read-only copy box.** `Data/Export.lua` (adapted from Azeroth Accord) writes CSV
   (RFC 4180, formula guard) and text (code blocks in parts for a chat), at most 256 KB with whole rows, into a box
   where the text is already selected and the player presses Ctrl+C. `CopyToClipboard` is not used. A warning about the
   group's names is always above the box, with an option to replace them with *Player 1, Player 2…*.

The detailed rules are in [SPEC-06](../specs/SPEC-06-analytics-export.md) (Italian).

## Alternatives considered

- **Metrics saved with each session at the end of the fight.** Comparisons open at once, but a new account schema and
  migration are needed, the saved figures could disagree with a report computed by a later version, and the saved data
  grow; decoding a session costs about as much as a report, which is already built in slices.
- **A separate implementation of the metrics.** Simpler code in one file, but two definitions of a crossing would
  sooner or later disagree with the report and the timeline.
- **Comparing every recorded fight.** More numbers, but a median over a dungeon trash pack and a raid boss means
  nothing, and *state only* fights would look like fights without crossings.
- **`CopyToClipboard` or a file.** Addons cannot write files; the clipboard function is unverified on Forever and would
  copy without the player seeing what leaves.
- **Names replaced by default.** Safer when the text is posted publicly, but most exports go to the same group, who
  need the names; the warning is always visible and the switch is one click.

## Consequences

- Positive: report, timeline and analytics cannot disagree on the same fight; nothing new is stored; the player sees
  every character that leaves the game before copying it.
- Negative: a comparison decodes up to 20 sessions again each time it is built (paused in combat); the size limit of
  the copy box cuts the readings of long fights; the box with 256 KB of text, the `||` escape and the paste into
  Discord and a spreadsheet must be checked in the game (checklist M6.6).
