# 0006. Git flow and automated shipping of milestone steps

- Status: Accepted
- Date: 2026-11-25 (same rules as Azeroth Accord, ADR 0012 there)

## Context

The project is developed in milestone steps by automated sessions, one fresh session per step, while the owner is
often away. The owner asked that every finished step is committed, pushed, opened as a pull request and merged
**automatically**, and that the wiki follows every change.

## Decision

1. `main` is always working; nobody commits to it directly (the only exception is the empty repository's first commit).
2. One branch per step from an up-to-date `main`: `step/m<N>-<k>-<name>` for roadmap steps, `fix/…`, `docs/…`,
   `chore/…` for the rest.
3. Messages, pull requests and issues in English.
4. **Authorized automation**: `python -I -X utf8 tools/ship_step.py --title … --body-file …` runs the local checks,
   merges `origin/main` if needed, squashes the step into **one commit authored and committed by the noreply address**,
   pushes, opens the pull request, waits for the required CI checks on that exact commit and, only if they are green,
   **fast-forwards `main` to it** and deletes the branch. On any failure it stops and the pull request stays open.
5. Every pull request says honestly what was **not** verified, especially anything that needs the real client.
6. Never `--force` on `main`, never rewrite published history, never skip hooks.
7. GitHub's own merge (`gh pr merge`, the web button) is never used: it authors the commit with the account's personal
   email.
8. Choices that belong to the owner (licence, names, scope, deleting their data) are not made autonomously: they are
   asked, or listed in [SPEC-09](../specs/SPEC-09-risks-open-questions.md) with a proposed answer that the code applies
   until the owner decides.

## Consequences

- Positive: one readable commit per step on `main`, no manual merge work, CI as the gate.
- Negative: no human review before merge; the checks must be good enough to be trusted.
