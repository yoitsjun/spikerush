"""A tiny software renderer for a posed, blocky Roblox-style avatar (used by generate_icon.py).

The avatar is built from textured boxes (head, hair, torso, upper/lower arms and legs) posed
with joint rotations, rasterized with a z-buffer, cel-shaded, and outlined in ink like an anime
still. Textures are drawn procedurally at full resolution, modelled on the owner's avatar: white
jacket with ink splatter over a black shirt, dark pants, light shoes, messy black hair and a
small purple accessory.
"""
import math
import random

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

INK = (20, 23, 43)

SKIN = (214, 168, 128)
JACKET = (234, 234, 228)
JACKET_SHADE = (196, 197, 194)
SPLAT = (58, 58, 60)
SHIRT = (22, 22, 25)
PANTS = (40, 40, 44)
PANTS_FOLD = (70, 70, 76)
SHOES = (212, 206, 192)
SOLE = (120, 116, 108)
HAIR = (22, 22, 26)
HAIR_SHINE = (70, 72, 86)
ACCESSORY = (168, 88, 150)
ACCESSORY_2 = (230, 140, 80)


# ------------------------------------------------------------------------------------------
# math
# ------------------------------------------------------------------------------------------

def rx(deg):
    a = math.radians(deg)
    c, s = math.cos(a), math.sin(a)
    return np.array([[1, 0, 0], [0, c, -s], [0, s, c]])


def ry(deg):
    a = math.radians(deg)
    c, s = math.cos(a), math.sin(a)
    return np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]])


def rz(deg):
    a = math.radians(deg)
    c, s = math.cos(a), math.sin(a)
    return np.array([[c, -s, 0], [s, c, 0], [0, 0, 1]])


class Frame:
    """A rigid transform: world = R @ local + t."""

    def __init__(self, R=None, t=None):
        self.R = np.eye(3) if R is None else R
        self.t = np.zeros(3) if t is None else np.asarray(t, dtype=float)

    def child(self, offset, R=None):
        """A joint at `offset` (in this frame) rotated by R (in this frame's axes)."""
        return Frame(self.R @ (np.eye(3) if R is None else R), self.R @ np.asarray(offset, dtype=float) + self.t)

    def point(self, p):
        return self.R @ np.asarray(p, dtype=float) + self.t


# ------------------------------------------------------------------------------------------
# textures (u to the viewer's right, v down, both 0..1)
# ------------------------------------------------------------------------------------------

def _canvas(color, size=256):
    img = Image.new("RGB", (size, size), color)
    return img, ImageDraw.Draw(img)


def _splatter(d, rnd, box, count, size):
    x0, y0, x1, y1 = box
    for _ in range(count):
        cx, cy = rnd.uniform(x0, x1), rnd.uniform(y0, y1)
        r = rnd.uniform(size * 0.3, size)
        color = SPLAT if rnd.random() < 0.7 else (100, 100, 102)
        d.ellipse([cx - r, cy - r * 0.8, cx + r, cy + r * 0.8], fill=color)
        for _ in range(rnd.randint(2, 6)):
            a = rnd.uniform(0, 2 * math.pi)
            L = r * rnd.uniform(1.2, 2.6)
            d.line([(cx, cy), (cx + L * math.cos(a), cy + L * math.sin(a))], fill=color, width=max(2, int(r * 0.25)))
            s = rnd.uniform(2, r * 0.35)
            px, py = cx + L * 1.15 * math.cos(a), cy + L * 1.15 * math.sin(a)
            d.ellipse([px - s, py - s, px + s, py + s], fill=color)
        if rnd.random() < 0.5:
            # a drip
            d.line([(cx, cy), (cx + rnd.uniform(-3, 3), cy + r * rnd.uniform(1.5, 3.5))], fill=color, width=max(2, int(r * 0.3)))


