"""Draws the Halloween event's effect sprites into assets/fx/halloween (white on clear and tinted in
code, unless noted). Run with any Python 3 that has Pillow; upload the PNGs and paste their ids
into Assets.Fx.

  SoulWisp.png    a screaming soul with a long wispy tail (the Reaper's Souls trail)
  Skull.png       a skull with hollow eyes (the Souls trail, the Reaper's landing)
  GhostSheet.png  a classic sheet ghost with black eyes (Ghost Swarm; the eyes stay black)
  Bat.png         a bat, wings spread
  BatFlap.png     a 2x2 flipbook of a bat's wingbeat (the Bat Swarm jump and trail)
  InkSplat.png    a splash of ink with flung drops (where a Souls spike lands)
  CandyCorn.png   a candy corn in its own colours, not tinted (Pumpkin Burst, the Candy Corn trail)
"""

import math
import os
import random

from PIL import Image, ImageDraw, ImageFilter

OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "fx", "halloween")
SS = 4  # drawn this many times bigger, then scaled down (smooth edges)
N = 512


def canvas():
    img = Image.new("RGBA", (N * SS, N * SS), (0, 0, 0, 0))
    return img, ImageDraw.Draw(img)


def finish(img, glow=0.0, blur=6):
    """Scale down; `glow` adds a soft halo of the shape's own alpha around it."""
    img = img.resize((N, N), Image.LANCZOS)
    if glow > 0:
        a = img.getchannel("A")
        halo = a.filter(ImageFilter.GaussianBlur(blur * 2))
        halo = halo.point(lambda v: int(v * glow))
        base = Image.new("RGBA", (N, N), (255, 255, 255, 0))
        base.putalpha(halo)
        base.alpha_composite(img)
        img = base
    return img


def S(v):
    return int(v * SS)


def soul_wisp():
    img, d = canvas()
    # the tail: a wavy column of circles thinning as it falls
    for i in range(140):
        f = i / 139
        x = 256 + math.sin(f * 3.4 + 0.6) * 70 * f
        y = 250 + f * 240
        r = 92 * (1 - f) ** 1.1 + 4
        a = int(255 * (1 - f) ** 0.6)
        d.ellipse([S(x - r), S(y - r), S(x + r), S(y + r)], fill=(255, 255, 255, a))
    # the head
    d.ellipse([S(150), S(70), S(362), S(320)], fill=(255, 255, 255, 255))
    # hollow eyes, slanted in fright, and a screaming mouth: cut clear
    d.ellipse([S(185), S(150), S(235), S(230)], fill=(0, 0, 0, 0))
    d.ellipse([S(277), S(150), S(327), S(230)], fill=(0, 0, 0, 0))
    d.ellipse([S(222), S(245), S(290), S(330)], fill=(0, 0, 0, 0))
    return finish(img, glow=0.55, blur=10)


def skull():
    img, d = canvas()
    d.ellipse([S(120), S(70), S(392), S(330)], fill=(255, 255, 255, 255))  # the cranium
    d.rounded_rectangle([S(170), S(280), S(342), S(420)], radius=S(36), fill=(255, 255, 255, 255))  # the jaw
    # cheekbones
    d.ellipse([S(140), S(230), S(220), S(320)], fill=(255, 255, 255, 255))
    d.ellipse([S(292), S(230), S(372), S(320)], fill=(255, 255, 255, 255))
    # hollow eye sockets and nose
    d.ellipse([S(165), S(165), S(245), S(260)], fill=(0, 0, 0, 0))
    d.ellipse([S(267), S(165), S(347), S(260)], fill=(0, 0, 0, 0))
    d.polygon([(S(256), S(268)), (S(234), S(312)), (S(278), S(312))], fill=(0, 0, 0, 0))
    # teeth: gaps down the jaw
    for i in range(5):
        x = 196 + i * 30
        d.rectangle([S(x), S(345), S(x + 6), S(405)], fill=(0, 0, 0, 0))
    d.rectangle([S(180), S(372), S(332), S(378)], fill=(0, 0, 0, 0))
    return finish(img, glow=0.45, blur=8)


