import Foundation

/// Schreibt eine Rechnung als XRechnung 3.0 in der CII-Syntax (UN/CEFACT Cross Industry Invoice).
/// Die Reihenfolge der Elemente folgt dem CII-Schema – Validatoren prüfen sie streng.
enum XRechnungWriter {
    static let guideline = "urn:cen.eu:en16931:2017#compliant#urn:xeinkauf.de:kosit:xrechnung_3.0"
    static let businessProcess = "urn:fdc:peppol.eu:2017:poacc:billing:01:1.0"

    static func xml(for invoice: Invoice, seller fallbackSeller: Company) -> String {
        let seller = invoice.seller ?? fallbackSeller
        let buyer = invoice.customer
        var x = XMLBuilder()
        x.raw(#"<?xml version="1.0" encoding="UTF-8"?>"#)
        x.open("rsm:CrossIndustryInvoice", attributes: [
            ("xmlns:rsm", "urn:un:unece:uncefact:data:standard:CrossIndustryInvoice:100"),
            ("xmlns:ram", "urn:un:unece:uncefact:data:standard:ReusableAggregateBusinessInformationEntity:100"),
            ("xmlns:qdt", "urn:un:unece:uncefact:data:standard:QualifiedDataType:100"),
            ("xmlns:udt", "urn:un:unece:uncefact:data:standard:UnqualifiedDataType:100"),
        ])

        x.open("rsm:ExchangedDocumentContext")
        x.open("ram:BusinessProcessSpecifiedDocumentContextParameter"); x.leaf("ram:ID", businessProcess); x.close()
        x.open("ram:GuidelineSpecifiedDocumentContextParameter"); x.leaf("ram:ID", guideline); x.close()
        x.close()

        x.open("rsm:ExchangedDocument")
        x.leaf("ram:ID", invoice.number.isEmpty ? "ENTWURF" : invoice.number)
        // 380 Rechnung, 381 Gutschrift/Storno (Beträge positiv, Bezug auf die Ursprungsrechnung)
        x.leaf("ram:TypeCode", invoice.isCancellation ? "381" : "380")
        x.open("ram:IssueDateTime"); x.date("udt:DateTimeString", invoice.issueDate); x.close()
        for note in notes(for: invoice, seller: seller) {
            x.open("ram:IncludedNote"); x.leaf("ram:Content", note); x.close()
        }
        x.close()

        x.open("rsm:SupplyChainTradeTransaction")
        for (index, item) in invoice.items.enumerated() {
            x.open("ram:IncludedSupplyChainTradeLineItem")
            x.open("ram:AssociatedDocumentLineDocument"); x.leaf("ram:LineID", "\(index + 1)"); x.close()
            x.open("ram:SpecifiedTradeProduct")
            x.leaf("ram:Name", item.title.isEmpty ? "Leistung" : item.title)
            if !item.detail.isEmpty { x.leaf("ram:Description", item.detail) }
            x.close()
            x.open("ram:SpecifiedLineTradeAgreement")
            x.open("ram:NetPriceProductTradePrice"); x.leaf("ram:ChargeAmount", amount(item.unitPrice, scale: 4)); x.close()
            x.close()
            x.open("ram:SpecifiedLineTradeDelivery")
            x.leaf("ram:BilledQuantity", amount(item.quantity, scale: 4), attributes: [("unitCode", item.unit.rawValue)])
            x.close()
            x.open("ram:SpecifiedLineTradeSettlement")
            x.open("ram:ApplicableTradeTax")
            x.leaf("ram:TypeCode", "VAT")
            x.leaf("ram:CategoryCode", invoice.taxCategory(for: item))
            x.leaf("ram:RateApplicablePercent", amount(invoice.effectiveRate(for: item), scale: 2))
            x.close()
            x.open("ram:SpecifiedTradeSettlementLineMonetarySummation"); x.leaf("ram:LineTotalAmount", amount(item.net)); x.close()
            x.close()
            x.close()
        }

        x.open("ram:ApplicableHeaderTradeAgreement")
        x.leaf("ram:BuyerReference", buyer.buyerReference.isEmpty ? (invoice.number.isEmpty ? "ENTWURF" : invoice.number) : buyer.buyerReference)
        x.open("ram:SellerTradeParty")
        // BR-CO-26: Ohne USt-IdNr. (oft bei Kleinunternehmern) braucht es eine Verkäuferkennung (BT-29) – dafür die Steuernummer
        if seller.vatID.isEmpty && !seller.taxNumber.isEmpty { x.leaf("ram:ID", seller.taxNumber) }
        x.leaf("ram:Name", seller.name)
        x.open("ram:DefinedTradeContact")
        x.leaf("ram:PersonName", seller.owner.isEmpty ? seller.name : seller.owner)
        x.open("ram:TelephoneUniversalCommunication"); x.leaf("ram:CompleteNumber", seller.phone); x.close()
        x.open("ram:EmailURIUniversalCommunication"); x.leaf("ram:URIID", seller.email); x.close()
        x.close()
        address(&x, street: seller.street, zip: seller.zip, city: seller.city, country: seller.country)
        x.open("ram:URIUniversalCommunication"); x.leaf("ram:URIID", seller.email, attributes: [("schemeID", "EM")]); x.close()
        if !seller.vatID.isEmpty {
            x.open("ram:SpecifiedTaxRegistration"); x.leaf("ram:ID", compact(seller.vatID), attributes: [("schemeID", "VA")]); x.close()
        }
        if !seller.taxNumber.isEmpty {
            x.open("ram:SpecifiedTaxRegistration"); x.leaf("ram:ID", seller.taxNumber, attributes: [("schemeID", "FC")]); x.close()
        }
        x.close()
        x.open("ram:BuyerTradeParty")
        x.leaf("ram:Name", buyer.name)
        if !buyer.contactPerson.isEmpty {
            x.open("ram:DefinedTradeContact"); x.leaf("ram:PersonName", buyer.contactPerson); x.close()
        }
        address(&x, street: buyer.street, zip: buyer.zip, city: buyer.city, country: buyer.country)
        x.open("ram:URIUniversalCommunication"); x.leaf("ram:URIID", buyer.email, attributes: [("schemeID", "EM")]); x.close()
        if !buyer.vatID.isEmpty {
            x.open("ram:SpecifiedTaxRegistration"); x.leaf("ram:ID", compact(buyer.vatID), attributes: [("schemeID", "VA")]); x.close()
        }
        x.close()
        x.close()

        x.open("ram:ApplicableHeaderTradeDelivery")
        x.open("ram:ActualDeliverySupplyChainEvent")
        x.open("ram:OccurrenceDateTime"); x.date("udt:DateTimeString", invoice.serviceEnd); x.close()
        x.close()
        x.close()

        x.open("ram:ApplicableHeaderTradeSettlement")
        x.leaf("ram:PaymentReference", invoice.number.isEmpty ? "ENTWURF" : invoice.number)
        x.leaf("ram:InvoiceCurrencyCode", "EUR")
        x.open("ram:SpecifiedTradeSettlementPaymentMeans")
        x.leaf("ram:TypeCode", "58")
        x.open("ram:PayeePartyCreditorFinancialAccount")
        x.leaf("ram:IBANID", compact(seller.iban))
        x.leaf("ram:AccountName", seller.owner.isEmpty ? seller.name : seller.owner)
        x.close()
        if !seller.bic.isEmpty {
            x.open("ram:PayeeSpecifiedCreditorFinancialInstitution"); x.leaf("ram:BICID", compact(seller.bic)); x.close()
        }
        x.close()
        for group in invoice.taxGroups {
            x.open("ram:ApplicableTradeTax")
            x.leaf("ram:CalculatedAmount", amount(group.amount))
            x.leaf("ram:TypeCode", "VAT")
            if let reason = exemptionReason(group.category) { x.leaf("ram:ExemptionReason", reason) }
            x.leaf("ram:BasisAmount", amount(group.basis))
            x.leaf("ram:CategoryCode", group.category)
            if let code = exemptionCode(group.category) { x.leaf("ram:ExemptionReasonCode", code) }
            x.leaf("ram:RateApplicablePercent", amount(group.rate))
            x.close()
        }
        if !Calendar.current.isDate(invoice.serviceStart, inSameDayAs: invoice.serviceEnd) {
            x.open("ram:BillingSpecifiedPeriod")
            x.open("ram:StartDateTime"); x.date("udt:DateTimeString", invoice.serviceStart); x.close()
            x.open("ram:EndDateTime"); x.date("udt:DateTimeString", invoice.serviceEnd); x.close()
            x.close()
        }
        x.open("ram:SpecifiedTradePaymentTerms")
        x.leaf("ram:Description", invoice.isCancellation
               ? "Storno der Rechnung \(invoice.referenceNumber). Bereits gezahlte Beträge werden erstattet."
               : "Zahlbar ohne Abzug bis \(DateText.format(invoice.dueDate)).")
        x.open("ram:DueDateDateTime"); x.date("udt:DateTimeString", invoice.dueDate); x.close()
        x.close()
        x.open("ram:SpecifiedTradeSettlementHeaderMonetarySummation")
        x.leaf("ram:LineTotalAmount", amount(invoice.netTotal))
        x.leaf("ram:TaxBasisTotalAmount", amount(invoice.netTotal))
        x.leaf("ram:TaxTotalAmount", amount(invoice.taxTotal), attributes: [("currencyID", "EUR")])
        x.leaf("ram:GrandTotalAmount", amount(invoice.grossTotal))
        x.leaf("ram:DuePayableAmount", amount(invoice.grossTotal))
        x.close()
        if invoice.isCancellation && !invoice.referenceNumber.isEmpty {
            x.open("ram:InvoiceReferencedDocument")
            x.leaf("ram:IssuerAssignedID", invoice.referenceNumber)
            if let date = invoice.referenceDate {
                x.open("ram:FormattedIssueDateTime"); x.date("qdt:DateTimeString", date); x.close()
            }
            x.close()
        }
        x.close()

        x.close()
        x.close()
        return x.text
    }

    static func notes(for invoice: Invoice, seller: Company) -> [String] {
        var notes: [String] = []
        if !invoice.subject.isEmpty { notes.append(invoice.subject) }
        if invoice.isCancellation && !invoice.intro.isEmpty { notes.append(invoice.intro) }
        if let notice = invoice.taxMode.notice { notes.append(notice) }
        return notes
    }

    static func exemptionReason(_ category: String) -> String? {
        switch category {
        case "E": "Kleinunternehmer gemäß § 19 UStG"
        case "AE": "Steuerschuldnerschaft des Leistungsempfängers"
        default: nil
        }
    }

    static func exemptionCode(_ category: String) -> String? { category == "AE" ? "VATEX-EU-AE" : nil }

    private static func address(_ x: inout XMLBuilder, street: String, zip: String, city: String, country: String) {
        x.open("ram:PostalTradeAddress")
        x.leaf("ram:PostcodeCode", zip)
        x.leaf("ram:LineOne", street)
        x.leaf("ram:CityName", city)
        x.leaf("ram:CountryID", country.isEmpty ? "DE" : country.uppercased())
        x.close()
    }

    /// IBAN, BIC und USt-IdNr. ohne Leerzeichen
    static func compact(_ value: String) -> String { value.replacingOccurrences(of: " ", with: "").uppercased() }

    /// Beträge mit Punkt, ohne Tausendertrennzeichen und ohne überflüssige Nullen bei Mengen
    static func amount(_ value: Decimal, scale: Int = 2) -> String {
        let rounded = value.rounded(scale)
        let f = NumberFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.numberStyle = .decimal
        f.usesGroupingSeparator = false
        f.minimumFractionDigits = scale == 2 ? 2 : 0
        f.maximumFractionDigits = scale
        return f.string(from: rounded as NSDecimalNumber) ?? "\(rounded)"
    }
}

/// Kleiner XML-Schreiber mit Einrückung und korrektem Escaping
struct XMLBuilder {
    private(set) var text = ""
    private var stack: [String] = []

    private var indent: String { String(repeating: "  ", count: stack.count) }

    mutating func raw(_ line: String) { text += line + "\n" }

    mutating func open(_ name: String, attributes: [(String, String)] = []) {
        text += indent + "<" + name + Self.attributeText(attributes) + ">\n"
        stack.append(name)
    }

    mutating func close() {
        let name = stack.removeLast()
        text += indent + "</" + name + ">\n"
    }

    mutating func leaf(_ name: String, _ value: String, attributes: [(String, String)] = []) {
        text += indent + "<" + name + Self.attributeText(attributes) + ">" + Self.escape(value) + "</" + name + ">\n"
    }

    /// Datum im Format 102 (JJJJMMTT)
    mutating func date(_ name: String, _ date: Date) {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyyMMdd"
        leaf(name, f.string(from: date), attributes: [("format", "102")])
    }

    private static func attributeText(_ attributes: [(String, String)]) -> String {
        attributes.map { " \($0.0)=\"\(escape($0.1))\"" }.joined()
    }

    static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
