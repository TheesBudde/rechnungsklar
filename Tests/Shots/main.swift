import AppKit
import SwiftUI

/// Nachgezeichneter Fensterrahmen mit Seitenleiste – NavigationSplitView lässt sich ohne Fensterserver nicht vollständig rendern.
/// Der Inhalt rechts sind die echten Ansichten der App.
struct ScreenshotWindow<Content: View>: View {
    var section: SidebarItem
    var store: DataStore
    var showsFreeTier = false
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                ForEach([Color(red: 1, green: 0.37, blue: 0.34), Color(red: 1, green: 0.74, blue: 0.18), Color(red: 0.16, green: 0.79, blue: 0.25)], id: \.self) {
                    Circle().fill($0).frame(width: 12, height: 12)
                }
                Text(section.title).font(.system(size: 14, weight: .semibold)).padding(.leading, 190)
                Spacer()
            }
            .padding(.horizontal, 18)
            .frame(height: 50)
            .background(Color(nsColor: .windowBackgroundColor))
            .overlay(alignment: .bottom) { Divider() }
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 1) {
                    row("Übersicht", "square.grid.2x2", .overview)
                    header("Rechnungen")
                    ForEach(InvoiceFilter.allCases) { filter in
                        row(filter.title, filter.symbol, .invoices(filter),
                            badge: filter == .draft ? store.invoices.filter { $0.status == .draft }.count : filter == .overdue ? store.overdueInvoices.count : 0)
                    }
                    header("Eingang")
                    row("E-Rechnungen", "tray.and.arrow.down", .incoming, badge: store.unpaidIncoming.count)
                    header("Adressen")
                    row("Kunden", "person.2", .customers)
                    Spacer()
                    if showsFreeTier {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("1 von 3 kostenlosen Rechnungen genutzt").font(.caption).foregroundStyle(.secondary)
                            ProgressView(value: 1, total: 3).tint(Theme.accent).controlSize(.small)
                            Text("Rechnungsklar Pro …").font(.caption.weight(.medium)).foregroundStyle(Theme.accent)
                        }
                        .padding(.horizontal, 6).padding(.bottom, 4)
                    }
                }
                .padding(10)
                .frame(width: 220)
                .background(Color(nsColor: .windowBackgroundColor).opacity(0.6))
                Divider()
                content.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func header(_ text: String) -> some View {
        Text(text).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary).padding(.horizontal, 10).padding(.top, 14).padding(.bottom, 3)
    }

    private func row(_ title: String, _ symbol: String, _ item: SidebarItem, badge: Int = 0) -> some View {
        let selected = item == section
        return HStack(spacing: 8) {
            Image(systemName: symbol).frame(width: 18).foregroundStyle(selected ? Color.white : Theme.accent)
            Text(title)
            Spacer()
            if badge > 0 { Text("\(badge)").font(.caption).foregroundStyle(selected ? Color.white.opacity(0.85) : .secondary) }
        }
        .foregroundStyle(selected ? Color.white : Color.primary)
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 6).fill(selected ? Theme.accent : Color.clear))
    }
}

/// Beispiel-Logo für die Screenshots: ein schlichtes Monogramm
struct SampleLogo: View {
    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(Color(red: 0.85, green: 0.38, blue: 0.27))
                Text("lh").font(.system(size: 30, weight: .bold, design: .serif)).foregroundStyle(.white)
            }
            .frame(width: 64, height: 64)
            VStack(alignment: .leading, spacing: 0) {
                Text("Lena Hoffmann").font(.system(size: 26, weight: .semibold, design: .serif))
                Text("DESIGN STUDIO").font(.system(size: 12, weight: .medium)).tracking(4).foregroundStyle(Color(white: 0.4))
            }
            .foregroundStyle(Color(white: 0.12))
        }
        .padding(4)
    }
}

