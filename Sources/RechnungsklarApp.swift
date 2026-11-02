import SwiftUI

@main
struct RechnungsklarApp: App {
    @StateObject private var store = DataStore()
    @StateObject private var nav = Navigation()
    @StateObject private var purchases = Purchases()

    var body: some Scene {
        Window("Rechnungsklar", id: "main") {
            ContentView()
                .environmentObject(store)
                .environmentObject(nav)
                .environmentObject(purchases)
                .frame(minWidth: 1100, minHeight: 680)
                .tint(Theme.accent)
                .environment(\.locale, Locale(identifier: "de_DE"))
                // Doppelklick auf eine XRechnung im Finder („Öffnen mit Rechnungsklar“)
                .onOpenURL { url in Importer.open(urls: [url], store: store, nav: nav) }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in store.saveNow() }
        }
        .defaultSize(width: 1320, height: 820)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Neue Rechnung") { nav.newInvoice(in: store) }
                    .keyboardShortcut("n")
                Button("E-Rechnung öffnen …") { Importer.showOpenPanel(store: store, nav: nav) }
                    .keyboardShortcut("o")
            }
            CommandGroup(after: .sidebar) {
                Divider()
                ForEach(Array(SidebarItem.main.enumerated()), id: \.element) { index, item in
                    Button(item.title) { nav.section = item }
                        .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
                }
            }
            CommandGroup(replacing: .help) {
                Link("Rechnungsklar-Hilfe", destination: URL(string: "https://rechnungsklar.de/hilfe")!)
                Link("Fragen und Antworten zur E-Rechnung (BMF)", destination: URL(string: "https://www.bundesfinanzministerium.de/Content/DE/FAQ/e-rechnung.html")!)
            }
        }

        Settings {
            SettingsView()
                .environmentObject(store)
                .environmentObject(purchases)
                .tint(Theme.accent)
                .environment(\.locale, Locale(identifier: "de_DE"))
        }
    }
}
