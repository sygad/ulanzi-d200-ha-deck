#!/bin/sh
# Renders the guide's figures.
#
# Two kinds come out of here. The Browser Mod panel and the profile page are
# DRAWN, in tools/figures/index.html, because a real screenshot of either one
# carries somebody's room names, panel names and browser id. The rest are shot
# from the panel harness, which runs the real panel against a house that does
# not exist.
#
# Every "look here" ring in the guide is the same vivid orange-red, set in one
# place in each source, so no figure ends up with a mark you cannot see.
#
#   sh tools/figures/shoot.sh
#
set -e
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
OUT="$ROOT/images/guide"
DOCS="$ROOT/docs"
DRAWN=8791
PANEL=8792
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
[ -x "$CHROME" ] || CHROME=$(ls /Applications/*Chrom*/Contents/MacOS/* 2>/dev/null | head -1)
[ -x "$CHROME" ] || { echo "no Chrome found" >&2; exit 1; }
TMP=$(mktemp -d)

python3 -m http.server "$DRAWN" --bind 127.0.0.1 --directory "$ROOT/tools/figures" >/dev/null 2>&1 &
A=$!
( cd "$ROOT/tools/panel-harness" && python3 serve.py "$PANEL" >/dev/null 2>&1 ) &
B=$!
trap 'kill $A $B 2>/dev/null || true; rm -rf "$TMP"' EXIT
until curl -s -o /dev/null "http://127.0.0.1:$DRAWN/"; do :; done
until curl -s -o /dev/null "http://127.0.0.1:$PANEL/"; do :; done

# grab <url> <out> <w> <h>
grab() {
  "$CHROME" --headless=new --disable-gpu --hide-scrollbars \
    --force-device-scale-factor=2 --window-size="$3,$4" --virtual-time-budget=9000 \
    --screenshot="$TMP/$2.png" "$1" >/dev/null 2>&1
}

# trim <name> [mode]
#   content  cut to everything that is not the page's own background (default)
#   bottom   full width, cut only the empty space below the content
trim() {
  python3 -I - "$TMP/$1.png" "$OUT/$1.png" "${2:-content}" <<'PY'
import sys
from PIL import Image
src, dst, mode = sys.argv[1], sys.argv[2], sys.argv[3]
im = Image.open(src).convert("RGB")
px, (W, H) = im.load(), im.size
bg = px[W - 3, H - 3]
def rowblank(y): return all(px[x, y] == bg for x in range(0, W, 3))
def colblank(x): return all(px[x, y] == bg for y in range(0, H, 3))
bot = next(y for y in range(H - 1, -1, -1) if not rowblank(y))
if mode == "bottom":
    box = (0, 0, W, min(H, bot + 40))
else:
    top = next(y for y in range(H) if not rowblank(y))
    lef = next(x for x in range(W) if not colblank(x))
    rig = next(x for x in range(W - 1, -1, -1) if not colblank(x))
    m = 6
    box = (max(0, lef - m), max(0, top - m), min(W, rig + m + 1), min(H, bot + m + 1))
im.crop(box).save(dst)
print("  %-30s %s" % (dst.split("/")[-1], Image.open(dst).size))
PY
}

# cut <name> <x0> <y0> <x1> <y1>   an exact region, for figures that need their
#                                  surroundings kept rather than trimmed away
cut() {
  python3 -I - "$TMP/$1.png" "$OUT/$1.png" "$2" "$3" "$4" "$5" <<'PY'
import sys
from PIL import Image
src, dst = sys.argv[1], sys.argv[2]
box = tuple(int(v) for v in sys.argv[3:7])
Image.open(src).crop(box).save(dst)
print("  %-30s %s" % (dst.split("/")[-1], Image.open(dst).size))
PY
}

echo "Drawn (no real screen behind them):"
grab "http://127.0.0.1:$DRAWN/?register" fig-navigate-register 1180 820; trim fig-navigate-register
grab "http://127.0.0.1:$DRAWN/?suspend"  fig-navigate-suspend  1180 760; trim fig-navigate-suspend
grab "http://127.0.0.1:$DRAWN/?wireless" fig-wireless-what-you-need 1180 700; trim fig-wireless-what-you-need
grab "http://127.0.0.1:$DRAWN/?setup"    fig-wireless-setup-page 1180 900; trim fig-wireless-setup-page

# The install page is the real one, served from the repo so its own files load.
python3 -m http.server 8793 --bind 127.0.0.1 --directory "$ROOT" >/dev/null 2>&1 &
C=$!
trap 'kill $A $B $C 2>/dev/null || true; rm -rf "$TMP"' EXIT
until curl -s -o /dev/null "http://127.0.0.1:8793/docs/flash/"; do :; done
echo "The install page:"
grab "http://127.0.0.1:8793/docs/flash/" fig-wireless-install 820 900; trim fig-wireless-install
# The deck in the middle of an update is drawn by the renderer itself.
python3 "$ROOT/tools/notice_figure.py"

echo "From the panel harness:"
grab "http://127.0.0.1:$PANEL/?navigate" fig-navigate 1280 980; trim fig-navigate bottom
grab "http://127.0.0.1:$PANEL/?gear"     fig-settings-gear 1280 900; cut fig-settings-gear 1180 0 2560 244
grab "http://127.0.0.1:$PANEL/?allow"    fig-wireless-allow 1280 900; cut fig-wireless-allow 1180 0 2560 244
grab "http://127.0.0.1:$PANEL/?board&ring" fig-wireless-update 1280 900; trim fig-wireless-update bottom
grab "http://127.0.0.1:$PANEL/?settings" fig-settings 1460 1200
python3 -I - "$TMP/fig-settings.png" "$OUT/fig-settings.png" <<'PY'
# The dialog with the dimmed page still around it. Cropped flush to its own edge
# it stopped looking like a pop-up at all: the rounded corners left dark wedges
# in the corners of the picture, which read as a bad paste rather than a dialog.
import sys
from PIL import Image
im = Image.open(sys.argv[1]).convert("RGB")
px, (W, H) = im.load(), im.size
def white(c): return c[0] > 250 and c[1] > 250 and c[2] > 250
mid = H // 2
xs = [x for x in range(W) if white(px[x, mid])]
lef, rig = xs[0], xs[-1]
col = (lef + rig) // 2
ys = [y for y in range(H) if white(px[col, y])]
top, bot = ys[0], ys[-1]
pad = 72                                   # how much dimmed page to keep around it
im.crop((max(0, lef - pad), max(0, top - pad),
         min(W, rig + pad + 1), min(H, bot + pad + 1))).save(sys.argv[2])
print("  %-30s %s" % (sys.argv[2].split("/")[-1], Image.open(sys.argv[2]).size))
PY

# the docs site keeps its own copies, under its own names
cp "$OUT/fig-navigate-register.png" "$DOCS/navigate-register.png"
cp "$OUT/fig-navigate-suspend.png"  "$DOCS/navigate-suspend.png"
cp "$OUT/fig-navigate.png"          "$DOCS/navigate.png"
cp "$OUT/fig-settings-gear.png"     "$DOCS/settings-gear.png"
cp "$OUT/fig-settings.png"          "$DOCS/deck-settings.png"
cp "$OUT/fig-updating.png"          "$DOCS/updating.png"
echo "Copied into docs/."