def textures(seed=7):
    rnd = random.Random(seed)
    T = {}

    # torso front: open white jacket over a black shirt
    img, d = _canvas(JACKET)
    d.polygon([(92, 0), (164, 0), (150, 256), (106, 256)], fill=SHIRT)
    d.line([(92, 0), (106, 256)], fill=(150, 150, 150), width=5)
    d.line([(164, 0), (150, 256)], fill=(150, 150, 150), width=5)
    d.polygon([(70, 0), (92, 0), (100, 70)], fill=JACKET_SHADE)  # lapels
    d.polygon([(186, 0), (164, 0), (156, 70)], fill=JACKET_SHADE)
    _splatter(d, rnd, (10, 90, 80, 220), 5, 16)
    _splatter(d, rnd, (176, 80, 246, 200), 5, 16)
    d.rectangle([0, 238, 256, 256], fill=JACKET_SHADE)
    T["torso_front"] = img

    img, d = _canvas(JACKET)
    _splatter(d, rnd, (40, 40, 216, 200), 9, 22)
    d.rectangle([0, 238, 256, 256], fill=JACKET_SHADE)
    T["torso_back"] = img

    img, d = _canvas(JACKET)
    _splatter(d, rnd, (30, 60, 226, 220), 3, 14)
    d.rectangle([0, 238, 256, 256], fill=JACKET_SHADE)
    T["torso_side"] = img
    T["torso_top"] = _canvas(JACKET_SHADE)[0]
    T["torso_bottom"] = _canvas(SHIRT)[0]

    # sleeves (upper and lower arm, the lower ending in a hand)
    img, d = _canvas(JACKET)
    _splatter(d, rnd, (20, 30, 236, 230), 3, 14)
    T["upper_arm"] = img
    img, d = _canvas(JACKET)
    _splatter(d, rnd, (20, 10, 236, 150), 2, 12)
    d.rectangle([0, 176, 256, 190], fill=JACKET_SHADE)  # cuff
    d.rectangle([0, 190, 256, 256], fill=SKIN)
    T["lower_arm"] = img
    T["hand"] = _canvas(SKIN)[0]

    # pants and shoes
    img, d = _canvas(PANTS)
    for _ in range(6):
        x = rnd.uniform(20, 236)
        d.line([(x, 0), (x + rnd.uniform(-20, 20), 256)], fill=PANTS_FOLD, width=rnd.randint(4, 9))
    T["upper_leg"] = img
    img, d = _canvas(PANTS)
    for _ in range(5):
        x = rnd.uniform(20, 236)
        d.line([(x, 0), (x + rnd.uniform(-25, 25), 190)], fill=PANTS_FOLD, width=rnd.randint(4, 9))
    d.rectangle([0, 196, 256, 256], fill=SHOES)
    d.rectangle([0, 238, 256, 256], fill=SOLE)
    T["lower_leg"] = img
    T["sole"] = _canvas(SOLE)[0]

    # head: skin, with the hair boxes on top
    T["skin"] = _canvas(SKIN)[0]
    img, d = _canvas(HAIR)
    for _ in range(5):
        x = rnd.uniform(0, 256)
        d.line([(x, rnd.uniform(0, 60)), (x + rnd.uniform(-30, 30), rnd.uniform(120, 256))], fill=HAIR_SHINE, width=2)
    T["hair"] = img
    T["accessory"] = _canvas(ACCESSORY)[0]
    T["accessory_2"] = _canvas(ACCESSORY_2)[0]
    return {k: np.asarray(v, dtype=float) for k, v in T.items()}


# ------------------------------------------------------------------------------------------
# geometry
# ------------------------------------------------------------------------------------------

# face -> (normal, corner function). Local axes: +X forward, +Y up, +Z the character's right.
def _faces(h):
    hx, hy, hz = h
    return {
        "front": ((1, 0, 0), lambda u, v: (hx, hy - 2 * hy * v, hz - 2 * hz * u)),
        "back": ((-1, 0, 0), lambda u, v: (-hx, hy - 2 * hy * v, -hz + 2 * hz * u)),
        "right": ((0, 0, 1), lambda u, v: (-hx + 2 * hx * u, hy - 2 * hy * v, hz)),
        "left": ((0, 0, -1), lambda u, v: (hx - 2 * hx * u, hy - 2 * hy * v, -hz)),
        "top": ((0, 1, 0), lambda u, v: (-hx + 2 * hx * v, hy, hz - 2 * hz * u)),
        "bottom": ((0, -1, 0), lambda u, v: (hx - 2 * hx * v, -hy, hz - 2 * hz * u)),
    }


class Box:
    def __init__(self, name, frame, size, center_offset, tex, group):
        self.name = name
        self.frame = frame
        self.half = np.asarray(size, dtype=float) / 2
        self.center = np.asarray(center_offset, dtype=float)
        self.tex = tex  # face -> texture key
        self.group = group  # boxes of one group don't get ink lines between them


