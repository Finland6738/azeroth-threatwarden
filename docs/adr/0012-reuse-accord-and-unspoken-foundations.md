# 0012. Reuse the foundations of Azeroth Accord and Azeroth Unspoken

- Status: Accepted
- Date: 2026-11-25

## Context

Azeroth Accord and Azeroth Unspoken, by the same owner and under GPL-3.0, already have working, tested foundations for
WoW Forever: the Compat layer, Config with schema versions, the event Bus, Diagnostics, the theme and widget kit of the
ecosystem (from Finland Dragon Credit Points), the lupa test harness and mock client, and the repository tooling (docs
checks, ship script, wiki sync, packaging, media, fonts and design previews).

## Decision

1. Threatwarden starts from **copies** of those files, renamed to its own namespace and adapted. From **Accord**: the
   process (CLAUDE.md, ADRs, roadmap and steps), `tools/` (checks, ship, release notes, wiki sync, packaging, media,
   fonts, mockups), the workflows and templates, `Core/` (Compat, Config, Bus, Diagnostics, Features), the UI kit
   (Theme, Assets, Motion, Widgets, Window) and `Tests/`. From **Unspoken**: the architecture document
   (`docs/ARCHITECTURE.md`), the interface review method (`docs/design/`) and the asset pipeline for README and wiki
   images.
2. The copies are independent: no shared library and no runtime dependency between the addons, so they can be
   installed together and evolve separately. Threatwarden reads nothing from the other addons
   ([SPEC-09 Q4](../specs/SPEC-09-risks-open-questions.md)).
3. Each copied file says in its header where it comes from; a fix found in one project is ported to the other by hand
   when it applies.

## Alternatives considered

- **A shared library addon.** One more thing to install and version for players.
- **Writing everything again.** Slower and loses tested behaviour.

## Consequences

- Positive: M1 is mostly adaptation; the test harness and the look exist from the first milestone.
- Negative: several copies of similar code to keep in mind.
