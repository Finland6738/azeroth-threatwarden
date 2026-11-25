# Stile dell'interfaccia: Threatwarden nella famiglia di FDCP e Accord

> Specifica dello step **M1.1**. Vale per M1.6 (media, font, tema, widget), M1.7 (finestra), M1.8 (Settings, Info,
> anteprime) e, per le barre e gli stati, per M2.5 (elenco della threat). Decisione in
> [ADR 0015](../adr/0015-interface-follows-the-ecosystem-style.md).

## 0. Base e come si legge

La **base** è `docs/specs/ui-style.md` di Azeroth Accord (`../azeroth-accord`), che a sua volta scrive solo le
differenze da quello di Finland Dragon Credit Points (`../finland-dragon-credit-points`): stesso proprietario,
GPL-3.0. Questo documento **non ripete** nessuno dei due: scrive solo le **differenze da Accord**. Dove qui non si dice
nulla vale Accord, e dove Accord non dice nulla vale FDCP: token e loro uso (FDCP §2.1), forme, ombre, movimento e
spaziatura (FDCP §2.2), tipografia (FDCP §2.3), componenti e come si costruiscono in gioco (FDCP §3, Accord §3 stato
M6.11–M6.14), font e licenze (FDCP §4), texture e prestazioni (FDCP §7), anteprime (Accord §8).

I due progetti si **leggono soltanto**: i file si copiano e si adattano ai nomi di Threatwarden, senza libreria
condivisa ([ADR 0012](../adr/0012-reuse-accord-and-unspoken-foundations.md)). Regole che non cambiano: nessuna arte di
Blizzard nel repository, ogni testo una chiave di lingua (`enUS` e `itIT`), nessun colore scritto fuori da
`UI/Theme.lua` (`tools/check_addon.py`, `-- theme-ok` per le eccezioni come in Accord).

La differenza di fondo: Accord è un pannello da leggere con calma, Threatwarden è anche una **sovrapposizione da
combattimento**, piccola, leggibile in movimento e con il daltonismo. Per questo ha una disposizione compatta (§3), le
barre della threat e quattro **token di stato** uguali in ogni tema (§4.2).

## 1. Nomi e prefissi

