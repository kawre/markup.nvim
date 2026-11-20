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
- `curl`, to download the engine of a release; or Rust 1.85 or newer, to build it

Run `:checkhealth markup` to check them, and that the engine matches the plugin.

## Installation

With [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "kawre/markup.nvim",
  version = "*", -- releases, which come with a built engine
}
```

lazy.nvim runs `build.lua` on install and update. On a release it downloads
the engine for your platform (Linux and macOS on x86_64 and arm64, Windows on
x86_64); anywhere else, such as on `master` without `version`,
it builds the engine with `cargo build --release`.

With any other plugin manager, run `nvim -l build.lua` in the plugin's
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

## For AI agents

markup.nvim comes with an [Agent Skill](https://agentskills.io) that teaches
coding agents its API, in `skills/markup-nvim`, and `llms.txt` points to the
rest of the docs. Both are generated from the code and carry its version.

- Claude Code, as a plugin:

  ```
  /plugin marketplace add kawre/markup.nvim
  /plugin install markup-nvim@markup-nvim
  ```

- Codex, Cursor, Gemini CLI, GitHub Copilot and other agents that read the
  same format: `npx skills add kawre/markup.nvim`
- By hand: `markup-nvim-skill.zip` from a release, or copy `skills/markup-nvim`
  where your agent looks for skills.

## Development

```sh
make test          # build the engine and run the Neovim tests
make test_engine   # the engine's own tests
make format        # StyLua and rustfmt
make lint          # clippy
make coverage      # Lua and Rust coverage, in .tests/coverage
```
