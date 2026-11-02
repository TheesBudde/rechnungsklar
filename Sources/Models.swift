import Foundation

// MARK: - Geld

extension Decimal {
    /// Kaufmännisch auf `scale` Nachkommastellen runden (wie es EN 16931 erwartet)
    func rounded(_ scale: Int = 2) -> Decimal {
        var value = self
        var result = Decimal()
        NSDecimalRound(&result, &value, scale, .plain)
        return result
    }

    var doubleValue: Double { NSDecimalNumber(decimal: self).doubleValue }
}

enum Money {
    static let euro: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.locale = Locale(identifier: "de_DE")
        f.currencyCode = "EUR"
        return f
    }()

    static let number: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: "de_DE")
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = 4
        return f
    }()

    static func format(_ value: Decimal, currency: String = "EUR") -> String {
        if currency == "EUR" { return euro.string(from: value as NSDecimalNumber) ?? "\(value) €" }
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.locale = Locale(identifier: "de_DE")
        f.currencyCode = currency
        return f.string(from: value as NSDecimalNumber) ?? "\(value) \(currency)"
    }

    static func quantity(_ value: Decimal) -> String { number.string(from: value as NSDecimalNumber) ?? "\(value)" }

    static func percent(_ value: Decimal) -> String { "\(quantity(value)) %" }
}

enum DateText {
    static let short: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateFormat = "dd.MM.yyyy"
        return f
    }()

    static func format(_ date: Date?) -> String { date.map { short.string(from: $0) } ?? "–" }
}

// MARK: - Stammdaten

/// Das eigene Unternehmen – Absender jeder Rechnung
struct Company: Codable, Equatable {
    var name = ""
    var owner = ""
    var street = ""
    var zip = ""
    var city = ""
    var country = "DE"
    var phone = ""
    var email = ""
    var website = ""
    var vatID = ""
    var taxNumber = ""
    var iban = ""
    var bic = ""
    var bankName = ""
    var smallBusiness = false
    var paymentDays = 14
    var invoicePrefix = "RE"
    var nextNumber = 1
    var closingText = "Vielen Dank für die gute Zusammenarbeit."
    /// Logo für den Briefkopf (PNG, verkleinert)
    var logo: Data?

    var isComplete: Bool { !name.isEmpty && !street.isEmpty && !zip.isEmpty && !city.isEmpty && !iban.isEmpty }
    /// Was für eine vollständige XRechnung noch fehlt (Kurzform für Hinweise)
    var missingEssentials: [String] {
        var missing: [String] = []
        if name.isEmpty { missing.append("Firmenname") }
        if street.isEmpty || zip.isEmpty || city.isEmpty { missing.append("Anschrift") }
        if phone.isEmpty || email.isEmpty { missing.append("Telefon und E-Mail") }
        if vatID.isEmpty && taxNumber.isEmpty { missing.append("Steuernummer") }
        if iban.isEmpty { missing.append("IBAN") }
        return missing
    }

    var addressLine: String { [name, street, "\(zip) \(city)"].filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.joined(separator: " · ") }
}

struct Customer: Codable, Identifiable, Equatable, Hashable {
    var id = UUID()
    var name = ""
    var contactPerson = ""
    var street = ""
    var zip = ""
    var city = ""
    var country = "DE"
    var email = ""
    var vatID = ""
    /// Leitweg-ID bei Behörden, sonst Bestellnummer o. Ä. (BT-10, in der XRechnung Pflicht)
    var buyerReference = ""
    var notes = ""
}

// MARK: - Rechnung

enum UnitCode: String, Codable, CaseIterable, Identifiable {
    case hour = "HUR", day = "DAY", piece = "C62", lumpSum = "LS", month = "MON", kilometre = "KMT"
    var id: String { rawValue }

    var label: String {
        switch self {
        case .hour: "Std."
        case .day: "Tag"
        case .piece: "Stk."
        case .lumpSum: "Pausch."
        case .month: "Monat"
        case .kilometre: "km"
        }
    }

    var longLabel: String {
        switch self {
        case .hour: "Stunden"
        case .day: "Tage"
        case .piece: "Stück"
        case .lumpSum: "Pauschale"
        case .month: "Monate"
        case .kilometre: "Kilometer"
        }
    }
}

