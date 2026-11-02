import Foundation

/// Eigens komponierter, lizenzfreier Musiktrack für den Werbeclip – vollständig synthetisiert, keine fremden Samples.
/// 125 BPM in F-Dur (F – C – Dm – B), so getimt, dass der Drop bei 7,4 s (Rechnungsklar zeigt die Rechnung)
/// und der Schluss bei 26,6 s (Logo) genau auf einem Takt liegen.
enum Music {
    static let sampleRate = 44_100
    static let length = 30.0
    static let bpm = 125.0
    static let beat = 60 / bpm                 // 0,48 s
    static let bar = beat * 4                  // 1,92 s
    static let drop = 7.4                      // Szene „lesbar“
    static let outro = 26.6                    // Logo, genau 10 Takte nach dem Drop
    static let unreadable = 5.4                // „Unlesbar.“ erscheint
    static let cuts = [12.2, 17.6, 22.4]       // Szenenwechsel im Groove
    static let gridOrigin = drop - 4 * bar     // Takte so legen, dass der Drop auf „eins“ fällt

    // F, C, Dm, B – Akkordtöne (MIDI) und Grundton im Bass
    static let chords: [[Int]] = [[53, 57, 60], [52, 55, 60], [50, 53, 57], [50, 53, 58]]
    static let roots = [41, 36, 38, 34]

    static func frequency(_ midi: Int) -> Double { 440 * pow(2, Double(midi - 69) / 12) }

    /// Stereo-Samples (links, rechts) als Float im Bereich −1…1
    static func render() -> (left: [Float], right: [Float]) {
        var mix = Mixer(count: Int(length * Double(sampleRate)) + sampleRate)
        var noise = Noise(seed: 2028)

        let barsBeforeDrop = Int(((drop - gridOrigin) / bar).rounded())
        let totalBars = Int(((outro - gridOrigin) / bar).rounded())

        for barIndex in 0..<totalBars {
            let start = gridOrigin + Double(barIndex) * bar
            let chord = barIndex % 4
            let inGroove = barIndex >= barsBeforeDrop
            let intro = !inGroove

            // Fläche: weich, in der Einleitung gedämpfter
            for (voice, note) in chords[chord].enumerated() {
                pad(&mix, start: max(0, start), length: bar + 0.3, frequency: frequency(note),
                    gain: intro ? 0.13 : 0.07, cutoff: intro ? 1200 : 1600, pan: Double(voice - 1) * 0.6)
            }

            // Zupfmelodie: Arpeggio über die Akkordtöne, im Groove in Achteln, davor in Vierteln
            let pattern = [0, 1, 2, 1, 2, 0, 1, 2]
            let steps = inGroove ? 8 : 4
            for step in 0..<steps {
                let t = start + Double(step) * bar / Double(steps)
                guard t >= 0.05 else { continue }
                let note = chords[chord][pattern[step % pattern.count]] + 12
                let lift = inGroove && start >= 17.0 ? 0.03 : 0
                pluck(&mix, &noise, at: t, frequency: frequency(note), gain: (intro ? 0.22 : 0.13) + lift, pan: step % 2 == 0 ? -0.5 : 0.5)
            }

            if inGroove {
                for b in 0..<4 {
                    let t = start + Double(b) * beat
                    kick(&mix, at: t, gain: 0.85)
                    if b == 1 || b == 3 { clap(&mix, &noise, at: t, gain: 0.33) }
                    hat(&mix, &noise, at: t + beat / 2, gain: 0.16, pan: 0.25)
                    hat(&mix, &noise, at: t + beat / 4, gain: 0.055, pan: -0.2)
                    hat(&mix, &noise, at: t + 3 * beat / 4, gain: 0.055, pan: -0.2)
                    // Bass auf den Offbeats, damit er der Bassdrum Platz lässt
                    bass(&mix, at: t + beat / 2, frequency: frequency(roots[chord]), gain: 0.32)
                }
                // ab der zweiten Hälfte: zweite, höhere Zupfstimme für mehr Schwung
                if start >= 17.0 {
                    for step in [0, 3, 6] {
                        let t = start + Double(step) * bar / 8
                        pluck(&mix, &noise, at: t, frequency: frequency(chords[chord][2] + 24), gain: 0.05, pan: 0.5)
                    }
                }
            } else if start >= 3.2 - 0.01 {
                // Spannung vor dem Drop: Ticken in Achteln und ein pochender Grundton auf jedem Schlag
                for b in 0..<8 {
                    let t = start + Double(b) * beat / 2
                    hat(&mix, &noise, at: t, gain: 0.09 + 0.05 * Double(b % 2), pan: b % 2 == 0 ? 0.3 : -0.3)
                }
                for b in 0..<4 {
                    bass(&mix, at: start + Double(b) * beat, frequency: frequency(roots[chord]), gain: 0.24, decay: 0.4)
                }
                kick(&mix, at: start, gain: 0.35)
            } else {
                // ganz am Anfang: weicher Puls, damit der Aufhänger nicht im Leeren steht
                kick(&mix, at: max(0.02, start), gain: 0.3)
                kick(&mix, at: start + 2 * beat, gain: 0.22)
            }
        }

        // „Unlesbar.“: dumpfer Schlag
        boom(&mix, &noise, at: unreadable, gain: 0.38)
        // Riser in den Drop
        riser(&mix, &noise, from: drop - 1.9, to: drop, gain: 0.22)
        // Drop: Einschlag und Becken
        boom(&mix, &noise, at: drop, gain: 0.75)
        crash(&mix, &noise, at: drop, gain: 0.2)
        // Szenenwechsel: kurze Whooshes
        for cut in cuts { whoosh(&mix, &noise, at: cut, gain: 0.12) }

        // Schluss: Akkord anschlagen, Glocke, Fläche ausklingen lassen
        boom(&mix, &noise, at: outro, gain: 0.45)
        for (i, note) in ([41, 53, 57, 60, 65, 69] as [Int]).enumerated() {
            pluck(&mix, &noise, at: outro + Double(i) * 0.035, frequency: frequency(note + 12), gain: 0.2, pan: Double(i) / 5 - 0.5, sustain: 0.9985)
        }
        for (voice, note) in chords[0].enumerated() {
            pad(&mix, start: outro, length: length - outro, frequency: frequency(note), gain: 0.17, cutoff: 1400, pan: Double(voice - 1) * 0.6, release: 1.4)
        }
        bell(&mix, at: outro + 0.5, frequency: frequency(81), gain: 0.13)
        bell(&mix, at: outro + 1.4, frequency: frequency(77), gain: 0.1)

        return mix.master(length: length, fadeOut: 0.9)
    }

