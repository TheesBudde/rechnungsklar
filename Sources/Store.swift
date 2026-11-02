import Foundation
import SwiftUI

/// Alle Daten der App. Liegt als JSON im App-Container – kein Konto, kein Server.
@MainActor
final class DataStore: ObservableObject {
    struct Snapshot: Codable {
        var company = Company()
        var customers: [Customer] = []
        var invoices: [Invoice] = []
        var incoming: [IncomingInvoice] = []
        var onboarded = false
    }

    @Published var company = Company() { didSet { scheduleSave() } }
    @Published var customers: [Customer] = [] { didSet { scheduleSave() } }
    @Published var invoices: [Invoice] = [] { didSet { scheduleSave() } }
    @Published var incoming: [IncomingInvoice] = [] { didSet { scheduleSave() } }
    @Published var onboarded = false { didSet { scheduleSave() } }

    let folder: URL?
    private var saveTask: Task<Void, Never>?
    private var loading = false

    /// `folder: nil` hält alles nur im Speicher (für Vorschauen und Tests)
    init(folder: URL? = DataStore.defaultFolder) {
        self.folder = folder
        load()
    }

    nonisolated static var defaultFolder: URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        return base.appendingPathComponent("Rechnungsklar", isDirectory: true)
    }

    var dataURL: URL? { folder?.appendingPathComponent("daten.json") }
    var archiveFolder: URL? { folder?.appendingPathComponent("Eingang", isDirectory: true) }

    /// Lädt die Daten neu von der Festplatte (z. B. nach dem Wiederherstellen einer Sicherung)
    func reload() {
        company = Company()
        customers = []
        invoices = []
        incoming = []
        onboarded = false
        load()
    }

    private func load() {
        guard let dataURL, let data = try? Data(contentsOf: dataURL) else { return }
        guard let snapshot = Self.decodeTolerant(data) else {
            // Nie überschreiben, was sich nicht lesen lässt: erst beiseitelegen, dann leer starten
            let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
            try? FileManager.default.moveItem(at: dataURL, to: dataURL.deletingLastPathComponent().appendingPathComponent("daten.unlesbar-\(stamp).json"))
            NSLog("Rechnungsklar: daten.json war nicht lesbar und wurde beiseitegelegt")
            return
        }
        loading = true
        company = snapshot.company
        customers = snapshot.customers
        invoices = snapshot.invoices
        incoming = snapshot.incoming
        onboarded = snapshot.onboarded
        loading = false
    }

    private func scheduleSave() {
        guard !loading, folder != nil else { return }
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    func saveNow() {
        guard let folder, let dataURL else { return }
        let snapshot = Snapshot(company: company, customers: customers, invoices: invoices, incoming: incoming, onboarded: onboarded)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let data = try Self.encoder.encode(snapshot)
            // Vorher eine Sicherung behalten – falls beim Schreiben etwas schiefgeht
            if FileManager.default.fileExists(atPath: dataURL.path) {
                let backup = folder.appendingPathComponent("daten.backup.json")
                try? FileManager.default.removeItem(at: backup)
                try? FileManager.default.copyItem(at: dataURL, to: backup)
            }
            do {
                try data.write(to: dataURL, options: .atomic)
            } catch {
                try data.write(to: dataURL)
            }
        } catch {
            NSLog("Rechnungsklar: Speichern fehlgeschlagen: \(error)")
        }
    }

    /// Liest auch Daten älterer Versionen: Fehlende Felder werden mit den Standardwerten der heutigen Modelle ergänzt.
    /// So gehen beim Update keine Daten verloren, wenn neue Felder hinzukommen.
    nonisolated static func decodeTolerant(_ data: Data) -> Snapshot? {
        if let snapshot = try? decoder.decode(Snapshot.self, from: data) { return snapshot }
        guard let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        func template<T: Encodable>(_ value: T) -> Any { (try? JSONSerialization.jsonObject(with: encoder.encode(value))) ?? [:] }
        // Schlüssel mit „?“ sind optionale Objekte: nur ergänzen, wenn sie in den Daten vorkommen
        var invoiceTemplate = template(Invoice()) as? [String: Any] ?? [:]
        invoiceTemplate["?seller"] = template(Company())
        var incomingTemplate = template(IncomingInvoice()) as? [String: Any] ?? [:]
        incomingTemplate["lines"] = [template(IncomingInvoice.Line())]
        incomingTemplate["taxes"] = [template(IncomingInvoice.Tax())]
        let snapshotTemplate: [String: Any] = [
            "company": template(Company()), "customers": [template(Customer())], "invoices": [invoiceTemplate],
            "incoming": [incomingTemplate], "onboarded": false,
        ]
        func merge(_ value: Any, _ template: Any) -> Any {
            if let dict = value as? [String: Any], let defaults = template as? [String: Any] {
                var result: [String: Any] = [:]
                // Fehlende Felder: Standardwert; Listen-Vorlagen werden zu leeren Listen
                for (key, d) in defaults where !key.hasPrefix("?") && dict[key] == nil { result[key] = d is [Any] ? [] : d }
                for (key, v) in dict {
                    if let d = defaults[key] ?? defaults["?" + key], !(v is NSNull) { result[key] = merge(v, d) } else { result[key] = v }
                }
                return result
            }
            if let array = value as? [Any], let element = (template as? [Any])?.first {
                return array.map { merge($0, element) }
            }
            return value
        }
        let merged = merge(raw, snapshotTemplate)
        guard let fixed = try? JSONSerialization.data(withJSONObject: merged) else { return nil }
        return try? decoder.decode(Snapshot.self, from: fixed)
    }

    nonisolated static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        // ISO 8601 mit Millisekunden, damit Zeitpunkte beim Speichern exakt erhalten bleiben
        e.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(DataStore.isoFractional.string(from: date))
        }
        return e
    }()

    nonisolated static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        // Liest beide Varianten: mit Millisekunden (heute) und ohne (Version 1.0)
        d.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            if let date = DataStore.isoFractional.date(from: text) ?? ISO8601DateFormatter().date(from: text) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Ungültiges Datum: \(text)"))
        }
        return d
    }()

    nonisolated(unsafe) static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    // MARK: Ausgangsrechnungen

    func newInvoice(for customer: Customer? = nil) -> Invoice {
        var invoice = Invoice()
        invoice.taxMode = company.smallBusiness ? .smallBusiness : .regular
        invoice.dueDate = Calendar.current.date(byAdding: .day, value: company.paymentDays, to: invoice.issueDate) ?? invoice.issueDate
        if let customer { invoice.customer = customer }
        if company.smallBusiness { invoice.items = [LineItem(vatRate: 0)] }
        invoices.insert(invoice, at: 0)
        return invoice
    }

    func update(_ invoice: Invoice) {
        guard let index = invoices.firstIndex(where: { $0.id == invoice.id }) else { return }
        invoices[index] = invoice
    }

    func invoice(id: Invoice.ID?) -> Invoice? { invoices.first { $0.id == id } }

    /// Nächste fortlaufende Nummer, z. B. RE-2026-0007 (§ 14 Abs. 4 Nr. 4 UStG: einmalig und fortlaufend)
    func peekNumber(for date: Date = Date()) -> String {
        let year = Calendar.current.component(.year, from: date)
        let prefix = company.invoicePrefix.trimmingCharacters(in: .whitespaces)
        let counter = String(format: "%04d", company.nextNumber)
        return [prefix.isEmpty ? nil : prefix, "\(year)", counter].compactMap { $0 }.joined(separator: "-")
    }

    /// Schreibt die Rechnung fest: Nummer vergeben, Absender einfrieren, ab dann unveränderbar
    @discardableResult
    func finalize(_ invoice: Invoice) -> Invoice {
        var final = invoice
        final.number = peekNumber(for: invoice.issueDate)
        final.seller = company
        final.status = .open
        company.nextNumber += 1
        update(final)
        // Kunde merken bzw. aktualisieren, damit er beim nächsten Mal zur Auswahl steht
        if let index = customers.firstIndex(where: { $0.id == final.customer.id }) {
            customers[index] = final.customer
        } else if !final.customer.name.isEmpty {
            customers.append(final.customer)
        }
        return final
    }

    /// Storniert eine festgeschriebene Rechnung: Es entsteht eine Stornorechnung mit eigener fortlaufender Nummer,
    /// die die ursprüngliche vollständig aufhebt. Löschen ist nach GoBD nicht erlaubt.
    @discardableResult
    func cancel(_ original: Invoice, on date: Date = Date()) -> Invoice? {
        guard original.kind == .invoice, original.status == .open || original.status == .paid, original.cancelledBy.isEmpty else { return nil }
        var storno = Invoice()
        storno.kind = .cancellation
        storno.customer = original.customer
        storno.items = original.items.map { var item = $0; item.id = UUID(); return item }
        storno.taxMode = original.taxMode
        storno.issueDate = date
        storno.serviceStart = original.serviceStart
        storno.serviceEnd = original.serviceEnd
        storno.dueDate = date
        storno.subject = "Storno der Rechnung \(original.number)"
        storno.intro = "Hiermit stornieren wir die Rechnung \(original.number) vom \(DateText.format(original.issueDate)) vollständig."
        storno.referenceNumber = original.number
        storno.referenceDate = original.issueDate
        storno.number = peekNumber(for: date)
        storno.seller = original.seller ?? company
        storno.status = .cancelled
        company.nextNumber += 1
        invoices.insert(storno, at: 0)
        var cancelled = original
        cancelled.status = .cancelled
        cancelled.cancelledBy = storno.number
        update(cancelled)
        return storno
    }

    /// Positionen aus früheren Rechnungen als Vorlagen – neueste zuerst, ohne Doppelte
    var previousItems: [LineItem] {
        var seen = Set<String>()
        var result: [LineItem] = []
        for invoice in invoices where invoice.kind == .invoice {
            for item in invoice.items where !item.title.trimmingCharacters(in: .whitespaces).isEmpty {
                let key = "\(item.title)|\(item.unitPrice)|\(item.unit.rawValue)"
                if seen.insert(key).inserted { result.append(item) }
            }
        }
        return Array(result.prefix(20))
    }

    func duplicate(_ invoice: Invoice) -> Invoice {
        var copy = Invoice()
        copy.customer = invoice.customer
        copy.items = invoice.items.map { var item = $0; item.id = UUID(); return item }
        copy.taxMode = invoice.taxMode
        copy.subject = invoice.isCancellation ? "" : invoice.subject
        if !invoice.isCancellation { copy.intro = invoice.intro }
        copy.dueDate = Calendar.current.date(byAdding: .day, value: company.paymentDays, to: copy.issueDate) ?? copy.issueDate
        invoices.insert(copy, at: 0)
        return copy
    }

    func deleteDraft(_ invoice: Invoice) {
        guard invoice.status == .draft else { return }
        invoices.removeAll { $0.id == invoice.id }
    }

    func setPaid(_ invoice: Invoice, paid: Bool) {
        guard invoice.kind == .invoice, invoice.status == .open || invoice.status == .paid else { return }
        var changed = invoice
        changed.status = paid ? .paid : .open
        changed.paidDate = paid ? Date() : nil
        update(changed)
    }

    // MARK: Eingangsrechnungen

    /// Liest eine E-Rechnung ein und legt das Original unverändert im Archiv ab
    func importIncoming(from url: URL) throws -> IncomingInvoice {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        var invoice = try EInvoiceReader.read(data: data)
        invoice.originalFileName = url.lastPathComponent
        if let duplicate = incoming.first(where: { $0.number == invoice.number && $0.seller.name == invoice.seller.name && !invoice.number.isEmpty }) {
            return duplicate
        }
        if let archiveFolder {
            try FileManager.default.createDirectory(at: archiveFolder, withIntermediateDirectories: true)
            let stored = "\(invoice.id.uuidString)-\(url.lastPathComponent)"
            try data.write(to: archiveFolder.appendingPathComponent(stored))
            invoice.storedFileName = stored
        }
        incoming.insert(invoice, at: 0)
        return invoice
    }

    func storedURL(of invoice: IncomingInvoice) -> URL? {
        guard !invoice.storedFileName.isEmpty else { return nil }
        return archiveFolder?.appendingPathComponent(invoice.storedFileName)
    }

    func updateIncoming(_ invoice: IncomingInvoice) {
        guard let index = incoming.firstIndex(where: { $0.id == invoice.id }) else { return }
        incoming[index] = invoice
    }

    func deleteIncoming(_ invoice: IncomingInvoice) {
        if let url = storedURL(of: invoice) { try? FileManager.default.removeItem(at: url) }
        incoming.removeAll { $0.id == invoice.id }
    }

    // MARK: Kennzahlen

    var openReceivables: Decimal { invoices.filter(\.awaitsPayment).reduce(0) { $0 + $1.grossTotal } }
    var openInvoices: [Invoice] { invoices.filter(\.awaitsPayment).sorted { $0.dueDate < $1.dueDate } }
    var overdueInvoices: [Invoice] { invoices.filter { $0.isOverdue() }.sorted { $0.dueDate < $1.dueDate } }
    var openPayables: Decimal { unpaidIncoming.reduce(0) { $0 + $1.dueAmount } }
    var unpaidIncoming: [IncomingInvoice] {
        incoming.filter { !$0.isPaid && !$0.isCreditNote }.sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
    }

    /// Nettoumsatz eines Jahres: alle festgeschriebenen Rechnungen, Stornos ziehen ab
    func revenue(year: Int) -> Decimal {
        invoices.filter { $0.status != .draft && Calendar.current.component(.year, from: $0.issueDate) == year }
            .reduce(0) { $0 + $1.signedNet }
    }

    /// Nettoumsatz je Monat des laufenden Jahres (festgeschriebene Rechnungen)
    func monthlyRevenue(year: Int) -> [(month: Int, net: Double)] {
        (1...12).map { month in
            let sum = invoices.filter { $0.status != .draft &&
                Calendar.current.component(.year, from: $0.issueDate) == year &&
                Calendar.current.component(.month, from: $0.issueDate) == month }
                .reduce(Decimal(0)) { $0 + $1.signedNet }
            return (month, sum.doubleValue)
        }
    }

    /// Zählt für das Freikontingent nur echte Rechnungen, keine Stornos
    var finalizedCount: Int { invoices.filter { $0.status != .draft && $0.kind == .invoice }.count }

    // MARK: Datensicherung

    /// Kopiert den gesamten Datenordner (Daten und archivierte Original-E-Rechnungen) in einen Sicherungsordner
    func exportBackup(to parent: URL, date: Date = Date()) throws -> URL {
        guard let folder else { throw CocoaError(.fileNoSuchFile) }
        saveNow()
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd_HH-mm"
        let target = parent.appendingPathComponent("Rechnungsklar-Sicherung_\(f.string(from: date))", isDirectory: true)
        try FileManager.default.copyItem(at: folder, to: target)
        return target
    }

    /// Stellt eine Sicherung wieder her. Die aktuellen Daten werden vorher beiseitegelegt, nicht gelöscht.
    func restoreBackup(from source: URL) throws {
        guard let folder else { throw CocoaError(.fileNoSuchFile) }
        let sourceData = source.appendingPathComponent("daten.json")
        guard let data = try? Data(contentsOf: sourceData), Self.decodeTolerant(data) != nil else {
            throw CocoaError(.fileReadCorruptFile, userInfo: [NSLocalizedDescriptionKey: "Der Ordner enthält keine gültige Rechnungsklar-Sicherung."])
        }
        saveTask?.cancel()
        let fm = FileManager.default
        if fm.fileExists(atPath: folder.path) {
            let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
            try fm.moveItem(at: folder, to: folder.deletingLastPathComponent().appendingPathComponent("Rechnungsklar-vor-Wiederherstellung-\(stamp)"))
        }
        try fm.copyItem(at: source, to: folder)
        reload()
    }
}

