# Auftrag dieses Repositories

Dieses Repository ist ausschliesslich das **Universaarl Kontrollzentrum**. Es beobachtet, prueft und bewertet genau diese zwei operativen Zielprojekte und veroeffentlicht deren bereits vorhandene, freigegebene Versionsstaende:

1. `blueprint` – `C:\Users\kkali\Documents\Universaarl Projekt BC Basic`
2. `project-twin` – `C:\Users\kkali\Documents\Universaarl-Project-Twin`

Die Pfade dürfen über die in `monitor.config.json` genannten Umgebungsvariablen ersetzt werden. Das technische Repository BCProjectOS darf zusaetzlich ausschliesslich als read-only Release-Evidence-Quelle fuer die Spectra-Bindungspruefung verwendet werden; es ist niemals operatives Zielprojekt oder Publisherziel. Andere externe Projekte gehören nicht zum Auftrag.

## Universaarl-Gesamtarchitektur

Der fachliche Datenfluss ist verbindlich: `Spectra` aus dem technischen Repository `BCProjectOS` -> versionierter Produktvertrag -> `Universaarl Projekt BC Basic` -> validierter Snapshot -> `Universaarl Project Twin`. Das Universaarl Kontrollzentrum steht ausserhalb dieser Datenkette und prueft Versionsbindung, Integritaet, Projektzustand, Snapshot-Vertrag und Veroeffentlichungsreife.

1. **Spectra** ist der wiederverwendbare, kundenunabhaengige Produktvertrag. Sein technisches Projekt und Repository bleiben **BCProjectOS** unter `C:\Users\kkali\Documents\BC Project OS` mit dem kanonischen Remote `https://github.com/sivla/BCProjectOS.git`; `product_id` lautet verbindlich `spectra`, und Release-Tags folgen `spectra-v<SemVer>`. Die Repository-Identitaet allein ist kein Release-Nachweis. Spectra definiert generische Schemas, IDs, Relationen, Statusmodelle, Ticketstrukturen, Generatoren, Validatoren und allgemeines Business-Central-Wissen, aber niemals ungefiltertes Kundenwissen, Kundendaten, Kunden-Evidence oder konkrete Universaarl-Projektentscheidungen.
2. **Universaarl Projekt BC Basic** unter `C:\Users\kkali\Documents\Universaarl Projekt BC Basic` ist die fachliche Kundeninstanz und alleinige Source of Truth fuer Unternehmenswissen, Prozesse, Anforderungen, Arbeitspakete, Meetings, Tests, UAT, Evidence, Abweichungen und Umsetzung.
3. **Universaarl Project Twin** unter `C:\Users\kkali\Documents\Universaarl-Project-Twin` ist eine ausschliesslich lesende Visualisierung eines validierten, versionierten Snapshots aus der Kundeninstanz. Er ist niemals Source of Truth, schreibt niemals zurueck, liest keine ungeprueften Arbeitsstaende und besitzt keine direkte fachliche Abhaengigkeit von BCProjectOS.
4. **Universaarl Kontrollzentrum** in diesem Repository ist die unabhaengige Pruef- und Veroeffentlichungsinstanz. Es ist keine Kundeninstanz, enthaelt keine fachliche Kundenwahrheit und installiert BCProjectOS nicht in einem Zielprojekt.

Die kanonischen oeffentlichen Remote-Zuordnungen verwenden `https://github.com/sivla/Universaarl-BC-Basic.git` fuer die Kundeninstanz und `https://github.com/sivla/Universaarl-Project-Twin.git` fuer Project Twin. Die Arbeitszweige bleiben `codex/universaarl-projekt` beziehungsweise `codex/universaarl-projekt-twin`; `main` ist jeweils der stabile Default-Branch. Die fruehere gemeinsame Zuordnung ueber `https://github.com/sivla/FiBu.git` ist ausschliesslich historische Release-Evidence beziehungsweise bis zum verifizierten Migrationsabschluss ein Legacy-Rueckfallanker und kein kanonisches Publisherziel. Repository- und Zweigidentitaeten ersetzen weder Produktrelease-, Snapshot- noch Freigabenachweise.

Eine Spectra-Version darf nur durch einen echten unveraenderlichen `spectra-v<SemVer>`-Release-Tag samt Commit und Digest aus BCProjectOS gebunden werden. Solange dieser Nachweis fehlt, lautet der bestehende technische Status ehrlich `PENDING_BCPROJECTOS_RELEASE`; weder Version noch Release duerfen erfunden oder aus einem beliebigen Arbeitsstand abgeleitet werden. Bestehende fachliche IDs der Kundeninstanz werden nur aufgrund einer ausdruecklichen Migrationsentscheidung geaendert. Wiederverwendbare Erkenntnisse gelangen ausschliesslich anonymisiert, fachlich geprueft und zunaechst als nicht uebernommene `blueprint-candidates` zurueck zu BCProjectOS.

Absolute lokale Pfade sind nur zur Erkennung des aktuell geoeffneten Arbeitsordners zulaessig und niemals eine dauerhafte fachliche oder technische Laufzeitbindung. Dauerhafte Kopplungen verwenden versionierte Kennungen, Release-Nachweise, relative Projektbeziehungen, Pfad-Aliase oder ausdrueckliche Umgebungsvariablen. Die oben und im bestehenden Auftrag genannten Pfade beschreiben deshalb ausschliesslich die aktuelle lokale Arbeitsraumzuordnung und erweitern den regulaeren Kontrollumfang nicht.

