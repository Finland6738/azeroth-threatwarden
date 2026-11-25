# SPEC-06: Analytics ed esportazione

> Fonte: [specifiche originali](source-specification.md) §5.5, §4.2. Da completare in **M6.1**.

## 1. Metriche (solo se i dati raccolti bastano)

| Metrica | Definizione | Categoria |
|---|---|---|
| Superamenti di soglia | ingressi in WARNING e DANGER per giocatore | calcolata |
| Tempo in WARNING / DANGER | somma degli intervalli tra campioni consecutivi nello stato | calcolata |
| Cambi di target | eventi di cambio target del mob | rilevata |
| Threat massima osservata | il massimo dei campioni validi | rilevata |
| Intervalli instabili | finestre con molti cambi di stato o di tank | calcolata |
| Rischio per scontro | frequenza delle situazioni di rischio | calcolata |
| Confronto | le stesse metriche tra scontri sullo stesso mob | calcolata |

- **ANA-01** MUST: niente classifiche accusatorie ("peggior DPS"); indicatori descrittivi, con contesto (durata,
  campioni validi) e verificabili.
- **ANA-02** MUST: con meno del 50 % di campioni validi una metrica si mostra come "Insufficient data".

## 2. Esportazione

Testo e CSV in una casella da copiare (gli addon non scrivono file). Un avviso sopra la casella ricorda che il testo
contiene i nomi del gruppo; opzione per sostituirli con *Player 1, Player 2…* (Q15).
