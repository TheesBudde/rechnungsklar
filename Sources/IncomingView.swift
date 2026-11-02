import SwiftUI
import UniformTypeIdentifiers

struct IncomingView: View {
    @EnvironmentObject var store: DataStore
    @EnvironmentObject var nav: Navigation
    @EnvironmentObject var purchases: Purchases
    @State private var search = ""
    @State private var onlyOpen = false

    private var filtered: [IncomingInvoice] {
        store.incoming.filter { !onlyOpen || !$0.isPaid }
            .filter { search.isEmpty || $0.seller.name.localizedCaseInsensitiveContains(search) || $0.number.localizedCaseInsensitiveContains(search) }
            .sorted { ($0.issueDate ?? $0.importedAt) > ($1.issueDate ?? $1.importedAt) }
    }

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                List(selection: $nav.incomingID) {
                    ForEach(filtered) { invoice in
                        IncomingRow(invoice: invoice).tag(invoice.id)
                    }
                }
                .overlay {
                    if filtered.isEmpty && !store.incoming.isEmpty {
                        EmptyState(symbol: "checkmark.circle", title: "Nichts gefunden", message: onlyOpen ? "Alle Eingangsrechnungen sind bezahlt." : "Keine Rechnung passt zur Suche.")
                    }
                }
                Divider()
                Toggle("Nur unbezahlte zeigen", isOn: $onlyOpen)
                    .toggleStyle(.checkbox)
                    .font(.callout)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minWidth: 260, idealWidth: 300, maxWidth: 380)

            Group {
                if let invoice = store.incoming.first(where: { $0.id == nav.incomingID }) {
                    IncomingDetail(invoice: invoice).id(invoice.id)
                } else {
                    DropHint()
                }
            }
            .frame(minWidth: 580, maxWidth: .infinity, maxHeight: .infinity)
        }
        .searchable(text: $search, placement: .toolbar, prompt: "Lieferant, Nummer")
        .navigationTitle("E-Rechnungs-Eingang")
        .toolbar {
            ToolbarItemGroup {
                Button {
                    nav.requirePro(purchases) {
                        FileActions.save(Data(CSVExport.incoming(store.incoming).utf8), suggestedName: "Eingangsrechnungen.csv", type: .commaSeparatedText)
                    }
                } label: { Label("Export für die Steuerberatung", systemImage: "tablecells") }
                    .help("Alle Eingangsrechnungen als CSV-Datei (Pro)")
                Button { Importer.showOpenPanel(store: store, nav: nav) } label: { Label("E-Rechnung öffnen", systemImage: "plus") }
                    .help("E-Rechnung öffnen (⌘O)")
            }
        }
    }
}

struct IncomingRow: View {
    var invoice: IncomingInvoice

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(invoice.seller.name.isEmpty ? "Unbekannter Absender" : invoice.seller.name).fontWeight(.medium).lineLimit(1)
                Text("\(invoice.number) · \(DateText.format(invoice.issueDate))").font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 3) {
                Text(Money.format(invoice.dueAmount, currency: invoice.currency)).monospacedDigit()
                invoice.statusLabel
            }
        }
        .padding(.vertical, 4)
    }
}

