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

The switches `alerts` and `coach` in `Core/Features.lua` stay **off** until M3.R; every step works and is tested behind
them (SPEC-04 §4.3).

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
  - [ ] One alert per entry, none on a fall or into UNKNOWN; none while muted (emitted with `muted`); never chat; the
    cooldown holds across target changes.
- Tests: `test_alerts.lua` (every case of SPEC-04 §6: bursts, oscillation, mute, exclusions, target change during the
  cooldown, the three probe outcomes, never chat, sound only when on), `AGGRO_CHANGED` cases in
  `test_threat_state.lua`, schema 3 in `test_config.lua`, `Tests/long/test_alerts_raid.lua`.
- Real client: the sound kit (SPEC-04 §1.4), how soon an alert follows the real change (P6).

### M3.3 — Coach rules with reason and confidence
- Branch: `step/m3-3-coach-rules`
- Depends on: M3.2
- Spec: SPEC-04 §2, §4.1, §5
- Scope: `Data/CoachRules.lua` (the table of SPEC-04 §2.2), `Data/Coach.lua` behind the `coach` switch (role, choice,
  cooldowns, numbers at most once a second, `COACH_TIP`); `settings.coach.enabled` (`Config.COACH_DEFAULTS`); the
  `COACH_*` locale keys in both languages following SPEC-04 §2.4; the Coach part of `/atw debug`.
- Done when:
  - [ ] Every rule fires only on its condition and role; predictions only with medium or high confidence; "Not enough
    data for advice" with its reason when the player's row is unknown; no message names a cause or an ability.
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
  - [ ] An alert shows for 4 s and gives way to the current tip; the border changes once per alert, never flashing;
    every tip shows its reason; no state by colour alone.
- Tests: `test_coach_strip.lua`.
- Real client: readability of the strip and of the border in combat, at small sizes.

### M3.5 — Alert settings and quick mute
- Branch: `step/m3-5-alert-settings`
- Depends on: M3.4
- Spec: SPEC-04 §1.5, §1.6, §4.2; SPEC-03 §5
- Scope: the *Alerts* card of Settings (SPEC-04 §4.2, the note of the game's own threat warning), `/atw mute`,
  `Bindings.xml` with `AzerothThreatwarden_ToggleMute`, the row menu *Mute alerts about this unit*, the previews
  `settings-alerts` and `alert-muted`; wiki pages *Settings* and *Commands* in both languages.
- Done when:
  - [ ] Every setting applies at once; `/atw mute` and the key answer in both languages and the mute ends with the
    fight; nothing of the card shows while the switches are off.
- Tests: `test_settings.lua`, `test_commands.lua`, `test_bindings.lua`, the row menu in `test_threat_list.lua`.
- Real client: the binding in the game's key bindings; what the game's own threat warning does.

### M3.6 — In-game checklist M3
- Branch: `step/m3-6-checklist`
- Depends on: M3.5
- Scope: `docs/checklists/M3.md` (a DPS nearing the tank, a tank losing the margin and the mob, a healer, a hunter's
  pet, *state only* and unknown data, mute and the key, the sound, the native warning, the demo; the tuning of the
  cooldown, Q12, and of the messages, Q11); README status.
- Done when:
  - [ ] The checklist covers every "Real client" line of M3.2–M3.5 and the exit criterion.

### M3.R — Release preparation `v0.3.0`
- Branch: `chore/release-v0.3.0`
- Depends on: M3.6
- Scope: switches `alerts` and `coach` on, `test_features.lua` updated; changelog promoted; READMEs and wiki status;
  Release workflow dry run, then the tag ([ADR 0014](../adr/0014-one-version-per-milestone-and-feature-switches.md)).
