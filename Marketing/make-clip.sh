#!/bin/bash
# Erzeugt den 30-Sekunden-Werbeclip (1080 × 1920, H.264) für Instagram Reels:
#   ./Marketing/make-clip.sh            → build/Rechnungsklar-Reel.mp4
# Braucht die Screenshots aus ./build.sh bzw. build/shots-bin und den H.264-Encoder von macOS
# (in manchen Sandboxen gesperrt – dann im normalen Terminal ausführen).
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
if [ ! -f build/shots/4c-eingang-ganz.png ]; then
  ./build.sh > /dev/null
  build/shots-bin build/shots > /dev/null 2>&1
fi
echo "→ Kompiliere Clip-Generator …"
swiftc -O -swift-version 5 -target "$(uname -m)-apple-macos14.0" -module-cache-path build/ModuleCache \
  $(ls Sources/*.swift | grep -v RechnungsklarApp.swift) Marketing/Clip/Music.swift Marketing/Clip/main.swift -o build/clip-bin
echo "→ Musik, 900 Bilder und Kodierung …"
build/clip-bin --music build/Rechnungsklar-Musik.wav
build/clip-bin build/shots build/Rechnungsklar-Reel.mp4
