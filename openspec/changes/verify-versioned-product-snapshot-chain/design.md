## Context

Die Produkt- und Projektidentitaeten sind jetzt bekannt:

- Spectra: `product_id: spectra`, technisches Repository BCProjectOS unter `https://github.com/sivla/BCProjectOS.git`, Tagformat `spectra-v<SemVer>`
- BC Basic: `https://github.com/sivla/FiBu.git`, `codex/universaarl-projekt`
- Project Twin: `https://github.com/sivla/FiBu.git`, `codex/universaarl-projekt-twin`

Repository- und Zweigidentitaet sind notwendige Herkunftsdaten, aber keine Release- oder Snapshotfreigabe.

## Goals / Non-Goals

**Goals:**

- Produktrelease, Kundenbindung, Snapshot und Twin-Lesevertrag als getrennte, pruefbare Stufen modellieren.
- Jede Stufe an unveraenderliche Commits und deterministische Digests binden.
- Fehlende oder widerspruechliche Evidence ohne Fallback blockieren.
- Zielprojekte weiterhin ausschliesslich ueber deren eigene Projekt-Chats aendern lassen.

**Non-Goals:**

- Ein drittes operatives Zielprojekt in den Publisher aufnehmen.
- Aus einem Branch, HEAD, Verzeichnisnamen oder Kandidatenmanifest eine Version ableiten.
- Ein selbstreferenzielles Snapshotmanifest mit seiner eigenen noch unbekannten Commit-SHA erzeugen.

## Decisions

### Decision: BCProjectOS bleibt externe Pruefquelle fuer Spectra

`monitor.config.json` fuehrt weiterhin genau Blueprint und Project Twin als operative Projekte. BCProjectOS darf nur als technische Produktvertragsquelle fuer eine bereits vorhandene Spectra-Kundenbindung gelesen und geprueft werden. Das Kontrollzentrum besitzt keinen Installations- oder Upgradepfad.

Die spaetere Konfiguration verwendet dafuer genau eine `verificationSources.bcprojectos`-Definition mit `verificationOnly: true`, kanonischem Remote, Pfadalias und Umgebungsvariable. Diese Quelle darf keine Publish-Konfiguration besitzen und erscheint nicht in `projects` oder im Publisher-`ValidateSet`.

### Decision: Spectra-Tag-Commit wird extern aufgeloest

Das BCProjectOS-Manifest speichert keinen `release_commit`. Der annotierte `spectra-v<SemVer>`-Tag wird extern auf eine volle Commit-SHA aufgeloest. Der Manifest-Source-Commit muss in dessen Historie liegen; der freigegebene Produktumfang darf sich bis zum Tag-Commit nicht veraendern. `product_id: spectra`, Manifestversion, Blueprintversion, Tag, Modus und SHA-256-Payload-Digest muessen konsistent sein; `releaseTag` entspricht exakt `spectra-v` plus `releaseVersion`.

### Decision: Laufender Handoff ist der commitgebundene Branch-Index

BC Basic besitzt den repository-relativen Datenindex `exports/project-data/v1/index.yaml`. Dieser Index ist im laufenden Entwicklungsmodus der einzige fachliche Export- und Allowlistvertrag. Er nennt Projekt- und Vertragsidentitaet, den erlaubten Entwicklungszweig, den Validierungsstatus sowie eindeutige IDs und sichere repository-relative Payloadpfade. Die Branchspitze wird genau einmal zu einer vollstaendigen Commit-SHA aufgeloest; Index und Payload werden danach ausschliesslich als Git-Blobs dieser SHA gelesen. Eine Datei im selben Commit muss und darf keine selbstreferenzielle Commit-SHA enthalten.

Das historische `snapshot-manifest.json` und fruehere A/B-Commits bleiben unveraenderte Historie, sind aber im Branchmodus nicht normativ. Es gibt keinen separaten Manifest-only-Commit, keine Parent-A-Pruefung und keinen A/B-Diff. Fuer eine spaetere Releasefreigabe wird der freizugebende normale Projektcommit oder ein Tag extern festgehalten.

