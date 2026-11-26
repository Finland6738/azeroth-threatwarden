# 0016. Recordings are the monitor's own readings, kept as compact columns in the account variable

- Status: Accepted (M4.1, before the M0 probe; to verify in the game: P7, P10, P12)
- Date: 2026-11-26

## Context

M4 records every fight so that a report can be shown after it (and, from M5, a timeline and a replay). Three questions
had to be settled before the recorder is written:

1. **What is recorded.** The recorder could call the threat functions itself, at its own pace, or record what the
   monitor (Scanner, Model, State) already read. The probe has not run (owner decision D7): threat may come as values,
   as a state only, or not at all, and may change in the middle of a fight.
2. **How it is stored.** The client writes a Lua array element as a line with its index comment, about 20 bytes for a
   small number: a fight of a raid of 25 sampled at 2 Hz for three minutes would take close to 2 MB in plain tables,
   the whole proposed budget (SPEC-09 Q8) for one session.
3. **Where it is stored.** ADR 0005 put recordings in `AzerothThreatwardenDB`; a third SavedVariable only for sessions
   would keep them apart from the settings.

## Decision

1. **The recorder never reads the client's threat functions.** It samples the rows of `Data/ThreatModel.lua` on its own
   bounded tick and records the monitor's Bus events (`STATE_CHANGED`, `AGGRO_CHANGED`, `TARGET_CHANGED`,
   `THREAT_MODE_CHANGED`, `ALERT_RAISED`, `COACH_TIP`), so a session holds exactly what the player was shown, with the
   same categories and reasons (ADR 0003). It makes the Scanner read with the window closed by declaring itself a
   consumer. Unknown readings are recorded as a code with their reason, only when the reason changes; nothing is filled
   in afterwards (ADR 0004 point 4).
2. **Samples are stored as compact columns:** one string per column (time, mob, unit, scaled percent, reading code),
   fixed-width fields in a base-62 alphabet, so a sample row costs 8 characters, any row can be read without decoding
   the rest, and the client writes the strings without escapes. Events are fixed-width records of 12 characters in one
   string. Margin, trend and predictions are not stored: the report recomputes them from the detected values. While a
   session is open, rows go into a small reused buffer packed into string pieces every 256 rows, and the open session
   already sits in the saved table, so a `/reload` keeps it.
3. **Sessions stay in `AzerothThreatwardenDB.sessions`** (account schema 4), as ADR 0005 point 2 and the owner's names
   (SPEC-09 Q1) say. `Data/Storage.lua` checks each session on its own and sets a damaged one aside in `corrupt`, so
   one bad session never touches the settings or the others; `Config` only checks that `sessions` is a table.
4. Limits are per session (rows, events, units, mobs) and in total (number of sessions and estimated size, settings
   with the proposed defaults of Q8); the oldest closed sessions are removed first.

The detailed format is in [SPEC-02 §4](../specs/SPEC-02-data-model-storage.md#4-sessioni-registrate-schema-4-m4) and
the behaviour in [SPEC-05 §1–§3](../specs/SPEC-05-recording-report-replay.md) (Italian).

## Alternatives considered

- **A recorder that reads the threat functions itself.** Twice the reading cost in combat, and a second source that
  could disagree with what the monitor showed; the report could then claim something the player never saw.
- **Plain Lua tables per sample** (`{ t = …, unit = …, pct = … }`). Simple, but about ten times larger in the saved
  file, and many small tables in memory during a fight (ARC-06).
- **Delta or run-length encoding of the numbers.** Smaller still, but every row would need the rows before it to be
  read; fixed width keeps random access for the replay of M5 and makes a damaged column easy to detect.
- **A third SavedVariable** (`AzerothThreatwardenSessionsDB`). Would isolate a damaged recording file from the settings,
  but adds a name the owner did not choose; per-session checks give the same isolation inside the account variable.
  Copying sessions during a future migration is cheap because Lua copies strings by reference.

## Consequences

- Positive: the report says no more than the monitor knew; the size of a session is predictable (at most about
  320 KB) and the limits always leave room; a `/reload` in combat keeps all but the last unpacked rows.
- Negative: with recording on, the Scanner reads in every recorded fight even with the window closed (its cost, SPEC-01
  §5.1, applies there too: P10 decides); the format is not human-readable in the saved file; a change of the format is
  a new account schema with a migration that converts or sets aside the old sessions.
