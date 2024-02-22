local Block = require("nui.block")
local Line = require("nui.line")

---@class NuiPadding : NuiBlock
---@field _ { padding: integer[] } | NuiBlockData
local Padding = Block:extend("NuiPadding")

local function create_vertical_padding(count)
  local padding = {}
  for _ = 1, count do
    table.insert(padding, Line())
  end
  return padding
end

function Padding:get_padding()
  return self._.padding
end

---@param content NuiElement[]
function Padding:vertical_pad(content)
  local padding = self:get_padding()

  if padding[1] > 0 then
    for _, line in ipairs(create_vertical_padding(padding[1])) do
      table.insert(content, 1, line)
    end
  end

  if padding[3] > 0 then
    for _, line in ipairs(create_vertical_padding(padding[3])) do
      table.insert(content, line)
    end
  end
end

---@param content NuiElement[]
function Padding:horizontal_pad(content)
  for _, element in ipairs(content) do
    self:add_horizonal_pad(element)
  end
end

---@param element NuiElement
function Padding:add_horizonal_pad(element)
  if element:is_instance_of(Line) then
    -- table.insert(element._texts, 1, Indent(text or "\t", "leetcode_indent"))
    return
  end

  for _, item in ipairs(element:content()) do
    self:add_horizonal_pad(item)
  end
end

function Padding:content()
  ---@type NuiElement[]
  local content = Padding.super.content(self)

  self:vertical_pad(content)
  -- self:horizontal_pad(content)

  return content
end

---@param content NuiElement[]
---@param padding integer[]
function Padding:init(content, padding)
  Padding.super.init(self, nil, content)
  self._.padding = padding
end

local NuiPadding = Padding

return NuiPadding
