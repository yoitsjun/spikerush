"""Finish the Blender rank renders (tools/render_rank_badges_blender.py) for the game: crop each to its outline, lift saturation and contrast, add a dark outline and an outer glow that grows with the rank, and centre it on a 512 px transparent square. Usage: finish_rank_badges.py RENDER_DIR [OUT_DIR=assets/ranks]"""
import sys
from pathlib import Path
from PIL import Image, ImageEnhance, ImageFilter, ImageChops

SRC = Path(sys.argv[1])
OUT = Path(sys.argv[2]) if len(sys.argv) > 2 else Path(__file__).resolve().parent.parent / "assets" / "ranks"
OUT.mkdir(parents=True, exist_ok=True)
RANKS = ["Bronze", "Silver", "Gold", "Platinum", "Diamond", "Mighty", "Almighty"]
# every badge: a division's own (Rank<Key>1..3) for Bronze to Diamond, then Mighty and Almighty
NAMES = [r + str(d) for r in RANKS[:5] for d in (1, 2, 3)] + ["Mighty", "Almighty"]
# outer glow per rank: colour, strength (0 none)
GLOW = {
    "Bronze": ((255, 140, 80), 0.0),
    "Silver": ((200, 225, 255), 0.25),
    "Gold": ((255, 200, 60), 0.45),
    "Platinum": ((80, 255, 210), 0.6),
    "Diamond": ((90, 180, 255), 0.8),
    "Mighty": ((190, 90, 255), 0.95),
    "Almighty": ((255, 110, 40), 1.1),
}
SIZE = 512
FILL = {"Bronze": 0.78, "Silver": 0.82, "Gold": 0.88, "Platinum": 0.9, "Diamond": 0.92, "Mighty": 0.94, "Almighty": 0.96}


def split(name):
    # "Gold2" -> ("Gold", 2); "Mighty" -> ("Mighty", None)
    if name[-1].isdigit():
        return name[:-1], int(name[-1])
    return name, None


def process(name):
    rank, div = split(name)
    up = (div or 1) - 1  # each division up: a little brighter and bigger
    im = Image.open(SRC / ("Rank%s.png" % name)).convert("RGBA")
    a = im.getchannel("A")
    rgb = im.convert("RGB")
    rgb = ImageEnhance.Contrast(ImageEnhance.Color(rgb).enhance(1.6)).enhance(1.25)
    im = rgb.convert("RGBA")
    im.putalpha(a)
    box = a.point(lambda v: 255 if v > 8 else 0).getbbox()
    im = im.crop(box)
    w, h = im.size
    k = SIZE * min(0.97, FILL[rank] + 0.025 * up) / max(w, h)
    im = im.resize((max(1, round(w * k)), max(1, round(h * k))), Image.LANCZOS)
    canvas = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    ox, oy = (SIZE - im.width) // 2, (SIZE - im.height) // 2
    # a thin dark outline so it reads on any background
    alpha = Image.new("L", (SIZE, SIZE), 0)
    alpha.paste(im.getchannel("A"), (ox, oy))
    edge = alpha.filter(ImageFilter.MaxFilter(7))
    col, s = GLOW[rank]
    s = s + 0.15 * up
    if s > 0:
        g = alpha.filter(ImageFilter.GaussianBlur(18)).point(lambda v: min(255, int(v * s * 1.6)))
        glow = Image.new("RGBA", (SIZE, SIZE), col + (0,))
        glow.putalpha(g)
        canvas.alpha_composite(glow)
    ink = Image.new("RGBA", (SIZE, SIZE), (14, 8, 22, 0))
    ink.putalpha(edge.point(lambda v: int(v * 0.85)))
    canvas.alpha_composite(ink)
    canvas.alpha_composite(im, (ox, oy))
    canvas.save(OUT / ("Rank%s.png" % name))
    return canvas


tiles = [process(n) for n in NAMES]
# a sheet: a rank a row (its three divisions), then Mighty and Almighty
COLS = 3
rows = (len(NAMES) + COLS - 1) // COLS
sheet = Image.new("RGBA", (SIZE * COLS, SIZE * rows), (24, 22, 36, 255))
for i, t in enumerate(tiles):
    sheet.alpha_composite(t, (SIZE * (i % COLS), SIZE * (i // COLS)))
sheet.save(OUT / "_all.png")
