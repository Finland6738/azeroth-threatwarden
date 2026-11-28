# 0021. The game's raid frames are only overlaid, never touched

- Status: Accepted (M8.1, before the M0 probe; to verify in the game: no taint, no blocked action, the marks in place)
- Date: 2026-11-28

## Context

The heatmap of M8 (the owner's specification §5.7) colours the rows of the Threat Monitor and, *only if technically
and legally compatible*, the raid frames. The game's own party and raid frames (*Compact Raid Frames*) are secure
code: click-casting, targeting and menus run through them in combat. An addon that writes into them (a field of the
frame table, a hook on their functions, a texture created on them, an anchor that ties them to its own frames) can
spread *taint*: the game then blocks a protected action (`ADDON_ACTION_BLOCKED`) or breaks the frames in combat, and
the player blames the addon or loses a fight. The API dump lists `hooksecurefunc` and the frames' global functions
(`CompactUnitFrame_UpdateAll`, `CompactUnitFrame_UpdateHealthColor`, `CompactUnitFrame_UpdateAggroHighlight`…) but no
frame by name; the probe does not test them; the Blizzard frames already highlight aggro with the game's own threat.

## Decision

1. **Nothing is written into, hooked on or anchored to the game's frames.** No `hooksecurefunc`, no `SetPoint`,
   `SetParent` or `SetFrameLevel` relative to them, no field, no texture, no method call other than reads.
2. **A detached overlay.** An addon frame parented to `UIParent`, never protected, holds a pool of marks placed at
   absolute coordinates. Out of combat only, `Core/Compat.lua` finds the visible frames by name at runtime and reads
   their `unit`, `IsVisible`, `GetRect` and `GetEffectiveScale`; the overlay copies their rectangles. In combat only
   the marks' colour, alpha and word change; a roster change in combat hides every mark until the fight ends.
3. **Marks only where there is a risk**, with an icon and a word (WARNING, DANGER, aggro on a non-tank), never on SAFE
   or UNKNOWN, never taking the mouse.
4. **Off by default**, behind the `heatmap` switch and its own setting, with the risk said on the card; no frames of
   other addons; nothing if the frames cannot be found or read (a `raidFrames` capability).
5. **Removed if the game blames it.** If the in-game check finds one blocked action or taint entry from the overlay,
   the option goes and the heatmap stays on the monitor rows (open question Q29).

## Consequences

- The overlay cannot follow a frame that moves during combat; it hides instead of drawing in the wrong place.
- It covers only the game's frames; players with replacement raid frames see nothing there (the card says so).
- Reading fields and geometry of secure frames is assumed harmless, as in the standard client: this is the residual
  risk the release checklist checks with the game's taint log.
- M8.3 built it as decided, behind the `heatmap` switch: `Compat.RaidFrames.Collect` is the only code that touches the
  frames (rawget and three reads, out of combat lockdown), the mock client logs every other touch and the tests fail on
  any; a change of the frames' layout or of the screen in combat hides the marks too. Not yet checked in the game.
- See [SPEC-07 §3.3](../specs/SPEC-07-multi-target-heatmap-profiles.md#33-i-riquadri-del-raid-di-blizzard-uiraidoverlaylua)
  (Italian) and SPEC-09 R14.