/// Wie die Umsatzsteuer auf der Rechnung behandelt wird
enum TaxMode: String, Codable, CaseIterable, Identifiable {
    case regular, smallBusiness, reverseCharge
    var id: String { rawValue }

    var label: String {
        switch self {
        case .regular: "Mit Umsatzsteuer"
        case .smallBusiness: "Kleinunternehmer (§ 19 UStG)"
        case .reverseCharge: "Reverse Charge (EU-Ausland)"
        }
    }

    /// Pflichthinweis auf der Rechnung
    var notice: String? {
        switch self {
        case .regular: nil
        case .smallBusiness: "Gemäß § 19 UStG wird keine Umsatzsteuer berechnet."
        case .reverseCharge: "Steuerschuldnerschaft des Leistungsempfängers (Reverse Charge)."
        }
    }
}

struct LineItem: Codable, Identifiable, Equatable {
    var id = UUID()
    var title = ""
    var detail = ""
    var quantity: Decimal = 1
    var unit: UnitCode = .hour
    var unitPrice: Decimal = 0
    var vatRate: Decimal = 19

    var net: Decimal { (quantity * unitPrice).rounded() }
}

/// Rechnung oder Stornorechnung (hebt eine festgeschriebene Rechnung vollständig auf)
enum DocumentKind: String, Codable {
    case invoice, cancellation
}

enum InvoiceStatus: String, Codable, CaseIterable {
    case draft, open, paid, cancelled

    var label: String {
        switch self {
        case .draft: "Entwurf"
        case .open: "Offen"
        case .paid: "Bezahlt"
        case .cancelled: "Storniert"
        }
    }
}

/// Eine Zeile der Steueraufstellung (BG-23)
struct TaxGroup: Identifiable, Equatable {
    var category: String
    var rate: Decimal
    var basis: Decimal
    var amount: Decimal
    var id: String { "\(category)-\(rate)" }
}

struct Invoice: Codable, Identifiable, Equatable {
    var id = UUID()
    /// Wird erst beim Festschreiben vergeben – Entwürfe haben keine Nummer
    var number = ""
    var customer = Customer()
    var issueDate = Date()
    var serviceStart = Date()
    var serviceEnd = Date()
    var dueDate = Calendar.current.date(byAdding: .day, value: 14, to: Date())!
    var subject = ""
    var intro = "Für meine Leistungen erlaube ich mir, Ihnen Folgendes in Rechnung zu stellen:"
    var items: [LineItem] = [LineItem()]
    var taxMode: TaxMode = .regular
    var status: InvoiceStatus = .draft
    var paidDate: Date?
    var remindersSent = 0
    /// Absender zum Zeitpunkt des Festschreibens – spätere Änderungen an den Stammdaten ändern die Rechnung nicht
    var seller: Company?
    var kind: DocumentKind = .invoice
    /// Bei Stornorechnungen: Nummer und Datum der aufgehobenen Rechnung (BT-25, BT-26)
    var referenceNumber = ""
    var referenceDate: Date?
    /// Bei stornierten Rechnungen: Nummer der Stornorechnung
    var cancelledBy = ""

    var isLocked: Bool { status != .draft }
    var isCancellation: Bool { kind == .cancellation }
    var displayNumber: String { number.isEmpty ? "Entwurf" : number }
    var title: String { isCancellation ? "Stornorechnung" : "Rechnung" }
    /// Für Umsatz und Export: Stornos zählen negativ
    var signedNet: Decimal { isCancellation ? -netTotal : netTotal }
    var signedGross: Decimal { isCancellation ? -grossTotal : grossTotal }
    /// Wartet diese Rechnung auf Geld?
    var awaitsPayment: Bool { kind == .invoice && status == .open }

    var netTotal: Decimal { items.reduce(0) { $0 + $1.net } }

    func taxCategory(for item: LineItem) -> String {
        switch taxMode {
        case .smallBusiness: "E"
        case .reverseCharge: "AE"
        case .regular: item.vatRate > 0 ? "S" : "Z"
        }
    }

    func effectiveRate(for item: LineItem) -> Decimal { taxMode == .regular ? item.vatRate : 0 }

