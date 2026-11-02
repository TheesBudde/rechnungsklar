import SwiftUI
import UniformTypeIdentifiers

struct InvoicesView: View {
    @EnvironmentObject var store: DataStore
    @EnvironmentObject var nav: Navigation
    @EnvironmentObject var purchases: Purchases
    var filter: InvoiceFilter
    @State private var search = ""

    /// Entwürfe oben, danach die neuesten zuerst
    private var filtered: [Invoice] {
        store.invoices.filter { filter.matches($0) }
            .filter { invoice in
                search.isEmpty || invoice.customer.name.localizedCaseInsensitiveContains(search)
                    || invoice.number.localizedCaseInsensitiveContains(search) || invoice.subject.localizedCaseInsensitiveContains(search)
            }
            .sorted { a, b in
                if (a.status == .draft) != (b.status == .draft) { return a.status == .draft }
                if a.issueDate != b.issueDate { return a.issueDate > b.issueDate }
                return a.number > b.number
            }
    }

    var body: some View {
        HSplitView {
            List(selection: $nav.invoiceID) {
                ForEach(filtered) { invoice in
                    InvoiceRow(invoice: invoice).tag(invoice.id)
                        .contextMenu {
                            Button("Duplizieren") { nav.show(store.duplicate(invoice)) }
                            if invoice.awaitsPayment { Button("Als bezahlt markieren") { store.setPaid(invoice, paid: true) } }
                            if invoice.status == .draft {
                                Divider()
                                Button("Entwurf löschen", role: .destructive) { store.deleteDraft(invoice) }
                            }
                        }
                }
            }
            .overlay {
                if filtered.isEmpty {
                    EmptyState(symbol: filter.symbol, title: search.isEmpty ? emptyTitle : "Nichts gefunden",
                               message: search.isEmpty ? emptyMessage : "Keine Rechnung passt zu „\(search)“.")
                }
            }
            .frame(minWidth: 260, idealWidth: 300, maxWidth: 380)

            Group {
                if let invoice = store.invoice(id: nav.invoiceID) {
                    InvoiceDetail(invoiceID: invoice.id).id(invoice.id)
                } else {
                    EmptyState(symbol: "doc.richtext", title: "Keine Rechnung ausgewählt",
                               message: "Wähle links eine Rechnung oder lege mit ⌘N eine neue an.")
                }
            }
            .frame(minWidth: 580, maxWidth: .infinity, maxHeight: .infinity)
        }
        .searchable(text: $search, placement: .toolbar, prompt: "Kunde, Nummer, Betreff")
        .navigationTitle(filter.title)
        .toolbar {
            ToolbarItemGroup {
                Button { nav.requirePro(purchases) { exportCSV() } } label: { Label("Export für die Steuerberatung", systemImage: "tablecells") }
                    .help("Alle festgeschriebenen Rechnungen als CSV-Datei (Pro)")
                Button { nav.newInvoice(in: store) } label: { Label("Neue Rechnung", systemImage: "square.and.pencil") }
                    .help("Neue Rechnung (⌘N)")
            }
        }
    }

    private var emptyTitle: String {
        switch filter {
        case .all: "Noch keine Rechnungen"
        case .draft: "Keine Entwürfe"
        case .open: "Nichts offen"
        case .overdue: "Nichts überfällig"
        case .paid: "Noch nichts bezahlt"
        }
    }

    private var emptyMessage: String {
        switch filter {
        case .all, .draft: "Mit ⌘N legst du eine neue Rechnung an."
        case .open: "Alle festgeschriebenen Rechnungen sind bezahlt."
        case .overdue: "Alle offenen Rechnungen sind noch innerhalb der Zahlungsfrist."
        case .paid: "Markiere eine Rechnung als bezahlt, sobald das Geld da ist."
        }
    }

    private func exportCSV() {
        FileActions.save(Data(CSVExport.outgoing(store.invoices).utf8), suggestedName: "Ausgangsrechnungen.csv", type: .commaSeparatedText)
    }
}

