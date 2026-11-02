import AppKit
import Foundation

// Prüft alle Fälle ohne Oberfläche: Rechenlogik, XRechnung schreiben und lesen, Datenhaltung, Storno,
// Import aller Formate, Seitenumbruch, GiroCode und CSV. Schreibt die erzeugten XML-Dateien nach argv[1],
// damit test.sh sie anschließend mit dem offiziellen KoSIT-Validator prüfen kann.
let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "build/selftest", isDirectory: true)
let fixtures = URL(fileURLWithPath: CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "Tests/Fixtures", isDirectory: true)
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
var failures = 0
var checks = 0

func check(_ condition: Bool, _ message: String) {
    checks += 1
    if condition { print("  ✓ \(message)") } else { print("  ✗ \(message)"); failures += 1 }
}

func write(_ text: String, _ name: String) { try! text.write(to: out.appendingPathComponent(name), atomically: false, encoding: .utf8) }

/// Baut ein minimales PDF mit eingebetteter Datei – so wie ZUGFeRD/Factur-X die XML-Daten mitliefert
func hybridPDF(embedding xml: Data, name: String = "factur-x.xml", viaNameTree: Bool = true) -> Data {
    var objects: [Data] = []
    let names = viaNameTree ? "/Names << /EmbeddedFiles << /Names [(\(name)) 4 0 R] >> >> " : ""
    objects.append(Data("<< /Type /Catalog /Pages 2 0 R \(names)/AF [4 0 R] >>".utf8))
    objects.append(Data("<< /Type /Pages /Kids [3 0 R] /Count 1 >>".utf8))
    objects.append(Data("<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] >>".utf8))
    objects.append(Data("<< /Type /Filespec /F (\(name)) /UF (\(name)) /EF << /F 5 0 R >> /AFRelationship /Data >>".utf8))
    var stream = Data("<< /Type /EmbeddedFile /Subtype /text#2Fxml /Length \(xml.count) >>\nstream\n".utf8)
    stream.append(xml)
    stream.append(Data("\nendstream".utf8))
    objects.append(stream)
    var pdf = Data("%PDF-1.7\n".utf8)
    var offsets: [Int] = []
    for (index, body) in objects.enumerated() {
        offsets.append(pdf.count)
        pdf.append(Data("\(index + 1) 0 obj\n".utf8))
        pdf.append(body)
        pdf.append(Data("\nendobj\n".utf8))
    }
    let xref = pdf.count
    var table = "xref\n0 \(objects.count + 1)\n0000000000 65535 f \n"
    for offset in offsets { table += String(format: "%010d 00000 n \n", offset) }
    table += "trailer\n<< /Size \(objects.count + 1) /Root 1 0 R >>\nstartxref\n\(xref)\n%%EOF\n"
    pdf.append(Data(table.utf8))
    return pdf
}