    // MARK: Klangerzeuger

    struct Noise {
        var state: UInt64
        init(seed: UInt64) { state = seed }
        mutating func next() -> Double {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Double(Int64(bitPattern: state >> 1) % 2_000_000) / 1_000_000 - 1
        }
    }

    struct Mixer {
        var left: [Double]
        var right: [Double]
        init(count: Int) { left = Array(repeating: 0, count: count); right = left }

        mutating func add(_ index: Int, _ value: Double, pan: Double = 0) {
            guard index >= 0, index < left.count else { return }
            left[index] += value * (1 - max(0, pan))
            right[index] += value * (1 + min(0, pan))
        }

        /// Sanfte Sättigung, Normalisierung auf −1 dBFS, Ein- und Ausblenden
        func master(length: Double, fadeOut: Double) -> (left: [Float], right: [Float]) {
            let count = Int(length * Double(Music.sampleRate))
            let peak = (0..<count).reduce(0.0) { max($0, abs(left[$1]), abs(right[$1])) }
            let drive = peak > 0 ? 1.1 / peak : 1
            func shape(_ x: Double) -> Double { tanh(x * drive) }
            let shapedPeak = tanh(1.1)
            let target = 0.89 / shapedPeak
            var l = [Float](repeating: 0, count: count), r = l
            let fadeStart = Double(count) - fadeOut * Double(Music.sampleRate)
            for i in 0..<count {
                var gain = target
                if i < 2205 { gain *= Double(i) / 2205 }
                if Double(i) > fadeStart { gain *= max(0, (Double(count) - Double(i)) / (fadeOut * Double(Music.sampleRate))) }
                l[i] = Float(shape(left[i]) * gain)
                r[i] = Float(shape(right[i]) * gain)
            }
            return (l, r)
        }
    }

    static func index(_ t: Double) -> Int { Int(t * Double(sampleRate)) }

