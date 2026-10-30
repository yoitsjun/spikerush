#!/usr/bin/env python3
"""Draw our own UI and ability icons, the plate slant and the halftone texture into assets/ui.

Every icon here replaces a Creator Store image another creator made (2026-10-28, so the game
holds no art someone else could claim): white glyphs on clear, 256 px, tinted in code. Drawn at
4x and scaled down for smooth edges. The slant is the right triangle Gui.plate mirrors into its
caps (right angle bottom left); the halftone is an opaque black-to-white dot fade.

    python3 tools/generate_ui_icons.py      -> assets/ui/*.png
"""
import math
import random
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "assets" / "ui"
S = 1024  # drawing size (4x)
W = (255, 255, 255, 255)
CLEAR = (0, 0, 0, 0)


def canvas():
    img = Image.new("RGBA", (S, S), CLEAR)
    return img, ImageDraw.Draw(img)


def finish(img, name, size=256):
    OUT.mkdir(parents=True, exist_ok=True)
    img.resize((size, size), Image.LANCZOS).save(OUT / (name + ".png"))
    print("wrote", name)


def line(d, pts, w, fill=W):
    """A thick polyline with round joints and caps."""
    d.line(pts, fill=fill, width=w, joint="curve")
    r = w / 2
    for x, y in (pts[0], pts[-1]):
        d.ellipse((x - r, y - r, x + r, y + r), fill=fill)


def ring(d, cx, cy, r, w, fill=W):
    d.ellipse((cx - r, cy - r, cx + r, cy + r), outline=fill, width=w)


def disc(d, cx, cy, r, fill=W):
    d.ellipse((cx - r, cy - r, cx + r, cy + r), fill=fill)


def poly_at(pts, cx, cy, ang, sc=1.0):
    c, s = math.cos(ang), math.sin(ang)
    return [(cx + (x * c - y * s) * sc, cy + (x * s + y * c) * sc) for x, y in pts]


def cut(img, shape_fn):
    """Erase what shape_fn draws (alpha 0) from img."""
    mask = Image.new("L", img.size, 0)
    shape_fn(ImageDraw.Draw(mask))
    a = img.getchannel("A")
    a.paste(0, mask=mask)
    img.putalpha(a)


# ---------------------------------------------------------------------------------- menu icons

def home():
    img, d = canvas()
    d.polygon([(512, 150), (870, 470), (790, 470), (790, 860), (234, 860), (234, 470), (154, 470)], fill=W)
    cut(img, lambda m: m.rounded_rectangle((440, 620, 584, 860), radius=24, fill=255))
    finish(img, "IconHome")


def settings():
    img, d = canvas()
    cx = cy = 512
    teeth = 8
    pts = []
    for i in range(teeth * 4):
        a = 2 * math.pi * i / (teeth * 4) - math.pi / 2
        r = 380 if (i % 4) in (1, 2) else 300
        pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    d.polygon(pts, fill=W)
    disc(d, cx, cy, 300)
    cut(img, lambda m: m.ellipse((cx - 130, cy - 130, cx + 130, cy + 130), fill=255))
    finish(img, "IconSettings")


def shop():
    img, d = canvas()
    line(d, [(120, 220), (240, 220), (330, 640), (780, 640)], 70)
    d.polygon([(270, 300), (880, 300), (820, 560), (320, 560)], fill=W)
    disc(d, 380, 790, 72)
    disc(d, 720, 790, 72)
    finish(img, "IconShop")


def players():
    img, d = canvas()
    # the one behind, then the one in front with a gap around them
    disc(d, 670, 360, 120)
    d.pieslice((470, 520, 870, 920), 180, 360, fill=W)
    d.rectangle((470, 720, 870, 800), fill=W)
    cut(img, lambda m: (m.ellipse((240, 220, 600, 580), fill=255), m.pieslice((130, 500, 710, 1080), 180, 360, fill=255)))
    disc(d, 420, 400, 150)
    d.pieslice((170, 580, 670, 1080), 180, 360, fill=W)
    d.rectangle((170, 830, 670, 860), fill=W)
    finish(img, "IconPlayers")


