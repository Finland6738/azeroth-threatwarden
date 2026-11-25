# M1 — Foundations

**Goal:** an addon that loads cleanly on Forever, in English and Italian, with the ecosystem look, a movable window,
settings, credits and a diagnostic report, on tested foundations copied from Azeroth Accord
([ADR 0012](../adr/0012-reuse-accord-and-unspoken-foundations.md)). No threat is read yet.

**Exit criterion:** the addon loads with no Lua error; the window opens, moves, locks, scales and remembers its place
after `/reload`; Settings and Info work in both languages; `/atw debug` lists what Compat found; the offline tests run
in CI. Released as `v0.1.0`.

*State (2026-11-25): M1 is complete in code (steps M1.1–M1.9, offline tests in CI) and released as `v0.1.0` (M1.R).
The part of the criterion that needs the game is **open** until the owner runs
[the M1 checklist](../checklists/M1.md).*

| Step | Model | Effort |
|---|---|---|
| M1.1 Specification: architecture, data, window, ui-style | Opus | high |
| M1.2 Skeleton, TOC, libraries and addon tools | Sonnet | medium |
| M1.3 Offline test harness and mock client | Sonnet | high |
| M1.4 Compat (API adapter) and Diagnostics | Opus | high |
| M1.5 Config, schema and migrations, language setting | Opus | high |
| M1.6 Media, fonts, theme and widget kit | Sonnet | medium |
| M1.7 Main window, commands, minimap and Compartment | Sonnet | medium |
| M1.8 Settings, Info and credits, first design previews | Sonnet | medium |
| M1.9 In-game checklist M1 | Sonnet | low |
| M1.R Release preparation `v0.1.0` | Sonnet | medium |

### M1.1 — Specification: architecture, data, window, ui-style
- Branch: `step/m1-1-spec`
- Depends on: — (may run before M0 ends; it marks what waits for the probe)
- Spec: SPEC-01, SPEC-02 §1–§3, SPEC-03 §4–§5
- Scope: complete SPEC-01 (module list, Bus events, Compat capability table drawn from the dump), SPEC-02 §3 (keys,
  types, defaults, schema 1, migration rules), SPEC-03 §4–§5 (window layout, commands); new `docs/specs/ui-style.md`
  (differences from Accord's: names, compact combat window, threat bars, state tokens, the **Warden** theme drawn from
  the logo's palette with contrast ratios); `docs/ARCHITECTURE.md` (English, the Unspoken model: overview, modules, flow
  of a threat update, data, extension points, what is planned).
- Done when:
  - [x] Every module of M1 has its responsibility, events and tests named.
  - [x] `ui-style.md` lists every token of the Warden theme and the four state tokens with their contrast.
  - [x] `check_docs.py` passes.
- Real client: nothing.
- *Done (2026-11-25, before the probe results): SPEC-01 (M1 modules with responsibility, Bus events and tests; Bus
  event table; feature switches; Compat API table from the dump, capabilities and the normalized threat read; `/atw
  debug`; languages), SPEC-02 §3 (schema 1 keys, types, defaults, enums; load, migration and corruption rules), SPEC-03
  §4–§5 (compact and wide layouts, module state, tabs, minimap and Compartment, commands, Settings cards),
  `docs/specs/ui-style.md` (Warden theme and the four state tokens with contrast), `docs/ARCHITECTURE.md`; ADR 0005 and
  0009 updated (own language tables instead of AceLocale). What waits for the probe is marked **[probe Pn]**.*

### M1.2 — Skeleton, TOC, libraries and addon tools
- Branch: `step/m1-2-skeleton`
- Depends on: M1.1
- Spec: SPEC-01 §3–§4
- Scope: `AzerothThreatwarden/AzerothThreatwarden.toc` (Interface 16001, `## Version: @project-version@`, Title, Notes
  and `Notes-itIT`, SavedVariables, Compartment functions, `IconTexture`, `X-License`, CurseForge line commented),
  `embeds.xml` (SPEC-01 §4), `Core/Init.lua`, `Core/Features.lua`, `Core/Locale.lua`, `Locales/enUS.lua` and `itIT.lua`
  (first keys); copied and
  adapted from Accord: `tools/fetch_libs.py`, `install_addon.py`, `check_addon.py`, `check_package.py`;
  `docs/RELEASING.md`, `docs/third-party.md`.
- Done when:
  - [x] `check_addon.py` and `check_package.py` pass and run inside `check_docs.py`.
  - [x] `fetch_libs.py` downloads the pinned libraries; nothing of `Libs/` is committed.
