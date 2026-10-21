# Game pass icons (Config.Passes, Config.Perks), in the game icon's look: a glowing rayed
# background, a glossy emblem with a dark outline and chunky yellow words. Roblox shows pass icons
# cropped to a circle, so everything sits inside one. 512x512, drawn at 2x.
# Out: assets/passes/<Key>.png and a contact sheet assets/passes/_all.png.
import math, os
from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "assets", "passes")
GAME_ICON = os.path.join(HERE, "..", "assets", "icon", "GameIcon.png")
FONT = "C:/Windows/Fonts/seguibl.ttf"
S = 1024  # drawn at 2x
INK = (14, 20, 48, 255)
YELLOW = (255, 214, 40, 255)


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(len(a)))


def background(inner, outer):
    img = Image.new("RGBA", (S, S))
    px = img.load()
    c = S / 2
    for y in range(S):
        for x in range(S):
            d = min(1, math.hypot(x - c, y - c) / (S * 0.62))
            px[x, y] = lerp(inner, outer, d ** 1.3) + (255,)
    rays = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(rays)
    for i in range(18):
        a0 = math.radians(i * 20)
        a1 = a0 + math.radians(7)
        d.polygon([(c, c), (c + S * math.cos(a0), c + S * math.sin(a0)), (c + S * math.cos(a1), c + S * math.sin(a1))], fill=(255, 255, 255, 34))
    rays = rays.filter(ImageFilter.GaussianBlur(6))
    img.alpha_composite(rays)
    # a soft glow behind the emblem
    glow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(glow).ellipse((c - 300, c - 340, c + 300, c + 260), fill=(255, 255, 255, 70))
    img.alpha_composite(glow.filter(ImageFilter.GaussianBlur(60)))
    return img


def outlined(img, mask, fill_img, width=16, color=INK):
    # paste fill_img through mask with a dark outline around it
    edge = mask.filter(ImageFilter.MaxFilter(width * 2 + 1))
    img.alpha_composite(Image.composite(Image.new("RGBA", img.size, color), Image.new("RGBA", img.size, (0, 0, 0, 0)), edge))
    img.alpha_composite(Image.composite(fill_img, Image.new("RGBA", img.size, (0, 0, 0, 0)), mask))


def linear(colors, angle=90):
    # a vertical-ish gradient through `colors`, over the whole canvas
    img = Image.new("RGBA", (S, S))
    px = img.load()
    a = math.radians(angle)
    dx, dy = math.cos(a), math.sin(a)
    for y in range(S):
        for x in range(S):
            t = ((x - S / 2) * dx + (y - S / 2) * dy) / (S * 0.7) + 0.5
            t = max(0, min(0.9999, t))
            k = t * (len(colors) - 1)
            i = int(k)
            px[x, y] = lerp(colors[i], colors[i + 1], k - i) + (255,)
    return img


def gloss(img, box):
    # a white shine over the top of an emblem
    x0, y0, x1, y1 = box
    g = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(g).ellipse((x0 + (x1 - x0) * 0.15, y0 + (y1 - y0) * 0.06, x0 + (x1 - x0) * 0.6, y0 + (y1 - y0) * 0.36), fill=(255, 255, 255, 120))
    img.alpha_composite(g.filter(ImageFilter.GaussianBlur(14)))


def words(img, text, y, size, color=YELLOW):
    f = ImageFont.truetype(FONT, size)
    d = ImageDraw.Draw(img)
    w = d.textlength(text, font=f)
    while w > S * 0.74 and size > 60:
        size -= 6
        f = ImageFont.truetype(FONT, size)
        w = d.textlength(text, font=f)
    x = (S - w) / 2
    # a drop shadow, then the outlined words
    d.text((x + 8, y + 10), text, font=f, fill=(0, 0, 0, 110), stroke_width=22, stroke_fill=(0, 0, 0, 110))
    d.text((x, y), text, font=f, fill=color, stroke_width=22, stroke_fill=INK)