def trophy():
    img, d = canvas()
    d.chord((260, 40, 764, 640), 0, 180, fill=W)
    d.rectangle((260, 150, 764, 340), fill=W)
    ring(d, 250, 330, 130, 56)
    ring(d, 774, 330, 130, 56)
    cut(img, lambda m: m.rectangle((300, 150, 724, 340), fill=0))  # keep the cup solid
    d.rectangle((260, 150, 764, 340), fill=W)
    d.rectangle((462, 600, 562, 760), fill=W)
    d.rounded_rectangle((300, 760, 724, 870), radius=20, fill=W)
    finish(img, "IconRanks")


def shirt():
    img, d = canvas()
    d.polygon([(370, 170), (440, 170), (512, 250), (584, 170), (654, 170), (900, 330), (810, 500),
               (730, 450), (730, 860), (294, 860), (294, 450), (214, 500), (124, 330)], fill=W)
    finish(img, "IconLocker")


def help_icon():
    from PIL import ImageFont
    img, d = canvas()
    disc(d, 512, 512, 420)
    font = None
    for path in ("C:/Windows/Fonts/ariblk.ttf", "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"):
        if Path(path).exists():
            font = ImageFont.truetype(path, 620)
            break
    cut(img, lambda m: m.text((512, 540), "?", font=font, fill=255, anchor="mm"))
    finish(img, "IconHelp")


def back():
    img, d = canvas()
    line(d, [(560, 230), (280, 512), (560, 794)], 110)
    line(d, [(300, 512), (800, 512)], 110)
    finish(img, "IconBack")


def lock():
    img, d = canvas()
    d.arc((300, 150, 724, 600), 180, 360, fill=W, width=90)
    d.rectangle((300, 360, 390, 470), fill=W)
    d.rectangle((634, 360, 724, 470), fill=W)
    d.rounded_rectangle((220, 450, 804, 900), radius=60, fill=W)
    cut(img, lambda m: (m.ellipse((462, 580, 562, 680), fill=255), m.rectangle((490, 640, 534, 780), fill=255)))
    finish(img, "IconLock")


def flag():
    img, d = canvas()
    d.rounded_rectangle((220, 120, 290, 910), radius=30, fill=W)
    d.polygon([(290, 150), (560, 200), (820, 150), (820, 540), (560, 590), (290, 540)], fill=W)
    finish(img, "IconForfeit")


def hourglass():
    img, d = canvas()
    d.rounded_rectangle((220, 110, 804, 190), radius=30, fill=W)
    d.rounded_rectangle((220, 834, 804, 914), radius=30, fill=W)
    d.polygon([(280, 190), (744, 190), (744, 260), (560, 512), (744, 764), (744, 834), (280, 834), (280, 764), (464, 512), (280, 260)], fill=W)
    # glass hollow, sand left in the bottom bulb and a trickle
    cut(img, lambda m: (m.polygon([(350, 250), (674, 250), (512, 470)], fill=255),
                        m.polygon([(512, 560), (680, 790), (344, 790)], fill=255)))
    d.polygon([(512, 640), (650, 790), (374, 790)], fill=W)
    d.rectangle((500, 500, 524, 650), fill=W)
    finish(img, "IconTimeout")


def star():
    img, d = canvas()
    pts = []
    for i in range(10):
        a = -math.pi / 2 + i * math.pi / 5
        r = 440 if i % 2 == 0 else 190
        pts.append((512 + r * math.cos(a), 540 + r * math.sin(a)))
    d.polygon(pts, fill=W)
    finish(img, "IconStar")


