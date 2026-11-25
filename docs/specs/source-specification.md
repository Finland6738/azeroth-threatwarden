<!-- The owner's original specification (2026-11-25), kept verbatim as the source of truth on WHAT the addon does. The SPEC-NN files refine it; where they differ, the SPEC file and its ADR record why. -->

# Azeroth Threatwarden

## Specifiche funzionali e tecniche

**Documento:** Product & Technical Specification\
**Stato:** Bozza iniziale --- da validare sul client effettivo di WoW
Forever\
**Nome prodotto:** Azeroth Threatwarden\
**Categoria:** Threat monitoring, threat coaching e combat analysis\
**Lingua del documento:** Italiano

------------------------------------------------------------------------

## 1. Visione del prodotto

Azeroth Threatwarden è un addon per World of Warcraft Forever che aiuta
i giocatori a comprendere, monitorare e gestire la threat durante
combattimenti, dungeon e raid.

Non deve essere un semplice clone di Omen. Il suo valore distintivo è
trasformare i dati di threat in informazioni operative:

-   mostrare chi sta generando threat e su quale unità;
-   avvisare prima che un giocatore rischi di attirare l'aggro;
-   spiegare, quando i dati lo consentono, come si è verificata una
    perdita di aggro;
-   registrare gli scontri per analizzare gli eventi dopo il
    combattimento;
-   produrre report comprensibili per DPS, tank e raid leader.

**Principio guida:** mostrare chiaramente ciò che è noto, distinguendolo
da stime, previsioni e ipotesi.

### 1.1 Promessa del prodotto

> Know your threat. Understand your mistakes. Prevent aggro loss.

### 1.2 Pubblico di riferimento

-   Tank che vogliono monitorare la stabilità della threat.
-   DPS che vogliono evitare di superare il tank.
-   Healer e support che desiderano comprendere i cambi di target.
-   Raid leader e officer che analizzano wipe e problemi ricorrenti.
-   Giocatori di dungeon con pull multipli.

### 1.3 Piattaforma e compatibilità

La piattaforma di destinazione è **WoW Forever**. La versione esatta del
client/API deve essere confermata prima di implementare le funzionalità
dipendenti dalle API.

Non assumere automaticamente compatibilità con Retail, Classic Era,
Vanilla 1.12, TBC 2.4.3 o WotLK 3.3.5a. La versione effettiva, le API
disponibili e le eventuali modifiche del server devono essere verificate
direttamente nell'ambiente di destinazione.

------------------------------------------------------------------------

## 2. Obiettivi e non-obiettivi

### 2.1 Obiettivi

1.  Fornire un monitoraggio threat live leggibile e configurabile.
2.  Evidenziare il rischio di aggro loss con soglie e avvisi
    contestuali.
3.  Registrare campioni ed eventi durante il combattimento.
4.  Consentire la revisione degli scontri e delle situazioni di aggro
    loss.
5.  Generare statistiche utili senza attribuire cause non dimostrate.
6.  Mantenere un'interfaccia leggera, leggibile e adatta al
    combattimento.
7.  Essere compatibile con il client specifico di WoW Forever, senza
    dipendenze da API non verificate.

### 2.2 Non-obiettivi della prima versione

-   Sostituire un combat log completo.
-   Ricostruire con certezza ogni singolo punto di threat se il client
    non espone i dati necessari.
-   Fornire rotazioni o consigli di classe completi.
-   Analizzare automaticamente ogni meccanica di ogni boss.
-   Richiedere un servizio esterno, account o backend.
-   Inviare dati dei giocatori a server remoti.
-   Replicare tutte le funzioni di WeakAuras.

------------------------------------------------------------------------

## 3. Principi di affidabilità dei dati

Questa sezione è vincolante per tutte le funzionalità.

