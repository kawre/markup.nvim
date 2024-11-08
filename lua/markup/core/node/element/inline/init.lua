local markup = require("markup")

---@class markup.Inline.props : markup.Element.props

---@class markup.Inline : markup.Element
---@field _ markup.Inline.props
local Inline = markup.Element:extend("MarkupInline") ---@diagnostic disable-line: undefined-field

---@class markup.Inline.constructor.props : markup.Element.constructor.props

---@alias markup.Inline.constructor fun(props?: string | markup.Node | markup.Element.constructor.props, style?: markup.Element.style.props): markup.Element

---@type markup.Element.constructor
local MarkupInline = Inline ---@diagnostic disable-line: assign-type-mismatch

return MarkupInline
