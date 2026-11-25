# Privacy e dati

*English: [[Privacy and Data|Privacy-and-Data]]*

Azeroth Threatwarden funziona **solo sul tuo computer**.

- **Niente rete.** L'addon non invia nulla: nessun messaggio ad altri giocatori, niente internet, nessuna telemetria.
- **Niente in chat.** Non scrive mai da solo nella chat del gruppo, del raid o pubblica.
- **Cosa conserva.** Le tue impostazioni e, dalla versione `v0.4.0`, le registrazioni dei combattimenti (i campioni di
  threat, gli eventi e i nomi dei membri del gruppo in quello scontro, che servono al report). Stanno nelle variabili
  salvate del gioco sul tuo computer (`<WoW folder>/_forever_/WTF/Account/<account>/SavedVariables/`).
- **Limiti.** Le registrazioni hanno un limite che puoi cambiare; le più vecchie si eliminano per prime.
- **Cancellare.** Puoi eliminare una registrazione o tutte dall'addon.
- **Le esportazioni** (dalla `v0.6.0`) sono testo che copi tu; possono sostituire i nomi con *Player 1, Player 2…*.

Le regole sono nell'[ADR 0001](https://github.com/Finland6738/azeroth-threatwarden/blob/main/docs/adr/0001-local-only-addon-no-network.md) (in inglese).
