# SPEC-04: Avvisi e Threat Coach

> Fonte: [specifiche originali](source-specification.md) §5.2, §6.3. Da completare in **M3.1**.

## 1. Avvisi

| Canale | Predefinito |
|---|---|
| Messaggio nella finestra (striscia del Coach) | acceso |
| Effetto visivo (bordo che pulsa, bagliore) | acceso |
| Suono | spento |
| Nessun avviso | — |

Opzioni: soglia WARNING; soglia DANGER; cooldown (predefinito proposto 8 s per tipo); solo in combattimento (acceso);
solo sul target corrente (acceso); esclusione di unità specifiche; disattivazione rapida (`/atw mute`, tasto
assegnabile).

- **ALR-01** MUST: un avviso scatta quando la condizione **entra** (passaggio di stato), non a ogni aggiornamento.
- **ALR-02** MUST: niente messaggi vocali né annunci in chat come impostazione predefinita; nessuno spam in party o
  raid ([ADR 0001](../adr/0001-local-only-addon-no-network.md)).
- **ALR-03** SHOULD: se l'avviso nativo della threat del gioco è attivo (`IsThreatWarningEnabled`), il manuale lo dice e
  propone di non duplicarlo.

## 2. Threat Coach

Suggerimenti semplici basati su regole, ciascuno con **motivazione breve** e, quando utile, **confidenza** (alta, media,
bassa).

Regole iniziali (fonte §5.2):

1. **COA-01** avvisare quando la percentuale supera una soglia configurata;
2. **COA-02** avvisare quando il trend indica un possibile superamento imminente (categoria *prevista*);
3. **COA-03** evitare la ripetizione con un cooldown;
4. **COA-04** non consigliare abilità specifiche finché disponibilità, cooldown e condizioni non sono verificabili;
5. **COA-05** non dichiarare mai la causa esatta di una perdita di aggro senza evidenza.

Messaggi di esempio (chiavi di locale, enUS e itIT): *Threat rising: consider delaying your burst.* — *You are close to
the risk threshold.* — *The tank has enough margin according to current data.* — *Not enough data for advice.*

Ruoli coperti dai primi suggerimenti: tank, DPS, healer, con messaggi per ruolo e nessun consiglio di classe (Q11).
