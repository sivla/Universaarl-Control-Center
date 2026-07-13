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

## Gesamtinstallation auf einem neuen Rechner

Diese Anleitung beschreibt den tatsaechlich vorhandenen Repository-Zustand. BC Basic und Project Twin liegen derzeit noch als getrennte Zweige im Repository `sivla/FiBu`. Die geplanten eigenen Repositories werden erst nach einer kontrollierten Migration verwendet; nicht vorhandene Repository-Namen duerfen nicht in Installationsskripten vorweggenommen werden.

### Schnellstart unter Windows

Auf einem neuen Windows-Rechner genuegen zunaechst Git, Node.js 20 und Windows PowerShell. Diesen Block einmal in PowerShell ausfuehren:

```powershell
git config --global core.longpaths true
New-Item -ItemType Directory -Force C:\U | Out-Null
Set-Location C:\U

git clone https://github.com/sivla/BCProjectOS.git "BC Project OS"
git clone --single-branch --branch codex/universaarl-projekt https://github.com/sivla/FiBu.git "Universaarl Projekt BC Basic"
git clone --single-branch --branch codex/universaarl-projekt-twin https://github.com/sivla/FiBu.git "Universaarl-Project-Twin"
git clone https://github.com/sivla/Universaarl-Control-Center.git "Universaarl ai"

Set-Location "C:\U\BC Project OS"
git switch --detach spectra-v1.1.0-alpha.1
powershell -NoProfile -ExecutionPolicy Bypass -File automation/Test-ReleaseCandidate.ps1 -Version 1.1.0-alpha.1 -RequirePublished

Set-Location "C:\U\Universaarl-Project-Twin"
npm ci
npm run check
```

Wenn alle Befehle erfolgreich waren, den Twin starten:

```powershell
Set-Location "C:\U\Universaarl-Project-Twin"
npm run dev -- --host 127.0.0.1 --port 4173
```

Danach im Browser `http://127.0.0.1:4173/` oeffnen. Beendet wird der lokale Server mit `Strg+C`.

Optional kann in einem zweiten PowerShell-Fenster das Kontrollzentrum pruefen:

```powershell
Set-Location "C:\U\Universaarl ai"
$env:UNIVERSAARL_BCPROJECTOS_PATH = 'C:\U\BC Project OS'
$env:UNIVERSAARL_BLUEPRINT_PATH = 'C:\U\Universaarl Projekt BC Basic'
$env:UNIVERSAARL_TWIN_PATH = 'C:\U\Universaarl-Project-Twin'
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/Invoke-UniversaarlAudit.ps1
```

Wenn einer dieser Schritte fehlschlaegt, nicht improvisieren: den Fehler anhand der folgenden Detailabschnitte einordnen. macOS bleibt bis zum echten Runnernachweis ein separates offenes Installationsgate.

### Verbindliche Portabilitaetsfreigabe

Ein beliebiger Branchstand ist niemals garantiert portabel. Die Bindung erfolgt deshalb zwingend in zwei Stufen:

1. Der unveraenderliche Kontrollzentrum-Commit enthaelt nur den Validator und `release/portfolio-portability-manifest.template.json`. Diese Datei ist eine Vorlage und niemals Release-Evidence.
2. Nach Veroeffentlichung dieses Commits wird ausserhalb des Repositorybaums ein finales Manifest als Release-Asset heruntergeladen oder als gebundener Bericht erzeugt. Erst dieses externe Manifest darf den Kontrollzentrum-Commit, die vier Komponenten, das Spectra-Releasemanifest und beide Plattform-Evidence-Dateien binden.

