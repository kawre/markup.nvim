local markup = require("markup")
local utils = require("markup.utils")
local log = require("markup.logger")
local State = require("markup.core.window.renderer.state")

---@alias markup.Renderer.state.position { row: integer, col: integer }
---@alias markup.Renderer.state.box { width: integer, height: integer }

---@class markup.Renderer.state
---@field row_start? integer
---@field row_end? integer
---@field col_start? integer
---@field col_end? integer
---@field initial? markup.Renderer.state.position
---@field final? markup.Renderer.state.position
---@field lengths? integer[]
---@field box? markup.Renderer.state.box
---@field parent? markup.Element
---@field rendered_children? markup.Element[]

---@class markup.Renderer.props : markup.Window.props
---@field ns_id integer
---@field body markup.Element
---@field state markup.Renderer.state[]
---@field row integer
---@field row_history {}
---@field lines table<integer, markup.Line>

---@class markup.Renderer : markup.Window
---@field _ markup.Renderer.props
local Renderer = markup.Window:extend("MarkupRenderer")

---@param props markup.Renderer.constructor.props
function Renderer:init(props)
    props = self:normalize_props(props, {
        bufnr = 0,
        winid = 0,
        ns_id = -1,
        state = {},
        lines = { [0] = markup.Line() },
        row = 0,
    })

    Renderer.super.init(self, props)

    self:set_opts({
        modifiable = true,
        buflisted = false,
        matchpairs = "",
        swapfile = false,
        buftype = "nofile",
        filetype = "preview",
        synmaxcol = 0,
    }, {
        wrap = false,
        colorcolumn = "",
        foldenable = false,
        foldcolumn = "0",
        cursorcolumn = false,
        cursorline = false,
        number = false,
        relativenumber = false,
        list = false,
        spell = false,
        signcolumn = "no",
        winfixbuf = true,
    })
    self:setup_autocmds()
end

function Renderer:normalize_props(props, defaults)
    local result = {}

    if type(props) == "number" then
        result.children = { markup.Text(props) }
    elseif getmetatable(props) then
        result.children = { props }
    else
        result = props
    end

    return vim.tbl_deep_extend("force", defaults or {}, result)
end

function Renderer:setup_autocmds()
    -- log.debug(self._.bufnr)
    -- vim.api.nvim_create_autocmd("WinResized", {
    -- 	buffer = self._.bufnr,
    -- 	callback = function()
    -- 		self:render()
    -- 	end,
    -- })
end

---Get grid position at row
---@param row_at integer (0-indexed)
---@return integer, integer (row, col): (0-indexed, 0-indexed)
function Renderer:set_pos(row_at)
    self._.row = row_at
end

function Renderer:reset_pos()
    self._.row = #self._.lines
end

---Get grid position at row
---@param row_at? integer (0-indexed)
---@return integer, integer (row, col): (0-indexed, 0-indexed)
function Renderer:get_pos(row_at)
    row_at = row_at or self._.row
    return row_at, self:get_col(row_at)
end

---Get grid column position at row
---@param row_at? integer (0-indexed)
---@return integer (col) (0-indexed)
function Renderer:get_col(row_at)
    return self:get_line(row_at):length()
end

---@param row_at? integer (0-indexed)
function Renderer:get_line(row_at)
    row_at = row_at or self:get_pos()

    if not self._.lines[row_at] then
        self._.lines[row_at] = markup.Line()
    end

    return self._.lines[row_at]
end

function Renderer:get_lines()
    return self._.lines
end

function Renderer:inc_row(n)
    local old_row = self._.row
    self._.row = old_row + n

    for row = old_row, self._.row do
        if not self._.lines[row] then
            self._.lines[row] = markup.Line()
        end
    end

    return self._.row
end

---@param text markup.Text
---@param row_at? integer (0-indexed)
function Renderer:add_text(text, row_at)
    self:get_line(row_at):append(text)
end

function Renderer:render()
    log.debug("[Renderer:render]")

    local elapsed_ms, fps = utils.measure_time(function()
        self:clear()
        self._.body:render(self)
        self:draw_lines()
    end)

    -- if __TEST__ then
    -- print(("elapsed time: %.2fms [FPS: %d]"):format(elapsed_ms, fps))
    -- end
end

