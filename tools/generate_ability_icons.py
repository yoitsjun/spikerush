#!/usr/bin/env python3
"""Draw our own white ability badge icons (transparent, 256 px) into assets/icon:

  AbilityTyrant.png    a crown (Dohwan, The Tyrant)
  AbilitySunshine.png  a sun with a ring of rays (Haesol, Sunshine)
  AbilityEnflamed.png  a roaring dragon's head with a mane of flame (Kuro, Enflamed Dragon)
  AbilityFallingStar.png  a star coming down on three streaks (Byeol, Falling Star)
  KuroMeterTop.png, KuroMeterJaw.png  the dragon on Kuro's meter, in two jaws

Drawn at 4x and scaled down for smooth edges. Re-run:  python3 tools/generate_ability_icons.py
"""
import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "assets" / "icon"
S = 1024  # drawing size (4x)
WHITE = (255, 255, 255, 255)


def finish(img, name):
    img.resize((256, 256), Image.LANCZOS).save(OUT / name)
    print("wrote", OUT / name)


def curve(pts, n=10):
    """A smooth line through pts (Catmull-Rom), for flame edges."""
    ext = [pts[0]] + list(pts) + [pts[-1]]
    out = []
    for i in range(1, len(ext) - 2):
        a, b, c, d = ext[i - 1], ext[i], ext[i + 1], ext[i + 2]
        for k in range(n):
            t = k / n
            out.append(tuple(0.5 * (2 * b[j] + (c[j] - a[j]) * t + (2 * a[j] - 5 * b[j] + 4 * c[j] - d[j]) * t * t + (3 * b[j] - a[j] - 3 * c[j] + d[j]) * t ** 3) for j in (0, 1)))
    out.append(pts[-1])
    return out


def dragon():
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    clear = (0, 0, 0, 0)
    # the head, nose to the right, mouth wide open, hard angles
    head = [
        (950, 430), (925, 372), (862, 352), (800, 372), (706, 356), (640, 292), (556, 262),
        (452, 150), (340, 44), (372, 190), (420, 296),  # a horn, swept back
        (372, 330), (330, 560), (360, 690), (470, 800),
        (640, 842), (770, 880), (846, 846), (858, 780),  # the jaw to the chin
        (820, 790), (806, 722), (776, 770), (742, 700), (708, 742), (672, 672), (640, 700), (590, 590),  # lower teeth
        (660, 546), (684, 604), (724, 532), (756, 596), (796, 520), (836, 620), (872, 500), (950, 486),  # upper teeth
    ]
    d.polygon(head, fill=WHITE)
    # the mane: flames licking back off the neck
    tongues = [
        [(470, 300), (330, 250), (210, 300), (130, 230), (60, 150), (70, 290), (150, 390), (300, 420), (450, 420)],
        [(420, 400), (280, 420), (150, 470), (40, 440), (90, 560), (210, 590), (420, 560)],
        [(400, 520), (260, 590), (170, 660), (60, 660), (130, 770), (270, 760), (440, 680)],
        [(420, 650), (330, 760), (280, 850), (190, 900), (320, 960), (440, 880), (530, 790)],
    ]
    for t in tongues:
        d.polygon(curve(t), fill=WHITE)
    # the eye, a nostril, and the cut between the jaw and the neck
    d.polygon([(556, 352), (640, 372), (690, 420), (610, 420), (548, 392)], fill=clear)
    d.polygon([(846, 402), (892, 396), (900, 424), (856, 428)], fill=clear)
    d.line([(578, 590), (500, 560), (440, 500)], fill=clear, width=26, joint="curve")
    finish(img, "AbilityEnflamed.png")


def falling_star():
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    # the star, low on the left, tipped the way it's falling
    cx, cy, ro, ri, tilt = 372, 652, 318, 134, math.radians(-16)
    star = []
    for i in range(10):
        a = tilt - math.pi / 2 + i * math.pi / 5
        r = ro if i % 2 == 0 else ri
        star.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    d.polygon(star, fill=WHITE)
    # three streaks off to the top right, the middle one longest, sharp at the far end
    u = (math.cos(math.radians(-45)), math.sin(math.radians(-45)))
    v = (-u[1], u[0])
    for off, start, length, w in ((-176, 340, 330, 30), (0, 372, 470, 38), (176, 340, 330, 30)):
        bx, by = cx + u[0] * start + v[0] * off, cy + u[1] * start + v[1] * off
        tip = (bx + u[0] * length, by + u[1] * length)
        d.polygon([(bx + v[0] * w, by + v[1] * w), tip, (bx - v[0] * w, by - v[1] * w)], fill=WHITE)
        d.ellipse((bx - w, by - w, bx + w, by + w), fill=WHITE)
    finish(img, "AbilityFallingStar.png")


