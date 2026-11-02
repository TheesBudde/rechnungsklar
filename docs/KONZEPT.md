# Rechnungsklar – Geschäftskonzept

*Stand: 1. November 2026*

## 1. Das Problem

**Die E-Rechnung wird in Deutschland Pflicht, und zwar für jedes Unternehmen.**

| Seit / ab | Wer | Was |
|---|---|---|
| 1.1.2025 | alle inländischen Unternehmen, **auch Kleinunternehmer** | E-Rechnungen **empfangen** und verarbeiten können |
| 1.1.2027 | Unternehmen mit > 800.000 € Vorjahresumsatz | E-Rechnungen **ausstellen** (B2B) |
| 1.1.2028 | **alle** übrigen Unternehmen (Kleinunternehmer nach § 19 UStG ausgenommen) | E-Rechnungen **ausstellen** (B2B) |

Eine E-Rechnung ist eine XML-Datei im Format XRechnung oder ZUGFeRD. Ein normales PDF zählt nicht mehr.
Daraus entstehen zwei handfeste Probleme:

1. **Empfangen:** Eine XRechnung öffnet sich am Mac als unlesbarer XML-Code. Ein Doppelklick zeigt nur Tags.
2. **Ausstellen:** Pages, Numbers und Word können keine E-Rechnung erzeugen. Freelancer, die bisher Rechnungen
   in Pages schreiben (sehr typisch für Designer, Entwickler, Berater, Fotografen am Mac), müssen bis spätestens
   2028 umsteigen.

Das ist eine seltene Lage: Der Gesetzgeber erzeugt Nachfrage mit festem Stichtag, und die Ausgabe ist für
die Kundschaft eine Betriebsausgabe, also steuerlich absetzbar.

## 2. Wettbewerb (recherchiert)

| Angebot | Art | Preis | Lücke |
|---|---|---|---|
| E-Rechnung Viewer (Welzel), Rechnungslupe, Web-Viewer | nur Anzeige | kostenlos | erzeugen keine Rechnungen |
| Rechnungsblick | native Mac-App, großer Funktionsumfang | 69,99 € einmalig | kein Mahnwesen erwähnt, eher „Büro-Suite“ |
| RechneX, kostenlose-erechnung.de u. a. | Web | Freemium | Browser, Daten auf fremden Servern |
| lexoffice, sevDesk, Accountable | Web/Cloud-Buchhaltung | Abo | Buchhaltungs-Komplettpaket, für viele zu viel |

**Positionierung von Rechnungsklar:** *Die einfachste native Mac-App, mit der Selbstständige E-Rechnungen
schreiben **und** lesen.* Lokal, ohne Konto, ohne Cloud. Keine Buchhaltungssoftware, sondern das Werkzeug
für genau diesen Pflichtwechsel.

Unterscheidungsmerkmale:
- **Beide Richtungen in einer App**: Der kostenlose Eingang holt Nutzer ab (Empfangspflicht gilt für alle),
  der bezahlte Ausgang verdient das Geld (Ausstellungspflicht ab 2027/2028).
- **GiroCode** (EPC-QR) auf jeder Rechnung *und* bei empfangenen E-Rechnungen: Mit der Banking-App
  scannen, fertig. Den Nutzen spürt man sofort.
- **Pflichtangaben-Prüfung in Alltagssprache**: Statt „BR-DE-6 violated“ heißt es „Telefonnummer fehlt“.
- **Zahlungserinnerungen in drei Stufen**: Laut Recherche fehlt das beim nativen Wettbewerber.
- **Datenschutz als Verkaufsargument**: Rechnungsdaten verlassen den Mac nicht.

## 3. Produkt (Version 1.0, fertig gebaut)

- Rechnungen schreiben: Kunden, Positionen, 19/7/0 %, Kleinunternehmer (§ 19), Reverse Charge (EU)
- Fortlaufende Nummern, Festschreiben (GoBD: nach Vergabe der Nummer unveränderbar)
- Export als **PDF** (DIN-5008-nahes Layout mit GiroCode) und **XRechnung 3.0 (CII)**
- Versand per Mail mit beiden Anhängen und vorformuliertem Text
- Live-Prüfung aller Pflichtangaben vor dem Festschreiben
- E-Rechnungs-Eingang: XRechnung (CII und UBL), ZUGFeRD 2.x, Factur-X, Peppol BIS 3.0
  - lesbare Ansicht, Summenprüfung, GiroCode zum Bezahlen, Original wird unverändert archiviert
  - Sichtansicht als PDF sichern
