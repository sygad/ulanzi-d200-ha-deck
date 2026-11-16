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
VERSION="4.10"

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
# Build the deck app rather than trusting the copy on disk: the version this
# bundle claims is read from deckd.c below, so a stale binary here means the
# app offers an update that installs the old one and never goes away.
sh "$ROOT/parts/02-deck-app/build.sh" >/dev/null
DECKD="$ROOT/parts/02-deck-app/deckd"
[ -f "$DECKD" ] || { echo "FAILED: no deck app at $DECKD" >&2; exit 1; }
[ "$DECKD" -nt "$ROOT/parts/02-deck-app/deckd.c" ] || {
  echo "FAILED: $DECKD is older than deckd.c" >&2; exit 1; }
cp "$DECKD" "$APP/Contents/Resources/deckd"
# the version of that deck app, so the Mac can tell whether a deck is behind
awk '/#define FW_MAJOR/{maj=$3} /#define FW_MINOR/{min=$3} END{printf "%s.%s\n", maj, min}' \
  "$ROOT/parts/02-deck-app/deckd.c" > "$APP/Contents/Resources/deckd.version"
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

# Sign last: signing seals the bundle, so anything written afterwards breaks it.
# This used to be "|| true", which quietly shipped an unsigned app when signing
# failed — and on a network volume it does fail now and then, then works on a
# second go. So: try, retry, verify, and stop the build if it still is not signed.
for try in 1 2 3; do
  codesign --force --deep --sign - "$APP" 2>"$TMP/codesign.err" || true
  codesign --verify --deep --strict "$APP" >/dev/null 2>&1 && break
  sleep 1
done
if ! codesign --verify --deep --strict "$APP" >/dev/null 2>&1; then
  echo "FAILED: could not sign $APP" >&2
  cat "$TMP/codesign.err" >&2 2>/dev/null || true
  codesign --verify --deep --strict "$APP" >&2
  exit 1
fi
# The zip is what people actually download, and it was being made by hand with
# a ditto command nobody had written down. A release should not depend on
# somebody remembering the right flags.
ZIP="$(dirname "$APP")/Ulanzi-Deck.zip"
rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"

echo "Built: $APP"
echo "Zipped: $ZIP"
echo
echo "Before publishing this, run:  sh tools/check-release.sh"
du -sh "$APP" | sed 's/^/  /'
