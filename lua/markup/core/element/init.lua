local markup = require("markup")
local utils = require("markup.utils") ---@diagnostic disable-line
local log = require("markup.logger") ---@diagnostic disable-line

---@alias markup.Element.style string|vim.api.keyset.highlight
---@alias markup.Element.type "block"|"inline"

---@class markup.Element.props
---@field id integer
---@field children markup.Node[]
---@field type markup.Element.type
---@field style markup.Element.style

---@class markup.Element : markup.Object
---@field _ markup.Element.props
---@field private GEN_ID fun(): integer STATIC generate a unique id
local Element = markup.Object("MarkupElement")

---------------------------------
---- Static
---------------------------------

Element.static.ID = 1

function Element.static.GEN_ID()
    local id = Element.static.ID
    Element.static.ID = Element.static.ID + 1
    return id
end

---------------------------------
---- Constructor
---------------------------------

---@param props markup.Element.constructor.props
---@param style? markup.Element.style.props
function Element:init(props, style)
    self._ = self:normalize_props(props, {
        children = {},
        style = style or {},
        type = "inline",
        id = Element.GEN_ID(),
    })
end

---------------------------------
---- Methods
---------------------------------

---@param props table
---@param defaults table
function Element:normalize_props(props, defaults)
    local result = {}

    if type(props) == "string" then
        result.children = { markup.Text(props) }
    elseif getmetatable(props) then
        result.children = { props }
    else
        result = props

        if type(props.children) == "string" then
            result.children = { markup.Text(props.children) }
        elseif getmetatable(props.children) then
            result.children = { props.children }
        end
    end

    return vim.tbl_deep_extend("force", defaults or {}, result)
end

---@param renderer markup.Renderer
function Element:before_build(renderer) end ---@diagnostic disable-line

---@param renderer markup.Renderer
---@param parent markup.Element
---@return markup.Element
function Element:build(renderer, parent)
    local state = renderer:set_state(self, parent)

    self:before_build(renderer)
    for _, child in ipairs(state.child_nodes) do
        child:build(renderer, self)
    end
    self:after_build(renderer)

    return self
end

---@param renderer markup.Renderer
function Element:after_build(renderer)
    local state = renderer:state(self)

    for _, child in ipairs(state.children) do
        local child_state = renderer:state(child)

        if child_state.prev_sibling then
            local sibling_state = renderer:state(child_state.prev_sibling) ---@diagnostic disable-line

            if not sibling_state or (sibling_state:is_block() or child_state:is_block()) then
                state:newl()
            end
        end

        local lines = child_state.lines
        for row, line in pairs(lines) do
            state:append(line, state.row + row)
        end

        local dir = state.direction
        if dir == "row" then
            state:set_row(0)
        else
            state:newl(#lines)
        end
    end
end

---------------------------------
---- Getters
---------------------------------

function Element:id()
    return self._.id
end

---@return markup.Node[]
function Element:child_nodes()
    return utils.shallow_copy(self._.children)
end

---@return markup.Element[]
function Element:children()
    return vim.tbl_filter(function(child)
        return utils.is_instance(child, markup.Element)
    end, self._.children)
end

function Element:style()
    return utils.shallow_copy(self._.style)
end

function Element:type()
    return self._.type
end

---------------------------------
---- Initializer
---------------------------------

---@class markup.Element.constructor.props
---@field children? string|markup.Node|markup.Node[]
---@field type? markup.Element.type
---@field style? markup.Element.style

---@alias markup.Element.style.props string|markup.Element.style

---@alias markup.Element.constructor fun(props?: string | markup.Node | markup.Element.constructor.props, style?: markup.Element.style.props): markup.Element

---@type markup.Element.constructor
local MarkupElement = Element ---@diagnostic disable-line

return MarkupElement
