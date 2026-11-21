"""Writes tests/browser/cell.ttf: a font for comparing layouts with a browser.

Every character is as many cells wide as Neovim says, which is what markup.nvim
lays text out with: half an em per cell, so at the page's 20px a cell is exactly
10px, on any machine. Neovim gives the widths: `strdisplaywidth` of each code
point, with the options it starts with, and none for what it joins to the
character before it, such as a combining accent.

Run with `python3 scripts/browser_font.py` after changing it, or when a newer
Neovim measures characters differently.
"""

import json
import subprocess
import tempfile

from fontTools.fontBuilder import FontBuilder
from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.ttLib.tables._c_m_a_p import cmap_format_13

UPEM = 1000
CELL = 500
OUT = "tests/browser/cell.ttf"
# The same widths, for the comparison to see where a test's options differ.
WIDTHS_OUT = "tests/browser/cell-widths.json"

# Runs of code points of one width, as `{ first, last, width }`.
WIDTHS = """
local runs, start, width = {}, nil, nil
local function close(last)
	if start then runs[#runs + 1] = { start, last, width } end
end
for cp = 0x20, 0x10FFFF do
	local w
	if cp < 0xD800 or cp > 0xDFFF then
		local char = vim.fn.nr2char(cp)
		w = vim.fn.strdisplaywidth(char)
		-- What Neovim joins to the character before it takes no cell.
		if vim.fn.strdisplaywidth("a" .. char) == 1 then
			w = 0
		end
	end
	if w ~= width or w == nil then
		close(cp - 1)
		start, width = w and cp or nil, w
	end
end
close(0x10FFFF)
io.write(vim.json.encode(runs))
"""


def widths():
    with tempfile.NamedTemporaryFile("w", suffix=".lua") as script:
        script.write(WIDTHS)
        script.flush()
        out = subprocess.run(
            ["nvim", "--headless", "-u", "NONE", "-l", script.name],
            check=True,
            capture_output=True,
            text=True,
        ).stdout
    return json.loads(out)


def box(cells):
    pen = TTGlyphPen(None)
    if cells > 0:
        pen.moveTo((50, 0))
        pen.lineTo((50, 700))
        pen.lineTo((cells * CELL - 50, 700))
        pen.lineTo((cells * CELL - 50, 0))
        pen.closePath()
    return pen.glyph()


runs = widths()
cells = sorted({width for _, _, width in runs})
names = [".notdef", "space"] + [f"cells{width}" for width in cells]

mapping = {}
for first, last, width in runs:
    for code in range(first, last + 1):
        mapping[code] = f"cells{width}"
mapping[0x20] = "space"

fb = FontBuilder(UPEM, isTTF=True)
fb.setupGlyphOrder(names)
# A format 4 table for what a browser looks up first, then the whole of
# Unicode in a format 13 one, where a run of code points shares one glyph.
fb.setupCharacterMap({code: mapping[code] for code in range(0x20, 0x7F)})
glyphs = {".notdef": box(0), "space": box(0)}
glyphs.update({f"cells{width}": box(width) for width in cells})
fb.setupGlyf(glyphs)
metrics = {".notdef": (CELL, 0), "space": (CELL, 0)}
metrics.update({f"cells{width}": (width * CELL, 0) for width in cells})
fb.setupHorizontalMetrics(metrics)
# A terminal's baseline is the bottom of its cell: all of the line is above it,
# so what sits on the baseline, such as an empty inline-block, ends on a row.
fb.setupHorizontalHeader(ascent=UPEM, descent=0)
fb.setupNameTable({"familyName": "markup cell", "styleName": "Regular"})
fb.setupOS2(
    sTypoAscender=UPEM, sTypoDescender=0, sTypoLineGap=0, usWinAscent=UPEM, usWinDescent=0
)
fb.setupPost(isFixedPitch=1)

table = cmap_format_13(13)
table.platformID, table.platEncID, table.language = 3, 10, 0
table.cmap = mapping
fb.font["cmap"].tables.append(table)

fb.save(OUT)
with open(WIDTHS_OUT, "w") as out:
    json.dump(runs, out, separators=(",", ":"))
print("wrote", OUT, "with", len(runs), "runs of widths", cells)
