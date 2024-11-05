local markup = require("markup")
local State = require("markup.core.element.state")

local utils = require("markup.utils") ---@diagnostic disable-line
local log = require("markup.logger") ---@diagnostic disable-line

---@alias markup.Renderer.state.position { row: integer, col: integer }
---@alias markup.Renderer.state.box { width: integer, height: integer }

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
        ns_id = -1,
        state = {},
    })

    Renderer.super.init(self, props)
    self.root = markup.Element(self:body())

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
        self:renderElement(self:body())
    end)

    if not __TEST__ then
        log.debug((" - render time: %.2fms [FPS: %d]"):format(elapsed_ms, fps))
    end
end

---@param element markup.Element
function Renderer:renderElement(element)
    self:clear()

    element:build(self) ---@diagnostic disable-line
    local state = self:state(element)

    self:with_modifiable(function()
        vim.api.nvim_buf_set_lines(self._.bufnr, 0, -1, false, {})
        for row, line in pairs(state.lines) do
            line:draw(self, row)
        end
    end)
end

function Renderer:clear()
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

---------------------------------
---- Setters
---------------------------------

---@param body markup.Element
function Renderer:set_body(body)
    self._.body = body
end

---@param element markup.Element
---@param parent markup.Element
function Renderer:set_state(element, parent)
    self._.state[element] = State(element, parent)

    return self._.state[element]
end

---------------------------------
---- Getters
---------------------------------

---@return markup.Element
function Renderer:body()
    return self._.body
end

---@param element markup.Element
function Renderer:state(element)
    return self._.state[element]
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
