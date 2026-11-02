import AppKit
import AVFoundation
import SwiftUI

// 30-Sekunden-Werbeclip für Instagram Reels (1080 × 1920, 30 fps), gebaut aus den echten App-Screenshots.
//   clip <shots-Ordner> <ausgabe.mp4>              rendert alle Bilder und kodiert das Video (braucht AVFoundation/H.264)
//   clip <shots-Ordner> --preview <ordner>          schreibt nur Standbilder an wichtigen Stellen (zur Kontrolle)
//   clip --music <ausgabe.wav>                      schreibt nur den Musiktrack (eigene Komposition, siehe Music.swift)

let width = 1080, height = 1920, fps = 30
let duration = 30.0

// MARK: Zeitfunktionen

func clamp(_ x: Double) -> Double { min(1, max(0, x)) }
func progress(_ t: Double, _ a: Double, _ b: Double) -> Double { clamp((t - a) / (b - a)) }
func ease(_ x: Double) -> Double { let t = clamp(x); return t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2 }
func easeOut(_ x: Double) -> Double { 1 - pow(1 - clamp(x), 3) }

let ink = Color(white: 0.09)
let paper = Color(red: 0.96, green: 0.95, blue: 0.92)
let petrol = Theme.accent

// MARK: Bausteine

/// Text, der von unten einschwebt
struct Rise: ViewModifier {
    var p: Double
    func body(content: Content) -> some View {
        content.opacity(easeOut(p)).offset(y: (1 - easeOut(p)) * 40)
    }
}

extension View {
    func rise(_ p: Double) -> some View { modifier(Rise(p: p)) }
}

/// Ausschnitt eines Screenshots (Bruchteile 0…1) als Bild mit Fensterrahmen
struct Shot: View {
    var image: CGImage
    var crop: CGRect
    var width: CGFloat
    var zoom: Double = 1

    var body: some View {
        let rect = CGRect(x: crop.minX * CGFloat(image.width), y: crop.minY * CGFloat(image.height),
                          width: crop.width * CGFloat(image.width), height: crop.height * CGFloat(image.height))
        let cropped = image.cropping(to: rect.integral) ?? image
        let h = width * CGFloat(cropped.height) / CGFloat(cropped.width)
        return Image(decorative: cropped, scale: 1)
            .resizable()
            .interpolation(.high)
            .frame(width: width, height: h)
            .scaleEffect(zoom)
            .frame(width: width, height: h)
            .clipShape(RoundedRectangle(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(Color.black.opacity(0.08), lineWidth: 2))
            .shadow(color: .black.opacity(0.16), radius: 30, y: 16)
    }
}

struct Headline: View {
    var text: String
    var size: CGFloat = 78
    var color: Color = ink

