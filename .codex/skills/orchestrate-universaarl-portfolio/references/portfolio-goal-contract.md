# Ausführliche Portfolio-Zielverträge

Diese Referenz ist bei jeder Zieldefinition oder Zielnachjustierung vollständig zu lesen. Sie beschreibt den Mindestumfang. Ein Projektauftrag darf konkreter, aber nicht kleiner werden.

## Gemeinsame Zielstruktur

Jeder Projektauftrag enthält:

1. Rolle und harte Repositorygrenze.
2. Belegten Ausgangscommit und bereits erreichte Ergebnisse.
3. Fachlichen Endzustand aus Benutzersicht.
4. Verbindliche Arbeitsstränge und ihre Reihenfolge.
5. Konkrete Artefakte und Evidence.
6. Positive und negative Qualitätsprüfungen.
7. Einen großen aktuellen Lieferblock.
8. Abnahmekriterien mit Branch, SHA, Tree, Tests, REVIEW und Arbeitsbaum.
9. Stop-Regeln, die echte Sicherheitsgrenzen von lösbaren Arbeitsproblemen trennen.
10. Genau die nächste größte Lücke nach der Übergabe.

Prompts sind keine Evidence. Mikro- und Alibi-Commits sind unzulässig.

## Gemeinsames Endprodukt: digitaler Projektzwilling

Das gemeinsame Endprodukt von Spectra, BC Basic und Project Twin ist die vollständige, realitätsnah simulierte Projektgeschichte einer BC-Basic-Einführung vom Angebot bis zum Ende der Hypercarephase.

BC Basic erzeugt die fachliche Wahrheit: versioniertes Angebotsdokument, Projektauftrag, vollständigen Confluence-Seitenbaum, Jira-ähnliche Tickets mit Statushistorie, Worklogs, Evidence, Arbeits- und Abschlusskommentaren, Meetings, Entscheidungen, Risiken, BC-Playthrough, Tests, UAT, Training, Cutover, GO_SIMULATION, simulierten Go-live, jeden Hypercaretag, Restart und Handover.

Spectra liefert dafür kundenunabhängige Schemas, Generatoren und Validatoren. Pflichttypen sind Angebot/Leistungspaket, Confluence-Seite und Seitenbaum, Ticket/Epic/Story/Task/Subtask/Bug/Change, Kommentar, Worklog, Statusübergang, Story-Ereignis, Hypercaretag und Projektabschluss. Done- oder Closed-Tickets benötigen erfüllte Akzeptanzkriterien, Evidence und Abschlusskommentar.

Project Twin visualisiert genau diese commitgebundene Geschichte: Managementcockpit, Angebot, Seitenbaum, Ticketboard, Ticketdetail mit Kommentaren, Timeline, BC-Sitzungen und Ledger Entries, Tests, Gates, Hypercaredashboard und Handover. Nutzer können zwischen Story-Ereignis, Ticket, Seite, Use-Case, BC-Sitzung, Test und Evidence navigieren.

Der gemeinsame Validator beweist:

- Angebot, Stunden, Kosten, Worklogs und Projektstory stimmen rechnerisch überein.
- Seiten, Tickets, Kommentare, Use-Cases, BC-Sitzungen, Tests, Evidence und Story sind bidirektional verknüpft.
- Keine leere oder unverknüpfte Confluence-Seite.
- Kein Done-Ticket ohne Abschlusskommentar.
- Kein Story-Ereignis ohne Evidence.
- Kein Hypercareabschluss mit offenem P1/P2.
- Vollständige Story vom ersten Angebotsstand bis zum letzten Hypercaretag.

## Projektübergreifender Lernkreislauf

Der verbindliche Kreislauf lautet:

`BC Basic -> anonymisierte Produktkandidaten -> Spectra -> versionierter Release -> BC Basic -> validierter Branch-Commit -> Project Twin -> commitgebundene Nutzungs- und Vertragsbefunde -> verantwortliches Projekt`.

Erkenntnisse fließen, Source-of-Truth-Inhalte und Repositorygrenzen nicht. Jede Übergabe enthält stabile Finding-ID, Herkunftsprojekt, beobachteten Commit, Problem, Evidence, Klassifikation, Anonymisierungsprüfung, betroffene Verträge, Zielprojekt, vorgeschlagene Entscheidung, Status und Begründung.

Die Klassifikation entscheidet den Weg:

- Kundenfachliche Erkenntnis bleibt in BC Basic.
- Generische Produktlücke wird anonymisierter, noch nicht übernommener `blueprint-candidate` für Spectra.
- Fehlende oder inkonsistente Twin-Quelldaten werden commitgebundener Producer-Befund für BC Basic.
- Generische Schema-, ID-, Referenz-, Portabilitäts- oder Validatorlücke wird Produktbefund für Spectra.
- Darstellungs-, Navigations-, Responsivitäts- oder Diagnoselücke bei korrekter Quelle bleibt im Twin.
- Release-, Integritäts- oder Publishlücke bleibt Befund des Kontrollzentrums beziehungsweise des betroffenen Releaseprozesses.

Übernahme erfolgt niemals automatisch. Spectra bewertet Kandidaten als Produktkern, optionales Modul, Dokumentationsbedarf, Consumerproblem oder abgelehnt und übernimmt sie nur über WIP-1-OpenSpec und einen späteren Release. BC Basic bindet erst den veröffentlichten Tag-/Commit-/Manifest-/Digest-Nachweis. Twin liest erst einen unabhängig validierten BC-Commit.

Der Statusfluss lautet `proposed -> accepted|rejected -> implemented -> released -> bound -> visualized`. Nicht anwendbare Stufen werden begründet ausgelassen. Rohkundendaten, Kunden-Evidence-Kopien und direkte Änderungen in fremden Repositories sind verboten.

Aktuelle wiederverwendbare Erkenntnisse:

- Simulierte Kunden-, UAT-, Cutover-, Go-live-, Hypercare-, Restart- und Handover-Gates sind First-Class-Records.
- BC-Bedienplaythroughs benötigen Seite, Aktion, Feld, Posting Preview, Dokumente, Ledger Entries, Kontrolle, Fehler, Korrektur und Retest.
- Consumervalidierung muss portabel und read-only gegen einen fremden Kundenworkspace funktionieren.
- Producer-definierte IDs benötigen einen eindeutigen zentralen Vertrag; Consumer dürfen keine abweichende Regex erfinden.
- Der Branchvertrag benötigt expliziten Branch, Validierungsstatus, sichere Allowlist und einmalige Commit-Pinnung.
- Legacy-Manifeste dürfen den modernen Branchmodus nicht berühren.
- Twin-Readiness erfordert echte Desktop-, Mobil- und fail-closed-Browser-Evidence.
- Spectra 1.0 benötigt zusätzlich Profile, Graphkontrolle, Upgrade, Backup/Restore, Datei-Intake, vollständige CLI und reproduzierbare Dokumentation.

## Spectra

### Rolle

Spectra ist der kundenunabhängige Produktvertrag und das wiederverwendbare Betriebssystem für Business-Central-Einführungsprojekte. Es enthält Schemas, IDs, Relationen, Statusmodelle, Generatoren, Installations- und Upgradepfade, Validatoren, Fixtures und allgemeines quellenbasiertes BC-Wissen. Kundenwissen, Kundendaten, Kundenentscheidungen und Kunden-Evidence bleiben ausgeschlossen.

### Endzustand

Spectra kann einen leeren Projektworkspace reproduzierbar initialisieren, die vollständige generische BC-Basic-Projektkette strukturieren, bestehende Kundeninhalte bei Updates schützen und jeden Workspace deterministisch read-only validieren. Ein unabhängiger Implementierer erkennt Pflichtartefakte, Beziehungen, Gates, Fehlerursachen, Korrekturweg sowie Build-, Upgrade- und Release-Reife.

Das verbindliche Hauptziel ist `Spectra 1.0.0`. Beta- und RC-Releases sind Beweisstufen, nicht das Projektende. 1.0.0 ist erst vollständig, wenn ein frischer Clone mindestens ein Implementation- und ein Support-only-Profil reproduzierbar erzeugen und betreiben kann, der vollständige Projektlebenszyklus abgedeckt ist und Installation, Validatorik, Upgrade, Backup/Restore, Portabilität, Sicherheit, Bedienung und deutsche Dokumentation unabhängig nachgewiesen sind.

### Pflichtumfang