Ogni informazione mostrata deve appartenere a una delle seguenti
categorie:

  -----------------------------------------------------------------------
  Categoria               Significato             Esempio
  ----------------------- ----------------------- -----------------------
  Rilevata                Ottenuta direttamente   Il target corrente è il
                          da API/evento           boss
                          disponibile             

  Calcolata               Derivata da dati        Percentuale rispetto al
                          rilevati                tank

  Stimata                 Approssimazione basata  Trend di threat negli
                          su campioni incompleti  ultimi secondi

  Prevista                Proiezione del trend,   Possibile superamento
                          non certezza            tra 3 secondi

  Ipotesi                 Interpretazione non     Burst probabilmente
                          dimostrabile            associato all'aumento
  -----------------------------------------------------------------------

Non presentare mai una stima o un'ipotesi come dato certo.

Se una funzione non è supportata dal client o i dati sono incompleti,
mostrare uno stato esplicito come **Non disponibile**, **Dati
insufficienti** o **Stima**. Non inventare valori.

------------------------------------------------------------------------

## 4. Funzionalità e priorità

### 4.1 MVP --- prima release pubblica

La prima versione pubblica deve concentrarsi su un nucleo piccolo ma
affidabile:

-   Threat tracking sul target selezionato.
-   Identificazione del tank e dei membri del gruppo/raid, nei limiti
    delle API.
-   Percentuale relativa e stato di rischio, se calcolabili.
-   Avvisi configurabili.
-   Registrazione locale dei campioni durante il combattimento.
-   Report essenziale a fine combattimento.
-   Opzioni per bloccare, spostare, ridimensionare e configurare la
    finestra.
-   Diagnostica per verificare quali API e dati sono disponibili.

### 4.2 Release successive

  Modulo                         Priorità   Descrizione
  ------------------------------ ---------- -------------------------------------------
  Threat Timeline                Alta       Evoluzione temporale della threat
  Threat Replay                  Alta       Revisione degli eventi registrati
  Threat Analytics               Alta       Statistiche aggregate per scontro
  Threat Coach                   Alta       Suggerimenti contestuali basati su regole
  Multi-target / Dungeon Focus   Media      Monitoraggio di più mob
  Heatmap                        Bassa      Evidenziazione visuale su frame o unità
  Export report                  Media      Esportazione testuale/CSV, se supportata
  Profili e preset               Media      Configurazioni per tank, DPS e healer

------------------------------------------------------------------------

## 5. Specifiche funzionali

### 5.1 Threat Monitor

**Scopo:** mostrare lo stato della threat durante il combattimento.

Informazioni desiderate per ogni unità:

-   Nome del giocatore.
-   Valore o percentuale di threat, se disponibile.
-   Stato rispetto al tank.
-   Indicatore visuale di rischio.
-   Target/mob associato.
-   Variazione recente o trend, quando i campioni sono sufficienti.

Stati proposti:

-   **SAFE:** margine ampio rispetto alla soglia di rischio.
-   **WARNING:** il giocatore si avvicina alla soglia.
-   **DANGER:** rischio elevato o soglia superata.
-   **UNKNOWN:** dati insufficienti o API non disponibili.

Le soglie devono essere configurabili. I valori predefiniti andranno
stabiliti dopo i test sul client, non assunti come universali.

La visualizzazione deve poter essere ordinata per: - threat assoluta, se
disponibile; - percentuale rispetto al tank; - livello di rischio; -
variazione recente.

### 5.2 Threat Coach

**Scopo:** trasformare le informazioni di threat in suggerimenti
semplici.

Esempi di messaggi:

-   "Threat in aumento: valuta di ritardare il burst."
-   "Sei vicino alla soglia di rischio."
-   "Il tank ha un margine sufficiente secondo i dati attuali."
-   "Dati insufficienti per formulare un consiglio."

Regole iniziali:

1.  Avvisare quando la percentuale supera una soglia configurata.
2.  Avvisare quando il trend indica un possibile superamento imminente.
3.  Evitare messaggi ripetitivi tramite cooldown.
4.  Non consigliare abilità specifiche finché disponibilità, cooldown e
    condizioni non sono verificabili.
