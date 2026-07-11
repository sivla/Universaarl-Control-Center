# Kontrollentscheidung Spectra 0.1.0-alpha.1

Stand: 2026-07-11

## Entscheidung

- **Draft-PR zur separaten Mergefreigabe bereit:** JA
- **Merge ausgefuehrt:** NEIN
- **Tag oder Release freigegeben:** NEIN
- **Nachgelagerte reale Bindung/Snapshotfreigabe:** NEIN

## Gepruefte Staende

- Spectra: `c3cfcd4723622136be824e45e0a18ab8c8978b12`, Tree `0825b59b217dc5d1324cf7fb582ec22f3c3fe135`, Branch `codex/spectra-v0-1-0-alpha-1`, Draft-PR 1, Remote-SHA identisch, Arbeitsbaum sauber.
- BC Basic: `7b305bac3f68e2257afa7337808a845514679074`, Tree `c086cc6dcee2bf060d1679b4ad49fce0b599e6bd`, Arbeitsbaum sauber, real weiterhin `PENDING_BCPROJECTOS_RELEASE`.
- Project Twin: `c739b8953948ebada7a47d560577316c6e18693d`, Tree `f31ac56b2b5e9ffb6453181cb70f7199fa82b627`, Arbeitsbaum sauber.
- Kontrollzentrum: `0fdfbe140cdf4b9f1e57b61d6b74794ea3b53c8e`, Bound-/Snapshot-A/B-Validator und synthetische Fixtures gruen.

## Kontrollnachweis

Der Spectra-Releasekandidat wurde aus einem frischen Checkout des exakten PR-Commits geprueft. `Test-ReleaseCandidate.ps1 -Version 0.1.0-alpha.1` endet mit Exit 0 und dem Payload-Digest `8ad2eed4e9eaf9dab0a9426c81a1dade6593b6cefcfb4d8170682fb661816a77`. Fehlender Source-Commit und fehlender annotierter Tag bleiben erwartete Pending-Gates bis nach einem separat freigegebenen Merge.

## Naechste getrennte Freigaben

1. Benutzer gibt den unveraenderten Spectra-PR separat zum Merge frei.
2. Erst danach werden finales Manifest, annotierter Tag und Release separat geprueft und freigegeben.
3. Erst mit diesem echten Release bindet BC Basic Spectra und erzeugt Snapshot A/B.
4. Erst danach wird Project Twin an Manifest-Commit B gebunden.
