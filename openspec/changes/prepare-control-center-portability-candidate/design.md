# Design

- Ein gemeinsamer Doctor prueft Git, Node.js, .NET SDK, PowerShell und Pflichtdateien ohne Zielprojektzugriff.
- Bootstrap erstellt nur ignorierte Kontrollzentrum-Artefakte und baut den Prozesshelfer.
- Windows behaelt Jobobjekte und handlegebundene Dateipruefungen.
- Unix verwendet direkten Prozessstart ohne Shell, bereinigte Umgebung, begrenzte Ausgabe, Zeitlimit und Prozessbaum-Terminierung. Pfadoperationen weisen Symlink-Komponenten vor und nach dem Zugriff ab.
- Das Kandidatenmanifest bleibt ohne Version und Quellcommit pending, bis ein echter macOS-Runner alle Gates bestanden hat.
