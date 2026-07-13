# Proposal: Portablen Kontrollzentrum-Kandidaten vorbereiten

Das Kontrollzentrum soll auf einem frischen Windows- oder macOS-System seine Voraussetzungen reproduzierbar pruefen und lokal bootstrap-faehig sein. Dieser Change aendert weder Zielprojekte noch den fachlichen Vertrag und behauptet ohne echten macOS-Runner keine Releasebereitschaft.

Zusaetzlich soll ein externer Portfolio-Portabilitaetsnachweis fail-closed verhindern, dass ein beliebiger Branch- oder Arbeitsbaumstand als installierbar gilt. Der gebundene Kontrollcommit enthaelt nur Validator und Vorlage; ein spaeteres externes Release-Asset bindet diesen Commit ohne Selbstreferenz. Nur vollstaendig remote aufloesbare Komponenten, getrennte Manifestdatei-/Aggregatdigests und recordgebundene echte Windows- und macOS-Evidence duerfen `PORTABLE_RELEASE_READY` ergeben.