def ghost_sheet():
    img, d = canvas()
    # the dome and the body widening to a wavy hem
    d.ellipse([S(126), S(40), S(386), S(300)], fill=(255, 255, 255, 255))
    d.polygon([(S(126), S(170)), (S(386), S(170)), (S(420), S(430)), (S(92), S(430))], fill=(255, 255, 255, 255))
    for i in range(4):  # the scalloped hem
        x0 = 92 + i * 82
        d.ellipse([S(x0), S(390), S(x0 + 82), S(470)], fill=(255, 255, 255, 255))
    for i in range(3):  # the gaps between the scallops
        x0 = 92 + 82 * (i + 1) - 26
        d.ellipse([S(x0), S(440), S(x0 + 52), S(500)], fill=(0, 0, 0, 0))
    # black eyes and a small round mouth (they stay black when the white is tinted)
    d.ellipse([S(186), S(150), S(232), S(216)], fill=(10, 10, 14, 255))
    d.ellipse([S(280), S(150), S(326), S(216)], fill=(10, 10, 14, 255))
    d.ellipse([S(236), S(236), S(276), S(282)], fill=(10, 10, 14, 255))
    return finish(img, glow=0.35, blur=8)


def bat():
    img, d = canvas()
    cx, cy = 256, 270
    d.ellipse([S(cx - 34), S(cy - 70), S(cx + 34), S(cy + 70)], fill=(255, 255, 255, 255))  # body
    d.ellipse([S(cx - 30), S(cy - 110), S(cx + 30), S(cy - 50)], fill=(255, 255, 255, 255))  # head
    d.polygon([(S(cx - 28), S(cy - 96)), (S(cx - 18), S(cy - 140)), (S(cx - 6), S(cy - 100))], fill=(255, 255, 255, 255))
    d.polygon([(S(cx + 28), S(cy - 96)), (S(cx + 18), S(cy - 140)), (S(cx + 6), S(cy - 100))], fill=(255, 255, 255, 255))
    for side in (-1, 1):
        # a wing: a fan from the shoulder, its trailing edge bitten into scallops
        pts = [(cx + side * 20, cy - 40), (cx + side * 120, cy - 120), (cx + side * 236, cy - 40),
               (cx + side * 200, cy + 30), (cx + side * 150, cy + 10), (cx + side * 110, cy + 60),
               (cx + side * 70, cy + 30), (cx + side * 30, cy + 40)]
        d.polygon([(S(x), S(y)) for x, y in pts], fill=(255, 255, 255, 255))
        for (bx, by, r) in ((175, 46, 30), (130, 58, 26), (90, 56, 22)):
            d.ellipse([S(cx + side * bx - r), S(cy + by - r), S(cx + side * bx + r), S(cy + by + r)], fill=(0, 0, 0, 0))
    return finish(img)


def bat_frame(lift):
    """One wingbeat pose: `lift` 1 is wings high, 0 level, -1 low (the wings turn about the
    shoulders and look shorter away from level)."""
    img, d = canvas()
    cx, cy = 256, 290
    d.ellipse([S(cx - 30), S(cy - 62), S(cx + 30), S(cy + 62)], fill=(255, 255, 255, 255))  # body
    d.ellipse([S(cx - 27), S(cy - 100), S(cx + 27), S(cy - 46)], fill=(255, 255, 255, 255))  # head
    d.polygon([(S(cx - 25), S(cy - 88)), (S(cx - 16), S(cy - 128)), (S(cx - 5), S(cy - 92))], fill=(255, 255, 255, 255))
    d.polygon([(S(cx + 25), S(cy - 88)), (S(cx + 16), S(cy - 128)), (S(cx + 5), S(cy - 92))], fill=(255, 255, 255, 255))
    span = 1 - 0.25 * abs(lift)
    for side in (-1, 1):
        # one wing, x out from the middle and y down from the body's centre: the leading edge from
        # the shoulder over the elbow to the tip, the trailing edge from the tip back to the flank
        shoulder, flank = (20, -40), (30, 36)
        elbow = (20 + 100 * span, -120 - 70 * lift)
        tip = (20 + 210 * span, -40 - 150 * lift)
        fingers = [(tip[0] + (flank[0] - tip[0]) * f, tip[1] + (flank[1] - tip[1]) * f) for f in (0.34, 0.64)]
        wing = [shoulder, elbow, tip, fingers[0], fingers[1], flank]
        d.polygon([(S(cx + side * x), S(cy + y)) for x, y in wing], fill=(255, 255, 255, 255))
        # the trailing edge bitten into scallops between the fingers (bites pushed out from the
        # wing's middle, so they only take the edge)
        mx = (shoulder[0] + elbow[0] + tip[0]) / 3
        my = (shoulder[1] + elbow[1] + tip[1]) / 3
        edge = [tip, fingers[0], fingers[1], flank]
        for a, b in zip(edge, edge[1:]):
            px, py = (a[0] + b[0]) / 2, (a[1] + b[1]) / 2
            r = math.dist(a, b) * 0.36
            nx, ny = px - mx, py - my
            n = math.hypot(nx, ny) or 1
            px, py = px + nx / n * r * 0.55, py + ny / n * r * 0.55
            d.ellipse([S(cx + side * px - r), S(cy + py - r), S(cx + side * px + r), S(cy + py + r)], fill=(0, 0, 0, 0))
    return finish(img)


