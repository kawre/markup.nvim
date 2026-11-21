# Browser layout comparisons

Run `make test_browser` with Neovim, Rust and a Chromium-based browser. Set `CHROME_BIN` to select the browser executable.

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
