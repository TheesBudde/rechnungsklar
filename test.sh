#!/bin/bash
# Führt alle Prüfungen aus: Rechenlogik und XRechnung, GiroCode (QR) und – wenn KOSIT_DIR gesetzt ist –
# die offizielle Validierung der erzeugten XRechnungen mit dem KoSIT-Validator.
#
#   KOSIT_DIR=~/kosit ./test.sh
#   (KOSIT_DIR enthält validator.jar und den entpackten Ordner config/ der XRechnung-Konfiguration)
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p build

echo "== Rechenlogik, XRechnung schreiben und lesen"
swiftc -swift-version 5 -target "$(uname -m)-apple-macos14.0" -module-cache-path build/ModuleCache \
  $(ls Sources/*.swift | grep -v RechnungsklarApp.swift) Tests/Shared/SampleData.swift Tests/SelfTest/main.swift -o build/selftest-bin
build/selftest-bin build/selftest Tests/Fixtures
cp Tests/Fixtures/ubl-rechnung.xml build/selftest/

echo "== GiroCode: QR-Codes erzeugen und unabhängig dekodieren"
swiftc -swift-version 5 -target "$(uname -m)-apple-macos14.0" -module-cache-path build/ModuleCache \
  Sources/QRCode.swift Sources/Components.swift Sources/Models.swift Sources/XRechnungWriter.swift Sources/InvoiceCheck.swift \
  Tests/QRTest/main.swift -o build/qrtest-bin
build/qrtest-bin > /dev/null 2>&1 || true   # Vision ist in Sandboxen oft nicht verfügbar; maßgeblich ist der Python-Decoder
python3 Tests/QRTest/decode.py build

if [ -n "${KOSIT_DIR:-}" ]; then
  echo "== Offizielle Prüfung mit dem KoSIT-Validator (XRechnung 3.0)"
  mkdir -p build/selftest/report
  "${JAVA:-java}" -jar "$KOSIT_DIR/validator.jar" -s "$KOSIT_DIR/config/scenarios.xml" -r "$KOSIT_DIR/config" \
    -o build/selftest/report -h build/selftest/*.xml
else
  echo "(KoSIT-Validierung übersprungen – KOSIT_DIR setzen, siehe Kopf dieser Datei)"
fi
