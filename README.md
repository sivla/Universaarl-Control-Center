# Universaarl Kontrollzentrum

Dieses Repository prüft und veröffentlicht vorhandene Versionsstände der Universaarl-Kundeninstanz und des Project Twin. Es erzeugt keine Kundenwahrheit, installiert Spectra nicht und bearbeitet keinen Zielcode.

## Verbindliche Kette

`BCProjectOS / Spectra → Universaarl Projekt BC Basic → unveränderlicher Snapshot → Universaarl Project Twin`

Das Kontrollzentrum steht außerhalb dieser Datenkette. Es prüft:

- den echten installierbaren Spectra-Release aus BCProjectOS;
- den vollständigen portablen BC-Basic-Snapshot;
- die strikt lesende Twin-Grenze;
- volle Commits, Trees, Digests, Arbeitsbaumfingerprints und Plattformstatus;
- die kontrollierte Veröffentlichung genau eines Zielprojekts je Lauf.

## Aktuelle geprüfte Anker

| Komponente | Stand |
|---|---|
| Spectra | `spectra-v1.2.0-alpha.12`, Commit `6b3d9a1bfaf6cd806218a802fdde8f1a4cfa55a1` |
| BC Basic | Commit `281d2bab4fadce74c7756cc42a14dbf0a6a9eb45`, Snapshot `UABC-PORTABLE-PILOT-0004` |
| Project Twin | Commit `cae38797e4cdee0cd53e59ff2b7e84446a2d9363` |

Der Snapshot bindet das Manifest mit SHA-256 `38fcef85b101c05aee075a0692e08956a5090796aa2015affd5c687a2503daf3`, 158 Projektquellen und insgesamt 161 Releasefiles. Der Spectra-Payloaddigest lautet `b637a82c381d7744f08949c264393382cb90d7e6b1f67d56afacb6e88a312c7b`.

Diese Werte sind Prüfevidence, keine freie Versionskonfiguration. Ein späterer Stand muss erneut vollständig nachgewiesen werden.

## Projektordner und Remotes

| Rolle | Lokaler Standardordner | Remote / Zweig |
|---|---|---|
| Spectra-Evidence | `C:\Users\kkali\Documents\BC Project OS` | `sivla/BCProjectOS`, Tag `spectra-v1.2.0-alpha.12` |
| Kundeninstanz | `C:\Users\kkali\Documents\Universaarl Projekt BC Basic` | `sivla/Universaarl-BC-Basic`, `codex/universaarl-projekt` |
| Project Twin | `C:\Users\kkali\Documents\Universaarl-Project-Twin` | `sivla/Universaarl-Project-Twin`, `codex/universaarl-projekt-twin` |
| Kontrollzentrum | `C:\Users\kkali\Documents\Universaarl ai` | `sivla/Universaarl-Control-Center` |

Abweichende lokale Pfade werden ausschließlich über `UNIVERSAARL_BCPROJECTOS_PATH`, `UNIVERSAARL_BLUEPRINT_PATH` und `UNIVERSAARL_TWIN_PATH` übergeben. Sie werden nicht als dauerhafte Laufzeitkopplung gespeichert.

## Installation auf einem neuen Rechner

Voraussetzungen sind Git ab 2.40, Node.js 20.19 oder ab 22.12, npm und auf macOS PowerShell 7.4 oder neuer.

```powershell
git clone https://github.com/sivla/BCProjectOS.git "BC Project OS"
git clone --single-branch --branch codex/universaarl-projekt https://github.com/sivla/Universaarl-BC-Basic.git "Universaarl Projekt BC Basic"
git clone --single-branch --branch codex/universaarl-projekt-twin https://github.com/sivla/Universaarl-Project-Twin.git "Universaarl-Project-Twin"
git clone https://github.com/sivla/Universaarl-Control-Center.git "Universaarl ai"
```

Spectra wird niemals von einem beliebigen Arbeitszweig installiert:

```powershell
Set-Location "BC Project OS"
git switch --detach spectra-v1.2.0-alpha.12
powershell -NoProfile -ExecutionPolicy Bypass -File automation/Test-ReleaseCandidate.ps1 -Version 1.2.0-alpha.12 -RequirePublished
```

Project Twin erhält nur einen externen Katalogeintrag. Für die lokale Kundeninstanz:

```powershell
Set-Location "..\Universaarl-Project-Twin"
npm ci
npm run twin:bootstrap
npm run twin:configure -- --catalog-id bc-basic --catalog-type filesystem --catalog-address "C:\Pfad\Universaarl Projekt BC Basic" --customer-id UABC-CUSTOMER-001 --project-id UABC-BC-BASIC-001 --display-name "Universaarl BC Basic"
npm run twin:doctor
npm run twin:start
npm run twin:status
```

