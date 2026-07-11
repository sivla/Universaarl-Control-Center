## ADDED Requirements

### Requirement: Das Kontrollzentrum bleibt ausserhalb der fachlichen Datenkette

Das Kontrollzentrum SHALL genau BC Basic und Project Twin als operative Zielprojekte ueberwachen und SHALL das technische Spectra-Repository BCProjectOS weder installieren noch als Kundeninstanz behandeln.

#### Scenario: Produktvertragspruefung wird konfiguriert

- **WHEN** eine BCProjectOS-Repository-Identitaet fuer die Bindungspruefung bekannt ist
- **THEN** SHALL sie als externe Produktvertragsquelle behandelt werden
- **AND** SHALL sie kein drittes Publisher-Ziel und keinen Installationspfad erzeugen

### Requirement: Repository-Identitaet ist kein Releasebeweis

Eine Spectra-Bindung SHALL nur mit `product_id: spectra`, konsistentem annotierten `spectra-v<SemVer>`-Tag, extern aufgeloestem Tag-Commit, finalem Manifest, gueltigem Manifest-Source-Commit und passendem SHA-256-Payload-Digest aus BCProjectOS als gebunden gelten.

#### Scenario: Nur das kanonische Remote ist bekannt

- **WHEN** `https://github.com/sivla/BCProjectOS.git` bekannt ist, aber Releasewerte fehlen
- **THEN** SHALL der Status `PENDING_BCPROJECTOS_RELEASE` bleiben
- **AND** SHALL kein Release, keine Version und kein Snapshot als freigegeben gelten

#### Scenario: Releasefelder widersprechen sich

- **WHEN** Tag, Tag-Commit, Manifestversion, Blueprintversion, Source-Commit, Modus oder Payload-Digest nicht gemeinsam uebereinstimmen
- **THEN** SHALL die Bindungspruefung fail-closed blockieren
- **AND** SHALL kein Branch, HEAD oder Arbeitsbaum als Ersatzbeweis dienen

#### Scenario: Nur ein Produktvertragsrelease ist gueltig

- **WHEN** ein finaler `product_contract` mit `CONTRACT_REFERENCE_ONLY` korrekt nachgewiesen ist
- **THEN** MAY er als Produktvertragsevidence berichtet werden
- **AND** SHALL er weder Kundeninstallation noch Snapshotfreigabe autorisieren

#### Scenario: Kundenbindung wird freigegeben

- **WHEN** eine Kundenbindung den Status BOUND beansprucht
- **THEN** SHALL sie zusaetzlich einen finalen `installable_blueprint` mit `INSTALLABLE_BLUEPRINT`, `installable_blueprint: true` und identischer Release-/Blueprintversion nachweisen

### Requirement: Der Branch-Index-Handoff ist commitgebunden und maschinenlesbar

BC Basic SHALL den laufenden Projektstand ueber `exports/project-data/v1/index.yaml` bereitstellen. Der Index SHALL Projekt- und Vertragsidentitaet, erlaubten Branch, Validierungsstatus sowie eine eindeutige positivgelistete Artefaktmenge enthalten.

#### Scenario: Branch-Index fehlt oder ist ungueltig

- **WHEN** kein Index existiert oder Identitaet, Branch, Status oder Allowlist ungueltig sind
- **THEN** SHALL das Kontrollzentrum den Projekt-Handoff als blockiert melden
- **AND** SHALL Project Twin keine fachlichen Daten daraus als freigegeben konsumieren

#### Scenario: Branch-Index ist vorhanden

- **WHEN** der erlaubte BC-Basic-Branch zu einer vollen Commit-SHA aufgeloest wurde
- **THEN** SHALL Twin den Index und alle fachlichen Payloadblobs ausschliesslich als Git-Blobs dieser einmal gepinnten Commit-SHA lesen
- **AND** SHALL kein Arbeitsbaum, kein spaeter bewegter Branchstand und kein Legacy-Snapshotmanifest als Fallback dienen
- **AND** SHALL jeder Allowlistpfad sicher repository-relativ sowie jede ID und jeder Pfad eindeutig sein
- **AND** SHALL jeder Index- und Payloadrecord exakt den regulaeren Git-Modus `100644` besitzen
- **AND** SHALL jeder positivgelistete erforderliche Git-Blob vorhanden sein
- **AND** SHALL das Kontrollzentrum fuer den Bericht einen deterministischen Digest ueber die ordinal sortierten Pfad-/Modus-/Groessen-/Blobdigest-Records bilden

### Requirement: Project Twin besitzt keine direkte BCProjectOS-Abhaengigkeit

Project Twin SHALL ausschliesslich den validierten Branch-Index und dessen positivgelistete BC-Basic-Payload lesen.

#### Scenario: Direkte Produktquelle wird angeboten

- **WHEN** Twin-Code oder -Konfiguration BCProjectOS direkt lesen, installieren oder als Laufzeitquelle verwenden soll
- **THEN** SHALL die Vertragspruefung blockieren
- **AND** SHALL kein Rueckschreib- oder Fallbackpfad aktiviert werden

### Requirement: PENDING und unbekannt koennen nicht Gruen werden

Nicht ausgefuehrte, fehlende, unbekannte, Pending- oder widerspruechliche Nachweise SHALL nie als bestanden oder veroeffentlichungsreif dargestellt werden.

#### Scenario: Ein vorgelagertes Gate ist offen

- **WHEN** BCProjectOS-Bindung, Branch-Index-Validierung, Consumeridentitaet oder commitgebundener Deutsch-Nachweis offen ist
- **THEN** SHALL der Gesamtstatus nicht Gruen sein
- **AND** SHALL eine Veroeffentlichung blockiert bleiben
