"""Finish the Blender rank renders (tools/render_rank_badges_blender.py) for the game: crop each to its outline, lift saturation and contrast, add a dark outline and an outer glow that grows with the rank, and centre it on a 512 px transparent square. Usage: finish_rank_badges.py RENDER_DIR [OUT_DIR=assets/ranks]"""
import sys
from pathlib import Path
from PIL import Image, ImageEnhance, ImageFilter, ImageChops

SRC = Path(sys.argv[1])
OUT = Path(sys.argv[2]) if len(sys.argv) > 2 else Path(__file__).resolve().parent.parent / "assets" / "ranks"
OUT.mkdir(parents=True, exist_ok=True)
NAMES = ["Bronze", "Silver", "Gold", "Platinum", "Diamond", "Mighty", "Almighty"]
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


def process(name):
    im = Image.open(SRC / ("Rank%s.png" % name)).convert("RGBA")
    a = im.getchannel("A")
    rgb = im.convert("RGB")
    rgb = ImageEnhance.Contrast(ImageEnhance.Color(rgb).enhance(1.6)).enhance(1.25)
    im = rgb.convert("RGBA")
    im.putalpha(a)
    box = a.point(lambda v: 255 if v > 8 else 0).getbbox()
    im = im.crop(box)
    w, h = im.size
    k = SIZE * FILL[name] / max(w, h)
    im = im.resize((max(1, round(w * k)), max(1, round(h * k))), Image.LANCZOS)
    canvas = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    ox, oy = (SIZE - im.width) // 2, (SIZE - im.height) // 2
    # a thin dark outline so it reads on any background
    alpha = Image.new("L", (SIZE, SIZE), 0)
    alpha.paste(im.getchannel("A"), (ox, oy))
    edge = alpha.filter(ImageFilter.MaxFilter(7))
    col, s = GLOW[name]
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
sheet = Image.new("RGBA", (SIZE * len(NAMES), SIZE), (24, 22, 36, 255))
for i, t in enumerate(tiles):
    sheet.alpha_composite(t, (SIZE * i, 0))
sheet.save(OUT / "_all.png")
sheet.convert("RGB").resize((SIZE * len(NAMES) // 2, SIZE // 2), Image.LANCZOS).save(OUT / "_preview.png")
