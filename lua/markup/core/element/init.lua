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
function Element:get_children()
    return self._.children
end

---@param renderer markup.Renderer
function Element:before_build(renderer)
    --
end

---@param renderer markup.Renderer
---@param parent? markup.Element
function Element:build(renderer, parent)
    local content = self:get_children()
    self:before_build(renderer)

    renderer:set_state(self, parent)

    for _, child in ipairs(content) do
        child:build(renderer, self)
    end

    self:after_build(renderer)
end

---@param renderer markup.Renderer
function Element:after_build(renderer)
    local state = renderer:get_state(self)

    for _, child in ipairs(state:get_children()) do
        local child_state = renderer:get_state(child)

        if child_state then
            local child_type = child_state:get_type()

            for _, line in pairs(child_state:get_lines()) do
                local sibling_state = renderer:get_prev_sibling_state(child)
                local sibling_type = sibling_state and sibling_state:get_type()

                if sibling_type and (sibling_type == "block" or child_type == "block") then
                    state:inc_row()
                end

                for _, text in ipairs(line:get_texts()) do
                    state:get_line():append(text)
                end
            end
        end
    end
end

function Element:get_type()
    return self._.type
end

---@class markup.Element.constructor.props
---@field children markup.Element[]
---@field color? string
---@field max_width_chars? integer
---@field type? "block"|"inline"

---@alias markup.Element.constructor fun(props?: string | markup.Element | markup.Element.constructor.props): markup.Element

---@type markup.Element.constructor
local MarkupElement = Element

return MarkupElement
