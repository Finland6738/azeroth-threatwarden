# 0011. Licence: GNU GPL v3.0 for code and documentation

- Status: Accepted
- Date: 2026-11-25 (the owner's choice, [SPEC-09 Q2](../specs/SPEC-09-risks-open-questions.md))

## Context

The owner's addons are GPL-3.0. Azeroth Unspoken separates the licence of its phrases (all rights reserved) because they
are its creative core; Azeroth Threatwarden has no such content: its texts are interface strings and Coach messages.

## Decision

The code, the interface texts and the documentation are released under the **GNU General Public License v3.0**
(`LICENSE`), like Azeroth Accord. Whoever modifies and redistributes the addon must publish their source under the same
licence. There is no separate content licence. Third-party parts keep their own licences: Ace3, LibDataBroker and
LibDBIcon (embedded by the packager), the fonts under the SIL Open Font License 1.1 with their texts (from M1), and the
NEBULA logos used with the guild's permission for the credits; all are listed in `docs/third-party.md` (from M1). Game
textures are referenced by file id or atlas name and never redistributed.

## Consequences

- Positive: improvements stay open; code can move freely between the owner's GPL projects.
- Negative: closed-source forks are not allowed.
