# Design

- Ein gemeinsamer Doctor prueft Git, Node.js, .NET SDK, PowerShell und Pflichtdateien ohne Zielprojektzugriff.
- Bootstrap erstellt nur ignorierte Kontrollzentrum-Artefakte und baut den Prozesshelfer.
- Windows behaelt Jobobjekte und handlegebundene Dateipruefungen.
- Unix verwendet direkten Prozessstart ohne Shell, bereinigte Umgebung, begrenzte Ausgabe, Zeitlimit und Prozessbaum-Terminierung. Pfadoperationen weisen Symlink-Komponenten vor und nach dem Zugriff ab.
- Das Kandidatenmanifest bleibt ohne Version und Quellcommit pending, bis ein echter macOS-Runner alle Gates bestanden hat.
- Ein separater versionierter Produktionsreifevertrag nennt je Komponente genau einen commitgebundenen Evidence-Pfad und trennt `platformReady`, `onboardingReady` und `customerGoLiveReady`.
- Das Kontrollzentrum liest diese kleinen Textblobs ausschliesslich aus sauberen HEAD-Commits. Fehlende oder ungueltige Evidence blockiert; Zielrepositories werden nicht beschrieben.
- Nur BC Basic darf `customerGoLiveReady=passed` liefern, und nur mit realer Evidence fuer Tenant, Lizenzen, Berechtigungen, UAT, Cutover, ersten Abschluss, UStVA und Supportuebergabe.
- Lizenz- und Distributionsreife bleibt ein eigenes Gate und darf die interne technische Nutzbarkeit nicht vortaeuschen oder umgekehrt.
