"""Draws the ball skins' textures into assets/balls: equirectangular maps (1024x512, the top row
the ball's north pole) for the UV sphere in assets/balls/BallSkinMeshes.fbx. Run with any
Python 3 that has numpy and Pillow; upload the PNGs and paste their ids into Assets.BallSkins.

  ProSwirl.png   yellow with three tapering blue crescents swirling out of a Y (a pro match ball)
  TriPanel.png   sweeping S-curved bands of red, white and green on a honeycomb
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


def frame(axis):
    """An orthonormal frame with `axis` as its pole: (theta from the pole, azimuth round it)."""
    a = np.array(axis, dtype=np.float64)
    a /= np.linalg.norm(a)
    ref = np.array([0.0, 1.0, 0.0]) if abs(a[1]) < 0.9 else np.array([1.0, 0.0, 0.0])
    b = np.cross(a, ref)
    b /= np.linalg.norm(b)
    c = np.cross(a, b)
    da = DX * a[0] + DY * a[1] + DZ * a[2]
    db = DX * b[0] + DY * b[1] + DZ * b[2]
    dc = DX * c[0] + DY * c[1] + DZ * c[2]
    return np.arccos(np.clip(da, -1, 1)), np.arctan2(dc, db)


def wrap(a):
    return (a + math.pi) % (2 * math.pi) - math.pi


def dimples(freq, size):
    """A field of small round dimples all over the ball (1 inside one, 0 between)."""
    f = np.cos(DX * freq) * np.cos(DY * freq) * np.cos(DZ * freq)
    g = np.cos((DX + DY) * freq * 0.7071) * np.cos((DY - DZ) * freq * 0.7071)
    return np.clip((np.maximum(np.abs(f), np.abs(g)) - (1 - size)) / size, 0, 1)


def pro_swirl():
    # the owner's reference: a pro match ball, yellow with three blue crescents that swirl out of a
    # Y-shaped junction and taper away round the far side; the blue dimpled, faint seams in the
    # yellow (no logos or print)
    theta, phi = frame((0.35, -0.45, 0.82))
    yellow, blue = rgb((250, 204, 34)), rgb((22, 58, 168))
    img = np.ones((H, W, 3)) * yellow
    # broad, gentle swooshes: narrow at the junction, widest round the middle, tapering to a
    # point on the far side; about a third of the ball blue
    twist = 0.95
    half = (math.pi / 3) * 0.72 * np.clip(np.sin(theta * 0.85 + 0.55), 0, 1) ** 1.3 * np.cos(theta / 2) ** 0.9
    arm = np.zeros_like(theta)
    edge = np.full_like(theta, 9.0)
    for k in range(3):
        centre = k * 2 * math.pi / 3 + twist * theta
        off = np.abs(wrap(phi - centre))
        inside = off < half
        arm = np.maximum(arm, inside.astype(np.float64))
        edge = np.minimum(edge, np.abs(off - half) * np.sin(np.clip(theta, 0.05, math.pi)))
        # a soft seam down the middle of each yellow lobe
        mid = np.abs(wrap(phi - centre - math.pi / 3)) * np.sin(np.clip(theta, 0.05, math.pi))
        img[mid < 0.006] = yellow * 0.86
    m = arm > 0
    d = dimples(70, 0.25)
    img[m] = blue * (1 - 0.22 * d[m, None])
    # yellow panels are smooth with a very faint pebble
    pebble = noise3(DX, DY, DZ, 60, 41)
    img[~m] = img[~m] * (0.96 + 0.06 * pebble[~m, None])
    # a crisp, slightly darker rim where blue meets yellow
    rim = (edge < 0.012) & m
    img[rim] = blue * 0.75
    save("ProSwirl.png", img)


def honeycomb(cells):
    """Raised hexagon outlines (1 on an edge, 0 in a cell), even all over the ball: laid on the
    six faces of a cube and projected out (the faces' joins vanish at this size)."""
    a = np.stack([np.abs(DX), np.abs(DY), np.abs(DZ)])
    face = np.argmax(a, axis=0)
    comp = [DX, DY, DZ]
    out = np.zeros_like(DX)
    k = 2 * math.pi * cells
    for f in range(3):
        m = face == f
        main = np.maximum(np.abs(comp[f]), 1e-6)
        u = comp[(f + 1) % 3] / main
        v = comp[(f + 2) % 3] / main
        g = np.cos(k * u) + np.cos(k * (0.5 * u + 0.866 * v)) + np.cos(k * (-0.5 * u + 0.866 * v))
        out[m] = (np.clip((1.2 - g) / 1.2, 0, 1) ** 6)[m]
    return out


def tri_panel():
    # the owner's reference: a match ball wrapped in sweeping S-curved bands of red, white and
    # green (the white widest), with a honeycomb texture all over (no logos or print). The bands
    # repeat twice pole to pole, so both ends of the wrap sit in the middle of a white band and
    # nothing closes into a ring.
    theta, phi = frame((0.2, 0.95, -0.25))
    lat = math.pi / 2 - theta
    s = lat + 0.85 * np.cos(lat) * np.sin(phi + 0.4) + 0.1 * np.cos(lat) * np.sin(2 * phi)
    green, red, white = rgb((20, 140, 72)), rgb((214, 32, 46)), rgb((246, 245, 240))
    widths = [("red", 0.43), ("white", 0.71), ("green", 0.43)]
    period = math.pi / 2
    # both poles (s = +-pi/2) land mid-white
    shift = (0.43 + 0.71 / 2) - math.pi / 2
    pos = (s + shift + 4 * period) % period
    img = np.zeros((H, W, 3))
    start = 0.0
    seam_dist = np.full_like(s, 9.0)
    for name, w in widths:
        inside = (pos >= start) & (pos < start + w)
        img[inside] = {"green": green, "red": red, "white": white}[name]
        seam_dist = np.minimum(seam_dist, np.abs(pos - start))
        start += w
    seam_dist = np.minimum(seam_dist, np.abs(pos - period))
    img[pos >= start] = white
    hexes = honeycomb(14)
    img = img * (1 - 0.13 * hexes[..., None])
    img[seam_dist < 0.011] = img[seam_dist < 0.011] * 0.72
    save("TriPanel.png", img)


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
