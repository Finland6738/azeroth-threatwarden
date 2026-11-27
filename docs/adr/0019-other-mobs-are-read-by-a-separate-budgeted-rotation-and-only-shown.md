# 0019. Other mobs are read by a separate, budgeted rotation and only shown; the monitor keeps one mob

- Status: Accepted (M7.1, before the M0 probe: a conditional go; to verify in M0: P5, P6, P9, P10)
- Date: 2026-11-27

## Context

M7 adds multi-target tracking and a Dungeon Focus view (the owner's specification §5.6): several mobs of a pull, the
risk of losing each one, a click to monitor one of them. Its roadmap gate needs the probe to show that the threat of
mobs other than the target can be read (P5, P6); the probe has not been run, and the owner's standing decision D7 is to
proceed and design for every outcome. Since M2 the monitor follows exactly one mob (the target or the target of
target), and the alerts, the Coach, the recorder, the report, the timeline and the analytics are all built on that one
mob's rows and keys. Four questions had to be settled before the modules are written:

1. **One monitor for many mobs, or one monitor and a second reader.** The scanner could read every unit on every mob,
   and every module downstream would have to learn which mob a row belongs to; or the monitor could stay as it is and
   another module read the other mobs.
2. **The cost.** A raid of 40 units on 8 mobs is 320 threat reads per pass; the monitor's own 40-unit tick is already
   above the budget proposed for P10 in the offline measure of M2.7.
3. **Identity.** Nameplate tokens are reassigned as plates appear and vanish, the members' targets change every few
   seconds, and GUIDs may be secret in instances (P9): a mob must keep one key, and the same mob must not be shown
   twice.
4. **What the probe may close.** Other mobs might answer with values, with the state only, with secrets, or not at
   all, and only some tokens might answer.

## Decision

1. **The monitor keeps one mob.** `Data/TargetTracker.lua`, `Data/ThreatScanner.lua`, the model, the states, the
   alerts of the monitored mob, the Coach and the recorder are unchanged. A new `Data/MobTracker.lua` reads the other
   mobs on a tick of its own (`"mobs"`, 2 Hz), and `Data/MobRisk.lua` gives each one a state and a reason with the
   monitor's own thresholds, hysteresis and dwell. The monitored mob's row in the list is built from the monitor's rows,
   never read twice.
2. **A bounded rotation.** At most 8 mobs (2 to 12, a setting), at most 48 reads per tick, at most 10 units per mob
   read (the player, the pet, the designated tanks and the last holder always, the others in turn); events only move a
   mob to the front of the next tick, never read outside it; a mob whose reads are all secret is read again after
   5 s. No trend or prediction on other mobs.
3. **Keys from GUIDs, tokens only when stable.** A mob is `mob:<GUID>`, the TargetTracker's own key, with the tokens
   that name it now (focus, boss, nameplates, the members' targets), checked against the GUID before every read and
   found again with `UnitTokenFromGUID`. Without a readable GUID only `focus` and `boss1–5` are used, compared with
   `UnitIsUnit` when the client permits it; otherwise only the target. The *reach* of the tracker (all mobs, focus and
   boss only, the target only, nothing) follows from the readings of the current fight and is always shown with its
   reason.
4. **Only shown, never saved; a click pins.** The list is not recorded and adds no session data; four settings (account
   schema 6) are the only new saved keys. A click on a mob pins it as the monitor's mob (a rule before the target's,
   released by the player, a new hostile target, its death or the end of the fight); no protected function is called.
   Alerts on other mobs exist only with `alerts.onlyTarget` off and are not recorded.
5. **The probe changes constants, not the design.** Which sources are on (`MobTracker.SOURCES`), the rate and the
   budget (`MobTracker.RATE`, `READ_BUDGET`) and, with the owner, the `multitarget` switch are the only places M0.7
   touches; every outcome already degrades by itself.

The detailed rules are in [SPEC-07 §0–§2](../specs/SPEC-07-multi-target-heatmap-profiles.md) (Italian).

## Alternatives considered

- **One scanner for every mob.** One reading path, but every downstream module (states, alerts, Coach, recorder,
  report, timeline, analytics) would need a mob dimension, the recordings a new format, and the monitor's cost would
  grow with the number of mobs.
- **Every unit on every mob, every tick.** Complete, but 320 reads per pass in a raid; the rotation keeps a party
  complete on every tick and a raid fresh within about a second.
- **Nameplates and members' targets keyed by token.** Simpler, but a token that is reassigned would carry one mob's
  numbers onto another, and the same mob would appear under two tokens.
- **Recording the other mobs.** A fuller report of a pull, but the sessions would grow by up to eight times and change
  format before anyone has seen whether the client allows it.
- **Waiting for the probe.** Against the owner's decision D7; the design costs nothing if a source is closed, and one
  switch removes the whole part.

## Consequences

- Positive: nothing already released changes behaviour; the cost has a fixed ceiling per tick; a closed source or a
  secret value shows as a reason, not as a number; the probe's verdict is applied by changing constants.
- Negative: other mobs are less fresh than the monitored one (about once a second in a raid); without the game's enemy
  nameplates most mobs nobody targets are invisible; whether any of this answers on Forever is unknown until the probe
  and the checklist M7.5.
