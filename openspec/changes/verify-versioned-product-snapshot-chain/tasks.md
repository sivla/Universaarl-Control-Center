## 1. Architektur und Fehlablage

- [x] 1.1 Fehlplatzierten BCProjectOS-Consumer, Installationspfad und dessen Tests aus dem Kontrollzentrum entfernen.
- [x] 1.2 Repository-Rollen, bekannte Remote-/Zweigidentitaeten und weiterhin ausstehenden Release-/Snapshotstatus dokumentieren.

## 2. Produzentenvertraege uebernehmen

- [x] 2.1 Das generische Spectra-Releasemanifest- und Release-Binding-Schema mit `product_id: spectra`, `spectra-v<SemVer>` und technischer BCProjectOS-Herkunft samt Produktumfang gegen den uebergebenen BCProjectOS-Commit pruefen.
- [x] 2.2 Den konkreten BC-Basic-Branch-Index, seine Allowlist, sicheren Pfade und commitgebundenen Git-Blobs gegen den uebergebenen Blueprint-Commit pruefen.
- [x] 2.3 Den Project-Twin-Consumervertrag ohne direkte BCProjectOS-Kopplung gegen den uebergebenen Twin-Commit pruefen.

## 3. Kontrollzentrum-Pruefung

- [x] 3.1 Produktvertragsquelle als reine Pruefquelle konfigurieren, ohne sie als drittes Zielprojekt oder Publisherziel aufzunehmen.
- [x] 3.2 Commitgebundenen Validator fuer Pending-/Bound-Spectra-Bindung aus BCProjectOS und den BC-Basic-Branch-Index implementieren.
- [x] 3.3 Audit- und Zielberichte um die Beziehungen Blueprint bindet Spectra aus BCProjectOS und Twin liest den validierten Branch-Index erweitern.
- [x] 3.4 Publisher bei Pending, fehlendem oder ungueltigem Index oder direkter Twin-Produktkopplung fail-closed blockieren.

## 4. Deterministische Evidence

- [x] 4.1 Positive Fixture fuer eine vollstaendig konsistente Produkt- und Snapshotbindung erstellen.
- [x] 4.2 Negative Fixtures fuer fehlenden Tag, falschen Tag-Commit, Manifestkonflikt, Source-Ancestry, Candidate-Digest, falschen Branch, unsichere oder doppelte Indexpfade/-IDs und fehlende aktuelle Simulationsevidence ergaenzen.
- [x] 4.3 Nachweisen, dass alle Zielprojekt-Lesevorgaenge commitgebunden, indexneutral und ohne reale `.env*`, Secrets oder Authentifizierungszustaende erfolgen.
- [x] 4.4 Kontrollzentrum-Haertung, Deutschpruefung, OpenSpec strict, `git diff --check` und diffbezogenen Secret-/Tenant-Scan ausfuehren.

## 5. Uebergabe

- [ ] 5.1 Spectra-Releasecommit, validierten BC-Basic-Branchcommit, Twin-Commit und Kontrollzentrum-Commit samt Trees, Testevidence und offenen Gates getrennt dokumentieren.
- [x] 5.2 Kein Zielprojekt pushen, solange der jeweilige Projekt- und Kontrollzentrum-Publish-Gate nicht separat bestanden ist.
