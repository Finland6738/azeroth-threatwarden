# M6 — Threat Analytics and export

**Goal:** descriptive, verifiable metrics per fight and across fights, and an export to copy
([SPEC-06](../specs/SPEC-06-analytics-export.md)).

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

### M6.1 — Specification — Branch `step/m6-1-spec`
### M6.2 — Metrics per session — Branch `step/m6-2-metrics`
- Scope: `Data/Metrics.lua` (SPEC-06 §1, ANA-01, ANA-02). Tests: `test_metrics.lua`.
### M6.3 — Comparison and aggregates — Branch `step/m6-3-compare`
- Tests: `test_compare.lua`.
### M6.4 — Analytics view — Branch `step/m6-4-analytics-view`
- Scope: view in the Reports tab, wiki page *Threat Analytics*, previews.
### M6.5 — Export — Branch `step/m6-5-export`
- Scope: `Data/Export.lua`, copy box with the names warning and *Player n* option (SPEC-09 Q15). Tests: `test_export.lua`.
### M6.6 — In-game checklist M6 — Branch `step/m6-6-checklist`
### M6.R — Release preparation `v0.6.0` — Branch `chore/release-v0.6.0`
