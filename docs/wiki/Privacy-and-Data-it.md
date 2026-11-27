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
- **Le esportazioni** (dalla `v0.6.0`) sono l'unico modo in cui qualcosa esce dal gioco, e solo per mano tua: un
  testo in una casella che copi con Ctrl+C. L'addon non scrive file, non tocca gli appunti e non pubblica né invia
  nulla. Un testo può contenere i **nomi del tuo gruppo** (uno scontro, i suoi eventi e le sue letture), i nomi dei
  nemici e delle zone, classi, ruoli, date e i numeri registrati. Non contiene mai identificativi dei personaggi
  (GUID), le tue impostazioni o il rapporto diagnostico. La casella avvisa dei nomi, e *Sostituisci i nomi con
  Giocatore 1, Giocatore 2…* scrive invece *Tu*, *Giocatore 1*, *Famiglio 1*…; i nomi dei nemici e della zona, le
  classi e i ruoli restano. Vedi [[Analytics della threat|Threat-Analytics-it]].

Le regole sono nell'[ADR 0001](https://github.com/Finland6738/azeroth-threatwarden/blob/main/docs/adr/0001-local-only-addon-no-network.md) (in inglese).
