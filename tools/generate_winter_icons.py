#!/usr/bin/env python3
"""Draw the Winter collab's own icons (white on clear, 256 px, tinted in code) into assets/ui:

  AbilityJoker.png    a playing card with a jester's hat cut out of it, a second card behind
                      (Jaja's ability, Joker)
  IconSnowflake.png   a six-armed snowflake (the event's currency, Snowflakes)

and the Icicle trail's particle into assets/fx/winter:

  Icicle.png          an icicle, its point up (the way it flies), a lighter facet down one side

Drawn at 4x and scaled down for smooth edges. Re-run:  python3 tools/generate_winter_icons.py
"""
import math
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "assets" / "ui"
S = 1024  # drawing size (4x)
W = (255, 255, 255, 255)
CLEAR = (0, 0, 0, 0)
C = S / 2


def finish(img, name):
    OUT.mkdir(parents=True, exist_ok=True)
    img.resize((256, 256), Image.LANCZOS).save(OUT / (name + ".png"))
    print("wrote", OUT / (name + ".png"))


def placed(img, angle, dx, dy):
    """A layer drawn about the centre, turned and moved."""
    return ImageChops.offset(img.rotate(angle, resample=Image.BICUBIC, center=(C, C)), dx, dy)


def card(w, h, outline=None):
    img = Image.new("RGBA", (S, S), CLEAR)
    d = ImageDraw.Draw(img)
    box = (C - w / 2, C - h / 2, C + w / 2, C + h / 2)
    if outline:
        d.rounded_rectangle(box, radius=58, outline=W, width=outline)
    else:
        d.rounded_rectangle(box, radius=58, fill=W)
    return img, d


def curve(pts, n=10):
    """A smooth line through pts (Catmull-Rom)."""
    ext = [pts[0]] + list(pts) + [pts[-1]]
    out = []
    for i in range(1, len(ext) - 2):
        a, b, c, e = ext[i - 1], ext[i], ext[i + 1], ext[i + 2]
        for k in range(n):
            t = k / n
            out.append(tuple(0.5 * (2 * b[j] + (c[j] - a[j]) * t + (2 * a[j] - 5 * b[j] + 4 * c[j] - e[j]) * t * t + (3 * b[j] - a[j] - 3 * c[j] + e[j]) * t ** 3) for j in (0, 1)))
    out.append(pts[-1])
    return out


def joker():
    # the card in front: a jester's hat cut out of it, a pip in two corners
    front, d = card(480, 680)
    # a jester's cap: the middle point stands, the two outer ones flop over to the sides, a bell
    # on each tip, a band under them
    d.polygon([(458, 604), (512, 396), (566, 604)], fill=CLEAR)
    flop = curve([(476, 604), (446, 508), (398, 446), (350, 452), (322, 510), (326, 556)]) + curve([(356, 540), (366, 506), (392, 510), (410, 560), (412, 604)])
    d.polygon(flop, fill=CLEAR)
    d.polygon([(S - x, y) for x, y in flop], fill=CLEAR)
    for x, y in ((512, 378), (338, 566), (S - 338, 566)):
        d.ellipse((x - 30, y - 30, x + 30, y + 30), fill=CLEAR)
    d.rounded_rectangle((398, 620, 626, 672), radius=22, fill=CLEAR)
    for x, y in ((338, 262), (686, 762)):  # the pips
        d.polygon([(x, y - 44), (x + 32, y), (x, y + 44), (x - 32, y)], fill=CLEAR)
    solid, _ = card(480, 680)
    # the card behind it, an outline, fanned the other way
    back, _ = card(440, 640, outline=36)
    out = placed(back, -17, 118, -26)
    # a gap between the two: the back card stops short of the front one's edge
    gap = placed(solid, 9, -52, 26).getchannel("A").filter(ImageFilter.MaxFilter(45))
    out.putalpha(ImageChops.subtract(out.getchannel("A"), gap))
    out.alpha_composite(placed(front, 9, -52, 26))
    finish(out, "AbilityJoker")


def snowflake():
    img = Image.new("RGBA", (S, S), CLEAR)
    d = ImageDraw.Draw(img)

    def stroke(a, b, w):
        d.line([a, b], fill=W, width=w)
        for x, y in (a, b):
            d.ellipse((x - w / 2, y - w / 2, x + w / 2, y + w / 2), fill=W)

    for i in range(6):
        a = math.radians(i * 60 - 90)
        ux, uy = math.cos(a), math.sin(a)
        stroke((C, C), (C + ux * 440, C + uy * 440), 56)
        # two pairs of branches up each arm, the outer pair shorter
        for at, length, w in ((0.46, 150, 46), (0.76, 96, 40)):
            bx, by = C + ux * 440 * at, C + uy * 440 * at
            for side in (-1, 1):
                b = a + side * math.radians(52)
                stroke((bx, by), (bx + math.cos(b) * length, by + math.sin(b) * length), w)
    # a small hollow in the middle
    d.ellipse((C - 30, C - 30, C + 30, C + 30), fill=CLEAR)
    finish(img, "IconSnowflake")


def icicle():
    img = Image.new("RGBA", (S, S), CLEAR)
    d = ImageDraw.Draw(img)
    # a long tapered spike, point up, a little crooked like a real one
    body = [(C, 40), (C + 70, 420), (C + 96, 760), (C + 60, 960), (C - 50, 972), (C - 92, 740), (C - 58, 400)]
    d.polygon(body, fill=W)
    # the shaded side: a greyer facet (the particle's tint keeps it icy)
    d.polygon([(C, 40), (C - 58, 400), (C - 92, 740), (C - 50, 972), (C - 14, 930), (C - 30, 700), (C - 8, 380)], fill=(200, 214, 232, 255))
    # a bright line down the middle of the lit side
    d.line([(C + 22, 220), (C + 40, 520), (C + 44, 820)], fill=(255, 255, 255, 255), width=14)
    out = img.filter(ImageFilter.GaussianBlur(3))
    dest = ROOT / "assets" / "fx" / "winter"
    dest.mkdir(parents=True, exist_ok=True)
    out.resize((256, 256), Image.LANCZOS).save(dest / "Icicle.png")
    print("wrote", dest / "Icicle.png")


if __name__ == "__main__":
    joker()
    snowflake()
    icicle()
