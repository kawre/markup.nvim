local markup = require("markup")

local u = require("markup.utils") ---@diagnostic disable-line: unused-local
local log = require("markup.logger") ---@diagnostic disable-line: unused-local

---@class markup.Renderer.props : markup.Window.props
---@field body markup.Element

---@class markup.Renderer : markup.Window
---@field protected super markup.Window
---@field _ markup.Renderer.props
local Renderer = markup.Window:extend("MarkupRenderer") ---@diagnostic disable-line: undefined-field

---------------------------------
---- Constructor
---------------------------------

---@param props markup.Renderer.constructor.props
function Renderer:init(props)
    local xd = self:_normalize_props(props, {
        body = nil,
    })

    Renderer.super.init(self, xd) ---@diagnostic disable-line: param-type-mismatch

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

---@return markup.Renderer.props
function Renderer:_normalize_props(props, defaults)
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
    u.measure_time("Renderer:render", function()
        local root = markup.Block(self:body())
        self:render_tree(root)
    end)
end

---@param root markup.Element
function Renderer:render_tree(root)
    root:render_node(self) ---@diagnostic disable-line: missing-parameter

    self:with_buf_option("modifiable", function()
        self:clear()
        for row, line in pairs(root:computed_lines()) do
            line:draw(self, row)
        end
    end)
end

---@param line_start? integer
---@param line_end? integer
function Renderer:buf_clear_namespace(line_start, line_end)
    Renderer.super.buf_clear_namespace(self, self._.ns_id, line_start, line_end)
end

function Renderer:clear()
    self:buf_clear_namespace()
    self:buf_set_lines(0, -1, false, {})
end

---------------------------------
---- Setters
---------------------------------

---@param body markup.Element
function Renderer:set_body(body)
    self._.body = body
end

---------------------------------
---- Getters
---------------------------------

---@return markup.Element
function Renderer:body()
    return self._.body
end

---------------------------------
---- Initializer
---------------------------------

---@class markup.Renderer.constructor.props : markup.Window.constructor.props
---@field body markup.Element

---@alias markup.Renderer.constructor fun(props: markup.Renderer.constructor.props): markup.Renderer

---@type markup.Renderer.constructor
local MarkupRenderer = Renderer ---@diagnostic disable-line: assign-type-mismatch

return MarkupRenderer
