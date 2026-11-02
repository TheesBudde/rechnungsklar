import CoreGraphics
import Foundation

/// Liest empfangene E-Rechnungen: XRechnung/ZUGFeRD/Factur-X in CII-Syntax, XRechnung/Peppol in UBL-Syntax
/// und ZUGFeRD-/Factur-X-PDFs mit eingebetteter XML-Datei.
enum EInvoiceReader {
    enum Failure: LocalizedError {
        case unreadable, noEmbeddedXML, unknownFormat(String)

        var errorDescription: String? {
            switch self {
            case .unreadable: "Die Datei konnte nicht gelesen werden."
            case .noEmbeddedXML: "Das PDF enthält keine E-Rechnung. Es ist eine normale PDF-Rechnung ohne eingebettete XML-Daten (kein ZUGFeRD/Factur-X)."
            case .unknownFormat(let root): "Unbekanntes Format (\(root)). Unterstützt werden XRechnung, ZUGFeRD, Factur-X und Peppol."
            }
        }
    }

    static func read(url: URL) throws -> IncomingInvoice {
        guard let data = try? Data(contentsOf: url) else { throw Failure.unreadable }
        var invoice = try read(data: data)
        invoice.originalFileName = url.lastPathComponent
        return invoice
    }

    static func read(data: Data) throws -> IncomingInvoice {
        if data.starts(with: Array("%PDF".utf8)) {
            guard let xml = PDFAttachments.embeddedInvoiceXML(in: data) else { throw Failure.noEmbeddedXML }
            var invoice = try parseXML(xml)
            invoice.format = invoice.format.replacingOccurrences(of: "CII", with: "PDF")
            return invoice
        }
        return try parseXML(data)
    }

    static func parseXML(_ data: Data) throws -> IncomingInvoice {
        guard let root = XMLTree.parse(data) else { throw Failure.unreadable }
        switch root.name {
        case "CrossIndustryInvoice": return parseCII(root)
        case "Invoice", "CreditNote": return parseUBL(root)
        default: throw Failure.unknownFormat(root.name)
        }
    }

    // MARK: CII (XRechnung CII, ZUGFeRD 2.x, Factur-X)

    static func parseCII(_ root: XMLNode) -> IncomingInvoice {
        var inv = IncomingInvoice()
        let guideline = root.text("ExchangedDocumentContext/GuidelineSpecifiedDocumentContextParameter/ID")
        inv.format = formatName(guideline: guideline, syntax: "CII")
        let doc = root.child("ExchangedDocument")
        inv.number = doc?.text("ID") ?? ""
        inv.typeCode = doc?.text("TypeCode").nonEmpty ?? "380"
        inv.issueDate = parseDate(doc?.text("IssueDateTime/DateTimeString"))
        inv.notes = doc?.children("IncludedNote").map { $0.text("Content") }.filter { !$0.isEmpty } ?? []

        let tx = root.child("SupplyChainTradeTransaction")
        let agreement = tx?.child("ApplicableHeaderTradeAgreement")
        inv.buyerReference = agreement?.text("BuyerReference") ?? ""
        inv.orderReference = agreement?.text("BuyerOrderReferencedDocument/IssuerAssignedID") ?? ""
        inv.seller = ciiParty(agreement?.child("SellerTradeParty"))
        inv.buyer = ciiParty(agreement?.child("BuyerTradeParty"))
        inv.serviceDate = parseDate(tx?.text("ApplicableHeaderTradeDelivery/ActualDeliverySupplyChainEvent/OccurrenceDateTime/DateTimeString"))

        let settlement = tx?.child("ApplicableHeaderTradeSettlement")
        inv.currency = settlement?.text("InvoiceCurrencyCode").nonEmpty ?? "EUR"
        inv.paymentReference = settlement?.text("PaymentReference") ?? ""
        if let means = settlement?.child("SpecifiedTradeSettlementPaymentMeans") {
            inv.iban = means.text("PayeePartyCreditorFinancialAccount/IBANID")
            inv.accountHolder = means.text("PayeePartyCreditorFinancialAccount/AccountName")
            inv.bic = means.text("PayeeSpecifiedCreditorFinancialInstitution/BICID")
        }
        inv.taxes = settlement?.children("ApplicableTradeTax").map { tax in
            IncomingInvoice.Tax(category: tax.text("CategoryCode"), rate: decimal(tax.text("RateApplicablePercent")),
                                basis: decimal(tax.text("BasisAmount")), amount: decimal(tax.text("CalculatedAmount")),
                                exemptionReason: tax.text("ExemptionReason"))
        } ?? []
        if let terms = settlement?.child("SpecifiedTradePaymentTerms") {
            inv.paymentTerms = terms.text("Description")
            inv.dueDate = parseDate(terms.text("DueDateDateTime/DateTimeString"))
        }
        inv.precedingInvoice = settlement?.text("InvoiceReferencedDocument/IssuerAssignedID") ?? ""
        if let sum = settlement?.child("SpecifiedTradeSettlementHeaderMonetarySummation") {
            inv.netTotal = decimal(sum.text("TaxBasisTotalAmount").nonEmpty ?? sum.text("LineTotalAmount"))
            // Es kann zwei TaxTotalAmount geben (Rechnungs- und Steuerwährung) – die in Rechnungswährung zählt
            let taxTotals = sum.children("TaxTotalAmount")
            inv.taxTotal = decimal((taxTotals.first { $0.attributes["currencyID"] == inv.currency } ?? taxTotals.first)?.value)
            inv.grossTotal = decimal(sum.text("GrandTotalAmount"))
            inv.dueAmount = decimal(sum.text("DuePayableAmount").nonEmpty ?? sum.text("GrandTotalAmount"))
        }

        inv.lines = tx?.children("IncludedSupplyChainTradeLineItem").map { line in
            let quantityNode = line.node("SpecifiedLineTradeDelivery/BilledQuantity")
            return IncomingInvoice.Line(
                position: line.text("AssociatedDocumentLineDocument/LineID"),
                name: line.text("SpecifiedTradeProduct/Name"),
                detail: line.text("SpecifiedTradeProduct/Description"),
                quantity: decimal(quantityNode?.value),
                unit: UnitCode(rawValue: quantityNode?.attributes["unitCode"] ?? "")?.label ?? (quantityNode?.attributes["unitCode"] ?? ""),
                unitPrice: decimal(line.text("SpecifiedLineTradeAgreement/NetPriceProductTradePrice/ChargeAmount")),
                net: decimal(line.text("SpecifiedLineTradeSettlement/SpecifiedTradeSettlementLineMonetarySummation/LineTotalAmount")),
                vatRate: line.text("SpecifiedLineTradeSettlement/ApplicableTradeTax/RateApplicablePercent").nonEmpty.map { decimal($0) })
        } ?? []
        return inv
    }

