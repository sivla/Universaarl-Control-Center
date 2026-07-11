# Auftrag dieses Repositories

Dieses Repository ist ausschliesslich das **Universaarl Kontrollzentrum**. Es beobachtet, prueft und bewertet genau diese zwei externen Projekte und veroeffentlicht deren bereits vorhandene, freigegebene Versionsstaende:

1. `blueprint` – `C:\Users\kkali\Documents\Universaarl Projekt BC Basic`
2. `project-twin` – `C:\Users\kkali\Documents\Universaarl-Project-Twin`

Die Pfade dürfen über die in `monitor.config.json` genannten Umgebungsvariablen ersetzt werden. Andere externe Projekte gehören nicht zum Auftrag.

## Unverhandelbare Grenzen

- Die Quelldateien der beiden Zielprojekte sind aus diesem Repository heraus grundsätzlich schreibgeschützt.
- Das Kontrollzentrum bearbeitet Zielcode niemals und erstellt dort keine Versionsstaende. Seine einzige regulaere Aenderung ausserhalb dieses Repositories ist ein geprueftes, normales `git push` eines bereits vorhandenen Versionsstands.
- Keine Abhaengigkeiten, Zweige, entfernten Repositories, Nachverfolgungszweige, Git-Marken, Freigaben oder Zusammenfuehrungsanfragen in den Zielprojekten anlegen oder veraendern.
- Keine automatischen Reparaturen durchführen. Befunde und Verbesserungsvorschläge gehören in Berichte dieses Repositories.
- Ausfuehrbare Tests und Erstellungsvorgaenge nur in einer bereinigten, exakt aus der festgehaltenen Commit-SHA erzeugten Wegwerfkopie ausserhalb der Zielprojekte starten. Diese Kopie ist keine Betriebssystem-Sandbox: Prozesse besitzen weiterhin den Benutzertoken und technisch erreichbaren Netzwerkzugang.
- Reale `.env*`, Authentifizierungszustaende, Zugriffsschluessel, Geheimnisse, Browserprofile, Ablaufspuren, Test-/Browser-Videos und Laufzeitnachweise weder lesen noch kopieren. Ausnahmen sind ausschliesslich die versionierte `HEAD:.env.example` fuer ihre begrenzte Dokumentationspruefung sowie der fuer Blueprint in `monitor.config.json` exakt positivgelistete regulaere Produktblob `artifacts/walkthrough/generated/UABC-WT-ENV-001/walkthrough.webm` im Modus `100644` bis 1 MiB. Diese Ausnahmen werden niemals als Laufzeitkonfiguration oder externer Laufzeitnachweis verwendet.
- Zielcode darf keine geerbten Zugangsdaten erhalten. Prüfprozesse verwenden eine minimale, bereinigte Umgebung.
- Nur Berichte, Konfiguration und Kontrollcode in diesem Repository veraendern.
- Eine andere Aenderung an einem Zielprojekt ist nur zulaessig, wenn der Benutzer sie spaeter ausdruecklich und projektspezifisch beauftragt. Sie ist nie Teil eines normalen Kontroll- oder Veroeffentlichungslaufs.

## Rollenverteilung

- Agenten in `blueprint` und `project-twin` duerfen lokal arbeiten, pruefen und Versionsstaende erstellen, aber niemals veroeffentlichen.
- Projekt-Agenten erzeugen keine inhaltsarmen Mikro- oder Alibi-Commits. Eine fachlich zusammenhaengende, reviewbare Aenderung darf bewusst zwei bis drei notwendige Arbeitsschritte umfassen und wird dennoch als genau ein kohaerenter Commit uebergeben.
- Nach jedem neuen Commit prueft der Projekt-Agent erneut, dass `REVIEW.md` sowohl in der Arbeitskopie als auch in `HEAD` leer beziehungsweise reiner Leerraum ist.
- Jede Uebergabe enthaelt Projektkennung, Zweig, vollstaendige Commit-SHA, Pruefergebnis und einen sauberen Arbeitsbaum.
- Das Kontrollzentrum erstellt in den Zielprojekten keine Versionsstaende. Es bewertet genau den uebergebenen Stand und veroeffentlicht ihn bei bestandenen Pruefstufen.

