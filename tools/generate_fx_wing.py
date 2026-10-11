"""The toon wing and feather (the owner: "can you make these more like actual wings", "add an
angel jump effect with angel wings"): Blue Phoenix and Angel wear the wing, Angel drops the
feathers. Our own drawing.

  fx_wing.png    one right wing on a square card, its shoulder at ROOT: the arm arches up to a
                 high wrist, broad overlapping feathers hang off it (rows of coverts, secondaries
                 forming the trailing edge, long primaries sweeping down and out to the tip)
  fx_feather.png one loose feather, quill along the card's height

White, with grey lines between feathers and a grey shade on each feather's trailing half; the
game tints them. Written to art/tex (1024x675 and 256). The cards go on art/SpikeRushFX6.fbx as FX_Wing
and FX_Feather.
Run: python tools/generate_fx_wing.py
"""
from pathlib import Path
import math

from PIL import Image, ImageDraw

N = 1024
SS = 2  # supersampling
W = N * SS
ROOT = (0.06, 0.42)  # the shoulder, as a share of the square (x right, y down)
CROP = 0.66
TEX = Path(__file__).resolve().parent.parent / "art" / "tex"


def bez(p, t):
    u = 1 - t
    return (u ** 3 * p[0][0] + 3 * u * u * t * p[1][0] + 3 * u * t * t * p[2][0] + t ** 3 * p[3][0],
            u ** 3 * p[0][1] + 3 * u * u * t * p[1][1] + 3 * u * t * t * p[2][1] + t ** 3 * p[3][1])


# the arm: the shoulder, arching up to the wrist high and out, then the hand bending down a little
ARM = (ROOT, (0.14, 0.12), (0.34, 0.03), (0.5, 0.06))
HAND = ((0.5, 0.06), (0.56, 0.08), (0.6, 0.11), (0.63, 0.15))


def arm(t):
    return bez(ARM, t) if t <= 1 else bez(HAND, t - 1)


def leaf(d, base, ang, length, width, shade, line, scale=W, edge=0.006):
    """A feather: from base along ang, a rounded pointed tip, the trailing half shaded."""
    ca, sa = math.cos(ang), math.sin(ang)
    nx, ny = -sa, ca

    def ring(grow):
        pts_l, pts_r = [], []
        for i in range(17):
            s = i / 16
            prof = (math.sin(math.pi * min(1, s / 0.75) / 2) ** 0.5) if s < 0.75 else math.cos((s - 0.75) / 0.25 * math.pi / 2) ** 0.7
            w = width * prof + grow
            L = length + grow
            pts_l.append(((base[0] + ca * s * L + nx * w) * scale, (base[1] + sa * s * L + ny * w) * scale))
            pts_r.append(((base[0] + ca * s * L - nx * w) * scale, (base[1] + sa * s * L - ny * w) * scale))
        return pts_l, pts_r

    ol, orr = ring(edge)
    d.polygon(ol + orr[::-1], fill=(line, line, line, 255))
    il, ir = ring(0)
    d.polygon(il + ir[::-1], fill=(shade, shade, shade, 255))
    mid = [((base[0] + ca * s / 16 * length) * scale, (base[1] + sa * s / 16 * length) * scale) for s in range(17)]
    dark = int(shade * 0.8)
    d.polygon(ir + mid[::-1], fill=(dark, dark, dark, 255))


img = Image.new("RGBA", (W, W), (0, 0, 0, 0))
d = ImageDraw.Draw(img)

# primaries (drawn first, at the back): from the hand, fanning from out-and-down at the tip to
# straight down under the wrist, longest at the outside
for i in range(8):
    f = i / 7
    t = 2.0 - 0.45 * f  # from the hand's end back toward the wrist
    b = arm(t)
    ang = math.radians(42 + 46 * f)  # 42 deg below horizontal at the tip, 88 under the wrist
    feather_len = 0.6 - 0.1 * f
    leaf(d, b, ang, feather_len, 0.075, 228, 110)
# secondaries: along the forearm, hanging down, getting shorter toward the shoulder (the trailing
# edge curving up into the body)
for i in range(9):
    f = i / 8
    t = 0.95 - 0.85 * f
    b = arm(t)
    ang = math.radians(90 + 12 * f)
    leaf(d, b, ang, 0.5 - 0.28 * f, 0.075, 238, 120)
# greater coverts: a row over the feathers' roots
for i in range(12):
    f = i / 11
    t = 1.75 - 1.65 * f
    b = arm(t)
    ang = math.radians(60 + 35 * f)
    leaf(d, b, ang, 0.24 - 0.08 * f, 0.06, 248, 140)
# lesser coverts: small scallops along the arm
for i in range(14):
    f = i / 13
    t = 1.5 - 1.45 * f
    b = arm(t)
    ang = math.radians(70 + 25 * f)
    leaf(d, b, ang, 0.1, 0.045, 255, 160)
# the leading edge: a smooth white band along the arm
pts = [arm(i / 30 * 1.6) for i in range(31)]
for i in range(30):
    w = (0.06 - 0.035 * i / 30) * W
    x, y = pts[i][0] * W, pts[i][1] * W
    d.ellipse([x - w / 2, y - w / 2, x + w / 2, y + w / 2], fill=(255, 255, 255, 255))

# the bottom third is empty: the card is cropped to the top CROP of the square (the shoulder sits
# at ROOT[0], ROOT[1] / CROP on the cropped card)
img.resize((N, N), Image.LANCZOS).crop((0, 0, N, int(N * CROP))).save(TEX / "fx_wing.png")
print("wrote", TEX / "fx_wing.png")

# a loose feather: quill up the card's middle, tip at the top
F = 256 * SS
fe = Image.new("RGBA", (F, F), (0, 0, 0, 0))
leaf(ImageDraw.Draw(fe), (0.5, 0.95), -math.pi / 2, 0.9, 0.17, 245, 140, scale=F, edge=0.02)
dq = ImageDraw.Draw(fe)
dq.line([(0.5 * F, 0.97 * F), (0.5 * F, 0.15 * F)], fill=(170, 170, 170, 255), width=int(0.015 * F))
fe.resize((256, 256), Image.LANCZOS).save(TEX / "fx_feather.png")
print("wrote", TEX / "fx_feather.png")
