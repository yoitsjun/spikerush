"""Kuro's fire dragon, our own mesh: a hollow head and serpent body drawn in tapered flame strokes
(the owner, 2026-11-04: "like sasuke's lightning dragon", "obviously with fire not lightning": the
idea of a huge see-through dragon of glowing lines out of a cracked sky; the design is ours).

    blender --background --python tools/generate_kuro_dragon.py -- <preview folder>

Writes assets/fx/KuroDragon.fbx with five meshes, and preview renders into the folder if one's given:

  DragonCoreA/B  the thin white-hot strokes     DragonGlowA/B  the same strokes, fatter, for the fire
  DragonSky      the veins that crack across the sky (a shallow bowl, Z up)

A and B are the same dragon with the strokes shaken differently: flipped quickly they crackle. Every
dragon mesh carries two specks at the same corners, so all four share one bounding box and stay lined
up as MeshParts. Unit: the head is 1 long; the nose points along +Y, the body trails back along -Y.
"""
import math
import os
import random
import sys

import bpy
from mathutils import Vector

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "fx", "KuroDragon.fbx")
BODY_LENGTH = 6.5


def catmull(pts, n):
    """n points along a smooth curve through pts."""
    p = [Vector(q) for q in pts]
    if len(p) == 2:
        return [p[0].lerp(p[1], i / (n - 1)) for i in range(n)]
    ext = [p[0] * 2 - p[1]] + p + [p[-1] * 2 - p[-2]]
    out = []
    for i in range(n):
        u = i / (n - 1) * (len(p) - 1)
        k = min(int(u), len(p) - 2)
        t = u - k
        a, b, c, d = ext[k], ext[k + 1], ext[k + 2], ext[k + 3]
        out.append(0.5 * (2 * b + (c - a) * t + (2 * a - 5 * b + 4 * c - d) * t * t + (3 * b - a - 3 * c + d) * t * t * t))
    return out


class Stroke:
    def __init__(self, pts, width=1.0, kind="line", n=None, shake=1.0):
        self.pts, self.width, self.kind, self.n, self.shake = pts, width, kind, n, shake

    def mirrored(self):
        return Stroke([(-q[0], q[1], q[2]) for q in self.pts], self.width, self.kind, self.n, self.shake)


def radius(kind, t):
    if kind == "flame":  # fat near the root, a sharp tip
        return max(0.03, math.sin(math.pi * t ** 0.62)) ** 0.8
    if kind == "fang":
        return max(0.03, 1 - t) ** 0.8
    return 0.4 + 0.6 * math.sin(math.pi * t)


def shaken(stroke, rng):
    """The stroke's points, smoothed and knocked about: flames lick, they don't run straight."""
    n = stroke.n or max(4, min(14, int(len(stroke.pts) * 2.5)))
    if stroke.kind == "flame":
        n = int(n * 1.7)  # flames curve; only the lines stay hard
    pts = catmull(stroke.pts, n)
    length = sum((pts[i + 1] - pts[i]).length for i in range(n - 1))
    amp = (0.009 if stroke.kind == "flame" else 0.016) * stroke.shake * min(1.0, length / 0.6 + 0.2)
    out = []
    for i, p in enumerate(pts):
        edge = max(0.0, math.sin(math.pi * i / (n - 1))) ** 0.5
        out.append(p + Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), rng.uniform(-1, 1))) * amp * edge)
    return out


