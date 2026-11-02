import Foundation

/// Beispiel-E-Rechnung für alle, die (noch) keine XRechnung zur Hand haben – auch für die App-Review von Apple.
/// Erfundene Firmen und Daten; die IBAN ist die übliche Test-IBAN der Commerzbank.
enum DemoContent {
    static func sampleXML() -> String {
        func day(_ d: Int, _ m: Int) -> Date {
            Calendar.current.date(from: DateComponents(year: Calendar.current.component(.year, from: Date()), month: m, day: d, hour: 12)) ?? Date()
        }
        var seller = Company()
        seller.name = "Beispiel Coworking GmbH"
        seller.owner = "Buchhaltung"
        seller.street = "Musterstraße 1"
        seller.zip = "10115"
        seller.city = "Berlin"
        seller.phone = "+49 30 1234567"
        seller.email = "rechnung@beispiel-coworking.de"
        seller.vatID = "DE999999999"
        seller.iban = "DE89370400440532013000"
        seller.bic = "COBADEFFXXX"

        var invoice = Invoice()
        invoice.number = "BSP-2026-001"
        invoice.customer = Customer(name: "Ihre Firma", street: "Beispielweg 5", zip: "50667", city: "Köln", email: "info@example.com", buyerReference: "Beispiel")
        let month = Calendar.current.component(.month, from: Date())
        invoice.issueDate = day(1, month)
        invoice.serviceStart = day(1, month)
        invoice.serviceEnd = day(28, month)
        invoice.dueDate = day(15, month)
        invoice.subject = "Beispielrechnung – so sieht eine XRechnung in Rechnungsklar aus"
        invoice.items = [
            LineItem(title: "Arbeitsplatz Flex", detail: "Monatspauschale inkl. Internet", quantity: 1, unit: .month, unitPrice: 249, vatRate: 19),
            LineItem(title: "Meetingraum", detail: "Raum „Spree“", quantity: 4, unit: .hour, unitPrice: 30, vatRate: 19),
        ]
        invoice.status = .open
        invoice.seller = seller
        return XRechnungWriter.xml(for: invoice, seller: seller)
    }
}

extension DataStore {
    /// Liest die Beispiel-E-Rechnung ein, als wäre sie aus einer Datei gekommen
    func importSample() -> IncomingInvoice? {
        guard var invoice = try? EInvoiceReader.parseXML(Data(DemoContent.sampleXML().utf8)) else { return nil }
        if let existing = incoming.first(where: { $0.number == invoice.number && $0.seller.name == invoice.seller.name }) { return existing }
        invoice.originalFileName = "Beispiel-XRechnung.xml"
        incoming.insert(invoice, at: 0)
        return invoice
    }
}
