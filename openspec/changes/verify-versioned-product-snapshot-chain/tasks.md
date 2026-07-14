## 1. Produkt- und Snapshotvertrag

- [x] 1.1 Spectra 1.2.0-alpha.12 mit annotiertem Tagobjekt, Tagcommit, Source-Commit, Source-Tree, Schema-4-Modusbindung und 323 Payloaddigesten unabhängig prüfen.
- [x] 1.2 BC-Basic-Snapshot 0003 mit Zeiger, Manifestdigest, 158 Projektquellen, Knowledge-Payload, Katalogfragment und vollständiger Index-Allowlist prüfen.
- [x] 1.3 Filesystem-/HTTPS-Transportrecords, Kundenisolation, Pfadsicherheit, Dateimenge und alle SHA-256-Werte fail-closed validieren.

## 2. Twin-Consumer

- [x] 2.1 Twin-Grenze ohne direkte BCProjectOS-Abhängigkeit prüfen.
- [x] 2.2 Reale Snapshotnormalisierung mit geleertem Prozesspfad und ohne Git-Laufzeitfallback im frischen Commit-Snapshot nachweisen.
- [x] 2.3 Erwarteten Projektzustand mit 50 Tickets, 28 Seiten und 1044 Relationen commitgebunden prüfen.

## 3. Kontrollzentrum

- [x] 3.1 Monitorvertrag, Audit, Zielprüfung, Berichtsparser und Publisher auf `portable-snapshot-release` umstellen.
- [x] 3.2 Projektziele und Installationstexte auf Spectra 1.2.0-alpha.12 und Snapshot 0003 aktualisieren.
- [x] 3.3 Kontrollzentrum-Fixtures, OpenSpec strict, Deutschprüfung und `git diff --check` ausführen.

## 4. Veröffentlichung und Plattform

- [x] 4.1 BC Basic und Project Twin nach vollständigem Kontrolllauf einzeln über `Publish-UniversaarlCommit.ps1` veröffentlichen.
- [x] 4.2 GitHub-Actions-Matrix für Twin auf `windows-latest` und `macos-14` real ausführen und beide Jobs commitgebunden prüfen.
- [x] 4.3 Finale SHAs, Trees, Digests, Plattformstatus und offene menschliche Freigabe im Kontrollzentrum-Bericht dokumentieren.
