# Azeroth Threatwarden

<img src="assets/logo-source.webp" alt="Azeroth Threatwarden logo" width="160" align="right">

**Know your threat. Understand your mistakes. Prevent aggro loss.** Azeroth Threatwarden is a threat monitoring,
threat coaching and combat analysis addon for **World of Warcraft: Forever**. It shows who is generating threat on
which mob, warns you before you pull aggro, records your fights and explains what happened, always telling what is
**known** from what is **estimated**.

> **Status: design phase.** The specification, the decisions and the plan are written; there is nothing to install
> yet. The first step is a probe in the real client (milestone M0): it checks which threat data WoW Forever gives an
> addon, because the client may hide threat values from addons in some situations. That
> [probe](docs/spike/README.md) (a development tool, never distributed) can now check the client and the threat
> functions, including whether their values are secret (P1–P4); the other checks come next. The first
> version, `v0.1.0`, comes after milestone M1; the MVP (monitor, alerts, Coach, recording and combat report) is `v0.4.0`.

[Italiano](README.it.md) · [Roadmap](ROADMAP.md) · [Specification (Italian)](docs/specs/README.md) ·
[Decisions](docs/adr/README.md) · [User manual](docs/wiki/Home.md) ([Italiano](docs/wiki/Home-it.md))

## Planned features

| Area | What you get | Milestone |
|---|---|---|
| **Threat Monitor** | Every group member's threat on your target, the tank, the scaled percentage (100% pulls aggro), the margin, the trend, and a clear state: **Safe**, **Warning**, **Danger** or **Unknown** | M2 |
| **Alerts and Coach** | Warnings before you overtake the tank, with cooldowns and a quick mute, never in chat; short advice with its reason and a confidence | M3 |
| **Combat Report** | Every fight recorded while it happens; at the end, threshold crossings, time in danger, tank changes | M4 (MVP) |
| **Threat Timeline and Replay** | How threat moved during a fight, with play, pause and seek; estimates and gaps clearly marked | M5 |
| **Threat Analytics** | Descriptive numbers per fight and across fights, and an export to copy; no blame rankings | M6 |
| **Multi-target / Dungeon Focus** | The mobs where your group is closest to losing aggro, if the client allows it | M7 |
| **Profiles and Heatmap** | Presets for tanks, damage dealers and healers; colour-blind friendly states | M8 |

**Honest data.** Every number is either read from the game, calculated from it, estimated or predicted, and the
addon shows which; when the game does not give a value, it says *Unknown* instead of guessing
([ADR 0003](docs/adr/0003-data-reliability-categories.md)).

**Private by design.** No network, no addon messages, nothing posted in chat; your recordings stay on your computer and
you can delete them ([ADR 0001](docs/adr/0001-local-only-addon-no-network.md)).

## How it is built

- Target: WoW Forever, `## Interface: 16001` ([ADR 0002](docs/adr/0002-wow-forever-target-and-api-dump.md)); Lua 5.1
  with embedded Ace3.
- Threat read only from the game's unit threat API, on events and by bounded sampling during combat
  ([ADR 0004](docs/adr/0004-threat-from-the-unit-threat-api-sampled-in-combat.md)).
- English by default, Italian from the first version; another language is one file
  ([ADR 0009](docs/adr/0009-interface-and-documentation-languages.md)).
- The look of the owner's addon family (Finland Dragon Credit Points, Azeroth Accord), with a **Warden** theme drawn
  from the logo ([ADR 0015](docs/adr/0015-interface-follows-the-ecosystem-style.md)).
- Offline tests with a mock client and scripted fights ([ADR 0010](docs/adr/0010-offline-tests-with-lupa-and-a-mock-client.md)).

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Issues, pull requests and public docs are in English; the specification is in
Italian.

## Licence

[GNU GPL v3.0](LICENSE), for the code and the documentation ([ADR 0011](docs/adr/0011-license-gpl-3.md)).
World of Warcraft is a trademark of Blizzard Entertainment, Inc.; this is an independent fan project, not affiliated
with or endorsed by Blizzard.

## Credits

- **Created and designed by Finland.**
- **Made with the Italian guild NEBULA** ([the guild's page](https://nebula-community.github.io/giochi/wow-forever/)).
  The NEBULA logo is used with the guild's permission.
- Support the project on [Ko-fi](https://ko-fi.com/finland6738); report a problem or suggest something in the
  [issues](https://github.com/Finland6738/azeroth-threatwarden/issues).
