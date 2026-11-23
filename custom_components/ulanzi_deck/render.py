"""Draws keys, and packs them into the blob the deck caches.

Nothing in here knows about Home Assistant. It takes the key configuration the
panel saves and, per key, a small dict of live facts (is the light on, what does
the sensor read), and returns images. That keeps it testable on a desk.

The deck's screen is one 1280x720 panel behind fourteen caps. Each key gets a
picture at its own place on the panel (see SLOTS), and only the middle of that
shows through its cap, so everything is composed inside a smaller safe box.
"""

from __future__ import annotations

from functools import lru_cache
import json
import math
from pathlib import Path
import struct
import zlib

from PIL import Image, ImageDraw, ImageFont

NKEYS, WIDE = 14, 13
PANEL_W, PANEL_H = 1280, 720

# Where every key is on the panel.
#
# These are measured on the deck itself, the only way that turned out to work.
# The screen is one panel behind fourteen windows in the case, and nothing in
# software says where the windows are. On 13 Nov 2026 the owner drew them: with
# `ulanzi-deck-bridge --grid` he nudged eighteen one-pixel lines onto the edges
# of the windows, looking at each key square-on, and these are where the lines
# stopped (kept in parts/06-lining-up-the-keys/grid.json). Each pair is the first and last
# pixel that shows through.
#
# Everything tried before this was wrong, and none of it should be tried again:
# equal thirds of the panel; a centred grid 256 apart; a correction for viewing
# angle worked out from photographs; and the manufacturer's own table from the
# vendor app, which is 3 to 4 pixels out across, 8 out for the wide key, and
# puts the rows too close together. To redo it, run the grid tool again.
KEY_X = ((14, 210), (274, 470), (533, 729), (793, 989), (1053, 1249))   # left, right of each column
KEY_Y = ((5, 196), (261, 455), (523, 715))                              # top, bottom of each row
WIDE_X = (791, 1247)                                                    # the wide key, on the bottom row
MARGIN = 24  # a key's picture runs this far past its window, so no edge shows from an angle


def _window(n: int) -> tuple[int, int, int, int]:
    """(left, top, right, bottom) of what shows through key n's cap, inclusive."""
    if n == WIDE:
        return (WIDE_X[0], KEY_Y[2][0], WIDE_X[1], KEY_Y[2][1])
    row, col = divmod(n, 5)
    return (KEY_X[col][0], KEY_Y[row][0], KEY_X[col][1], KEY_Y[row][1])