    static func kick(_ m: inout Mixer, at t: Double, gain: Double) {
        let n = index(0.32)
        var phase = 0.0
        for i in 0..<n {
            let x = Double(i) / Double(sampleRate)
            phase += 2 * .pi * (46 + 85 * exp(-x * 32)) / Double(sampleRate)
            let click = i < 60 ? 0.3 * (1 - Double(i) / 60) : 0
            m.add(index(t) + i, gain * (sin(phase) * exp(-x * 9) + click))
        }
    }

    static func clap(_ m: inout Mixer, _ noise: inout Noise, at t: Double, gain: Double) {
        let n = index(0.22)
        var low1 = 0.0, low2 = 0.0
        for i in 0..<n {
            let x = Double(i) / Double(sampleRate)
            let raw = noise.next()
            low1 += 0.35 * (raw - low1)
            low2 += 0.05 * (raw - low2)
            let band = low1 - low2
            // drei kurze Anschläge wie bei einem echten Klatschen
            let bursts = [0.0, 0.011, 0.022].reduce(0.0) { $0 + (x >= $1 ? exp(-(x - $1) * 70) : 0) } / 3
            let tail = exp(-x * 16)
            m.add(index(t) + i, gain * band * (0.6 * bursts + 0.5 * tail) * 2.2, pan: 0.05)
        }
    }

    static func hat(_ m: inout Mixer, _ noise: inout Noise, at t: Double, gain: Double, pan: Double) {
        let n = index(0.06)
        var previous = 0.0
        for i in 0..<n {
            let x = Double(i) / Double(sampleRate)
            let raw = noise.next()
            let high = raw - previous
            previous = raw
            m.add(index(t) + i, gain * high * exp(-x * 75), pan: pan)
        }
    }

    static func bass(_ m: inout Mixer, at t: Double, frequency f: Double, gain: Double, decay: Double = 0.22) {
        let n = index(decay + 0.05)
        var low = 0.0
        var phase = 0.0
        for i in 0..<n {
            let x = Double(i) / Double(sampleRate)
            phase += f / Double(sampleRate)
            let saw = 2 * (phase - floor(phase + 0.5))
            let sine = sin(2 * .pi * phase)
            low += 0.06 * (0.55 * saw + 0.8 * sine - low)
            let env = min(1, x / 0.004) * exp(-x * (4 / decay))
            m.add(index(t) + i, gain * low * env * 1.8)
        }
    }

    static func pad(_ m: inout Mixer, start: Double, length: Double, frequency f: Double, gain: Double, cutoff: Double, pan: Double, release: Double = 0.3) {
        let n = index(length)
        let detunes = [0.9985, 1.0, 1.0015]
        var phases = [0.13, 0.57, 0.81]
        var low = 0.0
        let coefficient = 1 - exp(-2 * .pi * cutoff / Double(sampleRate))
        for i in 0..<n {
            let x = Double(i) / Double(sampleRate)
            var sum = 0.0
            for (k, d) in detunes.enumerated() {
                phases[k] += f * d / Double(sampleRate)
                sum += 2 * (phases[k] - floor(phases[k] + 0.5))
            }
            low += coefficient * (sum / 3 - low)
            let attack = min(1, x / 0.12)
            let tail = min(1, max(0, (length - x) / release))
            m.add(index(start) + i, gain * low * attack * tail, pan: pan)
        }
    }

    /// Karplus-Strong: gezupfte Saite
    static func pluck(_ m: inout Mixer, _ noise: inout Noise, at t: Double, frequency f: Double, gain: Double, pan: Double, sustain: Double = 0.994) {
        let period = max(2, Int(Double(sampleRate) / f))
        var buffer = (0..<period).map { _ in noise.next() }
        var smoothed = 0.0
        for i in 0..<period { smoothed += 0.5 * (buffer[i] - smoothed); buffer[i] = smoothed }
        let n = index(sustain > 0.997 ? 2.2 : 0.7)
        var pos = 0
        for i in 0..<n {
            let next = (pos + 1) % period
            let value = buffer[pos]
            buffer[pos] = sustain * 0.5 * (buffer[pos] + buffer[next])
            pos = next
            let x = Double(i) / Double(sampleRate)
            m.add(index(t) + i, gain * value * min(1, x / 0.002), pan: pan)
        }
    }