def avatar_boxes(pose):
    """Build the posed avatar. pose: dict of joint -> rotation matrix (joint-local)."""
    g = pose.get
    root = Frame(pose["root"], (0, 0, 0))
    boxes = []

    def box(name, frame, size, off, tex, group=None):
        boxes.append(Box(name, frame, size, off, tex, group or name))

    torso_tex = {"front": "torso_front", "back": "torso_back", "right": "torso_side", "left": "torso_side", "top": "torso_top", "bottom": "torso_bottom"}
    box("torso", root, (1.0, 2.5, 2.0), (0, 0, 0), torso_tex)

    neck = root.child((0, 1.25, 0), g("neck"))
    head_tex = {k: "skin" for k in ("front", "back", "right", "left", "top", "bottom")}
    box("head", neck, (1.4, 1.4, 1.4), (0, 0.72, 0), head_tex, "head")
    hair = {k: "hair" for k in ("front", "back", "right", "left", "top", "bottom")}
    box("hair_cap", neck, (1.52, 0.55, 1.52), (-0.04, 1.3, 0), hair, "hair")
    box("hair_back", neck, (0.4, 1.2, 1.58), (-0.62, 0.92, 0), hair, "hair")
    box("hair_side_r", neck, (1.2, 0.7, 0.22), (-0.12, 1.02, 0.76), hair, "hair")
    box("hair_side_l", neck, (1.2, 0.7, 0.22), (-0.12, 1.02, -0.76), hair, "hair")
    # messy tufts sticking out all round, and bangs over the eyes
    rnd = random.Random(4)
    for i in range(22):
        a = -180 + i * (360 / 22) + rnd.uniform(-8, 8)
        tilt = rnd.uniform(-95, -55)
        tuft = neck.child((0, 1.3 + rnd.uniform(-0.15, 0.2), 0), ry(a) @ rz(tilt) @ rx(rnd.uniform(-25, 25)))
        box("tuft%d" % i, tuft, (0.26, 0.8 + rnd.uniform(0, 0.45), 0.26), (0.0, 0.9, 0), hair, "hair")
    for i in range(5):
        top = neck.child((rnd.uniform(-0.4, 0.3), 1.65, rnd.uniform(-0.45, 0.45)), rz(rnd.uniform(-35, 20)) @ rx(rnd.uniform(-30, 30)))
        box("crown%d" % i, top, (0.3, 0.55, 0.3), (0, 0.2, 0), hair, "hair")
    for i, z in enumerate((-0.5, -0.17, 0.17, 0.5)):
        bang = neck.child((0.7, 1.25, z), rz(rnd.uniform(-10, 12)) @ rx(rnd.uniform(-14, 14)))
        box("bang%d" % i, bang, (0.2, 0.62, 0.42), (0.02, -0.2, 0), hair, "hair")
    # the little accessory by the head
    acc = neck.child((0.1, 2.05, -0.95), rz(-15) @ rx(20))
    box("acc", acc, (0.22, 0.42, 0.22), (0, 0, 0), {k: "accessory" for k in ("front", "back", "right", "left", "top", "bottom")}, "acc")
    box("acc_w1", acc, (0.06, 0.3, 0.34), (0, 0.12, 0.2), {k: "accessory_2" for k in ("front", "back", "right", "left", "top", "bottom")}, "acc")
    box("acc_w2", acc, (0.06, 0.3, 0.34), (0, 0.12, -0.2), {k: "accessory_2" for k in ("front", "back", "right", "left", "top", "bottom")}, "acc")

    arm_up = {k: "upper_arm" for k in ("front", "back", "right", "left", "top")}
    arm_up["bottom"] = "upper_arm"
    arm_low = {k: "lower_arm" for k in ("front", "back", "right", "left", "top")}
    arm_low["bottom"] = "hand"
    leg_up = {k: "upper_leg" for k in ("front", "back", "right", "left", "top", "bottom")}
    leg_low = {k: "lower_leg" for k in ("front", "back", "right", "left", "top")}
    leg_low["bottom"] = "sole"

    hands = {}
    for side, z in (("r", 1.5), ("l", -1.5)):
        sh = root.child((0, 0.75, z), g("shoulder_" + side))
        box("uarm_" + side, sh, (1.0, 1.3, 1.0), (0, -0.15, 0), arm_up, "arm_" + side)
        el = sh.child((0, -0.8, 0), g("elbow_" + side))
        box("larm_" + side, el, (0.98, 1.25, 0.98), (0, -0.62, 0), arm_low, "arm_" + side)
        hands[side] = el.point((0, -1.25, 0))
    for side, z in (("r", 0.5), ("l", -0.5)):
        hip = root.child((0, -1.25, z), g("hip_" + side))
        box("uleg_" + side, hip, (1.0, 1.3, 1.0), (0, -0.65, 0), leg_up, "leg_" + side)
        kn = hip.child((0, -1.3, 0), g("knee_" + side))
        box("lleg_" + side, kn, (0.98, 1.25, 0.98), (0, -0.62, 0), leg_low, "leg_" + side)
    return boxes, hands


