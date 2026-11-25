# Project decisions (ADRs)

The architecture and method decisions of Azeroth Threatwarden, one per file, in the [MADR](https://adr.github.io/madr/)
format in English: **context**, **decision**, **alternatives considered**, **consequences**.

They record *why* the project is built a certain way. A decision that changes is not rewritten: a new ADR supersedes
it, and the old one moves to the "superseded" status (a small change may be added as a dated update section). The
detailed design is in the [specification](../specs/README.md) (Italian).

## Index

| No. | Decision | Status |
|---|---|---|
| [0001](0001-local-only-addon-no-network.md) | A local-only addon: no network, no addon messages, data stays on the computer | accepted |
| [0002](0002-wow-forever-target-and-api-dump.md) | Target WoW Forever (Interface 16001) and use the API dump as a reference | accepted (threat APIs to verify in M0) |
| [0003](0003-data-reliability-categories.md) | Every value shown has a reliability category; unknown is shown, never invented | accepted |
| [0004](0004-threat-from-the-unit-threat-api-sampled-in-combat.md) | Threat is read from the unit threat API, on events and by bounded sampling during combat | accepted (to verify in M0) |
| [0005](0005-embedded-ace3-savedvariables-and-schema-versions.md) | Embedded Ace3, SavedVariables and schema versions | accepted |
| [0006](0006-git-flow-and-automated-shipping.md) | Git flow and automated shipping of milestone steps | accepted |
| [0007](0007-github-wiki-generated-from-docs-wiki.md) | The GitHub wiki: a user manual generated from `docs/wiki/` | accepted |
| [0008](0008-automatic-rules-ci-docs-rule-wiki-sync.md) | Automatic rules: CI, a docs rule and the wiki sync | accepted |
| [0009](0009-interface-and-documentation-languages.md) | A multilingual interface (English by default, Italian); documentation languages | accepted |
| [0010](0010-offline-tests-with-lupa-and-a-mock-client.md) | Offline tests with lupa and a mock client; long tests apart | accepted |
| [0011](0011-license-gpl-3.md) | Licence: GNU GPL v3.0 for code and documentation | accepted |
| [0012](0012-reuse-accord-and-unspoken-foundations.md) | Reuse the foundations of Azeroth Accord and Azeroth Unspoken | accepted |
| [0013](0013-design-previews-original-art-invented-data.md) | Design previews: original art, invented data, drawn from the addon's texts | accepted |
| [0014](0014-one-version-per-milestone-and-feature-switches.md) | One version per milestone, feature switches for unfinished parts; `v1.0.0` after the last milestone | accepted |
| [0015](0015-interface-follows-the-ecosystem-style.md) | The interface follows the ecosystem style of FDCP and Accord, with a Warden theme from the logo | accepted |
