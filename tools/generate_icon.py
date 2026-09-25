#!/usr/bin/env python3
"""Generate Spike Rush's game icon (512x512) and thumbnail (1920x1080).

Original art, drawn entirely here (no source images): a shaded yellow / blue / white
volleyball in the classic 18-panel layout, a speed ribbon, a burst of light, soft grey
stadium haze with light rays, floating bubbles and the "SPIKE RUSH" logo.

    python3 tools/generate_icon.py            -> assets/icon/GameIcon.png, Thumbnail.png

Upload them in the Creator Hub (your experience > Places > Icon / Thumbnails).
Needs numpy and pillow.
"""
import math
import random
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "assets" / "icon"

INK = (20, 23, 43)
SPARK = (255, 225, 77)
YELLOW = np.array([255, 205, 40], dtype=float)
BLUE = np.array([34, 86, 196], dtype=float)
WHITE = np.array([246, 247, 250], dtype=float)
SEAM = np.array([40, 44, 70], dtype=float)

FONT_CANDIDATES = [
    "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
    "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf",
    "/usr/share/fonts/truetype/freefont/FreeSansBold.ttf",
]


def font(size):
    for path in FONT_CANDIDATES:
        if Path(path).exists():
            return ImageFont.truetype(path, size)
    return ImageFont.load_default()


def rot_matrix(ax, ay, az):
    cx, sx = math.cos(ax), math.sin(ax)
    cy, sy = math.cos(ay), math.sin(ay)
    cz, sz = math.cos(az), math.sin(az)
    rx = np.array([[1, 0, 0], [0, cx, -sx], [0, sx, cx]])
    ry = np.array([[cy, 0, sy], [0, 1, 0], [-sy, 0, cy]])
    rz = np.array([[cz, -sz, 0], [sz, cz, 0], [0, 0, 1]])
    return rz @ ry @ rx


def volleyball(size, rotation=(0.5, -0.6, 0.25)):
    """RGBA image of a shaded volleyball `size` pixels across."""
    n = size
    ys, xs = np.mgrid[0:n, 0:n].astype(float)
    x = (xs + 0.5) / n * 2 - 1
    y = 1 - (ys + 0.5) / n * 2
    r2 = x * x + y * y
    inside = r2 <= 1.0
    z = np.sqrt(np.clip(1 - r2, 0, 1))
    normal = np.stack([x, y, z], axis=-1)

    # panel layout lives on the rotated sphere
    p = normal @ rot_matrix(*rotation).T
    ax_ = np.abs(p)
    dom = np.argmax(ax_, axis=-1)
    color = np.zeros((n, n, 3))
    seam = np.zeros((n, n))
    # each cube face holds three strips; the strip direction alternates between face pairs
    split_axis = {0: 1, 1: 2, 2: 0}
    palette = {
        (0, 1): [YELLOW, WHITE, BLUE],
        (0, -1): [BLUE, WHITE, YELLOW],
        (1, 1): [BLUE, WHITE, YELLOW],
        (1, -1): [YELLOW, WHITE, BLUE],
        (2, 1): [YELLOW, WHITE, BLUE],
        (2, -1): [BLUE, WHITE, YELLOW],
    }
    for d in range(3):
        mask = dom == d
        sign = np.sign(p[..., d])
        s = split_axis[d]
        u = p[..., s] / np.maximum(ax_[..., d], 1e-6)
        for sgn in (1, -1):
            m = mask & (sign == sgn)
            cols = palette[(d, sgn)]
            strip = np.where(u < -1 / 3, 0, np.where(u > 1 / 3, 2, 1))
            for k in range(3):
                mm = m & (strip == k)
                color[mm] = cols[k]
        # seams between strips
        seam_u = np.minimum(np.abs(np.abs(u) - 1 / 3), 1)
        seam[mask] = np.maximum(seam[mask], (seam_u[mask] < 0.035).astype(float))
    # seams between faces (two largest components nearly equal)
    srt = np.sort(ax_, axis=-1)
    face_edge = (srt[..., 2] - srt[..., 1]) < 0.03
    seam = np.maximum(seam, face_edge.astype(float))
    color = color * (1 - seam[..., None] * 0.85) + SEAM * seam[..., None] * 0.85

    # lighting: key light top-left, soft fill, specular, rim
    light = np.array([-0.55, 0.65, 0.52])
    light /= np.linalg.norm(light)
    lambert = np.clip(normal @ light, 0, 1)
    shade = 0.42 + 0.68 * lambert
    view = np.array([0, 0, 1.0])
    half = light + view
    half /= np.linalg.norm(half)
    spec = np.clip(normal @ half, 0, 1) ** 40
    rim = (1 - z) ** 3
    rgb = color * shade[..., None] + 255 * spec[..., None] * 0.55 + np.array([180, 200, 255]) * rim[..., None] * 0.25
    rgb = np.clip(rgb, 0, 255)

    # soft antialiased edge + dark outline
    dist = np.sqrt(r2)
    edge = np.clip((1 - dist) * n / 2.0, 0, 1)
    outline = np.clip(1 - np.abs(dist - 0.985) * n / 3.0, 0, 1) * inside
    rgb = rgb * (1 - outline[..., None] * 0.8) + np.array(INK) * outline[..., None] * 0.8
    alpha = (edge * 255).astype(np.uint8)
    img = np.dstack([rgb.astype(np.uint8), alpha])
    return Image.fromarray(img, "RGBA")


