"""Builds parts/02-deck-app/default-layout.bin: what a freshly installed deck shows until
Home Assistant sends it something better."""
import sys
from pathlib import Path
ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "custom_components" / "ulanzi_deck"))
import render

keys = [None] * 14
keys[13] = {"type": "button", "l": "Waiting for Home Assistant", "i": "home-assistant",
            "c": "#03a9f4", "layout": "h", "tap": {"a": "none", "t": ""}, "hold": {"a": "none", "t": ""}}
# sleep=20 matches DEFAULT_SLEEP in const.py: a deck that never hears from Home
# Assistant still turns its screen off rather than sitting lit
blob = render.build_layout([{"name": "Start", "keys": keys}], sleep=20)
(ROOT / "parts" / "02-deck-app" / "default-layout.bin").write_bytes(blob)
print(len(blob), "bytes")
