"""Draw the guide's picture of a deck in the middle of an update.

The demo house's first screen, as the deck shows it, with the wide key taken
over by the notice the integration sends while something is being updated
(render.notice). Nothing here is anybody's real home: see demo_house.py.

    python3 tools/notice_figure.py            writes images/guide/fig-updating.png
"""
import copy, sys
from pathlib import Path
from PIL import Image, ImageDraw
ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "custom_components" / "ulanzi_deck"))
sys.path.insert(0, str(ROOT / "tools"))
import render, demo_house

WORDS = "Updating the board"
pages = copy.deepcopy(demo_house.PAGES)
# the very key render.notice() draws, put where the deck puts it
pages[0]["keys"][render.WIDE] = {"type": "button", "l": WORDS, "i": "progress-download",
                                 "c": render.NOTICE_COLOUR, "layout": "h"}
screen = render.preview(pages, 0, lambda s, n: None if n == render.WIDE else demo_house.live(s, n))

# The deck's body around the screen, and the edge of each clear key: the same
# proportions as images/deck.png, so the two pictures read as the same object.
SIDE, TOP, FOOT = 34, 34, 54
W, H = screen.width + 2 * SIDE, screen.height + TOP + FOOT
body = Image.new("RGB", (W * 2, H * 2), (247, 247, 245))          # the guide's page colour, behind the corners
d = ImageDraw.Draw(body)
d.rounded_rectangle((0, 0, W * 2 - 1, H * 2 - 1), radius=68, fill=(28, 28, 30))
d.rounded_rectangle((2 * SIDE - 12, 2 * TOP - 12, 2 * (W - SIDE) + 11, 2 * (TOP + screen.height) + 11), radius=30, fill=(0, 0, 0))
d.ellipse((W - 26, 2 * (H - 27) - 26, W + 26, 2 * (H - 27) + 26), fill=(52, 52, 56), outline=(20, 20, 22), width=3)
body = body.resize((W, H), Image.LANCZOS)
body.paste(screen, (SIDE, TOP))
d = ImageDraw.Draw(body)
# The edge of each clear key, at the places images/deck.png draws them: five
# across at a pitch of 256, three down at 240, the wide key over the last two.
for row in range(3):
    for col in range(5):
        if row == 2 and col >= 3:
            continue
        x, y = 40 + 256 * col, 40 + 240 * row
        d.rounded_rectangle((x, y, x + 245, y + 228), radius=18, outline=(36, 36, 38), width=2)
d.rounded_rectangle((40 + 256 * 3, 40 + 240 * 2, 40 + 256 * 4 + 245, 40 + 240 * 2 + 228), radius=18, outline=(36, 36, 38), width=2)

out = ROOT / "images" / "guide" / "fig-updating.png"
body.save(out)
print(out.relative_to(ROOT), body.size)
