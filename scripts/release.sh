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

# Extract changelog entries for a version and convert to HTML <ul>
extract_changelog() {
  local version="$1"
  local changelog="$2"
  local in_section=false
  local html="<ul>"

  while IFS= read -r line; do
    if [[ "$line" =~ ^##\ \[${version}\] ]]; then
      in_section=true
      continue
    fi
    if $in_section && [[ "$line" =~ ^##\  ]]; then
      break
    fi
    if $in_section && [[ "$line" =~ ^-\ (.+) ]]; then
      html+="<li>${BASH_REMATCH[1]}</li>"
    fi
  done < "$changelog"

  html+="</ul>"
  if [ "$html" = "<ul></ul>" ]; then
    echo ""
  else
    echo "$html"
  fi
}

# Extract raw markdown changelog entries for a version
extract_changelog_markdown() {
  local version="$1"
  local changelog="$2"
  local in_section=false
  local md=""

  while IFS= read -r line; do
    if [[ "$line" =~ ^##\ \[${version}\] ]]; then
      in_section=true
      continue
    fi
    if $in_section && [[ "$line" =~ ^##\  ]]; then
      break
    fi
    if $in_section && [[ "$line" =~ ^-\ (.+) ]]; then
      md+="- ${BASH_REMATCH[1]}"$'\n'
    fi
  done < "$changelog"

  echo "$md"
}

TEAM_ID="${APPLE_TEAM_ID:?Set APPLE_TEAM_ID}"
SIGNING_IDENTITY="Developer ID Application: ${SIGNING_IDENTITY_NAME:?Set SIGNING_IDENTITY_NAME} ($TEAM_ID)"
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

echo "🏷️  Tagging v$VERSION..."
git tag "v$VERSION"
git push --tags

echo "📡 Generating Sparkle appcast..."
SPARKLE_BIN=$(find ~/Library/Developer/Xcode/DerivedData/FastTalk-*/SourcePackages/artifacts/sparkle/Sparkle/bin -maxdepth 0 2>/dev/null | head -1)
SIGNATURE=$("$SPARKLE_BIN/sign_update" build/FastTalk.dmg 2>&1)
ED_SIG=$(echo "$SIGNATURE" | grep -o 'sparkle:edSignature="[^"]*"' | cut -d'"' -f2)
LENGTH=$(echo "$SIGNATURE" | grep -o 'length="[^"]*"' | cut -d'"' -f2)
PUB_DATE=$(date -u +"%a, %d %b %Y %H:%M:%S +0000")

# Extract release notes from CHANGELOG.md
RELEASE_NOTES=$(extract_changelog "$VERSION" "CHANGELOG.md")
if [ -z "$RELEASE_NOTES" ]; then
  echo "⚠️  No changelog entry for v$VERSION in CHANGELOG.md. Appcast will have no release notes."
fi

# Preserve existing items from current appcast (exclude current version if re-releasing)
EXISTING_ITEMS=""
if [ -f site/public/appcast.xml ]; then
  EXISTING_ITEMS=$(awk '
    /<item>/ { buf=""; capture=1 }
    capture { buf = buf $0 "\n" }
    /<\/item>/ {
      capture=0
      if (buf !~ /<sparkle:version>'"$VERSION"'</) printf "%s", buf
    }
  ' site/public/appcast.xml)
fi

# Build description element if we have release notes
DESC_ELEMENT=""
if [ -n "$RELEASE_NOTES" ]; then
  DESC_ELEMENT="      <description><![CDATA[$RELEASE_NOTES]]></description>"
fi

cat > build/appcast.xml << APPCAST
<?xml version="1.0" standalone="yes"?>
<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/" version="2.0">
  <channel>
    <title>Fast Talk</title>
    <item>
      <title>Version $VERSION</title>
      <sparkle:version>$VERSION</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>15.0</sparkle:minimumSystemVersion>
      <pubDate>$PUB_DATE</pubDate>
$DESC_ELEMENT
      <enclosure
        url="https://github.com/Shpigford/fasttalk/releases/download/v$VERSION/FastTalk.dmg"
        sparkle:edSignature="$ED_SIG"
        length="$LENGTH"
        type="application/octet-stream"
      />
    </item>
$EXISTING_ITEMS
  </channel>
</rss>
APPCAST

echo "📡 Updating site appcast..."
cp build/appcast.xml site/public/appcast.xml
git add site/public/appcast.xml
git commit -m "chore: update appcast for v$VERSION" || true
git push

echo "🚀 Creating GitHub Release..."
CHANGELOG_MD=$(extract_changelog_markdown "$VERSION" "CHANGELOG.md")
if [ -n "$CHANGELOG_MD" ]; then
  gh release create "v$VERSION" build/FastTalk.dmg \
    --title "Fast Talk v$VERSION" \
    --notes "$CHANGELOG_MD"
else
  gh release create "v$VERSION" build/FastTalk.dmg \
    --title "Fast Talk v$VERSION" \
    --generate-notes
fi

echo "✅ Done! Release: https://github.com/Shpigford/fasttalk/releases/tag/v$VERSION"
