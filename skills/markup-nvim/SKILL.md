---
name: markup-nvim
description: Build reactive user interfaces inside Neovim with markup.nvim - elements with CSS-like props (block, inline, button, flex, grid), signals, views, floating windows and popups, animations, pickers and images. Use when writing, changing or debugging Lua code that calls require("markup"), Markup.view, Markup.window, Markup.picker or Markup.animate, or when asked to build a UI, menu, dashboard, popup or picker in Neovim with markup.nvim.
metadata:
  version: "0.4.0" # x-release-please-version
---

# markup.nvim

For markup.nvim 0.4.0. <!-- x-release-please-version -->

A Neovim plugin for building reactive UIs. You describe the UI as elements
with CSS-like props. A layout engine in Rust lays them out and draws them into
a buffer. Signals update only the parts that read them.

## Mental model

```
signals -> elements (m.block, m.inline, ...) -> view:render() -> engine (Rust) -> buffer
```

- `local m = require("markup")` gives the element constructors, signals and
  components. Requiring it also sets the global `Markup`, which loads modules
  on first use: `Markup.window`, `Markup.view`, `Markup.picker`,
  `Markup.animate`, `Markup.util`, ...
- A **window** (`Markup.window(opts)`) is a float or split with a buffer.
- A **view** (`Markup.view(win, opts)`) draws elements into that window.
  Call `view:render(element)` once. After that the UI updates by itself when
  the signals it reads change. Do not render again to update it.

## Minimal example

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
-- A click or <CR> presses the button.
```

## Elements

`m.<tag>(props, style?)` builds an element. `props` is a table: its list part
holds the children and its keys are props. Shorthands: `m.inline("text")`,
`m.inline("text", "HlGroup")`, `m.block("text")`.

| Tag | What it is |
| --- | --- |
| `m.block` | Starts on a new line and takes the full width, like a CSS block |
| `m.inline` | A run of text in the line, like a CSS inline span |
| `m.button` | A block as wide as its content, interactive, pressed by `on_press` |
| `m.flex` / `m.hflex` / `m.vflex` | Flexbox, row by default, `vflex` is a column |
| `m.grid` | CSS grid, with `columns` and `rows` |
| `m.newl` | An empty line |
| `m.fragment` | Children without a box of their own |

Children can be strings, numbers, elements, lists of them, or **functions**
(including signals). A function child is re-read when the signals it reads
change, and only that part updates.

Props (all of them are in `reference/elements.md` under `markup.node.props`):

- Box: `width`, `height`, `min_*`, `max_*` (cells, `"auto"`, `"fit"`, `"full"`),
  `margin`, `padding` (one number, or CSS order such as `{ y, x }`),
  `border` (`"single"`, `"rounded"`, `"double"`, `"heavy"`, `"half"`),
  `border_style`, `border_sides`, `overflow`, `overflow_x`, `white_space`.
- Flex and grid: `direction`, `vertical`, `reverse`, `wrap`, `justify`,
  `align`, `align_self`, `gap`, `grow`, `shrink`, `basis`, `columns`, `rows`,
  `column`, `row`, `column_span`, `row_span`.
- Position: `position` (`"static"`, `"relative"`, `"absolute"`, `"fixed"`),
  `top`, `right`, `bottom`, `left`, `inset`, `z`, `overlay`.
- Look: `style` is a highlight group name, or a table of attributes such as
  `{ fg = "#ff0000", bold = true }`.
- Interaction: `on_press`, `click` (`"single"`, `"double"`, `false`),
  `on_hover(hovered)`, `interactive`, `snap`.
- **Any prop can be a function**, re-read when the signals it reads change:
  `style = function() return active() and "Visual" or nil end`.

## Reactivity

```lua
local count = m.signal(0)   -- create
count()                     -- read (and subscribe, inside an effect or render)
count(5)                    -- write
count(function(n) return n + 1 end) -- update from the previous value

