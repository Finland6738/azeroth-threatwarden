# Spike: the probe addon

`AzTw_Probe` is a **throwaway** addon used in milestone M0 to answer, in the real WoW Forever client, what the design
cannot answer offline: which threat data the client gives an addon, in which contexts, and at which cost. The checks
P1–P12, with their exact calls, contexts, recorded fields and the consequence of each verdict, are specified in
[SPEC-08 §1](../specs/SPEC-08-quality-probe-release.md#1-probe-m0) (in Italian); the steps are in
[M0-probe.md](../roadmap/M0-probe.md).

> **Status: P1–P12 written (M0.6).** The probe installs and loads, lists P1–P12, stores notes and exports; P1–P4
> (client, threat functions, secret values, the tank and DPS trial), P5, P6, P9 (units and mobs, threat events, GUIDs
> and roles), P7, P8 (combat events, the damage meter) and P10–P12 (cost of sampling, restrictions, reload and
> logout) work, with `/atwp ctx`, `/atwp watch` and `/atwp perf`. Nothing has been verified in the real client yet.

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

All these commands exist (M0.4 and M0.5 add none: P5–P9 read through `/atwp watch`, `/atwp run` and, for the taunt of
P7, `/atwp note P7 taunt`).

| Command | Step | What it does |
|---|---|---|
| `/atwp` or `/atwp list` | M0.2 | Lists P1–P12 with a short description and the last verdict |
| `/atwp run <id>` | M0.2 | Runs one check now, for example `/atwp run P2`; checks that need a fight start their readings by themselves while active |
| `/atwp export` | M0.2 | Opens a movable frame with all results and logs as plain text, already selected: press Ctrl+C and paste it back |
| `/atwp note <id> <text>` | M0.2 | Stores a free-text observation, for example `/atwp note P4 melee`; never write player or guild names in it |
| `/atwp reset` | M0.2 | Clears the stored results and logs and stops a `/atwp perf` run; an armed P12 buffer is kept (do not reset in the middle of a P12 trial) |
| `/atwp help` | M0.2 | Prints the commands your version has |
| `/atwp ctx <label>` | M0.3 | Labels the current context (`solo`, `party`, `dungeon`, `raid`, `bg`…); every reading also carries the context the probe detects by itself. `/atwp ctx` alone prints the current stamp, `/atwp ctx clear` removes the label |
| `/atwp watch on\|off` | M0.3 | Automatic readings in combat (at combat start, every second, at encounter start, at combat end and 2 s later): used by P3–P7 and P9. It stays on across `/reload` until `/atwp watch off` |
| `/atwp perf [hz] [units] [mobs]` | M0.6 | P10: times the threat reading at 2, 5 and 10 Hz with 5, 10 and 40 units on 1 mob (or the given rate, units and mobs), 30 seconds each; it stops by itself. `/atwp perf stop` stops it earlier |

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

## P7 and P8 (M0.5)

P7 counts the unit events only while `/atwp watch on` is set; its combat log part and P8 work by themselves. Keep the
watch on in a party, a dungeon (with a boss) and, if you can, a raid; `/atwp run P7` and `/atwp run P8` print the
proposed verdict, `todo` while the evidence is incomplete.

| Check | What you do | What it records |
|---|---|---|
| P7 | Nothing at login. In a party and in a dungeon, the tank uses a taunt at least once and, right after it, you write `/atwp note P7 taunt`; fight a boss in the dungeon; let a few mobs die. Then `/atwp run P7` | **Combat log**: at login the probe tries to register `COMBAT_LOG_EVENT_UNFILTERED`, `COMBAT_LOG_EVENT` and `COMBAT_LOG_EVENT_INTERNAL_UNFILTERED` on a frame of its own: whether the client accepted each one, and any blocked or forbidden action that followed (the game may show its "blocked" message once: that is the answer, not a fault). How many events arrived, with the number and the kind of their arguments (never their content), and what the readers found at run time returned (`CombatLogGetCurrentEventInfo`, `C_CombatLogInternal.GetCurrentEventInfo`, `C_CombatLogSecure.GetCurrentEventInfo`: only the kinds), called on the first events and once per fight; `C_CombatLog.IsCombatLogRestricted()`. **Unit events** (watch on): whether `UnitAffectingCombat` agrees with `PLAYER_REGEN_DISABLED`/`ENABLED` at once or how late; `UNIT_TARGET` per kind of unit and what the mob targets after it (you, the group, another player, an NPC, nothing); `PLAYER_TARGET_CHANGED`; encounters (id, difficulty, size, result, never the name); deaths of members and mobs and which source saw each one first (`UNIT_HEALTH`, `UNIT_FLAGS`, `UNIT_DIED`, `PARTY_KILL`, `PLAYER_DEAD`, a check every second), with whether `UnitHealth` and `UnitHealthMax` were readable or secret; the spells cast by you, your pet and the members (spell id, or `secret`) and, when the caster had a hostile target, whether that mob turned to the caster within 0.5 s. Your note logs the group's casts of the last 10 s with their result, so the taunt's spell id can be read |
| P8 | Fight alone (a few mobs) and in a dungeon; the probe reads by itself 2 s after every fight. Then `/atwp run P8` | Whether `C_DamageMeter.IsDamageMeterAvailable()` says yes (and the reason when it says no); the names and values of `Enum.DamageMeterSessionType` and `Enum.DamageMeterType` (a type named like "threat" is flagged at the top of the verdict); the sessions of `GetAvailableCombatSessions` and the durations of `GetSessionDurationSeconds` against the length of the fight measured by the probe; for every session type and meter type, the kind of every field of every source (never its name or GUID), how many sources are you, how many have a death time; the three damage meter events and how long after the start or the end of the fight they came |

What to expect and what to send back:

- The proposed verdicts: P7 `partial` (the expected case) when the combat log gave nothing readable and the unit
  events worked (`UNIT_TARGET` on mobs, readable spell ids, the combat start, a death, a boss in a dungeon and a taunt
  followed by a turn of the mob), `supported` when, in addition, a reader returned readable values; `not supported`
  when `UNIT_TARGET` never came for a mob (or always secret), the group's spell ids were secret in instances, or
  `UnitAffectingCombat` never agreed with the combat events. P8 `not supported` when the damage meter is missing or
  not available (the reason is saved), `partial` when fields were secret in instances, a group showed only your own
  data, death times were secret or the durations were more than 1 s off the fights, `supported` after a fight alone
  and one in a dungeon with everything readable and aligned.
- P7 never treats a taunt as identified by itself: M0.7 reads the spell ids followed by a turn of the mob, and your
  notes, to decide which ones are taunts.
- `/atwp export` adds the combat log registration and counters, the P7 counters per context (combat start, targets,
  casts per spell id, deaths), the encounters, and the P8 counters per context (availability, durations and their
  differences from the fights, the fields per session, the events), plus the logs `P7` and `P8`.

## P10, P11 and P12 (M0.6)

| Check | What you do | What it records |
|---|---|---|
| P10 | In a raid, in a fight (best); otherwise anywhere, in and out of combat. Keep a hostile mob targeted, `/atwp watch off`, then `/atwp perf` and play normally for about 5 minutes. For one configuration only: `/atwp perf 5 40` (rate, units); a third number reads several mobs (`/atwp perf 5 40 8`). `/atwp run P10` only summarises | For each configuration (rate × units × mobs, 30 s): milliseconds per tick (median, 95th percentile, maximum, from `debugprofilestop`) and per second; kilobytes of compact samples per minute (retained: measured with the samples and without them; gross: before the cleanup, so it includes temporary garbage), for the addon and for the whole Lua memory; FPS before and during; how many readings gave a number, `nil`, a secret or an error; whether it was a `raid fight` (40 different units were there) or `simulated` (the available units read again and again) |
| P11 | The log is always on from the login. In **each** context (solo in a fight, party, dungeon, raid and, if you like, battleground), during a fight with a hostile mob targeted and not during a boss: `/atwp run P11`, wait 15 s | Per context: `ADDON_ACTION_BLOCKED` and `ADDON_ACTION_FORBIDDEN` (function, and whether the probe was blamed), restriction state changes and the restrictions active, the combat lockdown, every failed game call of the probe (counts and scrubbed texts). `/atwp run P11` adds 1000 threat readings in one frame (how many answered, `nil`, secret or errored, and whether the answers changed), registers and unregisters the two threat events, and starts a ticker of 10 ticks to see that it keeps running in combat |
| P12 | Alone: `/atwp run P12` (arms a buffer), pull a mob, `/reload` in the middle of the fight, wait 10 s, `/atwp run P12`. Then again for the logout: `/atwp run P12`, pull a mob and log out in the fight (or, if the client does not allow it, right after), log in, wait 10 s, `/atwp run P12` | One compact sample a second in combat in the saved variables, with a final stamp at logout; at the next load: samples found against samples written, whether the final stamp is there, the time since the last sample, combat state and lockdown right after, whether `PLAYER_REGEN_DISABLED` came again, and when the threat on the target answered again |

What to expect:

- A `/atwp perf` run is silent while it measures, prints one line per configuration and ends with the P10 verdict. At
  the end of each configuration there is a short stutter: the probe cleans up the Lua memory to measure it. Nothing
  keeps running afterwards, and a `/reload` cancels the run. The samples themselves are not saved, only the figures.
- The proposed P10 verdict: `supported` when 40 units at 5 Hz stay within the proposed budget (at most 1 ms per tick
  at the 95th percentile and 5 ms per second), `partial` when only fewer units or 2 Hz do, `not supported` when even 5
  units at 2 Hz do not. A `raid fight` result is preferred to a `simulated` one.
- The proposed P11 verdict: `supported` when the bursts answered in a fight alone, in a party, in a dungeon and in a
  raid, with nothing blocked and no limit; `partial` when something was secret or `nil` under a restriction, or the
  ticker or the event registration failed; `not supported` when a threat call or the registration of a threat event was
  blocked or errored where it matters. Blocked actions of other addons, and the refusal of the combat log (P7), are
  counted but do not change it.
- P12: the first `/atwp run P12` arms, the one after the reload reports, the next one arms again. If the run after a
  reload says it armed a **new** buffer, the reload did not save the old one: write `/atwp note P12 lost`. The proposed
  verdict is `supported` after a reload in a fight and a logout with everything found, `partial` when samples or the
  final stamp were missing or the fight was not readable after.

**Numbers to send back.** The whole `/atwp export`. It contains, for P10, one line per configuration (above all
`5Hz x 40 units` and `2Hz x 5 units`: p95 and ms per second, retained KB per minute, FPS before and during, `raid fight`
or `simulated`); for P11 the counters per context, the bursts, tickers and error texts; for P12 each trial with the
samples found, the final stamp and the readings after the load. Say also how many players were in the raid, whether the
watch was on, and anything you saw on screen (a "blocked" message, a freeze).

## In-game procedure per context

Do the contexts in this order; each one assumes the probe is installed and `/atwp watch on` was run once. At the end of
each session in game, `/atwp export` and send the text back. Do not run `/atwp reset` between contexts.

### Solo

| # | Do | Checks |
|---|---|---|
| 1 | Log in, `/atwp run P1` | P1 |
| 2 | `/atwp ctx solo`; with no target, then a friendly target, then a hostile mob not engaged: `/atwp run P2` each time | P2, P3 |
| 3 | Fight a mob of your level (an elite with many hit points is better); after it dies, `/atwp run P2` with the corpse targeted | P2, P3, P8 |
| 4 | `/atwp run P12`, pull a mob, `/reload` in the middle of the fight, wait 10 s, then `/atwp run P12` again; repeat with a logout | P12 |
| 5 | In another fight: `/atwp run P11` | P11 |
| 6 | `/atwp run P8`, `/atwp watch off`, `/atwp perf` out of combat (simulated); then `/atwp watch on` again | P8, P10 |

### Party (open world, 2–5 players)

| # | Do | Checks |
|---|---|---|
| 1 | `/atwp ctx party`; fight a few single mobs | P3, P6 |
| 2 | With a tank: the tank builds threat for about 10 s, you (DPS) `/atwp note P4 melee` and deal damage until you take aggro; three times in melee, three at range (`/atwp note P4 ranged`); then `/atwp run P4` | P4 |
| 3 | Pull 3 or more mobs, with one that nobody targets, with enemy nameplates shown and then hidden; `/atwp run P5` | P5 |
| 4 | The tank uses a taunt at least once and you write `/atwp note P7 taunt`; `/atwp run P6`, `/atwp run P7` | P6, P7 |
| 5 | During a fight: `/atwp run P11` | P11 |

### Dungeon (5-player instance)

| # | Do | Checks |
|---|---|---|
| 1 | Entering: `/atwp ctx dungeon`, `/atwp run P9` | P9 |
| 2 | Play trash packs normally (3 or more mobs per pull when possible) | P3, P5, P6 |
| 3 | A boss: let the probe record the fight; after the kill `/atwp run P9` again | P3, P7, P9 |
| 4 | During a trash fight: `/atwp run P11` | P11 |
| 5 | At the end: `/atwp run P3`, `P5`, `P6`, `P7`, `P8` | all of them |

### Raid

| # | Do | Checks |
|---|---|---|
| 1 | In a raid group (a converted party is enough): `/atwp ctx raid`, `/atwp run P9` | P9 |
| 2 | Fight in the raid (a raid instance boss if possible) | P3, P5, P7 |
| 3 | During a long fight with as many players as possible: `/atwp watch off`, `/atwp perf`; then `/atwp watch on` again | P10 |
| 4 | During a fight, after the perf run ended: `/atwp run P11`; then `/atwp run P3` | P3, P11 |

### Battleground (optional)

| # | Do | Checks |
|---|---|---|
| 1 | `/atwp ctx bg`; play a match; `/atwp run P11` during a fight, `/atwp run P3` at the end | P3, P11 |

## Results

M0.7 reads the exports and writes `docs/spike/M0-results.md`: one row per check with the evidence, the verdict and the
consequence, the feature support matrix per context, and the MVP scope decision.
