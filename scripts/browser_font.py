"""Writes tests/browser/cell.ttf: a monospace font for comparing
layouts with a browser. Every printable ASCII character is a box exactly half
an em wide, so at 20px each takes exactly 10px, one cell, on any machine.

Run with `python3 scripts/browser_font.py` after changing it.
"""

from fontTools.fontBuilder import FontBuilder
from fontTools.pens.ttGlyphPen import TTGlyphPen

UPEM = 1000
ADVANCE = 500
OUT = "tests/browser/cell.ttf"


def box(filled):
    pen = TTGlyphPen(None)
    if filled:
        pen.moveTo((50, 0))
        pen.lineTo((50, 700))
        pen.lineTo((450, 700))
        pen.lineTo((450, 0))
        pen.closePath()
    return pen.glyph()


names = [".notdef"] + [f"c{code}" for code in range(32, 127)]
fb = FontBuilder(UPEM, isTTF=True)
fb.setupGlyphOrder(names)
fb.setupCharacterMap({code: f"c{code}" for code in range(32, 127)})
fb.setupGlyf({name: box(name not in (".notdef", "c32")) for name in names})
fb.setupHorizontalMetrics({name: (ADVANCE, 0) for name in names})
fb.setupHorizontalHeader(ascent=800, descent=-200)
fb.setupNameTable({"familyName": "markup cell", "styleName": "Regular"})
fb.setupOS2(sTypoAscender=800, sTypoDescender=-200, usWinAscent=800, usWinDescent=200)
fb.setupPost(isFixedPitch=1)
fb.save(OUT)
print("wrote", OUT)
