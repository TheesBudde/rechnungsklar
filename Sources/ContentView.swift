import SwiftUI
import UniformTypeIdentifiers

enum InvoiceFilter: String, CaseIterable, Identifiable, Hashable {
    case all, draft, open, overdue, paid
    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "Alle Rechnungen"
        case .draft: "Entwürfe"
        case .open: "Offen"
        case .overdue: "Überfällig"
        case .paid: "Bezahlt"
        }
    }

    var symbol: String {
        switch self {
        case .all: "doc.text"
        case .draft: "pencil.line"
        case .open: "clock"
        case .overdue: "exclamationmark.circle"
        case .paid: "checkmark.circle"
        }
    }

    func matches(_ invoice: Invoice) -> Bool {
        switch self {
        case .all: true
        case .draft: invoice.status == .draft
        case .open: invoice.awaitsPayment
        case .overdue: invoice.isOverdue()
        case .paid: invoice.status == .paid
        }
    }
}

enum SidebarItem: Hashable, Identifiable {
    case overview, invoices(InvoiceFilter), incoming, customers
    var id: String {
        switch self {
        case .overview: "overview"
        case .invoices(let filter): "invoices-\(filter.rawValue)"
        case .incoming: "incoming"
        case .customers: "customers"
        }
    }

    var title: String {
        switch self {
        case .overview: "Übersicht"
        case .invoices(let filter): filter == .all ? "Rechnungen" : filter.title
        case .incoming: "E-Rechnungs-Eingang"
        case .customers: "Kunden"
        }
    }

    /// Hauptbereiche für Menübefehle (⌘1 bis ⌘4)
    static let main: [SidebarItem] = [.overview, .invoices(.all), .incoming, .customers]
}

/// Was gerade ausgewählt ist – geteilt zwischen Seitenleiste, Listen und Menübefehlen
@MainActor
final class Navigation: ObservableObject {
    @Published var section: SidebarItem? = .overview
    @Published var invoiceID: Invoice.ID?
    @Published var incomingID: IncomingInvoice.ID?
    @Published var customerID: Customer.ID?
    @Published var showPaywall = false
    @Published var importError: String?
    @Published var reminderFor: Invoice?

    /// Führt eine Pro-Funktion aus oder zeigt die Paywall
    func requirePro(_ purchases: Purchases, _ action: () -> Void) {
        if purchases.isPro { action() } else { showPaywall = true }
    }

    /// Zeigt eine Rechnung; wechselt den Filter, falls sie im aktuellen nicht vorkommt
    func show(_ invoice: Invoice) {
        if case .invoices(let filter) = section, filter.matches(invoice) {} else { section = .invoices(.all) }
        invoiceID = invoice.id
    }

    func newInvoice(in store: DataStore, for customer: Customer? = nil) {
        let invoice = store.newInvoice(for: customer)
        section = .invoices(.all)
        invoiceID = invoice.id
    }
}

struct ContentView: View {
    @EnvironmentObject var store: DataStore
    @EnvironmentObject var nav: Navigation
    @EnvironmentObject var purchases: Purchases
    @State private var dropTargeted = false

    var body: some View {
        NavigationSplitView {
            Sidebar()
                .navigationSplitViewColumnWidth(min: 200, ideal: 220)
        } detail: {
            switch nav.section ?? .overview {
            case .overview: DashboardView()
            case .invoices(let filter): InvoicesView(filter: filter)
            case .incoming: IncomingView()
            case .customers: CustomersView()
            }
        }
        .sheet(isPresented: $nav.showPaywall) { PaywallView() }
        .sheet(item: $nav.reminderFor) { invoice in ReminderSheet(invoice: invoice) }
        .sheet(isPresented: Binding(get: { !store.onboarded }, set: { if !$0 { store.onboarded = true } })) { OnboardingView() }
        .alert("Datei konnte nicht gelesen werden", isPresented: Binding(get: { nav.importError != nil }, set: { if !$0 { nav.importError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(nav.importError ?? "")
        }
        // Eine E-Rechnung irgendwo ins Fenster ziehen öffnet sie im Eingang
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
            Importer.handle(providers: providers, store: store, nav: nav)
        }
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Theme.accent, lineWidth: 2)
                    .background(Theme.accent.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
                    .overlay(Text("Loslassen, um die E-Rechnung zu öffnen").font(.headline).padding(.horizontal, 14).padding(.vertical, 8)
                        .background(.regularMaterial, in: Capsule()))
                    .padding(6)
                    .allowsHitTesting(false)
            }
        }
    }
}

