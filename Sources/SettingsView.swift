import StoreKit
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: DataStore
    @EnvironmentObject var purchases: Purchases

    var body: some View {
        TabView {
            CompanyForm(company: $store.company, showsLogo: true).tabItem { Label("Firma", systemImage: "building.2") }
            numbering.tabItem { Label("Rechnungen", systemImage: "number") }
            DataSettings().tabItem { Label("Daten", systemImage: "externaldrive") }
            proTab.tabItem { Label("Pro", systemImage: "seal") }
        }
        .frame(width: 580, height: 620)
    }

    private var numbering: some View {
        Form {
            Section {
                TextField("Präfix", text: $store.company.invoicePrefix)
                Stepper("Nächste laufende Nummer: \(store.company.nextNumber)", value: $store.company.nextNumber, in: 1...99_999)
                LabeledContent("Nächste Rechnung", value: store.peekNumber())
            } header: {
                Text("Rechnungsnummern")
            } footer: {
                Text("Nummern sind fortlaufend und werden nur einmal vergeben. Wenn du von einem anderen Programm wechselst, setze hier die nächste freie Nummer.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Standardwerte für neue Rechnungen") {
                Stepper("Zahlungsziel: \(store.company.paymentDays) Tage", value: $store.company.paymentDays, in: 0...120)
                TextField("Schlusssatz", text: $store.company.closingText, axis: .vertical).lineLimit(1...3)
            }
        }
        .formStyle(.grouped)
    }

    private var proTab: some View {
        Form {
            Section {
                if purchases.isPro {
                    Label("Rechnungsklar Pro ist aktiv. Danke für deine Unterstützung.", systemImage: "checkmark.seal.fill").foregroundStyle(Theme.paid)
                } else {
                    Text("Kostenlos: E-Rechnungen lesen ohne Grenze und \(Purchases.freeInvoices) eigene Rechnungen zum Ausprobieren.")
                }
                Button("Käufe wiederherstellen") { Task { await purchases.restore() } }
                if let message = purchases.message { Text(message).font(.caption).foregroundStyle(.secondary) }
            }
        }
        .formStyle(.grouped)
    }
}

struct DataSettings: View {
    @EnvironmentObject var store: DataStore
    @State private var message: String?
    @State private var confirmRestore: URL?

