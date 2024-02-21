local Object = require("nui.object")

Classes = {}

---@class NuiBlockStyle
local BlockStyle = Object("NuiBlockStyle")

---@param class string
function BlockStyle:merge(class) --
  if Classes[class] then
    self = vim.tbl_deep_extend("keep", self, Classes[class])
  end

  return self
end

function BlockStyle:init() --
end

---@alias NuiBlockStyle.constructor fun(texts?: NuiText[]): NuiLine
---@type NuiBlockStyle|NuiBlockStyle.constructor
local NuiBlockStyle = BlockStyle

return NuiBlockStyle