Vor der Uebernahme eines Versionsstands muss der externe Assetpfad explizit angegeben werden:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/Test-UniversaarlPortableRelease.ps1 -ManifestPath C:\release-evidence\portfolio-final.json
```

Nur die exakte Ausgabe `PORTABLE_RELEASE_READY` ist eine Portabilitaetsfreigabe. `BLOCKED`, `PENDING` oder ein fehlender Nachweis bedeutet: Diesen Stand nicht auf einem anderen System ausrollen. Der Pruefer klont alle vier Repositories mit isoliertem Git-Home und ohne Credential Helper, verifiziert Commit und Tree, prueft die SHA-256 der Spectra-Manifestdatei getrennt vom neu aus allen manifestgelisteten Releaseblobs berechneten Aggregatdigest und verlangt fuer Windows und macOS denselben unveraenderlichen Snapshotdigest. Fresh Clone, Installation, Start, gitfreie Laufzeit, Pilotanzeige, Filesystem-/HTTP-Paritaet, Onboarding und Isolation muessen als exakt vorgeschriebene Command-/Artefaktrecords mit Provenienz vorliegen; freie Booleans werden nicht akzeptiert.

Der gebundene Validatorcommit ist selbst ein Trust Anchor: Der Kontrollarbeitsbaum und Index muessen sauber sein, und Validator sowie Vorlage muessen bytegenau ihren Blobs in diesem Commit entsprechen. Fuer Plattformnachweise werden der konkrete oeffentliche GitHub-Actions-Run, Repository, Workflowpfad, Commit, erfolgreicher Plattformjob, Runnerlabel sowie das anonym heruntergeladene Attestierungsarchiv samt GitHub- und Download-SHA-256 geprueft. Die Archivmetadaten liegen dabei ausserhalb der enthaltenen Evidence-Datei im jeweiligen Plattformzeiger des finalen Manifests, damit keine selbstreferenzielle Digestbindung entsteht. Das Archiv muss exakt die byteidentische Plattform-Evidence und ihre acht Record-Artefakte enthalten; fehlende, doppelte, absolute, traversierende, uebergrosse, verlinkte oder digestabweichende Member werden abgelehnt. Records werden in der Produktionspruefung nur aus dem sicher entpackten Archiv validiert. Ein Arbeits-Mac-Nachweis, eine nicht anonym abrufbare Attestation oder ein nur lokal nachgebautes Fixture bleibt `PENDING`.

### Voraussetzungen

- Git ab Version 2.40;
- Node.js `20.19.x` oder ab `22.12.x` sowie das mitgelieferte `npm`;
- Windows PowerShell 5.1 oder PowerShell 7 auf Windows;
- PowerShell 7.4 oder neuer (`pwsh`) auf macOS;
- .NET SDK 6 fuer den Prozesshelfer des Kontrollzentrums;
- Anonymer Lesezugriff auf alle vier im finalen Manifest gebundenen oeffentlichen Repositories.

Passwoerter, Tokens und andere Secrets gehoeren nicht in die Repositories. Lokale Zugangsdaten werden spaeter ausschliesslich ueber die Laufzeitumgebung oder ignorierte lokale Konfiguration bereitgestellt. Die folgenden PowerShell-Beispiele verwenden auf Windows `powershell`. Auf macOS lautet der ausfuehrbare Name `pwsh`; macOS darf jedoch erst nach den unten genannten offenen Plattformgates als installationsbereit gelten.

### 1. Verzeichnisstruktur anlegen

Alle vier Checkouts liegen nebeneinander. Unter Windows wird wegen langer versionierter Projektpfade ein kurzer Root wie `C:\U` verwendet. Git for Windows muss lange Pfade erlauben:

```powershell
git config --global core.longpaths true
mkdir C:\U
cd C:\U
```

Unter macOS kann beispielsweise `~/universaarl` verwendet werden:

```powershell
mkdir -p ~/universaarl
cd ~/universaarl
```

```text
C:/U/ oder ~/universaarl/
|-- BC Project OS/
|-- Universaarl Projekt BC Basic/
|-- Universaarl-Project-Twin/
`-- Universaarl ai/
```

### 2. Repositories klonen

```powershell
git clone https://github.com/sivla/BCProjectOS.git "BC Project OS"
git clone --single-branch --branch codex/universaarl-projekt https://github.com/sivla/FiBu.git "Universaarl Projekt BC Basic"
git clone --single-branch --branch codex/universaarl-projekt-twin https://github.com/sivla/FiBu.git "Universaarl-Project-Twin"
git clone https://github.com/sivla/Universaarl-Control-Center.git "Universaarl ai"
```

Spectra wird fuer eine reproduzierbare Installation nicht von einem beliebigen Arbeitszweig verwendet, sondern auf den veroeffentlichten installierbaren Tag gestellt:

```powershell
cd "BC Project OS"
git switch --detach spectra-v1.1.0-alpha.1
cd ..
```

### 3. Den veroeffentlichten Spectra-Release pruefen

Der aktuell veroeffentlichte Stand wird direkt am ausgecheckten Tag geprueft:

```powershell
cd "BC Project OS"
powershell -NoProfile -ExecutionPolicy Bypass -File automation/Test-ReleaseCandidate.ps1 -Version 1.1.0-alpha.1 -RequirePublished
cd ..
```

Schlaegt die Pruefung fehl, wird nicht mit der Installation fortgefahren. Der veroeffentlichte Pruefer startet intern noch Windows PowerShell und ist deshalb fuer diese Version nur unter Windows freigegeben. Der neue Bootstrap mit lokalem Projektregister, `doctor` und Snapshot-Katalog ist noch nicht Bestandteil von `spectra-v1.1.0-alpha.1`. Er darf erst als Installationsweg verwendet werden, nachdem ein entsprechender portabler Spectra-Release veroeffentlicht und unabhaengig auf macOS geprueft wurde.

### 4. Project Twin installieren und starten

```powershell
cd "Universaarl-Project-Twin"
npm ci
npm run check
npm run dev -- --host 127.0.0.1 --port 4173
```

Danach ist der Twin unter `http://127.0.0.1:4173/` erreichbar und wird mit `Strg+C` beendet. Der Remote-Zweig enthaelt den komfortablen Starter noch nicht. Die Befehle `npm run twin:bootstrap`, `npm run twin:doctor`, `npm run twin:start`, `npm run twin:status` und `npm run twin:stop` liegen derzeit nur als lokaler, noch nicht veroeffentlichter Kandidat vor und duerfen in einer Fresh-Clone-Installation noch nicht vorausgesetzt werden. Bis der Snapshot-Katalogvertrag veroeffentlicht ist, verwendet der aktuelle Stand noch den benachbarten BC-Basic-Checkout. Diese Git-Laufzeitbindung ist ein dokumentierter Uebergangszustand und nicht das Zielmodell.

### 5. Kontrollzentrum vorbereiten und pruefen

```powershell
cd "../Universaarl ai"
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/Invoke-UniversaarlAudit.ps1
```

Der neue `Initialize-UniversaarlControlCenter.ps1` mit `doctor` und Bootstrap ist im lokalen Portabilitaetskandidaten implementiert und commitgebunden geprueft, aber noch nicht auf dem Remote-Standardzweig veroeffentlicht. Er darf in einer Fresh-Clone-Anleitung erst nach dieser Veroeffentlichung vorausgesetzt werden.

Fuer die vollstaendige commitgebundene Pruefung:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/Invoke-UniversaarlAudit.ps1 -RunValidations
```

### 6. Installation abnehmen

Eine Installation ist erst abgenommen, wenn:

1. alle vier Arbeitsbaeume sauber sind;
2. Spectra an einen echten annotierten Release-Tag, Commit, Manifest und Digest gebunden ist;
3. `twin:doctor` und `twin:status` erfolgreich sind;
4. der Twin ausschliesslich den validierten BC-Basic-Stand anzeigt;
5. die Kontrollzentrum-Pruefung keine kritischen Befunde meldet;
6. auf macOS ein echter Runnerlauf statt nur synthetischer Pfadtests vorliegt.

### Aktuell noch offene Installationsgates

- Die portablen Spectra-Snapshot-/Katalogerweiterungen sind noch kein veroeffentlichter Release.
- BC Basic und Project Twin werden noch aus zwei Zweigen des gemeinsamen `FiBu`-Repositories geklont.
- Die endgueltige Twin-Laufzeit ueber `current.json` und immutable Snapshot-Releases ist noch nicht veroeffentlicht.
- Echte macOS-Runner-Evidence bleibt `PENDING_MACOS_RUNNER_EVIDENCE`.

Diese Punkte muessen offen ausgewiesen werden. Sie duerfen weder durch lokale Arbeitsstaende noch durch erfundene Versionsnummern als bestanden dargestellt werden.

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