---@param element markup.Element
function Renderer:draw_range(element)
    local row_start, col_start = self:get_pos()
    element:draw(self)
    local row_end = self:get_pos()

    local state = self:get_state(element)
    for _, child in ipairs(state.rendered_children) do
        local child_state = self:get_state(child)
        row_start = math.min(row_start, child_state.row_start)
        row_end = math.max(row_end, child_state.row_end)
        col_start = math.min(col_start, child_state.col_start)
    end

    return row_start, col_start, row_end
end

function Renderer:draw_lines()
    self:with_modifiable(function()
        for row, line in pairs(self._.lines) do
            line:draw(self, row)
        end
    end)
end

function Renderer:clear()
    self:with_modifiable(function()
        vim.api.nvim_buf_set_lines(self._.bufnr, 0, -1, false, {})
    end)
    self._.row = 0
    self._.lines = { [self._.row] = markup.Line() }
    self._.state = {}
end

---@param n? integer
function Renderer:endl(n)
    self:inc_row(n or 1)
end

---Add padding (row_at, col_at)
---@param n integer repeat
---@param row_at? integer (0-indexed)
---@param col_at? integer (0-indexed)
function Renderer:pad(n, row_at, col_at)
    local row, col = self:get_pos(row_at)
    col = col_at or col
    self:get_line(row):append(markup.Padding(n), col)
end

function Renderer:with_modifiable(fn)
    local bufnr = self._.bufnr
    if not (bufnr and vim.api.nvim_buf_is_valid(bufnr)) then
        return
    end

    local modifiable = vim.api.nvim_get_option_value("modifiable", { buf = bufnr })
    if not modifiable then
        utils.set_option_value("modifiable", true, { buf = bufnr })
        fn()
        utils.set_option_value("modifiable", false, { buf = bufnr })
    else
        fn()
    end
end

---@param element markup.Element
---@param state markup.Renderer.state
function Renderer:set_state(element, state)
    local old_state = self._.state[element]
    if old_state and not old_state.parent then
        state.box = { width = self:width(), height = self:height() }
    end

    self._.state[element] = vim.tbl_deep_extend("force", old_state or {}, state)
end

---@param element markup.Element
function Renderer:get_state(element)
    return self._.state[element]
end

---@param element markup.Element
---@param state? markup.Renderer.state
function Renderer:get_parent_state(element, state)
    if state then
        return self:get_state(state.parent)
    else
        local element_state = self:get_state(element)
        return element_state and self:get_state(element_state.parent)
    end
end

function Renderer:append_rendered_child(element, child)
    local state = self:get_state(element)

    if state then
        table.insert(state.rendered_children, child)
    end
end

---@param element markup.Element
function Renderer:get_rendered_size(element)
    local row_start, col_start, row_end, col_end

    local state = self:get_state(element)
    for _, child in ipairs(state.rendered_children) do
        local child_state = self:get_state(child)
        row_start = math.min(row_start, child_state.row_start)
        row_end = math.max(row_end, child_state.row_end)
        col_start = math.min(col_start, child_state.col_start)
    end

    return row_start, col_start, row_end, col_end
end

---@param body markup.Element
function Renderer:set_body(body)
    self._.body = body
end

---@param element markup.Element
function Renderer:get_prev_rendered_sibling(element)
    local parent_state = self:get_parent_state(element)
    return parent_state and parent_state.rendered_children[#parent_state.rendered_children]
end

function Renderer:get_current_element_range(element)
    local state = self:get_state(element)

    local row_start, col_start, row_end, col_end =
        state.row_start, state.col_start, state.row_end, state.col_end

    for _, child in ipairs(state.rendered_children) do
        local child_state = self:get_state(child)
        row_start = math.min(row_start, child_state.row_start)
        row_end = math.max(row_end, child_state.row_end)
        col_start = math.min(col_start, child_state.col_start)
    end

    log.debug({
        row_start = row_start,
        row_end = row_end,
        col_start = col_start,
        col_end = col_end,
    })

    return row_start, col_start, row_end, col_end
end

---@class markup.Renderer.constructor.props
---@field winid integer
---@field bufnr integer
---@field body markup.Element
---@field ns_id? integer

---@alias markup.Renderer.constructor fun(props: markup.Renderer.constructor.props): markup.Renderer

---@type markup.Renderer.constructor
local MarkupRenderer = Renderer

return MarkupRenderer
