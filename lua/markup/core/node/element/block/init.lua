local markup = require("markup")
local log = require("markup.logger") ---@diagnostic disable-line: unused-local

---@class markup.Block : markup.Element
---@field protected super markup.Element
local Block = markup.Element:extend("markup.block") ---@diagnostic disable-line: undefined-field

function Block:init(...)
    self:_extend_default_props({
        display = "block",
    })
    Block.super.init(self, ...)
end

function Block:after_render()
    markup.Inline.after_render(self) ---@diagnostic disable-line: undefined-field
end

---@class markup.Block.constructor.props : markup.Element.constructor.props
---@alias markup.Block.constructor markup.Element.constructor

---@type markup.Block.constructor
local MarkupBlock = Block ---@diagnostic disable-line: assign-type-mismatch

return MarkupBlock
