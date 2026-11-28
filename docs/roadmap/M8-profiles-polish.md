# M8 — Profiles, heatmap, polish and v1.0.0

**Goal:** role profiles, the heatmap, accessibility, the translator guide, a final performance pass, the CurseForge
page with the documentation of limits, and the full release check
([SPEC-07 §3–§7](../specs/SPEC-07-multi-target-heatmap-profiles.md#3-heatmap-m83),
[SPEC-08 §5–§10](../specs/SPEC-08-quality-probe-release.md#5-definition-of-done-dellmvp-fonte-18)).

**Exit criterion:** the full release checklist passes; released as `v0.8.0` and then, with nothing left in the plan,
`v1.0.0`.

> **Before the probe** (owner's decision D7, as M2–M7). M8 is specified and built offline for every outcome of the
> probe. Two things depend on the game more than the rest: the automatic choice of a profile needs the assigned role to
> be readable (P9), and the raid-frame marks must cause no taint, which only the game's taint log can show. Both have a
> safe fallback (the profile does not change; the option is off by default and removed if the game blames it).
> **`v1.0.0`** needs the full release check and the Definition of Done, eight items of which need the real client
> ([SPEC-08 §5.1](../specs/SPEC-08-quality-probe-release.md#51-come-si-chiude-ogni-voce-m81)); while the probe and the
> checklists have not been run, M8.R tags `v0.8.0`, prepares `v1.0.0` and **stops before its tag**, waiting for the
> owner's answer to [SPEC-09 Q31](../specs/SPEC-09-risks-open-questions.md) (D29).

| Step | Model | Effort |
|---|---|---|
| M8.1 Specification of profiles, heatmap and release | Opus | high |
| M8.2 Profiles and role presets (account schema 7, character schema 3) | Opus | high |
| M8.3 Heatmap (rows; raid frames only through a detached overlay) | Opus | high |
| M8.4 Accessibility: colour-blind palettes, text-only and icon-only marks | Sonnet | medium |
| M8.5 Translator guide and locale checks | Sonnet | low |
| M8.6 Final performance and memory pass | Sonnet | high |
| M8.7 CurseForge page and documentation of limits | Sonnet | low |
| M8.8 In-game checklist M8 and the full release checklist | Sonnet | medium |
| M8.R Release preparation `v0.8.0`, then `v1.0.0` | Sonnet | medium |

**Switches.** `profiles` (M8.2: `Data/Profiles.lua`, the *Profile* card, `/atw profile`, the *Profiles* section of
`/atw debug`), `heatmap` (M8.3: the row heat, `UI/RaidOverlay.lua`, the *Heatmap* card, the *Heatmap* section) and
`accessibility` (new in M8.4: the palettes and the marks; off, `standard` and `both` apply) in `Core/Features.lua`
stay **off** until M8.R and are **on** from `v0.8.0` (SPEC-09 Q28–Q30); every step is built and tested behind them
(SPEC-07 §6), and tests that need them off set them to `false` in `M.features`. Off, nothing of them is visible, no
game event is registered and nothing is written but the schemas. The account schema goes to **7** and the character
schema to **3** in M8.2 (the plan said "schema 3, migration 2 → 3" before M2–M7 used account schemas 2–6, D25), with
every key M8.3 and M8.4 need, even with the switches off.

### M8.1 — Specification of profiles, heatmap and release
- Branch: `step/m8-1-spec`
- Spec: SPEC-07 §3–§4, SPEC-08, SPEC-02, SPEC-03, ui-style, SPEC-09, SPEC-00 §5 and §7; ADR 0003, 0005, 0009, 0014,
  0015, 0019
- Scope: SPEC-07 §3 (heatmap: HM-01–HM-06, the row heat in five steps, the raid frames only through a detached
  overlay that never touches the game's frames, checked against the dump, with the taint risk stated; settings, card,
  `/atw debug`), §4 (profiles: PR-01–PR-08, the keys and the presets, the automatic choice from the assigned role with
  `NONE` and secret roles, switching out of combat, copy back, copy and reset, card, command), §5 (accessibility:
  AC-01–AC-06, palettes, marks), §6 (modules, events, switches, tests per step), §7 (probe and game); SPEC-08 §5.1 (how
  each item of the Definition of Done closes and its state), §6 (`v0.8.0`, `v1.0.0` and what stays not verified), §7
  (translations and locale checks), §8 (performance and memory budgets), §9 (CurseForge page and limits), §10 (the M8
  and release checklists); SPEC-02 §3.11 (account schema 7, character schema 3); ui-style §3.8, §4.4; two ADRs;
  SPEC-00 D25–D29; SPEC-09 Q28–Q31, R14, R15, Q6; the steps below detailed.
- Done when:
  - [x] SPEC-07 §3–§7 and SPEC-08 §5–§10 say, for every setting, role answer, frame read, palette, mark, budget and
    release step, what the code does and what the player sees; what waits for the probe and the game and the question
    on `v1.0.0` are recorded; `check_docs.py` passes.
- *Done (2026-11-28, before M0.7): SPEC-07 §3 (row heat from the state token in five steps with a 2-point
  hysteresis, nothing on UNKNOWN; Blizzard raid frames only through a detached overlay parented to `UIParent`, reading
  `unit`, `IsVisible`, `GetRect`, `GetEffectiveScale` out of combat, marks only for WARNING, DANGER and aggro on a
  non-tank, off by default, the taint risk and its residual cases written, the option removed if the game blames it;
  the dump lists `hooksecurefunc` and `CompactUnitFrame_*` but no frame by name), §4 (three account profiles, the
  active one per character, `UnitGroupRolesAssigned("player")` with `NONE` or secret leaving the profile unchanged, a
  manual choice kept until the role changes, never in combat, copies applied onto the live settings), §5 (palettes
  `standard`, `redgreen`, `blueyellow`, no free colours, marks `both`, `text`, `icons`, the state badge always icon and
  word), §6–§7; SPEC-08 §5.1, §6–§10; SPEC-02 §3.11; ui-style §3.8, §4.4; new
  [ADR 0020](../adr/0020-role-profiles-are-copies-of-chosen-settings-applied-onto-the-live-settings.md) and
  [ADR 0021](../adr/0021-raid-frames-are-only-overlaid-never-touched.md); SPEC-00 D25–D29; SPEC-09 Q28–Q31, R14, R15,
  Q6; a third switch `accessibility` planned. Nothing changes in the addon.*

### M8.2 — Profiles and role presets
- Branch: `step/m8-2-profiles`
- Depends on: M8.1
- Spec: SPEC-07 §4, §6; SPEC-02 §3.11; ADR 0020
- Scope: `Core/Config.lua` account schema 7 and character schema 3 **whole** (`profiles`, `settings.heatmap`,
  `settings.palette`, `settings.marks`, `char.profile`; `Config.PROFILE_KEYS`, `Config.PRESETS`,
  `Config.HEATMAP_DEFAULTS`, `Config.PALETTES`, `Config.MARKS`; profile rules generated from the settings' rules;
  migrations `account[7]`, copying today's settings into the three profiles, and `char[3]`, a no-op); behind `profiles`
  (off): `Data/Profiles.lua` (the choice of SPEC-07 §4.3 from `Compat.Unit.Role("player")` on `ENTERING_WORLD`,
  `GROUP_CHANGED`, `PLAYER_ROLES_ASSIGNED` and `COMBAT_ENDED`; `Switch` out of combat with the *applying* flag, copy
  back on `CONFIG_CHANGED`, copy, reset, *Reset settings*, read-only data, `PROFILE_CHANGED`); the *Profile* card in
  `UI/Settings.lua`; `/atw profile` in `Core/Commands.lua`; the *Profiles* section of `/atw debug`; the `PROFILE_*`
  keys in both languages; the TOC; the wiki *Settings* and *Commands* pages and a section *Role profiles* (both
  languages).
- Done when:
  - [x] Upgrading from schema 6 changes nothing on screen and fills the three profiles; a new installation gets the
    presets; every answer of the role gives the profile of SPEC-07 §4.3; a switch never happens in combat; a change in
    a card lands in the active profile and only there; with the switch off nothing is registered and the settings work
    as today.
- *Done (2026-11-28): account schema 7 and character schema 3 whole in `Core/Config.lua` (`PROFILE_KEYS`, `PRESETS`,
  `HEATMAP_DEFAULTS`, `PALETTES`, `MARKS`, profile rules that are the settings' own, migrations `account[7]` and
  `char[3]`, `Config:SetProfileValues`, `Config:ResetSettings(keep)`); behind `profiles` (off) `Data/Profiles.lua`, the
  *Profile* card, `/atw profile`, the *Profiles* section of `/atw debug`, `PROFILE_CHANGED` and `PROFILE_ROLE_READ`; a
  choice by hand records the role read then (SPEC-07 §4.3); copy and reset in combat apply after it; a role switch
  waits for the end of the demo. SPEC-09 Q28 gains the case of a `v0.7.x` fix made from `main`. Tests:
  `test_profiles.lua` and additions to `test_config.lua`, `test_settings.lua`, `test_commands.lua`,
  `test_diagnostics.lua`, `test_ui_texts.lua`, `test_api_boundary.lua`.*
- Tests: `test_profiles.lua` (SPEC-07 §6); additions to `test_config.lua` (schemas 7 and 3), `test_settings.lua`,
  `test_commands.lua`, `test_diagnostics.lua`, `test_ui_texts.lua`, `test_api_boundary.lua`.
- Real client: whether `UnitGroupRolesAssigned("player")` answers in a finder group, a hand-made group and a raid
  (P9); whether `PLAYER_ROLES_ASSIGNED` arrives when a role is set.

### M8.3 — Heatmap
- Branch: `step/m8-3-heatmap`
- Depends on: M8.2
- Spec: SPEC-07 §3, §6; ui-style §3.8; ADR 0021
- Scope: behind `heatmap` (off): the row heat in `UI/ThreatList.lua` (`Heatmap.ALPHA`, `Heatmap.HYSTERESIS`, the
  steps of SPEC-07 §3.2, a fade without flashing); `Core/Compat.lua` `RaidFrames.Collect` (frames found by name with
  `rawget`, reads only, out of combat), the API entry and the capability `raidFrames`; `UI/RaidOverlay.lua` (the
  detached overlay: a pool of 40 marks on `UIParent`, positions copied out of combat and every 2 s in a group, marks
  only for WARNING, DANGER and aggro on a non-tank, all hidden after a roster change in combat, never in the demo,
  never taking the mouse); the *Heatmap* card; the *Heatmap* section of `/atw debug` with the blocked and forbidden
  actions counted by `Core/Diagnostics.lua`; the mock's compact frames with a log of every forbidden call; the
  `HEATMAP_*` keys; the TOC; the wiki *Threat Monitor* and *Settings* pages (both languages) with the taint risk and
  how to turn the option off; previews `monitor-heat` (three themes).
- Done when:
  - [x] Every state and mode gives the heat step of SPEC-07 §3.2 and UNKNOWN never has heat; the overlay never makes
    a forbidden call on the mock's frames (the test fails on any), copies positions only out of combat and hides after
    a roster change in combat; the contrast of text on the heat holds in every theme; the monitor tick with the heat
    and the overlay stays within SPEC-08 §8; with the switch or the settings off nothing is created or registered.
- *Done (2026-11-28): behind `heatmap` (off) the row heat in `UI/ThreatList.lua` (`ThreatList.Heatmap`: `ALPHA`,
  `HYSTERESIS`, `HOLD`, `Step`, `For`; a change of state moves the step at once, the one-a-second limit is inside a
  state); `Compat.RaidFrames.Collect` (rawget, three reads, refused in or without an answer of combat lockdown), the API
  entry `frames.Raid` and the capability `raidFrames`; `UI/RaidOverlay.lua` (`AzerothThreatwardenRaidOverlay` on
  `UIParent`, a pool of 40 marks with a border per state, no fade, copies at the events and every 2 s through a 1 Hz
  Scheduler tick, hidden after a roster, frame-profile or screen change in combat, nothing in the demo); the *Heatmap*
  card; the *Heatmap* section with `Diag.WatchActions`/`ActionSeen`; `StateBadge{ small = true }`; `RAID_FRAMES_READ`
  on the Bus; the mock's compact frames with the log of every forbidden touch (`Tests/mock/55_raidframes.lua`); the
  `HEATMAP_*` keys; previews `monitor-heat` (three themes, both languages). Contrast on the heat in ui-style §3.8
  (0.18 holds everywhere; the bar's fill sits on its opaque track). Offline cost at 5 Hz: +3 560 instructions for the
  heat, +1 925 for the overlay, 0 bytes.*
- Tests: `test_heatmap.lua`; additions to `test_theme.lua`, `test_compat.lua`, `test_api_boundary.lua`,
  `test_settings.lua`, `test_diagnostics.lua`, `Tests/long/test_monitor_budget.lua` (SPEC-07 §6).
- Real client: the frame names on Forever and whether their geometry can be read (P11); the marks in place at common
  UI scales and after a roster change; the game's taint log and `ADDON_ACTION_BLOCKED` with the overlay on (Q29); the
  heat in combat in three themes.

### M8.4 — Accessibility
- Branch: `step/m8-4-accessibility`
- Depends on: M8.3
- Spec: SPEC-07 §5, §6; ui-style §4.2–§4.4
- Scope: the `accessibility` switch (new, off) in `Core/Features.lua` and `test_features.lua`;
  `Theme.STATE_PALETTES`, `Theme.SetPalette` and `Theme.Mark(id)` in `UI/Theme.lua`; the values of `redgreen` and
  `blueyellow` fixed with the test (contrast in three themes, the heat rule, the ΔE distances in the simulations of
  Machado 2009) and written in ui-style §4.4; the marks of SPEC-07 §5.3 in `UI/Widgets/Threat.lua`,
  `UI/ThreatList.lua`, `UI/FocusList.lua`, `UI/CoachStrip.lua`; *Colours* and *Marks* in the *Appearance* card; the
  `MARK_*` and `PALETTE_*` keys; the wiki *Settings* page and a section *Accessibility* (both languages); previews
  `settings-appearance` and `monitor` in the palettes.
- Done when:
  - [ ] Every palette passes ST-01–ST-03 and the heat rule in three themes, and its distances are recorded; the state
    badge is the same in every mode; no mark loses information in any mode (the tooltip keeps it); the words fit at
    the minimum size in both languages; with the switch off `standard` and `both` apply.
- Tests: additions to `test_theme.lua`, `test_settings.lua`, `test_ui_texts.lua`; `test_marks.lua` (SPEC-07 §6).
- Real client: the palettes seen by colour-blind players (or a screen simulator); the marks at the minimum size and in
  Italian.

### M8.5 — Translator guide and locale checks
- Branch: `step/m8-5-translations`
- Depends on: M8.4
- Spec: SPEC-08 §7; ADR 0009
- Scope: `Config.LANGUAGES` derived from the registered tables plus `auto`, and `LANGUAGE_NAME` in each locale file
  (LOC-01); partial locales allowed with a warning count, `itIT` still complete (LOC-02); in `tools/check_addon.py` the
  placeholder, unknown-key, colour-code and empty-string checks (LOC-03), with its own tests; LOC-04 in
  `test_ui_texts.lua` and `test_coach_wording.lua` for every locale present; the wiki page *Translating*
  (`docs/wiki/Translating.md` and `Translating-it.md`, in the sidebar); `CONTRIBUTING.md` points to it.
- Done when:
  - [ ] A new locale is one file and one TOC line (a test adds a partial `deDE` file in a temporary copy and the addon
    loads it, lists it in the *Language* card and falls back to English for the missing keys); every check of LOC-03
    fails on a broken example and passes on the real files; the guide exists in both languages.
- Tests: additions to `test_language.lua`, `test_locales.lua`, `test_ui_texts.lua`, `test_coach_wording.lua`; the
  self-tests of `tools/check_addon.py`.
- Real client: the language list in the card and a partial locale after `/reload`.

### M8.6 — Final performance and memory pass
- Branch: `step/m8-6-performance`
- Depends on: M8.5
- Spec: SPEC-08 §8; SPEC-01 §5; ADR 0019
- Scope: every budget of SPEC-08 §8 measured with the M8 switches on (`Tests/long/test_monitor_budget.lua`,
  `test_multi_mob_long.lua`, `test_recorder_raid.lua`, `test_replay_long.lua` and the others); the decoding of a
  recording at the limit split over frames at most 1 000 000 instructions each (ARC-07); the margin of the mobs tick
  with the list brought back to at least 5 % if it can be done without changing Q26; the heat on the Dungeon Focus rows
  only if the margin allows it (a note in SPEC-07 §3.2); the memory after loading and with 25 sessions recorded; the
  numbers in SPEC-01 §5.1.
- Done when:
  - [ ] Every measure of SPEC-08 §8 is within its budget and written in SPEC-01 §5.1; no frame of work outside a tick
    exceeds 1 000 000 instructions; the memory does not grow in any long test.
- Tests: the long tests above, with `--long` in CI.
- Real client: FPS and the tick times of `/atw debug` in a party and a 40-player raid, with and without the overlay
  (P10).

### M8.7 — CurseForge page and documentation of limits
- Branch: `step/m8-7-curseforge`
- Depends on: M8.6
- Spec: SPEC-08 §5.1, §9; SPEC-00 §6; SPEC-09 Q6, Q17, Q31
- Scope: `docs/curseforge.md` for `v0.8.0` and `v1.0.0` (features with profiles, heatmap and accessibility; *Limits*;
  *What is verified* honest, the probe and every checklist *not run* until they are; *Before publishing* for the
  owner); the wiki page *Limits and Compatibility* (both languages, in the sidebar); the limits in `README.md` and
  `README.it.md`; the *Home* page links it.
- Done when:
  - [ ] The page, the README and the wiki say what is verified offline and what is not verified in the game, line by
    line as SPEC-08 §5.1, and promise nothing that a checklist has not shown; the wiki page exists in both languages.
- Tests: `check_docs.py` (wiki twins and links).
- Real client: none; the owner reviews the page against the probe and the checklists before publishing it.

### M8.8 — In-game checklist M8 and the full release checklist
- Branch: `step/m8-8-release-checklist`
- Depends on: M8.7
- Spec: SPEC-08 §4, §5.1, §10
- Scope: `docs/checklists/M8.md` (switches on in the installed copy while they are off, backup; profiles, heat,
  overlay with the taint log, palettes, marks, a partial locale, Q28–Q30 notes, a table linking every *Real client*
  line of M8.2–M8.7 to a section); `docs/checklists/release.md` (the full check of SPEC-08 §10, the twelve items of the
  Definition of Done one by one, the go / no-go for `v1.0.0` that answers Q31); the checklists index; README status.
- Done when:
  - [ ] `M8.md` covers every *Real client* line of M8.2–M8.7; `release.md` covers every item of SPEC-08 §5.1 and every
    checklist M1–M8 and the probe, and ends with the go / no-go.
- Real client: both checklists are for the owner to run.

### M8.R — Release preparation `v0.8.0`, then `v1.0.0`
- Branch: `chore/release-v0.8.0`, then `chore/release-v1.0.0`
- Depends on: M8.8
- Spec: SPEC-08 §6; ADR 0014; `docs/RELEASING.md`; SPEC-09 Q6, Q31
- Scope, `v0.8.0`: the `profiles`, `heatmap` and `accessibility` switches on (Q28–Q30), `SHIPPED_ON` in
  `test_features.lua`; changelog promoted to `0.8.0`; READMEs and wiki status; `docs/curseforge.md`; the Release
  workflow dry run (with `--long`), then the tag `v0.8.0` and its GitHub Release; CurseForge only if the owner has set
  it up (Q6).
- Scope, `v1.0.0`: with nothing left in the plan, `chore/release-v1.0.0`: changelog `1.0.0`, status, wiki, CurseForge
  draft and `release.md` saying what is not verified in the game (SPEC-08 §6.2), the dry run. **The tag waits for the
  owner** (Q31, and `v1.0.0` is not a milestone tag with standing approval): shipped with
  `tools/ship_step.py --no-merge`, the pull request stays open with the question until the owner answers; then the
  fast-forward of `main`, the tag and the GitHub Release.
- Done when:
  - [ ] `v0.8.0`: the three switches are on; changelog promoted, status updated; the checks are green (quick and long);
    the dry run is green, and the tag `v0.8.0` and its GitHub Release exist.
  - [ ] `v1.0.0`: the preparation is in its branch and an open pull request with the question (not fast-forwarded to
    `main`, so that `main` never says `1.0.0` without the tag), the dry run is green; the merge, the tag `v1.0.0` and
    its GitHub Release happen **only after the owner's answer to Q31**.