struct InvoiceRow: View {
    var invoice: Invoice

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(invoice.customer.name.isEmpty ? "Ohne Empfänger" : invoice.customer.name).fontWeight(.medium).lineLimit(1)
                Text(invoice.status == .draft ? (invoice.subject.isEmpty ? "Entwurf" : invoice.subject) : "\(invoice.number) · \(DateText.format(invoice.issueDate))")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 3) {
                Text(Money.format(invoice.signedGross)).monospacedDigit()
                    .strikethrough(invoice.status == .cancelled && !invoice.isCancellation, color: .secondary)
                invoice.statusLabel
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Detail

struct InvoiceDetail: View {
    @EnvironmentObject var store: DataStore
    @EnvironmentObject var nav: Navigation
    @EnvironmentObject var purchases: Purchases
    var invoiceID: Invoice.ID
    @State private var preview = false
    @State private var confirmFinalize = false
    @State private var confirmCancel = false

    private var invoice: Binding<Invoice> {
        Binding(get: { store.invoice(id: invoiceID) ?? Invoice() }, set: { store.update($0) })
    }

    private var branding: Bool { !purchases.isPro }

    var body: some View {
        let current = invoice.wrappedValue
        VStack(spacing: 0) {
            DetailHeader(title: current.isLocked ? "\(current.title) \(current.number)" : "Neue Rechnung", subtitle: subtitle(current)) {
                if current.isLocked { lockedActions(current) } else { draftActions(current) }
            }
            if let note = relationNote(current) { note }
            if current.isLocked || preview {
                InvoicePreview(invoice: current, company: store.company, branding: branding)
            } else {
                InvoiceEditor(invoice: invoice)
            }
        }
        .confirmationDialog("Rechnung festschreiben?", isPresented: $confirmFinalize) {
            Button("Als \(store.peekNumber(for: current.issueDate)) festschreiben") { store.finalize(current) }
        } message: {
            Text("Die Rechnung bekommt die nächste fortlaufende Nummer und lässt sich danach nicht mehr ändern – so verlangen es die Regeln für ordnungsgemäße Buchführung (GoBD). Fehler korrigierst du später mit einem Storno.")
        }
        .confirmationDialog("Rechnung \(current.number) stornieren?", isPresented: $confirmCancel) {
            Button("Stornorechnung erstellen", role: .destructive) {
                if let storno = store.cancel(current) { nav.show(storno) }
            }
        } message: {
            Text("Es entsteht eine Stornorechnung mit der Nummer \(store.peekNumber()), die diese Rechnung vollständig aufhebt. Schick sie deinem Kunden, damit seine Buchhaltung Bescheid weiß.")
        }
    }

    private func subtitle(_ invoice: Invoice) -> String {
        let customer = invoice.customer.name.isEmpty ? "Noch kein Empfänger" : invoice.customer.name
        return "\(customer) · \(Money.format(invoice.signedGross)) · \(invoice.statusText)"
    }

    /// Verweis zwischen Rechnung und Storno, mit Sprung zum Gegenstück
    private func relationNote(_ invoice: Invoice) -> AnyView? {
        let text: String
        let target: String
        if invoice.isCancellation {
            text = "Diese Stornorechnung hebt die Rechnung \(invoice.referenceNumber) vom \(DateText.format(invoice.referenceDate)) auf."
            target = invoice.referenceNumber
        } else if !invoice.cancelledBy.isEmpty {
            text = "Diese Rechnung wurde mit \(invoice.cancelledBy) storniert."
            target = invoice.cancelledBy
        } else {
            return nil
        }
        return AnyView(
            HStack {
                Image(systemName: "arrow.uturn.backward").foregroundStyle(.secondary)
                Text(text).font(.callout)
                Spacer()
                if let other = store.invoices.first(where: { $0.number == target }) {
                    Button("\(other.title) zeigen") { nav.show(other) }.buttonStyle(.link)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .background(Color.secondary.opacity(0.07))
        )
    }

    @ViewBuilder private func draftActions(_ current: Invoice) -> some View {
        Picker("Ansicht", selection: $preview) {
            Text("Bearbeiten").tag(false)
            Text("Vorschau").tag(true)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
        Menu {
            Button("Duplizieren") { nav.show(store.duplicate(current)) }
            Divider()
            Button("Entwurf löschen", role: .destructive) {
                store.deleteDraft(current)
                nav.invoiceID = nil
            }
        } label: { Image(systemName: "ellipsis.circle") }
        .menuIndicator(.hidden)
        .fixedSize()
        let blocking = InvoiceCheck.blocking(for: current, company: store.company)
        Button("Festschreiben …") {
            if purchases.canFinalize(finalizedSoFar: store.finalizedCount) { confirmFinalize = true } else { nav.showPaywall = true }
        }
        .buttonStyle(.borderedProminent)
        .disabled(!blocking.isEmpty)
        .help(blocking.isEmpty ? "Nummer vergeben und Rechnung abschließen" : "Es fehlen noch \(blocking.count) Angaben – siehe unten")
    }

    @ViewBuilder private func lockedActions(_ current: Invoice) -> some View {
        Menu {
            Button("PDF sichern …") {
                FileActions.save(pdf(current), suggestedName: current.fileBaseName + ".pdf", type: .pdf)
            }
            Button("XRechnung sichern …") {
                FileActions.save(xml(current), suggestedName: current.fileBaseName + "_XRechnung.xml", type: .xml)
            }
            Button("PDF und XRechnung in einen Ordner …") {
                FileActions.saveAll([(current.fileBaseName + ".pdf", pdf(current)), (current.fileBaseName + "_XRechnung.xml", xml(current))])
            }
            Divider()
            Button("Drucken …") { FileActions.print(pdf(current), jobTitle: "\(current.title) \(current.number)") }
            Button("Duplizieren") { nav.show(store.duplicate(current)) }
            if current.status == .paid {
                Button("Wieder als offen markieren") { store.setPaid(current, paid: false) }
            }
            if current.kind == .invoice && current.cancelledBy.isEmpty && current.status != .cancelled {
                Divider()
                Button("Stornieren …", role: .destructive) { confirmCancel = true }
            }
        } label: { Label("Ablage", systemImage: "square.and.arrow.up") }
        .fixedSize()
        Button { send(current) } label: { Label("Senden", systemImage: "paperplane") }
            .buttonStyle(.bordered)
        if current.awaitsPayment {
            if current.isOverdue() {
                Button("Erinnern …") { nav.requirePro(purchases) { nav.reminderFor = current } }
            }
            Button("Bezahlt") { store.setPaid(current, paid: true) }
                .buttonStyle(.borderedProminent)
                .help("Als bezahlt markieren")
        }
    }

    private func pdf(_ invoice: Invoice) -> Data { InvoicePDF.data(for: invoice, company: store.company, branding: branding) }
    private func xml(_ invoice: Invoice) -> Data { Data(XRechnungWriter.xml(for: invoice, seller: store.company).utf8) }

    private func send(_ invoice: Invoice) {
        let seller = invoice.seller ?? store.company
        let attachments = [FileActions.temporaryFile(pdf(invoice), name: invoice.fileBaseName + ".pdf"),
                           FileActions.temporaryFile(xml(invoice), name: invoice.fileBaseName + "_XRechnung.xml")].compactMap { $0 }
        let greeting = invoice.customer.contactPerson.isEmpty ? "Guten Tag" : "Hallo \(invoice.customer.contactPerson)"
        let sign = seller.owner.isEmpty ? seller.name : seller.owner
        let body: String
        if invoice.isCancellation {
            body = """
            \(greeting),

            anbei erhalten Sie die Stornorechnung \(invoice.number). Sie hebt die Rechnung \(invoice.referenceNumber) vom \(DateText.format(invoice.referenceDate)) vollständig auf.

            Die Stornorechnung liegt als E-Rechnung (XRechnung) und als PDF bei.

            Viele Grüße
            \(sign)
            """
        } else {
            body = """
            \(greeting),

            anbei erhalten Sie die Rechnung \(invoice.number) über \(Money.format(invoice.grossTotal)), zahlbar bis zum \(DateText.format(invoice.dueDate)).

            Die Rechnung liegt als E-Rechnung im Format XRechnung bei, dazu als PDF zum Lesen. Mit dem GiroCode auf dem PDF können Sie direkt aus Ihrer Banking-App bezahlen.

            Viele Grüße
            \(sign)
            """
        }
        FileActions.compose(to: invoice.customer.email, subject: "\(invoice.title) \(invoice.number) – \(seller.name)", body: body, attachments: attachments)
    }
}

// MARK: - Editor

struct InvoiceEditor: View {
    @EnvironmentObject var store: DataStore
    @Binding var invoice: Invoice
    @State private var editingCustomer = false

    var body: some View {
        let issues = InvoiceCheck.issues(for: invoice, company: store.company)
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                recipient
                details
                items
                checklist(issues)
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 26)
            .frame(maxWidth: 780, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .textFieldStyle(.roundedBorder)
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text).font(.headline)
    }

    // Empfänger

    private var recipient: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                sectionTitle("Empfänger")
                Spacer()
                Menu("Aus Kunden wählen") {
                    ForEach(store.customers.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }) { customer in
                        Button(customer.name) { invoice.customer = customer; editingCustomer = false }
                    }
                    if !store.customers.isEmpty { Divider() }
                    Button("Neuer Empfänger") { invoice.customer = Customer(); editingCustomer = true }
                }
                .fixedSize()
            }
            if editingCustomer || invoice.customer.name.isEmpty {
                customerFields
            } else {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(invoice.customer.name).fontWeight(.medium)
                        if !invoice.customer.contactPerson.isEmpty { Text(invoice.customer.contactPerson) }
                        Text(invoice.customer.street)
                        Text("\(invoice.customer.zip) \(invoice.customer.city)")
                        Text(invoice.customer.email).foregroundStyle(.secondary).padding(.top, 2)
                    }
                    Spacer()
                    Button("Ändern") { editingCustomer = true }.buttonStyle(.link)
                }
                .padding(14)
                .background(Theme.panel, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.separator.opacity(0.6), lineWidth: 0.5))
            }
        }
    }

    private var customerFields: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
            GridRow {
                Field("Firma oder Name") { TextField("", text: $invoice.customer.name) }.gridCellColumns(2)
                Field("Ansprechperson") { TextField("", text: $invoice.customer.contactPerson) }
            }
            GridRow {
                Field("Straße und Hausnummer") { TextField("", text: $invoice.customer.street) }.gridCellColumns(2)
                Field("Land (z. B. DE, AT, NL)") { TextField("", text: $invoice.customer.country) }
            }
            GridRow {
                Field("PLZ") { TextField("", text: $invoice.customer.zip) }
                Field("Ort") { TextField("", text: $invoice.customer.city) }.gridCellColumns(2)
            }
            GridRow {
                Field("E-Mail für Rechnungen") { TextField("", text: $invoice.customer.email) }.gridCellColumns(2)
                Field("USt-IdNr. (EU-Kunden)") { TextField("", text: $invoice.customer.vatID) }
            }
            GridRow {
                Field("Leitweg-ID oder Bestellnummer") {
                    TextField("", text: $invoice.customer.buyerReference, prompt: Text("bei Behörden Pflicht"))
                }
                .gridCellColumns(3)
            }
        }
    }

    // Angaben

    private var details: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Angaben")
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 12) {
                GridRow {
                    Field("Betreff") { TextField("", text: $invoice.subject, prompt: Text("z. B. Webdesign Oktober")) }.gridCellColumns(2)
                    Field("Umsatzsteuer") {
                        Picker("", selection: $invoice.taxMode) { ForEach(TaxMode.allCases) { Text($0.label).tag($0) } }
                            .labelsHidden()
                    }
                }
                GridRow {
                    Field("Rechnungsdatum") { DatePicker("", selection: $invoice.issueDate, displayedComponents: .date).labelsHidden().fixedSize() }
                    Field("Leistung von – bis") {
                        HStack(spacing: 6) {
                            DatePicker("", selection: $invoice.serviceStart, displayedComponents: .date).labelsHidden().fixedSize()
                            Text("–").foregroundStyle(.secondary)
                            DatePicker("", selection: $invoice.serviceEnd, displayedComponents: .date).labelsHidden().fixedSize()
                        }
                    }
                    Field("Zahlbar bis") {
                        HStack(spacing: 6) {
                            DatePicker("", selection: $invoice.dueDate, displayedComponents: .date).labelsHidden().fixedSize()
                            Menu("Frist") {
                                ForEach([7, 14, 30], id: \.self) { days in
                                    Button("\(days) Tage nach Rechnungsdatum") {
                                        invoice.dueDate = Calendar.current.date(byAdding: .day, value: days, to: invoice.issueDate) ?? invoice.dueDate
                                    }
                                }
                            }
                            .menuStyle(.borderlessButton)
                            .fixedSize()
                        }
                    }
                }
                GridRow {
                    Field("Einleitung") { TextField("", text: $invoice.intro, axis: .vertical).lineLimit(1...3) }.gridCellColumns(3)
                }
            }
        }
    }

    // Positionen

    private var showsVAT: Bool { invoice.taxMode == .regular }

    private var items: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionTitle("Positionen").padding(.bottom, 10)
            HStack(spacing: 8) {
                Text("Leistung").frame(maxWidth: .infinity, alignment: .leading)
                Text("Menge").frame(width: 64, alignment: .trailing)
                Text("Einheit").frame(width: 112, alignment: .leading)
                Text("Einzelpreis").frame(width: 86, alignment: .trailing)
                if showsVAT { Text("USt").frame(width: 78, alignment: .leading) }
                Text("Betrag").frame(width: 86, alignment: .trailing)
                Color.clear.frame(width: 18)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.bottom, 6)
            Divider()
            ForEach($invoice.items) { $item in
                LineItemRow(item: $item, showsVAT: showsVAT) { invoice.items.removeAll { $0.id == item.id } }
                Divider()
            }
            HStack(spacing: 14) {
                Button {
                    let last = invoice.items.last
                    invoice.items.append(LineItem(unit: last?.unit ?? .hour, unitPrice: 0, vatRate: showsVAT ? (last?.vatRate ?? 19) : 0))
                } label: { Label("Position", systemImage: "plus") }
                let templates = store.previousItems
                if !templates.isEmpty {
                    Menu("Aus früheren Positionen") {
                        ForEach(templates) { template in
                            Button("\(template.title) – \(Money.format(template.unitPrice)) je \(template.unit.label)") {
                                var copy = template
                                copy.id = UUID()
                                copy.quantity = 1
                                if !showsVAT { copy.vatRate = 0 }
                                if invoice.items.count == 1, invoice.items[0].title.isEmpty, invoice.items[0].unitPrice == 0 {
                                    invoice.items = [copy]
                                } else {
                                    invoice.items.append(copy)
                                }
                            }
                        }
                    }
                    .fixedSize()
                }
                Spacer()
            }
            .buttonStyle(.borderless)
            .padding(.top, 10)
            totals.padding(.top, 14)
        }
    }

    private var totals: some View {
        HStack {
            Spacer()
            Grid(alignment: .trailing, horizontalSpacing: 24, verticalSpacing: 5) {
                GridRow {
                    Text("Netto").foregroundStyle(.secondary)
                    Text(Money.format(invoice.netTotal))
                }
                ForEach(invoice.taxGroups) { group in
                    GridRow {
                        Text(taxLabel(group)).foregroundStyle(.secondary)
                        Text(Money.format(group.amount))
                    }
                }
                GridRow { Divider().gridCellColumns(2) }
                GridRow {
                    Text("Gesamt").fontWeight(.semibold)
                    Text(Money.format(invoice.grossTotal)).fontWeight(.semibold)
                }
            }
            .monospacedDigit()
            .frame(width: 280)
        }
    }

    private func taxLabel(_ group: TaxGroup) -> String {
        switch group.category {
        case "E": "Keine USt (§ 19 UStG)"
        case "AE": "Keine USt (Reverse Charge)"
        default: "USt \(Money.percent(group.rate))"
        }
    }

    // Prüfung

    @ViewBuilder private func checklist(_ issues: [InvoiceIssue]) -> some View {
        let errors = issues.filter { $0.severity == .error }
        let hints = issues.filter { $0.severity == .hint }
        VStack(alignment: .leading, spacing: 8) {
            if errors.isEmpty {
                Label("Bereit zum Festschreiben. Alle Pflichtangaben für Rechnung und XRechnung sind vorhanden.", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(Theme.paid)
            } else {
                Text("Vor dem Festschreiben fehlt noch").font(.headline)
                ForEach(errors) { issue in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Circle().fill(Theme.overdue).frame(width: 5, height: 5).alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
                        Text("\(issue.area.rawValue): \(issue.message)")
                        Spacer()
                        Text(issue.rule).font(.caption.monospaced()).foregroundStyle(.tertiary)
                    }
                }
                if errors.contains(where: { $0.area == .company }) {
                    SettingsLink { Text("Firmendaten in den Einstellungen ergänzen") }.buttonStyle(.link).padding(.top, 2)
                }
            }
            ForEach(hints) { issue in
                Label(issue.message, systemImage: "info.circle").font(.callout).foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background((errors.isEmpty ? Theme.paid : Theme.open).opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
    }
}

/// Eine Zeile der Positionstabelle – schlicht wie eine Tabellenkalkulation
struct LineItemRow: View {
    @Binding var item: LineItem
    var showsVAT: Bool
    var onDelete: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                TextField("", text: $item.title, prompt: Text("Leistung"))
                    .textFieldStyle(.plain).fontWeight(.medium)
                TextField("", text: $item.detail, prompt: Text("Beschreibung (optional)"), axis: .vertical)
                    .textFieldStyle(.plain).font(.callout).foregroundStyle(.secondary).lineLimit(1...4)
            }
            .frame(maxWidth: .infinity)
            numberField($item.quantity).frame(width: 64)
            Picker("", selection: $item.unit) { ForEach(UnitCode.allCases) { Text($0.longLabel).tag($0) } }
                .labelsHidden().pickerStyle(.menu).frame(width: 112)
            numberField($item.unitPrice, money: true).frame(width: 86)
            if showsVAT {
                Picker("", selection: $item.vatRate) {
                    Text("19 %").tag(Decimal(19))
                    Text("7 %").tag(Decimal(7))
                    Text("0 %").tag(Decimal(0))
                }
                .labelsHidden().pickerStyle(.menu).frame(width: 78)
            }
            Text(Money.format(item.net)).monospacedDigit().frame(width: 86, alignment: .trailing).padding(.top, 2)
            Button(action: onDelete) { Image(systemName: "minus.circle") }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .opacity(hovering ? 1 : 0.35)
                .frame(width: 18)
                .help("Position entfernen")
        }
        .padding(.vertical, 9)
        .onHover { hovering = $0 }
    }

    private func numberField(_ value: Binding<Decimal>, money: Bool = false) -> some View {
        DecimalField(value: value, minimumFractionDigits: money ? 2 : 0)
            .textFieldStyle(.plain)
            .multilineTextAlignment(.trailing)
            .monospacedDigit()
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 4))
    }
}

