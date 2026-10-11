"""Textures for the Blender effect meshes (art/SpikeRushFX.blend): white with soft alpha, so
the game tints them (SpecialMesh.VertexColor) and their edges dissolve instead of ending hard.
Original, procedural (numpy noise), written to art/tex/*.png at 512 px.

  fx_wisp.png   a flame tongue: bright at the root, ragged noisy edges, licking out at the tip
  fx_slash.png  a slash streak: a hot leading edge (v=1) fading to a feathered tail (v=0)
  fx_ring.png   a shock ring across v: sharp bright outer edge, soft fade inward, a little grain
  fx_shell.png  a dome shell: bright rim (v=0) fading to clear at the top, with streaks
  fx_swirl.png  wind streaks along u, soft across v
  fx_bolt.png   lightning: a white-hot core along the middle of v, a glow falling off to the edges
  fx_beam.png   a rising column texture (for Beams): flickering vertical flame streaks, tileable

Run: python tools/generate_fx_mesh_textures.py
"""
from pathlib import Path

import numpy as np
from PIL import Image

N = 512
OUT = Path(__file__).resolve().parent.parent / "art" / "tex"
rng = np.random.default_rng(20261010)


def smooth_noise(n, cells, octaves=4, seed=0, tile=True):
    """Value noise in [0,1], tileable along both axes."""
    r = np.random.default_rng(seed)
    out = np.zeros((n, n))
    amp, total = 1.0, 0.0
    for o in range(octaves):
        c = cells * (2 ** o)
        grid = r.random((c, c))
        ys = np.linspace(0, c, n, endpoint=False)
        y0 = np.floor(ys).astype(int)
        fy = ys - y0
        fy = fy * fy * (3 - 2 * fy)
        y1 = (y0 + 1) % c
        rows = grid[y0] * (1 - fy)[:, None] + grid[y1] * fy[:, None]
        x0, x1 = y0, y1
        fx = fy
        layer = rows[:, x0] * (1 - fx)[None, :] + rows[:, x1] * fx[None, :]
        out += layer * amp
        total += amp
        amp *= 0.5
    return out / total


def save(name, alpha, white=None):
    alpha = np.clip(alpha, 0, 1)
    rgb = np.ones((N, N, 3)) if white is None else np.clip(white, 0, 1)[..., None].repeat(3, axis=2)
    img = np.dstack([rgb, alpha[..., None]]) * 255
    OUT.mkdir(parents=True, exist_ok=True)
    Image.fromarray(img.astype(np.uint8), "RGBA").save(OUT / name)
    print("wrote", OUT / name)


u = np.linspace(0, 1, N)[None, :].repeat(N, axis=0)  # across (x)
v = np.linspace(1, 0, N)[:, None].repeat(N, axis=1)  # along (y, 0 at the bottom of the image)

# a flame tongue: u across (0..1), v from root (0) to tip (1)
n1 = smooth_noise(N, 4, seed=1)
n2 = smooth_noise(N, 8, seed=2)
width = 0.5 * (1 - v) ** 0.55 + 0.04
edge = np.abs(u - 0.5 - 0.08 * (n1 - 0.5) * v) / np.maximum(width, 1e-3)
body = np.clip(1 - edge, 0, 1) ** 0.8
licks = np.clip((n2 - 0.35) * 2.2, 0, 1)
alpha = body * (0.55 + 0.45 * licks) * np.clip((1 - v) * 1.4, 0, 1) * np.clip(v * 8, 0, 1)
core = np.clip(1 - edge * 1.6, 0, 1) * (1 - v) ** 0.6
save("fx_wisp.png", alpha * 0.95, white=0.75 + 0.25 * core)

# a slash streak: u along the arc, v across (1 = the leading edge)
n3 = smooth_noise(N, 6, seed=3)
lead = np.clip((v - 0.15) / 0.85, 0, 1) ** 2.2
streaks = 0.75 + 0.25 * smooth_noise(N, 16, octaves=2, seed=4)[:, :1].repeat(N, axis=1)
ends = np.sin(np.pi * u) ** 0.6
alpha = lead * streaks * ends * (0.8 + 0.2 * n3)
save("fx_slash.png", alpha, white=0.7 + 0.3 * lead)

# a shock ring: u around, v across (1 = the outer edge)
grain = smooth_noise(N, 12, seed=5)
alpha = (v ** 3.0) * (0.75 + 0.25 * grain) + np.clip((v - 0.92) * 10, 0, 1) * 0.4
save("fx_ring.png", alpha)

# a dome shell: u around, v up from the rim (0) to the top (1)
streak = smooth_noise(N, 10, octaves=3, seed=6)
alpha = (1 - v) ** 1.8 * (0.6 + 0.4 * streak) + np.clip((0.06 - v) * 12, 0, 1) * 0.5
save("fx_shell.png", alpha)

# wind streaks: u along, v across
lines = smooth_noise(N, 3, octaves=3, seed=7)
bands = np.clip(np.sin((v * 7 + lines * 2) * np.pi) * 1.4 - 0.2, 0, 1)
alpha = bands * np.sin(np.pi * v) ** 0.8 * (0.5 + 0.5 * smooth_noise(N, 5, seed=8))
save("fx_swirl.png", alpha)

# lightning: u along the bolt, v across (the core in the middle)
d = np.abs(v - 0.5) * 2
alpha = np.clip(1 - d, 0, 1) ** 2.5 + np.clip(1 - d * 4, 0, 1)
save("fx_bolt.png", np.clip(alpha, 0, 1), white=np.clip(1 - d * 0.5, 0, 1))

# a rising column for Beams: vertical flame streaks, tileable along v
cols = smooth_noise(N, 6, octaves=4, seed=9)
alpha = np.clip((cols - 0.3) * 1.8, 0, 1) * np.sin(np.pi * u) ** 0.7
save("fx_beam.png", alpha)