- Initialisierung, Planung, Setup, Migration, P2P, O2C, Cash, Bank, Lager, Monatsabschluss und UStVA-Vorschau.
- SIT, UAT, Training, Cutover, Go-live-Rehearsal, Hypercare, Restart, Abschluss und Handover.
- Synthetische Kunden- und Fachbereichsfreigaben als ausführbare Gates mit Rolle, Kriterien, Entscheidung und Evidence.
- Spezialisierte Schemas für jeden katalogisierten Typ.
- Fail-closed-Referenzgraph, Pfad-, ID-, Kunden-, Status-, Hash-, Modus- und Evidence-Prüfung.
- Stabile Fehlercodes und deterministische maschinenlesbare Ausgabe.
- Idempotente Neuinstallation, Dry-run, Konflikterkennung, Upgrade und Abbruchfälle.
- Positive Fixture je Typ und negative Matrix je Fehlerklasse.
- Offizielle Microsoft-Quellen; dokumentiertes Verhalten, Annahme und synthetischen Wert trennen.
- Implementation- und Support-only-Profil aus demselben Produktkern.
- Einheitliches Ticket-, Change-, Incident-, Problem-, Risk-, Decision- und Wissensmodell.
- Kontrollierter External-File-Intake mit Klassifikation, Hash, Quarantäne-/Ablehnungsweg und ohne Secret-Leak.
- Versionierte Kompatibilitätsmatrix, Upgrade-Dry-run, Konfliktanalyse, Abbruch ohne Teilschaden und Schutz vorhandener Kundeninhalte.
- Backup mit Integritätsmanifest, Restore in ein leeres Ziel und identischer Validierungs-Roundtrip.
- CLI für Init, Validate, Plan Upgrade, Upgrade, Backup, Restore, Candidate und Releaseprüfung.
- Quickstart, Operator-, Implementierungs-, Support-, Upgrade-, Backup-/Restore- und Fehlerbehebungshandbuch.

### Releasetakt

Genau ein OpenSpec-Change und ein Releaseziel gleichzeitig. Ausgangsrelease, Delta, Scope, Nicht-Scope, SemVer und Akzeptanzmatrix müssen vor Candidate-Erzeugung belegt sein. Candidate-Manifest bindet Source-Commit, Payload, Modi und Digest. Candidate ist kein Release. Merge, annotierter Tag und Veröffentlichung benötigen ein getrenntes Gate.

Der Weg zum Hauptrelease besitzt vier Stufen:

1. Beta.1 belegt die vollständige synthetische BC-Basic-Prozesskette und Simulationsgates.
2. Eine evidenzbasierte Vollständigkeits-Beta schließt die verbleibenden 1.0-Fähigkeiten.
3. Ein Pilot/RC beweist beide Profile, Upgrade, Backup/Restore, Manipulationsmatrix, Bedienbarkeit und keine offenen P1/P2-Produktdefects.
4. 1.0.0 wird erst nach unabhängiger Vollständigkeits- und Releaseprüfung über normalen PR, Merge, finales Manifest, annotierten Tag und nicht als Draft veröffentlicht.

Nach jedem Release ist eine 1.0-Gap-Matrix zu aktualisieren. Sie klassifiziert jede Pflichtfähigkeit als vorhanden, teilweise, fehlend oder unbewiesen, nennt die Evidence und bestimmt genau den nächsten großen Releaseblock.

Die Entwicklung läuft ohne Leerlauf releaseweise bis 1.0.0: veröffentlichter Ausgang, aktualisierte Gap-Matrix, ein WIP-1-Change, belegtes Delta, Candidate, unabhängiger Gate, normaler PR/Merge/Tag/Release, Post-Release-Verifikation und unmittelbar der nächste Zyklus. Unveröffentlichte Featurestapel über mehrere Zyklen und willkürliches Pausieren nach einem Candidate sind unzulässig.

### Definition of Done für 1.0.0

Ein unabhängiger Prüfer kann aus einem frischen Clone zwei isolierte synthetische Workspaces erzeugen, beide Profile bedienen, ein BC-Basic-Projekt bis zum Handover durchführen, Tickets und Evidence verwalten, alle Validatoren ausführen, einen unterstützten Upgradepfad durchlaufen, Backup und Restore identisch nachweisen und Manipulationen fail-closed ablehnen. Manifest, Digest, Tag, Commit und GitHub-Release sind konsistent; keine Pflichtfähigkeit und kein P1/P2-Produktdefect bleibt offen.

### Übergabe

Branch, volle SHA, Parent, Tree, Remote-SHA, Produktdelta, OpenSpec-Status, Testmatrix, Fixture-, Installations-, Upgrade- und Validatorproof, Candidate-Manifest/Digest, REVIEW leer, Arbeitsbaum sauber, bekannte Grenzen und nächste größte Produktlücke.

## Universaarl BC Basic

### Rolle

