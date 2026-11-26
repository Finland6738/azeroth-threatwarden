# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

- M3.5: alert settings and the quick mute, behind the `alerts` and `coach` switches (off until `v0.3.0`, so nothing
  changes yet for players). An *Alerts* card in Settings (alerts, message, visual effect and sound, cooldown, alerts
  about others, the pet, the monitor's thresholds with a button to their card, the note that the game's own threat
  warning may warn twice, and the Threat Coach switch); `/atw mute` and a key binding with no default key
  (`Bindings.xml`) that mute the alerts until the end of the fight, or of the next one; a right-click menu on a row,
  *Mute alerts about this unit* (until a reload, nothing saved). Design previews `settings-alerts` and `alert-muted`;
  manual pages *Settings*, *Commands* and *Alerts and Coach* updated.
- M3.4: the Coach strip in the Monitor view, behind the `alerts` and `coach` switches (off until `v0.3.0`, so nothing
  changes yet for players). Between the header of the enemy and the list: an alert with its state badge for 4 seconds
  (a more severe one replaces it), then the Coach's tip, with a confidence pill for estimates and predictions, *Alerts
  muted*, and *Advice appears during combat* out of combat; hover for the whole text, why, the data category, the
  confidence and since when. In a low window the list header gives way, never the strip. The window's border takes the
  colour of an alert's state once (120 ms in, 1.5 s, 320 ms out; no flashing, no glow); with the window message off the
  title bar's pill shows the state's icon too. Alerts gain a reason in the tooltip (new `ALERT_WHY_*` texts in English
  and Italian), two icons (`coach`, `mute`), design previews and a new manual page *Alerts and Coach*.
- M3.3: the Threat Coach rules, behind the `coach` switch (off until `v0.3.0`, so nothing changes yet for players). One
  tip at a time for your role (tank, DPS, healer), each with its reason, the category of the data it rests on and, for
  estimates and predictions, a confidence; predictions only with medium or high confidence, with *may* and *about*.
  *Not enough data for advice* with the reason when your row is unknown, the tank is unknown or the trend is not ready.
  A tip that leaves does not come back before its cooldown (8 s, 15 s for reassurances); the numbers change at most
  once a second. No message names a cause, an ability or a class (a test checks every Coach and alert text in both
  languages). New setting `settings.coach.enabled` (on by default; its switch comes with the Alerts card in M3.5).
  `/atw debug` shows the current tip and the rules shown.
- M3.2: the alert manager, behind the `alerts` switch (off until `v0.3.0`, so nothing changes yet for players). An alert
  is raised only when a risk **enters**: your state rises to Warning or Danger, or the unit holding the mob changes (a
  new `AGGRO_CHANGED` event of the monitor). Seven kinds (Warning, Danger, aggro, margin, lost mob, pet, others), one
  alert per transition, a cooldown per kind and unit that survives target changes and fights, at most one alert about
  others and one sound every 3 s; only in combat and for the monitored mob. Channels: a message and a visual effect for
  the window (drawn from M3.4), a game sound for Danger and aggro (off by default), never anything in chat. A mute until
  the end of the fight and a per-session exclusion of a unit (their command, key and menu arrive with M3.5). Account
  saved data move to schema 3 (`settings.alerts`; a migration adds the defaults and keeps everything else). `/atw debug`
  has a new *Alerts and Coach* section.

### Documentation

- M3.1: specification of alerts and the Threat Coach (SPEC-04, Italian), written before the in-game M0 probe like M2.
  Alerts fire only when a risk **enters** (a state rises, or the unit holding the mob changes: a new `AGGRO_CHANGED`
  event of the monitor), never on every update, with a cooldown of 8 s per kind and unit, on three channels (a message
  in the window, a one-time tint of the window border, a game sound for Danger and aggro, off by default), never in
  chat and never opening the window; `/atw mute` and a key binding mute them until the end of the fight. The Coach
  picks one tip at a time from a rule table per role (tank, DPS, healer), each with its reason, its data category and,
  for predictions, a confidence (only medium or high); it never names a cause or an ability, and says *Not enough data
  for advice* with the reason when the data is unknown or *state only*. Also: the Coach strip in the window, account
  schema 3 (`settings.alerts`, `settings.coach`), the *Alerts* settings card, the tests per step, SPEC-09 Q11–Q12
  refined, and the M3 steps detailed in the milestone file. Nothing changes in the addon yet.
