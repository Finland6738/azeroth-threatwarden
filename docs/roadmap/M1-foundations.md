# M1 — Foundations

**Goal:** an addon that loads cleanly on Forever, in English and Italian, with the ecosystem look, a movable window,
settings, credits and a diagnostic report, on tested foundations copied from Azeroth Accord
([ADR 0012](../adr/0012-reuse-accord-and-unspoken-foundations.md)). No threat is read yet.

**Exit criterion:** the addon loads with no Lua error; the window opens, moves, locks, scales and remembers its place
after `/reload`; Settings and Info work in both languages; `/atw debug` lists what Compat found; the offline tests run
in CI. Released as `v0.1.0`.

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
  - [ ] Every module of M1 has its responsibility, events and tests named.
  - [ ] `ui-style.md` lists every token of the Warden theme and the four state tokens with their contrast.
  - [ ] `check_docs.py` passes.
- Real client: nothing.

### M1.2 — Skeleton, TOC, libraries and addon tools
- Branch: `step/m1-2-skeleton`
- Depends on: M1.1
- Spec: SPEC-01 §3–§4
- Scope: `AzerothThreatwarden/AzerothThreatwarden.toc` (Interface 16001, `## Version: @project-version@`, Title, Notes
  and `Notes-itIT`, SavedVariables, Compartment functions, `IconTexture`, `X-License`, CurseForge line commented),
  `embeds.xml`, `Core/Init.lua`, `Core/Features.lua`, `Locales/enUS.lua` and `itIT.lua` (first keys); copied and
  adapted from Accord: `tools/fetch_libs.py`, `install_addon.py`, `check_addon.py`, `check_package.py`;
  `docs/RELEASING.md`, `docs/third-party.md`.
- Done when:
  - [ ] `check_addon.py` and `check_package.py` pass and run inside `check_docs.py`.
  - [ ] `fetch_libs.py` downloads the pinned libraries; nothing of `Libs/` is committed.
- Tests: the tools' own cases.
- Real client: the addon appears in the AddOns list.

### M1.3 — Offline test harness and mock client
- Branch: `step/m1-3-test-harness`
- Depends on: M1.2
- Spec: SPEC-08 §2–§3, [ADR 0010](../adr/0010-offline-tests-with-lupa-and-a-mock-client.md)
- Scope: `Tests/run_tests.py` (lupa 2.8, TOC order, `--long`, name filter, `-v`), `Tests/lib/` (assert, harness),
  `Tests/mock/` (core, clock and timers, frames and events, units and groups, combat state, **threat API with scripted
  answers, secret values and nil**, each file citing the dump), `/reload` simulation, `Tests/test_locales.lua`,
  `Tests/test_features.lua`; CI and Long tests run them.
- Done when:
  - [ ] The addon boots in the mock and survives a simulated `/reload`.
  - [ ] The locale test enforces ADR 0009 rule 3.
- Tests: the harness's own tests.
- Real client: nothing.

### M1.4 — Compat (API adapter) and Diagnostics
- Branch: `step/m1-4-compat-diagnostics`
- Depends on: M1.3
- Spec: SPEC-01 §1–§2 (ARC-01, ARC-02), [ADR 0003](../adr/0003-data-reliability-categories.md)
- Scope: `Core/Compat.lua` (capability table checked against the dump, `available/missing/restricted/error`, `pcall`
  guards, secret-value detection that never reads a secret value, normalized returns), `Core/Bus.lua`,
  `Core/Scheduler.lua` (bounded ticks, only while needed), `Core/Diagnostics.lua` (error ring, report text without
  names), `UI/DiagnosticsBox.lua` (copy box); a test that no `UI/` file calls a game API directly.
- Done when:
  - [ ] Every API of SPEC-01 §2 is in the capability table; a missing or secret one is reported, never raised.
  - [ ] `/atw debug` produces the report (header, client, locale, features, APIs, saved data, memory, errors).
- Tests: `test_compat.lua`, `test_diagnostics.lua`, `test_bus.lua`, `test_scheduler.lua`.
- Real client: the capability states and the report text.

