"""Draws the advent calendar's textures (Config.Winter.Advent; the owner, 2026-11-18: "make up a tone of
cosmetics for advent calender").

Ball maps into assets/balls, equirectangular (1024x512) for the UV sphere the other texture balls
use (tools/generate_ball_skins.py, whose helpers these borrow):

  Gingerbread.png  baked gingerbread: warm brown, darker crumb, white icing zigzags round it, three
                   rows of sugar buttons and a sprinkle of sugar
  Pudding.png      a Christmas pudding: dark fruity brown speckled with raisins and peel, a thick
                   white custard cap over the top with drips running down (the holly is BallSkins')
  Wreath.png       a pine wreath: needles in dark and light greens all over, small pine cones

Particles into assets/fx/winter, drawn in their own colours (not tinted), 256 px on clear, at 4x
and scaled down for smooth edges:

  HollyLeaf.png    a holly sprig: two spiky leaves and three red berries (the Holly trail)
  CandyCane.png    a candy cane, red and white stripes, the hook up (the Candy Canes trail)
  GingerMan.png    a gingerbread man with white icing trim and buttons (the Gingerbread Men trail)
  Bell.png         a gold jingle bell with a red bow (the Sleigh Bells trail)

Run with any Python 3 that has numpy and Pillow:  python tools/generate_advent_textures.py
"""

import math
import os
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import generate_ball_skins as B  # noqa: E402

DX, DY, DZ, LON, LAT, H, W = B.DX, B.DY, B.DZ, B.LON, B.LAT, B.H, B.W
rgb, frame, noise3, save = B.rgb, B.frame, B.noise3, B.save

ROOT = Path(__file__).resolve().parent.parent
FX = ROOT / "assets" / "fx" / "winter"


def mix(img, color, amount):
    a = np.clip(amount, 0, 1)[..., None]
    return img * (1 - a) + rgb(color) * a


def soft(d, w, edge=0.004):
    return np.clip((w - d) / edge, 0, 1)


def spots(count, seed, size, jitter=0.25):
    """`count` round spots scattered evenly over the sphere: 0..1 coverage, and which spot."""
    r = np.random.default_rng(seed)
    out = np.zeros_like(DX)
    for i in range(count):
        y = 1 - (i + 0.5) / count * 2
        rr = math.sqrt(max(0.0, 1 - y * y))
        a = i * 2.39996 + r.uniform(-jitter, jitter)
        v = np.array([math.cos(a) * rr, y, math.sin(a) * rr]) + r.normal(scale=jitter * 0.3, size=3)
        theta, _ = frame(v)
        out = np.maximum(out, soft(theta, size * r.uniform(0.75, 1.2), 0.01))
    return out


# ---------------------------------------------------------------------------------------------
# balls
# ---------------------------------------------------------------------------------------------

def gingerbread():
    base, dark, light = rgb((190, 112, 52)), rgb((128, 66, 26)), rgb((222, 150, 84))
    crumb = noise3(DX, DY, DZ, 9, 41) * 0.6 + noise3(DX, DY, DZ, 30, 42) * 0.4
    img = base[None, None, :] * np.ones((H, W, 1))
    img = mix(img, dark, np.clip((0.46 - crumb) * 3, 0, 1) * 0.7)
    img = mix(img, light, np.clip((crumb - 0.6) * 3, 0, 1) * 0.5)
    pores = noise3(DX, DY, DZ, 90, 43)
    img = img * (0.94 + 0.08 * pores[..., None])
    icing = (255, 252, 246)
    # three rings of icing zigzag round it (the middle one wider), a thin line of shadow under each
    for lat0, amp, n in ((0.0, 0.11, 16), (0.62, 0.07, 12), (-0.62, 0.07, 12)):
        wave = lat0 + amp * (np.abs(((LON / (2 * math.pi) * n) % 1) - 0.5) * 4 - 1)
        d = np.abs(LAT - wave)
        img = mix(img, (110, 56, 20), soft(np.abs(LAT - (wave - 0.022)), 0.016) * 0.5)
        img = mix(img, icing, soft(d, 0.022, 0.006))
    # sugar buttons between the zigzags: red and green in turn, a white glint on each
    for lat0, n, off in ((0.31, 10, 0.0), (-0.31, 10, 0.5)):
        for k in range(n):
            lon0 = (k + off) / n * 2 * math.pi - math.pi
            v = (math.cos(lat0) * math.cos(lon0), math.sin(lat0), math.cos(lat0) * math.sin(lon0))
            theta, _ = frame(v)
            col = (214, 30, 44) if k % 2 == 0 else (40, 160, 74)
            img = mix(img, (90, 40, 14), soft(theta, 0.085, 0.01) * 0.6)
            img = mix(img, col, soft(theta, 0.07, 0.008))
            glint = frame((v[0] + 0.05, v[1] + 0.05, v[2]))[0]
            img = mix(img, (255, 255, 255), soft(glint, 0.02, 0.01) * 0.8)
    # the caps of the poles iced white
    img = mix(img, icing, soft(np.abs(LAT) - math.radians(78), 0.0, -0.02) * 0 + (np.abs(LAT) > math.radians(80)))
    sugar = noise3(DX, DY, DZ, 160, 44)
    img = mix(img, (255, 250, 240), np.clip((sugar - 0.8) * 6, 0, 1) * 0.6)
    save("Gingerbread.png", img)


