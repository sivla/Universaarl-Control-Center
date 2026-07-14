# Proposal: Portablen Kontrollzentrum-Kandidaten vorbereiten

Das Kontrollzentrum soll auf einem frischen Windows- oder macOS-System seine Voraussetzungen reproduzierbar pruefen und lokal bootstrap-faehig sein. Dieser Change aendert weder Zielprojekte noch den fachlichen Vertrag und behauptet ohne echten macOS-Runner keine Releasebereitschaft.

Zusaetzlich soll ein externer Portfolio-Portabilitaetsnachweis fail-closed verhindern, dass ein beliebiger Branch- oder Arbeitsbaumstand als installierbar gilt. Der gebundene Kontrollcommit enthaelt nur Validator und Vorlage; ein spaeteres externes Release-Asset bindet diesen Commit ohne Selbstreferenz. Nur vollstaendig remote aufloesbare Komponenten, getrennte Manifestdatei-/Aggregatdigests und recordgebundene echte Windows- und macOS-Evidence duerfen `PORTABLE_RELEASE_READY` ergeben.

Der Change schliesst ausserdem die Betriebsreife fuer reale Kundenarbeit: Plattformreife, wiederholbares Kunden-Onboarding und der kundenspezifische Go-live werden als drei getrennte, commitgebundene Gates bewertet. Ein Portfolio darf fuer neue Kundenarbeit bereit sein, waehrend der konkrete Kunden-Go-live bis zu realem Tenant, Lizenzen, Berechtigungen, UAT, Cutover, erstem Abschluss, UStVA und Supportuebergabe ehrlich pending bleibt. Synthetische Evidence darf dieses Gate nie schliessen.
