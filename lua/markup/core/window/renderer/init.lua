local markup = require("markup")
local utils = require("markup.utils")
local log = require("markup.logger")
local State = require("markup.core.element.state")

---@alias markup.Renderer.state.position { row: integer, col: integer }
---@alias markup.Renderer.state.box { width: integer, height: integer }

---@class markup.Renderer.props : markup.Window.props
---@field ns_id integer
---@field body markup.Element
---@field state table<markup.Element, markup.Element.State>

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

function Renderer:render()
    local elapsed_ms, fps = utils.measure_time(function()
        self:clear()

        local body = self._.body
        local DOM = markup.Element({ children = body })

        self._.state[DOM] = State(DOM)

        body:build(self, DOM)
        self:draw_lines(body)
    end)

    if __TEST__ then
        print(("elapsed time: %.2fms [FPS: %d]"):format(elapsed_ms, fps))
    end
end

function Renderer:draw_lines(body)
    local state = self:get_state(body)

    self:with_modifiable(function()
        for row, line in pairs(state:get_lines()) do
            line:draw(self, row)
        end
    end)
end

function Renderer:clear()
    self:with_modifiable(function()
        vim.api.nvim_buf_set_lines(self._.bufnr, 0, -1, false, {})
    end)
    self._.state = {}
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
---@param parent markup.Element
function Renderer:set_state(element, parent)
    self._.state[element] = State(element, parent)
    return self._.state[element]
end

---@param element markup.Element
function Renderer:get_state(element)
    return self._.state[element]
end

function Renderer:get_prev_sibling_state(element)
    local state = self:get_state(element)
    if not state then
        return
    end

    local prev_sibling = state:get_prev_sibling()

    if prev_sibling then
        return self:get_state(prev_sibling)
    end
end

---@param element markup.Element
function Renderer:get_parent_state(element)
    local state = self:get_state(element)
    return state and self:get_state(state:get_parent())
end

---@param body markup.Element
function Renderer:set_body(body)
    self._.body = body
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