# ------------------------------------------------------------------------------------------
# camera and rasterizer
# ------------------------------------------------------------------------------------------

class Camera:
    def __init__(self, pos, target, fov, width, height):
        self.pos = np.asarray(pos, dtype=float)
        f = np.asarray(target, dtype=float) - self.pos
        f /= np.linalg.norm(f)
        r = np.cross(f, (0, 1, 0))
        r /= np.linalg.norm(r)
        u = np.cross(r, f)
        self.f, self.r, self.u = f, r, u
        self.w, self.h = width, height
        self.focal = (height / 2) / math.tan(math.radians(fov) / 2)

    def project(self, p):
        d = np.asarray(p, dtype=float) - self.pos
        z = d @ self.f
        x = d @ self.r
        y = d @ self.u
        return np.array([self.w / 2 + self.focal * x / z, self.h / 2 - self.focal * y / z]), z


def _homography(src, dst):
    A = []
    for (x, y), (X, Y) in zip(src, dst):
        A.append([x, y, 1, 0, 0, 0, -X * x, -X * y])
        A.append([0, 0, 0, x, y, 1, -Y * x, -Y * y])
    b = np.array([c for pt in dst for c in pt], dtype=float)
    h = np.linalg.solve(np.array(A, dtype=float), b)
    return np.append(h, 1).reshape(3, 3)


def render(boxes, cam, tex, light=(-0.4, 0.8, 0.45), fill=(0.3, -0.5, -0.6)):
    W, H = cam.w, cam.h
    color = np.zeros((H, W, 3))
    depth = np.full((H, W), np.inf)
    ids = np.full((H, W), -1, dtype=int)
    groups = np.full((H, W), -1, dtype=int)
    soft = np.zeros((H, W), dtype=bool)  # hair: no box-edge lines inside it, just the silhouette
    L = np.asarray(light, dtype=float)
    L /= np.linalg.norm(L)
    F = np.asarray(fill, dtype=float)
    F /= np.linalg.norm(F)
    group_index = {}
    face_id = 0
    for b in boxes:
        gi = group_index.setdefault(b.group, len(group_index))
        for face, (n_local, corner) in _faces(b.half).items():
            face_id += 1
            n = b.frame.R @ np.asarray(n_local, dtype=float)
            corners3 = [b.frame.point(b.center + np.asarray(corner(u, v))) for u, v in ((0, 0), (1, 0), (1, 1), (0, 1))]
            centre = sum(corners3) / 4
            if n @ (cam.pos - centre) <= 0:
                continue
            pts, zs = zip(*[cam.project(c) for c in corners3])
            if min(zs) <= 0.1:
                continue
            pts = np.array(pts)
            x0, y0 = np.floor(pts.min(axis=0)).astype(int)
            x1, y1 = np.ceil(pts.max(axis=0)).astype(int)
            x0, y0 = max(x0, 0), max(y0, 0)
            x1, y1 = min(x1, W - 1), min(y1, H - 1)
            if x1 < x0 or y1 < y0:
                continue
            Hm = _homography(pts, [(0, 0), (1, 0), (1, 1), (0, 1)])
            ys, xs = np.mgrid[y0:y1 + 1, x0:x1 + 1]
            q = np.stack([xs.ravel() + 0.5, ys.ravel() + 0.5, np.ones(xs.size)])
            uvw = Hm @ q
            u = uvw[0] / uvw[2]
            v = uvw[1] / uvw[2]
            inside = (u >= 0) & (u <= 1) & (v >= 0) & (v <= 1)
            if not inside.any():
                continue
            u, v = u[inside], v[inside]
            px, py = xs.ravel()[inside], ys.ravel()[inside]
            P = corners3[0][:, None] + np.outer(corners3[1] - corners3[0], u) + np.outer(corners3[3] - corners3[0], v)
            z = (P - cam.pos[:, None]).T @ cam.f
            closer = z < depth[py, px]
            if not closer.any():
                continue
            px, py, u, v, z = px[closer], py[closer], u[closer], v[closer], z[closer]
            t = tex[b.tex[face]]
            th, tw = t.shape[:2]
            c = t[np.clip((v * th).astype(int), 0, th - 1), np.clip((u * tw).astype(int), 0, tw - 1)]
            # cel shading: three bands of key light, a cool fill from below
            lam = max(0.0, float(n @ L))
            band = 1.0 if lam > 0.62 else (0.84 if lam > 0.22 else 0.68)
            fillv = max(0.0, float(n @ F)) * 0.18
            shaded = c * band + np.array([120, 150, 255]) * fillv
            color[py, px] = np.clip(shaded, 0, 255)
            depth[py, px] = z
            ids[py, px] = face_id
            groups[py, px] = gi
            soft[py, px] = b.group == "hair"
    return color, depth, ids, groups, soft