    var body: some View {
        Text(text).font(.system(size: size, weight: .bold)).foregroundStyle(color)
            .multilineTextAlignment(.center).lineSpacing(2).fixedSize(horizontal: false, vertical: true)
    }
}

struct Sub: View {
    var text: String
    var body: some View {
        Text(text).font(.system(size: 40, weight: .medium)).foregroundStyle(Color(white: 0.35))
            .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: Szenen

struct Assets {
    var incoming: CGImage
    var editor: CGImage
    var overview: CGImage
    var page: CGImage
    var xmlLines: [String]
}

struct ClipFrame: View {
    var t: Double
    var a: Assets

    struct Scene { var start: Double; var end: Double }
    static let scenes = [Scene(start: 0, end: 3.2), Scene(start: 3.2, end: 7.4), Scene(start: 7.4, end: 12.2),
                         Scene(start: 12.2, end: 17.6), Scene(start: 17.6, end: 22.4), Scene(start: 22.4, end: 26.6),
                         Scene(start: 26.6, end: 30.0)]
    static let fade = 0.35

    var body: some View {
        ZStack {
            paper
            ForEach(Array(Self.scenes.enumerated()), id: \.offset) { index, scene in
                let local = t - scene.start
                let visible = t >= scene.start - Self.fade && t <= scene.end + Self.fade
                if visible {
                    let fadeIn = index == 0 ? 1 : ease(progress(t, scene.start - Self.fade, scene.start + Self.fade))
                    let fadeOut = index == Self.scenes.count - 1 ? 1 : 1 - ease(progress(t, scene.end - Self.fade, scene.end + Self.fade))
                    view(for: index, local: local, length: scene.end - scene.start)
                        .opacity(fadeIn * fadeOut)
                }
            }
        }
        .frame(width: CGFloat(width), height: CGFloat(height))
        .environment(\.colorScheme, .light)
    }

    @ViewBuilder func view(for index: Int, local s: Double, length: Double) -> some View {
        switch index {
        case 0: hook(s)
        case 1: xml(s)
        case 2: readable(s, length)
        case 3: writing(s, length)
        case 4: pdf(s, length)
        case 5: overview(s, length)
        default: outro(s)
        }
    }

    // 0: Aufhänger
    func hook(_ s: Double) -> some View {
        VStack(spacing: 18) {
            Text("Ab 2028").font(.system(size: 150, weight: .heavy)).foregroundStyle(petrol).rise(progress(s, 0.0, 0.5))
            Headline(text: "ist die PDF-Rechnung").rise(progress(s, 0.45, 0.95))
            Headline(text: "Geschichte.").rise(progress(s, 0.9, 1.4))
            Sub(text: "Die E-Rechnungs-Pflicht kommt –\nfür jedes Unternehmen.").padding(.top, 40).rise(progress(s, 1.5, 2.1))
        }
        .padding(.horizontal, 70)
    }

    // 1: So sieht eine XRechnung aus
    func xml(_ s: Double) -> some View {
        // Nur die sichtbaren Zeilen zeichnen – Zuschneiden greift beim Rendern in Bilder nicht zuverlässig
        let lineHeight: CGFloat = 34
        let visibleLines = 27
        let scroll = s * 2.1
        let first = Int(scroll)
        let lines = (0..<visibleLines).map { a.xmlLines[(first + $0) % a.xmlLines.count] }
        return VStack(spacing: 40) {
            Headline(text: "So sieht eine\nE-Rechnung aus:", size: 70).rise(progress(s, 0, 0.5))
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                    Text(line).font(.system(size: 22, design: .monospaced)).foregroundStyle(Color(red: 0.62, green: 0.86, blue: 0.74))
                        .lineLimit(1).frame(width: 884, height: lineHeight, alignment: .leading)
                        .opacity(index == 0 ? 1 - (scroll - Double(first)) : index == visibleLines - 1 ? scroll - Double(first) : 1)
                }
            }
            .padding(28)
            .frame(width: 940, height: 1000, alignment: .topLeading)
            .background(Color(red: 0.11, green: 0.12, blue: 0.14), in: RoundedRectangle(cornerRadius: 22))
            .rise(progress(s, 0.2, 0.8))
            Text("Unlesbar.").font(.system(size: 70, weight: .heavy)).foregroundStyle(Theme.overdue)
                .scaleEffect(1 + 0.25 * (1 - easeOut(progress(s, 2.2, 2.6))))
                .opacity(easeOut(progress(s, 2.2, 2.5)))
        }
    }

    // 2: Rechnungsklar macht sie lesbar
    func readable(_ s: Double, _ length: Double) -> some View {
        VStack(spacing: 34) {
            Headline(text: "Rechnungsklar macht\ndaraus eine Rechnung.", size: 64).rise(progress(s, 0, 0.5))
            Shot(image: a.incoming, crop: CGRect(x: 0.432, y: 0.112, width: 0.556, height: 0.58), width: 980,
                 zoom: 1 + 0.05 * progress(s, 0, length))
                .rise(progress(s, 0.3, 0.9))
            Sub(text: "Summen geprüft. Bezahlen per GiroCode.").rise(progress(s, 1.2, 1.7))
        }
    }

