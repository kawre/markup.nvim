# Browser layout comparisons

Run `make test_browser` with Neovim, Rust and a Chromium-based browser. Set `CHROME_BIN` to select the browser executable.

## Cells

The page uses `tests/browser/cell.ttf`, a font in which every printable ASCII character is exactly half an em wide: 10px at the page's 20px. A cell is then exactly 10px wide and a row 20px tall on any machine, whatever monospace font it has. Lengths are translated to pixels, not `ch`: Chrome rounds `ch` on its own, a little short of the characters, and boxes that fit to the cell in markup.nvim would wrap in the browser. `scripts/browser_font.py` writes the font.

Text breaks as markup.nvim breaks it: a word longer than its line breaks anywhere, but the narrowest a box can be is its longest word. That is CSS `overflow-wrap: break-word`.

## Conventions

A mismatch is a difference from CSS, which markup.nvim fixes. A few things are terminal conventions instead, and the translation gives them the same meaning in the browser:

- A run of inline content that is only empty text is a line, as `m.block("")` makes a blank one. In the browser an empty inline-block holds the line open.
- An inline given a size (`width`, `height`, `min_width` or `max_width`) is an inline-block.
- `center` and `end` never push content past the start of its box: a terminal has no column before the first. That is CSS `safe` alignment.

What the translation adds for these is marked `data-line` and takes no place in element paths.

Each fixture supplies one static markup.nvim tree and a viewport width in cells. The runner mounts the tree in Neovim and translates it into HTML and CSS for Chromium. It compares the **border box** of every authored block, flex container and grid container, including empty and nested boxes. Both trees identify each element by its path among element siblings. For example, `/1/2` is the second element child of the first top-level element.

Chromium supplies `getBoundingClientRect()`. The runner converts its viewport-relative coordinates to cells relative to the fixture root. On the engine side it reads the layout inspector and removes margins from the outer rectangle. A mismatch reports the path and the two rectangles in `[x, y, width, height]` order.

The profile supports whole-cell geometry, printable ASCII, inline flow, flex rows, grids, integer widths and heights, min/max width, column tracks, gaps and horizontal justification. Inline spans and text participate in intrinsic sizing and wrapping. Fractional browser rectangles are reported as skipped fixtures.

Set `check_text = true` on a fixture to also compare its rendered character rows. Fixture text is limited to printable ASCII (space through `~`). Chromium supplies each visible character’s position and advance. A text comparison requires one column per character and unique whole-cell placement. Leading and internal spaces and blank rows count. Trailing spaces are treated as empty cells.

To try a layout, save a Lua file and run `make test_browser FILE=/path/to/case.lua`:

```lua
local m = require("markup")
return {
  {
    name = "empty child of capped parent",
    width = 12,
    tree = m.block({ max_width = 5, m.block({ height = 2 }) }),
  },
}
```

Chromium gives the child at `/1/1` the rectangle `[0, 0, 5, 2]`. This fixture detects a width error even though both renderers display a blank surface.

## Existing Neovim tests

Run `make test BROWSER=1` to instrument the existing MiniTest suite. The dedicated **Browser layout comparisons** CI job uses this mode on stable Neovim. Ordinary tests and coverage use their usual runner.

Each attached markup view records distinct committed frames from the running test, including reactive updates and resizes. The capture uses the mounted node tree, the input style values sent to the engine, its computed boxes, and the painted buffer. Chromium processes the captured layouts in batches after MiniTest finishes, so browser startup does not run inside animation or input callbacks.

The runner compares whole-cell rectangles and printable ASCII text where the browser profile applies. Frames containing unsupported inputs, such as wide characters, carry a skip reason. Borders, clipping, and absolutely positioned content get geometry checks only. Tests that exercise signals, configuration, or other behavior without rendering a view still run their original assertions.

The job fails on a test failure, a browser mismatch, a capture error, or zero successful comparisons. Its `browser-comparison-report` artifact (`.tests/browser-report.jsonl` locally) contains counts per test case, skip reasons, and the viewport and translated HTML for mismatches. A mismatch records a difference from browser CSS, which can also be an intentional TUI convention.