Für einen veröffentlichten Katalog wird `--catalog-type https` mit einer HTTPS-Basisadresse verwendet. Filesystem und HTTPS müssen exakt denselben Zeiger, dasselbe Manifest und dieselben Payloadbytes liefern. `.env`-Dateien, Repositoryscans und Git sind keine Twin-Laufzeitquellen.

Beenden:

```powershell
npm run twin:stop
```

## Produktionsreife und reales Kunden-Onboarding

Produktionsreife wird in drei getrennten Ebenen bewertet:

1. `platformReady`: Installation, Betrieb, Tests, Sicherheit und Plattformnachweis sind belastbar.
2. `onboardingReady`: Ein neuer Kunde kann mit vollstaendigen Inputs, Rollen, Runbooks, Recovery und Uebergaben gestartet werden.
3. `customerGoLiveReady`: Ein konkreter Kunde darf erst nach realem Tenant, Lizenzen, Berechtigungen, UAT, Cutover, erstem Abschluss, UStVA und Supportuebergabe gruene Evidence besitzen.

Eine vollstaendige Simulation kann die ersten beiden Ebenen belegen, niemals aber den realen Kunden-Go-live. Die commitgebundene Pruefung lautet:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/Test-UniversaarlProductionReadiness.ps1
```

Solange Zielkomponenten ihre versionierte Readiness-Evidence noch nicht uebergeben haben, endet der Lauf absichtlich mit `PORTFOLIO_NOT_READY_FOR_CUSTOMER_WORK`. Mit `-AllowPending -Json` kann der vollstaendige offene Befund fuer die Koordination ausgegeben werden. Die Lizenz- und Distributionsfreigabe ist ein separates Gate; oeffentliche Lesbarkeit eines Repositories erteilt keine Lizenz.

## Kontrollprüfung

Schnelle Metadaten- und Vertragsprüfung:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/Invoke-UniversaarlAudit.ps1
```

Vollständige Prüfung in frischen, exakt commitgebundenen Wegwerfkopien:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/Invoke-UniversaarlAudit.ps1 -RunValidations
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/Invoke-UniversaarlGoalReview.ps1
```

Berichte liegen unter einer eindeutigen Laufkennung in `reports/runs` und `reports/goal-runs`. Sie werden nicht eingecheckt. `Nicht ausgeführt`, `unbekannt` und `PENDING` sind niemals bestanden.

## Veröffentlichungsablauf

Der Projekt-Agent übergibt einen sauberen Commit mit leerer `REVIEW.md`. Das Kontrollzentrum führt alle technischen, deutschen, strategischen und projektübergreifenden Gates erneut aus.

Nur Bereitschaft prüfen:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/Publish-UniversaarlCommit.ps1 -Project blueprint
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/Publish-UniversaarlCommit.ps1 -Project project-twin
```

Exakt den geprüften HEAD ohne Force veröffentlichen:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/Publish-UniversaarlCommit.ps1 -Project blueprint -Execute
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/Publish-UniversaarlCommit.ps1 -Project project-twin -Execute
```

Der Publisher erstellt keine Commits, Tags, Releases oder Pull Requests. Er überträgt genau einen bereits vorhandenen Commit auf den positivgelisteten gleichnamigen Zweig.

## Plattformstatus

Der Spectra-Release 1.2.0-alpha.12 besitzt einen grünen Windows-/macOS-Release-Lauf. Die projektübergreifende Twin-Snapshot-Matrix ist ein eigener Nachweis. Bis der veröffentlichte Twin-Commit auf `windows-latest` und `macos-14` real erfolgreich gelaufen ist, bleibt sie `PENDING_PLATFORM_BROWSER_EVIDENCE`.

Ein lokaler Windows-Browserlauf oder ein synthetisches Unix-Fixture ersetzt diesen Plattformnachweis nicht. Der externe Portfolio-Validator gibt erst bei vollständig gebundenem finalem Manifest exakt `PORTABLE_RELEASE_READY` aus:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/Test-UniversaarlPortableRelease.ps1 -ManifestPath C:\release-evidence\portfolio-final.json
```

## Sicherheitsgrenzen

- Zielprojekte werden während der Prüfung nicht verändert.
- Lesezugriffe verwenden `GIT_OPTIONAL_LOCKS=0`.
- Reale `.env*`, Secrets, Browserprofile, Traces und Laufzeitvideos werden nicht gelesen oder kopiert.
- Testprozesse erhalten eine minimale bereinigte Umgebung und laufen in commitgebundenen Wegwerfkopien.
- Der Twin liest keine BCProjectOS- oder Git-Laufzeitquelle und schreibt keine Fachdaten zurück.
- Force-Push, `--no-verify`, neue Remotes, Tags, Releases und Pull Requests sind im normalen Publisherpfad verboten.
