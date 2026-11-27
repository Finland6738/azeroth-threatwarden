# Comandi

*English: [[Commands|Commands]]*

Scrivi un comando nella casella della chat del gioco. `/atw` e `/threatwarden` sono lo stesso comando. Le risposte
compaiono solo nella tua finestra di chat, nella lingua dell'addon; nulla viene mai scritto agli altri giocatori.

| Comando | Cosa fa |
|---|---|
| `/atw` | mostra o nasconde la finestra |
| `/atw show` | mostra la finestra |
| `/atw hide` | nasconde la finestra |
| `/atw lock` | blocca la finestra: non si sposta né si ridimensiona |
| `/atw unlock` | sblocca la finestra |
| `/atw reset` | riporta posizione, dimensioni e scala della finestra ai valori predefiniti e la mostra al centro |
| `/atw settings` | apre la pagina [Impostazioni](Settings-it) |
| `/atw about` | apre la pagina [Info](About-it) |
| `/atw debug` | apre il [rapporto diagnostico](Reporting-Bugs-and-Feedback-it), pronto da copiare (sempre in inglese) |
| `/atw help` | elenca i comandi |
| `/atw demo` | avvia la [modalità demo](Threat-Monitor-it#modalità-demo), uno scontro inventato (scritto di nuovo, la chiude) |
| `/atw demo stop` | chiude la modalità demo (anche `/atw demo off`) |
| `/atw mute` | silenzia gli [avvisi](Alerts-and-Coach-it#silenziare) fino alla fine di questo combattimento, o del prossimo; scritto di nuovo li riaccende |
| `/atw reports` | apre la [scheda Report](Combat-Reports-it) |
| `/atw replay` | apre il [Replay della threat](Threat-Replay-it) dell'ultimo scontro finito |
| `/atw replay 2` | il replay del secondo scontro dell'elenco (1 è il più recente) |
| `/atw focus` | dalla `v0.7.0`: apre l'elenco del [Dungeon Focus](Dungeon-Focus-it) (scritto di nuovo, lo chiude); lo dice quando non ci sono altri mob o la parte è spenta nelle Impostazioni |

Prima della loro versione, `/atw reports`, `/atw replay` e `/atw focus` rispondono con la versione che li porterà.

## Assegnazione di un tasto

Le assegnazioni dei tasti del gioco hanno **Silenzia gli avvisi** sotto *Azeroth Threatwarden* (nella
categoria degli addon), senza tasto predefinito: fa quello che fa `/atw mute`. Il nome è nella lingua del gioco.

## La finestra

- Si apre al primo accesso; poi resta aperta o chiusa come l'hai lasciata, per ogni personaggio. Può
  anche aprirsi e chiudersi da sola ([quando si mostra la finestra](Settings-it#monitor)).
- Si **sposta** trascinando la barra del titolo e si **ridimensiona** dall'angolo tratteggiato in basso a destra. Il
  lucchetto nella barra del titolo blocca entrambe le cose.
- La scheda **Monitor** è piccola, per stare sopra il gioco; **Impostazioni** è più grande. Ognuna ricorda la propria
  dimensione.
- La pastiglia nella barra del titolo dice cosa sta facendo il
  [monitor della threat](Threat-Monitor-it#il-piede-e-la-barra-del-titolo): *In attesa*, *In diretta*, *Solo stato*,
  *Non disponibile* o *Demo*.
- `Esc` la chiude. Si mostra, si nasconde, si sposta e si ridimensiona anche in combattimento.

## Pulsante della minimappa e Addon Compartment

Il pulsante sulla minimappa e la voce nell'Addon Compartment del gioco (se il tuo client lo ha) funzionano allo stesso
modo: **clic sinistro** mostra o nasconde la finestra, **clic destro** apre le Impostazioni. Trascina il pulsante per
spostarlo attorno alla minimappa.