BC Basic ist die alleinige fachliche Kunden-Source-of-Truth. Das vollständige Einführungsprojekt wird mit konsistenten synthetischen Daten repositorybasiert so durchgeführt, als wären die geplanten Schritte in einer BC-Sandbox ausgeführt worden. Es wird keine aktive BC-, Kunden-, Bank-, Mail-, Steuer- oder Produktivumgebung benutzt.

### Simulationswahrheit

Jeder geplante Prozessschritt wird als Datei- und Datenrehearsal ausgeführt. Synthetische Belege, Beträge, Konten, MwSt., Lagerbewegungen, Zahlungen und Kontrollsummen bilden eine zusammenhängende Projektwelt. Kundenfreigabe, Fachbereichsabnahme, UAT-Sign-off, Cutover-GO, Go-live, Hypercare-Abnahme, Restart und Handover sind echte, abschließbare Simulationsgates. Sie benötigen Rollen, Eingaben, Kriterien, Entscheidung, Abweichung und Evidence. Produktive Nutzung ist außerhalb des Simulationsscopes und kein offener Simulationsblocker.

### Pflichtphasen

1. Auftrag, Scope, Budget, Rollen, Meilensteine und Gate-Matrix.
2. Discovery, Prozesse, Use-Cases, Anforderungen und Traceability.
3. Finanz-, MwSt.-, Buchungsgruppen-, Nummernserien-, Dimensions-, Perioden-, Lager- und Berechtigungssetup.
4. Stammdaten, Migration, Datenqualität, Probeladung und Kontrollsummen.
5. P2P mit Normal-, Abweichungs-, Gutschrift-, Storno- und Sperrfällen.
6. O2C mit Angebot, Auftrag, Lieferung, Rechnung, Zahlung, Ausgleich, Rückgabe und Korrektur.
7. Zahlungen, Kunden-/Lieferantenausgleich, synthetischer Kontoauszug und Bankabstimmung.
8. Lagerbewegung, Inventur, Differenz, Korrektur sowie Mengen-/Wertabgleich.
9. Monatsabschluss, Nebenbuch-/Sachbuchabgleich und synthetische UStVA-Vorschau.
10. SIT, Defects, Ursachen, Fixes und Retests.
11. UAT, Trainings, Lernerfolg und synthetischer Sign-off.
12. Cutover-Generalprobe und GO_SIMULATION.
13. Simulierter Go-live, Hypercare, P1/P2-Triage, Restart, Abschluss und Support-Handover.

### Evidence je Use-Case

Stabile ID, Phase, Rolle, Eingaben, Vorbedingungen, geplante BC-Schritte, synthetische Belegnummern, Buchungs-/Konten-/MwSt.-/Lagerwirkung, Kontrollsumme, Abweichung, Korrektur, Retest, synthetische Abnahme und Referenzen zu Anforderung, Arbeitspaket, Test, Entscheidung, Quelle und Evidence.

Ein realitätsnaher BC-Zugriffsplaythrough ergänzt je Use-Case den offiziellen BC-Seitennamen, Suche oder Navigation, Aktion, FastTab, Feldwerte, Validierungen, Buchungsvorschau, Bestätigung, erzeugte Dokumentnummern, erwartete Sach-, Debitoren-, Kreditoren-, MwSt.-, Bank-, Artikel- und Wertposten sowie die Nachkontrolle über Drill-down oder Find Entries. Fehlerfall, Korrektur und Retest sind Pflicht. Diese strukturierten Sitzungsprotokolle simulieren die Bedienung; sie dürfen nicht als echte UI-Antwort oder Live-BC-Evidence ausgegeben werden.

### Vertragsgrenzen

Nur echten Spectra-Release mit Tag, Commit, Manifest, Source-Commit und Digest binden. `exports/project-data/v1/index.yaml` ist der einzige Twin-Allowlistvertrag. Alle aktuellen Twin-Artefakte werden im selben normalen Commit positivgelistet. Kein A/B-Manifest, keine Selbst-SHA und kein ungepinnter Arbeitsbaumvertrag.

### Abnahme

Alle Phasen und Gates besitzen konkrete synthetische Evidence, keine offenen P1/P2-Simulationsdefects, alle Deliverables sind simulated-complete oder begründet außerhalb des Scopes, Demo-Readiness ist grün, Spectra-Bindung und Branch-Index sind validiert, REVIEW ist in Arbeitskopie und HEAD leer, Arbeitsbaum sauber. Übergabe mit Branch, SHA, Parent, Tree, Tests, Indexblob, Artefaktzahl, Digest und sichtbaren Twin-Ergebnissen.

