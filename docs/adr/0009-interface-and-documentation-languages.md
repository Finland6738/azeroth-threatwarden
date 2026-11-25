# 0009. A multilingual interface (English by default, Italian); documentation languages

- Status: Accepted
- Date: 2026-11-25 (the owner's request; the approach of Azeroth Accord, ADR 0015 there)

## Context

The owner speaks Italian and plays with an Italian guild; the addon is published for every WoW Forever player. The
owner asked for a real multilingual design, with English as the default and Italian from the start.

## Decision

1. Every visible string is an AceLocale key. `Locales/enUS.lua` is the base and the fallback; `Locales/itIT.lua` ships
   from the first release (`v0.1.0`). Another language is **one more file** in `Locales/` and one line in the TOC, with
   no code change; a translator guide comes in M8.
2. The language follows the game client (`GetLocale()`); locales without a file fall back to English. A setting
   *Language: Automatic / English / Italiano* can force one (proposed in
   [SPEC-09 Q5](../specs/SPEC-09-risks-open-questions.md), applied as proposed until the owner decides).
3. `Tests/test_locales.lua` (from M1.3) fails when a key exists in one table only, a string is empty, placeholders differ
   in kind or order, a key used in the code is missing in English, or a string is identical in both languages without
   being on the short list of intended ones.
4. **Documentation**: README, ADRs, CONTRIBUTING, CHANGELOG, code, comments, commits, issues and pull requests in
   English; `README.it.md` is the Italian front page; the specification in `docs/specs/` is in **Italian**, with code
   names, APIs and interface texts in English; **the user manual is bilingual**: every `docs/wiki/<Page>.md` has an
   Italian twin `<Page>-it.md` with the same images, and `tools/check_docs.py` checks it.
5. The `/atw debug` report is not translated: it is pasted into English bug reports. Names the game gives (mobs,
   zones, spells) are never translated by the addon.

## Consequences

- Positive: usable in Italian from the first release; other languages are cheap to add.
- Negative: two READMEs, two wiki pages per topic and two locale files to keep in step (checked by tools).
