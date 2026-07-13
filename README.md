# Universaarl Kontrollzentrum

Dieses Repository hat genau einen Zweck: den Zustand des Universaarl BC Blueprint V2 und des Universaarl Project Twin unabhaengig zu beobachten, getrennt zu bewerten, Probleme in ihrem Zusammenspiel sichtbar zu machen und bereits vorhandene freigegebene Versionsstaende kontrolliert zu veroeffentlichen. Es enthaelt keine Funktionen des Blueprint oder des Twin und bearbeitet oder erstellt dort niemals Zielcode-Versionen.

## Vertragskette

Der fachliche Datenfluss ist `Spectra (technisches Repository BCProjectOS) -> versionierter Produktvertrag -> BC Basic -> validierter Snapshot -> Project Twin`. Das Kontrollzentrum steht ausserhalb dieser Kette. Es installiert keinen Produktvertrag und erzeugt keine Kunden- oder Snapshotwahrheit, sondern prueft die vorhandenen Nachweise commitgebunden.

- Spectra: `product_id: spectra`; technisches Repository BCProjectOS unter `https://github.com/sivla/BCProjectOS.git`; Release-Tags `spectra-v<SemVer>`
- BC Basic: `https://github.com/sivla/FiBu.git`, Zweig `codex/universaarl-projekt`
- Project Twin: `https://github.com/sivla/FiBu.git`, Zweig `codex/universaarl-projekt-twin`

Die bekannte BCProjectOS-Repository-URL ist noch kein Spectra-Release. Bis annotierter `spectra-v<SemVer>`-Tag, Tag-Commit, finales Manifest, gueltiger Manifest-Source-Commit und passender SHA-256-Payload-Digest gemeinsam nachgewiesen sind, bleibt die Bindung `PENDING_BCPROJECTOS_RELEASE`; ein Snapshot ist dann nicht veroeffentlichungsreif. Ein reiner `CONTRACT_REFERENCE_ONLY`-Release darf zwar als Produktvertrag geprueft werden, autorisiert aber keine Kundeninstallation und keinen Snapshot. Dafuer ist ein finaler `INSTALLABLE_BLUEPRINT`-Release erforderlich. Ein irrtuemlich im Kontrollzentrum angelegter Consumer-/Installationspfad wurde deshalb entfernt. Die konkrete Consumer-Bindung gehoert ausschliesslich in BC Basic.

Die dauerhafte Rollenpruefung kann separat ausgefuehrt werden:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-ControlCenterRoleBoundary.ps1
```

## Überwachte Projekte

| ID | Aufgabe | Standardpfad |
|---|---|---|
| `blueprint` | Fachliche und technische Projektwahrheit | `C:\Users\kkali\Documents\Universaarl Projekt BC Basic` |
| `project-twin` | Ausschliesslich lesende Darstellung des Blueprint | `C:\Users\kkali\Documents\Universaarl-Project-Twin` |

Die Standardpfade stehen in `monitor.config.json`. Für einen anderen Rechner können sie ohne Dateiänderung mit `UNIVERSAARL_BLUEPRINT_PATH` und `UNIVERSAARL_TWIN_PATH` überschrieben werden.

## Frisches System vorbereiten

Der Doctor prueft die lokale Werkzeugkette und Pflichtdateien, ohne Zielprojekte oder Zugangsdaten zu lesen. Der Bootstrap baut zusaetzlich nur den ignorierten Prozesshelfer unter `.work/`:

```powershell
./scripts/Initialize-UniversaarlControlCenter.ps1 -Json
./scripts/Initialize-UniversaarlControlCenter.ps1 -Bootstrap
```

Vorausgesetzt werden Git 2.40, Node.js 20, .NET SDK 6 und unter macOS PowerShell 7.4. Auf Windows bleibt PowerShell 5.1 zulaessig. Die portable Implementierung ist lokal unter Windows und synthetisch fuer Unix pruefbar; echte macOS-Releasebereitschaft bleibt bis zu einem bestandenen macOS-Runnerlauf `PENDING_MACOS_RUNNER_EVIDENCE`.

## Prüfung starten

Die schnelle Prüfung liest nur Metadaten, Manifeste und Git-Zustand:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Invoke-UniversaarlAudit.ps1
```

