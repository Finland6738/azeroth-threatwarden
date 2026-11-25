# Anteprime di progetto

Immagini dell'interfaccia di Azeroth Threatwarden fatte prima che l'addon giri nel client vero. Sono **anteprime di
progetto, non screenshot** ([ADR 0013](../../adr/0013-design-previews-original-art-invented-data.md)): disegnate dal
layout, dai colori (`UI/Theme.lua`) e dai testi (`Locales/`) dell'addon, quindi la finestra vera può differire in
piccoli dettagli (resa dei font e delle texture del gioco, spaziature esatte). Ogni immagine lo dice nella striscia in
basso.

- **Solo arte originale**: forme CSS e SVG, il logo dell'addon e i loghi NEBULA di [`assets/`](../../../assets/) e i
  font che l'addon distribuisce (SIL OFL 1.1, `AzerothThreatwarden/Media/Fonts/`). Nessun'immagine, icona o texture del
  gioco; nulla viene scaricato dalla rete.
- **Dati inventati**: nessun giocatore, gilda o reame vero. Le anteprime di M1 mostrano solo i valori predefiniti delle
  impostazioni; quelle del monitor (M2.5) un combattimento inventato (mob e nomi che non esistono).
- **File leggeri**: WebP, qualità 80.

| Cartella | Contenuto | Prodotta da |
|---|---|---|
| [`previews/`](previews/README.md) | il monitor della threat (valori, vista del tank, solo stato, sconosciuto, nessun bersaglio, demo; Nebula e Warden, la prima anche in Aurora), la card Monitor delle Impostazioni, la finestra di M1 (scheda Monitor vuota), le Impostazioni e la pagina Info nei tre temi, in inglese e italiano | `tools/make_mockups.py` |

## Rifarle

Servono Chrome o Edge (la variabile d'ambiente `CHROME` sostituisce la ricerca) e Pillow
(`python -m pip install --user pillow`).

```bash
python -X utf8 tools/make_mockups.py              # tutte le immagini e l'indice
python -X utf8 tools/make_mockups.py settings     # solo quelle con "settings" nel nome
python -X utf8 tools/make_mockups.py --index      # solo l'indice, senza browser
```

Le scene sono in `tools/mockup_scenes.py`, i pezzi e i token in `tools/mockup_lib.py`. `tools/check_docs.py` costruisce
ogni scena dai file dell'addon e fallisce se un'immagine o una riga dell'indice manca, o se c'è un file in più. Non sa
vedere se un'immagine è vecchia: **dopo un cambio dell'interfaccia, dei temi o dei testi si rigenerano**.

Adattato dagli strumenti dei mockup di Azeroth Accord (stesso proprietario, GPL-3.0,
[ADR 0012](../../adr/0012-reuse-accord-and-unspoken-foundations.md)); le pagine annotate (`mockup_spec.py`,
`render.sh`) non servono ancora.
