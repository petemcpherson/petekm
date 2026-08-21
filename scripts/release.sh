#!/usr/bin/env bash
#
# Build a signed, notarized PeteKM.dmg for direct distribution (spec §20.1).
#
#   scripts/release.sh <marketing-version> <build-number>
#
# Requires: DEVELOPMENT_TEAM env var, a Developer ID Application certificate in
# the keychain, and a notarytool keychain profile named `petekm-notary`
# (see context/DISTRIBUTION.md).

set -euo pipefail

VERSION="${1:?usage: release.sh <marketing-version> <build-number>}"
BUILD="${2:?usage: release.sh <marketing-version> <build-number>}"
TEAM="${DEVELOPMENT_TEAM:?set DEVELOPMENT_TEAM to your Apple Developer team ID}"
PROFILE="${NOTARY_PROFILE:-petekm-notary}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/build"
ARCHIVE="$OUT/PeteKM.xcarchive"
EXPORT_DIR="$OUT/export"
DMG="$OUT/PeteKM-$VERSION.dmg"

rm -rf "$OUT"
mkdir -p "$OUT" "$EXPORT_DIR"

cat > "$OUT/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key><string>developer-id</string>
    <key>teamID</key><string>$TEAM</string>
    <key>signingStyle</key><string>automatic</string>
</dict>
</plist>
PLIST

echo "==> Archiving $VERSION ($BUILD)"
xcodebuild -project "$ROOT/PeteKM.xcodeproj" -scheme PeteKM -configuration Release \
    -archivePath "$ARCHIVE" \
    MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$BUILD" \
    DEVELOPMENT_TEAM="$TEAM" \
    archive

echo "==> Exporting with Developer ID"
xcodebuild -exportArchive -archivePath "$ARCHIVE" \
    -exportOptionsPlist "$OUT/ExportOptions.plist" \
    -exportPath "$EXPORT_DIR"

echo "==> Building disk image"
hdiutil create -volname "PeteKM" -srcfolder "$EXPORT_DIR/PeteKM.app" -ov -format UDZO "$DMG"

echo "==> Signing disk image"
codesign --force --sign "Developer ID Application" --timestamp "$DMG"

echo "==> Notarizing (this waits for Apple)"
xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait

echo "==> Stapling"
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"

echo "==> Done: $DMG"
echo "Sign the appcast entry with Sparkle's sign_update, then publish the dmg and appcast.xml."