Die vollstaendige Pruefung erzeugt fuer beide Projekte aus der jeweils festgehaltenen vollen Commit-SHA eine eigene temporaere Git-Kopie ohne Remote. Arbeitskopie, ignorierte und unversionierte Dateien werden nicht uebernommen. `npm ci`, Tests und Erstellungslauf laufen ausschliesslich dort:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Invoke-UniversaarlAudit.ps1 -RunValidations
```

Ergebnisse werden unter einer eindeutigen Laufkennung in `reports/runs/` gespeichert; `reports/latest.*` ist nur eine bequeme Ansicht und niemals ein Veroeffentlichungsnachweis. Diese Laufdaten werden nicht eingecheckt.

## Projektziele pruefen

Technische Gesundheit allein beweist noch keinen Fortschritt zum Projektziel. Die separate Zielpruefung vergleicht deshalb lokalen, veroeffentlichten und noch nicht abgeschlossenen Arbeitsstand, erkennt strategische Abweichungen und bewertet auch das Zusammenspiel beider Projekte:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Invoke-UniversaarlGoalReview.ps1
```

Der gebundene Bericht liegt unter seiner Laufkennung in `reports/goal-runs/`; `reports/goals-latest.*` ist nur eine Ansicht. Die Pruefung liest Zieltexte als kleine regulaere Blobs aus den festgehaltenen Commits. Sie liest keine realen `.env*`, Authentifizierungszustaende, Geheimnisse, Ablaufspuren, Videos oder Laufzeitnachweise. Rot markiert einen Zielwiderspruch, Gelb eine offene Ziel- oder Reihenfolgeluecke und Gruen einen belegbar ausgerichteten Stand.

Die sichtbaren Kontrolltexte und alle erzeugten Markdown-Berichte muessen deutsch sein. Die Kontrollzentrum-Pruefung ist nur eine ergaenzende Oberflaechenpruefung. Fuer eine Veroeffentlichung muss jedes Zielprojekt zusaetzlich den in `monitor.config.json` benannten npm-Pruefer ausfuehren und einen commitgebundenen JSON-Nachweis mit Projekt-ID, voller SHA, Sprache `de` und bestaetigtem deutschen Eigeninhalt liefern:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Test-UniversaarlGermanSurface.ps1
```

Der projektspezifische npm-Pruefer schreibt genau ein JSON-Objekt auf die Standardausgabe, beispielsweise:

```json
{"schemaVersion":1,"status":"passed","language":"de","projectId":"project-twin","commit":"<VOLLSTAENDIGE_SHA>","userVisibleOwnContentGerman":true}
```

Fehlender, unlesbarer, nicht commitgebundener oder anders aufgebauter Nachweis blockiert die Veroeffentlichung.

## Versionsstand- und Veroeffentlichungsablauf

1. Der jeweilige Projekt-Agent bearbeitet und prüft nur sein Zielprojekt. Er vermeidet inhaltsarme Mikro- oder Alibi-Commits; eine fachlich zusammenhaengende, reviewbare Aenderung darf bewusst zwei bis drei notwendige Arbeitsschritte umfassen und wird als genau ein kohaerenter Commit uebergeben.
2. Er leert `REVIEW.md`, erstellt dort einen lokalen Versionsstand und prueft nach jedem neuen Commit erneut, dass `REVIEW.md` sowohl in der Arbeitskopie als auch in `HEAD` leer beziehungsweise reiner Leerraum ist.
3. Er uebergibt Zweig, vollstaendige Commit-SHA, Pruefergebnis, Nachweis der leeren Pruefdatei und sauberen Git-Zustand.
4. Das Kontrollzentrum fuehrt eine commitgebundene technische Pruefung in bereinigten Wegwerfkopien und die Twin-Blueprint-Vertragspruefung aus.
5. Das Kontrollzentrum blockiert die Veroeffentlichung zusaetzlich bei roter Projektziel- oder Zusammenspielbewertung; gelbe, offen ausgewiesene Folgeziele bleiben sichtbar.
6. Die jeweilige Projektsuite muss alle nutzerseitig sichtbaren Eigeninhalte als deutsch bestaetigen; technische Kennungen, Pfade und unveraenderliche externe Quellwerte bleiben stabil.
7. Nur bei gruenen technischen Pruefstufen, bestandenem projektspezifischem JSON-Deutsch-Nachweis, bestandener ergaenzender Kontrolltextpruefung und nicht roter Zielausrichtung veroeffentlicht das Kontrollzentrum exakt die gepruefte volle Commit-SHA ohne erzwungenes Ueberschreiben.

Die reine Veroeffentlichungsbereitschaftspruefung veraendert kein entferntes Repository:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Publish-UniversaarlCommit.ps1 -Project blueprint
```

