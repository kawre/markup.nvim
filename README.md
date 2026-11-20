<div align="center">

# markup.nvim

</div>

Build reactive user interfaces inside Neovim. You describe the UI as elements
with CSS-like props. A layout engine written in Rust lays them out and draws
them into a buffer. Signals update only the parts that change.

- **Layout**: blocks, inline text, flexbox, grid, absolute and fixed
  positioning, padding, margin, borders and text wrapping, with exact widths
  for wide characters and icons.
- **Reactivity**: signals, memos and effects, with components that update in place.
- **Building blocks**: windows and popups that can dim what is under them,
  animations, spinners, progress bars, slides, images and a fuzzy picker.
- **Devkit**: an inspector that shows the element tree, box model and frame
  times of a view.

## Requirements

- Neovim 0.10 or newer
- Rust 1.85 or newer, to build the engine

Run `:checkhealth markup` to check both.

## Installation

With [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "kawre/markup.nvim",
  build = "cargo build --release",
}
```

With any other plugin manager, run `cargo build --release` in the plugin's
directory after installing or updating it.

## Example

```lua
local m = require("markup")

local count = m.signal(0)

local win = Markup.window({ width = 30, height = 5, border = "rounded", enter = true })
local view = Markup.view(win)

view:render(m.block({
  padding = { 0, 1 },
  m.block({ m.inline("Pressed "), m.inline(count, "Number"), m.inline(" times") }),
  m.button({
    "[ press me ]",
    margin_top = 1,
    style = "Special",
    on_press = function()
      count(count() + 1)
    end,
  }),
}))

-- A click presses the button already. This makes <CR> press it too.
vim.keymap.set("n", "<CR>", function()
  view:press()
end, { buffer = win.buf })
```

## Development

```sh
make test          # build the engine and run the Neovim tests
make test_engine   # the engine's own tests
make format        # StyLua and rustfmt
make lint          # clippy
make coverage      # Lua and Rust coverage, in .tests/coverage
```