/// Leerer Eingang: erklärt in zwei Sätzen, was hier passiert, und bietet ein Beispiel an
struct DropHint: View {
    @EnvironmentObject var store: DataStore
    @EnvironmentObject var nav: Navigation

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "tray.and.arrow.down").font(.system(size: 40, weight: .light)).foregroundStyle(Theme.accent)
            Text("E-Rechnungen lesbar machen").font(.title3.weight(.semibold))
            Text("Eine XRechnung ist eine XML-Datei, die man ohne passendes Programm nicht lesen kann. Zieh sie hierher – Rechnungsklar zeigt sie als normale Rechnung, rechnet die Summen nach und bewahrt das Original unverändert auf.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary).frame(maxWidth: 440)
            Text("XRechnung (CII und UBL) · ZUGFeRD · Factur-X · Peppol").font(.caption).foregroundStyle(.tertiary)
            HStack(spacing: 10) {
                Button("Datei öffnen …") { Importer.showOpenPanel(store: store, nav: nav) }
                    .buttonStyle(.borderedProminent)
                if store.incoming.isEmpty {
                    Button("Beispiel ansehen") {
                        if let sample = store.importSample() { nav.incomingID = sample.id }
                    }
                }
            }
            .padding(.top, 4)
        }
        .padding(36)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct IncomingDetail: View {
    @EnvironmentObject var store: DataStore
    @EnvironmentObject var nav: Navigation
    var invoice: IncomingInvoice
    @State private var confirmDelete = false

    /// Rechnet nach: Steuern je Satz ergeben die Steuersumme, Netto plus Steuer ergibt den Bruttobetrag
    private var sumsCheck: Bool {
        let taxSum = invoice.taxes.reduce(Decimal(0)) { $0 + $1.amount }
        let basisSum = invoice.taxes.reduce(Decimal(0)) { $0 + $1.basis }
        let taxesOK = invoice.taxes.isEmpty || (abs((taxSum - invoice.taxTotal).doubleValue) < 0.011 && abs((basisSum - invoice.netTotal).doubleValue) < 0.011)
        return taxesOK && abs((invoice.netTotal + invoice.taxTotal - invoice.grossTotal).doubleValue) < 0.011
    }

    private func money(_ value: Decimal) -> String { Money.format(value, currency: invoice.currency) }

    var body: some View {
        VStack(spacing: 0) {
            DetailHeader(title: "\(invoice.typeLabel) \(invoice.number)",
                         subtitle: "\(invoice.seller.name) · \(money(invoice.dueAmount)) · \(dueText)") {
                Menu {
                    Button("Lesbare Fassung als PDF sichern …") { savePDF() }
                    Button("Original sichern …") { saveOriginal() }
                    Button("Original im Finder zeigen") {
                        if let url = store.storedURL(of: invoice) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                    }
                    .disabled(store.storedURL(of: invoice) == nil)
                    Divider()
                    Button("Aus dem Archiv löschen …", role: .destructive) { confirmDelete = true }
                } label: { Label("Ablage", systemImage: "square.and.arrow.up") }
                .fixedSize()
                if !invoice.isCreditNote {
                    if invoice.isPaid {
                        Button("Als unbezahlt markieren") { setPaid(false) }
                    } else {
                        Button("Bezahlt") { setPaid(true) }.buttonStyle(.borderedProminent).help("Als bezahlt markieren")
                    }
                }
            }
            ScrollView {
                sheet
                    .padding(28)
                    .frame(maxWidth: 860)
                    .frame(maxWidth: .infinity)
            }
            .background(Color(nsColor: .underPageBackgroundColor))
        }
        .confirmationDialog("„\(invoice.number)“ aus dem Archiv löschen?", isPresented: $confirmDelete) {
            Button("Löschen", role: .destructive) {
                store.deleteIncoming(invoice)
                nav.incomingID = nil
            }
        } message: {
            Text("Auch die archivierte Originaldatei wird gelöscht. Eingangsrechnungen musst du in der Regel 8 Jahre aufbewahren – lösche nur Doppelte oder Irrläufer.")
        }
    }

    private var dueText: String {
        if invoice.isPaid { return "bezahlt am \(DateText.format(invoice.paidDate))" }
        if invoice.isOverdue() { return "überfällig seit \(DateText.format(invoice.dueDate))" }
        return invoice.dueDate == nil ? "ohne Fälligkeit" : "fällig am \(DateText.format(invoice.dueDate))"
    }

    private func setPaid(_ paid: Bool) {
        var changed = invoice
        changed.isPaid = paid
        changed.paidDate = paid ? Date() : nil
        store.updateIncoming(changed)
    }

    /// Die Rechnung als zusammenhängendes Blatt
    private var sheet: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 24) {
                party("Von", invoice.seller)
                party("An", invoice.buyer)
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 3) {
                    Text(money(invoice.dueAmount)).font(.system(size: 24, weight: .semibold)).monospacedDigit()
                    Text(dueText).font(.callout).foregroundStyle(invoice.isOverdue() ? Theme.overdue : .secondary)
                }
            }
            .padding(20)
            Divider()
            facts.padding(.horizontal, 20).padding(.vertical, 12)
            Divider()
            lines.padding(20)
            Divider()
            payment.padding(20)
            if !invoice.notes.isEmpty || !invoice.paymentTerms.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(invoice.notes, id: \.self) { Text($0) }
                    if !invoice.paymentTerms.isEmpty { Text(invoice.paymentTerms) }
                }
                .font(.callout).foregroundStyle(.secondary)
                .padding(20)
            }
        }
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.separator.opacity(0.6), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
        .textSelection(.enabled)
    }

    private func party(_ title: String, _ p: IncomingInvoice.Party) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary).padding(.bottom, 2)
            Text(p.name).fontWeight(.medium)
            ForEach(p.addressLines, id: \.self) { Text($0) }
            if !p.vatID.isEmpty { Text("USt-IdNr. \(p.vatID)").foregroundStyle(.secondary) }
            if !p.taxNumber.isEmpty { Text("Steuernr. \(p.taxNumber)").foregroundStyle(.secondary) }
            if !p.email.isEmpty { Text(p.email).foregroundStyle(.secondary) }
        }
        .font(.callout)
        .frame(minWidth: 180, alignment: .leading)
    }

    private var facts: some View {
        HStack(spacing: 28) {
            fact("Rechnungsdatum", DateText.format(invoice.issueDate))
            if invoice.serviceDate != nil { fact("Leistung", DateText.format(invoice.serviceDate)) }
            if !invoice.buyerReference.isEmpty { fact("Referenz", invoice.buyerReference) }
            if !invoice.precedingInvoice.isEmpty { fact("Bezug", invoice.precedingInvoice) }
            fact("Format", invoice.format)
            VStack(alignment: .leading, spacing: 2) {
                Text("Summen").font(.caption).foregroundStyle(.secondary)
                Label(sumsCheck ? "nachgerechnet" : "weichen ab", systemImage: sumsCheck ? "checkmark" : "exclamationmark.triangle")
                    .foregroundStyle(sumsCheck ? Theme.paid : Theme.overdue)
            }
            Spacer(minLength: 0)
        }
        .font(.callout)
    }

    private func fact(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value.isEmpty ? "–" : value).lineLimit(1)
        }
    }

    private var lines: some View {
        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 8) {
            GridRow {
                Text("Pos."); Text("Leistung")
                Text("Menge").gridColumnAlignment(.trailing)
                Text("Einzelpreis").gridColumnAlignment(.trailing)
                Text("USt").gridColumnAlignment(.trailing)
                Text("Netto").gridColumnAlignment(.trailing)
            }
            .font(.caption).foregroundStyle(.secondary)
            Divider()
            ForEach(invoice.lines) { line in
                GridRow(alignment: .firstTextBaseline) {
                    Text(line.position).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(line.name)
                        if !line.detail.isEmpty { Text(line.detail).font(.caption).foregroundStyle(.secondary) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Text("\(Money.quantity(line.quantity)) \(line.unit)")
                    Text(money(line.unitPrice))
                    Text(line.vatRate.map { Money.percent($0) } ?? "–")
                    Text(money(line.net))
                }
                .monospacedDigit()
            }
            Divider()
            totalRow("Summe netto", money(invoice.netTotal))
            ForEach(invoice.taxes) { tax in
                totalRow(tax.exemptionReason.isEmpty ? "USt \(Money.percent(tax.rate)) auf \(money(tax.basis))" : tax.exemptionReason, money(tax.amount))
            }
            totalRow("Gesamt", money(invoice.grossTotal), bold: true)
        }
        .font(.callout)
    }

    private func totalRow(_ label: String, _ value: String, bold: Bool = false) -> some View {
        GridRow {
            Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
            Text(label).gridCellColumns(4).frame(maxWidth: .infinity, alignment: .trailing)
                .foregroundStyle(bold ? .primary : .secondary).fontWeight(bold ? .semibold : .regular)
            Text(value).fontWeight(bold ? .semibold : .regular).monospacedDigit()
        }
    }

    private var giroPayload: String? {
        guard !invoice.isPaid, !invoice.isCreditNote, invoice.currency == "EUR" else { return nil }
        return GiroCode.payload(name: invoice.accountHolder.isEmpty ? invoice.seller.name : invoice.accountHolder, iban: invoice.iban, bic: invoice.bic,
                                amount: invoice.dueAmount, reference: invoice.paymentReference.isEmpty ? invoice.number : invoice.paymentReference)
    }

    private var payment: some View {
        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Überweisung").font(.headline)
                if invoice.iban.isEmpty {
                    Text("Die E-Rechnung enthält keine Bankverbindung.").foregroundStyle(.secondary)
                } else {
                    Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 6) {
                        copyRow("Empfänger", invoice.accountHolder.isEmpty ? invoice.seller.name : invoice.accountHolder)
                        copyRow("IBAN", IBAN.formatted(invoice.iban))
                        if !invoice.bic.isEmpty { copyRow("BIC", invoice.bic) }
                        copyRow("Betrag", money(invoice.dueAmount))
                        copyRow("Verwendungszweck", invoice.paymentReference.isEmpty ? invoice.number : invoice.paymentReference)
                    }
                    .font(.callout)
                }
            }
            Spacer(minLength: 0)
            if let payload = giroPayload {
                VStack(spacing: 6) {
                    GiroCodeView(payload: payload, size: 112)
                    Text("GiroCode – mit der\nBanking-App scannen").font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
            }
        }
    }

    private func copyRow(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            HStack(spacing: 6) {
                Text(value).monospacedDigit()
                Button { FileActions.copy(value.replacingOccurrences(of: label == "IBAN" ? " " : "\u{0}", with: "")) } label: { Image(systemName: "doc.on.doc") }
                    .buttonStyle(.borderless).foregroundStyle(.secondary).help("\(label) kopieren")
            }
        }
    }

    private func saveOriginal() {
        guard let url = store.storedURL(of: invoice), let data = try? Data(contentsOf: url) else { return }
        FileActions.save(data, suggestedName: invoice.originalFileName.isEmpty ? "\(invoice.number).xml" : invoice.originalFileName,
                         type: invoice.originalFileName.lowercased().hasSuffix(".pdf") ? .pdf : .xml)
    }

    private func savePDF() {
        let data = NSMutableData()
        var box = CGRect(origin: .zero, size: InvoicePage.size)
        guard let consumer = CGDataConsumer(data: data as CFMutableData), let context = CGContext(consumer: consumer, mediaBox: &box, nil) else { return }
        let renderer = ImageRenderer(content: IncomingPrintPage(invoice: invoice))
        renderer.proposedSize = ProposedViewSize(InvoicePage.size)
        renderer.render { _, draw in
            context.beginPDFPage(nil)
            draw(context)
            context.endPDFPage()
        }
        context.closePDF()
        FileActions.save(data as Data, suggestedName: "\(invoice.seller.name)_\(invoice.number)_lesbar.pdf", type: .pdf)
    }
}

