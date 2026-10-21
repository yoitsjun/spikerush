#!/usr/bin/env python3
"""Draw our own white ability badge icons (transparent, 256 px) into assets/icon:

  AbilityTyrant.png    a crown (Dohwan, The Tyrant)
  AbilitySunshine.png  a sun with a ring of rays (Haesol, Sunshine)

Drawn at 4x and scaled down for smooth edges. Re-run:  python3 tools/generate_ability_icons.py
"""
import math
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "assets" / "icon"
S = 1024  # drawing size (4x)
WHITE = (255, 255, 255, 255)


def finish(img, name):
    img.resize((256, 256), Image.LANCZOS).save(OUT / name)
    print("wrote", OUT / name)


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
