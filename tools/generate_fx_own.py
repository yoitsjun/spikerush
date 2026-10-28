#!/usr/bin/env python3
"""Our own particle textures for Fx.lua, replacing the 26 Creator Store sprites and flipbooks
other creators made (2026-10-28). Procedural; same slot names and layouts as before, so Fx.lua's
kits play them unchanged:

  single 256 px:  Glow Dot Sparkle Glint Specks Streak Ring SpikyRing Radial HitStar HitBurst
                  Slash GroundWave DustRing Bolt Bolt2 Rock Crater
  4x4 flipbooks:  Fire Fireball Smoke Electric HitRing Crack FireWhite   (16 frames of 256)
  2x2 flipbook:   Arcs                                                     (4 frames of 512)

White on clear (the game tints them), except Fire, Fireball and Rock, which carry their own
colours (their kits don't tint). Written to assets/fx/own.

    python3 tools/generate_fx_own.py
"""
import math
import random
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "assets" / "fx" / "own"
N = 256


# ------------------------------------------------------------------------------------ helpers

def noise(n, cells, seed, octaves=4, shift=(0.0, 0.0)):
    """Tileable value noise in 0..1 (fbm)."""
    r = np.random.default_rng(seed)
    out = np.zeros((n, n))
    amp, total = 1.0, 0.0
    for o in range(octaves):
        c = cells * (2 ** o)
        grid = r.random((c + 1, c + 1))
        grid[-1, :] = grid[0, :]
        grid[:, -1] = grid[:, 0]
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


def coords(n=N):
    """x, y in -1..1 (y up), r, angle."""
    ys, xs = np.mgrid[0:n, 0:n].astype(float)
    x = (xs + 0.5) / n * 2 - 1
    y = 1 - (ys + 0.5) / n * 2
    return x, y, np.hypot(x, y), np.arctan2(y, x)


