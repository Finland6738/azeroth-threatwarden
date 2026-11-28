# Monitor della threat

*English: [[Threat Monitor|Threat-Monitor]]*

> **Nuovo nella `v0.2.0`, non verificato in gioco.** Quali dati di threat WoW Forever dia davvero a un addon è ancora
> da verificare (la sonda M0 e le verifiche in gioco sono aperte), perciò il monitor è fatto per ogni risposta: valori,
> *solo stato* o sconosciuto, con il motivo. Soglie e frequenza di lettura sono provvisorie.

La scheda **Monitor** mostra chi minaccia il nemico che stai combattendo. Legge il gioco quando sei in combattimento,
c'è un nemico monitorato e la finestra è aperta su questa scheda. Di base la finestra si apre da sola quando inizia un
combattimento o entri in un gruppo ([quando si mostra la finestra](Settings-it#monitor)); soglie, frequenza, ordine e il
resto sono nella [card Monitor delle Impostazioni](Settings-it#monitor).

![Il monitor con i valori di threat: un DPS in ATTENZIONE, uno in PERICOLO](../specs/mockups/previews/monitor-values-nebula.webp)

## L'intestazione

- Il **nemico**: quello che selezioni o, se selezioni un alleato (un guaritore che seleziona il tank), il bersaglio
  dell'alleato. Il tipo (*Élite*, *Raro*, *Boss*) è scritto accanto al nome.
- Il **tuo stato**, con un'icona e una parola.
- **Tank**: chi tiene il nemico. Se non lo tiene nessuno del gruppo leggi *(non in elenco)* dopo il nome, e *Tank
  sconosciuto* quando nulla di leggibile dice chi sia.
- **Margine**: per un DPS o un guaritore, quanto sei lontano dal 100 % (prendere l'aggro); per il tank, quanto il
  secondo è lontano dal 100 %.

Dalla `v0.3.0` sotto l'intestazione c'è una striscia con [[avvisi e consigli|Alerts-and-Coach-it]]. Dalla `v0.7.0`
(non verificato in gioco), in un pull con più mob una barra sotto l'intestazione apre il [[Dungeon Focus|Dungeon-Focus-it]],
e una puntina accanto al nome segna un mob che hai scelto di seguire dal suo elenco.

## L'elenco

Una riga per ogni unità nella lista della threat del nemico (tu, il tuo famiglio, il gruppo o l'incursione):

| Parte della riga | Significato |
|---|---|
| Striscia a sinistra, distintivo a destra | lo stato: **Sicuro**, **Attenzione**, **Pericolo** o **Sconosciuto**, sempre con icona e parola |
| Icona del ruolo, icona dello scudo | il ruolo assegnato; lo scudo indica chi tiene il nemico |
| Nome | il colore di classe (la tua riga ha un contorno) |
| Barra e numero | la threat scalata: 100 % significa prendere l'aggro. Le tacche sono le soglie Attenzione (82 %) e Pericolo (91 %), o le tue |
| Freccia | la tendenza degli ultimi secondi (una *stima*); `~2 s` significa *potrebbe prendere l'aggro fra circa 2 s* (una *previsione*) |
| `?` e barra tratteggiata | sconosciuto: passa sulla riga per leggere il motivo |
| `—` senza barra | *solo stato*: il gioco dà lo stato ma nasconde i numeri |

Passa il mouse su una riga per vedere ogni valore con la sua categoria (*rilevato*, *calcolato*, *stimato*,
*previsto*) e, per ciò che manca, il motivo (*Valore segreto*, *Non disponibile*, *Dati insufficienti*, *Dato
vecchio*). Una finestra stretta toglie l'icona del ruolo, la tendenza e la barra prima delle parole.

Clicca **Ordine** per cambiarlo: *Percentuale*, *Threat assoluta* (solo dove il gioco la dà), *Rischio*, *Variazione
recente*. Le righe sconosciute sono sempre in fondo. **Io in cima** tiene la tua riga per prima. L'ordine cambia al
massimo una volta al secondo, e subito quando qualcuno entra in Pericolo. Entrambe le scelte vengono salvate. Quando l'elenco non ci sta, l'ultima riga dice *+N
altri* e la tua resta visibile.

![La vista del tank, con il margine sul secondo](../specs/mockups/previews/monitor-tank-warden.webp)

## Gli stati

| Stato | Per un DPS o un guaritore | Per il tank che tiene il nemico |
|---|---|---|
| **Sicuro** | sotto l'82 % | il secondo è sotto l'82 % |
| **Attenzione** | dall'82 %, o si prevede che arrivi al 91 % entro 3 s | il secondo è dall'82 % |
| **Pericolo** | dal 91 %, o tiene il nemico | il secondo è dal 91 %, o ha più threat |
| **Sconosciuto** | il gioco non dà nulla di leggibile, o il dato è vecchio | lo stesso |

Le soglie vengono dal gioco: dall'**82 %** chi fa danni o cura rallenta (meno lanci, meno danni o cure, o incantesimi
di rank più basso), dal **91 %** smette per un attimo di fare danni o di curare; gli
[[avvisi e il Coach|Alerts-and-Coach-it]] lo dicono. Le puoi cambiare nelle [Impostazioni](Settings-it#monitor); se non
le avevi mai cambiate, i vecchi 80 % e 95 % sono diventati 82 % e 91 % con questa versione, mentre le soglie scelte da
te restano tue. Uno stato sale subito e scende solo dopo un secondo, così non lampeggia.

## La heatmap

> **In arrivo nella `v0.8.0`**: costruita e provata offline, spenta in questa versione, non verificata in gioco.

![La heatmap delle righe: una tinta di ogni stato, più forte vicino al successivo](../specs/mockups/previews/monitor-heat-nebula.webp)

**Le righe.** Ogni riga prende una tinta leggera del suo stato dietro nome, barra e distintivo, più forte man mano che
si avvicina allo stato successivo. Ripete soltanto ciò che dice il distintivo: icona e parola restano, e una riga in
stato **Sconosciuto** non ha alcuna tinta.

| Tinta | Quando |
|---|---|
| nessuna | Sconosciuto; Sicuro sotto il 50 % (per il tank che tiene il nemico: il secondo sotto il 50 %); Sicuro quando il gioco dà solo gli stati |
| leggerissima | Sicuro dal 50 % |
| leggera | Attenzione sotto la metà fra le due soglie (86,5 % con 82 e 91), o quando il gioco dà solo gli stati |
| media | Attenzione da quella metà |
| forte | Pericolo, e la riga di chi tiene il nemico senza essere un tank |

Una riga cambia tinta al più una volta al secondo finché il suo stato resta lo stesso, e un confine ha 2 punti di
margine, così la tinta non tremola; un cambio di stato (il Pericolo prima di tutto) la cambia subito. Il cambio sfuma in
120 ms con le animazioni attive; non lampeggia mai. Il testo resta leggibile sulla tinta più forte in ogni tema. Le
righe del [[Dungeon Focus|Dungeon-Focus-it]] non hanno tinta. Anche la [demo](#modalità-demo) la mostra.

**I riquadri del raid del gioco (spenti di predefinito).** Con *Segna i riquadri del raid del gioco* acceso, l'addon
disegna un **segno** sopra i riquadri del gruppo e del raid del gioco (i *Compact Raid Frames*) di chi è in
**Attenzione** o **Pericolo**, o tiene il nemico senza essere un tank: un bordo del colore del suo stato e un piccolo
distintivo con icona e parola sul lato alto. Sicuro e Sconosciuto non hanno nulla. I segni non prendono mai il mouse:
clic, menu e clic con incantesimo restano del gioco. Nella demo non si mostrano.

Come resta fuori dai piedi del gioco: i segni stanno in un frame separato dell'addon sopra lo schermo. L'addon non
cambia, non aggancia e non attacca nulla ai riquadri del gioco: fuori dal combattimento ne **legge** soltanto la
posizione e di chi sono, e la copia. In combattimento le posizioni restano quelle copiate; se il gruppo cambia durante
un combattimento (qualcuno entra, esce o si sposta) i riquadri possono essersi mossi, quindi **tutti i segni si
nascondono fino alla fine del combattimento**. I riquadri di altri addon che sostituiscono quelli del gioco non hanno
segni.

> **Il rischio, detto com'è.** I riquadri del raid del gioco sono codice protetto. Un addon che ci scrive dentro può far
> bloccare al gioco un'azione ("*azione bloccata da un addon*") o rompere i riquadri in combattimento; questo li legge
> soltanto e non dovrebbe, ma **non è ancora stato provato in gioco**. Se il gioco segnala un problema con un addon
> mentre i segni sono accesi, **spegnili**: [Impostazioni → Heatmap](Settings-it#heatmap) → *Segna i riquadri del raid
> del gioco*. `/atw debug` (sezione *Heatmap*) conta le azioni bloccate o vietate viste mentre i segni sono accesi;
> mettila in una [[segnalazione|Reporting-Bugs-and-Feedback-it]]. Se il gioco dà la colpa ai segni anche una sola
> volta, l'opzione sarà tolta e la tinta delle righe resta.

## Quando il gioco nasconde i numeri

![Solo stato: stati senza percentuali](../specs/mockups/previews/monitor-state-nebula.webp)

In modalità **solo stato** il gioco dice chi tiene il nemico e lo stato di ognuno, ma nessun numero: niente barre,
margine o tendenza, e il piede dice *Solo stato*.

![Dati di threat non disponibili](../specs/mockups/previews/monitor-unknown-warden.webp)

Quando nulla è leggibile vedi **Dati di threat non disponibili** con il motivo: mai un numero inventato, mai una barra
vuota che sembri 0 %.

## Prima e dopo un combattimento

![Nessun bersaglio](../specs/mockups/previews/monitor-no-target-nebula.webp)

Senza un nemico la finestra dice *Nessun bersaglio*. Fuori dal combattimento dice *Non in combattimento*; alla fine di
un combattimento le ultime righe restano, segnate come vecchie, sotto *Combattimento finito*. Un nemico morto o
scomparso mostra *Bersaglio morto* o *Bersaglio perso*.

## Modalità demo

Scrivi `/atw demo`, o premi **Avvia la demo** nella card Monitor delle Impostazioni, per guardare uno scontro inventato
senza essere in uno vero: un *Golem della demo*, un tank, un guaritore e un DPS inventati, e tu. Compaiono a turno
Attenzione, Pericolo, un tank che perde il nemico e lo riprende e le previsioni, poi lo scontro ricomincia. Serve a
vedere com'è il monitor e a provare le impostazioni.

![Modalità demo: uno scontro inventato, dichiarato tale](../specs/mockups/previews/monitor-demo-nebula.webp)

- La pastiglia dice **Demo**, il piede *DEMO · scontro inventato, non il gioco* e i tooltip dicono che i valori sono
  inventati.
- Nulla è letto dal gioco e la demo non salva nulla. Ciò che cambi nel frattempo (un'impostazione, l'ordine
  dell'elenco, il posto della finestra) viene salvato come sempre.
- Finisce con `/atw demo stop` (o di nuovo `/atw demo`), quando chiudi la finestra e **da sola appena inizia un
  combattimento vero**. Non può partire in combattimento e non sopravvive a una ricarica.

## Il piede e la barra del titolo

Il piede dice quanto sono vecchi i dati e quante letture degli ultimi 10 s erano utilizzabili. La pastiglia nella barra
del titolo dice *In attesa*, *In diretta*, *Solo stato*, *Non disponibile* o *Demo*.

L'interfaccia è in italiano e in inglese:

![Il monitor in italiano, tema Aurora](../specs/mockups/previews/monitor-values-aurora-it.webp)

![Modalità demo in italiano, tema Warden](../specs/mockups/previews/monitor-demo-warden-it.webp)

*Anteprime di progetto, non screenshot: disegnate dal layout e dai testi dell'addon, con un combattimento inventato, perché l'addon non è ancora stato provato in gioco ([tutte le anteprime](https://github.com/Finland6738/azeroth-threatwarden/blob/main/docs/specs/mockups/previews/README.md)).*
