"""Unabhängiger Prüf-Decoder für die QR-Matrizen aus QRTest (nur Byte-Modus, ohne Fehlerkorrektur):
liest Formatbits, entfernt die Maske, sammelt die Codewörter im Zickzack, prüft jede Reed-Solomon-Prüfsumme
(alle Syndrome müssen 0 sein) und dekodiert den Text."""
import sys

EXP = [0] * 512
LOG = [0] * 256
x = 1
for i in range(255):
    EXP[i] = x
    LOG[x] = i
    x <<= 1
    if x & 0x100:
        x ^= 0x11D
for i in range(255, 512):
    EXP[i] = EXP[i - 255]

def gmul(a, b):
    return 0 if a == 0 or b == 0 else EXP[LOG[a] + LOG[b]]

ECC = {1: (10, 1), 2: (16, 1), 3: (26, 1), 4: (18, 2), 5: (24, 2), 6: (16, 4), 7: (18, 4), 8: (22, 4), 9: (22, 5), 10: (26, 5), 11: (30, 5), 12: (22, 8), 13: (22, 9), 14: (24, 9), 15: (24, 10)}

def decode(rows):
    n = len(rows)
    m = [[c == "1" for c in r] for r in rows]
    version = (n - 17) // 4
    # Formatbits (erste Kopie) lesen und gegen alle 32 gültigen Codes abgleichen
    bits = 0
    coords = [(8, i) for i in range(6)] + [(8, 7), (8, 8), (7, 8)] + [(14 - i, 8) for i in range(9, 15)]
    for i, (cx, cy) in enumerate(coords):
        bits |= m[cy][cx] << i
    best = None
    for data in range(32):
        rem = data
        for _ in range(10):
            rem = (rem << 1) ^ ((rem >> 9) * 0x537)
        code = ((data << 10) | rem) ^ 0x5412
        dist = bin(code ^ bits).count("1")
        if best is None or dist < best[0]:
            best = (dist, data)
    assert best[0] == 0, "Formatbits beschädigt"
    ecl, mask = best[1] >> 3, best[1] & 7
    assert ecl == 0, "Fehlerkorrektur ist nicht M"
    # Funktionsbereiche markieren
    func = [[False] * n for _ in range(n)]
    def mark(x0, y0, w, h):
        for yy in range(max(0, y0), min(n, y0 + h)):
            for xx in range(max(0, x0), min(n, x0 + w)):
                func[yy][xx] = True
    mark(0, 0, 9, 9); mark(n - 8, 0, 8, 9); mark(0, n - 8, 9, 8)
    mark(6, 0, 1, n); mark(0, 6, n, 1)
    if version > 1:
        k = version // 7 + 2
        step = (version * 8 + k * 3 + 5) // (k * 4 - 4) * 2
        pos = [6] + sorted([n - 7 - i * step for i in range(k - 1)])
        for a in pos:
            for b in pos:
                if (a, b) in [(6, 6), (6, pos[-1]), (pos[-1], 6)]:
                    continue
                mark(a - 2, b - 2, 5, 5)
    if version >= 7:
        mark(n - 11, 0, 3, 6); mark(0, n - 11, 6, 3)
    masks = [lambda x, y: (x + y) % 2 == 0, lambda x, y: y % 2 == 0, lambda x, y: x % 3 == 0, lambda x, y: (x + y) % 3 == 0,
             lambda x, y: (x // 3 + y // 2) % 2 == 0, lambda x, y: x * y % 2 + x * y % 3 == 0,
             lambda x, y: (x * y % 2 + x * y % 3) % 2 == 0, lambda x, y: ((x + y) % 2 + x * y % 3) % 2 == 0]
    stream = []
    right = n - 1
    while right >= 1:
        if right == 6:
            right = 5
        for vert in range(n):
            for j in range(2):
                xx = right - j
                upward = ((right + 1) & 2) == 0
                yy = n - 1 - vert if upward else vert
                if not func[yy][xx]:
                    stream.append(m[yy][xx] ^ masks[mask](xx, yy))
        right -= 2
    codewords = [int("".join("1" if b else "0" for b in stream[i:i + 8]), 2) for i in range(0, len(stream) - len(stream) % 8, 8)]
    ecc_len, blocks = ECC[version]
    total = len(codewords)
    short_blocks = blocks - total % blocks
    short_len = total // blocks
    lengths = [short_len if i < short_blocks else short_len + 1 for i in range(blocks)]
    data_lengths = [l - ecc_len for l in lengths]
    blk = [[] for _ in range(blocks)]
    idx = 0
    for i in range(max(data_lengths)):
        for b in range(blocks):
            if i < data_lengths[b]:
                blk[b].append(codewords[idx]); idx += 1
    for i in range(ecc_len):
        for b in range(blocks):
            blk[b].append(codewords[idx]); idx += 1
    data = []
    for b, block in enumerate(blk):
        for i in range(ecc_len):
            s = 0
            for c in block:
                s = gmul(s, EXP[i]) ^ c
            assert s == 0, f"Reed-Solomon-Syndrom {i} in Block {b} ist nicht 0"
        data += block[:data_lengths[b]]
    bitstr = "".join(f"{c:08b}" for c in data)
    assert bitstr[:4] == "0100", "kein Byte-Modus"
    count_bits = 8 if version <= 9 else 16
    length = int(bitstr[4:4 + count_bits], 2)
    start = 4 + count_bits
    raw = bytes(int(bitstr[start + 8 * i:start + 8 * i + 8], 2) for i in range(length))
    return version, mask, raw.decode("utf-8")

ok = True
for index in range(int(sys.argv[2]) if len(sys.argv) > 2 else 4):
    rows = open(f"{sys.argv[1]}/qr-{index}.txt").read().split("\n")
    expected = open(f"{sys.argv[1]}/qr-{index}.expected").read()
    try:
        version, mask, text = decode(rows)
        good = text == expected
        ok &= good
        print(("✓" if good else "✗"), f"Probe {index}: Version {version}, Maske {mask}, Text {'identisch' if good else 'abweichend: ' + repr(text)}")
    except AssertionError as e:
        ok = False
        print("✗", f"Probe {index}:", e)
sys.exit(0 if ok else 1)
