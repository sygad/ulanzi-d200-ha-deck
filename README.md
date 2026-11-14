# Ulanzi D200 Home Assistant Control Deck

Fourteen keys on your desk that run your house. Toggle lights, fire scenes, switch
screens, and watch a reading move as a number, a bar, a dial or a graph. You set all
of it up from a page inside Home Assistant, pressing keys to try them before they ever
reach the deck.

<br>

<a href="images/ulanzi-d200.png"><img src="images/ulanzi-d200.png" alt="The Ulanzi D200: a desk stream deck with fourteen clear keys and a stand" width="100%"></a>

<p align="center"><sub>The Ulanzi D200. Thirteen keys plus one double-width key, sold as U·STUDIO.</sub></p>

<br>

---

<br>

## Try it right now, in your browser

### **[→ Open the panel](https://sygad.github.io/ulanzi-d200-ha-deck/docs/try/)**

That is the real panel out of this repository, running against a house that does not
exist. Nothing is installed, nothing is downloaded, and nothing of yours is touched.

Press **PREVIEW** at the top right and the keys become live: tap a light and watch it
come on, tap **Next screen** and the deck moves. It is the same preview you get once
it is installed, and it is the quickest way to decide whether you want this.

<br>

---

<br>

## What it looks like

### On the deck

One of its screens, drawn by the deck itself. Click to see it full size.

<br>

<a href="images/deck.png"><img src="images/deck.png" alt="The deck: fourteen keys showing lights, a temperature graph, a power dial and a wide CO2 reading" width="100%"></a>

<br>
<br>

### In Home Assistant

Where you set it up, with a live preview of the deck beside you.

<br>

<a href="images/panel.jpg"><img src="images/panel.jpg" alt="The Ulanzi Deck panel: key settings on the left, a live preview of the fourteen keys on the right" width="100%"></a>

<br>

Everything pictured is the invented house in [`tools/demo_house.py`](tools/demo_house.py),
which comes with the repository. No real home appears anywhere in here.

<br>

---

<br>

## Setting it up

Five steps. Three of them happen inside Home Assistant, and none of them involves a
terminal, a file copied by hand, or lining anything up.

### **[→ The setup guide, with a picture of every step](https://sygad.github.io/ulanzi-d200-ha-deck/docs/)**

In short:

| | |
|---|---|
| **1** | **Add it to the Marketplace, once.** In Home Assistant go to **Settings → Marketplace**, press the three dots at the top right, choose **Custom repositories**, paste `https://github.com/sygad/ulanzi-d200-ha-deck`, pick **Integration** and press Add. Ulanzi Deck then appears in the list: open it and press **Download**. |
| **2** | **Restart Home Assistant.** It asks you to. Nothing you have just downloaded is running until it has. |
| **3** | **Open Ulanzi Deck in the sidebar.** It is there after the restart. Press **Get the companion app**. |
| **4** | **Open the companion app on your Mac.** It finds Home Assistant by itself. Plug the deck in whenever you like — before or after makes no difference — and it sets the deck up on its own. |
| **5** | **Customise your deck.** Pick a key, give it something to do, press it in the preview to check, then **Send to device**. |

Steps 1 to 4 take a few minutes. Step 5 is yours and has no end.

<br>

### What you need

| | |
|---|---|
| **An Ulanzi D200** | Sold by [Ulanzi](https://www.ulanzi.com). Its case is printed U·STUDIO |
| **A Mac** | The deck plugs into it over USB and is powered by it. Tested on Apple silicon, macOS 13 or newer |
| **The cable it came with** | It has to be a data cable. Some are power only |
| **Home Assistant** | Anywhere on the same network as the Mac. It does not have to be the Mac. Tested on 2026.11.1 |

Nothing else. No Xcode, no Homebrew, no `adb`, no Python — the companion app carries
everything it needs inside it.

<br>

### You start with a blank deck

The panel opens on one empty screen. Nothing is set up for you, on purpose: a key
pointing at a light you do not own is worse than no key. Press a **+**, pick one of your
own entities, press **Send to device**, and it is on the deck a second later.

<br>

---

<br>

## Before you start

- **It replaces the software on the deck.** Ulanzi's own app will not see the deck while
  this is installed. Yours is saved first and the companion app puts it back.
- **The companion app is Mac only.** The deck has no network of its own, so the computer
  it is plugged into carries its traffic. There is no Windows or Linux version yet.
- **It has been built and tested on one deck.** Mine. Where something might differ on
  yours, the page says so.

<br>

---

<br>

## Things to know

| | |
|---|---|
| **The deck needs the Mac** | It is powered over USB and has no network of its own. Mac off, deck off |
| **It starts fast** | The deck draws its last layout from its own memory the moment it has power, before anything else is running |
| **A dot means not connected** | Top right of the wide key: red for no companion app, amber for an app with no Home Assistant behind it. Keys do nothing until it clears |
| **Nothing is queued** | A press made while disconnected is dropped, not saved up |
| **The screen turns itself off** | After 20 minutes of nothing happening, to save the panel. Any key wakes it, and that waking press does nothing else. Change it, or turn it off, with the gear in the panel's top bar |
| **It froze once** | During development the deck stopped completely, screen lit and not answering, and needed its cable pulled. It has not happened again and I never found the cause |

<br>

---

<br>

## Looking inside

You do not need any of this to use it. It is here because the whole thing is open, and
because somebody will want to know how a deck with no network ends up showing a graph.

```
docs/                             the setup guide, and the panel you can try in a browser
custom_components/ulanzi_deck/    the Home Assistant integration and its panel
parts/
  01-the-deck/                    what is inside a D200
  02-deck-app/                    the app that runs on the deck: one C file, no libraries
  03-mac-bridge/                  the companion app, and the agent underneath it
  04-home-assistant/              the integration, and what it gives you
  05-the-panel/                   how keys and screens are set up
  06-lining-up-the-keys/          how the key positions were measured in the first place
shared/                           the wire format, the layout file, the sizing rule
tools/                            helpers, and the invented house everything is demonstrated on
```

<br>

---

<br>

## Licence

[MIT](LICENSE): use, copy and change anything here, for any purpose.

The fonts and icons bundled with the integration keep their own licences, listed in
[NOTICE.md](NOTICE.md). Ulanzi's own software is not included in this repository.

## Credits

- **Roboto** by Google, [Apache License 2.0](http://www.apache.org/licenses/LICENSE-2.0).
- **Material Design Icons** by [Pictogrammers](https://pictogrammers.com/library/mdi/),
  under the Pictogrammers Free License (fonts and icons: Apache License 2.0).
- `adb`, carried inside the companion app, is Apache License 2.0.
- Not affiliated with Ulanzi or with Home Assistant.