- M2.R: `v0.2.0` released on GitHub; the release step is ticked in the M2 milestone file.

## [0.2.0] - 2026-11-26

The second test version: the **Threat Monitor** (milestone M2), switched on. On the mob you target (or on your friend's
target) the Monitor tab lists who is on its threat list, the tank, the scaled percentage, the margin, the trend and the
state **Safe**, **Warning**, **Danger** or **Unknown**. What it shows depends on what the client gives an addon:
**values**, **state only** (no numbers) or **unknown**, always with the reason, never an invented number. `/atw demo`
plays an invented fight to try it without one. The thresholds (Warning 80 %, Danger 95 %) and the rate (5 reads per
second) are **provisional**.

It has been checked by offline tests only. The results of the M0 probe (which threat data the client gives an addon)
and the in-game checklists of [M1](https://github.com/Finland6738/azeroth-threatwarden/blob/v0.2.0/docs/checklists/M1.md) and [M2](https://github.com/Finland6738/azeroth-threatwarden/blob/v0.2.0/docs/checklists/M2.md) are **still open**, so nothing
below has been verified in the real client. The monitor was built before the probe, on the specification's assumptions.
Alerts, Coach, recording and reports are switched off until later versions. The probe is a development tool in the
repository and is not part of this package.

### Documentation

- M2.8: the [in-game checklist of M2](https://github.com/Finland6738/azeroth-threatwarden/blob/v0.2.0/docs/checklists/M2.md): the monitor solo, in a party, a dungeon and a raid, the
  tank line and margin, Warning and Danger without flicker, target changes and deaths, *state only* and unknown values,
  sorting, the settings, demo mode, CPU and frame rate in a raid at 2, 5 and 10 Hz, and the threshold tuning notes
  (Q7). README status updated: M2 is complete in code; the in-game check and the probe are open.

### Added

- M2.7: performance budget and long tests of the threat monitor. Long scenarios (`Tests/long/test_monitor_raid.lua`,
  on a simulated raid of 40, `Tests/lib/raid.lua`) play hours of combat ticks through the whole pipeline, from the
  scanner to the list: one mob at 2, 5 and 10 Hz with tank deaths, a boss and four adds with frequent target changes
  through the three probe outcomes, and states oscillating around the thresholds; the state rules are checked on every
  tick and memory, pools and frames stop growing. A per-tick budget (`Tests/long/test_monitor_budget.lua`) fails the
  *Long tests* workflow on a regression of work (VM instructions), allocation or time (relative to a reference loop);
  the workflow now runs on changes to the interface too. The default of 5 reads per second stays provisional until the
  in-game probe P10; its offline cost is recorded in SPEC-09 Q14 and SPEC-01 §5.

- M2.6: monitor settings and demo mode, behind the `monitor` switch. A *Monitor* card in Settings: Warning and Danger
  thresholds (Danger always at least 5 points above), reads per second (2-10 Hz, default 5, provisional), units per read
  (5-40), when the window shows (*In group or combat*, the default: it opens at a fight and on joining a group and
  closes 10 s after a fight outside a group; *Always*; *Manually*), the order of the list, *Pin me on top* and *Follow
  the target of a friend*. The account's saved data move to schema 2 (`settings.monitor`; a migration adds the
  defaults and keeps everything else). `/atw demo` (or the button of the card) plays an invented fight through the same
  model, states and list as a real one, marked *Demo* in the window; it reads nothing from the game, saves nothing, and
  stops with `/atw demo stop`, when the window closes or as soon as a real fight starts. Design previews of the card and
  of the demo, and the wiki pages *Settings*, *Threat Monitor* and *Commands* updated.

- M2.5: the threat list view in the Monitor tab, behind the `monitor` switch (off until v0.2.0; the M1 text stays
  while it is off). `UI/ThreatList.lua`: the header of the monitored mob (name, kind, your state, the tank, the
  margin), one row per unit on its threat list (class colour, role and holder icons, bar, scaled percentage, margin in
  a wide window, a state badge with icon and word, trend arrow or `~2 s` of a prediction, your row ringed), tooltips
  with every value, its reliability category and the reason of everything missing, the *state only*, unreadable, empty,
  out of combat, combat ended, dead and lost views, a data-quality footer, four orders (percentage, absolute threat,
  risk, recent change) with *Me on top*, at most one new order a second and at once on Danger, *+N more* with your row
  always visible, and a narrow layout that keeps the state's word. It redraws once per update, only while visible, and
  writes a text only when it changes. The title bar's pill follows the monitor's mode. New role icons in the icon sheet,
  new locale keys in English and Italian, design previews of every state and the wiki page *Threat Monitor*.
- M2.5: for the view, `Compat.ClassColor` and `Compat.Unit.Classification`, the mob's name, classification and holder
  name in `Data/TargetTracker.lua` (and `TARGET_STATUS` when a dead mob is deselected), and the share of valid reads of
  the last 10 s in `Data/ThreatScanner.lua`.

- M2.2: the threat scanner and the target tracker, behind the `monitor` switch (off until v0.2.0).
  `Data/TargetTracker.lua` picks the monitored mob (the hostile target, or the target of a friendly target), keys it by
  GUID or by a counter when the GUID is secret, and sees target changes, a death, a disappearance and a new creature
  behind the same token (`TARGET_CHANGED`). `Data/ThreatScanner.lua` reads the threat of the player, the pet and the
  party or raid only in combat, with a mob and a consumer (the window on the Monitor tab): threat events gathered to at
  most one full scan every 100 ms plus a 5 Hz tick that stops at the end of combat, a cap of units read per scan with a
  round robin, one pooled record per unit and no allocation per scan; nil, error, missing and secret answers are kept
  as their reason, never as a value (`THREAT_SCANNED`, the threat capabilities). Compat gains allocation-free unit and
  group reads (`Compat.Unit`, `Compat.Group`, the new API entry `group.RaidIndex` for `UnitInRaid`) and the lead of the
  unit holding the mob (`Compat.Threat.ReadLead`). After a `/reload` in combat the combat starts again from the
  player's combat flag at `PLAYER_ENTERING_WORLD` [probe P12].

- M2.3: the threat model and calculator, behind the `monitor` switch. `Data/ThreatModel.lua` keeps one pooled row per
  watched unit: whether it is on the mob's threat list, stale (older than twice its read interval, at least 0.5 s, or
  after the fight), why its values are missing, and every value with its reliability category (detected, calculated,
  estimated, predicted; unknown with a reason when missing). `Data/ThreatCalc.lua` computes the margin (100 minus the
  percentage, or for the tank 100 minus the second highest), the trend (least squares over the valid samples of the
  last 3 s, at least 3 samples over 0.5 s, with a high, medium or low confidence, otherwise *Insufficient data*) and
  the time to overtake (only with a rising trend of at least medium confidence, within 10 s). Samples start again at a
  new mob, a new fight, a new holder of the mob and after a gap of more than 1 s. Each update publishes
  `THREAT_UPDATED` and allocates nothing.