Die tatsaechliche Uebertragung benoetigt zusaetzlich `-Execute`:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Publish-UniversaarlCommit.ps1 -Project blueprint -Execute
```

Die beiden kanonischen Arbeitszweige sind `codex/universaarl-projekt` und `codex/universaarl-projekt-twin`. Sie werden ueber den kontrollierten Publisher auf ihre exakt gleichnamigen Zweige im freigegebenen GitHub-Repository uebertragen. Jeder Zielordner verfolgt nur seinen eigenen Arbeitszweig. Alte FiBu- und technische Nebenarbeitskopien sind weder Pruefquelle noch Veroeffentlichungsquelle.

## Bewertung

Der Strukturwert von 0 bis 100 bewertet Erreichbarkeit, Git-Ausgangsstand, sauberen Arbeitsbaum, Manifest, Pruefbefehl, Abhaengigkeits-Sperrdatei, festgelegte Abhaengigkeiten und offene OpenSpec-Arbeit. Die technische Pruefung und kritische Sicherheitsbefunde sind zusaetzliche Pruefstufen.

- **Gruen:** technische und projektspezifische Deutsch-Pruefung bestanden, mindestens 85 Strukturpunkte und kein kritischer, hoher oder mittlerer Befund.
- **Gelb:** beide Pruefungen bestanden, aber mindestens ein hoher oder mittlerer Befund oder weniger als 85 Strukturpunkte.
- **Rot:** kritischer Befund, fehlgeschlagene technische oder Deutsch-Pruefung oder kein sicher aufgeloester Commit.
- **Grau:** technische oder Deutsch-Pruefung wurde nicht ausgefuehrt beziehungsweise ist nicht nachweislich bestanden.

Ein unsauberer Arbeitsbaum ist nicht automatisch ein Softwarefehler, verhindert aber eine belastbare gruene Aussage ueber den veroeffentlichten Stand.

## Sicherheitsmodell

- Externe Zielpfade stehen auf einer festen Positivliste.
- Die Wegwerfkopie wird ausschliesslich aus dem exakten Commit erzeugt; Arbeitskopie, ignorierte und unversionierte Dateien werden nie kopiert.
- Die Vertragspruefung verwendet nochmals frisch erzeugte Commitkopien und eine neue skriptfreie Abhaengigkeitsinstallation; Ergebnisse oder `node_modules` vorheriger Zielpruefungen werden nicht wiederverwendet.
- Versionierte reale `.env*`, Laufzeitmaterial, Test-/Browser-Videos und Reparse-Punkte werden vor einer Pruefkopie blockiert. Einzige Produktmedien-Ausnahme ist fuer Blueprint der exakte regulaere Commitblob `artifacts/walkthrough/generated/UABC-WT-ENV-001/walkthrough.webm` im Modus `100644` bis 1 MiB; Project Twin besitzt keine Medien-Positivliste.
- Laufberichte und Protokolle werden nur in komponentenweise gepruefte, reparse-freie Verzeichnisse geschrieben, groessenbegrenzt handlegebunden erzeugt und anschliessend erneut verifiziert.
- Reale `.env*` bleiben ungelesen; nur die versionierte `HEAD:.env.example` wird als Dokumentationsvertrag auf Platzhalter, Groesse, Mandantenkennungen und absolute Hostpfade geprueft.
- Pruefprozesse erben keine Benutzergeheimnisse und erhalten ein getrenntes Benutzer- und Zwischenspeicherverzeichnis. Protokolle sind groessenbegrenzt und redigieren bekannte Geheimnisformen.
- Die Wegwerfkopie ist keine Betriebssystem-Sandbox. Zielprozesse laufen weiterhin mit dem Benutzertoken und koennen technisch Netzwerk und andere fuer diesen Benutzer erreichbare Pfade ansprechen.
- Volle HEAD-SHA sowie Status- und Index-Fingerprint werden vor und nach jedem Lauf ohne worktreeweiten Inhalts-Hash verglichen.
- Nach einer echten Uebertragung werden HEAD, Status und Index beider Zielprojekte erneut gegen den gebundenen Lauf geprueft.
- Das Kontrollzentrum berichtet und empfiehlt; es repariert keines der beiden Projekte automatisch.
- Die Veroeffentlichungspruefstufe kann weder Versionsstaende erstellen noch erzwungen uebertragen, Git-Marken, Freigaben oder Zusammenfuehrungsanfragen erzeugen.
- Fuer Remote-Abfragen und die Uebertragung gelten keine geerbten Git-Umgebungsvariablen oder URL-Umschreibungen: Die rohe Ziel-Remote-URL muss exakt passen, und der Push startet aus einer frischen remotelosen Commitkopie mit bereinigter Git-Konfiguration sowie einem neu erzeugten, reparse-freien, nachweislich leeren und ausschliesslich innerhalb der Publisher-Wegwerfkopie liegenden Hookpfad. `--no-verify` und jede Abweichung von dieser Publisher-Hookpolicy sind verboten; unversionierte Zielprojekt-Hooks werden niemals uebernommen oder ausgefuehrt.
