# Kontrollzentrum-Portabilitaet

## ADDED Requirements

### Requirement: Reproduzierbarer Doctor
Der Doctor MUSS (`MUST`) Voraussetzungen und Repository-Pflichtdateien ohne Secrets, Authentisierungszustaende oder Zielprojektinhalte pruefen und einen maschinenlesbaren Status liefern.

#### Scenario: Doctor ohne Zielprojektzugriff
- **WENN** der Doctor in einem frischen Kontrollzentrum-Clone gestartet wird
- **DANN** prueft er nur lokale Voraussetzungen und Kontrollzentrum-Pflichtdateien und liefert einen maschinenlesbaren Status

### Requirement: Plattformneutraler Bootstrap
Der Bootstrap MUSS (`MUST`) ausschliesslich ignorierte Artefakte im Kontrollzentrum erzeugen und den sicheren Prozesshelfer mit der lokal aufgeloesten .NET-Werkzeugkette bauen.

#### Scenario: Bootstrap bleibt im Kontrollzentrum
- **WENN** der Bootstrap ausgefuehrt wird
- **DANN** entstehen nur ignorierte Kontrollzentrum-Artefakte und kein Zielprojekt wird veraendert

### Requirement: Sicherheitsgrenzen
Windows MUSS (`MUST`) die bestehenden Jobobjekt- und Handle-Garantien behalten. Unix MUSS Prozesse ohne Shell mit expliziter Umgebung starten, Ausgabe und Laufzeit begrenzen, den Prozessbaum bei Zeitlimit beenden und Symlink-Komponenten fail-closed abweisen.

#### Scenario: Unsicherer Prozess oder Pfad
- **WENN** ein Prozess das Zeitlimit ueberschreitet oder eine Pfadkette einen Link enthaelt
- **DANN** beendet beziehungsweise blockiert das Kontrollzentrum den Vorgang fail-closed

### Requirement: Ehrlicher Releasezustand
Ohne einen echten macOS-Runnernachweis MUSS (`MUST`) der Kandidat `PENDING_MACOS_RUNNER_EVIDENCE` bleiben und DARF weder Version noch Quellcommit oder macOS-Releasebereitschaft behaupten.

#### Scenario: macOS-Nachweis fehlt
- **WENN** kein echter commitgebundener macOS-Runnernachweis vorliegt
- **DANN** bleibt der Kandidat `PENDING_MACOS_RUNNER_EVIDENCE`

### Requirement: Fail-closed Portfolio-Portabilitaetsfreigabe
Das Kontrollzentrum MUSS (`MUST`) einen Portfolio-Stand nur dann als portabel freigeben, wenn ein externes maschinenlesbares Manifest vier getrennte ohne lokale Credentials anonym frisch klonbare oeffentliche Repositories und deren verifizierte Commit- und Tree-SHAs bindet. Der gebundene Kontrollcommit DARF nur Validator und Template enthalten; das finale Manifest MUSS als spaeteres Release-Asset oder generierter Bericht ausserhalb dieses Commits liegen und den Validatorcommit explizit binden. Arbeitsbaum und Index des Kontrollzentrums MUESSEN sauber sein; Validator und Template MUESSEN bytegenau den Blobs des gebundenen Kontrollcommits entsprechen. Die SHA-256 der Spectra-Manifestdatei MUSS getrennt von einem aus allen manifestgelisteten, am Releasecommit verifizierten Payloadblobs kanonisch neu berechneten Aggregatdigest geprueft werden.

Windows- und macOS-Evidence MUESSEN denselben unveraenderlichen Snapshotdigest binden. Fresh Clone, Installation, Start, gitfreie Laufzeit, Pilotanzeige, Filesystem-/HTTP-Paritaet, Onboarding und Isolation MUESSEN als erfolgreiche Records mit vorgeschriebener Command-ID, festem Commandtext, schema-validem Inhaltsartefakt, SHA-256 und Zeitbezug vorliegen. Die Runnerprovenienz MUSS den exakten oeffentlichen GitHub-Actions-Run, Repository, Workflowpfad, Commit, erfolgreiche Plattformjobs und Runnerlabels binden; das Attestierungsarchiv MUSS anonym heruntergeladen und gegen GitHub- sowie Download-Digest geprueft werden. Es MUSS die byteidentische Plattform-Evidence und exakt deren acht gebundene Record-Artefakte enthalten. Nur sicher entpackte Archivmember duerfen die Inhaltspruefung speisen; fehlende, doppelte, absolute, traversierende, uebergrosse, verlinkte oder digestabweichende Member MUESSEN blockieren. Freie Manifest- oder Evidence-Booleans duerfen kein Gate schliessen; ein Arbeits-Mac oder anderweitig nicht verifizierbares Attest bleibt `PENDING`.