- M2.4: threat states, thresholds and tank detection, behind the `monitor` switch. `Data/ThreatState.lua` gives every
  row on the threat list SAFE, WARNING, DANGER or UNKNOWN with its reason: a non tank on its own percentage (WARNING at
  80 %, DANGER at 95 %, provisional, or while it holds the mob), the tank holding the mob on its margin over the
  second, the game's threat state in *state only* mode, UNKNOWN with the reason when nothing is readable or the row is
  stale. A predicted WARNING when the trend reaches DANGER within 3 s with at least a medium confidence. Hysteresis of 3
  points and a 1 s dwell for falls (rises are immediate), also after the fight, so states never flicker. Tanks are the
  units with the TANK role, or whoever holds the mob when no one has it; a tank that loses the mob to a non tank is
  DANGER (*lost aggro*); no readable holder is an Unknown tank. `STATE_CHANGED` only on a real change of the shown
  state, `THREAT_MODE_CHANGED` when the reading mode changes. The thresholds read the player's settings when they exist
  (M2.6).

### Changed

- M2.R: the `monitor` switch is on: the threat monitor of M2.2-M2.7 (scanner, model, calculator, states, threat list,
  settings and demo mode) is part of this version. The Monitor tab no longer says that monitoring arrives later, and the
  module pill, the `/atw demo` command and the *Monitor* card of Settings work. Entries below that say a part is
  "behind the `monitor` switch (off until v0.2.0)" describe it before this release.

