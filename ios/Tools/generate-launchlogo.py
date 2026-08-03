#!/usr/bin/env python3
"""Generate the JarHead Labs launch-screen logo PNGs (1x/2x/3x).

Rasterizes icons/jarhead-logo.svg (minus its cream background rect) with
qlmanage, flood-fills the white matte to transparency, crops to the artwork,
and centres it on square transparent canvases sized so UILaunchScreen shows
the mark at 200pt on every device — with the "JARHEAD LABS" wordmark (Press
Start 2P, brand cream) baked in under the jar (a UILaunchScreen dict can only
show ONE image, so the studio name rides inside it).

Usage: python3 Tools/generate-launchlogo.py <out.imageset-dir>
"""
import subprocess
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
SVG = ROOT.parent / "icons" / "jarhead-logo.svg"
FONT = ROOT / "Assets" / "Fonts" / "PressStart2P.ttf"
SCRATCH = ROOT / "build" / "icon"
PT = 200          # on-screen size in points
ART_FILL = 0.62   # jar height as a fraction of the canvas (wordmark below)
WORDMARK = "JARHEAD LABS"
CREAM = (246, 243, 236, 255)   # the brand cream #f6f3ec
BG_LINE = '<rect width="1024" height="1024" fill="#f6f3ec"/>'
MARKER = (1, 2, 3, 255)


def render_svg() -> Image.Image:
    SCRATCH.mkdir(parents=True, exist_ok=True)
    nobg = SCRATCH / "jarhead-nobg.svg"
    nobg.write_text("\n".join(
        line for line in SVG.read_text().splitlines() if BG_LINE not in line))
    subprocess.run(["qlmanage", "-t", "-s", "1024", "-o", str(SCRATCH),
                    str(nobg)], check=True, capture_output=True)
    return Image.open(SCRATCH / "jarhead-nobg.svg.png").convert("RGBA")


def dematte(im: Image.Image) -> Image.Image:
    """Flood-fill the white backdrop (from all four corners) to transparent."""
    im = im.copy()
    for corner in [(0, 0), (im.width - 1, 0), (0, im.height - 1),
                   (im.width - 1, im.height - 1)]:
        ImageDraw.floodfill(im, corner, MARKER, thresh=28)
    px = im.load()
    for y in range(im.height):
        for x in range(im.width):
            if px[x, y] == MARKER:
                px[x, y] = (0, 0, 0, 0)
    return im


def wordmark_layer(size: int) -> tuple[Image.Image, int]:
    """Render the wordmark on a transparent strip, shrinking the font until it
    fits inside 90% of the canvas width. Returns (strip, strip height)."""
    probe = ImageDraw.Draw(Image.new("RGBA", (4, 4)))
    px = max(8, round(size * 0.10))
    while px > 6:
        font = ImageFont.truetype(str(FONT), px)
        w = probe.textlength(WORDMARK, font=font)
        if w <= size * 0.90:
            break
        px -= 1
    font = ImageFont.truetype(str(FONT), px)
    bbox = font.getbbox(WORDMARK)
    tw, th = int(probe.textlength(WORDMARK, font=font)), bbox[3] - bbox[1]
    strip = Image.new("RGBA", (tw, th + 2), (0, 0, 0, 0))
    ImageDraw.Draw(strip).text((0, -bbox[1]), WORDMARK, font=font, fill=CREAM)
    return strip, strip.height


def main() -> None:
    out = Path(sys.argv[1])
    out.mkdir(parents=True, exist_ok=True)
    art = dematte(render_svg())
    art = art.crop(art.getbbox())
    for scale in (1, 2, 3):
        size = PT * scale
        canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        h = round(size * ART_FILL)
        w = round(art.width * h / art.height)
        jar = art.resize((w, h), Image.LANCZOS)
        mark, mark_h = wordmark_layer(size)
        gap = round(size * 0.05)
        # Centre the jar+wordmark BLOCK (not the jar alone) in the canvas.
        block_h = h + gap + mark_h
        top = (size - block_h) // 2
        canvas.alpha_composite(jar, ((size - w) // 2, top))
        canvas.alpha_composite(mark, ((size - mark.width) // 2, top + h + gap))
        name = f"LaunchLogo@{scale}x.png"
        canvas.save(out / name)
        print(f"wrote {out / name} ({canvas.width}x{canvas.height})")


if __name__ == "__main__":
    main()