Der Kontrollvalidator prueft jeden positivgelisteten Pfad genau einmal. Pfade verwenden ausschliesslich `/`, muessen sicher repository-relativ sein und duerfen keine leeren, Punkt-, Traversierungs-, absoluten, Laufwerks-, URI-, Backslash- oder Steuerzeichensegmente enthalten. Jeder Index- und Payloadblob muss ein regulaerer Git-Blob im Modus `100644` sein. Fuer den Bericht wird weiterhin ein deterministischer SHA-256-Bundledigest ueber ordinal sortierte Pfad-, Modus-, Groessen- und Blobdigest-Records berechnet. Doppelte IDs oder Pfade, fehlende Blobs und unsichere Pfade blockieren.

Der `payloadBundleDigest` in `spectraReleaseBinding` gehoert ausschliesslich zum Spectra-Releasepayload aus BCProjectOS. Der aeussere `payloadBundleDigest` gehoert ausschliesslich zum BC-Basic-Snapshot. Beide Digests muessen jeweils korrekt nachgewiesen werden, duerfen aber niemals aufgrund gleicher Feldnamen gleichgesetzt werden.

### Decision: Releasemodus und Pending bleiben explizit

Die bekannte BCProjectOS-Repository-URL und `productId: spectra` duerfen im internen Pending-Vertrag stehen. Releaseversion, Tag, Tag-Commit, Manifestpfad, Manifest-Source-Commit und Payload-Digest bleiben jedoch `null`. Pending ist kein Parserfehler, blockiert aber Gruen, Snapshotfreigabe und Veroeffentlichung. Eine Snapshotmanifestinstanz darf im Pending-Zustand nicht erzeugt werden.

Ein finaler `product_contract` / `CONTRACT_REFERENCE_ONLY`-Release kann als gueltige Produktvertragsevidence berichtet werden, haelt Kundeninstallation und Snapshot aber weiterhin blockiert. Nur ein finales Manifest mit `release_kind: installable_blueprint`, `consumer_mode: INSTALLABLE_BLUEPRINT`, `installable_blueprint: true` und identischer Release-/Blueprintversion kann eine Kundenbindung und den nachgelagerten Snapshot freigeben.

### Decision: Twin liest niemals BCProjectOS direkt

Project Twin loest den erlaubten BC-Basic-Branch einmal zu einer SHA auf, validiert den Index und liest ausschliesslich die darin positivgelisteten Git-Blobs derselben SHA. Eine direkte BCProjectOS-Abfrage, Installation oder Runtime-Abhaengigkeit bleibt verboten.

## Validation Model

Der Kontrolllauf prueft spaeter mindestens:

- exakte Blueprint- und Twin-SHA sowie unveraenderte Arbeitsbaum-/Index-Fingerprints;
- kanonische Repository-/Zweigidentitaeten;
- BCProjectOS-Pending- oder Bound-Zustand als strikte Zustandsmaschine;
- bei Bound: annotierter Tag, Tag-Commit, finales installierbares Manifest, Source-Ancestry, unveraenderter Payload und SHA-256-Digest;
- aufgeloesten BC-Basic-Branchcommit, Indexidentitaet, Allowlist, sichere eindeutige Pfade, vorhandene Git-Blobs und neu berechneten Berichtsdigest;
- Twin-Consumeridentitaet, Nur-Lese-Richtung und fehlende direkte BCProjectOS-Kopplung;
- commitgebundene deutsche Maschinen- und Oberflaechennachweise.

## Rollback

Kontrollcode und Konfiguration koennen als ein kohaerenter lokaler Commit zurueckgenommen werden. Zielprojekte werden nicht veraendert. Bereits vorhandene Zielprojekt-Commits oder Releaseartefakte sind nicht Teil dieses Rollbacks.