def jaw_sprite(polys, cuts, name):
    """A jaw of Kuro's meter, 512 px, hinge at the centre so turning the image opens it: white takes the
    tint, the navy edge and eye don't."""
    size = 1024
    mask = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(mask)
    for p in polys:
        d.polygon(p, fill=255)
    edge = mask.filter(ImageFilter.MaxFilter(23))
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    img.paste((18, 22, 40, 255), mask=edge)
    img.paste(WHITE, mask=mask)
    d = ImageDraw.Draw(img)
    for p in cuts:
        d.polygon(p, fill=(18, 22, 40, 255))
    img.resize((512, 512), Image.LANCZOS).save(OUT / name)
    print("wrote", OUT / name)


def meter_head():
    # the head and top jaw, nose to the right; the mouth's line runs through the hinge at (512, 512)
    top = [
        (470, 505), (540, 500), (566, 556), (596, 500), (640, 500), (668, 566), (700, 500), (746, 500), (772, 560), (804, 500),
        (850, 500), (880, 584), (912, 498), (968, 492), (990, 450), (960, 404), (896, 386), (812, 404), (716, 386), (652, 330), (572, 296),
        (480, 180), (352, 60), (392, 220), (430, 330), (396, 400), (404, 500),
    ]
    mane = [
        [(440, 330), (320, 280), (210, 320), (120, 262), (40, 180), (60, 320), (150, 410), (300, 440), (440, 440)],
        [(420, 420), (290, 440), (170, 490), (30, 470), (100, 570), (230, 590), (430, 520)],
    ]
    eye = [(590, 372), (660, 388), (708, 430), (636, 430), (582, 404)]
    nostril = [(884, 418), (926, 412), (934, 436), (892, 440)]
    jaw_sprite([top] + [curve(m) for m in mane], [eye, nostril], "KuroMeterTop.png")
    # the bottom jaw, its teeth between the top ones when it's shut
    low = [
        (470, 530), (520, 552), (610, 552), (636, 498), (664, 552), (716, 552), (742, 504), (770, 552), (822, 552), (850, 490), (884, 552), (934, 556),
        (950, 590), (916, 640), (820, 664), (690, 690), (560, 712), (470, 690), (420, 610),
    ]
    frill = [
        [(430, 560), (300, 620), (190, 640), (80, 620), (150, 730), (290, 730), (460, 660)],
        [(450, 640), (370, 740), (320, 830), (220, 880), (350, 930), (460, 850), (540, 720)],
    ]
    jaw_sprite([low] + [curve(m) for m in frill], [], "KuroMeterJaw.png")


def crown():
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    # the band
    d.rounded_rectangle((210, 640, 814, 770), radius=34, fill=WHITE)
    # five points rising from it, the middle one tallest
    base_y = 660
    tips = [(220, 330), (366, 420), (512, 250), (658, 420), (804, 330)]
    valleys = [(293, 560), (439, 560), (585, 560), (731, 560)]
    poly = [(214, base_y)]
    for i, tip in enumerate(tips):
        poly.append(tip)
        if i < len(valleys):
            poly.append(valleys[i])
    poly.append((810, base_y))
    d.polygon(poly, fill=WHITE)
    # a ball on each tip
    for x, y in tips:
        r = 44 if x != 512 else 54
        d.ellipse((x - r, y - r, x + r, y + r), fill=WHITE)
    # three gems cut out of the band
    for x in (330, 512, 694):
        d.ellipse((x - 30, 675, x + 30, 735), fill=(0, 0, 0, 0))
    finish(img, "AbilityTyrant.png")


def sun():
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    c = S / 2
    # sixteen rays, long and short in turn
    for i in range(16):
        a = i * math.pi / 8
        long = i % 2 == 0
        r0, r1 = 300, 470 if long else 400
        w = 0.11 if long else 0.08
        pts = [
            (c + r0 * math.cos(a - w), c + r0 * math.sin(a - w)),
            (c + r1 * math.cos(a), c + r1 * math.sin(a)),
            (c + r0 * math.cos(a + w), c + r0 * math.sin(a + w)),
        ]
        d.polygon(pts, fill=WHITE)
    # the ring, then the disc inside it
    d.ellipse((c - 285, c - 285, c + 285, c + 285), fill=WHITE)
    d.ellipse((c - 235, c - 235, c + 235, c + 235), fill=(0, 0, 0, 0))
    d.ellipse((c - 195, c - 195, c + 195, c + 195), fill=WHITE)
    finish(img, "AbilitySunshine.png")


if __name__ == "__main__":
    crown()
    sun()
    dragon()
    falling_star()
    meter_head()
