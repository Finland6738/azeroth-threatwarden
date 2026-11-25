# M3 — Alerts and Threat Coach

**Goal:** configurable, non-invasive alerts and a rule-based Coach with a reason and a confidence for each advice
([SPEC-04](../specs/SPEC-04-alerts-coach.md)).

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

### M3.1 — Specification of alerts and Coach
- Branch: `step/m3-1-spec`
- Spec: SPEC-04, SPEC-09 Q11–Q12
- Scope: SPEC-04 completed: alert triggers as state transitions, cooldowns per kind, rule table (condition, message
  key, reason key, confidence, role), wording rules for predictions and hypotheses, previews.

### M3.2 — Alert manager
- Branch: `step/m3-2-alerts`
- Scope: `Data/Alerts.lua` (channels: window message, visual, sound, none; cooldown; only in combat; only current
  target; excluded units; mute), listening to `STATE_CHANGED`.
- Done when:
  - [ ] One alert per transition; none while muted; none outside combat when so set; never chat.
- Tests: `test_alerts.lua` (bursts, oscillation, mute, exclusions, target change during cooldown).

### M3.3 — Coach rules with reason and confidence
- Branch: `step/m3-3-coach-rules`
- Scope: `Data/CoachRules.lua`, `Data/Coach.lua` (COA-01–COA-05; predictions only with medium or high confidence;
  "Not enough data for advice").
- Tests: `test_coach.lua` (each rule, each role, no cause claimed, no ability named).

### M3.4 — Coach strip and role messages
- Branch: `step/m3-4-coach-ui`
- Scope: the Coach strip in the window (message, reason on hover, confidence badge), visual effect, role messages in
  both languages; wiki page *Alerts and Coach*.

### M3.5 — Alert settings and quick mute
- Branch: `step/m3-5-alert-settings`
- Scope: settings card for alerts, `/atw mute`, a key binding, previews.

### M3.6 — In-game checklist M3
- Branch: `step/m3-6-checklist`
- Scope: `docs/checklists/M3.md`; README status.

### M3.R — Release preparation `v0.3.0`
- Branch: `chore/release-v0.3.0`
