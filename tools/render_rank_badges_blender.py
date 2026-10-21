"""Render the ranked badges (Config.Ranked.Ranks) as 3D crests in Blender (run inside Blender: the
Scripting tab, or `blender -b -P tools/render_rank_badges_blender.py -- OUT_DIR`). It replaces
tools/generate_rank_badges.py's flat drawings (the owner, 2026-10-21: "the rank icons are quite ugly
right now. let try and make it way way way cooler"; their references were glossy game crests with a
glowing orb).

Each rank is a bevelled shield crest in its metal with a swirling orb in a ring, and more around it
the higher it goes: Bronze plain, Silver side flares, Gold a gem and wings, Platinum spikes, Diamond
crystals and bigger wings, Mighty a gold crown and tail feathers, Almighty a gold halo, a crown and the
biggest wings. Renders 1024 px RGBA PNGs (transparent) into OUT_DIR as Rank<Key>.png; then run
tools/finish_rank_badges.py to crop, grade, outline and glow them into assets/ranks.
"""
import math
import os
import sys

import bmesh
import bpy
from mathutils import Vector


# ------------------------------------------------------------------------------- materials

def metal(name, top, bottom=None, rough=0.25, coat=0.5):
    # a coated metal whose colour runs from `bottom` to `top` up the badge (world Z)
    bottom = bottom or tuple(c * 0.45 for c in top)
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    b = nt.nodes.new("ShaderNodeBsdfPrincipled")
    geo = nt.nodes.new("ShaderNodeNewGeometry")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    mr = nt.nodes.new("ShaderNodeMapRange")
    mr.inputs["From Min"].default_value = -1.0
    mr.inputs["From Max"].default_value = 1.0
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].color = (*bottom, 1)
    ramp.color_ramp.elements[1].color = (*top, 1)
    nt.links.new(geo.outputs["Position"], sep.inputs[0])
    nt.links.new(sep.outputs["Z"], mr.inputs["Value"])
    nt.links.new(mr.outputs[0], ramp.inputs["Fac"])
    nt.links.new(ramp.outputs["Color"], b.inputs["Base Color"])
    b.inputs["Metallic"].default_value = 1.0
    b.inputs["Roughness"].default_value = rough
    b.inputs["Coat Weight"].default_value = coat
    b.inputs["Coat Roughness"].default_value = 0.04
    nt.links.new(b.outputs[0], out.inputs[0])
    return m


def glow(name, col, strength=1.3, base=None):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    b = nt.nodes.new("ShaderNodeBsdfPrincipled")
    b.inputs["Base Color"].default_value = (*(base or col), 1)
    b.inputs["Roughness"].default_value = 0.05
    b.inputs["Emission Color"].default_value = (*col, 1)
    b.inputs["Emission Strength"].default_value = strength
    b.inputs["Coat Weight"].default_value = 1.0
    nt.links.new(b.outputs[0], out.inputs[0])
    return m


def orbmat(name, c0, c1, strength=0.45):
    # a glowing orb of noise-warped swirls between two colours
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    b = nt.nodes.new("ShaderNodeBsdfPrincipled")
    tc = nt.nodes.new("ShaderNodeTexCoord")
    noise = nt.nodes.new("ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = 2.2
    noise.inputs["Detail"].default_value = 6
    noise.inputs["Distortion"].default_value = 3.5
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].color = (*c0, 1)
    ramp.color_ramp.elements[1].color = (*c1, 1)
    ramp.color_ramp.elements[0].position = 0.35
    ramp.color_ramp.elements[1].position = 0.7
    nt.links.new(tc.outputs["Object"], noise.inputs["Vector"])
    nt.links.new(noise.outputs["Fac"], ramp.inputs["Fac"])
    nt.links.new(ramp.outputs["Color"], b.inputs["Base Color"])
    nt.links.new(ramp.outputs["Color"], b.inputs["Emission Color"])
    b.inputs["Emission Strength"].default_value = strength
    b.inputs["Roughness"].default_value = 0.05
    b.inputs["Coat Weight"].default_value = 1.0
    nt.links.new(b.outputs[0], out.inputs[0])
    return m


# ------------------------------------------------------------------------------- shapes

def link(ob):
    bpy.context.scene.collection.objects.link(ob)
    return ob