def sparkle(img, cx, cy, r, color=(255, 255, 255, 235)):
    d = ImageDraw.Draw(img)
    d.polygon([(cx, cy - r), (cx + r * 0.22, cy - r * 0.22), (cx + r, cy), (cx + r * 0.22, cy + r * 0.22), (cx, cy + r), (cx - r * 0.22, cy + r * 0.22), (cx - r, cy), (cx - r * 0.22, cy - r * 0.22)], fill=color)


GOLDS = [(255, 246, 190), (255, 210, 60), (230, 150, 20), (150, 80, 0)]


def crown(img, cx, cy, w):
    h = w * 0.72
    x0, y0 = cx - w / 2, cy - h / 2
    def P(u, v):
        return (x0 + u * w, y0 + v * h)
    pts = [P(0.04, 0.9), P(0.0, 0.3), P(0.25, 0.55), P(0.32, 0.1), P(0.5, 0.42), P(0.68, 0.1), P(0.75, 0.55), P(1.0, 0.3), P(0.96, 0.9)]
    m = Image.new("L", (S, S), 0)
    ImageDraw.Draw(m).polygon(pts, fill=255)
    ImageDraw.Draw(m).rounded_rectangle((x0, y0 + h * 0.74, x0 + w, y0 + h), radius=int(h * 0.08), fill=255)
    outlined(img, m, linear(GOLDS, 90), 16)
    d = ImageDraw.Draw(img)
    d.line([P(0.03, 0.76), P(0.97, 0.76)], fill=INK, width=10)
    for u, v in ((0.0, 0.3), (0.32, 0.1), (0.68, 0.1), (1.0, 0.3)):
        x, y = P(u, v)
        d.ellipse((x - 30, y - 30, x + 30, y + 30), fill=INK)
        d.ellipse((x - 20, y - 20, x + 20, y + 20), fill=(255, 250, 225, 255))
    for u, col in ((0.22, (40, 140, 255)), (0.5, (230, 30, 60)), (0.78, (40, 200, 110))):
        x, y = P(u, 0.87)
        r = 30 if u == 0.5 else 24
        d.ellipse((x - r - 8, y - r - 8, x + r + 8, y + r + 8), fill=INK)
        d.ellipse((x - r, y - r, x + r, y + r), fill=col + (255,))
        d.ellipse((x - r * 0.5, y - r * 0.6, x - r * 0.05, y - r * 0.15), fill=(255, 255, 255, 200))
    gloss(img, (x0, y0, x0 + w, y0 + h))


def vp_coin(img, cx, cy, r):
    m = Image.new("L", (S, S), 0)
    ImageDraw.Draw(m).ellipse((cx - r, cy - r, cx + r, cy + r), fill=255)
    bands = Image.new("RGBA", (S, S))
    bd = ImageDraw.Draw(bands)
    # the V Points ball: yellow, white and blue bands on a slant (Gui.icon.vp)
    a = math.radians(25)
    dx, dy = math.cos(a), math.sin(a)
    px = bands.load()
    for y in range(int(cy - r - 2), int(cy + r + 2)):
        for x in range(int(cx - r - 2), int(cx + r + 2)):
            t = ((x - cx) * dx + (y - cy) * dy) / (2 * r) + 0.5
            px[x, y] = (255, 205, 40, 255) if t < 0.36 else ((250, 250, 250, 255) if t < 0.66 else (34, 86, 196, 255))
    outlined(img, m, bands, 18)
    # seams between the bands, kept inside the ball
    seams = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    sd = ImageDraw.Draw(seams)
    for t in (0.36, 0.66):
        k = (t - 0.5) * 2 * r
        px0, py0 = cx + dx * k, cy + dy * k
        sd.line([(px0 - dy * 2 * r, py0 + dx * 2 * r), (px0 + dy * 2 * r, py0 - dx * 2 * r)], fill=INK, width=12)
    img.alpha_composite(Image.composite(seams, Image.new("RGBA", (S, S), (0, 0, 0, 0)), m))
    gloss(img, (cx - r, cy - r, cx + r, cy + r))


