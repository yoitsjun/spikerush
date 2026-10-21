# Ranked badges (Config.Ranked.Ranks), after the owner's references (2026-10-21): a bevelled gem
# hexagon in the rank's metal with an emblem in it, and more around it the higher it goes: Bronze
# plain, Silver ribbons, Gold a star and small wings, Platinum a gem, spikes and wings, Diamond a
# diamond, stars and big wings, Mighty a trophy orb with purple wings and a crown, Almighty a
# burning red-gold crest with huge wings, a crown and a halo. Transparent 512x512, drawn at 2x.
# Out: assets/ranks/Rank<Key>.png and a sheet assets/ranks/_all.png.
import math, os
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "assets", "ranks")
S = 1024
C = S / 2
INK = (18, 12, 26, 255)


def grad(c0, c1, angle=90, power=1.0):
    # a linear gradient over the canvas from c0 to c1 (RGBA)
    y, x = np.mgrid[0:S, 0:S].astype(np.float32)
    a = math.radians(angle)
    t = ((x - C) * math.cos(a) + (y - C) * math.sin(a)) / (S * 0.6) + 0.5
    t = np.clip(t, 0, 1) ** power
    c0, c1 = np.array(c0, np.float32), np.array(c1, np.float32)
    arr = c0[None, None, :] * (1 - t[..., None]) + c1[None, None, :] * t[..., None]
    return Image.fromarray(arr.astype(np.uint8), "RGBA")


def boxgrad(c0, c1, box):
    # a vertical gradient from c0 at the box's top to c1 at its bottom (the rest of the canvas clamps)
    y = np.arange(S, dtype=np.float32)[:, None] * np.ones((1, S), np.float32)
    t = np.clip((y - box[1]) / max(1, box[3] - box[1]), 0, 1)
    c0, c1 = np.array(c0, np.float32), np.array(c1, np.float32)
    arr = c0[None, None, :] * (1 - t[..., None]) + c1[None, None, :] * t[..., None]
    return Image.fromarray(arr.astype(np.uint8), "RGBA")


def emblem(img, points, top, bottom, outline=10):
    xs, ys = [p[0] for p in points], [p[1] for p in points]
    paint(img, mask_poly(points), boxgrad(top, bottom, (min(xs), min(ys), max(xs), max(ys))), outline=outline)


def mask_poly(points, blur=0):
    m = Image.new("L", (S, S), 0)
    ImageDraw.Draw(m).polygon(points, fill=255)
    return m.filter(ImageFilter.GaussianBlur(blur)) if blur else m


def mask_ellipse(box):
    m = Image.new("L", (S, S), 0)
    ImageDraw.Draw(m).ellipse(box, fill=255)
    return m


def paint(img, mask, fill, outline=14, ink=INK):
    # fill (an image or a colour) through mask, with a dark outline round it
    if isinstance(fill, tuple):
        fill = Image.new("RGBA", (S, S), fill)
    if outline:
        edge = mask.filter(ImageFilter.MaxFilter(outline * 2 + 1))
        img.alpha_composite(Image.composite(Image.new("RGBA", (S, S), ink), Image.new("RGBA", (S, S), (0, 0, 0, 0)), edge))
    img.alpha_composite(Image.composite(fill, Image.new("RGBA", (S, S), (0, 0, 0, 0)), mask))


def hexagon(cx, cy, r, rot=0):
    return [(cx + r * math.cos(math.radians(60 * i + 30 + rot)), cy + r * math.sin(math.radians(60 * i + 30 + rot))) for i in range(6)]


def lighten(c, t):
    return tuple(int(c[i] + (255 - c[i]) * t) for i in range(3)) + (255,)


def darken(c, t):
    return tuple(int(c[i] * (1 - t)) for i in range(3)) + (255,)