class Mesh:
    def __init__(self):
        self.verts, self.faces = [], []

    def tube(self, pts, r0, kind):
        sides = 3
        n = len(pts)
        base = len(self.verts)
        side = Vector((0.31, 0.17, 0.93))
        for i, p in enumerate(pts):
            tangent = (pts[min(i + 1, n - 1)] - pts[max(i - 1, 0)]).normalized()
            u = tangent.cross(side)
            if u.length < 1e-4:
                u = tangent.cross(Vector((1, 0, 0)))
            u.normalize()
            v = tangent.cross(u)
            r = r0 * radius(kind, i / (n - 1))
            for k in range(sides):
                a = 2 * math.pi * k / sides
                self.verts.append(tuple(p + (u * math.cos(a) + v * math.sin(a)) * r))
        for i in range(n - 1):
            for k in range(sides):
                a = base + i * sides + k
                b = base + i * sides + (k + 1) % sides
                c, d = a + sides, b + sides
                self.faces.append((a, b, d))
                self.faces.append((a, d, c))
        last = base + (n - 1) * sides
        self.faces.append((base + 2, base + 1, base))
        self.faces.append((last, last + 1, last + 2))

    def speck(self, p, r=0.004):
        base = len(self.verts)
        for d in ((r, 0, 0), (0, r, 0), (0, 0, r), (-r, -r, -r)):
            self.verts.append((p[0] + d[0], p[1] + d[1], p[2] + d[2]))
        for f in ((0, 1, 2), (0, 3, 1), (1, 3, 2), (2, 3, 0)):
            self.faces.append(tuple(base + i for i in f))

    def bounds(self):
        xs = list(zip(*self.verts))
        return tuple(min(a) for a in xs), tuple(max(a) for a in xs)


def centre(s):
    """The body's line at s (0 at the neck, 1 at the tail): it winds more the further back it goes."""
    swing = 0.1 + 0.9 * s
    return Vector((0.72 * swing * math.sin(s * 8.6), 0.08 - BODY_LENGTH * s, 0.05 + 0.5 * swing * math.sin(s * 6.1 + 0.7)))


def girth(s):
    return 0.36 * (1 - s) ** 0.75 + 0.02


