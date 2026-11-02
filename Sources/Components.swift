import AppKit
import PDFKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Gestaltung

/// Wenige, ruhige Farben: ein Petrol als Markenfarbe, gedeckte Statusfarben
enum Theme {
    /// Im Dunkelmodus heller, damit Links und Knöpfe auf dunklem Grund lesbar bleiben
    static let accent = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 0.22, green: 0.62, blue: 0.58, alpha: 1)
            : NSColor(red: 0.05, green: 0.42, blue: 0.40, alpha: 1)
    })
    static let open = Color(red: 0.84, green: 0.55, blue: 0.10)
    static let overdue = Color(red: 0.80, green: 0.23, blue: 0.20)
    static let paid = Color(red: 0.20, green: 0.56, blue: 0.35)
    static let muted = Color.secondary

    static let separator = Color(nsColor: .separatorColor)
    static let panel = Color(nsColor: .controlBackgroundColor)
}

/// Status als Punkt mit Text – wie in Mail oder Finder, ohne bunte Kapseln
struct StatusLabel: View {
    var text: String
    var color: Color

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(text).foregroundStyle(.secondary)
        }
        .font(.caption)
    }
}

extension Invoice {
    var statusText: String {
        if isCancellation { return "Storno" }
        if isOverdue() { return "Überfällig" }
        return status.label
    }

    var statusColor: Color {
        if isCancellation || status == .cancelled || status == .draft { return Color.secondary.opacity(0.6) }
        if isOverdue() { return Theme.overdue }
        return status == .paid ? Theme.paid : Theme.open
    }

    var statusLabel: StatusLabel { StatusLabel(text: statusText, color: statusColor) }
}

extension IncomingInvoice {
    var statusLabel: StatusLabel {
        if isPaid { return StatusLabel(text: "Bezahlt", color: Theme.paid) }
        if isCreditNote { return StatusLabel(text: "Gutschrift", color: Color.secondary.opacity(0.6)) }
        if isOverdue() { return StatusLabel(text: "Überfällig", color: Theme.overdue) }
        return StatusLabel(text: "Offen", color: Theme.open)
    }
}

/// Zurückhaltende Fläche für zusammengehörige Inhalte
struct Panel<Content: View>: View {
    var title: String?
    var padding: CGFloat = 16
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title { Text(title).font(.headline) }
            content
        }
        .padding(padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.separator.opacity(0.6), lineWidth: 0.5))
    }
}

/// Kleine Beschriftung über einem Eingabefeld
struct Field<Content: View>: View {
    var label: String
    @ViewBuilder var content: Content

    init(_ label: String, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            content
        }
    }
}

struct EmptyState: View {
    var symbol: String
    var title: String
    var message: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 30, weight: .light)).foregroundStyle(.tertiary)
            Text(title).font(.headline)
            Text(message).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 300)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Kopfzeile über Detailansichten: Titel links, Aktionen rechts
struct DetailHeader<Actions: View>: View {
    var title: String
    var subtitle: String
    @ViewBuilder var actions: Actions

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.title3.weight(.semibold)).lineLimit(1)
                Text(subtitle).font(.callout).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 12)
            actions
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) { Divider() }
    }
}

// MARK: - GiroCode (EPC-QR)

/// QR-Code für SEPA-Überweisungen nach EPC069-12. Banking-Apps lesen ihn und füllen die Überweisung aus.
enum GiroCode {
    static func payload(name: String, iban: String, bic: String, amount: Decimal, reference: String) -> String? {
        let cleanIBAN = XRechnungWriter.compact(iban)
        guard IBAN.isValid(cleanIBAN), amount > 0, amount < 1_000_000_000 else { return nil }
        let lines = [
            "BCD", "002", "1", "SCT",
            XRechnungWriter.compact(bic),
            String(name.prefix(70)),
            cleanIBAN,
            "EUR" + XRechnungWriter.amount(amount),
            "", "",
            String(reference.prefix(140)),
        ]
        return lines.joined(separator: "\n")
    }
}

struct GiroCodeView: View {
    var payload: String
    var size: CGFloat = 120

    var body: some View {
        if let code = QRCode(text: payload) {
            QRCodeShape(code: code).frame(width: size, height: size)
        }
    }
}

// MARK: - Dateien sichern, drucken, teilen

