"""Toon flipbooks for the particle effects (the owner: "make them look more similar to blox fruits"):
animated sheets a ParticleEmitter plays through (Flipbook Grid4x4, OneShot), in the anime style of
Blox Fruits' fire, smoke and lightning: each frame a bold blob with a white core and a grey band,
blooming, breaking up and dissolving. Our own, procedural; white and grey (the game tints them).

  fx_fb_fire.png     a fire puff: blooms, rises, licks and burns away
  fx_fb_smoke.png    a cel-shaded smoke puff: billows and erodes
  fx_fb_spark.png    a four-pointed star glint: flares and shrinks
  fx_fb_electric.png a crackle of jagged bolts, new ones every frame
  fx_fb_burst.png    an impact burst: a spiky star blast that rings out

Each is 1024x1024, 16 frames of 256. Written to art/tex.
Run: python tools/generate_fx_flipbooks.py
"""
from pathlib import Path
import math, random

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

S = 256  # one frame
OUT = Path(__file__).resolve().parent.parent / "art" / "tex"


def noise(n, cells, seed, octaves=3, shift=(0.0, 0.0)):
    r = np.random.default_rng(seed)
    out = np.zeros((n, n))
    amp, total = 1.0, 0.0
    for o in range(octaves):
        c = cells * (2 ** o)
        grid = r.random((c + 1, c + 1))
        ys = (np.linspace(0, c, n, endpoint=False) + shift[1] * c) % c
        xs = (np.linspace(0, c, n, endpoint=False) + shift[0] * c) % c
        y0, x0 = np.floor(ys).astype(int), np.floor(xs).astype(int)
        fy, fx = ys - y0, xs - x0
        fy, fx = fy * fy * (3 - 2 * fy), fx * fx * (3 - 2 * fx)
        a = grid[y0][:, x0] * (1 - fx) + grid[y0][:, x0 + 1] * fx
        b = grid[y0 + 1][:, x0] * (1 - fx) + grid[y0 + 1][:, x0 + 1] * fx
        out += (a * (1 - fy)[:, None] + b * fy[:, None]) * amp
        total += amp
        amp *= 0.5
    return out / total


yy, xx = np.mgrid[0:S, 0:S]
X = (xx / (S - 1) - 0.5) * 2
Y = (0.5 - yy / (S - 1)) * 2  # up is +


def frame_rgba(alpha, shade):
    rgb = np.clip(shade, 0, 1)[..., None].repeat(3, axis=2)
    return np.dstack([rgb, np.clip(alpha, 0, 1)[..., None]])


def sheet(name, frames):
    out = np.zeros((S * 4, S * 4, 4))
    for i, f in enumerate(frames[:16]):
        r, c = divmod(i, 4)
        out[r * S:(r + 1) * S, c * S:(c + 1) * S] = f
    OUT.mkdir(parents=True, exist_ok=True)
    Image.fromarray((out * 255).astype(np.uint8), "RGBA").save(OUT / name)
    print("wrote", OUT / name)


def toon(value, thr, core):
    alpha = (value > thr).astype(float)
    shade = np.where(value > thr + core, 1.0, 0.6)
    return frame_rgba(alpha, shade)


# fire: a blob that rises and stretches, its edge licked by noise, eroding from the outside in
fire = []
for t in range(16):
    k = t / 15
    n = noise(S, 4, 1, shift=(0, -k * 1.2))
    n2 = noise(S, 8, 2, shift=(0.1 * k, -k * 2.0))
    lift = 0.35 * k
    r = np.sqrt((X / (0.85 - 0.25 * k)) ** 2 + ((Y + 0.35 - lift) / (1.0 + 0.6 * k)) ** 2)
    tongues = 0.35 * np.clip(Y + 0.2, 0, 2) * (n2 - 0.5)
    value = (1 - r) + 0.55 * (n - 0.5) + tongues
    fire.append(toon(value, 0.02 + 0.55 * k ** 1.4, 0.32 - 0.12 * k))
sheet("fx_fb_fire.png", fire)

# smoke: a round cel-shaded puff, billowing out and eroding, light on top, grey underneath
smoke = []
for t in range(16):
    k = t / 15
    n = noise(S, 3, 3, shift=(0.05 * k, -0.3 * k))
    r = np.sqrt(X ** 2 + (Y * 1.1) ** 2) / (0.6 + 0.35 * k)
    value = (1 - r) + 0.5 * (n - 0.5)
    thr = 0.02 + 0.6 * k ** 1.6
    alpha = (value > thr).astype(float)
    shade = np.where(Y + 0.3 * (n - 0.5) > -0.15, 1.0, 0.68)
    smoke.append(frame_rgba(alpha, shade))
sheet("fx_fb_smoke.png", smoke)

# spark: a four-pointed star that flares then shrinks, with a round core
spark = []
for t in range(16):
    k = t / 15
    size = math.sin(min(1, k * 2.2) * math.pi / 2) * (1 - k) ** 0.8
    ax, ay = np.abs(X), np.abs(Y)
    star = 1 - (np.sqrt(ax) + np.sqrt(ay)) / max(size * 1.3, 1e-3)
    core = 1 - np.sqrt(X ** 2 + Y ** 2) / max(size * 0.35, 1e-3)
    value = np.maximum(star, core)
    spark.append(toon(value, 0.0, 0.35))
sheet("fx_fb_spark.png", spark)

# electric: jagged bolts from the middle out, redrawn every frame, white core in a grey glow
electric = []
rnd = random.Random(11)
for t in range(16):
    k = t / 15
    img = Image.new("L", (S, S), 0)
    core = Image.new("L", (S, S), 0)
    d, dc = ImageDraw.Draw(img), ImageDraw.Draw(core)
    for b in range(4 if k < 0.7 else 2):
        a = rnd.uniform(0, 6.28)
        pts = [(S / 2, S / 2)]
        x, y = S / 2, S / 2
        for s in range(6):
            a += rnd.uniform(-0.9, 0.9)
            step = S * 0.08 * (1 + 0.6 * (1 - k))
            x, y = x + math.cos(a) * step, y + math.sin(a) * step
            pts.append((x, y))
        d.line(pts, fill=255, width=14)
        dc.line(pts, fill=255, width=5)
    glow = np.asarray(img.filter(ImageFilter.MaxFilter(3))) / 255
    c = np.asarray(core) / 255
    fade = 1 - max(0, k - 0.6) / 0.4
    alpha = (glow > 0.5) * fade
    shade = np.where(c > 0.5, 1.0, 0.6)
    electric.append(frame_rgba(alpha, shade))
sheet("fx_fb_electric.png", electric)

# burst: a spiky star blast ringing out (a hit spark), its spikes thinning as it grows
burst = []
ang = np.arctan2(Y, X)
rad = np.sqrt(X ** 2 + Y ** 2)
spikes = (0.5 + 0.5 * np.cos(ang * 9 + 0.7 * np.cos(ang * 4))) ** 3
for t in range(16):
    k = t / 15
    outer = 0.25 + 0.8 * k ** 0.6
    inner = max(0.0, (k - 0.25) * 1.1) * outer
    value = np.where(rad < outer * (0.55 + 0.45 * spikes), 1.0, 0.0) * (rad > inner)
    shade = np.where(rad < outer * (0.55 + 0.45 * spikes) * 0.7, 1.0, 0.6)
    burst.append(frame_rgba(value * (1 - max(0, k - 0.8) / 0.2), shade))
sheet("fx_fb_burst.png", burst)