## Rollenspezifisch: Universaarl Kontrollzentrum

- Dieses Projekt prueft die Universaarl-Kundeninstanz, deren Spectra-Versionsbindung aus BCProjectOS, den daraus erzeugten Snapshot-Vertrag und den Project Twin, ohne Bestandteil der fachlichen Datenkette zu werden.
- Der regulaere operative Zielumfang bleibt auf `blueprint` und `project-twin` begrenzt. BCProjectOS wird nicht installiert, kopiert, automatisch uebernommen oder aus diesem Repository heraus bearbeitet; eine vorhandene Bindung wird lediglich gegen Release-Tag, Commit und Digest geprueft.
- Fehlt ein echter Spectra-Release-Nachweis aus BCProjectOS, meldet das Kontrollzentrum `PENDING_BCPROJECTOS_RELEASE` und darf daraus weder Gruen noch Veroeffentlichungsreife ableiten.
- Das Kontrollzentrum erzeugt keine Kundenwahrheit, keine Snapshot-Fachdaten und keine Zielprojekt-Commits. Es bewertet vorhandene Versionsstaende und veroeffentlicht ausschliesslich ueber die bereits definierten Pruef- und Sicherheitsstufen.
- Befunde zu wiederverwendbaren Erkenntnissen duerfen nur anonymisierte, noch nicht uebernommene `blueprint-candidates` empfehlen; eine Rueckuebernahme in BCProjectOS bleibt ein eigener fachlicher Release-Prozess.

## Unverhandelbare Grenzen

- Schreibarbeit am Blueprint erfolgt ausschliesslich in `C:\Users\kkali\Documents\Universaarl Projekt BC Basic` auf `codex/universaarl-projekt`.
- Schreibarbeit am Project Twin erfolgt ausschliesslich in `C:\Users\kkali\Documents\Universaarl-Project-Twin` auf `codex/universaarl-projekt-twin`.
- Fuer Universaarl- oder FiBu-Arbeit werden keine zusaetzlichen Arbeits-Worktrees, P001-Ausweichordner, technischen Nebencheckouts oder temporaeren Schreibkopien angelegt. Jedes in Codex eingerichtete Projekt wird nur in seinem eigenen Projektordner bearbeitet.
- Bereinigte Wegwerfkopien fuer commitgebundene Tests bleiben reine Pruefkopien. Sie sind niemals Arbeitsquelle und werden nicht fuer Datei- oder Commit-Aenderungen verwendet.
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

### Pragmatische Abschlussregel

- Fuer koordinierte Arbeit gilt standardmaessig der kleinste fachlich zusammenhaengende und sichere Umfang.
- Nach der Umsetzung folgt hoechstens eine gezielte unabhaengige Review-Runde. Danach blockieren nur konkrete, reproduzierbare Vertrags-, Sicherheits- oder Veroeffentlichungsfehler; Komfort-, Stil- und zusaetzliche Haertungswuensche werden als getrennte Folgeauftraege notiert.
- Zuerst laufen die direkt betroffenen Tests, danach genau ein angemessener Gesamtcheck. Ein reines Werkzeug-Timeout wird mit passendem Zeitlimit wiederholt und nicht als neue Analyse- oder Refactoringrunde behandelt.
- Sobald der vereinbarte Umfang und seine verbindlichen Gates gruen sind, wird der lokale Stand unmittelbar als ein kohaerenter Commit uebergeben. Weitere Optimierung erfolgt nur nach einem eigenen Auftrag.

Jede Bewertung unterscheidet:

- den veroeffentlichten Zustand: Commit, Zweig, Nachverfolgungszweig und reproduzierbaren Ausgangsstand;
- den lokalen Zustand: unsauberen Arbeitsbaum, unversionierte Arbeit und lokale Artefakte;
- die technische Pruefung: Tests, Erstellungslauf und projektspezifische Pruefer;
- das Zusammenspiel: Der Twin muss den Blueprint-Vertrag weiterhin sicher lesen können.

Berichte muessen eindeutige Laufkennung, Zeitpunkt, beide Eingabe-SHA-Felder, geprueften Stand, Nachweisabdeckung und konkrete Befunde nennen. Bekannte SHAs sind immer vollstaendig; ein nicht aufloesbarer Wert wird im Feld ausdruecklich als unbekannt dargestellt und blockiert jede Veroeffentlichung. `Nicht ausgefuehrt` oder `unbekannt` darf niemals als bestanden oder gruen dargestellt werden.

## Sicherheitsregel für Git

Lesende Git-Abfragen verwenden `GIT_OPTIONAL_LOCKS=0`, damit Git den Index des Zielprojekts nicht nebenbei aktualisiert. Vor und nach einem Lauf werden volle HEAD-SHA sowie Status- und Index-Fingerprint ohne Inhaltszugriff auf reale `.env*` verglichen. Eine Abweichung macht den Lauf ungueltig und erzeugt einen kritischen Befund.
