# Spike: the probe addon

`AzTw_Probe` is a **throwaway** addon used in milestone M0 to answer, in the real WoW Forever client, what the design
cannot answer offline: which threat data the client gives an addon, in which contexts, and at which cost. The checks
P1–P12, with their exact calls, contexts, recorded fields and the consequence of each verdict, are specified in
[SPEC-08 §1](../specs/SPEC-08-quality-probe-release.md#1-probe-m0) (in Italian); the steps are in
[M0-probe.md](../roadmap/M0-probe.md).

> **Status: P1–P6 and P9 written (M0.4).** The probe installs and loads, lists P1–P12, stores notes and exports; P1–P4
> (client, threat functions, secret values, the tank and DPS trial) and P5, P6, P9 (units and mobs, threat events,
> GUIDs and roles) work, with `/atwp ctx` and `/atwp watch`. P7, P8 and P10–P12 still answer `todo`, "not implemented
> yet, step M0.x"; they arrive in M0.5 and M0.6. Nothing has been verified in the real client yet.

## What the probe is

- It lives in `tools/probe/AzTw_Probe/` (TOC `## Interface: 16001`) and is **never distributed**: it is not part of any
  package or release, and `.pkgmeta` never includes it.
- Every game API call is wrapped in `pcall`; an error is a result, not a crash.
- Every returned value is tested with `issecretvalue` before anything else. A secret value is recorded only as
  `secret`: never compared, formatted, printed or saved. The probe never tries to work around secrecy.
- No player, guild or character name is ever printed or stored, and no player GUID: players become `<player n>`, mobs
  `<mob n>` (plus the GUID type and the creature id, which are not personal data). Unit tokens such as `party2` are kept.
- No network, no addon messages, nothing sent to chat channels, no CVar or game setting changed.
- Results are saved in `AzTw_ProbeDB` as `{id, verdict, details, build, context, time}` (verdict: `supported`,
  `partial`, `not supported` or `todo`), plus one log per check. `context` is the stamp of SPEC-08 §1.2.
- Error texts and notes are scrubbed of GUIDs and of the names the probe has seen through a unit token (you, your
  group, your targets, nameplates; also guild and realm). It cannot recognise any other name: never type one in a note.

## Install

1. Copy `tools/local.example.ini` to `tools/local.ini` (git-ignored) and set `addons` to the
   `<WoW folder>/_forever_/Interface/AddOns` folder of your installation.
2. Run:

   ```bash
   python -I -X utf8 tools/install_probe.py
   ```

   It copies `tools/probe/AzTw_Probe/` into that folder and nothing else.
3. In game, `/reload` (restart the client the first time, so that it sees the new folder). The chat shows
   "AzTw Probe: loaded", and `/atwp` lists P1–P12. If it does not load, enable "Load out of date AddOns" and send the
   exact error.

Run the installer again after every update of the probe, then `/reload`. The results in `AzTw_ProbeDB` survive the
update. To remove the probe after M0, delete the `AzTw_Probe` folder from the AddOns folder.

## Commands

Commands of M0.2 and M0.3 exist now (M0.4 adds no command: P5, P6 and P9 read through `/atwp watch` and `/atwp run`); `/atwp perf` arrives with M0.6.

| Command | Step | What it does |
|---|---|---|
| `/atwp` or `/atwp list` | M0.2 | Lists P1–P12 with a short description and the last verdict |
| `/atwp run <id>` | M0.2 | Runs one check now, for example `/atwp run P2`; checks that need a fight start their readings by themselves while active |
| `/atwp export` | M0.2 | Opens a movable frame with all results and logs as plain text, already selected: press Ctrl+C and paste it back |
| `/atwp note <id> <text>` | M0.2 | Stores a free-text observation, for example `/atwp note P4 melee`; never write player or guild names in it |
| `/atwp reset` | M0.2 | Clears the stored results and logs (not during P12) |
| `/atwp help` | M0.2 | Prints the commands your version has |
| `/atwp ctx <label>` | M0.3 | Labels the current context (`solo`, `party`, `dungeon`, `raid`, `bg`…); every reading also carries the context the probe detects by itself. `/atwp ctx` alone prints the current stamp, `/atwp ctx clear` removes the label |
| `/atwp watch on\|off` | M0.3 | Automatic readings in combat (at combat start, every second, at encounter start, at combat end and 2 s later): used by P3–P7 and P9. It stays on across `/reload` until `/atwp watch off` |
| `/atwp perf [hz] [units]` | M0.6 | P10: times the threat reading at 2, 5 and 10 Hz with 5, 10 and 40 units (or the given ones), 30 seconds each |

Later steps may add commands; the usage line printed by `/atwp help` (and by any unknown command) always lists the
ones your version has.

## What each step adds

| Step | Checks | File |
|---|---|---|
| M0.2 | skeleton, registry, export, name scrubbing, install script | `AzTw_Probe.lua` |
| M0.3 | P1–P4 | `Checks_ThreatAPI.lua` |
| M0.4 | P5, P6, P9 | `Checks_Units.lua` |
| M0.5 | P7, P8 | `Checks_Events.lua` |
| M0.6 | P10–P12 | `Checks_Cost.lua` |

## P1–P4 (M0.3)

Each `/atwp run <id>` prints one line: the check, the **proposed** verdict in brackets and its details. The verdict
follows the criteria of SPEC-08 §1; when the evidence is not complete yet it stays `todo` and the details say what is
missing. M0.7 decides the final verdicts from the export, so keep playing the contexts even after a `supported`.

| Check | What you do | What it records |
|---|---|---|
| P1 | Once per client build, after the login: `/atwp run P1` | The six values of `GetBuildInfo`, `WOW_PROJECT_ID` (and every `WOW_PROJECT_*` constant), the client language, `C_Secrets.HasSecretRestrictions()`, `C_CombatLog.IsCombatLogRestricted()` and a census of the APIs P2–P12 use (present or absent) |
| P2 | `/atwp run P2` with no target, a friendly target, a hostile mob not engaged, during a fight and on the corpse. After the first run of the session it also reads by itself every 0.5 s while you are in combat | The case it recognised (a no target, b friendly, c not engaged, d in combat with you, e in combat with someone else, f dead mob); for each of the four threat functions, called with the mob's token and with its GUID, how many values came back and the kind of each (`nil`, `secret`, boolean, number with its value); the threat colours and whether the native threat warning is on |
| P3 | `/atwp watch on` once, `/atwp ctx <label>` when you enter a context, then play; `/atwp run P3` at the end | For you, every group member and `targettarget` on the same hostile mob: the `C_Secrets.ShouldUnitThreat…BeSecret` predictions and whether they were right, which values and which state came back secret, per context. P3b: the first time a value is secret in a context, the probe passes it to a hidden bar and a hidden text and records only whether the client accepted it |
| P4 | In a party with a tank, on one mob with many hit points: the tank builds threat for about 10 s, you write `/atwp note P4 melee` and deal damage until you take the aggro. Three times in melee, three at range (`/atwp note P4 ranged`); then `/atwp run P4` | Each note arms one trial: 10 samples a second of your threat and the tank's, and when the aggro changes the 3 s before and 1 s after, with the highest raw and scaled percentages before the change |

What to expect and what to send back:

- The proposed verdicts: P1 `supported` when the client is build `1.60.1` (70170 or later) with interface 16001; P2
  `supported` when the five cases a–d and f were seen and nothing was missing, out of range or only reachable with the
  GUID; P3 `not supported` when, in a party, dungeon or raid fight, both your values and your state were secret,
  `partial` when something was secret, `supported` only after fights solo, in a party, in a dungeon and in a raid with
  nothing secret; P4 `supported` when the aggro changed at about 110 % raw in melee and 130 % at range, with the
  scaled percentage at about 100 just before.
- If P3 shows the values secret in a party, P4 cannot measure anything there: repeat it in `solo-combat` with a pet or a
  companion as the tank (the probe uses `pet` when you have no group), or leave it without a verdict.
- `/atwp export` contains the per-case counters of P2, the per-context counters of P3, the P4 trials and the logs of
  every reading; send the whole text. A secret value appears only as `S` (or `secret`), never as a number.

## P5, P6 and P9 (M0.4)

The three checks read by themselves while `/atwp watch on` is set: keep it on for every fight in a party, a dungeon
and a raid, and label the context with `/atwp ctx <label>` when you enter it. `/atwp run P5`, `/atwp run P6` and
`/atwp run P9` print the proposed verdict; like P1–P4 it stays `todo` while the evidence is incomplete.

| Check | What you do | What it records |
|---|---|---|
| P5 | In a party or a dungeon, pull 3 or more mobs, at least one that nobody targets; once with the enemy nameplates shown and once hidden (the game's key; the probe never changes a setting). Then `/atwp run P5` | Every second in combat (every third second in a raid): which hostile mobs `target`, `focus`, `mouseover`, `targettarget`, `pettarget`, `boss1–5`, the members' targets and `nameplate1–40` reach (one mob counted once, by GUID in memory), and for each mob token kind × unit kind (you, your pet, the party or raid members) how many readings came back with a number, only a state, secret, `nil` or an error. Per fight: the mobs nobody targets and those seen only on a nameplate, and whether they answered; for mobs no token reaches any more, whether `UnitTokenFromGUID` gives them one; whether the target can be compared with the other tokens (`C_Secrets.CanCompareUnitTokens`); the nameplate events and the time a sweep takes |
| P6 | At least three fights in a party and three in a dungeon, keeping a hostile mob targeted; then `/atwp run P6` | Per context, how many `UNIT_THREAT_LIST_UPDATE` and `UNIT_THREAT_SITUATION_UPDATE` arrived, the kind of unit in their payload (`target`, `nameplate`, `player`, `party`…, or `secret`), the average and the peak per second. In combat the probe also samples the threat on your target ten times a second (you, your pet and up to four members) and measures the delay from a change it sees to the next event (negative when the event came first), the changes with no event within 1 s and the events with no change. The first 20 events of each fight are in the log |
| P9 | `/atwp run P9` when you enter a dungeon (a group from the finder and, if you can, one made by hand) and a raid, again after a pull and after a boss | For every unit (you, the members, target, focus, `targettarget`, nameplates, bosses): whether `UnitGUID` is readable, secret or `nil`, and whether `C_Secrets.ShouldUnitIdentityBeSecret` predicted it; GUID types and creature ids (never a player GUID); whether `UnitTokenFromGUID` leads back to the same GUID; the roles (`TANK`, `HEALER`, `DAMAGER`, `NONE` or secret); whether the target can be compared with each member's target. While watching, it also checks that the target, the focus, the bosses and the nameplates keep the same mob GUID until the token changes, and logs any mob whose GUID changed |

What to expect and what to send back:

- The proposed verdicts: P5 `supported` when you and the members answered on the target, the nameplates and the
  members' targets (and the bosses, if any), and a mob seen only on a nameplate answered too; `partial` when some of
  those never answered; `not supported` when only you on your target answered. P6 `supported` after three fights in a
  party or a dungeon when both events arrived, also for mobs, with a median delay of 200 ms or less and few changes
  without an event; `partial` when they are rare, late or only for you; `not supported` when none arrived or their
  payload was always secret. P9 `supported` when GUIDs and roles were readable in a dungeon and no mob GUID changed;
  `partial` when player GUIDs or roles were secret, or roles were always `NONE`; `not supported` when mob GUIDs were
  secret or changed.
- P5 counts a secret answer as an answer and says how many there were: whether they are usable is P3's question. If
  the threat values are secret, P6 cannot measure the delay and stays `todo`; it still counts the events.
- `/atwp export` adds the P5 matrix per context, the P6 counters per context and the P9 counters per context, plus
  the logs `P5`, `P6` and `P9`.

## In-game procedure per context

Do the contexts in this order; each one assumes the probe is installed and `/atwp watch on` was run once. At the end of
each session in game, `/atwp export` and send the text back. Do not run `/atwp reset` between contexts.

### Solo

| # | Do | Checks |
|---|---|---|
| 1 | Log in, `/atwp run P1` | P1 |
| 2 | `/atwp ctx solo`; with no target, then a friendly target, then a hostile mob not engaged: `/atwp run P2` each time | P2, P3 |
| 3 | Fight a mob of your level (an elite with many hit points is better); after it dies, `/atwp run P2` with the corpse targeted | P2, P3, P8 |
| 4 | `/atwp run P12`, pull a mob, `/reload` in the middle of the fight, then `/atwp run P12` again; repeat with a logout | P12 |
| 5 | `/atwp run P11`, `/atwp run P8`, `/atwp perf` out of combat (simulated) | P8, P10, P11 |

### Party (open world, 2–5 players)

| # | Do | Checks |
|---|---|---|
| 1 | `/atwp ctx party`; fight a few single mobs | P3, P6 |
| 2 | With a tank: the tank builds threat for about 10 s, you (DPS) `/atwp note P4 melee` and deal damage until you take aggro; three times in melee, three at range (`/atwp note P4 ranged`); then `/atwp run P4` | P4 |
| 3 | Pull 3 or more mobs, with one that nobody targets, with enemy nameplates shown and then hidden; `/atwp run P5` | P5 |
| 4 | The tank uses a taunt at least once and you write `/atwp note P7 taunt`; `/atwp run P6`, `/atwp run P7`, `/atwp run P11` | P6, P7, P11 |

### Dungeon (5-player instance)

| # | Do | Checks |
|---|---|---|
| 1 | Entering: `/atwp ctx dungeon`, `/atwp run P9` | P9 |
| 2 | Play trash packs normally (3 or more mobs per pull when possible) | P3, P5, P6 |
| 3 | A boss: let the probe record the fight; after the kill `/atwp run P9` again | P3, P7, P9 |
| 4 | At the end: `/atwp run P3`, `P5`, `P6`, `P7`, `P8`, `P11` | all of them |

### Raid

| # | Do | Checks |
|---|---|---|
| 1 | In a raid group (a converted party is enough): `/atwp ctx raid`, `/atwp run P9` | P9 |
| 2 | Fight in the raid (a raid instance boss if possible) | P3, P5, P7 |
| 3 | During a fight with as many players as possible: `/atwp perf` | P10 |
| 4 | `/atwp run P3`, `/atwp run P11` | P3, P11 |

### Battleground (optional)

| # | Do | Checks |
|---|---|---|
| 1 | `/atwp ctx bg`; play a match; `/atwp run P11` and `/atwp run P3` | P3, P11 |

## Results

M0.7 reads the exports and writes `docs/spike/M0-results.md`: one row per check with the evidence, the verdict and the
consequence, the feature support matrix per context, and the MVP scope decision.
