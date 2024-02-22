local Element = require("nui.element")
local Inline = require("nui.element.inline")
local Text = require("nui.text")

---@class NuiBlock.data
---@field style NuiStyle
---@field content NuiElement[]

---@class NuiBlock : NuiElement
---@field _ NuiBlock.data
local Block = Element:extend("NuiBlock")

---@alias NuiBlock.constructor fun(classes?: string[], style?: NuiStyle): NuiLine
---@type NuiBlock|NuiBlock.constructor
local NuiBlock = Block

return NuiBlock