def outline_obj(name, pts, depth, bevel, mat, z=0.0):
    # a closed 2D outline in the badge plane (x right, y up) extruded and bevelled; the badge plane
    # is world XZ facing the camera at -Y, and a larger z sits nearer the camera
    cu = bpy.data.curves.new(name, "CURVE")
    cu.dimensions = "2D"
    cu.fill_mode = "BOTH"
    sp = cu.splines.new("POLY")
    sp.points.add(len(pts) - 1)
    for i, (x, y) in enumerate(pts):
        sp.points[i].co = (x, y, 0, 1)
    sp.use_cyclic_u = True
    cu.extrude = depth
    cu.bevel_depth = bevel
    cu.bevel_resolution = 4
    ob = link(bpy.data.objects.new(name, cu))
    ob.data.materials.append(mat)
    ob.rotation_euler = (math.radians(90), 0, 0)
    ob.location = (0, -z, 0)
    return ob


def scale_pts(pts, k, dy=0.0):
    return [(x * k, y * k + dy) for x, y in pts]


def full(half):
    # mirror a right-half outline (top centre -> bottom centre) into a closed loop
    return half + [(-x, y) for x, y in reversed(half[1:-1])]


def mirror(ob):
    ob.modifiers.new("Mirror", "MIRROR").use_axis = (True, False, False)
    return ob


def sphere(name, r, loc, mat, segs=48):
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=segs, v_segments=segs // 2, radius=r)
    bm.to_mesh(me)
    bm.free()
    for p in me.polygons:
        p.use_smooth = True
    ob = link(bpy.data.objects.new(name, me))
    ob.location = loc
    ob.data.materials.append(mat)
    return ob


def gem(name, r, h, loc, mat, sides=8, scale=(1, 1, 1)):
    # a cut gem (table, crown, pointed pavilion) with its table to the camera
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    top, gird = [], []
    for i in range(sides):
        a = 2 * math.pi * i / sides
        gird.append(bm.verts.new((r * math.cos(a), r * math.sin(a), 0)))
        a2 = a + math.pi / sides
        top.append(bm.verts.new((0.55 * r * math.cos(a2), 0.55 * r * math.sin(a2), h * 0.45)))
    tip = bm.verts.new((0, 0, -h))
    bm.faces.new(top)
    for i in range(sides):
        j = (i + 1) % sides
        bm.faces.new((gird[i], gird[j], top[i]))
        bm.faces.new((top[i], gird[j], top[j]))
        bm.faces.new((gird[j], gird[i], tip))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(me)
    bm.free()
    ob = link(bpy.data.objects.new(name, me))
    ob.data.materials.append(mat)
    ob.rotation_euler = (math.radians(90), 0, 0)
    ob.location = loc
    ob.scale = scale
    return ob


def torus(name, R, r, loc, mat):
    # a ring facing the camera
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    n, m = 96, 16
    vs = []
    for i in range(n):
        a = 2 * math.pi * i / n
        row = []
        for j in range(m):
            b = 2 * math.pi * j / m
            row.append(bm.verts.new(((R + r * math.cos(b)) * math.cos(a), r * math.sin(b), (R + r * math.cos(b)) * math.sin(a))))
        vs.append(row)
    for i in range(n):
        for j in range(m):
            bm.faces.new((vs[i][j], vs[(i + 1) % n][j], vs[(i + 1) % n][(j + 1) % m], vs[i][(j + 1) % m]))
    bm.to_mesh(me)
    bm.free()
    for p in me.polygons:
        p.use_smooth = True
    ob = link(bpy.data.objects.new(name, me))
    ob.location = loc
    ob.data.materials.append(mat)
    return ob


def feather(length, width, curl):
    # one wing blade from the origin along +x, its tip curling up
    n = 12
    pts = [(i / n * length, width * 0.5 * (1 - i / n) ** 0.6 + curl * (i / n) ** 2) for i in range(n + 1)]
    pts += [(i / n * length, -width * 0.5 * (1 - i / n) ** 1.4 + curl * (i / n) ** 2) for i in range(n, -1, -1)]
    return pts


def place(pts, ang, ox, oy):
    c, s = math.cos(ang), math.sin(ang)
    return [(ox + x * c - y * s, oy + x * s + y * c) for x, y in pts]


