# Privacy and Data

*Italiano: [[Privacy e dati|Privacy-and-Data-it]]*

Azeroth Threatwarden works **only on your computer**.

- **No network.** The addon sends nothing: no addon messages to other players, no internet, no telemetry.
- **Nothing in chat.** It never posts in party, raid or public chat on its own.
- **What it keeps.** Your settings and, from version `v0.4.0`, the recordings of your fights (the threat samples, the
  events and the names of the group members in that fight, which the report needs). They are stored in the game's
  saved variables on your computer (`<WoW folder>/_forever_/WTF/Account/<account>/SavedVariables/`).
- **Limits.** Recordings have a limit you can change; the oldest are removed first.
- **Deleting.** You can delete one recording or all of them from the addon.
- **Exports** (from `v0.6.0`) are text you copy yourself; they can replace names with *Player 1, Player 2…*.

The rules behind this are in [ADR 0001](https://github.com/Finland6738/azeroth-threatwarden/blob/main/docs/adr/0001-local-only-addon-no-network.md).