| Cosa | Azeroth Accord | Azeroth Threatwarden |
|---|---|---|
| Cartella dell'addon e percorso dei media | `AzerothAccord/Media/` | `AzerothThreatwarden/Media/` (`Interface\AddOns\AzerothThreatwarden\Media\`) |
| Dati salvati | `AzerothAccordDB`, `AzerothAccordCharDB` | `AzerothThreatwardenDB` (account), `AzerothThreatwardenCharDB` (personaggio), [SPEC-02 §3](SPEC-02-data-model-storage.md#3-savedvariables) |
| Oggetti font (`CreateFont`) | `AzerothAccordFont<Id>` | `AzerothThreatwardenFont<Id>`: gli `<Id>` di Accord (`Display`, `DisplaySmall`, `H1`, `H2`, `Body`, `BodyMedium`, `Small`, `Eyebrow`, `Th`, `Tab`, `Button`, `Mono`, `MonoMedium`, `MonoSmall`) più `TabCompact`, `Row`, `RowMono` e `Badge` (§3.1) |
| Spazio dei nomi del codice | `ns.Theme`, `ns.Assets`, `ns.Motion`, `ns.Widgets` | gli stessi (`AzerothThreatwarden.Theme`… nei test) |
| Frame con nome | `AzerothAccord…` | `AzerothThreatwarden…` (`AzerothThreatwardenWindow`, `AzerothThreatwardenTooltip`), [SPEC-01](SPEC-01-platform-architecture.md) ARC-04 |
| Chiavi di lingua | `Locale/enUS.lua`, `itIT.lua` | `Locales/enUS.lua`, `itIT.lua`, registrate con `ns.Locale.Register` ([SPEC-01 §10](SPEC-01-platform-architecture.md#10-lingue-corelocalelua)) |
| Comandi | `/accord`, `/acc` | `/threatwarden`, `/atw` |
| Temi | Nebula, Aurora, **Accord** | Nebula, Aurora, **Warden** (non c'è un tema Accord) |

I file media hanno i nomi di Accord (`rr_fill_8`, `rr_ring_12`, `shadow`, `glow_s`, `logo_256`, `logo_64`, `icons`…)
più i loghi NEBULA e, dal M1.6, `rr_fill_4` e `rr_ring_4` (la barra della threat) e `dash` (il tratteggio dello stato
sconosciuto, ripetuto in orizzontale); il foglio di icone aggiunge le icone di §3.4. `logo_256` è il logo intero,
`logo_64` il riquadro intorno allo scudo, perché a 18 pt si legga. `UI/Assets.lua` resta la tabella unica di texture e
font.

## 2. Impostazioni dell'aspetto

Come Accord §2: per **account**, perché sono gusti della persona. Chiavi, tipi e predefiniti in
[SPEC-02 §3.2](SPEC-02-data-model-storage.md#32-schema-1-account-azeroththreatwardendb):

| Chiave | Valori | Predefinito |
|---|---|---|
| `account.settings.theme` | `nebula`, `aurora`, `warden` | `nebula` |
| `account.settings.effects` | booleano: bagliori e testo neon | `true` |
| `account.settings.animations` | booleano: tutto il movimento di `Motion` | `true` |
| `account.settings.font` | `addon` (Orbitron, Outfit, JetBrains Mono) o `game` | `addon` |

Differenza da Accord: le quattro chiavi sono già nello **schema 1** (Accord le aggiunse con una migrazione 1 → 2), e
accanto c'è `account.settings.language`. Il cambio si vede subito tranne il font (al riavvio del client) e la lingua
(dopo `/reload`). `Config:Set` emette `CONFIG_CHANGED`, `Theme` ridipinge ed emette `THEME_CHANGED(themeId)`.

## 3. Finestra compatta, barre e stati

### 3.1 Densità

La finestra ha due disposizioni ([SPEC-03 §4.2](SPEC-03-threat-monitor-ui.md#42-due-disposizioni-una-finestra)). La
**ampia** (Settings, Info, Reports) segue Accord §3 così com'è: barra del titolo, schede da 36 pt con l'indicatore da
2 pt, colonna di card larga fino a 520 pt, raggio 12, ombra. La **compatta** (Monitor) cambia la densità di FDCP:

| Elemento | Accord / FDCP | Compatta di Threatwarden |
|---|---|---|
| Barra del titolo | 52 pt, logo, nome in Orbitron 20–26 pt | 28 pt, logo 18 pt, `THREATWARDEN` in `DisplaySmall` (Orbitron 12 pt), pastiglia dello stato del modulo |
| Schede | 44 pt (36 pt nella ampia di Threatwarden, font `Tab` 14 pt) | 24 pt, testo `TabCompact` (Outfit Medium 11 pt), indicatore da 2 pt |
| Righe | 36–40 pt, testo 13 pt | **20 pt**, testo `Row` (Outfit Medium 11 pt), numeri `RowMono` (JetBrains Mono Medium 11 pt) |
| Interno | 20 pt, card distanziate 14–16 | 8 pt, nessuna card: le righe stanno direttamente su `surface-1` |
| Raggio e ombra | 12, ombra morbida | 8, ombra più leggera (la finestra sta sopra il mondo, non sopra altre finestre) |
| Testo minimo | 10 pt | 10 pt (`Badge`, Outfit SemiBold 9 pt maiuscolo, solo dentro il distintivo di stato) |
| Effetti | un elemento neon per vista | nessun neon e nessun bagliore nella compatta: niente distrae dal combattimento; il bagliore del logo resta nella ampia |

### 3.2 La barra della threat (`Widgets.ThreatBar`, M1.6; dati da M2)

- Binario `surface-3`, alto 10 pt nella riga da 20 pt, raggio 4 (9-slice `rr_fill_4`, aggiunta in M1.6).
- Riempimento nel **token di stato** della riga (§4.2), largo `min(scaledPercent, 100) %`; oltre 100 % il binario è
  pieno e una tacca di 2 pt `text-1` segna il superamento.
- Tacche di soglia: 1 pt `border-strong` alle soglie WARNING e DANGER (le soglie di
  [SPEC-03 §2](SPEC-03-threat-monitor-ui.md#2-stati-e-soglie)).
- Il numero sta **a destra** della barra, mai sopra: `RowMono` `text-1` (`87 %`). Un valore stimato ha il prefisso `~` e
  `text-2`; una previsione l'icona `predict` e la parola *may* nel tooltip ([ADR 0003](../adr/0003-data-reliability-categories.md)).
- **Sconosciuto**: nessun riempimento, contorno tratteggiato `state-unknown` sul binario, `?` al posto del numero e il
  tooltip con il motivo (*Secret value*, *Not available*, *Insufficient data*, *Stale*). Mai una barra vuota che sembri
  0 %.
- Il tank: icona `tank` `text-2` prima del nome; la barra mostra il margine sul secondo (MON-11) con la stessa regola.
- La propria riga: anello di 1 pt `accent` intorno alla riga (non un colore di fondo, che si confonderebbe con gli
  stati).
- Movimento: la larghezza scorre in 120 ms (`OUT`) se le animazioni sono accese; il colore cambia con una dissolvenza
  di 120 ms. **Nessun lampeggio** (mai più di un cambio al secondo per riga, nessun effetto a intermittenza).

### 3.3 Il distintivo di stato (`Widgets.StateBadge`, M1.6; dati da M2)

Una pillola alta 14 pt nella riga (18 pt nell'intestazione del mob): icona di stato 10 pt e parola in `Badge`, tutte e
due in `on-state` sul riempimento del token di stato. Una striscia di 3 pt sul bordo sinistro della riga ripete il
colore. Lo stato sintetico dell'intestazione usa lo stesso distintivo, più grande.

### 3.4 Icone nuove

Nel foglio di icone (bianco, celle di 16 px, generato da `tools/make_media.py`, nessuna arte di Blizzard):

| Icona | Uso |
|---|---|
| `state-safe` (scudo con spunta), `state-warning` (triangolo con `!`), `state-danger` (ottagono con `!!`), `state-unknown` (cerchio vuoto con `?`: gli altri tre sono pieni, M1.6) | distintivo di stato; forme diverse perché i quattro colori hanno la stessa luminanza (§4.2) |
| `lock`, `unlock` | blocco della finestra |
| `tank` | chi tiene il mob |
| `trend-up`, `trend-down`, `trend-flat` | trend (stimato) |
| `predict` | valore previsto |
| `stale` | dato vecchio |

## 4. Il tema Warden e i token di stato

### 4.1 Token del tema Warden

- **Nebula** (predefinito, scuro) e **Aurora** (chiaro): i token di FDCP §2.1, invariati (come in Accord).
- **Warden** (scuro), dalla palette del logo (`assets/logo-source.webp`): fondo verde-petrolio profondo (dominante
  `#071419`), cornice di **bronzo invecchiato** (`#AD8E5D` nelle luci, `#6F5534` nei mezzi toni), testo d'oro antico e
  il bagliore **verde menta** al centro dello scudo (`#ACEDBA` nel nucleo, `#88CDA3` e `#549073` intorno). Prende il
  posto che in Accord ha il tema Accord, da cui si distingue: accento di bronzo invece dell'oro saturo dello stendardo,
  testo color pergamena invece del bianco menta, fondo più blu.

| Token | Warden | Uso (come in FDCP §2.1) |
|---|---|---|
| `bg` | `#06141A` | fondo della finestra |
| `surface-1` | `#0B1D22` | card, barra del titolo, schede, righe del monitor |
| `surface-2` | `#11272B` | intestazioni di tabella, campi, riga al passaggio del mouse |
| `surface-3` | `#173135` | chip, binario della barra, pulsante secondario |
| `raised` | `#1E3B3E` | segmento selezionato, toast |
| `border-subtle` | `rgba(239,232,216,.08)` | divisori di riga, bordo card |
| `border` | `rgba(239,232,216,.14)` | bordo finestra, campi |
| `border-strong` | `rgba(239,232,216,.26)` | card aperta, tacche di soglia |
| `text-1` / `text-2` / `text-3` | `#EFE8D8` / `#CFC5AE` / `#9F9A86` | testo principale (pergamena), secondario, attenuato |
| `on-accent` | `#221605` | testo sul pulsante principale |
| `accent` | `#C89B58` | il bronzo della cornice: selezione, indicatore della scheda, pulsante principale |
| `accent-hover` | `#DDB676` | passaggio del mouse sull'accento |
| `accent-text` | `#D9B57A` | l'oro delle rune: numeri, sopratitoli, colonna ordinata |
| `accent-2` | `#5FAE86` | secondo colore del gradiente del pulsante (menta) |
| `neon` / `neon-core` | `#9BEBC0` / `#4FA37C` | un solo elemento neon per vista (solo nella disposizione ampia): il bagliore dello scudo |
| `ok` / `warn` / `err` | `#5CCB8D` / `#F2B33D` / `#FF6B5E` | esiti dell'interfaccia (salvato, attenzione, errore), **non** gli stati della threat |
| `highlight` | `rgba(255,255,255,.06)` | riga di luce di 1 px in cima alla card |
| `scrim` | `rgba(2,9,12,.72)` | velo dei dialog |
| `grad-1` … `grad-4` | `#D9B57A → #A8D9A0 → #5FAE86 → #1F6B5C` | barre sottili, timer (oro → menta → verde profondo) |

Il bronzo dell'accento è più chiaro del bronzo medio del logo per reggere il testo scuro sopra; il fondo è più scuro di
quello del logo per lasciare ai gradini di superficie lo spazio che hanno in Nebula. Effetti neon, bagliori `ADD` e
testo neon del titolo come in Nebula; i colori di classe restano quelli del gioco.

### 4.2 I quattro token di stato

Gli stati della threat hanno token **propri**, fuori dai temi e **identici in Nebula, Aurora e Warden**
([ADR 0015](../adr/0015-interface-follows-the-ecosystem-style.md) regola 4). `ok`, `warn` ed `err` restano per gli
esiti dell'interfaccia e cambiano con il tema; gli stati no, così un giocatore li riconosce anche cambiando tema.

| Token | Valore | Icona | Parola (`enUS` / proposta `itIT`) | Chiave di lingua |
|---|---|---|---|---|
| `state-safe` | `#299159` (verde) | `state-safe` | SAFE / SICURO | `STATE_SAFE` |
| `state-warning` | `#B07309` (ambra) | `state-warning` | WARNING / ATTENZIONE | `STATE_WARNING` |
| `state-danger` | `#E5473C` (rosso) | `state-danger` | DANGER / PERICOLO | `STATE_DANGER` |
| `state-unknown` | `#6F819A` (grigio-blu, anche per i dati neutri) | `state-unknown` | UNKNOWN / SCONOSCIUTO | `STATE_UNKNOWN` |
| `on-state` | `#0A0F14` | — | inchiostro di parola e icona dentro il distintivo | — |

Regole (le controlla `Tests/test_theme.lua`, M1.6):

- **ST-01** MUST: i token di stato stanno in `Theme.STATE`, non in `Theme.themes`; nessun tema li ridefinisce.
- **ST-02** MUST: uno stato si mostra sempre con **icona e parola** insieme, mai con il solo colore; la parola sta
  dentro il distintivo, in `on-state` sul riempimento (contrasto ≥ 4,5:1), mai come testo colorato su una superficie.
- **ST-03** MUST: su una superficie il colore di stato colora solo elementi non testuali (riempimento della barra,
  striscia del bordo, icona fuori dal distintivo), con contrasto ≥ 3:1 su **ogni** superficie di **ogni** tema.
- **ST-04**: per reggere insieme lo scuro e il chiaro i quattro riempimenti hanno la **stessa luminanza** (≈ 0,215):
  in scala di grigi sono uguali, per questo forma dell'icona e parola portano il significato. La tavolozza per il
  daltonismo (M8) cambia le tinte, non queste regole.
- **ST-05** MUST: `GetThreatStatusColor` del gioco non si usa mai per disegnare (solo confronto nei test del probe).
- Le parole italiane sono una proposta: M2.5 le fissa nei file di lingua (*Sconosciuto* è già in
  [SPEC-00 §4](SPEC-00-vision-scope.md#4-affidabilità-dei-dati-vincolante)).

### 4.3 Contrasto

Formula WCAG 2.x (luminanza relativa, `(L1+0,05)/(L2+0,05)`), con le regole di Accord §4.2; il valore è il **peggiore**
fra le superfici indicate. `Tests/test_theme.lua` (M1.6) ricalcola tutto da `UI/Theme.lua` e la tabella e il codice
devono dire la stessa cosa.

**Tema Warden**

| Regola | Minimo | Peggiore caso (Warden) |
|---|---|---|
| `text-1` e `text-2` su ogni superficie (`bg`, `surface-1/2/3`, `raised`) | 4,5:1 | `text-2` su `raised`: **7,00** (`text-1`: 9,83) |
| `text-3` su `bg`, `surface-1`, `surface-2` | 3:1 | **5,52** |
| `accent-text` su `bg`, `surface-1`, `surface-2` | 4,5:1 | **8,04** |
| `on-accent` su `accent` | 4,5:1 | **6,99** (su `accent-hover` 9,31) |
| `ok`, `warn`, `err` su `surface-1` | 4,5:1 | `err`: **6,20** (`ok` 8,56, `warn` 9,31) |
| `ok`, `warn`, `err` su `surface-3` e `raised` | 3:1 | `err` su `raised`: **4,29** (`ok` 5,93, `warn` 6,45) |
| `accent` su `bg` (elementi non testuali) | 3:1 | **7,38** |

**Token di stato** (uguali nei tre temi; superfici `bg`, `surface-1`, `surface-2`, `surface-3`, `raised`)

| Token | `on-state` sul riempimento (min 4,5:1) | Nebula, peggiore (min 3:1) | Aurora, peggiore | Warden, peggiore |
|---|---|---|---|---|
| `state-safe` `#299159` | **4,85** | 3,95 (`raised`) | 3,23 (`surface-3`) | 3,02 (`raised`) |
| `state-warning` `#B07309` | **4,86** | 3,96 (`raised`) | 3,23 (`surface-3`) | 3,03 (`raised`) |
| `state-danger` `#E5473C` | **4,85** | 3,96 (`raised`) | 3,23 (`surface-3`) | 3,03 (`raised`) |
| `state-unknown` `#6F819A` | **4,84** | 3,95 (`raised`) | 3,24 (`surface-3`) | 3,02 (`raised`) |

Tutte le regole sono rispettate. Il margine dei token di stato è stretto per costruzione (un colore uguale su fondi
scuri e chiari), quindi un valore non si cambia senza ricalcolare la tabella; le righe del monitor stanno su
`surface-1`, dove il peggiore è 4,88 (Nebula), 3,96 (Aurora) e 4,35 (Warden).

## 5. Logo e crediti

| Elemento | Dove |
|---|---|
| Logo dell'addon (`assets/logo-source.webp`, lo scudo runico) | barra del titolo (18 pt nella compatta, 24 pt nella ampia), pulsante della minimappa, voce dell'Addon Compartment (`## IconTexture`), pagina Info; texture `logo_256` e `logo_64` generate da `tools/make_media.py` (M1.6); attenuato al 20 % dietro il testo della scheda Monitor vuota |
| Loghi NEBULA (`assets/nebula-logo-dark.png`, `assets/nebula-logo-light.png`) | solo nei crediti (Info, M1.8): quello scuro in Nebula e Warden, quello chiaro in Aurora; usati con il permesso della gilda |
| Crediti | *Created and designed by Finland. Made with the Italian guild NEBULA.*, link alla pagina di NEBULA, repository e segnalazioni (caselle da copiare), licenza GPL-3.0, `docs/third-party.md`, avviso di fan-made non affiliato a Blizzard |

Il nome pubblico è solo "Finland": nessun nome reale, e-mail o percorso personale in nessun file.

## 6. Quale sezione usa ogni step

| Step | Accord `ui-style.md` (e FDCP attraverso di lui) | Questo documento |
|---|---|---|
| **M1.6** media, font, tema, widget | §1, §2, §4 (e FDCP §2–§5, §7, §9) | §1, §2, §3.1–§3.4, §4 |
| **M1.7** finestra, schede, minimappa | §3 (finestra autonoma, schede) | §3.1, §5; [SPEC-03 §4](SPEC-03-threat-monitor-ui.md#4-finestra) |
| **M1.8** Settings, Info, anteprime | §3 (Settings), §5, §8 | §2, §5; anteprime in Nebula, Aurora e Warden, in inglese e italiano ([ADR 0013](../adr/0013-design-previews-original-art-invented-data.md)) |
| **M2.5** elenco della threat | §3 (tabella, righe da pool) | §3.2, §3.3, §4.2 |

## 7. Cosa non è verificato nel client

I media, il tema e il kit esistono dal M1.6 e sono provati solo offline: **nulla è stato provato nel client vero**. Oltre a ciò che Accord §7 e FDCP §7
elencano (TGA e font su Forever, 9-slice a scala frazionaria, fusione `ADD`, colore degli oggetti font, menu senza
`UIDropDownMenu`), per Threatwarden:

- l'aspetto del tema **Warden** su schermo (i colori sono presi da un'immagine, non da una prova);
- la leggibilità della disposizione compatta a 220 × 140 pt, delle righe da 20 pt e del testo da 10–11 pt in
  movimento, alle scale dell'interfaccia comuni e con le UI personalizzate;
- i quattro colori di stato con la stessa luminanza: distinguibili in combattimento grazie a icone e parole?
- le icone di stato a 10 pt;
- il tratteggio della barra sconosciuta (texture ripetuta alta 1 pt) e il raggio 4 della barra;
- il logo come icona del Compartment e della minimappa;
- la larghezza delle schede compatte e dei distintivi in italiano (*ATTENZIONE*, *SCONOSCIUTO*).
