[← Part 3](../03-mac-bridge/README.md) · [All parts](../../README.md#the-parts) · [Part 5 →](../05-the-panel/README.md)

# Part 4 · Home Assistant integration

The part that does the thinking. It keeps your key settings, draws every key as a
picture, sends the pictures to the deck, redraws a key when the thing it shows
changes, and carries out what a press asks for.

## At a glance

| | |
|---|---|
| **Built from** | A custom integration in Python. Pictures are drawn with Pillow, which Home Assistant already has |
| **Files** | Not in this folder: in [`custom_components/ulanzi_deck/`](../../custom_components/ulanzi_deck) at the top of the repo, where Home Assistant and HACS look for it |
| **Also needs** | The bridge ([Part 3](../03-mac-bridge/README.md)) to reach the deck |
| **Reads** | Whatever entities your keys point at; their history, for graph keys |
| **Gives you** | A sidebar panel, two entities, and an event on every key press |

## How it works

1. You set up keys in the panel ([Part 5](../05-the-panel/README.md)). Every change is
   saved as a **draft**, straight away.
2. **Send to device** makes the draft the **published** layout. Only the published
   layout ever reaches the deck.
3. The integration draws each key of the published layout and packs every screen into
   one file, which the deck stores ([shared · the layout file](../../shared/README.md#the-layout-file)).
4. While the deck is connected, it watches the entities your keys use. When one
   changes, that key is redrawn and sent. A light going off dims its key; a sensor
   moving redraws its number.
5. When a key is pressed, the deck says which key, and the integration calls the
   service you chose.

## What it gives you

| | |
|---|---|
| **Ulanzi Deck** in the sidebar | The panel, for admins |
| `binary_sensor.ulanzi_deck_connection` | On while the deck is connected |
| `sensor.ulanzi_deck_screen` | The name of the screen the deck is showing. Unavailable when the deck is |
| The `ulanzi_deck_key` event | Fired on every press of a button key, with `screen`, `screen_name`, `key`, `label`, `gesture` (`tap` or `hold`), `action` and `target`. Use it to trigger automations of your own |

## What a key can do

| Group | Actions |
|---|---|
| Lights | Toggle · Turn on · Turn off |
| Switches | Toggle · Turn on · Turn off |
| Buttons | Press |
| Covers | Toggle · Open · Close |
| Media | Play / pause · Volume up · Volume down |
| Scripts and scenes | Run a script · Activate a scene |
| Screens | Previous screen · Next screen · Go to screen · Back |

Screen changes happen on the deck itself. Everything else is a Home Assistant service
call on the entity you picked. For anything not in the list, give the key an action
that suits and trigger an automation from the `ulanzi_deck_key` event.

## Settings I chose

- **Draft and published are separate.** You can change things for as long as you
  like without the deck flickering through half-finished screens.
- **A key that drives something looks like it.** A light key dims when the light is
  off. Keys for scripts, scenes and buttons stay lit, because those have no "off".
- **The deck's stored layout shows no readings.** Sensor keys are stored showing
  `--`, so a deck that has just powered up never shows an old number as if it were
  current. Live values arrive when the bridge connects.
- **The bridge is not behind Home Assistant's login.** It has no user. It proves
  itself with its own secret, and is ignored until an admin has pressed Allow.
- **Changes to how keys are drawn don't need a restart.** Reloading the integration
  picks up changed code.

## Add just this part

1. Copy the folder `custom_components/ulanzi_deck` from this repo into the
   `custom_components` folder inside your Home Assistant `config` folder. Create
   `custom_components` if it isn't there.
2. Restart Home Assistant.
3. Go to **Settings → Devices & services → Add integration**, search for
   **Ulanzi Deck**, and add it. It asks no questions.
4. **Ulanzi Deck** appears in the sidebar. Until the bridge is running its chip reads
   "Bridge not connected".

**With HACS:** the repo is laid out for it, so adding it as a custom repository
(type: Integration) should work. I installed it by copying the folder, and have not
tested the HACS route.

To remove it: delete the integration under Devices & services, delete the folder,
and restart.

---

[← Part 3](../03-mac-bridge/README.md) · [All parts](../../README.md#the-parts) · [Part 5 →](../05-the-panel/README.md)
