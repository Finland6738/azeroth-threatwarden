# Impostazioni

*English: [[Settings|Settings]]*

Si aprono con `/atw settings`, con un clic destro sul pulsante della minimappa o dalla scheda **Impostazioni** della
finestra. La stessa pagina è nella finestra delle impostazioni del gioco, in *Opzioni → AddOns → Azeroth
Threatwarden*, se il tuo client lo permette. Una modifica fatta in un posto si vede nell'altro, e ogni modifica viene
salvata subito. Si applica **subito**, tranne il carattere (completo dopo il riavvio del gioco) e la lingua (dopo aver
ricaricato l'interfaccia). La pagina si scorre con la rotella del mouse.

![La pagina Impostazioni, tema Nebula: la parte alta e la pagina scorsa in basso](../specs/mockups/previews/settings-nebula.webp)

![La pagina Impostazioni in italiano, tema Warden](../specs/mockups/previews/settings-warden-it.webp)

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

## Ripristino

**Ripristina impostazioni** riporta ai valori predefiniti l'aspetto, la lingua e il pulsante della minimappa, ed
elimina i dati danneggiati che l'addon aveva messo da parte per le segnalazioni. Chiede
un secondo clic entro pochi secondi. Le registrazioni (di una versione futura) non vengono toccate; la posizione della
finestra si ripristina con *Ripristina finestra*.

## Dati in sola lettura

Se i dati salvati vengono da una versione più recente dell'addon (o non si sono potuti aggiornare), la pagina lo dice:
l'addon funziona, ma le modifiche non vengono salvate ([[Privacy e dati|Privacy-and-Data-it]]).
