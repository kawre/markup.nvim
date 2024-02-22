local Element = require("nui.element")

---@class NuiInline : NuiElement
local Inline = Element:extend("NuiInline")

---@alias NuiInline.constructor fun(texts?: NuiText[]): NuiInline
---@type NuiInline|NuiInline.constructor
local NuiInline = Inline

return NuiInline