// MARK: - Zahlungserinnerung

struct ReminderSheet: View {
    @EnvironmentObject var store: DataStore
    @EnvironmentObject var purchases: Purchases
    @Environment(\.dismiss) private var dismiss
    var invoice: Invoice
    @State private var level = 1
    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Zahlungserinnerung").font(.title3.weight(.semibold))
                Text("\(invoice.customer.name) · \(invoice.number) · \(Money.format(invoice.grossTotal)) · seit \(invoice.daysOverdue()) Tagen fällig")
                    .foregroundStyle(.secondary)
            }
            Picker("Stufe", selection: $level) {
                Text("Freundlich").tag(1)
                Text("Bestimmt").tag(2)
                Text("Letzte Mahnung").tag(3)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            TextEditor(text: $text)
                .font(.body)
                .frame(minHeight: 240)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(Theme.panel, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.separator.opacity(0.6), lineWidth: 0.5))
            HStack {
                Button("Text kopieren") { FileActions.copy(text) }
                Spacer()
                Button("Abbrechen") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("In Mail öffnen") {
                    let pdf = FileActions.temporaryFile(InvoicePDF.data(for: invoice, company: store.company, branding: !purchases.isPro), name: invoice.fileBaseName + ".pdf")
                    FileActions.compose(to: invoice.customer.email, subject: subject, body: text, attachments: [pdf].compactMap { $0 })
                    var updated = invoice
                    updated.remindersSent = max(updated.remindersSent, level)
                    store.update(updated)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 560)
        .onAppear { level = min(3, invoice.remindersSent + 1); text = Self.template(level: level, invoice: invoice, company: invoice.seller ?? store.company) }
        .onChange(of: level) { _, newLevel in text = Self.template(level: newLevel, invoice: invoice, company: invoice.seller ?? store.company) }
    }

    private var subject: String {
        ["Zahlungserinnerung", "2. Zahlungserinnerung", "Letzte Mahnung"][level - 1] + " – Rechnung \(invoice.number)"
    }

    static func template(level: Int, invoice: Invoice, company: Company) -> String {
        let greeting = invoice.customer.contactPerson.isEmpty ? "Guten Tag" : "Hallo \(invoice.customer.contactPerson)"
        let newDue = DateText.format(Calendar.current.date(byAdding: .day, value: level == 3 ? 7 : 10, to: Date()))
        let facts = "Rechnung \(invoice.number) vom \(DateText.format(invoice.issueDate)) über \(Money.format(invoice.grossTotal)), fällig seit dem \(DateText.format(invoice.dueDate))"
        let bank = "IBAN \(IBAN.formatted(company.iban)), Verwendungszweck \(invoice.number)"
        let sign = company.owner.isEmpty ? company.name : company.owner
        switch level {
        case 1:
            return """
            \(greeting),

            im Alltag rutscht so etwas schnell durch: Für die \(facts) habe ich noch keinen Zahlungseingang gesehen.

            Ich freue mich, wenn Sie den Betrag bis zum \(newDue) überweisen (\(bank)). Falls sich die Zahlung mit dieser Nachricht überschnitten hat, betrachten Sie sie bitte als gegenstandslos.

            Viele Grüße
            \(sign)
            """
        case 2:
            return """
            \(greeting),

            leider ist die \(facts) weiterhin offen, auch nach meiner ersten Erinnerung.

            Bitte überweisen Sie den Betrag bis spätestens \(newDue) (\(bank)). Sollte es Unklarheiten zur Rechnung geben, melden Sie sich gern direkt bei mir.

            Viele Grüße
            \(sign)
            """
        default:
            return """
            \(greeting),

            trotz zweier Erinnerungen ist die \(facts) noch nicht beglichen.

            Ich bitte Sie, den Betrag bis zum \(newDue) zu überweisen (\(bank)). Nach Ablauf dieser Frist behalte ich mir vor, Verzugszinsen nach § 288 BGB und eine Verzugspauschale von 40 € geltend zu machen sowie weitere Schritte einzuleiten.

            Mit freundlichen Grüßen
            \(sign)
            """
        }
    }
}
