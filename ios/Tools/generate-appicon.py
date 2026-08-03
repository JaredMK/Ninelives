#!/usr/bin/env python3
"""Generate the ShouldaSaidSame app icon (1024x1024, single-size slot).

Design (CRT pixel-casino contract: locked palette, square corners, hard
edges, no gradients/blur):
  - felt-deep full-bleed background (iOS applies the rounded mask).
  - a felt-mid panel with a hard ink border, filled with the game's
    felt-deep/felt-mid checker dither (same pattern as MapArt.mapBackground).
  - a chunky pixel-block "=" mark in phosphor (the "same" signature), with a
    hard-edged phosphor halo (the sanctioned static glow — NO blur) and a
    hard ink drop shadow.
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

S = 1024
FONT = "Assets/Fonts/PressStart2P.ttf"


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

    # ── The phosphor "=" — chunky pixel blocks on a coarse grid ────────────
    C = 34                       # pixel-cell size
    bar_w, bar_h, gap = 16, 4, 3  # cells: 544px bars, 136px tall, 102px gap
    mark_w = bar_w * C
    mark_h = 2 * bar_h * C + gap * C
    mx = (S - mark_w) // 2       # centred horizontally
    my = 218                     # above centre; the wordmark sits below
    bars = [(mx, my + i * (bar_h + gap) * C, mark_w, bar_h * C) for i in range(2)]

    halo = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    hd = ImageDraw.Draw(halo)
    for (x, y, w, h) in bars:    # hard-edged glow: 1-cell halo, flat alpha
        hd.rectangle([x - C, y - C, x + w + C - 1, y + h + C - 1],
                     fill=PHOSPHOR + (60,))
    img.alpha_composite(halo)
    for (x, y, w, h) in bars:    # hard ink shadow, 10px down-right
        d.rectangle([x + 10, y + 10, x + w + 9, y + h + 9], fill=INK)
    for (x, y, w, h) in bars:    # the mark itself
        d.rectangle([x, y, x + w - 1, y + h - 1], fill=PHOSPHOR)

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
    wx, wy = (S - tw) // 2, 700
    sh = Image.new("RGBA", (tw, th), INK + (255,))
    sh.putalpha(tmp.getchannel("A"))
    img.alpha_composite(sh, (wx + 8, wy + 8))   # hard ink shadow
    img.alpha_composite(cream, (wx, wy))

    img.convert("RGB").save(out)
    print(f"wrote {out} ({S}x{S})")


if __name__ == "__main__":
    main()
