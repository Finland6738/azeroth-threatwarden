# 0001. A local-only addon: no network, no addon messages, data stays on the computer

- Status: Accepted
- Date: 2026-11-25 ([specification](../specs/source-specification.md) §2.2 and §10)

## Context

Azeroth Threatwarden reads the threat the game client exposes, warns the player and records fights for later review.
The owner's other addons (Azeroth Accord, Finland Dragon Credit Points) share data inside a guild; a threat meter does
not need to: every client reads the threat of its own group from the game. The specification excludes external
services, accounts, backends and sending player data anywhere.

## Decision

1. The addon is **client-only and local-only**: no addon messages (`C_ChatInfo.SendAddonMessage`), no chat output by
   default, no web requests, no telemetry. AceComm is not embedded.
2. Recordings and settings live only in the SavedVariables of the player's computer and can be deleted from the
   interface.
3. Nothing is ever posted in party, raid or public chat automatically. A future "announce" feature, if the owner
   wants one, needs its own ADR and is off by default.

## Alternatives considered

- **Sharing threat between group members over addon messages**, as old threat meters did to reach mobs nobody
  targets. Unnecessary when the client exposes the group's threat, and it brings protocol, trust and lockdown problems.

## Consequences

- Positive: no protocol, no trust rules, no privacy risk outside the computer; the addon works alone.
- Negative: the addon sees only what the local client exposes; mobs no group member can query stay unknown
  ([SPEC-07](../specs/SPEC-07-multi-target-heatmap-profiles.md)).