def smooth(e0, e1, v):
    t = np.clip((v - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)


def white(alpha, shade=None):
    a = np.clip(alpha, 0, 1)
    rgb = np.ones(a.shape + (3,)) if shade is None else np.repeat(np.clip(shade, 0, 1)[..., None], 3, axis=2)
    return np.dstack([rgb, a])


def save(name, rgba):
    OUT.mkdir(parents=True, exist_ok=True)
    Image.fromarray((np.clip(rgba, 0, 1) * 255).astype(np.uint8), "RGBA").save(OUT / (name + ".png"))
    print("wrote", name)


def sheet(name, frames, grid=4):
    n = frames[0].shape[0]
    out = np.zeros((n * grid, n * grid, 4))
    for i, f in enumerate(frames):
        r, c = divmod(i, grid)
        out[r * n:(r + 1) * n, c * n:(c + 1) * n] = f
    save(name, out)


def toon(v, thr, core):
    """A cel look: alpha where v > thr, a white core above `core`, a grey band between."""
    a = smooth(thr - 0.02, thr + 0.02, v)
    shade = 0.62 + 0.38 * smooth(core - 0.02, core + 0.02, v)
    return a, shade


def pil_layer(n, draw_fn, blur=0):
    img = Image.new("L", (n, n), 0)
    draw_fn(ImageDraw.Draw(img))
    if blur:
        img = img.filter(ImageFilter.GaussianBlur(blur))
    return np.asarray(img, dtype=float) / 255


def jagged(p0, p1, rnd, depth=6, rough=0.28):
    """Midpoint-displaced lightning path from p0 to p1."""
    pts = [p0, p1]
    for _ in range(depth):
        new = [pts[0]]
        for a, b in zip(pts, pts[1:]):
            mx, my = (a[0] + b[0]) / 2, (a[1] + b[1]) / 2
            dx, dy = b[0] - a[0], b[1] - a[1]
            L = math.hypot(dx, dy)
            off = rnd.uniform(-rough, rough) * L
            new += [(mx - dy / (L + 1e-9) * off, my + dx / (L + 1e-9) * off), b]
        pts = new
    return pts


def bolt_layers(n, paths, core_w, glow_w):
    core = pil_layer(n, lambda d: [d.line(p, fill=255, width=w, joint="curve") for p, w in paths])
    halo = pil_layer(n, lambda d: [d.line(p, fill=255, width=int(w * glow_w), joint="curve") for p, w in paths], blur=n / 60)
    return core, halo


# ------------------------------------------------------------------------------- single sprites

def glow():
    _, _, r, _ = coords()
    save("Glow", white(np.exp(-(r / 0.42) ** 2) * (r < 1)))


def dot():
    _, _, r, _ = coords()
    save("Dot", white(smooth(0.55, 0.2, r)))


def sparkle():
    x, y, r, _ = coords()
    star = (np.abs(x) ** 0.6 + np.abs(y) ** 0.6) ** (1 / 0.6)
    a = smooth(0.95, 0.75, star) + np.exp(-(r / 0.22) ** 2)
    save("Sparkle", white(a, 0.8 + 0.2 * smooth(0.5, 0.1, star)))


def glint():
    x, y, r, _ = coords()
    h = np.exp(-(y / 0.025) ** 2) * (1 - np.abs(x)) ** 2
    v = np.exp(-(x / 0.025) ** 2) * (1 - np.abs(y)) ** 2
    save("Glint", white(np.maximum(h, v) + np.exp(-(r / 0.09) ** 2)))


def specks():
    rnd = random.Random(4)
    x, y, _, _ = coords()
    a = np.zeros_like(x)
    for _ in range(26):
        cx, cy, s = rnd.uniform(-0.85, 0.85), rnd.uniform(-0.85, 0.85), rnd.uniform(0.03, 0.11)
        dx, dy = np.abs(x - cx) / s, np.abs(y - cy) / s
        star = (dx ** 0.6 + dy ** 0.6) ** (1 / 0.6)
        a = np.maximum(a, smooth(1.0, 0.6, star))
    save("Specks", white(a))


def streak():
    x, y, _, _ = coords()
    t = (x + 1) / 2  # 0 tail .. 1 head
    width = 0.02 + 0.14 * t ** 1.6
    a = np.exp(-(y / width) ** 2) * smooth(0.0, 0.25, t) * smooth(1.0, 0.9, t)
    save("Streak", white(a, 0.75 + 0.25 * np.exp(-(y / (width * 0.4)) ** 2)))


def ring():
    _, _, r, _ = coords()
    save("Ring", white(np.exp(-((r - 0.86) / 0.035) ** 2)))


def spiky_ring():
    _, _, r, th = coords()
    rnd = np.random.default_rng(8)
    k = np.arange(1, 25)
    amp, ph = rnd.random(24) / k ** 0.6, rnd.random(24) * 2 * math.pi
    wob = sum(amp[i] * np.cos(k[i] * th + ph[i]) for i in range(24))
    edge = 0.8 + 0.07 * wob / np.abs(wob).max()
    spikes = 0.1 * np.clip(np.cos(17 * th + 0.5) , 0, 1) ** 6
    outer = edge + spikes
    a = smooth(outer, outer - 0.03, r) * smooth(outer - 0.3, outer - 0.06, r)
    save("SpikyRing", white(a, 0.7 + 0.3 * smooth(outer - 0.15, outer - 0.03, r)))


def radial():
    _, _, r, th = coords()
    rnd = random.Random(12)
    a = np.zeros_like(r)
    for _ in range(64):
        c = rnd.uniform(-math.pi, math.pi)
        w = rnd.uniform(0.004, 0.014)
        r0, r1 = rnd.uniform(0.45, 0.7), rnd.uniform(0.82, 0.99)
        d = np.angle(np.exp(1j * (th - c)))
        line = np.exp(-(d / w) ** 2) * smooth(r0, r0 + 0.08, r) * smooth(r1, r1 - 0.05, r)
        a = np.maximum(a, line)
    save("Radial", white(a))


def star_poly(n, cx, cy, spikes, r_out, r_in, rnd, jitter=0.25):
    pts = []
    for i in range(spikes * 2):
        a = -math.pi / 2 + i * math.pi / spikes + rnd.uniform(-0.08, 0.08)
        r = r_out * rnd.uniform(1 - jitter, 1) if i % 2 == 0 else r_in * rnd.uniform(0.85, 1.1)
        pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    return pts


def hit_star():
    n = N * 4
    rnd = random.Random(3)
    outer = star_poly(n, n / 2, n / 2, 11, n * 0.48, n * 0.22, rnd, 0.35)
    inner = star_poly(n, n / 2, n / 2, 11, n * 0.3, n * 0.14, random.Random(5), 0.3)
    a = pil_layer(n, lambda d: d.polygon(outer, fill=255))
    core = pil_layer(n, lambda d: d.polygon(inner, fill=255))
    rgba = white(a, 0.7 + 0.3 * core)
    save("HitStar", np.asarray(Image.fromarray((rgba * 255).astype(np.uint8), "RGBA").resize((N, N), Image.LANCZOS)) / 255)


def hit_burst():
    x, y, r, th = coords()
    rnd = np.random.default_rng(9)
    a = np.zeros_like(r)
    for i in range(30):
        c = i / 30 * 2 * math.pi + rnd.uniform(-0.08, 0.08)
        L = rnd.uniform(0.6, 0.98)
        d = np.angle(np.exp(1j * (th - c)))
        width = 0.09 * (1 - r / L)
        a = np.maximum(a, (np.abs(d) < width) * (r < L))
    a = np.maximum(a, smooth(0.32, 0.26, r))
    a = np.array(Image.fromarray((a * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(0.8)), dtype=float) / 255
    save("HitBurst", white(a, 0.75 + 0.25 * smooth(0.45, 0.2, r)))


def slash():
    x, y, r, _ = coords()
    outer = np.hypot(x, y + 0.35) < 0.95
    inner = np.hypot(x - 0.08, y + 0.6) < 1.0
    band = outer & ~inner & (y > -0.3)
    taper = smooth(-0.95, -0.2, x) * smooth(0.95, 0.2, x)
    a = band * taper
    a = np.array(Image.fromarray((a * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(1.2)), dtype=float) / 255
    save("Slash", white(a, 0.7 + 0.3 * smooth(-0.1, 0.2, y)))


def ground_wave():
    _, _, r, _ = coords()
    a = (r / 0.9) ** 3 * smooth(0.93, 0.88, r) * 0.85 + np.exp(-((r - 0.88) / 0.025) ** 2) * 0.6
    save("GroundWave", white(a))


def dust_ring():
    x, y, r, th = coords()
    nz = noise(N, 6, 21)
    band = np.exp(-((r - 0.72) / 0.16) ** 2)
    a = band * smooth(0.35, 0.65, nz) * smooth(0.98, 0.9, r)
    save("DustRing", white(a, 0.75 + 0.25 * nz))


def bolt(name, seed, branches):
    n = N * 2
    rnd = random.Random(seed)
    main = jagged((n * 0.5, n * 0.02), (n * 0.5, n * 0.98), rnd, depth=6, rough=0.22)
    paths = [(main, 9)]
    for _ in range(branches):
        i = rnd.randrange(len(main) // 5, len(main) * 4 // 5)
        sx, sy = main[i]
        ex, ey = sx + rnd.choice((-1, 1)) * rnd.uniform(0.15, 0.32) * n, sy + rnd.uniform(0.1, 0.25) * n
        paths.append((jagged((sx, sy), (ex, ey), rnd, depth=4, rough=0.3), 4))
    core, halo = bolt_layers(n, paths, 9, 4)
    a = np.maximum(core, halo * 0.7)
    img = Image.fromarray((white(a, 0.75 + 0.25 * core) * 255).astype(np.uint8), "RGBA").resize((N, N), Image.LANCZOS)
    save(name, np.asarray(img) / 255)


def rock():
    n = N
    rnd = random.Random(6)
    pts = []
    for i in range(9):
        a = i / 9 * 2 * math.pi + rnd.uniform(-0.2, 0.2)
        rr = n * rnd.uniform(0.32, 0.46)
        pts.append((n / 2 + rr * math.cos(a), n / 2 + rr * math.sin(a)))
    a = pil_layer(n, lambda d: d.polygon(pts, fill=255))
    x, y, _, _ = coords(n)
    light = np.clip(0.55 + 0.35 * (-x * 0.6 + y * 0.8), 0, 1)
    nz = noise(n, 8, 31)
    base = np.array([118, 104, 92]) / 255
    rgb = base[None, None, :] * (0.6 + 0.6 * light[..., None]) * (0.8 + 0.4 * nz[..., None])
    edge = a - np.asarray(Image.fromarray((a * 255).astype(np.uint8)).filter(ImageFilter.MinFilter(7)), dtype=float) / 255
    rgb = rgb * (1 - 0.7 * edge[..., None])
    save("Rock", np.dstack([np.clip(rgb, 0, 1), a]))


def crater():
    n = N * 2
    x, y, r, th = coords(n)
    nz = noise(n, 6, 41)
    bowl = smooth(0.62, 0.55, r)
    rim = np.exp(-((r - 0.62 - 0.04 * (nz - 0.5)) / 0.07) ** 2)
    rnd = random.Random(2)
    cracks = pil_layer(n, lambda d: [d.line(jagged((n / 2, n / 2), (n / 2 + math.cos(a) * n * rnd.uniform(0.38, 0.49), n / 2 + math.sin(a) * n * rnd.uniform(0.38, 0.49)), rnd, depth=5, rough=0.18), fill=255, width=6)
                                     for a in [i / 9 * 2 * math.pi + rnd.uniform(-0.2, 0.2) for i in range(9)]])
    a = np.clip(bowl * 0.75 + rim * 0.9 + cracks, 0, 1) * smooth(0.99, 0.9, r)
    shade = np.clip(0.45 + 0.35 * nz + 0.4 * rim - 0.25 * cracks, 0, 1)
    img = Image.fromarray((white(a, shade) * 255).astype(np.uint8), "RGBA").resize((N, N), Image.LANCZOS)
    save("Crater", np.asarray(img) / 255)


# ----------------------------------------------------------------------------------- flipbooks

FIRE_RAMP = [(0.0, (0.55, 0.06, 0.02)), (0.35, (0.95, 0.27, 0.04)), (0.62, (1.0, 0.62, 0.1)), (0.85, (1.0, 0.92, 0.55)), (1.0, (1.0, 1.0, 0.92))]


def ramp(v, stops):
    v = np.clip(v, 0, 1)
    out = np.zeros(v.shape + (3,))
    for (t0, c0), (t1, c1) in zip(stops, stops[1:]):
        m = (v >= t0) & (v <= t1)
        f = ((v - t0) / (t1 - t0))[..., None]
        out[m] = (np.array(c0) * (1 - f) + np.array(c1) * f)[m]
    return out


def flame_field(t, seed, n=N):
    """A flame puff: blooms from the bottom, rises and licks, then burns away (t 0..1)."""
    x, y, _, _ = coords(n)
    nz = noise(n, 4, seed, shift=(0.0, -t * 0.9))
    fine = noise(n, 9, seed + 1, shift=(0.0, -t * 1.6))
    grow = 0.35 + 0.55 * min(1.0, t * 2.2)
    cy = -0.35 + 0.45 * t
    # a teardrop: wide at the bottom, a tip licking up
    dx = x / (grow * (0.75 - 0.35 * np.clip((y - cy) / grow, 0, 1)))
    dy = (y - cy) / (grow * 1.25)
    shape = 1 - np.hypot(dx, np.where(dy > 0, dy * 0.7, dy * 1.25))
    v = shape + (nz - 0.5) * 0.7 + (fine - 0.5) * 0.25
    burn = 0.08 + 0.75 * max(0.0, t - 0.35) / 0.65
    return v - burn


def fire():
    frames = []
    for i in range(16):
        t = i / 15
        v = flame_field(t, 51)
        a = smooth(0.0, 0.04, v)
        heat = np.clip(v / 0.55, 0, 1) * (1 - 0.5 * t)
        # cel bands: snap the heat to four steps
        heat = np.floor(heat * 4 + 0.5) / 4
        rgb = ramp(0.2 + 0.8 * heat, FIRE_RAMP)
        frames.append(np.dstack([rgb, a]))
    sheet("Fire", frames)


def fire_white():
    frames = []
    for i in range(16):
        t = i / 15
        v = flame_field(t, 77)
        a, shade = toon(v, 0.0, 0.28 - 0.15 * t)
        frames.append(white(a, shade))
    sheet("FireWhite", frames)


def fireball():
    frames = []
    x, y, r, _ = coords()
    for i in range(16):
        t = i / 15
        nz = noise(N, 4, 61, shift=(t * 0.3, -t * 0.5))
        rad = 0.35 + 0.5 * (1 - (1 - t) ** 2)
        v = 1 - r / rad + (nz - 0.5) * 0.8
        a = smooth(0.0, 0.05, v - 0.55 * max(0.0, t - 0.5) / 0.5)
        heat = np.clip(v * (1.3 - 1.4 * t), 0, 1)
        heat = np.floor(heat * 4 + 0.5) / 4
        rgb = ramp(heat, FIRE_RAMP)
        smoke = np.array([0.22, 0.2, 0.2])
        k = smooth(0.35, 0.9, t) * (1 - heat)[..., None]
        rgb = rgb * (1 - k) + smoke * k
        frames.append(np.dstack([rgb, a]))
    sheet("Fireball", frames)


def smoke():
    frames = []
    x, y, r, _ = coords()
    for i in range(16):
        t = i / 15
        v = np.full_like(r, -1.0)
        rnd = random.Random(71)
        for _ in range(6):
            cx, cy, s = rnd.uniform(-0.28, 0.28), rnd.uniform(-0.3, 0.15), rnd.uniform(0.3, 0.42)
            s *= 0.75 + 0.6 * t
            cy += 0.25 * t
            v = np.maximum(v, 1 - np.hypot(x - cx, y - cy) / s)
        nz = noise(N, 5, 73, shift=(0.0, -t * 0.4))
        v = v + (nz - 0.5) * 0.45 * smooth(-0.3, 0.1, v) - 0.7 * t ** 1.5
        a, shade = toon(v, 0.05, 0.35)
        frames.append(white(a, shade))
    sheet("Smoke", frames)


def electric():
    frames = []
    for i in range(16):
        rnd = random.Random(800 + i)
        n = N
        paths = []
        for _ in range(rnd.randint(3, 5)):
            a = rnd.uniform(0, 2 * math.pi)
            L = rnd.uniform(0.32, 0.48) * n
            p = jagged((n / 2, n / 2), (n / 2 + math.cos(a) * L, n / 2 + math.sin(a) * L), rnd, depth=5, rough=0.35)
            paths.append((p, rnd.choice((3, 4))))
        core, halo = bolt_layers(n, paths, 4, 4)
        fade = 1 - 0.5 * (i % 4) / 3
        a = np.maximum(core, halo * 0.6) * fade
        frames.append(white(a, 0.75 + 0.25 * core))
    sheet("Electric", frames)


def hit_ring():
    frames = []
    _, _, r, th = coords()
    breakup = noise(N, 3, 91)
    seg = np.cos(th * 9 + breakup * 6)
    for i in range(16):
        t = i / 15
        rad = 0.25 + 0.65 * (1 - (1 - t) ** 2)
        w = 0.12 * (1 - t) + 0.015
        a = np.exp(-((r - rad) / w) ** 2)
        gap = -1.3 + 2.1 * t ** 1.4
        a = a * smooth(gap, gap + 0.3, seg)  # whole at first; gaps open up as it rings out
        frames.append(white(a * (1 - 0.3 * t), 0.7 + 0.3 * np.exp(-((r - rad) / (w * 0.4)) ** 2)))
    sheet("HitRing", frames)


def crack():
    n = N * 2
    rnd = random.Random(13)
    arms = []
    for k in range(7):
        a = k / 7 * 2 * math.pi + rnd.uniform(-0.25, 0.25)
        L = rnd.uniform(0.36, 0.48) * n
        main = jagged((n / 2, n / 2), (n / 2 + math.cos(a) * L, n / 2 + math.sin(a) * L), rnd, depth=5, rough=0.2)
        arms.append((main, 7))
        for _ in range(2):
            j = rnd.randrange(len(main) // 3, len(main) - 2)
            sx, sy = main[j]
            b = a + rnd.choice((-1, 1)) * rnd.uniform(0.5, 1.0)
            arms.append((jagged((sx, sy), (sx + math.cos(b) * L * 0.35, sy + math.sin(b) * L * 0.35), rnd, depth=4, rough=0.25), 4))
    frames = []
    for i in range(16):
        grow = min(1.0, (i + 1) / 8)  # spreads over the first half, then holds

        def draw(d):
            for path, w in arms:
                m = max(2, int(len(path) * grow))
                d.line(path[:m], fill=255, width=w, joint="curve")
        core = pil_layer(n, draw)
        halo = pil_layer(n, draw, blur=n / 80)
        a = np.maximum(core, halo * 0.5)
        img = Image.fromarray((white(a, 0.7 + 0.3 * core) * 255).astype(np.uint8), "RGBA").resize((N, N), Image.LANCZOS)
        frames.append(np.asarray(img) / 255)
    sheet("Crack", frames)


def arcs():
    n = 512
    frames = []
    for i in range(4):
        rnd = random.Random(500 + i)
        paths = []
        for _ in range(3):
            a0 = rnd.uniform(0, 2 * math.pi)
            a1 = a0 + rnd.uniform(1.2, 2.4)
            R = rnd.uniform(0.3, 0.44) * n
            mid = (a0 + a1) / 2
            pts = [(n / 2 + R * math.cos(a), n / 2 + R * math.sin(a)) for a in (a0, mid, a1)]
            path = jagged(pts[0], pts[1], rnd, depth=4, rough=0.3)[:-1] + jagged(pts[1], pts[2], rnd, depth=4, rough=0.3)
            paths.append((path, 5))
        core, halo = bolt_layers(n, paths, 5, 4)
        a = np.maximum(core, halo * 0.6)
        frames.append(white(a, 0.75 + 0.25 * core))
    sheet("Arcs", frames, grid=2)


def main():
    glow(); dot(); sparkle(); glint(); specks(); streak(); ring(); spiky_ring(); radial()
    hit_star(); hit_burst(); slash(); ground_wave(); dust_ring()
    bolt("Bolt", 1, 2); bolt("Bolt2", 2, 4); rock(); crater()
    fire(); fire_white(); fireball(); smoke(); electric(); hit_ring(); crack(); arcs()


if __name__ == "__main__":
    main()