def background(w, h, seed):
    rnd = random.Random(seed)
    ys = np.linspace(0, 1, h)[:, None]
    xs = np.linspace(0, 1, w)[None, :]
    top = np.array([236, 240, 246], dtype=float)
    mid = np.array([178, 186, 204], dtype=float)
    bot = np.array([84, 92, 120], dtype=float)
    t = ys + 0.15 * (xs - 0.5)
    t = np.clip(t, 0, 1)[..., None]
    col = np.where(t < 0.55, top + (mid - top) * (t / 0.55), mid + (bot - mid) * ((t - 0.55) / 0.45))
    # haze glow from the top left
    gx, gy = 0.25, 0.1
    d = np.sqrt((xs - gx) ** 2 * (w / h) ** 2 + (ys - gy) ** 2)
    col = col + np.clip(1 - d / 0.9, 0, 1)[..., None] ** 2 * 40
    img = Image.fromarray(np.clip(col, 0, 255).astype(np.uint8), "RGB").convert("RGBA")

    # light rays
    rays = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    rd = ImageDraw.Draw(rays)
    ox, oy = -0.1 * w, -0.25 * h
    for i in range(7):
        a0 = math.radians(28 + i * 7.5 + rnd.uniform(-1.5, 1.5))
        a1 = a0 + math.radians(rnd.uniform(1.8, 3.6))
        L = 2.5 * max(w, h)
        rd.polygon([(ox, oy), (ox + L * math.cos(a0), oy + L * math.sin(a0)), (ox + L * math.cos(a1), oy + L * math.sin(a1))], fill=(255, 255, 255, 34))
    rays = rays.filter(ImageFilter.GaussianBlur(max(w, h) / 120))
    img.alpha_composite(rays)
    return img


def bubbles(img, count, seed, scale):
    rnd = random.Random(seed)
    w, h = img.size
    layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    for _ in range(count):
        r = rnd.uniform(6, 34) * scale
        x, y = rnd.uniform(0, w), rnd.uniform(0, h)
        d.ellipse([x - r, y - r, x + r, y + r], fill=(255, 255, 255, 30), outline=(255, 255, 255, 150), width=max(1, int(2 * scale)))
        d.ellipse([x - r * 0.55, y - r * 0.6, x - r * 0.15, y - r * 0.2], fill=(255, 255, 255, 170))
    img.alpha_composite(layer.filter(ImageFilter.GaussianBlur(0.6 * scale)))


def ribbon(img, start, end, width, color):
    """A smooth speed ribbon from start (a thin tail) to end (wide, at the ball)."""
    w, h = img.size
    sx, sy = start
    ex, ey = end
    length = math.hypot(ex - sx, ey - sy)
    ux, uy = (ex - sx) / length, (ey - sy) / length
    nx, ny = -uy, ux
    ys, xs = np.mgrid[0:h, 0:w].astype(float)
    along = ((xs - sx) * ux + (ys - sy) * uy) / length  # 0 at the tail, 1 at the ball
    across = (xs - sx) * nx + (ys - sy) * ny
    a = np.clip(along, 0, 1)
    half = width * a ** 1.3 + 1e-3
    inside = (along >= 0) & (along <= 1.02)
    edge = np.clip(1 - np.abs(across) / half, 0, 1)
    body = inside * np.clip(edge * 2.2, 0, 1) * (0.25 + 0.75 * a)
    core = inside * np.clip(1 - np.abs(across) / (half * 0.3), 0, 1) * a
    layer = np.zeros((h, w, 4))
    layer[..., :3] = np.array(color, dtype=float)
    layer[..., :3] = layer[..., :3] * (1 - core[..., None]) + 255 * core[..., None]
    layer[..., 3] = np.clip(body * 235 + core * 200, 0, 255)
    img.alpha_composite(Image.fromarray(layer.astype(np.uint8), "RGBA").filter(ImageFilter.GaussianBlur(width / 30)))


def burst(img, center, radius, rays, color, seed):
    rnd = random.Random(seed)
    w, h = img.size
    layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    cx, cy = center
    for i in range(rays):
        a = 2 * math.pi * i / rays + rnd.uniform(-0.1, 0.1)
        L = radius * rnd.uniform(0.7, 1.25)
        s = rnd.uniform(0.012, 0.03)
        d.polygon([(cx, cy), (cx + L * math.cos(a - s), cy + L * math.sin(a - s)), (cx + L * math.cos(a + s), cy + L * math.sin(a + s))], fill=color + (70,))
    glow = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    gd.ellipse([cx - radius * 0.55, cy - radius * 0.55, cx + radius * 0.55, cy + radius * 0.55], fill=(255, 255, 255, 170))
    img.alpha_composite(layer.filter(ImageFilter.GaussianBlur(radius / 60)))
    img.alpha_composite(glow.filter(ImageFilter.GaussianBlur(radius / 5)))


