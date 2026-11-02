import Foundation
import StoreKit

/// Rechnungsklar Pro über den Mac App Store (StoreKit 2).
/// Kostenlos: E-Rechnungen empfangen und lesen ohne Grenze, dazu 3 eigene Rechnungen zum Ausprobieren.
@MainActor
final class Purchases: ObservableObject {
    nonisolated static let monthly = "de.rechnungsklar.pro.monthly"
    nonisolated static let yearly = "de.rechnungsklar.pro.yearly"
    nonisolated static let lifetime = "de.rechnungsklar.pro.lifetime"
    nonisolated static let allIDs = [yearly, monthly, lifetime]
    nonisolated static let freeInvoices = 3

    @Published private(set) var products: [Product] = []
    @Published private(set) var isPro = false
    @Published private(set) var busy = false
    @Published var message: String?

    private var updates: Task<Void, Never>?

    init(unlocked: Bool = false) {
        isPro = unlocked || Self.debugUnlock
        guard !unlocked else { return }
        updates = Task { [weak self] in
            for await result in Transaction.updates {
                if case .verified(let transaction) = result { await transaction.finish() }
                await self?.refresh()
            }
        }
        Task { await load() }
    }

    deinit { updates?.cancel() }

    /// Nur in Entwickler-Builds: mit `--pro` starten schaltet Pro frei, ohne zu kaufen
    private static var debugUnlock: Bool {
        #if DEBUG
        CommandLine.arguments.contains("--pro")
        #else
        false
        #endif
    }

    func canFinalize(finalizedSoFar: Int) -> Bool { isPro || finalizedSoFar < Self.freeInvoices }

    func load() async {
        do {
            products = try await Product.products(for: Self.allIDs).sorted { order($0) < order($1) }
        } catch {
            products = []
        }
        await refresh()
    }

    private func order(_ product: Product) -> Int { Self.allIDs.firstIndex(of: product.id) ?? 9 }

    func refresh() async {
        var active = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result, Self.allIDs.contains(transaction.productID), transaction.revocationDate == nil {
                active = true
            }
        }
        isPro = active || Self.debugUnlock
    }

    func buy(_ product: Product) async {
        busy = true
        defer { busy = false }
        do {
            switch try await product.purchase() {
            case .success(let verification):
                if case .verified(let transaction) = verification {
                    await transaction.finish()
                    await refresh()
                    message = "Danke! Rechnungsklar Pro ist freigeschaltet."
                } else {
                    message = "Der Kauf konnte nicht bestätigt werden."
                }
            case .pending: message = "Der Kauf wartet noch auf eine Bestätigung."
            case .userCancelled: break
            @unknown default: break
            }
        } catch {
            message = "Kauf fehlgeschlagen: \(error.localizedDescription)"
        }
    }

    func restore() async {
        busy = true
        defer { busy = false }
        try? await AppStore.sync()
        await refresh()
        message = isPro ? "Käufe wiederhergestellt." : "Es wurde kein früherer Kauf gefunden."
    }
}

/// Preise, die angezeigt werden, solange der App Store keine Produkte geliefert hat (z. B. vor der Freigabe)
struct PlanInfo: Identifiable {
    var id: String
    var title: String
    var price: String
    var detail: String
    var badge: String?

    static let fallback = [
        PlanInfo(id: Purchases.yearly, title: "Jährlich", price: "49,99 €", detail: "4,17 € im Monat · 2 Monate geschenkt", badge: "Beliebt"),
        PlanInfo(id: Purchases.monthly, title: "Monatlich", price: "5,99 €", detail: "jederzeit kündbar"),
        PlanInfo(id: Purchases.lifetime, title: "Einmalkauf", price: "129,99 €", detail: "einmal zahlen, für immer nutzen"),
    ]
}
