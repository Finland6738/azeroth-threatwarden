# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Documentation

- M0.0: repository bootstrap. The owner's original specification (`docs/specs/source-specification.md`) and the
  detailed specification in Italian, [SPEC-00](docs/specs/SPEC-00-vision-scope.md) to
  [SPEC-09](docs/specs/SPEC-09-risks-open-questions.md): vision and the binding data reliability categories, platform
  and the threat APIs of the Forever dump (including **secret threat values** and the missing
  `CombatLogGetCurrentEventInfo`), data model, monitor, alerts and Coach, recording and replay, analytics,
  multi-target, the M0 probe checks P1–P12, risks and open questions. The owner's answers of 2026-11-25: names
  `AzerothThreatwarden` and `/atw` (Q1), GPL-3.0 for everything (Q2), MVP = M1–M4 (Q3), a standalone addon with NEBULA
  credits (Q4). ADRs 0001–0015 and their index. `ROADMAP.md` and one file per milestone, M0 to M8, with steps, checks
  and the model and effort of each step's session. `CLAUDE.md`, `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md`, both READMEs
  and the first wiki pages in English and Italian.

- M0.1: probe specification. [SPEC-08 §1](docs/specs/SPEC-08-quality-probe-release.md#1-probe-m0) now details every
  check P1–P12 of the probe `AzTw_Probe`: exact calls and unit tokens (checked against the Forever dump), contexts
  (solo, party, dungeon, raid, battleground), the fields recorded per reading (never names or player GUIDs, secret
  values only as `secret`), how the owner runs it, and the consequence of each verdict (supported / partially / not
  supported) on specs, ADRs and milestones. New common rules PRB-01–PRB-06, the context stamp and P3b (whether a secret
  value can be shown without being read). [docs/spike/README.md](docs/spike/README.md): what the probe is, the planned
  install (`tools/install_probe.py`, `tools/local.ini`), the planned `/atwp` commands and the in-game procedure per
  context. SPEC-01 §2: the threat secrecy checks live in `C_Secrets`.

### Added

- The owner's logo (`assets/logo-source.webp`) and the NEBULA logos for the credits (`assets/`).
- Repository tooling adapted from Azeroth Accord: `tools/check_docs.py` (links, wiki twins, ADR index, privacy scan, LF
  endings), `tools/check_pr_docs.py`, `tools/ship_step.py`, `tools/release_notes.py`, `tools/sync_wiki.py`; the
  workflows CI, Docs rule, Long tests, DCO, Release and Wiki sync; issue and pull request templates; `.pkgmeta`,
  `.luarc.json`, `.gitattributes`, `.gitignore`.
