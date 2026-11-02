import AppKit
import SwiftUI

/// Eine A4-Seite der Rechnung. Wird für die Vorschau in der App und für den PDF-Export verwendet.
/// Maße in Punkt (1 pt = 0,3528 mm); Anschriftfeld nach DIN 5008 Form B.
struct InvoicePage: View {
    static let size = CGSize(width: 595.28, height: 841.89)
    static let margin: CGFloat = 57 // ca. 20 mm

    var invoice: Invoice
    var company: Company
    var items: ArraySlice<LineItem>
    var pageIndex: Int
    var pageCount: Int
    /// Hinweis „Erstellt mit Rechnungsklar“ in der kostenlosen Version
    var branding = false

    private var seller: Company { invoice.seller ?? company }
    private var isFirst: Bool { pageIndex == 0 }
    private var isLast: Bool { pageIndex == pageCount - 1 }
    private var sign: Decimal { invoice.isCancellation ? -1 : 1 }
    private let ink = Color(white: 0.1)
    private let muted = Color(white: 0.42)
    private let rule = Color(white: 0.86)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if isFirst { header } else { continuationHeader }
            itemTable
            if isLast { totals; closing }
            Spacer(minLength: 0)
            footer
        }
        .padding(.horizontal, Self.margin)
        .padding(.top, 42)
        .padding(.bottom, 28)
        .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
        .background(Color.white)
        .foregroundStyle(ink)
        .environment(\.colorScheme, .light)
    }

    private func money(_ value: Decimal) -> String { Money.format(sign * value) }

    // MARK: Kopf

    private var letterhead: some View {
        HStack(alignment: .top) {
            if let logo = LogoImage.image(seller.logo) {
                logo.resizable().scaledToFit().frame(maxWidth: 170, maxHeight: 46, alignment: .topLeading)
            } else {
                Text(seller.name.isEmpty ? "Dein Firmenname" : seller.name).font(.system(size: 16, weight: .semibold))
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 1.5) {
                if seller.logo != nil { Text(seller.name).fontWeight(.medium).foregroundStyle(ink) }
                Text(seller.street)
                Text("\(seller.zip) \(seller.city)")
                if !seller.phone.isEmpty { Text(seller.phone).padding(.top, 3) }
                if !seller.email.isEmpty { Text(seller.email) }
                if !seller.website.isEmpty { Text(seller.website) }
            }
            .font(.system(size: 7.8))
            .foregroundStyle(muted)
        }
        .frame(height: 74, alignment: .top)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            letterhead

            HStack(alignment: .top, spacing: 20) {
                // Anschriftfeld: 85 × 45 mm, mit Rücksendezeile
                VStack(alignment: .leading, spacing: 1.5) {
                    Text(seller.addressLine)
                        .font(.system(size: 6.5)).foregroundStyle(muted).lineLimit(1)
                        .padding(.bottom, 6)
                    Text(invoice.customer.name.isEmpty ? "Empfänger" : invoice.customer.name).font(.system(size: 10, weight: .medium))
                    if !invoice.customer.contactPerson.isEmpty { Text(invoice.customer.contactPerson) }
                    Text(invoice.customer.street)
                    Text("\(invoice.customer.zip) \(invoice.customer.city)")
                    if invoice.customer.country != "DE" && !invoice.customer.country.isEmpty {
                        Text(Locale(identifier: "de_DE").localizedString(forRegionCode: invoice.customer.country)?.uppercased() ?? invoice.customer.country)
                    }
                }
                .font(.system(size: 10))
                .frame(width: 230, height: 110, alignment: .topLeading)

                Spacer()

                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 3) {
                    infoRow(invoice.isCancellation ? "Storno-Nr." : "Rechnungsnr.", invoice.displayNumber, bold: true)
                    infoRow("Datum", DateText.format(invoice.issueDate))
                    if invoice.isCancellation {
                        infoRow("zur Rechnung", invoice.referenceNumber)
                        infoRow("vom", DateText.format(invoice.referenceDate))
                    } else {
                        infoRow(Calendar.current.isDate(invoice.serviceStart, inSameDayAs: invoice.serviceEnd) ? "Leistungsdatum" : "Leistungszeitraum",
                                invoice.servicePeriodText)
                        infoRow("Zahlbar bis", DateText.format(invoice.dueDate))
                    }
                    if !invoice.customer.buyerReference.isEmpty { infoRow("Ihre Referenz", invoice.customer.buyerReference) }
                    if !invoice.customer.vatID.isEmpty { infoRow("Ihre USt-IdNr.", invoice.customer.vatID) }
                }
                .font(.system(size: 8.5))
                .fixedSize()
                .padding(.top, 14)
            }
            .padding(.top, 26)

            Text(invoice.isLocked ? invoice.title : "\(invoice.title) (Entwurf)")
                .font(.system(size: 18, weight: .semibold))
                .padding(.top, 22)
            if !invoice.subject.isEmpty {
                Text(invoice.subject).font(.system(size: 10)).foregroundStyle(muted).padding(.top, 2)
            }
            if !invoice.intro.isEmpty {
                Text(invoice.intro).font(.system(size: 9.5)).padding(.top, 12).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.bottom, 14)
    }

    private func infoRow(_ label: String, _ value: String, bold: Bool = false) -> some View {
        GridRow {
            Text(label).foregroundStyle(muted)
            Text(value).fontWeight(bold ? .semibold : .regular).monospacedDigit()
        }
    }

    private var continuationHeader: some View {
        HStack {
            Text(seller.name).font(.system(size: 9.5, weight: .semibold))
            Spacer()
            Text("\(invoice.title) \(invoice.displayNumber) · Seite \(pageIndex + 1)").font(.system(size: 8.5)).foregroundStyle(muted)
        }
        .padding(.bottom, 18)
    }

    // MARK: Positionen

    private var showsVAT: Bool { invoice.taxMode == .regular && Set(invoice.items.map(\.vatRate)).count > 1 }

    private var itemTable: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Text("Pos.").frame(width: 24, alignment: .leading)
                Text("Leistung").frame(maxWidth: .infinity, alignment: .leading)
                Text("Menge").frame(width: 62, alignment: .trailing)
                Text("Einzelpreis").frame(width: 62, alignment: .trailing)
                if showsVAT { Text("USt").frame(width: 30, alignment: .trailing) }
                Text("Betrag").frame(width: 68, alignment: .trailing)
            }
            .font(.system(size: 7.5, weight: .medium))
            .foregroundStyle(muted)
            .padding(.vertical, 5)
            .overlay(alignment: .bottom) { Rectangle().fill(ink).frame(height: 0.7) }

            ForEach(Array(items.enumerated()), id: \.element.id) { offset, item in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(items.startIndex + offset + 1)").frame(width: 24, alignment: .leading).foregroundStyle(muted)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title.isEmpty ? "Neue Position" : item.title).fontWeight(.medium)
                        if !item.detail.isEmpty {
                            Text(item.detail).font(.system(size: 8)).foregroundStyle(muted).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Text("\(Money.quantity(item.quantity)) \(item.unit.label)").frame(width: 62, alignment: .trailing)
                    Text(Money.format(item.unitPrice)).frame(width: 62, alignment: .trailing)
                    if showsVAT { Text("\(Money.quantity(item.vatRate)) %").frame(width: 30, alignment: .trailing) }
                    Text(money(item.net)).frame(width: 68, alignment: .trailing)
                }
                .font(.system(size: 9))
                .monospacedDigit()
                .padding(.vertical, 6)
                .overlay(alignment: .bottom) { Rectangle().fill(rule).frame(height: 0.5) }
            }
        }
    }

    // MARK: Summen und Abschluss

    private var totals: some View {
        HStack(alignment: .top) {
            if let payload = giroPayload {
                HStack(alignment: .top, spacing: 8) {
                    GiroCodeView(payload: payload, size: 62)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Mit GiroCode bezahlen").font(.system(size: 7.5, weight: .semibold))
                        Text("Mit der Banking-App scannen – Betrag und Verwendungszweck sind schon ausgefüllt.")
                            .font(.system(size: 7)).foregroundStyle(muted).frame(width: 118, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.top, 10)
            }
            Spacer()
            Grid(alignment: .trailing, horizontalSpacing: 18, verticalSpacing: 4) {
                GridRow {
                    Text("Summe netto").foregroundStyle(muted)
                    Text(money(invoice.netTotal))
                }
                ForEach(invoice.taxGroups) { group in
                    GridRow {
                        Text(taxLabel(group)).foregroundStyle(muted)
                        Text(money(group.amount))
                    }
                }
                GridRow {
                    Rectangle().fill(ink).frame(height: 0.7).gridCellColumns(2)
                }
                GridRow {
                    Text(invoice.isCancellation ? "Stornobetrag" : "Rechnungsbetrag").font(.system(size: 10.5, weight: .semibold))
                    Text(money(invoice.grossTotal)).font(.system(size: 10.5, weight: .semibold))
                }
            }
            .font(.system(size: 9))
            .monospacedDigit()
            .frame(width: 236, alignment: .trailing)
            .padding(.top, 10)
        }
    }

    private func taxLabel(_ group: TaxGroup) -> String {
        switch group.category {
        case "E": "Umsatzsteuer (§ 19 UStG)"
        case "AE": "Umsatzsteuer (Reverse Charge)"
        default: "zzgl. \(Money.percent(group.rate)) USt auf \(money(group.basis))"
        }
    }

    /// GiroCode nur auf Rechnungen, nicht auf Stornos
    private var giroPayload: String? {
        guard !invoice.isCancellation else { return nil }
        return GiroCode.payload(name: seller.owner.isEmpty ? seller.name : seller.owner, iban: seller.iban, bic: seller.bic,
                                amount: invoice.grossTotal, reference: invoice.displayNumber)
    }

    private var closing: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let notice = invoice.taxMode.notice {
                Text(notice + (invoice.taxMode == .reverseCharge && !invoice.customer.vatID.isEmpty ? " USt-IdNr. des Leistungsempfängers: \(invoice.customer.vatID)" : ""))
                    .fontWeight(.medium)
            }
            if invoice.isCancellation {
                Text("Die Rechnung \(invoice.referenceNumber) ist damit vollständig aufgehoben. Bereits gezahlte Beträge erstatten wir auf Ihr Konto.")
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Bitte überweisen Sie den Rechnungsbetrag ohne Abzug bis zum \(DateText.format(invoice.dueDate)) auf das unten genannte Konto. Verwendungszweck: \(invoice.displayNumber).")
                    .fixedSize(horizontal: false, vertical: true)
                if !seller.closingText.isEmpty { Text(seller.closingText) }
            }
            if !seller.owner.isEmpty { Text(seller.owner).padding(.top, 4) }
        }
        .font(.system(size: 9.5))
        .padding(.top, 22)
    }

    // MARK: Fuß

    private var footer: some View {
        VStack(spacing: 6) {
            Rectangle().fill(rule).frame(height: 0.5)
            HStack(alignment: .top, spacing: 12) {
                footerColumn([seller.name, seller.street, "\(seller.zip) \(seller.city)"])
                footerColumn([seller.phone, seller.email, seller.website])
                footerColumn([seller.taxNumber.isEmpty ? "" : "Steuernr. \(seller.taxNumber)", seller.vatID.isEmpty ? "" : "USt-IdNr. \(seller.vatID)",
                              seller.owner.isEmpty ? "" : "Inhaber/in: \(seller.owner)"])
                footerColumn([seller.bankName, seller.iban.isEmpty ? "" : "IBAN \(IBAN.formatted(seller.iban))", seller.bic.isEmpty ? "" : "BIC \(seller.bic)"])
            }
            HStack {
                if branding { Text("Erstellt mit Rechnungsklar") }
                Spacer()
                if pageCount > 1 { Text("Seite \(pageIndex + 1) von \(pageCount)") }
            }
            .font(.system(size: 6.5))
            .foregroundStyle(Color(white: 0.62))
        }
    }

    private func footerColumn(_ lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 1.5) {
            ForEach(Array(lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.enumerated()), id: \.offset) { _, line in
                Text(line).lineLimit(1).minimumScaleFactor(0.8)
            }
        }
        .font(.system(size: 6.8))
        .foregroundStyle(muted)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Seitenumbruch und PDF

