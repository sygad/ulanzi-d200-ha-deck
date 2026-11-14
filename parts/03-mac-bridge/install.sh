#!/bin/sh
# Builds the bridge and sets it to start with the Mac.
#
#   ./install.sh http://homeassistant.local:8123     (the address is remembered; give it once)
#
# To remove:  launchctl bootout gui/$(id -u)/com.ulanzi-deck.bridge
#             rm ~/Library/LaunchAgents/com.ulanzi-deck.bridge.plist
set -e
cd "$(dirname "$0")"
LABEL=com.ulanzi-deck.bridge
DEST="$HOME/Library/Application Support/UlanziDeck"
LOGS="$HOME/Library/Logs/UlanziDeck"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"

mkdir -p build "$DEST" "$LOGS" "$HOME/Library/LaunchAgents"
# compile from a local copy: on a network drive swiftc can see the source's
# timestamp move under it and refuse to finish
TMP="$(mktemp -d)"
cp main.swift "$TMP/main.swift"
swiftc -O "$TMP/main.swift" -o "$TMP/ulanzi-deck-bridge"
cp "$TMP/ulanzi-deck-bridge" build/ulanzi-deck-bridge
rm -rf "$TMP"
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
cp build/ulanzi-deck-bridge "$DEST/ulanzi-deck-bridge"
[ -n "$1" ] && "$DEST/ulanzi-deck-bridge" --set-url "$1"

cat > "$PLIST" <<PLIST_END
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key><array><string>$DEST/ulanzi-deck-bridge</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>ProcessType</key><string>Background</string>
  <key>StandardOutPath</key><string>$LOGS/bridge.log</string>
  <key>StandardErrorPath</key><string>$LOGS/bridge.log</string>
</dict>
</plist>
PLIST_END
launchctl bootstrap "gui/$(id -u)" "$PLIST"
echo "Bridge installed and running. Log: $LOGS/bridge.log"