- Tests: the tools' own cases.
- Real client: the addon appears in the AddOns list.
- *Done (2026-11-25): TOC, `embeds.xml`, `Core/Locale.lua`, `Locales/`, `Core/Init.lua`, `Core/Features.lua` (every
  switch off), the four tools with their self-tests, `docs/RELEASING.md`, `docs/third-party.md`. The Compartment
  functions live in `Core/Init.lua` until `UI/Launcher.lua` (M1.7). **Left for later:** `## IconTexture` (M1.6, with
  `Media/logo_64`; `check_addon.py` requires it as soon as the texture exists), the media list of `check_package.py`
  (`REQUIRED_MEDIA`, M1.6), moving the game calls of `Init` and `Locale` behind Compat (M1.4). Not run in the game.*

### M1.3 — Offline test harness and mock client
- Branch: `step/m1-3-test-harness`
- Depends on: M1.2
- Spec: SPEC-08 §2–§3, [ADR 0010](../adr/0010-offline-tests-with-lupa-and-a-mock-client.md)
- Scope: `Tests/run_tests.py` (lupa 2.8, TOC order, `--long`, name filter, `-v`), `Tests/lib/` (assert, harness),
  `Tests/mock/` (core, clock and timers, frames and events, units and groups, combat state, **threat API with scripted
  answers, secret values and nil**, each file citing the dump), `/reload` simulation, `Tests/test_locales.lua`,
  `Tests/test_features.lua`, `Tests/test_init.lua`; CI and Long tests run them.
- Done when:
  - [x] The addon boots in the mock and survives a simulated `/reload`.
  - [x] The locale test enforces ADR 0009 rule 3.
- Tests: the harness's own tests.
- Real client: nothing.
- *Done (2026-11-25): `Tests/run_tests.py`, `lib/` (assert, harness, fight scripts), `mock/` (core, secret values,
  clock, frames and events, timers, client, units and groups, combat and instances, threat API), `test_init`,
  `test_features`, `test_locales`, `test_mock`, `test_mock_game`, `test_fight`, `long/test_raid`; CI and *Long tests*
  always run them. The threat numbers of the mock, `type()` of a secret and the restriction enum values are assumptions
  until the probe (marked in the mock files). **Left for later:** the "a command of a part switched off does not act"
  case (`test_commands.lua`, M1.7); the mock of each further API arrives with the step that calls it.*

### M1.4 — Compat (API adapter) and Diagnostics
- Branch: `step/m1-4-compat-diagnostics`
- Depends on: M1.3
- Spec: SPEC-01 §1–§2 (ARC-01, ARC-02), [ADR 0003](../adr/0003-data-reliability-categories.md)
- Scope: `Core/Compat.lua` (capability table checked against the dump, `available/missing/restricted/error`, `pcall`
  guards, secret-value detection that never reads a secret value, normalized returns), `Core/Bus.lua`,
  `Core/Scheduler.lua` (bounded ticks, only while needed), `Core/Diagnostics.lua` (error ring, report text without
  names), `UI/DiagnosticsBox.lua` (copy box); a test that no `UI/` file calls a game API directly.
- Done when:
  - [x] Every API of SPEC-01 §2 is in the capability table; a missing or secret one is reported, never raised.
  - [x] `/atw debug` produces the report (header, client, locale, features, APIs, saved data, memory, errors).