    private static func ciiParty(_ node: XMLNode?) -> IncomingInvoice.Party {
        guard let node else { return .init() }
        var p = IncomingInvoice.Party()
        p.name = node.text("Name")
        p.street = [node.text("PostalTradeAddress/LineOne"), node.text("PostalTradeAddress/LineTwo")].filter { !$0.isEmpty }.joined(separator: ", ")
        p.zip = node.text("PostalTradeAddress/PostcodeCode")
        p.city = node.text("PostalTradeAddress/CityName")
        p.country = node.text("PostalTradeAddress/CountryID")
        for registration in node.children("SpecifiedTaxRegistration") {
            guard let id = registration.child("ID") else { continue }
            if id.attributes["schemeID"] == "VA" { p.vatID = id.value } else { p.taxNumber = id.value }
        }
        p.contact = node.text("DefinedTradeContact/PersonName")
        p.phone = node.text("DefinedTradeContact/TelephoneUniversalCommunication/CompleteNumber")
        p.email = node.text("DefinedTradeContact/EmailURIUniversalCommunication/URIID").nonEmpty ?? node.text("URIUniversalCommunication/URIID")
        return p
    }

    // MARK: UBL (XRechnung UBL, Peppol BIS Billing 3.0)

    static func parseUBL(_ root: XMLNode) -> IncomingInvoice {
        var inv = IncomingInvoice()
        let isCredit = root.name == "CreditNote"
        inv.format = formatName(guideline: root.text("CustomizationID"), syntax: "UBL")
        inv.number = root.text("ID")
        inv.typeCode = (isCredit ? root.text("CreditNoteTypeCode") : root.text("InvoiceTypeCode")).nonEmpty ?? (isCredit ? "381" : "380")
        inv.issueDate = parseDate(root.text("IssueDate"))
        inv.dueDate = parseDate(root.text("DueDate").nonEmpty ?? root.text("PaymentMeans/PaymentDueDate"))
        inv.currency = root.text("DocumentCurrencyCode").nonEmpty ?? "EUR"
        inv.buyerReference = root.text("BuyerReference")
        inv.orderReference = root.text("OrderReference/ID")
        inv.notes = root.children("Note").map(\.value).filter { !$0.isEmpty }
        inv.seller = ublParty(root.node("AccountingSupplierParty/Party"))
        inv.buyer = ublParty(root.node("AccountingCustomerParty/Party"))
        inv.serviceDate = parseDate(root.text("Delivery/ActualDeliveryDate").nonEmpty ?? root.text("InvoicePeriod/EndDate"))
        if let means = root.child("PaymentMeans") {
            inv.iban = means.text("PayeeFinancialAccount/ID")
            inv.accountHolder = means.text("PayeeFinancialAccount/Name")
            inv.bic = means.text("PayeeFinancialAccount/FinancialInstitutionBranch/ID")
            inv.paymentReference = means.text("PaymentID")
        }
        inv.paymentTerms = root.text("PaymentTerms/Note")
        inv.precedingInvoice = root.text("BillingReference/InvoiceDocumentReference/ID")
        let taxTotals = root.children("TaxTotal")
        let mainTax = taxTotals.first { $0.child("TaxSubtotal") != nil } ?? taxTotals.first
        inv.taxTotal = decimal(mainTax?.text("TaxAmount"))
        inv.taxes = mainTax?.children("TaxSubtotal").map { sub in
            IncomingInvoice.Tax(category: sub.text("TaxCategory/ID"), rate: decimal(sub.text("TaxCategory/Percent")),
                                basis: decimal(sub.text("TaxableAmount")), amount: decimal(sub.text("TaxAmount")),
                                exemptionReason: sub.text("TaxCategory/TaxExemptionReason"))
        } ?? []
        let total = root.child("LegalMonetaryTotal")
        inv.netTotal = decimal(total?.text("TaxExclusiveAmount"))
        inv.grossTotal = decimal(total?.text("TaxInclusiveAmount"))
        inv.dueAmount = decimal(total?.text("PayableAmount").nonEmpty ?? total?.text("TaxInclusiveAmount"))

        let lineName = isCredit ? "CreditNoteLine" : "InvoiceLine"
        let quantityName = isCredit ? "CreditedQuantity" : "InvoicedQuantity"
        inv.lines = root.children(lineName).map { line in
            let q = line.child(quantityName)
            let unitCode = q?.attributes["unitCode"] ?? ""
            return IncomingInvoice.Line(
                position: line.text("ID"),
                name: line.text("Item/Name"),
                detail: line.text("Item/Description"),
                quantity: decimal(q?.value),
                unit: UnitCode(rawValue: unitCode)?.label ?? unitCode,
                unitPrice: decimal(line.text("Price/PriceAmount")),
                net: decimal(line.text("LineExtensionAmount")),
                vatRate: line.text("Item/ClassifiedTaxCategory/Percent").nonEmpty.map { decimal($0) })
        }
        return inv
    }