enum InvoiceLayout {
    /// Teilt die Positionen auf Seiten auf. Grobe Schätzung über Zeilen, die für übliche Rechnungen gut passt.
    static func pages(for items: [LineItem]) -> [ArraySlice<LineItem>] {
        guard !items.isEmpty else { return [items[...]] }
        func weight(_ item: LineItem) -> Int { 2 + (item.detail.isEmpty ? 0 : 1 + item.detail.count / 60) + (item.title.count > 55 ? 1 : 0) }
        // Eine Einheit ≈ 11 pt: Zeile ≈ 22 pt, je Beschreibungszeile ≈ 11 pt; Summen und Zahlungshinweis ≈ 200 pt
        let firstCapacity = 33, nextCapacity = 62, totalsWeight = 18
        var pages: [ArraySlice<LineItem>] = []
        var start = 0
        var used = 0
        var capacity = firstCapacity
        for (index, item) in items.enumerated() {
            let w = weight(item)
            if used + w > capacity && index > start {
                pages.append(items[start..<index])
                start = index
                used = 0
                capacity = nextCapacity
            }
            used += w
        }
        // Summen und Zahlungshinweis müssen noch auf die letzte Seite passen
        if used + totalsWeight > capacity && items.count - start > 1 {
            let last = items.count - 1
            pages.append(items[start..<last])
            pages.append(items[last..<items.count])
        } else {
            pages.append(items[start..<items.count])
        }
        return pages
    }
}

