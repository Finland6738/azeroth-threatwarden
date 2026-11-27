# CurseForge page: draft for the owner

Draft of the project page for `v0.7.0` (the first CurseForge candidate was `v0.4.0`)
([SPEC-09 Q6](specs/SPEC-09-risks-open-questions.md)). **Nothing is published**: the owner creates the project and the
secret ([RELEASING](RELEASING.md#setting-up-curseforge-once)). Title, summary and keywords follow
[SPEC-00 §6](specs/SPEC-00-vision-scope.md#6-nome-tono-e-identità) and the source specification §16.

## Before publishing

- [ ] Approve the title ([Q17](specs/SPEC-09-risks-open-questions.md)): from `v0.5.0`, with the replay switched on, the
  draft uses the title of the specification, ending in *Combat Replay*.
- [x] The recording, report, timeline and replay described below are switched on from `v0.5.0` (M5.R), analytics and
  export from `v0.6.0` (M6.R), the Dungeon Focus from `v0.7.0` (M7.R).
- [ ] Run the [probe](spike/README.md) and the in-game checklists ([M1](checklists/M1.md)–[M7](checklists/M7.md)), then
  rewrite *What is verified* and the feature list with what they showed. Remove every feature that did not work.
- [ ] The game version **WoW Forever** exists in the project's choices.
- [ ] Add screenshots only from the real game, with names hidden. The design previews of the repository are not
  screenshots: do not upload them as such.

## Project name

Azeroth Threatwarden — Threat Meter, Coach & Combat Replay

## Summary

A local-only threat monitor, threat coach, combat report and combat replay addon for WoW Forever. Early version, not
yet verified in the game.

## Description

*Copy from here to the end of the section.*

**Know your threat. Understand your mistakes. Prevent aggro loss.**

Azeroth Threatwarden is a threat meter and threat monitor addon for **WoW Forever** (`## Interface: 16001`), with a
threat coach, an aggro warning, a combat report, a combat replay, threat analytics with export and a Dungeon Focus for the other mobs of a pull. It is an
independent addon, for players who want an Omen alternative that says what it knows and what it does not.

> **Early version, not yet verified in the game.** It has been tested only offline, with a simulated client. It has not
> been checked in the real WoW Forever client, and the client may hide threat values from addons in some situations. In
> that case the addon shows only the threat state, or says *Unknown*: it does not guess.

### What is in version 0.7.0

- **Threat monitor**: the group's threat on the enemy you target, the tank, the percentage, the margin, the trend and a
  state: Safe, Warning, Danger or Unknown.
- **Aggro warnings**: alerts in the addon's window when a risk begins, with a cooldown, an optional sound and a quick
  mute. Defaults: Warning at 82 %, Danger at 91 %.
- **Threat coach**: short role-based advice with its reason and how confident it is. No class rotations.
- **Combat report**: fights in a group or an instance are recorded on your computer; the report shows duration, rises
  to and time in Warning and Danger, tank changes, aggro losses, deaths, alerts and data quality. It never claims to
  know why something happened.
- **Timeline and combat replay**: a chart of the threat during a recorded fight, with its events, and a replay with
  play, pause, seek and step. Estimates and gaps are drawn differently from detected readings.
- **Threat analytics**: numbers per recorded fight with their category, and a comparison of fights against the same
  enemy; *Insufficient data* when there is not enough to say. No rankings of players.
- **Export**: a fight, its events, its readings or a comparison as text or CSV in a box that you copy yourself; names
  of your group can be replaced. The addon writes no file and sends nothing.
- **Dungeon Focus**: in a pull with several mobs, a bar and a list of the ones your group risks losing; a click makes
  one the mob the monitor follows, without changing your game target. Alerts about other mobs are optional and off by
  default. It shows only what the client lets an addon read, which is **not verified in the game**: it may be limited to
  your focus and the bosses, or to your target only, and says why. Mobs that nobody targets need the enemy nameplates.
- English and Italian.

**Not in this version**: role profiles and heatmap. Some are planned; none is promised for a
date, and some depend on what the game allows.

### Limits

- The monitor follows one enemy: the one you target (or the target of the friend you target), or the one you pick in
  the Dungeon Focus. The other mobs are only shown, never recorded.
- Values come from what the game gives an addon. When it gives none, you see *state only*, *Not available* or
  *Insufficient data*.
- Predictions say *may*; they are estimates. The thresholds are defaults you can change.
- A recording stores what the monitor saw: nothing is filled in afterwards. The oldest recordings are removed when you
  reach the limits (25 recordings or about 2 MB by default).
- The replay shows only what was recorded, and pauses during combat.
- Analytics only reads recordings and the comparison pauses during combat. A very long fight does not fit in one
  export of its readings; the box says how many rows were left out.
- Performance in large raids has not been measured in the game.
- Only WoW Forever. No support is claimed for any other version of the game.

### What is verified

| Area | Offline tests | Real game |
|---|---|---|
| Monitor, alerts, coach, recording, report, timeline, replay, analytics, export, Dungeon Focus, settings | yes, with a simulated client | **not yet** |
| Which threat data WoW Forever gives an addon | no | **not yet** |
| Performance in party and raid | estimates only | **not yet** |

### Privacy

No network, no messages to other players, no telemetry, nothing posted in chat. Recordings keep the names of your
group members so the report can show them; they stay in your saved variables and you can delete them. An export can
hold those names: it leaves the game only if you copy it.

### Commands

`/atw` shows or hides the window, `/atw reports` the reports, `/atw replay` the replay, `/atw focus` the Dungeon Focus, `/atw settings` the settings, `/atw mute` mutes alerts,
`/atw demo` plays an invented fight, `/atw help` lists everything.

### Feedback and source

Source code, manual and issues: <https://github.com/Finland6738/azeroth-threatwarden>. Please never paste other
players' names.

GNU GPL v3.0. Created and designed by Finland. Made with the Italian guild NEBULA. World of Warcraft is a trademark of
Blizzard Entertainment, Inc.; this is an independent fan project, not affiliated with or endorsed by Blizzard.

## Categories and keywords

Suggested categories: *Combat*, *Boss Encounters* (only if it fits after the tests). Keywords the text already uses
naturally: threat meter, threat monitor, threat coach, aggro warning, threat analysis (as *combat report*), combat
replay, Omen alternative, WoW Forever.