5.  Non dichiarare una causa esatta di aggro loss senza evidenza.

Ogni consiglio deve essere accompagnato da una motivazione breve e,
quando utile, da un indicatore di confidenza.

### 5.3 Threat Timeline

**Scopo:** rappresentare l'andamento della threat nel tempo.

Dati da rappresentare, se disponibili:

-   threat del tank;
-   threat dei giocatori più vicini alla soglia;
-   percentuale relativa;
-   cambi di target;
-   eventi rilevanti registrati;
-   momenti in cui viene superata una soglia.

La timeline deve supportare: - selezione di un intervallo; - pausa e
riproduzione; - salto avanti/indietro; - tooltip o dettaglio sul
campione; - distinzione visiva tra dati rilevati e stime.

### 5.4 Threat Replay

**Scopo:** consentire l'analisi post-combattimento.

La registrazione deve avvenire durante il combattimento. Non si deve
presumere che il combat log possa ricostruire retroattivamente campioni
di threat non acquisiti.

Eventi/campioni da salvare, in base alla disponibilità:

-   timestamp relativo all'inizio dello scontro;
-   identificativo del combattimento;
-   GUID o identificatore disponibile del mob;
-   nome del mob;
-   giocatore/unità osservata;
-   valore/percentuale di threat disponibile;
-   unità che detiene il target, se rilevabile;
-   cambio di target;
-   morte;
-   inizio/fine combattimento;
-   eventi di taunt o abilità rilevanti, solo se identificabili in modo
    affidabile.

Funzioni UI:

-   elenco degli ultimi scontri;
-   durata dello scontro;
-   timeline;
-   eventi ordinati cronologicamente;
-   selezione di un evento per vedere i dati circostanti;
-   indicazione dei dati mancanti;
-   eliminazione delle registrazioni.

### 5.5 Threat Analytics

**Scopo:** generare riepiloghi quantitativi.

Metriche possibili, solo se i dati raccolti sono sufficienti:

-   numero di superamenti di soglia;
-   durata trascorsa in WARNING/DANGER;
-   numero di cambi di target;
-   giocatore con maggiore threat osservata;
-   intervalli di threat più instabile;
-   frequenza di situazioni di rischio per scontro;
-   confronto tra scontri registrati.

Evitare classifiche accusatorie o giudizi soggettivi come "peggior DPS".
Preferire indicatori descrittivi, contestualizzati e verificabili.

### 5.6 Multi-target / Dungeon Focus

**Scopo:** identificare i mob sui quali il gruppo rischia maggiormente
di perdere aggro.

Per ogni mob tracciabile: - identificativo stabile durante lo scontro; -
nome; - target corrente, se disponibile; - threat relativa dei membri
osservati; - stato SAFE/WARNING/DANGER; - ultimo aggiornamento.

Il modulo deve degradare in modo pulito se il client non permette di
interrogare la threat di unità non selezionate o non accessibili.

### 5.7 Heatmap

Funzionalità opzionale: - colorazione delle righe del Threat Monitor; -
integrazione con raid frame solo se tecnicamente e legalmente
compatibile; - nessuna dipendenza obbligatoria da addon esterni; -
colori configurabili e alternative non basate soltanto sul colore.

------------------------------------------------------------------------

## 6. UX e interfaccia

### 6.1 Principi

-   Informazioni essenziali leggibili durante il combattimento.
-   Pannello compatto e ridimensionabile.
-   Nessun blocco dell'interfaccia di gioco.
-   Aggiornamenti efficienti, senza polling eccessivo.
-   Avvisi non invasivi e configurabili.
-   Supporto a modalità solo testo/solo icone, ove utile.
-   Contrasto sufficiente e opzioni per daltonismo.

### 6.2 Pannello principale

Elementi previsti:

