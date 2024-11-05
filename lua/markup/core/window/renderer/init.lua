local markup = require("markup")
local State = require("markup.core.element.state")

local utils = require("markup.utils") ---@diagnostic disable-line
local log = require("markup.logger") ---@diagnostic disable-line

---@class markup.Renderer.props : markup.Window.props
---@field ns_id integer
---@field body markup.Element
---@field state table<markup.Element, markup.Element.State>

---@class markup.Renderer : markup.Window
---@field _ markup.Renderer.props
local Renderer = markup.Window:extend("MarkupRenderer") ---@diagnostic disable-line

---------------------------------
---- Constructor
---------------------------------

---@param props markup.Renderer.constructor.props
function Renderer:init(props)
    props = self:normalize_props(props, {
        bufnr = 0,
        winid = 0,
        ns_id = vim.api.nvim_create_namespace("markup.nvim"),
        state = {},
        body = nil,
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

---------------------------------
---- Methods
---------------------------------

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
        -- local root = markup.Block(self:body())
        self:renderElement(self:body())
    end)

    -- if __TEST__ then
    print((" - render time: %.2fms [FPS: %d]"):format(elapsed_ms, fps))
    -- end
end

---@param element markup.Element
function Renderer:renderElement(element)
    self:clear()

    element:build(self) ---@diagnostic disable-line
    local state = self:state(element)

    self:with_modifiable(function()
        self:buf_set_lines(0, -1, false, {})
        for row, line in pairs(state.lines) do
            line:draw(self, row)
        end
    end)
end

---@param line_start? integer
---@param line_end? integer
function Renderer:buf_clear_namespace(line_start, line_end)
    line_start = line_start or 0
    line_end = line_end or -1
    vim.api.nvim_buf_clear_namespace(self._.bufnr, self._.ns_id, line_start, line_end)
end

function Renderer:clear()
    self:buf_clear_namespace()
    self._.state = {}
end

function Renderer:with_modifiable(fn)
    local modifiable = self:buf_get_option_value("modifiable")
    if not modifiable then
        self:buf_set_option_value("modifiable", true)
        fn()
        self:buf_set_option_value("modifiable", false)
    else
        fn()
    end
end

---------------------------------
---- Setters
---------------------------------

---@param body markup.Element
function Renderer:set_body(body)
    self._.body = body
end

---@param element markup.Element
---@param parent markup.Element
---@return markup.Element.State
function Renderer:set_state(element, parent)
    self._.state[element:id()] = State(element, parent, self)
    return self._.state[element:id()]
end

---------------------------------
---- Getters
---------------------------------

---@return markup.Element
function Renderer:body()
    return self._.body
end

---@param element markup.Element
---@return markup.Element.State
function Renderer:state(element)
    assert(element.id, "Element must have an id")
    return self._.state[element:id()]
end

---@param element markup.Element
function Renderer:parent_state(element)
    local state = self:state(element)
    return state and self:state(state.parent)
end

---@param element markup.Element
function Renderer:prev_sibling_state(element)
    local prev_sibling = self:state(element).prev_sibling
    if prev_sibling then
        return self:state(prev_sibling)
    end
end

---------------------------------
---- Initializer
---------------------------------

---@class markup.Renderer.constructor.props
---@field winid integer
---@field bufnr integer
---@field body markup.Element
---@field ns_id? integer

---@alias markup.Renderer.constructor fun(props: markup.Renderer.constructor.props): markup.Renderer

---@type markup.Renderer.constructor
local MarkupRenderer = Renderer ---@diagnostic disable-line

return MarkupRenderer