def _place(n: int) -> tuple[int, int, int, int, int, int]:
    """Key n's picture on the panel, and where in it the middle of the key is."""
    left, top, right, bottom = _window(n)
    x0, y0 = max(0, left - MARGIN), max(0, top - MARGIN)
    x1, y1 = min(PANEL_W, right + 1 + MARGIN), min(PANEL_H, bottom + 1 + MARGIN)
    return (x0, y0, x1 - x0, y1 - y0, (left + right + 1) // 2 - x0, (top + bottom + 1) // 2 - y0)


_PLACES = [_place(n) for n in range(NKEYS)]
for _a in range(NKEYS):  # no two pictures may overlap: the deck draws them independently
    for _b in range(_a):
        _ax, _ay, _aw, _ah = _PLACES[_a][:4]
        _bx, _by, _bw, _bh = _PLACES[_b][:4]
        assert _ax + _aw <= _bx or _bx + _bw <= _ax or _ay + _ah <= _by or _by + _bh <= _ay, (_a, _b)
SLOTS = [p[:4] for p in _PLACES]       # (x, y, w, h) on the panel: what the deck is told
CENTRES = [p[4:] for p in _PLACES]     # the middle of the key, inside its picture

# Sizes. The panel's preview and this renderer follow one rule, set on the real
# deck: on a key 100 wide, an icon is 54 and a label is 14. The panel writes every
# size as a fraction of the key's width (--k in panel.js); here a key is K = 200
# pixels wide, so each size below is the panel's fraction times 200. Change one,
# change the other.
#
# A cap shows about 197 x 193 (see above); K rounds that to 200 to keep the sums easy.
# Content keeps the preview's padding inside it, which leaves the box below.
K = 200
SAFE_W, SAFE_H, SAFE_WIDE_W = 184, 166, 440

# What a key is drawn on unless it has a background colour of its own ("bg").
# Black, like the frame round the caps. (For a few hours on 13 Nov 2026 it was a
# mid grey, #9D9D9D, so that the edges of the keys could be seen while they were
# being lined up; that was a debugging aid and the owner had it taken out.)
# The panel uses the same colour (KEYBG in panel.js): change both.
BACKGROUND = (0, 0, 0)
BLACK = (0, 0, 0)          # between the keys, where the frame is
# The caps are tinted and muted colours drift towards the nearest bright hue, so
# "off" is a neutral dark grey rather than a dim version of the key's colour.
OFF = (84, 84, 84)
TRACK = (44, 44, 44)       # the unfilled part of a bar or dial, on a black key


def track_for(bg: tuple[int, int, int]) -> tuple[int, int, int]:
    """The unfilled part of a bar or dial: a step darker than a light key, lighter than a dark one.

    It has to show against the key's background and against the filled part,
    whatever colours those are. The panel does the same sum (trackOf in panel.js).
    """
    light = 0.299 * bg[0] + 0.587 * bg[1] + 0.114 * bg[2] > 90
    return tuple(round(c * 0.78) if light else round(c + (255 - c) * 0.17) for c in bg)
GREEN, AMBER, RED = (139, 195, 74), (255, 193, 7), (255, 82, 82)

SS = 4  # supersampling for anything that is not text

_DIR = Path(__file__).parent
_FONT_FILES = {
    "medium": "Roboto-Medium.ttf",
    "regular": "Roboto-Regular.ttf",
    "mdi": "mdi.ttf",
}
_SUB = {chr(0x2080 + i): str(i) for i in range(10)}
_SUP = {"\u00b2": "2", "\u00b3": "3", "\u00b9": "1"}


@lru_cache(maxsize=None)
def _icons() -> dict[str, str]:
    return json.loads((_DIR / "frontend" / "icons.json").read_text(encoding="utf-8"))


@lru_cache(maxsize=256)
def _font(kind: str, size: int) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(str(_DIR / "fonts" / _FONT_FILES[kind]), max(4, size))


@lru_cache(maxsize=None)
def _notdef(kind: str) -> bytes:
    return bytes(_font(kind, 32).getmask("\uffff"))


@lru_cache(maxsize=4096)
def _has(kind: str, ch: str) -> bool:
    if ch.isspace():
        return True
    return bytes(_font(kind, 32).getmask(ch)) != _notdef(kind)


def _rgb(c: str | None) -> tuple[int, int, int]:
    try:
        c = (c or "#ffffff").lstrip("#")
        return (int(c[0:2], 16), int(c[2:4], 16), int(c[4:6], 16))
    except (ValueError, IndexError):
        return (255, 255, 255)


def _dim(c: tuple[int, int, int], f: float) -> tuple[int, int, int]:
    return (round(c[0] * f), round(c[1] * f), round(c[2] * f))


# ---------------------------------------------------------------- items
#
# A key is a short list of items, each knowing its size and how to draw itself.
# Laying a key out is then only arithmetic on boxes.


class _Text:
    """One line of text, possibly in several runs sharing a baseline."""

    def __init__(self, runs, line_h: float, name: str = "") -> None:
        # runs: (text, kind, size, colour)
        self.runs = [r for r in runs if r[0]]
        self.h = round(line_h)
        self.name = name
        self.gap = 3  # between runs: a reading and its unit
        self.w = round(sum(self._len(r) for r in self.runs) + self.gap * max(0, len(self.runs) - 1))
        self.pos = (0, 0)  # filled in by draw: left edge, baseline

    @staticmethod
    def _pieces(text: str, kind: str, size: int):
        """Split into (string, font, drop) where the font actually has the glyphs."""
        out: list[list] = []
        for ch in text:
            if ch in _SUB or ch in _SUP:
                piece = [
                    _SUB.get(ch) or _SUP[ch],
                    _font(kind, round(size * 0.62)),
                    round(size * 0.12) if ch in _SUB else -round(size * 0.34),
                ]
            elif _has(kind, ch):
                piece = [ch, _font(kind, size), 0]
            else:
                piece = [ch, ImageFont.load_default(size), 0]
            if out and out[-1][1] is piece[1] and out[-1][2] == piece[2]:
                out[-1][0] += piece[0]
            else:
                out.append(piece)
        return out

    def _len(self, run) -> float:
        return sum(f.getlength(s) for s, f, _ in self._pieces(run[0], run[1], run[2]))

    def draw(self, d: ImageDraw.ImageDraw, x: float, y: float) -> None:
        asc, desc = _font(self.runs[0][1], self.runs[0][2]).getmetrics() if self.runs else (0, 0)
        base = y + (self.h - (asc + desc)) / 2 + asc
        self.pos = (round(x), round(base))
        for text, kind, size, colour in self.runs:
            for s, f, drop in self._pieces(text, kind, size):
                d.text((x, base + drop), s, font=f, fill=colour, anchor="ls")
                x += f.getlength(s)
            x += self.gap


class _Slot(_Text):
    """Room kept for text the deck draws itself (the time, the date)."""

    def draw(self, d, x, y) -> None:
        asc, desc = _font(self.runs[0][1], self.runs[0][2]).getmetrics()
        self.pos = (round(x), round(y + (self.h - (asc + desc)) / 2 + asc))


class _Label:
    """Up to two lines, wrapped, ellipsis on overflow."""

    def __init__(self, text: str, size: int, colour, max_w: int, align: str) -> None:
        self.size, self.colour, self.align = size, colour, align
        probe = _Text([("x", "medium", size, colour)], size)
        words, lines, line = text.split(), [], ""
        fits = lambda s: probe._len((s, "medium", size, colour)) <= max_w  # noqa: E731
        while words:
            w = words.pop(0)
            trial = (line + " " + w).strip()
            if fits(trial):
                line = trial
                continue
            if line:
                lines.append(line)
                line = ""
                words.insert(0, w)
                continue
            cut = len(w)  # a single word wider than the key
            while cut > 1 and not fits(w[:cut]):
                cut -= 1
            lines.append(w[:cut])
            words.insert(0, w[cut:])
        if line:
            lines.append(line)
        if len(lines) > 2:
            last = lines[1]
            while last and not fits(last + "\u2026"):
                last = last[:-1]
            lines = [lines[0], last + "\u2026"]
        self.lines = [_Text([(s, "medium", size, colour)], size * 1.15) for s in lines]
        self.w = max((t.w for t in self.lines), default=0)
        self.h = sum(t.h for t in self.lines)

    def draw(self, d, x, y) -> None:
        for t in self.lines:
            t.draw(d, x if self.align == "left" else x + (self.w - t.w) / 2, y)
            y += t.h


class _Icon:
    def __init__(self, name: str, size: int, colour) -> None:
        self.cp = _icons().get(name)
        self.w = self.h = size
        self.colour = colour

    def draw(self, d, x, y) -> None:
        if self.cp:
            d.text((x + self.w / 2, y + self.h / 2), chr(int(self.cp, 16)),
                   font=_font("mdi", self.w), fill=self.colour, anchor="mm")


class _Shape:
    """Anything drawn with lines: supersampled, then pasted through its own mask."""

    def __init__(self, w: int, h: int) -> None:
        self.w, self.h = w, h

    def _layers(self):  # yields (colour, painter(draw, scale))
        raise NotImplementedError

    def draw(self, d, x, y) -> None:
        img = d._image  # noqa: SLF001 - the image this draw object belongs to
        for colour, paint in self._layers():
            m = Image.new("L", (self.w * SS, self.h * SS), 0)
            paint(ImageDraw.Draw(m), SS)
            m = m.resize((self.w, self.h), Image.Resampling.LANCZOS)
            img.paste(colour, (round(x), round(y)), m)


class _Bar(_Shape):
    """A bar `thick` deep, in the middle of a box h high.

    On a stacked key the box is the same size as a graph's, so a bar key and a
    graph key put their reading and name in the same places.
    """

    def __init__(self, frac, w, h, colour, thick: int | None = None) -> None:
        super().__init__(w, h)
        self.frac, self.colour, self.thick = frac, colour, thick or h

    def _layers(self):
        w, t, f = self.w, self.thick, self.frac
        top = (self.h - t) / 2
        yield getattr(self, "track", TRACK), lambda d, s: d.rounded_rectangle(
            (0, top * s, w * s - 1, (top + t) * s - 1), t * s // 2, fill=255)
        if f > 0:
            fw = max(t, round(w * f))
            yield self.colour, lambda d, s: d.rounded_rectangle(
                (0, top * s, fw * s - 1, (top + t) * s - 1), t * s // 2, fill=255)


class _Gauge(_Shape):
    """A 270 degree dial, open at the bottom."""

    def __init__(self, frac, size, colour) -> None:
        super().__init__(size, size)
        self.frac, self.colour = frac, colour

    def _arc(self, d, s, sweep):
        size = self.w * s
        r, t = size * 0.4, size * 0.1
        box = (size / 2 - r - t / 2, size / 2 - r - t / 2, size / 2 + r + t / 2, size / 2 + r + t / 2)
        d.arc(box, 135, 135 + sweep, fill=255, width=round(t))
        for a in (135, 135 + sweep):  # round caps
            cx = size / 2 + r * math.cos(math.radians(a))
            cy = size / 2 + r * math.sin(math.radians(a))
            d.ellipse((cx - t / 2, cy - t / 2, cx + t / 2, cy + t / 2), fill=255)

    def _layers(self):
        yield getattr(self, "track", TRACK), lambda d, s: self._arc(d, s, 270)
        if self.frac > 0.004:
            yield self.colour, lambda d, s: self._arc(d, s, 270 * self.frac)


class _GaugeWithReading(_Gauge):
    """A dial with its reading in the middle and the unit in the gap at the bottom.

    A dial is the one graphic with a hole in it. Putting the reading there lets
    the dial be half as big again on a stacked key, where dial, reading and name
    would otherwise have to share the height three ways.
    """

    def __init__(self, frac, size, colour, text: str, unit: str) -> None:
        super().__init__(frac, size, colour)
        room = size * 0.56  # what the ring leaves clear across its middle, with a little air
        vs = round(size * 0.36)
        while True:
            self.reading = _Text([(text, "medium", vs, colour)], vs)
            if self.reading.w <= room or vs <= 14:
                break
            vs -= 2
        us = max(12, round(size * 0.17))
        self.unit = _Text([(unit, "regular", us, _dim(colour, 0.75))], us) if unit else None

    def draw(self, d, x, y) -> None:
        super().draw(d, x, y)
        cx, cy = x + self.w / 2, y + self.h / 2
        self.reading.draw(d, cx - self.reading.w / 2, cy - self.reading.h / 2 - self.h * 0.03)
        if self.unit:
            self.unit.draw(d, cx - self.unit.w / 2, cy + self.h * 0.36 - self.unit.h / 2)


class _Spark(_Shape):
    def __init__(self, hist, w, h, colour) -> None:
        super().__init__(w, h)
        self.hist, self.colour = hist, colour

    def _layers(self):
        hist = self.hist
        if len(hist) < 2:
            return
        lo, hi = min(hist), max(hist)
        span = (hi - lo) or 1
        w, h = self.w, self.h
        pad = 6

        def paint(d, s):
            pts = [
                ((pad + i / (len(hist) - 1) * (w - 2 * pad)) * s,
                 (h - pad - (v - lo) / span * (h - 2 * pad)) * s)
                for i, v in enumerate(hist)
            ]
            t = 3.5 * s
            d.line(pts, fill=255, width=round(t), joint="curve")
            for px, py in pts:
                d.ellipse((px - t / 2, py - t / 2, px + t / 2, py + t / 2), fill=255)
            px, py = pts[-1]
            d.ellipse((px - 5 * s, py - 5 * s, px + 5 * s, py + 5 * s), fill=255)

        yield self.colour, paint


# ---------------------------------------------------------------- keys


def _horiz(key: dict, n: int) -> str:
    return key.get("layout", "v") if n == WIDE and key.get("layout") in ("h", "hr") else ""


def band_colour(v: float, key: dict) -> tuple[int, int, int]:
    lo, hi = float(key.get("min", 0)), float(key.get("max", 100))
    warn = key.get("warn", lo + (hi - lo) * 0.5)
    alert = key.get("alert", lo + (hi - lo) * 0.75)
    return GREEN if v < warn else AMBER if v < alert else RED


def _compose(key: dict, n: int, live: dict, z: float):
    """Returns (art item or None, text items, slots) at zoom z."""
    px = lambda v: max(1, round(v * z))  # noqa: E731
    horiz = _horiz(key, n)
    wide = n == WIDE
    max_w = SAFE_WIDE_W if wide else SAFE_W
    align = "left" if horiz else "centre"
    colour = _rgb(key.get("c"))
    show_icon = key.get("showIcon") is not False
    label = (key.get("l") or "").strip()
    art, text, slots = None, [], {}

    if key.get("type") == "clock":
        if key.get("i") and show_icon:
            art = _Icon(key["i"], px(116 if horiz else 58), colour)
        nominal = "00:00" + (":00" if key.get("secs") else "") + (" pm" if key.get("fmt") == "12" else "")
        # the time is as large as its widest reading allows, and no larger
        size = px(106 if wide else 68)
        room = max_w - (art.w + 24 if art and horiz else 0)
        wide_as = _Slot([(nominal, "medium", size, colour)], size).w
        if wide_as > room:
            size = max(8, int(size * room / wide_as))
        slots["time"] = _Slot([(nominal, "medium", size, colour)], size)
        text.append(slots["time"])
        if key.get("date"):
            dsize = px(28)
            slots["date"] = _Slot([("Wed 30 Sep", "regular", dsize, _dim(colour, 0.75))], dsize + px(8))
            text.append(slots["date"])
        if label:
            text.append(_Label(label, px(28), colour, max_w, align))
        return art, text, slots

    if key.get("type") == "entity":
        v = live.get("value")
        lo, hi = float(key.get("min", 0)), float(key.get("max", 100))
        frac = 0.0 if v is None else max(0.0, min(1.0, (v - lo) / ((hi - lo) or 1)))
        style = key.get("style", "icon")
        if key.get("band") and style in ("bar", "gauge", "graph"):
            colour = band_colour(lo if v is None else v, key)
        if style == "bar":
            # stacked, a bar takes the room a graph would: same width, same height
            art = _Bar(frac, px(128), px(16), colour) if horiz else _Bar(frac, px(154), px(64), colour, px(16))
        elif style == "gauge" and horiz:
            art = _Gauge(frac, px(116), colour)
        elif style == "gauge":
            # stacked: the reading goes inside the dial, so only the name is left underneath
            named = key.get("show") == "full" and (label or live.get("name"))
            art = _GaugeWithReading(frac, px(120 if named else 150), colour,
                                    live.get("text") or "--", live.get("unit") or "")
        elif style == "graph":
            hist = live.get("history") or []
            if len(hist) >= 2:
                art = _Spark(hist, px(180 if horiz else 154), px(80 if horiz else 64), colour)
        elif style == "icon" and key.get("i"):
            art = _Icon(key["i"], px(116 if horiz else 58), colour if horiz else _dim(colour, 0.85))
        big = bool(horiz) or style in ("icon", "number") or art is None
        vs, us = (px(69 if horiz else 56), px(32)) if big else (px(40), px(26))
        if art is not None:
            art.track = track_for(background_of(key))
        unit = live.get("unit") or ""
        if not isinstance(art, _GaugeWithReading):  # that one carries its own reading
            text.append(_Text(
                [(live.get("text") or "--", "medium", vs, colour),
                 (unit, "regular", us, _dim(colour, 0.75))],
                vs))
        name = label or live.get("name") or ""
        if key.get("show") == "full" and name:
            text.append(_Label(name, px(28), colour, max_w, align))
        elif not horiz and isinstance(art, (_Bar, _Spark)):
            # no name under it: the reading would crowd up against the bar or graph
            # with empty key below, so it stands a little further off
            art.after = px(12)
        return art, text, slots

    # button
    if not live.get("lit", True):
        colour = OFF
    if key.get("i") and show_icon:
        art = _Icon(key["i"], px(116 if horiz else 108), colour)
        art.after = 0 if horiz else px(6)  # a button's icon stands a little clear of its label
    if label:
        text.append(_Label(label, px(28), colour, max_w, align))
    return art, text, slots


def background_of(key: dict | None) -> tuple[int, int, int]:
    """A key's own background colour if it has one, the deck's otherwise."""
    return _rgb(key["bg"]) if key and key.get("bg") else BACKGROUND


def render_key(key: dict | None, n: int, live: dict | None = None):
    """Draw one key. Returns (image, slots) \u2014 slots say where the deck draws time and date."""
    _, _, tw, th = SLOTS[n]
    img = Image.new("RGB", (tw, th), background_of(key))
    if not key:
        return img, {}
    live = live or {}
    d = ImageDraw.Draw(img)
    horiz = _horiz(key, n)
    safe_w = SAFE_WIDE_W if n == WIDE else SAFE_W
    gap_v, gap_t = 6, 4
    cx, cy = CENTRES[n]  # the middle of the key, which need not be the middle of its picture

    z = 1.0
    while True:  # shrink until the content fits its window
        art, text, slots = _compose(key, n, live, z)
        if horiz:
            tw_ = max((t.w for t in text), default=0)
            th_ = sum(t.h for t in text) + gap_t * max(0, len(text) - 1)
            need_w = (art.w if art else 0) + tw_ + (24 if art and text else 0)
            need_h = max(art.h if art else 0, th_)
        else:
            items = ([art] if art else []) + text
            need_w = max((i.w for i in items), default=0)
            need_h = sum(i.h + getattr(i, "after", 0) for i in items) + gap_v * max(0, len(items) - 1)
        if (need_w <= safe_w and need_h <= SAFE_H) or z < 0.5:
            break
        z *= 0.93

    if horiz:
        # each part keeps its own width; what is left over is split into equal gaps
        parts = ([art] if art else []) + ([text] if text else [])
        if horiz == "hr":
            parts.reverse()
        widths = [p.w if p is art else tw_ for p in parts]
        gap = (safe_w - sum(widths)) / (len(parts) + 1)
        x = cx - safe_w / 2 + gap
        for p, w in zip(parts, widths):
            if p is art:
                art.draw(d, x, cy - art.h / 2)
            else:
                y = cy - th_ / 2
                for t in text:
                    t.draw(d, x, y)
                    y += t.h + gap_t
            x += w + gap
        anchor = 1  # the deck draws its text from the left of the column
    else:
        y = cy - need_h / 2
        for i in items:
            i.draw(d, cx - i.w / 2, y)
            y += i.h + getattr(i, "after", 0) + gap_v
        anchor = 0  # centred on the key
    out = {}
    for name, s in slots.items():
        text_, kind, size, colour = s.runs[0]
        out[name] = {
            "align": anchor,
            "x": s.pos[0] if anchor else cx,
            "y": s.pos[1],
            "kind": kind,
            "size": size,
            "rgb": colour,
        }
    return img, out


# ---------------------------------------------------------------- packing


# The colour of a notice. Amber, because it has to stand out from keys that may
# be any colour or none, and because amber already means "something is being
# brought up to date" everywhere else: it is the panel's --amber for a part that
# is behind, and the deck's own marker for a link that is half there.
NOTICE_COLOUR = "#ffa000"


def notice(label: str, icon: str = "progress-download") -> bytes:
    """The picture the deck shows on its wide key while something is being updated.

    Drawn exactly as a key is, so it looks like part of the deck: an icon and a
    line of words, side by side, both in NOTICE_COLOUR. The deck puts it over
    whatever the wide key was, a clock included, and takes it down by itself.
    """
    key = {"type": "button", "l": label, "i": icon, "c": NOTICE_COLOUR, "layout": "h"}
    return rle_encode(render_key(key, WIDE)[0])


def rle_encode(img: Image.Image) -> bytes:
    """u16 width, u16 height, then runs. See rle_decode() in parts/02-deck-app/deckd.c."""
    img = img.convert("RGB")
    w, h = img.size
    data = img.tobytes()
    n = w * h
    out = bytearray(struct.pack("<HH", w, h))
    lit = bytearray()

    def flush():
        for i in range(0, len(lit), 127 * 3):
            chunk = lit[i:i + 127 * 3]
            out.append(0x7F + len(chunk) // 3)
            out.extend(chunk)
        lit.clear()

    i = 0
    while i < n:
        px = data[3 * i:3 * i + 3]
        j, step = i + 1, 1
        while j < n:  # gallop to the end of the run
            step = min(step, n - j)
            if data[3 * j:3 * (j + step)] == px * step:
                j += step
                step *= 2
            elif step == 1:
                break
            else:
                step //= 2
        cnt = j - i
        if cnt == 1:
            lit.extend(px)
        else:
            flush()
            while cnt:
                c = min(cnt, 0xFFFF)
                if c <= 128:
                    out.append(c - 1)
                else:
                    out.append(0xFF)
                    out.extend(struct.pack("<H", c))
                out.extend(px)
                cnt -= c
        i = j
    flush()
    return bytes(out)


_TIME_CHARS = "0123456789:- apm"
_DATE_CHARS = "".join(chr(c) for c in range(32, 127)) + "".join(chr(c) for c in range(0xA0, 0x100))


def _atlas(kind: str, size: int, chars: str):
    """Glyph records and their alpha data, for the deck to draw text with."""
    font = _font(kind, size)
    glyphs = []
    for ch in chars:
        if not _has(kind, ch):
            continue
        x0, y0, x1, y1 = font.getbbox(ch, anchor="ls")
        w, h = min(255, max(0, x1 - x0)), min(255, max(0, y1 - y0))
        data = b""
        if w and h:
            m = Image.new("L", (w, h), 0)
            ImageDraw.Draw(m).text((-x0, -y0), ch, font=font, fill=255, anchor="ls")
            data = m.tobytes()
        glyphs.append((ord(ch), w, h, max(-128, min(127, x0)), max(-128, min(127, y0)),
                       min(255, round(font.getlength(ch))), data))
    return glyphs


_NAV = {"deck.previous_page": 2, "deck.next_page": 3, "deck.go_to_page": 4, "deck.back": 5}


def _action(slot: dict | None, npages: int) -> tuple[int, int]:
    a = (slot or {}).get("a") or "none"
    t = (slot or {}).get("t") or ""
    if a == "none":
        return 0, 0
    if a in _NAV:
        if a == "deck.go_to_page":
            try:
                page = int(t)
            except ValueError:
                return 0, 0
            return (4, page) if 0 <= page < npages else (0, 0)
        return _NAV[a], 0
    return (1, 0) if t else (0, 0)  # Home Assistant's to carry out


def build_layout(pages: list[dict], live=None, tiles: dict | None = None, sleep: int = 0) -> bytes:
    """The whole deck, as the blob the device stores and draws from at power-up.

    live(screen, key) may supply facts for a key; by default every key is drawn
    as it looks with nothing known, which is the honest picture before the
    bridge connects. Pass a dict as tiles to get each key's image back as well.

    sleep is how many minutes of nothing happening turn the deck's screen off,
    0 for never. It rides in the header so the deck keeps it over a power cut,
    like everything else about the layout.
    """
    pages = pages[:32] or [{"keys": []}]
    fonts: dict[tuple, int] = {}
    recs, images = [], []

    def font_id(spec, chars):
        return fonts.setdefault((spec["kind"], spec["size"], chars), len(fonts))

    for s, page in enumerate(pages):
        keys = list(page.get("keys") or [])
        keys += [None] * (NKEYS - len(keys))
        for n in range(NKEYS):
            key = keys[n]
            if not key:
                if BACKGROUND == BLACK:
                    recs.append(None)  # the deck draws nothing, which is black
                else:  # an empty place still shows the background
                    recs.append({"img": len(images), "flags": 1, "tap": (0, 0), "hold": (0, 0), "slots": {}})
                    images.append(rle_encode(render_key(None, n)[0]))
                continue
            img, slots = render_key(key, n, live(s, n) if live else None)
            rec = {"img": len(images), "flags": 1, "tap": (0, 0), "hold": (0, 0), "slots": {}}
            images.append(rle_encode(img))
            if tiles is not None:
                tiles[(s, n)] = images[-1]
            if key.get("type") == "clock":
                rec["flags"] |= 2 | (4 if key.get("fmt") == "12" else 0) | (8 if key.get("secs") else 0) \
                    | (16 if key.get("date") and "date" in slots else 0)
                for name, chars in (("time", _TIME_CHARS), ("date", _DATE_CHARS)):
                    if name in slots:
                        rec["slots"][name] = (font_id(slots[name], chars), slots[name])
            elif key.get("type", "button") == "button":
                rec["tap"] = _action(key.get("tap"), len(pages))
                rec["hold"] = _action(key.get("hold"), len(pages))
            recs.append(rec)

    atlases = [_atlas(kind, size, chars) for (kind, size, chars) in fonts]
    head = 24 + 8 * NKEYS
    fonts_off = head
    screens_off = fonts_off + 4 * len(atlases)
    pos = screens_off + 32 * len(recs)

    font_blobs, font_offs = [], []
    for glyphs in atlases:
        font_offs.append(pos)
        table = pos + 4 + 12 * len(glyphs)
        blob = bytearray(struct.pack("<HH", len(glyphs), 0))
        data = bytearray()
        for code, w, h, xo, yo, adv, bits in glyphs:
            blob += struct.pack("<HBBbbBBI", code, w, h, xo, yo, adv, 0, table + len(data))
            data += bits
        font_blobs.append(bytes(blob + data))
        pos += len(blob) + len(data)
    img_offs = []
    for im in images:
        img_offs.append(pos)
        pos += len(im)

    # byte 14 is the screen to start on, byte 15 the sleep timeout in minutes
    out = bytearray(struct.pack("<4sIIBBBBII", b"UDL2", pos, 0, len(pages), len(atlases), 0,
                                max(0, min(255, int(sleep))), fonts_off, screens_off))
    for slot in SLOTS:  # where each key goes: the deck has no other source for this
        out += struct.pack("<4H", *slot)
    for o in font_offs:
        out += struct.pack("<I", o)
    for rec in recs:
        if rec is None:
            out += bytes(32)
            continue
        tfont, t = rec["slots"].get("time", (0, None))
        dfont, dt = rec["slots"].get("date", (0, None))
        t = t or {"align": 0, "x": 0, "y": 0, "rgb": (0, 0, 0)}
        dt = dt or {"align": 0, "x": 0, "y": 0, "rgb": (0, 0, 0)}
        out += struct.pack(
            "<BBBBBBBBhhhh3BB3BBII",
            rec["tap"][0], rec["tap"][1], rec["hold"][0], rec["hold"][1],
            rec["flags"], tfont, t["align"], dfont,
            t["x"], t["y"], dt["x"], dt["y"],
            *t["rgb"], dt["align"], *dt["rgb"], 0,
            img_offs[rec["img"]], len(images[rec["img"]]),
        )
    for b in font_blobs:
        out += b
    for im in images:
        out += im
    assert len(out) == pos
    struct.pack_into("<I", out, 8, zlib.crc32(bytes(out)) or 1)
    return bytes(out)


def layout_id(blob: bytes) -> int:
    return struct.unpack_from("<I", blob, 8)[0]


def preview(pages: list[dict], screen: int, live=None) -> Image.Image:
    """One whole screen as the panel sees it \u2014 for tests and for looking at."""
    canvas = Image.new("RGB", (PANEL_W, PANEL_H), BLACK)
    keys = list(pages[screen].get("keys") or [])
    keys += [None] * (NKEYS - len(keys))
    for n in range(NKEYS):
        img, _ = render_key(keys[n], n, live(screen, n) if live else None)
        canvas.paste(img, SLOTS[n][:2])
    return canvas
