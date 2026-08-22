#!/usr/bin/env python3
"""Build the tiny deterministic font used to detect unresolved glyphs.

The font maps only U+FDD0 to glyph 1. Glyphs 0 (.notdef) and 1 have identical
outlines and metrics, so a platform-supported character renders differently,
while a genuinely unresolved character is byte-identical to the mapped
sentinel without introducing a second unresolved code point.
"""

from pathlib import Path

from fontTools.fontBuilder import FontBuilder
from fontTools.pens.ttGlyphPen import TTGlyphPen

REPO = Path(__file__).resolve().parent.parent
OUTPUT = REPO / "assets" / "font" / "GlyphCoverageProbe.ttf"


def box_glyph():
    pen = TTGlyphPen(None)
    pen.moveTo((80, 0))
    pen.lineTo((520, 0))
    pen.lineTo((520, 700))
    pen.lineTo((80, 700))
    pen.closePath()
    pen.moveTo((150, 80))
    pen.lineTo((150, 620))
    pen.lineTo((450, 620))
    pen.lineTo((450, 80))
    pen.closePath()
    return pen.glyph()


def main() -> None:
    builder = FontBuilder(1000, isTTF=True)
    builder.setupGlyphOrder([".notdef", "sentinel"])
    builder.setupCharacterMap({0xFDD0: "sentinel"})
    builder.setupGlyf({".notdef": box_glyph(), "sentinel": box_glyph()})
    builder.setupHorizontalMetrics(
        {".notdef": (600, 0), "sentinel": (600, 0)}
    )
    builder.setupHorizontalHeader(ascent=800, descent=-200)
    builder.setupOS2(
        sTypoAscender=800,
        sTypoDescender=-200,
        usWinAscent=800,
        usWinDescent=200,
    )
    builder.setupNameTable(
        {
            "familyName": "Extera Missing Glyph Probe",
            "styleName": "Regular",
            "uniqueFontIdentifier": "ExteraMissingGlyphProbe-Regular",
            "fullName": "Extera Missing Glyph Probe Regular",
            "psName": "ExteraMissingGlyphProbe-Regular",
            "version": "Version 1.0",
        }
    )
    builder.setupPost()
    builder.setupMaxp()
    builder.setupHead()
    builder.font.recalcTimestamp = False
    builder.font["head"].created = 0
    builder.font["head"].modified = 0
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    builder.save(OUTPUT)
    print(f"wrote {OUTPUT} ({OUTPUT.stat().st_size} bytes)")


if __name__ == "__main__":
    main()
