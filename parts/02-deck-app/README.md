[← Part 1](../01-the-deck/README.md) · [All parts](../../README.md) · [Part 3 →](../03-mac-bridge/README.md)

# Part 2 · Deck app

![What a freshly installed deck shows: "Waiting for Home Assistant" on the wide key](starter-screen.png)

The program that runs on the deck. It draws the keys, reads presses, and remembers
the last layout so the deck has something to show the moment it gets power.

It does almost no thinking. Home Assistant draws every key and sends it as a
finished picture ([Part 4](../04-home-assistant/README.md)). The deck shows what it
is given.

## At a glance

| | |
|---|---|
| **Built from** | One C file with no libraries at all, not even the C library. 21 KB when built |
| **Files in this folder** | `deckd` (ready to install) · `deckd.c` (the source) · `build.sh` (rebuilds it) · `install.sh` (puts it on the deck) · `default-layout.bin` (the starter screen) |
| **Also needs** | `adb` on the Mac. The `lld` linker only if you rebuild it |
| **Reads** | The fourteen keys; messages from the bridge |
| **Shows** | Whatever layout it was last sent |

## What it does

| | |
|---|---|
| **Draws at once** | At power-up it draws the layout saved on the deck, before any computer is talking to it |
| **Tells tap from hold** | A hold is half a second. A key with nothing set for hold acts the instant it is pressed |
| **Changes screen by itself** | Previous, Next, Go to and Back are handled on the deck, so they are instant |
| **Keeps the time** | Clock keys tick on the deck. The bridge tells it the time, because the deck has no clock of its own |
| **Shows when it is cut off** | A dot at the top right of the wide key: red for no bridge, amber for a bridge with no Home Assistant behind it |
| **Does nothing while cut off** | With no bridge the keys are drawn but dead, and presses are dropped rather than saved up |
| **Lights a key while pressed** | The whole key brightens for as long as it is held down |
| **Turns the screen off** | After a spell with nothing happening it sets the backlight to zero. Any key brings it back, and that press does nothing else. How long comes from the layout, so the deck keeps it over a power cut |

## Settings I chose

- **Installed as `/userdata/UlanziDeckKey`.** That is the name the deck's own start-up
  script runs, so nothing in the system has to be changed to make it start.
- **No libraries.** It makes it small, and it means there is nothing on the deck for
  it to depend on or break.
- **The layout is kept on the deck**, in `/userdata/deck/layout.bin`. Readings are
  not: they are held in memory and dropped when the link goes, so the deck never
  shows a stale number as if it were live.
- **Home Assistant draws, the deck shows.** The one exception is the time on a clock
  key, which the deck draws from letter shapes Home Assistant sends with the layout.

## What I changed

This replaces the vendor's app, so "changed" here means changed on the deck:

1. **The vendor app is copied aside first**, to `/userdata/vendor/UlanziDeckKey`, the
   first time the installer runs. It is never overwritten after that.
2. **The app takes the screen over at start.** Otherwise the deck goes on showing its
   "starting up" logo over everything.
3. **A folder is created**, `/userdata/deck/`, for the layout and the key map.

Nothing outside `/userdata` is touched.

## Putting it on a deck by hand

*Developer notes. None of this is part of setting a deck up — [the setup guide](../../README.md) is.*


1. Plug the deck in and check `adb devices` lists it ([Part 1](../01-the-deck/README.md)).
2. From the repo folder, run:

   ```bash
   ./parts/02-deck-app/install.sh
   ```

3. It should finish with `deckd 1.1` and `running`, and the wide key should read
   "Waiting for Home Assistant" with a red dot.

That is as far as this part goes by itself. The dot clears once the bridge
([Part 3](../03-mac-bridge/README.md)) and Home Assistant ([Part 4](../04-home-assistant/README.md))
are in place.

### Rebuilding it

Only if you want to change the source. `build.sh` uses Apple's `clang` to compile and
an ELF linker to link:

```bash
brew install lld
```

```bash
./parts/02-deck-app/build.sh
```

`install.sh` uses a fresh build if there is one, and the ready-made `deckd` otherwise.

### Going back

To put the vendor app back:

```bash
adb shell 'killall UlanziDeckKey; cp /userdata/vendor/UlanziDeckKey /userdata/UlanziDeckKey; reboot'
```

On my deck the vendor app was already failing to start before I began, so I have not
been able to check that going back gives a working deck.

---

[← Part 1](../01-the-deck/README.md) · [All parts](../../README.md) · [Part 3 →](../03-mac-bridge/README.md)
