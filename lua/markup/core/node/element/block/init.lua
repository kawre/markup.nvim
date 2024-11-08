local markup = require("markup")
local log = require("markup.logger") ---@diagnostic disable-line

---@class markup.Block.props : markup.Element.props

---@class markup.Block : markup.Element
---@field _ markup.Block.props
local Block = markup.Element:extend("MarkupBlock") ---@diagnostic disable-line

---@param props markup.Block.constructor.props
function Block:init(props)
    props = self:_normalize_props(props, {
        display = "block",
    })

    Block.super.init(self, props)
end

---@class markup.Block.constructor.props : markup.Element.constructor.props

---@alias markup.Block.constructor fun(props?: string | markup.Element | markup.Block.constructor.props): markup.Block

---@type markup.Block.constructor
local MarkupBlock = Block ---@diagnostic disable-line

return MarkupBlock
