local markup = require("markup")
local log = require("markup.logger") ---@diagnostic disable-line: unused-local

---@class markup.Block : markup.Element
---@field protected super markup.Element
local Block = markup.Element:extend("markup.block") ---@diagnostic disable-line: undefined-field

function Block:after_init()
    self._.display = "block"
end

---@class markup.Block.constructor.props : markup.Element.constructor.props
---@alias markup.Block.constructor markup.Element.constructor

---@type markup.Block.constructor
local MarkupBlock = Block ---@diagnostic disable-line: assign-type-mismatch

return MarkupBlock
