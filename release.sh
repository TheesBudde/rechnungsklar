#!/bin/bash
# Baut ein für den Mac App Store signiertes Installationspaket (build/Rechnungsklar.pkg) – ohne Xcode.
# Hochladen danach mit der App „Transporter“ (kostenlos im Mac App Store) oder:
#   xcrun altool --upload-package build/Rechnungsklar.pkg --type macos --apple-id … --password @keychain:AC_PASSWORD
#
# Voraussetzungen (einmalig, siehe docs/APP-STORE.md):
#   - Apple Developer Program (99 €/Jahr)
#   - Zertifikate „3rd Party Mac Developer Application“ und „3rd Party Mac Developer Installer“ (bzw. „Apple Distribution“
#     und „Mac Installer Distribution“) im Schlüsselbund
#   - Provisioning Profile für die Bundle-ID als build/embedded.provisionprofile
#
#   TEAM="Max Mustermann (ABCDE12345)" ./release.sh
set -euo pipefail
cd "$(dirname "$0")"
: "${TEAM:?TEAM setzen, z. B. TEAM=\"Max Mustermann (ABCDE12345)\"}"
APP_CERT="${APP_CERT:-3rd Party Mac Developer Application: $TEAM}"
PKG_CERT="${PKG_CERT:-3rd Party Mac Developer Installer: $TEAM}"
PROFILE="${PROFILE:-build/embedded.provisionprofile}"

[ -f "$PROFILE" ] || { echo "Provisioning Profile fehlt: $PROFILE"; exit 1; }

UNIVERSAL=1 ./build.sh
APP="build/Rechnungsklar.app"
cp "$PROFILE" "$APP/Contents/embedded.provisionprofile"

# Die App-Store-Signatur braucht Team- und App-ID in den Berechtigungen
TEAM_ID=$(echo "$TEAM" | sed -E 's/.*\(([A-Z0-9]+)\).*/\1/')
BUNDLE_ID=$(/usr/libexec/PlistBuddy -c "Print CFBundleIdentifier" Resources/Info.plist)
ENT=build/release.entitlements
cp Resources/Rechnungsklar.entitlements "$ENT"
/usr/libexec/PlistBuddy -c "Add :com.apple.application-identifier string $TEAM_ID.$BUNDLE_ID" "$ENT"
/usr/libexec/PlistBuddy -c "Add :com.apple.developer.team-identifier string $TEAM_ID" "$ENT"

echo "→ Signiere für den App Store …"
codesign --force --timestamp --options runtime --entitlements "$ENT" --sign "$APP_CERT" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"

echo "→ Baue Installationspaket …"
productbuild --component "$APP" /Applications --sign "$PKG_CERT" build/Rechnungsklar.pkg
echo "✓ Fertig: build/Rechnungsklar.pkg – jetzt mit Transporter hochladen."
