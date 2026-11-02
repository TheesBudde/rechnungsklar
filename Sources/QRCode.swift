import SwiftUI

/// QR-Code-Encoder (ISO/IEC 18004) für Byte-Modus und Fehlerkorrektur M – genug für den GiroCode.
/// Nach dem Referenzverfahren von Project Nayuki. Liefert eine Modulmatrix, die als Vektorgrafik
/// gezeichnet wird: scharf im PDF und unabhängig von CoreImage.
struct QRCode {
    let size: Int
    private(set) var modules: [[Bool]]
    private var isFunction: [[Bool]]
    let version: Int

    private static let eccPerBlock = [-1, 10, 16, 26, 18, 24, 16, 18, 22, 22, 26, 30, 22, 22, 24, 24, 28, 28, 26, 26, 26,
                                      26, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28]
    private static let blockCount = [-1, 1, 1, 1, 2, 2, 4, 4, 4, 5, 5, 5, 8, 9, 9, 10, 10, 11, 13, 14, 16,
                                     17, 17, 18, 20, 21, 23, 25, 26, 28, 29, 31, 33, 35, 37, 38, 40, 43, 45, 47, 49]
    /// Formatbits für Fehlerkorrektur M
    private static let eccFormatBits = 0

    init?(text: String) {
        let bytes = Array(text.utf8)
        var chosen = 0
        for v in 1...40 {
            let countBits = v <= 9 ? 8 : 16
            if 4 + countBits + bytes.count * 8 <= Self.dataCodewords(v) * 8 && bytes.count < (1 << countBits) { chosen = v; break }
        }
        guard chosen > 0 else { return nil }
        version = chosen
        size = chosen * 4 + 17
        modules = Array(repeating: Array(repeating: false, count: size), count: size)
        isFunction = modules

        // Datenbits: Modus, Länge, Bytes, Abschluss, Füllbytes
        var bits: [Bool] = []
        func append(_ value: Int, _ length: Int) { for i in stride(from: length - 1, through: 0, by: -1) { bits.append((value >> i) & 1 == 1) } }
        append(0x4, 4)
        append(bytes.count, chosen <= 9 ? 8 : 16)
        bytes.forEach { append(Int($0), 8) }
        let capacity = Self.dataCodewords(chosen) * 8
        append(0, min(4, capacity - bits.count))
        append(0, (8 - bits.count % 8) % 8)
        var pad = 0xEC
        while bits.count < capacity { append(pad, 8); pad ^= 0xEC ^ 0x11 }
        var data = [Int](repeating: 0, count: bits.count / 8)
        for (i, bit) in bits.enumerated() where bit { data[i >> 3] |= 1 << (7 - (i & 7)) }

        drawFunctionPatterns()
        drawCodewords(addECCAndInterleave(data))

        // Maske mit der geringsten Strafpunktzahl wählen
        var best = 0
        var bestPenalty = Int.max
        for mask in 0..<8 {
            applyMask(mask)
            drawFormatBits(mask)
            let p = penalty()
            if p < bestPenalty { best = mask; bestPenalty = p }
            applyMask(mask)
        }
        applyMask(best)
        drawFormatBits(best)
    }

    // MARK: Kapazität

    private static func rawDataModules(_ v: Int) -> Int {
        var result = (16 * v + 128) * v + 64
        if v >= 2 {
            let align = v / 7 + 2
            result -= (25 * align - 10) * align - 55
            if v >= 7 { result -= 36 }
        }
        return result
    }

    private static func dataCodewords(_ v: Int) -> Int { rawDataModules(v) / 8 - eccPerBlock[v] * blockCount[v] }

    // MARK: Funktionsmuster

    private mutating func set(_ x: Int, _ y: Int, _ dark: Bool) {
        modules[y][x] = dark
        isFunction[y][x] = true
    }

