## Context

Die verbindliche Kette lautet: Spectra-Release aus BCProjectOS → BC-Basic-Kundeninstanz → unveränderlicher Snapshotrelease → read-only Project Twin. Das Kontrollzentrum steht außerhalb dieser Datenkette und prüft nur vorhandene Commit- und Releaseevidence.

## Decisions

### Spectra wird aus dem Snapshot heraus gegen BCProjectOS geprüft

Der BC-Basic-Snapshot bindet Produkt-ID, kanonisches Repository, Releaseversion, annotiertes Tagobjekt, geschälten Commit, Manifestpfad, Manifest-Source-Commit, Source-Tree, Consumer-Modus, Payloaddigest und Plattformstatus. Der Kontrollvalidator löst das annotierte Tag unabhängig auf und berechnet den Schema-4-Digest einschließlich Git-Modus erneut aus allen 323 Payloadblobs.

### Der portable Snapshot ist der einzige Producer-Consumer-Vertrag

Der Zeiger `exports/project-data/v1/snapshots/current.json` muss exakt ein unveränderliches Release auswählen. Sein Manifest enthält genau 161 Records: einen Projektindex, 158 Projektquellen, einen Knowledge-Payload und ein Katalogfragment. Jeder Record besitzt einen sicheren relativen Pfad, Größe, SHA-256 und identische Filesystem-/HTTPS-Transportbindung.

Projektindex und Projektquellen müssen byteidentisch aus dem festgehaltenen Source-Commit stammen. Die 158 Projektquellen müssen ID, Pfad, Format und Pflichtstatus der vollständigen Index-Allowlist entsprechen. Zusätzliche oder fehlende Dateien im Releaseverzeichnis blockieren.

### Twin-Runtime bleibt gitfrei

Der frische Vertrags-Smoke lädt den realen Snapshot über den Twin-Katalogreader, nachdem der Prozesspfad geleert wurde. Erwartet werden Release 0003, Producer-Commit `8132f2ce692dfcb8e12a3a4db4a287c643a6376f`, Spectra 1.2.0-alpha.12, 50 Tickets, 28 Seiten und 1044 Relationen. Git-, Branch-, Arbeitsbaum- oder zuletzt-bekannt-Fallbacks sind unzulässig.

### Berichte bleiben vollständig gebunden

Audit und Zielprüfung nennen volle Blueprint-, Twin- und BCProjectOS-SHAs, alle wesentlichen Digests und Fingerprints vor sowie nach dem Lauf. Der Publisher akzeptiert nur exakt diese Berichte, grüne technische Beziehungen, nicht rote strategische Beziehungen, leere REVIEW-Dateien und saubere Arbeitsbäume.

### Plattformgates bleiben ehrlich

Der veröffentlichte Spectra-Release besitzt bestandene Windows-/macOS-Releaseevidence. Die neue projektübergreifende Twin-Snapshot-Matrix ist davon getrennt und bleibt bis zum echten Remote-Lauf `PENDING_PLATFORM_BROWSER_EVIDENCE`.

## Rollback

Kontrollcode und Konfiguration können als ein kohärenter Kontrollzentrum-Commit zurückgenommen werden. Zielprojekt-Commits, Spectra-Tag und Snapshotrelease werden dabei nicht verändert.
