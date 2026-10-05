"""Draws the ball skins' textures into assets/balls: equirectangular maps (1024x512, the top row
the ball's north pole) for the UV sphere in assets/balls/BallSkinMeshes.fbx. Run with any
Python 3 that has numpy and Pillow; upload the PNGs and paste their ids into Assets.BallSkins.

  ProSwirl.png   eight curved panels swirling pole to pole, yellow and blue (a pro match ball)
  TriPanel.png   the classic 18-panel layout in white, red and green
  Beach.png      six bright gores with white caps
  Eyeball.png    a bloodshot white with a green-blue iris
  Lava.png       black basalt split by glowing cracks
  Galaxy.png     a violet nebula full of stars
  Planet.png     a banded gas giant
"""

import math
import os

import numpy as np
from PIL import Image

OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "balls")
W, H = 1024, 512


def directions():
    y, x = np.mgrid[0:H, 0:W].astype(np.float64)
    lon = (x + 0.5) / W * 2 * math.pi - math.pi
    lat = math.pi / 2 - (y + 0.5) / H * math.pi
    dx = np.cos(lat) * np.cos(lon)
    dy = np.sin(lat)
    dz = np.cos(lat) * np.sin(lon)
    return lon, lat, dx, dy, dz


LON, LAT, DX, DY, DZ = directions()


def rgb(c):
    return np.array(c, dtype=np.float64) / 255.0


def fill(mask, color, img):
    img[mask] = rgb(color)


def save(name, img):
    Image.fromarray((np.clip(img, 0, 1) * 255 + 0.5).astype(np.uint8), "RGB").save(os.path.join(OUT, name))
    print("wrote", name)


def noise3(x, y, z, freq, seed):
    """Cheap smooth 3D noise: a sum of random sinusoids (seamless on the sphere)."""
    r = np.random.default_rng(seed)
    total = np.zeros_like(x)
    for _ in range(10):
        k = r.normal(size=3)
        k = k / np.linalg.norm(k) * freq * r.uniform(0.7, 1.3)
        total += np.sin(x * k[0] + y * k[1] + z * k[2] + r.uniform(0, 6.3))
    return total / 10 * 0.5 + 0.5


def shade(img, amount=0.12):
    # a touch of darkening toward the seams of the map is handled by the panels themselves; this
    # adds a faint grain so flat colours don't look plastic
    g = noise3(DX, DY, DZ, 40, 99)
    return img * (1 - amount / 2 + amount * g[..., None])


def pro_swirl():
    img = np.zeros((H, W, 3))
    # panels swept by latitude: each band's edge leans further round the higher it climbs
    t = (LON + 1.15 * np.sin(LAT * 1.6) + 0.35 * LAT) / (2 * math.pi) * 8
    idx = np.floor(t).astype(int) % 8
    frac = t - np.floor(t)
    yellow, blue, seam = (255, 206, 40), (28, 84, 196), (18, 28, 60)
    for i in range(8):
        fill(idx == i, yellow if i % 2 == 0 else blue, img)
    edge = np.minimum(frac, 1 - frac)
    img[edge < 0.035] = rgb(seam)
    # the two poles meet in small white-rimmed caps
    cap = np.abs(LAT) > math.radians(80)
    img[cap] = rgb((240, 240, 236))
    img[(np.abs(LAT) > math.radians(78.5)) & ~cap] = rgb(seam)
    save("ProSwirl.png", shade(img))


def tri_panel():
    img = np.zeros((H, W, 3))
    a = np.stack([np.abs(DX), np.abs(DY), np.abs(DZ)])
    face = np.argmax(a, axis=0)
    comp = [DX, DY, DZ]
    # within each face, three strips across the next axis round (the 18-panel ball)
    strips = np.zeros_like(DX)
    for f in range(3):
        m = face == f
        main = comp[f]
        across = comp[(f + 1 + (f % 2)) % 3] / np.maximum(np.abs(main), 1e-6)
        strips[m] = across[m]
    s = np.clip((strips + 1) / 2 * 3, 0, 2.999)
    strip = np.floor(s).astype(int)
    white, red, green, seam = (244, 244, 238), (214, 32, 44), (24, 150, 72), (40, 40, 44)
    group = face * 2 + (np.sign(np.choose(face, comp)) > 0)
    for g in range(6):
        for k in range(3):
            m = (group == g) & (strip == k)
            if k == 1:
                c = white
            else:
                c = red if g % 3 == 0 else green if g % 3 == 1 else white
                if g % 3 == 2:
                    c = red if k == 0 else green
            fill(m, c, img)
    fr = s - np.floor(s)
    edge = np.minimum(fr, 1 - fr)
    img[edge < 0.04] = rgb(seam)
    # seams between faces
    top2 = np.sort(a, axis=0)
    img[(top2[2] - top2[1]) < 0.025] = rgb(seam)
    save("TriPanel.png", shade(img))


