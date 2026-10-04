"""Draws the score effects' own textures into assets/fx (white or near-white on clear, tinted in
code). Run with any Python 3 that has numpy and Pillow; upload the PNGs and paste their ids into
Assets.Fx.

  Swirl.png      a spiral accretion disc, the Black Hole's
  Wind.png       a tapered, streaky band of wind, the Tornado's beams (laid along a Beam)
  Foam.png       4x4 flipbook of spray bursting and thinning, the Tsunami's crest
  Water.png      a tiling wall of water with foam streaks running down, the wave's surface
  Shock.png      a soft glowing ring with a hot rim, laid flat on the floor
  Flare.png      a six-point lens flare with a hot core
"""

import math
import os

import numpy as np
from PIL import Image

OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "fx")
rng = np.random.default_rng(7)


def grid(n):
    y, x = np.mgrid[0:n, 0:n].astype(np.float64)
    x = (x + 0.5) / n * 2 - 1
    y = (y + 0.5) / n * 2 - 1
    return x, y


def smooth(t):
    t = np.clip(t, 0, 1)
    return t * t * (3 - 2 * t)


def value_noise(n, cells, seed):
    """Tileable smooth value noise in [0, 1]."""
    r = np.random.default_rng(seed)
    g = r.random((cells, cells))
    y, x = np.mgrid[0:n, 0:n].astype(np.float64) / n * cells
    x0 = np.floor(x).astype(int)
    y0 = np.floor(y).astype(int)
    fx = smooth(x - x0)
    fy = smooth(y - y0)
    x1 = (x0 + 1) % cells
    y1 = (y0 + 1) % cells
    x0 %= cells
    y0 %= cells
    a = g[y0, x0] * (1 - fx) + g[y0, x1] * fx
    b = g[y1, x0] * (1 - fx) + g[y1, x1] * fx
    return a * (1 - fy) + b * fy


def fbm(n, base, octaves, seed):
    total = np.zeros((n, n))
    amp = 1.0
    norm = 0.0
    for o in range(octaves):
        total += value_noise(n, base * 2 ** o, seed + o) * amp
        norm += amp
        amp *= 0.5
    return total / norm


def save(name, rgb, alpha):
    a = np.clip(alpha, 0, 1)
    img = np.dstack([np.clip(rgb, 0, 1)] * 3 if rgb.ndim == 2 else [np.clip(rgb[..., i], 0, 1) for i in range(3)])
    rgba = np.dstack([img, a])
    Image.fromarray((rgba * 255 + 0.5).astype(np.uint8), "RGBA").save(os.path.join(OUT, name))
    print("wrote", name)


def swirl(n=512):
    x, y = grid(n)
    r = np.sqrt(x * x + y * y)
    th = np.arctan2(y, x)
    # log-spiral arms, sheared by radius
    arms = 0.5 + 0.5 * np.cos(3 * (th - 4.2 * np.log(r + 0.05)))
    arms = arms ** 2.2
    streak = fbm(n, 6, 4, 11)
    disc = smooth((r - 0.16) / 0.12) * smooth((1 - r) / 0.5)
    hot = np.exp(-((r - 0.24) / 0.05) ** 2)  # the bright inner rim around the hole
    alpha = disc * (0.35 + 0.65 * arms) * (0.6 + 0.6 * streak) + hot
    rgb = 0.75 + 0.25 * np.clip(hot * 2 + arms * 0.4, 0, 1)
    save("Swirl.png", rgb, alpha)


def wind(w=256, h=1024):
    y, x = np.mgrid[0:h, 0:w].astype(np.float64)
    u = (x + 0.5) / w  # across the band
    v = (y + 0.5) / h  # along it
    # streaks: noise stretched hard along v
    s = np.zeros((h, w))
    for i, f in enumerate([6, 13, 27]):
        r = np.random.default_rng(30 + i)
        phases = r.random(f * 4)
        idx = np.floor(u * f * 4).astype(int) % (f * 4)
        frac = u * f * 4 - np.floor(u * f * 4)
        band = np.sin(frac * math.pi) ** 2
        s += band * (0.5 + 0.5 * np.sin(v * math.pi * 2 * (1 + i) + phases[idx] * 6.28)) / (i + 1)
    s /= s.max()
    edge = np.sin(u * math.pi) ** 0.7
    taper = smooth(v / 0.25) * smooth((1 - v) / 0.25)
    alpha = edge * taper * (0.15 + 0.85 * s ** 1.5)
    save("Wind.png", np.ones_like(alpha), alpha)


