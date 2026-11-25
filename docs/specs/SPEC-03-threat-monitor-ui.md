# SPEC-03: Threat Monitor e interfaccia

> Fonte: [specifiche originali](source-specification.md) §5.1, §6. Da completare in **M1.1** (finestra, §4–§5) e
> **M2.1** (monitor, §1–§3), con l'esito del probe.

## 1. Cosa mostra il monitor

Per ogni unità osservata sul mob monitorato (di predefinito il target del giocatore; se non è un nemico, il target del
target):

| Campo | Categoria | Se manca |
|---|---|---|
| Nome del giocatore (colore di classe, icona del ruolo) | rilevata | `?` |
| Percentuale scalata (100 % = prende l'aggro) e barra | rilevata | barra vuota tratteggiata, "Unknown" |
| Margine rispetto al tank | calcolata | "—" |
| Stato SAFE / WARNING / DANGER / UNKNOWN | calcolata | UNKNOWN |
| Trend (freccia e valore) | stimata | nessuna freccia, "Insufficient data" |
| Tank attuale (chi ha `isTanking`) | rilevata | "Unknown tank" |
| Mob monitorato (nome, classificazione) | rilevata | "No target" |

- **MON-01** MUST: con dati segreti o assenti si vede UNKNOWN con il motivo nel tooltip, mai un numero.
- **MON-02** MUST: se l'API dà solo lo stato (`UnitThreatSituation`) e non i valori, il monitor mostra lo stato senza
  percentuale (modalità *state only*) e lo dice.
- **MON-03** SHOULD: indicatore di qualità dei dati nella barra del titolo: ultimo aggiornamento, percentuale di letture
  valide negli ultimi 10 s.

## 2. Stati e soglie

| Stato | Regola (predefinita provvisoria, Q7) |
|---|---|
| SAFE | `scaledPercent` < soglia WARNING |
| WARNING | soglia WARNING ≤ `scaledPercent` < soglia DANGER, oppure trend previsto oltre DANGER entro 3 s |
| DANGER | `scaledPercent` ≥ soglia DANGER, oppure situazione 2–3 per un non-tank |
| UNKNOWN | dati insufficienti, segreti o non disponibili |

- Soglie predefinite **provvisorie**: WARNING 80 %, DANGER 95 % (da tarare con le prove di M2, Q7).
- **MON-10** MUST: isteresi di 3 punti per non far lampeggiare lo stato attorno alla soglia.
- **MON-11** MUST: per il tank lo stato misura il **margine** sul secondo (`UnitThreatPercentageOfLead` o il massimo
  degli altri): poco margine = WARNING.

## 3. Ordinamenti

Per threat assoluta (se disponibile), percentuale rispetto al tank (predefinito), livello di rischio, variazione
recente. Il giocatore stesso è sempre evidenziato; opzione "fissa me in cima".

## 4. Finestra **[da completare in M1.1]**

Elementi (fonte §6.2): titolo e stato del modulo; target monitorato; stato sintetico; margine o percentuale; elenco dei
giocatori; trend; indicatore di qualità dei dati.

- Pannello compatto e ridimensionabile; si sposta, si blocca, si scala; posizione per personaggio.
- Nessun blocco dell'interfaccia di gioco; nessuna azione protetta in combattimento.
- Barra del titolo e schede nello stile dell'ecosistema ([ADR 0015](../adr/0015-interface-follows-the-ecosystem-style.md)):
  *Monitor*, *Reports* (da M4), *Settings*; Info e crediti in Settings.
- Modalità solo testo e solo icone dove utile; contrasto sufficiente; stato mai affidato al solo colore.
- Pulsante nel Compartment degli addon e icona della minimappa (LibDBIcon, nascondibile).

## 5. Comandi e configurazione

`/threatwarden` e `/atw`: `show`, `hide`, `lock`, `unlock`, `reset`, `debug`, `about`, `help` (M1); `demo` (M2);
`mute` (M3); `reports` (M4).

Configurazione (fonte §6.4): moduli accesi o spenti; dimensione e posizione; soglie; frequenza di aggiornamento; durata
e limite delle registrazioni; notifiche; profili per ruolo (M8); lingua (Q5); aspetto (tema, effetti, animazioni,
font); reset delle impostazioni.