    // 3: Rechnungen schreiben
    func writing(_ s: Double, _ length: Double) -> some View {
        VStack(spacing: 34) {
            Headline(text: "Eigene Rechnungen?\nIn einer Minute.", size: 66).rise(progress(s, 0, 0.5))
            Shot(image: a.editor, crop: CGRect(x: 0.448, y: 0.395, width: 0.522, height: 0.30), width: 1000,
                 zoom: 1 + 0.06 * progress(s, 0, length))
                .rise(progress(s, 0.3, 0.9))
            HStack(spacing: 14) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.paid)
                Text("Prüft jede Pflichtangabe").foregroundStyle(ink)
            }
            .font(.system(size: 44, weight: .semibold))
            .rise(progress(s, 1.6, 2.1))
            Sub(text: "Kleinunternehmer, 19 %, 7 %, Reverse Charge").rise(progress(s, 2.2, 2.7))
        }
    }

    // 4: PDF und XRechnung
    func pdf(_ s: Double, _ length: Double) -> some View {
        let w: CGFloat = 760
        let h = w * CGFloat(a.page.height) / CGFloat(a.page.width)
        return VStack(spacing: 40) {
            Headline(text: "PDF und XRechnung.\nMit einem Klick.", size: 66).rise(progress(s, 0, 0.5))
            ZStack(alignment: .bottomTrailing) {
                Image(decorative: a.page, scale: 1).resizable().interpolation(.high).frame(width: w, height: h)
                    .shadow(color: .black.opacity(0.18), radius: 30, y: 16)
                    .rotationEffect(.degrees(-2 + 2 * ease(progress(s, 0.3, 1.2))))
                    .scaleEffect(1.02 + 0.04 * progress(s, 0, length))
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.seal.fill").foregroundStyle(.white)
                    Text("XRechnung 3.0 · KoSIT-geprüft").foregroundStyle(.white)
                }
                .font(.system(size: 32, weight: .bold))
                .padding(.horizontal, 26).padding(.vertical, 18)
                .background(petrol, in: Capsule())
                .offset(x: 40, y: 30)
                .scaleEffect(0.6 + 0.4 * easeOut(progress(s, 1.3, 1.8)))
                .opacity(easeOut(progress(s, 1.3, 1.6)))
            }
            .rise(progress(s, 0.2, 0.8))
        }
    }

    // 5: Überblick
    func overview(_ s: Double, _ length: Double) -> some View {
        VStack(spacing: 34) {
            Headline(text: "Wissen, wer noch\nzahlen muss.", size: 70).rise(progress(s, 0, 0.5))
            Shot(image: a.overview, crop: CGRect(x: 0.208, y: 0.155, width: 0.742, height: 0.11), width: 1000)
                .rise(progress(s, 0.3, 0.8))
            Shot(image: a.overview, crop: CGRect(x: 0.208, y: 0.56, width: 0.37, height: 0.235), width: 860,
                 zoom: 1 + 0.04 * progress(s, 0, length))
                .rise(progress(s, 0.7, 1.2))
            Sub(text: "Erinnerungen in drei Stufen – vorformuliert.").rise(progress(s, 1.5, 2.0))
        }
    }

    // 6: Abspann
    func outro(_ s: Double) -> some View {
        VStack(spacing: 30) {
            AppIconView(size: 300)
                .scaleEffect(0.8 + 0.2 * easeOut(progress(s, 0, 0.6)))
                .opacity(easeOut(progress(s, 0, 0.4)))
            Text("Rechnungsklar").font(.system(size: 96, weight: .heavy)).foregroundStyle(ink).rise(progress(s, 0.3, 0.8))
            Sub(text: "E-Rechnungen schreiben und lesen.\nOhne Konto. Ohne Cloud. Auf dem Mac.").rise(progress(s, 0.6, 1.1))
            HStack(spacing: 14) {
                Image(systemName: "apple.logo")
                Text("Kostenlos im Mac App Store")
            }
            .font(.system(size: 40, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 40).padding(.vertical, 24)
            .background(ink, in: Capsule())
            .padding(.top, 30)
            .rise(progress(s, 1.1, 1.6))
        }
    }
}

// MARK: Rendern und Kodieren