def flame(name):
    img, d = canvas()
    # an outer flame licking up in three tongues, a hollow core with an inner tongue
    outer = [(512, 940), (330, 900), (220, 760), (210, 590), (290, 430), (330, 520), (390, 300),
             (470, 180), (520, 70), (560, 230), (650, 330), (700, 230), (780, 420), (820, 600),
             (800, 780), (690, 900)]
    d.polygon(outer, fill=W)
    d.ellipse((220, 560, 804, 950), fill=W)
    cut(img, lambda m: m.polygon([(512, 870), (410, 820), (370, 700), (430, 560), (470, 620), (520, 470),
                                   (590, 600), (640, 700), (610, 820)], fill=255))
    finish(img, name)


def shield(name):
    img, d = canvas()
    d.polygon([(512, 100), (850, 220), (830, 560), (700, 780), (512, 930), (324, 780), (194, 560), (174, 220)], fill=W)
    cut(img, lambda m: m.polygon([(512, 210), (740, 290), (726, 540), (630, 710), (512, 810), (512, 210)], fill=255))
    d.polygon([(512, 260), (690, 320), (680, 530), (600, 670), (512, 750)], fill=W)
    finish(img, name)


def jump(name):
    img, d = canvas()
    # a figure springing up off a line, two chevrons above
    disc(d, 600, 300, 80)
    line(d, [(560, 410), (470, 600)], 90)          # body
    line(d, [(540, 450), (700, 380), (790, 250)], 70)   # arm up
    line(d, [(520, 470), (380, 420), (300, 300)], 70)   # other arm
    line(d, [(470, 600), (600, 700), (560, 840)], 76)   # leg
    line(d, [(470, 600), (340, 690), (250, 650)], 76)   # trailing leg
    line(d, [(140, 920), (884, 920)], 50)
    line(d, [(720, 170), (800, 100), (880, 170)], 50)
    finish(img, name)


def speed():
    img, d = canvas()
    # a forward double chevron with three speed lines behind it
    d.polygon([(470, 200), (800, 512), (470, 824), (390, 744), (620, 512), (390, 280)], fill=W)
    d.polygon([(700, 200), (1000, 512), (700, 824), (620, 744), (850, 512), (620, 280)], fill=W)
    for y, x0 in ((360, 120), (512, 40), (664, 120)):
        line(d, [(x0, y), (x0 + 220, y)], 56)
    finish(img, "IconSpeed")


# ------------------------------------------------------------------------------- ability icons

def bolt():
    img, d = canvas()
    d.polygon([(600, 60), (240, 580), (480, 580), (380, 960), (790, 400), (540, 400), (680, 60)], fill=W)
    finish(img, "AbilityThunder")


def dragon():
    img, d = canvas()
    # a dragon's head in profile facing right: brow horn swept back, open jaw, a whisker
    head = [(160, 520), (260, 400), (420, 330), (600, 330), (760, 380), (900, 430), (930, 480),
            (800, 500), (900, 560), (880, 600), (720, 610), (600, 680), (440, 720), (300, 700)]
    d.polygon(head, fill=W)
    d.polygon([(420, 340), (280, 160), (560, 330)], fill=W)       # horn
    d.polygon([(560, 340), (520, 200), (660, 340)], fill=W)       # second horn
    d.polygon([(300, 690), (160, 860), (420, 720)], fill=W)       # jaw tuft
    line(d, [(860, 470), (960, 330), (1000, 250)], 30)            # whisker
    cut(img, lambda m: (m.polygon([(600, 420), (700, 430), (620, 470)], fill=255),   # eye slit
                        m.polygon([(800, 505), (900, 540), (720, 560)], fill=255)))  # mouth
    finish(img, "AbilityAzure")


def claws():
    img, d = canvas()
    for i, dx in enumerate((-230, 0, 230)):
        cx = 512 + dx
        top, bot = (cx + 150, 120 + abs(dx) * 0.2), (cx - 150, 900 - abs(dx) * 0.2)
        mid = ((top[0] + bot[0]) / 2 + 25, (top[1] + bot[1]) / 2)
        d.polygon([top, (mid[0] + 50, mid[1]), bot, (mid[0] - 20, mid[1])], fill=W)
    finish(img, "AbilityFeral")


