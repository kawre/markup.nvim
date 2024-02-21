local Block = require("nui.block")

---@class NuiBodyData : NuiBlockData
---@field line_index integer

---@class NuiBody : NuiBlock
---@field _ NuiBodyData
local Body = Block:extend("NuiBody")

---@param inc? integer
function Body:get_line_idx(inc)
  local index = self._.line_index
  self._.line_index = self._.line_index + (inc or 0)
  return index
end

function Body:draw(data)
  self.bufnr = data.bufnr
  self.win_id = data.winid
  local content = self:content()

  self._.line_index = 1

  for _, element in ipairs(content) do
    element:draw(self)
  end
end

function Body:init() --
  Body.super.init(self)

  self._.line_index = 1
end

local NuiBody = Body

return NuiBody
