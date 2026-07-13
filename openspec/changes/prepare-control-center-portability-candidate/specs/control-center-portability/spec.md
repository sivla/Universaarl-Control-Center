# Kontrollzentrum-Portabilitaet

## Requirement: Reproduzierbarer Doctor
Der Doctor MUSS Voraussetzungen und Repository-Pflichtdateien ohne Secrets, Authentisierungszustaende oder Zielprojektinhalte pruefen und einen maschinenlesbaren Status liefern.

## Requirement: Plattformneutraler Bootstrap
Der Bootstrap MUSS ausschliesslich ignorierte Artefakte im Kontrollzentrum erzeugen und den sicheren Prozesshelfer mit der lokal aufgeloesten .NET-Werkzeugkette bauen.

## Requirement: Sicherheitsgrenzen
Windows MUSS die bestehenden Jobobjekt- und Handle-Garantien behalten. Unix MUSS Prozesse ohne Shell mit expliziter Umgebung starten, Ausgabe und Laufzeit begrenzen, den Prozessbaum bei Zeitlimit beenden und Symlink-Komponenten fail-closed abweisen.

## Requirement: Ehrlicher Releasezustand
Ohne einen echten macOS-Runnernachweis MUSS der Kandidat `PENDING_MACOS_RUNNER_EVIDENCE` bleiben und DARF weder Version noch Quellcommit oder macOS-Releasebereitschaft behaupten.

## Requirement: Fail-closed Portfolio-Portabilitaetsfreigabe
Das Kontrollzentrum MUSS einen Portfolio-Stand nur dann als portabel freigeben, wenn ein externes maschinenlesbares Manifest vier getrennte ohne lokale Credentials anonym frisch klonbare oeffentliche Repositories und deren verifizierte Commit- und Tree-SHAs bindet. Der gebundene Kontrollcommit DARF nur Validator und Template enthalten; das finale Manifest MUSS als spaeteres Release-Asset oder generierter Bericht ausserhalb dieses Commits liegen und den Validatorcommit explizit binden. Arbeitsbaum und Index des Kontrollzentrums MUESSEN sauber sein; Validator und Template MUESSEN bytegenau den Blobs des gebundenen Kontrollcommits entsprechen. Die SHA-256 der Spectra-Manifestdatei MUSS getrennt von einem aus allen manifestgelisteten, am Releasecommit verifizierten Payloadblobs kanonisch neu berechneten Aggregatdigest geprueft werden.

Windows- und macOS-Evidence MUESSEN denselben unveraenderlichen Snapshotdigest binden. Fresh Clone, Installation, Start, gitfreie Laufzeit, Pilotanzeige, Filesystem-/HTTP-Paritaet, Onboarding und Isolation MUESSEN als erfolgreiche Records mit vorgeschriebener Command-ID, festem Commandtext, schema-validem Inhaltsartefakt, SHA-256 und Zeitbezug vorliegen. Die Runnerprovenienz MUSS den exakten oeffentlichen GitHub-Actions-Run, Repository, Workflowpfad, Commit, erfolgreiche Plattformjobs und Runnerlabels binden; das Attestierungsarchiv MUSS anonym heruntergeladen und gegen GitHub- sowie Download-Digest geprueft werden. Es MUSS die byteidentische Plattform-Evidence und exakt deren acht gebundene Record-Artefakte enthalten. Nur sicher entpackte Archivmember duerfen die Inhaltspruefung speisen; fehlende, doppelte, absolute, traversierende, uebergrosse, verlinkte oder digestabweichende Member MUESSEN blockieren. Freie Manifest- oder Evidence-Booleans duerfen kein Gate schliessen; ein Arbeits-Mac oder anderweitig nicht verifizierbares Attest bleibt `PENDING`.

## Requirement: Reproduzierbares Pilot- und Neu-Projekt-Onboarding
Die Plattform-Evidence MUSS aus einem oeffentlichen Fresh Clone Spectra und Twin installieren, den BC-Basic-Pilot-Snapshot ohne Git-Laufzeitquelle anzeigen, Filesystem-/HTTP-Paritaet beweisen und ein zweites isoliertes Projekt anlegen und sichtbar machen.

### Scenario: Arbeits-Mac kann Pilot und neues Projekt verwenden
- **WENN** die vier oeffentlichen Repositories frisch geklont werden
- **DANN** zeigt der Twin den digestvalidierten Pilotstand und nach Spectra-Onboarding ein zweites isoliertes Projekt, ohne ein Quellrepository zur Laufzeit zu lesen

### Scenario: Vollstaendig belegter Stand
- **WENN** alle Komponenten, Vertragsgates und beide Plattformnachweise vollstaendig und digestkonsistent sind
- **DANN** liefert der Pruefer exakt `PORTABLE_RELEASE_READY`

### Scenario: Fehlender oder widerspruechlicher Nachweis
- **WENN** ein Repository nicht oeffentlich ist oder eine SHA, ein Remote-Ref, ein Digest, ein Snapshot-/Onboarding-Gate oder ein Plattformnachweis fehlt beziehungsweise abweicht
- **DANN** blockiert der Pruefer und darf keine Portabilitaetsfreigabe ausgeben
