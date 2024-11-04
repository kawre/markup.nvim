local markup = require("markup")
local utils = require("markup.utils")
local log = require("markup.logger")

---@alias markup.Box.align "start"|"center"|"end"
---@alias markup.Box.direction "row"|"column"
---@alias markup.Box.spacing string|integer

---@class markup.Box.props : markup.Element.props
---@field align markup.Box.align
---@field spacing markup.Box.spacing
---@field direction markup.Box.direction

---@class markup.Box : markup.Element
---@field _ markup.Box.props
local Box = markup.Block:extend("MarkupBox")

function Box:init(props)
    props = self:normalize_props(props, {
        align = "start",
        direction = "column",
        spacing = 0,
    })

    Box.super.init(self, props)
end

---@param renderer markup.Renderer
function Box:after_build(renderer)
    local state = renderer:get_state(self)
    local align = state:get_align()
    local dir = state:get_direction()

    local max_width, max_height = 0, 0
    local children = state:get_children()
    for _, child in ipairs(children) do
        local child_state = renderer:get_state(child)
        max_height = math.max(max_height, child_state:get_height())
        max_width = math.max(max_width, child_state:get_width())
    end

    for _, child in ipairs(children) do
        local child_state = renderer:get_state(child)
        local width = child_state:get_width()

        if dir == "column" then
            for _, line in pairs(child_state:get_lines()) do
                local padding = max_width - width

                if align == "start" then
                    line:rightpad(padding)
                    line:append(markup.Padding(padding))
                elseif align == "center" then
                    local halfpad = math.floor(padding / 2)
                    -- line:leftpad(halfpad)
                    -- line:rightpad(halfpad + padding % 2)

                    line:prepend(markup.Padding(halfpad))
                    line:append(markup.Padding(halfpad + padding % 2))
                elseif align == "end" then
                    line:prepend(markup.Padding(padding))
                    -- line:leftpad(padding)
                end
            end
        else
            for i = 1, max_height do
                local line = child_state:get_line(i - 1)
                local len = line:length()
                if len < width then
                    line:append(markup.Padding(width - len))
                    -- line:rightpad(width - len)
                end
            end
        end
    end

    Box.super.after_build(self, renderer)
end

---@class markup.Box.constructor.props
---@field children markup.Element[]
---@field spacing? markup.Box.spacing
---@field align? markup.Box.align
---@field direction? markup.Box.direction

---@alias markup.Box.constructor fun(props?: markup.Element | markup.Box.constructor.props): markup.Box

---@type markup.Box.constructor
local MarkupBox = Box

return MarkupBox
