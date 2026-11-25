# Impostazioni

*English: [[Settings|Settings]]*

Si aprono con `/atw settings`, con un clic destro sul pulsante della minimappa o dalla scheda **Impostazioni** della
finestra. La stessa pagina è nella finestra delle impostazioni del gioco, in *Opzioni → AddOns → Azeroth
Threatwarden*, se il tuo client lo permette. Una modifica fatta in un posto si vede nell'altro, e ogni modifica viene
salvata subito. Si applica **subito**, tranne il carattere (completo dopo il riavvio del gioco) e la lingua (dopo aver
ricaricato l'interfaccia). La pagina si scorre con la rotella del mouse.

![La pagina Impostazioni, tema Nebula: la parte alta e la pagina scorsa in basso](../specs/mockups/previews/settings-nebula.webp)

![La pagina Impostazioni in italiano, tema Warden](../specs/mockups/previews/settings-warden-it.webp)

![La card Monitor in italiano, tema Warden](../specs/mockups/previews/settings-monitor-warden-it.webp)

*Anteprime di progetto, non screenshot: disegnate dal layout e dai testi dell'addon, perché l'addon non è ancora stato provato in gioco ([tutte le anteprime](https://github.com/Finland6738/azeroth-threatwarden/blob/main/docs/specs/mockups/previews/README.md)).*

## Aspetto

Salvato per tutto l'account.

| Opzione | Scelte | Predefinito |
|---|---|---|
| Tema | **Nebula** (scuro, viola e arancio), **Aurora** (chiaro, blu e verde acqua), **Warden** (scuro, dai colori del logo) | Nebula |
| Effetti neon | sì / no: bagliori e ombre; spenti danno un aspetto piatto | sì |
| Animazioni | sì / no: dissolvenze e scorrimenti; spente rendono ogni cambio immediato | sì |
| Carattere | **Dell'addon** (Orbitron, Outfit, JetBrains Mono) o **Del gioco** | Dell'addon |

Il cambio di **carattere** è completo solo dopo il **riavvio del gioco**: il gioco legge i nuovi file dei caratteri
solo quando parte. I colori degli stati della threat non cambiano con il tema.

## Lingua

**Automatica** (segue la lingua del gioco: inglese, o italiano in un client italiano), **English** o **Italiano**. Il
cambio vale dopo aver ricaricato l'interfaccia: premi **Ricarica ora** (è attivo solo se la scelta è diversa dalla
lingua a schermo) o scrivi `/reload`.

## Finestra

Salvata per personaggio, tranne il pulsante della minimappa (tutto l'account).

| Opzione | Cosa fa | Predefinito |
|---|---|---|
| Blocca la finestra | la finestra non si sposta né si ridimensiona (anche il lucchetto nella barra del titolo, `/atw lock`) | no |
| Scala della finestra | dal 50 % al 200 %, a passi del 5 %; si applica quando rilasci il cursore | 100 % |
| Mostra il pulsante sulla minimappa | mostra o nasconde il pulsante | sì |
| Ripristina finestra | posizione, dimensioni e scala predefinite, finestra al centro (come `/atw reset`) | — |

## Monitor

Salvato per tutto l'account. Ogni modifica si applica subito, anche a una
[demo](Threat-Monitor-it#modalità-demo) o a un combattimento in corso.

![La card Monitor delle Impostazioni, tema Nebula: la parte alta e la pagina scorsa in basso](../specs/mockups/previews/settings-monitor-nebula.webp)

| Opzione | Cosa fa | Scelte | Predefinito |
|---|---|---|---|
| Soglia di attenzione | da questa quota della threat che prende il nemico una riga dice **Attenzione** | dal 50 % al 95 % | 80 % |
| Soglia di pericolo | da questa quota, **Pericolo** | dal 60 % al 100 % | 95 % |
| Letture al secondo | ogni quanto si legge la threat in combattimento: una frequenza più alta reagisce prima e costa di più | da 2 a 10 Hz | 5 Hz |
| Unità per lettura | quante unità si leggono ogni volta; in un gruppo più grande le altre si leggono a turno (tu, il famiglio, i tank e chi tiene il nemico ogni volta) | da 5 a 40 | 40 |
| Quando si mostra la finestra | vedi sotto | In gruppo o in lotta, Sempre, A mano | In gruppo o in lotta |
| Ordine dell'elenco | *Percentuale*, *Threat assoluta*, *Rischio*, *Variazione recente* (anche il pulsante **Ordine** dell'elenco) | | Percentuale |
| Tienimi in cima | la tua riga viene per prima (anche **Io in cima** nell'elenco) | sì / no | no |
| Segui il bersaglio di un alleato | con un alleato selezionato (il tank), il monitor mostra il nemico che ha come bersaglio | sì / no | sì |
| Avvia la demo | uno scontro inventato, per provare queste impostazioni ([modalità demo](Threat-Monitor-it#modalità-demo)) | pulsante | |

Pericolo resta almeno 5 punti sopra Attenzione: spostando un cursore l'altro si sposta di conseguenza. Soglie,
frequenza e numero di unità sono provvisori finché non vengono tarati in gioco.

**Quando si mostra la finestra:**

- **In gruppo o in lotta**: la finestra si apre da sola, sulla scheda Monitor, quando inizia un combattimento e quando
  entri in un gruppo. Fuori da un gruppo si chiude da sola 10 secondi dopo un combattimento, salvo che tu l'abbia
  riaperta o sia passato a un'altra scheda. Se la chiudi durante un combattimento, resta chiusa fino al successivo. Al
  login è come l'hai lasciata (e aperta se sei in un gruppo).
- **Sempre**: si mostra a ogni accesso e a ogni ricarica; la chiudi solo tu.
- **A mano**: resta aperta o chiusa come la lasci.

Le aperture e chiusure automatiche non cambiano mai la tua scelta a mano.

## Ripristino

**Ripristina impostazioni** riporta ai valori predefiniti l'aspetto, la lingua, il pulsante della minimappa e le impostazioni del monitor, ed
elimina i dati danneggiati che l'addon aveva messo da parte per le segnalazioni. Chiede
un secondo clic entro pochi secondi. Le registrazioni (di una versione futura) non vengono toccate; la posizione della
finestra si ripristina con *Ripristina finestra*.

## Dati in sola lettura

Se i dati salvati vengono da una versione più recente dell'addon (o non si sono potuti aggiornare), la pagina lo dice:
l'addon funziona, ma le modifiche non vengono salvate ([[Privacy e dati|Privacy-and-Data-it]]).
