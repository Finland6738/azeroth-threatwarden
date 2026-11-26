# SPEC-04: Avvisi e Threat Coach

> Fonte: [specifiche originali](source-specification.md) §5.2, §6.3. Completato in **M3.1** (2026-11-26) **prima**
> dell'esito del probe M0, come M2 ([SPEC-00 §7](SPEC-00-vision-scope.md#7-registro-delle-decisioni) D7): avvisi e Coach
> leggono solo gli stati e i valori del monitor ([SPEC-03](SPEC-03-threat-monitor-ui.md)), quindi valgono per i tre
> esiti del probe (§2.5); ciò che il probe può cambiare è marcato **[probe Pn]**, ciò che solo il gioco può dire
> **[da provare in gioco]**. Piano per step in §6.

Due parti, due interruttori ([ADR 0014](../adr/0014-one-version-per-milestone-and-feature-switches.md)), spenti fino a
M3.R:

- gli **avvisi** (`Data/Alerts.lua`, interruttore `alerts`): un segnale breve quando una condizione di rischio
  **entra**, sui canali che il giocatore sceglie (§1);
- il **Threat Coach** (`Data/CoachRules.lua`, `Data/Coach.lua`, interruttore `coach`): un consiglio continuo, uno alla
  volta, con la sua **motivazione** e, quando conta, la sua **confidenza** (§2).

Tutti e due si vedono nella **striscia del Coach** della finestra (§3) e non leggono nulla dal gioco: lavorano sulle
righe di `Data/ThreatModel.lua` e sugli eventi di `Data/ThreatState.lua`. Gli unici accessi al gioco sono il suono e
la lettura di `IsThreatWarningEnabled`, attraverso `Core/Compat.lua`.

## 1. Avvisi

### 1.1 Quando scatta un avviso

- **ALR-01** MUST: un avviso scatta quando la condizione **entra** (passaggio di stato o di chi tiene il mob), non a ogni
  aggiornamento. Le sole sorgenti sono due eventi del Bus, già ripuliti da isteresi e permanenza (MON-10, MON-12):
  - `STATE_CHANGED(unitKey, mobKey, old, new)` di `ThreatState` (M2.4);
  - `AGGRO_CHANGED(mobKey, unitKey, oldUnitKey)`, nuovo in **M3.2** in `ThreatState`: chi tiene il mob è cambiato.
    Serve perché un passaggio di aggro non sempre cambia lo stato mostrato (un DPS in DANGER per soglia che prende il
    mob resta DANGER, con motivo `aggro`; il tank in DANGER sul margine che lo perde resta DANGER, con motivo
    `lost-aggro`) e `STATE_CHANGED` non lo direbbe.
- `AGGRO_CHANGED` si emette quando la riga che tiene il mob (`ThreatState.tank`) è **nota** e diversa dall'ultima nota
  per lo stesso mob; un detentore che diventa sconosciuto (*Unknown tank*) non emette nulla e, se torna lo stesso, non
  è un cambio. Al primo detentore noto di un mob o di un combattimento `oldUnitKey` è `nil`. Il motivo del cambio non
  si conosce mai (COA-05): l'evento dice solo chi, prima e dopo. Nello stesso aggiornamento si emette **prima** degli
  `STATE_CHANGED` (i tank sono già stabiliti, gli stati delle righe non ancora): così Alerts dà un solo avviso per il
  cambio (§1.2) (M3.2).
