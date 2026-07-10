# Universaarl Kontrollzentrum

Dieses Repository hat genau einen Zweck: den Zustand des Universaarl BC Blueprint V2 und des Universaarl Project Twin unabhaengig zu beobachten, getrennt zu bewerten, Probleme in ihrem Zusammenspiel sichtbar zu machen und bereits vorhandene freigegebene Versionsstaende kontrolliert zu veroeffentlichen. Es enthaelt keine Funktionen des Blueprint oder des Twin und bearbeitet oder erstellt dort niemals Zielcode-Versionen.

## Überwachte Projekte

| ID | Aufgabe | Standardpfad |
|---|---|---|
| `blueprint` | Fachliche und technische Projektwahrheit | `C:\Users\kkali\Universaarl-BC-Blueprint-V2` |
| `project-twin` | Ausschliesslich lesende Darstellung des Blueprint | `C:\Users\kkali\Documents\Universaarl-Project-Twin` |

Die Standardpfade stehen in `monitor.config.json`. Für einen anderen Rechner können sie ohne Dateiänderung mit `UNIVERSAARL_BLUEPRINT_PATH` und `UNIVERSAARL_TWIN_PATH` überschrieben werden.

## Prüfung starten

Die schnelle Prüfung liest nur Metadaten, Manifeste und Git-Zustand:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Invoke-UniversaarlAudit.ps1
```

Die vollstaendige Pruefung kopiert beide Projekte ohne Geheimnisse und erzeugte Daten in ein temporaeres Verzeichnis. `npm ci`, Tests und Erstellungslauf laufen ausschliesslich dort:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Invoke-UniversaarlAudit.ps1 -RunValidations
```

Ergebnisse werden lokal als `reports/latest.md`, `reports/latest.json` und unter `reports/runs/` gespeichert. Diese Laufdaten werden nicht eingecheckt.

## Projektziele pruefen

Technische Gesundheit allein beweist noch keinen Fortschritt zum Projektziel. Die separate Zielpruefung vergleicht deshalb lokalen, veroeffentlichten und noch nicht abgeschlossenen Arbeitsstand, erkennt strategische Abweichungen und bewertet auch das Zusammenspiel beider Projekte:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Invoke-UniversaarlGoalReview.ps1
```

Der Bericht liegt unter `reports/goals-latest.md` und `reports/goals-latest.json`. Die Pruefung ist gegenueber Blueprint und Twin strikt nur lesend. Sie liest keine `.env*`, Authentifizierungszustaende, Geheimnisse, Ablaufspuren, Videos oder Laufzeitnachweise. Rot markiert einen Zielwiderspruch, Gelb eine offene Ziel- oder Reihenfolgeluecke und Gruen einen belegbar ausgerichteten Stand.

Die sichtbaren Kontrolltexte und alle erzeugten Markdown-Berichte muessen deutsch sein. Die Sprachpruefung laesst technische Kennungen, Pfade, Zweignamen und maschinenlesbare JSON-Werte unveraendert:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Test-UniversaarlGermanSurface.ps1
```

## Versionsstand- und Veroeffentlichungsablauf

1. Der jeweilige Projekt-Agent bearbeitet und prüft nur sein Zielprojekt.
2. Er leert `REVIEW.md`, erstellt dort einen lokalen Versionsstand und prueft danach, dass auch `REVIEW.md` in `HEAD` leer ist.
3. Er uebergibt Zweig, vollstaendige Commit-SHA, Pruefergebnis, Nachweis der leeren Pruefdatei und sauberen Git-Zustand.
4. Das Kontrollzentrum fuehrt eine abgeschottete technische Pruefung und die Twin-Blueprint-Vertragspruefung aus.
5. Das Kontrollzentrum blockiert die Veroeffentlichung zusaetzlich bei roter Projektziel- oder Zusammenspielbewertung; gelbe, offen ausgewiesene Folgeziele bleiben sichtbar.
6. Die jeweilige Projektsuite muss alle nutzerseitig sichtbaren Eigeninhalte als deutsch bestaetigen; technische Kennungen, Pfade und unveraenderliche externe Quellwerte bleiben stabil.
7. Nur bei gruenen technischen Pruefstufen, bestandener Deutsch-Pruefung und nicht roter Zielausrichtung veroeffentlicht das Kontrollzentrum exakt diesen vorhandenen Versionsstand ohne erzwungenes Ueberschreiben.

Die reine Veroeffentlichungsbereitschaftspruefung veraendert kein entferntes Repository:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Publish-UniversaarlCommit.ps1 -Project blueprint
```

Die tatsaechliche Uebertragung benoetigt zusaetzlich `-Execute`:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Publish-UniversaarlCommit.ps1 -Project blueprint -Execute
```

Beide Projekte veroeffentlichen nach `https://github.com/sivla/FiBu.git`, aber ausschliesslich auf ihre getrennt freigegebenen Zweige: Blueprint auf `codex/universaarl-blueprint-v2`, Project Twin auf `codex/read-only-project-twin-mvp`. Ein spaeterer responsiver Arbeitszwischenstand des Twin gehoert nicht zur MVP-Uebertragung.

## Bewertung

Der Strukturwert von 0 bis 100 bewertet Erreichbarkeit, Git-Ausgangsstand, sauberen Arbeitsbaum, Manifest, Pruefbefehl, Abhaengigkeits-Sperrdatei, festgelegte Abhaengigkeiten und offene OpenSpec-Arbeit. Die technische Pruefung und kritische Sicherheitsbefunde sind zusaetzliche Pruefstufen.

- **Gruen:** mindestens 85 Punkte, technische Pruefung bestanden, mindestens 90 % Nachweisabdeckung und kein hoher oder kritischer Befund.
- **Gelb:** mindestens 70 Punkte oder ein begrenztes Stabilitäts-/Hygienerisiko.
- **Rot:** unter 70 Punkte, fehlgeschlagene Pruefung, fehlender Git-Ausgangsstand, Vertragsbruch oder kritischer Befund.
- **Grau:** weniger als 70 % Nachweisabdeckung; der Zustand ist nicht ausreichend geprueft.

Ein unsauberer Arbeitsbaum ist nicht automatisch ein Softwarefehler, verhindert aber eine belastbare gruene Aussage ueber den veroeffentlichten Stand.

## Sicherheitsmodell

- Externe Zielpfade stehen auf einer festen Positivliste.
- NTFS-Verzeichnisverknuepfungen werden beim Kopieren nicht verfolgt.
- Vertrauliche und erzeugte Verzeichnisse werden aus der abgeschotteten Pruefumgebung ausgeschlossen.
- Reale `.env*` bleiben ungelesen; nur die versionierte `HEAD:.env.example` wird als Dokumentationsvertrag auf Platzhalter, Groesse, Mandantenkennungen und absolute Hostpfade geprueft.
- Pruefprozesse erben keine Benutzergeheimnisse und erhalten ein getrenntes Benutzer- und Zwischenspeicherverzeichnis.
- Eine Vorher-/Nachher-Inhaltspruefsumme stellt sicher, dass das Kontrollzentrum die relevanten Quelldaten nicht veraendert hat.
- Das Kontrollzentrum berichtet und empfiehlt; es repariert keines der beiden Projekte automatisch.
- Die Veroeffentlichungspruefstufe kann weder Versionsstaende erstellen noch erzwungen uebertragen, Git-Marken, Freigaben oder Zusammenfuehrungsanfragen erzeugen.
