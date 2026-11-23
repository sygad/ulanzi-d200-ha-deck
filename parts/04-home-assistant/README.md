[← Part 3](../03-mac-bridge/README.md) · [All parts](../../README.md) · [Part 5 →](../05-the-panel/README.md)

# Part 4 · The integration

The part that does the thinking. It keeps your key settings, draws every key as a
picture, sends the pictures to the deck, redraws a key when the thing it shows
changes, and carries out what a press asks for.

## At a glance

| | |
|---|---|
| **Built from** | A custom integration in Python. Pictures are drawn with Pillow, which Home Assistant already has |
| **Files** | Not in this folder: in [`custom_components/ulanzi_deck/`](../../custom_components/ulanzi_deck) at the top of the repo, where Home Assistant and HACS look for it |
| **Also needs** | Something to reach the deck through: the connector app on a Mac ([Part 3](../03-mac-bridge/README.md)) or the wireless board ([Part 7](../07-wireless-board/README.md)) |
| **Reads** | Whatever entities your keys point at; their history, for graph keys |
| **Gives you** | A sidebar panel, two entities, and an event on every key press |

It also hands out the connector app: the panel's **Get the connector app** button
builds a zip holding the published app, a pairing file carrying this server's address
and a key for that Mac, and a page explaining what macOS is about to do. When a newer app exists it says so in an amber bar above the version line under the
panel, and **Update now** tells the Mac to fetch it from here. Only one part can be
updated at a time, in the order they depend on each other. Home Assistant downloads it, pinned to the version this integration goes with, and passes it on; the Mac never talks to anywhere but your server.

**With a wireless board** it does the same job differently in three places:

- **It carries the board's software**, in `custom_components/ulanzi_deck/board/`. The Mac's
  app is too big to ship inside an integration and is fetched from its release; the board's
  is not, so **Update now** hands it straight over and nothing is fetched from anywhere.
- **It tells the board the time zone.** A Mac knows its own. A board knows none, so it is
  sent this server's when it is let in and again within a minute of it changing.
- **The panel says Board software** where it says Connector app, and sends a board too old
  to be updated from here to the install page instead.

**During any update it puts a notice on the deck.** Before it tells the Mac, the board or
the deck to update, it draws one picture, an amber **Updating**, and sends it to the deck's
wide key ([the formats](../../shared/README.md#the-messages)). The deck keeps it up through
the restarts that follow. If the update fails, the notice is taken down at once.

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
| Dashboards | Go to view — needs [Browser Mod](https://github.com/thomasloven/hass-browser_mod) |

Screen changes happen on the deck itself: the layout tells it which keys are its own,
and it never asks Home Assistant about them. Everything else is a service call.

Most of those call on the entity you picked. **Go to view** is the exception, and the
only action here that leans on another integration. Its target is a dashboard path
rather than an entity, and it carries the browser to move alongside it, so the key
ends up calling `browser_mod.navigate` with `path` and `browser_id`. With no browser
named it moves every registered one, which is browser_mod's own default and what
**All screens** means in the panel.

Browser Mod is not in `manifest.json`, under `dependencies` or `after_dependencies`.
It is wanted by one action out of the twenty above, and every check for it happens while
something is running rather than while the integration is loading: the panel asks
`hass.services` before it offers the action, and the integration asks `has_service`
before it makes the call. Naming it in the manifest would buy nothing and would tie
this integration's loading to one that most people installing it will not have.

For anything not in the list, give the key an action that suits and trigger an
automation from the `ulanzi_deck_key` event.

## Settings I chose

- **Draft and published are separate.** You can change things for as long as you
  like without the deck flickering through half-finished screens.
- **A key that drives something looks like it.** A light key dims when the light is
  off. Keys for scripts, scenes and buttons stay lit, because those have no "off".
- **The deck's stored layout shows no readings.** Sensor keys are stored showing
  `--`, so a deck that has just powered up never shows an old number as if it were
  current. Live values arrive when the bridge connects.
- **The bridge is not behind Home Assistant's login.** It has no user. It proves
  itself with its own secret, and is admitted straight away when it arrives with a key this server wrote down, which is
what the pairing file in the download carries. One that turns up without a key waits
until an admin presses Allow.
- **Changes to how keys are drawn don't need a restart.** Reloading the integration
  picks up changed code.

## Add just this part

The ordinary way is the Marketplace, in [step 1 of the setup guide](../../README.md).
This is the same thing by hand, for working on it:

1. Copy the folder `custom_components/ulanzi_deck` from this repo into the
   `custom_components` folder inside your Home Assistant `config` folder. Create
   `custom_components` if it isn't there.
2. Restart Home Assistant.
3. Go to **Settings → Devices & services → Add integration**, search for
   **Ulanzi Deck**, and add it. It asks no questions.
4. **Ulanzi Deck** appears in the sidebar. Until the connector app is running its chip
   reads "Bridge not connected".

The repo carries a `hacs.json` and is laid out the way the Marketplace expects, so it
installs as a custom repository (type: Integration). It is not in the Marketplace's own
list of integrations, so it has to be added by its address first.

To remove it: delete the integration under Devices & services, delete the folder,
and restart.

---

[← Part 3](../03-mac-bridge/README.md) · [All parts](../../README.md) · [Part 5 →](../05-the-panel/README.md)