// MARK: - CSV für die Steuerberatung

enum CSVExport {
    static func outgoing(_ invoices: [Invoice]) -> String {
        var rows = [["Rechnungsnr.", "Art", "Datum", "Kunde", "Netto", "USt", "Brutto", "Fällig", "Status", "Bezahlt am", "Bezug"]]
        for i in invoices.sorted(by: { $0.number < $1.number }) where i.status != .draft {
            let sign: Decimal = i.isCancellation ? -1 : 1
            rows.append([i.number, i.title, DateText.format(i.issueDate), i.customer.name, plain(sign * i.netTotal), plain(sign * i.taxTotal),
                         plain(sign * i.grossTotal), i.isCancellation ? "" : DateText.format(i.dueDate), i.status.label,
                         i.paidDate.map { DateText.format($0) } ?? "", i.isCancellation ? i.referenceNumber : i.cancelledBy])
        }
        return csv(rows)
    }

    static func incoming(_ invoices: [IncomingInvoice]) -> String {
        var rows = [["Rechnungsnr.", "Datum", "Lieferant", "USt-IdNr.", "Netto", "USt", "Brutto", "Fällig", "Bezahlt", "Format", "Datei"]]
        for i in invoices {
            rows.append([i.number, DateText.format(i.issueDate), i.seller.name, i.seller.vatID, plain(i.netTotal), plain(i.taxTotal),
                         plain(i.grossTotal), DateText.format(i.dueDate), i.isPaid ? "ja" : "nein", i.format, i.originalFileName])
        }
        return csv(rows)
    }

    private static func plain(_ value: Decimal) -> String {
        XRechnungWriter.amount(value).replacingOccurrences(of: ".", with: ",")
    }

    /// Semikolon und BOM, damit Excel und Numbers in Deutschland die Datei direkt richtig öffnen
    private static func csv(_ rows: [[String]]) -> String {
        "\u{FEFF}" + rows.map { row in
            row.map { field in
                field.contains(";") || field.contains("\"") || field.contains("\n")
                    ? "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : field
            }.joined(separator: ";")
        }.joined(separator: "\r\n") + "\r\n"
    }
}