MainActor.assumeIsolated {
    let company = SampleData.company

    print("Rechenlogik")
    var invoice = SampleData.mainInvoice
    invoice.number = "RE-2026-0017"
    invoice.status = .open
    // 32 × 95 = 3040, 1450, 0,5 × 780 = 390, 2 × 38,32 = 76,64
    check(invoice.netTotal == Decimal(string: "4956.64")!, "Netto 4.956,64 €")
    let groups = invoice.taxGroups
    check(groups.count == 2, "Zwei Steuersätze")
    check(groups.first { $0.rate == 19 }?.amount == Decimal(string: "927.2")!, "19 % auf 4.880,00 € = 927,20 €")
    check(groups.first { $0.rate == 7 }?.amount == Decimal(string: "5.36")!, "7 % auf 76,64 € = 5,36 €")
    check(invoice.grossTotal == Decimal(string: "5889.2")!, "Brutto 5.889,20 €")
    var rounding = Invoice()
    rounding.items = [LineItem(quantity: Decimal(string: "0.333")!, unitPrice: Decimal(string: "10.005")!, vatRate: 19)]
    check(rounding.items[0].net == Decimal(string: "3.33")!, "Positionsbetrag wird kaufmännisch gerundet (0,333 × 10,005 = 3,33)")
    var zero = Invoice()
    zero.items = [LineItem(title: "Buch", quantity: 1, unitPrice: 10, vatRate: 0)]
    check(zero.taxGroups.first?.category == "Z" && zero.taxTotal == 0, "0 % ergibt Kategorie Z ohne Steuer")

    print("Pflichtangaben")
    check(InvoiceCheck.blocking(for: invoice, company: company).isEmpty, "Beispielrechnung ist vollständig")
    var empty = Invoice()
    empty.items = [LineItem()]
    check(InvoiceCheck.blocking(for: empty, company: Company()).count >= 10, "Leere Rechnung meldet fehlende Angaben")
    var rcNoVat = invoice
    rcNoVat.taxMode = .reverseCharge
    rcNoVat.customer.vatID = ""
    check(InvoiceCheck.blocking(for: rcNoVat, company: company).contains { $0.rule == "BR-AE-2" }, "Reverse Charge ohne USt-IdNr. des Kunden wird blockiert")
    var zeroInvoice = invoice
    zeroInvoice.items = [LineItem(title: "Beratung", quantity: 1, unitPrice: 0)]
    check(InvoiceCheck.blocking(for: zeroInvoice, company: company).contains { $0.rule == "BT-112" }, "Rechnung über 0 € wird blockiert")
    var badDates = invoice
    badDates.dueDate = Calendar.current.date(byAdding: .day, value: -3, to: badDates.issueDate)!
    check(InvoiceCheck.blocking(for: badDates, company: company).contains { $0.rule == "BT-9" }, "Fälligkeit vor Rechnungsdatum wird erkannt")
    var smallMismatch = company
    smallMismatch.smallBusiness = true
    check(InvoiceCheck.issues(for: invoice, company: smallMismatch).contains { $0.rule == "§ 19 UStG" && $0.severity == .hint },
          "Hinweis, wenn Kleinunternehmer Umsatzsteuer ausweist")
    check(IBAN.isValid("DE89 3704 0044 0532 0130 00"), "Gültige IBAN wird erkannt")
    check(!IBAN.isValid("DE89 3704 0044 0532 0130 01"), "Falsche Prüfziffer wird erkannt")
    check(!IBAN.isValid("DE89"), "Zu kurze IBAN wird erkannt")
    check(IBAN.formatted("de89370400440532013000") == "DE89 3704 0044 0532 0130 00", "IBAN wird in Vierergruppen formatiert")

    print("XRechnung schreiben und wieder lesen")
    func roundTrip(_ invoice: Invoice, seller: Company, file: String) {
        let xml = XRechnungWriter.xml(for: invoice, seller: seller)
        write(xml, file)
        guard let read = try? EInvoiceReader.parseXML(Data(xml.utf8)) else { check(false, "\(file): einlesbar"); return }
        check(read.number == invoice.number && read.grossTotal == invoice.grossTotal && read.taxTotal == invoice.taxTotal
              && read.lines.count == invoice.items.count && read.format.hasPrefix("XRechnung 3.0"),
              "\(file): Nummer, Summen (\(Money.format(read.grossTotal))), \(read.lines.count) Positionen, Format")
    }
    roundTrip(invoice, seller: company, file: "regulaer.xml")

    var small = invoice
    var smallCompany = company
    smallCompany.smallBusiness = true
    smallCompany.vatID = ""
    small.seller = smallCompany
    small.taxMode = .smallBusiness
    small.number = "RE-2026-0018"
    check(small.taxTotal == 0 && small.grossTotal == small.netTotal, "Kleinunternehmer: keine Umsatzsteuer")
    roundTrip(small, seller: smallCompany, file: "kleinunternehmer.xml")

    var reverse = invoice
    reverse.customer = SampleData.customers[3]
    reverse.taxMode = .reverseCharge
    reverse.number = "RE-2026-0019"
    roundTrip(reverse, seller: company, file: "reverse-charge.xml")

    var period = SampleData.supplierInvoice
    roundTrip(period, seller: company, file: "eingang-coworking.xml")
    period.items[0].title = "Sonderzeichen & <Test> \"Anführung\""
    let escaped = XRechnungWriter.xml(for: period, seller: company)
    check((try? EInvoiceReader.parseXML(Data(escaped.utf8)))?.lines.first?.name == period.items[0].title, "Sonderzeichen werden korrekt maskiert")

    print("Datenhaltung")
    let folder = out.appendingPathComponent("datentest-\(UUID().uuidString)", isDirectory: true)
    let store = DataStore(folder: folder)
    store.company = company
    store.company.nextNumber = 1
    let draft = store.newInvoice(for: SampleData.customers[0])
    check(store.invoices.count == 1 && draft.status == .draft && draft.number.isEmpty, "Neue Rechnung ist ein Entwurf ohne Nummer")
    check(Calendar.current.dateComponents([.day], from: draft.issueDate, to: draft.dueDate).day == company.paymentDays, "Fälligkeit nach Zahlungsziel")
    var filled = draft
    filled.items = SampleData.mainInvoice.items
    store.update(filled)
    let year = Calendar.current.component(.year, from: Date())
    let first = store.finalize(store.invoice(id: draft.id)!)
    check(first.number == "RE-\(year)-0001" && first.status == .open && first.seller?.name == company.name, "Festschreiben vergibt RE-\(year)-0001 und friert den Absender ein")
    check(store.company.nextNumber == 2 && store.peekNumber() == "RE-\(year)-0002", "Zähler läuft weiter")
    check(store.customers.contains { $0.id == SampleData.customers[0].id }, "Kunde wird beim Festschreiben gemerkt")
    let copy = store.duplicate(first)
    check(copy.status == .draft && copy.number.isEmpty && copy.items.count == first.items.count && copy.items[0].id != first.items[0].id,
          "Duplizieren erzeugt einen neuen Entwurf mit neuen Positionen")
    store.deleteDraft(first)
    check(store.invoice(id: first.id) != nil, "Festgeschriebene Rechnung lässt sich nicht löschen")
    store.deleteDraft(copy)
    check(store.invoice(id: copy.id) == nil, "Entwurf lässt sich löschen")
    store.setPaid(first, paid: true)
    check(store.invoice(id: first.id)?.status == .paid && store.invoice(id: first.id)?.paidDate != nil, "Als bezahlt markieren")
    store.setPaid(store.invoice(id: first.id)!, paid: false)
    check(store.invoice(id: first.id)?.status == .open && store.invoice(id: first.id)?.paidDate == nil, "Wieder offen")
    check(store.openReceivables == first.grossTotal && store.revenue(year: year) == first.netTotal, "Offene Posten und Umsatz stimmen")
    check(store.previousItems.contains { $0.title == SampleData.mainInvoice.items[0].title }, "Frühere Positionen stehen als Vorlage bereit")

    print("Storno")
    let storno = store.cancel(store.invoice(id: first.id)!)
    let cancelled = store.invoice(id: first.id)!
    check(storno?.number == "RE-\(year)-0002" && storno?.kind == .cancellation && storno?.referenceNumber == first.number,
          "Stornorechnung mit eigener Nummer und Bezug auf \(first.number)")
    check(cancelled.status == .cancelled && cancelled.cancelledBy == storno?.number, "Ursprungsrechnung ist als storniert markiert")
    check(store.revenue(year: year) == 0 && store.openReceivables == 0, "Nach Storno: Umsatz 0, nichts mehr offen")
    check(store.cancel(cancelled) == nil && store.cancel(storno!) == nil, "Doppeltes Storno und Storno eines Stornos sind nicht möglich")
    check(store.finalizedCount == 1, "Stornos zählen nicht zum Freikontingent")
    store.setPaid(storno!, paid: true)
    check(store.invoice(id: storno!.id)?.status == .cancelled, "Storno lässt sich nicht als bezahlt markieren")
    write(XRechnungWriter.xml(for: storno!, seller: company), "storno.xml")
    let stornoRead = try? EInvoiceReader.parseXML(Data(XRechnungWriter.xml(for: storno!, seller: company).utf8))
    check(stornoRead?.typeCode == "381" && stornoRead?.precedingInvoice == first.number, "Storno-XRechnung: Typ 381 mit Bezug (BT-25)")
    let csvOut = CSVExport.outgoing(store.invoices)
    check(csvOut.contains("-\(XRechnungWriter.amount(first.grossTotal).replacingOccurrences(of: ".", with: ","))"), "CSV weist das Storno negativ aus")

    print("Speichern und Laden")
    store.saveNow()
    let reloaded = DataStore(folder: folder)
    @MainActor func persisted(_ s: DataStore) -> Data {
        try! DataStore.encoder.encode(DataStore.Snapshot(company: s.company, customers: s.customers, invoices: s.invoices, incoming: s.incoming, onboarded: s.onboarded))
    }
    check(persisted(reloaded) == persisted(store) && reloaded.invoices.count == 2, "Alles wird verlustfrei gespeichert und geladen (auf die Millisekunde)")
    // Ältere Version: neue Felder fehlen in der Datei
    let dataURL = folder.appendingPathComponent("daten.json")
    var raw = try! JSONSerialization.jsonObject(with: Data(contentsOf: dataURL)) as! [String: Any]
    var oldCompany = raw["company"] as! [String: Any]
    oldCompany.removeValue(forKey: "logo")
    oldCompany.removeValue(forKey: "closingText")
    raw["company"] = oldCompany
    raw["invoices"] = (raw["invoices"] as! [[String: Any]]).map { dict in
        var d = dict
        for key in ["kind", "referenceNumber", "referenceDate", "cancelledBy", "remindersSent"] { d.removeValue(forKey: key) }
        return d
    }
    raw.removeValue(forKey: "incoming")
    try! JSONSerialization.data(withJSONObject: raw).write(to: dataURL)
    let legacy = DataStore(folder: folder)
    check(legacy.invoices.count == store.invoices.count && legacy.company.name == company.name && legacy.incoming.isEmpty,
          "Daten einer älteren Version (fehlende Felder) werden gelesen")
    check(legacy.company.closingText == Company().closingText && legacy.invoices.allSatisfy { $0.kind == .invoice },
          "Fehlende Felder bekommen Standardwerte")
    let legacyDraft = DataStore(folder: nil)
    legacyDraft.invoices = [Invoice()]
    var draftRaw = try! JSONSerialization.jsonObject(with: DataStore.encoder.encode(DataStore.Snapshot(invoices: [Invoice()]))) as! [String: Any]
    draftRaw["invoices"] = (draftRaw["invoices"] as! [[String: Any]]).map { var d = $0; d.removeValue(forKey: "kind"); return d }
    let decodedDraft = DataStore.decodeTolerant(try! JSONSerialization.data(withJSONObject: draftRaw))
    check(decodedDraft?.invoices.count == 1 && decodedDraft?.invoices.first?.seller == nil && decodedDraft?.customers.isEmpty == true,
          "Entwürfe bekommen keinen erfundenen Absender, fehlende Listen bleiben leer")
    try! Data("{ kaputt".utf8).write(to: dataURL)
    let broken = DataStore(folder: folder)
    let leftovers = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
    check(broken.invoices.isEmpty && leftovers.contains { $0.hasPrefix("daten.unlesbar-") } && !leftovers.contains("daten.json"),
          "Unlesbare Datei wird beiseitegelegt, nicht überschrieben")

    print("Datensicherung")
    let backupStore = DataStore(folder: folder.appendingPathComponent("b", isDirectory: true))
    backupStore.company = company
    backupStore.invoices = [SampleData.mainInvoice]
    let backup = try? backupStore.exportBackup(to: folder)
    check(backup.map { FileManager.default.fileExists(atPath: $0.appendingPathComponent("daten.json").path) } == true, "Sicherung enthält die Daten")
    backupStore.invoices = []
    backupStore.saveNow()
    if let backup { try? backupStore.restoreBackup(from: backup) }
    check(backupStore.invoices.count == 1 && backupStore.company.name == company.name, "Wiederherstellen bringt die Daten zurück")
    check((try? backupStore.restoreBackup(from: folder.appendingPathComponent("gibt-es-nicht"))) == nil, "Ungültiger Sicherungsordner wird abgelehnt")

    print("E-Rechnungen empfangen")
    let inbox = DataStore(folder: folder.appendingPathComponent("eingang", isDirectory: true))
    let xmlURL = out.appendingPathComponent("eingang-coworking.xml")
    let imported = try? inbox.importIncoming(from: xmlURL)
    check(imported?.seller.name == "Werkhaus Coworking GmbH" && imported?.grossTotal == Decimal(string: "522.41")!, "XRechnung (CII) wird eingelesen")
    check(imported.flatMap { inbox.storedURL(of: $0) }.map { (try? Data(contentsOf: $0)) == (try? Data(contentsOf: xmlURL)) } == true,
          "Original wird unverändert archiviert")
    _ = try? inbox.importIncoming(from: xmlURL)
    check(inbox.incoming.count == 1, "Doppelter Import legt keine zweite Rechnung an")
    let ubl = try? inbox.importIncoming(from: fixtures.appendingPathComponent("ubl-rechnung.xml"))
    check(ubl?.format == "XRechnung 3.0 (UBL)" && ubl?.seller.name == "Hostwerk Cloud GmbH" && ubl?.dueAmount == Decimal(string: "23.8")!
          && ubl?.iban == "DE02120300000000202051" && ubl?.lines.first?.name == "Server S" && ubl?.lines.first?.unit == "Monat",
          "XRechnung (UBL) wird mit Bankdaten und Positionen eingelesen")
    let ciiData = Data(XRechnungWriter.xml(for: SampleData.supplierInvoice, seller: company).utf8)
    let pdfURL = out.appendingPathComponent("zugferd.pdf")
    try! hybridPDF(embedding: ciiData).write(to: pdfURL)
    let zugferd = try? EInvoiceReader.read(url: pdfURL)
    check(zugferd?.format.contains("PDF") == true && zugferd?.grossTotal == Decimal(string: "522.41")!, "ZUGFeRD/Factur-X-PDF: eingebettete XML wird gefunden")
    try! hybridPDF(embedding: ciiData, name: "zugferd-invoice.xml", viaNameTree: false).write(to: pdfURL)
    check((try? EInvoiceReader.read(url: pdfURL))?.number == "INV-88213", "Eingebettete XML nur über /AF (PDF/A-3) wird gefunden")
    let plainPDF = NSMutableData()
    var box = CGRect(x: 0, y: 0, width: 595, height: 842)
    let ctx = CGContext(consumer: CGDataConsumer(data: plainPDF as CFMutableData)!, mediaBox: &box, nil)!
    ctx.beginPDFPage(nil); ctx.endPDFPage(); ctx.closePDF()
    do { _ = try EInvoiceReader.read(data: plainPDF as Data); check(false, "Normales PDF wird abgelehnt") } catch {
        check(error.localizedDescription.contains("keine E-Rechnung"), "Normales PDF: verständliche Meldung „keine E-Rechnung“")
    }
    do { _ = try EInvoiceReader.read(data: Data("<Bestellung><Nr>1</Nr></Bestellung>".utf8)); check(false, "Fremdes XML wird abgelehnt") } catch {
        check(error.localizedDescription.contains("Unbekanntes Format"), "Fremdes XML: Meldung „Unbekanntes Format“")
    }
    check((try? EInvoiceReader.read(data: Data([0xFF, 0x00, 0x12]))) == nil, "Unsinnige Daten werden abgelehnt")
    var paidIn = inbox.incoming[0]
    paidIn.isPaid = true
    inbox.updateIncoming(paidIn)
    check(inbox.unpaidIncoming.count == inbox.incoming.count - 1, "Bezahlte Eingangsrechnung zählt nicht mehr als offen")
    let toDelete = inbox.incoming[0]
    let storedFile = inbox.storedURL(of: toDelete)
    inbox.deleteIncoming(toDelete)
    check(!inbox.incoming.contains { $0.id == toDelete.id } && (storedFile.map { !FileManager.default.fileExists(atPath: $0.path) } ?? true),
          "Löschen entfernt Eintrag und archivierte Datei")

    print("Beispiel-E-Rechnung")
    let demo = try? EInvoiceReader.parseXML(Data(DemoContent.sampleXML().utf8))
    check(demo?.grossTotal == Decimal(string: "439.11")!, "Beispiel liest sich ein (Brutto 439,11 €)")
    write(DemoContent.sampleXML(), "beispiel.xml")
    let sampleStore = DataStore(folder: nil)
    _ = sampleStore.importSample()
    _ = sampleStore.importSample()
    check(sampleStore.incoming.count == 1, "Beispiel wird nur einmal angelegt")

    print("Seitenumbruch")
    check(InvoiceLayout.pages(for: []).count == 1, "Rechnung ohne Positionen hat eine Seite")
    check(InvoiceLayout.pages(for: [LineItem()]).count == 1, "Eine Position: eine Seite")
    for count in [5, 12, 13, 14, 30, 61, 120] {
        let items = (0..<count).map { LineItem(title: "Position \($0)", detail: $0 % 2 == 0 ? String(repeating: "Beschreibung ", count: 8) : "") }
        let pages = InvoiceLayout.pages(for: items)
        let flattened = pages.flatMap { Array($0) }.map(\.id)
        check(flattened == items.map(\.id) && pages.allSatisfy { !$0.isEmpty }, "\(count) Positionen: \(pages.count) Seiten, jede Position genau einmal, keine leere Seite")
    }

    print("Zahleneingabe")
    let cases: [(String, String?)] = [("12,5", "12.5"), ("1.450", "1450"), ("1.450,75", "1450.75"), ("12.5", "12.5"), ("95,50 €", "95.5"),
                                      ("", "0"), ("1.000.000", "1000000"), ("abc", nil), ("0,333", "0.333")]
    for (input, expected) in cases {
        check(DecimalField.parse(input) == expected.flatMap { Decimal(string: $0) }, "„\(input)“ → \(expected ?? "ignoriert")")
    }
    check(DecimalField.parse(DecimalField.format(Decimal(string: "1450.5")!)) == Decimal(string: "1450.5")!, "Anzeige und Eingabe passen zusammen (1.450,5)")
    check(DecimalField.format(Decimal(string: "95.5")!, minimumFractionDigits: 2) == "95,50", "Preise mit zwei Nachkommastellen (95,50)")

    print("GiroCode")
    let payload = GiroCode.payload(name: "Lena Hoffmann", iban: "DE89 3704 0044 0532 0130 00", bic: "COBADEFFXXX", amount: Decimal(string: "5889.2")!, reference: "RE-2026-0015")
    check(payload?.components(separatedBy: "\n") == ["BCD", "002", "1", "SCT", "COBADEFFXXX", "Lena Hoffmann", "DE89370400440532013000", "EUR5889.20", "", "", "RE-2026-0015"],
          "EPC-Datensatz nach Standard (Betrag EUR5889.20)")
    check(GiroCode.payload(name: "X", iban: "DE00 1234", bic: "", amount: 10, reference: "") == nil, "Ungültige IBAN: kein GiroCode")
    check(GiroCode.payload(name: "X", iban: "DE89370400440532013000", bic: "", amount: 0, reference: "") == nil, "Betrag 0: kein GiroCode")

    print("CSV")
    var tricky = SampleData.mainInvoice
    tricky.number = "RE-1"
    tricky.status = .open
    tricky.customer.name = "Müller; Söhne \"GmbH\""
    let csv = CSVExport.outgoing([tricky])
    check(csv.hasPrefix("\u{FEFF}Rechnungsnr.;Art;Datum"), "Kopfzeile mit BOM und Semikolon")
    check(csv.contains("\"Müller; Söhne \"\"GmbH\"\"\""), "Semikolon und Anführungszeichen werden maskiert")
    check(csv.contains("4956,64"), "Beträge mit Dezimalkomma")
    check(!CSVExport.outgoing([Invoice()]).contains("Entwurf"), "Entwürfe erscheinen nicht im Export")

    try? FileManager.default.removeItem(at: folder)
}

if failures > 0 {
    print("\n\(failures) von \(checks) Prüfungen fehlgeschlagen")
    exit(1)
}
print("\nAlle \(checks) Prüfungen bestanden")
