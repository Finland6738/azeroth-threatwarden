# Instructions for development sessions

The owner speaks Italian: talk to them in Italian. Code, comments, commits, pull requests, issues, README and ADRs are
in English; the wiki is bilingual (every `docs/wiki/<Page>.md` has an Italian twin `<Page>-it.md`, same images, and
`tools/check_docs.py` checks it); the specification in `docs/specs/` is in Italian; the interface is English by default
with Italian, one locale file each ([ADR 0009](docs/adr/0009-interface-and-documentation-languages.md)).

## Where things are

- The owner's original specification: `docs/specs/source-specification.md` (the source of truth on **what** the addon
  does). Detailed specification: `docs/specs/` (SPEC-00…SPEC-09). Decisions: `docs/adr/` (index in
  `docs/adr/README.md`). User manual: `docs/wiki/`. Plan: `ROADMAP.md` and the milestone files in `docs/roadmap/` (take
  the first unticked step, tick it in the same PR with a short *Done* note).
- Open questions for the owner: `docs/specs/SPEC-09-risks-open-questions.md` (Q1, Q2…, each with a proposed answer that
  the code applies until the owner decides; each answer changes in one place).
- WoW Forever API dump: `../WoW-Addons/docs/api.json` (consult only, never copy,
  [ADR 0002](docs/adr/0002-wow-forever-target-and-api-dump.md)).
- Sibling projects to copy foundations from, read only: `../azeroth-accord` (process, tools, Core, UI kit, tests) and
  `../azeroth-unspoken` (architecture document, UI review, assets pipeline); same owner, GPL-3.0
  ([ADR 0012](docs/adr/0012-reuse-accord-and-unspoken-foundations.md)). Each copied file says where it comes from.

## Rules of the code

- Every value shown has a reliability category (detected, calculated, estimated, predicted, hypothesis); unknown is
  shown as unknown, never invented; secret values are never read ([ADR 0003](docs/adr/0003-data-reliability-categories.md)).
- Every game API goes through `Core/Compat.lua` and is checked against the dump; no `UI/` file calls a game API.
- No network, no addon messages, nothing posted in chat by default ([ADR 0001](docs/adr/0001-local-only-addon-no-network.md)).
- No globals except the addon's; saved data versioned with migrations; every visible string a locale key in `enUS`
  and `itIT`; no colour outside `UI/Theme.lua`; unfinished parts behind `Core/Features.lua`.
- No change without tests (`Tests/`, lupa and the mock client, [ADR 0010](docs/adr/0010-offline-tests-with-lupa-and-a-mock-client.md)).

## Git automation (authorized by the owner, ADR 0006)

For every milestone step or fix:

1. Branch from an up-to-date `main`: `step/m<N>-<k>-<name>` (or `fix/…`, `docs/…`, `chore/…`). Never commit to `main`.
2. Do the work. In the same branch update `CHANGELOG.md`, the affected specs/ADRs (and the ADR index), `README.md` +
   `README.it.md` when features or status change, `docs/wiki/` in both languages for anything user-visible, and the
   step's checkbox in its milestone file.
3. Run `python -I -X utf8 tools/check_docs.py` and the addon tests (`python -X utf8 Tests/run_tests.py`, from M1.3).
4. Write the pull request body (what and why, what was **not** verified in the real client) and ship **without asking**:
   `python -I -X utf8 tools/ship_step.py --title "M<N>: <summary>" --body-file <file> --commit "<message>"`
   It squashes the step into one noreply commit, pushes, opens the PR, waits for CI and fast-forwards `main` to the
   checked commit. If it stops, leave the PR open and report why.
5. **Never** `gh pr merge` and never merge from the GitHub web UI (they would use the owner's personal email).
6. The wiki is published by the `Wiki sync` workflow after the merge: never edit the wiki on GitHub, and **never run
   `tools/sync_wiki.py`** (not even with `--help`): it publishes.

Do not decide alone what belongs to the owner (licence, names, scope, deleting their data): ask, or open an issue with
the options, and list it in SPEC-09.

## Sessions

One fresh session per step, started by the coordinating session ([docs/roadmap/README.md](docs/roadmap/README.md#sessions-one-fresh-session-per-step)).
A step session does only its step and reports in Italian: the pull request, the commit on `main`, the number of tests,
and what is not verified in the game.

## Privacy

No personal data in the repository: no real names, emails (only GitHub noreply addresses), or personal paths (use
`<WoW folder>` and similar). `tools/check_docs.py` fails on them. This includes git authorship: this repository's git
identity is the noreply address, and `ship_step.py` authors and commits every step with it. `prompt.txt` holds the
owner's notes and is git-ignored.
