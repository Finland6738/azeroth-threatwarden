# M0 — Probe in the real client

**Goal:** know exactly which threat data WoW Forever gives an addon, and with which limits
([SPEC-08 §1](../specs/SPEC-08-quality-probe-release.md#1-probe-m0), specification §8).

**Who:** the owner in game (solo, in a party, in a dungeon and, for P5–P10, ideally a raid); the sessions prepare the
probe and read the results.

**Exit criterion:** `docs/spike/M0-results.md` answers P1–P12, each with *supported / partially / not supported*; the
feature support matrix and the MVP scope decision are written; the affected specs, ADRs and milestone files are updated.

The probe addon `AzTw_Probe` lives in `tools/probe/`, is **never distributed**, wraps every call in `pcall`, and never
prints or stores player or guild names.

| Step | Model | Effort |
|---|---|---|
| M0.0 Repository bootstrap | Opus | high |
| M0.1 Probe specification | Opus | high |
| M0.2 Probe skeleton | Sonnet | medium |
| M0.3 Client and threat API (P1–P4) | Opus | high |
| M0.4 Units, mobs and threat events (P5, P6, P9) | Opus | high |
| M0.5 Combat events (P7, P8) | Opus | high |
| M0.6 Cost, restrictions and reload (P10–P12) | Sonnet | high |
| M0.7 Results and decisions | Opus | high |

### M0.0 — Repository bootstrap
- Branch: `chore/m0-0-bootstrap`
- Depends on: —
- Spec: all (first draft)
- Scope: repository skeleton, `CLAUDE.md`, ADRs 0001–0015 and their index, the specification (SPEC-00–SPEC-09 from the
  owner's original), `ROADMAP.md` and the milestone files with model and effort per step, the docs and privacy checks,
  the ship script and the workflows copied from Azeroth Accord, READMEs and the first wiki pages in both languages, the
  owner's logo.
- Done when:
  - [x] `check_docs.py` passes locally and in CI; the base is on `main` through `ship_step.py`.
- *Done (2026-11-25): shipped as the first step; owner's answers Q1–Q4 recorded in SPEC-09.*

### M0.1 — Probe specification
- Branch: `step/m0-1-probe-spec`
- Depends on: —
- Spec: SPEC-08 §1, SPEC-01 §2, SPEC-09 R1–R3
- Scope: each check P1–P12 detailed in SPEC-08 §1 (exact calls, units, contexts, what is recorded, how the owner runs
  it, the expected outcome per verdict and what it changes in the plan); `docs/spike/README.md` with the install and the
  commands planned; the in-game procedure as a short table per context (solo, party, dungeon, raid).
- Done when:
  - [ ] Every check has its calls, contexts, recorded fields and the three verdicts with their consequence.
  - [ ] `docs/spike/README.md` exists and `check_docs.py` passes.
- Real client: nothing (documentation only).

### M0.2 — Probe skeleton
- Branch: `step/m0-2-probe-skeleton`
- Depends on: M0.1
- Spec: SPEC-08 §1
- Scope: `tools/probe/AzTw_Probe/` (TOC 16001), `/atwp list|run <id>|export|note <id> <text>|reset`, the check
  registry, results `{id, verdict, details, build, context, time}` in `AzTw_ProbeDB`, an export frame with all results
  as text (selected, ready for Ctrl+C); `tools/install_probe.py` and `tools/local.example.ini` (`<WoW folder>` only);
  name scrubbing helper (`<player n>`, `<mob n>`).
- Done when:
  - [ ] Offline: files, commands, registry, scrubbing and install script exist; a Lua syntax check of the probe passes;
        `check_docs.py` passes.
  - [ ] The probe loads on Forever and `/atwp` lists the checks. *(in game)*
- Real client: everything.

### M0.3 — Client and threat API (P1–P4)
- Branch: `step/m0-3-threat-api`
- Depends on: M0.2
- Spec: SPEC-08 §1 P1–P4, SPEC-01 §2
- Scope: P1 build and interface; P2 presence, arity and returns of the four threat functions on the target, with
  `nil` cases (no target, friendly target, dead mob); P3 `ShouldUnitThreatValuesBeSecret`,
  `ShouldUnitThreatStateBeSecret` and `issecretvalue` on every return, before and during combat, solo, party, dungeon,
  raid, with a context stamp per reading; P4 a guided test (tank and DPS on one mob) that logs `scaledPercent` and
  `rawPercent` at the moment aggro changes.
- Done when:
  - [ ] Offline: `/atwp run P1`…`P4` and their logging exist; `check_docs.py` passes.
  - [ ] P1–P4 answered with a verdict each. *(in game)*
- Real client: everything.

### M0.4 — Units, mobs and threat events (P5, P6, P9)
- Branch: `step/m0-4-units-events`
- Depends on: M0.2
- Spec: SPEC-08 §1 P5, P6, P9; SPEC-07 §1
- Scope: which unit tokens answer the threat API for which mob (group members and their targets, `focus`, `mouseover`,
  `targettarget`, `boss1–5`, `nameplateN`), including mobs nobody targets; `UNIT_THREAT_LIST_UPDATE` and
  `UNIT_THREAT_SITUATION_UPDATE` counts, payload units and delay against a polling tick; `UnitGUID` and
  `UnitGroupRolesAssigned` (secret or not) in instances; GUID stability of a mob across a fight.
- Done when:
  - [ ] Offline: the checks and their counters exist; `check_docs.py` passes.
  - [ ] P5, P6 and P9 answered. *(in game, party and dungeon)*
- Real client: everything.

### M0.5 — Combat events (P7, P8)
- Branch: `step/m0-5-combat-events`
- Depends on: M0.2
- Spec: SPEC-08 §1 P7, P8; SPEC-05 §1
- Scope: whether `COMBAT_LOG_EVENT_UNFILTERED` fires for addons and anything of its payload is readable (and through
  which function); `PLAYER_REGEN_*`, `UNIT_TARGET`, `PLAYER_TARGET_CHANGED`, `ENCOUNTER_START/END`, deaths
  (`UNIT_HEALTH`, `UNIT_FLAGS`, `UnitIsDead`), taunts seen through `UNIT_SPELLCAST_SUCCEEDED` on group units;
  `C_DamageMeter.IsDamageMeterAvailable`, sessions and deaths.
- Done when:
  - [ ] Offline: the checks exist; `check_docs.py` passes.
  - [ ] P7 and P8 answered. *(in game)*
- Real client: everything.

### M0.6 — Cost, restrictions and reload (P10–P12)
- Branch: `step/m0-6-cost-restrictions`
- Depends on: M0.3, M0.4
- Spec: SPEC-08 §1 P10–P12; SPEC-01 §5
- Scope: `/atwp perf` samples the threat API at 2, 5 and 10 Hz on up to 40 units and reports milliseconds per tick
  (`debugprofilestop`) and memory per minute of compact samples; blocked-action and error log in and out of combat and
  in a battleground; `/reload` and logout in the middle of a fight with a stamped sample buffer.
- Done when:
  - [ ] Offline: `/atwp perf`, the blocked-action log and the reload stamps exist; `check_docs.py` passes.
  - [ ] P10–P12 answered; a default sampling rate is proposed with its numbers. *(in game)*
- Real client: everything.

### M0.7 — Results and decisions
- Branch: `step/m0-7-results`
- Depends on: M0.3–M0.6 and the owner's results
- Spec: SPEC-08 §1, all specs
- Scope: `docs/spike/M0-results.md` (one row per check: evidence, verdict, consequence); the **feature support matrix**
  (monitor values or state only, per context; multi-target; events for the recorder); the MVP scope decision with the
  owner when R2 bites; updates to SPEC-01–SPEC-09, ADR 0002 and 0004 (or new ADRs), the milestone files, ROADMAP and
  the READMEs.
- Done when:
  - [ ] Every check P1–P12 has a result and a consequence; go / revise per area written.
  - [ ] The roadmap reflects the results; the owner's decisions are recorded in SPEC-09.
