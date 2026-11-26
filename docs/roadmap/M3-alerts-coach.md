# M3 — Alerts and Threat Coach

**Goal:** configurable, non-invasive alerts and a rule-based Coach with a reason and a confidence for each advice
([SPEC-04](../specs/SPEC-04-alerts-coach.md)).

> **Started before M0.7, like M2** (owner's decision D7, [SPEC-00 §7](../specs/SPEC-00-vision-scope.md#7-registro-delle-decisioni)).
> Alerts and Coach read only the monitor's states and values, so they work for every probe outcome (values, *state
> only*, unknown: SPEC-04 §2.5); M0.7 revises them where the results contradict the specification (`[probe Pn]` marks).

**Exit criterion:** in game, a DPS nearing the tank gets one warning (not one per update), the cooldown holds, nothing
goes to chat, and every Coach message shows its reason. Released as `v0.3.0`.

| Step | Model | Effort |
|---|---|---|
| M3.1 Specification of alerts and Coach | Opus | high |
| M3.2 Alert manager | Sonnet | high |
| M3.3 Coach rules with reason and confidence | Opus | medium |
| M3.4 Coach strip and role messages | Sonnet | medium |
| M3.5 Alert settings and quick mute | Sonnet | medium |
| M3.6 In-game checklist M3 | Sonnet | low |
| M3.R Release preparation `v0.3.0` | Sonnet | medium |

The switches `alerts` and `coach` in `Core/Features.lua` stayed **off** until M3.R; every step works and is tested
behind them (SPEC-04 §4.3).

*State (2026-11-26): M3 is complete in code (steps M3.1–M3.6, offline tests in CI) and released as `v0.3.0` (M3.R).
The exit criterion needs the game and is **open** until the owner runs [the M3 checklist](../checklists/M3.md).*

### M3.1 — Specification of alerts and Coach
- Branch: `step/m3-1-spec`
- Spec: SPEC-04, SPEC-09 Q11–Q12
- Scope: SPEC-04 completed: alert triggers as state transitions, cooldowns per kind, rule table (condition, message
  key, reason key, confidence, role), wording rules for predictions and hypotheses, previews.
- Done when:
  - [x] SPEC-04 says, for every alert kind and Coach rule, its trigger, message and reason keys, category, confidence,
    cooldown and what happens in *state only* and with unknown data; `check_docs.py` passes.
- *Done (2026-11-26, before M0.7): SPEC-04 §1 (alerts only when a state or the aggro holder **enters**, from
  `STATE_CHANGED` and the new `AGGRO_CHANGED` of `ThreatState`; seven kinds with severity; cooldown 8 s per kind and
  unit, bursts of others and sounds limited; channels window, visual and sound, never chat, never opening the window;
  options, exclusions without names, `/atw mute` and a key binding; the game's own threat warning), §2 (roles, the rule
  table T1–T7, D1–D5, A1 with priorities and cooldowns, choice and duration, wording rules WR-01–WR-07, *state only*
  and unknown cases), §3 (the Coach strip, the one-time border effect, previews), §4 (account schema 3, the *Alerts*
  card, the switches), §5–§6 (modules, Bus events, diagnostics, tests per step); SPEC-02 §3.6, SPEC-09 Q11–Q12, R6,
  R9; SPEC-01, SPEC-03, ui-style and ARCHITECTURE for the new modules, events and icons. The steps below detailed.*

### M3.2 — Alert manager
- Branch: `step/m3-2-alerts`
- Depends on: M3.1
- Spec: SPEC-04 §1, §4.1, §5; SPEC-03 §2.4
- Scope: `AGGRO_CHANGED` in `Data/ThreatState.lua`; `Data/Alerts.lua` behind the `alerts` switch (the kinds of §1.2,
  cooldown per kind and unit, `OTHER_GAP`, `SOUND_GAP`, channels window / visual / sound / none, `ToggleMute`,
  `alerts.others` and `alerts.pet`, the session exclusion by `unitKey`, demo, the Scanner consumer, `ALERT_RAISED` and
  `MUTE_CHANGED`); the sound call through Compat (`ui.PlaySound`, kit in one place); account schema 3 with
  `settings.alerts` (`Config.ALERTS_DEFAULTS`, migration and its test); the `ALERT_*` locale keys in both languages;
  the *Alerts and Coach* section of `/atw debug` (alerts part).
- Done when:
  - [x] One alert per entry, none on a fall or into UNKNOWN; none while muted (emitted with `muted`); never chat; the
    cooldown holds across target changes.
