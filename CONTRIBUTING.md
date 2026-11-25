# Contributing to Azeroth Threatwarden

Thank you for your interest! This guide explains how to report problems, propose ideas and change the project.

## Language

Issues, pull requests, commit messages, code comments and public documentation are in **English**. The internal
specification in `docs/specs/` is in Italian; the user manual in `docs/wiki/` is in English and Italian
([ADR 0009](docs/adr/0009-interface-and-documentation-languages.md)).

## Contents

1. [Before you start](#1-before-you-start)
2. [Reporting a problem or proposing an idea](#2-reporting-a-problem-or-proposing-an-idea)
3. [Changing the code](#3-changing-the-code)
4. [Checks and tests](#4-checks-and-tests)
5. [Git, issues and pull requests](#5-git-issues-and-pull-requests)
6. [What is not accepted](#6-what-is-not-accepted)
7. [Licensing of contributions](#licensing-of-contributions)

## 1. Before you start

- Read the [specification](docs/specs/README.md) and the [ADRs](docs/adr/README.md): they explain what the addon does
  and why. The binding rule is [ADR 0003](docs/adr/0003-data-reliability-categories.md): never show a guess as a fact.
- The addon targets **WoW Forever, Interface 16001**. Check every API in the Forever API dump
  ([ADR 0002](docs/adr/0002-wow-forever-target-and-api-dump.md)) and guard it with the Compat layer.

## 2. Reporting a problem or proposing an idea

- **Bugs**: open an issue with the *Bug report* form and paste the `/atw debug` report.
- **Ideas and questions**: start a topic in the
  [Feedback discussions](https://github.com/Finland6738/azeroth-threatwarden/discussions/categories/feedback); a concrete
  request can become a *Feature request* issue.
- **Checks in the real client**: use the *In-game test report* form.
- **Privacy**: never paste other players' names, whispers, account names or folder paths from your PC.

## 3. Changing the code

- The addon lives in `AzerothThreatwarden/` (Lua 5.1 only, from M1.2): `Core/` infrastructure, `Data/` logic without
  graphics, `UI/` views, `Locales/` texts. Modules talk through the internal event bus.
- Every game API call goes through `Core/Compat.lua`; a secret value is never read.
- Every visible string goes through AceLocale (`L["KEY"]`) and exists in `enUS` and `itIT`.
- Saved data changes need a schema migration ([ADR 0005](docs/adr/0005-embedded-ace3-savedvariables-and-schema-versions.md)).
- Libraries are never committed: they are pinned in `.pkgmeta`.

## 4. Checks and tests

```
python -I -X utf8 tools/check_docs.py
python -m pip install lupa==2.8            # once, from M1.3
python -X utf8 Tests/run_tests.py          # all offline tests, from M1.3
python -X utf8 Tests/run_tests.py --long   # the long scenarios
```

`check_docs.py` checks relative links, the wiki sidebar, links and Italian twins, the ADR index, personal data (emails
and personal paths) and LF line endings; from M1.2 also the addon TOC and the package contents. The offline tests run
Lua 5.1 through lupa on a mock client with scripted fights
([ADR 0010](docs/adr/0010-offline-tests-with-lupa-and-a-mock-client.md)).

## 5. Git, issues and pull requests

- One branch per step or fix from an up-to-date `main`: `step/m<N>-<k>-<name>`, `fix/<name>`, `docs/<name>`,
  `chore/<name>`.
- Every pull request updates **in the same PR**: `CHANGELOG.md` ("Unreleased"), the affected docs (specs, ADRs and the
  ADR index, both READMEs) and **the wiki pages in `docs/wiki/`, in both languages, for any user-visible change**. The
  *Docs rule* check enforces it for changes to the addon ([ADR 0008](docs/adr/0008-automatic-rules-ci-docs-rule-wiki-sync.md)).
- The wiki is **never edited on GitHub**: it is published from `docs/wiki/` after every merge
  ([ADR 0007](docs/adr/0007-github-wiki-generated-from-docs-wiki.md)).
- A pull request reaches `main` as one squashed commit when `Tests` and `Docs rule` are green; the maintainer's steps
  are shipped with `tools/ship_step.py` ([ADR 0006](docs/adr/0006-git-flow-and-automated-shipping.md)).
- A pull request that fixes an issue says `Closes #N`.

## 6. What is not accepted

- Code that sends anything outside the game, posts in chat automatically, telemetry or external services
  ([ADR 0001](docs/adr/0001-local-only-addon-no-network.md)).
- Values presented as certain when they are estimated, predicted or unknown.
- Attempts to read secret values or work around the client's restrictions.
- Files copied from the game client, from Omen or from other addons.
- Personal data in the repository.

## Licensing of contributions

By submitting a contribution you agree that it is released under the project's licence, the
[GNU GPL v3.0](LICENSE), and you certify that you have the right to submit it (Developer Certificate of Origin: sign off
your commits with `git commit -s`).
