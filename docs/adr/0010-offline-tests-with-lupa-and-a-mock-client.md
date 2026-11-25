# 0010. Offline tests with lupa and a mock client; long tests apart

- Status: Accepted
- Date: 2026-11-25 (the approach of Azeroth Accord, ADR 0016 there)

## Context

The addon runs only inside WoW Forever, which cannot start in continuous integration, and the owner cannot test in the
client for every step. Most of the logic (threat model, states, rules, recorder, storage, metrics, replay) does not
depend on graphics.

## Decision

1. **Runner** `Tests/run_tests.py` with `lupa.lua51` (pinned `lupa==2.8`, Lua 5.1 like the client): it loads the real
   embedded libraries and the addon files in TOC order, each with the addon name and a private namespace table.
2. **Mock client** in `Tests/mock/`, one area per file (frames and events, a controllable clock and timers, units and
   groups, the threat API with scripted fights, **secret values** and `nil` answers, combat state), each file citing
   the dump entries it imitates.
3. **`/reload` simulation** that serializes and restores the SavedVariables declared in the TOC.
4. **Fight scripts** in `Tests/lib/`: a small language for scripted pulls (who does what threat, when the tank dies,
   when a mob disappears or changes GUID), so states, alerts and recordings are tested against known answers.
5. **Long tests** (`Tests/run_tests.py --long`, workflow `Long tests`): a 40-player raid with many mobs for hours,
   storage near its limit, reloads in combat; CI runs only the quick tests.
6. Every step adds tests for what it builds; no change without tests. The harness starts as a copy of Azeroth Accord's
   ([ADR 0012](0012-reuse-accord-and-unspoken-foundations.md)).

## Consequences

- Positive: fast tests in CI; the logic is proven on scripted fights with known answers.
- Negative: a green test shows that the code agrees with our assumptions about the client, not that the client agrees:
  the M0 probe and the in-game check of each milestone stay necessary.