def burst(name, points=12, r_out=470, r_in=240):
    img, d = canvas()
    rnd = random.Random(points)
    pts = []
    for i in range(points * 2):
        a = -math.pi / 2 + i * math.pi / points
        r = (r_out * rnd.uniform(0.82, 1.0)) if i % 2 == 0 else r_in
        pts.append((512 + r * math.cos(a), 512 + r * math.sin(a)))
    d.polygon(pts, fill=W)
    cut(img, lambda m: m.ellipse((392, 392, 632, 632), fill=255))
    disc(d, 512, 512, 80)
    finish(img, name)


def crosshair():
    img, d = canvas()
    ring(d, 512, 512, 330, 70)
    for a in range(4):
        ang = a * math.pi / 2
        x0, y0 = 512 + 180 * math.cos(ang), 512 + 180 * math.sin(ang)
        x1, y1 = 512 + 450 * math.cos(ang), 512 + 450 * math.sin(ang)
        line(d, [(x0, y0), (x1, y1)], 64)
    disc(d, 512, 512, 50)
    finish(img, "AbilityVector")


def zero_point():
    img, d = canvas()
    # a dot with four wedges closing in on it (a pinpoint, not a scope)
    disc(d, 512, 512, 90)
    for a in range(4):
        ang = math.pi / 4 + a * math.pi / 2
        d.polygon(poly_at([(170, 0), (430, -90), (430, 90)], 512, 512, ang), fill=W)
    ring(d, 512, 512, 470, 30)
    finish(img, "AbilityZeroPoint")


def circling_arrows():
    img, d = canvas()
    for start in (200, 20):
        d.arc((170, 170, 854, 854), start, start + 130, fill=W, width=90)
        a = math.radians(start + 130)
        cx, cy = 512 + 342 * math.cos(a), 512 + 342 * math.sin(a)
        d.polygon(poly_at([(0, -110), (150, 0), (0, 110)], cx, cy, a + math.pi / 2), fill=W)
    finish(img, "AbilityTurnabout")


def plunge():
    img, d = canvas()
    # (the owner, 2026-10-29: "just a straight line then a dip ---\"): a flat shaft off the hand,
    # a sharp turn down, the arrowhead on the tip, and speed lines behind
    turn, tip = (540, 300), (790, 860)
    ux, uy = tip[0] - turn[0], tip[1] - turn[1]
    n = (ux * ux + uy * uy) ** 0.5
    ux, uy = ux / n, uy / n
    px, py = -uy, ux
    back = (tip[0] - ux * 250, tip[1] - uy * 250)
    line(d, [(150, 300), turn, back], 120)
    d.polygon([tip, (back[0] + px * 170, back[1] + py * 170), (back[0] - px * 170, back[1] - py * 170)], fill=W)
    line(d, [(40, 170), (300, 170)], 50)
    line(d, [(40, 430), (240, 430)], 50)
    finish(img, "AbilityPlunge")


def rising_sun():
    img, d = canvas()
    d.pieslice((232, 380, 792, 940), 180, 360, fill=W)
    for i in range(7):
        a = math.pi + (i + 0.5) * math.pi / 7
        line(d, [(512 + 330 * math.cos(a), 660 + 330 * math.sin(a)), (512 + 460 * math.cos(a), 660 + 460 * math.sin(a))], 56)
    d.rounded_rectangle((100, 690, 924, 750), radius=30, fill=W)
    d.rounded_rectangle((220, 810, 804, 860), radius=25, fill=W)
    finish(img, "AbilityRisingSun")


