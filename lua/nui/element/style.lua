local Object = require("nui.object")

---@class NuiStyle.properties
---@field padding? integer[]
---@field padding_top? integer
---@field padding_right? integer
---@field padding_bottom? integer
---@field padding_left? integer
-- -@field margin? integer[]
-- -@field margin_top? integer
-- -@field margin_right? integer
-- -@field margin_bottom? integer
-- -@field margin_left? integer
---@field gap? integer
---@field highlight? string
---@field position? "left"|"center"|"right"

---@class NuiStyle.data
---@field padding integer[]
---@field gap? integer
---@field highlight? string
---@field position? "left"|"center"|"right"

---@class NuiStyle
---@field _ NuiStyle.properties
local Style = Object("NuiStyle")

---@param class string|string[]
function Style:merge(class) --
  return self
end

function Style:get_padding()
  if not self._.padding then
    if self._.position then
      return { 0, 0, 0, 0 }
    end
    return
  end

  ---@type integer[]
  local padding = self._.padding
  if #padding > 4 then
    error("padding can only have 1-4 values")
  end
  if #padding == 1 then
    padding = { padding[1], padding[1], padding[1], padding[1] }
  elseif #padding == 2 then
    padding = { padding[1], padding[2], padding[1], padding[2] }
  elseif #padding == 3 then
    padding = { padding[1], padding[2], padding[3], padding[2] }
  end

  if self._.padding_top then
    padding[1] = self._.padding_top
  elseif self._.padding_right then
    padding[2] = self._.padding_right
  elseif self._.padding_bottom then
    padding[3] = self._.padding_bottom
  elseif self._.padding_left then
    padding[4] = self._.padding_left
  end

  return padding
end

---@return NuiStyle.data
function Style:get()
  return {
    padding = self:get_padding(),
    gap = self._.gap,
    highlight = self._.highlight,
    position = self._.position,
  }
end

---@param properties NuiStyle.properties
function Style:init(properties)
  self._ = properties
end

---@alias NuiStyle.constructor fun(properties: NuiStyle.properties): NuiLine
---@type NuiStyle|NuiStyle.constructor
local NuiStyle = Style

return NuiStyle