def beach():
    img = np.zeros((H, W, 3))
    cols = [(232, 40, 44), (255, 210, 30), (30, 110, 230), (245, 245, 240), (40, 190, 80), (255, 130, 30)]
    g = np.floor((LON + math.pi) / (2 * math.pi) * 6).astype(int) % 6
    for i, c in enumerate(cols):
        fill(g == i, c, img)
    img[np.abs(LAT) > math.radians(76)] = rgb((250, 250, 248))
    save("Beach.png", shade(img, 0.08))


def eyeball():
    img = np.ones((H, W, 3)) * rgb((245, 240, 232))
    # the eye looks out along +x
    ang = np.degrees(np.arccos(np.clip(DX, -1, 1)))
    # veins: thin ridges of noise, thicker toward the back
    v = noise3(DX, DY, DZ, 14, 5)
    veins = np.exp(-((v - 0.5) / 0.012) ** 2) * np.clip((ang - 40) / 80, 0, 1)
    img = img * (1 - veins[..., None]) + rgb((190, 30, 40)) * veins[..., None]
    iris = ang < 26
    th = np.arctan2(DZ, DY)
    fibres = 0.5 + 0.5 * np.sin(th * 60 + noise3(DX, DY, DZ, 30, 6) * 6)
    ic = rgb((40, 160, 150)) * (0.6 + 0.4 * fibres[..., None]) * (0.7 + 0.3 * (ang / 26)[..., None])
    img[iris] = ic[iris]
    img[(ang > 24.5) & (ang < 26.5)] = rgb((20, 50, 50))
    img[ang < 11] = rgb((8, 8, 10))
    hl = np.degrees(np.arccos(np.clip(DX * 0.97 + DY * 0.17 + DZ * 0.17, -1, 1))) < 4
    img[hl] = rgb((255, 255, 255))
    save("Eyeball.png", img)


def lava():
    r = np.random.default_rng(12)
    pts = r.normal(size=(70, 3))
    pts /= np.linalg.norm(pts, axis=1, keepdims=True)
    d = np.stack([DX, DY, DZ], axis=-1)
    dots = d @ pts.T
    s = np.sort(dots, axis=-1)
    gap = s[..., -1] - s[..., -2]  # small near a crack (two cells equally close)
    crack = np.exp(-(gap / 0.018) ** 2)
    rock = 0.06 + 0.1 * noise3(DX, DY, DZ, 18, 13)
    img = np.stack([rock * 1.1, rock * 0.95, rock * 0.9], axis=-1)
    hot = rgb((255, 120, 20)) * crack[..., None] + rgb((255, 230, 120)) * (crack ** 4)[..., None]
    glow = np.exp(-(gap / 0.06) ** 2)[..., None] * rgb((120, 30, 0)) * 0.6
    save("Lava.png", img + hot + glow)


def galaxy():
    n1 = noise3(DX, DY, DZ, 3, 21)
    n2 = noise3(DX, DY, DZ, 7, 22)
    base = rgb((12, 6, 30))
    neb = rgb((150, 50, 220)) * (n1 ** 3)[..., None] + rgb((40, 120, 255)) * (n2 ** 4)[..., None] * 0.8
    img = base + neb * 0.9
    r = np.random.default_rng(23)
    stars = r.random((H, W)) > 0.9965
    img[stars] = 1.0
    big = r.random((H, W)) > 0.9995
    for yy, xx in zip(*np.nonzero(big)):
        img[max(0, yy - 1):yy + 2, max(0, xx - 1):xx + 2] = rgb((255, 240, 255))
    save("Galaxy.png", img)


def planet():
    turb = noise3(DX, DY, DZ, 6, 31)
    band = np.sin(LAT * 9 + turb * 2.2) * 0.5 + 0.5
    band2 = np.sin(LAT * 23 + turb * 4) * 0.5 + 0.5
    a, b, c = rgb((230, 196, 140)), rgb((186, 120, 70)), rgb((250, 236, 200))
    img = a * band[..., None] + b * (1 - band[..., None])
    img = img * (0.85 + 0.15 * band2[..., None])
    storm = np.degrees(np.arccos(np.clip(DX * 0.82 + DY * -0.34 + DZ * 0.46, -1, 1))) < 7
    img[storm] = rgb((200, 90, 60))
    img = img * 0.9 + c * 0.1
    save("Planet.png", img)


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    pro_swirl()
    tri_panel()
    beach()
    eyeball()
    lava()
    galaxy()
    planet()