- M2.7: three allocations per tick removed from the threat list, with no change of behaviour: reading a setting
  (`Config:Get`, done at every bar animation) no longer splits its path each time, recolouring a region in
  `UI/Theme.lua` writes over its entry instead of making one, and the list asks for the colour of a class once. In a
  raid of 40 a tick with changing values went from about 12 KB of new tables to a few bytes of new text.

- M2.4: the scanner's allocation test keeps the smallest growth of three batches of 500 scans under 4 KB, as the
  model's test does: a growth of the Lua state outside the scans (2.5-2.8 KB now and then) no longer fails it, while
  an allocation per scan (at least 16 KB) still does.

- M2.1: the test fight scripts (`Tests/lib/fight.lua`) gain the verbs `outcome` (the three probe outcomes,
  `Fight.OUTCOMES`), `role`, `secrets`, `answer`, `clearAnswers`, `silent` and `event`, for the monitor's tests.

### Documentation

- M2.1: specification of the threat monitor, written before the M0 probe results by the owner's decision of
  2026-11-25 and designed for every probe outcome (threat values readable, *state only*, nothing readable). SPEC-03
  §1–§3: per-row reading modes, the monitored mob (target or target of target), units watched and their cap, threat
  events plus a 5 Hz combat tick (provisional), freshness, hysteresis and a 1 s dwell, the tank margin, trend and time
  to overtake with confidence, sorting, and what each state looks like; §5.1 when the window shows itself (Q13); §6 the
  modules, Bus events and tests of each step M2.2–M2.7. SPEC-02: `ThreatRecord` and `ThreatRow` fields, calculated
  values, schema 2 (`settings.monitor`). SPEC-08 §2.1: the fight-script format. The decision is recorded in SPEC-00 §7
  (D7), the roadmap and M0.7's scope.
- M1.R: `v0.1.0` released on GitHub; the release step is ticked in the M1 milestone file.

## [0.1.0] - 2026-11-25

The **first test version**: the foundations of the addon (milestone M1). It is built for WoW Forever (Interface 16001)
and has saved settings with migrations, English and Italian, three themes, a movable window, Settings and an Info page with
the credits, the commands `/atw` and `/threatwarden`, a minimap button, the Addon Compartment entry and the diagnostic
report `/atw debug`. **It reads no threat yet**: the threat monitor arrives in v0.2.0, and every part of a later
milestone is switched off.

