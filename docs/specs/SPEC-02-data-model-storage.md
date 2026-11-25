# SPEC-02: Modello dati e salvataggio

> Fonte: [specifiche originali](source-specification.md) §5.4, §7.3–§7.5. Da completare in **M1.1** (impostazioni) e
> **M4.1** (registrazioni).

## 1. `ThreatRecord` (in memoria)

Il modello normalizzato di una lettura, per coppia (unità osservata, mob):

```lua
ThreatRecord = {
    unitGUID = nil,          -- GUID dell'unità osservata, nil se segreto o non disponibile
    unitName = nil,          -- nome mostrato; mai salvato fuori dalle sessioni (§3)
    mobGUID = nil,           -- GUID del mob
    mobName = nil,
    isTanking = nil,         -- bool o nil
    situation = nil,         -- 0..3 (UnitThreatSituation) o nil
    scaledPercent = nil,     -- 0..100+: 100 = prende l'aggro; nil se segreto
    rawPercent = nil,
    rawThreat = nil,
    observedAt = 0,          -- GetTime() della lettura
    source = "detected",     -- detected | calculated | estimated | predicted | hypothesis | unknown
    confidence = "unknown",  -- high | medium | low | unknown
    reason = nil,            -- perché manca: "secret", "nil", "error", "no-unit", "stale"
}
```

- **DAT-10** MUST: un campo segreto o assente resta `nil` con `reason`; mai `0` al posto di "sconosciuto".
- **DAT-11** MUST: i record sono riusati da un pool ([SPEC-01](SPEC-01-platform-architecture.md) ARC-06).
- **DAT-12** MUST: una lettura più vecchia della soglia di freschezza (predefinita: 2 intervalli di campionamento)
  diventa `stale` e l'interfaccia lo mostra.

## 2. Valori calcolati

| Valore | Formula | Categoria |
|---|---|---|
| Percentuale rispetto al tank | `scaledPercent` dell'unità (il client già considera la regola del 110 % / 130 %) | rilevata |
| Margine (Threat Margin) | `100 − scaledPercent`, in punti percentuali | calcolata |
| Trend | pendenza di `scaledPercent` sugli ultimi N campioni validi (N ≥ 3) | stimata |
| Tempo al superamento | margine / trend, solo se trend > 0 e confidenza ≥ media | prevista |

Dettagli e soglie in [SPEC-03](SPEC-03-threat-monitor-ui.md) e [SPEC-04](SPEC-04-alerts-coach.md).

## 3. SavedVariables

`AzerothThreatwardenDB` (account) e `AzerothThreatwardenCharDB` (personaggio), ciascuna con `schema`
([ADR 0005](../adr/0005-embedded-ace3-savedvariables-and-schema-versions.md)).

| Chiave | Contenuto | Schema | Milestone |
|---|---|---|---|
| `db.schema` | numero di versione | 1 | M1 |
| `db.settings` | lingua, tema, effetti, animazioni, font, soglie, frequenza, avvisi | 1 → | M1, M2, M3 |
| `db.profiles` | preset per ruolo | 3 | M8 |
| `db.sessions` | registrazioni (§4) | 2 | M4 |
| `db.corrupt` | tabelle danneggiate messe da parte | 1 | M1 |
| `char.schema`, `char.ui` | posizione, dimensione, scala, blocco della finestra, ultima scheda | 1 | M1 |

- **DAT-20** MUST: una migrazione per versione, idempotente, provata con un test che parte dai dati della versione
  precedente.
- **DAT-21** MUST: uno schema più nuovo di quello conosciuto lascia i dati intatti e l'addon in sola lettura.
- **DAT-22** MUST: un valore di impostazione sbagliato torna al predefinito senza errori.
- **DAT-23** MUST: la configurazione sopravvive a logout e `/reload` (test con la simulazione di `/reload`).

## 4. Sessioni registrate **[da completare in M4.1]**

```lua
Session = {
    id = "s-<time>-<n>", startedAt = 0, endedAt = nil, complete = false,
    zone = nil, instanceType = nil,          -- "none", "party", "raid"…
    mobs = { [mobKey] = { name, guid } },    -- mobKey stabile per sessione
    units = { [unitKey] = { name, role } },   -- nomi del gruppo, solo in locale (Q15)
    samples = { ... },                       -- colonne compatte: t, unitKey, mobKey, pct, situation, src
    events = { ... },                        -- t, tipo, dati: combat start/end, target change, death, threshold, tank change
    stats = { ... },                         -- riepilogo calcolato a fine scontro
}
```

- Timestamp relativi all'inizio dello scontro; identificativo univoco; nessun campione inventato per i buchi (i buchi
  sono registrati come tali).
- Limiti predefiniti proposti: 25 sessioni, circa 2 MB stimati in tutto, le più vecchie eliminate per prime (Q8).
- Sessioni incomplete (reload, disconnessione) chiuse al caricamento successivo e marcate `complete = false`.
- Eliminazione di una o di tutte le registrazioni dall'interfaccia.
