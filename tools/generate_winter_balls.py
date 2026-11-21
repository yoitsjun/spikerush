"""Draws the Winter collab's ball skins into assets/balls: equirectangular maps (1024x512) for the
UV sphere the other texture balls use (tools/generate_ball_skins.py, whose helpers these borrow).

  Snowflake.png   pale ice with a white six-armed snowflake on every side, frost between them
  Ornament.png    a glossy red bauble: a gold band with white points round its middle, a gold cap
  Snowball.png    packed snow: white, lumpy, faint blue in the hollows
  Peppermint.png  a peppermint sweet: red and white stripes swirling pole to pole, thin green ones
  Gift.png        a wrapped present: green paper with small white stars, a red ribbon both ways and a bow

Run with any Python 3 that has numpy and Pillow:  python3 tools/generate_winter_balls.py
"""

import math
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import generate_ball_skins as B  # noqa: E402

DX, DY, DZ, LON, LAT, H, W = B.DX, B.DY, B.DZ, B.LON, B.LAT, B.H, B.W
rgb, frame, wrap, noise3, save = B.rgb, B.frame, B.wrap, B.noise3, B.save


def mix(img, color, amount):
    """Blend `color` over img by `amount` (0..1 per pixel)."""
    a = np.clip(amount, 0, 1)[..., None]
    return img * (1 - a) + rgb(color) * a


def soft(d, w, edge=0.004):
    """1 inside a line of half-width w (d: the distance to its middle), feathered at the edge."""
    return np.clip((w - d) / edge, 0, 1)


def snowflake_at(axis, size):
    """A six-armed snowflake centred on `axis` (0..1 coverage), `size` its arms' length in radians."""
    theta, phi = frame(axis)
    # fold the six arms onto one, and that arm's two sides onto one
    sector = math.pi / 3
    a = np.abs((phi + sector / 2) % sector - sector / 2)
    x, y = theta * np.cos(a), theta * np.sin(a)
    out = soft(y, size * 0.045) * (x < size)
    # two pairs of branches up the arm, the outer shorter, each leaning out at 60 degrees
    for at, length in ((0.42, 0.34), (0.7, 0.2)):
        bx, by = x - size * at, y
        along = bx * math.cos(sector) + by * math.sin(sector)
        across = np.abs(-bx * math.sin(sector) + by * math.cos(sector))
        out = np.maximum(out, soft(across, size * 0.036) * (along > 0) * (along < size * length))
    # a small hexagon ring round the middle, and the tips rounded off
    out = np.maximum(out, soft(np.abs(theta - size * 0.17), size * 0.03))
    return np.clip(out, 0, 1) * (theta < size * 1.05)


def snowflake():
    ice, deep, white = rgb((168, 222, 255)), rgb((70, 150, 236)), (255, 255, 255)
    # pale ice, deeper blue in slow drifts, a fine frost over it
    drift = noise3(DX, DY, DZ, 2.2, 7)
    img = ice[None, None, :] * (1 - 0.55 * drift[..., None]) + deep[None, None, :] * (0.55 * drift[..., None])
    frost = noise3(DX, DY, DZ, 55, 23)
    img = mix(img, white, np.clip((frost - 0.62) * 3.2, 0, 1) * 0.5)
    # a big snowflake on each of the six sides, a small one on each of the eight corners between
    flakes = np.zeros_like(DX)
    for axis in ((1, 0, 0), (-1, 0, 0), (0, 1, 0), (0, -1, 0), (0, 0, 1), (0, 0, -1)):
        flakes = np.maximum(flakes, snowflake_at(axis, 0.62))
    for sx in (-1, 1):
        for sy in (-1, 1):
            for sz in (-1, 1):
                flakes = np.maximum(flakes, snowflake_at((sx, sy, sz), 0.26))
    # a soft blue shadow round each flake so it sits on the ice, then the flake in white
    img = mix(img, (255, 255, 255), flakes)
    save("Snowflake.png", img)


