[← Part 6](../06-lining-up-the-keys/README.md) · [All parts](../../README.md)

# Part 7 · The wireless board

An ESP32-S3 board that takes the Mac's place. The deck plugs into it, it joins your
Wi-Fi, and it carries the deck's messages to Home Assistant and back. With it, the deck
needs a wall socket and nothing else.

**Nothing on this page is part of setting one up** — [the wireless guide](../../WIRELESS.md)
is. What follows is how it works and how to build it yourself.

Like the connector app ([Part 3](../03-mac-bridge/README.md)), it doesn't understand the
messages. It passes them on. It does three things for itself: tells the deck the time,
tells it whether anyone is listening, and puts the deck software on a deck that hasn't
got it.

## At a glance

| | |
|---|---|
| **Built from** | An ESP32-S3 board with two USB-C sockets (mine: a diymore ESP32-S3 DevKitC-1 N16R8). Seven C files, about 1,700 lines, on ESP-IDF 5.5 |
| **Files in this folder** | `firmware/` (the source, an ESP-IDF project) · `firmware/tools/` (three small Python helpers for working on it) |
| **Also needs** | Nothing, to use it: [the web page](https://sygad.github.io/ulanzi-d200-ha-deck/docs/flash/) puts a built copy on the board, and Home Assistant keeps it up to date after that. To build it: ESP-IDF 5.5 |
| **Reads** | The deck, over USB; Home Assistant, over Wi-Fi |
| **Tested on** | One board and one deck |

## How it works

```
deck  <-- USB: the debug port, stream "tcp:5210" -->  board  <-- Wi-Fi, WebSocket -->  Home Assistant
```

The connector app talks to the deck over its **data channel**, 1024 bytes at a time
([Part 1](../01-the-deck/README.md)). The board can't. An ESP32-S3 is a full-speed USB
host, and ESP-IDF's host code refuses any channel that asks for more than a few hundred
bytes a packet: 408 as it is set up here, 600 at the very most. The deck asks for 1024
even at full speed, so the board is turned away before a byte is sent.

The deck's **debug port** asks for 64 bytes, which is fine. So the board goes in that way:

1. It opens the deck's debug port, the same one `adb` uses, and speaks just enough of
   that protocol to open streams.
2. It checks what the deck is running. If the deck software is missing or older than the
   copy the board carries, it installs it: keeps Ulanzi's own in `/userdata/vendor/`,
   copies the new one across, gives it a starter screen, starts it. It compares checksums
   and reads the version out of the file; it never runs a program to find out what it is.
3. It opens a stream to port 5210 on the deck, where the deck software
   ([Part 2](../02-deck-app/README.md)) listens. The messages on that stream are the same
   ones the data channel carries, each with its length in front
   ([the formats](../../shared/README.md#deck--board-a-stream)).
4. Every two seconds it sends the deck the time, the date, and whether Home Assistant is
   connected.
5. It connects to Home Assistant at `/api/ulanzi_deck/bridge` and waits to be allowed,
   exactly as the connector app does. Once allowed, whatever the deck says goes to Home
   Assistant and whatever Home Assistant says goes to the deck.

To Home Assistant it is one more bridge, called **Ulanzi D200 Wireless**.

## Settings I chose

- **Its own setup network.** With no Wi-Fi details, or when it can't join for a minute, it
  offers an open network called **Ulanzi Deck Setup** with one page at `http://192.168.4.1`.
  Holding the **BOOT** button for five seconds brings that network back on purpose.
- **The time comes from Home Assistant.** The board has no clock either. It asks Home
  Assistant for a page and reads the date off the reply, so nothing outside your network
  is contacted. The time zone is fixed to the UK's for now.
- **A secret of its own.** As with the connector app, it proves itself to Home Assistant
  with a secret it made up on first start, and Home Assistant keeps only a fingerprint.
  Someone has to press **Allow** in the panel the first time.
- **It keeps looking.** If Home Assistant closes the connection, or restarts, the board
  reconnects after five seconds. If it sees no deck, it switches its USB socket off and on
  every eight seconds until one appears.
- **Its updates come from Home Assistant.** The integration carries the board's software
  ([Part 4](../04-home-assistant/README.md)). When the panel's **Update now** is pressed, Home
  Assistant tells the board, the board asks where to fetch it, and is given a one-time
  address on that same Home Assistant: the conversation the connector app has, word for
  word. The board checks the first byte before it stores anything, so being handed the
  Mac's app by an older integration is refused with a plain message.
- **Two copies of itself.** The board's memory holds two slots for its software. A new
  version goes into the other slot and is only kept once it has joined Wi-Fi. If it
  hasn't by the time the board next restarts, the board goes back to the one that worked.
- **It writes down a crash.** If it ever crashes, it records where, and says so on the
  first line of its log at every start until the record is cleared.

## The board's own page

Open the board's address in a browser and it says where everything stands: Wi-Fi, Home
Assistant, the deck, the clock.

Four more addresses exist for working on the project. All but the first want the board's
key in an `X-Deck-Key` header, and the key is only ever printed on the serial console
(`KEY`), so it takes the cable in the COM socket to learn it.

| Address | What it does |
|---|---|
| `GET /status` | The same line as the page, then the board's recent log |
| `POST /sh` | Runs a command on the deck and returns what it printed |
| `POST /setupdeck` | Installs the deck software again, whatever the deck has |
| `POST /update` | Takes new board software and restarts into it |

`tools/deckweb.py` uses them: `status`, `sh "<command>"`, `setupdeck`, `update <file>`.

## Building it yourself

*Developer notes. None of this is needed to use the board: [the web page](https://sygad.github.io/ulanzi-d200-ha-deck/docs/flash/)
installs a built copy.*

1. Install [ESP-IDF 5.5](https://docs.espressif.com/projects/esp-idf/en/stable/esp32s3/get-started/)
   and open a shell with it loaded.

2. Build:

   ```bash
   cd parts/07-wireless-board/firmware
   ```

   ```bash
   idf.py build
   ```

3. Plug the board's **COM** socket into the computer and put it on the board. Give the
   port by name, so nothing else plugged in can be written to by mistake:

   ```bash
   idf.py -p /dev/cu.usbmodemXXXX -b 230400 flash
   ```

   My board would not take the faster speeds `idf.py` tries first.

The deck software the board carries is `firmware/main/deck/deckd`, a copy of
[Part 2](../02-deck-app/README.md)'s `deckd`, with the starter screen beside it. If you
rebuild the deck software, copy it there before building the board's.

The built board software that everyone else gets is one file,
`custom_components/ulanzi_deck/board/ulanzi-d200-wireless.bin`: `build/ulanzi_esp32.bin`
from this build, copied there. The integration hands that file to a board that asks, and
the web page installs the same one. `tools/check-release.sh` opens it and checks what
version it and the deck software inside it really are.

### The serial console

The COM socket is also a command line, at 115200. Each command is one line; replies
start `| ` and end with `OK` or `ERR`. `tools/deckctl.py` speaks it, and `tools/hub.py`
holds the port open so that looking at the board does not restart it. Both read the
port's name from `tools/.port`, a file you make yourself.

| Command | What it does |
|---|---|
| `INFO` | Where everything stands |
| `LOG` | The board's recent log |
| `SH <command>` | Runs a command on the deck |
| `PUT <path> <mode> <size>` | Copies a file to the deck |
| `URL <address>` | Sets the Home Assistant address |
| `KEY` | Prints the board's key, for `tools/.key` |
| `SETUPDECK` | Installs the deck software again |
| `FORGET` | Forgets the Wi-Fi details and offers the setup network |
| `REBOOT` | Restarts the board |
| `UPDATEFROM <address>` | Fetches board software from an address and restarts into it, for trying the update path by hand |
| `CRASH` | Crashes the board on purpose, to check the crash record works |
| `CLEARCRASH` | Clears the crash record |

## Things that caught me out

| What | Why it matters |
|---|---|
| The deck's data channel is out of reach | It asks for 1024-byte packets, and the ESP32-S3's host code stops well short of that. Hence the debug port |
| The first try at the debug port always fails | The board sees the deck, is refused the port, and sees the deck arrive a second time about a second later. That second time works. The firmware waits for it |
| A clean goodbye was final | The WebSocket library reconnects after an error but not after the other end closes politely, which is what Home Assistant does when it restarts. It has to be told to (`enable_close_reconnect`) |
| A cut-off answer looked like a new deck | Asking the deck what it runs, on a connection that drops mid-answer, gives an empty reply. Every question now ends with a marker, and no marker means ask again |
| Opening the serial port restarts the board | That is how these boards are wired. `tools/hub.py` opens it once and keeps it open |
| Other boards on the same computer | Another project's flashing tool wrote to this board because it was the only serial port. Always name the port |

---

[← Part 6](../06-lining-up-the-keys/README.md) · [All parts](../../README.md)
