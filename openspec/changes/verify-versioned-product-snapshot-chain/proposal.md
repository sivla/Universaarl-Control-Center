## Why

Das Produkt Spectra besitzt mit BCProjectOS jetzt ein eigenstaendiges technisches Repository, waehrend die Kundeninstanz und Project Twin weiterhin getrennte Projektidentitaeten auf ihren vorhandenen FiBu-Zweigen besitzen. Das Kontrollzentrum muss diese Kette pruefen koennen, ohne selbst BCProjectOS-Consumer, Kundeninstanz oder Snapshot-Produzent zu werden.

Ein zuvor lokal angelegtes Consumer-/Installationssetup lag deshalb im falschen Repository. Ausserdem muss der Kontrolllauf sowohl die vorgelagerte Releasebindung als auch den einfachen commitgebundenen Branch-Index pruefen.

## What Changes

- Entfernt den fehlplatzierten BCProjectOS-Consumer aus dem Kontrollzentrum.
- Definiert die pruefbare Kette aus Spectra-Releasebindung im technischen Repository BCProjectOS, BC-Basic-Branch-Index und rein lesendem Twin.
- Behaelt genau `blueprint` und `project-twin` als operative Zielprojekte bei.
- Fuehrt BCProjectOS ausschliesslich als externe Release-Evidence-Quelle fuer `product_id: spectra` ein, deren vorhandene Bindung gegen Repository-Identitaet, `spectra-v<SemVer>`-Tag, Commit, finales Manifest, Releasemodus und Payload-Digest geprueft wird.
- Verlangt fuer den laufenden projektuebergreifenden Handoff einen strikt validierbaren repository-relativen Datenindex im normalem BC-Basic-Projektcommit.
- Blockiert Gruen und Veroeffentlichungsreife bei `PENDING_BCPROJECTOS_RELEASE`, fehlendem oder ungueltigem Branch-Index oder widerspruechlicher Provenienz.

## Capabilities

### New Capabilities

- `universaarl-contract-chain-verification`: Prueft die vollstaendige Produktvertrag-zu-Branch-Index-zu-Twin-Kette commitgebunden und fail-closed.

### Modified Capabilities

- None.

## Impact

- Betrifft nur Berichte, Konfiguration, OpenSpec, Kontrollcode und Tests dieses Repositories.
- Erwartet den BC-Basic-Handoff unter `exports/project-data/v1/index.yaml`; der Twin loest den erlaubten Branch einmal zu einer SHA auf und liest nur deren positivgelistete Git-Blobs.
- Aendert keine Zielprojektdatei, keinen Zielzweig, kein Remote, keinen Tag und keinen Release.
- Pending- oder unvollstaendige Nachweise werden nicht als validiert ausgegeben.

## Non-Goals

- BCProjectOS installieren, kopieren, taggen oder veroeffentlichen.
- Kundenwissen oder Snapshot-Fachdaten im Kontrollzentrum speichern.
- Project Twin direkt an BCProjectOS anbinden.
- Bestehende Zielprojekt-Commits aus dem Kontrollzentrum erzeugen oder veraendern.