def ornament():
    red, dark = rgb((206, 22, 40)), rgb((132, 6, 22))
    # a deep glossy red, a little darker toward the bottom
    t = np.clip((math.pi / 2 - LAT) / math.pi, 0, 1)
    img = red[None, None, :] * (1 - 0.45 * t[..., None] ** 1.5) + dark[None, None, :] * (0.45 * t[..., None] ** 1.5)
    gold, pale = (255, 204, 70), (255, 240, 190)
    # the band round the middle: two gold lines, white points between them, gold dots outside
    band = np.abs(LAT)
    img = mix(img, gold, soft(np.abs(band - 0.3), 0.022))
    zig = np.abs(((LON / (2 * math.pi) * 14) % 1) - 0.5) * 2  # 0 at a point's tip, 1 between
    img = mix(img, (250, 250, 246), ((band < 0.26 * (1 - zig)) & (band < 0.26)).astype(np.float64))
    for row, n, off in ((0.46, 14, 0.0), (0.6, 14, 0.5)):
        for s in (1, -1):
            cell = np.abs(((LON / (2 * math.pi) * n + off) % 1) - 0.5) * 2 * math.pi / n * np.cos(LAT)
            d = np.sqrt(cell ** 2 + (LAT - s * row) ** 2)
            img = mix(img, pale, soft(d, 0.032))
    # the cap: gold over the top, ribbed
    cap = LAT > math.radians(70)
    ribs = 0.82 + 0.18 * np.cos(LON * 18)
    img[cap] = (rgb(gold)[None, :] * ribs[cap, None])
    img = mix(img, (120, 84, 20), soft(np.abs(LAT - math.radians(70)), 0.012))
    save("Ornament.png", img)


def snowball():
    white, hollow = rgb((252, 253, 255)), rgb((186, 208, 236))
    lumps = noise3(DX, DY, DZ, 7, 11) * 0.6 + noise3(DX, DY, DZ, 19, 5) * 0.4
    k = np.clip((0.5 - lumps) * 3.2, 0, 1)
    img = white[None, None, :] * (1 - k[..., None]) + hollow[None, None, :] * k[..., None]
    # a fine sparkle of ice grains
    grain = noise3(DX, DY, DZ, 120, 77)
    img = img * (0.97 + 0.05 * grain[..., None])
    save("Snowball.png", img)


def peppermint():
    theta, phi = frame((0.0, 1.0, 0.0))
    # six red wedges swirling a third of a turn pole to pole, a thin green stripe down each white one
    swirl = phi + 1.1 * (theta - math.pi / 2)
    wedge = (swirl / (2 * math.pi) * 6) % 1
    width = np.sin(np.clip(theta, 0.02, math.pi - 0.02))  # (stripes keep their edge near the poles)
    img = np.ones((H, W, 3)) * rgb((250, 250, 246))
    img = mix(img, (214, 26, 44), np.clip((0.5 - np.abs(wedge - 0.25) * 2) / 0.02 * width + 0.5, 0, 1) * (np.abs(wedge - 0.25) < 0.26))
    img = mix(img, (40, 160, 84), soft(np.abs(wedge - 0.75) * width, 0.03, 0.01))
    # a glossy sweet: a faint lighter sheen in a band
    sheen = np.clip(1 - np.abs(LAT - 0.5) / 0.35, 0, 1) ** 2
    img = img * (1 + 0.06 * sheen[..., None])
    save("Peppermint.png", img)


def gift():
    green, dark = rgb((24, 132, 74)), rgb((14, 96, 54))
    stripes = (np.floor((LAT + math.pi / 2) / math.pi * 18) % 2)[..., None]
    img = green[None, None, :] * (1 - stripes) + dark[None, None, :] * stripes
    # small white stars scattered on the paper (four-pointed, on a loose grid)
    for axis_seed in range(40):
        r = np.random.default_rng(300 + axis_seed)
        v = r.normal(size=3)
        theta, phi = frame(v)
        a = np.abs((phi + math.pi / 4) % (math.pi / 2) - math.pi / 4)
        star = (theta * (1 + 2.6 * np.sin(a))) < 0.07
        img[star] = rgb((246, 250, 244))
    # the ribbon: red both ways round, a gold line down each edge
    for axis in ((1, 0, 0), (0, 0, 1)):
        theta, _ = frame(axis)
        d = np.abs(theta - math.pi / 2)
        img = mix(img, (214, 26, 44), soft(d, 0.2))
        img = mix(img, (255, 210, 90), soft(np.abs(d - 0.2), 0.014))
    # the bow on top: four loops and a knot
    theta, phi = frame((0, 1, 0))
    loop = np.abs(np.cos(2 * (phi + math.pi / 4))) ** 0.6 * 0.5
    img = mix(img, (236, 44, 60), ((theta < loop) & (theta > 0.07)).astype(np.float64))
    img = mix(img, (150, 10, 26), soft(np.abs(theta - loop), 0.012) * (theta > 0.07))
    img = mix(img, (255, 210, 90), (theta < 0.085).astype(np.float64))
    save("Gift.png", img)


if __name__ == "__main__":
    os.makedirs(B.OUT, exist_ok=True)
    snowflake()
    ornament()
    snowball()
    peppermint()
    gift()