    private static func ublParty(_ node: XMLNode?) -> IncomingInvoice.Party {
        guard let node else { return .init() }
        var p = IncomingInvoice.Party()
        p.name = node.text("PartyLegalEntity/RegistrationName").nonEmpty ?? node.text("PartyName/Name")
        p.street = [node.text("PostalAddress/StreetName"), node.text("PostalAddress/AdditionalStreetName")].filter { !$0.isEmpty }.joined(separator: ", ")
        p.zip = node.text("PostalAddress/PostalZone")
        p.city = node.text("PostalAddress/CityName")
        p.country = node.text("PostalAddress/Country/IdentificationCode")
        for scheme in node.children("PartyTaxScheme") {
            let id = scheme.text("CompanyID")
            if scheme.text("TaxScheme/ID") == "VAT" { p.vatID = id } else { p.taxNumber = id }
        }
        p.contact = node.text("Contact/Name")
        p.phone = node.text("Contact/Telephone")
        p.email = node.text("Contact/ElectronicMail").nonEmpty ?? node.text("EndpointID")
        return p
    }

    // MARK: Hilfen

    static func formatName(guideline: String, syntax: String) -> String {
        let g = guideline.lowercased()
        if g.contains("xrechnung") {
            let version = g.components(separatedBy: "xrechnung_").last.map { "\($0.prefix(3))" } ?? ""
            return "XRechnung \(version) (\(syntax))".replacingOccurrences(of: "  ", with: " ")
        }
        if g.contains("peppol") { return "Peppol BIS 3.0 (\(syntax))" }
        if g.contains("factur-x") || g.contains("zugferd") || g.contains("en16931") || g.contains("basic") || g.contains("extended") {
            return "ZUGFeRD / Factur-X (\(syntax))"
        }
        return "E-Rechnung (\(syntax))"
    }

    static func decimal(_ text: String?) -> Decimal {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return 0 }
        return Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")) ?? 0
    }

    static func parseDate(_ text: String?) -> Date? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        for format in ["yyyyMMdd", "yyyy-MM-dd", "yyyyMMddHHmmss"] {
            f.dateFormat = format
            if let date = f.date(from: String(text.prefix(format.count))) { return date }
        }
        return nil
    }
}

extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}

// MARK: - XML-Baum

/// Minimaler DOM-Baum mit Namensraum-freien Elementnamen, damit Pfade wie "A/B/C" in CII und UBL funktionieren
final class XMLNode {
    let name: String
    var attributes: [String: String]
    var value = ""
    var children: [XMLNode] = []

    init(name: String, attributes: [String: String]) {
        self.name = name
        self.attributes = attributes
    }