def clover(img, cx, cy, r):
    m = Image.new("L", (S, S), 0)
    md = ImageDraw.Draw(m)
    for k in range(4):
        a = math.radians(45 + k * 90)
        lx, ly = cx + math.cos(a) * r * 0.55, cy + math.sin(a) * r * 0.55
        b = a + math.pi / 2
        for s in (-1, 1):
            ox, oy = lx + math.cos(b) * s * r * 0.24, ly + math.sin(b) * s * r * 0.24
            md.ellipse((ox - r * 0.36, oy - r * 0.36, ox + r * 0.36, oy + r * 0.36), fill=255)
        tx, ty = cx + math.cos(a) * r * 0.08, cy + math.sin(a) * r * 0.08
        md.polygon([(tx, ty), (lx + math.cos(b) * r * 0.5, ly + math.sin(b) * r * 0.5), (lx - math.cos(b) * r * 0.5, ly - math.sin(b) * r * 0.5)], fill=255)
    stem = Image.new("L", (S, S), 0)
    ImageDraw.Draw(stem).line([(cx, cy), (cx + r * 0.25, cy + r * 0.7), (cx + r * 0.1, cy + r * 1.05)], fill=255, width=40, joint="curve")
    both = Image.composite(Image.new("L", (S, S), 255), m, stem)
    outlined(img, both, linear([(170, 255, 140), (60, 200, 80), (20, 120, 50)], 70), 16)
    d = ImageDraw.Draw(img)
    # the gaps between the four leaves, and each leaf's notch and vein
    for k in range(4):
        a = math.radians(k * 90)
        d.line([(cx, cy), (cx + math.cos(a) * r * 1.0, cy + math.sin(a) * r * 1.0)], fill=INK, width=22)
        a2 = math.radians(45 + k * 90)
        d.line([(cx + math.cos(a2) * r * 0.12, cy + math.sin(a2) * r * 0.12), (cx + math.cos(a2) * r * 0.62, cy + math.sin(a2) * r * 0.62)], fill=(30, 110, 50, 255), width=10)
    d.ellipse((cx - 26, cy - 26, cx + 26, cy + 26), fill=INK)
    d.ellipse((cx - 14, cy - 14, cx + 14, cy + 14), fill=(90, 200, 90, 255))
    gloss(img, (cx - r, cy - r, cx + r, cy + r))


def speaker(img, cx, cy, r):
    m = Image.new("L", (S, S), 0)
    md = ImageDraw.Draw(m)
    md.rounded_rectangle((cx - r * 0.95, cy - r * 0.32, cx - r * 0.45, cy + r * 0.32), radius=18, fill=255)
    md.polygon([(cx - r * 0.5, cy - r * 0.32), (cx + r * 0.1, cy - r * 0.78), (cx + r * 0.1, cy + r * 0.78), (cx - r * 0.5, cy + r * 0.32)], fill=255)
    outlined(img, m, linear([(255, 255, 255), (215, 225, 245), (140, 150, 190)], 90), 16)
    d = ImageDraw.Draw(img)
    for i, rr in enumerate((0.42, 0.72, 1.02)):
        box = (cx + r * 0.1 - r * rr, cy - r * rr, cx + r * 0.1 + r * rr, cy + r * rr)
        d.arc(box, -48, 48, fill=INK, width=64)
        d.arc(box, -46, 46, fill=(255, 214, 40, 255), width=40)
    gloss(img, (cx - r, cy - r * 0.8, cx + r * 0.2, cy + r * 0.8))


