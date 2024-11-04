local markup = require("markup")
local utils = require("markup.utils")
local log = require("markup.logger")

---@alias markup.Element.style vim.api.keyset.highlight
---@alias markup.Element.type "block"|"inline"

---@class markup.Element.props
---@field children markup.Element[]
---@field extmark any
---@field type markup.Element.type
---@field style markup.Element.style

---@class markup.Element : markup.Object
---@field _ markup.Element.props
local Element = markup.Object("MarkupElement")

---@param props markup.Element.constructor.props
function Element:init(props)
    self._ = self:normalize_props(props, {
        children = {},
        style = {},
        type = "inline",
    })
end

---@param props table
---@param defaults table
---@return markup.Element.props
function Element:normalize_props(props, defaults)
    local result = {}

    if type(props) == "string" then
        result.children = { markup.Text(props) }
    elseif getmetatable(props) then
        result.children = { props }
    else
        result = props
    end

    return vim.tbl_deep_extend("force", defaults or {}, result)
end

---@return markup.Element[]
function Element:children()
    return self._.children
end

function Element:style()
    return self._.style
end

function Element:type()
    return self._.type
end

---@param renderer markup.Renderer
function Element:before_build(renderer)
    --
end

---@param renderer markup.Renderer
---@param parent markup.Element
function Element:build(renderer, parent)
    renderer:set_state(self, parent)

    self:before_build(renderer)
    local content = self:children()
    for _, child in ipairs(content) do
        child:build(renderer, self)
    end
    self:after_build(renderer)
end

---@param renderer markup.Renderer
function Element:after_build(renderer)
    local state = renderer:state(self)

    for _, child in ipairs(state.children) do
        local child_state = renderer:state(child)

        local sibling_state = renderer:state(state.prev_sibling)
        local child_type = child_state.type

        if sibling_state then
            local sibling_type = sibling_state.type
            if sibling_type == "block" or child_type == "block" then
                state:endl()
            end
        end

        local lines = child_state.lines
        for row, line in pairs(lines) do
            state:append_line(line, state:get_row() + row)
        end

        local dir = state:direction()
        if dir == "row" then
            state:set_row(0)
        else
            state:endl(#lines)
        end
    end
end

---@class markup.Element.constructor.props
---@field children markup.Element[]
---@field color? string
---@field max_width_chars? integer
---@field type? "block"|"inline"

---@alias markup.Element.constructor fun(props?: string | markup.Element | markup.Element.constructor.props): markup.Element

---@type markup.Element.constructor
local MarkupElement = Element ---@diagnostic disable-line

return MarkupElement