1.  Titolo e stato del modulo.
2.  Target attualmente monitorato.
3.  Stato sintetico SAFE/WARNING/DANGER/UNKNOWN.
4.  Margine o percentuale di threat, se disponibile.
5.  Elenco dei giocatori monitorati.
6.  Trend recente.
7.  Indicatore di qualità/aggiornamento dei dati.

### 6.3 Avvisi

Canali configurabili: - messaggio nella finestra; - effetto visivo; -
suono; - nessun avviso.

Opzioni: - soglia WARNING; - soglia DANGER; - cooldown; - avviso solo in
combattimento; - avviso solo sul target corrente; - esclusione di
specifiche unità; - disattivazione rapida.

Non usare messaggi vocali o annunci in chat come impostazione
predefinita. Evitare spam in party/raid.

### 6.4 Configurazione

La configurazione dovrebbe includere: - abilitazione/disabilitazione dei
moduli; - dimensione e posizione; - soglie; - frequenza di
aggiornamento; - durata e limite delle registrazioni; - opzioni di
notifica; - profili per ruolo; - reset delle impostazioni.

------------------------------------------------------------------------

## 7. Architettura software proposta

Architettura modulare in Lua, adattata alla versione effettiva del
client.

``` text
AzerothThreatwarden/
├── AzerothThreatwarden.toc
├── Core/
│   ├── Bootstrap.lua
│   ├── Events.lua
│   ├── Compatibility.lua
│   ├── APIAdapter.lua
│   ├── Scheduler.lua
│   └── Diagnostics.lua
├── Threat/
│   ├── ThreatScanner.lua
│   ├── ThreatModel.lua
│   ├── ThreatCalculator.lua
│   ├── ThreatState.lua
│   └── TargetTracker.lua
├── Coach/
│   ├── Rules.lua
│   ├── Recommendations.lua
│   └── AlertManager.lua
├── Recording/
│   ├── Recorder.lua
│   ├── Session.lua
│   ├── Storage.lua
│   └── Replay.lua
├── Analytics/
│   ├── Metrics.lua
│   └── Reports.lua
├── UI/
│   ├── MainWindow.lua
│   ├── ThreatList.lua
│   ├── Timeline.lua
│   ├── ReplayWindow.lua
│   ├── Options.lua
│   └── Widgets.lua
├── Localization/
│   ├── enUS.lua
│   └── itIT.lua
└── README.md
```

La struttura è indicativa: può essere semplificata per la prima release.

### 7.1 Core

Responsabilità: - inizializzazione; - registrazione degli eventi; -
gestione del ciclo di vita; - compatibilità con la versione del
client; - diagnostica; - gestione delle dipendenze interne.

### 7.2 API Adapter

Tutte le chiamate alle API del gioco devono passare, per quanto
ragionevole, da un livello di compatibilità.

Questo consente di: - verificare la presenza delle funzioni; - gestire
differenze tra client; - normalizzare i risultati; - centralizzare
fallback e controlli; - impedire che moduli UI chiamino direttamente API
non verificate.

### 7.3 Threat Model

Modello normalizzato per ogni unità/mob:

``` lua
ThreatRecord = {
    unitGUID = nil,
    unitName = nil,
    targetGUID = nil,
    threatValue = nil,
    threatPercent = nil,
    threatSituation = nil,
    observedAt = 0,
    source = "api",
    confidence = "unknown",
}
```

I campi sono concettuali. I valori effettivi dipenderanno dalle API del
client.

### 7.4 Recorder

Il recorder deve: - avviare una sessione quando viene rilevato l'inizio
del combattimento; - raccogliere campioni con frequenza configurabile; -
registrare gli eventi disponibili; - limitare la quantità di dati
salvati; - chiudere la sessione a fine combattimento; - proteggere da
sessioni duplicate o incomplete; - gestire logout, reload e
interruzioni.

### 7.5 Storage

Usare SavedVariables locali.

Requisiti: - schema versionato; - migrazione quando cambia il formato; -
limite configurabile di sessioni e dimensione; - eliminazione delle
sessioni più vecchie; - nessun invio automatico a servizi esterni; -
gestione dei dati corrotti senza bloccare l'addon.

