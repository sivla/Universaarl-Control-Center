## Why

Spectra, BC Basic und Project Twin besitzen jetzt getrennte, reale Versionsstände. Das Kontrollzentrum muss deren portable Kette unabhängig prüfen, ohne Produktcode zu installieren, Kundenwahrheit zu erzeugen oder Zielprojekt-Commits zu verändern.

Der frühere Branch-Index-Handoff ist nicht mehr der produktive Laufzeitvertrag. BC Basic veröffentlicht mit `current.json` einen unveränderlichen Snapshotrelease; Project Twin liest ausschließlich diesen Release über Filesystem oder HTTPS.

## What Changes

- Prüft den echten Spectra-Release `spectra-v1.2.0-alpha.12` aus BCProjectOS einschließlich annotiertem Tagobjekt, Tagcommit, Source-Commit, Source-Tree, finalem Manifest, 323 Payloadblobs, Git-Modi und SHA-256-Bundledigest.
- Prüft `UABC-PORTABLE-PILOT-0003` aus BC Basic einschließlich Zeiger, Manifestdigest, Producer- und Source-Commit, 158 Projektquellen, Projektindex, Knowledge-Payload, Katalogfragment und beiden Transportrecords.
- Prüft, dass Project Twin ausschließlich den portablen Snapshotreader verwendet, keine direkte BCProjectOS-Abhängigkeit besitzt und den realen Release ohne verfügbares Git-Programm normalisieren kann.
- Bindet Audit, Zielprüfung und Publisher an die vollständigen Spectra-, Blueprint- und Twin-SHAs sowie unveränderte Repository-Fingerprints.
- Lässt echte macOS-/GitHub-Actions-Evidence offen, bis ein tatsächlicher Remote-Runnerlauf vorliegt.

## Impact

- Änderungen betreffen ausschließlich Konfiguration, OpenSpec, Kontrollcode, Kontrolltests, Berichte und Dokumentation dieses Repositories.
- BCProjectOS bleibt reine Release-Evidence-Quelle und kein Publisherziel.
- BC Basic und Project Twin bleiben die einzigen operativen Zielprojekte.
- Zielprojekte werden nur über das bestehende kontrollierte Publish-Skript und niemals erzwungen übertragen.

## Non-Goals

- Kundenwissen oder Snapshot-Fachdaten im Kontrollzentrum speichern.
- Project Twin direkt an BCProjectOS anbinden.
- Git, Branch oder Arbeitsbaum wieder als produktive Twin-Laufzeitquelle einführen.
- Menschliche Freigabe, macOS-Evidence oder Plattformbereitschaft aus lokalen Tests ableiten.
