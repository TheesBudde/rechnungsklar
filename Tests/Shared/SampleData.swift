import Foundation

/// Beispieldaten für Tests, Vorschaubilder und App-Store-Screenshots
enum SampleData {
    static func date(_ day: Int, _ month: Int, _ year: Int = 2026) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    static var company: Company {
        var c = Company()
        c.name = "Lena Hoffmann Design"
        c.owner = "Lena Hoffmann"
        c.street = "Lindenstraße 12"
        c.zip = "50674"
        c.city = "Köln"
        c.phone = "+49 221 1234567"
        c.email = "hallo@lenahoffmann.design"
        c.website = "lenahoffmann.design"
        c.vatID = "DE123456789"
        c.taxNumber = "214/5678/1234"
        c.iban = "DE89370400440532013000"
        c.bic = "COBADEFFXXX"
        c.bankName = "Commerzbank"
        c.nextNumber = 18
        return c
    }

    static let customers: [Customer] = [
        Customer(name: "Nordlicht Software GmbH", contactPerson: "Jonas Berg", street: "Hafenstraße 4", zip: "20457", city: "Hamburg",
                 email: "buchhaltung@nordlicht-software.de", vatID: "DE298765432", buyerReference: "PO-2026-114"),
        Customer(name: "Café Morgenrot", contactPerson: "Aylin Kaya", street: "Ehrenstraße 81", zip: "50672", city: "Köln",
                 email: "aylin@cafe-morgenrot.de"),
        Customer(name: "Stadtwerke Bergheim", contactPerson: "Frau Weber", street: "Am Rathaus 1", zip: "50126", city: "Bergheim",
                 email: "rechnungseingang@stadtwerke-bergheim.de", buyerReference: "05362004-0001-38"),
        Customer(name: "Studio Vrij B.V.", contactPerson: "Daan de Vries", street: "Keizersgracht 221", zip: "1016 DV", city: "Amsterdam",
                 country: "NL", email: "finance@studiovrij.nl", vatID: "NL859123456B01"),
    ]

    static var mainInvoice: Invoice {
        var i = Invoice()
        i.customer = customers[0]
        i.issueDate = date(28, 10)
        i.serviceStart = date(1, 10)
        i.serviceEnd = date(24, 10)
        i.dueDate = date(11, 11)
        i.subject = "Redesign App-Oberfläche, Oktober 2026"
        i.items = [
            LineItem(title: "UI-Design App „Nordlicht Plan“", detail: "Screens für Onboarding, Dashboard und Einstellungen inkl. Dark Mode",
                     quantity: 32, unit: .hour, unitPrice: 95, vatRate: 19),
            LineItem(title: "Design-System", detail: "Komponentenbibliothek in Figma, Farben und Typografie",
                     quantity: 1, unit: .lumpSum, unitPrice: 1450, vatRate: 19),
            LineItem(title: "Workshop vor Ort", detail: "Halbtägiger Abstimmungstermin in Hamburg", quantity: 0.5, unit: .day, unitPrice: 780, vatRate: 19),
            LineItem(title: "Fachbuch „Design Systems“", detail: "Für das Team, wie besprochen", quantity: 2, unit: .piece, unitPrice: 38.32, vatRate: 7),
        ]
        return i
    }