def wings(mats, count, length, spread, z=0.05, ox=0.6, oy=0.1, width=0.32, curl=0.16, taper=0.3, prefix="Wing"):
    for i in range(count):
        t = i / max(1, count - 1)
        ang = math.radians(spread[0] + (spread[1] - spread[0]) * t)
        p = place(feather(length * (1 - taper * t), width, curl), ang, ox, oy)
        mirror(outline_obj(prefix + str(i), p, 0.05, 0.03, mats[i % len(mats)], z=z + 0.03 * i))


# right halves of the shield (top centre -> bottom centre): plainer for the low ranks
SHAPES = {
    "plain": [(0, 0.9), (0.38, 0.78), (0.66, 0.6), (0.68, 0.0), (0.5, -0.48), (0, -0.92)],
    "flared": [(0, 0.95), (0.3, 0.84), (0.55, 0.78), (0.8, 0.82), (0.7, 0.5), (0.7, 0.0), (0.5, -0.5), (0, -0.98)],
    "crest": [(0, 0.98), (0.2, 0.86), (0.42, 0.84), (0.58, 0.72), (0.86, 0.78), (0.74, 0.5), (0.7, 0.18),
              (0.78, -0.08), (0.6, -0.2), (0.5, -0.5), (0.22, -0.72), (0, -1.02)],
}

# each rank's metals (top, bottom of the gradient), orb swirl colours and gem glow
PAL = {
    "Bronze": dict(main=((0.95, 0.55, 0.32), (0.45, 0.16, 0.06)), light=((1.0, 0.75, 0.55), (0.7, 0.32, 0.14)), dark=((0.35, 0.12, 0.05), (0.14, 0.04, 0.02)), orb=((0.7, 0.28, 0.12), (1.0, 0.8, 0.6)), gem=(1.0, 0.45, 0.2)),
    "Silver": dict(main=((0.95, 0.97, 1.0), (0.45, 0.5, 0.58)), light=((1.0, 1.0, 1.0), (0.7, 0.75, 0.82)), dark=((0.3, 0.33, 0.4), (0.1, 0.11, 0.15)), orb=((0.55, 0.65, 0.8), (1.0, 1.0, 1.0)), gem=(0.75, 0.9, 1.0)),
    "Gold": dict(main=((1.0, 0.85, 0.15), (0.85, 0.32, 0.0)), light=((1.0, 0.95, 0.5), (1.0, 0.55, 0.05)), dark=((0.45, 0.18, 0.02), (0.18, 0.05, 0.0)), orb=((0.95, 0.5, 0.1), (1.0, 0.95, 0.75)), gem=(1.0, 0.8, 0.25)),
    "Platinum": dict(main=((0.55, 1.0, 0.85), (0.05, 0.45, 0.42)), light=((0.85, 1.0, 0.95), (0.2, 0.7, 0.62)), dark=((0.04, 0.25, 0.25), (0.01, 0.09, 0.1)), orb=((0.1, 0.7, 0.6), (0.85, 1.0, 0.95)), gem=(0.4, 1.0, 0.85)),
    "Diamond": dict(main=((0.55, 0.85, 1.0), (0.05, 0.25, 0.75)), light=((0.85, 0.97, 1.0), (0.25, 0.55, 1.0)), dark=((0.03, 0.12, 0.4), (0.01, 0.03, 0.15)), orb=((0.1, 0.4, 1.0), (0.85, 0.97, 1.0)), gem=(0.45, 0.85, 1.0)),
    "Mighty": dict(main=((0.85, 0.55, 1.0), (0.32, 0.06, 0.6)), light=((0.95, 0.85, 1.0), (0.6, 0.3, 0.95)), dark=((0.18, 0.03, 0.35), (0.06, 0.0, 0.14)), orb=((0.55, 0.1, 0.95), (1.0, 0.85, 1.0)), gem=(0.85, 0.45, 1.0)),
    "Almighty": dict(main=((1.0, 0.88, 0.25), (0.8, 0.28, 0.0)), light=((1.0, 0.97, 0.6), (1.0, 0.6, 0.1)), dark=((0.55, 0.03, 0.03), (0.2, 0.0, 0.01)), orb=((0.9, 0.05, 0.05), (1.0, 0.85, 0.3)), gem=(1.0, 0.2, 0.15)),
}


