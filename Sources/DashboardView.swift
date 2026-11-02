import Charts
import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var store: DataStore
    @EnvironmentObject var nav: Navigation
    @EnvironmentObject var purchases: Purchases
    var today = Date()

    private var year: Int { Calendar.current.component(.year, from: today) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                if !store.company.missingEssentials.isEmpty { setupNotice }
                figures
                Panel(title: "Umsatz \(String(year))") { revenueChart }
                HStack(alignment: .top, spacing: 18) {
                    Panel(title: "Offene Rechnungen") { receivables }
                    Panel(title: "Zu bezahlen") { payables }
                }
                Text("E-Rechnungs-Pflicht: Empfang seit 1.1.2025, Versand ab 1.1.2028 (bei über 800.000 € Vorjahresumsatz ab 1.1.2027). Rechnungsklar erzeugt XRechnung 3.0, geprüft mit dem Validator der KoSIT.")
                    .font(.caption).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true)
            }
            .padding(28)
            .frame(maxWidth: 1100, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Übersicht")
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Übersicht").font(.system(size: 26, weight: .bold))
                Text(DateFormatter.longGerman.string(from: today)).foregroundStyle(.secondary)
            }
            Spacer()
            Button("E-Rechnung öffnen …") { Importer.showOpenPanel(store: store, nav: nav) }
            Button("Neue Rechnung") { nav.newInvoice(in: store) }
                .buttonStyle(.borderedProminent)
        }
    }

    private var setupNotice: some View {
        HStack(spacing: 12) {
            Image(systemName: "building.2").font(.title3).foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text("Firmendaten vervollständigen").fontWeight(.semibold)
                Text("Für gültige E-Rechnungen fehlt noch: \(store.company.missingEssentials.joined(separator: ", ")).")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            SettingsLink { Text("Einstellungen öffnen") }
        }
        .padding(14)
        .background(Theme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }

    /// Vier Kennzahlen in einer Reihe, durch feine Linien getrennt
    private var figures: some View {
        let overdue = store.overdueInvoices
        let open = store.openInvoices
        return HStack(spacing: 0) {
            figure("Offen", Money.format(store.openReceivables), open.isEmpty ? "keine offenen Rechnungen" : "\(open.count) \(open.count == 1 ? "Rechnung" : "Rechnungen")")
            Divider().padding(.vertical, 6)
            figure("Überfällig", Money.format(overdue.reduce(0) { $0 + $1.grossTotal }),
                   overdue.isEmpty ? "alles pünktlich" : "\(overdue.count) zum Erinnern", highlight: !overdue.isEmpty)
            Divider().padding(.vertical, 6)
            figure("Umsatz \(String(year))", Money.format(store.revenue(year: year)), "netto, ohne Entwürfe")
            Divider().padding(.vertical, 6)
            figure("Zu bezahlen", Money.format(store.openPayables),
                   store.unpaidIncoming.isEmpty ? "keine offenen Eingänge" : "\(store.unpaidIncoming.count) Eingangsrechnungen")
        }
        .padding(.vertical, 14)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.separator.opacity(0.6), lineWidth: 0.5))
    }

    private func figure(_ label: String, _ value: String, _ note: String, highlight: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.callout).foregroundStyle(.secondary)
            Text(value).font(.system(size: 22, weight: .semibold)).monospacedDigit()
                .foregroundStyle(highlight ? Theme.overdue : .primary)
                .lineLimit(1).minimumScaleFactor(0.7)
            Text(note).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var revenueChart: some View {
        let currentMonth = Calendar.current.component(.month, from: today)
        let months = ["Jan", "Feb", "Mär", "Apr", "Mai", "Jun", "Jul", "Aug", "Sep", "Okt", "Nov", "Dez"]
        return Chart(store.monthlyRevenue(year: year), id: \.month) { entry in
            BarMark(x: .value("Monat", months[entry.month - 1]), y: .value("Netto", entry.net), width: .ratio(0.55))
                .foregroundStyle(entry.month == currentMonth ? Theme.accent : Theme.accent.opacity(0.35))
                .cornerRadius(2)
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Theme.separator)
                AxisValueLabel { if let v = value.as(Double.self) { Text(v >= 1000 ? "\(Int(v / 1000)) T€" : "\(Int(v)) €") } }
            }
        }
        .chartXAxis { AxisMarks { _ in AxisValueLabel() } }
        .frame(height: 170)
    }

    private var receivables: some View {
        let list = Array(store.openInvoices.prefix(6))
        return VStack(spacing: 0) {
            if list.isEmpty {
                Text("Alle Rechnungen sind bezahlt.").foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
            }
            ForEach(list) { invoice in
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(invoice.customer.name).lineLimit(1)
                        Text(dueText(invoice)).font(.caption).foregroundStyle(invoice.isOverdue(on: today) ? Theme.overdue : .secondary)
                    }
                    Spacer()
                    Text(Money.format(invoice.grossTotal)).monospacedDigit()
                    Menu {
                        Button("Öffnen") { nav.show(invoice) }
                        Button("Als bezahlt markieren") { store.setPaid(invoice, paid: true) }
                        if invoice.isOverdue(on: today) {
                            Button("Zahlungserinnerung …") { nav.requirePro(purchases) { nav.reminderFor = invoice } }
                        }
                    } label: { Image(systemName: "ellipsis") }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                }
                .padding(.vertical, 7)
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { nav.show(invoice) }
                if invoice.id != list.last?.id { Divider() }
            }
        }
    }

    private func dueText(_ invoice: Invoice) -> String {
        if invoice.isOverdue(on: today) { return "\(invoice.number) · seit \(invoice.daysOverdue(on: today)) Tagen überfällig" }
        return "\(invoice.number) · fällig \(DateText.format(invoice.dueDate))"
    }

    private var payables: some View {
        let list = Array(store.unpaidIncoming.prefix(6))
        return VStack(spacing: 0) {
            if list.isEmpty {
                Text("Nichts zu bezahlen.").foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
            }
            ForEach(list) { invoice in
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(invoice.seller.name).lineLimit(1)
                        Text("\(invoice.number) · fällig \(DateText.format(invoice.dueDate))").font(.caption)
                            .foregroundStyle(invoice.isOverdue(on: today) ? Theme.overdue : .secondary)
                    }
                    Spacer()
                    Text(Money.format(invoice.dueAmount, currency: invoice.currency)).monospacedDigit()
                    Button { nav.section = .incoming; nav.incomingID = invoice.id } label: { Image(systemName: "chevron.right") }
                        .buttonStyle(.borderless)
                        .help("Im Eingang öffnen")
                }
                .padding(.vertical, 7)
                if invoice.id != list.last?.id { Divider() }
            }
        }
    }
}
