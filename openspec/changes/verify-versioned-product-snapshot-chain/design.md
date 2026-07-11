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

### Decision: Snapshot-Handoff ist ein JSON-Manifest

BC Basic besitzt intern seine Consumerbindung und den repository-relativen Datenindex. Der projektuebergreifende Handoff erfolgt spaeter ueber `exports/project-data/v1/snapshot-manifest.json` samt versioniertem JSON Schema. Das Manifest verwendet exakt die Felder `schemaVersion`, `producerId`, `projectId`, `contractId`, `producerCommitSha`, `schemaPath`, `indexPath`, `consumer`, `spectraReleaseBinding`, `consumerBindingDigest`, `payloadDigestFormat`, `index`, `payloads`, `payloadBundleDigest` und `validationStatus`; unbekannte Zusatzfelder sind verboten. `spectraReleaseBinding` projiziert die vollstaendige installierbare Spectra-Bindung, waehrend `technicalRepositoryName: BCProjectOS` und die kanonische Repository-URL die technische Herkunft erhalten.

Das fachliche Quellcommit `A` und sein Payload werden zuerst festgeschrieben. Erst der direkte, einzelne Elternnachfolger `B` darf das daraus erzeugte Manifest enthalten. Die Twin-Registry bindet `B` extern; das Manifest in `B` nennt ausschliesslich `A` als `producerCommitSha`. Twin liest Manifest, Schema, Index und ausgelieferte Payload ausschliesslich als Git-Blobs aus `B`; `A` dient der Provenienz- und Unveraendertheitspruefung. `git diff A B` darf exakt die positivgelistete Datei `exports/project-data/v1/snapshot-manifest.json` neu enthalten oder aendern; Renames, Deletes, Merge-Parents oder weitere Pfade sind verboten. Schema, Generator, Validator, Index und alle Payloadblobs muessen in `A` und `B` objektidentisch sein. Damit wird keine eigene Commit-SHA erfunden.

Der Snapshot-Payload-Digest verwendet die kanonische Form `uabc-snapshot-records-v1`. Er umfasst den Datenindex und jeden darin positivgelisteten Artefaktpfad genau einmal. Pfade verwenden ausschliesslich `/`, muessen sicher repository-relativ sein und duerfen keine leeren, Punkt-, Traversierungs-, absoluten, Laufwerks-, URI-, Backslash- oder Steuerzeichensegmente enthalten. Sie werden nach ihren UTF-8-Bytes ordinal sortiert. Jeder Index- und Payloadblob muss ein regulaerer Git-Blob im Modus `100644` sein. Pro Pfad wird exakt folgender Byte-Record gebildet: `pathUtf8 + NUL + gitModeAscii + NUL + sizeBytesDecimalAscii + NUL + sha256HexLowerAscii + LF`. `sha256HexLower` ist der SHA-256-Digest des unveraenderten Git-Blobinhalts, nicht die Git-Objekt-ID. Der Gesamtdigest ist SHA-256 ueber die Verkettung aller Records und wird als `sha256:<64 lowercase hex>` gespeichert. Doppelte Pfade, abweichende Modi, Groessen, Blobs oder Reihenfolgen blockieren.

Der `payloadBundleDigest` in `spectraReleaseBinding` gehoert ausschliesslich zum Spectra-Releasepayload aus BCProjectOS. Der aeussere `payloadBundleDigest` gehoert ausschliesslich zum BC-Basic-Snapshot. Beide Digests muessen jeweils korrekt nachgewiesen werden, duerfen aber niemals aufgrund gleicher Feldnamen gleichgesetzt werden.

### Decision: Releasemodus und Pending bleiben explizit

Die bekannte BCProjectOS-Repository-URL und `productId: spectra` duerfen im internen Pending-Vertrag stehen. Releaseversion, Tag, Tag-Commit, Manifestpfad, Manifest-Source-Commit und Payload-Digest bleiben jedoch `null`. Pending ist kein Parserfehler, blockiert aber Gruen, Snapshotfreigabe und Veroeffentlichung. Eine Snapshotmanifestinstanz darf im Pending-Zustand nicht erzeugt werden.

Ein finaler `product_contract` / `CONTRACT_REFERENCE_ONLY`-Release kann als gueltige Produktvertragsevidence berichtet werden, haelt Kundeninstallation und Snapshot aber weiterhin blockiert. Nur ein finales Manifest mit `release_kind: installable_blueprint`, `consumer_mode: INSTALLABLE_BLUEPRINT`, `installable_blueprint: true` und identischer Release-/Blueprintversion kann eine Kundenbindung und den nachgelagerten Snapshot freigeben.

### Decision: Twin liest niemals BCProjectOS direkt

Project Twin validiert das Snapshotmanifest aus dem extern gebundenen Metadatencommit `B` und die darin referenzierten fachlichen Git-Blobs aus dessen direktem Produzenten-Parent `A`. Eine direkte BCProjectOS-Abfrage, Installation oder Runtime-Abhaengigkeit bleibt verboten.

## Validation Model

Der Kontrolllauf prueft spaeter mindestens:

- exakte Blueprint- und Twin-SHA sowie unveraenderte Arbeitsbaum-/Index-Fingerprints;
- kanonische Repository-/Zweigidentitaeten;
- BCProjectOS-Pending- oder Bound-Zustand als strikte Zustandsmaschine;
- bei Bound: annotierter Tag, Tag-Commit, finales installierbares Manifest, Source-Ancestry, unveraenderter Payload und SHA-256-Digest;
- extern gebundenen Snapshot-Metadatencommit, dessen direkten Produzenten-Parent, Snapshotmanifest-Schema, Indexreferenz, Allowlist und neu berechneten Snapshotdigest;
- Twin-Consumeridentitaet, Nur-Lese-Richtung und fehlende direkte BCProjectOS-Kopplung;
- commitgebundene deutsche Maschinen- und Oberflaechennachweise.

## Rollback

Kontrollcode und Konfiguration koennen als ein kohaerenter lokaler Commit zurueckgenommen werden. Zielprojekte werden nicht veraendert. Bereits vorhandene Zielprojekt-Commits oder Releaseartefakte sind nicht Teil dieses Rollbacks.
