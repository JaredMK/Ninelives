#!/usr/bin/env python3
"""Generate the JarHead Labs launch-screen logo PNGs (1x/2x/3x).

Rasterizes icons/jarhead-logo.svg (minus its cream background rect) with
qlmanage, flood-fills the white matte to transparency, crops to the artwork,
and centres it on square transparent canvases sized so UILaunchScreen shows
the mark at 200pt on every device.

Usage: python3 Tools/generate-launchlogo.py <out.imageset-dir>
"""
import subprocess
import sys
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
SVG = ROOT.parent / "icons" / "jarhead-logo.svg"
SCRATCH = ROOT / "build" / "icon"
PT = 200          # on-screen size in points
ART_FILL = 0.86   # artwork height as a fraction of the canvas
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


def main() -> None:
    out = Path(sys.argv[1])
    out.mkdir(parents=True, exist_ok=True)
    art = dematte(render_svg())
    art = art.crop(art.getbbox())
    for scale in (1, 2, 3):
        canvas = Image.new("RGBA", (PT * scale, PT * scale), (0, 0, 0, 0))
        h = round(PT * scale * ART_FILL)
        w = round(art.width * h / art.height)
        sized = art.resize((w, h), Image.LANCZOS)
        canvas.alpha_composite(sized, ((canvas.width - w) // 2,
                                       (canvas.height - h) // 2))
        name = f"LaunchLogo@{scale}x.png"
        canvas.save(out / name)
        print(f"wrote {out / name} ({canvas.width}x{canvas.height})")


if __name__ == "__main__":
    main()
