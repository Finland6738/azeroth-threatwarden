# 0003. Every value shown has a reliability category; unknown is shown, never invented

- Status: Accepted
- Date: 2026-11-25 ([specification](../specs/source-specification.md) §3, binding for every feature)

## Context

The product's value is trust: a threat meter that shows a confident number that is wrong is worse than none. Some data
comes straight from the client, some is computed, some is a projection of a trend, and some explanations can never be
proven from the data the client gives.

## Decision

1. Every value the addon shows, records or reports carries one category: **detected** (read from an API or event),
   **calculated** (derived from detected values), **estimated** (from incomplete samples), **predicted** (a projection
   of a trend) or **hypothesis** (an interpretation that cannot be proven).
2. The interface shows the difference: estimated and predicted values have a visible marker and a tooltip that says so;
   hypotheses are worded as possibilities ("probably", "may"), never as causes.
3. When the client does not expose a value, or answers with a secret value, `nil` or stale data, the addon shows an
   explicit state (**Unknown**, **Not available**, **Insufficient data**), never a guessed number.
4. The data model keeps the category (`ThreatRecord.source`, `confidence`) next to each value, so recordings and
   reports keep it too ([SPEC-02](../specs/SPEC-02-data-model-storage.md)).
5. The Coach never states an exact cause of an aggro loss without evidence, and never recommends a class ability whose
   availability it cannot verify.

## Consequences

- Positive: players can trust what is shown; the limits of the client are visible instead of hidden.
- Negative: more states to design and test; some screens will say "Unknown" often if the client restricts threat.