// Rendert die App-Ansichten mit Beispieldaten als PNG (Sichtprüfung und App-Store-Screenshots),
// eine Beispielrechnung als PDF/XML und das App-Symbol als .iconset.
// Aufruf: shots <Ausgabeordner> [--icon <iconset-Ordner>]
MainActor.assumeIsolated {
    let application = NSApplication.shared
    application.setActivationPolicy(.prohibited)
    let args = CommandLine.arguments
    let out = URL(fileURLWithPath: args.count > 1 ? args[1] : "build/shots", isDirectory: true)
    try? FileManager.default.createDirectory(at: out.appendingPathComponent("appstore"), withIntermediateDirectories: true)

    func render<V: View>(_ view: V, size: CGSize, to name: String, dark: Bool = false, scale: CGFloat = 2) {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
        host.frame = NSRect(origin: .zero, size: size)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))
        host.layoutSubtreeIfNeeded()
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0) else { return }
        rep.size = size
        host.cacheDisplay(in: NSRect(origin: .zero, size: size), to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: out.appendingPathComponent(name))
        print("  \(name)")
    }

    // App-Symbol
    if let i = args.firstIndex(of: "--icon"), i + 1 < args.count {
        let iconset = URL(fileURLWithPath: args[i + 1], isDirectory: true)
        try? FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
        for (name, pixels) in [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128), ("128x128@2x", 256),
                               ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)] {
            let renderer = ImageRenderer(content: AppIconView(size: CGFloat(pixels)))
            renderer.scale = 1
            if let image = renderer.cgImage {
                let rep = NSBitmapImageRep(cgImage: image)
                try? rep.representation(using: .png, properties: [:])?.write(to: iconset.appendingPathComponent("icon_\(name).png"))
            }
        }
        print("Symbol geschrieben nach \(iconset.path)")
        exit(0)
    }

    // Beispieldaten im Speicher
    let store = DataStore(folder: nil)
    var company = SampleData.company
    let logoRenderer = ImageRenderer(content: SampleLogo())
    logoRenderer.scale = 3
    if let image = logoRenderer.nsImage { company.logo = LogoImage.normalized(image) }
    store.company = company
    store.customers = SampleData.customers
    store.invoices = SampleData.invoices(company: company)
    store.onboarded = true
    let supplier = SampleData.supplierInvoice
    var incoming = try! EInvoiceReader.parseXML(Data(XRechnungWriter.xml(for: supplier, seller: supplier.seller!).utf8))
    incoming.originalFileName = "INV-88213_werkhaus.xml"
    incoming.importedAt = SampleData.date(16, 10)
    var second = IncomingInvoice()
    second.format = "ZUGFeRD / Factur-X (PDF)"
    second.number = "2026-10-4471"
    second.seller.name = "Druckerei Rheinbogen KG"
    second.issueDate = SampleData.date(22, 10)
    second.dueDate = SampleData.date(5, 11)
    second.netTotal = 412.6
    second.taxTotal = 78.39
    second.grossTotal = 490.99
    second.dueAmount = 490.99
    var third = IncomingInvoice()
    third.format = "XRechnung 3.0 (UBL)"
    third.number = "A-77812"
    third.seller.name = "Hostwerk Cloud GmbH"
    third.issueDate = SampleData.date(1, 10)
    third.dueDate = SampleData.date(15, 10)
    third.grossTotal = 23.8
    third.dueAmount = 23.8
    third.isPaid = true
    store.incoming = [incoming, second, third]

    let nav = Navigation()
    let purchases = Purchases(unlocked: true)
    let free = Purchases(unlocked: false)
    let today = SampleData.date(1, 11)

    func app<V: View>(_ view: V, purchases p: Purchases = purchases) -> some View {
        view.environmentObject(store).environmentObject(nav).environmentObject(p).tint(Theme.accent)
            .environment(\.locale, Locale(identifier: "de_DE"))
    }
    func window<V: View>(_ section: SidebarItem, _ content: V, freeTier: Bool = false) -> some View {
        app(ScreenshotWindow(section: section, store: store, showsFreeTier: freeTier) { content })
    }

    let size = CGSize(width: 1440, height: 900)
    let mainInvoice = store.invoices.first { $0.number == "RE-2026-0015" }!
    let draft = store.invoices.first { $0.status == .draft }!
    print("Ansichten")
    render(window(.overview, DashboardView(today: today)), size: size, to: "1-uebersicht.png")
    nav.invoiceID = mainInvoice.id
    render(window(.invoices(.all), InvoicesView(filter: .all)), size: size, to: "2-rechnung-vorschau.png")
    nav.invoiceID = draft.id
    render(window(.invoices(.all), InvoicesView(filter: .all)), size: size, to: "3-rechnung-bearbeiten.png")
    render(window(.invoices(.all), InvoicesView(filter: .all)), size: CGSize(width: 1440, height: 1300), to: "3b-rechnung-bearbeiten-ganz.png")
    nav.invoiceID = nil
    render(window(.invoices(.overdue), InvoicesView(filter: .overdue)), size: size, to: "3c-ueberfaellig.png")
    nav.incomingID = incoming.id
    render(window(.incoming, IncomingView()), size: size, to: "4-eingang.png")
    render(window(.incoming, IncomingView()), size: CGSize(width: 1440, height: 1200), to: "4c-eingang-ganz.png")
    nav.incomingID = nil
    let emptyStore = DataStore(folder: nil)
    emptyStore.onboarded = true
    render(ScreenshotWindow(section: .incoming, store: emptyStore) { IncomingView() }
        .environmentObject(emptyStore).environmentObject(nav).environmentObject(purchases).tint(Theme.accent), size: size, to: "4b-eingang-leer.png")
    nav.customerID = SampleData.customers[0].id
    render(window(.customers, CustomersView()), size: size, to: "5-kunden.png")
    render(window(.overview, DashboardView(today: today)), size: size, to: "6-uebersicht-dunkel.png", dark: true)
    nav.incomingID = incoming.id
    render(window(.incoming, IncomingView()), size: size, to: "6b-eingang-dunkel.png", dark: true)
    nav.invoiceID = draft.id
    render(window(.invoices(.all), InvoicesView(filter: .all)), size: size, to: "6c-bearbeiten-dunkel.png", dark: true)
    // Neue Firma ohne Daten: Hinweis in der Übersicht
    let fresh = DataStore(folder: nil)
    fresh.onboarded = true
    render(ScreenshotWindow(section: .overview, store: fresh, showsFreeTier: true) { DashboardView(today: today) }
        .environmentObject(fresh).environmentObject(nav).environmentObject(free).tint(Theme.accent), size: size, to: "6d-uebersicht-neu.png")

    print("Fenster")
    render(app(PaywallView(), purchases: free), size: CGSize(width: 480, height: 640), to: "7-pro.png")
    render(app(OnboardingView()), size: CGSize(width: 620, height: 560), to: "8-willkommen.png")
    render(app(OnboardingView(step: 1)), size: CGSize(width: 620, height: 560), to: "8b-firma.png")
    render(app(SettingsView()), size: CGSize(width: 580, height: 620), to: "9-einstellungen.png")
    render(app(DataSettings()), size: CGSize(width: 580, height: 420), to: "9b-daten.png")
    let overdue = store.overdueInvoices.first ?? store.invoices[2]
    render(app(ReminderSheet(invoice: overdue)), size: CGSize(width: 560, height: 470), to: "10-erinnerung.png")
    render(AppIconView(size: 512), size: CGSize(width: 512, height: 512), to: "symbol.png", scale: 1)

    print("Rechnung")
    try? InvoicePDF.data(for: mainInvoice, company: company).write(to: out.appendingPathComponent("RE-2026-0015.pdf"))
    try? XRechnungWriter.xml(for: mainInvoice, seller: company).write(to: out.appendingPathComponent("RE-2026-0015_XRechnung.xml"), atomically: false, encoding: .utf8)
    render(InvoicePage(invoice: mainInvoice, company: company, items: mainInvoice.items[...], pageIndex: 0, pageCount: 1),
           size: InvoicePage.size, to: "rechnung-seite.png")
    var plain = mainInvoice
    plain.seller?.logo = nil
    render(InvoicePage(invoice: plain, company: company, items: plain.items[...], pageIndex: 0, pageCount: 1, branding: true),
           size: InvoicePage.size, to: "rechnung-ohne-logo.png")
    let stornoStore = DataStore(folder: nil)
    stornoStore.company = company
    stornoStore.invoices = [mainInvoice]
    if let storno = stornoStore.cancel(mainInvoice, on: today) {
        render(InvoicePage(invoice: storno, company: company, items: storno.items[...], pageIndex: 0, pageCount: 1),
               size: InvoicePage.size, to: "storno-seite.png")
        try? InvoicePDF.data(for: storno, company: company).write(to: out.appendingPathComponent("Storno.pdf"))
    }
    // Lange Rechnung, um den Seitenumbruch zu prüfen
    var long = mainInvoice
    long.items = (1...30).map { LineItem(title: "Leistung \($0)", detail: $0 % 3 == 0 ? "Mit einer etwas längeren Beschreibung, die über eine Zeile hinausgehen kann" : "",
                                          quantity: Decimal($0 % 5 + 1), unit: .hour, unitPrice: 85, vatRate: 19) }
    try? InvoicePDF.data(for: long, company: company).write(to: out.appendingPathComponent("lange-rechnung.pdf"))
    let longPages = InvoiceLayout.pages(for: long.items)
    for (index, slice) in longPages.enumerated() {
        render(InvoicePage(invoice: long, company: company, items: slice, pageIndex: index, pageCount: longPages.count),
               size: InvoicePage.size, to: "lange-rechnung-\(index + 1).png", scale: 1)
    }

    print("App Store")
    func marketing<V: View>(_ headline: String, _ sub: String, _ section: SidebarItem, _ content: V, dark: Bool = false) -> some View {
        VStack(spacing: 10) {
            Text(headline).font(.system(size: 44, weight: .bold)).foregroundStyle(Color(white: 0.1))
            Text(sub).font(.system(size: 21)).foregroundStyle(Color(white: 0.35))
            window(section, content)
                .frame(width: 1440, height: 900)
                .environment(\.colorScheme, dark ? .dark : .light)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.black.opacity(0.12), lineWidth: 1))
                .scaleEffect(0.8)
                .frame(width: 1152, height: 720)
                .shadow(color: .black.opacity(0.18), radius: 28, y: 14)
                .padding(.top, 18)
        }
        .frame(width: 1440, height: 900)
        .background(Color(red: 0.95, green: 0.94, blue: 0.91))
    }
    nav.invoiceID = mainInvoice.id
    render(marketing("Rechnungen, die das Finanzamt mag.", "Als PDF und als XRechnung 3.0 – bereit für die E-Rechnungs-Pflicht", .invoices(.all), InvoicesView(filter: .all)),
           size: size, to: "appstore/1-rechnung.png")
    nav.incomingID = incoming.id
    render(marketing("XRechnung? Endlich lesbar.", "XRechnung, ZUGFeRD und Factur-X öffnen – und per GiroCode bezahlen", .incoming, IncomingView()),
           size: size, to: "appstore/2-eingang.png")
    render(marketing("Wissen, wer noch zahlen muss.", "Offene Posten, Umsatz und Zahlungserinnerungen auf einen Blick", .overview, DashboardView(today: today)),
           size: size, to: "appstore/3-uebersicht.png")
    nav.invoiceID = draft.id
    render(marketing("Prüft jede Pflichtangabe.", "Fehlt etwas für eine gültige E-Rechnung, siehst du es vor dem Versand", .invoices(.all), InvoicesView(filter: .all)),
           size: size, to: "appstore/4-pruefung.png")
    render(marketing("Deine Daten bleiben bei dir.", "Kein Konto, keine Cloud – Rechnungsklar arbeitet nur auf deinem Mac", .incoming, IncomingView(), dark: true),
           size: size, to: "appstore/5-dunkel.png", dark: true)
    print("Fertig: \(out.path)")
}