def burst(img, cx, cy, r):
    pts = []
    for i in range(28):
        a = math.radians(i * (360 / 28) - 90)
        rr = r if i % 2 == 0 else r * 0.68
        pts.append((cx + math.cos(a) * rr, cy + math.sin(a) * rr))
    m = Image.new("L", (S, S), 0)
    ImageDraw.Draw(m).polygon(pts, fill=255)
    outlined(img, m, linear([(255, 250, 200), (255, 200, 40), (255, 110, 20)], 90), 14)
    # the volleyball from the game icon, in the middle
    if os.path.exists(GAME_ICON):
        icon = Image.open(GAME_ICON).convert("RGBA").resize((1024, 1024), Image.LANCZOS)
        bx, by, br = 570, 410, 296  # the ball in the 2x game icon
        ball = icon.crop((bx - br, by - br, bx + br, by + br))
        bm = Image.new("L", ball.size, 0)
        ImageDraw.Draw(bm).ellipse((6, 6, ball.size[0] - 6, ball.size[1] - 6), fill=255)
        size = int(r * 1.15)
        ball = ball.resize((size, size), Image.LANCZOS)
        bm = bm.resize((size, size), Image.LANCZOS)
        ring = Image.new("L", (S, S), 0)
        ImageDraw.Draw(ring).ellipse((cx - size / 2 - 12, cy - size / 2 - 12, cx + size / 2 + 12, cy + size / 2 + 12), fill=255)
        img.alpha_composite(Image.composite(Image.new("RGBA", (S, S), INK), Image.new("RGBA", (S, S), (0, 0, 0, 0)), ring))
        img.paste(ball, (int(cx - size / 2), int(cy - size / 2)), bm)


ICONS = {
    "VIP": dict(bg=((150, 70, 230), (30, 8, 70)), draw=lambda im: crown(im, 512, 420, 560), text="VIP", size=230, y=600),
    "DoubleVP": dict(bg=((60, 150, 255), (8, 26, 90)), draw=lambda im: vp_coin(im, 470, 400, 230), text="V POINTS", size=150, y=650, extra="2x"),
    "Lucky": dict(bg=((70, 220, 110), (6, 60, 30)), draw=lambda im: clover(im, 512, 380, 260), text="LUCKY", size=190, y=640),
    "ScoreSound": dict(bg=((240, 80, 190), (60, 8, 60)), draw=lambda im: speaker(im, 540, 400, 250), text="SOUNDS", size=170, y=650),
    "ScoreImage": dict(bg=((255, 150, 40), (110, 20, 10)), draw=lambda im: burst(im, 512, 400, 270), text="SCORE FX", size=150, y=650),
    # the Clan Founder pass (Config.Clans.PassId): a crown over the word, in the clans' blue
    "ClanFounder": dict(bg=((60, 200, 255), (6, 30, 80)), draw=lambda im: crown(im, 512, 410, 520), text="CLAN", size=220, y=610),
}


def make(key):
    spec = ICONS[key]
    img = background(*spec["bg"])
    spec["draw"](img)
    if spec.get("extra"):
        f = ImageFont.truetype(FONT, 260)
        d = ImageDraw.Draw(img)
        d.text((620 + 10, 330 + 12), spec["extra"], font=f, fill=(0, 0, 0, 110), stroke_width=26, stroke_fill=(0, 0, 0, 110))
        d.text((620, 330), spec["extra"], font=f, fill=YELLOW, stroke_width=26, stroke_fill=INK)
    words(img, spec["text"], spec["y"], spec["size"])
    for sx, sy, sr in ((230, 230, 34), (800, 260, 26), (790, 560, 20)):
        sparkle(img, sx, sy, sr)
    return img.resize((512, 512), Image.LANCZOS)


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    sheet = Image.new("RGBA", (len(ICONS) * 260 + 10, 270), (20, 22, 30, 255))
    for i, key in enumerate(ICONS):
        im = make(key)
        im.save(os.path.join(OUT, key + ".png"))
        # how Roblox shows it: in a circle
        c = im.resize((250, 250), Image.LANCZOS)
        m = Image.new("L", (250, 250), 0)
        ImageDraw.Draw(m).ellipse((0, 0, 249, 249), fill=255)
        sheet.paste(c, (10 + i * 260, 10), m)
    sheet.save(os.path.join(OUT, "_all.png"))
    print("ok")
