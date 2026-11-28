# Commands

*Italiano: [[Comandi|Commands-it]]*

Type a command in the game's chat box. `/atw` and `/threatwarden` are the same command. The answers appear only in your
own chat window, in the addon's language; nothing is ever posted to other players.

| Command | What it does |
|---|---|
| `/atw` | shows or hides the window |
| `/atw show` | shows the window |
| `/atw hide` | hides the window |
| `/atw lock` | locks the window: it cannot be moved or resized |
| `/atw unlock` | unlocks the window |
| `/atw reset` | puts the window's position, size and scale back to the defaults and shows it in the centre |
| `/atw settings` | opens the [Settings](Settings) page |
| `/atw about` | opens the [Info](About) page |
| `/atw debug` | opens the [diagnostic report](Reporting-Bugs-and-Feedback), ready to copy (always in English) |
| `/atw help` | lists the commands |
| `/atw demo` | starts [demo mode](Threat-Monitor#demo-mode), an invented fight (typed again, stops it) |
| `/atw demo stop` | ends demo mode (`/atw demo off` too) |
| `/atw mute` | mutes the [alerts](Alerts-and-Coach#muting) until the end of this fight, or of the next one; typed again, unmutes them |
| `/atw reports` | opens the [Reports tab](Combat-Reports) |
| `/atw replay` | opens the [Threat Replay](Threat-Replay) of the latest finished fight |
| `/atw replay 2` | the replay of the second fight of the list (1 is the newest) |
| `/atw focus` | from `v0.7.0`: opens the list of the [Dungeon Focus](Dungeon-Focus) (typed again, closes it); it says so when there is no other mob or the part is off in Settings |
| `/atw profile` | from `v0.8.0`: says which [role profile](Settings#role-profiles) is in use and where it comes from |
| `/atw profile tank` | chooses a profile by hand: `tank`, `healer` or `dps`; in combat it applies after the fight |
| `/atw profile auto` | the profile follows the role your group gives you again |

Until its version, `/atw reports`, `/atw replay`, `/atw focus` and `/atw profile` answer with the version that will
bring them.

## Key binding

The game's key bindings have **Mute alerts** under *Azeroth Threatwarden* (in the addons' category),
with no key set: it does the same as `/atw mute`. Its name is in the language of your game.

## The window

- It opens the first time you log in; afterwards it stays open or closed as you left it, for each character. It
  can also open and close by itself ([when the window shows](Settings#monitor)).
- **Move** it by dragging its title bar, **resize** it from the dashed corner at the bottom right. The lock button in
  the title bar stops both.
- The **Monitor** tab is small, to sit over the game; **Settings** is larger. Each remembers its own size.
- The pill in the title bar says what the [threat monitor](Threat-Monitor#the-footer-and-the-title-bar) is doing:
  *Idle*, *Live*, *State only*, *Unavailable* or *Demo*.
- `Esc` closes it. It can be shown, hidden, moved and resized in combat too.

## Minimap button and Addon Compartment

The button on the minimap and the entry in the game's Addon Compartment (if your client has it) work the same way:
**left click** shows or hides the window, **right click** opens Settings. Drag the minimap button to move it around the
minimap.
