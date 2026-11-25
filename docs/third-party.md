# Third-party material and licences

> Adapted from Azeroth Accord (docs/third-party.md), same owner, GPL-3.0
> ([ADR 0012](adr/0012-reuse-accord-and-unspoken-foundations.md)).

The addon is GPL-3.0 ([LICENSE](../LICENSE), [ADR 0011](adr/0011-license-gpl-3.md)). This page records where every
library, font and picture that ships in the package comes from and under which licence. It is the single place to update
when one is added: `tools/check_addon.py` fails when a file of `AzerothThreatwarden/Media/` is not named here or a font
folder has no licence text.

## Libraries (`AzerothThreatwarden/Libs/`, fetched, never committed)

Each library is a whole repository at a tag, pinned in [`.pkgmeta`](../.pkgmeta): `tools/fetch_libs.py` downloads it for
development and CI, the BigWigs packager embeds it in a release. The licence is the library's own; its licence file or
header travels inside its folder. [SPEC-01 §4](specs/SPEC-01-platform-architecture.md#4-librerie) says which parts the
addon loads (`AzerothThreatwarden/embeds.xml`).

| Library | Pinned tag | Source | Loaded | Licence, as the library states it |
|---|---|---|---|---|
| **Ace3** | `Release-r1403` | <https://github.com/WoWUIDev/Ace3> | LibStub, CallbackHandler-1.0, AceAddon-3.0, AceEvent-3.0, AceConsole-3.0 | BSD-style, `Libs/Ace3/LICENSE.txt` (no standalone redistribution of Ace3) |
| **LibDataBroker-1.1** | `v1.1.4` | <https://github.com/tekkub/libdatabroker-1-1> | `LibDataBroker-1.1.lua` | the repository carries no licence file; it is distributed by its author for embedding in addons |
| **LibDBIcon-1.0** | `v8.0.4` | <https://github.com/wowace-clone/LibDBIcon-1.0> | `LibDBIcon-1.0/lib.xml` | `X-License: GPLv2 or later` in `LibDBIcon-1.0.toc` |

The folders come whole, so the package also holds parts of these repositories that the addon does not load (other Ace3
libraries, the copies of LibStub, CallbackHandler and LibDataBroker inside LibDBIcon).

## Fonts, textures and logos (`AzerothThreatwarden/Media/`)

None yet. Step M1.6 adds the fonts (SIL Open Font License 1.1, each family with its licence text), the generated
textures and icons, the addon's logo made from `assets/logo-source.webp` (supplied by the repository owner) and the
NEBULA logos made from `assets/nebula-logo-dark.png` and `assets/nebula-logo-light.png` (**used with the guild's
permission** for the credits, not covered by the GPL-3.0 grant for any other use). Each file is described here in the
same pull request.

The `assets/` folder holds the source pictures only and is never part of the package.

## Game art

No Blizzard artwork is copied into the repository. Game textures and fonts are referenced by name at run time only,
never shipped as files.
