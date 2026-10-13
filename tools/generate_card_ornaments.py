# Almighty card ornaments (Config.Cards, Look.Divine; Gui.playerCard): gold feathered wings (left, right) and a crest with a red gem.
# Drawn at 4x and scaled down for smooth edges. Out: almighty_wing_l.png, almighty_wing_r.png,
# almighty_crest.png in this folder.
import math, os
from PIL import Image, ImageDraw, ImageFilter, ImageChops

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "card")
SS = 4

GOLD_DARK = (128, 72, 8)
GOLD_MID = (232, 170, 40)
GOLD_LIGHT = (255, 232, 140)
GOLD_WHITE = (255, 250, 220)
OUTLINE = (58, 28, 4, 255)


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(len(a)))


def gold_at(t):
    # 0 dark .. 1 bright
    if t < 0.5:
        return lerp(GOLD_DARK, GOLD_MID, t / 0.5)
    if t < 0.85:
        return lerp(GOLD_MID, GOLD_LIGHT, (t - 0.5) / 0.35)
    return lerp(GOLD_LIGHT, GOLD_WHITE, (t - 0.85) / 0.15)


def gradient(size, angle_deg, stops=None):
    w, h = size
    img = Image.new("RGBA", size)
    px = img.load()
    a = math.radians(angle_deg)
    dx, dy = math.cos(a), math.sin(a)
    proj = [x * dx + y * dy for x, y in ((0, 0), (w, 0), (0, h), (w, h))]
    lo, hi = min(proj), max(proj)
    for y in range(h):
        for x in range(w):
            t = ((x * dx + y * dy) - lo) / (hi - lo)
            px[x, y] = gold_at(t) + (255,)
    return img


def bez(p0, p1, p2, t):
    return (
        (1 - t) ** 2 * p0[0] + 2 * (1 - t) * t * p1[0] + t * t * p2[0],
        (1 - t) ** 2 * p0[1] + 2 * (1 - t) * t * p1[1] + t * t * p2[1],
    )


def feather_poly(root, tip, bow, width, n=40):
    # a tapered, slightly leaf-shaped feather along a quadratic curve root -> tip
    mid = ((root[0] + tip[0]) / 2, (root[1] + tip[1]) / 2)
    dx, dy = tip[0] - root[0], tip[1] - root[1]
    L = math.hypot(dx, dy)
    nx, ny = -dy / L, dx / L
    ctrl = (mid[0] + nx * bow, mid[1] + ny * bow)
    top, bot = [], []
    for i in range(n + 1):
        t = i / n
        p = bez(root, ctrl, tip, t)
        q = bez(root, ctrl, tip, min(1, t + 0.01))
        tx, ty = q[0] - p[0], q[1] - p[1]
        tl = math.hypot(tx, ty) or 1
        ox, oy = -ty / tl, tx / tl
        w = width * (math.sin(math.pi * min(1, t * 1.05)) ** 0.6 * (1 - 0.55 * t) + 0.15 * (1 - t))
        top.append((p[0] + ox * w, p[1] + oy * w))
        bot.append((p[0] - ox * w, p[1] - oy * w))
    spine = [bez(root, ctrl, tip, i / n) for i in range(n + 1)]
    return top + bot[::-1], spine


def draw_wing(W=512, H=320):
    w, h = W * SS, H * SS
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    root = (0.92 * w, 0.72 * h)
    # (tip x, tip y, bow, width) from the bottom feather up, so the top ones overlap
    feathers = [
        (0.46, 0.97, -0.02, 0.085),
        (0.30, 0.86, -0.05, 0.095),
        (0.17, 0.64, -0.08, 0.105),
        (0.09, 0.38, -0.11, 0.112),
        (0.08, 0.10, -0.13, 0.118),
        (0.20, 0.02, -0.10, 0.100),
    ]
    for i, (tx, ty, bow, wd) in enumerate(feathers):
        poly, spine = feather_poly(root, (tx * w, ty * h), bow * w, wd * h)
        mask = Image.new("L", (w, h), 0)
        ImageDraw.Draw(mask).polygon(poly, fill=255)
        fill = gradient((w, h), -35 + i * 4)
        # a darker underside toward the root
        shade = Image.new("RGBA", (w, h), (90, 45, 0, 0))
        layer = Image.composite(fill, Image.new("RGBA", (w, h), (0, 0, 0, 0)), mask)
        # outline: dilate the mask, outline colour under the feather
        edge = mask.filter(ImageFilter.MaxFilter(13))
        outline = Image.new("RGBA", (w, h), OUTLINE)
        img = Image.alpha_composite(img, Image.composite(outline, Image.new("RGBA", (w, h), (0, 0, 0, 0)), edge))
        img = Image.alpha_composite(img, layer)
        # spine highlight
        d = ImageDraw.Draw(img)
        sp = spine[3:int(len(spine) * 0.85)]
        d.line(sp, fill=GOLD_WHITE + (170,), width=int(0.009 * h))
        # a dark groove just under the spine
        sp2 = [(x, y + 0.012 * h) for x, y in sp]
        d.line(sp2, fill=(120, 60, 5, 150), width=int(0.008 * h))
    # the shoulder: a gold scroll at the root
    d = ImageDraw.Draw(img)
    cx, cy, r = root[0] - 0.02 * w, root[1], 0.11 * h
    d.ellipse((cx - r - 13, cy - r - 13, cx + r + 13, cy + r + 13), fill=OUTLINE)
    boss = gradient((int(2 * r), int(2 * r)), -60)
    bm = Image.new("L", boss.size, 0)
    ImageDraw.Draw(bm).ellipse((0, 0, boss.size[0] - 1, boss.size[1] - 1), fill=255)
    img.paste(boss, (int(cx - r), int(cy - r)), bm)
    r2 = r * 0.45
    d.ellipse((cx - r2 - 8, cy - r2 - 8, cx + r2 + 8, cy + r2 + 8), fill=OUTLINE)
    d.ellipse((cx - r2, cy - r2, cx + r2, cy + r2), fill=(200, 24, 40, 255))
    d.ellipse((cx - r2 * 0.55, cy - r2 * 0.75, cx - r2 * 0.05, cy - r2 * 0.25), fill=(255, 190, 190, 230))
    img = img.resize((W, H), Image.LANCZOS)
    return img


