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

The plugin runs `build.lua` on install and update. On a release it downloads
the engine for your platform (Linux and macOS on x86_64 and arm64, Windows on
x86_64) and checks its SHA-256; anywhere else, such as on `master`, it builds
the engine with `cargo build --release`.

### [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  "kawre/markup.nvim",
  version = "*", -- releases, which come with a built engine
}
```

lazy.nvim runs `build.lua` by itself.

### vim.pack (Neovim 0.12+)

```lua
-- Before vim.pack.add, so it sees the first install too.
vim.api.nvim_create_autocmd("PackChanged", {
  callback = function(ev)
    local data = ev.data
    if data.spec.name == "markup.nvim" and data.kind ~= "delete" then
      vim.system({ "nvim", "-l", "build.lua" }, { cwd = data.path }):wait()
    end
  end,
})

vim.pack.add({
  { src = "https://github.com/kawre/markup.nvim", version = vim.version.range("*") },
})
```

`vim.version.range("*")` follows releases, as `version = "*"` does in lazy.nvim.

### Other plugin managers

Run `nvim -l build.lua` in the plugin's directory after installing or updating
it.

## Checking compatibility

Client plugins can check their supported release range before loading the UI or
the engine. For example, `^0.2` accepts stable releases from 0.2.0 up to 0.3.0
(exclusive). The function accepts the same range syntax as `vim.version.range`.

```lua
local ok, config = pcall(require, "markup.config")
if not (ok and config.supports and config.supports("^0.2")) then
  return -- missing, predates the version check, or outside the supported range
end
```

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
```

A click or `<CR>` presses the button. Pass `press_key` to the view to press with
other keys, as in `Markup.view(win, { press_key = { "<CR>", "<Space>" } })`, or
`false` to bind none.

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
make test BROWSER=1 # also compare committed views against Chromium
make test_engine   # the engine's own tests
make format        # StyLua and rustfmt
make lint          # clippy
make coverage      # Lua and Rust coverage, in .tests/coverage
```
