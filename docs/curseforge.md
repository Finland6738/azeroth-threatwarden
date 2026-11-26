# CurseForge page: draft for the owner

Draft of the project page for `v0.4.0`, the first CurseForge candidate
([SPEC-09 Q6](specs/SPEC-09-risks-open-questions.md)). **Nothing is published**: the owner creates the project and the
secret ([RELEASING](RELEASING.md#setting-up-curseforge-once)). Title, summary and keywords follow
[SPEC-00 §6](specs/SPEC-00-vision-scope.md#6-nome-tono-e-identità) and the source specification §16.

## Before publishing

- [ ] Approve the title ([Q17](specs/SPEC-09-risks-open-questions.md)): the title of the specification ends in *Combat
  Replay*, which `v0.4.0` does not have. The draft says *Combat Report* until replay exists (`v0.5.0`).
- [x] `v0.4.0` is released (M4.R), so the recording and report described below are switched on.
- [ ] Run the [probe](spike/README.md) and the in-game checklists ([M1](checklists/M1.md)–[M4](checklists/M4.md)), then
  rewrite *What is verified* and the feature list with what they showed. Remove every feature that did not work.
- [ ] The game version **WoW Forever** exists in the project's choices.
- [ ] Add screenshots only from the real game, with names hidden. The design previews of the repository are not
  screenshots: do not upload them as such.

## Project name

Azeroth Threatwarden — Threat Meter, Coach & Combat Report

## Summary

A local-only threat monitor, threat coach and combat report addon for WoW Forever. Early version, not yet verified in
the game.

## Description

*Copy from here to the end of the section.*

**Know your threat. Understand your mistakes. Prevent aggro loss.**

Azeroth Threatwarden is a threat meter and threat monitor addon for **WoW Forever** (`## Interface: 16001`), with a
threat coach, an aggro warning and a combat report. It is an independent addon, for players who want an Omen
alternative that says what it knows and what it does not.

> **Early version, not yet verified in the game.** It has been tested only offline, with a simulated client. It has not
> been checked in the real WoW Forever client, and the client may hide threat values from addons in some situations. In
> that case the addon shows only the threat state, or says *Unknown*: it does not guess.

### What is in version 0.4.0

- **Threat monitor**: the group's threat on the enemy you target, the tank, the percentage, the margin, the trend and a
  state: Safe, Warning, Danger or Unknown.
- **Aggro warnings**: alerts in the addon's window when a risk begins, with a cooldown, an optional sound and a quick
  mute. Defaults: Warning at 82 %, Danger at 91 %.
- **Threat coach**: short role-based advice with its reason and how confident it is. No class rotations.
- **Combat report**: fights in a group or an instance are recorded on your computer; the report shows duration, rises
  to and time in Warning and Danger, tank changes, aggro losses, deaths, alerts and data quality. It never claims to
  know why something happened.
- English and Italian.

**Not in this version**: threat timeline, combat replay, analytics, export, several enemies at once, role profiles and
heatmap. Some are planned; none is promised for a date, and some depend on what the game allows.

### Limits

- Only the enemy you target (or the target of the friend you target) is monitored.
- Values come from what the game gives an addon. When it gives none, you see *state only*, *Not available* or
  *Insufficient data*.
- Predictions say *may*; they are estimates. The thresholds are defaults you can change.
- A recording stores what the monitor saw: nothing is filled in afterwards. The oldest recordings are removed when you
  reach the limits (25 recordings or about 2 MB by default).
- Performance in large raids has not been measured in the game.
- Only WoW Forever. No support is claimed for any other version of the game.

### What is verified

| Area | Offline tests | Real game |
|---|---|---|
| Monitor, alerts, coach, recording, report, settings | yes, with a simulated client | **not yet** |
| Which threat data WoW Forever gives an addon | no | **not yet** |
| Performance in party and raid | estimates only | **not yet** |

### Privacy

No network, no messages to other players, no telemetry, nothing posted in chat. Recordings keep the names of your
group members so the report can show them; they stay in your saved variables and you can delete them.

### Commands

`/atw` shows or hides the window, `/atw reports` the reports, `/atw settings` the settings, `/atw mute` mutes alerts,
`/atw demo` plays an invented fight, `/atw help` lists everything.

### Feedback and source

Source code, manual and issues: <https://github.com/Finland6738/azeroth-threatwarden>. Please never paste other
players' names.

GNU GPL v3.0. Created and designed by Finland. Made with the Italian guild NEBULA. World of Warcraft is a trademark of
Blizzard Entertainment, Inc.; this is an independent fan project, not affiliated with or endorsed by Blizzard.

## Categories and keywords

Suggested categories: *Combat*, *Boss Encounters* (only if it fits after the tests). Keywords the text already uses
naturally: threat meter, threat monitor, threat coach, aggro warning, threat analysis (as *combat report*), Omen
alternative, WoW Forever. Add *combat replay* only when replay is released.
