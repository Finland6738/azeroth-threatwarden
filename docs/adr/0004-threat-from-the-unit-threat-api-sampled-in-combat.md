# 0004. Threat is read from the unit threat API, on events and by bounded sampling during combat

- Status: Accepted (to verify in M0: probe checks P2 to P9)
- Date: 2026-11-25

## Context

Old threat meters rebuilt threat from the combat log with per-class formulas. On Forever the combat log payload is
probably not readable by addons (ADR 0002), and the specification forbids assuming data can be rebuilt afterwards. The
client itself computes threat and exposes it per unit and mob, possibly as secret values.

## Decision

1. The only source of threat values is the unit threat API (`UnitDetailedThreatSituation` and its relatives) through
   `Core/Compat.lua`. No threat is computed from the combat log or from class formulas.
2. Reading is driven by `UNIT_THREAT_LIST_UPDATE` and `UNIT_THREAT_SITUATION_UPDATE` where they fire, plus a bounded
   sampling tick **only during combat**, with a configurable rate and a cap on units and mobs. The default rate is set
   from the M0 measurements, not guessed.
3. A secret value, a `nil` or an error is recorded as such (category *unknown*), never replaced by an estimate that
   looks like a reading.
4. Recordings store what was sampled while the fight happened; replay never claims samples that were not taken.

## Alternatives considered

- **Combat log reconstruction.** Not available to addons on this client as far as the dump shows; also inaccurate.
- **Polling every frame.** Wasteful and forbidden by the specification (§9).

## Consequences

- Positive: values match what the game itself uses; the cost is bounded and measurable.
- Negative: if the probe finds threat secret in instances, the monitor degrades to the threat *state* or to
  "Unknown" there, and the roadmap changes (M0.7 decides).