def gem_hex(img, color, r=300, cy=C + 20):
    # the bevelled hexagon: a dark rim, a lit metal frame, a deep inner face, a gloss
    paint(img, mask_poly(hexagon(C, cy, r)), grad(lighten(color, 0.55), darken(color, 0.45), 70), outline=16)
    paint(img, mask_poly(hexagon(C, cy, r * 0.8)), grad(darken(color, 0.55), lighten(color, 0.15), 80), outline=0)
    paint(img, mask_poly(hexagon(C, cy, r * 0.66)), grad(lighten(color, 0.25), darken(color, 0.35), 100), outline=6, ink=darken(color, 0.7))
    # gloss across the top half
    gloss = Image.new("RGBA", (S, S), (255, 255, 255, 0))
    gm = Image.composite(Image.new("L", (S, S), 90), Image.new("L", (S, S), 0), mask_poly(hexagon(C, cy, r * 0.66)))
    cut = Image.new("L", (S, S), 0)
    ImageDraw.Draw(cut).polygon([(0, 0), (S, 0), (S, cy - r * 0.15), (0, cy + r * 0.1)], fill=255)
    gm = Image.fromarray(np.minimum(np.array(gm), np.array(cut)))
    gloss.putalpha(gm)
    img.alpha_composite(gloss)


def bez(p0, p1, p2, n=16):
    return [((1 - t) ** 2 * p0[0] + 2 * (1 - t) * t * p1[0] + t * t * p2[0], (1 - t) ** 2 * p0[1] + 2 * (1 - t) * t * p1[1] + t * t * p2[1]) for t in [i / n for i in range(n + 1)]]


def wings(img, color, span=1.0, cy=C + 20, feathers=5):
    # curved, layered feathers fanning out of both sides behind the gem (longest at the top), each
    # a leaf shape with a lit edge
    for side in (-1, 1):
        for i in reversed(range(feathers)):
            ang = math.radians(-34 + i * (78 / max(1, feathers - 1)))
            length = (230 + 30 * (feathers - i)) * span
            base = (C + side * 175, cy - 90 + i * 40)
            tip = (base[0] + side * length * math.cos(ang), base[1] + length * math.sin(ang) - 40 * span)
            mid = ((base[0] + tip[0]) / 2, (base[1] + tip[1]) / 2)
            dx, dy = tip[0] - base[0], tip[1] - base[1]
            dl = math.hypot(dx, dy) or 1
            nx, ny = -dy / dl, dx / dl
            w = 135 * span
            upper = bez(base, (mid[0] + nx * w * side, mid[1] + ny * w * side - 20), tip)
            lower = bez(tip, (mid[0] - nx * w * 0.35 * side, mid[1] - ny * w * 0.35 * side + 10), base)
            c = lighten(color, 0.05 + 0.07 * i)
            paint(img, mask_poly(upper + lower), grad(lighten(c, 0.45), darken(c, 0.3), 90), outline=9)
            # the quill
            q = Image.new("L", (S, S), 0)
            ImageDraw.Draw(q).line([base, ((base[0] + 2 * tip[0]) / 3, (base[1] + 2 * tip[1]) / 3)], fill=150, width=5)
            img.alpha_composite(Image.composite(Image.new("RGBA", (S, S), lighten(c, 0.7)), Image.new("RGBA", (S, S), (0, 0, 0, 0)), q))


def star(cx, cy, r, points=5, inner=0.45, rot=-90):
    pts = []
    for i in range(points * 2):
        rr = r if i % 2 == 0 else r * inner
        a = math.radians(rot + i * 180 / points)
        pts.append((cx + rr * math.cos(a), cy + rr * math.sin(a)))
    return pts


def diamond(cx, cy, w, h):
    return [(cx, cy - h * 0.55), (cx + w / 2, cy - h * 0.1), (cx, cy + h * 0.45), (cx - w / 2, cy - h * 0.1)]


def crown(img, cy, w, color):
    x0 = C - w / 2
    pts = [(x0, cy + 90), (x0, cy), (x0 + w * 0.2, cy + 50), (x0 + w * 0.35, cy - 30), (C, cy + 30), (x0 + w * 0.65, cy - 30), (x0 + w * 0.8, cy + 50), (x0 + w, cy), (x0 + w, cy + 90)]
    paint(img, mask_poly(pts), grad(lighten(color, 0.5), darken(color, 0.3), 90), outline=12)
    for px in (x0 + w * 0.35, C, x0 + w * 0.65):
        paint(img, mask_ellipse((px - 22, cy - 22 + (0 if px != C else 50), px + 22, cy + 22 + (0 if px != C else 50))), (255, 255, 255, 255), outline=6)


def ribbons(img, color):
    for side in (-1, 1):
        pts = [(C + side * 110, C + 260), (C + side * 200, C + 420), (C + side * 150, C + 400), (C + side * 120, C + 460), (C + side * 40, C + 300)]
        paint(img, mask_poly(pts), grad(lighten(color, 0.2), darken(color, 0.3), 90), outline=10)


