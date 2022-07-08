pcall(require, "luacov")

local Popup = require("nui.popup")
local Text = require("nui.text")
local h = require("tests.nui")

local eq = h.eq

describe("nui.popup", function()
  local popup_options = {}

  before_each(function()
    popup_options = {
      ns_id = vim.api.nvim_create_namespace("NuiTest"),
      position = "50%",
      size = {
        height = 2,
        width = 8,
      },
    }
  end)

  describe("border.style", function()
    it("supports string name", function()
      popup_options = vim.tbl_deep_extend("force", popup_options, {
        border = {
          style = "rounded",
          padding = { 0 },
        },
      })

      local popup = Popup(popup_options)

      popup:mount()

      h.assert_buf_lines(popup.border.bufnr, {
        "╭────────╮",
        "│        │",
        "│        │",
        "╰────────╯",
      })
    end)

    it("supports list table", function()
      local style = h.popup.create_border_style_list()

      popup_options = vim.tbl_deep_extend("force", popup_options, {
        border = {
          style = style,
          padding = { 0 },
        },
      })

      local popup = Popup(popup_options)

      popup:mount()

      h.popup.assert_border_lines(popup_options, popup.border.bufnr)
    end)

    it("supports map table", function()
      local style = h.popup.create_border_style_map()

      popup_options = vim.tbl_deep_extend("force", popup_options, {
        border = {
          style = style,
          padding = { 0 },
        },
      })

      local popup = Popup(popup_options)

      popup:mount()

      h.popup.assert_border_lines(popup_options, popup.border.bufnr)
    end)

    describe("supports highlight", function()
      it("as (char, hl_group) tuple in map table", function()
        local hl_group = "NuiPopupTest"
        local style = h.popup.create_border_style_map_with_tuple(hl_group)

        popup_options = vim.tbl_deep_extend("force", popup_options, {
          border = {
            style = style,
            padding = { 0 },
          },
        })

        local popup = Popup(popup_options)

        popup:mount()

        h.popup.assert_border_lines(popup_options, popup.border.bufnr)
        h.popup.assert_border_highlight(popup_options, popup.border.bufnr, hl_group)
      end)

      it("as nui.text in map table", function()
        local hl_group = "NuiPopupTest"
        local style = h.popup.create_border_style_map_with_nui_text(hl_group)

        popup_options = vim.tbl_deep_extend("force", popup_options, {
          border = {
            style = style,
            padding = { 0 },
          },
        })

        local popup = Popup(popup_options)

        popup:mount()

        h.popup.assert_border_lines(popup_options, popup.border.bufnr)
        h.popup.assert_border_highlight(popup_options, popup.border.bufnr, hl_group)
      end)
    end)
  end)

  describe("border.text", function()
    it("supports simple text", function()
      local text = "popup"

      popup_options = vim.tbl_deep_extend("force", popup_options, {
        border = {
          style = "single",
          text = {
            top = text,
          },
        },
      })

      local popup = Popup(popup_options)

      popup:mount()

      local linenr = 1
      local line = vim.api.nvim_buf_get_lines(popup.border.bufnr, linenr - 1, linenr, false)[linenr]
      local byte_start = string.find(line, text)

      popup:unmount()

      eq(type(byte_start), "number")
    end)

    it("supports nui.text", function()
      local text = "popup"
      local hl_group = "NuiPopupTest"

      popup_options = vim.tbl_deep_extend("force", popup_options, {
        border = {
          style = "single",
          text = {
            top = Text(text, hl_group),
          },
        },
      })

      local popup = Popup(popup_options)

      popup:mount()

      local linenr = 1
      local line = vim.api.nvim_buf_get_lines(popup.border.bufnr, linenr - 1, linenr, false)[linenr]
      local byte_start = string.find(line, text)

      local extmarks = h.get_line_extmarks(popup.border.bufnr, popup_options.ns_id, linenr, byte_start, #text)

      popup:unmount()

      eq(type(byte_start), "number")

      eq(#extmarks, 1)
      h.assert_extmark(extmarks[1], linenr, text, hl_group)
    end)
  end)

  describe("method :mount", function()
    it("sets winhighlight from popup", function()
      local winhighlight = "Normal:Normal,FloatBorder:FloatBorder"

      popup_options = vim.tbl_deep_extend("force", popup_options, {
        border = {
          style = "rounded",
          text = {
            top = "text",
          },
        },
        win_options = {
          winhighlight = winhighlight,
        },
      })

      local popup = Popup(popup_options)

      popup:mount()

      eq(vim.api.nvim_win_get_option(popup.border.winid, "winhighlight"), winhighlight)
    end)

    it("does nothing if popup mounted", function()
      popup_options = vim.tbl_deep_extend("force", popup_options, {
        border = {
          style = "rounded",
          text = {
            top = "text",
          },
        },
      })

      local popup = Popup(popup_options)

      popup:mount()

      local bufnr, winid = popup.border.bufnr, popup.border.winid
      eq(type(bufnr), "number")
      eq(type(winid), "number")

      popup.border:mount()

      eq(bufnr, popup.border.bufnr)
      eq(winid, popup.border.winid)
    end)
  end)

  describe("method :set_text", function()
    it("works", function()
      local text_top, text_bottom = "top", "bot"

      popup_options = vim.tbl_deep_extend("force", popup_options, {
        border = {
          style = "rounded",
          text = {
            top = text_top,
            top_align = "left",
          },
        },
      })

      local popup = Popup(popup_options)

      popup:mount()

      h.assert_buf_lines(popup.border.bufnr, {
        "╭top─────╮",
        "│        │",
        "│        │",
        "╰────────╯",
      })

      popup.border:set_text("top", text_top, "center")

      h.assert_buf_lines(popup.border.bufnr, {
        "╭──top───╮",
        "│        │",
        "│        │",
        "╰────────╯",
      })

      popup.border:set_text("top", text_top, "right")

      h.assert_buf_lines(popup.border.bufnr, {
        "╭─────top╮",
        "│        │",
        "│        │",
        "╰────────╯",
      })

      local hl_group = "NuiPopupTest"

      popup.border:set_text("bottom", Text(text_bottom, hl_group))

      h.assert_buf_lines(popup.border.bufnr, {
        "╭─────top╮",
        "│        │",
        "│        │",
        "╰──bot───╯",
      })

      local linenr = 4
      local line = vim.api.nvim_buf_get_lines(popup.border.bufnr, linenr - 1, linenr, false)[1]
      local byte_start = string.find(line, text_bottom)

      local extmarks = h.get_line_extmarks(popup.border.bufnr, popup_options.ns_id, linenr, byte_start, #text_bottom)
      h.assert_extmark(
        vim.tbl_filter(function(extmark)
          return extmark[4].hl_group == hl_group
        end, extmarks)[1],
        linenr,
        text_bottom,
        hl_group
      )

      popup:unmount()
    end)

    it("does nothing for simple border", function()
      popup_options = vim.tbl_deep_extend("force", popup_options, {
        border = {
          style = "rounded",
        },
      })

      local popup = Popup(popup_options)

      popup:mount()

      eq(type(popup.border.bufnr), "nil")

      popup.border:set_text("top", "text")

      eq(type(popup.border.bufnr), "nil")

      popup:unmount()
    end)
  end)
end)
