#!/bin/bash
# Baut build/Rechnungsklar.app – braucht nur die Xcode Command Line Tools.
# UNIVERSAL=1 baut für Apple Silicon und Intel, DEBUG=1 einen Entwickler-Build (Start mit --pro schaltet Pro frei).
set -euo pipefail
cd "$(dirname "$0")"

APP="build/Rechnungsklar.app"
mkdir -p build
rm -rf "$APP" build/AppIcon.iconset
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
FLAGS=(-O -swift-version 5 -module-cache-path build/ModuleCache)
[ "${DEBUG:-0}" = "1" ] && FLAGS=(-Onone -g -D DEBUG -swift-version 5 -module-cache-path build/ModuleCache)

echo "→ Kompiliere …"
if [ "${UNIVERSAL:-0}" = "1" ]; then
  for arch in arm64 x86_64; do
    swiftc "${FLAGS[@]}" -target "$arch-apple-macos14.0" Sources/*.swift -o "build/Rechnungsklar-$arch"
  done
  lipo -create build/Rechnungsklar-arm64 build/Rechnungsklar-x86_64 -output "$APP/Contents/MacOS/Rechnungsklar"
  rm build/Rechnungsklar-arm64 build/Rechnungsklar-x86_64
else
  swiftc "${FLAGS[@]}" -target "$(uname -m)-apple-macos14.0" Sources/*.swift -o "$APP/Contents/MacOS/Rechnungsklar"
fi

cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/PrivacyInfo.xcprivacy "$APP/Contents/Resources/"
printf "APPL????" > "$APP/Contents/PkgInfo"

echo "→ Erzeuge App-Symbol …"
swiftc -swift-version 5 -D DEBUG -target "$(uname -m)-apple-macos14.0" -module-cache-path build/ModuleCache \
  $(ls Sources/*.swift | grep -v RechnungsklarApp.swift) Tests/Shared/SampleData.swift Tests/Shots/main.swift -o build/shots-bin
build/shots-bin build/shots --icon build/AppIcon.iconset > /dev/null 2>&1
if ! iconutil -c icns build/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns" 2>/dev/null; then
  # iconutil braucht Systemdienste, die in einer Sandbox fehlen – dann die .icns selbst zusammensetzen
  python3 - build/AppIcon.iconset "$APP/Contents/Resources/AppIcon.icns" <<'PY'
import os, struct, sys
source, target = sys.argv[1], sys.argv[2]
types = [("icp4", "16x16"), ("icp5", "32x32"), ("ic11", "16x16@2x"), ("ic12", "32x32@2x"), ("ic07", "128x128"),
         ("ic13", "128x128@2x"), ("ic08", "256x256"), ("ic14", "256x256@2x"), ("ic09", "512x512"), ("ic10", "512x512@2x")]
chunks = b""
for kind, size in types:
    data = open(os.path.join(source, f"icon_{size}.png"), "rb").read()
    chunks += kind.encode() + struct.pack(">I", len(data) + 8) + data
open(target, "wb").write(b"icns" + struct.pack(">I", len(chunks) + 8) + chunks)
PY
fi

echo "→ Signiere (ad hoc, mit Sandbox) …"
codesign --force --sign - --entitlements Resources/Rechnungsklar.entitlements --options runtime "$APP" > /dev/null

echo "✓ Fertig: $APP"