    var body: some View {
        Form {
            Section {
                LabeledContent("Speicherort", value: "Nur auf diesem Mac")
                Button("Datenordner im Finder zeigen") {
                    if let url = store.dataURL { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                }
            } footer: {
                Text("Rechnungsklar hat kein Konto und keinen Server. Time Machine sichert deine Daten automatisch mit.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Button("Sicherung erstellen …") {
                    guard let folder = FileActions.chooseFolder(prompt: "Hier sichern", message: "Wähle, wo die Sicherung abgelegt werden soll.") else { return }
                    do {
                        let target = try store.exportBackup(to: folder)
                        message = "Gesichert in „\(target.lastPathComponent)“."
                        NSWorkspace.shared.activateFileViewerSelecting([target])
                    } catch {
                        message = "Sicherung fehlgeschlagen: \(error.localizedDescription)"
                    }
                }
                Button("Sicherung wiederherstellen …") {
                    confirmRestore = FileActions.chooseFolder(prompt: "Wiederherstellen", message: "Wähle einen Ordner „Rechnungsklar-Sicherung_…“.")
                }
                if let message { Text(message).font(.caption).foregroundStyle(.secondary) }
            } header: {
                Text("Datensicherung")
            } footer: {
                Text("Eine Sicherung enthält alle Rechnungen, Kunden, Einstellungen und die archivierten Original-E-Rechnungen.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .confirmationDialog("Sicherung wiederherstellen?", isPresented: Binding(get: { confirmRestore != nil }, set: { if !$0 { confirmRestore = nil } })) {
            Button("Wiederherstellen", role: .destructive) {
                guard let url = confirmRestore else { return }
                do {
                    try store.restoreBackup(from: url)
                    message = "Sicherung wiederhergestellt. Die bisherigen Daten liegen daneben im Ordner „Rechnungsklar-vor-Wiederherstellung“."
                } catch {
                    message = error.localizedDescription
                }
            }
        } message: {
            Text("Die aktuellen Daten werden durch die Sicherung ersetzt. Sie werden vorher beiseitegelegt, nicht gelöscht.")
        }
    }
}

struct CompanyForm: View {
    @Binding var company: Company
    var showsLogo = false

    var body: some View {
        Form {
            Section("Unternehmen") {
                TextField("Firmenname", text: $company.name, prompt: Text("z. B. Lena Hoffmann Design"))
                TextField("Inhaber/in", text: $company.owner)
                TextField("Straße und Hausnummer", text: $company.street)
                TextField("PLZ", text: $company.zip)
                TextField("Ort", text: $company.city)
            }
            if showsLogo {
                Section {
                    HStack(spacing: 14) {
                        Group {
                            if let logo = LogoImage.image(company.logo) {
                                logo.resizable().scaledToFit()
                            } else {
                                Text("Kein Logo").font(.caption).foregroundStyle(Color(white: 0.55))
                            }
                        }
                        .frame(width: 140, height: 48)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.separator, lineWidth: 0.5))
                        VStack(alignment: .leading, spacing: 6) {
                            Button(company.logo == nil ? "Logo wählen …" : "Anderes Logo …") {
                                if let data = FileActions.chooseLogo() { company.logo = data }
                            }
                            if company.logo != nil { Button("Entfernen", role: .destructive) { company.logo = nil }.buttonStyle(.link) }
                        }
                    }
                } header: {
                    Text("Logo auf Rechnungen")
                } footer: {
                    Text("Ohne Logo steht dein Firmenname im Briefkopf.").font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("Kontakt (Pflicht in der XRechnung)") {
                TextField("Telefon", text: $company.phone)
                TextField("E-Mail", text: $company.email)
                TextField("Website", text: $company.website)
            }
            Section {
                Toggle("Kleinunternehmer nach § 19 UStG", isOn: $company.smallBusiness)
                TextField("Steuernummer", text: $company.taxNumber)
                TextField("USt-IdNr.", text: $company.vatID, prompt: Text("DE…"))
            } header: {
                Text("Steuer")
            } footer: {
                Text("Als Kleinunternehmer weist du keine Umsatzsteuer aus. Neue Rechnungen werden dann automatisch passend angelegt.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                TextField("IBAN", text: $company.iban)
                TextField("BIC", text: $company.bic)
                TextField("Bank", text: $company.bankName)
            } header: {
                Text("Bankverbindung")
            } footer: {
                // Immer vorhanden, nur der Text wechselt – sonst springt das Formular beim Tippen nach oben
                Text(!company.iban.isEmpty && !IBAN.isValid(company.iban) ? "Diese IBAN stimmt nicht – bitte prüfe sie." : " ")
                    .font(.caption).foregroundStyle(Theme.overdue)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Einrichtung

struct OnboardingView: View {
    @EnvironmentObject var store: DataStore
    @Environment(\.dismiss) private var dismiss
    @State var step = 0

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch step {
                case 0: welcome
                case 1: CompanyForm(company: $store.company)
                default: done
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            HStack {
                Text("Schritt \(step + 1) von 3").font(.caption).foregroundStyle(.secondary)
                Spacer()
                if step > 0 { Button("Zurück") { step -= 1 } }
                if step == 0 { Button("Später") { finish() } }
                Button(step == 2 ? "Fertig" : "Weiter") { if step == 2 { finish() } else { step += 1 } }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: 620, height: 560)
    }

    private func finish() {
        store.onboarded = true
        dismiss()
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 16) {
                AppIconView(size: 72)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Rechnungsklar").font(.system(size: 26, weight: .bold))
                    Text("E-Rechnungen schreiben und lesen.").font(.title3).foregroundStyle(.secondary)
                }
            }
            Text("Ab 2028 müssen alle Unternehmen ihren Geschäftskunden E-Rechnungen schicken; empfangen müssen sie sie schon heute. Rechnungsklar erledigt beides – ohne Konto, ohne Cloud, direkt auf deinem Mac.")
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 12) {
                point("Rechnungen schreiben", "als PDF und als XRechnung, mit Prüfung aller Pflichtangaben")
                point("E-Rechnungen lesen", "XRechnung, ZUGFeRD und Factur-X – kostenlos und ohne Grenze")
                point("Den Überblick behalten", "offene Posten, Zahlungserinnerungen, Export für die Steuerberatung")
            }
            Text("Als Nächstes trägst du deine Firmendaten ein. Das dauert etwa zwei Minuten.").foregroundStyle(.secondary)
        }
        .padding(36)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func point(_ title: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "checkmark").font(.caption.weight(.bold)).foregroundStyle(Theme.accent)
            Text(title).fontWeight(.semibold) + Text(" – \(text)").foregroundColor(.secondary)
        }
    }

    private var done: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(store.company.missingEssentials.isEmpty ? "Alles bereit." : "Fast fertig.").font(.system(size: 26, weight: .bold))
            if store.company.missingEssentials.isEmpty {
                Text("Deine erste Rechnung legst du mit ⌘N an. Empfangene E-Rechnungen ziehst du einfach ins Fenster.")
            } else {
                Text("Für gültige E-Rechnungen fehlt noch: \(store.company.missingEssentials.joined(separator: ", ")). Du kannst das jederzeit in den Einstellungen (⌘,) ergänzen.")
            }
            Text("Tipp: Mit „Aus früheren Positionen“ legst du wiederkehrende Leistungen mit einem Klick an.").foregroundStyle(.secondary)
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(36)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Paywall

struct PaywallView: View {
    @EnvironmentObject var purchases: Purchases
    @Environment(\.dismiss) private var dismiss
    @State private var selected = Purchases.yearly

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 14) {
                AppIconView(size: 56)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Rechnungsklar Pro").font(.title2.weight(.bold))
                    Text("Für alle, die regelmäßig Rechnungen schreiben.").foregroundStyle(.secondary)
                }
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark") }.buttonStyle(.borderless).keyboardShortcut(.cancelAction)
            }

            VStack(alignment: .leading, spacing: 7) {
                bullet("Unbegrenzt Rechnungen als PDF und XRechnung")
                bullet("Zahlungserinnerungen in drei Stufen")
                bullet("CSV-Export für Steuerberatung und Buchhaltung")
                bullet("Rechnungen ohne „Erstellt mit Rechnungsklar“")
                bullet("Updates für neue XRechnung-Versionen")
            }

            VStack(spacing: 8) {
                ForEach(plans) { plan in
                    Button { selected = plan.id } label: {
                        HStack {
                            Image(systemName: selected == plan.id ? "largecircle.fill.circle" : "circle")
                                .foregroundStyle(selected == plan.id ? Theme.accent : .secondary)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(plan.title).fontWeight(.medium)
                                Text(plan.detail).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(plan.price).fontWeight(.semibold).monospacedDigit()
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 8).fill(selected == plan.id ? Theme.accent.opacity(0.08) : Color.clear))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(selected == plan.id ? Theme.accent : Theme.separator, lineWidth: selected == plan.id ? 1.5 : 0.5))
                        .contentShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
            }

            Button {
                guard let product = purchases.products.first(where: { $0.id == selected }) else {
                    purchases.message = "Der App Store ist gerade nicht erreichbar. Bitte versuche es später noch einmal."
                    return
                }
                Task {
                    await purchases.buy(product)
                    if purchases.isPro { dismiss() }
                }
            } label: {
                Text(selected == Purchases.lifetime ? "Einmalig kaufen" : "Abonnieren").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(purchases.busy)

            if let message = purchases.message { Text(message).font(.caption).foregroundStyle(.secondary) }

            HStack(spacing: 16) {
                Button("Käufe wiederherstellen") { Task { await purchases.restore() } }
                Link("Nutzungsbedingungen", destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
                Link("Datenschutz", destination: URL(string: "https://rechnungsklar.de/datenschutz")!)
            }
            .buttonStyle(.link)
            .font(.caption)
            Text("Abos verlängern sich automatisch und sind jederzeit in den App-Store-Einstellungen kündbar. E-Rechnungen lesen bleibt immer kostenlos.")
                .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(26)
        .frame(width: 480)
    }

    /// Echte Preise aus dem App Store, sonst die geplanten Standardpreise
    private var plans: [PlanInfo] {
        PlanInfo.fallback.map { plan in
            guard let product = purchases.products.first(where: { $0.id == plan.id }) else { return plan }
            var p = plan
            p.price = product.displayPrice
            return p
        }
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "checkmark").font(.caption.weight(.bold)).foregroundStyle(Theme.accent)
            Text(text)
        }
    }
}

// MARK: - App-Symbol

/// Das App-Symbol: ein Kassenbon mit gezackter Kante auf Petrol, die Summenzeile hervorgehoben.
/// Wird auch zum Erzeugen der Symboldateien (AppIcon.icns) verwendet.
struct AppIconView: View {
    var size: CGFloat

