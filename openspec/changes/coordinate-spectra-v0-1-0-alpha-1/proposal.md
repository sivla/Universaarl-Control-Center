# Spectra v0.1.0-alpha.1 koordinieren

## Warum

Spectra besitzt bereits einen lokal geprueften ersten Produktvertrag, aber noch
keinen installierbaren, unveraenderlichen Release. Ohne Release-Tag, Commit und
Digest bleibt die Universaarl-Kette korrekt bei
`PENDING_BCPROJECTOS_RELEASE` blockiert.

## Ziel

Der erste kleine, reproduzierbare Alpha-Release wird als
`0.1.0-alpha.1` vorbereitet. Das technische Spectra-Projekt arbeitet in seinem
eigenen Repository auf einem eigenen Arbeitszweig, pusht diesen Zweig und
uebergibt einen Pull Request. Das Kontrollzentrum bewertet den exakt gebundenen
Commit und koordiniert die Freigabe zum Merge nach `main`; es bearbeitet keinen
Spectra-Quellcode.

## Umfang

- installierbarer Spectra-Produktvertrag mit `product_id: spectra`;
- maschinenlesbares Release-Manifest mit Version, Tag, Commit und Digest;
- reproduzierbare Produkt-, Schema-, Consumer- und Secret-Pruefungen;
- Arbeitsbranch und Pull Request statt direktem Push nach `main`;
- kontrollierte Freigabe des Tags `spectra-v0.1.0-alpha.1` erst nach Merge.

## Nicht im Umfang

- produktive Stabilitaetszusage oder Beta-Reife;
- ungefilterte Kundeninhalte oder Universaarl-Projektentscheidungen;
- Blueprint-Snapshot, Project-Twin-Merge oder automatische Rueckschreibungen;
- Force-Push, direkter Projekt-Agent-Merge, Release vom ungeprueften Arbeitsstand.
