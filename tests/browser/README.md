# Browser layout comparisons

Run `make test_browser` with Neovim, the Rust build tools, and a Chromium-based browser. Set `CHROME_BIN` if the browser executable is outside PATH.

Each fixture builds an element tree with the public Lua API. One path renders the tree into a real Neovim window. A separate translator turns the element tags and props into HTML and CSS. Chromium performs the layout. The comparison uses DOM text ranges to locate characters and the root height to preserve blank rows. Both outputs omit trailing space on each line. A difference prints both buffers and exits with a failure.

The initial profile covers static printable ASCII text, block and inline flow, flex rows, grids, integral cell widths and heights, min/max width, column tracks, gaps and horizontal justification. One column is the browser’s monospace character width and one row is a 20px line. Use fixtures with whole-cell geometry. Unsupported props, character sets and fractional text positions produce errors. Highlights, images, clipping and reactive updates are outside this profile.

To try a layout, save a Lua file like this and run `make test_browser FILE=/path/to/case.lua`:

```lua
local m = require("markup")
return {
  {
    name = "wrap at maximum width",
    width = 12,
    tree = m.block({ max_width = 5, "aa bb cc" }),
  },
}
```

Chromium should place `aa bb` and `cc` on separate rows. The expected rows come directly from Chromium each time.
