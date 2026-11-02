# Rechnungsklar in den Mac App Store bringen

## A. Was du einmalig brauchst

1. **Apple Developer Program**: 99 €/Jahr, [developer.apple.com/programs](https://developer.apple.com/programs/).
   Danach sofort das **App Store Small Business Program** beantragen (15 % statt 30 % Provision).
2. **Xcode** aus dem Mac App Store (kostenlos). Auf diesem Mac sind derzeit nur die Command Line Tools installiert.
3. **Bundle-ID** festlegen: Voreingestellt ist `de.rechnungsklar.app`. Wenn du sie änderst, dann in
   `Resources/Info.plist`, `project.yml` und für die In-App-Käufe in `Sources/Purchases.swift`.
4. **Website mit Impressum und Datenschutzerklärung**: In Deutschland Pflicht, und Apple verlangt eine
   Datenschutz-URL. Die App verlinkt `https://rechnungsklar.de/datenschutz` und `/hilfe`. Die Domain ist noch zu sichern.
5. **EU-Händlerstatus (Digital Services Act)**: Wer im EU-App-Store verkauft, muss sich in App Store Connect als
   „Trader“ einstufen. Adresse, Telefon und E-Mail werden dann **öffentlich** im Store angezeigt.
   Für Einzelunternehmer lohnt sich eine Geschäftsadresse (z. B. Coworking).
6. **Steuer und Bank** in App Store Connect hinterlegen (Agreements, Tax, and Banking), sonst sind keine
   In-App-Käufe möglich.

## B. In App Store Connect anlegen

**App:** Plattform macOS, Name **Rechnungsklar: E-Rechnung**, Primärsprache Deutsch, Bundle-ID wie oben,
SKU `rechnungsklar-mac`.

**In-App-Käufe** (IDs müssen exakt so heißen):

| Produkt-ID | Typ | Preis (DE) | Referenzname |
|---|---|---|---|
| `de.rechnungsklar.pro.monthly` | Automatisch verlängerbares Abo, Gruppe „Rechnungsklar Pro“ | 5,99 € | Pro monatlich |
| `de.rechnungsklar.pro.yearly` | Automatisch verlängerbares Abo, gleiche Gruppe | 49,99 € | Pro jährlich |
| `de.rechnungsklar.pro.lifetime` | Nicht verbrauchbar | 129,99 € | Pro Einmalkauf |

Für jedes Produkt einen Screenshot der Paywall hochladen (`docs/screenshots/7-pro.png`).

## C. Store-Eintrag (zum Kopieren)

**Name (max. 30):** Rechnungsklar: E-Rechnung
**Untertitel (max. 30):** XRechnung & ZUGFeRD für Mac
**Kategorie:** Wirtschaft (sekundär: Finanzen)
**Altersfreigabe:** 4+
**Keywords (max. 100 Zeichen):**
`XRechnung,ZUGFeRD,Rechnung,Rechnungsprogramm,Freelancer,Kleinunternehmer,Mahnung,GiroCode,Factur-X`

**Werbetext (max. 170):**
Ab 2028 müssen alle Unternehmen E-Rechnungen schreiben – empfangen müssen sie sie schon heute. Rechnungsklar macht beides einfach, direkt auf deinem Mac.

**Beschreibung:**

> E-Rechnungen schreiben und lesen – so einfach wie eine Mail.
>
> Seit 2025 müssen alle Unternehmen in Deutschland E-Rechnungen empfangen können, ab 2027/2028 auch selbst
> ausstellen. Eine XRechnung ist aber nur XML-Code, und Pages oder Word können keine E-Rechnung erzeugen.
> Rechnungsklar löst beides.
>
> E-RECHNUNGEN LESEN – KOSTENLOS
> • XRechnung (CII und UBL), ZUGFeRD, Factur-X und Peppol öffnen
> • Lesbare Ansicht mit Positionen, Steuern und Bankverbindung
> • Summen werden automatisch nachgerechnet
> • GiroCode: mit der Banking-App scannen und bezahlen
> • Original wird unverändert archiviert
>
> RECHNUNGEN SCHREIBEN
> • In einer Minute zur fertigen Rechnung – als PDF und als XRechnung 3.0
> • Prüft alle Pflichtangaben, bevor die Rechnung rausgeht
> • Kleinunternehmer (§ 19 UStG), Reverse Charge, 19 % und 7 %
> • Fortlaufende Rechnungsnummern, nach dem Festschreiben unveränderbar
> • GiroCode auf jeder Rechnung – deine Kunden zahlen schneller
> • Per Mail versenden mit PDF und XRechnung im Anhang
>
> ÜBERBLICK UND MAHNWESEN
> • Offene und überfällige Rechnungen auf einen Blick
> • Zahlungserinnerungen in drei Stufen, vorformuliert
> • CSV-Export für Steuerberatung und Buchhaltung
>
> DEINE DATEN BLEIBEN BEI DIR
> Kein Konto, keine Cloud, kein Tracking. Alles liegt nur auf deinem Mac.
>
> Kostenlos: E-Rechnungen lesen ohne Grenze und 3 eigene Rechnungen. Rechnungsklar Pro: unbegrenzt
> Rechnungen, Mahnwesen und CSV-Export – monatlich, jährlich oder als Einmalkauf.
>
> Rechnungsklar ersetzt keine Steuerberatung.

**Screenshots** (2880 × 1800, fertig): `docs/appstore/1-rechnung.png` bis `5-dunkel.png`

**App-Datenschutz („Privacy Nutrition Label“):** „Keine Daten erfasst“. Das stimmt: Die App hat keine Analyse,
kein Konto und keinen Server. Das passende `PrivacyInfo.xcprivacy` liegt bei.

**Hinweise für die App-Prüfung (Review Notes):**
> No account or login is required. All data stays on the device. To try the free e-invoice viewer without your
> own file, open "E-Rechnungs-Eingang" and click "Keine E-Rechnung zur Hand? Beispiel ansehen". The first 3
> invoices are free; afterwards the paywall (StoreKit 2) appears. Sample XRechnung files are attached.

## D. Bauen und hochladen

**Weg 1: Xcode (empfohlen)**
```bash
brew install xcodegen
```
```bash
cd Rechnungsklar && xcodegen
```
Dann `Rechnungsklar.xcodeproj` öffnen, unter *Signing & Capabilities* dein Team wählen und die In-App-Käufe
lokal testen (das Schema nutzt `Resources/Rechnungsklar.storekit`). Danach *Product → Archive →
Distribute App → App Store Connect*.

**Weg 2: ohne Xcode-Oberfläche** (Zertifikate und Provisioning Profile vorausgesetzt)
```bash
TEAM="Vorname Nachname (TEAMID1234)" ./release.sh
```
Danach `build/Rechnungsklar.pkg` mit der App **Transporter** hochladen.

## E. Vor jedem Release

```bash
KOSIT_DIR=~/kosit ./test.sh
```
Damit werden alle erzeugten XRechnungen mit dem **offiziellen KoSIT-Validator** geprüft
([Validator](https://github.com/itplr-kosit/validator/releases), [XRechnung-Konfiguration](https://github.com/itplr-kosit/validator-configuration-xrechnung/releases),
dazu Java 17+). Erst wenn hier alles „acceptable“ ist, darf eine Version raus.
