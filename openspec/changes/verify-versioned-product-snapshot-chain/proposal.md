## Why

Das Produkt Spectra besitzt mit BCProjectOS jetzt ein eigenstaendiges technisches Repository, waehrend die Kundeninstanz und Project Twin weiterhin getrennte Projektidentitaeten auf ihren vorhandenen FiBu-Zweigen besitzen. Das Kontrollzentrum muss diese Kette pruefen koennen, ohne selbst BCProjectOS-Consumer, Kundeninstanz oder Snapshot-Produzent zu werden.

Ein zuvor lokal angelegtes Consumer-/Installationssetup lag deshalb im falschen Repository. Ausserdem prueft der aktuelle Kontrolllauf nur die Beziehung Twin liest Blueprint, nicht die vorgelagerte Releasebindung und ein eigenstaendiges Snapshotmanifest.

## What Changes

- Entfernt den fehlplatzierten BCProjectOS-Consumer aus dem Kontrollzentrum.
- Definiert die pruefbare Kette aus Spectra-Releasebindung im technischen Repository BCProjectOS, BC-Basic-Consumerbindung, versioniertem Snapshotmanifest und rein lesendem Twin.
- Behaelt genau `blueprint` und `project-twin` als operative Zielprojekte bei.
- Fuehrt BCProjectOS ausschliesslich als externe Release-Evidence-Quelle fuer `product_id: spectra` ein, deren vorhandene Bindung gegen Repository-Identitaet, `spectra-v<SemVer>`-Tag, Commit, finales Manifest, Releasemodus und Payload-Digest geprueft wird.
- Verlangt fuer den projektuebergreifenden Snapshot-Handoff ein strikt validierbares JSON-Manifest, das auf einen repository-relativen Datenindex verweist.
- Blockiert Gruen und Veroeffentlichungsreife bei `PENDING_BCPROJECTOS_RELEASE`, fehlendem Snapshotmanifest oder widerspruechlicher Provenienz.

## Capabilities

### New Capabilities

- `universaarl-contract-chain-verification`: Prueft die vollstaendige Produktvertrag-zu-Snapshot-zu-Twin-Kette commitgebunden und fail-closed.

### Modified Capabilities

- None.

## Impact

- Betrifft nur Berichte, Konfiguration, OpenSpec, Kontrollcode und Tests dieses Repositories.
- Erwartet spaeter einen durch BC Basic erzeugten JSON-Handoff unter `exports/project-data/v1/snapshot-manifest.json`; ein reiner `CONTRACT_REFERENCE_ONLY`-Release genuegt dafuer nicht.
- Aendert keine Zielprojektdatei, keinen Zielzweig, kein Remote, keinen Tag und keinen Release.
- Der aktuelle Zustand bleibt `PENDING_BCPROJECTOS_RELEASE`; es wird kein Snapshot als validiert ausgegeben.

## Non-Goals

- BCProjectOS installieren, kopieren, taggen oder veroeffentlichen.
- Kundenwissen oder Snapshot-Fachdaten im Kontrollzentrum speichern.
- Project Twin direkt an BCProjectOS anbinden.
- Bestehende Zielprojekt-Commits aus dem Kontrollzentrum erzeugen oder veraendern.