- Tests: `test_compat.lua`, `test_api_boundary.lua`, `test_diagnostics.lua`, `test_bus.lua`, `test_scheduler.lua`.
- Real client: the capability states and the report text.
- *Done (2026-11-25): `Core/Compat.lua` (58 APIs of SPEC-01 §8.2, all checked against the dump, with the states
  available/missing/restricted/error; capabilities of §8.4, unknown until a reading proves them; client restrictions
  from `Enum.AddOnRestrictionType` and `ADDON_RESTRICTION_STATE_CHANGED`; `IsSecret` that never reads a secret;
  `Compat.Threat.Read` of §8.3, allocation-free), `Core/Bus.lua`, `Core/Scheduler.lua` (named ticks, 1–10 Hz, stop at
  `COMBAT_ENDED`, cost per tick; none runs in M1), `Core/Diagnostics.lua` (error ring, the report of §9 in English,
  without names), `UI/DiagnosticsBox.lua` (the client's own dialog look until M1.6), `/atw debug` through AceConsole
  (the other commands are M1.7). Compat and Bus now load before `Locale`; `Init` and `Locale` call the game only through
  Compat. Two APIs added to the table: `client.RealmName`, `addon.ErrorHandler`. 201 quick tests, 202 with `--long`.
  Not run in the game: the capability states, the restriction names and values [probe P11], the report text and the
  copy box.*

### M1.5 — Config, schema and migrations, language setting
- Branch: `step/m1-5-config`
- Depends on: M1.4
- Spec: SPEC-02 §3 (DAT-20–DAT-23), SPEC-09 Q5, [ADR 0005](../adr/0005-embedded-ace3-savedvariables-and-schema-versions.md)
- Scope: `Core/Config.lua` (schema 1 for account and character, typed rules with enums and ranges, defaults, migration
  framework, read-only on a newer schema, damaged tables kept under `corrupt`, `CONFIG_CHANGED` on the Bus),
  `settings.language` (`auto`, `enUS`, `itIT`) applied by `Core/Locale.lua` at load (SPEC-01 §10, ADR 0009 update).
- Done when:
  - [x] A wrong value falls back to its default; a newer schema is left untouched and read-only.
  - [x] The language setting picks the locale after `/reload`; `auto` follows the client.
- Tests: `test_config.lua` (migrations, read-only, corruption, reload), `test_language.lua`.
- Real client: settings survive logout and `/reload`.
- *Done (2026-11-25): `Core/Config.lua` (schema 1 of SPEC-02 §3.2–§3.3, rules, defaults, migrations on a copy with a
  failing or missing step leading to read-only, read-only on a newer schema, `corrupt` with at most 5 bounded entries,
  sizes clamped and scale rounded, `Set` with `CONFIG_CHANGED`, `ResetSettings`/`ResetWindow` for M1.7–M1.8, the
  *Saved data* lines of `/atw debug`, `Config.DEV` for the packager); `account.settings.language` applied by
  `Locale.Apply` at `ADDON_LOADED`; `Compat.ServerTime` (`time.ServerTime` now since M1) dates the `corrupt` entries.
  SPEC-02 §3.4 completed (position checked for shape only, the window keeps it on screen in M1.7). 251 quick tests, 252
  with `--long`. Not run in the game: settings surviving a real logout and `/reload`, the language after `/reload`.*

### M1.6 — Media, fonts, theme and widget kit
- Branch: `step/m1-6-look`
- Depends on: M1.5
- Spec: `ui-style.md`, [ADR 0015](../adr/0015-interface-follows-the-ecosystem-style.md)
- Scope: copied and adapted from Accord: `tools/make_media.py` (logo textures `logo_256`/`logo_64` from
  `assets/logo-source.webp`, NEBULA logos, shapes, icons including state icons), `tools/make_fonts.py`,
  `UI/Assets.lua`, `UI/Theme.lua` (Nebula, Aurora, Warden; state tokens), `UI/Motion.lua`, `UI/Widgets/`;
  `docs/third-party.md` updated; `## IconTexture` in the TOC (left out by M1.2); `REQUIRED_MEDIA` of
  `tools/check_package.py`.
- Done when:
  - [x] Every media file is in `Assets.lua` and `third-party.md`; fonts have their OFL texts.
  - [x] No colour outside `UI/Theme.lua` (`check_addon.py`).
- Tests: `test_theme.lua`, `test_widgets.lua`, `test_assets.lua`.
- Real client: fonts and textures render.
- *Done (2026-11-25): `tools/make_media.py` (20 textures, among them `rr_*_4` and `dash` for the threat bar, the icon
  sheet with the new icons, `logo_256`, `logo_64`, NEBULA logos), `tools/make_fonts.py` (copied from FDCP), `UI/Assets.lua`,
  `UI/Theme.lua` (three themes, `Theme.STATE`, compact fonts, the *Look* section of `/atw debug`), `UI/Motion.lua` (with
  `Motion.Tween`), `UI/Widgets/` (Core, Controls, ThinBar, Tooltip, Threat), `DiagnosticsBox` in the new look, `## IconTexture`,
  `REQUIRED_MEDIA`, `ui.CreateColor` in the Compat table. 337 tests with `--long`. Not run in the game: TGA and fonts,
  9-slice, glows, the three themes on screen, the dashed outline, the icons at 10 pt, the logo as an icon.*

### M1.7 — Main window, commands, minimap and Compartment
- Branch: `step/m1-7-window`
- Depends on: M1.6
- Spec: SPEC-03 §4–§5
- Scope: `UI/Window.lua` (title bar with the logo and the module state, tabs *Monitor*, *Settings*, move, lock,
  resize, scale, position per character, Esc closes; compact and wide layouts of SPEC-03 §4.2), an empty Monitor tab
  saying "Threat monitoring arrives in v0.2.0", `Core/Commands.lua` with `/threatwarden` and `/atw` (no argument
  toggles; `show`, `hide`, `lock`, `unlock`, `reset`, `settings`, `debug`, `about`, `help`), `UI/Launcher.lua` with the
  LibDBIcon button (hideable) and the Addon Compartment.
- Done when:
  - [x] The window keeps position, size, scale and lock after `/reload`.
  - [x] Every command answers in both languages.
- Tests: `test_window.lua`, `test_commands.lua`, `test_launcher.lua`.
- Real client: moving, resizing and scaling; the window in combat.
- *Done (2026-11-25): `UI/Window.lua` (compact and wide layouts, module state, tabs with Reports behind its switch, move,
  lock, resize, scale, `char.ui`, Esc, screen edges), `Core/Commands.lua`, `UI/Launcher.lua` (LibDBIcon button,
  Compartment functions moved there from `Init`), the Bus event `DISPLAY_CHANGED`, wiki *Commands*. The Settings tab and
  the Info page are one line of text until M1.8, which also gives the controls for scale and the minimap button. The wide
  title bar is 52 pt (the kit of M1.6; SPEC-03 said 44). Both boxes are checked offline only: 404 tests with `--long`.
  Not run in the game: moving, resizing and scaling, the window after a real `/reload`, in combat and on another screen
  size, Esc, the minimap button, the Addon Compartment, the title fit with the real fonts.*

### M1.8 — Settings, Info and credits, first design previews
- Branch: `step/m1-8-settings-about`
- Depends on: M1.7
- Spec: SPEC-03 §5, [ADR 0013](../adr/0013-design-previews-original-art-invented-data.md)
- Scope: `UI/Settings.lua` (Appearance: theme, effects, animations, font; Language; Window; reset), the game's settings
  panel entry, `UI/About.lua` (logo, version, credits *Created and designed by Finland. Made with the Italian guild
  NEBULA.*, NEBULA logos by theme, links); `tools/make_mockups.py` and `mockup_lib.py` adapted; first previews (window,
  settings, about, in English and Italian, in Nebula, Aurora and Warden); wiki pages Installation, Interface Tour,
  Commands, Settings, About (both languages); README images.
- Done when:
  - [x] Every setting applies at once (except the font, which needs a restart, and the manual says so).
  - [x] The previews are generated, linked and checked by `check_docs.py`.
- Tests: `test_settings.lua`, `test_about.lua`, `test_ui_texts.lua` (nothing on screen without a locale key).
- Real client: settings and credits in both languages.
- *Done (2026-11-25): `UI/Settings.lua` (page selector, Appearance, Language with *Reload now*, Window, Reset asking
  twice, the read-only warning, the panel in the game's settings window through `Compat.RegisterSettingsPanel`),
  `UI/About.lua` (logo, version, credits, NEBULA logo by theme, repository and Ko-fi), `Compat.Reload`,
  `Locale.Resolve`; the language also needs a `/reload`; `tools/make_mockups.py`, `mockup_lib.py`, `mockup_scenes.py`
  and 18 previews (window, settings, about; three themes; English and Italian) in `docs/specs/mockups/`; wiki
  *Installation*, *Interface Tour*, *Settings*, *About* in both languages, README images. Accord's annotated spec pages
  were not adapted. Checked offline only. Not run in the game: the Settings tab and the panel in the game's own window,
  the slider and the copy boxes, *Reload now*, the text wrapping with the real fonts, the logos.*

### M1.9 — In-game checklist M1
- Branch: `step/m1-9-checklist`
- Depends on: M1.8
- Scope: `docs/checklists/M1.md` (load, window, commands, settings, language, `/atw debug`, UI scales and custom UIs);
  README status.
- Done when:
  - [x] The checklist exists and links the *In-game test report* form.
- Real client: the checklist itself, run by the owner.
- *Done (2026-11-25): `docs/checklists/M1.md` (setup, loading, commands, window, minimap and Compartment, Settings,
  Info, saved data, combat, `/atw debug`, UI scales and custom UIs, result table), checklist index, README status in
  both languages. Documentation only; **the checklist has not been run in the game**.*

### M1.R — Release preparation `v0.1.0`
- Branch: `chore/release-v0.1.0`
- Depends on: M1.9
- Scope: switches of later milestones off; `release_notes.py --promote 0.1.0`; README and wiki status; a dry run of
  the Release workflow; then the annotated tag `v0.1.0`, its push, and a check of the GitHub Release and of the zip.
- Done when:
  - [x] The dry run is green and the zip contains only the addon, its libraries, fonts and `LICENSE`.
  - [x] The GitHub Release `v0.1.0` exists with the changelog section as its notes.
- *Done (2026-11-25): changelog promoted and status updated (commit `d8d2fb5`, every feature switch off, 448 quick
  tests); the dry run of the Release workflow was green; annotated tag `v0.1.0` on that commit,
  [GitHub Release](https://github.com/Finland6738/azeroth-threatwarden/releases/tag/v0.1.0) with the changelog section
  as notes and `AzerothThreatwarden-v0.1.0-forever.zip` (131 files in `AzerothThreatwarden/`: addon, libraries, media,
  fonts with their OFL texts, `LICENSE` and the `CHANGELOG.md` the packager writes; `## Version: v0.1.0`).
  CurseForge skipped (no `CF_API_KEY`). The zip has not been installed or run in the game.*
