#!/usr/bin/env python3
"""Put the key positions found by `ulanzi-deck-bridge --grid` into the integration.

The grid tool saves where each of its eighteen lines stopped. This reads that
file and rewrites the three lines in render.py that say where the keys are.

    python3 tools/apply_grid.py            # use the grid the tool last saved
    python3 tools/apply_grid.py grid.json  # use a named file
    python3 tools/apply_grid.py --check    # show what would change, change nothing

Afterwards copy custom_components/ulanzi_deck to Home Assistant again and reload
the integration.
"""

import json
from pathlib import Path
import re
import sys

REPO = Path(__file__).resolve().parent.parent
RENDER = REPO / "custom_components" / "ulanzi_deck" / "render.py"
SAVED = Path.home() / "Library" / "Application Support" / "UlanziDeck" / "grid.json"


def main() -> int:
    args = [a for a in sys.argv[1:] if a != "--check"]
    check = "--check" in sys.argv[1:]
    source = Path(args[0]) if args else SAVED
    if not source.exists():
        print(f"no grid file at {source}: run ulanzi-deck-bridge --grid first")
        return 1
    grid = json.loads(source.read_text())
    if grid.get("placed") != grid.get("of"):
        print(f"only {grid.get('placed')} of {grid.get('of')} lines are placed: finish the grid first")
        return 1
    at = {line["name"]: int(line["at"]) for line in grid["lines"]}

    def pair(name: str, a: str, b: str) -> str:
        first, last = at[f"{name} {a}"], at[f"{name} {b}"]
        if not first < last:
            raise SystemExit(f"{name}: {a} ({first}) is not before {b} ({last}). Place those two lines again.")
        return f"({first}, {last})"

    try:
        new = {
            "KEY_X": "(" + ", ".join(pair(f"column {c}", "left", "right") for c in range(1, 6)) + ")",
            "KEY_Y": "(" + ", ".join(pair(f"row {r}", "top", "bottom") for r in range(1, 4)) + ")",
            "WIDE_X": pair("wide key", "left", "right"),
        }
    except KeyError as missing:
        print(f"the grid file has no line called {missing}")
        return 1

    text = RENDER.read_text()
    changed = False
    for name, value in new.items():
        found = re.search(rf"^{name} = (.+?)(\s+#.*)?$", text, re.M)
        if not found:
            print(f"cannot find {name} in {RENDER}")
            return 1
        old = found.group(1)
        print(f"{name}: {old}" + ("  (no change)" if old == value else f"\n{' ' * len(name)}  -> {value}"))
        if old != value:
            changed = True
            text = text[:found.start(1)] + value + text[found.end(1):]
    if check:
        print("nothing written (--check)")
    elif changed:
        RENDER.write_text(text)
        print(f"written to {RENDER.relative_to(REPO)}")
    else:
        print("render.py already matches the grid")
    return 0


if __name__ == "__main__":
    sys.exit(main())
