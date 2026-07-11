# Spectra Alpha Release

## ADDED Requirements

### Requirement: Der erste Release ist eindeutig identifiziert

Das System MUSS den ersten Spectra-Release als Version `0.1.0-alpha.1` mit
Produktkennung `spectra` und Tag `spectra-v0.1.0-alpha.1` identifizieren.

#### Scenario: Release-Metadaten stimmen ueberein

- **WHEN** der Alpha-Kandidat geprueft wird
- **THEN** muessen Produktkennung, Version und Tag exakt miteinander
  uebereinstimmen
- **AND** Commit und Digest muessen vollstaendig und reproduzierbar sein

### Requirement: Projekt-Agenten veroeffentlichen nur Arbeitszweige

Der Spectra-Projekt-Agent MUSS auf einem eigenen Arbeitszweig arbeiten und DARF
diesen Zweig pushen. Er DARF weder direkt nach `main` pushen noch selbst mergen,
taggen oder einen Release veroeffentlichen.

#### Scenario: Alpha-Kandidat wird uebergeben

- **WHEN** der Spectra-Arbeitszweig alle Projektpruefungen besteht
- **THEN** wird genau der gepruefte Commit gepusht und als Pull Request
  uebergeben
- **AND** die Uebergabe nennt vollen Commit, Tree und Pruefergebnisse

### Requirement: Das Kontrollzentrum entscheidet fail-closed

Das Kontrollzentrum MUSS den uebergebenen Spectra-Kandidaten read-only pruefen
und DARF nur den exakt geprueften Commit zum Merge freigeben.

#### Scenario: Nachweis ist unvollstaendig

- **WHEN** Repository, Commit, Tree, Tests, Manifest oder Digest nicht eindeutig
  nachgewiesen sind
- **THEN** bleibt die Freigabe blockiert
- **AND** es wird kein Tag oder Release abgeleitet

#### Scenario: Merge wurde freigegeben und ausgefuehrt

- **WHEN** der gepruefte Kandidat unveraendert nach `main` gemergt wurde
- **THEN** darf `spectra-v0.1.0-alpha.1` exakt auf dem freigegebenen
  Main-Commit erstellt werden
- **AND** der Release muss denselben Commit und Digest ausweisen

### Requirement: Der Alpha-Release bleibt kundenunabhaengig

Der Spectra-Release DARF keine Kundendaten, Kunden-Evidence oder konkrete
Universaarl-Projektentscheidungen enthalten.

#### Scenario: Release-Diff enthaelt Kundeninhalt

- **WHEN** die Inhalts- oder Secret-Pruefung kundenspezifische Daten erkennt
- **THEN** muss die Releasefreigabe blockiert werden