------------------------------------------------------------------------

## 8. Verifica tecnica preliminare obbligatoria

Prima di implementare Coach, Replay e Analytics, creare un piccolo **API
Capability Probe**.

Il probe deve essere eseguito sul client effettivo di WoW Forever e
verificare:

1.  Versione del client e interfaccia dichiarata.
2.  Presenza delle API threat pertinenti.
3.  Firma e comportamento delle API disponibili.
4.  Disponibilità delle informazioni per target selezionato.
5.  Disponibilità per unità non selezionate.
6.  Disponibilità di GUID e identificatori.
7.  Eventi combat log effettivamente ricevuti.
8.  Eventi di cambio target e morte.
9.  Restrizioni di frequenza o accesso.
10. Comportamento in party, raid, dungeon e combattimento.

API da verificare, senza presumerne la presenza o il comportamento: -
`UnitDetailedThreatSituation` - `UnitThreatSituation` -
`UnitThreatPercentageOfLead` - eventi di combattimento e relativi
payload.

Produrre un report con: - API presente/assente; - parametri accettati; -
valori restituiti; - condizioni in cui restituisce `nil`; - test
effettuato; - conclusione: supportato, parzialmente supportato o non
supportato.

**Gate di progetto:** non iniziare a promettere Threat Replay completo o
multi-target tracking finché il probe non dimostra che i dati necessari
sono effettivamente ottenibili.

------------------------------------------------------------------------

## 9. Prestazioni e robustezza

-   Evitare scansioni complete a ogni frame.
-   Usare eventi quando disponibili e campionamento controllato per i
    dati che richiedono polling.
-   Rendere configurabile la frequenza di campionamento.
-   Limitare il numero di unità e mob osservati.
-   Riutilizzare tabelle e strutture quando possibile.
-   Evitare allocazioni ripetute nei percorsi eseguiti frequentemente.
-   Non bloccare il thread UI con analisi o serializzazioni pesanti.
-   Gestire correttamente target che scompaiono, muoiono o cambiano
    GUID.
-   Gestire dati mancanti, ritardati o incoerenti.

La frequenza di campionamento iniziale deve essere scelta tramite test
sul client, misurando CPU e qualità dei dati, non fissata
arbitrariamente.

------------------------------------------------------------------------

## 10. Sicurezza, privacy e conformità

-   Nessuna comunicazione di rete nella prima versione.
-   Nessuna raccolta di credenziali o dati personali.
-   Dati salvati localmente nelle SavedVariables.
-   Funzione per cancellare le registrazioni.
-   Nessun messaggio automatico in chat pubblica.
-   Rispettare le regole addon e le API consentite dal client.
-   Non tentare di aggirare protezioni o restrizioni del client.
-   Non leggere memoria del processo o utilizzare strumenti esterni al
    normale ambiente addon.

------------------------------------------------------------------------

## 11. Compatibilità e dipendenze

Prima del rilascio definire: - versione esatta del client WoW Forever; -
valore Interface corretto nel file TOC; - API disponibili; - eventuali
dipendenze obbligatorie; - compatibilità con gli addon UI più comuni; -
comportamento in assenza di altri addon.

L'addon dovrebbe funzionare autonomamente. Eventuali integrazioni con
altri addon devono essere opzionali e isolate.

------------------------------------------------------------------------

## 12. Piano di sviluppo

### Milestone 0 --- Ricerca e fattibilità

Deliverable: - identificazione del client; - API Capability Probe; -
report delle API; - matrice delle funzionalità supportate; - decisione
sul perimetro MVP.

Criterio di completamento: sapere esattamente quali dati di threat sono
disponibili e con quali limiti.

### Milestone 1 --- Core e Threat Monitor

Deliverable: - struttura addon; - caricamento TOC; - adapter API; -
rilevamento target; - monitor threat; - pannello UI; - configurazione
iniziale.

