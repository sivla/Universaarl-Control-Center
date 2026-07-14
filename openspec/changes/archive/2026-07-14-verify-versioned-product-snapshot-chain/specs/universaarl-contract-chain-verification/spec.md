## ADDED Requirements

> Archivierte, in den Kontrollvertrag uebernommene Delta-Spezifikation.

### Requirement: Das Kontrollzentrum bleibt außerhalb der fachlichen Datenkette

Das Kontrollzentrum SHALL genau BC Basic und Project Twin als operative Zielprojekte überwachen. BCProjectOS SHALL ausschließlich als read-only Spectra-Release-Evidence-Quelle verwendet werden.

#### Scenario: Produktvertragsprüfung

- **WHEN** ein BC-Basic-Snapshot einen Spectra-Release bindet
- **THEN** SHALL das Kontrollzentrum den Release unabhängig im kanonischen BCProjectOS-Repository prüfen
- **AND** SHALL daraus weder ein drittes Publisherziel noch ein Installationspfad entstehen

### Requirement: Spectra benötigt unveränderliche Releaseevidence

Eine Spectra-Bindung SHALL nur mit Produkt-ID `spectra`, annotiertem `spectra-v<SemVer>`-Tagobjekt, geschältem Commit, finalem installierbarem Manifest, gültigem Source-Commit und Source-Tree sowie erneut berechnetem Payloaddigest als gebunden gelten.

#### Scenario: Tag, Commit oder Digest widersprechen sich

- **WHEN** ein gebundener Wert nicht mit den 323 Manifestpayloads und ihren Git-Modi übereinstimmt
- **THEN** SHALL die gesamte Snapshotkette blockieren
- **AND** SHALL kein Branch oder Arbeitsbaum als Ersatzbeweis dienen

### Requirement: Der portable Snapshotrelease ist vollständig digestgebunden

BC Basic SHALL den aktuellen Consumerstand über `current.json` und ein unveränderliches Release-Manifest bereitstellen. Zeiger, Manifest, Projektindex, 158 Projektquellen, Knowledge-Payload und Katalogfragment SHALL vor jeder Freigabe vollständig geprüft werden.

#### Scenario: Release 0003 ist vollständig

- **WHEN** `UABC-PORTABLE-PILOT-0003` geprüft wird
- **THEN** SHALL das Manifest exakt 161 sichere, eindeutige und reguläre Releaseblobs enthalten
- **AND** SHALL Größe und SHA-256 jedes Blobs stimmen
- **AND** SHALL Filesystem und HTTPS für jeden Blob denselben Pfad und Digest binden
- **AND** SHALL die Projektquellen byteidentisch zum festgehaltenen Source-Commit und vollständig in dessen Index-Allowlist enthalten sein

#### Scenario: Identität, Pfad oder Byte weicht ab

- **WHEN** Kunde, Projekt, Release, Source-Commit, Allowlist, Pfadabbildung, Dateimenge, Größe, Digest oder Transportrecord abweicht
- **THEN** SHALL die Consumerbeziehung fail-closed blockieren

### Requirement: Project Twin besitzt keine produktive Git-Laufzeitabhängigkeit

Project Twin SHALL ausschließlich einen expliziten Filesystem- oder HTTPS-Katalog lesen und SHALL keine direkte BCProjectOS-, Repository-, Branch- oder Arbeitsbaumquelle verwenden.

#### Scenario: Git ist nicht verfügbar

- **WHEN** der echte Snapshotrelease mit geleertem Prozesspfad geladen wird
- **THEN** SHALL der Twin denselben Projektzustand normalisieren
- **AND** SHALL kein Git-Fallback aufgerufen werden

### Requirement: PENDING und unbekannt werden niemals grün

Nicht ausgeführte, fehlende, unbekannte oder widersprüchliche Plattform- und Vertragsnachweise SHALL nie als bestanden oder veröffentlichungsreif dargestellt werden.

#### Scenario: Remote-Plattformmatrix fehlt

- **WHEN** Windows- oder macOS-Job der projektübergreifenden Twin-Matrix nicht real ausgeführt wurde
- **THEN** SHALL `PENDING_PLATFORM_BROWSER_EVIDENCE` offen bleiben
- **AND** SHALL kein lokaler Browserlauf diesen Plattformnachweis ersetzen