    static func invoices(company: Company) -> [Invoice] {
        var result: [Invoice] = []
        var number = 1
        func add(_ customer: Customer, _ day: Int, _ month: Int, _ items: [LineItem], status: InvoiceStatus, mode: TaxMode = .regular, subject: String = "") {
            var i = Invoice()
            i.customer = customer
            i.issueDate = date(day, month)
            i.serviceStart = date(max(1, day - 20), month)
            i.serviceEnd = date(day, month)
            i.dueDate = Calendar.current.date(byAdding: .day, value: 14, to: i.issueDate)!
            i.items = items
            i.taxMode = mode
            i.subject = subject
            i.status = status
            if status != .draft {
                i.number = String(format: "RE-2026-%04d", number)
                i.seller = company
                number += 1
            }
            if status == .paid { i.paidDate = Calendar.current.date(byAdding: .day, value: 9, to: i.issueDate) }
            result.append(i)
        }
        let hours = { (h: Decimal, title: String) in LineItem(title: title, quantity: h, unit: .hour, unitPrice: 95, vatRate: 19) }
        add(customers[1], 20, 1, [hours(14, "Logo und Speisekarte")], status: .paid)
        add(customers[0], 31, 1, [hours(40, "UI-Design Sprint 1")], status: .paid)
        add(customers[3], 27, 2, [LineItem(title: "Brand Workshop", quantity: 2, unit: .day, unitPrice: 780, vatRate: 0)], status: .paid, mode: .reverseCharge)
        add(customers[0], 31, 3, [hours(36, "UI-Design Sprint 2")], status: .paid)
        add(customers[2], 15, 4, [hours(22, "Kundenportal Konzept")], status: .paid)
        add(customers[0], 30, 4, [hours(28, "UI-Design Sprint 3")], status: .paid)
        add(customers[1], 12, 5, [hours(8, "Social-Media-Vorlagen")], status: .paid)
        add(customers[0], 31, 5, [hours(44, "UI-Design Sprint 4")], status: .paid)
        add(customers[2], 30, 6, [hours(30, "Kundenportal Screens")], status: .paid)
        add(customers[0], 31, 7, [hours(38, "UI-Design Sprint 5")], status: .paid)
        add(customers[3], 20, 8, [LineItem(title: "Packaging Design", quantity: 1, unit: .lumpSum, unitPrice: 2900, vatRate: 0)], status: .paid, mode: .reverseCharge)
        add(customers[0], 30, 9, [hours(41, "UI-Design Sprint 6")], status: .paid)
        add(customers[1], 6, 10, [hours(12, "Herbstkarte und Plakate")], status: .open, subject: "Herbstkarte 2026")
        add(customers[2], 14, 10, [hours(26, "Kundenportal Feinschliff")], status: .open)
        result.append(contentsOf: [])
        var main = mainInvoice
        main.number = String(format: "RE-2026-%04d", number)
        main.seller = company
        main.status = .open
        result.append(main)
        var draft = Invoice()
        draft.customer = customers[1]
        draft.subject = "Weihnachtsaktion"
        draft.items = [hours(6, "Gutschein-Design"), LineItem(title: "Druckabwicklung", quantity: 1, unit: .lumpSum, unitPrice: 120, vatRate: 19)]
        result.append(draft)
        return result.reversed()
    }

    /// Eine typische Eingangsrechnung als XRechnung (wie sie z. B. von einem Software-Anbieter kommt)
    static var supplierInvoice: Invoice {
        var i = Invoice()
        i.number = "INV-88213"
        i.customer = Customer(name: "Lena Hoffmann Design", contactPerson: "Lena Hoffmann", street: "Lindenstraße 12", zip: "50674", city: "Köln",
                              email: "hallo@lenahoffmann.design", buyerReference: "LH-2026")
        i.issueDate = date(15, 10)
        i.serviceStart = date(1, 10)
        i.serviceEnd = date(31, 10)
        i.dueDate = date(29, 10)
        i.subject = "Coworking Oktober 2026"
        i.items = [
            LineItem(title: "Fixdesk Oktober", detail: "Arbeitsplatz inkl. Internet und Kaffee", quantity: 1, unit: .month, unitPrice: 289, vatRate: 19),
            LineItem(title: "Meetingraum", detail: "Raum „Rhein“", quantity: 6, unit: .hour, unitPrice: 25, vatRate: 19),
        ]
        i.status = .open
        var seller = Company()
        seller.name = "Werkhaus Coworking GmbH"
        seller.owner = "Team Buchhaltung"
        seller.street = "Vogelsanger Str. 286"
        seller.zip = "50825"
        seller.city = "Köln"
        seller.phone = "+49 221 9876543"
        seller.email = "rechnung@werkhaus-koeln.de"
        seller.vatID = "DE311222333"
        seller.iban = "DE02120300000000202051"
        seller.bic = "BYLADEM1001"
        i.seller = seller
        return i
    }
}