- Tests: `test_alerts.lua` (every case of SPEC-04 §6: bursts, oscillation, mute, exclusions, target change during the
  cooldown, the three probe outcomes, never chat, sound only when on), `AGGRO_CHANGED` cases in
  `test_threat_state.lua`, schema 3 in `test_config.lua`, `Tests/long/test_alerts_raid.lua`.
- Real client: the sound kit (SPEC-04 §1.4), how soon an alert follows the real change (P6).
- *Done (2026-11-26, before M0.7): `Data/Alerts.lua` as SPEC-04 §1, with `AGGRO_CHANGED` in `ThreatState` (emitted
  before the `STATE_CHANGED` of the same update), `Compat.PlaySound`, account schema 3 (`settings.alerts`), the
  `ALERT_*` keys and the debug section; `test_alerts.lua`, the new cases of `test_threat_state.lua`, `test_config.lua`
  and `test_compat.lua`, a sound mock and `Tests/long/test_alerts_raid.lua`. Added to the specification: the tank's
  Danger margin alert also stands for the same second's own Danger. Open for M3.6: the one cooldown of the `margin` and
  `other` kinds can hold back a more severe alert of the same kind (SPEC-09 Q12).*

### M3.3 — Coach rules with reason and confidence
- Branch: `step/m3-3-coach-rules`
- Depends on: M3.2
- Spec: SPEC-04 §2, §4.1, §5
- Scope: `Data/CoachRules.lua` (the table of SPEC-04 §2.2), `Data/Coach.lua` behind the `coach` switch (role, choice,
  cooldowns, numbers at most once a second, `COACH_TIP`); `settings.coach.enabled` (`Config.COACH_DEFAULTS`); the
  `COACH_*` locale keys in both languages following SPEC-04 §2.4; the Coach part of `/atw debug`.
- Done when:
  - [x] Every rule fires only on its condition and role; predictions only with medium or high confidence; "Not enough
    data for advice" with its reason when the player's row is unknown; no message names a cause or an ability.
- *Done (2026-11-26, before M0.7): `Data/CoachRules.lua` (T1–T7, D1–D5, A1, the arguments of every key) and
  `Data/Coach.lua` behind the `coach` switch (role, choice by priority, cooldowns, numbers at most once a second,
  `COACH_TIP`, `Coach.Text` for M3.4); `settings.coach.enabled` (`Config.COACH_DEFAULTS`, no new migration step); 35
  `COACH_*` keys in both languages; the Coach lines in *Alerts and Coach* of `/atw debug`. Refined in SPEC-04 §2.2–§2.3
  and SPEC-09 Q11: no tip (not A1) while the rule that holds waits for its cooldown; no cooldown for a rule interrupted
  by a fact without one; D3 also on the list's predicted Warning. Tests: `test_coach.lua`, `test_coach_wording.lua`,
  `test_config.lua`.*
- Tests: `test_coach.lua` (each rule, each role, the *state only* forms, cooldowns, SPEC-04 §2.5),
  `test_coach_wording.lua` (WR-01–WR-07 on every `COACH_*` and `ALERT_*` key, both languages).
- Real client: whether the messages help in a real fight (Q11); the roles in a group (P9).

### M3.4 — Coach strip and role messages
- Branch: `step/m3-4-coach-ui`
- Depends on: M3.3
- Spec: SPEC-04 §3; ui-style §3.1, §3.4, §4.2
- Scope: `UI/CoachStrip.lua` in the Monitor view (message, badge of an alert's state, `coach` icon, reason and category
  on hover, confidence badge for estimated and predicted tips, the idle and muted views, the short window), the border
  effect in `UI/Window.lua`, the icons `coach` and `mute` (`tools/make_media.py`), the previews `coach-dps`,
  `coach-tank`, `coach-unknown`, `alert-danger`; wiki page *Alerts and Coach* in both languages (with the game's own
  threat warning, ALR-03).
- Done when:
  - [x] An alert shows for 4 s and gives way to the current tip; the border changes once per alert, never flashing;
    every tip shows its reason; no state by colour alone.
- Tests: `test_coach_strip.lua`.
- Real client: readability of the strip and of the border in combat, at small sizes.
- *Done (2026-11-26, before M0.7): `UI/CoachStrip.lua` built into the Monitor view, the border effect and the pill's
  state icon in `UI/Window.lua`, the icons `coach` and `mute`, previews `coach-dps`, `coach-tank`, `coach-unknown`,
  `alert-danger` and the wiki page *Alerts and Coach*. Added to the specification: a reason for every alert
  (`ALERT_WHY_*`, `Alerts.Text`); an alert is kept only while the strip can show it. `test_coach_strip.lua`.*