@MainActor
func renderFrame(_ t: Double, _ assets: Assets) -> CGImage? {
    let renderer = ImageRenderer(content: ClipFrame(t: t, a: assets))
    renderer.scale = 1
    renderer.proposedSize = ProposedViewSize(width: CGFloat(width), height: CGFloat(height))
    return renderer.cgImage
}

func loadImage(_ path: String) -> CGImage {
    guard let image = NSImage(contentsOfFile: path), let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        FileHandle.standardError.write("Bild fehlt: \(path) – zuerst ./build.sh bzw. die Screenshots erzeugen\n".data(using: .utf8)!)
        exit(1)
    }
    return cg
}

MainActor.assumeIsolated {
    _ = NSApplication.shared
    let args = CommandLine.arguments
    if args.count >= 3, args[1] == "--music" {
        let track = Music.render()
        try? Music.wav(left: track.left, right: track.right).write(to: URL(fileURLWithPath: args[2]))
        print("✓ Musik geschrieben: \(args[2])")
        exit(0)
    }
    guard args.count >= 3 else {
        print("Aufruf: clip <shots-Ordner> <ausgabe.mp4> | clip <shots-Ordner> --preview <ordner>")
        exit(2)
    }
    let shots = args[1]
    let xml = DemoContent.sampleXML().components(separatedBy: "\n").filter { !$0.isEmpty }
    let assets = Assets(incoming: loadImage("\(shots)/4c-eingang-ganz.png"), editor: loadImage("\(shots)/3b-rechnung-bearbeiten-ganz.png"),
                        overview: loadImage("\(shots)/1-uebersicht.png"), page: loadImage("\(shots)/rechnung-seite.png"),
                        xmlLines: xml + xml)

    if args[2] == "--preview" {
        let folder = args.count > 3 ? args[3] : "build/clip-preview"
        try? FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        for t in [1.8, 5.8, 10.0, 15.5, 20.5, 25.0, 29.0] {
            guard let image = renderFrame(t, assets) else { continue }
            let rep = NSBitmapImageRep(cgImage: image)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "\(folder)/bild-\(String(format: "%04.1f", t))s.png"))
            print("  Standbild bei \(t) s")
        }
        exit(0)
    }

    let url = URL(fileURLWithPath: args[2])
    try? FileManager.default.removeItem(at: url)
    guard let writer = try? AVAssetWriter(outputURL: url, fileType: .mp4) else { print("Kann \(url.path) nicht anlegen"); exit(1) }
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
        AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height,
        AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 10_000_000, AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel],
    ])
    input.expectsMediaDataInRealTime = false
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB, kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height,
    ])
    writer.add(input)

    // Tonspur: eigener Musiktrack als AAC
    let music = Music.render()
    let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: [
        AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: Music.sampleRate, AVNumberOfChannelsKey: 2, AVEncoderBitRateKey: 256_000,
    ])
    audioInput.expectsMediaDataInRealTime = false
    writer.add(audioInput)
    var audioFormat: CMAudioFormatDescription?
    var asbd = AudioStreamBasicDescription(mSampleRate: Float64(Music.sampleRate), mFormatID: kAudioFormatLinearPCM,
                                           mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked, mBytesPerPacket: 8,
                                           mFramesPerPacket: 1, mBytesPerFrame: 8, mChannelsPerFrame: 2, mBitsPerChannel: 32, mReserved: 0)
    CMAudioFormatDescriptionCreate(allocator: nil, asbd: &asbd, layoutSize: 0, layout: nil, magicCookieSize: 0, magicCookie: nil,
                                   extensions: nil, formatDescriptionOut: &audioFormat)
    var audioFramesWritten = 0
    /// Hängt Ton bis zur Zeit `until` an (in Häppchen von 0,1 s), soweit der Encoder bereit ist
    func appendAudio(until seconds: Double) {
        let target = min(music.left.count, Int(seconds * Double(Music.sampleRate)))
        while audioFramesWritten < target && audioInput.isReadyForMoreMediaData {
            let frames = min(4410, target - audioFramesWritten)
            var interleaved = [Float](repeating: 0, count: frames * 2)
            for i in 0..<frames {
                interleaved[2 * i] = music.left[audioFramesWritten + i]
                interleaved[2 * i + 1] = music.right[audioFramesWritten + i]
            }
            let bytes = frames * 8
            var block: CMBlockBuffer?
            CMBlockBufferCreateWithMemoryBlock(allocator: nil, memoryBlock: nil, blockLength: bytes, blockAllocator: nil, customBlockSource: nil,
                                               offsetToData: 0, dataLength: bytes, flags: 0, blockBufferOut: &block)
            guard let block, let audioFormat else { return }
            _ = interleaved.withUnsafeBytes { CMBlockBufferReplaceDataBytes(with: $0.baseAddress!, blockBuffer: block, offsetIntoDestination: 0, dataLength: bytes) }
            var sample: CMSampleBuffer?
            CMAudioSampleBufferCreateReadyWithPacketDescriptions(allocator: nil, dataBuffer: block, formatDescription: audioFormat, sampleCount: frames,
                                                                 presentationTimeStamp: CMTime(value: CMTimeValue(audioFramesWritten), timescale: CMTimeScale(Music.sampleRate)),
                                                                 packetDescriptions: nil, sampleBufferOut: &sample)
            guard let sample else { return }
            guard audioInput.append(sample) else {
                print("Ton konnte nicht angehängt werden: \(writer.error?.localizedDescription ?? "unbekannt")")
                exit(1)
            }
            audioFramesWritten += frames
        }
    }

    guard writer.startWriting() else { print("Video-Encoder nicht verfügbar: \(writer.error?.localizedDescription ?? "")"); exit(1) }
    writer.startSession(atSourceTime: .zero)

    let total = Int(duration * Double(fps))
    for frame in 0..<total {
        guard let image = renderFrame(Double(frame) / Double(fps), assets) else { continue }
        appendAudio(until: Double(frame) / Double(fps) + 1)
        // Wartet das Video, will der Encoder meist mehr Ton im Voraus: dann so viel nachliefern, wie er annimmt
        while !input.isReadyForMoreMediaData {
            if writer.status == .failed { print("Kodieren fehlgeschlagen: \(writer.error?.localizedDescription ?? "")"); exit(1) }
            appendAudio(until: duration + 1)
            RunLoop.current.run(until: Date().addingTimeInterval(0.005))
        }
        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32ARGB, [kCVPixelBufferCGImageCompatibilityKey: true] as CFDictionary, &buffer)
        guard let buffer else { continue }
        CVPixelBufferLockBaseAddress(buffer, [])
        if let context = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: width, height: height, bitsPerComponent: 8,
                                   bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                   bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue) {
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])
        adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(frame), timescale: Int32(fps)))
        if frame % 90 == 0 { print("  \(frame / fps) s von \(Int(duration)) s") }
    }
    print("  Bilder fertig, schreibe restlichen Ton …")
    // Erst den Ton vollständig liefern, dann beide Spuren schließen – sonst wartet der Encoder auf Video, das nicht mehr kommt
    var waited = 0.0
    while audioFramesWritten < music.left.count {
        if writer.status == .failed { print("Kodieren fehlgeschlagen: \(writer.error?.localizedDescription ?? "")"); exit(1) }
        let before = audioFramesWritten
        appendAudio(until: duration + 1)
        if audioFramesWritten == before {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
            waited += 0.01
            if waited > 20 { print("  Ton-Encoder nimmt nichts mehr an (\(audioFramesWritten) von \(music.left.count) Samples) – schließe trotzdem"); break }
        }
    }
    input.markAsFinished()
    audioInput.markAsFinished()
    print("  schließe Datei …")
    var done = false
    writer.finishWriting { done = true }
    while !done { RunLoop.current.run(until: Date().addingTimeInterval(0.05)) }
    if writer.status == .completed {
        print("✓ Fertig: \(url.path)")
    } else {
        print("Kodieren fehlgeschlagen: \(writer.error?.localizedDescription ?? "unbekannt")")
        exit(1)
    }
}