    private mutating func drawFunctionPatterns() {
        for i in 0..<size {
            set(6, i, i % 2 == 0)
            set(i, 6, i % 2 == 0)
        }
        drawFinder(3, 3)
        drawFinder(size - 4, 3)
        drawFinder(3, size - 4)
        let positions = alignmentPositions()
        let n = positions.count
        for i in 0..<n {
            for j in 0..<n where !((i == 0 && j == 0) || (i == 0 && j == n - 1) || (i == n - 1 && j == 0)) {
                for dy in -2...2 { for dx in -2...2 { set(positions[i] + dx, positions[j] + dy, max(abs(dx), abs(dy)) != 1) } }
            }
        }
        drawFormatBits(0)
        drawVersion()
    }

    private mutating func drawFinder(_ x: Int, _ y: Int) {
        for dy in -4...4 {
            for dx in -4...4 {
                let xx = x + dx, yy = y + dy
                guard xx >= 0, xx < size, yy >= 0, yy < size else { continue }
                let distance = max(abs(dx), abs(dy))
                set(xx, yy, distance != 2 && distance != 4)
            }
        }
    }

    private func alignmentPositions() -> [Int] {
        guard version > 1 else { return [] }
        let n = version / 7 + 2
        let step = (version * 8 + n * 3 + 5) / (n * 4 - 4) * 2
        var result = [Int](repeating: 0, count: n)
        result[0] = 6
        var pos = size - 7
        for i in stride(from: n - 1, through: 1, by: -1) {
            result[i] = pos
            pos -= step
        }
        return result
    }

    private mutating func drawFormatBits(_ mask: Int) {
        let data = Self.eccFormatBits << 3 | mask
        var rem = data
        for _ in 0..<10 { rem = (rem << 1) ^ ((rem >> 9) * 0x537) }
        let bits = (data << 10 | rem) ^ 0x5412
        func bit(_ i: Int) -> Bool { (bits >> i) & 1 == 1 }
        for i in 0...5 { set(8, i, bit(i)) }
        set(8, 7, bit(6))
        set(8, 8, bit(7))
        set(7, 8, bit(8))
        for i in 9..<15 { set(14 - i, 8, bit(i)) }
        for i in 0..<8 { set(size - 1 - i, 8, bit(i)) }
        for i in 8..<15 { set(8, size - 15 + i, bit(i)) }
        set(8, size - 8, true)
    }

    private mutating func drawVersion() {
        guard version >= 7 else { return }
        var rem = version
        for _ in 0..<12 { rem = (rem << 1) ^ ((rem >> 11) * 0x1F25) }
        let bits = version << 12 | rem
        for i in 0..<18 {
            let dark = (bits >> i) & 1 == 1
            let a = size - 11 + i % 3, b = i / 3
            set(a, b, dark)
            set(b, a, dark)
        }
    }

    // MARK: Fehlerkorrektur (Reed-Solomon über GF(256))

    private func addECCAndInterleave(_ data: [Int]) -> [Int] {
        let blocks = Self.blockCount[version]
        let eccLength = Self.eccPerBlock[version]
        let rawCodewords = Self.rawDataModules(version) / 8
        let shortBlocks = blocks - rawCodewords % blocks
        let shortLength = rawCodewords / blocks
        let divisor = Self.rsDivisor(eccLength)
        var all: [[Int]] = []
        var k = 0
        for i in 0..<blocks {
            let length = shortLength - eccLength + (i < shortBlocks ? 0 : 1)
            var block = Array(data[k..<k + length])
            k += length
            let ecc = Self.rsRemainder(block, divisor)
            if i < shortBlocks { block.append(0) }
            all.append(block + ecc)
        }
        var result: [Int] = []
        for i in 0..<all[0].count {
            for j in 0..<all.count where i != shortLength - eccLength || j >= shortBlocks {
                result.append(all[j][i])
            }
        }
        return result
    }

    private static func rsDivisor(_ degree: Int) -> [Int] {
        var result = [Int](repeating: 0, count: degree)
        result[degree - 1] = 1
        var root = 1
        for _ in 0..<degree {
            for j in 0..<result.count {
                result[j] = gfMultiply(result[j], root)
                if j + 1 < result.count { result[j] ^= result[j + 1] }
            }
            root = gfMultiply(root, 0x02)
        }
        return result
    }