### M3.5 — Alert settings and quick mute
- Branch: `step/m3-5-alert-settings`
- Depends on: M3.4
- Spec: SPEC-04 §1.5, §1.6, §4.2; SPEC-03 §5
- Scope: the *Alerts* card of Settings (SPEC-04 §4.2, the note of the game's own threat warning), `/atw mute`,
  `Bindings.xml` with `AzerothThreatwarden_ToggleMute`, the row menu *Mute alerts about this unit*, the previews
  `settings-alerts` and `alert-muted`; wiki pages *Settings* and *Commands* in both languages.
- Done when:
  - [x] Every setting applies at once; `/atw mute` and the key answer in both languages and the mute ends with the
    fight; nothing of the card shows while the switches are off.
- Tests: `test_settings.lua`, `test_commands.lua`, `test_bindings.lua`, the row menu in `test_threat_list.lua`.
- Real client: the binding in the game's key bindings; what the game's own threat warning does.
- *Done (2026-11-26, before M0.7): the *Alerts* card in `UI/Settings.lua` (read-only data as the *Monitor* card), the
  note of `IsThreatWarningEnabled` through `Compat.ThreatWarningEnabled`, read when the card shows and on the new Bus
  event `ENTERING_WORLD`; `/atw mute`; `Bindings.xml` (`AZEROTHTHREATWARDEN_MUTE` calling
  `AzerothThreatwarden_ToggleMute()`, as SPEC-04 §1.5 names them); the row menu with `Widgets.Menu` (adapted from
  Accord, no `UIDropDownMenu`); previews `settings-alerts` and `alert-muted`; wiki *Settings*, *Commands*, *Alerts and
  Coach*. Tests: `test_settings.lua`, `test_commands.lua`, `test_bindings.lua`, `test_threat_list.lua`.*

### M3.6 — In-game checklist M3
- Branch: `step/m3-6-checklist`
- Depends on: M3.5
- Scope: `docs/checklists/M3.md` (a DPS nearing the tank, a tank losing the margin and the mob, a healer, a hunter's
  pet, *state only* and unknown data, mute and the key, the sound, the native warning, the demo; the tuning of the
  cooldown, Q12, and of the messages, Q11); README status.
- Done when:
  - [x] The checklist covers every "Real client" line of M3.2–M3.5 and the exit criterion.
- *Done (2026-11-26, before M0.7): [docs/checklists/M3.md](../checklists/M3.md), with the exit criterion (step 2), the
  sound kit and the delay of an alert (steps 8, 2.8), Q11 and the roles (steps 3.8, 4, 11), the strip and border
  (step 10), the key binding and the game's own warning (steps 7, 9), Q12 (steps 3.3, 11). Written, **not run**: it
  waits for the owner.*

### M3.R — Release preparation `v0.3.0`
- Branch: `chore/release-v0.3.0`
- Depends on: M3.6
- Scope: switches `alerts` and `coach` on, `test_features.lua` updated; changelog promoted; READMEs and wiki status;
  Release workflow dry run, then the tag ([ADR 0014](../adr/0014-one-version-per-milestone-and-feature-switches.md)).
- Done when:
  - [x] The `alerts` and `coach` switches are on, the later ones off; changelog promoted, status updated; the checks are
        green.
  - [x] The dry run is green, and the tag `v0.3.0` and its GitHub Release (changelog section as notes, zip with only the
        addon) exist.
- *Done (2026-11-26): `alerts` and `coach` switched on, changelog promoted and status updated (commit `ec39134`, every
  later switch off, 936 quick tests and 957 with `--long`; the long budget test also bounds the shipped switches at 160 B
  per tick, SPEC-01 §5.1); the dry run of the Release workflow was green; annotated tag `v0.3.0` on that commit,
  [GitHub Release](https://github.com/Finland6738/azeroth-threatwarden/releases/tag/v0.3.0) with the changelog section
  as notes and `AzerothThreatwarden-v0.3.0-forever.zip` (144 files, all in `AzerothThreatwarden/`;
  `## Version: v0.3.0`). CurseForge skipped (no `CF_API_KEY`). The zip has not been installed or run in the game; the M0
  probe and the M1, M2 and M3 checklists are still open.*
