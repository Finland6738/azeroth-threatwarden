# 0007. The GitHub wiki: a user manual generated from `docs/wiki/`

- Status: Accepted
- Date: 2026-11-25 (same approach as Azeroth Accord, ADR 0013 there)

## Context

Players need a manual that is easy to navigate and has no developer content. A GitHub wiki is a separate git
repository, outside pull requests and reviews.

## Decision

1. `docs/wiki/*.md` is the **only source** of the wiki; the wiki is a generated mirror and is **never edited on GitHub**.
2. `tools/sync_wiki.py` clones the wiki, copies the pages with a "generated, do not edit here" note, copies the images
   they show, removes what is gone, and pushes as `github-actions[bot]`. Development sessions never run it.
3. The **Wiki sync** workflow runs it on every push to `main` that changes `docs/wiki/`.
4. GitHub creates the wiki repository only after its first page is saved in the browser; until then the sync passes
   with a warning. The owner saves that first page once.
5. Developer documentation (specs, ADRs, contributing) stays in the repository.

## Consequences

- Positive: one reviewed source; the manual cannot drift from the repository.
- Negative: user-visible changes must update `docs/wiki/` in the same pull request.
