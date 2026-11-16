#!/bin/sh
# Renders the guide's drawn figures from tools/figures/index.html.
#
# These are illustrations rather than screenshots, because a real screenshot of
# somebody's Home Assistant carries their room names, their panel names and
# their browser id. Nothing here is real.
#
#   sh tools/figures/shoot.sh
#
set -e
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
OUT="$ROOT/images/guide"
PORT=8791
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
[ -x "$CHROME" ] || CHROME=$(ls /Applications/*Chrom*/Contents/MacOS/* 2>/dev/null | head -1)
[ -x "$CHROME" ] || { echo "no Chrome found" >&2; exit 1; }

python3 -m http.server "$PORT" --bind 127.0.0.1 --directory "$ROOT/tools/figures" >/dev/null 2>&1 &
SERVER=$!
trap 'kill $SERVER 2>/dev/null || true' EXIT
until curl -s -o /dev/null "http://127.0.0.1:$PORT/"; do :; done

shoot() {                       # shoot <scene> <file> <width> <height>
  "$CHROME" --headless=new --disable-gpu --hide-scrollbars \
    --force-device-scale-factor=2 --window-size="$3,$4" --virtual-time-budget=6000 \
    --screenshot="$ROOT/tools/figures/$2.raw.png" \
    "http://127.0.0.1:$PORT/?$1" >/dev/null 2>&1
  python3 -I - "$ROOT/tools/figures/$2.raw.png" "$OUT/$2.png" <<'PY'
import sys
from PIL import Image
im = Image.open(sys.argv[1]).convert("RGB")
px, (W, H) = im.load(), im.size
bg = px[2, 2]                                   # the sheet's own background
def blank(line): return all(px[x, line] == bg for x in range(0, W, 3))
def blankcol(c): return all(px[c, y] == bg for y in range(0, H, 3))
top = next(y for y in range(H) if not blank(y))
bot = next(y for y in range(H - 1, -1, -1) if not blank(y))
lef = next(x for x in range(W) if not blankcol(x))
rig = next(x for x in range(W - 1, -1, -1) if not blankcol(x))
m = 6
im.crop((max(0, lef - m), max(0, top - m), min(W, rig + m + 1), min(H, bot + m + 1))).save(sys.argv[2])
print("  %-34s %s" % (sys.argv[2].split("/")[-1], Image.open(sys.argv[2]).size))
PY
  rm -f "$ROOT/tools/figures/$2.raw.png"
}

echo "Drawing:"
shoot register fig-navigate-register 1180 760
shoot suspend  fig-navigate-suspend  1180 700
echo "Done."
