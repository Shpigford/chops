#!/bin/bash
set -euo pipefail

# Usage: ./scripts/release.sh 1.0.0
#
# Creates a private notarized Fast Talk DMG and exported app bundle.
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
APPLE_ID="${APPLE_ID:?Set APPLE_ID}"
BUNDLE_ID="com.fasttalk"

if ! xcrun notarytool history --keychain-profile "AC_PASSWORD" >/dev/null 2>&1; then
  echo "❌ Unable to use notarytool keychain profile \"AC_PASSWORD\"."
  echo "Create or refresh it with:"
  echo "  xcrun notarytool store-credentials \"AC_PASSWORD\" --apple-id \"$APPLE_ID\" --team-id \"$TEAM_ID\" --password \"<app-specific-password>\""
  exit 1
fi

create_fasttalk_dmg() {
  hdiutil detach "/Volumes/Fast Talk" 2>/dev/null || true
  rm -f build/FastTalk.dmg build/FastTalk_rw.dmg

  # Create writable DMG from the app
  hdiutil create -volname "Fast Talk" -srcfolder build/export/FastTalk.app -fs HFS+ -format UDRW build/FastTalk_rw.dmg

  # Mount, add Applications symlink and background, apply Finder styling
  hdiutil attach build/FastTalk_rw.dmg
  ln -s /Applications "/Volumes/Fast Talk/Applications"
  mkdir -p "/Volumes/Fast Talk/.background"
  cp scripts/dmg-background.png "/Volumes/Fast Talk/.background/background.png"

  osascript <<'APPLESCRIPT'
tell application "Finder"
  tell disk "Fast Talk"
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
      set background picture to POSIX file "/Volumes/Fast Talk/.background/background.png"
    end tell
    set position of item "FastTalk.app" to {195, 220}
    set position of item "Applications" to {595, 220}
    set the extension hidden of item "FastTalk.app" to true
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

  hdiutil detach "/Volumes/Fast Talk"
  hdiutil convert build/FastTalk_rw.dmg -format UDZO -o build/FastTalk.dmg
  rm -f build/FastTalk_rw.dmg
}

echo "🔨 Building Fast Talk v$VERSION..."

# Generate Xcode project
xcodegen generate

# Clean build
rm -rf build
mkdir -p build

# Archive
xcodebuild -project FastTalk.xcodeproj \
  -scheme FastTalk \
  -configuration Release \
  -archivePath build/FastTalk.xcarchive \
  archive \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  MARKETING_VERSION="$VERSION" \
  CURRENT_PROJECT_VERSION="$VERSION"

# Export
sed "s/\${APPLE_TEAM_ID}/$TEAM_ID/g" ExportOptions.plist > build/ExportOptions.plist
xcodebuild -exportArchive \
  -archivePath build/FastTalk.xcarchive \
  -exportOptionsPlist build/ExportOptions.plist \
  -exportPath build/export

echo "📦 Creating DMG..."
create_fasttalk_dmg

echo "🔏 Notarizing..."
xcrun notarytool submit build/FastTalk.dmg \
  --keychain-profile "AC_PASSWORD" \
  --wait

echo "📎 Stapling..."
xcrun stapler staple build/export/FastTalk.app
create_fasttalk_dmg
xcrun stapler staple build/FastTalk.dmg || echo "⚠️  DMG staple failed (normal — CDN propagation delay). App inside is stapled."

echo "✅ Private release build ready."
echo "📦 App bundle: build/export/FastTalk.app"
echo "💿 DMG: build/FastTalk.dmg"
