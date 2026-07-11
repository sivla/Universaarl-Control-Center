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

### Requirement: Der Snapshot-Handoff ist commitgebunden und maschinenlesbar

BC Basic SHALL einen freigegebenen Snapshot ueber ein strikt schemavalidiertes JSON-Manifest bereitstellen, das auf einen repository-relativen, positivgelisteten Datenindex verweist.

#### Scenario: Snapshotmanifest fehlt oder ist vorgeschlagen

- **WHEN** kein Manifest existiert oder Lifecycle beziehungsweise Validierungsstatus nicht freigegeben sind
- **THEN** SHALL das Kontrollzentrum den Snapshot als blockiert melden
- **AND** SHALL Project Twin keine fachlichen Daten daraus als freigegeben konsumieren

#### Scenario: Snapshotmanifest ist vorhanden

- **WHEN** ein Manifest fuer eine volle Blueprint-Quell-SHA vorliegt
- **THEN** SHALL der extern gebundene Snapshot-Metadatencommit genau einen Parent besitzen und dieser dem im Manifest genannten Produzentencommit entsprechen
- **AND** SHALL Twin Manifest, Schema, Datenindex und fachliche Payloadblobs ausschliesslich aus dem Metadatencommit lesen und den Produzentencommit nur fuer Provenienz und Objektidentitaet verwenden
- **AND** SHALL der A-zu-B-Diff ausschliesslich den positivgelisteten Snapshotmanifestpfad enthalten
- **AND** SHALL der Digest nach `uabc-snapshot-records-v1` aus den UTF-8-ordinal sortierten sicheren Pfaden sowie je Record aus Pfad, NUL, Git-Modus, NUL, Dezimalgroesse, NUL, lowercase SHA-256 des Blobinhalts und LF gebildet werden
- **AND** SHALL jeder Index- und Payloadrecord exakt den regulaeren Git-Modus `100644` besitzen
- **AND** SHALL der Spectra-Releasepayload-Digest getrennt vom BC-Basic-Snapshotpayload-Digest validiert und niemals mit ihm gleichgesetzt werden
- **AND** SHALL Produzenten-ID, Produzentencommit, Snapshot-Metadatencommit, Schema- und Indexreferenz, `spectraReleaseBinding` mit `productId: spectra` und technischer BCProjectOS-Herkunft sowie Digest gemeinsam validiert werden

### Requirement: Project Twin besitzt keine direkte BCProjectOS-Abhaengigkeit

Project Twin SHALL ausschliesslich das validierte Snapshotmanifest und dessen Blueprint-Payload lesen.

#### Scenario: Direkte Produktquelle wird angeboten

- **WHEN** Twin-Code oder -Konfiguration BCProjectOS direkt lesen, installieren oder als Laufzeitquelle verwenden soll
- **THEN** SHALL die Vertragspruefung blockieren
- **AND** SHALL kein Rueckschreib- oder Fallbackpfad aktiviert werden

### Requirement: PENDING und unbekannt koennen nicht Gruen werden

Nicht ausgefuehrte, fehlende, unbekannte, Pending- oder widerspruechliche Nachweise SHALL nie als bestanden oder veroeffentlichungsreif dargestellt werden.

#### Scenario: Ein vorgelagertes Gate ist offen

- **WHEN** BCProjectOS-Bindung, Snapshotvalidierung, Consumeridentitaet oder commitgebundener Deutsch-Nachweis offen ist
- **THEN** SHALL der Gesamtstatus nicht Gruen sein
- **AND** SHALL eine Veroeffentlichung blockiert bleiben
