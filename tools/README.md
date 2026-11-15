[The guide](../README.md)

# Tools

Small helpers for working on the project. None is needed to install or use the deck,
except `apply_grid.py` if you line up the keys yourself.

The Python ones need Python 3. Those that draw need Pillow (`pip install pillow`).

| File | What it does | Needs |
|---|---|---|
| `apply_grid.py` | Copies the key positions you measured into the integration. See [Part 6](../parts/06-lining-up-the-keys/README.md) | Python |
| `fb_grab.py` | Saves a picture of what the deck's screen is showing, read over `adb`. `python3 tools/fb_grab.py out.png` | Pillow, `adb`, the deck plugged in |
| `render_test.py` | Draws the three demo screens to PNG files and builds a layout file, with no deck and no Home Assistant. `python3 tools/render_test.py some-folder` | Pillow |
| `demo_house.py` | A made-up house, and the three demo screens built from it. Everything the project shows off comes from here, so none of it is anyone's real home | – |
| `make_demo_data.py` | Rebuilds `panel-harness/data.json` from `demo_house.py`, after changing the house | – |
| `make_default_layout.py` | Rebuilds the starter screen in `parts/02-deck-app/default-layout.bin` | Pillow |
| `deck_trace.py` | Records the deck's health to a log on the Mac every 30 seconds, to catch what happens before a freeze | `adb`, the deck plugged in |
| `panel-harness/` | Runs the panel in a browser against a pretend Home Assistant. See [Part 5](../parts/05-the-panel/README.md#working-on-the-panel-itself) | Python |

## `check-release.sh`

Opens the built app, the published binaries and the zip, and checks every
version claim against the bytes. Run it before publishing a release:

```sh
sh tools/check-release.sh
```

Reading the source cannot catch what this catches. Every release fault so far
has been the same shape — something claiming a version it did not have, while
the source it was built from was correct.