def draw_crest(W=256, H=200):
    w, h = W * SS, H * SS
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    # a crown of five points over a band
    base_y, top_y = 0.78 * h, 0.08 * h
    pts = [(0.08 * w, base_y), (0.08 * w, 0.42 * h), (0.24 * w, 0.58 * h), (0.32 * w, 0.22 * h),
           (0.42 * w, 0.46 * h), (0.5 * w, top_y), (0.58 * w, 0.46 * h), (0.68 * w, 0.22 * h),
           (0.76 * w, 0.58 * h), (0.92 * w, 0.42 * h), (0.92 * w, base_y)]
    mask = Image.new("L", (w, h), 0)
    ImageDraw.Draw(mask).polygon(pts, fill=255)
    edge = mask.filter(ImageFilter.MaxFilter(17))
    img = Image.alpha_composite(img, Image.composite(Image.new("RGBA", (w, h), OUTLINE), Image.new("RGBA", (w, h), (0, 0, 0, 0)), edge))
    img = Image.alpha_composite(img, Image.composite(gradient((w, h), -70), Image.new("RGBA", (w, h), (0, 0, 0, 0)), mask))
    d = ImageDraw.Draw(img)
    # the band
    d.rounded_rectangle((0.04 * w, 0.7 * h, 0.96 * w, 0.94 * h), radius=int(0.06 * h), fill=OUTLINE)
    band = gradient((int(0.88 * w), int(0.2 * h)), 90)
    bm = Image.new("L", band.size, 0)
    ImageDraw.Draw(bm).rounded_rectangle((0, 0, band.size[0] - 1, band.size[1] - 1), radius=int(0.05 * h), fill=255)
    img.paste(band, (int(0.06 * w), int(0.72 * h)), bm)
    d = ImageDraw.Draw(img)
    # pearls on the points
    for px_, py_ in ((0.32, 0.22), (0.5, 0.08), (0.68, 0.22), (0.08, 0.42), (0.92, 0.42)):
        r = 0.045 * h
        d.ellipse((px_ * w - r - 8, py_ * h - r - 8, px_ * w + r + 8, py_ * h + r + 8), fill=OUTLINE)
        d.ellipse((px_ * w - r, py_ * h - r, px_ * w + r, py_ * h + r), fill=GOLD_WHITE + (255,))
    # the red gem in the middle, a diamond
    gx, gy, gw, gh = 0.5 * w, 0.6 * h, 0.13 * w, 0.2 * h
    dia = [(gx, gy - gh), (gx + gw, gy), (gx, gy + gh), (gx - gw, gy)]
    d.polygon([(gx, gy - gh - 14), (gx + gw + 14, gy), (gx, gy + gh + 14), (gx - gw - 14, gy)], fill=OUTLINE)
    d.polygon(dia, fill=(190, 16, 36, 255))
    d.polygon([(gx, gy - gh), (gx + gw, gy), (gx, gy)], fill=(235, 50, 70, 255))
    d.polygon([(gx - gw * 0.55, gy - gh * 0.25), (gx - gw * 0.1, gy - gh * 0.8), (gx - gw * 0.05, gy - gh * 0.35)], fill=(255, 210, 215, 235))
    # side gems
    for sx in (0.22, 0.78):
        r = 0.05 * h
        d.ellipse((sx * w - r - 8, 0.82 * h - r - 8, sx * w + r + 8, 0.82 * h + r + 8), fill=OUTLINE)
        d.ellipse((sx * w - r, 0.82 * h - r, sx * w + r, 0.82 * h + r), fill=(200, 24, 40, 255))
    img = img.resize((W, H), Image.LANCZOS)
    return img


left = draw_wing()
left.save(os.path.join(OUT, "almighty_wing_l.png"))
left.transpose(Image.FLIP_LEFT_RIGHT).save(os.path.join(OUT, "almighty_wing_r.png"))
draw_crest().save(os.path.join(OUT, "almighty_crest.png"))
# a preview on a red ribbon, like the card
pv = Image.new("RGBA", (1100, 360), (24, 28, 44, 255))
d = ImageDraw.Draw(pv)
d.polygon([(300, 110), (840, 110), (800, 250), (260, 250)], fill=(150, 14, 28, 255), outline=(255, 210, 90, 255), width=6)
pv.alpha_composite(left.resize((340, 212)), (10, 70))
pv.alpha_composite(left.transpose(Image.FLIP_LEFT_RIGHT).resize((340, 212)), (750, 70))
pv.alpha_composite(draw_crest().resize((150, 117)), (475, 10))
pv.save(os.path.join(OUT, "almighty_preview.png"))
print("ok")
