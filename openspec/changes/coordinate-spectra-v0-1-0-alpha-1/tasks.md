# Aufgaben: Spectra v0.1.0-alpha.1

## 1. Releasekandidat im Spectra-Projekt

- [x] 1.1 Eigenen Branch `codex/spectra-v0-1-0-alpha-1` vom aktuellen
  freigegebenen Spectra-Ausgangsstand erstellen.
- [x] 1.2 Produktname und technische Bezeichnungen konsistent auf Spectra
  ausrichten, ohne stabile Maschinenkennungen unkontrolliert zu migrieren.
- [x] 1.3 Installierbaren Produktvertrag und maschinenlesbares Release-Manifest
  fuer `0.1.0-alpha.1` fertigstellen.
- [x] 1.4 Produkt-, Schema-, Consumer-, Diff- und Secret-Pruefungen ausfuehren.
- [x] 1.5 Genau einen kohaerenten Kandidaten committen, Branch pushen und Pull
  Request mit Commit-, Tree- und Testnachweis uebergeben.

## 2. Kontrollzentrum-Freigabe

- [x] 2.1 Remote, Arbeitsbranch, vollen Commit, Tree und sauberen Kandidaten
  read-only pruefen.
- [x] 2.2 Version, Tag, Manifest, Payload-Digest und Kundenunabhaengigkeit
  reproduzierbar validieren.
- [x] 2.3 Merge nach `main` freigeben oder konkrete Blocker dokumentieren.

## 3. Alpha veroeffentlichen

- [ ] 3.1 Freigegebenen Pull Request unveraendert nach `main` mergen.
- [ ] 3.2 Tag `spectra-v0.1.0-alpha.1` exakt auf dem freigegebenen Main-Commit
  erstellen und unveraendert veroeffentlichen.
- [ ] 3.3 Tag, Commit, Tree, Digest und Release-URL als Alpha-Nachweis erfassen.

## 4. Nachgelagerte getrennte Auftraege

- [ ] 4.1 BC Basic an den echten Spectra-Alpha-Nachweis binden.
- [ ] 4.2 Validierten Snapshot A/B erzeugen und pruefen.
- [ ] 4.3 Project Twin an Manifest-Commit B binden und separat freigeben.
