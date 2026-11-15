[All parts](../../README.md) · [Part 2 →](../02-deck-app/README.md)

# Part 1 · The deck

The Ulanzi D200 looks like fourteen little screens. It is one screen, behind a case
with fourteen clear keys in it, driven by a small Linux computer that only speaks USB.

Everything on this page was read off my own deck. Where I can't say it holds for
every D200, it says so.

## At a glance

| | |
|---|---|
| **Built from** | Ulanzi D200. The case is printed U·STUDIO |
| **Files in this folder** | This page only |
| **Also needs** | A Mac with `adb` to look inside it: see [What you need](../../README.md#what-you-need-and-how-it-joins-up) |
| **Reads** | Fourteen keys |
| **Shows** | One 1280 × 720 picture, seen through fourteen windows |

## What is inside

| | |
|---|---|
| Processor | Rockchip RK3308, four cores, 32-bit ARM |
| System | Buildroot 2021.11, Linux 5.10.160 |
| Screen | One panel, 720 × 1280, mounted on its side. In use it is a 1280 × 720 picture |
| Keys | 14 switches: 13 single keys and one double-width key at bottom right |
| Storage | A small system partition, completely full, and a 52 MB partition at `/userdata` with 44 MB free |
| Network | None. No Wi-Fi, no Ethernet |
| Clock | None that keeps time. It starts in 1970 every time it is powered |
| Power | From the USB cable |

## How it talks to the computer

Over USB it presents three things at once:

| What | Used for |
|---|---|
| A data channel, 1024 bytes each way | Everything this project sends. No driver needed on a Mac |
| A debug port (ADB) | Getting in to install the app |
| A keyboard | How the vendor's software types shortcuts. Not used here |

## Getting in

*Developer notes. None of this is part of setting a deck up — [the setup guide](../../README.md) is.*


Plug the deck into the Mac and run:

```bash
adb devices
```

On my deck that listed one device straight away, with a root shell and no password.
I don't know whether every D200 ships that way. If yours lists nothing, this project
can't be installed on it as written.

## What runs on it, and why replacing it is safe

At power-up the deck starts one program, `/userdata/UlanziDeckKey`. That is the
vendor's app. This project puts its own app at that path ([Part 2](../02-deck-app/README.md)).

- The debug port is started separately, by a different script. Whatever the app
  does, you can still get in with `adb`.
- Nothing outside `/userdata` is touched.
- The vendor app is copied to `/userdata/vendor/` first.

On my deck the vendor app was already failing to start before I changed anything.
So I can tell you how to put it back, but not that it will work when you do.

## Things that caught me out

| What | Why it matters |
|---|---|
| The screen is on its side, and upside down from the obvious guess | The app turns every picture before drawing it. You don't have to |
| The keys are not a tidy grid | Their windows are 259 to 260 pixels apart across and not evenly spaced down. See [Part 6](../06-lining-up-the-keys/README.md) |
| The boot logo stays on screen | Until an app takes the screen over, the deck keeps showing "starting up". The app does this at start |
| The clear keys are thick | Looked at from an angle, what is behind a key appears to slide. Line things up looking square-on |
| It froze once | Screen lit, not answering, cable had to be pulled. Once in a day of use, cause not found |

---

[All parts](../../README.md) · [Part 2 →](../02-deck-app/README.md)
