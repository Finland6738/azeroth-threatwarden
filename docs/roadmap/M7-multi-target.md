# M7 — Multi-target and Dungeon Focus

**Goal:** follow several mobs at once and show where the group is closest to losing aggro
([SPEC-07 §1–§2](../specs/SPEC-07-multi-target-heatmap-profiles.md)).

**Gate:** this milestone runs **only if** the probe (P5, P6) shows that the threat of mobs other than the target can be
read. Otherwise M0.7 replaces it (for example with a *focus* and *boss* only version) and records why.

**Exit criterion:** in a dungeon pull, the focus list shows the mobs at risk and degrades cleanly on mobs that cannot be
queried. Released as `v0.7.0`.

| Step | Model | Effort |
|---|---|---|
| M7.1 Specification with the go / no-go from M0 | Opus | high |
| M7.2 Multi-mob tracker | Opus | medium |
| M7.3 Dungeon focus view | Sonnet | medium |
| M7.4 Degradation and performance with many mobs | Sonnet | high |
| M7.5 In-game checklist M7 | Sonnet | low |
| M7.R Release preparation `v0.7.0` | Sonnet | medium |

### M7.1 — Specification — Branch `step/m7-1-spec`
### M7.2 — Multi-mob tracker — Branch `step/m7-2-multi-mob`
- Scope: mobs from the unit tokens P5 confirmed, stable keys, rotation, limit (MT-01, MT-02). Tests: `test_multi_mob.lua`.
### M7.3 — Dungeon focus view — Branch `step/m7-3-focus-view`
- Scope: risk-sorted mob list, click to monitor; wiki page *Dungeon Focus*; previews.
### M7.4 — Degradation and performance — Branch `step/m7-4-performance`
- Scope: long tests with 40 mobs, unreachable mobs, GUID changes.
### M7.5 — In-game checklist M7 — Branch `step/m7-5-checklist`
### M7.R — Release preparation `v0.7.0` — Branch `chore/release-v0.7.0`