## Project Twin

### Rolle

Der Twin ist ein strikt nur-lesendes, vollständig deutsches Projektcockpit für den neuesten validierten BC-Basic-Branch-Commit. Er ist keine Source of Truth, schreibt niemals zurück, liest keine ungeprüften Arbeitsstände und erfindet keine Fachwerte.

### Quellvertrag

Den erlaubten Branch einmal auf eine volle SHA auflösen. Danach ausschließlich `exports/project-data/v1/index.yaml` und positivgelistete Git-Blobs aus dieser SHA lesen. Projektidentität, Branch, validationStatus, readOnly, contractRole, pathSemantics, sichere Pfade, eindeutige IDs, Blobs, Modi, Digests und Referenzen fail-closed prüfen. Im Branchmodus Legacy-Manifest, Schema, Parent-A und A/B-Diff überhaupt nicht öffnen oder verwenden. Kein Tree-Scan, Arbeitsbaum-Fallback oder Rückschreiben. `.env.local` bleibt ungelesen und unverändert.

### Sichtbarer Pflichtumfang

- Projektidentität, Simulationskennzeichnung, Branch, SHA, Validierungsstatus und Spectra-Release.
- Gesamtstatus und Phasen von Discovery bis Handover.
- Prozesse, Use-Cases, Anforderungen, Arbeitspakete und Abhängigkeiten.
- SIT, UAT, Defects, Fixes und Retests.
- Entscheidungen, Risiken, Maßnahmen und Restwirkung.
- Deliverables, Demo-Readiness, Cutover, GO_SIMULATION, Hypercare, Restart und Abschluss.
- Synthetische Kunden-/Fachbereichsfreigaben als bestandene Gates, wenn Evidence dies belegt.
- Klarer Hinweis: vollständig simuliert, keine reale BC- oder Produktivaktivität.

### Negative Matrix

Falsches Projekt, falscher Branch, falscher validationStatus, ungültige Vertragsfelder, unsicherer oder doppelter Pfad, fehlender Blob, falscher Modus/Digest, doppelte ID, ungültige Referenz, Branchbewegung, ungepinnter Read und lokale Umgebungsübersteuerung blockieren. Fehlendes oder kaputtes Legacy-Manifest bleibt im Branchmodus wirkungslos.

### Browserabnahme

Positive Desktop- und Mobilansicht gegen die finale BC-SHA sowie mindestens ein echter fail-closed-Browserfall mit Screenshot. Relevante Tests, genau ein `npm run check`, Deutschgate, REVIEW leer, `.env.local` unverändert und sauberer Arbeitsbaum. Übergabe mit Twin-SHA, Parent, Tree, BC-SHA, Testzahlen, Screenshotpfaden, sichtbaren Ergebnissen und Negativfehlercode.

## Kontrollzentrum

### Rolle

Das Kontrollzentrum bleibt außerhalb der Fachdatenkette. Es definiert Ziele, steuert große Lieferblöcke, prüft Übergaben unabhängig, bewertet Integrität und Zusammenspiel und koordiniert eine spätere Veröffentlichung. Es bearbeitet keinen Zielcode und erzeugt keine Kundenwahrheit.

### Arbeitsweise

1. Tatsächlichen Task-, Git- und Teststand erfassen.
2. Pro Projekt genau die größte verbleibende Lücke bestimmen.
3. Einen großen ergebnisorientierten Block mit konkreter Abnahme zuweisen.
4. Übergabe gegen SHA, Tree, Tests, REVIEW, Arbeitsbaum und Vertrag prüfen.
5. BC-Spectra-Bindung und BC-Twin-Index unabhängig validieren.
6. Positive Browser-Evidence verlangen; Unit-Tests ersetzen sie nicht.
7. Portfoliozustand nur nach geprüfter Evidence aktualisieren.
8. Keine realitätsfremden Blocker erzeugen: vollständig simulierte Freigaben schließen Simulationsgates.
9. Release oder Push nur über vorhandene freigegebene Gates.

### Gesamtabschluss

Spectra besitzt den erforderlichen veröffentlichten Release und einen belegten nächsten Candidate-Zyklus. BC Basic ist fachlich vollständig simuliert, synthetisch abgenommen und als sauberer validierter Commit übergeben. Twin zeigt genau diesen Commit auf Desktop und Mobil und blockiert negative Fälle fail-closed. Das Kontrollzentrum hat die Kette unabhängig geprüft und den aktuellen Portfoliozustand reproduzierbar festgehalten.
