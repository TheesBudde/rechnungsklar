import SwiftUI

struct CustomersView: View {
    @EnvironmentObject var store: DataStore
    @EnvironmentObject var nav: Navigation
    @State private var search = ""

    private var filtered: [Customer] {
        store.customers.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || $0.city.localizedCaseInsensitiveContains(search) }
            .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        HSplitView {
            List(selection: $nav.customerID) {
                ForEach(filtered) { customer in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(customer.name.isEmpty ? "Neuer Kunde" : customer.name).fontWeight(.medium).lineLimit(1)
                        Text([customer.city, revenueText(customer)].filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                    .tag(customer.id)
                }
            }
            .overlay {
                if filtered.isEmpty {
                    EmptyState(symbol: "person.2", title: search.isEmpty ? "Noch keine Kunden" : "Nichts gefunden",
                               message: search.isEmpty ? "Kunden werden beim Festschreiben einer Rechnung automatisch gemerkt." : "Kein Kunde passt zur Suche.")
                }
            }
            .frame(minWidth: 240, idealWidth: 280, maxWidth: 360)

            Group {
                if let index = store.customers.firstIndex(where: { $0.id == nav.customerID }) {
                    CustomerDetail(customer: $store.customers[index]).id(store.customers[index].id)
                } else {
                    EmptyState(symbol: "person.crop.rectangle", title: "Kein Kunde ausgewählt", message: "Wähle links einen Kunden oder lege einen neuen an.")
                }
            }
            .frame(minWidth: 520, maxWidth: .infinity, maxHeight: .infinity)
        }
        .searchable(text: $search, placement: .toolbar, prompt: "Kunden suchen")
        .navigationTitle("Kunden")
        .toolbar {
            Button {
                let customer = Customer()
                store.customers.append(customer)
                nav.customerID = customer.id
            } label: { Label("Neuer Kunde", systemImage: "person.badge.plus") }
        }
    }

    private func revenueText(_ customer: Customer) -> String {
        let total = store.invoices.filter { $0.customer.id == customer.id && $0.status != .draft }.reduce(Decimal(0)) { $0 + $1.signedNet }
        return total != 0 ? "\(Money.format(total)) netto" : ""
    }
}

struct CustomerDetail: View {
    @EnvironmentObject var store: DataStore
    @EnvironmentObject var nav: Navigation
    @Binding var customer: Customer
    @State private var confirmDelete = false

    private var invoices: [Invoice] {
        store.invoices.filter { $0.customer.id == customer.id && $0.status != .draft }.sorted { $0.issueDate > $1.issueDate }
    }

    var body: some View {
        VStack(spacing: 0) {
            DetailHeader(title: customer.name.isEmpty ? "Neuer Kunde" : customer.name,
                         subtitle: invoices.isEmpty ? "Noch keine Rechnungen" : "\(invoices.count) Rechnungen · \(Money.format(invoices.reduce(0) { $0 + $1.signedNet })) netto") {
                Button("Neue Rechnung") { nav.newInvoice(in: store, for: customer) }
                    .buttonStyle(.borderedProminent)
                    .disabled(customer.name.isEmpty)
            }
            Form {
                Section("Anschrift") {
                    TextField("Firma oder Name", text: $customer.name)
                    TextField("Ansprechperson", text: $customer.contactPerson)
                    TextField("Straße und Hausnummer", text: $customer.street)
                    TextField("PLZ", text: $customer.zip)
                    TextField("Ort", text: $customer.city)
                    TextField("Land (ISO-Code, z. B. DE)", text: $customer.country)
                }
                Section {
                    TextField("E-Mail für Rechnungen", text: $customer.email)
                    TextField("USt-IdNr.", text: $customer.vatID)
                    TextField("Leitweg-ID oder Referenz", text: $customer.buyerReference)
                } header: {
                    Text("Für E-Rechnungen")
                } footer: {
                    Text("Die E-Mail ist in der XRechnung Pflicht. Behörden geben eine Leitweg-ID vor, die auf jede Rechnung muss.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Notizen") {
                    TextField("Notizen", text: $customer.notes, axis: .vertical).lineLimit(3...8).labelsHidden()
                }
                if !invoices.isEmpty {
                    Section("Rechnungen") {
                        ForEach(invoices) { invoice in
                            Button { nav.show(invoice) } label: {
                                HStack {
                                    Text(invoice.number).monospacedDigit()
                                    Text(DateText.format(invoice.issueDate)).foregroundStyle(.secondary)
                                    Spacer()
                                    invoice.statusLabel
                                    Text(Money.format(invoice.signedGross)).monospacedDigit().frame(width: 100, alignment: .trailing)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                Section {
                    Button("Kunde löschen …", role: .destructive) { confirmDelete = true }
                        .disabled(!invoices.isEmpty)
                        .help(invoices.isEmpty ? "Kunde entfernen" : "Kunden mit Rechnungen bleiben erhalten")
                }
            }
            .formStyle(.grouped)
        }
        .confirmationDialog("„\(customer.name)“ löschen?", isPresented: $confirmDelete) {
            Button("Löschen", role: .destructive) {
                let id = customer.id
                nav.customerID = nil
                store.customers.removeAll { $0.id == id }
            }
        }
    }
}