## Veroeffentlichungspruefstufe

Eine Uebertragung ist nur ueber `scripts/Publish-UniversaarlCommit.ps1` und nur fuer ein einzelnes Projekt erlaubt. Alle Bedingungen muessen erfuellt sein:

1. Das Projekt ist in `monitor.config.json` ausdruecklich fuer die Veroeffentlichung aktiviert.
2. Name des entfernten Repositories, exakte Uebertragungsadresse und Zielzweig stimmen mit der Positivliste ueberein.
3. Arbeitsbaum ist sauber; Zweig und HEAD stimmen unveraendert mit dem Pruefbericht ueberein.
4. Die konfigurierte Pruefdatei existiert in `HEAD` und ist dort sowie in der Arbeitskopie leer beziehungsweise reiner Leerraum.
5. Commitgebundene technische Pruefung in der bereinigten Wegwerfkopie, projektspezifischer maschinenlesbarer Deutsch-Nachweis, Projektstatus und Twin-Blueprint-Vertrag sind bestanden beziehungsweise gruen.
6. Die strategische Zielpruefung ist fuer das zu veroeffentlichende Projekt und das Zusammenspiel nicht rot; gelbe, ausdruecklich dokumentierte Folgeziele bleiben zulaessig.
7. Die projektspezifische Pruefsuite weist nach, dass alle nutzerseitig sichtbaren Eigeninhalte deutsch sind; technische Kennungen, Pfade und unveraenderliche externe Quellwerte bleiben davon ausgenommen.
8. Der entfernte Stand ist ein Vorfahr von HEAD oder der Zielzweig existiert noch nicht.
9. Es wird genau `HEAD` ohne erzwungenes Ueberschreiben auf den konfigurierten Zweig uebertragen.

Erzwungene Uebertragung, `--force-with-lease`, `--no-verify`, Git-Marken, Freigaben, Zusammenfuehrungsanfragen, Aenderungen entfernter Repositories und jede Abweichung vom kontrolliert leeren Publisher-Hookpfad sind im normalen Arbeitsablauf verboten. Unversionierte Hooks der Zielarbeitskopien werden aus Sicherheitsgruenden niemals in die frische Push-Kopie uebernommen oder ausgefuehrt; dieser Ausschluss ist kein Umgehen der Publisher-Hookpolicy.

## Arbeitsweise

Jede Bewertung unterscheidet:

- den veroeffentlichten Zustand: Commit, Zweig, Nachverfolgungszweig und reproduzierbaren Ausgangsstand;
- den lokalen Zustand: unsauberen Arbeitsbaum, unversionierte Arbeit und lokale Artefakte;
- die technische Pruefung: Tests, Erstellungslauf und projektspezifische Pruefer;
- das Zusammenspiel: Der Twin muss den Blueprint-Vertrag weiterhin sicher lesen können.

Berichte muessen eindeutige Laufkennung, Zeitpunkt, beide Eingabe-SHA-Felder, geprueften Stand, Nachweisabdeckung und konkrete Befunde nennen. Bekannte SHAs sind immer vollstaendig; ein nicht aufloesbarer Wert wird im Feld ausdruecklich als unbekannt dargestellt und blockiert jede Veroeffentlichung. `Nicht ausgefuehrt` oder `unbekannt` darf niemals als bestanden oder gruen dargestellt werden.

## Sicherheitsregel für Git

Lesende Git-Abfragen verwenden `GIT_OPTIONAL_LOCKS=0`, damit Git den Index des Zielprojekts nicht nebenbei aktualisiert. Vor und nach einem Lauf werden volle HEAD-SHA sowie Status- und Index-Fingerprint ohne Inhaltszugriff auf reale `.env*` verglichen. Eine Abweichung macht den Lauf ungueltig und erzeugt einen kritischen Befund.
