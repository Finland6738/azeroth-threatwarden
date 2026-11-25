# SPEC-07: Multi-target, heatmap e profili

> Fonte: [specifiche originali](source-specification.md) §5.6, §5.7, §4.2. Da completare in **M7.1** e **M8.1**.
> **Gate**: niente promesse di multi-target finché il probe non dimostra che i dati sono ottenibili (P5, P6).

## 1. Multi-target (M7)

Per ogni mob tracciabile: identificativo stabile nello scontro; nome; target corrente; threat relativa dei membri
osservati; stato; ultimo aggiornamento.

- Unità interrogabili da verificare: `target`, `focus`, `mouseover`, `targettarget`, `boss1`–`boss5`,
  `nameplate1`–`nameplateN`, i target dei membri del gruppo (`party1target`…) **[verificare]** P5.
- **MT-01** MUST: degrado pulito: un mob che non si può interrogare resta "Unknown" o non compare, senza errori e senza
  numeri vecchi spacciati per attuali.
- **MT-02** MUST: limite di mob osservati (predefinito proposto 8) e campionamento a rotazione.

## 2. Dungeon focus (M7)

Elenco dei mob con il rischio più alto per il gruppo (un DPS vicino a strappare, un mob senza tank), ordinato per
rischio; clic per monitorare quel mob.

## 3. Heatmap (M8)

Colorazione delle righe del monitor; integrazione con i riquadri del raid di Blizzard **solo** se non causa taint
**[verificare]**; nessuna dipendenza da addon esterni; colori configurabili e alternative non basate sul colore.

## 4. Profili e preset (M8)

Profili per tank, DPS e healer (soglie, canali, colonne); scelta automatica dal ruolo assegnato, se rilevabile;
copia e reset di un profilo.
