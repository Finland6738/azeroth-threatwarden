# 0008. Automatic rules: CI, a docs rule and the wiki sync

- Status: Accepted
- Date: 2026-11-25 (same approach as Azeroth Accord, ADR 0014 there)

## Context

Automated merges ([ADR 0006](0006-git-flow-and-automated-shipping.md)) are only safe if the rules are enforced by
machines.

## Decision

1. **CI** (`ci.yml`, job `Tests`): documentation checks (`tools/check_docs.py`: relative links, wiki sidebar, links and
   Italian twins, ADR index, privacy scan for emails and personal paths, LF endings, the docs rule's own cases) and,
   from milestone M1, the addon and package checks and the offline tests.
2. **Long tests** (`long-tests.yml`): the slow scenarios, on changes to the threat pipeline and every Monday.
3. **Docs rule** (`docs-check.yml`, job `Docs rule`): a pull request that changes `AzerothThreatwarden/` must also
   change `CHANGELOG.md` and a documentation file, unless it has the label `no-docs-needed`.
4. **Wiki sync** (`wiki-sync.yml`) as in [ADR 0007](0007-github-wiki-generated-from-docs-wiki.md).
5. **DCO** (`dco.yml`): an advisory warning for external commits without a sign-off.
6. **Branch protection on `main`**: `Tests` and `Docs rule` required as status checks; no required reviews and no
   "require a pull request" rule, because shipping fast-forwards `main`; no force pushes; no deletion. The owner turns
   it on in the repository settings.
7. Actions are pinned to a commit and declare the least permissions they need.

## Consequences

- Positive: no merge with failing checks; docs and wiki travel with the code.
- Negative: a pull request that touches the addon needs a changelog entry and a doc (or the label).
