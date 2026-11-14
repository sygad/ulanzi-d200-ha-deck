# Build it with your AI

You don't have to follow the steps by hand. Point an AI at this repo and it can do
the install with you: check the deck, put the app on it, build the bridge, and get
the integration into Home Assistant.

It needs setting up first. An AI in a chat window can't reach your deck. One running
on the Mac the deck is plugged into can.

- [Part 1: For you](#part-1-for-you)
- [Part 2: For the AI](#part-2-for-the-ai)

---

## Part 1: For you

### What happens

1. **Questions first.** The AI asks what you have, one question at a time. Nothing is
   changed yet.
2. **You approve a plan.** It tells you what it is going to do, and waits for a yes.
3. **It installs and checks.** Each piece is tested before the next. A few clicks are
   yours: restarting Home Assistant, adding the integration, and pressing **Allow**.

### What you need

| | |
|---|---|
| **Tested route** | [Claude Code](https://claude.com/claude-code), running on the Mac the deck is plugged into |
| **Hardware** | An Ulanzi D200, a Mac, a USB data cable, a Home Assistant server on the same network |
| **A way to reach Home Assistant's files** | The integration is a folder that has to be copied into Home Assistant's `config` folder. Either the AI can reach that folder (for example the Samba share add-on, with the share opened on the Mac), or you copy the folder yourself when it asks |
| **Optional** | [HA-MCP](https://github.com/homeassistant-ai/ha-mcp), so the AI can look up your entities and check the deck's sensors in Home Assistant |
| **Passwords** | Typed by you, never by the AI |

Other AI assistants that can run commands on your Mac should work too. Claude Code is
the one I've tested. A chat AI with no access to your Mac can still walk you through
the [quick start](README.md#quick-start), one step at a time.

**Know before you start:** this replaces the app on the deck, and Ulanzi's own
software won't see the deck afterwards. The vendor app is saved first. See
[Part 2 · Going back](parts/02-deck-app/README.md#going-back).

### The prompt

Open Claude Code in a folder on the Mac, and paste:

```text
I want to set up the Ulanzi D200 Home Assistant Control Deck from
https://github.com/sygad/ulanzi-d200-ha-deck on this Mac and my Home Assistant.

Clone the repo, read BUILD-WITH-AI.md in it, and follow its "Part 2: For the AI"
section exactly. Start with the questions in Step 1, one at a time.
Don't install, create or change anything until I've approved your plan.
```

---

## Part 2: For the AI

You are installing this project for the person you are talking to. Follow these steps
in order. They are not reading the code, so tell them what you are doing in plain
words and keep it short.

### The files

| File | What it is |
|---|---|
| `README.md` | Overview, what is needed, and the manual quick start |
| `parts/01-the-deck/README.md` | What the hardware is, and what was found on the tested deck |
| `parts/02-deck-app/deckd` | The deck app, ready-built for the deck (32-bit ARM, static). **Install this; do not rebuild it unless asked** |
| `parts/02-deck-app/deckd.c`, `build.sh` | Its source, and how it is built |
| `parts/02-deck-app/install.sh` | Puts the app on the deck over `adb`. Saves the vendor app first |
| `parts/02-deck-app/default-layout.bin` | The starter screen a new deck shows |
| `parts/03-mac-bridge/main.swift` | The bridge. One file, built on the user's Mac |
| `parts/03-mac-bridge/install.sh` | Builds the bridge and sets it to start at login |
| `custom_components/ulanzi_deck/` | The Home Assistant integration, panel included. **Copy this folder as it is** |
| `parts/06-lining-up-the-keys/` | How key positions are measured, and the tested deck's measurements |
| `tools/apply_grid.py` | Copies measured key positions into the integration |
| `shared/README.md` | The message format and layout file, if you need to debug |

### Rules

- **Change nothing until the plan is approved.** Looking is fine: `adb devices`,
  `sw_vers`, reading files.
- **Ask before installing anything** on the Mac (Command Line Tools, `adb`, Homebrew).
- **On the deck, touch nothing outside `/userdata`.** Never delete or overwrite
  `/userdata/vendor/`. Never copy the vendor's app off the deck or share it.
- **Use the installers as they are.** Don't rewrite `install.sh`, don't "tidy" the
  source, don't rebuild the deck app unless the user asks for a change to it.
- **Don't restart Home Assistant without a clear yes** for that restart.
- **The Allow button is the user's click.** Don't press it for them or work round it.
- **Never guess an entity ID.** If you suggest one, check it exists first.
- **Never type passwords or tokens** for the user.
- **Stop if a check fails.** Say what you saw. Don't carry on to the next step.
- **If this isn't a Mac, stop.** The bridge is macOS only. Say so, and that the deck
  app and integration would still need a bridge written for their system.

### Step 1: Ask the user

One question at a time. Check what you can for yourself first, and don't ask what you
can find out.

1. Is the deck an Ulanzi D200, and is it plugged into this Mac? (Then run
   `adb devices` if `adb` is there, and confirm one device is listed.)
2. This replaces the app on the deck, and Ulanzi's software won't see it afterwards.
   The vendor app is saved first. Is that all right?
3. What is the address of Home Assistant, as this Mac reaches it? (For example
   `http://homeassistant.local:8123`. Check it answers.)
4. How should the integration folder get into Home Assistant's `config` folder? Can
   you reach that folder from here, or will they copy it?
5. Are `adb` and the Xcode Command Line Tools installed? (Check: `which adb`,
   `xcode-select -p`. Ask only for permission to install what is missing.)

### Step 2: Check what you have

| Check | How | If it fails |
|---|---|---|
| This is a Mac | `sw_vers` | Stop: see Rules |
| The deck is reachable | `adb devices` lists exactly one device | Stop. Not every deck may have an open debug port |
| It is the right deck | `adb shell ls /userdata/UlanziDeckKey` finds the file | Stop. This is not a D200 as tested |
| There is room | `adb shell df /userdata` shows a few MB free | Stop and say so |
| Swift is there | `swiftc --version` | Ask to run `xcode-select --install` |
| Home Assistant answers | Fetch its address | Ask for the right address |

### Step 3: Show the plan and wait

Tell the user, briefly: what will go on the deck, what will be installed on the Mac,
what will be copied to Home Assistant, and which clicks will be theirs. Wait for a
clear yes.

### Step 4: Install

Do these in order. Check each before the next.

| # | Do | What it is for | Check |
|---|---|---|---|
| 1 | `./parts/02-deck-app/install.sh` | Puts the app on the deck | It prints `deckd 1.1` and `running`. On a first install it also prints `vendor app saved to /userdata/vendor` |
| 2 | Copy `custom_components/ulanzi_deck` into Home Assistant's `config/custom_components/` | The integration | The folder is there with `manifest.json` in it |
| 3 | Home Assistant is restarted (the user, or you after a yes) | So it finds the integration | It comes back |
| 4 | The user adds **Ulanzi Deck** under Settings → Devices & services → Add integration | Turns it on | **Ulanzi Deck** is in the sidebar |
| 5 | `./parts/03-mac-bridge/install.sh <their address>` | Builds and starts the bridge | `~/Library/Logs/UlanziDeck/bridge.log` shows `deck attached` and `waiting to be allowed` |
| 6 | The user opens **Ulanzi Deck** in the sidebar and presses **Allow** | Pairs this Mac | The log shows `Home Assistant connected` and `deck online` |

Substitutions: there is only one. The Home Assistant address in step 5 is the user's.
Nothing in the files needs editing.

### Step 5: Set up keys

Keys are set up by the user in the panel: [Part 5](parts/05-the-panel/README.md). Tell
them how to make the first one: click a key, choose what it does, press **Send to
device**. If you can read their Home Assistant, offer real entity names to pick from.

### Step 6: Check it works

- `binary_sensor.ulanzi_deck_connection` is on in Home Assistant.
- The wide key shows no red or amber dot.
- After **Send to device**, the deck shows the key the user made.
- Pressing a light key toggles the light, and the key dims when the light is off.
- Ask the user: does pressing a key do what that key says, and is the content centred
  in each key, looking at it square-on?
  - Wrong key answering: do Job 1 in [Part 6](parts/06-lining-up-the-keys/README.md).
  - Off-centre: do Job 2 in Part 6. The user places the lines; you run the commands.
    Never work the positions out from a photograph or a table. That was tried and was
    wrong.

To see what the deck is showing without asking, `python3 tools/fb_grab.py out.png`
reads its screen over `adb` (needs Pillow). Compare with `images/deck-screen.png`.

### Reference: what goes where

| Thing | Where it ends up | Removed by |
|---|---|---|
| Deck app | `/userdata/UlanziDeckKey` on the deck | [Going back](parts/02-deck-app/README.md#going-back) |
| Vendor app, saved | `/userdata/vendor/UlanziDeckKey` on the deck | Never remove |
| Layout and key map | `/userdata/deck/` on the deck | Not needed |
| Bridge program and its settings | `~/Library/Application Support/UlanziDeck/` | [Removing it](parts/03-mac-bridge/README.md#removing-it) |
| Bridge login agent | `~/Library/LaunchAgents/com.ulanzi-deck.bridge.plist` | The same |
| Bridge log | `~/Library/Logs/UlanziDeck/bridge.log` | Delete the file |
| Integration | `config/custom_components/ulanzi_deck/` in Home Assistant | [Part 4](parts/04-home-assistant/README.md#add-just-this-part) |