@MainActor
enum FileActions {
    /// Sichern-Dialog; schreibt die Daten an den gewählten Ort
    static func save(_ data: Data, suggestedName: String, type: UTType) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedName
        panel.allowedContentTypes = [type]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try data.write(to: url) } catch { NSAlert(error: error).runModal() }
    }

    /// Mehrere Dateien auf einmal in einen gewählten Ordner
    static func saveAll(_ files: [(name: String, data: Data)]) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Hier sichern"
        panel.message = "Wähle einen Ordner für PDF und XRechnung."
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        for file in files {
            do { try file.data.write(to: folder.appendingPathComponent(file.name)) } catch { NSAlert(error: error).runModal(); return }
        }
        NSWorkspace.shared.activateFileViewerSelecting(files.map { folder.appendingPathComponent($0.name) })
    }

    static func chooseFolder(prompt: String, message: String) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = prompt
        panel.message = message
        return panel.runModal() == .OK ? panel.url : nil
    }

    static func temporaryFile(_ data: Data, name: String) -> URL? {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let url = folder.appendingPathComponent(name)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try data.write(to: url)
            return url
        } catch {
            return nil
        }
    }

    /// Druckt ein PDF über den Systemdialog
    static func print(_ data: Data, jobTitle: String) {
        guard let document = PDFDocument(data: data) else { return }
        let info = NSPrintInfo.shared.copy() as? NSPrintInfo ?? NSPrintInfo()
        info.jobDisposition = .spool
        guard let operation = document.printOperation(for: info, scalingMode: .pageScaleToFit, autoRotate: false) else { return }
        operation.jobTitle = jobTitle
        operation.run()
    }

    /// Öffnet eine neue E-Mail in Mail mit Empfänger, Betreff, Text und Anhängen
    static func compose(to recipient: String, subject: String, body: String, attachments: [URL]) {
        if let service = NSSharingService(named: .composeEmail) {
            service.recipients = recipient.isEmpty ? [] : [recipient]
            service.subject = subject
            let items: [Any] = [body as NSString] + attachments.map { $0 as NSURL }
            if service.canPerform(withItems: items) {
                service.perform(withItems: items)
                return
            }
        }
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = recipient
        components.queryItems = [URLQueryItem(name: "subject", value: subject), URLQueryItem(name: "body", value: body)]
        if let url = components.url { NSWorkspace.shared.open(url) }
    }

    static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    /// Logo wählen, auf höchstens 800 px Breite verkleinern und als PNG zurückgeben
    static func chooseLogo() -> Data? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .heic, .tiff]
        panel.message = "Wähle dein Logo (PNG mit transparentem Hintergrund sieht am besten aus)."
        guard panel.runModal() == .OK, let url = panel.url, let image = NSImage(contentsOf: url) else { return nil }
        return LogoImage.normalized(image)
    }
}

enum LogoImage {
    static func normalized(_ image: NSImage, maxWidth: CGFloat = 800) -> Data? {
        guard let source = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let scale = min(1, maxWidth / CGFloat(source.width))
        let width = Int(CGFloat(source.width) * scale), height = Int(CGFloat(source.height) * scale)
        guard width > 0, height > 0,
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .high
        context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let scaled = context.makeImage() else { return nil }
        return NSBitmapImageRep(cgImage: scaled).representation(using: .png, properties: [:])
    }

    static func image(_ data: Data?) -> Image? {
        guard let data, let image = NSImage(data: data) else { return nil }
        return Image(nsImage: image)
    }
}

// MARK: - Eingabe von Beträgen

/// Zahlenfeld, das jede Eingabe sofort übernimmt – nicht erst beim Verlassen des Feldes – und deutsche Schreibweise versteht.
/// So stimmen Summen und Vorschau auch dann, wenn man direkt nach dem Tippen auf „Festschreiben“ klickt.
struct DecimalField: View {
    @Binding var value: Decimal
    /// Bei Geldbeträgen 2, bei Mengen 0 Mindest-Nachkommastellen
    var minimumFractionDigits = 0
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField("", text: $text)
            .focused($focused)
            .onAppear { text = Self.format(value, minimumFractionDigits: minimumFractionDigits) }
            .onChange(of: text) { _, new in
                if let parsed = Self.parse(new), parsed != value { value = parsed }
            }
            .onChange(of: value) { _, new in
                if !focused && Self.parse(text) != new { text = Self.format(new, minimumFractionDigits: minimumFractionDigits) }
            }
            .onChange(of: focused) { _, isFocused in
                if !isFocused { text = Self.format(value, minimumFractionDigits: minimumFractionDigits) }
            }
    }

    static func format(_ value: Decimal, minimumFractionDigits: Int = 0) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: "de_DE")
        f.minimumFractionDigits = minimumFractionDigits
        f.maximumFractionDigits = 4
        return f.string(from: value as NSDecimalNumber) ?? "\(value)"
    }

    /// Versteht „12,5“, „1.450“, „1.450,75“ und auch „12.5“; leer heißt 0, Unsinn wird ignoriert (nil)
    static func parse(_ raw: String) -> Decimal? {
        var s = raw.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "€", with: "")
        if s.isEmpty { return 0 }
        if s.contains(",") {
            s = s.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")
        } else if let dot = s.lastIndex(of: "."), s.filter({ $0 == "." }).count > 1 || s.distance(from: dot, to: s.endIndex) == 4 {
            // „1.450“ oder „1.000.000“: Punkte sind Tausendertrennzeichen
            s = s.replacingOccurrences(of: ".", with: "")
        }
        guard s.allSatisfy({ $0.isNumber || $0 == "." || $0 == "-" }), let value = Decimal(string: s, locale: Locale(identifier: "en_US_POSIX")) else { return nil }
        return value
    }
}


extension FormatStyle where Self == Decimal.FormatStyle {
    static var german: Decimal.FormatStyle { Decimal.FormatStyle(locale: Locale(identifier: "de_DE")).precision(.fractionLength(0...4)) }
}

extension DateFormatter {
    static let longGerman: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateFormat = "EEEE, d. MMMM yyyy"
        return f
    }()
}
