# Releasing

> Adapted from Azeroth Accord (docs/RELEASING.md), same owner, GPL-3.0
> ([ADR 0012](adr/0012-reuse-accord-and-unspoken-foundations.md)).

How a version of Azeroth Threatwarden is built and published. The workflow is
[release.yml](../.github/workflows/release.yml); the decisions are in
[ADR 0014](adr/0014-one-version-per-milestone-and-feature-switches.md) (versions and switches) and
[ADR 0005](adr/0005-embedded-ace3-savedvariables-and-schema-versions.md) (embedded libraries). **No version has been
released yet.** The milestone tags `v0.<N>.0` have the owner's standing approval; any other tag (a fix, a pre-release)
is asked first, and only the owner adds secrets. Development steps create no tags.

## The versions

| Tag | When |
|---|---|
| `v0.1.0` … `v0.8.0` | after milestone M1 … M8 is complete ([the plan](roadmap/README.md)); M0 is the probe and has no release; `v0.4.0` is the MVP |
| `v0.<N>.<F>` | the F-th fix release of milestone N (`v0.2.1`, `v0.2.2`) |
| `v1.0.0` | when every planned milestone is done, after the full release check |

Each version has an in-game checklist in `docs/checklists/`, written by the last step of its milestone.

**No half-finished feature in a release.** Whatever a later milestone left in the addon is hidden behind its switch in
`AzerothThreatwarden/Core/Features.lua` (off in the shipped code, checked by `Tests/test_features.lua` from M1.3) and
switched on when that milestone is complete. A pre-release suffix (`-alpha.N`, `-beta.N`, `-rc.N`) makes the GitHub
Release a pre-release.

## What a tag does

Pushing a tag `vMAJOR.MINOR.PATCH` (optionally with a pre-release suffix) starts the workflow **Release**, which:

1. checks what the package will contain (`tools/check_package.py`);
2. builds the zip with the [BigWigs packager](https://github.com/BigWigsMods/packager): libraries from `.pkgmeta`,
   `## Version` filled in with the tag, `Tests/`, `docs/`, `tools/` (with the probe), `assets/` and Markdown left out,
   `LICENSE` kept, development code switched off;
3. checks the zip itself (`tools/check_package.py --zip`) and keeps it as a workflow artifact for 14 days;
4. creates the **GitHub Release** with that zip (a pre-release when the tag has a suffix); its body is the section of
   `CHANGELOG.md` for the version (`tools/release_notes.py`: the section of the exact tag, else of the base version,
   else *Unreleased*);
5. uploads to **CurseForge**, only if both the `CF_API_KEY` secret and the project ID in the TOC are set (not for `-rc`
   tags). Otherwise it says "CurseForge skipped" and the run stays green.

Check the package locally at any time, with no network and no secrets:

```bash
python -I -X utf8 tools/check_package.py --list
```

## Installing a development copy

```bash
python -I -X utf8 tools/fetch_libs.py
python -I -X utf8 tools/install_addon.py
```

`install_addon.py` replaces `Interface/AddOns/AzerothThreatwarden` with the folder of the repository. The AddOns folder
comes from `tools/local.ini` (git-ignored; copy `tools/local.example.ini`). A development copy shows
`@project-version@` as its version.

## Try it without publishing anything

1. **Dry run**: Actions → *Release* → *Run workflow* on `main`, leave `draft_tag` empty. It builds and checks the zip;
   download it from the run's artifacts and look inside. Nothing is published.
2. **Draft release**: run it again with `draft_tag` = `v0.0.1-alpha.1`. It creates a **draft** GitHub Release with the
   zip; only the repository's owner sees drafts. Open it, then delete the draft. No tag is pushed and CurseForge is not
   touched.

## Setting up CurseForge (once)

CurseForge is **optional and off** until the owner creates the project and the secret
([SPEC-09 Q6](specs/SPEC-09-risks-open-questions.md): proposed from the MVP, `v0.4.0`). The TOC has the project line
commented out and the repository has no `CF_API_KEY` secret, so a tag publishes on GitHub only. To switch it on:

1. Create a project on [CurseForge](https://www.curseforge.com/wow/addons) for World of Warcraft addons: name
   *Azeroth Threatwarden*, licence GPL-3.0, the unofficial notice and the privacy summary
   ([Privacy and Data](wiki/Privacy-and-Data.md)) on the description. Make sure the project's game versions include
   **WoW Forever**.
2. Copy the **Project ID** (a number, on the project's *About* panel) into the TOC: in
   `AzerothThreatwarden/AzerothThreatwarden.toc` replace the commented line `# ## X-Curse-Project-ID: 0` with
   `## X-Curse-Project-ID: 12345` (your number, two `#` signs, no space in front). Ship that in a normal pull request.
3. Create an API token at <https://www.curseforge.com/account/api-tokens>.
4. Add it in the GitHub repository: **Settings → Secrets and variables → Actions → New repository secret**, name
   `CF_API_KEY`, value the token. The owner does this; never paste the token in an issue, a pull request or a chat.
5. Push a `-beta` tag first, and look at the CurseForge file: its game version and release type (*Beta*).

## Releasing a version

The release-preparation step of the milestone (`M<N>.R`, branch `chore/release-v0.N.0`) does this:

1. Everything merged on `main`, CI green, the unfinished parts of later milestones hidden. The in-game checklist of the
   version is run when the owner can; when it was not run before the tag, the changelog section says so.
2. In a normal pull request: promote the changelog with `python -I -X utf8 tools/release_notes.py --promote 0.1.0`
   (*Unreleased* becomes `## [0.1.0] - <date>` and a new empty *Unreleased* goes on top), update the status of
   `README.md`, `README.it.md` and the wiki, and run the dry run above. Check what the release will say:
   `python -I -X utf8 tools/release_notes.py v0.1.0`.
3. Tag the merge commit and push the tag. **Check the git identity first**: an annotated tag records the tagger's name
   and email, and this repository's rule is the GitHub noreply address ([CLAUDE.md](../CLAUDE.md), Privacy).
   `git config user.email` must print an `@users.noreply.github.com` address; then:

   ```bash
   git tag -a v0.1.0 -m "Azeroth Threatwarden 0.1.0"
   git push origin v0.1.0
   ```

4. Watch the run in the Actions tab, then open the GitHub Release (and CurseForge) and download the zip once: the folder
   must be `AzerothThreatwarden/` with the TOC inside.
5. Wrong release? Delete the GitHub Release and the tag (`gh release delete vX --cleanup-tag --yes`), remove the file on
   CurseForge, fix, and tag again with a new patch number; do not reuse a tag that was public.
