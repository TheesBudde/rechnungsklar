# Rechnungsklar 1.0.0

Erste Version: E-Rechnungen schreiben und lesen, direkt auf dem Mac.

## Neu

**Rechnungen schreiben**
- Rechnungen mit Kunden, Positionen, 19 %, 7 %, 0 %, Kleinunternehmer (§ 19 UStG) und Reverse Charge
- Export als PDF (mit GiroCode) und als **XRechnung 3.0 (CII)**, geprüft mit dem offiziellen KoSIT-Validator
- Prüfung aller Pflichtangaben vor dem Festschreiben, in verständlicher Sprache
- Fortlaufende Rechnungsnummern; festgeschriebene Rechnungen sind unveränderbar (GoBD)
- Stornorechnung (XRechnung-Typ 381 mit Bezug auf die Ursprungsrechnung)
- Logo im Briefkopf, Vorlagen aus früheren Positionen, Drucken, Versand per Mail mit PDF und XRechnung

**E-Rechnungen empfangen**
- XRechnung (CII und UBL), ZUGFeRD 2.x, Factur-X und Peppol BIS 3.0 öffnen – auch per Drag & Drop
- Lesbare Ansicht, Summen werden nachgerechnet, GiroCode zum Bezahlen
- Original wird unverändert archiviert; lesbare Fassung als PDF

**Überblick**
- Offene und überfällige Rechnungen, Umsatz je Monat, offene Eingangsrechnungen
- Zahlungserinnerungen in drei Stufen
- CSV-Export für die Steuerberatung
- Datensicherung und Wiederherstellung; alle Daten bleiben auf dem Mac

## Installation

1. `Rechnungsklar-1.0.0-macOS.zip` herunterladen und entpacken.
2. `Rechnungsklar.app` in den Ordner „Programme“ ziehen.
3. Beim ersten Start **Rechtsklick → Öffnen** wählen: Diese Vorschau-Version ist nicht mit einem Apple-Entwicklerzertifikat
   signiert und nicht notarisiert, deshalb fragt macOS einmal nach.

Voraussetzung: macOS 14 (Sonoma) oder neuer, Apple Silicon oder Intel.

## Hinweise zu dieser Vorschau-Version

- Die In-App-Käufe sind erst über den Mac App Store verfügbar. In dieser Version sind E-Rechnungen lesen ohne Grenze und
  **3 eigene Rechnungen** möglich; danach erscheint die Pro-Seite, ein Kauf ist hier noch nicht möglich.
- ZUGFeRD/Factur-X-PDFs können gelesen, aber noch nicht erzeugt werden (geplant für 1.1).
- Rechnungsklar ersetzt keine Steuerberatung.

## Prüfsumme

SHA-256 von `Rechnungsklar-1.0.0-macOS.zip`:
`7fd62e0f6a0ba7700e081750f83d1da60eb0e1acbe527760b8dfbe6bb7d44c45`
