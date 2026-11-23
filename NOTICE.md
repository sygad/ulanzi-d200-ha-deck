# Third-party files in this repo

The repo's own code is under the [MIT licence](LICENSE). These bundled files are not:
they keep the licences they came with.

| File | What it is | Licence |
|---|---|---|
| `custom_components/ulanzi_deck/fonts/Roboto-Medium.ttf`<br>`custom_components/ulanzi_deck/fonts/Roboto-Regular.ttf` | Roboto, version 2.137 (2017), Latin subset. Copyright 2011 Google Inc. Used to draw the text on every key | [Apache License 2.0](http://www.apache.org/licenses/LICENSE-2.0) |
| `custom_components/ulanzi_deck/fonts/mdi.ttf`<br>`custom_components/ulanzi_deck/frontend/mdi.woff2` | The Material Design Icons font by [Pictogrammers](https://pictogrammers.com/library/mdi/). Used to draw the icon on a key, on the deck and in the panel | [Pictogrammers Free License](https://github.com/Templarian/MaterialDesign/blob/master/LICENSE): fonts and icons under Apache License 2.0 |
| `custom_components/ulanzi_deck/frontend/icons.json`<br>`custom_components/ulanzi_deck/frontend/alias.json` | The names, code points and search aliases of those icons | As the icons |
| `docs/flash/bootloader.bin`<br>`docs/flash/partition-table.bin`<br>`docs/flash/ota-data.bin`<br>`docs/flash/ulanzi-d200-wireless.bin` | The wireless board's software, built from `parts/07-wireless-board/firmware`. The built files contain [ESP-IDF](https://github.com/espressif/esp-idf), copyright Espressif Systems, and Espressif's `esp_websocket_client` | [Apache License 2.0](http://www.apache.org/licenses/LICENSE-2.0) for those parts; the project's own code in them is MIT |
| Loaded by `docs/flash/index.html`, not stored here | [ESP Web Tools](https://github.com/esphome/esp-web-tools), which writes that software to a board from the browser | [Apache License 2.0](http://www.apache.org/licenses/LICENSE-2.0) |

Not included, on purpose: Ulanzi's own software. The deck app here was written from
scratch, and the vendor's app is neither needed nor redistributed.