Criteri di accettazione: - l'addon si carica senza errori Lua; -
gestisce correttamente target validi e non validi; - visualizza UNKNOWN
quando i dati non sono disponibili; - non genera spam o carico
eccessivo.

### Milestone 2 --- Alert e Threat Coach

Deliverable: - soglie configurabili; - stati SAFE/WARNING/DANGER; -
cooldown; - suggerimenti basati su regole; - indicazione della
confidenza.

Criteri di accettazione: - gli alert scattano alle condizioni
configurate; - non si ripetono a ogni aggiornamento; - i consigli non
dichiarano certezze non dimostrate.

### Milestone 3 --- Recorder e Replay

Deliverable: - sessioni di combattimento; - campionamento; - salvataggio
locale; - lista sessioni; - timeline e replay essenziale.

Criteri di accettazione: - le sessioni sono separate; - i timestamp sono
coerenti; - i dati persistono dopo reload; - i limiti di storage sono
rispettati; - sessioni incomplete non causano errori.

### Milestone 4 --- Analytics

Deliverable: - report per sessione; - metriche aggregate; - riepilogo
delle soglie superate; - esportazione, se praticabile.

Criteri di accettazione: - ogni metrica è riconducibile ai dati
registrati; - dati insufficienti sono segnalati; - non vengono
attribuite cause non dimostrate.

### Milestone 5 --- Multi-target e rifinitura

Deliverable: - tracking multi-target, se supportato; - dungeon focus; -
preset; - localizzazione; - ottimizzazione; - documentazione e release
CurseForge.

------------------------------------------------------------------------

## 13. Piano di test

Testare almeno i seguenti scenari:

### Funzionali

-   giocatore solo;
-   party;
-   raid;
-   tank con threat stabile;
-   DPS che si avvicina alla soglia;
-   cambio target;
-   target che muore;
-   più mob;
-   taunt;
-   morte del tank;
-   morte di un DPS;
-   fine combattimento;
-   logout/reload durante o dopo una sessione.

### Dati e affidabilità

-   API che restituisce `nil`;
-   unità non accessibile;
-   GUID non disponibile;
-   campioni mancanti;
-   eventi duplicati;
-   eventi fuori ordine;
-   mob che scompare;
-   target sostituito;
-   differenze tra target selezionato e non selezionato.

### Prestazioni

-   raid numeroso;
-   pull con molti mob;
-   sessioni lunghe;
-   storico vicino al limite;
-   apertura e chiusura ripetuta del replay.

### Interfaccia

-   diverse risoluzioni;
-   diverse scale UI;
-   interfaccia in movimento;
-   modalità combat lockdown, se applicabile al client;
-   compatibilità con UI personalizzate.

------------------------------------------------------------------------

## 14. Localizzazione e stile

Nome prodotto: **Azeroth Threatwarden**

Tono: fantasy, autorevole, chiaro e non eccessivamente tecnico.

Termini UI consigliati: - Threat - Aggro - Safe - Warning - Danger -
Threat Margin - Threat Replay - Combat Report

La prima lingua dell'interfaccia può essere inglese (`enUS`), con
italiano (`itIT`) come localizzazione aggiuntiva.

------------------------------------------------------------------------

## 15. Identità visiva

Direzione creativa: - scudo runico come simbolo principale; - occhio o
gemma al centro dello scudo; - palette fantasy sobria; - verde per SAFE,
ambra per WARNING, rosso per DANGER; - grigio/blu per informazioni
neutre e dati sconosciuti.

Il logo deve rimanere leggibile anche a dimensioni ridotte, ad esempio
nella lista degli addon di CurseForge.

Evitare di copiare icone, loghi o asset di Omen o di altri addon.

------------------------------------------------------------------------

## 16. Pagina CurseForge e posizionamento

Titolo consigliato:

**Azeroth Threatwarden --- Threat Meter, Coach & Combat Replay**

Descrizione breve:

> A threat monitoring and combat analysis addon for WoW Forever. Track
> threat, anticipate aggro loss, review combat encounters and understand
> threat changes.

Keyword da integrare in modo naturale nella descrizione: - threat
meter; - threat monitor; - threat coach; - aggro warning; - threat
analysis; - combat replay; - Omen alternative; - WoW Forever.

Non dichiarare compatibilità con versioni diverse da quella
effettivamente testata.

Screenshot consigliati: 1. Threat Monitor durante un combattimento. 2.
Esempio di warning. 3. Threat Timeline. 4. Threat Replay. 5. Combat
Report.

------------------------------------------------------------------------

## 17. Rischi principali

  -----------------------------------------------------------------------
  Rischio                 Impatto                 Mitigazione
  ----------------------- ----------------------- -----------------------
  API threat non          Molto alto              Capability Probe prima
  disponibili o limitate                          dello sviluppo

  Threat non              Alto                    MVP focalizzato sul
  interrogabile su più                            target accessibile
  mob                                             

  Dati storici incompleti Alto                    Registrazione continua
                                                  durante il fight

  Falsi positivi nelle    Medio-alto              Soglie configurabili e
  previsioni                                      confidenza

  Consumo CPU o           Medio                   Sampling e retention
  SavedVariables                                  configurabili
  eccessive                                       

  Differenze tra client   Alto                    Adapter e test sulla
                                                  build target

  Confusione tra          Alto                    Etichettare ipotesi e
  correlazione e causa                            dati osservati
  -----------------------------------------------------------------------

------------------------------------------------------------------------

## 18. Definition of Done --- MVP

L'MVP è pronto per una release pubblica quando:

-   [ ] Il client target è identificato e documentato.
-   [ ] Il probe API è completato.
-   [ ] Le API utilizzate sono state verificate sul client.
-   [ ] Il Threat Monitor funziona in condizioni reali.
-   [ ] Gli stati UNKNOWN e dati insufficienti sono gestiti.
-   [ ] Gli alert sono configurabili e non invasivi.
-   [ ] Non ci sono errori Lua nei test previsti.
-   [ ] Le prestazioni sono accettabili in party e raid.
-   [ ] Le SavedVariables sono versionate e gestite.
-   [ ] La configurazione sopravvive a logout e reload.
-   [ ] La documentazione spiega limiti e compatibilità.
-   [ ] La pagina CurseForge non promette funzioni non verificate.

------------------------------------------------------------------------

## 19. Decisioni ancora aperte

Le seguenti decisioni devono essere chiuse prima o durante la Milestone
0:

1.  Qual è la versione esatta del client WoW Forever?
2.  Quali API threat sono realmente disponibili?
3.  Il server espone threat accurata o implementa comportamenti custom?
4.  Quali unità possono essere interrogate contemporaneamente?
5.  Quanto deve durare lo storico locale?
6.  Il replay deve essere solo locale o esportabile?
7.  L'interfaccia deve essere standalone o integrarsi con una UI
    esistente?
8.  Quali classi/ruoli saranno coperti dai primi suggerimenti?

------------------------------------------------------------------------

## 20. Direzione raccomandata

Sviluppare Azeroth Threatwarden in quest'ordine:

1.  **Verificare le API di WoW Forever.**
2.  Costruire un Threat Monitor affidabile.
3.  Aggiungere alert e Threat Coach basato su regole.
4.  Registrare i dati durante il combattimento.
5.  Realizzare Threat Replay.
6.  Aggiungere Threat Analytics.
7.  Espandere al multi-target solo se il client lo consente.

Il differenziale del prodotto non deve essere il numero di barre o di
opzioni, ma la qualità delle informazioni e la capacità di aiutare il
giocatore a capire cosa sta succedendo.

**Azeroth Threatwarden non deve limitarsi a mostrare chi ha l'aggro.
Deve aiutare il giocatore a capire il rischio, riconoscere ciò che è
successo e prendere decisioni migliori nel combattimento.**