def bat_flap():
    """A 2x2 flipbook of one wingbeat (up, level, down, level), played on a loop."""
    sheet = Image.new("RGBA", (N * 2, N * 2), (0, 0, 0, 0))
    for i, lift in enumerate((1, 0.15, -1, 0.15)):
        sheet.paste(bat_frame(lift), ((i % 2) * N, (i // 2) * N))
    return sheet


def ink_splat():
    random.seed(11)
    img, d = canvas()
    # a lumpy blob: overlapping circles round the middle
    for _ in range(26):
        a = random.random() * math.tau
        r = random.uniform(30, 120)
        x, y = 256 + math.cos(a) * r * 0.8, 256 + math.sin(a) * r * 0.8
        s = random.uniform(50, 110)
        d.ellipse([S(x - s), S(y - s), S(x + s), S(y + s)], fill=(255, 255, 255, 255))
    # flung streaks: tapered spikes out of the blob, a drop at the end of some
    for i in range(18):
        a = (i + random.uniform(-0.3, 0.3)) / 18 * math.tau
        r0, r1 = random.uniform(90, 120), random.uniform(170, 238)
        w = random.uniform(10, 22)
        ca, sa = math.cos(a), math.sin(a)
        px, py = -sa, ca
        pts = [(256 + ca * r0 + px * w, 256 + sa * r0 + py * w), (256 + ca * r1, 256 + sa * r1),
               (256 + ca * r0 - px * w, 256 + sa * r0 - py * w)]
        d.polygon([(S(x), S(y)) for x, y in pts], fill=(255, 255, 255, 255))
        if random.random() < 0.5:
            s = w * 0.7
            x, y = 256 + ca * (r1 + s + 6), 256 + sa * (r1 + s + 6)
            d.ellipse([S(x - s), S(y - s), S(x + s), S(y + s)], fill=(255, 255, 255, 255))
    # loose round drops
    for _ in range(22):
        a = random.random() * math.tau
        r = random.uniform(140, 235)
        s = random.uniform(4, 13)
        x, y = 256 + math.cos(a) * r, 256 + math.sin(a) * r
        d.ellipse([S(x - s), S(y - s), S(x + s), S(y + s)], fill=(255, 255, 255, 255))
    return finish(img)


def candy_corn():
    img, d = canvas()
    tri = [(256, 60), (420, 440), (92, 440)]
    d.polygon([(S(x), S(y)) for x, y in tri], fill=(255, 196, 40, 255))
    # the bands: orange in the middle, white at the tip (clipped to the triangle by redrawing)
    def band(y0, y1, color):
        def xs(y):
            f = (y - 60) / 380
            return 256 - 164 * f, 256 + 164 * f
        a0, b0 = xs(y0)
        a1, b1 = xs(y1)
        d.polygon([(S(a0), S(y0)), (S(b0), S(y0)), (S(b1), S(y1)), (S(a1), S(y1))], fill=color)
    band(60, 330, (255, 116, 18, 255))
    band(60, 190, (255, 250, 240, 255))
    img = img.filter(ImageFilter.GaussianBlur(SS * 3))  # rounds the corners
    a = img.getchannel("A").point(lambda v: 255 if v > 110 else 0)
    img.putalpha(a)
    return finish(img)


def main():
    os.makedirs(OUT, exist_ok=True)
    for name, fn in (("SoulWisp", soul_wisp), ("Skull", skull), ("GhostSheet", ghost_sheet), ("Bat", bat),
                     ("BatFlap", bat_flap), ("InkSplat", ink_splat), ("CandyCorn", candy_corn)):
        img = fn()
        img.save(os.path.join(OUT, name + ".png"))
        print("wrote", name)


if __name__ == "__main__":
    main()