#### Scenario: Portabilitaetsevidence ist unvollstaendig
- **WENN** ein Commit, Tree, Digest, Record oder Runnernachweis fehlt oder abweicht
- **DANN** darf das Kontrollzentrum `PORTABLE_RELEASE_READY` nicht ausgeben

### Requirement: Reproduzierbares Pilot- und Neu-Projekt-Onboarding
Die Plattform-Evidence MUSS (`MUST`) aus einem oeffentlichen Fresh Clone Spectra und Twin installieren, den BC-Basic-Pilot-Snapshot ohne Git-Laufzeitquelle anzeigen, Filesystem-/HTTP-Paritaet beweisen und ein zweites isoliertes Projekt anlegen und sichtbar machen.

#### Scenario: Arbeits-Mac kann Pilot und neues Projekt verwenden
- **WENN** die vier oeffentlichen Repositories frisch geklont werden
- **DANN** zeigt der Twin den digestvalidierten Pilotstand und nach Spectra-Onboarding ein zweites isoliertes Projekt, ohne ein Quellrepository zur Laufzeit zu lesen

#### Scenario: Vollstaendig belegter Stand
- **WENN** alle Komponenten, Vertragsgates und beide Plattformnachweise vollstaendig und digestkonsistent sind
- **DANN** liefert der Pruefer exakt `PORTABLE_RELEASE_READY`

#### Scenario: Fehlender oder widerspruechlicher Nachweis
- **WENN** ein Repository nicht oeffentlich ist oder eine SHA, ein Remote-Ref, ein Digest, ein Snapshot-/Onboarding-Gate oder ein Plattformnachweis fehlt beziehungsweise abweicht
- **DANN** blockiert der Pruefer und darf keine Portabilitaetsfreigabe ausgeben

### Requirement: Dreistufige Produktionsreife
Das Kontrollzentrum MUSS (`MUST`) fuer Spectra, BC Basic, Project Twin und sich selbst Plattformreife, Onboarding-Reife und kundenspezifische Go-live-Reife getrennt aus commitgebundener Evidence bewerten. Plattform- und Onboarding-Reife MUESSEN bestanden sein, bevor das Portfolio als bereit fuer neue Kundenarbeit gilt. Ein konkreter Kunden-Go-live DARF nur durch BC Basic und ausschliesslich mit realer Evidence fuer Tenant, Lizenzen, Berechtigungen, UAT, Cutover, ersten Abschluss, UStVA und Supportuebergabe bestanden werden. Synthetische, historische oder quellabhaengig dargestellte Evidence DARF diesen Status nicht schliessen.

#### Scenario: Portfolio ist arbeitsbereit, Kunde aber noch nicht live
- **WENN** alle vier Komponenten Plattform- und Onboarding-Reife bestanden haben, aber reale Kundenevidence fehlt
- **DANN** lautet der Portfoliostatus `PORTFOLIO_READY_FOR_CUSTOMER_WORK` und der Kundenstatus weiterhin `PENDING_REAL_CUSTOMER_EVIDENCE`

#### Scenario: Simulation versucht echten Go-live zu schliessen
- **WENN** eine Kundeninstanz `customerGoLiveReady=passed` mit synthetischer oder unvollstaendiger Evidence meldet
- **DANN** blockiert die Pruefung fail-closed

### Requirement: Deployment- und Distributionsgrenzen
Jede Komponente MUSS (`MUST`) ihre Deploymentgrenze commitgebunden ausweisen. Der Twin ist im aktuellen Produktstand ausschliesslich als lokaler Loopback-Einzeloperator zulaessig. Externe Distribution MUSS getrennt von technischer Arbeitsreife eine ausdrueckliche Lizenzentscheidung nachweisen; ein oeffentlich lesbares Repository allein ist keine Nutzungslizenz.

#### Scenario: Oeffentliches Repository ohne Lizenzentscheidung
- **WENN** ein Repository oeffentlich lesbar ist, aber keine ausdrueckliche Lizenzentscheidung besitzt
- **DANN** bleibt die externe Distribution nicht freigegeben, auch wenn die interne technische Arbeitsreife bestanden ist
