#!/usr/bin/env python3
"""Reach the Ulanzi board over Wi-Fi, when it is on a wall supply with no cable.

  deckweb.py status                 where everything stands, and the board's recent log
  deckweb.py sh "<shell command>"   run it on the deck
  deckweb.py setupdeck              put the deck app on the deck again
  deckweb.py update <firmware.bin>  new firmware for the board; it restarts into it

Needs the board's address in tools/.ip and its key in tools/.key. The key is only
ever shown on the serial console: deckctl.py raw KEY.
"""
import sys, os, urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
def read(name):
    try: return open(os.path.join(HERE, name)).read().strip()
    except OSError: sys.exit(f"missing tools/{name}")

def call(path, data=None, timeout=60):
    req = urllib.request.Request(f"http://{read('.ip')}{path}", data=data, method="POST" if data is not None else "GET")
    req.add_header("X-Deck-Key", read(".key"))
    if data is not None: req.add_header("Content-Type", "application/octet-stream")
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return r.read().decode("utf-8", "replace")

a = sys.argv[1:]
if not a: sys.exit(__doc__)
try:
    if a[0] == "status": print(call("/status"), end="")
    elif a[0] == "sh": print(call("/sh", a[1].encode()), end="")
    elif a[0] == "setupdeck": print(call("/setupdeck", b"x"), end="")
    elif a[0] == "update": print(call("/update", open(a[1], "rb").read(), timeout=180), end="")
    else: sys.exit(__doc__)
except Exception as e:
    sys.exit(f"ERR {e}")
