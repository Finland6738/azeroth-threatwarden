# SPEC-05: Registrazione, report, timeline e replay

> Fonte: [specifiche originali](source-specification.md) §5.3, §5.4, §7.4. Da completare in **M4.1** (§1–§3) e
> **M5.1** (§4–§5).

## 1. Recorder (M4)

- **REC-01** MUST: la sessione si apre all'inizio del combattimento (`PLAYER_REGEN_DISABLED` o il primo campione con
  threat, **[verificare]** P7) e si chiude alla fine (uscita dal combattimento più un breve ritardo per i pull a catena).
- **REC-02** MUST: campioni con frequenza configurabile, solo durante il combattimento, con limiti di unità e mob.
- **REC-03** MUST: eventi registrati se disponibili: inizio e fine, cambio di target del mob, cambio di tank, morte
  (del tank, di un DPS, del mob), superamento di soglia, mob che scompare. Taunt e abilità solo se identificabili in
  modo affidabile (P7), altrimenti no.
- **REC-04** MUST: protezione da sessioni doppie o incomplete; logout, `/reload` e disconnessione chiudono la sessione
  come incompleta.
- **REC-05** MUST: nessuna ricostruzione retroattiva dal combat log ([ADR 0004](../adr/0004-threat-from-the-unit-threat-api-sampled-in-combat.md)).

## 2. Storage (M4)

Formato compatto per colonne in `db.sessions` ([SPEC-02 §4](SPEC-02-data-model-storage.md#4-sessioni-registrate-da-completare-in-m41)),
schema 2 con migrazione, limiti configurabili (Q8), eliminazione delle più vecchie, dati danneggiati messi da parte
senza bloccare l'addon. Stima della dimensione visibile nelle impostazioni.

## 3. Report di fine combattimento (M4)

Riepilogo essenziale: durata; mob principale; tank osservati e cambi di tank; superamenti di soglia per giocatore; tempo
in WARNING e DANGER; percentuale massima osservata; momenti di perdita dell'aggro; percentuale di campioni validi.

- **REC-10** MUST: ogni metrica è riconducibile ai campioni registrati; con dati insufficienti la riga dice
  "Insufficient data".
- **REC-11** MUST: nessuna causa attribuita; al massimo un'*ipotesi* etichettata come tale ("probably").
- Il report si apre dalla scheda *Reports* e, se il giocatore lo vuole, come piccola notifica a fine scontro.

## 4. Timeline (M5)

Rappresenta nel tempo: threat del tank, giocatori più vicini alla soglia, percentuale relativa, cambi di target,
eventi, momenti di superamento. Supporta selezione di un intervallo, pausa e riproduzione, salto avanti e indietro,
dettaglio del campione, **distinzione visiva tra dati rilevati e stime** (linea piena e tratteggiata) e buchi visibili.

## 5. Replay (M5)

Elenco degli ultimi scontri con durata; timeline; eventi in ordine cronologico; selezione di un evento per vedere i
dati attorno (±5 s); indicazione dei dati mancanti; eliminazione delle registrazioni.
