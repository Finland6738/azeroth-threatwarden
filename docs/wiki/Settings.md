# Settings

*Italiano: [[Impostazioni|Settings-it]]*

Open it with `/atw settings`, with a right click on the minimap button, or from the **Settings** tab of the window. The
same page is in the game's own settings window, under *Options → AddOns → Azeroth Threatwarden*, if your client allows
it. A change made in one place shows in the other, and every change is saved as you make it. It applies **at once**,
except the font (complete after you restart the game) and the language (after a reload of the interface). The page
scrolls with the mouse wheel.

![The Settings page, theme Nebula: the top and the page scrolled down](../specs/mockups/previews/settings-nebula.webp)

![The Settings page in Italian, theme Warden](../specs/mockups/previews/settings-warden-it.webp)

![The Monitor card in Italian, theme Warden](../specs/mockups/previews/settings-monitor-warden-it.webp)

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

## Monitor

*Arrives with `v0.2.0`.* Saved for the whole account. Every change applies at once, also to a
[demo](Threat-Monitor#demo-mode) or a fight in progress.

![The Monitor card of Settings, theme Nebula: the top and the page scrolled down](../specs/mockups/previews/settings-monitor-nebula.webp)

| Option | What it does | Choices | Default |
|---|---|---|---|
| Warning threshold | from this share of the threat that takes the mob, a row says **Warning** | 50 % to 95 % | 80 % |
| Danger threshold | from this share, **Danger** | 60 % to 100 % | 95 % |
| Reads per second | how often the threat is read in combat: a higher rate reacts sooner and costs more | 2 to 10 Hz | 5 Hz |
| Units per read | how many units are read each time; in a larger group the others are read in turn (you, your pet, the tanks and who holds the mob every time) | 5 to 40 | 40 |
| When the window shows | see below | In group or combat, Always, Manually | In group or combat |
| Order of the list | *Percentage*, *Absolute threat*, *Risk*, *Recent change* (also the **Sort** button of the list) | | Percentage |
| Pin me on top | your row comes first (also **Me on top** in the list) | on / off | off |
| Follow the target of a friend | with a friendly target (the tank), the monitor shows the enemy it targets | on / off | on |
| Start the demo | plays an invented fight, to try these settings ([demo mode](Threat-Monitor#demo-mode)) | button | |

Danger stays at least 5 points above Warning: moving one slider pushes the other. The thresholds, the rate and the
number of units are provisional until they are tuned in the game.

**When the window shows:**

- **In group or combat**: the window opens by itself, on the Monitor tab, when a fight starts and when you join a group.
  Outside a group it closes by itself 10 seconds after a fight, unless you opened it again or moved to another tab. If
  you close it during a fight, it stays closed until the next fight. At login it is as you left it (and open in a group).
- **Always**: it is shown every time you log in or reload; only you close it.
- **Manually**: it stays open or closed as you leave it.

Opening or closing by itself never changes what you chose by hand.

## Reset

**Reset settings** puts the appearance, the language, the minimap button and the monitor settings back to the defaults, and drops the damaged
data the addon had set aside for bug reports. It asks for a second
click, within a few seconds. Your recordings (from a later version) are not touched; the window's place is reset with
*Reset window*.

## Read-only data

If your saved data was written by a newer version of the addon (or could not be updated), the page says so: the addon
works, but changes are not saved ([[Privacy and Data|Privacy-and-Data]]).
