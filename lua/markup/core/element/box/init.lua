local markup = require("markup")
local utils = require("markup.utils") ---@diagnostic disable-line
local log = require("markup.logger") ---@diagnostic disable-line

---@alias markup.Box.align "start"|"center"|"end"
---@alias markup.Box.direction "row"|"column"
---@alias markup.Box.spacing string|integer

---@class markup.Box.props : markup.Element.props
---@field align markup.Box.align
---@field spacing markup.Box.spacing
---@field direction markup.Box.direction

---@class markup.Box : markup.Element
---@field _ markup.Box.props
local Box = markup.Block:extend("MarkupBox") ---@diagnostic disable-line

---------------------------------
---- Constructor
---------------------------------

function Box:init(props)
    props = self:normalize_props(props, {
        align = "start",
        direction = "column",
        spacing = 0,
    })

    Box.super.init(self, props)
end

---------------------------------
---- Methods
---------------------------------

---@param renderer markup.Renderer
function Box:after_build(renderer)
    local state = renderer:state(self)
    local dir, align, spacing = state.direction, state.align, state.spacing
    local children = state.children

    for i, child in ipairs(children) do
        local child_state = renderer:state(child)
        local child_width = child_state:width()

        if dir == "row" then
            local max_height = select(2, state:max_size(renderer))

            for row = 0, max_height - 1 do
                local line = child_state:line(row)
                local padding = child_width - line:width()
                if padding > 0 then
                    line:append(markup.Padding(padding))
                end
                if spacing > 0 and i ~= #children then
                    line:append(markup.Padding(spacing))
                end
            end
        else
            if spacing > 0 and i ~= #children then
                child_state:newl(spacing)
            end
        end
    end

    Box.super.after_build(self, renderer)

    local width = state:box_size(renderer)
    for _, line in pairs(state.lines) do
        local padding = width - line:length()

        if align == "start" then
            line:append(markup.Padding(padding))
            -- line:pad_right(padding)
        elseif align == "center" then
            local halfpad = math.floor(padding / 2)
            local leftpad, rightpad = halfpad, halfpad + padding % 2
            line:prepend(markup.Padding(rightpad)):append(markup.Padding(leftpad))
        elseif align == "end" then
            -- line:pad_left(padding)
            line:prepend(markup.Padding(padding))
        end
    end
end

---------------------------------
---- Getters
---------------------------------

function Box:direction()
    return self._.direction
end

function Box:align()
    return self._.align
end

function Box:spacing()
    return self._.spacing
end

---------------------------------
---- Initializer
---------------------------------

---@class markup.Box.constructor.props
---@field children? markup.Element[]
---@field spacing? markup.Box.spacing
---@field align? markup.Box.align
---@field direction? markup.Box.direction

---@alias markup.Box.constructor fun(props?: markup.Element | markup.Box.constructor.props): markup.Box

---@type markup.Box.constructor
local MarkupBox = Box ---@diagnostic disable-line

return MarkupBox