### M1.5 — Config, schema and migrations, language setting
- Branch: `step/m1-5-config`
- Depends on: M1.4
- Spec: SPEC-02 §3 (DAT-20–DAT-23), SPEC-09 Q5, [ADR 0005](../adr/0005-embedded-ace3-savedvariables-and-schema-versions.md)
- Scope: `Core/Config.lua` (schema 1 for account and character, typed rules with enums and ranges, defaults, migration
  framework, read-only on a newer schema, damaged tables kept under `corrupt`, `CONFIG_CHANGED` on the Bus),
  `settings.language` (`auto`, `enUS`, `itIT`) applied through AceLocale at load.
- Done when:
  - [ ] A wrong value falls back to its default; a newer schema is left untouched and read-only.
  - [ ] The language setting picks the locale after `/reload`; `auto` follows the client.
- Tests: `test_config.lua` (migrations, read-only, corruption, reload), `test_language.lua`.
- Real client: settings survive logout and `/reload`.

### M1.6 — Media, fonts, theme and widget kit
- Branch: `step/m1-6-look`
- Depends on: M1.5
- Spec: `ui-style.md`, [ADR 0015](../adr/0015-interface-follows-the-ecosystem-style.md)
- Scope: copied and adapted from Accord: `tools/make_media.py` (logo textures `logo_256`/`logo_64` from
  `assets/logo-source.webp`, NEBULA logos, shapes, icons including state icons), `tools/make_fonts.py`,
  `UI/Assets.lua`, `UI/Theme.lua` (Nebula, Aurora, Warden; state tokens), `UI/Motion.lua`, `UI/Widgets/`;
  `docs/third-party.md` updated.
- Done when:
  - [ ] Every media file is in `Assets.lua` and `third-party.md`; fonts have their OFL texts.
  - [ ] No colour outside `UI/Theme.lua` (`check_addon.py`).
- Tests: `test_theme.lua`, `test_widgets.lua`.
- Real client: fonts and textures render.

### M1.7 — Main window, commands, minimap and Compartment
- Branch: `step/m1-7-window`
- Depends on: M1.6
- Spec: SPEC-03 §4–§5
- Scope: `UI/Window.lua` (title bar with the logo and the module state, tabs *Monitor*, *Settings*, move, lock,
  resize, scale, position per character, Esc closes), an empty Monitor tab saying "Threat monitoring arrives in
  v0.2.0", `/threatwarden` and `/atw` (`show`, `hide`, `lock`, `unlock`, `reset`, `debug`, `about`, `help`), LibDBIcon
  button (hideable) and Addon Compartment.
- Done when:
  - [ ] The window keeps position, size, scale and lock after `/reload`.
  - [ ] Every command answers in both languages.
- Tests: `test_window.lua`, `test_commands.lua`.
- Real client: moving, resizing and scaling; the window in combat.

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
  - [ ] Every setting applies at once (except the font, which needs a restart, and the manual says so).
  - [ ] The previews are generated, linked and checked by `check_docs.py`.
- Tests: `test_settings.lua`, `test_about.lua`, `test_ui_texts.lua` (nothing on screen without a locale key).
- Real client: settings and credits in both languages.

### M1.9 — In-game checklist M1
- Branch: `step/m1-9-checklist`
- Depends on: M1.8
- Scope: `docs/checklists/M1.md` (load, window, commands, settings, language, `/atw debug`, UI scales and custom UIs);
  README status.
- Done when:
  - [ ] The checklist exists and links the *In-game test report* form.
- Real client: the checklist itself, run by the owner.

### M1.R — Release preparation `v0.1.0`
- Branch: `chore/release-v0.1.0`
- Depends on: M1.9
- Scope: switches of later milestones off; `release_notes.py --promote 0.1.0`; README and wiki status; a dry run of
  the Release workflow; then the annotated tag `v0.1.0`, its push, and a check of the GitHub Release and of the zip.
- Done when:
  - [ ] The dry run is green and the zip contains only the addon, its libraries, fonts and `LICENSE`.
  - [ ] The GitHub Release `v0.1.0` exists with the changelog section as its notes.
