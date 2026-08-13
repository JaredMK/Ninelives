#!/usr/bin/env python3
"""
Shoulda Said Same — app icon renderer ("Blinds").
Pinky peeks through the gap between the two equals bars: the mark keeps
Spacing A (phosphor bars, offset gold dots), the face is the UNTOUCHED
32x32 idle sprite scaled nearest — eyes dead-center of the icon.
Subtle scanline texture that fades out at small sizes. Pure Pillow.
"""
from PIL import Image, ImageDraw
import os

BG   = (23, 48, 37, 255)      # #173025 CRT felt
MARK = (78, 240, 138, 255)    # #4ef08a phosphor
DOT  = (217, 164, 65, 255)    # #d9a441 gold

# Geometry in 0..100 space (Spacing A, bars widened for the peek)
BAR_X0, BAR_X1 = 18.0, 82.0
CAP_R          = 11.5
BAR_H          = 13.0
TOP_Y, BOT_Y   = 40.0, 70.0
DOT_R          = 5.0
TOP_DOT_X      = 44.0   # nudged left
BOT_DOT_X      = 56.0   # nudged right

# Sprite placement at the 1024 master: the idle sheet cropped to the jar
# (cells 6..25 x 4..23), scaled x20 nearest, eyes centered in the bar gap.
HERE = os.path.dirname(os.path.abspath(__file__))
SPRITE = os.path.join(HERE, "..", "Assets", "PixelArt", "spr-pink-idle.png")
CROP   = (6, 4, 26, 24)
K      = 20
SPR_TOP = 373

MASTER = 1024
SS = 4                  # supersample factor for the smooth bar layer
SCAN_PERIOD = 4         # px of dark band at 1024 (equal gap)
SCAN_ALPHA = 30


def bar_layer() -> Image.Image:
    S = MASTER * SS
    ov = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(ov)
    u = lambda v: v / 100.0 * S
    for cy, dot_x in ((TOP_Y, TOP_DOT_X), (BOT_Y, BOT_DOT_X)):
        d.rectangle([u(BAR_X0), u(cy - BAR_H / 2), u(BAR_X1), u(cy + BAR_H / 2)], fill=MARK)
        for cx in (BAR_X0, BAR_X1):
            d.ellipse([u(cx - CAP_R), u(cy - CAP_R), u(cx + CAP_R), u(cy + CAP_R)], fill=MARK)
        d.ellipse([u(dot_x - DOT_R), u(cy - DOT_R), u(dot_x + DOT_R), u(cy + DOT_R)], fill=DOT)
    return ov.resize((MASTER, MASTER), Image.LANCZOS)


def master() -> Image.Image:
    img = Image.new("RGBA", (MASTER, MASTER), BG)
    face = Image.open(SPRITE).convert("RGBA").crop(CROP)
    face = face.resize((face.width * K, face.height * K), Image.NEAREST)
    img.alpha_composite(face, ((MASTER - face.width) // 2, SPR_TOP))
    img.alpha_composite(bar_layer())     # the bars are the blinds: face behind
    ov = Image.new("RGBA", (MASTER, MASTER), (0, 0, 0, 0))
    d = ImageDraw.Draw(ov)
    for y in range(0, MASTER, SCAN_PERIOD * 2):
        d.rectangle([0, y, MASTER, y + SCAN_PERIOD - 1], fill=(0, 0, 0, SCAN_ALPHA))
    return Image.alpha_composite(img, ov)


SIZES = [
    ("icon-1024.png", 1024), ("icon-180.png", 180), ("icon-167.png", 167),
    ("icon-152.png", 152), ("icon-120.png", 120), ("icon-87.png", 87),
    ("icon-80.png", 80), ("icon-76.png", 76), ("icon-60.png", 60),
    ("icon-58.png", 58), ("icon-40.png", 40), ("icon-29.png", 29),
    ("icon-20.png", 20),
]

# Writes straight into the asset catalog the app builds against, so tweaking a
# geometry constant above and re-running this is the whole workflow.
OUT = os.path.join(HERE, "..", "App", "Assets.xcassets", "AppIcon.appiconset")
os.makedirs(OUT, exist_ok=True)
m = master()
for name, px in SIZES:
    out = m if px == MASTER else m.resize((px, px), Image.LANCZOS)
    out.convert("RGB").save(os.path.join(OUT, name), "PNG")
print("rendered", len(SIZES), "sizes")
