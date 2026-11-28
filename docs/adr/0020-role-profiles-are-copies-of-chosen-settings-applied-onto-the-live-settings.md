# 0020. Role profiles are copies of chosen settings, applied onto the live settings

- Status: Accepted (M8.1, before the M0 probe; to verify in M0: P9, whether the assigned role can be read)
- Date: 2026-11-28

## Context

M8 adds role profiles (the owner's specification §4.2 and §6.4: configurations for tanks, damage dealers and healers,
chosen from the assigned role when it can be detected, with copy and reset). Since M1 every module reads its settings
with `Config:Get("account.settings.…")` and every card writes them with `Config:Set`, which emits `CONFIG_CHANGED`;
about twenty modules and their tests rely on that. The plan said "schema 3, migration 2 → 3" for profiles before
M2–M7 used account schemas 2–6. Four questions had to be settled before the module is written:

1. **Where a module finds the value it uses.** Settings could be resolved through the active profile on every read
   (`Get` looks in the profile first), or the active profile could be written onto the settings the modules already
   read.
2. **What a profile holds.** All the settings, or only those that differ by role; the language, the theme, the window
   and the recording are a person's or a computer's choices, not a role's.
3. **Account or character.** One tank plays several characters; one character changes role between groups.
4. **When a profile changes.** A change in the middle of a fight would move the thresholds under the hysteresis of the
   states and under the thresholds recorded in the session.

## Decision

1. **Profiles are copies applied onto the live settings.** `account.profiles.tank`, `.healer` and `.damager` hold a
   value for each key of a fixed list, `Config.PROFILE_KEYS`, in the same shape as `settings`. Switching profile
   writes those values into `account.settings` with `Config:Set` (the thresholds with `Config:SetThresholds`), with a
   flag that stops the copy back, and emits one `PROFILE_CHANGED`. A change the player makes in a card is copied into
   the active profile when its `CONFIG_CHANGED` arrives. No other module knows that profiles exist.
2. **A fixed list of keys.** Thresholds, sort and *pin me on top*, the alert channels and their rules, the Coach, the
   other mobs and the heatmap. Language, look, palette, window, sampling rate, units, recording and the other mobs'
   limits stay outside. Three profiles only, named after the game's roles; no profile made by the player in M8.
3. **Profiles per account, choice per character.** The active profile, the automatic choice and the last role that
   chose a profile are `char.profile` (character schema 3); the profiles are in the account (account schema 7).
4. **Never in combat.** A switch asked in combat (by the role or by the player) waits for `COMBAT_ENDED`.
5. **The role is the one assigned to the player** (`UnitGroupRolesAssigned`), read on entering the world, on group
   and role changes and after combat; `NONE` or a secret role leaves the profile as it is; a manual choice holds until
   the assigned role changes. No role from the specialization (not probed).
6. **Upgrading changes nothing visible.** The account migration copies today's settings into all three profiles; a
   new installation starts from the presets (`Config.PRESETS`).

## Consequences

- No module, test or card that reads settings changes; `Data/Profiles.lua` is the only new reader and writer, and it
  is off behind the `profiles` switch until M8.R (the schemas and migrations are written even with it off).
- Settings are written twice (the live value and the profile's copy); the copy is a few dozen keys and only on a
  change, never in a tick.
- A setting outside `PROFILE_KEYS` is the same for every role; adding a key to a profile later is a migration and a
  line in the list.
- What the presets contain, and the alternatives (profiles of the player's own, the specialization's role), are open
  question Q28.
- See [SPEC-07 §4](../specs/SPEC-07-multi-target-heatmap-profiles.md#4-profili-e-preset-m82) and
  [SPEC-02 §3.11](../specs/SPEC-02-data-model-storage.md#311-schema-7-dellaccount-e-schema-3-del-personaggio-m8)
  (Italian).
