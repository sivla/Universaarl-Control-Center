# Auftrag dieses Repositories

Dieses Repository ist ausschliesslich das **Universaarl Kontrollzentrum**. Es beobachtet, prueft und bewertet genau diese zwei externen Projekte und veroeffentlicht deren bereits vorhandene, freigegebene Versionsstaende:

1. `blueprint` – `C:\Users\kkali\Universaarl-BC-Blueprint-V2`
2. `project-twin` – `C:\Users\kkali\Documents\Universaarl-Project-Twin`

Die Pfade dürfen über die in `monitor.config.json` genannten Umgebungsvariablen ersetzt werden. Andere externe Projekte gehören nicht zum Auftrag.

## Unverhandelbare Grenzen

- Die Quelldateien der beiden Zielprojekte sind aus diesem Repository heraus grundsätzlich schreibgeschützt.
- Das Kontrollzentrum bearbeitet Zielcode niemals und erstellt dort keine Versionsstaende. Seine einzige regulaere Aenderung ausserhalb dieses Repositories ist ein geprueftes, normales `git push` eines bereits vorhandenen Versionsstands.
- Keine Abhaengigkeiten, Zweige, entfernten Repositories, Nachverfolgungszweige, Git-Marken, Freigaben oder Zusammenfuehrungsanfragen in den Zielprojekten anlegen oder veraendern.
- Keine automatischen Reparaturen durchführen. Befunde und Verbesserungsvorschläge gehören in Berichte dieses Repositories.
- Ausfuehrbare Tests und Erstellungsvorgaenge nur in einer bereinigten Wegwerfkopie ausserhalb der Zielprojekte starten.
- `.env*`, Authentifizierungszustaende, Zugriffsschluessel, Geheimnisse, Browserprofile, Ablaufspuren, Videos und Laufzeitnachweise weder lesen noch kopieren.
- Zielcode darf keine geerbten Zugangsdaten erhalten. Prüfprozesse verwenden eine minimale, bereinigte Umgebung.
- Nur Berichte, Konfiguration und Kontrollcode in diesem Repository veraendern.
- Eine andere Aenderung an einem Zielprojekt ist nur zulaessig, wenn der Benutzer sie spaeter ausdruecklich und projektspezifisch beauftragt. Sie ist nie Teil eines normalen Kontroll- oder Veroeffentlichungslaufs.

## Rollenverteilung

- Agenten in `blueprint` und `project-twin` duerfen lokal arbeiten, pruefen und Versionsstaende erstellen, aber niemals veroeffentlichen.
- Jede Uebergabe enthaelt Projektkennung, Zweig, vollstaendige Commit-SHA, Pruefergebnis und einen sauberen Arbeitsbaum.
- Das Kontrollzentrum erstellt in den Zielprojekten keine Versionsstaende. Es bewertet genau den uebergebenen Stand und veroeffentlicht ihn bei bestandenen Pruefstufen.

## Veroeffentlichungspruefstufe

Eine Uebertragung ist nur ueber `scripts/Publish-UniversaarlCommit.ps1` und nur fuer ein einzelnes Projekt erlaubt. Alle Bedingungen muessen erfuellt sein:

1. Das Projekt ist in `monitor.config.json` ausdruecklich fuer die Veroeffentlichung aktiviert.
2. Name des entfernten Repositories, exakte Uebertragungsadresse und Zielzweig stimmen mit der Positivliste ueberein.
3. Arbeitsbaum ist sauber; Zweig und HEAD stimmen unveraendert mit dem Pruefbericht ueberein.
4. Die konfigurierte Pruefdatei existiert in `HEAD` und ist dort sowie in der Arbeitskopie leer beziehungsweise reiner Leerraum.
5. Abgeschottete technische Pruefung, Projektstatus und Twin-Blueprint-Vertrag sind bestanden beziehungsweise gruen.
6. Die strategische Zielpruefung ist fuer das zu veroeffentlichende Projekt und das Zusammenspiel nicht rot; gelbe, ausdruecklich dokumentierte Folgeziele bleiben zulaessig.
7. Die projektspezifische Pruefsuite weist nach, dass alle nutzerseitig sichtbaren Eigeninhalte deutsch sind; technische Kennungen, Pfade und unveraenderliche externe Quellwerte bleiben davon ausgenommen.
8. Der entfernte Stand ist ein Vorfahr von HEAD oder der Zielzweig existiert noch nicht.
9. Es wird genau `HEAD` ohne erzwungenes Ueberschreiben auf den konfigurierten Zweig uebertragen.

Erzwungene Uebertragung, `--force-with-lease`, Git-Marken, Freigaben, Zusammenfuehrungsanfragen, Aenderungen entfernter Repositories und das Umgehen von Git-Pruefhaken sind im normalen Arbeitsablauf verboten.

## Arbeitsweise

Jede Bewertung unterscheidet:

- den veroeffentlichten Zustand: Commit, Zweig, Nachverfolgungszweig und reproduzierbaren Ausgangsstand;
- den lokalen Zustand: unsauberen Arbeitsbaum, unversionierte Arbeit und lokale Artefakte;
- die technische Pruefung: Tests, Erstellungslauf und projektspezifische Pruefer;
- das Zusammenspiel: Der Twin muss den Blueprint-Vertrag weiterhin sicher lesen können.

Berichte muessen Zeitpunkt, geprueften Stand, Nachweisabdeckung und konkrete Befunde nennen. `Nicht ausgefuehrt` oder `unbekannt` darf niemals als bestanden oder gruen dargestellt werden.

## Sicherheitsregel für Git

Lesende Git-Abfragen verwenden `GIT_OPTIONAL_LOCKS=0`, damit Git den Index des Zielprojekts nicht nebenbei aktualisiert. Vor und nach einem Lauf wird eine Inhaltspruefsumme der erlaubten Quelldateien verglichen. Eine Abweichung macht den Lauf ungueltig und erzeugt einen kritischen Befund.