def pudding():
    brown, dark = rgb((92, 46, 22)), rgb((52, 24, 10))
    n = noise3(DX, DY, DZ, 12, 51) * 0.5 + noise3(DX, DY, DZ, 40, 52) * 0.5
    img = brown[None, None, :] * (1 - 0.6 * n[..., None]) + dark[None, None, :] * (0.6 * n[..., None])
    # raisins (near black), peel (orange) and cherries (red) studded through it
    img = mix(img, (30, 12, 6), spots(70, 53, 0.05))
    img = mix(img, (226, 120, 30), spots(40, 54, 0.035))
    img = mix(img, (180, 20, 30), spots(26, 55, 0.04))
    # a glossy crust: a faint lighter band
    img = img * (1 + 0.08 * np.clip(1 - np.abs(LAT - 0.3) / 0.4, 0, 1)[..., None])
    # the custard cap: thick over the top, its edge running down in drips of different lengths
    drips = 0.0
    r = np.random.default_rng(56)
    edge = np.full_like(LON, math.radians(32))
    for _ in range(11):
        c = r.uniform(-math.pi, math.pi)
        wdt = r.uniform(0.12, 0.24)
        depth = r.uniform(0.22, 0.55)
        dl = np.abs((LON - c + math.pi) % (2 * math.pi) - math.pi)
        edge = edge - depth * np.clip(1 - (dl / wdt) ** 2, 0, 1) ** 0.5
    wave = edge + 0.04 * np.sin(LON * 7)
    custard = soft(-(LAT - wave), 0.0, 0.012) + (LAT > wave)
    custard = np.clip(custard, 0, 1)
    cream, shade = (255, 248, 226), (226, 210, 170)
    img = mix(img, (60, 30, 12), soft(np.abs(LAT - (wave - 0.02)), 0.02) * 0.5)
    img = mix(img, shade, custard)
    img = mix(img, cream, custard * np.clip((LAT - wave) / 0.15, 0, 1))
    save("Pudding.png", img)


