#!/bin/sh
# Puts the device app on the deck over adb, keeping the vendor app safe.
#
# The stock init script starts /userdata/UlanziDeckKey at boot, so that is the
# name the app is installed under. Nothing outside /userdata is touched, and adb
# is started by a different script, so the debug port survives whatever happens.
#
# To go back:  adb shell 'killall UlanziDeckKey; cp /userdata/vendor/UlanziDeckKey /userdata/UlanziDeckKey'
set -e
cd "$(dirname "$0")"
# use a build made here if there is one, otherwise the ready-made binary in this folder
# Prefer a fresh build, but only if it IS fresh: build/ is not tracked, so an
# old one left lying here would otherwise beat the published binary beside the
# source and quietly install something older than deckd.c.
BIN=build/deckd
if [ -f "$BIN" ] && [ ! "$BIN" -nt deckd.c ]; then
  echo "Ignoring $BIN: it is older than deckd.c. Run ./build.sh, or delete it." >&2
  BIN=deckd
fi
[ -f "$BIN" ] || BIN=deckd
adb get-state >/dev/null

adb shell '
  mkdir -p /userdata/deck /userdata/vendor
  # first install only: keep the vendor app exactly as it was found
  if [ ! -f /userdata/vendor/UlanziDeckKey ]; then
    cp -p /userdata/UlanziDeckKey /userdata/vendor/UlanziDeckKey && echo "vendor app saved to /userdata/vendor"
  fi'
adb push "$BIN" /userdata/UlanziDeckKey.new >/dev/null
if [ "$(adb shell 'ls /userdata/deck/layout.bin 2>/dev/null')" = "" ]; then
  adb push default-layout.bin /userdata/deck/layout.bin >/dev/null && echo "starter layout installed"
fi
adb shell '
  killall UlanziDeckKey 2>/dev/null
  chmod 755 /userdata/UlanziDeckKey.new
  mv /userdata/UlanziDeckKey.new /userdata/UlanziDeckKey
  sync
  (setsid /userdata/UlanziDeckKey -platform linuxfb >/dev/null 2>&1 &)
  sleep 1
  /userdata/UlanziDeckKey --version
  ps | grep "[U]lanziDeckKey" >/dev/null && echo "running" || echo "NOT running"'