    private static func rsRemainder(_ data: [Int], _ divisor: [Int]) -> [Int] {
        var result = [Int](repeating: 0, count: divisor.count)
        for byte in data {
            let factor = byte ^ result.removeFirst()
            result.append(0)
            for i in 0..<result.count { result[i] ^= gfMultiply(divisor[i], factor) }
        }
        return result
    }

    private static func gfMultiply(_ x: Int, _ y: Int) -> Int {
        var z = 0
        for i in stride(from: 7, through: 0, by: -1) {
            z = (z << 1) ^ ((z >> 7) * 0x11D)
            z ^= ((y >> i) & 1) * x
        }
        return z
    }

    // MARK: Daten platzieren und maskieren

    private mutating func drawCodewords(_ data: [Int]) {
        var i = 0
        var right = size - 1
        while right >= 1 {
            if right == 6 { right = 5 }
            for vert in 0..<size {
                for j in 0..<2 {
                    let x = right - j
                    let upward = (right + 1) & 2 == 0
                    let y = upward ? size - 1 - vert : vert
                    if !isFunction[y][x] && i < data.count * 8 {
                        modules[y][x] = (data[i >> 3] >> (7 - (i & 7))) & 1 == 1
                        i += 1
                    }
                }
            }
            right -= 2
        }
    }

    private mutating func applyMask(_ mask: Int) {
        for y in 0..<size {
            for x in 0..<size where !isFunction[y][x] {
                let invert: Bool
                switch mask {
                case 0: invert = (x + y) % 2 == 0
                case 1: invert = y % 2 == 0
                case 2: invert = x % 3 == 0
                case 3: invert = (x + y) % 3 == 0
                case 4: invert = (x / 3 + y / 2) % 2 == 0
                case 5: invert = x * y % 2 + x * y % 3 == 0
                case 6: invert = (x * y % 2 + x * y % 3) % 2 == 0
                default: invert = ((x + y) % 2 + x * y % 3) % 2 == 0
                }
                if invert { modules[y][x].toggle() }
            }
        }
    }

    /// Vereinfachte Bewertung (Läufe, 2×2-Blöcke, Hell-Dunkel-Verhältnis) – jede Maske ist gültig, diese hilft nur beim Scannen
    private func penalty() -> Int {
        var result = 0
        for line in 0..<size {
            var runRow = 1, runCol = 1
            for i in 1..<size {
                if modules[line][i] == modules[line][i - 1] { runRow += 1 } else { if runRow >= 5 { result += runRow - 2 }; runRow = 1 }
                if modules[i][line] == modules[i - 1][line] { runCol += 1 } else { if runCol >= 5 { result += runCol - 2 }; runCol = 1 }
            }
            if runRow >= 5 { result += runRow - 2 }
            if runCol >= 5 { result += runCol - 2 }
        }
        for y in 0..<size - 1 {
            for x in 0..<size - 1 {
                let c = modules[y][x]
                if c == modules[y][x + 1] && c == modules[y + 1][x] && c == modules[y + 1][x + 1] { result += 3 }
            }
        }
        let dark = modules.reduce(0) { $0 + $1.filter { $0 }.count }
        let total = size * size
        result += (abs(dark * 20 - total * 10) + total - 1) / total * 10
        return result
    }
}

/// Zeichnet einen QR-Code als Vektorpfad mit weißer Ruhezone
struct QRCodeShape: View {
    var code: QRCode
    var quietZone = 3

    var body: some View {
        Canvas { context, canvas in
            let count = CGFloat(code.size + quietZone * 2)
            let cell = min(canvas.width, canvas.height) / count
            context.fill(Path(CGRect(origin: .zero, size: canvas)), with: .color(.white))
            var path = Path()
            for y in 0..<code.size {
                for x in 0..<code.size where code.modules[y][x] {
                    path.addRect(CGRect(x: CGFloat(x + quietZone) * cell, y: CGFloat(y + quietZone) * cell, width: cell, height: cell))
                }
            }
            context.fill(path, with: .color(.black))
        }
    }
}