def mats(rank):
    p = PAL[rank]
    return dict(
        main=metal(rank + "Main", *p["main"]),
        light=metal(rank + "Light", *p["light"], rough=0.15),
        dark=metal(rank + "Dark", *p["dark"], rough=0.3),
        orb=orbmat(rank + "Orb", *p["orb"]),
        gem=glow(rank + "Gem", p["gem"], 1.3, base=p["gem"]),
        crown=metal("CrownGold", (1.0, 0.86, 0.2), (0.85, 0.35, 0.0), rough=0.18),
        halo=glow("HaloGold", (1.0, 0.7, 0.15), 2.0, base=(1.0, 0.75, 0.2)),
    )


def body(shape, m, k=1.0):
    half = scale_pts(SHAPES[shape], k)
    outline_obj("Body", full(half), 0.16, 0.06, m["main"], z=0)
    outline_obj("Inner", full(scale_pts(half, 0.78, -0.02)), 0.08, 0.04, m["dark"], z=0.2)
    torus("Ring", 0.44 * k, 0.07 * k, (0, -0.32, 0.03), m["light"])
    sphere("Orb", 0.4 * k, (0, -0.12, 0.03), m["orb"])


def crown(m, y=0.86, w=0.5, h=0.32, points=5):
    def tall(i):
        return h * (1.25 if i == points // 2 else (1.0 if i % 2 == 0 else 0.75))
    pts = [(-w, y)]
    for i in range(points):
        pts.append((-w + 2 * w * i / points, y + 0.06))
        pts.append((-w + 2 * w * (i + 0.5) / points, y + tall(i)))
    pts += [(w, y + 0.06), (w, y), (w * 0.9, y - 0.12), (-w * 0.9, y - 0.12)]
    ob = outline_obj("Crown", pts, 0.08, 0.035, m["crown"], z=0.28)
    ob.location.z = 0.08
    for i in range(points):
        sphere("CrownBall" + str(i), 0.055, (-w + 2 * w * (i + 0.5) / points, -0.4, y + tall(i) + 0.08), m["gem"])


def spikes(m, n, y=0.78, spread=0.3, h=0.42):
    for i in range(n):
        t = (i / (n - 1) - 0.5) * 2 if n > 1 else 0
        x, tall = t * spread, h * (1 - 0.35 * abs(t))
        outline_obj("Spike" + str(i), [(x - 0.09, y), (x, y + tall), (x + 0.09, y), (x, y - 0.1)], 0.06, 0.025, m["light"], z=0.06)


def build(rank):
    for o in list(bpy.data.objects):
        if o.type in ("MESH", "CURVE"):
            bpy.data.objects.remove(o, do_unlink=True)
    m = mats(rank)
    if rank == "Bronze":
        body("plain", m, 0.92)
        gem("TopGem", 0.1, 0.12, (0, -0.4, 0.86), m["gem"], sides=4, scale=(1, 1, 1.3))
    elif rank == "Silver":
        body("flared", m, 0.95)
        gem("TopGem", 0.12, 0.14, (0, -0.4, 0.92), m["gem"], sides=4, scale=(1.1, 1.1, 1.5))
        wings([m["light"]], 2, 0.55, (25, -10), ox=0.5, oy=0.25, width=0.26, curl=0.1)
    elif rank == "Gold":
        body("crest", m)
        gem("TopGem", 0.17, 0.2, (0, -0.4, 0.95), m["gem"], sides=4, scale=(1.3, 1.3, 1.9))
        wings([m["light"], m["main"]], 4, 0.9, (42, -22), oy=0.12, curl=0.16)
    elif rank == "Platinum":
        body("crest", m)
        spikes(m, 3)
        gem("TopGem", 0.17, 0.2, (0, -0.42, 0.98), m["gem"], sides=6, scale=(1.3, 1.3, 1.9))
        wings([m["light"], m["main"]], 5, 1.0, (48, -28), oy=0.12, curl=0.2)
    elif rank == "Diamond":
        body("crest", m, 1.02)
        gem("TopGem", 0.26, 0.3, (0, -0.42, 1.0), m["gem"], sides=4, scale=(1.0, 1.0, 1.8))
        for s in (-1, 1):
            g = gem("SideGem" + str(s), 0.12, 0.14, (s * 0.38, -0.36, 0.9), m["gem"], sides=4, scale=(0.8, 0.8, 1.6))
            g.rotation_euler[1] = math.radians(-25 * s)
        wings([m["light"], m["main"]], 6, 1.12, (55, -32), width=0.34, curl=0.22)
    elif rank == "Mighty":
        body("crest", m, 1.02)
        crown(m, y=0.86, w=0.46, h=0.34)
        wings([m["light"], m["main"]], 6, 1.2, (60, -35), width=0.36, curl=0.26)
        wings([m["dark"]], 3, 0.8, (-40, -70), z=0.12, ox=0.45, oy=-0.3, width=0.26, curl=-0.1, prefix="Tail")
    elif rank == "Almighty":
        torus("Halo", 1.2, 0.06, (0, 0.5, 0.25), m["halo"])
        body("crest", m, 1.04)
        crown(m, y=0.88, w=0.5, h=0.4)
        wings([m["main"], m["crown"]], 7, 1.3, (66, -36), width=0.38, curl=0.3)
        wings([m["dark"], m["main"]], 4, 0.95, (-30, -72), z=0.12, ox=0.45, oy=-0.3, width=0.28, curl=-0.12, prefix="Tail")


# ------------------------------------------------------------------------------- the stage

def stage():
    sc = bpy.context.scene
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    cam = link(bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam")))
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = 3.4
    cam.location = (0, -10, 0.1)
    cam.rotation_euler = (math.radians(90), 0, 0)
    sc.camera = cam
    for name, loc, energy, size, color in (
        ("Key", (-4, -6, 5), 450, 5, (1, 1, 1)),
        ("Rim", (5, 3, 4), 350, 4, (1, 0.95, 0.85)),
        ("Fill", (2, -6, -4), 125, 6, (0.8, 0.85, 1)),
        ("Top", (0, -2, 7), 200, 3, (1, 1, 1)),
    ):
        light = bpy.data.lights.new(name, "AREA")
        light.energy, light.size, light.color = energy, size, color
        o = link(bpy.data.objects.new(name, light))
        o.location = loc
        o.rotation_euler = (-Vector(loc)).to_track_quat("-Z", "Y").to_euler()
    # a dark studio with one bright band a little above the horizon, for the metals to reflect
    w = bpy.data.worlds.get("RankWorld") or bpy.data.worlds.new("RankWorld")
    sc.world = w
    w.use_nodes = True
    nt = w.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    out = nt.nodes.new("ShaderNodeOutputWorld")
    bg = nt.nodes.new("ShaderNodeBackground")
    tc = nt.nodes.new("ShaderNodeTexCoord")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    mr = nt.nodes.new("ShaderNodeMapRange")
    mr.inputs["From Min"].default_value = -1
    mr.inputs["From Max"].default_value = 1
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    cr = ramp.color_ramp
    while len(cr.elements) < 5:
        cr.elements.new(0.5)
    for e, (p, c) in zip(cr.elements, [(0.0, (0.01, 0.01, 0.015)), (0.48, (0.02, 0.02, 0.03)), (0.56, (1.2, 1.15, 1.1)), (0.64, (0.05, 0.05, 0.06)), (1.0, (0.6, 0.6, 0.65))]):
        e.position, e.color = p, (*c, 1)
    nt.links.new(tc.outputs["Generated"], sep.inputs[0])
    nt.links.new(sep.outputs["Z"], mr.inputs["Value"])
    nt.links.new(mr.outputs[0], ramp.inputs["Fac"])
    nt.links.new(ramp.outputs["Color"], bg.inputs["Color"])
    nt.links.new(bg.outputs[0], out.inputs[0])
    r = sc.render
    r.resolution_x = r.resolution_y = 1024
    r.film_transparent = True
    r.image_settings.file_format = "PNG"
    r.image_settings.color_mode = "RGBA"
    sc.view_settings.view_transform = "Standard"
    sc.eevee.use_raytracing = True


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    out = argv[0] if argv else os.path.join(os.path.dirname(bpy.data.filepath) or ".", "rank_renders")
    os.makedirs(out, exist_ok=True)
    stage()
    for rank in PAL:
        build(rank)
        bpy.context.scene.render.filepath = os.path.join(out, "Rank" + rank + ".png")
        bpy.ops.render.render(write_still=True)
    print("rendered into", out)


if __name__ == "__main__":
    main()
