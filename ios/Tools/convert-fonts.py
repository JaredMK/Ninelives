#!/usr/bin/env python3
"""
convert-fonts.py — the FONT BRIDGE from the web build to the iOS build.

The web ships VT323 + Press Start 2P as .woff2 (a web-only container). iOS
can't load woff2, so this unwraps them to .ttf — same glyphs, same metrics,
same files, just a different wrapper.

    pip3 install fonttools brotli
    python3 ios/Tools/convert-fonts.py

Writes ios/Assets/Fonts/*.ttf, which the app target bundles and registers via
UIAppFonts. Re-run only if the web's font files are ever replaced.
"""
import os
import sys

try:
    from fontTools.ttLib import TTFont
except ImportError:
    sys.exit("fontTools is missing — run: pip3 install fonttools brotli")

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.normpath(os.path.join(HERE, "..", ".."))
SRC = os.path.join(REPO, "app", "assets", "fonts")
OUT = os.path.join(HERE, "..", "Assets", "Fonts")

os.makedirs(OUT, exist_ok=True)

for name in ("VT323", "PressStart2P"):
    src = os.path.join(SRC, name + ".woff2")
    if not os.path.exists(src):
        sys.exit("missing %s — the web font moved?" % src)
    font = TTFont(src)
    font.flavor = None                    # drop the woff2 wrapper
    dst = os.path.join(OUT, name + ".ttf")
    font.save(dst)
    # The POSTSCRIPT name is what UIFont(name:) wants — print it so the Swift
    # side can never drift from the file.
    print("%-14s -> %-24s postscript=%s  (%d bytes)"
          % (name + ".woff2", os.path.basename(dst),
             font["name"].getDebugName(6), os.path.getsize(dst)))
