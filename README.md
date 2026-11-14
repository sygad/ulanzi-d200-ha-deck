# Setting up your Ulanzi deck

Six steps, and four of them happen inside Home Assistant. Nothing is typed into a
terminal and no files are copied by hand.

<br>

<a href="images/ulanzi-d200.png"><img src="images/ulanzi-d200.png" alt="The Ulanzi D200: a desk stream deck with fourteen clear keys and a stand" width="100%"></a>

<br>

### **[→ Try the panel in your browser first](https://sygad.github.io/ulanzi-d200-ha-deck/docs/try/)**

The real panel, running against a house that does not exist. Nothing is installed and
nothing of yours is touched. Press **PREVIEW** and the keys answer.

<br>

<a href="images/deck.png"><img src="images/deck.png" alt="The deck: fourteen keys showing lights, a temperature graph, a power dial and a wide CO2 reading" width="100%"></a>

<br>

---

<br>

## What you need, and how it joins up

<img src="images/guide/fig-what-you-need.png" alt="Home Assistant, where it already runs, joined over the network to your Mac, which the deck plugs into over USB" width="100%">

<br>

---

<br>

## 1 &nbsp; Download from the Marketplace

In **Settings → Marketplace**, press the three dots at the top right and choose
**Custom repositories**. Press **Add from link** at the bottom right, paste
`https://github.com/sygad/ulanzi-d200-ha-deck` and press **Add**. Nothing else is asked;
it works out what it is.

<br>

<img src="images/guide/fig-step1-add.png" alt="The Add from a GitHub link dialog, with the repository address typed in" width="100%">

<br>
<br>

**Ulanzi Deck** is then in the list, as an Integration. Click that row.

<br>

<img src="images/guide/fig-step1-list.png" alt="The Custom repositories list with Ulanzi Deck in it" width="100%">

<br>
<br>

Its own page opens. Press **Install**.

<br>

<img src="images/guide/fig-step1-install.png" alt="The Ulanzi Deck page in the Marketplace, with an Install button" width="100%">

<br>

---

<br>

## 2 &nbsp; Restart Home Assistant

Home Assistant raises this itself after any new download. Nothing you have just
installed is running until it has restarted once.

If you miss the prompt: **Settings → System**, the power icon in the top right, then
**Restart Home Assistant**.

<br>

<img src="images/guide/fig-step2.png" alt="Home Assistant asking to restart after the download" width="100%">

<br>

---

<br>

## 3 &nbsp; Add it under Devices & services

Downloading put the files in place; this switches it on. Go to **Settings → Devices &
services**, press **Add integration** at the bottom right, search for **Ulanzi Deck**
and pick it. It asks nothing — press Submit and it is done.

<br>

---

<br>

## 4 &nbsp; Open Ulanzi Deck in the sidebar

A new item appears down the left. Open it and press the one button on the page.

<br>

<img src="images/guide/fig-step3.png" alt="The Ulanzi Deck page in Home Assistant, offering to get the companion app" width="100%">

<br>

---

<br>

## What the companion app is, before you run it

Downloading a program from someone you have never met is a fair thing to be wary of.
So here is exactly what it is, and why it has to exist at all.

**Your deck has no network.** No wifi, no ethernet, no address of its own. Everything
it shows arrives down the USB cable. Home Assistant runs somewhere else on your
network and cannot see a USB device plugged into a different computer. Something has
to sit on the computer the cable goes into and pass messages along. That is the whole
job.

<br>

**What it does**

- ✅ &nbsp;Holds the USB connection and passes messages between the deck and your Home Assistant.
- ✅ &nbsp;Tells the deck the time, because the deck has no clock of its own.
- ✅ &nbsp;Copies the deck software across. Once, at the start, keeping Ulanzi's own copy so you can go back.

**What it never does**

- ❌ &nbsp;No account, no sign-in, no cloud service. Nothing of yours leaves your network.
- ❌ &nbsp;Talks to one address only: the Home Assistant you pointed it at.
- ❌ &nbsp;No analytics, no telemetry, no automatic updates, nothing else running in the background.

<br>

Every line of it is published, the program that runs on the deck included. You can read
it, change it, or build the app yourself rather than download it.

<br>

---

<br>

## 5 &nbsp; Open the companion app

Open the zip. There are two things inside it: the app, and a small file beside it.

**Double-click Ulanzi Deck.** Leave `ulanzi-deck-pairing.json` where it is — the app
reads it the first time it runs. That file is what tells the app where your Home
Assistant is and lets it straight in, which is why there is nothing to type and nothing
to allow. Once the app has opened, you can throw it away and move the app into
Applications if you want it there.

<br>

<p align="center"><img src="images/guide/fig-step5-unzip.png" alt="The unzipped folder: the Ulanzi Deck app, and the pairing file beside it" width="560"></p>

<br>

### macOS will stop you the first time. Here is how to get past it.

<img src="images/guide/fig-gate-dialog.png" alt="The macOS warning: Ulanzi Deck Not Opened, with Done and Move to Bin" width="320">

1. Press **Done**. **Not** Move to Bin, however blue that button is.
2. Open **System Settings → Privacy & Security**.
3. Scroll down to Security. There is a line about Ulanzi Deck being blocked.
4. Press **Open Anyway**.

That is it, once, forever. Every Mac shows this for software not sold through Apple's
own store — it means nobody has paid Apple to vouch for it, not that anything is wrong
with it.

<br>

One window, and it finds Home Assistant by itself. **Plug the deck in whenever you
like** — before or after opening the app makes no difference. A deck already plugged in
is picked up the moment it starts.

If your deck is still running the software it came with, the app says so and offers one
button, *Set up my deck*. Press it once and it takes a few seconds. After that there is
never anything to press.

<br>

<p align="center"><img src="images/guide/fig-step4.png" alt="The companion app: Everything is working, with Home Assistant and Deck both showing a green dot" width="440"></p>

<br>

---

<br>

## 6 &nbsp; Customise your deck

Back in the same sidebar page. Pick a key, give it something to do, and press **Send to
device**. **Preview** lets you try a key in the browser before it ever reaches the deck.

<br>

<a href="images/guide/fig-step5.png"><img src="images/guide/fig-step5.png" alt="The Ulanzi Deck panel: key settings on the left, a live preview of the fourteen keys on the right" width="100%"></a>

<br>

---

<br>

**Licence** — [MIT](LICENSE). Fonts and icons keep their own licences, listed in [NOTICE.md](NOTICE.md).

**Credits** — **Roboto** by Google, Apache 2.0. **Material Design Icons** by [Pictogrammers](https://pictogrammers.com/library/mdi/). `adb`, carried inside the companion app, Apache 2.0. Ulanzi's own software is not included here. Not affiliated with Ulanzi or with Home Assistant.