- Übersicht: offene Posten, Überfälliges, Umsatz je Monat, Countdown zur Pflicht
- Zahlungserinnerung: freundlich, bestimmt, letzte Mahnung (mit § 288 BGB)
- CSV-Export für die Steuerberatung (Ausgang und Eingang)
- Drag & Drop, „Öffnen mit …“ aus dem Finder, Dunkelmodus, Tastenkürzel

## 4. Geld verdienen

**Modell: Freemium mit Abo und Einmalkauf** (StoreKit 2, im Code fertig)

| Stufe | Preis | Inhalt |
|---|---|---|
| Kostenlos | 0 € | E-Rechnungen empfangen und lesen, **unbegrenzt**, plus 3 eigene Rechnungen zum Ausprobieren |
| Pro monatlich | 5,99 € | unbegrenzt Rechnungen, Mahnwesen, CSV-Export |
| Pro jährlich | 49,99 € | wie monatlich, 2 Monate gespart (Standardauswahl in der Paywall) |
| Pro Einmalkauf | 129,99 € | für alle, die Abos ablehnen (bei Mac-Nutzern verbreitet) |

**Warum diese Preise:** Die Web-Konkurrenz (Buchhaltungs-Abos) kostet meist deutlich mehr pro Monat. Der
native Einmalkauf-Wettbewerber liegt bei 69,99 €. Das Jahresabo liegt bewusst darunter und finanziert
laufende Updates, denn XRechnung bekommt regelmäßig neue Versionen. Diese Pflege ist das ehrliche
Argument für ein Abo.

### Rechnung: Was braucht es für 5.000 € im Monat?

Apple Small Business Program: 15 % Provision. App-Store-Preise enthalten 19 % USt.

| Produkt | Endpreis | netto ohne USt | nach 15 % Apple | pro Monat |
|---|---|---|---|---|
| Jährlich | 49,99 € | 42,01 € | 35,71 €/Jahr | **2,98 €** |
| Monatlich | 5,99 € | 5,03 € | 4,28 €/Monat | **4,28 €** |
| Einmalkauf | 129,99 € | 109,24 € | **92,85 €** einmalig | – |

Beispielmix für **≈ 5.080 € Auszahlung pro Monat** (vor Einkommensteuer):
- 1.100 aktive Jahresabos → 3.273 €
- 250 aktive Monatsabos → 1.070 €
- 8 Einmalkäufe im Monat → 743 €

Gebraucht werden also **rund 1.350 zahlende Abonnenten plus etwa 8 Einmalkäufe im Monat**. Zum Vergleich:
In Deutschland gibt es Millionen Selbstständige und kleine Unternehmen, die bis 2028 umstellen müssen.
Selbst ein kleiner Bruchteil der Mac-Nutzer darunter reicht.

**Ehrliche Einordnung:** Laut den recherchierten Branchenzahlen verdient eine typische erfolgreiche
Mac-Utility 1.000 bis 8.000 $ im Monat, die meisten Apps deutlich weniger. 5.000 €/Monat ist erreichbar,
aber nicht garantiert. Realistisch braucht es 12 bis 18 Monate und aktives Marketing (siehe 6.). Der
Stichtag 1.1.2028 ist das Zeitfenster: Bis dahin muss die App bekannt sein.

## 5. Risiken und Gegenmaßnahmen

| Risiko | Gegenmaßnahme |
|---|---|
| Wettbewerber Rechnungsblick ist günstiger (Einmalkauf) | Einmalkauf-Option anbieten, Fokus auf Einfachheit, Eingang kostenlos, GiroCode, Mahnwesen |
| Stichtage werden politisch verschoben | Empfangspflicht gilt schon heute, der kostenlose Teil wirkt unabhängig davon |
| Haftung bei fehlerhaften Rechnungen | Version 1.0 besteht die offizielle KoSIT-Validierung ohne Fehler und Warnungen; vor jedem Release erneut prüfen (test.sh), Hinweis „keine Steuerberatung“ in AGB |
| Sichtbarkeit im App Store | Kostenloser Viewer als Suchmaschinen-Magnet („XRechnung öffnen Mac“), Inhalte und Ratgeber |
| Abo-Müdigkeit bei Mac-Nutzern | Einmalkauf zusätzlich, Abo durch echte Pflege begründen |
| Format-Änderungen (XRechnung 3.x, 4.0) | Formatlogik ist in zwei Dateien gekapselt (`XRechnungWriter.swift`, `EInvoiceReader.swift`) |