def ink(color, depth, ids, groups, soft, outline, inner):
    """Anime ink: a thick silhouette outline, lines where parts meet, thin lines on box edges."""
    H, W = depth.shape
    mask = np.isfinite(depth)
    out = np.zeros((H, W, 4), dtype=np.uint8)
    out[..., :3] = color.astype(np.uint8)
    out[..., 3] = mask * 255
    img = Image.fromarray(out, "RGBA")

    def edges(a, b, cond):
        e = np.zeros((H, W), dtype=bool)
        e[:, :-1] |= cond(a[:, :-1], a[:, 1:], b[:, :-1], b[:, 1:])
        e[:-1, :] |= cond(a[:-1, :], a[1:, :], b[:-1, :], b[1:, :])
        return e

    part = edges(groups, depth, lambda g0, g1, d0, d1: (g0 != g1) & (g0 >= 0) & (g1 >= 0))
    face = edges(ids, depth, lambda i0, i1, d0, d1: (i0 != i1) & (i0 >= 0) & (i1 >= 0))
    face &= ~soft
    # inside the hair only strands that stand clearly in front of others get a line
    finite = np.where(np.isfinite(depth), depth, 1e9)
    hair_line = edges(finite, soft, lambda d0, d1, s0, s1: s0 & s1 & (np.abs(d0 - d1) > 0.35))
    part |= hair_line
    line = Image.fromarray((part * 255).astype(np.uint8)).filter(ImageFilter.MaxFilter(inner * 2 + 1))
    thin = Image.fromarray((face * 255).astype(np.uint8)).filter(ImageFilter.MaxFilter(max(1, inner) | 1))
    ink_layer = Image.new("RGBA", (W, H), INK + (255,))
    img.paste(Image.new("RGBA", (W, H), (60, 62, 80, 255)), (0, 0), thin.point(lambda x: x * 0.55))
    img.paste(ink_layer, (0, 0), line)
    sil = Image.fromarray((mask * 255).astype(np.uint8)).filter(ImageFilter.MaxFilter(outline * 2 + 1))
    base = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    base.paste(ink_layer, (0, 0), sil)
    base.alpha_composite(img)
    return base


SPIKE_POSE = {
    # whole body: jackknifing into the swing, seen from the front-left
    "root": ry(-6) @ rz(-12),
    "neck": rz(-10),
    # hitting arm (the far one) high and out past the head, whipping through the ball
    "shoulder_r": rz(172) @ rx(-24),
    "elbow_r": rz(8),
    # the near arm down at the side
    "shoulder_l": rz(-14) @ rx(14),
    "elbow_l": rz(16),
    # legs kicked back, knees bent
    "hip_r": rz(-24) @ rx(-6),
    "knee_r": rz(-80),
    "hip_l": rz(14) @ rx(8),
    "knee_l": rz(-96),
}
HITTING_HAND = "r"


def render_spiker(height_px, pose=SPIKE_POSE, supersample=2):
    """The avatar spiking, seen from its front-left so it faces screen left, cropped to its
    silhouette and scaled to `height_px` tall. Returns the RGBA image and the hitting hand's
    pixel position in it."""
    S = int(height_px * 1.6) * supersample
    boxes, hands = avatar_boxes(pose)
    cam = Camera(pos=(12.0, -2.2, -12.0), target=(0.6, 0.8, 0), fov=30, width=S, height=S)
    tex = textures()
    color, depth, ids, groups, soft = render(boxes, cam, tex)
    img = ink(color, depth, ids, groups, soft, outline=3 * supersample, inner=1 * supersample)
    hand_px, _ = cam.project(hands[HITTING_HAND])
    x0, y0, x1, y1 = img.getbbox()
    pad = 4 * supersample
    x0, y0, x1, y1 = max(0, x0 - pad), max(0, y0 - pad), min(S, x1 + pad), min(S, y1 + pad)
    img = img.crop((x0, y0, x1, y1))
    k = height_px / img.size[1]
    img = img.resize((max(1, int(img.size[0] * k)), height_px), Image.LANCZOS)
    return img, ((hand_px[0] - x0) * k, (hand_px[1] - y0) * k)
