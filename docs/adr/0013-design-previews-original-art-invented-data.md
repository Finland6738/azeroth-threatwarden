# 0013. Design previews: original art, invented data, drawn from the addon's texts

- Status: Accepted
- Date: 2026-11-25 (the approach of Azeroth Accord, ADR 0019 there)

## Context

The wiki and the READMEs should show what the interface looks like before the addon has run in the client, and later
show states that are hard to capture (a near-aggro warning, an unknown state, a replay).

## Decision

1. The images are **design previews, not screenshots**, and say so in a strip at the bottom of every image. They are
   drawn from the addon's own layout and **texts** (`Locales/enUS.lua`, `itIT.lua`) by `tools/make_mockups.py` (from
   M1), so they cannot disagree with the interface, and regenerated when the interface changes.
2. **Original art only**: shapes are CSS and inline SVG; the pictures are the addon's logo (`assets/logo-source.webp`)
   and the NEBULA logos for the credits; the fonts are the ones the addon ships. No game screenshot, icon, texture or
   font is copied or loaded from a network.
3. **Invented data**: characters, guilds, mobs and numbers are made up; no real player appears.
4. WebP, quality 80, under `docs/specs/mockups/`, linked with relative paths from the wiki and the READMEs; the Italian
   previews come from the Italian locale.
5. When the owner's in-game checks produce real screenshots, they may replace the previews of a view.

## Consequences

- Positive: a manual with pictures before the first run in the game; no licensing question about game art.
- Negative: the previews can differ from the real window and must be regenerated when a view changes.