It has been checked by offline tests only. The in-game check of M1
([checklist](https://github.com/Finland6738/azeroth-threatwarden/blob/v0.1.0/docs/checklists/M1.md)) and the results of
the M0 probe (which threat data the client gives an addon) are **still open**, so nothing below has been verified in the
real client. The probe is a development tool in the repository and is not part of this package.

### Added

- M1.8: the **Settings** page (`UI/Settings.lua`): Appearance (theme Nebula, Aurora or Warden, neon effects,
  animations, addon or game font), Language (Automatic, English, Italiano, with *Reload now*), Window (lock, scale,
  minimap button, reset window) and *Reset settings*, which asks for a second click. Every change applies at once,
  except the font (complete after a game restart) and the language (after a reload); saved data that cannot be written
  is announced and never rewritten. The same page is in the game's own settings window, if the client allows it. The
  **Info** page (`UI/About.lua`, `/atw about`): logo, version, *Created and designed by Finland. Made with the Italian
  guild NEBULA.* with the NEBULA logo of the theme, the repository and Ko-fi in copy boxes, licence and notices.
  Design previews (`tools/make_mockups.py`, `docs/specs/mockups/`, never screenshots) of the window, Settings and Info
  in three themes and two languages; wiki pages *Installation*, *Interface Tour*, *Settings* and *About*. Not run in
  the game.
- M1.7: the main window (`UI/Window.lua`): compact layout for the Monitor tab (which says that threat monitoring
  arrives in v0.2.0), wide layout for Settings (a placeholder until M1.8), title bar with the logo, the module state
  (*Off* in this version), lock and close; moved by the title bar, resized from the corner grip, scaled and locked;
  position, size, scale, lock, tab and visibility remembered per character; Esc closes it; it comes back inside a
  smaller screen. **`/atw`** and **`/threatwarden`** (`Core/Commands.lua`) with `show`, `hide`, `lock`, `unlock`,
  `reset`, `settings`, `about`, `debug`, `help`, in English and Italian; `demo`, `mute` and `reports` say which version
  brings them. A minimap button (hideable, saved per account) and the Addon Compartment entry (`UI/Launcher.lua`):
  left click shows or hides the window, right click opens Settings. Wiki page *Commands*. Not run in the game.
- M1.6: the look of the addon. `AzerothThreatwarden/Media/` with the textures and icons drawn by
  `tools/make_media.py` (rounded shapes, shadow, glows, the icon sheet with four state icons of different shapes), the
  logo from the owner's picture (also the AddOns list icon), the NEBULA logos for the credits and the fonts Outfit,
  JetBrains Mono and Orbitron with their OFL texts (`tools/make_fonts.py`). `UI/Assets.lua`, `UI/Theme.lua` (Nebula,
  Aurora and **Warden**; the SAFE, WARNING, DANGER and UNKNOWN colours identical in every theme; a theme changes without
  `/reload`; fonts fall back to the game's), `UI/Motion.lua` and the widget kit `UI/Widgets/` (buttons, cards, tabs,
  title bar, dialog, fields, switch, slider, select, tooltip, and the threat bar, state badge and stripe, with no data
  until v0.2.0). The `/atw debug` box now has this look, and the report gains a *Look* section. `check_addon.py` also
  requires every media file in `UI/Assets.lua`, `check_package.py` every media file in the package. Not run in the game.
- M1.5: `Core/Config.lua` keeps the two SavedVariables (`AzerothThreatwardenDB` per account, `AzerothThreatwardenCharDB`
  per character) at schema 1 of SPEC-02 §3: typed rules with enumerations and ranges, defaults added without
  overwriting, one idempotent migration step per version run on a copy, **read-only** when the saved schema is newer
  (or a migration fails: the data is never rewritten), damaged tables set aside under `corrupt` (at most 5) instead of
  stopping the addon, unknown keys always kept; `Config:Set` validates and emits `CONFIG_CHANGED(path)`. The language
  setting `account.settings.language` (`auto`, `enUS`, `itIT`) is applied by `Core/Locale.lua` at load: `auto` follows
  the client, other client languages fall back to English, a change takes effect after `/reload` (the Settings page to
  change it is M1.8). The *Saved data* section of `/atw debug` now comes from Config (schema found, read-only, `corrupt`
  entries, problems corrected, size). Not run in the game.
- M1.4: `Core/Compat.lua`, the only door to the game: the API table of SPEC-01 §8.2 (58 entries, checked against the
  Forever dump) with the states available, missing, restricted and error; the capabilities of §8.4, unknown until a
  reading proves them; the client restrictions; secret-value checks that never read a secret; the normalized threat
  read (`Compat.Threat.Read`: values, state only or none, with the reason), allocation-free, ready for M2.
  `Core/Bus.lua` (internal events), `Core/Scheduler.lua` (named, bounded ticks; none runs yet) and
  `Core/Diagnostics.lua` (the addon's error ring and the diagnostic report, in English and without names).
  **`/atw debug`** opens the report in a box, already selected, to paste into a bug report; the other commands arrive
  with the window (M1.7). A test checks that no file but Compat calls the game. Not run in the game.
- M1.3: the offline test harness `Tests/` (development only, never packaged), adapted from Azeroth Accord:
  `run_tests.py` (lupa 2.8, Lua 5.1, the real libraries and the addon in TOC order, a name filter, `-v`, `--long`, the
  libraries fetched when missing), assertions and harness with a `/reload` and re-login simulation of the SavedVariables,
  and a mock client for the environment, secret values, clock and timers, frames and events, the client build, units and
  groups, combat and instances, and the threat API (computed, scripted, secret and `nil` answers; each file cites the
  Forever dump and marks what is an assumption until the probe). Fight scripts (`lib/fight.lua`) for scripted pulls.
  Tests of the addon's start, `/reload`, feature switches (all off), the language tables (ADR 0009 rule 3) and of the
  harness itself; the first long scenario (a 40-player raid). CI always runs the quick tests, the *Long tests* workflow
  the long ones.
- M1.2: the addon skeleton `AzerothThreatwarden/` — TOC for Interface 16001 with the two SavedVariables, the Addon
  Compartment functions, licence and credits; `embeds.xml` with LibStub, CallbackHandler, AceAddon, AceEvent,
  AceConsole, LibDataBroker and LibDBIcon; `Core/Init.lua` (addon object, Forever check, lifecycle, combat start and
  end, debug sections, Compartment entry points), `Core/Locale.lua` (own language tables, English as fallback),
  `Locales/enUS.lua` and `itIT.lua`, `Core/Features.lua` with every later part switched off. It shows only its entry in
  the AddOns list and in the Addon Compartment; no window, command or saved setting yet. Not run in the game.
- M1.2: tools copied from Azeroth Accord: `fetch_libs.py`, `install_addon.py`, `check_addon.py` (TOC, embeds, locales,
  colours, media) and `check_package.py` (what the release zip holds; never the probe or `assets/`), both run by
  `check_docs.py`; [docs/RELEASING.md](docs/RELEASING.md) and [docs/third-party.md](docs/third-party.md).

### Documentation

- M1.9: the in-game checklist of milestone M1 (`docs/checklists/M1.md`), to be run by the owner in WoW Forever
  and reported with the *In-game test report* form; README status: M1 complete in code, in-game check open. Not run
  in the game.
- M0.0: repository bootstrap. The owner's original specification (`docs/specs/source-specification.md`) and the
  detailed specification in Italian, [SPEC-00](docs/specs/SPEC-00-vision-scope.md) to
  [SPEC-09](docs/specs/SPEC-09-risks-open-questions.md): vision and the binding data reliability categories, platform
  and the threat APIs of the Forever dump (including **secret threat values** and the missing
  `CombatLogGetCurrentEventInfo`), data model, monitor, alerts and Coach, recording and replay, analytics,
  multi-target, the M0 probe checks P1–P12, risks and open questions. The owner's answers of 2026-11-25: names
  `AzerothThreatwarden` and `/atw` (Q1), GPL-3.0 for everything (Q2), MVP = M1–M4 (Q3), a standalone addon with NEBULA
  credits (Q4). ADRs 0001–0015 and their index. `ROADMAP.md` and one file per milestone, M0 to M8, with steps, checks
  and the model and effort of each step's session. `CLAUDE.md`, `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md`, both READMEs
  and the first wiki pages in English and Italian.

- M0.1: probe specification. [SPEC-08 §1](docs/specs/SPEC-08-quality-probe-release.md#1-probe-m0) now details every
  check P1–P12 of the probe `AzTw_Probe`: exact calls and unit tokens (checked against the Forever dump), contexts
  (solo, party, dungeon, raid, battleground), the fields recorded per reading (never names or player GUIDs, secret
  values only as `secret`), how the owner runs it, and the consequence of each verdict (supported / partially / not
  supported) on specs, ADRs and milestones. New common rules PRB-01–PRB-06, the context stamp and P3b (whether a secret
  value can be shown without being read). [docs/spike/README.md](docs/spike/README.md): what the probe is, the planned
  install (`tools/install_probe.py`, `tools/local.ini`), the planned `/atwp` commands and the in-game procedure per
  context. SPEC-01 §2: the threat secrecy checks live in `C_Secrets`.

- M1.1: specification of architecture, data, window and look, written before the probe results (what waits for the
  probe is marked **[probe Pn]**). [SPEC-01](docs/specs/SPEC-01-platform-architecture.md): every M1 module with its
  responsibility, Bus events and tests; the Bus event table up to M4; the feature switches; the Compat API table drawn
  from the Forever dump, the capabilities (`threatValues`, `threatState`, `groupThreat`…) and the normalized threat
  read that asks `C_Secrets` before each call; the `/atw debug` report; languages. [SPEC-02 §3](docs/specs/SPEC-02-data-model-storage.md#3-savedvariables):
  schema 1 of both SavedVariables (keys, types, defaults, enums, `settings.language` for Q5) and the load, migration
  and corruption rules (DAT-24, DAT-25). [SPEC-03 §4–§5](docs/specs/SPEC-03-threat-monitor-ui.md#4-finestra): one window
  with a compact layout (Monitor) and a wide one (Settings, Info, Reports), the module state, tabs, minimap button and
  Addon Compartment, commands and Settings cards. New [ui-style.md](docs/specs/ui-style.md): the differences from
  Accord, the compact combat density, the threat bar and state badge, the **Warden** theme drawn from the logo and the
  four state tokens SAFE / WARNING / DANGER / UNKNOWN, identical in every theme, with icon and word and their contrast
  ratios. New [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) on the Azeroth Unspoken model. ADR 0005 and ADR 0009
  updated: the language is chosen by the addon's own tables (AceLocale's choice is global), and only AceAddon,
  AceEvent, AceConsole, LibDataBroker and LibDBIcon are embedded.

### Added

- M0.2: probe skeleton (development only, never distributed). `tools/probe/AzTw_Probe/` (`## Interface: 16001`,
  `AzTw_ProbeDB`) with `/atwp list|run <id>|export|note <id> <text>|reset|help`, the check registry (P1–P12 answer
  "not implemented yet, step M0.x"), results `{id, verdict, details, build, context, time}`, the context stamp of
  SPEC-08, secret-safe calls, name scrubbing (`<player n>`, `<mob n>`, `<guild>`, `<realm>`) and an export frame with
  the text already selected. `tools/install_probe.py` copies it into the AddOns folder named in `tools/local.ini`.
  `tools/check_probe.py` checks its Lua 5.1 syntax, its TOC and that `.pkgmeta` leaves `tools/` out; it runs from
  `check_docs.py` and in CI.

- M0.3: probe checks P1–P4 (`tools/probe/AzTw_Probe/Checks_ThreatAPI.lua`, development only). P1 logs the six values
  of `GetBuildInfo`, `WOW_PROJECT_ID`, the locale, `C_Secrets.HasSecretRestrictions`,
  `C_CombatLog.IsCombatLogRestricted` and a census of the 49 APIs P2–P12 call. P2 recognises the case of the target
  (none, friendly, hostile not engaged, in combat, dead) and records count, kind and readable value of every return
  of the four threat functions, with the mob's token and with its GUID, reading by itself every 0.5 s in combat once
  run. P3 reads the player, the group and `targettarget` on the same mob with the `C_Secrets` predictions,
  `issecretvalue` and `canaccessvalue`, counts secret values and state per context, and tests once per context
  whether a secret value can be shown without being read (P3b). P4 is the guided tank and DPS trial: `/atwp note P4
  melee|ranged` arms it, it samples at 10 Hz and logs the 3 s before and 1 s after the aggro changes. Each check
  proposes a verdict from SPEC-08 §1. New commands `/atwp ctx <label>` and `/atwp watch on|off` (automatic readings in
  combat, also for later checks); `/atwp reset` also clears what P2–P4 counted. Nothing verified in game yet.

- M0.4: probe checks P5, P6 and P9 (`tools/probe/AzTw_Probe/Checks_Units.lua`, development only), all reading
  through `/atwp watch`. P5 reads, every second in combat (every third in a raid), the threat of the player, the pet and
  every member on every hostile mob a token reaches (`target`, `focus`, `mouseover`, `targettarget`, `pettarget`,
  `boss1–5`, the members' targets, `nameplate1–40`), deduplicated by GUID in memory, and counts each mob token kind ×
  unit kind as number / state / secret / nil / error; it tracks per fight the mobs nobody targets and those seen only on
  a nameplate, asks `UnitTokenFromGUID` for mobs no token reaches any more and `C_Secrets.CanCompareUnitTokens` for the
  target against the other tokens, and counts nameplate events. P6 counts `UNIT_THREAT_LIST_UPDATE` and
  `UNIT_THREAT_SITUATION_UPDATE` per payload kind and context (average and peak per second) and, with a 10 Hz sampling
  of the threat on the target, the delay from a change to the next event, changes without an event within 1 s and
  events without a change. P9 reads `UnitGUID` and `C_Secrets.ShouldUnitIdentityBeSecret` on every unit (GUID types and
  creature ids, never a player GUID), the `UnitTokenFromGUID` round trip, `UnitGroupRolesAssigned`,
  `C_Secrets.ShouldUnitComparisonBeSecret` with `UnitIsUnit`, and checks that a token keeps the same mob GUID until the
  token changes. Each proposes its verdict from SPEC-08 §1. P1's census now has 53 APIs. Nothing verified in game yet.

- M0.5: probe checks P7 and P8 (`tools/probe/AzTw_Probe/Checks_Events.lua`, development only). P7: at login the probe
  tries to register `COMBAT_LOG_EVENT_UNFILTERED`, `COMBAT_LOG_EVENT` and `COMBAT_LOG_EVENT_INTERNAL_UNFILTERED` on a
  frame of its own (inside `pcall`), records whether the client accepted them and any `ADDON_ACTION_BLOCKED` or
  `ADDON_ACTION_FORBIDDEN` (function and whether the probe was blamed), counts every delivery with the number and kind
  of its arguments, never their content, and calls the readers it finds at run time (`CombatLogGetCurrentEventInfo`,
  `C_CombatLogInternal.GetCurrentEventInfo`, `C_CombatLogSecure.GetCurrentEventInfo`) only on the first deliveries and
  once per fight, recording the kinds of what came back; it reads `C_CombatLog.IsCombatLogRestricted()`. With
  `/atwp watch on` it counts `PLAYER_REGEN_*` against `UnitAffectingCombat` (with the delay), `UNIT_TARGET` per payload
  kind and what the mob targets, `PLAYER_TARGET_CHANGED`, encounters (id, difficulty, size, result; never the name),
  deaths of members and mobs with the source that saw them (`UNIT_HEALTH`, `UNIT_FLAGS`, `UNIT_DIED`, `PARTY_KILL`,
  `PLAYER_DEAD`, a poll every second; `UnitIsDead`, `UnitIsDeadOrGhost`, health 0) and the kinds of `UnitHealth` and
  `UnitHealthMax`, and the spells cast by the group (`UNIT_SPELLCAST_SUCCEEDED`, spell id or `secret`) with whether the
  mob the caster targets turned to the caster within 0.5 s; `/atwp note P7 taunt` logs the group's casts of the last
  10 s. P8: after every fight (2 s after its end) and at `/atwp run P8`, `C_DamageMeter.IsDamageMeterAvailable`, the
  values of `Enum.DamageMeterSessionType` and `Enum.DamageMeterType` found at run time (a threat type would be flagged),
  `GetAvailableCombatSessions` and `GetSessionDurationSeconds` against the measured length of the fight,
  `GetCombatSessionFromType` for every pair of values with, of each source, only the kind of every field, the deaths
  and the local player flag (never `name` or `sourceGUID`), and the three damage meter events with their delay after
  `PLAYER_REGEN_*`. Each proposes its verdict from SPEC-08 §1. Nothing verified in game yet.

- M0.6: probe checks P10–P12 (`tools/probe/AzTw_Probe/Checks_Cost.lua`, development only). P10: `/atwp perf [hz]
  [units] [mobs]` times, with `debugprofilestop` and a `C_Timer` ticker, a tick that reads the threat, the state and
  the secrecy predictions of N units on M mobs, at 2, 5 and 10 Hz with 5, 10 and 40 units, 30 s each; it records
  median, 95th percentile and maximum per tick, milliseconds per second, kilobytes of compact samples per minute
  (retained and gross, `GetAddOnMemoryUsage` and `collectgarbage`), FPS before and during, and whether the units were
  real (a raid fight) or simulated; it runs only when asked, stops by itself (or with `/atwp perf stop`) and proposes
  the default sampling rate of Q14. P11: always on, per context, `ADDON_ACTION_BLOCKED` and `ADDON_ACTION_FORBIDDEN`,
  restriction states, the combat lockdown and the probe's failed calls; `/atwp run P11` adds a burst of 1000 threat
  readings in one frame (not during an encounter), a register and unregister round of the threat events and a 10-tick
  ticker. P12: `/atwp run P12` arms a buffer of one compact sample a second in combat in the saved variables, with a
  final stamp at `PLAYER_LOGOUT`; the next load compares it and reads the combat state and the threat again
  (`/atwp note P12 lost` records a reload that saved nothing). Each proposes its verdict from SPEC-08 §1. P1's census
  now has 57 APIs. Nothing verified in game yet.

- The owner's logo (`assets/logo-source.webp`) and the NEBULA logos for the credits (`assets/`).
- Repository tooling adapted from Azeroth Accord: `tools/check_docs.py` (links, wiki twins, ADR index, privacy scan, LF
  endings), `tools/check_pr_docs.py`, `tools/ship_step.py`, `tools/release_notes.py`, `tools/sync_wiki.py`; the
  workflows CI, Docs rule, Long tests, DCO, Release and Wiki sync; issue and pull request templates; `.pkgmeta`,
  `.luarc.json`, `.gitattributes`, `.gitignore`.