def glow(img, color, r=380, alpha=120):
    g = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(g).ellipse((C - r, C - r, C + r, C + r), fill=color[:3] + (alpha,))
    img.alpha_composite(g.filter(ImageFilter.GaussianBlur(70)))


def badge(key):
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    if key == "Bronze":
        col = (205, 120, 70)
        glow(img, col, alpha=70)
        gem_hex(img, col)
        for dy in (-70, 70):
            emblem(img, hexagon(C, C + 20 + dy, 60, 30), lighten(col, 0.75), darken(col, 0.15), outline=8)
    elif key == "Silver":
        col = (200, 212, 228)
        glow(img, col, alpha=80)
        ribbons(img, (220, 50, 50))
        gem_hex(img, col)
        emblem(img, [(C, C - 70), (C + 80, C + 80), (C - 80, C + 80)], (255, 255, 255, 255), (150, 165, 190, 255))
    elif key == "Gold":
        col = (255, 196, 50)
        glow(img, col, alpha=100)
        wings(img, (255, 170, 40), span=0.66, feathers=3)
        gem_hex(img, col)
        emblem(img, star(C, C + 20, 120), (255, 252, 220, 255), (255, 160, 10, 255))
    elif key == "Platinum":
        col = (70, 220, 195)
        glow(img, col, alpha=110)
        wings(img, (80, 230, 200), span=0.8, feathers=4)
        for side in (-1, 0, 1):
            paint(img, mask_poly([(C + side * 120 - 40, C - 200), (C + side * 150, C - 380 + abs(side) * 60), (C + side * 120 + 40, C - 200)]), grad((220, 255, 250, 255), (40, 170, 150, 255), 90), outline=10)
        gem_hex(img, col)
        emblem(img, diamond(C, C + 20, 170, 220), (235, 255, 252, 255), (30, 170, 150, 255))
    elif key == "Diamond":
        col = (80, 170, 255)
        glow(img, col, alpha=130)
        wings(img, (110, 190, 255), span=0.9, feathers=5)
        ribbons(img, (200, 40, 60))
        gem_hex(img, col)
        emblem(img, diamond(C, C + 20, 200, 250), (245, 252, 255, 255), (40, 110, 240, 255))
        for i, dx in enumerate((-150, 0, 150)):
            paint(img, mask_poly(star(C + dx, C - 320 + (40 if dx != 0 else 0), 50 if dx else 64, 4, 0.35)), (240, 250, 255, 255), outline=8)
    elif key == "Mighty":
        col = (175, 85, 255)
        glow(img, col, r=440, alpha=150)
        wings(img, (190, 110, 255), span=0.98, feathers=6)
        gem_hex(img, col, r=290)
        paint(img, mask_ellipse((C - 130, C - 110, C + 130, C + 150)), grad((255, 240, 255, 255), (150, 60, 230, 255), 90), outline=10)
        emblem(img, star(C, C + 20, 90), (255, 255, 240, 255), (255, 180, 50, 255), outline=8)
        crown(img, C - 380, 300, (255, 200, 60))
    elif key == "Almighty":
        col = (240, 60, 60)
        glow(img, (255, 120, 40), r=480, alpha=170)
        # a halo ring behind everything
        ring = Image.new("L", (S, S), 0)
        d = ImageDraw.Draw(ring)
        d.ellipse((C - 400, C - 380, C + 400, C + 420), outline=255, width=24)
        paint(img, ring, grad((255, 240, 160, 255), (255, 140, 40, 255), 90), outline=6)
        wings(img, (255, 190, 60), span=1.05, feathers=7)
        gem_hex(img, col, r=290)
        emblem(img, diamond(C, C + 20, 190, 250), (255, 255, 235, 255), (230, 40, 30, 255))
        crown(img, C - 390, 340, (255, 210, 60))
    return img.resize((512, 512), Image.LANCZOS)


KEYS = ["Bronze", "Silver", "Gold", "Platinum", "Diamond", "Mighty", "Almighty"]

if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    sheet = Image.new("RGBA", (len(KEYS) * 260 + 10, 270), (20, 22, 30, 255))
    for i, key in enumerate(KEYS):
        im = badge(key)
        im.save(os.path.join(OUT, "Rank" + key + ".png"))
        sheet.alpha_composite(im.resize((250, 250), Image.LANCZOS), (10 + i * 260, 10))
    sheet.save(os.path.join(OUT, "_all.png"))
    print("ok")
