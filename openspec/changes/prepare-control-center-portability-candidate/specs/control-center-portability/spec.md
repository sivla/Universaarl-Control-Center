# Kontrollzentrum-Portabilitaet

## Requirement: Reproduzierbarer Doctor
Der Doctor MUSS Voraussetzungen und Repository-Pflichtdateien ohne Secrets, Authentisierungszustaende oder Zielprojektinhalte pruefen und einen maschinenlesbaren Status liefern.

## Requirement: Plattformneutraler Bootstrap
Der Bootstrap MUSS ausschliesslich ignorierte Artefakte im Kontrollzentrum erzeugen und den sicheren Prozesshelfer mit der lokal aufgeloesten .NET-Werkzeugkette bauen.

## Requirement: Sicherheitsgrenzen
Windows MUSS die bestehenden Jobobjekt- und Handle-Garantien behalten. Unix MUSS Prozesse ohne Shell mit expliziter Umgebung starten, Ausgabe und Laufzeit begrenzen, den Prozessbaum bei Zeitlimit beenden und Symlink-Komponenten fail-closed abweisen.

## Requirement: Ehrlicher Releasezustand
Ohne einen echten macOS-Runnernachweis MUSS der Kandidat `PENDING_MACOS_RUNNER_EVIDENCE` bleiben und DARF weder Version noch Quellcommit oder macOS-Releasebereitschaft behaupten.
