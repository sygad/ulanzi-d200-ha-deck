#!/bin/sh
# Checks the thing that actually ships, not the source that was meant to make it.
#
# Every release fault so far has been the same shape: something claimed a
# version it did not have. The app advertised 4.3 and carried a deck binary
# from 1.2. The build said it signed and did not. Reading the source would
# never have caught any of them, because the source was right — what was
# written to disk was not.
#
# So this opens the built app, the published binaries and the zip, and checks
# each claim against the bytes. Run it before publishing anything.
#
#   sh tools/check-release.sh
#
set -e
cd "$(dirname "$0")/.."
ROOT=$(pwd)
APP="$ROOT/parts/03-mac-bridge/build/Ulanzi Deck.app"
ZIP="$ROOT/parts/03-mac-bridge/build/Ulanzi-Deck.zip"
FAIL=0

say()  { printf '  %-52s %s\n' "$1" "$2"; }
ok()   { say "$1" "ok"; }
bad()  { say "$1" "FAILED — $2"; FAIL=1; }
same() { [ "$2" = "$3" ] && ok "$1" || bad "$1" "$2 vs $3"; }

# ---------------------------------------------------------------- the sources agree
MANIFEST=$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
  "$ROOT/custom_components/ulanzi_deck/manifest.json")
SCRIPT=$(sed -n 's/^VERSION="\([^"]*\)".*/\1/p' "$ROOT/parts/03-mac-bridge/build-app.sh")
FW=$(awk '/#define FW_MAJOR/{a=$3} /#define FW_MINOR/{b=$3} END{printf "%s.%s", a, b}' \
  "$ROOT/parts/02-deck-app/deckd.c")

echo "Release $MANIFEST"
same "build-app.sh is on the same version"   "$SCRIPT"   "$MANIFEST"
same "deckd.c is on the same version"        "$FW"       "$MANIFEST"

# ---------------------------------------------------------------- the app exists
if [ ! -d "$APP" ]; then
  bad "the app is built" "no app at $APP"
  echo; echo "FAILED"; exit 1
fi

# ---------------------------------------------------------------- what the app claims
PLIST=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" \
  "$APP/Contents/Info.plist" 2>/dev/null || echo "")
same "the app's own version"                 "$PLIST"    "$MANIFEST"

CLAIMS=$(cat "$APP/Contents/Resources/deckd.version" 2>/dev/null || echo "")
same "the deck version the app advertises"   "$CLAIMS"   "$MANIFEST"

# ---------------------------------------------------------------- and what it carries
# The one that bit: the number above is read out of deckd.c, so it is right
# even when the binary beside it is three releases old. Build deckd again and
# compare the bytes.
sh "$ROOT/parts/02-deck-app/build.sh" >/dev/null 2>&1 \
  || { bad "the deck app builds" "build.sh failed"; echo; echo "FAILED"; exit 1; }
FRESH=$(md5 -q "$ROOT/parts/02-deck-app/build/deckd")
same "the published deck binary is that build" \
     "$(md5 -q "$ROOT/parts/02-deck-app/deckd")"            "$FRESH"
same "the deck binary inside the app is that build" \
     "$(md5 -q "$APP/Contents/Resources/deckd")"            "$FRESH"

# ---------------------------------------------------------------- signed, really
if codesign --verify --deep --strict "$APP" >/dev/null 2>&1; then
  ok "the app is signed"
else
  bad "the app is signed" "codesign --verify says no"
fi

# ---------------------------------------------------------------- and survives the zip
if [ ! -f "$ZIP" ]; then
  bad "the zip is built" "no zip at $ZIP"
else
  OUT=$(mktemp -d)
  ditto -x -k "$ZIP" "$OUT" >/dev/null 2>&1
  if [ -d "$OUT/Ulanzi Deck.app" ]; then
    if codesign --verify --deep --strict "$OUT/Ulanzi Deck.app" >/dev/null 2>&1; then
      ok "the zipped app is still signed"
    else
      bad "the zipped app is still signed" "the signature did not survive"
    fi
    same "the zipped app carries the same deck binary" \
         "$(md5 -q "$OUT/Ulanzi Deck.app/Contents/Resources/deckd")"  "$FRESH"
  else
    bad "the zip holds the app" "nothing unpacked"
  fi
  rm -rf "$OUT"
fi

echo
[ "$FAIL" = 0 ] && echo "All checks passed. Safe to publish $MANIFEST." && exit 0
echo "FAILED — do not publish." >&2
exit 1
