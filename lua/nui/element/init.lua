local Object = require("nui.object")

---@class NuiElement : NuiObject
local Element = Object("NuiElement")

function Element:init()
  self._ = {}
end

---@alias NuiElement.constructor fun(): NuiElement
---@type NuiElement|NuiElement.constructor
local NuiElement = Element

return NuiElement