/// Lesbare Fassung einer empfangenen E-Rechnung zum Ausdrucken oder Weitergeben
struct IncomingPrintPage: View {
    var invoice: IncomingInvoice

    private func money(_ value: Decimal) -> String { Money.format(value, currency: invoice.currency) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Lesbare Fassung einer E-Rechnung (\(invoice.format)). Rechtlich maßgeblich ist die Originaldatei „\(invoice.originalFileName)“.")
                .font(.system(size: 7)).foregroundStyle(Color(white: 0.5))
            Text("\(invoice.typeLabel) \(invoice.number)").font(.system(size: 18, weight: .semibold))
            HStack(alignment: .top) {
                party("Rechnungssteller", invoice.seller)
                Spacer()
                party("Rechnungsempfänger", invoice.buyer)
            }
            HStack(spacing: 24) {
                fact("Datum", DateText.format(invoice.issueDate))
                fact("Fällig", DateText.format(invoice.dueDate))
                fact("Leistung", DateText.format(invoice.serviceDate))
                fact("Referenz", invoice.buyerReference)
            }
            VStack(spacing: 0) {
                ForEach(invoice.lines) { line in
                    HStack(alignment: .firstTextBaseline) {
                        Text(line.position).frame(width: 22, alignment: .leading)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(line.name)
                            if !line.detail.isEmpty { Text(line.detail).font(.system(size: 7.5)).foregroundStyle(Color(white: 0.45)) }
                        }
                        Spacer()
                        Text("\(Money.quantity(line.quantity)) \(line.unit) × \(money(line.unitPrice))")
                        Text(money(line.net)).frame(width: 80, alignment: .trailing)
                    }
                    .padding(.vertical, 5)
                    Rectangle().fill(Color(white: 0.86)).frame(height: 0.5)
                }
            }
            .font(.system(size: 9))
            VStack(alignment: .trailing, spacing: 3) {
                Text("Netto \(money(invoice.netTotal))")
                ForEach(invoice.taxes) { Text("USt \(Money.percent($0.rate)): \(money($0.amount))") }
                Text("Zu zahlen \(money(invoice.dueAmount))").fontWeight(.semibold)
            }
            .font(.system(size: 10)).frame(maxWidth: .infinity, alignment: .trailing)
            if !invoice.iban.isEmpty {
                Text("Bankverbindung: \(invoice.accountHolder) · IBAN \(IBAN.formatted(invoice.iban))\(invoice.bic.isEmpty ? "" : " · BIC \(invoice.bic)")")
                    .font(.system(size: 9))
            }
            Spacer()
        }
        .padding(50)
        .frame(width: InvoicePage.size.width, height: InvoicePage.size.height, alignment: .topLeading)
        .background(Color.white)
        .foregroundStyle(Color(white: 0.1))
        .environment(\.colorScheme, .light)
    }

    private func party(_ title: String, _ p: IncomingInvoice.Party) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.system(size: 7.5, weight: .semibold)).foregroundStyle(Color(white: 0.45))
            Text(p.name).fontWeight(.medium)
            ForEach(p.addressLines, id: \.self) { Text($0) }
            if !p.vatID.isEmpty { Text("USt-IdNr. \(p.vatID)") }
        }
        .font(.system(size: 9))
    }

    private func fact(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.system(size: 7.5)).foregroundStyle(Color(white: 0.45))
            Text(value.isEmpty ? "–" : value).font(.system(size: 9))
        }
    }
}
