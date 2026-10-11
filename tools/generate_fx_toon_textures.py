"""Toon versions of the effect textures (the owner: "match it more closely to blox fruits"): bold,
mostly opaque shapes with hard-edged bands instead of soft noise, so the effects read crisp and
bright like Blox Fruits' (anime fire tongues, clean slashes, hard rings). White and grey only: the
game tints them. Written over art/tex/*.png (the soft originals stay reproducible with
generate_fx_mesh_textures.py).

Run: python tools/generate_fx_toon_textures.py
"""
from pathlib import Path

import numpy as np
from PIL import Image

N = 512
OUT = Path(__file__).resolve().parent.parent / "art" / "tex"


def smooth_noise(n, cells, octaves=3, seed=0):
    r = np.random.default_rng(seed)
    out = np.zeros((n, n))
    amp, total = 1.0, 0.0
    for o in range(octaves):
        c = cells * (2 ** o)
        grid = r.random((c, c))
        ys = np.linspace(0, c, n, endpoint=False)
        y0 = np.floor(ys).astype(int)
        f = ys - y0
        f = f * f * (3 - 2 * f)
        y1 = (y0 + 1) % c
        rows = grid[y0] * (1 - f)[:, None] + grid[y1] * f[:, None]
        layer = rows[:, y0] * (1 - f)[None, :] + rows[:, y1] * f[None, :]
        out += layer * amp
        total += amp
        amp *= 0.5
    return out / total


def bands(x, cuts, levels):
    """posterize x into hard bands: below cuts[0] -> levels[0], ..."""
    out = np.full_like(x, levels[0])
    for c, l in zip(cuts, levels[1:]):
        out = np.where(x >= c, l, out)
    return out


def save(name, alpha, shade):
    rgb = np.clip(shade, 0, 1)[..., None].repeat(3, axis=2)
    img = np.dstack([rgb, np.clip(alpha, 0, 1)[..., None]]) * 255
    OUT.mkdir(parents=True, exist_ok=True)
    Image.fromarray(img.astype(np.uint8), "RGBA").save(OUT / name)
    print("wrote", OUT / name)


u = np.linspace(0, 1, N)[None, :].repeat(N, axis=0)
v = np.linspace(1, 0, N)[:, None].repeat(N, axis=1)

# a flame: three overlapping tongues (a tall centre, two shorter curling sides), each a bold white
# core inside a grey band, hard edges (anime fire)
n1 = smooth_noise(N, 3, seed=1)


def tongue(cx, h, w, curl):
    vv = v / h
    x = u - cx - curl * vv ** 1.5 - 0.04 * (n1 - 0.5)
    wid = w * np.clip(1 - vv, 0, 1) ** 0.75 * np.clip(vv * 6, 0, 1) ** 0.3 + 1e-3
    return np.where(vv < 1, 1 - np.abs(x) / wid, -1)


body = np.maximum.reduce([tongue(0.5, 0.98, 0.34, 0.0), tongue(0.33, 0.72, 0.2, -0.1), tongue(0.67, 0.66, 0.2, 0.12)])
alpha = bands(body, [0.0], [0.0, 1.0])
shade = bands(body, [0.0, 0.42], [0.0, 0.62, 1.0])
save("fx_wisp.png", alpha, shade)

# a slash: a crisp crescent band, white leading edge, grey trailing band, cut ends
lead = v
alpha = bands(lead, [0.35], [0.0, 1.0]) * (np.sin(np.pi * u) > 0.08)
shade = bands(lead, [0.35, 0.72], [0.0, 0.6, 1.0])
save("fx_slash.png", alpha, shade)

# a shock ring: a hard white outer band and a thinner grey inner band
alpha = bands(v, [0.55], [0.0, 1.0])
shade = bands(v, [0.55, 0.8], [0.0, 0.55, 1.0])
save("fx_ring.png", alpha, shade)

# a dome shell: a bright rim band, a grey band above it, clear at the top
alpha = bands(1 - v, [0.55], [0.0, 1.0])
shade = bands(1 - v, [0.55, 0.85], [0.0, 0.5, 1.0])
save("fx_shell.png", alpha, shade)

# lightning: a white core, a grey glow band, hard edges
d = np.abs(v - 0.5) * 2
alpha = bands(1 - d, [0.35], [0.0, 1.0])
shade = bands(1 - d, [0.35, 0.7], [0.0, 0.6, 1.0])
save("fx_bolt.png", alpha, shade)

# a column of light: hard vertical streaks
cols = smooth_noise(N, 5, octaves=2, seed=9)
alpha = bands(cols * np.sin(np.pi * u), [0.32], [0.0, 1.0])
shade = bands(cols, [0.0, 0.55], [0.0, 0.65, 1.0])
save("fx_beam.png", alpha, shade)

# wind streaks: hard bands
lines = smooth_noise(N, 3, octaves=2, seed=7)
s = np.sin((v * 6 + lines * 2) * np.pi) * np.sin(np.pi * v)
alpha = bands(s, [0.45], [0.0, 1.0])
shade = bands(s, [0.45, 0.75], [0.0, 0.65, 1.0])
save("fx_swirl.png", alpha, shade)

# a speed-line bubble: hard streaks
streaks = smooth_noise(N, 10, octaves=2, seed=17)[:, :1].repeat(N, axis=1)
alpha = bands(streaks, [0.62], [0.0, 0.85])
save("fx_bubble.png", alpha, np.ones((N, N)))

# a smoke puff: a cel-shaded cloud, light top, grey underside, hard lumpy edge
x = (u - 0.5) * 2
y = (v - 0.5) * 2
rad = np.sqrt(x * x + y * y)
puff = smooth_noise(N, 3, octaves=3, seed=18)
body = 0.78 + 0.3 * (puff - 0.5) - rad
alpha = bands(body, [0.0], [0.0, 1.0])
shade = np.where(y + 0.25 * (puff - 0.5) > -0.1, 1.0, 0.72)
save("fx_smoke.png", alpha, shade)

# scorch: a hard-edged burnt blot with a darker inner band
blot = smooth_noise(N, 4, octaves=3, seed=13)
body = 0.62 + 0.3 * (blot - 0.5) - rad
alpha = bands(body, [0.0, 0.18], [0.0, 0.75, 1.0])
save("fx_scorch.png", alpha, np.ones((N, N)))
