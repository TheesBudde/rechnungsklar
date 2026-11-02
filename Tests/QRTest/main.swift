import AppKit
import SwiftUI
import Vision

// Erzeugt GiroCodes, zeichnet sie und liest sie mit Apples Vision-Framework zurück
MainActor.assumeIsolated {
    _ = NSApplication.shared
    var failures = 0
    let samples = [
        GiroCode.payload(name: "Lena Hoffmann", iban: "DE89370400440532013000", bic: "COBADEFFXXX", amount: Decimal(string: "5889.20")!, reference: "RE-2026-0015")!,
        GiroCode.payload(name: "Werkhaus Coworking GmbH", iban: "DE02120300000000202051", bic: "", amount: Decimal(string: "522.41")!, reference: "INV-88213")!,
        "kurz",
        String(repeating: "Lange Nutzlast für höhere QR-Versionen ÄÖÜ ", count: 6),
    ]
    for (index, payload) in samples.enumerated() {
        guard let code = QRCode(text: payload) else { print("✗ Kein Code für Probe \(index)"); failures += 1; continue }
        // Matrix und Text für den unabhängigen Prüf-Decoder (Tests/QRTest/decode.py)
        let matrix = code.modules.map { row in String(row.map { $0 ? "1" : "0" }) }.joined(separator: "\n")
        try? matrix.write(toFile: "build/qr-\(index).txt", atomically: false, encoding: .utf8)
        try? payload.write(toFile: "build/qr-\(index).expected", atomically: false, encoding: .utf8)
        let side: CGFloat = 400
        let host = NSHostingView(rootView: QRCodeShape(code: code).frame(width: side, height: side))
        host.frame = NSRect(x: 0, y: 0, width: side, height: side)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
        host.cacheDisplay(in: host.bounds, to: rep)
        if index == 0 { try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "build/girocode-test.png")) }
        let request = VNDetectBarcodesRequest()
        request.symbologies = [.qr]
        request.usesCPUOnly = true
        do {
            try VNImageRequestHandler(cgImage: rep.cgImage!).perform([request])
            let decoded = request.results?.first?.payloadStringValue
            if decoded == payload {
                print("✓ Probe \(index): Version \(code.version), \(payload.utf8.count) Bytes – gelesen und identisch")
            } else {
                print("✗ Probe \(index): gelesen „\(decoded ?? "nichts")“")
                failures += 1
            }
        } catch {
            print("? Vision nicht verfügbar: \(error.localizedDescription)")
            failures += 1
        }
    }
    exit(failures == 0 ? 0 : 1)
}