    func child(_ name: String) -> XMLNode? { children.first { $0.name == name } }
    func children(_ name: String) -> [XMLNode] { children.filter { $0.name == name } }

    func node(_ path: String) -> XMLNode? {
        var current: XMLNode? = self
        for part in path.split(separator: "/") { current = current?.child(String(part)) }
        return current
    }

    func text(_ path: String) -> String { node(path)?.value ?? "" }
}

enum XMLTree {
    static func parse(_ data: Data) -> XMLNode? {
        let delegate = Delegate()
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true
        parser.delegate = delegate
        return parser.parse() ? delegate.root : nil
    }

    private final class Delegate: NSObject, XMLParserDelegate {
        var root: XMLNode?
        var stack: [XMLNode] = []
        var buffer = ""

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?,
                    attributes: [String: String] = [:]) {
            let local = elementName.split(separator: ":").last.map(String.init) ?? elementName
            let node = XMLNode(name: local, attributes: attributes)
            if let parent = stack.last { parent.children.append(node) } else { root = node }
            stack.append(node)
            buffer = ""
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) { buffer += string }

        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
            if let node = stack.popLast(), node.children.isEmpty {
                node.value = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            buffer = ""
        }
    }
}

// MARK: - Eingebettete Dateien in PDFs (ZUGFeRD / Factur-X)

enum PDFAttachments {
    /// Bekannte Dateinamen der Rechnungs-XML in hybriden PDFs, bevorzugt in dieser Reihenfolge
    static let knownNames = ["factur-x.xml", "zugferd-invoice.xml", "xrechnung.xml", "zugferd_invoice.xml", "ZUGFeRD-invoice.xml"]

    static func embeddedInvoiceXML(in data: Data) -> Data? {
        guard let provider = CGDataProvider(data: data as CFData), let document = CGPDFDocument(provider),
              let catalog = document.catalog else { return nil }
        var files: [(String, Data)] = []

        var names: CGPDFDictionaryRef?
        var embedded: CGPDFDictionaryRef?
        if CGPDFDictionaryGetDictionary(catalog, "Names", &names), let names,
           CGPDFDictionaryGetDictionary(names, "EmbeddedFiles", &embedded), let embedded {
            collect(nameTree: embedded, into: &files, depth: 0)
        }
        // PDF/A-3 verknüpft die Datei zusätzlich über /AF im Katalog
        var associated: CGPDFArrayRef?
        if files.isEmpty, CGPDFDictionaryGetArray(catalog, "AF", &associated), let associated {
            for index in 0..<CGPDFArrayGetCount(associated) {
                var spec: CGPDFDictionaryRef?
                if CGPDFArrayGetDictionary(associated, index, &spec), let spec, let file = fileData(spec: spec) { files.append(file) }
            }
        }

        for known in knownNames {
            if let match = files.first(where: { $0.0.lowercased() == known.lowercased() }) { return match.1 }
        }
        return files.first { $0.0.lowercased().hasSuffix(".xml") }?.1
    }

    private static func collect(nameTree node: CGPDFDictionaryRef, into files: inout [(String, Data)], depth: Int) {
        guard depth < 16 else { return }
        var namesArray: CGPDFArrayRef?
        if CGPDFDictionaryGetArray(node, "Names", &namesArray), let namesArray {
            let count = CGPDFArrayGetCount(namesArray)
            var index = 1
            while index < count {
                var spec: CGPDFDictionaryRef?
                if CGPDFArrayGetDictionary(namesArray, index, &spec), let spec, let file = fileData(spec: spec) { files.append(file) }
                index += 2
            }
        }
        var kids: CGPDFArrayRef?
        if CGPDFDictionaryGetArray(node, "Kids", &kids), let kids {
            for index in 0..<CGPDFArrayGetCount(kids) {
                var kid: CGPDFDictionaryRef?
                if CGPDFArrayGetDictionary(kids, index, &kid), let kid { collect(nameTree: kid, into: &files, depth: depth + 1) }
            }
        }
    }

    private static func fileData(spec: CGPDFDictionaryRef) -> (String, Data)? {
        var name = ""
        for key in ["UF", "F"] {
            var string: CGPDFStringRef?
            if CGPDFDictionaryGetString(spec, key, &string), let string, let text = CGPDFStringCopyTextString(string) {
                name = text as String
                break
            }
        }
        var ef: CGPDFDictionaryRef?
        guard CGPDFDictionaryGetDictionary(spec, "EF", &ef), let ef else { return nil }
        var stream: CGPDFStreamRef?
        guard CGPDFDictionaryGetStream(ef, "F", &stream) || CGPDFDictionaryGetStream(ef, "UF", &stream), let stream else { return nil }
        var format = CGPDFDataFormat.raw
        guard let data = CGPDFStreamCopyData(stream, &format) else { return nil }
        return (name, data as Data)
    }
}
