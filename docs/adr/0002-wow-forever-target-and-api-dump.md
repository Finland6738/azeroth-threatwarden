# 0002. Target WoW Forever (Interface 16001) and use the API dump as a reference

- Status: Accepted (the threat APIs are verified in M0)
- Date: 2026-11-25 (same decision as Azeroth Accord, ADR 0002 there)

## Context

The addon is for **World of Warcraft: Forever**: build `1.60.1`, `## Interface: 16001`, on a modern client engine with
level-60 content. Public documentation mostly covers retail or old classic clients, and the specification forbids
assuming compatibility with Retail, Classic Era, 1.12, 2.4.3 or 3.3.5a.

## Decision

1. The TOC declares `## Interface: 16001`; at load the addon checks the project id and the interface number.
2. The public API dump extracted from the Forever client (`Atraeau/WoW-Addons`, cloned next to the project) is the
   reference for what can be called. It declares no licence, so none of its files enter this repository.
3. Functions missing from the dump, or whose behaviour on Forever is unknown, are marked **[verificare]** in the specs,
   guarded by `Core/Compat.lua` and confirmed by the probe of milestone M0.
4. What the dump says today (build 70170) about threat, checked on 2026-11-25:
   - present: `UnitDetailedThreatSituation(unit, mob)` (isTanking, status, scaledPercentage, rawPercentage,
     rawThreat), `UnitThreatSituation`, `UnitThreatPercentageOfLead`, `UnitThreatLeadSituation`,
     `GetThreatStatusColor`, `IsThreatWarningEnabled`, the events `UNIT_THREAT_LIST_UPDATE` and
     `UNIT_THREAT_SITUATION_UPDATE`;
   - present and decisive: `ShouldUnitThreatValuesBeSecret(unit, mob)`, `ShouldUnitThreatStateBeSecret(unit, mob)`
     and `issecretvalue`: threat answers **may be secret values** an addon cannot read;
   - absent: `CombatLogGetCurrentEventInfo`; only `C_CombatLogInternal` and the secure combat log exist, so the
     payload of `COMBAT_LOG_EVENT_UNFILTERED` is probably not readable by an addon.

## Alternatives considered

- **Relying on the retail or classic documentation.** Useful for meaning, unreliable for availability on Forever.
- **Copying the dump into the repository.** Not allowed without a licence.

## Consequences

- Positive: no calls to functions that do not exist; the biggest risks (secret values, combat log) are known before any
  feature is promised.
- Negative: the dump is from build 70170; every client update needs a new check.