def wreath():
    """Pine boughs: thousands of short needles drawn as strokes, in clusters that each lean their own
    way, dark under light, small pine cones and a dusting of snow."""
    r = np.random.default_rng(61)
    img = Image.new("RGB", (W, H), (8, 40, 20))
    d = ImageDraw.Draw(img)
    greens = [((10, 52, 26), 3200), ((18, 76, 38), 2600), ((28, 100, 50), 1700), ((44, 126, 62), 800), ((86, 164, 84), 250)]
    for layer, (col, count) in enumerate(greens):
        for _ in range(count):
            cx, cy = r.uniform(0, W), r.uniform(0, H)
            flow = math.sin(cx / W * 12 + layer) * 0.9 + math.cos(cy / H * 9) * 0.6
            for k in range(5):
                ang = flow + (k - 2) * 0.35 + r.normal(scale=0.12)
                ln = r.uniform(14, 26) * (1.6 if abs(cy - H / 2) > H * 0.4 else 1)
                x0, y0 = cx + r.normal(scale=3), cy + r.normal(scale=3)
                d.line([(x0, y0), (x0 + math.cos(ang) * ln * 2.0, y0 + math.sin(ang) * ln)], fill=col, width=3)
    for _ in range(16):
        cx, cy = r.uniform(0, W), r.uniform(H * 0.15, H * 0.85)
        for k in range(6):
            y = cy - 18 + k * 7
            w = 16 - abs(k - 2.5) * 3
            d.ellipse((cx - w, y - 6, cx + w, y + 6), fill=(118, 70, 32), outline=(70, 38, 14))
    for _ in range(350):
        x, y = r.uniform(0, W), r.uniform(0, H)
        d.ellipse((x - 2, y - 1.5, x + 2, y + 1.5), fill=(236, 244, 255))
    arr = np.asarray(img.filter(ImageFilter.GaussianBlur(0.6)), dtype=np.float64) / 255.0
    save("Wreath.png", arr)


# ---------------------------------------------------------------------------------------------
# particles (their own colours, on clear)
# ---------------------------------------------------------------------------------------------

S = 1024
CLEAR = (0, 0, 0, 0)


def finish(img, name):
    FX.mkdir(parents=True, exist_ok=True)
    img.resize((256, 256), Image.LANCZOS).save(FX / (name + ".png"))
    print("wrote", FX / (name + ".png"))


def outline(img, color=(20, 10, 6, 255), width=18):
    """A dark rim round everything drawn, so it reads over the court."""
    a = img.split()[3]
    grown = a.filter(ImageFilter.MaxFilter(width * 2 + 1))
    rim = Image.new("RGBA", img.size, color)
    rim.putalpha(grown)
    rim.alpha_composite(img)
    return rim


def leaf(d, cx, cy, angle, length, width, col, vein):
    """A holly leaf: a long shape with three spiky points down each side."""
    pts = []
    n = 7
    for side in (1, -1):
        rng = range(n + 1) if side == 1 else range(n, -1, -1)
        for i in rng:
            t = i / n
            w = math.sin(t * math.pi) * width
            spike = 1.0 if i % 2 == 1 else 0.62
            x = (t - 0.5) * length
            y = side * w * spike
            pts.append((x, y))
    ca, sa = math.cos(angle), math.sin(angle)
    poly = [(cx + x * ca - y * sa, cy + x * sa + y * ca) for x, y in pts]
    d.polygon(poly, fill=col)
    d.line([(cx - 0.5 * length * ca, cy - 0.5 * length * sa), (cx + 0.5 * length * ca, cy + 0.5 * length * sa)], fill=vein, width=12)


def holly():
    img = Image.new("RGBA", (S, S), CLEAR)
    d = ImageDraw.Draw(img)
    leaf(d, 350, 470, math.radians(-30), 560, 150, (24, 120, 56, 255), (12, 70, 30, 255))
    leaf(d, 660, 470, math.radians(210), 560, 150, (34, 140, 64, 255), (12, 70, 30, 255))
    for x, y in ((470, 560), (580, 570), (525, 650)):
        d.ellipse((x - 80, y - 80, x + 80, y + 80), fill=(206, 20, 40, 255))
        d.ellipse((x - 45, y - 55, x - 5, y - 15), fill=(255, 160, 160, 255))
    finish(outline(img), "HollyLeaf")


