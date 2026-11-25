# 0015. The interface follows the ecosystem style of FDCP and Accord, with a Warden theme from the logo

- Status: Accepted
- Date: 2026-11-25 (the owner's request; Azeroth Accord ADR 0021)

## Context

The owner's addons read as one family: Finland Dragon Credit Points (FDCP) and Azeroth Accord share dark "nebula"
surfaces, tabs with an indicator, rounded 9-slice shapes, the Outfit, JetBrains Mono and Orbitron fonts, and a themed
title bar. A threat meter is also a combat overlay: it must stay readable at small sizes, during movement and with
colour-blindness.

## Decision

1. **Threatwarden follows the ecosystem style.** Accord's `docs/specs/ui-style.md` (itself based on FDCP's) is the base;
   Threatwarden's `docs/specs/ui-style.md` (written in M1.1) records only the differences: names and prefixes
   (`AzerothThreatwarden`, `AzerothThreatwardenFont<Id>`), the compact combat window, the threat bars and the state
   colours.
2. **Copy and adapt, no shared library** ([ADR 0012](0012-reuse-accord-and-unspoken-foundations.md)): Theme, Assets,
   Motion, the widget kit, the window and the media and font tools are copied from Accord and renamed.
3. **Three themes** with the ecosystem's token names: **Nebula** (default, dark) and **Aurora** (light) with the
   ecosystem's values, and **Warden** (dark), made from the logo's palette: deep teal-green background, aged bronze
   frames and gold text, mint-green glow.
4. **State colours** are their own tokens and the same in every theme: green SAFE, amber WARNING, red DANGER, grey-blue
   UNKNOWN and neutral data ([specification](../specs/source-specification.md) §15). A state is never shown by colour
   alone: every state also has an icon and a word, and a colour-blind palette is offered (M8).
5. **Rules that do not change:** no Blizzard art in the repository, every string a locale key, no colour written outside
   `UI/Theme.lua`, credits "Created and designed by Finland. Made with the Italian guild NEBULA." with the NEBULA logos
   (used with the guild's permission), fonts under SIL OFL 1.1 with their licence texts, every media file listed in
   `docs/third-party.md`.

## Consequences

- Positive: one visual family with the owner's other addons from the first release; a tested theme and widget system.
- Negative: duplicated code to keep in step by hand; more media in the package; nothing is verified in the real client
  until the owner's checks.
