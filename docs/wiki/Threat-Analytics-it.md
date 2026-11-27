# Analytics della threat

*English: [[Threat Analytics|Threat-Analytics]]*

> **In arrivo con la `v0.6.0`**, non ancora pubblicata e non verificata in gioco. Nella versione attuale questa parte è
> spenta: non se ne vede nulla.

Analytics descrive gli scontri registrati con numeri che si possono controllare: una card in ogni
[[report|Combat-Reports-it]] e una pagina che confronta gli scontri contro lo stesso nemico. Legge soltanto le
registrazioni: non salva nulla e nulla esce dal tuo computer. Non fa classifiche di persone, non giudica nessuno e non
dice che le cose stanno migliorando o peggiorando.

![La pagina Analytics: i nemici e un confronto in una finestra stretta, con le ultime colonne fuori](../specs/mockups/previews/analytics-overview-nebula.webp)

![Un confronto di scontri: la riga Tutti gli scontri, Dati insufficienti e Non confrontabile](../specs/mockups/previews/analytics-compare-nebula.webp)

![La card Analytics del report, con gli intervalli instabili e il collegamento al confronto](../specs/mockups/previews/report-analytics-nebula.webp)

*Anteprime di progetto, non screenshot: disegnate dall'impaginazione e dai testi dell'addon con scontri inventati,
perché l'addon non è ancora stato provato in gioco
([tutte le anteprime](https://github.com/Finland6738/azeroth-threatwarden/blob/main/docs/specs/mockups/previews/README.md)).*

## Dove si trova

Nella scheda **Report**, in alto, c'è il selettore *Registrazioni · Analytics*. *Registrazioni* è l'elenco con i report;
*Analytics* è la pagina descritta sotto. La scheda ricorda la scelta fino al prossimo `/reload`; `/atw reports` apre
*Registrazioni*.

## La card di un report

Viene dopo la card *Timeline* ed è calcolata dopo il report.

| Riga | Che cosa significa |
|---|---|
| Campioni leggibili | quante letture avevano un valore, solo uno stato o nulla, e per quanto del combattimento il nemico è stato monitorato |
| Superamenti di soglia | salite in Attenzione e in Pericolo di ogni unità con dati sufficienti |
| Tempo con un'unità in Attenzione o Pericolo | tempo con almeno un'unità in quegli stati, e in Pericolo |
| Cambi di chi tiene il nemico | un'altra unità ha preso il nemico da chi lo teneva: da tank a tank, a un non tank, di nuovo a un tank (il primo a tenerlo in un pull non è un cambio) |
| Preso da un non tank | quante volte un'unità non trattata da tank ha preso il nemico |
| Intervalli instabili | tratti con almeno 3 cambi di stato o di chi tiene il nemico entro 10 s; i primi tre sono elencati e un clic ne apre il replay |
| Situazioni di rischio | salite in Pericolo più le prese di un non tank, per minuto di combattimento noto |
| Più vicino al tank | la percentuale più alta di un'unità che non teneva il nemico |
| Confronta con … | apre la pagina sugli altri scontri contro questo nemico |

Dove il report ha già il valore, è lo stesso numero. Se nulla era leggibile la card ha solo i campioni leggibili e una
nota.

## Le categorie e i valori mancanti

Ogni valore ha la sua categoria: *rilevato* (letto o contato), *calcolato* (derivato), *stimato* (*almeno*, o *~* per
una mediana: mancava parte dei dati). La tabella le segna con una lettera (**R**, **C**, **S**) e passando il mouse su
un valore si leggono categoria, motivo e base (le soglie o gli stati del gioco).

- **Dati insufficienti**: con meno di **metà** dei campioni leggibili, o con il nemico monitorato per meno di metà del
  combattimento, Analytics non dà un numero, perché ingannerebbe. Il report può ancora mostrare un limite inferiore.
- **Non disponibile**: il gioco non l'ha mai dato (le percentuali quando si legge solo lo stato).
- **Non confrontabile**: nel confronto, lo scontro non ha la stessa base (altre soglie o stati del gioco) o, per le tue
  colonne, il tuo ruolo.

## Confrontare gli scontri

La card **Nemici** elenca ogni nemico registrato, il più recente per primo, con il numero di scontri, il tempo in
combattimento, l'ultima data e i campioni leggibili. Gli scontri contro un nemico sconosciuto sono raggruppati e non si
possono confrontare. Clicca un nemico per confrontare i suoi scontri:

- solo scontri contro **quel nemico**, al più i 20 più recenti;
- di predefinito con lo stesso **gruppo**, la stessa **difficoltà** e lo stesso **ruolo** del più recente (spegni un
  filtro per includerne altri);
- la prima riga, **Tutti gli scontri**, mostra le mediane (il rischio è su tutti gli scontri); passando il mouse su un
  valore si leggono mediana, totale, minimo e massimo con la data. Gli aggregati chiedono almeno 2 scontri
  confrontabili (*Un solo scontro confrontabile*);
- una riga per scontro, il più recente per primo; un clic apre il suo report. Una registrazione danneggiata ha una riga
  che non conta;
- in una finestra stretta le ultime colonne spariscono e restano nel suggerimento della riga.

Il confronto si calcola uno scontro alla volta e **si ferma durante il combattimento**. Una registrazione eliminata ne
esce; per quelle nuove compare il pulsante **Aggiorna**.

L'esportazione da copiare (testo o CSV) arriva con un passo successivo della stessa versione.