def logo(img, text, center, size, lean=0.18):
    """Heavy italic title: yellow fill, thick ink outline, drop shadow."""
    f = font(size)
    stroke = max(3, size // 9)
    probe = ImageDraw.Draw(Image.new("RGBA", (8, 8)))
    bbox = probe.textbbox((0, 0), text, font=f, stroke_width=stroke)
    tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
    pad = 4 * stroke
    slant = int(lean * (th + 2 * pad))
    W, H = tw + 2 * pad + slant, th + 2 * pad
    tmp = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(tmp)
    ox, oy = pad - bbox[0], pad - bbox[1]
    shadow = Image.new("RGBA", tmp.size, (0, 0, 0, 0))
    sd = ImageDraw.Draw(shadow)
    sd.text((ox + stroke, oy + stroke * 1.2), text, font=f, fill=INK + (200,), stroke_width=stroke, stroke_fill=INK + (200,))
    tmp.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(stroke / 2)))
    d.text((ox, oy), text, font=f, fill=SPARK + (255,), stroke_width=stroke, stroke_fill=INK + (255,))
    # a light band across the top of the letters
    band = Image.new("RGBA", tmp.size, (0, 0, 0, 0))
    ImageDraw.Draw(band).text((ox, oy), text, font=f, fill=(255, 250, 220, 255))
    mask = Image.new("L", tmp.size, 0)
    ImageDraw.Draw(mask).rectangle([0, 0, W, oy + bbox[1] + th * 0.45], fill=150)
    band.putalpha(Image.fromarray(np.minimum(np.array(band.split()[3]), np.array(mask))))
    tmp.alpha_composite(band)
    # italic lean: the top slides right
    leaned = tmp.transform(tmp.size, Image.AFFINE, (1, lean, -lean * H, 0, 1, 0), resample=Image.BICUBIC, fillcolor=(0, 0, 0, 0))
    x = int(center[0] - W / 2)
    y = int(center[1] - H / 2)
    img.alpha_composite(leaned, (max(0, x), max(0, y)))


def compose_icon(size=512):
    img = background(size, size, seed=3)
    bubbles(img, 16, seed=5, scale=size / 512)
    ball_d = int(size * 0.62)
    cx, cy = int(size * 0.56), int(size * 0.42)
    ribbon(img, (size * -0.1, size * 0.98), (cx - ball_d * 0.1, cy + ball_d * 0.1), size * 0.16, (255, 70, 120))
    burst(img, (cx, cy), size * 0.52, 22, (255, 250, 225), seed=9)
    ball = volleyball(ball_d)
    img.alpha_composite(ball, (cx - ball_d // 2, cy - ball_d // 2))
    logo(img, "SPIKE", (size * 0.5, size * 0.77), int(size * 0.17))
    logo(img, "RUSH", (size * 0.5, size * 0.9), int(size * 0.13))
    return img.convert("RGB")


def compose_thumbnail(w=1920, h=1080):
    img = background(w, h, seed=11)
    bubbles(img, 40, seed=13, scale=h / 700)
    ball_d = int(h * 0.62)
    cx, cy = int(w * 0.68), int(h * 0.44)
    ribbon(img, (-w * 0.05, h * 1.0), (cx - ball_d * 0.15, cy + ball_d * 0.1), h * 0.16, (255, 70, 120))
    ribbon(img, (-w * 0.02, h * 0.75), (cx - ball_d * 0.2, cy), h * 0.06, (80, 220, 255))
    burst(img, (cx, cy), h * 0.6, 28, (255, 250, 225), seed=17)
    ball = volleyball(ball_d, rotation=(0.35, -0.8, 0.4))
    img.alpha_composite(ball, (cx - ball_d // 2, cy - ball_d // 2))
    logo(img, "SPIKE RUSH", (w * 0.33, h * 0.78), int(h * 0.15))
    f = font(int(h * 0.04))
    d = ImageDraw.Draw(img)
    tag = "ANIME VOLLEYBALL  -  1v1  2v2  3v3"
    tb = d.textbbox((0, 0), tag, font=f)
    d.text((w * 0.33 - (tb[2] - tb[0]) / 2, h * 0.9), tag, font=f, fill=(255, 255, 255, 255), stroke_width=4, stroke_fill=INK + (255,))
    return img.convert("RGB")


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    compose_icon().save(OUT / "GameIcon.png")
    compose_thumbnail().save(OUT / "Thumbnail.png")
    print("wrote", OUT / "GameIcon.png", "and", OUT / "Thumbnail.png")


if __name__ == "__main__":
    main()
