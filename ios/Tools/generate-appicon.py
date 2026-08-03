#!/usr/bin/env python3
"""Generate the ShouldaSaidSame app icon (1024x1024, single-size slot).

Design (CRT pixel-casino contract: locked palette, square corners, hard
edges, no gradients/blur):
  - felt-deep full-bleed background (iOS applies the rounded mask).
  - a felt-mid panel with a hard ink border, filled with the game's
    felt-deep/felt-mid checker dither (same pattern as MapArt.mapBackground).
  - the game's "same" logo mark EXACTLY as the main menu draws it
    (MapArt.menuLogo / icons/logo.svg): two gold bars with dumbbell ends +
    phosphor dots — rendered at the game's small pixel size and upscaled
    NEAREST, so the icon keeps the same chunky pixel edges the player sees
    in-game. No drop shadow, no wordmark (the menu mark has neither).

Usage: python3 Tools/generate-appicon.py <out.png>
"""
import sys
from PIL import Image, ImageDraw

# Locked palette (styleguide / CRT tokens).
FELT_DEEP = (0x14, 0x28, 0x20)
FELT_MID = (0x1E, 0x3A, 0x2C)
INK = (0x10, 0x10, 0x0E)
PHOSPHOR = (0x4E, 0xF0, 0x8A)
GOLD = (0xD9, 0xA4, 0x41)

S = 1024


def draw_same_mark(d: ImageDraw.ImageDraw, scale: float) -> None:
    """The in-game mark, verbatim from MapArt.menuLogo (icons/logo.svg,
    viewBox 100): gold bars at y=40/y=60 (stroke-width 9) with r=8 end
    circles — the bone shape — and r=3 phosphor dots at (52,40) / (48,60).
    Drawn in the 100x100 viewBox at `scale` px per unit."""
    def U(v): return v * scale
    for y in (40, 60):
        d.rectangle([U(30), U(y - 4.5), U(70), U(y + 4.5)], fill=GOLD)
        for x in (30, 70):
            d.ellipse([U(x - 8), U(y - 8), U(x + 8), U(y + 8)], fill=GOLD)
    for (cx, cy) in ((52, 40), (48, 60)):
        d.ellipse([U(cx - 3), U(cy - 3), U(cx + 3), U(cy + 3)], fill=PHOSPHOR)


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

    # ── The in-game "same" mark: draw at the game's pixel size (3px per
    # viewBox unit — the menu renders ~1px/unit), crop to the mark's bbox
    # (x 22..78, y 31..69), then NEAREST-upscale so the pixels stay chunky.
    PX = 3
    mark = Image.new("RGBA", (100 * PX, 100 * PX), (0, 0, 0, 0))
    draw_same_mark(ImageDraw.Draw(mark), PX)
    mark = mark.crop((22 * PX, 31 * PX, 78 * PX, 69 * PX))     # 168 x 114 px
    tw = 560
    th = round(mark.height * tw / mark.width)
    mark = mark.resize((tw, th), Image.NEAREST)
    img.alpha_composite(mark, ((S - tw) // 2, (S - th) // 2))

    img.convert("RGB").save(out)
    print(f"wrote {out} ({S}x{S})")


if __name__ == "__main__":
    main()
