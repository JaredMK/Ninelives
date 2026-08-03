#!/usr/bin/env python3
"""Generate the ShouldaSaidSame app icon (1024x1024, single-size slot).

Design (CRT pixel-casino contract: locked palette, square corners, hard
edges, no gradients/blur):
  - felt-deep full-bleed background (iOS applies the rounded mask).
  - a felt-mid panel with a hard ink border, filled with the game's
    felt-deep/felt-mid checker dither (same pattern as MapArt.mapBackground).
  - the game's "same" logo mark (icons/logo.svg): two gold rounded bars
    with big dumbbell ends + small phosphor dots, hard ink drop shadow.
  - "SAME" wordmark in card-cream Press Start 2P (the bundled TTF), rendered
    small and upscaled nearest-neighbour so it stays pixel-crisp.

Usage: python3 Tools/generate-appicon.py <out.png>
"""
import sys
from PIL import Image, ImageDraw, ImageFont

# Locked palette (styleguide / CRT tokens).
FELT_DEEP = (0x14, 0x28, 0x20)
FELT_MID = (0x1E, 0x3A, 0x2C)
CARD_CREAM = (0xEC, 0xE4, 0xCF)
INK = (0x10, 0x10, 0x0E)
PHOSPHOR = (0x4E, 0xF0, 0x8A)
GOLD = (0xD9, 0xA4, 0x41)

S = 1024
FONT = "Assets/Fonts/PressStart2P.ttf"


def draw_same_mark(d: ImageDraw.ImageDraw, ox: int, oy: int, scale: float,
                   color, dots) -> None:
    """The game's logo mark (icons/logo.svg): two gold rounded bars with big
    round ends — the dumbbell-sided '=' — plus the small phosphor dots.
    Drawn in the SVG's 100x100 viewBox space at (ox, oy) scaled by `scale`."""
    def X(v): return ox + v * scale
    def Y(v): return oy + v * scale
    sw = 9 * scale                       # bar stroke width
    for y in (40, 60):                   # the two bars (round line caps)
        d.line([X(30), Y(y), X(70), Y(y)], fill=color, width=round(sw))
    r = 8 * scale                        # the big dumbbell ends
    for (cx, cy) in ((30, 40), (70, 40), (30, 60), (70, 60)):
        d.ellipse([X(cx) - r, Y(cy) - r, X(cx) + r, Y(cy) + r], fill=color)
    dr = 3 * scale                       # the phosphor dots
    for (cx, cy) in ((52, 40), (48, 60)):
        d.ellipse([X(cx) - dr, Y(cy) - dr, X(cx) + dr, Y(cy) + dr], fill=dots)


def main() -> None:
    out = sys.argv[1] if len(sys.argv) > 1 else "build/AppIcon-1024.png"
    img = Image.new("RGBA", (S, S), FELT_DEEP + (255,))
    d = ImageDraw.Draw(img)

    # Panel: felt-mid with a hard ink border, inset so the iOS mask only
    # clips its corners (the frame reads as running under the mask edge).
    m, b = 64, 8
    d.rectangle([m - b, m - b, S - m + b - 1, S - m + b - 1], fill=INK)
    d.rectangle([m, m, S - m - 1, S - m - 1], fill=FELT_MID)
    # Checker dither inside the panel (MapArt.mapBackground pattern, 6px cells).
    cell = 6
    for y in range(m, S - m, cell):
        for x in range(m, S - m, cell):
            if ((x - m) // cell + (y - m) // cell) % 2 == 0:
                d.rectangle([x, y, x + cell - 1, y + cell - 1], fill=FELT_DEEP)

    # ── The in-game "same" mark (icons/logo.svg): gold dumbbell-ended bars +
    # phosphor dots, supersampled 4x for smooth rounds, hard ink shadow ─────
    SS = 4
    mark_scale = 5.6 * SS                # 100-unit viewBox → 560px on the icon
    layer = Image.new("RGBA", (S * SS, S * SS), (0, 0, 0, 0))
    ld = ImageDraw.Draw(layer)
    # The mark's own bbox inside the viewBox is x 22..78, y 32..68 — centre it.
    bbox_w, bbox_h = 56 * mark_scale, 36 * mark_scale
    mx = (S * SS - bbox_w) // 2 - 22 * mark_scale
    my = round(300 * SS) - 32 * mark_scale
    draw_same_mark(ld, mx + 10 * SS, my + 10 * SS, mark_scale, INK, INK)  # shadow
    draw_same_mark(ld, mx, my, mark_scale, GOLD, PHOSPHOR)
    layer = layer.resize((S, S), Image.LANCZOS)
    img.alpha_composite(layer)

    # ── "SAME" wordmark — PS2P rendered small, upscaled nearest ────────────
    word = "SAME"
    f = ImageFont.truetype(FONT, 48)
    tmp = Image.new("RGBA", (640, 128), (0, 0, 0, 0))
    ImageDraw.Draw(tmp).text((8, 8), word, font=f, fill=(255, 255, 255, 255))
    bbox = tmp.getbbox()
    tmp = tmp.crop(bbox)
    tw = 368
    th = round(tmp.height * tw / tmp.width)
    tmp = tmp.resize((tw, th), Image.NEAREST)

    cream = Image.new("RGBA", (tw, th), CARD_CREAM + (255,))
    cream.putalpha(tmp.getchannel("A"))
    wx, wy = (S - tw) // 2, 640
    sh = Image.new("RGBA", (tw, th), INK + (255,))
    sh.putalpha(tmp.getchannel("A"))
    img.alpha_composite(sh, (wx + 8, wy + 8))   # hard ink shadow
    img.alpha_composite(cream, (wx, wy))

    img.convert("RGB").save(out)
    print(f"wrote {out} ({S}x{S})")


if __name__ == "__main__":
    main()