def dragon(rng):
    strokes = []

    def both(pts, width=1.0, kind="line", n=None, shake=1.0):
        s = Stroke(pts, width, kind, n, shake)
        strokes.append(s)
        strokes.append(s.mirrored())

    # the top of the snout, over the nostril and up the brow
    top = [(0.0, 1.0, 0.1), (0.07, 0.94, 0.21), (0.1, 0.8, 0.2), (0.11, 0.6, 0.22), (0.19, 0.42, 0.34), (0.25, 0.24, 0.47), (0.22, 0.02, 0.42), (0.16, -0.16, 0.34)]
    lip = [(0.02, 1.02, 0.0), (0.15, 0.87, -0.03), (0.21, 0.62, -0.02), (0.27, 0.36, -0.07), (0.31, 0.14, -0.16)]
    jaw = [(0.31, 0.12, -0.17), (0.25, 0.36, -0.35), (0.19, 0.6, -0.5), (0.11, 0.82, -0.62), (0.02, 0.93, -0.63)]
    chin = [(0.0, 0.92, -0.71), (0.13, 0.62, -0.63), (0.23, 0.32, -0.47), (0.3, 0.04, -0.33), (0.3, -0.16, -0.2)]
    both(top, 1.25, n=14)
    both(lip, 1.15, n=12)
    both(jaw, 1.15, n=12)
    both(chin, 1.0, n=12)
    # a nostril's curl
    both([(0.04, 0.95, 0.15), (0.11, 0.92, 0.2), (0.15, 0.85, 0.15), (0.11, 0.81, 0.09), (0.07, 0.85, 0.11)], 0.8, n=9, shake=0.4)
    # the eye: a hard slant under a heavy brow that runs back into a spike
    both([(0.17, 0.5, 0.25), (0.25, 0.38, 0.27), (0.31, 0.24, 0.35), (0.26, 0.31, 0.24), (0.2, 0.42, 0.2), (0.17, 0.5, 0.25)], 1.3, n=12, shake=0.2)
    both([(0.13, 0.56, 0.3), (0.24, 0.45, 0.38), (0.33, 0.3, 0.44), (0.42, 0.1, 0.5), (0.5, -0.14, 0.6)], 1.35, "flame", n=11)
    both([(0.24, 0.33, 0.28), (0.26, 0.33, 0.26), (0.24, 0.35, 0.25)], 2.4, n=4, shake=0)
    # horns, branching
    both([(0.15, 0.12, 0.42), (0.22, -0.2, 0.6), (0.3, -0.58, 0.72), (0.34, -0.98, 0.98), (0.4, -1.36, 1.3)], 1.5, "flame", n=13)
    both([(0.27, -0.42, 0.67), (0.42, -0.58, 0.9), (0.48, -0.8, 1.14)], 1.4, "flame", n=8)
    both([(0.32, -0.8, 0.84), (0.2, -0.98, 1.1), (0.16, -1.2, 1.38)], 1.2, "flame", n=8)
    # whiskers: out past the nose, then a long lazy flame back along the head
    both([(0.09, 0.92, 0.12), (0.32, 1.04, 0.2), (0.6, 0.82, 0.32), (0.86, 0.3, 0.22), (1.02, -0.3, 0.4), (1.3, -0.9, 0.3)], 1.0, "flame", n=14)
    both([(0.15, 0.82, -0.04), (0.42, 0.86, -0.22), (0.66, 0.52, -0.4), (0.8, 0.0, -0.3), (1.02, -0.6, -0.5)], 0.9, "flame", n=13)
    # fangs, top and bottom: one long one in front, the rest a saw
    lips = catmull(lip, 24)
    jaws = catmull(jaw, 24)
    for i, (a, drop) in enumerate(((1, 0.28), (4, 0.16), (6, 0.2), (9, 0.14), (11, 0.17), (14, 0.12), (16, 0.14), (19, 0.1))):
        p = lips[a]
        both([tuple(p), tuple(p + Vector((-0.012, 0.006, -drop)))], 1.8 if i == 0 else 1.3, "fang", n=4, shake=0.1)
        both([tuple(lips[a + 2]), tuple(p + Vector((-0.012, 0.006, -drop)))], 0.6, "fang", n=3, shake=0.1)
    for i, (a, rise) in enumerate(((21, 0.24), (18, 0.13), (15, 0.16), (12, 0.11), (9, 0.13), (6, 0.1))):
        p = jaws[a]
        both([tuple(p), tuple(p + Vector((-0.01, 0.012, rise)))], 1.6 if i == 0 else 1.2, "fang", n=4, shake=0.1)
    # the tangle over the face: ribs from the ridge down to the lip, jaw to chin, and a keel on top
    tops = catmull(top, 20)
    for t, l, bulge in ((3, 2, 0.03), (6, 6, 0.04), (9, 10, 0.05), (12, 15, 0.08), (15, 21, 0.1), (17, 23, 0.1)):
        p, q = tops[t], lips[l]
        both([tuple(p), tuple(p.lerp(q, 0.5) + Vector((bulge, 0, 0.02))), tuple(q)], 0.7, n=6, shake=1.6)
    chins = catmull(chin, 24)
    for j, c in ((6, 20), (10, 16), (14, 12), (18, 8), (21, 4)):
        p, q = jaws[j], chins[c]
        both([tuple(p), tuple(p.lerp(q, 0.5) + Vector((0.04, 0, -0.02))), tuple(q)], 0.7, n=5, shake=1.6)
    both([(0.0, 0.84, 0.25), (0.05, 0.6, 0.3), (0.08, 0.34, 0.5), (0.05, 0.1, 0.58), (0.05, -0.2, 0.5)], 0.8, n=11, shake=1.4)
    # cheek flames, swept back off the hinge of the jaw
    for i, (dy, dz, dx) in enumerate(((-0.62, 0.34, 0.42), (-0.8, 0.08, 0.56), (-0.86, -0.2, 0.62), (-0.66, -0.52, 0.5), (-0.42, -0.72, 0.34))):
        p = Vector((0.31, 0.1 - 0.05 * i, -0.08 - 0.07 * i))
        both([tuple(p), tuple(p + Vector((dx * 0.45, dy * 0.4, dz * 0.25 + 0.05))), tuple(p + Vector((dx * 0.75, dy * 0.75, dz * 0.75))), tuple(p + Vector((dx, dy, dz)))], 1.25, "flame", n=11, shake=1.2)
    # the mane: flames off the back of the skull
    for i in range(11):
        a = -1.25 + 2.5 * i / 10
        root = Vector((0.26 * math.sin(a), -0.05 - 0.05 * rng.random(), 0.14 + 0.28 * math.cos(a)))
        out = Vector((math.sin(a), 0, math.cos(a)))
        reach = rng.uniform(0.8, 1.35)
        s = Stroke([tuple(root), tuple(root + out * 0.18 + Vector((0, -0.3, 0)) * reach), tuple(root + out * 0.3 + Vector((0.08, -0.68, -0.08)) * reach), tuple(root + out * 0.52 + Vector((-0.08, -1.05, 0.12)) * reach)], 1.25, "flame", n=11, shake=1.3)
        strokes.append(s)

    # the body: strands winding down it, broken rings, a crest of flame on its back
    for k in range(4):
        pts = []
        for i in range(44):
            s = i / 43
            a = k * math.pi / 2 + s * 15
            c = centre(s)
            pts.append(c + Vector((math.cos(a), 0, math.sin(a))) * girth(s))
        strokes.append(Stroke([tuple(p) for p in pts], 1.4 if k % 2 == 0 else 1.0, "line", n=44, shake=1.0))
    for i in range(34):
        s = 0.015 + 0.95 * i / 33
        c = centre(s)
        start = rng.uniform(0, 6.28)
        sweep = rng.uniform(3.2, 5.2)
        pts = [c + Vector((math.cos(start + sweep * j / 6), -0.08 * math.sin(j), math.sin(start + sweep * j / 6))) * girth(s) for j in range(7)]
        strokes.append(Stroke([tuple(p) for p in pts], 0.8, "line", n=7, shake=1.4))
    for i in range(30):
        s = 0.01 + 0.93 * i / 29
        c = centre(s)
        h = (0.24 + 0.4 * (1 - s)) * rng.uniform(0.75, 1.25)
        a = rng.uniform(-0.75, 0.75)
        up = Vector((math.sin(a), 0, math.cos(a)))
        root = c + up * girth(s)
        strokes.append(Stroke([tuple(root), tuple(root + up * h * 0.45 + Vector((0, -0.14, 0))), tuple(root + up * h * 0.8 + Vector((0.05, -0.36, 0))), tuple(root + up * h + Vector((-0.05, -0.62, 0)))], 1.5, "flame", n=8, shake=1.2))
    # the tail: a last spray of flame
    tail = centre(1.0)
    for i in range(7):
        a = i / 7 * 6.28
        out = Vector((math.cos(a), -2.2, math.sin(a)))
        strokes.append(Stroke([tuple(tail), tuple(tail + out * 0.2), tuple(tail + out * 0.42 + Vector((0.05, 0, 0.05)))], 1.2, "flame", n=6))
    return strokes