def corona():
    img, d = canvas()
    # a sun with a flaring ring and long solar prominences
    disc(d, 512, 512, 220)
    ring(d, 512, 512, 290, 36)
    rnd = random.Random(7)
    for i in range(16):
        a = i * math.pi / 8
        L = 470 if i % 2 == 0 else 390
        w = 70 if i % 2 == 0 else 46
        d.polygon(poly_at([(320, -w / 2), (L, 0), (320, w / 2)], 512, 512, a + rnd.uniform(-0.05, 0.05)), fill=W)
    finish(img, "AbilityCorona")


def megaphone():
    img, d = canvas()
    d.polygon([(220, 400), (620, 200), (620, 820), (220, 620)], fill=W)
    d.rounded_rectangle((140, 390, 260, 630), radius=30, fill=W)
    d.polygon([(280, 610), (420, 640), (380, 860), (280, 840)], fill=W)
    for r in (300, 420):
        d.arc((620 - r + 120, 512 - r, 620 + r - 120, 512 + r), -40, 40, fill=W, width=50)
    finish(img, "AbilityRallyCry")


def crossed_swords():
    img, d = canvas()
    for flip in (1, -1):
        ang = math.radians(45 * flip)
        blade = [(-40, -430), (0, -500), (40, -430), (40, 220), (-40, 220)]
        guard = [(-160, 220), (160, 220), (160, 280), (-160, 280)]
        grip = [(-35, 280), (35, 280), (35, 430), (-35, 430)]
        for shape in (blade, guard, grip):
            d.polygon(poly_at(shape, 512, 512, ang, 0.9), fill=W)
        px, py = poly_at([(0, 470)], 512, 512, ang, 0.9)[0]
        disc(d, px, py, 50)
    finish(img, "AbilityCounter")


def skyward():
    img, d = canvas()
    # three chevrons climbing, the top one largest
    for i, (y, s) in enumerate(((760, 0.6), (540, 0.8), (290, 1.0))):
        d.polygon(poly_at([(-380, 160), (0, -170), (380, 160), (380, 280), (0, -40), (-380, 280)], 512, y, 0, s), fill=W)
    finish(img, "AbilitySkyward")


# ------------------------------------------------------------------------------------- others

def team_sun():
    img, d = canvas()
    ring(d, 512, 512, 210, 60)
    for i in range(8):
        a = i * math.pi / 4
        line(d, [(512 + 290 * math.cos(a), 512 + 290 * math.sin(a)), (512 + 450 * math.cos(a), 512 + 450 * math.sin(a))], 56)
    finish(img, "TeamSunrise")


def team_waves():
    img, d = canvas()
    for y in (300, 512, 724):
        pts = [(x, y + 70 * math.sin((x - 100) / 824 * 4 * math.pi)) for x in range(100, 925, 8)]
        d.line(pts, fill=W, width=80, joint="curve")
        for x, yy in (pts[0], pts[-1]):
            disc(d, x, yy, 40)
    finish(img, "TeamTidal")


def pumpkin():
    img, d = canvas()
    orange, dark, stem = (255, 132, 24, 255), (190, 74, 8, 255), (92, 120, 40, 255)
    d.rounded_rectangle((470, 120, 560, 290), radius=30, fill=stem)
    for x0, x1 in ((130, 560), (464, 894), (300, 724)):
        d.ellipse((x0, 240, x1, 900), fill=orange, outline=dark, width=18)
    face = (40, 18, 6, 255)
    d.polygon([(330, 470), (450, 470), (390, 380)], fill=face)
    d.polygon([(574, 470), (694, 470), (634, 380)], fill=face)
    d.polygon([(250, 600), (330, 640), (400, 600), (470, 650), (554, 650), (624, 600), (694, 640), (774, 600),
               (700, 790), (512, 830), (324, 790)], fill=face)
    finish(img, "CardPumpkin")


