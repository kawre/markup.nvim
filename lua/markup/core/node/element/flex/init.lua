local markup = require("markup")
local u = require("markup.utils") ---@diagnostic disable-line: unused-local
local log = require("markup.logger") ---@diagnostic disable-line: unused-local

---@class markup.Flex.props : markup.Element.props

---@class markup.Flex : markup.Element
---@field protected _ markup.Flex.props
---@field protected super markup.Element
local Flex = markup.Block:extend("markup.Flex") ---@diagnostic disable-line: undefined-field

---------------------------------
---- Constructor
---------------------------------

function Flex:init(...)
    self:_extend_default_props({
        display = "flex",
    })
    Flex.super.init(self, ...)
end

---------------------------------
---- Methods
---------------------------------

function Flex:_set_state(renderer, parent)
    Flex.super._set_state(self, renderer, parent)

    self.align = self._.align
    self.spacing = self._.spacing
    self.vertical = self._.vertical
    self.reverse = self._.reverse
end

function Flex:after_render()
    local spacing, vertical = self.spacing, self.vertical
    local children = self.children

    if not vertical or spacing > 0 then
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
    end

    Flex.super.after_render(self)

    local width = self:box_size()
    local align = self.align
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
---- Initializer
---------------------------------

---@alias markup.Flex.constructor markup.Element.constructor

---@type markup.Flex.constructor
local MarkupFlex = Flex ---@diagnostic disable-line: assign-type-mismatch

return MarkupFlex