- Sono **entrate** solo le salite: SAFE → WARNING → DANGER, `nil` (l'unità entra nella lista) → WARNING o DANGER.
  Le discese non avvisano mai. Da UNKNOWN a uno stato noto si avvisa solo se è più alto dell'**ultimo stato noto**
  della stessa unità sullo stesso mob (una lettura che torna dopo un buco non ripete l'avviso di prima). Entrare in
  UNKNOWN non avvisa mai: lo dicono la pastiglia e le righe ([SPEC-03 §2.6](SPEC-03-threat-monitor-ui.md#26-cosa-si-vede-in-ogni-stato)).
- Un nuovo mob o un nuovo combattimento ripartono da capo, come gli stati; i **cooldown no** (§1.3).
- **Un solo mob**: in M3 il monitor ne ha uno (il target o il target del target, [SPEC-03 §1.2](SPEC-03-threat-monitor-ui.md#12-il-mob-monitorato-datatargettrackerlua))
  e gli avvisi valgono solo per lui. Per questo l'opzione della fonte *avviso solo sul target corrente* in M3 è la sola
  regola possibile, senza interruttore; l'impostazione `alerts.onlyTarget` arriva con M7, quando l'addon potrà leggere
  altri mob (**[probe P5]**).
- **Solo in combattimento**: lo Scanner legge solo in combattimento (SPEC-03 §1.4), quindi gli stati salgono solo lì;
  in più Alerts ignora ogni evento arrivato fuori dal combattimento. Lo legge da `ThreatScanner.inCombat`, non da un
  proprio ascolto di `COMBAT_STARTED`: lo Scanner fa la prima scansione dentro quell'evento, prima dei moduli che
  vengono dopo (M3.2). Anche l'opzione della fonte *avviso solo in combattimento* è quindi una regola fissa, senza
  interruttore (spenta non cambierebbe nulla).

### 1.2 Tipi di avviso

Il **soggetto** di un avviso è il giocatore, il suo famiglio o un'altra unità osservata. *Tank* è quello di
[SPEC-03 §2.1](SPEC-03-threat-monitor-ui.md#21-chi-è-il-tank) (`row.isTank`): un tank designato (ruolo `TANK`) o, senza
tank designati, chi tiene il mob. La **gravità** ordina gli avvisi: 1 WARNING, 2 DANGER, 3 aggro passata.

| Tipo (`kind`) | Soggetto | Quando entra | Gravità e stato | Messaggio (chiave, proposta `enUS`) | Categoria | Suono |
|---|---|---|---|---|---|---|
| `warning` | la propria riga, che non tiene il mob | `STATE_CHANGED` → WARNING con motivo soglia (nessuno) | 1, WARNING | `ALERT_WARNING` *Threat %d %%: close to taking aggro* | rilevata | no |
| `warning` | come sopra | → WARNING con motivo `predicted` (solo con confidenza almeno media, SPEC-03 §2.5) | 1, WARNING | `ALERT_WARNING_PREDICTED` *Threat rising: you may reach Danger in about %d s* | prevista | no |
| `warning` | come sopra, modalità `state` | → WARNING con motivo `state-only` (`g = 1`) | 1, WARNING | `ALERT_WARNING_STATE` *Your threat is above the tank's* | rilevata | no |
| `danger` | la propria riga, che non tiene il mob | → DANGER con motivo soglia (nessuno) | 2, DANGER | `ALERT_DANGER` *Threat %d %%: very close to taking aggro* | rilevata | sì |
| `aggro` | il giocatore, non tank | `AGGRO_CHANGED`: il giocatore diventa chi tiene il mob. Da soli (nessun tank designato) solo se prima lo teneva il proprio famiglio | 3, DANGER | `ALERT_AGGRO` *You have aggro* | rilevata | sì |
| `margin` | la propria riga, tank che tiene il mob | → WARNING (soglia sul secondo, o `l = 1` in `state`) | 1, WARNING | `ALERT_MARGIN_WARNING` *Margin shrinking: %s at %d %%* (in `state`: *Your margin is getting small*) | calcolata / rilevata | no |
| `margin` | come sopra | → DANGER per soglia sul secondo o `l` 2–3 (motivo nessuno o `margin`) | 2, DANGER | `ALERT_MARGIN_DANGER` *%s is very close to taking the mob* (in `state`: *Your margin is very small*) | calcolata / rilevata | sì |
| `margin` | come sopra | → DANGER con motivo `behind` (stato 2) | 2, DANGER | `ALERT_BEHIND` *Someone has more threat than you* | rilevata | sì |
| `lost` | il giocatore, tank designato | `AGGRO_CHANGED`: teneva il mob e ora lo tiene un'unità osservata **non** tank (un altro tank designato è un cambio di tank, non un avviso) | 3, DANGER | `ALERT_LOST` *%s has the mob* | rilevata | sì |
| `pet` | il proprio famiglio, in gruppo con almeno un tank designato | `AGGRO_CHANGED`: il famiglio diventa chi tiene il mob | 2, DANGER | `ALERT_PET` *Your pet has the mob* | rilevata | sì |
| `other` | un'altra unità osservata non tank e non il proprio famiglio; solo secondo `alerts.others` (§1.5) | → DANGER per soglia | 2, DANGER | `ALERT_OTHER_DANGER` *%s is very close to taking aggro* | rilevata | sì |
| `other` | come sopra | `AGGRO_CHANGED`: diventa chi tiene il mob togliendolo a un tank designato | 3, DANGER | `ALERT_OTHER_AGGRO` *%s has the mob* | rilevata | sì |

- Un passaggio che vale per due righe della tabella (per esempio SAFE → DANGER con motivo `aggro` e, nello stesso
  aggiornamento, `AGGRO_CHANGED`) dà **un** avviso, quello di gravità più alta: `STATE_CHANGED` con motivo `aggro` o
  `lost-aggro` non avvisa da solo, perché lo fa `AGGRO_CHANGED`.
- Precisato in M3.2 per *un passaggio, un avviso*: un cambio di chi tiene il mob dà al più un avviso, prima quello sul
  giocatore (`aggro` o `lost`: chi perde il mob a favore del proprio famiglio riceve solo `lost`); gli avvisi sul
  giocatore di gravità uguale o più bassa dello stesso aggiornamento si scartano (da soli, `aggro` e non anche
  `margin`). Quando il tank riceve l'avviso `margin` di DANGER, lo stesso aggiornamento non dà anche `other` per il
  DANGER del secondo; se quel `margin` non esce (cooldown), `other` esce.
- Le chiavi `ALERT_*` sono quelle della tabella più `ALERT_MARGIN_WARNING_STATE` e `ALERT_MARGIN_DANGER_STATE` per le
  forme `state` (usate anche quando nessun'altra riga è in `values`); i testi inglesi e italiani sono in `Locales/`.
- `%s` è l'unità di cui parla l'avviso (il secondo, chi ha preso il mob): l'avviso ne porta la chiave (`otherKey`), mai
  il nome, e la vista scrive il nome o l'etichetta del token (*Party 2*) come l'elenco ([SPEC-03 §1.6](SPEC-03-threat-monitor-ui.md#16-i-campi-uno-per-uno)).
  `%d` sono numeri già mostrati dal monitor (percentuale scalata, secondi della previsione), arrotondati come lì.
- Le parole proposte seguono le regole di scrittura di §2.4; i testi definitivi e l'italiano li fissano M3.2 (chiavi
  `ALERT_*`) e il test delle parole di M3.3.
- **[probe P2]**: i significati di `g` e `l` in modalità `state` sono quelli della documentazione; **[probe P4]**: se il
  server non passa l'aggro a 100 % di scalata la WARNING prevista si spegne (SPEC-03 §2.2) e con lei
  `ALERT_WARNING_PREDICTED`; **[probe P9]**: con ruoli segreti o `NONE` non ci sono tank designati, quindi niente `lost`,
  `pet` e `other` per aggro (resta `aggro` da soli col famiglio).

### 1.3 Cooldown e raffiche

- **Cooldown per tipo e soggetto**: dopo un avviso, un altro dello **stesso tipo** sulla **stessa unità** non scatta
  prima di `alerts.cooldown` secondi (predefinito **8 s**, da 3 a 30, Q12). Tipi diversi hanno cooldown separati: un
  `danger` non aspetta il cooldown di un `warning`, e un `aggro` non aspetta nessuno.
- Il cooldown dipende **solo dal tempo** (`Compat.Now`): non si azzera cambiando mob, a un nuovo combattimento o
  silenziando; lo azzera solo un `/reload`. Così chi cambia target in un gruppo di mob non riceve lo stesso avviso per
  ogni mob.
- Un avviso entro il cooldown non si emette e si conta (`Alerts.stats.cooled`, per `/atw debug`).
- **Raffiche di altri**: al massimo un avviso `other` ogni **3 s** (`Alerts.OTHER_GAP`); gli altri si contano
  (`Alerts.stats.dropped`) e non si emettono. Gli avvisi sul giocatore e sul famiglio non hanno questo limite.
- I tipi `margin` e `other` hanno più gravità con **un solo** cooldown: un DANGER dello stesso tipo entro il cooldown di
  una WARNING non esce (per il margine esce allora l'`other` del secondo, se `others` lo permette). Se in gioco è
  troppo, si decide con [Q12](SPEC-09-risks-open-questions.md) (checklist M3.6).
- **Suono**: al massimo uno ogni **3 s** (`Alerts.SOUND_GAP`), qualunque sia il tipo; un avviso dentro l'intervallo
  si mostra senza suono.
- **Oscillazioni**: `ThreatState` non cambia stato più di una volta al secondo per riga nelle discese (MON-12), e una
  salita dopo una discesa è un'entrata nuova: il cooldown di 8 s è ciò che impedisce l'avviso ripetuto.

### 1.4 Canali

| Canale | Impostazione | Predefinito | Cosa fa |
|---|---|---|---|
| Messaggio nella finestra | `alerts.window` | acceso | la striscia del Coach (§3) mostra l'avviso, con il distintivo del suo stato, per **4 s** (`Alerts.HOLD`), poi torna al consiglio corrente |
| Effetto visivo | `alerts.visual` | acceso | il bordo della finestra prende il colore dello stato dell'avviso una volta (§3.2): nessun lampeggio |
| Suono | `alerts.sound` | **spento** | un suono del gioco per gli avvisi di gravità 2 e 3 (mai per WARNING), attraverso `Compat` (`ui.PlaySound`) |
| Nessun avviso | `alerts.enabled` spento | — | nessun canale, nessun avviso emesso |

- **ALR-02** MUST: niente messaggi vocali, nessun annuncio in chat, in **nessun** canale e nemmeno nella finestra di chat
  del giocatore; nessuna chiamata di `SendChatMessage` o simili; nulla in party o raid
  ([ADR 0001](../adr/0001-local-only-addon-no-network.md)). L'unica riga in chat legata agli avvisi è la risposta di
  `/atw mute`, che il giocatore ha chiesto (§1.5).
- **ALR-04** MUST: un avviso non apre la finestra, non cambia scheda e non sposta nulla (non invasivo, Q12). Se la
  finestra è chiusa o su un'altra scheda, messaggio ed effetto non si vedono (il bordo si vede su ogni scheda con la
  finestra aperta) e l'avviso non si conserva per dopo: un avviso vecchio non serve.
- **Il suono** è `PlaySound(soundKitID)` del gioco (nel dump, sistema `Sound`, firma `(soundKitID, uiSoundSubType,
  forceNoDuplicates, …)`), con un solo suono del gioco, il kit `Alerts.SOUND_KIT` (proposta **8959**, il suono degli
  avvisi del raid nel client moderno) **[da provare in gioco]**: esiste su Forever? si sente? Il volume è quello degli
  effetti del gioco. Nessun file sonoro nell'addon. `Compat.PlaySound` usa `PlaySound` o, se manca,
  `C_Sound.PlaySound` (M3.2). Se mancano, danno errore o rispondono *non suonato* il suono si salta, senza errore e con
  la causa in `/atw debug`.
- **Demo** ([SPEC-03 §5.2](SPEC-03-threat-monitor-ui.md#52-modalità-demo-atw-demo-m26)): durante `Demo.IsActive()`
  avvisi e Coach lavorano sui dati inventati per farli **provare**, ma solo nella finestra (messaggio ed effetto), mai
  con il suono (la demo non chiama il gioco, MON-14); l'avviso porta `demo = true` e la registrazione (M4) lo ignora.
- **Consumatore dello Scanner**: gli avvisi leggono la threat attraverso la finestra (che la vuole quando è aperta
  sulla scheda Monitor). Quando il suono è acceso, gli avvisi accesi e non silenziati, Alerts chiama
  `ThreatScanner.Want("alerts", true)`, così il suono funziona anche a finestra chiusa (SPEC-03 §1.4); altrimenti
  `Want("alerts", false)`.

### 1.5 Opzioni, esclusioni e silenzio

| Opzione della fonte (§6.3) | Dove sta |
|---|---|
| Soglia WARNING, soglia DANGER | le stesse del monitor, `settings.monitor.warning` e `.danger` (card *Monitor*, [SPEC-03 §5](SPEC-03-threat-monitor-ui.md#5-comandi-e-configurazione)): un solo posto. La card *Alerts* le ricorda con una riga e un collegamento |
| Cooldown | `alerts.cooldown` (§1.3) |
| Solo in combattimento | regola fissa (§1.1) |
| Solo sul target corrente | regola fissa in M3, impostazione da M7 (§1.1) |
| Esclusione di unità | `alerts.others` e `alerts.pet` (salvate) più l'esclusione per sessione (sotto) |
| Disattivazione rapida | `/atw mute` e il tasto assegnabile (sotto) |
| Canali | §1.4 |

- **Altre unità** `alerts.others`: `tank` (predefinito: gli avvisi `other` solo quando il giocatore è un tank), `always`
  (sempre, per chi vuole seguire tutto il gruppo), `never`. Gli altri tank designati non sono mai soggetto di `other`.
- **Famiglio** `alerts.pet` (acceso): l'avviso `pet` quando il proprio famiglio prende il mob in un gruppo con un tank.
- **Esclusione per sessione** (M3.5): dal menu del clic destro su una riga dell'elenco, *Mute alerts about this unit*;
  vale fino al `/reload` e si tiene per `unitKey`, in memoria: **nessun nome nelle impostazioni**
  ([SPEC-02 §3.3](SPEC-02-data-model-storage.md#33-schema-1-personaggio-azeroththreatwardenchardb)). Il tooltip della
  riga lo dice (*Alerts about this unit are muted*). Il giocatore non si può escludere.
- **Silenzio** (`Alerts.ToggleMute()`, M3.2; comando e tasto M3.5): `/atw mute` silenzia tutti i canali degli avvisi
  **fino alla fine del combattimento** in corso; fuori dal combattimento, fino alla fine del **prossimo**. Di nuovo
  `/atw mute` li riaccende prima. Non si salva (un `/reload` lo toglie). Il Coach non si silenzia: è testo nella
  striscia, non un segnale (si spegne dalla card, §4).
  - Risposte (finestra di chat del giocatore, ADR 0001): *Alerts muted until the end of this fight.*, *Alerts muted
    until the end of the next fight.*, *Alerts back on.*; con gli avvisi spenti nella card *Alerts are off in
    Settings.*; con l'interruttore `alerts` spento *This arrives in v0.3.0.* (come ogni comando di una parte spenta).
  - Mentre è silenziato un avviso si valuta lo stesso (cooldown compreso) e si emette con `muted = true` e nessun
    canale: la registrazione (M4) può dire che cosa sarebbe scattato. La striscia mostra l'icona `mute` (§3.1).
  - **Tasto**: `Bindings.xml` (M3.5) con il binding `AZEROTHTHREATWARDEN_MUTE` nella categoria degli addon, intestazione
    `BINDING_HEADER_AZEROTHTHREATWARDEN` e nome `BINDING_NAME_AZEROTHTHREATWARDEN_MUTE` (chiave `BINDING_MUTE`, nella
    lingua del client perché i nomi servono prima dell'`ADDON_LOADED`, [SPEC-01 §10](SPEC-01-platform-architecture.md#10-lingue-corelocalelua));
    chiama la funzione globale `AzerothThreatwarden_ToggleMute()` (ARC-04), che fa e risponde come `/atw mute`.
    Nessun tasto predefinito. Come in Accord (`Bindings.xml`, ADR 0012) **[da provare in gioco]**.
- `MUTE_CHANGED(muted)` sul Bus a ogni cambio (la striscia, `/atw debug`).
- Interfaccia per M3.5 (M3.2): `Alerts.ToggleMute()` risponde `"muted-fight"`, `"muted-next"`, `"unmuted"`,
  `"disabled"` (avvisi spenti nella card: nulla cambia) o `"off"` (interruttore); `Alerts.Exclude(unitKey, sì/no)` e
  `Alerts.IsExcluded(unitKey)`.

### 1.6 L'avviso nativo del gioco

- **ALR-03** SHOULD: se l'avviso della threat del gioco è acceso (`IsThreatWarningEnabled()`, voce
  `threat.WarningEnabled` di Compat, nel dump firma `() → bool`), la card *Alerts* lo dice: *The game's own threat
  warning is on: you may get two warnings for the same thing. You can turn off one of them: in the game's options, or
  with the switches above.* La pagina del manuale *Alerts and Coach* (M3.4) dice lo stesso. L'addon **non** cambia
  l'impostazione del gioco e non spegne i propri avvisi da solo.
- Si legge quando la card si mostra e a `PLAYER_ENTERING_WORLD`; `/atw debug` lo riporta già (voce con `show`). Se la
  funzione manca o dà errore la card non dice nulla. Che cosa mostri davvero l'avviso nativo su Forever
  **[da provare in gioco]**.

## 2. Threat Coach

Suggerimenti semplici basati su regole, uno alla volta, ciascuno con **motivazione breve** e, quando conta,
**confidenza** (alta, media). Le regole guardano **la riga del giocatore** e, per il tank, il secondo della lista; non
leggono nulla che il monitor non abbia già.

### 2.1 Ruolo

| Ruolo del Coach | Quando | Regole |
|---|---|---|
| `tank` | la riga del giocatore è tank (`row.isTank`): ruolo `TANK`, o senza tank designati il giocatore che tiene il mob | T1–T7 |
| `healer` | ruolo `HEALER` | D1–D5 con le parole del guaritore |
| `dps` | ruolo `DAMAGER`, oppure nessun ruolo (`NONE` o segreto, **[probe P9]**) e non tank | D1–D5 |

Nessun consiglio di classe o di abilità (Q11, COA-04): i ruoli cambiano solo le parole. Da soli, senza nessun altro
nella lista (il giocatore che tiene il proprio mob, senza famiglio), il Coach tace: non c'è nulla da consigliare.

### 2.2 Tabella delle regole (`Data/CoachRules.lua`)

`p` = percentuale scalata della riga del giocatore, `W`/`D` = soglie, `s` = percentuale del secondo (il secondo è la
riga in `values` con la percentuale più alta dopo chi tiene il mob), `m` = margine, `t` = secondi della previsione, `g` e
`l` = stato e vantaggio del gioco (SPEC-03 §2.3). Ogni regola ha: condizione, messaggio, motivazione, **base** (la
categoria del dato su cui poggia, ADR 0003), confidenza, priorità e cooldown (§2.3). Fra le regole del ruolo vale la
prima vera in ordine di priorità.

| Id | Ruolo | Condizione | Messaggio (chiave, proposta `enUS`) | Motivazione (chiave, proposta `enUS`) | Base | Confidenza | Prio | Cooldown |
|---|---|---|---|---|---|---|---|---|
| **T1** `tank-lost` | tank | tank designato, non tiene il mob, lo tiene un non tank (stato DANGER `lost-aggro`) | `COACH_TANK_LOST` *%s has the mob.* | `COACH_WHY_HOLDER` *%s is at the top of the threat list. The cause is not known.* | rilevata | alta | 100 | 0 |
| **T2** `tank-behind` | tank | tiene il mob ma `g = 2` (motivo `behind`) | `COACH_TANK_BEHIND` *Someone has more threat than you: you may lose the mob.* | `COACH_WHY_BEHIND` *The game's threat state shows another unit above you.* | rilevata | alta | 90 | 0 |
| **T3** `tank-danger` | tank | tiene il mob, DANGER sul margine (`s ≥ D`; in `state` `l` 2–3) | `COACH_TANK_DANGER` *%s is very close to taking the mob.* (in `state` `COACH_TANK_DANGER_STATE` *Your margin is very small.*) | `COACH_WHY_SECOND` *The second, %s, is at %d %% (Danger from %d %%).* (in `state` `COACH_WHY_STATE`) | calcolata (`state`: rilevata) | alta | 80 | 0 |
| **T4** `tank-overtake` | tank | tiene il mob, SAFE o WARNING, in `values`; il secondo ha un tempo al superamento `t ≤ 10 s` con confidenza almeno media | `COACH_TANK_OVERTAKE` *%s may overtake you in about %d s.* | `COACH_WHY_TREND_OTHER` *Their threat is rising by %.1f points per second (%s confidence).* | prevista | quella del trend del secondo (media o alta) | 70 | 8 s |
| **T5** `tank-warning` | tank | tiene il mob, WARNING sul margine (`W ≤ s < D`; in `state` `l = 1`) | `COACH_TANK_WARNING` *Your margin is shrinking.* | `COACH_WHY_SECOND_W` *The second, %s, is at %d %% (Warning from %d %%).* (in `state` `COACH_WHY_STATE`) | calcolata (`state`: rilevata) | alta | 60 | 8 s |
| **T6** `tank-other` | tank | tank designato che non tiene il mob, lo tiene un altro tank designato | `COACH_TANK_OTHER` *Another tank has the mob.* | `COACH_WHY_HOLDER_TANK` *%s, a tank, is at the top of the threat list.* | rilevata | alta | 30 | 8 s |
| **T7** `tank-safe` | tank | tiene il mob, SAFE, con almeno un'altra riga nella lista | `COACH_TANK_SAFE` *You have enough margin according to current data.* | `COACH_WHY_MARGIN` *The second is at %d %% (margin %d points).* (in `state` `COACH_WHY_LEAD` *The game's threat state shows a comfortable lead.*) | calcolata (`state`: rilevata) | alta | 10 | 15 s |
| **D1** `aggro` | dps, healer | tiene il mob da non tank (stato DANGER `aggro`) | `COACH_AGGRO` *You have aggro: the tank needs to take it back.* (healer `COACH_AGGRO_HEALER` *The mob is on you.*) | `COACH_WHY_TOP` *You are at the top of its threat list.* | rilevata | alta | 100 | 0 |
| **D2** `danger` | dps, healer | DANGER per soglia (`p ≥ D`), non tiene il mob | `COACH_DANGER` *Very close to taking aggro: ease off your threat.* (healer `COACH_DANGER_HEALER` *Very close to taking aggro: the mob may turn to you.*) | `COACH_WHY_P_DANGER` *Your threat is %d %% (Danger from %d %%).* | rilevata | alta | 90 | 0 |
| **D3** `rising` | dps, healer | in `values`, non tiene il mob, trend oltre +2 punti/s con confidenza almeno media e una previsione: WARNING prevista (`predictedIn`) o tempo al superamento `t ≤ 10 s` | `COACH_RISING` *Threat rising: consider delaying your burst.* (healer `COACH_RISING_HEALER` *Threat rising: the mob may turn to you.*) | `COACH_WHY_TREND` *At this trend you may reach %d %% in about %d s (%s confidence).* | prevista | quella del trend (media o alta) | 80 | 8 s |
| **D4** `warning` | dps, healer | WARNING per soglia (`W ≤ p < D`) o, in `state`, `g = 1` | `COACH_WARNING` *You are close to the risk threshold.* (in `state` `COACH_WARNING_STATE` *Your threat is above the tank's.*) | `COACH_WHY_P_WARNING` *Your threat is %d %% (Warning from %d %%).* (in `state` `COACH_WHY_STATE` *From the game's threat state: no numbers here.*) | rilevata | alta | 60 | 8 s |
| **D5** `safe` | dps, healer | SAFE con un tank noto; in `values` con un trend di confidenza almeno media non oltre +2 punti/s; in `state` `g = 0` | `COACH_SAFE` *The tank has enough margin according to current data.* (in `state` `COACH_SAFE_STATE` *You are below the tank's threat.*) | `COACH_WHY_P_SAFE` *Your threat is %d %%, steady or falling (%s confidence).* (in `state` `COACH_WHY_STATE`) | stimata (`state`: rilevata) | quella del trend (`state`: alta) | 10 | 15 s |
| **A1** `insufficient` | tutti | in combattimento con un mob e nessun'altra regola vera: la riga del giocatore è UNKNOWN, la modalità è `none`, il tank è sconosciuto, o in `values` il trend è *Insufficient data* (§2.5) | `COACH_INSUFFICIENT` *Not enough data for advice.* | il motivo: quelli dell'elenco (*Secret value*, *Stale*, *Insufficient data*…, `WHY_*` di M2.5) o `COACH_WHY_UNKNOWN_TANK` *No one on the list is known to hold the mob.* | — | — | 0 | 0 |

- I quattro messaggi della fonte (§5.2) sono D3, D4, D5 (e T7) e A1. Gli altri sono proposte di questo documento.
- **COA-01** (soglia) è D2, D4, T3, T5; **COA-02** (superamento imminente, *prevista*) è D3 e T4, solo con confidenza
  **media o alta**: con confidenza bassa la regola non vale e si passa alla successiva; **COA-03** (niente ripetizioni) è
  §2.3; **COA-04** e **COA-05** sono §2.4 e i test di M3.3.
- Le chiavi e le parole definitive (inglese e italiano) le fissa M3.3 (`Locales/`), seguendo §2.4; le proposte italiane
  dei quattro messaggi della fonte sono quelle della fonte (*Threat in aumento: valuta di ritardare il burst.*, *Sei
  vicino alla soglia di rischio.*, *Il tank ha un margine sufficiente secondo i dati attuali.*, *Dati insufficienti per
  formulare un consiglio.*).
- Con la previsione spenta da **[probe P4]** (SPEC-03 §2.2) D3 e T4 non valgono mai.

### 2.3 Scelta, durata e cooldown (`Data/Coach.lua`)

- **Quando**: a ogni `THREAT_UPDATED` (dopo `ThreatState`: Coach è più avanti nel TOC, quindi il suo ascoltatore viene
  dopo), a `STATE_CHANGED` e `AGGRO_CHANGED` della riga del giocatore, a `TARGET_CHANGED`, `COMBAT_STARTED` e
  `COMBAT_ENDED`. Una valutazione legge solo la riga del giocatore, il secondo e `ThreatState`, non alloca (ARC-06) e
  costa al più una decina di confronti.
- **Solo in combattimento con un mob**: fuori dal combattimento, senza mob o con il giocatore fuori dalla lista il
  consiglio è **nessuno** (`COACH_TIP(nil)`) e la striscia torna a riposo (§3.1).
- **Cambio**: il consiglio cambia subito quando la sua condizione finisce o quando vale una regola di priorità più
  alta. Una regola di priorità più bassa non toglie quella mostrata finché questa vale.
- **COA-03** MUST: una regola con cooldown che lascia la striscia non torna prima del suo cooldown (8 s, 15 s per le
  rassicurazioni D5 e T7); intanto vale la regola successiva vera, o A1. Le regole con cooldown 0 (aggro, DANGER, tank
  dietro) sono fatti che si mostrano sempre quando sono veri: non lampeggiano perché gli stati sotto hanno isteresi e
  permanenza (MON-10, MON-12).
- **Numeri**: con la stessa regola i numeri del testo (`%d`) si aggiornano al massimo una volta al secondo, perché il
  testo non tremi; `COACH_TIP` si emette solo quando cambia la regola o un numero mostrato.
- Il consiglio (`tip`) è una tabella riusata: `{ rule, role, message, reason, args, otherKey, category, confidence,
  priority, since, mobKey, demo }`; `args` ha al più tre numeri, `otherKey` la chiave dell'unità di `%s`. Mai nomi né
  valori segreti (SPEC-01 §3.3).

### 2.4 Regole di scrittura

Valgono per ogni messaggio e motivazione del Coach e per ogni avviso (chiavi `COACH_*` e `ALERT_*`), in `enUS` e `itIT`;
le prova il test delle parole di M3.3 (`test_coach_wording.lua`).

- **WR-01** MUST (previsioni, categoria *prevista*): il verbo è *may* / *potresti*, *potrebbe*; il tempo è *about* /
  *circa* con i secondi arrotondati per eccesso; mai *will*, *is going to*, *sta per*, *succederà*. Il tooltip dice la
  confidenza. Una previsione con confidenza bassa non si mostra.
- **WR-02** MUST (ipotesi, categoria *ipotesi*): *probably* / *probabilmente*, mai come causa, mai negli avvisi. In M3
  **nessuna** regola è un'ipotesi: la prima (nel report, M4 e oltre) seguirà questa regola.
- **WR-03** MUST (**COA-05**, nessuna causa): nessun messaggio dice perché la threat è salita o perché l'aggro è passata:
  vietate *because*, *due to*, *caused by*, *after your*, *since you*, *perché*, *a causa di*, *per colpa di*, *dovuto a*,
  *dopo il tuo*. La **motivazione** spiega su quali dati poggia il consiglio (percentuali, soglie, trend, stato del
  gioco), non la causa di ciò che succede; T1 lo dice apertamente (*The cause is not known*).
- **WR-04** MUST (**COA-04**, nessuna abilità): nessun nome di abilità, incantesimo, talento, oggetto, postura o
  classe, in nessuna lingua; i verbi restano generici (*ease off your threat*, *delay your burst*). Il test confronta i
  testi con un elenco di parole vietate: le classi (*Warrior*, *Rogue*, *Hunter*, *Mage*, *Priest*, *Warlock*,
  *Paladin*, *Druid*, *Shaman* e in italiano *Guerriero*, *Ladro*, *Cacciatore*, *Mago*, *Sacerdote*, *Stregone*,
  *Paladino*, *Druido*, *Sciamano*) e le abilità di threat più note (*Taunt*, *Growl*, *Feint*, *Fade*, *Cower*,
  *Vanish*, *Feign Death*, *Soulshatter*, *Salvation*, *Mocking Blow*, *Challenging Shout*, *Challenging Roar*, *Sunder
  Armor*, *Shield Slam*, *Righteous Fury*, *Defensive Stance*, *Bear Form* e i nomi italiani del client); l'elenco sta
  nel test e si allunga quando serve.
- **WR-05** MUST: nessuna colpa e nessun giudizio su altre persone (*%s has the mob*, mai *%s stole/pulled it*); nessun
  invito a scrivere in chat o ad avvisare altri.
- **WR-06** SHOULD: messaggi brevi, al massimo **60 caratteri** in `enUS` con gli argomenti più lunghi (nome di 12
  lettere, numeri di 3 cifre); la striscia taglia con *…* e il tooltip mostra tutto. Il presente per i fatti; i numeri
  come nell'elenco (percentuali intere, trend con un decimale).
- **WR-07** MUST: ogni messaggio ha la sua categoria nel tooltip, con le parole di M2.5 (*detected*, *calculated*,
  *estimated*, *predicted*; *hypothesis* da M4).

### 2.5 Solo stato e dati sconosciuti

Il Coach usa solo ciò che il monitor ha, secondo la modalità **della riga del giocatore** (MON-04) e, per T3–T5 e T7,
del secondo:

| Situazione | Avvisi | Coach |
|---|---|---|
| `values` | tutta la tabella di §1.2 | tutte le regole del ruolo |
| `state` (*state only*) | `warning` con `ALERT_WARNING_STATE`, `margin` da `l`, `behind`, `aggro`, `lost`, `pet`, `other` per aggro; nessun `danger` per soglia, nessuna previsione | D1, D2 no, D3 no, D4 e D5 nelle forme `state`, T1–T3, T5–T7 nelle forme `state`, T4 no; motivazione *From the game's threat state: no numbers here* |
| `none`, o riga del giocatore UNKNOWN (`secret`, `missing`, `error`, `no-unit`, `stale`) | nessuno (UNKNOWN non avvisa) | A1 con il motivo della riga |
| tank sconosciuto (*Unknown tank*, SPEC-03 §2.1) | nessun `aggro`, `lost`, `pet`, `other` per aggro finché il detentore non è noto | per il tank A1 con `COACH_WHY_UNKNOWN_TANK`; per gli altri le regole che non lo usano (D2–D4), poi A1 |
| `values` con trend *Insufficient data* (primi istanti, buchi) | quelli di soglia e di aggro | D1, D2, D4 se vere; altrimenti A1 con *Insufficient data* (D5 e D3 vogliono il trend) |
| giocatore non nella lista | quelli su famiglio e altri | nessun consiglio: l'intestazione dice già *You are not on its threat list* |

Righe miste: se il secondo è in `state` mentre il giocatore è in `values`, le regole del tank usano le forme `state`
(SPEC-03 §2.2). Mai un numero inventato (DAT-02): una regola che ha bisogno di un valore che manca non vale.

## 3. La striscia del Coach e l'effetto visivo (`UI/CoachStrip.lua`, `UI/Window.lua`, M3.4)

### 3.1 La striscia

- **Dove**: nella disposizione compatta, sotto l'intestazione del mob e sopra l'intestazione dell'elenco, larga quanto
  il contenuto, alta **18 pt**, su `surface-2`. C'è quando almeno uno è vero: interruttore `coach` acceso e
  `coach.enabled`, oppure interruttore `alerts` acceso, `alerts.enabled` e `alerts.window`; altrimenti non c'è e
  l'elenco si prende lo spazio. Il posto è fisso, così le righe non saltano quando arriva un messaggio.
- **In una finestra bassa**: se con la striscia l'elenco avrebbe meno di due righe, sparisce prima l'intestazione
  dell'elenco (ordinamento e *Me on top* restano nella card *Monitor*); la striscia resta.
- **Contenuto**, da sinistra: striscia di 3 pt (token dello stato per un avviso, `accent` per un consiglio, ST-03);
  per un avviso il distintivo di stato piccolo (icona e parola, ST-02), per un consiglio l'icona `coach`; il testo in
  `Row` `text-1` su una riga, tagliato con *…*; per una base *prevista* l'icona `predict`; per una base *stimata* o
  *prevista* una pastiglia di confidenza in `Badge` (*HIGH*, *MEDIUM* / *ALTA*, *MEDIA*) su `surface-3`; a destra l'icona
  `mute` quando gli avvisi sono silenziati.
- **A riposo**: fuori dal combattimento, con il Coach acceso, *Advice appears during combat* in `text-3`; in
  combattimento senza consiglio la striscia è vuota (solo il posto).
- **Avviso e consiglio**: un avviso prende la striscia per 4 s (`Alerts.HOLD`), poi torna il consiglio corrente; un
  avviso nuovo di gravità uguale o più alta sostituisce quello mostrato (e riparte dai 4 s), uno di gravità più bassa
  non lo copre. Silenziando o riaccendendo la striscia dice *Alerts muted* / *Alerts back on* per 2 s.
- **Tooltip** (al passaggio del mouse; la striscia non ha clic): il testo intero; *Why:* e la motivazione; la categoria
  (*detected*, *calculated*, *estimated*, *predicted*) e la confidenza; *Alert* o *Advice*; da quanto; *Demo:
  invented values* durante la demo; *Alerts muted until the end of this fight* se silenziato.
- Testi nelle due lingue; nessuna API del gioco (`test_api_boundary.lua`); i nomi di `%s` vengono dalle righe del
  modello, come nell'elenco.

### 3.2 L'effetto visivo

- Il **bordo** della finestra (la cornice 9-slice dello sfondo, token `border`) prende il token dello stato dell'avviso
  (`state-warning` o `state-danger`): dissolvenza in entrata di 120 ms, tenuta di **1,5 s**, dissolvenza in uscita di
  320 ms (`UI/Motion.lua`). **Una volta per avviso**, mai a intermittenza ([ui-style §3.2](ui-style.md#32-la-barra-della-threat-widgetsthreatbar-m16-dati-da-m2):
  nessun lampeggio); un avviso più grave durante l'effetto lo riparte, uno uguale o meno grave no.
- Con le animazioni spente: il colore per 1,5 s, senza dissolvenze. Con la finestra chiusa: nulla.
- È un colore su un elemento non testuale (ST-03) e non un bagliore (nessun neon nella compatta, ui-style §3.1).
  Poiché da solo sarebbe un segnale di solo colore, con `alerts.window` spento l'effetto mostra anche l'icona dello
  stato nella pastiglia della barra del titolo per la stessa durata (ST-02).
- `FlashClientIcon` (nel dump) **non** si usa: far lampeggiare la finestra del client è invasivo.

### 3.3 Anteprime

Con `tools/make_mockups.py` ([ADR 0013](../adr/0013-design-previews-original-art-invented-data.md)), in inglese e
italiano, Nebula più Warden: M3.4 `coach-dps` (D3 con la confidenza), `coach-tank` (T4 e il margine), `coach-unknown`
(A1 in *state only* o `none`), `alert-danger` (striscia con l'avviso e il bordo); M3.5 `settings-alerts` (la card,
anche con la nota dell'avviso nativo) e `alert-muted`.

## 4. Configurazione e interruttori

### 4.1 Schema 3 dell'account

Lo schema dell'account passa a **3** con le tabelle `settings.alerts` e `settings.coach`; quello del personaggio resta 1.
La migrazione `Config.migrations.account[3]` non fa nulla (i predefiniti aggiungono le chiavi) ma esiste e ha il suo
test (DAT-20). I predefiniti hanno un solo posto, `Config.ALERTS_DEFAULTS` e `Config.COACH_DEFAULTS` (gli intervalli
`Config.ALERTS`, l'enumerazione `Config.ALERT_OTHERS`), come `Config.MONITOR_DEFAULTS`; li realizza **M3.2** (per gli
avvisi) e **M3.3** (per il Coach), la card **M3.5**. Dettaglio in
[SPEC-02 §3.6](SPEC-02-data-model-storage.md#36-schema-3-m3-avvisi-e-coach).

| Percorso | Tipo | Predefinito | Regola | Uso |
|---|---|---|---|---|
| `settings.alerts.enabled` | booleano | `true` | — | avvisi accesi (spento = *nessun avviso*) |
| `settings.alerts.window` | booleano | `true` | — | messaggio nella finestra (Q12) |
| `settings.alerts.visual` | booleano | `true` | — | effetto visivo (Q12) |
| `settings.alerts.sound` | booleano | `false` | — | suono (Q12) |
| `settings.alerts.cooldown` | intero | `8` | 3–30 (s) | cooldown per tipo e unità (§1.3) |
| `settings.alerts.others` | stringa | `"tank"` | enum `tank`, `always`, `never` | avvisi su altre unità (§1.5) |
| `settings.alerts.pet` | booleano | `true` | — | avviso `pet` (§1.5) |
| `settings.coach.enabled` | booleano | `true` | — | Threat Coach acceso |

Non si salvano: il silenzio, l'esclusione per sessione, i cooldown in corso.

### 4.2 La card *Alerts* (M3.5)

Nella pagina Settings dopo *Monitor* e prima di *Reset*, solo con l'interruttore `alerts` (la parte del Coach solo con
`coach`): *Alerts* (interruttore), *Message in the window*, *Visual effect*, *Sound* (interruttori), *Cooldown*
(cursore 3–30 s, salvato al rilascio), *Alerts about others* (segmentato *When I tank · Always · Never*), *Your pet
takes the mob* (interruttore), la riga delle soglie con il collegamento alla card *Monitor*, la nota dell'avviso
nativo (§1.6), *Threat Coach* (interruttore). Con gli avvisi spenti i controlli dei canali restano visibili ma inattivi.
Con dati in sola lettura le scelte valgono per la sessione, come nella card *Monitor*.

### 4.3 Interruttori (`Core/Features.lua`)

`alerts` e `coach` restano **spenti** fino a M3.R. Spento vuol dire (SPEC-01 §3.4): nessuna striscia, nessuna card,
nessun avviso o consiglio emesso, nessun suono, nessun consumatore dello Scanner, nulla scritto; `/atw mute` e il tasto
rispondono *This arrives in v0.3.0.*; l'evento `AGGRO_CHANGED` di `ThreatState` invece c'è con `monitor` (è un fatto
del monitor). I due interruttori sono indipendenti: il Coach senza avvisi e gli avvisi senza Coach funzionano.

## 5. Moduli, eventi e diagnostica

| File | Responsabilità | Bus | Step |
|---|---|---|---|
| `Data/ThreatState.lua` (cambio) | `AGGRO_CHANGED` (§1.1): l'ultimo detentore noto per mob | emette `AGGRO_CHANGED(mobKey, unitKey, oldUnitKey)` | M3.2 |
| `Data/Alerts.lua` | tipi (§1.2), cooldown e raffiche (§1.3), canali, suono attraverso Compat, silenzio, esclusioni, consumatore dello Scanner | ascolta `STATE_CHANGED`, `AGGRO_CHANGED`, `COMBAT_ENDED`, `CONFIG_LOADED`, `CONFIG_CHANGED`, `DEMO_CHANGED`; emette `ALERT_RAISED(alert)`, `MUTE_CHANGED(muted)` | M3.2 |
| `Data/CoachRules.lua` | la tabella di §2.2: dati e condizioni, senza stato | — | M3.3 |
| `Data/Coach.lua` | ruolo, scelta, cooldown, numeri (§2.3) | ascolta `THREAT_UPDATED`, `STATE_CHANGED`, `AGGRO_CHANGED`, `TARGET_CHANGED`, `COMBAT_STARTED`, `COMBAT_ENDED`, `CONFIG_CHANGED`; emette `COACH_TIP(tip)` (`nil` = nessun consiglio) | M3.3 |
| `UI/CoachStrip.lua` | la striscia (§3.1), costruita dalla vista di `UI/ThreatList.lua` | ascolta `ALERT_RAISED`, `COACH_TIP`, `MUTE_CHANGED`, `CONFIG_CHANGED`, `THEME_CHANGED` | M3.4 |
| `UI/Window.lua` (cambio) | l'effetto del bordo (§3.2) | ascolta `ALERT_RAISED` | M3.4 |
| `UI/Settings.lua`, `Core/Commands.lua`, `Bindings.xml` | card *Alerts*, `/atw mute`, il tasto, il menu della riga | — | M3.5 |

- **L'avviso** (`ALERT_RAISED`) è una tabella da un anello di 8 riusate (chi la conserva la copia, come farà il
  Recorder): `{ kind, severity, state, reason, subject ("self", "pet", "other"), unitKey, otherKey, mobKey, message,
  args, category, confidence, at, muted, demo, window, visual, sound }`, gli ultimi tre i canali davvero usati
  (`sound` solo se il suono è partito). `args` ha al più un numero e il `%s`, quando c'è, viene prima.
- **`/atw debug`** (sezione *Alerts and Coach*): interruttori e impostazioni, silenzio, avvisi emessi per tipo, in
  cooldown e scartati, età dell'ultimo, stato di `ui.PlaySound` e di `threat.WarningEnabled`, regola corrente del Coach
  e numero di consigli. Mai nomi.
- La registrazione (M4) ascolterà `ALERT_RAISED` e `COACH_TIP` e conserverà categoria e confidenza (DAT-04).

## 6. Piano di M3: test per step

Ogni test che passa per il monitor gira sui tre esiti del probe (`Fight.OUTCOMES`, [SPEC-08 §2](SPEC-08-quality-probe-release.md#2-test-offline)).

| Step | Test e casi |
|---|---|
| **M3.2** | `test_alerts.lua`: un avviso per entrata, nessuno per le discese e per UNKNOWN; da UNKNOWN solo sopra l'ultimo stato noto; ogni riga di §1.2 (giocatore, famiglio, altri, tank) nelle modalità `values` e `state`, niente in `none`; un solo avviso quando `STATE_CHANGED` e `AGGRO_CHANGED` arrivano insieme; cambio fra due tank designati senza avviso; **raffiche** (dieci entrate in un secondo → un avviso), **oscillazione** attorno alle soglie attraverso `ThreatState` (al più un avviso per tipo ogni cooldown), **cambio di target durante il cooldown** (stesso tipo: nessuno; tipo più grave: sì), `OTHER_GAP` e `SOUND_GAP`; **silenzio** (nessun canale, `muted = true`, finisce a `COMBAT_ENDED` o alla fine del prossimo combattimento, non sopravvive a un `/reload`); **esclusioni** (`others` nelle tre scelte, `pet`, esclusione per sessione); canali (finestra, effetto, suono solo per gravità 2–3 e solo se acceso; `ui.PlaySound` mancante o in errore senza errore); **mai chat** (nessuna chiamata a funzioni di chat nel mock, nessuna riga stampata da Alerts); demo (solo finestra, mai suono); consumatore dello Scanner; interruttore spento (nulla). In `test_threat_state.lua` i casi di `AGGRO_CHANGED`. In `test_config.lua` lo schema 3 per gli avvisi. Test lungo `Tests/long/test_alerts_raid.lua`: un raid da 40 per 30 minuti con `others = always`, avvisi al minuto entro il limite di §1.3, nessuna crescita di memoria |
| **M3.3** | `test_coach.lua`: ogni regola di §2.2 per ogni ruolo e nelle forme `state`; priorità; cooldown e ritorno (COA-03); numeri al massimo una volta al secondo; previsioni solo con confidenza media o alta; ogni riga di §2.5; nessun consiglio fuori dal combattimento, senza mob o fuori dalla lista; da soli senza altri; nessuna allocazione per aggiornamento dopo il riscaldamento; interruttore spento. `test_coach_wording.lua`: §2.4 su tutte le chiavi `COACH_*` e `ALERT_*` nelle due lingue (parole vietate, *may*/*potresti* nelle previsioni, lunghezza), chiavi presenti in `enUS` e `itIT` (ADR 0009). In `test_config.lua` lo schema 3 per il Coach |
| **M3.4** | `test_coach_strip.lua`: la striscia in ogni situazione di §3.1 (riposo, consiglio, avviso per 4 s poi il consiglio, gravità, silenzio, demo), tooltip con motivazione, categoria e confidenza, pastiglia solo per stimata e prevista, finestra bassa; l'effetto del bordo una volta per avviso, con e senza animazioni, l'icona nella barra del titolo senza il messaggio; testi nelle due lingue; nessuna API del gioco. Pagina del manuale *Alerts and Coach* nelle due lingue con le anteprime |
| **M3.5** | `test_settings.lua` (la card, la nota dell'avviso nativo con `IsThreatWarningEnabled` vero, falso, mancante), `test_commands.lua` (`/atw mute` nelle due lingue e in ogni stato), `test_bindings.lua` (`Bindings.xml`, la funzione globale, i nomi), il menu della riga in `test_threat_list.lua`; pagine *Settings* e *Commands* del manuale |

## 7. Cosa aspetta il probe e il gioco

- **[probe P2]** i significati di `g` e `l` (§1.2, §2.2); **[probe P3]** quale modalità ci sarà in gruppo e in istanza
  (§2.5); **[probe P4]** se la previsione resta accesa (D3, T4, `ALERT_WARNING_PREDICTED`); **[probe P5]** l'opzione
  *solo sul target corrente* (M7); **[probe P6]** quanto presto arriva un avviso dopo il passaggio vero (eventi o tick);
  **[probe P9]** ruoli e quindi il ruolo del Coach e i tipi `lost`, `pet`, `other`.
- **[da provare in gioco]** (checklist M3.6): il kit sonoro 8959 su Forever e il suo volume; il tasto nelle
  impostazioni dei tasti del gioco; che cosa fa l'avviso nativo e se si duplica; la leggibilità della striscia e
  dell'effetto del bordo in combattimento; se 8 s di cooldown sono giusti (Q12); se i messaggi aiutano davvero (Q11).
