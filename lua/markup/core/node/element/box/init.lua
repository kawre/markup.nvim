local markup = require("markup")
local u = require("markup.utils") ---@diagnostic disable-line: unused-local
local log = require("markup.logger") ---@diagnostic disable-line: unused-local

---@class markup.Box.props : markup.Element.props
---@field align markup.Box.align
---@field spacing markup.Box.spacing
---@field vertical boolean
---@field reverse boolean

---@class markup.Box : markup.Element
---@field protected _ markup.Box.props
---@field protected super markup.Element
---@field align markup.Box.align
---@field spacing markup.Box.spacing
---@field vertical boolean
---@field reverse boolean
local Box = markup.Block:extend("markup.box") ---@diagnostic disable-line: undefined-field

---------------------------------
---- Constructor
---------------------------------

---@param props markup.Box.constructor.props
---@param style? markup.Element.style
function Box:init(props, style)
    props = Box.static._normalize_props(props, {
        align = "start",
        spacing = 0,
        vertical = true,
        reverse = false,
    })

    Box.super.init(self, props, style)
end

---------------------------------
---- Methods
---------------------------------

function Box:_set_state(renderer, parent)
    Box.super._set_state(self, renderer, parent)

    self.align = self._.align
    self.spacing = self._.spacing
    self.vertical = self._.vertical
    self.reverse = self._.reverse
end

function Box:after_render()
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

    Box.super.after_render(self)

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

---@class markup.Box.constructor.props : markup.Element.constructor.props
---@field align? markup.Box.align
---@field spacing? markup.Box.spacing
---@field vertical? boolean
---@field reverse? boolean

---@alias markup.Box.constructor fun(props?: markup.Element|markup.Box.constructor.props, style?: markup.Element.style): markup.Box

---@type markup.Box.constructor
local MarkupBox = Box ---@diagnostic disable-line: assign-type-mismatch

return MarkupBox
