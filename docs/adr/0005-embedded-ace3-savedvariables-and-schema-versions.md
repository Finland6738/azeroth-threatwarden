# 0005. Embedded Ace3, SavedVariables and schema versions

- Status: Accepted
- Date: 2026-11-25 (same as Azeroth Accord, ADR 0011 there)

## Context

The addon needs events, timers, a slash command, localization, configuration and saved recordings whose shape will
change over the milestones.

## Decision

1. Ace3 (AceAddon, AceEvent, AceTimer, AceConsole, AceLocale, AceDB, AceConfig), LibDataBroker and LibDBIcon are
   **embedded**, pinned by tag in `.pkgmeta` and never committed: `tools/fetch_libs.py` downloads them for development
   and CI. AceComm is not embedded ([ADR 0001](0001-local-only-addon-no-network.md)).
2. `AzerothThreatwardenDB` (account-wide: settings, profiles, recordings) and `AzerothThreatwardenCharDB` (per
   character: window position and state).
3. Every saved table has a `schema` number; one migration function per version runs at `ADDON_LOADED`; unknown future
   versions are kept untouched and the addon runs read-only on them; a damaged table is set aside (kept under a
   `corrupt` key) instead of blocking the addon.
4. Recordings have limits the player can change (number of sessions, size): the oldest are removed first.

## Consequences

- Positive: proven libraries, safe upgrades, recordings that cannot grow without end.
- Negative: a few hundred KB of libraries in the package.

## Update (2026-11-25, M1.1)

The architecture specification ([SPEC-01 §4](../specs/SPEC-01-platform-architecture.md#4-librerie)) narrows point 1 to
what the addon uses, as Azeroth Accord does: **LibStub, CallbackHandler, AceAddon, AceEvent, AceConsole, LibDataBroker
and LibDBIcon** are embedded. Not embedded: **AceDB** (`Core/Config.lua` manages the two variables directly, because
the schema, read-only and `corrupt` rules of point 3 need the raw tables), **AceTimer** (the client's timers go through
Compat and the Scheduler), **AceConfig** (Settings is a page in the ecosystem style, [ADR 0015](0015-interface-follows-the-ecosystem-style.md))
and **AceLocale** (its language choice is global, see the update of [ADR 0009](0009-interface-and-documentation-languages.md)).
Points 2–4 are unchanged; the keys, defaults and rules of schema 1 are in
[SPEC-02 §3](../specs/SPEC-02-data-model-storage.md#3-savedvariables).
