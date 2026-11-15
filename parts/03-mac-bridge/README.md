[← Part 2](../02-deck-app/README.md) · [All parts](../../README.md) · [Part 4 →](../04-home-assistant/README.md)

# Part 3 · The connector app

The Mac app the deck plugs into. The deck has no network, so this carries its messages
to Home Assistant and back.

To a user it is an ordinary app: Home Assistant hands it over, it puts itself in
Applications, and it lives in the menu bar by the clock with its version in its window
and Quit in its menu. Closing the window does not stop it. **Nothing on this page is
part of setting one up** — [the setup guide](../../README.md) is. What follows is how
it works and how to build it yourself.

It doesn't understand the messages. It passes them on. The two things it does for
itself are the two the deck can't: tell it the time, and tell it whether anyone is
listening.

## At a glance

| | |
|---|---|
| **Built from** | One Swift file. No packages, no drivers |
| **Files in this folder** | `app/` (the app's source) · `build-app.sh` (builds it) · `main.swift` and `install.sh` (the older headless bridge, kept for reference) |
| **Also needs** | Nothing, to use it. To build it: Xcode Command Line Tools (`xcode-select --install`) |
| **Reads** | The deck, over USB; Home Assistant, over the network |
| **Mac only** | It uses macOS's own USB and networking. There is no Windows or Linux version |

## How it works

```
deck  <-- USB, 1024 bytes at a time -->  bridge  <-- WebSocket -->  Home Assistant
```

1. It finds the deck's data channel by its USB identity and opens it. macOS asks for
   no permission to do this.
2. Every two seconds it sends the deck the time, the date, and whether Home Assistant
   is connected.
3. It connects to Home Assistant at `/api/ulanzi_deck/bridge` and waits to be allowed.
4. Once allowed, whatever the deck says goes to Home Assistant and whatever Home
   Assistant says goes to the deck.

## Settings I chose

- **No access token.** It proves itself with a secret of its own, kept in
  `~/Library/Application Support/UlanziDeck/bridge.json`; Home Assistant keeps only a
  fingerprint of it. Normally that secret arrives in the pairing file beside the
  download, so there is nothing to allow. A Mac that turns up without one is held at
  the door until somebody presses **Allow** in the panel.
- **It backs off.** If Home Assistant can't be reached it tries again after 3 seconds,
  then 6, up to 30.
- **It is downloaded, and macOS says so.** The app comes from Home Assistant, so the
  first time it is opened macOS refuses it and you tell it once that you meant it. An
  update fetched by the app itself is not held back, because no browser touched it.

## Building it yourself

*Developer notes. None of this is needed to use the app: Home Assistant hands you a
built one.*

1. Install the Command Line Tools if you haven't:

   ```bash
   xcode-select --install
   ```

2. Build and start the bridge, with your own Home Assistant address:

   ```bash
   ./parts/03-mac-bridge/install.sh http://homeassistant.local:8123
   ```

3. Check its log:

   ```bash
   tail ~/Library/Logs/UlanziDeck/bridge.log
   ```

   With the deck plugged in you should see `deck attached`. Once Home Assistant has the
   integration ([Part 4](../04-home-assistant/README.md)) you will see
   `waiting to be allowed`, and after you press Allow, `Home Assistant connected` and
   `deck online`.

### Other things it can do

Stop the login agent first for the ones marked *, so two programs aren't talking to
the deck at once:

```bash
launchctl bootout gui/$(id -u)/com.ulanzi-deck.bridge
```

| Command | What it does |
|---|---|
| `ulanzi-deck-bridge --set-url <address>` | Changes the Home Assistant address and exits |
| `ulanzi-deck-bridge --keytest` * | Learns which physical key is which: you press all fourteen in order. See [Part 6](../06-lining-up-the-keys/README.md) |
| `ulanzi-deck-bridge --grid` * | Finds where each key's window is on the screen. See [Part 6](../06-lining-up-the-keys/README.md) |
| `ulanzi-deck-bridge --push <file>` * | Sends a layout file straight to the deck, for development |

The built program is at `~/Library/Application Support/UlanziDeck/ulanzi-deck-bridge`.
Start the agent again with:

```bash
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.ulanzi-deck.bridge.plist
```

### Removing it

```bash
launchctl bootout gui/$(id -u)/com.ulanzi-deck.bridge
```

```bash
rm ~/Library/LaunchAgents/com.ulanzi-deck.bridge.plist
```

---

[← Part 2](../02-deck-app/README.md) · [All parts](../../README.md) · [Part 4 →](../04-home-assistant/README.md)