def sky(rng):
    """Veins across a shallow bowl of sky, radius 1: they branch out of the middle and join up."""
    strokes = []

    def spot(r, a):
        return (r * math.cos(a), r * math.sin(a), -0.2 * r * r)

    arms = 11
    rings = []
    for i in range(arms):
        a0 = i / arms * 6.283 + rng.uniform(-0.1, 0.1)
        pts = []
        r, a = 0.04, a0
        for _ in range(9):
            pts.append(spot(r, a))
            r += rng.uniform(0.09, 0.14)
            a += rng.uniform(-0.1, 0.1)
        strokes.append(Stroke(pts, 1.7, "flame", n=12, shake=1.6))
        rings.append((a0, pts))
        for b in range(3):
            k = rng.randint(2, 7)
            r2 = math.hypot(pts[k][0], pts[k][1])
            a2 = math.atan2(pts[k][1], pts[k][0])
            turn = rng.choice((-1, 1)) * rng.uniform(0.2, 0.5)
            strokes.append(Stroke([pts[k], spot(r2 + 0.09, a2 + turn * 0.5), spot(r2 + 0.17, a2 + turn), spot(r2 + 0.27, a2 + turn * 1.2)], 0.9, "flame", n=7, shake=1.6))
    for i in range(arms):
        cur, nxt = rings[i][1], rings[(i + 1) % arms][1]
        for k in (2, 4, 6):
            k2 = min(8, k + rng.randint(-1, 1))
            mid = tuple((cur[k][j] + nxt[k2][j]) / 2 + rng.uniform(-0.02, 0.02) for j in range(3))
            strokes.append(Stroke([cur[k], mid, nxt[k2]], 0.7, "line", n=6, shake=1.8))
    return strokes


def build(name, mesh, collection):
    data = bpy.data.meshes.new(name)
    data.from_pydata(mesh.verts, [], mesh.faces)
    data.update()
    ob = bpy.data.objects.new(name, data)
    collection.objects.link(ob)
    return ob


