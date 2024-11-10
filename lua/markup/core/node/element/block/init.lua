local markup = require("markup")
local log = require("markup.logger") ---@diagnostic disable-line: unused-local

---@class markup.Block.props : markup.Element.props

---@class markup.Block : markup.Element
---@field protected super markup.Element
local Block = markup.Element:extend("MarkupBlock") ---@diagnostic disable-line: undefined-field

---@param props markup.Block.constructor.props
---@param style? markup.Element.style
function Block:init(props, style)
    props = Block.static._normalize_props(props, {
        display = "block",
    })

    Block.super.init(self, props, style)
end

---@class markup.Block.constructor.props : markup.Element.constructor.props

---@alias markup.Block.constructor fun(props?: string|markup.Node|markup.Element.constructor.props, style?: markup.Element.style.props): markup.Element

---@type markup.Block.constructor
local MarkupBlock = Block ---@diagnostic disable-line: assign-type-mismatch

return MarkupBlock
