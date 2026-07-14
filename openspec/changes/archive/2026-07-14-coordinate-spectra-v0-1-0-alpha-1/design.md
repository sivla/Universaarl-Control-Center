# Design: erster Spectra-Alpha-Release

> Historischer Entwurf; durch die spaetere versionierte Spectra-/Snapshotkette ersetzt.

## Release-Identitaet

- Produktname: `Spectra`
- Produktkennung: `spectra`
- SemVer: `0.1.0-alpha.1`
- Release-Tag: `spectra-v0.1.0-alpha.1`
- Releasequelle: exakt ein nach `main` gemergter Spectra-Commit

Die weiterhin vorhandene technische Repository-Adresse ist nur Transport- und
Identitaetsinformation. Sie ersetzt weder Produktkennung noch Release-Nachweis.
Eine spaetere Umbenennung des GitHub-Repositories darf den Releasevertrag nicht
stillschweigend veraendern.

## Verantwortungen

Der Spectra-Projektchat erstellt genau einen kohaerenten Arbeitsbranch, fuehrt
die projektspezifischen Pruefungen aus, pusht nur diesen Branch und uebergibt
Commit, Tree, Testergebnisse und Pull Request. Er merged, taggt und released
nicht selbst.

Das Kontrollzentrum liest den uebergebenen Stand, prueft Repository, Branch,
Commit, Tree, Vertragsinhalt, Testnachweise und Diff. Es gibt den Merge frei
oder nennt reproduzierbare Blocker. Tag und Release duerfen erst auf dem
freigegebenen Commit nach Merge nach `main` entstehen.

## Alpha-Vertrag

Der Release muss ohne Kundenwissen installierbar und validierbar sein. Das
Release-Manifest bindet mindestens Schema-Version, Produktkennung, SemVer,
Tag, vollen Commit, Payload-Digest und den vorgesehenen Consumer-Modus. Digest
und Commit werden aus dem freigegebenen Inhalt berechnet und niemals manuell
erfunden.

## Nachgelagerte Kette

Nach dem Release bindet BC Basic exakt Tag, Commit und Digest. Erst danach wird
ein validierter Snapshot als Produzentenstand A plus direkter Manifest-Commit B
erzeugt. Project Twin bindet ausschliesslich B. Diese Schritte bleiben eigene
OpenSpec-Auftraege und blockieren den Alpha-Release nicht.
