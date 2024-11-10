local markup = require("markup")
local u = require("markup.utils") ---@diagnostic disable-line: unused-local
local log = require("markup.logger") ---@diagnostic disable-line: unused-local

---@alias markup.Window.position "float"|"top"|"right"|"bottom"|"left"

---@class markup.Window.props
---@field winid integer
---@field bufnr integer
---@field ns_id integer
---@field buf_opts table<any, any>
---@field win_opts table<any, any>
---@field keys table<string, string>
---@field enter boolean
---@field show boolean
---@field config vim.api.keyset.win_config
---@field position markup.Window.position

---@class markup.Window : markup.Object
---@field protected _ markup.Window.props
local Window = markup.Object("MarkupWindow")

function Window.static:_normalize_props(props)
    local defaults = {
        ns_id = vim.api.nvim_create_namespace("markup.window"),
        enter = false,
        show = true,
        position = "float",
        config = {},
        buf_opts = {},
        win_opts = {
            cursorcolumn = false,
            cursorline = false,
            cursorlineopt = "both",
            fillchars = "eob: ,lastline:…",
            list = false,
            listchars = "extends:…,tab:  ",
            number = false,
            relativenumber = false,
            signcolumn = "no",
            spell = false,
            winbar = "",
            statuscolumn = "",
            wrap = false,
            sidescrolloff = 0,
        },
        keys = {
            q = "close",
        },
    }

    return vim.tbl_deep_extend("force", defaults, props)
end

---@param props markup.Window.constructor.props
function Window:init(props)
    self._ = Window.static:_normalize_props(props)

    if self:props().show == true then
        self:show()
    end
end

local defaults = {
    split = {
        relative = "editor",
        height = 0.4,
        width = 0.4,
    },
    float = {
        relative = "editor",
        height = 0.9,
        width = 0.9,
        zindex = 50,
    },
}

function Window:_is_float()
    return self._.position == "float"
end

---@return vim.api.keyset.win_config
function Window:_win_config()
    local props = self:props()
    local config = props.config

    if self:_is_float() then
        config = vim.tbl_deep_extend("force", defaults.float, config)
    else
        config = vim.tbl_deep_extend("force", defaults.split, config)
    end

    local parent = self:parent_size()
    config.height = config.height == 0 and parent.height or config.height
    config.width = config.width == 0 and parent.width or config.width
    config.height = math.floor(config.height < 1 and parent.height * config.height or config.height)
    config.width = math.floor(config.width < 1 and parent.width * config.width or config.width)

    if self:_is_float() and config.relative ~= "cursor" then
        config.row = config.row or math.floor((parent.height - config.height) / 2)
        config.col = config.col or math.floor((parent.width - config.width) / 2)
    end

    return config
end

function Window:show()
    self:win_open()
    self:apply_opts()
end

---@param preserve_buf? boolean
function Window:close(preserve_buf)
    vim.schedule(function()
        self:win_close()
        if preserve_buf ~= true then
            self:buf_delete()
        end
        -- if self.augroup then
        --     pcall(vim.api.nvim_del_augroup_by_id, self.augroup)
        --     self.augroup = nil
        -- end
    end)
end

function Window:buf_delete()
    if self:buf_is_valid() then
        vim.api.nvim_buf_delete(self._.bufnr, { force = true })
    end
    self._.bufnr = nil
end

function Window:win_close()
    if self:win_is_valid() then
        vim.api.nvim_win_close(self._.winid, true)
    end
    self._.winid = nil
end

function Window:hide()
    self:close(true)
end

function Window:toggle()
    if self:is_valid() then
        self:hide()
    else
        self:show()
    end
end

function Window:buf_open()
    if not self._.bufnr or not self:buf_is_valid() then
        self._.bufnr = vim.api.nvim_create_buf(false, true)
    end

    return self._.bufnr
end

local split_commands = {
    editor = {
        top = "topleft",
        right = "vertical botright",
        bottom = "botright",
        left = "vertical topleft",
    },
    win = {
        top = "aboveleft",
        right = "vertical rightbelow",
        bottom = "belowright",
        left = "vertical leftabove",
    },
}

function Window:_split_cmd(relative, position, size)
    local cmd = split_commands[relative][position]
    return ("silent noswapfile %s %s split"):format(cmd, size)
