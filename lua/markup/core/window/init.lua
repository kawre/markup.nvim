local markup = require("markup")

---@class markup.Window.props
---@field winid integer
---@field bufnr integer

---@class markup.Window : markup.Object
---@field protected _ markup.Window.props
local Window = markup.Object("MarkupWindow")

---@param props markup.Window.constructor.props
function Window:init(props)
    self._ = self:_normalize_props(props, {
        bufnr = vim.api.nvim_get_current_buf(),
        winid = vim.api.nvim_get_current_win(),
    })
end

function Window:_normalize_props(props, defaults)
    return vim.tbl_deep_extend("force", defaults or {}, props or {})
end

function Window:buf_is_valid()
    return self._.bufnr and vim.api.nvim_buf_is_valid(self._.bufnr)
end

function Window:win_is_valid()
    return vim.api.nvim_win_is_valid(self._.winid)
end

---@param name string
function Window:buf_get_option_value(name)
    assert(self:buf_is_valid(), "Buffer is not valid")
    return vim.api.nvim_get_option_value(name, { buf = self._.bufnr })
end

---@param name string
---@param value any
function Window:buf_set_option_value(name, value)
    assert(self:buf_is_valid(), "Buffer is not valid")
    vim.api.nvim_set_option_value(name, value, { buf = self._.bufnr })
end

---@param name string
function Window:win_get_option_value(name)
    assert(self:win_is_valid(), "Window is not valid")
    return vim.api.nvim_get_option_value(name, { win = self._.winid, scope = "local" })
end

---@param name string
---@param value any
function Window:win_set_option_value(name, value)
    assert(self:win_is_valid(), "Window is not valid")
    vim.api.nvim_set_option_value(name, value, { win = self._.winid, scope = "local" })
end

---@param start number
---@param end_ number
---@param strict_indexing boolean
---@param replacement string[]
function Window:buf_set_lines(start, end_, strict_indexing, replacement)
    assert(self:buf_is_valid(), "Buffer is not valid")
    vim.api.nvim_buf_set_lines(self._.bufnr, start, end_, strict_indexing, replacement)
end

---@param line_start? integer
---@param line_end? integer
function Window:buf_clear_namespace(ns_id, line_start, line_end)
    vim.api.nvim_buf_clear_namespace(self._.bufnr, ns_id, line_start or 0, line_end or -1)
end

---@param line integer
---@param col integer
---@param opts vim.api.keyset.set_extmark
---@return integer
function Window:buf_set_extmark(line, col, opts)
    return vim.api.nvim_buf_set_extmark(self._.bufnr, 0, line, col, opts)
end

---@param buffer_opts? table<any, any>
---@param window_opts? table<any, any>
function Window:set_opts(buffer_opts, window_opts)
    local u = require("markup.utils")

    if buffer_opts then
        u.buf_set_opts(self._.bufnr, buffer_opts)
    end
    if window_opts then
        u.win_set_opts(self._.winid, window_opts)
    end
end

---@param option string
function Window:with_buf_option(option, fn)
    local value = self:buf_get_option_value(option)
    if not value then
        self:buf_set_option_value(option, true)
        fn()
        self:buf_set_option_value(option, false)
    else
        fn()
    end
end

---@param option string
function Window:with_win_option(option, fn)
    local value = self:win_get_option_value(option)
    if not value then
        self:win_set_option_value(option, true)
        fn()
        self:win_set_option_value(option, false)
    else
        fn()
    end
end

function Window:width()
    return vim.api.nvim_win_get_width(self._.winid)
end

function Window:height()
    return vim.api.nvim_win_get_height(self._.winid)
end

---@class markup.Window.constructor.props
---@field winid integer
---@field bufnr integer

---@alias markup.Window.constructor fun(props: markup.Window.constructor.props): markup.Window

---@type markup.Window.constructor
local MarkupWindow = Window ---@diagnostic disable-line

return MarkupWindow
