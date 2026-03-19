#!/bin/bash
set -euo pipefail

# Usage: ./scripts/release.sh 1.0.0
#
# Reads credentials from .env in the project root.
# See .env.example for required variables.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [ -f "$SCRIPT_DIR/../.env" ]; then
  set -a
  source "$SCRIPT_DIR/../.env"
  set +a
fi

VERSION="${1:?Usage: ./scripts/release.sh <version>}"
TEAM_ID="${APPLE_TEAM_ID:?Set APPLE_TEAM_ID}"
SIGNING_IDENTITY="Developer ID Application: ${SIGNING_IDENTITY_NAME:?Set SIGNING_IDENTITY_NAME} ($TEAM_ID)"
APPLE_ID="${APPLE_ID:?Set APPLE_ID}"
BUNDLE_ID="com.joshpigford.Chops"

create_chops_dmg() {
  hdiutil detach "/Volumes/Chops" 2>/dev/null || true
  rm -f build/Chops.dmg build/Chops_rw.dmg

  # Create writable DMG from the app
  hdiutil create -volname "Chops" -srcfolder build/export/Chops.app -fs HFS+ -format UDRW build/Chops_rw.dmg

  # Mount, add Applications symlink and background, apply Finder styling
  hdiutil attach build/Chops_rw.dmg
  ln -s /Applications "/Volumes/Chops/Applications"
  mkdir -p "/Volumes/Chops/.background"
  cp scripts/dmg-background.png "/Volumes/Chops/.background/background.png"

  osascript <<'APPLESCRIPT'
tell application "Finder"
  tell disk "Chops"
    open
    tell container window
      set current view to icon view
      set toolbar visible to false
      set statusbar visible to false
      set the bounds to {200, 120, 990, 600}
    end tell
    set opts to the icon view options of container window
    tell opts
      set icon size to 128
      set text size to 13
      set arrangement to not arranged
      set background picture to POSIX file "/Volumes/Chops/.background/background.png"
    end tell
    set position of item "Chops.app" to {195, 220}
    set position of item "Applications" to {595, 220}
    set the extension hidden of item "Chops.app" to true
    close
    open
    delay 1
    tell container window
      set the bounds to {200, 120, 980, 590}
    end tell
    delay 1
    tell container window
      set the bounds to {200, 120, 990, 600}
    end tell
    delay 3
  end tell
end tell
APPLESCRIPT

  hdiutil detach "/Volumes/Chops"
  hdiutil convert build/Chops_rw.dmg -format UDZO -o build/Chops.dmg
  rm -f build/Chops_rw.dmg
}

echo "🔨 Building Chops v$VERSION..."

# Generate Xcode project
xcodegen generate

# Clean build
rm -rf build
mkdir -p build

# Archive
xcodebuild -project Chops.xcodeproj \
  -scheme Chops \
  -configuration Release \
  -archivePath build/Chops.xcarchive \
  archive \
  CODE_SIGN_IDENTITY="$SIGNING_IDENTITY" \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  MARKETING_VERSION="$VERSION" \
  CURRENT_PROJECT_VERSION="$VERSION"

# Export
sed "s/\${APPLE_TEAM_ID}/$TEAM_ID/g" ExportOptions.plist > build/ExportOptions.plist
xcodebuild -exportArchive \
  -archivePath build/Chops.xcarchive \
  -exportOptionsPlist build/ExportOptions.plist \
  -exportPath build/export

echo "📦 Creating DMG..."
create_chops_dmg

echo "🔏 Notarizing..."
xcrun notarytool submit build/Chops.dmg \
  --keychain-profile "AC_PASSWORD" \
  --wait

echo "📎 Stapling..."
xcrun stapler staple build/export/Chops.app
create_chops_dmg
xcrun stapler staple build/Chops.dmg || echo "⚠️  DMG staple failed (normal — CDN propagation delay). App inside is stapled."

echo "🏷️  Tagging v$VERSION..."
git tag "v$VERSION"
git push --tags

echo "📡 Generating Sparkle appcast..."
SPARKLE_BIN=$(find ~/Library/Developer/Xcode/DerivedData/Chops-*/SourcePackages/artifacts/sparkle/Sparkle/bin -maxdepth 0 2>/dev/null | head -1)
SIGNATURE=$("$SPARKLE_BIN/sign_update" build/Chops.dmg 2>&1)
ED_SIG=$(echo "$SIGNATURE" | grep -o 'sparkle:edSignature="[^"]*"' | cut -d'"' -f2)
LENGTH=$(echo "$SIGNATURE" | grep -o 'length="[^"]*"' | cut -d'"' -f2)
PUB_DATE=$(date -u +"%a, %d %b %Y %H:%M:%S +0000")

cat > build/appcast.xml << APPCAST
<?xml version="1.0" standalone="yes"?>
<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/" version="2.0">
  <channel>
    <title>Chops</title>
    <item>
      <title>Version $VERSION</title>
      <sparkle:version>$VERSION</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>26.0</sparkle:minimumSystemVersion>
      <pubDate>$PUB_DATE</pubDate>
      <enclosure
        url="https://github.com/Shpigford/chops/releases/download/v$VERSION/Chops.dmg"
        sparkle:edSignature="$ED_SIG"
        length="$LENGTH"
        type="application/octet-stream"
      />
    </item>
  </channel>
</rss>
APPCAST

echo "📡 Updating site appcast..."
cp build/appcast.xml site/public/appcast.xml
git add site/public/appcast.xml
git commit -m "chore: update appcast for v$VERSION" || true
git push

echo "🚀 Creating GitHub Release..."
gh release create "v$VERSION" build/Chops.dmg \
  --title "Chops v$VERSION" \
  --generate-notes

echo "✅ Done! Release: https://github.com/Shpigford/chops/releases/tag/v$VERSION"