def emission(name, color, strength):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    nodes.clear()
    out = nodes.new("ShaderNodeOutputMaterial")
    em = nodes.new("ShaderNodeEmission")
    em.inputs[0].default_value = (*color, 1)
    em.inputs[1].default_value = strength
    mat.node_tree.links.new(em.outputs[0], out.inputs[0])
    return mat


def main():
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    preview = args[0] if args else None
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    col = scene.collection
    meshes = {}
    for tag, seed in (("A", 11), ("B", 23)):
        structure = random.Random(5)  # the same dragon both times
        strokes = dragon(structure)
        rng = random.Random(seed)
        core, glow = Mesh(), Mesh()
        for s in strokes:
            pts = shaken(s, rng)
            core.tube(pts, 0.0085 * s.width, s.kind)
            glow.tube(pts, 0.019 * s.width, s.kind)
        meshes["DragonCore" + tag] = core
        meshes["DragonGlow" + tag] = glow
    lo = [min(m.bounds()[0][i] for m in meshes.values()) - 0.01 for i in range(3)]
    hi = [max(m.bounds()[1][i] for m in meshes.values()) + 0.01 for i in range(3)]
    for m in meshes.values():
        m.speck(lo)
        m.speck(hi)
    rng = random.Random(41)
    web = Mesh()
    for s in sky(rng):
        web.tube(shaken(s, rng), 0.0042 * s.width, s.kind)
    meshes["DragonSky"] = web
    objs = {name: build(name, m, col) for name, m in meshes.items()}
    for name, m in meshes.items():
        print(name, "tris", len(m.faces))
    print("bounds", [round(v, 3) for v in lo], [round(v, 3) for v in hi])
    print("nose from centre (head lengths)", round(1.04 - (lo[1] + hi[1]) / 2, 3), "x", round((lo[0] + hi[0]) / 2, 3), "z", round((lo[2] + hi[2]) / 2, 3))

    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.export_scene.fbx(filepath=OUT, use_selection=True, object_types={"MESH"}, mesh_smooth_type="FACE", bake_anim=False, add_leaf_bones=False)
    print("wrote", OUT)

    if preview:
        os.makedirs(preview, exist_ok=True)
        objs["DragonCoreA"].data.materials.append(emission("Core", (1, 0.9, 0.62), 1))
        objs["DragonGlowA"].data.materials.append(emission("Glow", (1, 0.3, 0.03), 1))
        for n in ("DragonCoreB", "DragonGlowB", "DragonSky"):
            objs[n].hide_render = True
        world = bpy.data.worlds.new("w")
        world.use_nodes = True
        world.node_tree.nodes["Background"].inputs[0].default_value = (0.03, 0.01, 0.015, 1)
        scene.world = world
        scene.render.engine = "BLENDER_EEVEE"
        scene.view_settings.view_transform = "Standard"
        scene.render.resolution_x, scene.render.resolution_y = 1100, 760
        cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
        col.objects.link(cam)
        scene.camera = cam
        for tag, eye, at, lens in (("head", (1.9, 3.2, 0.3), (0, 0.15, -0.05), 45), ("side", (5.2, 0.2, 0.2), (0, 0.0, 0), 40), ("dive", (1.4, 4.2, -0.9), (0, -1.6, 0.1), 38)):
            cam.location = eye
            cam.rotation_euler = (Vector(at) - Vector(eye)).to_track_quat("-Z", "Y").to_euler()
            cam.data.lens = lens
            scene.render.filepath = os.path.join(preview, "dragon_" + tag + ".png")
            bpy.ops.render.render(write_still=True)
        objs["DragonCoreA"].hide_render = True
        objs["DragonGlowA"].hide_render = True
        objs["DragonSky"].hide_render = False
        objs["DragonSky"].data.materials.append(emission("Sky", (1, 0.4, 0.08), 4))
        cam.location = (0, 0, -1.6)
        cam.rotation_euler = (0, math.pi, 0)
        cam.data.lens = 18
        scene.render.filepath = os.path.join(preview, "dragon_sky.png")
        bpy.ops.render.render(write_still=True)


main()
