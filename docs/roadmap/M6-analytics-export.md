# M6 — Threat Analytics and export

**Goal:** descriptive, verifiable metrics per fight and across fights, and an export to copy
([SPEC-06](../specs/SPEC-06-analytics-export.md)).

> **Started before M0.7, like M2–M5** (owner's decision D7, [SPEC-00 §7](../specs/SPEC-00-vision-scope.md#7-registro-delle-decisioni)).
> Analytics and export only read recorded sessions and save nothing
> ([ADR 0018](../adr/0018-analytics-and-export-are-computed-in-memory-and-leave-only-through-a-copy-box.md)): where the
> report has a metric they use the report's own cells, and a metric with fewer than half the samples readable is
> *Insufficient data* (ANA-02). A session may hold values, *state only* or nothing readable (SPEC-06 §0); the wiki and
> the release notes say how much of Analytics depends on the probe (P3, P9).

**Exit criterion:** every metric shown can be traced to recorded samples; "Insufficient data" appears where it must; an
export can be copied as text or CSV, with names replaceable. Released as `v0.6.0`.

| Step | Model | Effort |
|---|---|---|
| M6.1 Specification of analytics and export | Opus | high |
| M6.2 Metrics per session | Opus | medium |
| M6.3 Comparison and aggregates | Opus | medium |
| M6.4 Analytics view | Sonnet | medium |
| M6.5 Export (text and CSV) | Sonnet | medium |
| M6.6 In-game checklist M6 | Sonnet | low |
| M6.R Release preparation `v0.6.0` | Sonnet | medium |

**Switches.** `analytics` (`Data/Metrics.lua`, `Data/Compare.lua`, the *Analytics* page and the report's *Analytics*
card) and `export` (`Data/Export.lua`, the export box, the *Export* buttons) in `Core/Features.lua` stay **off** until
M6.R; the export needs both (and `reports`). Every step works and is tested behind them (SPEC-06 §5); tests that need
them set them to `true` in `M.features`. Nothing is added to the sessions, the account schema stays 5 and the
character schema 2.

### M6.1 — Specification of analytics and export
- Branch: `step/m6-1-spec`
- Spec: SPEC-06, SPEC-05 §3–§4, SPEC-02 §4, SPEC-03 §4.4, ui-style, SPEC-09
- Scope: SPEC-06 completed (principles and the three outcomes; every metric per session with its formula over the
  recorded rows and events, category, *Insufficient data* rule and behaviour in each outcome and in interrupted,
  truncated, linked and mixed sessions, reusing the report's cells; unstable intervals and risk situations; what can be
  compared and the aggregates; the overview by enemy; the *Analytics* page and card of the Reports tab; the export as
  text and CSV with its columns, escaping, parts, names and size limit, and the copy box; modules, switches, `/atw
  debug`, tests per step, game checks); a new ADR; decisions in SPEC-00 §7; open questions in SPEC-09; ui-style §3.6;
  the steps below detailed.
- Done when:
  - [x] SPEC-06 says, for every metric and every export column, its source in the session, its category and what
    happens in *state only*, with nothing readable and in an interrupted or truncated session; `check_docs.py` passes.
- *Done (2026-11-26, before M0.7): SPEC-06 §0 (read-only, the report's own definitions, the three outcomes, no
  ranking), §1 (ANA-01–ANA-05; the two bases of valid samples and the coverage of the fight; the order that decides a
  metric's state; the metrics: context, valid samples, threshold crossings, time with a unit in Warning or Danger,
  changes of the enemy's holder split three ways, taken by a non-tank, highest recorded and closest-to-the-tank
  percentages, unstable intervals of 3 changes within 10 s, risk situations per minute of known combat; interrupted,
  truncated, linked and mixed sessions; the model built in slices with a cache of 25), §2 (comparison by main enemy with
  group, difficulty and role filters, same thresholds for state metrics, at most 20 fights, totals, medians and ranges,
  at least 2 fights; the overview from the headers; the queue paused in combat), §3 (the *Recordings · Analytics*
  selector, the page, the report's *Analytics* card, the table of states, previews and wiki), §4 (EXP-01–EXP-07; four
  contents; CSV columns and values; text in code blocks of 1 900 characters; names warning and *Player n*; the copy box
  and the client's limits; sizes), §5–§7 (modules, switches, `/atw debug`, tests per step, game checks); new
  [ADR 0018](../adr/0018-analytics-and-export-are-computed-in-memory-and-leave-only-through-a-copy-box.md); SPEC-00
  D17–D20; SPEC-09 Q15 (proposed answer for the export), Q22–Q24 new and R12; SPEC-01, SPEC-02, ui-style §3.6 and
  ARCHITECTURE for the new modules. Nothing changes in the addon.*

### M6.2 — Metrics per session
- Branch: `step/m6-2-metrics`
- Depends on: M6.1
- Spec: SPEC-06 §1, §5, §6; SPEC-05 §3; ADR 0018
- Scope: `Data/Metrics.lua` behind the `analytics` switch: `Metrics.Compute(s, d, step)` (the report's cells through
  `Report.Compute`, a `Report.Walk` pass with the `state`, `hold`, `cross`, `watch` and new `holder` hooks, a pass over
  the rows for the closest-to-the-tank percentage), the bases and the coverage of §1.2, the state order of §1.3 with
  `MIN_VALID`, `MIN_COVERAGE`, `MIN_RATE_TIME`, the metrics of §1.4, the unstable intervals of §1.5
  (`UNSTABLE_WINDOW`, `UNSTABLE_MIN`, `MAX_UNSTABLE`), the sessions of §1.6; `Metrics.Build(id, done)` in slices of
  `SLICE` with the cache of `CACHE` sessions dropped at `SESSIONS_CHANGED`; the words (`ANALYTICS_*` keys in both
  languages, `Metrics.Text`); the `holder` hook in `Data/Report.lua` (the report's results and tests unchanged); the
  metrics lines of a new *Analytics and export* section of `/atw debug`; `Data/Metrics.lua` in the TOC after
  `Data/Timeline.lua`.
- Done when:
  - [x] Known sessions give known metrics in the three outcomes and in a mixed, an interrupted, a truncated and a linked
    one; every metric the report has equals the report's cell on the same session; ANA-02 switches at 50 % on each base
    and on the coverage; the build in slices equals the one-pass build; the session is unchanged afterwards; nothing is
    built with the switch off.
- *Done (2026-11-26, before M0.7): `Data/Metrics.lua` behind `analytics` (off): `Metrics.Compute` with the report's
  cells, a `Report.Walk` pass with the hooks `state`, `cross`, `watch` and the new `holder` (the report's results and
  tests unchanged), a short pass over the events for the pull of each change and the outcome (the timeline's), a pass
  over the rows for the closest-to-the-tank percentage; the bases and coverage, ANA-02 compared without rounding, the
  metrics of §1.4 with their categories, lower bounds and reasons (`low-valid`, `little-monitored`, `no-units`,
  `few-not-holding`, `short-known`), unstable intervals, interrupted, truncated, `Z e`, linked and mixed sessions;
  `Metrics.Build` in slices with an LRU cache of 25 dropped at `SESSIONS_CHANGED`; `Metrics.Key`; the `ANALYTICS_*`
  words in both languages; the *Analytics and export* section of `/atw debug`; the TOC. `test_metrics.lua` (45 tests)
  and the ANA-01 check of the wording test; SPEC-06 §1.7 *Realizzato in M6.2*.*
- Tests: `test_metrics.lua` (SPEC-06 §6); `test_report.lua` unchanged and passing; `test_coach_wording.lua` extended to
  the `ANALYTICS_*` keys and the forbidden words of merit (ANA-01).
- Real client: how long `Metrics.Build` takes on a real raid session (P10); how many metrics are *Insufficient data* or
  *Not available* on real groups (P3).

### M6.3 — Comparison and aggregates
- Branch: `step/m6-3-compare`
- Depends on: M6.2
- Spec: SPEC-06 §2, §5, §6
- Scope: `Data/Compare.lua` behind `analytics`: the key of a session (`npc`, else name and classification, else none),
  `Compare.Set(key, filters)` with the group, difficulty and role filters and `MAX_FIGHTS`, comparability per metric
  (same thresholds or game states, values for percentages), the aggregates of §2.2 (total, median, minimum, maximum,
  the weighted risk rate, `MIN_FIGHTS`, lower bounds passed on), the overview by enemy from the headers only,
  `Compare.Build(key, filters, progress, done)` as a queue of `Metrics.Build` one session at a time, paused in combat
  (`PAUSE_IN_COMBAT`) and resumed at `COMBAT_ENDED`, sessions deleted or damaged while building; the comparison lines of
  `/atw debug`; the `ANALYTICS_*` keys of the comparison.
- Done when:
  - [ ] Known sets of sessions give known comparisons and aggregates; fights with different thresholds, bases or
    enemies are never aggregated together; the overview decodes nothing; the queue pauses in combat and resumes;
    twenty sessions at the limits build within the frame budget without the memory growing past the cache.
- Tests: `test_compare.lua` (SPEC-06 §6); `Tests/long/test_compare_long.lua` (twenty sessions at the limits).
- Real client: whether the creature number is readable (P9), so that the key is not the name; the time of a
  comparison of twenty real sessions out of combat.

### M6.4 — Analytics view
- Branch: `step/m6-4-analytics-view`
- Depends on: M6.3
- Spec: SPEC-06 §3, §5; ui-style §3.6
- Scope: `UI/Analytics.lua` behind `analytics` and the change to `UI/Reports.lua`: the *Recordings · Analytics*
  selector, the page (the *Enemies* overview with pooled rows, the *Compare fights* card with filters, the *All fights*
  row and one row per fight, columns dropped by priority under a width, category markers and tooltips, a click opening
  the fight's report), the report's *Analytics* card after the *Timeline* card (built after the report, in slices;
  unstable intervals opening the replay with `REPLAY_REQUESTED(id, t)` only with the `replay` switch; *Compare with…*
  opening the page on the key), every state of §3.4; the wiki page *Threat Analytics* (`docs/wiki/Threat-Analytics.md`
  and `Threat-Analytics-it.md`, linked from *Combat Reports* and the sidebar); previews `analytics-overview`,
  `analytics-compare` (also in Aurora and Warden), `report-analytics`.
- Done when:
  - [ ] The page and the card show every metric of SPEC-06 §1.4 and every aggregate of §2.2 with its category marker,
    reason and basis, in the three outcomes; *Insufficient data*, *Not available* and *Not comparable* never look like
    a number; every state of §3.4 is shown; nothing shows with the switch off; the wiki page exists in both languages.
- Tests: `test_analytics_view.lua` (SPEC-06 §6); `test_reports.lua` (the selector and the card); `test_ui_texts.lua`
  (no text without a locale key).
- Real client: the readability of the comparison table at small widths and in Italian; the cost of opening the page
  with many recordings.

### M6.5 — Export (text and CSV)
- Branch: `step/m6-5-export`
- Depends on: M6.4
- Spec: SPEC-06 §4, §5; SPEC-09 Q15, Q24; ui-style §3.6
- Scope: `Data/Export.lua` behind `export` (adapted from Azeroth Accord's `Data/Export.lua`, ADR 0012): the four
  contents (`fight`, `compare`, `events`, `readings`), CSV with the columns and values of §4.3, RFC 4180 escaping, the
  formula guard and `||` (EXP-02–EXP-04), the text in code blocks in parts of `PART_MAX` (§4.4), the names of §4.5
  (`ANONYMOUS_DEFAULT` off, `Export.Names`), the limit `MAX_TEXT` with whole rows and the count left out (EXP-07),
  building in slices of `SLICE`; `UI/ExportBox.lua` (`AzerothThreatwardenExport`, the selectors, the names switch, the
  warning, the read-only field selected, the status line, Esc) with the read-only multi-line field of
  `UI/DiagnosticsBox.lua` moved into `Widgets.CopyArea` for both boxes; the *Export* buttons of the report's head card
  and of the *Compare fights* card; the UTC date through Compat if needed; `Tests/lib/csv.lua` (from Accord); the
  export lines of `/atw debug`; the *Export* section of the wiki page *Threat Analytics* and what the export lets
  leave on *Privacy and Data*, in both languages; preview `export-box`.
- Done when:
  - [ ] Every content and format round-trips through the test CSV reader; every value carries its category and status;
    with names replaced no name of the sessions appears; the limit keeps whole rows and says what was left out outside
    the text; nothing is sent, posted or written; nothing shows with the switch off.
- Tests: `test_export.lua`, `test_export_box.lua` (SPEC-06 §6); `test_diagnostics.lua` still passing with the shared
  field; `Tests/long/test_export_long.lua` (`readings` and `events` of a session at the limits).
- Real client: the copy box with 256 KB (time of `SetText`, scrolling, Ctrl+A and Ctrl+C, `||` copied as `|`); the text
  pasted into Discord and the CSV opened in a spreadsheet (commas, apostrophe before formulas, accents).

### M6.6 — In-game checklist M6
- Branch: `step/m6-6-checklist`
- Depends on: M6.5
- Scope: `docs/checklists/M6.md` (switches on in the installed copy while they are off, backup of the saved data;
  recorded fights in a party, a dungeon and a raid, against the same enemy several times; the *Analytics* card of a
  report in the three outcomes; *Insufficient data* under half the samples readable; the comparison with its filters,
  different thresholds and an interrupted fight; unstable intervals opening the replay; every export content and format
  copied, pasted into Discord and opened in a spreadsheet; names replaced; the box with a long fight's readings; the
  table at small sizes and in Italian; Q22–Q24 and Q15 tuning notes); the checklists index; README status.
- Done when:
  - [ ] The checklist covers every "Real client" line of M6.2–M6.5 and the exit criterion.

### M6.R — Release preparation `v0.6.0`
- Branch: `chore/release-v0.6.0`
- Depends on: M6.6
- Scope: switches `analytics` and `export` on, `SHIPPED_ON` in `test_features.lua` updated; changelog promoted; READMEs
  and wiki status; `docs/curseforge.md` (features list with Analytics and export, nothing promised beyond what is
  tested); Release workflow dry run (with `--long`), then the tag
  ([ADR 0014](../adr/0014-one-version-per-milestone-and-feature-switches.md)); CurseForge only if the owner has set up
  the project and `CF_API_KEY` (SPEC-09 Q6).
- Done when:
  - [ ] The `analytics` and `export` switches are on, the later ones off; changelog promoted, status updated; the
    checks are green (quick and long).
  - [ ] The dry run is green, and the tag `v0.6.0` and its GitHub Release (changelog section as notes, zip with only
    the addon) exist.
