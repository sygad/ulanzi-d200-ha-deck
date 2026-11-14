[All parts](../README.md#the-parts)

# Shared · how the parts talk to each other

Things more than one part relies on, explained once. You don't need any of this to
install or use the deck. It is here for anyone changing a part, or writing a bridge
for another computer.

- [How a key reaches the screen](#how-a-key-reaches-the-screen)
- [The messages](#the-messages)
- [The layout file](#the-layout-file)
- [The sizing rule](#the-sizing-rule)

---

## How a key reaches the screen

1. **The panel** ([Part 5](../parts/05-the-panel/README.md)) saves what you chose for
   the key: its kind, name, icon, colours, and what it does.
2. **The integration** ([Part 4](../parts/04-home-assistant/README.md)) draws the key
   as a picture, at the size and place of that key's window on the deck's screen.
3. Every key of every screen is packed into one **layout file** and sent to the deck,
   which stores it.
4. **The deck app** ([Part 2](../parts/02-deck-app/README.md)) draws the pictures for
   the screen it is on. That is all it does with them.
5. When something changes, the integration draws that one key again and sends just
   that picture, a **tile**. Tiles are kept in the deck's memory, never stored, and
   are thrown away when the link drops.

A press goes the other way: the deck says "screen 2, key 7, tapped", and the
integration looks up what that key is for.

The bridge ([Part 3](../parts/03-mac-bridge/README.md)) sits in the middle and passes
messages along unread.

---

## The messages

### Deck ↔ bridge: USB

The deck's data channel carries reports of 1024 bytes each way. A message that
doesn't fit in one report is sent as several.

| Byte | Meaning |
|---|---|
| 0 | Flags: `1` this report starts a message, `2` it ends one, `3` both |
| 1–2 | How many payload bytes are in this report (little-endian) |
| 3… | Payload. The first byte of a message is its type |

All numbers are little-endian.

**To the deck**

| Type | Name | Body |
|---|---|---|
| 1 | Ping | Time as Unix seconds (4 bytes) · offset from UTC in seconds (4, signed) · is Home Assistant connected (1) · length of the date text (1) · today's date as text |
| 2 | Layout | A whole [layout file](#the-layout-file). The deck stores it and redraws |
| 3 | Tile | Screen (1) · key (1) · a picture. Replaces that key's picture until the link drops |
| 4 | Show | Screen (1). Switch to it |
| 5 | Backlight | Brightness, 0 to 255 (1) |
| 6 | Clear | Nothing. Forget every tile and redraw from the layout |
| 7 | Key map | Fourteen key codes, in reading order. The deck stores them |

The bridge sends a ping every two seconds. A deck that stops hearing them shows its
red dot.

**From the deck**

| Type | Name | Body |
|---|---|---|
| 0x81 | Status | Protocol version (1) · app version, major and minor (2) · screen showing (1) · number of screens (1) · has a usable layout (1) · the layout's id (4) · the key map (14) |
| 0x82 | Key | Screen (1) · key (1) · `1` for a tap, `2` for a hold |
| 0x83 | Raw key | Key code (1) · `1` pressed, `0` released. Sent for every key while a bridge is connected, whatever the layout. Used by the tools in [Part 6](../parts/06-lining-up-the-keys/README.md) |

The deck answers every ping with a status, and sends one whenever its screen or
layout changes.

### Bridge ↔ Home Assistant: WebSocket

The bridge connects to `/api/ulanzi_deck/bridge` on Home Assistant.

| Direction | Message | Meaning |
|---|---|---|
| Bridge → HA | Text: `{"type": "hello", "bridge_id", "secret", "name"}` | Who the bridge is. Always first |
| HA → bridge | Text: `{"type": "pending"}` | Not allowed yet. Wait for someone to press Allow |
| HA → bridge | Text: `{"type": "ready"}` | Allowed. Go ahead |
| Bridge → HA | Text: `{"type": "deck", "status"}` | A deck is plugged in and answering. `status` is its status message, base64 |
| Bridge → HA | Text: `{"type": "deck_gone"}` | The deck has gone |
| Either way | Binary | One deck message, exactly as in the tables above |

Home Assistant keeps a SHA-256 fingerprint of each allowed bridge's secret, never the
secret.

---

## The layout file

One file holds every screen. The deck keeps it at `/userdata/deck/layout.bin` and
draws from it at power-up. The integration builds it in `build_layout()` in
[`render.py`](../custom_components/ulanzi_deck/render.py); the deck reads it in
[`deckd.c`](../parts/02-deck-app/deckd.c).

| Offset | Size | What |
|---|---|---|
| 0 | 4 | The letters `UDL2`. The deck refuses anything else |
| 4 | 4 | Size of the whole file |
| 8 | 4 | The layout's id: a CRC-32 of the file, worked out with this field as zero |
| 12 | 1 | Number of screens, up to 32 |
| 13 | 1 | Number of fonts |
| 14 | 1 | The screen to start on |
| 15 | 1 | Minutes of nothing happening before the deck turns its screen off. `0` never |
| 16 | 4 | Where the font table starts |
| 20 | 4 | Where the key records start |
| 24 | 112 | Fourteen rectangles, one per key: x, y, width, height on the 1280 × 720 screen, 2 bytes each |
| … | 4 each | Font table: where each font starts |
| … | 32 each | Key records: fourteen for each screen |
| … | | The fonts, then the pictures |

The id is how Home Assistant knows whether the deck already has the current layout.
If the deck reports the same id, nothing is resent.

**A key record** (32 bytes)

| Offset | Size | What |
|---|---|---|
| 0 | 2 | Tap: kind, then argument |
| 2 | 2 | Hold: kind, then argument |
| 4 | 1 | Flags: `1` there is a key here · `2` it is a clock · `4` 12-hour · `8` show seconds · `16` show the date |
| 5 | 3 | Clock: font for the time · how the time is aligned · font for the date |
| 8 | 8 | Clock: x and y of the time, x and y of the date, inside the key's picture (2 bytes each, signed) |
| 16 | 8 | Clock: colour of the time (3) · how the date is aligned (1) · colour of the date (3) · unused (1) |
| 24 | 4 | Where this key's picture starts |
| 28 | 4 | Its length |

Kinds of tap and hold: `0` nothing · `1` ask Home Assistant · `2` previous screen ·
`3` next screen · `4` go to the screen in the argument · `5` back.

**A picture** is its width and height (2 bytes each), then runs of pixels, three
bytes each for red, green and blue:

| First byte | Then | Meaning |
|---|---|---|
| `0x00`–`0x7F` | One pixel | That pixel, repeated (byte + 1) times |
| `0x80`–`0xFE` | (byte − `0x7F`) pixels | Those pixels, as they are |
| `0xFF` | A 2-byte count, then one pixel | That pixel, repeated that many times |

A picture may be at most 512 × 240.

**A font** is there only for clock keys, so the deck can draw the time itself. It is
a count of letters (2 bytes, then 2 unused), then a 12-byte entry for each: character
code (2), width (1), height (1), x and y offset (1 each, signed), how far to move on
(1), unused (1), and where its shape starts (4). A shape is one byte of opacity per
pixel.

---

## The sizing rule

One rule sets every size, and the panel's preview and the deck both follow it:

> On a key 100 wide, an icon is 54 and a label is 14.

Everything else is scaled to match those two.

| Where | How it applies the rule |
|---|---|
| The panel's preview, `panel.js` | Every size is written as a fraction of the key's width, so the preview is right at any size |
| The deck, `render.py` | A key is taken as 200 pixels wide (`K = 200`), so an icon is 108 pixels and a label 28 |

Change a size in one and you must change it in the other. The comments in both files
say so where it matters.

What shows through a key is about 197 × 193 pixels, and content is kept inside a
smaller box than that (184 × 166, or 440 wide on the wide key), so nothing touches
the edge of a key.

---

[All parts](../README.md#the-parts)
