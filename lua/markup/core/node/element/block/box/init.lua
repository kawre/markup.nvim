local markup = require("markup")
local utils = require("markup.utils") ---@diagnostic disable-line
local log = require("markup.logger") ---@diagnostic disable-line

---@class markup.Box.props : markup.Element.props
---@field align markup.Box.align
---@field spacing markup.Box.spacing
---@field vertical boolean
---@field reverse boolean

---@class markup.Box : markup.Element
---@field protected _ markup.Box.props
---@field protected super markup.Element
local Box = markup.Block:extend("MarkupBox") ---@diagnostic disable-line

---------------------------------
---- Constructor
---------------------------------

function Box:init(props)
    props = self:_normalize_props(props, {
        align = "start",
        spacing = 0,
        vertical = false,
        reverse = false,
    })

    Box.super.init(self, props)
end

---------------------------------
---- Methods
---------------------------------

function Box:after_render()
    local spacing, vertical = self:spacing(), self:vertical()
    local children = self.children

    for i, child in ipairs(self.children) do
        if not vertical then
            local max_height = select(2, self:max_size())
            local child_width = child:width()

            for row = 0, max_height - 1 do
                local line = child:_line(row)
                local padding = child_width - line:width()
                if padding > 0 then
                    line:append(markup.Pad(padding))
                end
                if spacing > 0 and i ~= #children then
                    line:append(markup.Pad(spacing))
                end
            end
        elseif spacing > 0 and i ~= #children then
            child:_newl(spacing)
        end
    end

    Box.super.after_render(self)

    local width = self:box_size()
    local align = self:align()
    for _, line in pairs(self._.lines) do
        local padding = width - line:length()

        if align == "start" then
            line:append(markup.Pad(padding))
        elseif align == "center" then
            local halfpad = math.floor(padding / 2)
            local leftpad, rightpad = halfpad, halfpad + padding % 2
            line:prepend(markup.Pad(rightpad)):append(markup.Pad(leftpad))
        elseif align == "end" then
            line:prepend(markup.Pad(padding))
        end
    end
end

---------------------------------
---- Getters
---------------------------------

function Box:vertical()
    return self._.vertical
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

---@class markup.Box.constructor.props : markup.Element.constructor.props
---@field align? markup.Box.align
---@field spacing? markup.Box.spacing
---@field vertical? boolean
---@field reverse? boolean

---@alias markup.Box.constructor fun(props?: markup.Element | markup.Box.constructor.props): markup.Box

---@type markup.Box.constructor
local MarkupBox = Box ---@diagnostic disable-line

return MarkupBox
