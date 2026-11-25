# Settings

*Italiano: [[Impostazioni|Settings-it]]*

Open it with `/atw settings`, with a right click on the minimap button, or from the **Settings** tab of the window. The
same page is in the game's own settings window, under *Options → AddOns → Azeroth Threatwarden*, if your client allows
it. A change made in one place shows in the other, and every change is saved as you make it. It applies **at once**,
except the font (complete after you restart the game) and the language (after a reload of the interface). The page
scrolls with the mouse wheel.

![The Settings page, theme Nebula: the top and the page scrolled down](../specs/mockups/previews/settings-nebula.webp)

![The Settings page in Italian, theme Warden](../specs/mockups/previews/settings-warden-it.webp)

*Design previews, not screenshots: drawn from the addon's own layout and texts, because the addon has not been run in the game yet ([all previews](https://github.com/Finland6738/azeroth-threatwarden/blob/main/docs/specs/mockups/previews/README.md)).*

## Appearance

Saved for the whole account.

| Option | Choices | Default |
|---|---|---|
| Theme | **Nebula** (dark, violet and orange), **Aurora** (light, blue and teal), **Warden** (dark, from the colours of the logo) | Nebula |
| Neon effects | on / off: glows and shadows; off gives a flat look | on |
| Animations | on / off: fades and slides; off makes every change immediate | on |
| Font | **Addon font** (Orbitron, Outfit, JetBrains Mono) or **Game font** | Addon font |

A change of **font** is complete only after you **restart the game**: the game reads new font files only when it starts.
The colours of the threat states do not change with the theme.

## Language

**Automatic** (follows the language of your game: English, or Italian in an Italian client), **English** or
**Italiano**. The change takes effect after a reload of the interface: press **Reload now** (it is active only when the
choice differs from the language on screen) or type `/reload`.

## Window

Saved for each character, except the minimap button (whole account).

| Option | What it does | Default |
|---|---|---|
| Lock the window | the window cannot be moved or resized (also the lock in the title bar, `/atw lock`) | off |
| Window scale | 50 % to 200 %, in steps of 5 %; it applies when you release the slider | 100 % |
| Show minimap button | shows or hides the button on the minimap | on |
| Reset window | position, size and scale back to the defaults, the window in the centre (like `/atw reset`) | — |

## Reset

**Reset settings** puts the appearance, the language and the minimap button back to the defaults, and drops the damaged
data the addon had set aside for bug reports. It asks for a second
click, within a few seconds. Your recordings (from a later version) are not touched; the window's place is reset with
*Reset window*.

## Read-only data

If your saved data was written by a newer version of the addon (or could not be updated), the page says so: the addon
works, but changes are not saved ([[Privacy and Data|Privacy-and-Data]]).
