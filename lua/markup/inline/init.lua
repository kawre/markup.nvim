local markup = require("markup")
local log = require("markup.logger")

---@class markup.Inline.props : markup.Element.props
---@field children markup.Inline
---@field max_width_chars? integer

---@class markup.Inline : markup.Element
---@field _ markup.Inline.props
local Inline = markup.Element:extend("MarkupInline")

---@class markup.Inline.constructor.props

---@alias markup.Inline.constructor fun(props: string | markup.Inline.constructor.props): markup.Inline

---@type markup.Inline.constructor
local MarkupInline = Inline

return MarkupInline