local double = m.memo(function() return count() * 2 end) -- cached, derived
m.effect(function() print(count()) end) -- runs again when count changes
m.on_cleanup(function() ... end)        -- when the owner unmounts
m.untrack(fn)                           -- read without subscribing
```

Updates are batched and applied on the next turn of the event loop. In tests,
call `require("markup.reactive").flush()` to apply them at once.

## Components and control flow

```lua
local Todo = m.component(function(props)
  local done = m.signal(false) -- state of its own, per instance
  return m.button({
    function() return (done() and "[x] " or "[ ] ") .. props.title end,
    on_press = function() done(not done()) end,
  })
end)

view:render(m.block({
  m.each(items, function(title) return Todo({ title = title }) end),
  m.show(function() return #items() == 0 end, m.inline("nothing to do", "Comment")),
}))
```

- `m.show(when, content, fallback?)` renders `content` while `when()` is truthy.
- `m.each(list, render, { key = fn }?)` renders a keyed list and keeps the UI
  of items that stay.
- `m.collapse(when, content, opts?)` is like `show`, but the height animates.
- `m.slide(key, render, opts?)` slides between pages as `key()` changes.
- `m.use_view()` gives the view of the current component, and
  `m.use_key(lhs, fn, opts?)` binds a key while the component is mounted.
- `m.provide` / `m.inject` pass values down without props.

## Windows

```lua
local win = Markup.window({
  width = 0.5, height = 0.4, -- a fraction of the editor, or cells
  border = "rounded",
  enter = true,
  dim = true, -- dim everything under the popup; or a number from 0 to 1
})
win:close()
```

`position` (such as `"current"`, `"bottom"`) and `relative` make splits and
windows relative to others. See `reference/window.md`.

## Animation, loaders, images, picker

- `m.animated(value, opts)` is a number that animates towards each value
  written to it. `m.frames(list, opts)` cycles through values.
- `m.loader(props)` is a spinner, `m.progress(props)` is a bar.
- `m.image({ data = png_bytes, width = 20 })` draws an image over its box.
- `Markup.picker({ title, items = { { label, value } }, on_select })` is a
  fuzzy picker.
- `Markup.animate.set_fps(n)` changes the frame rate (60 by default).

## Pitfalls

- **`<CR>` presses, like a click.** The view binds it to `view:press()`. Choose
  other keys with `Markup.view(win, { press_key = { "<CR>", "<Space>" } })`, or
  none with `press_key = false`. A component's `m.use_key("<CR>", ...)` takes it
  over while mounted. Do not bind `<CR>` to `view:press()` yourself.
- **`width` is the content box.** Padding and border are added around it, as
  in CSS `box-sizing: content-box`. `width = 8, padding = { 0, 2 }` takes 12 cells.
- **Render once.** Change signals to update the UI. Do not call
  `view:render()` again for every change.
- **A view's window is drawn in `NormalFloat`**, through `MarkupNormal`, even
  when it is a split.
- **The engine must be built** (`cargo build --release`). `:checkhealth markup`
  reports whether it loads.
- Neovim 0.10 or newer.

## Reference

Generated from the annotations in the code: every class, field and function
with its full signature. Read only the file for what you are working on;
`reference/README.md` lists the classes in each.

| File | What is in it |
| --- | --- |
| `reference/elements.md` | `require("markup")`, element constructors, every prop and its type |
| `reference/reactive.md` | signals, memos, effects, owners |
| `reference/view.md` | `Markup.view`, components, loaders, progress |
| `reference/window.md` | `Markup.window` and its options, backdrop, dim |
| `reference/animate.md` | `Markup.animate`, easings |
| `reference/picker.md` | `Markup.picker` |
| `reference/image.md` | images |
| `reference/layout.md` | `Markup.layout`, boxes of windows |
| `reference/misc.md` | config, commands, logging, utilities |
| `reference/devkit.md` | the inspector and stress test, for working on markup.nvim |
| `reference/internals.md` | engine bindings and view internals, rarely needed |