@MainActor
enum InvoicePDF {
    static func data(for invoice: Invoice, company: Company, branding: Bool = false) -> Data {
        let pages = InvoiceLayout.pages(for: invoice.items)
        let data = NSMutableData()
        var box = CGRect(origin: .zero, size: InvoicePage.size)
        let seller = invoice.seller ?? company
        let info: [CFString: Any] = [
            kCGPDFContextTitle: "\(invoice.title) \(invoice.displayNumber)",
            kCGPDFContextAuthor: seller.name,
            kCGPDFContextCreator: "Rechnungsklar",
            kCGPDFContextSubject: invoice.subject,
        ]
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &box, info as CFDictionary) else { return Data() }
        for (index, slice) in pages.enumerated() {
            let renderer = ImageRenderer(content: InvoicePage(invoice: invoice, company: company, items: slice, pageIndex: index,
                                                              pageCount: pages.count, branding: branding))
            renderer.proposedSize = ProposedViewSize(InvoicePage.size)
            renderer.render { _, draw in
                context.beginPDFPage(nil)
                draw(context)
                context.endPDFPage()
            }
        }
        context.closePDF()
        return data as Data
    }
}

/// Alle Seiten untereinander, wie in einem Dokumentbetrachter
struct InvoicePreview: View {
    var invoice: Invoice
    var company: Company
    var branding = false

    var body: some View {
        GeometryReader { geo in
            let scale = min(1.2, max(0.4, (geo.size.width - 56) / InvoicePage.size.width))
            ScrollView {
                VStack(spacing: 22) {
                    let pages = InvoiceLayout.pages(for: invoice.items)
                    ForEach(Array(pages.enumerated()), id: \.offset) { index, slice in
                        InvoicePage(invoice: invoice, company: company, items: slice, pageIndex: index, pageCount: pages.count, branding: branding)
                            .scaleEffect(scale, anchor: .topLeading)
                            .frame(width: InvoicePage.size.width * scale, height: InvoicePage.size.height * scale, alignment: .topLeading)
                            .shadow(color: .black.opacity(0.12), radius: 1, y: 0)
                            .shadow(color: .black.opacity(0.10), radius: 10, y: 4)
                    }
                }
                .padding(28)
                .frame(maxWidth: .infinity)
            }
            .background(Color(nsColor: .underPageBackgroundColor))
        }
    }
}