    /// Steuer je Kategorie und Satz, auf Gruppenebene gerundet (BR-CO-17)
    var taxGroups: [TaxGroup] {
        var groups: [String: TaxGroup] = [:]
        for item in items {
            let category = taxCategory(for: item)
            let rate = effectiveRate(for: item)
            let key = "\(category)-\(rate)"
            groups[key, default: TaxGroup(category: category, rate: rate, basis: 0, amount: 0)].basis += item.net
        }
        return groups.values
            .map { var g = $0; g.amount = (g.basis * g.rate / 100).rounded(); return g }
            .sorted { $0.rate > $1.rate }
    }

    var taxTotal: Decimal { taxGroups.reduce(0) { $0 + $1.amount } }
    var grossTotal: Decimal { netTotal + taxTotal }

    func isOverdue(on date: Date = Date()) -> Bool {
        awaitsPayment && Calendar.current.startOfDay(for: dueDate) < Calendar.current.startOfDay(for: date)
    }

    func daysOverdue(on date: Date = Date()) -> Int {
        max(0, Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: dueDate),
                                               to: Calendar.current.startOfDay(for: date)).day ?? 0)
    }

    var servicePeriodText: String {
        Calendar.current.isDate(serviceStart, inSameDayAs: serviceEnd)
            ? DateText.format(serviceEnd)
            : "\(DateText.format(serviceStart)) – \(DateText.format(serviceEnd))"
    }

    var fileBaseName: String {
        let customerPart = customer.name.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: "-")
        return [displayNumber, customerPart].filter { !$0.isEmpty }.joined(separator: "_")
    }
}

// MARK: - Eingangsrechnung

/// Eine empfangene E-Rechnung (XRechnung, ZUGFeRD oder Factur-X), so wie sie aus der Datei gelesen wurde
struct IncomingInvoice: Codable, Identifiable, Equatable {
    struct Party: Codable, Equatable {
        var name = ""
        var street = ""
        var zip = ""
        var city = ""
        var country = ""
        var vatID = ""
        var taxNumber = ""
        var email = ""
        var phone = ""
        var contact = ""

        var addressLines: [String] {
            [street, [zip, city].filter { !$0.isEmpty }.joined(separator: " "), country == "DE" ? "" : country].filter { !$0.isEmpty }
        }
    }

    struct Line: Codable, Equatable, Identifiable {
        var id = UUID()
        var position = ""
        var name = ""
        var detail = ""
        var quantity: Decimal = 0
        var unit = ""
        var unitPrice: Decimal = 0
        var net: Decimal = 0
        var vatRate: Decimal?
    }

    struct Tax: Codable, Equatable, Identifiable {
        var id = UUID()
        var category = ""
        var rate: Decimal = 0
        var basis: Decimal = 0
        var amount: Decimal = 0
        var exemptionReason = ""
    }

    var id = UUID()
    var format = ""
    var number = ""
    var typeCode = "380"
    var issueDate: Date?
    var dueDate: Date?
    var serviceDate: Date?
    var currency = "EUR"
    var buyerReference = ""
    var orderReference = ""
    var seller = Party()
    var buyer = Party()
    var lines: [Line] = []
    var taxes: [Tax] = []
    var netTotal: Decimal = 0
    var taxTotal: Decimal = 0
    var grossTotal: Decimal = 0
    var dueAmount: Decimal = 0
    var iban = ""
    var bic = ""
    var accountHolder = ""
    var paymentReference = ""
    var paymentTerms = ""
    /// Bei Gutschriften und Korrekturen: Nummer der Bezugsrechnung (BT-25)
    var precedingInvoice = ""
    var notes: [String] = []

    // Verwaltung in der App
    var importedAt = Date()
    var originalFileName = ""
    /// Unveränderte Originaldatei im App-Container (GoBD: das Original zählt)
    var storedFileName = ""
    var isPaid = false
    var paidDate: Date?
    var category = ""

    var isCreditNote: Bool { typeCode == "381" }
    var typeLabel: String {
        switch typeCode {
        case "381": "Gutschrift"
        case "384": "Rechnungskorrektur"
        case "326": "Teilrechnung"
        case "875", "876", "877": "Schlussrechnung"
        default: "Rechnung"
        }
    }

    func isOverdue(on date: Date = Date()) -> Bool {
        guard !isPaid, let dueDate else { return false }
        return Calendar.current.startOfDay(for: dueDate) < Calendar.current.startOfDay(for: date)
    }
}