struct Sidebar: View {
    @EnvironmentObject var store: DataStore
    @EnvironmentObject var nav: Navigation

    var body: some View {
        List(selection: $nav.section) {
            Label("Übersicht", systemImage: "square.grid.2x2").tag(SidebarItem.overview)
            Section("Rechnungen") {
                ForEach(InvoiceFilter.allCases) { filter in
                    Label(filter.title, systemImage: filter.symbol)
                        .badge(badge(filter))
                        .tag(SidebarItem.invoices(filter))
                }
            }
            Section("Eingang") {
                Label("E-Rechnungen", systemImage: "tray.and.arrow.down")
                    .badge(store.unpaidIncoming.count)
                    .tag(SidebarItem.incoming)
            }
            Section("Adressen") {
                Label("Kunden", systemImage: "person.2").tag(SidebarItem.customers)
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) { FreeTierNote() }
    }

    private func badge(_ filter: InvoiceFilter) -> Int {
        switch filter {
        case .draft: store.invoices.filter { $0.status == .draft }.count
        case .overdue: store.overdueInvoices.count
        default: 0
        }
    }
}

/// Dezenter Hinweis auf das Freikontingent – keine Werbefläche
struct FreeTierNote: View {
    @EnvironmentObject var store: DataStore
    @EnvironmentObject var nav: Navigation
    @EnvironmentObject var purchases: Purchases

    var body: some View {
        if !purchases.isPro {
            let used = min(store.finalizedCount, Purchases.freeInvoices)
            VStack(alignment: .leading, spacing: 6) {
                Text("\(used) von \(Purchases.freeInvoices) kostenlosen Rechnungen genutzt").font(.caption).foregroundStyle(.secondary)
                ProgressView(value: Double(used), total: Double(Purchases.freeInvoices)).tint(Theme.accent).controlSize(.small)
                Button("Rechnungsklar Pro …") { nav.showPaywall = true }
                    .buttonStyle(.link)
                    .font(.caption.weight(.medium))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }
}

/// Öffnet E-Rechnungen aus Drag & Drop, Öffnen-Dialog und dem Finder („Öffnen mit …“)
@MainActor
enum Importer {
    static let types: [UTType] = [.xml, .pdf]

    static func open(urls: [URL], store: DataStore, nav: Navigation) {
        var last: IncomingInvoice?
        var errors: [String] = []
        for url in urls {
            do { last = try store.importIncoming(from: url) } catch {
                errors.append("\(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
        if let last {
            nav.section = .incoming
            nav.incomingID = last.id
        }
        if !errors.isEmpty { nav.importError = errors.joined(separator: "\n\n") }
    }

    static func handle(providers: [NSItemProvider], store: DataStore, nav: Navigation) -> Bool {
        let fileProviders = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
        guard !fileProviders.isEmpty else { return false }
        for provider in fileProviders {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in open(urls: [url], store: store, nav: nav) }
            }
        }
        return true
    }

    static func showOpenPanel(store: DataStore, nav: Navigation) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = types
        panel.allowsMultipleSelection = true
        panel.message = "Wähle XRechnung-, ZUGFeRD- oder Factur-X-Dateien (XML oder PDF)."
        guard panel.runModal() == .OK else { return }
        open(urls: panel.urls, store: store, nav: nav)
    }
}