## 6. Markteinführung

1. **Website** rechnungsklar.de (Domain noch prüfen und sichern) mit Impressum, Datenschutz und Ratgeber-Artikeln:
   „XRechnung öffnen auf dem Mac“, „E-Rechnung als Freelancer“, „ZUGFeRD vs. XRechnung“.
   Genau nach diesen Begriffen wird gesucht (siehe Recherche).
2. **Kostenlosen Viewer** offensiv bewerben: Er löst ein Problem, das *alle* Unternehmen schon heute haben.
3. **Communities:** Freelancer-Verbände (VGSD führt Linksammlungen zu E-Rechnungs-Tools), r/de_EDV,
   Gründer-Foren, Mac-Blogs (ifun.de hat bereits über E-Rechnungs-Mac-Apps berichtet).
4. **Steuerberater-Kanal:** Kanzleien suchen einfache Empfehlungen für Mandanten mit Mac.
5. **Q4 2027:** Kampagne „Noch X Tage bis zur E-Rechnungs-Pflicht“. Der Countdown ist schon in der App.

## 7. Roadmap

| Version | Inhalt |
|---|---|
| 1.1 | **ZUGFeRD/Factur-X erzeugen** (PDF/A-3 mit eingebetteter XML), Stornorechnung und Gutschrift |
| 1.2 | Angebote → Rechnung, wiederkehrende Rechnungen (Retainer), Skonto |
| 1.3 | Quick-Look-Erweiterung: XRechnung im Finder mit der Leertaste lesen |
| 2.0 | iPhone/iPad-App mit iCloud-Sync (der SwiftUI-Code ist dafür vorbereitet), DATEV-Export |
| später | Zeiterfassung → Rechnung, Versand über Peppol, Englisch für AT/CH/EU |

## 8. Quellen der Recherche

- E-Rechnungs-Pflicht und Fristen: [kostenlose-erechnung.de](https://kostenlose-erechnung.de/ratgeber/e-rechnung-kleinunternehmer/),
  [qonto.com](https://qonto.com/de/blog/selbststaendige/management-buchhaltung/e-rechnung-pflicht-freiberufler),
  [advisori.de](https://www.advisori.de/blog/e-rechnungspflicht), [taxfix.de](https://taxfix.de/ratgeber/selbststaendige/e-rechnung-pflicht/)
- Problem „XML nicht lesbar“: [ifun.de](https://www.ifun.de/xrechnung-mac-app-wandelt-xml-rechnungen-in-lesbare-pdfs-218152/),
  [e-rechnungen.org](https://www.e-rechnungen.org/blog/xrechnung-oeffnen-lesen), [belegkasten.de](https://belegkasten.de/ratgeber/e-rechnung-xml-oeffnen)
- Mac-Optionen und Wettbewerb: [rechnex.de](https://rechnex.de/blog/xrechnung-auf-mac-erstellen-optionen-vergleich),
  [rechnungsblick.de](https://rechnungsblick.de/), [App Store: E-Rechnung Viewer](https://apps.apple.com/de/app/e-rechnung-viewer/id6742571585),
  [VGSD-Linksammlung](https://www.vgsd.de/linksammlung-kostenlose-e-rechnungs-tools/)
- Umsätze von Mac-Apps: [macapps.report](https://macapps.report/market), [stealwhatworks.com](https://stealwhatworks.com/blogs/news/mac-apps-making-real-money-now),
  [youcouldshipthis.com](https://youcouldshipthis.com/blog/indie-app-revenue-realistic-expectations), [getgrumpi.com](https://getgrumpi.com/blog/how-much-do-indie-apps-make)

*Rechtliche Angaben (Fristen, Schwellenwerte) stammen aus Ratgeberseiten und sind vor dem Marketing-Einsatz mit
dem BMF-Schreiben bzw. einer Steuerberatung abzugleichen.*