    var body: some View {
        let s = size / 1024
        ZStack {
            RoundedRectangle(cornerRadius: 185 * s, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.09, green: 0.50, blue: 0.47), Color(red: 0.03, green: 0.30, blue: 0.29)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: 824 * s, height: 824 * s)
                .shadow(color: .black.opacity(0.22), radius: 16 * s, y: 9 * s)
            ReceiptShape(teeth: 9)
                .fill(Color(red: 0.99, green: 0.98, blue: 0.95))
                .frame(width: 470 * s, height: 600 * s)
                .shadow(color: .black.opacity(0.18), radius: 12 * s, y: 6 * s)
                .overlay(alignment: .top) {
                    VStack(alignment: .leading, spacing: 30 * s) {
                        Capsule().fill(Color(white: 0.2)).frame(width: 150 * s, height: 26 * s)
                        ForEach(0..<3) { i in
                            HStack {
                                Capsule().fill(Color(white: 0.78)).frame(width: [200, 240, 170][i] * s, height: 18 * s)
                                Spacer()
                                Capsule().fill(Color(white: 0.78)).frame(width: 70 * s, height: 18 * s)
                            }
                        }
                        Rectangle().fill(Color(white: 0.2)).frame(height: 6 * s).padding(.top, 8 * s)
                        HStack {
                            Spacer()
                            Capsule().fill(Color(red: 0.05, green: 0.42, blue: 0.40)).frame(width: 150 * s, height: 30 * s)
                        }
                    }
                    .frame(width: 350 * s)
                    .padding(.top, 78 * s)
                }
        }
        .frame(width: size, height: size)
    }
}

/// Rechteck mit gezackter Unterkante wie ein abgerissener Bon
struct ReceiptShape: Shape {
    var teeth: Int

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let toothWidth = rect.width / CGFloat(teeth)
        let depth = toothWidth * 0.45
        let corner = rect.width * 0.05
        p.move(to: CGPoint(x: rect.minX, y: rect.minY + corner))
        p.addQuadCurve(to: CGPoint(x: rect.minX + corner, y: rect.minY), control: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - corner, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + corner), control: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - depth))
        for i in stride(from: teeth, to: 0, by: -1) {
            let x = rect.minX + CGFloat(i) * toothWidth
            p.addLine(to: CGPoint(x: x - toothWidth / 2, y: rect.maxY))
            p.addLine(to: CGPoint(x: x - toothWidth, y: rect.maxY - depth))
        }
        p.closeSubpath()
        return p
    }
}