end

function Window:win_open()
    self:buf_open()

    if self:win_is_valid() then
        return
    end

    local props = self:props()
    local config = self:_win_config()

    if self:_is_float() then
        self._.winid = vim.api.nvim_open_win(props.bufnr, props.enter, config)
    else
        local parent = config.win or 0
        local size = config.vertical and config.width or config.height

        vim.api.nvim_win_call(parent, function()
            vim.cmd(self:_split_cmd(config.relative, props.position, size))
            vim.api.nvim_win_set_buf(0, props.bufnr)
            self._.winid = vim.api.nvim_get_current_win()
        end)

        if props.enter then
            vim.api.nvim_set_current_win(self._.winid)
        end
    end
end

function Window:apply_opts()
    self:apply_buf_opts()
    self:apply_win_opts()
end

function Window:apply_buf_opts()
    if self:buf_is_valid() then
        u.buf_set_opts(self._.bufnr, self._.buf_opts)
    end
end

function Window:apply_win_opts()
    if self:win_is_valid() then
        u.win_set_opts(self._.winid, self._.win_opts)
    end
end

function Window:buf_is_valid()
    return self._.bufnr and vim.api.nvim_buf_is_valid(self._.bufnr)
end

function Window:win_is_valid()
    return self._.winid and vim.api.nvim_win_is_valid(self._.winid)
end

function Window:is_valid()
    return self:win_is_valid()
        and self:buf_is_valid()
        and vim.api.nvim_win_get_buf(self._.winid) == self._.bufnr
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

---@param ns_id? integer
---@param line_start? integer
---@param line_end? integer
function Window:buf_clear_namespace(ns_id, line_start, line_end)
    ns_id = ns_id or self._.ns_id
    vim.api.nvim_buf_clear_namespace(self._.bufnr, ns_id, line_start or 0, line_end or -1)
end

---@param line integer
---@param col integer
---@param opts vim.api.keyset.set_extmark
---@return integer
function Window:buf_set_extmark(ns_id, line, col, opts)
    ns_id = ns_id or self._.ns_id
    return vim.api.nvim_buf_set_extmark(self._.bufnr, ns_id, line, col, opts)
end

---@param buffer_opts? table<any, any>
---@param window_opts? table<any, any>
function Window:set_opts(buffer_opts, window_opts)
    if buffer_opts then
        u.buf_set_opts(self._.bufnr, buffer_opts)
    end
    if window_opts then
        u.win_set_opts(self._.winid, window_opts)
    end
end

---@param option string
---@param fn fun()
---@param inverse? boolean
function Window:with_buf_option(option, fn, inverse)
    local value = self:buf_get_option_value(option)
    if not value then
        inverse = inverse or false
        self:buf_set_option_value(option, not inverse)
        fn()
        self:buf_set_option_value(option, inverse)
    else
        fn()
    end
end

---@param option string
---@param fn fun()
---@param inverse? boolean
function Window:with_win_option(option, fn, inverse)
    local value = self:win_get_option_value(option)
    if not value then
        inverse = inverse or false
        self:win_set_option_value(option, not inverse)
        fn()
        self:win_set_option_value(option, inverse)
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

function Window:bufnr()
    return self._.bufnr
end

function Window:winid()
    return self._.bufnr
end

function Window:parent_size()
    local relative = self:props().config.relative

    local height = relative == "win" and vim.api.nvim_win_get_height(self._.config.win)
        or vim.o.lines
    local width = relative == "win" and vim.api.nvim_win_get_width(self._.config.win)
        or vim.o.columns

    return { width = width, height = height }
end

---@return markup.Window.props
function Window:props()
    return self._
end

---@class markup.Window.constructor.props
---@field winid? integer
---@field bufnr? integer
---@field ns_id? integer
---@field buf_opts? table<any, any>
---@field win_opts? table<any, any>
---@field keys? table<string, string>
---@field enter? boolean
---@field show? boolean
---@field config? vim.api.keyset.win_config
---@field position? markup.Window.position

---@alias markup.Window.constructor fun(props: markup.Window.constructor.props): markup.Window

---@type markup.Window.constructor
local MarkupWindow = Window ---@diagnostic disable-line: assign-type-mismatch

return MarkupWindow
