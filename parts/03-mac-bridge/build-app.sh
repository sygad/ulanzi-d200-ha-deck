#!/bin/sh
# Builds "Ulanzi Deck.app" — the one thing an owner of a deck downloads.
#
#   ./build-app.sh [output-folder]        default: ./build
#
# Needs Xcode's command line tools (xcode-select --install) and nothing else.
# It is built for both kinds of Mac, and carries inside it:
#   - the deck app and its starter screen, to set a deck up over USB
#   - adb, which is how that copy is made (Apache 2.0; NOTICE-adb.txt goes with it)
# Set ADB=/path/to/adb if yours is somewhere this script does not look.
set -e
cd "$(dirname "$0")"
HERE="$(pwd)"
ROOT="$(cd ../.. && pwd)"
OUT="${1:-$HERE/build}"
APP="$OUT/Ulanzi Deck.app"
VERSION="3.4"

# swiftc on a network drive can see the source move under it, so build from a copy
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
cp app/*.swift "$TMP/"

echo "Building…"
for arch in arm64 x86_64; do
  swiftc -O -parse-as-library -target "$arch-apple-macos13" \
    "$TMP"/*.swift \
    -o "$TMP/UlanziDeck-$arch"
done
lipo -create "$TMP/UlanziDeck-arm64" "$TMP/UlanziDeck-x86_64" -output "$TMP/UlanziDeck"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$TMP/UlanziDeck" "$APP/Contents/MacOS/UlanziDeck"

# what it needs to set a deck up
cp app/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp app/menubar.png app/menubar@2x.png "$APP/Contents/Resources/"
cp "$ROOT/parts/02-deck-app/deckd" "$APP/Contents/Resources/deckd"
cp "$ROOT/parts/02-deck-app/default-layout.bin" "$APP/Contents/Resources/default-layout.bin"

ADB="${ADB:-}"
if [ -z "$ADB" ]; then
  for c in "$(command -v adb 2>/dev/null)" \
           /opt/homebrew/bin/adb /usr/local/bin/adb; do
    [ -n "$c" ] && [ -x "$c" ] && ADB="$c" && break
  done
fi
[ -n "$ADB" ] || { echo "No adb found. Install it (brew install android-platform-tools) or set ADB=." >&2; exit 1; }
cp "$ADB" "$APP/Contents/Resources/adb"
chmod 755 "$APP/Contents/Resources/adb"
ADB_DIR="$(dirname "$(readlink "$ADB" 2>/dev/null || echo "$ADB")")"
if [ -f "$ADB_DIR/NOTICE.txt" ]; then
  cp "$ADB_DIR/NOTICE.txt" "$APP/Contents/Resources/NOTICE-adb.txt"
else
  echo "adb is Apache License 2.0. See https://android.googlesource.com/platform/packages/modules/adb/" \
    > "$APP/Contents/Resources/NOTICE-adb.txt"
fi

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Ulanzi Deck</string>
  <key>CFBundleDisplayName</key><string>Ulanzi Deck</string>
  <key>CFBundleIdentifier</key><string>com.ulanzideck.app</string>
  <key>CFBundleExecutable</key><string>UlanziDeck</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSHumanReadableCopyright</key><string>MIT. Includes adb, Apache License 2.0.</string>
  <key>NSLocalNetworkUsageDescription</key><string>Ulanzi Deck looks for Home Assistant on your network so you do not have to type its address.</string>
  <key>NSBonjourServices</key><array><string>_home-assistant._tcp</string></array>
</dict></plist>
PLIST

codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true
echo "Built: $APP"
du -sh "$APP" | sed 's/^/  /'
