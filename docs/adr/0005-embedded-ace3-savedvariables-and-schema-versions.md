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