def gift():
    img, d = canvas()
    d.rectangle((170, 420, 854, 560), fill=W)
    d.rectangle((220, 560, 804, 900), fill=W)
    cut(img, lambda m: m.rectangle((470, 420, 554, 900), fill=255))
    d.rectangle((486, 420, 538, 900), fill=W)
    d.ellipse((290, 210, 510, 420), outline=W, width=60)
    d.ellipse((514, 210, 734, 420), outline=W, width=60)
    finish(img, "IconGift")


def calendar():
    img, d = canvas()
    d.rounded_rectangle((160, 200, 864, 880), radius=60, fill=W)
    cut(img, lambda m: [m.rectangle((230 + c * 150, 420 + r * 140, 330 + c * 150, 500 + r * 140), fill=255)
                        for r in range(3) for c in range(4)])
    for x in (330, 694):
        d.rounded_rectangle((x - 30, 120, x + 30, 280), radius=30, fill=W)
    finish(img, "IconDaily")


def ticket():
    img, d = canvas()
    d.rounded_rectangle((110, 280, 914, 744), radius=50, fill=W)
    cut(img, lambda m: (m.ellipse((50, 452, 170, 572), fill=255), m.ellipse((854, 452, 974, 572), fill=255),
                        [m.rectangle((630, y, 660, y + 50), fill=255) for y in range(320, 720, 90)]))
    finish(img, "IconCode")


def wrench():
    img, d = canvas()
    d.polygon(poly_at([(-60, -250), (60, -250), (60, 330), (-60, 330)], 512, 512, math.radians(45)), fill=W)
    hx, hy = poly_at([(0, -320)], 512, 512, math.radians(45))[0]
    disc(d, hx, hy, 190)
    cut(img, lambda m: m.polygon(poly_at([(-70, -560), (70, -560), (70, -330), (-70, -330)], 512, 512, math.radians(45)), fill=255))
    tx, ty = poly_at([(0, 330)], 512, 512, math.radians(45))[0]
    disc(d, tx, ty, 90)
    finish(img, "IconAdmin")


def slant():
    img = Image.new("RGBA", (S, S), CLEAR)
    ImageDraw.Draw(img).polygon([(0, 0), (0, S), (S, S)], fill=W)
    finish(img, "Slant")


def halftone(w=840, h=650):
    """Opaque: black at the top, white at the bottom, a ragged band of growing dots between."""
    img = Image.new("RGB", (w, h), (0, 0, 0))
    d = ImageDraw.Draw(img)
    rnd = random.Random(11)
    step = 10
    # the edge where it turns white wanders like a cloud line
    edge = [0.45 + 0.12 * math.sin(x / w * 7.0) + 0.06 * math.sin(x / w * 19.0 + 1.3) for x in range(w)]
    for gy in range(0, h + step, step):
        for gx in range(0, w + step, step):
            e = edge[min(w - 1, gx)] * h
            t = (gy - (e - 0.3 * h)) / (0.45 * h)  # 0 above the band, 1 below it
            t = max(0.0, min(1.0, t + rnd.uniform(-0.12, 0.12)))
            r = t * step * 0.75
            if r > 0.4:
                d.ellipse((gx - r, gy - r, gx + r, gy + r), fill=(255, 255, 255))
    d.rectangle((0, int(0.86 * h), w, h), fill=(255, 255, 255))
    OUT.mkdir(parents=True, exist_ok=True)
    img.save(OUT / "Halftone.png")
    print("wrote Halftone")


def main():
    home(); settings(); shop(); players(); trophy(); shirt(); help_icon(); back(); lock(); flag()
    hourglass(); star(); flame("IconAttack"); flame("AbilityAdrenaline"); shield("IconDefense")
    shield("AbilityIronWall"); jump("IconJump"); speed()
    bolt(); dragon(); claws(); burst("AbilityChainReaction"); crosshair(); zero_point()
    circling_arrows(); plunge(); rising_sun(); corona(); megaphone(); crossed_swords(); skyward()
    team_sun(); team_waves(); pumpkin(); gift(); calendar(); ticket(); wrench(); slant(); halftone()


if __name__ == "__main__":
    main()