def foam(cell=256, frames=16):
    sheet = np.zeros((cell * 4, cell * 4, 4))
    x, y = grid(cell)
    blobs = [(rng.uniform(-0.35, 0.35), rng.uniform(-0.3, 0.35), rng.uniform(0.2, 0.42)) for _ in range(12)]
    for f in range(frames):
        t = f / (frames - 1)
        a = np.zeros((cell, cell))
        for bx, by, br in blobs:
            # each puff blows outward and up, grows, then thins away
            cx = bx * (0.6 + t * 0.9)
            cy = by * (0.6 + t * 0.9) - t * 0.25
            rr = br * (0.6 + t * 1.1)
            d = np.sqrt((x - cx) ** 2 + (y - cy) ** 2) / rr
            a = np.maximum(a, smooth(1 - d))
        detail = fbm(cell, 4, 4, 50 + f)
        a = a * (0.55 + 0.7 * detail)
        # hollow it out as it ages: spray, not a ball
        a = np.clip(a - t * 0.55 * (1 - detail), 0, 1) * (1 - smooth((t - 0.6) / 0.4) * 0.9)
        edge = smooth((1 - np.sqrt(x * x + y * y)) / 0.15)
        a *= edge
        row, col = divmod(f, 4)
        sheet[row * cell:(row + 1) * cell, col * cell:(col + 1) * cell, 3] = a
        sheet[row * cell:(row + 1) * cell, col * cell:(col + 1) * cell, :3] = (0.86 + 0.14 * detail)[..., None]
    save("Foam.png", sheet[..., :3], sheet[..., 3])


def water(n=512):
    y, x = np.mgrid[0:n, 0:n].astype(np.float64) / n
    base = fbm(n, 4, 5, 70)
    # foam streaks running down the face (tile both ways)
    streaks = fbm(n, 8, 3, 80)
    lines = 0.5 + 0.5 * np.sin((x * 18 + streaks * 3) * 2 * math.pi)
    foamy = np.clip((lines ** 6) * (0.4 + base), 0, 1)
    caustic = np.abs(np.sin((base * 9 + y * 2) * math.pi)) ** 8
    rgb = np.dstack([
        0.55 + 0.45 * np.clip(foamy + caustic * 0.6, 0, 1),
        0.78 + 0.22 * np.clip(foamy + caustic * 0.6, 0, 1),
        np.ones((n, n)),
    ])
    alpha = 0.55 + 0.45 * np.clip(foamy + caustic * 0.5, 0, 1)
    save("Water.png", rgb, alpha)


def shock(n=512):
    x, y = grid(n)
    r = np.sqrt(x * x + y * y)
    th = np.arctan2(y, x)
    ragged = 0.03 * (fbm(n, 6, 3, 90) - 0.5)
    rim = np.exp(-((r - 0.86 + ragged) / 0.035) ** 2)
    trail = smooth((r - 0.35) / 0.5) * (r < 0.88) * 0.45
    rays = (0.5 + 0.5 * np.cos(th * 40 + fbm(n, 5, 2, 95) * 8)) ** 4 * trail * 0.6
    alpha = np.clip(rim + trail * 0.5 + rays, 0, 1) * smooth((1 - r) / 0.06)
    save("Shock.png", np.ones_like(alpha), alpha)


def flare(n=512):
    x, y = grid(n)
    r = np.sqrt(x * x + y * y)
    th = np.arctan2(y, x)
    core = np.exp(-(r / 0.08) ** 2)
    glow = np.exp(-(r / 0.35) ** 2) * 0.45
    spikes = np.zeros_like(r)
    for k, (count, width, length) in enumerate([(4, 0.012, 1.0), (4, 0.02, 0.55)]):
        off = math.pi / 4 * k
        for i in range(count):
            a = off + i * math.pi * 2 / count
            along = x * math.cos(a) + y * math.sin(a)
            across = -x * math.sin(a) + y * math.cos(a)
            spikes += (along > 0) * np.exp(-(across / (width * (1 + 3 * along))) ** 2) * np.clip(1 - along / length, 0, 1) ** 1.5
    alpha = np.clip(core + glow + spikes, 0, 1)
    save("Flare.png", np.ones_like(alpha), alpha)


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    swirl()
    wind()
    foam()
    water()
    shock()
    flare()
