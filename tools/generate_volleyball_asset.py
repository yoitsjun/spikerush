#!/usr/bin/env python3
"""Generate the Spike Rush volleyball asset (stand-in for a Blender export).

Outputs (in ../assets):
  volleyball.obj          UV sphere, radius 1, 64x32 segments, normals + equirectangular UVs
  volleyball_albedo.png   2048x1024 texture: the classic 18-panel layout (six cube-face groups of
                          three strips, strips rotated 90 degrees between neighbouring groups),
                          navy / sun-yellow / white, with dark seams.

Import volleyball.obj with Studio's 3D Importer (or upload it as a MeshPart), upload the PNG
as a Decal/Image, then paste both ids into src/shared/Assets.lua (Assets.Mesh). The mesh has
radius 1, so the client scales it to the gameplay ball radius exactly.
"""
from pathlib import Path

import numpy as np
from PIL import Image

OUT = Path(__file__).resolve().parent.parent / "assets"
OUT.mkdir(exist_ok=True)

NAVY = np.array([34, 86, 196], dtype=np.float32)
YELLOW = np.array([255, 205, 40], dtype=np.float32)
WHITE = np.array([250, 250, 244], dtype=np.float32)
SEAM = np.array([40, 42, 56], dtype=np.float32)

# strips per face group: (axis the face points along, axis the strips run along)
GROUPS = {
    0: (2, [NAVY, YELLOW, NAVY]),  # +/-X faces: strips split along Z
    1: (0, [YELLOW, WHITE, YELLOW]),  # +/-Y faces: strips split along X
    2: (1, [WHITE, NAVY, WHITE]),  # +/-Z faces: strips split along Y
}


def texture(width=2048, height=1024):
    u = (np.arange(width) + 0.5) / width
    v = (np.arange(height) + 0.5) / height
    uu, vv = np.meshgrid(u, v)
    theta = uu * 2 * np.pi
    phi = vv * np.pi
    x = np.sin(phi) * np.cos(theta)
    y = np.cos(phi)
    z = np.sin(phi) * np.sin(theta)
    p = np.stack([x, y, z], axis=-1)
    a = np.abs(p)
    face = np.argmax(a, axis=-1)
    img = np.zeros((height, width, 3), dtype=np.float32)
    seam = np.zeros((height, width), dtype=bool)

    # face boundaries: the two largest components are nearly equal
    srt = np.sort(a, axis=-1)
    seam |= (srt[..., 2] - srt[..., 1]) < 0.022

    for f, (split_axis, colors) in GROUPS.items():
        mask = face == f
        coord = p[..., split_axis] / np.maximum(a[..., f], 1e-6)  # in [-1, 1] on the cube face
        band = np.clip(((coord + 1) / 2 * 3).astype(int), 0, 2)
        for i, col in enumerate(colors):
            img[mask & (band == i)] = col
        # seams between strips at coord = -1/3 and +1/3
        edge = np.minimum(np.abs(coord - 1 / 3), np.abs(coord + 1 / 3))
        seam |= mask & (edge < 0.03)

    # soft shading along seams so they read as stitched grooves
    img[seam] = SEAM
    # subtle leather grain
    rng = np.random.default_rng(7)
    grain = rng.normal(0, 3.2, size=(height, width, 1)).astype(np.float32)
    img = np.clip(img + grain, 0, 255)
    Image.fromarray(img.astype(np.uint8), "RGB").save(OUT / "volleyball_albedo.png", optimize=True)


def mesh(segments=64, rings=32):
    lines = ["# Spike Rush volleyball, radius 1", "o Volleyball"]
    verts, uvs, norms = [], [], []
    for r in range(rings + 1):
        phi = np.pi * r / rings
        for s in range(segments + 1):
            theta = 2 * np.pi * s / segments
            x = np.sin(phi) * np.cos(theta)
            y = np.cos(phi)
            z = np.sin(phi) * np.sin(theta)
            verts.append((x, y, z))
            norms.append((x, y, z))
            uvs.append((s / segments, 1 - r / rings))
    for x, y, z in verts:
        lines.append(f"v {x:.6f} {y:.6f} {z:.6f}")
    for uu, vv in uvs:
        lines.append(f"vt {uu:.6f} {vv:.6f}")
    for x, y, z in norms:
        lines.append(f"vn {x:.6f} {y:.6f} {z:.6f}")
    row = segments + 1
    faces = 0
    for r in range(rings):
        for s in range(segments):
            a = r * row + s + 1
            b = a + row
            c = b + 1
            d = a + 1
            # counter-clockwise when seen from outside
            if r != 0:
                lines.append(f"f {a}/{a}/{a} {d}/{d}/{d} {b}/{b}/{b}")
                faces += 1
            if r != rings - 1:
                lines.append(f"f {d}/{d}/{d} {c}/{c}/{c} {b}/{b}/{b}")
                faces += 1
    (OUT / "volleyball.obj").write_text("\n".join(lines) + "\n")
    return len(verts), faces


if __name__ == "__main__":
    texture()
    nv, nf = mesh()
    print(f"volleyball.obj: {nv} vertices, {nf} triangles")
    print("volleyball_albedo.png: 2048x1024")
