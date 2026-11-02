import Foundation

/// Prüft vor dem Festschreiben, ob alle Pflichtangaben für § 14 UStG und XRechnung 3.0 vorhanden sind.
/// Die Meldungen sind bewusst in Alltagssprache gehalten, mit der Regel-ID in Klammern für Profis.
struct InvoiceIssue: Identifiable, Hashable {
    enum Area: String { case company = "Eigene Firma", customer = "Kunde", invoice = "Rechnung", items = "Positionen" }
    enum Severity { case error, hint }

    var area: Area
    var message: String
    var rule: String
    var severity: Severity = .error
    var id: String { area.rawValue + message }
}

enum InvoiceCheck {
    static func issues(for invoice: Invoice, company: Company) -> [InvoiceIssue] {
        var result: [InvoiceIssue] = []
        let seller = invoice.seller ?? company
        func need(_ value: String, _ area: InvoiceIssue.Area, _ message: String, _ rule: String) {
            if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { result.append(InvoiceIssue(area: area, message: message, rule: rule)) }
        }

        need(seller.name, .company, "Firmenname fehlt", "BT-27")
        need(seller.street, .company, "Straße fehlt", "BT-35")
        need(seller.zip, .company, "Postleitzahl fehlt", "BR-DE-4")
        need(seller.city, .company, "Ort fehlt", "BR-DE-3")
        need(seller.phone, .company, "Telefonnummer fehlt", "BR-DE-6")
        need(seller.email, .company, "E-Mail-Adresse fehlt", "BR-DE-7")
        need(seller.iban, .company, "IBAN fehlt", "BR-DE-23")
        if seller.vatID.isEmpty && seller.taxNumber.isEmpty {
            result.append(InvoiceIssue(area: .company, message: "Steuernummer oder USt-IdNr. fehlt", rule: "BR-DE-16"))
        }
        if !seller.iban.isEmpty && !IBAN.isValid(seller.iban) {
            result.append(InvoiceIssue(area: .company, message: "IBAN ist ungültig (Prüfziffer stimmt nicht)", rule: "BR-DE-19"))
        }

        need(invoice.customer.name, .customer, "Name des Kunden fehlt", "BT-44")
        need(invoice.customer.street, .customer, "Straße des Kunden fehlt", "BT-50")
        need(invoice.customer.zip, .customer, "Postleitzahl des Kunden fehlt", "BR-DE-9")
        need(invoice.customer.city, .customer, "Ort des Kunden fehlt", "BR-DE-8")
        need(invoice.customer.email, .customer, "E-Mail-Adresse des Kunden fehlt", "BT-49")
        if invoice.taxMode == .reverseCharge && invoice.customer.vatID.isEmpty {
            result.append(InvoiceIssue(area: .customer, message: "Für Reverse Charge braucht der Kunde eine USt-IdNr.", rule: "BR-AE-2"))
        }
        if invoice.taxMode == .reverseCharge && seller.vatID.isEmpty {
            result.append(InvoiceIssue(area: .company, message: "Für Reverse Charge brauchst du eine eigene USt-IdNr.", rule: "BR-AE-2"))
        }
        if invoice.customer.buyerReference.isEmpty {
            result.append(InvoiceIssue(area: .customer, message: "Keine Leitweg-ID/Referenz – es wird die Rechnungsnummer verwendet. Bei Behörden ist die Leitweg-ID Pflicht.",
                                       rule: "BR-DE-15", severity: .hint))
        }

        if invoice.items.isEmpty {
            result.append(InvoiceIssue(area: .items, message: "Mindestens eine Position wird benötigt", rule: "BG-25"))
        }
        for (index, item) in invoice.items.enumerated() {
            if item.title.trimmingCharacters(in: .whitespaces).isEmpty {
                result.append(InvoiceIssue(area: .items, message: "Position \(index + 1): Bezeichnung fehlt", rule: "BT-153"))
            }
            if item.quantity <= 0 {
                result.append(InvoiceIssue(area: .items, message: "Position \(index + 1): Menge muss größer als 0 sein", rule: "BT-129"))
            }
            if item.unitPrice < 0 {
                result.append(InvoiceIssue(area: .items, message: "Position \(index + 1): Preis darf nicht negativ sein", rule: "BT-146"))
            }
        }
        if !invoice.items.isEmpty && invoice.grossTotal <= 0 {
            result.append(InvoiceIssue(area: .items, message: "Der Rechnungsbetrag ist 0 € – trag Menge und Preis ein", rule: "BT-112"))
        }
        if invoice.dueDate < Calendar.current.startOfDay(for: invoice.issueDate) {
            result.append(InvoiceIssue(area: .invoice, message: "Fälligkeit liegt vor dem Rechnungsdatum", rule: "BT-9"))
        }
        if invoice.serviceEnd < Calendar.current.startOfDay(for: invoice.serviceStart) {
            result.append(InvoiceIssue(area: .invoice, message: "Leistungszeitraum endet vor seinem Beginn", rule: "BG-14"))
        }
        if invoice.taxMode == .regular && seller.smallBusiness {
            result.append(InvoiceIssue(area: .invoice, message: "Du bist als Kleinunternehmer eingetragen, die Rechnung weist aber Umsatzsteuer aus.",
                                       rule: "§ 19 UStG", severity: .hint))
        }
        return result
    }

    static func blocking(for invoice: Invoice, company: Company) -> [InvoiceIssue] {
        issues(for: invoice, company: company).filter { $0.severity == .error }
    }
}

enum IBAN {
    /// Prüfziffer nach ISO 13616 (Modulo 97)
    static func isValid(_ raw: String) -> Bool {
        let iban = raw.replacingOccurrences(of: " ", with: "").uppercased()
        guard iban.count >= 15, iban.count <= 34, iban.allSatisfy({ $0.isLetter || $0.isNumber }) else { return false }
        let rearranged = iban.dropFirst(4) + iban.prefix(4)
        var remainder = 0
        for character in rearranged {
            let digits: String
            if let value = character.wholeNumberValue {
                digits = String(value)
            } else if let ascii = character.asciiValue, character.isLetter {
                digits = String(Int(ascii) - 55)
            } else {
                return false
            }
            for digit in digits { remainder = (remainder * 10 + Int(String(digit))!) % 97 }
        }
        return remainder == 1
    }

    static func formatted(_ raw: String) -> String {
        let iban = raw.replacingOccurrences(of: " ", with: "").uppercased()
        return stride(from: 0, to: iban.count, by: 4).map { start in
            let s = iban.index(iban.startIndex, offsetBy: start)
            let e = iban.index(s, offsetBy: min(4, iban.count - start))
            return String(iban[s..<e])
        }.joined(separator: " ")
    }
}