    static func bell(_ m: inout Mixer, at t: Double, frequency f: Double, gain: Double) {
        let n = index(2.4)
        let partials: [(Double, Double, Double)] = [(1, 1, 1.6), (2.76, 0.4, 3), (5.4, 0.2, 5), (8.93, 0.1, 7)]
        for i in 0..<n {
            let x = Double(i) / Double(sampleRate)
            let v = partials.reduce(0.0) { $0 + $1.1 * sin(2 * .pi * f * $1.0 * x) * exp(-x * $1.2) }
            m.add(index(t) + i, gain * v * min(1, x / 0.003), pan: 0.2)
        }
    }

    static func boom(_ m: inout Mixer, _ noise: inout Noise, at t: Double, gain: Double) {
        let n = index(1.2)
        var phase = 0.0
        var low = 0.0
        for i in 0..<n {
            let x = Double(i) / Double(sampleRate)
            phase += 2 * .pi * (38 + 60 * exp(-x * 9)) / Double(sampleRate)
            low += 0.02 * (noise.next() - low)
            m.add(index(t) + i, gain * (sin(phase) * exp(-x * 3.2) + 2.5 * low * exp(-x * 6)))
        }
    }

    static func crash(_ m: inout Mixer, _ noise: inout Noise, at t: Double, gain: Double) {
        let n = index(1.8)
        var previous = 0.0
        for i in 0..<n {
            let x = Double(i) / Double(sampleRate)
            let raw = noise.next()
            let high = raw - 0.6 * previous
            previous = raw
            m.add(index(t) + i, gain * high * exp(-x * 2.6), pan: i % 2 == 0 ? 0.3 : -0.3)
        }
    }

    static func riser(_ m: inout Mixer, _ noise: inout Noise, from a: Double, to b: Double, gain: Double) {
        let n = index(b - a)
        var low = 0.0
        var phase = 0.0
        for i in 0..<n {
            let p = Double(i) / Double(n)
            let cutoff = 200 * pow(40, p)
            low += (1 - exp(-2 * .pi * cutoff / Double(sampleRate))) * (noise.next() - low)
            phase += (220 + 900 * p * p) / Double(sampleRate)
            let v = (low * 1.6 + 0.25 * sin(2 * .pi * phase)) * p * p
            m.add(index(a) + i, gain * v, pan: sin(p * 12) * 0.4)
        }
    }

    static func whoosh(_ m: inout Mixer, _ noise: inout Noise, at cut: Double, gain: Double) {
        let start = cut - 0.45, total = 0.75
        let n = index(total)
        var low = 0.0
        for i in 0..<n {
            let x = Double(i) / Double(sampleRate)
            let p = x / total
            let cutoff = 400 + 5000 * sin(.pi * p)
            low += (1 - exp(-2 * .pi * cutoff / Double(sampleRate))) * (noise.next() - low)
            let env = sin(.pi * min(1, p * 1.25)) * (p < 0.6 ? 1 : max(0, 1 - (p - 0.6) / 0.4))
            m.add(index(start) + i, gain * low * env * 1.8, pan: -0.6 + 1.2 * p)
        }
    }

    // MARK: WAV

    /// 16-Bit-Stereo-WAV ohne Abhängigkeiten
    static func wav(left: [Float], right: [Float]) -> Data {
        var data = Data()
        func append<T: FixedWidthInteger>(_ v: T) { var le = v.littleEndian; data.append(Data(bytes: &le, count: MemoryLayout<T>.size)) }
        let frames = left.count
        let bytes = frames * 4
        data.append(contentsOf: Array("RIFF".utf8)); append(UInt32(36 + bytes))
        data.append(contentsOf: Array("WAVE".utf8)); data.append(contentsOf: Array("fmt ".utf8))
        append(UInt32(16)); append(UInt16(1)); append(UInt16(2)); append(UInt32(sampleRate)); append(UInt32(sampleRate * 4))
        append(UInt16(4)); append(UInt16(16))
        data.append(contentsOf: Array("data".utf8)); append(UInt32(bytes))
        data.reserveCapacity(data.count + bytes)
        for i in 0..<frames {
            append(Int16(max(-1, min(1, left[i])) * 32767))
            append(Int16(max(-1, min(1, right[i])) * 32767))
        }
        return data
    }
}
