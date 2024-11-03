local markup = require("markup")
local log = require("markup.logger")

---@class markup.Block.props : markup.Element.props

---@class markup.Block : markup.Element
---@field _ markup.Block.props
local Block = markup.Element:extend("MarkupBlock")

function Block:init(props)
    props = self:normalize_props(props, {
        type = "block",
    })

    Block.super.init(self, props)
end

---@class markup.Block.constructor.props : markup.Element.constructor.props

---@alias markup.Block.constructor fun(props?: string | markup.Element | markup.Block.constructor.props): markup.Block

---@type markup.Block.constructor
local MarkupBlock = Block

return MarkupBlock
