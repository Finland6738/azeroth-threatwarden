# M8 — Profiles, heatmap, polish and v1.0.0

**Goal:** role profiles, the heatmap, accessibility, the translator guide, the CurseForge page and a final performance
pass ([SPEC-07 §3–§4](../specs/SPEC-07-multi-target-heatmap-profiles.md), [SPEC-08 §5](../specs/SPEC-08-quality-probe-release.md#5-definition-of-done-dellmvp-fonte-18)).

**Exit criterion:** the full release checklist passes; released as `v0.8.0` and then, with nothing left in the plan,
`v1.0.0`.

| Step | Model | Effort |
|---|---|---|
| M8.1 Specification of profiles, heatmap and release | Opus | high |
| M8.2 Profiles and role presets (schema 3) | Opus | high |
| M8.3 Heatmap (rows; raid frames only without taint) | Opus | high |
| M8.4 Accessibility: colour-blind palettes, text-only and icon-only modes | Sonnet | medium |
| M8.5 Translator guide and locale checks | Sonnet | low |
| M8.6 Final performance and memory pass | Sonnet | high |
| M8.7 CurseForge page and documentation of limits | Sonnet | low |
| M8.8 Full release checklist | Sonnet | medium |
| M8.R Release preparation `v0.8.0` and `v1.0.0` | Sonnet | medium |

### M8.1 — Specification — Branch `step/m8-1-spec`
### M8.2 — Profiles and role presets — Branch `step/m8-2-profiles`
- Scope: `db.profiles`, migration 2 → 3, automatic choice from the assigned role. Tests: `test_profiles.lua`.
### M8.3 — Heatmap — Branch `step/m8-3-heatmap`
- Scope: row colouring; Blizzard raid frames tinted only through non-tainting means, off by default. Tests on taint
  guards in the mock.
### M8.4 — Accessibility — Branch `step/m8-4-accessibility`
### M8.5 — Translator guide — Branch `step/m8-5-translations`
- Scope: `docs/wiki/Translating.md` (both languages), how a new locale is one file.
### M8.6 — Final performance pass — Branch `step/m8-6-performance`
### M8.7 — CurseForge page — Branch `step/m8-7-curseforge`
### M8.8 — Full release checklist — Branch `step/m8-8-release-checklist`
- Scope: `docs/checklists/release.md`, run again over everything before `v1.0.0`.
### M8.R — Release preparation — Branch `chore/release-v0.8.0`, then `chore/release-v1.0.0`
