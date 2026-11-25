# 0014. One version per milestone, feature switches for unfinished parts; v1.0.0 after the last milestone

- Status: Accepted
- Date: 2026-11-25 (the rules of Azeroth Accord, ADR 0020 there and its update of 2026-11-25)

## Decision

1. Every milestone N is released as **`v0.N.0`** after it is complete: `v0.1.0` (M1) … `v0.8.0` (M8). M0 is the probe
   and has no release. Minor numbers may go past 9.
2. Fixes to a released milestone raise only the last number: `v0.2.1`, `v0.2.2`.
3. **`v1.0.0`** is released when every planned milestone is done, after the full release check.
4. Pre-release suffixes (`-alpha.N`, `-beta.N`, `-rc.N`) stay available.
5. **No half-finished feature in a release**: what a later milestone left in the code is switched off in
   `AzerothThreatwarden/Core/Features.lua` (off in the shipped code, checked by `Tests/test_features.lua`) until that
   milestone is complete.
6. Before every tag a release-preparation step (`M<N>.R`, branch `chore/release-v0.N.0`) hides the unfinished parts,
   promotes the changelog with `tools/release_notes.py --promote`, updates the status of the READMEs and the wiki, and
   runs the Release workflow as a dry run. Then the annotated tag is pushed and the GitHub Release and its zip are
   checked. Milestone tags have the owner's standing approval; any other tag is asked first.
7. GitHub Releases from `v0.1.0`; CurseForge from the MVP (`v0.4.0`), when the owner sets it up
   ([SPEC-09 Q6](../specs/SPEC-09-risks-open-questions.md)).

## Consequences

- Each milestone file ends with its in-game checklist step and a release-preparation step.
- The "Unreleased" section of the changelog is promoted to `0.N.0` at each milestone release.
