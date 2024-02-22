local Object = require("nui.object")

Classes = {}

---@class NuiClass
local Class = Object("NuiClass")

function Class:init(name, style)
  self.name = name
  self.style = style
end

local NuiClass = Class

---@param name string
---@param style NuiStyle
function Class.static:create(name, style)
  Classes[name] = NuiClass(name, style)
end

function Class.static:get(name)
  return Classes[name]
end

return NuiClass