def candy_cane():
    shape = Image.new("L", (S, S), 0)
    d = ImageDraw.Draw(shape)
    w = 104
    stick = [(560, 900 - i * 14) for i in range(41)]
    cx, cy, rr = 430, 340, 130
    hook = [(cx + rr * math.cos(i / 30 * math.pi), cy - rr * math.sin(i / 30 * math.pi)) for i in range(31)]
    path = stick + hook + [(cx - rr, cy + 60)]
    for i in range(len(path) - 1):
        d.line([path[i], path[i + 1]], fill=255, width=w)
    for p in path:
        d.ellipse((p[0] - w / 2, p[1] - w / 2, p[0] + w / 2, p[1] + w / 2), fill=255)
    # diagonal red bands across everything, kept inside the cane
    bands = Image.new("RGBA", (S, S), (250, 250, 246, 255))
    bd = ImageDraw.Draw(bands)
    for k in range(-20, 30):
        x = k * 70
        bd.polygon([(x, 0), (x + 34, 0), (x + 34 - S, S), (x - S, S)], fill=(214, 26, 44, 255))
    # a soft shine down one side
    shine = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(shine).line([(526, 880), (526, 360)], fill=(255, 255, 255, 90), width=22)
    bands.alpha_composite(shine.filter(ImageFilter.GaussianBlur(6)))
    img = Image.new("RGBA", (S, S), CLEAR)
    img.paste(bands, (0, 0), shape)
    finish(outline(img), "CandyCane")


def ginger_man():
    img = Image.new("RGBA", (S, S), CLEAR)
    d = ImageDraw.Draw(img)
    body = (196, 116, 54, 255)
    d.ellipse((392, 120, 632, 360), fill=body)  # head
    d.rounded_rectangle((372, 330, 652, 700), radius=110, fill=body)  # body
    d.line([(420, 420), (230, 360)], fill=body, width=130)  # arms
    d.line([(604, 420), (794, 360)], fill=body, width=130)
    for x in (230, 794):
        d.ellipse((x - 65, 295, x + 65, 425), fill=body)
    d.line([(450, 650), (360, 880)], fill=body, width=140)  # legs
    d.line([(574, 650), (664, 880)], fill=body, width=140)
    for x in (360, 664):
        d.ellipse((x - 70, 810, x + 70, 950), fill=body)
    ic = (255, 252, 246, 255)
    # icing: eyes, a smile, squiggles across the cuffs, buttons
    for x in (470, 554):
        d.ellipse((x - 20, 210, x + 20, 250), fill=ic)
    d.arc((450, 220, 574, 320), 20, 160, fill=ic, width=14)
    for cx, cy in ((250, 365), (774, 365), (370, 860), (654, 860)):
        for k in range(-2, 3):
            d.line([(cx + k * 22 - 10, cy - 30), (cx + k * 22 + 10, cy + 30)], fill=ic, width=12)
    for y, col in ((440, (214, 30, 44, 255)), (530, (40, 160, 74, 255)), (620, (214, 30, 44, 255))):
        d.ellipse((512 - 32, y - 32, 512 + 32, y + 32), fill=col)
    finish(outline(img, (70, 34, 10, 255)), "GingerMan")


def bell():
    img = Image.new("RGBA", (S, S), CLEAR)
    d = ImageDraw.Draw(img)
    gold, dark, hi = (255, 200, 60, 255), (190, 130, 20, 255), (255, 242, 180, 255)
    # a sleigh bell: round, a slot across its lower half, a loop on top
    d.ellipse((200, 230, 824, 854), fill=gold)
    d.ellipse((200, 230, 824, 854), outline=dark, width=18)
    d.rounded_rectangle((300, 610, 724, 660), radius=25, fill=(70, 40, 10, 255))
    d.ellipse((470, 640, 554, 724), fill=(70, 40, 10, 255))
    d.line([(200, 540), (824, 540)], fill=dark, width=16)
    d.ellipse((300, 300, 460, 420), fill=hi)  # the shine
    # a red bow on the loop
    d.ellipse((462, 150, 562, 250), outline=dark, width=26)
    red = (214, 26, 44, 255)
    d.polygon([(512, 230), (330, 140), (340, 320)], fill=red)
    d.polygon([(512, 230), (694, 140), (684, 320)], fill=red)
    d.ellipse((470, 190, 554, 274), fill=(170, 14, 30, 255))
    finish(outline(img, (60, 30, 6, 255)), "Bell")


if __name__ == "__main__":
    os.makedirs(B.OUT, exist_ok=True)
    gingerbread()
    pudding()
    wreath()
    holly()
    candy_cane()
    ginger_man()
    bell()
