local Element = require("nui.element")
local Line = require("nui.line")
local Text = require("nui.text")

---@class NuiBlockData
---@field style NuiBlockStyle
---@field content NuiElement[]

---@class NuiBlock : NuiElement
---@field _ NuiBlockData
local Block = Element:extend("NuiBlock")

function Block:content()
  local content = {}

  local i, len = 1, #self._.content
  while i <= len do
    local element = self._.content[i]

    if element:is_instance_of(Text) then
      local texts = { element }

      while i + 1 <= len and self._.content[i + 1]:is_instance_of(Text) do
        table.insert(texts, self._.content[i + 1])
        i = i + 1
      end

      element = Line(texts)
    end

    table.insert(content, element)
    i = i + 1
  end

  return content
end

function Block:draw(body)
  local content = self:content()

  for _, element in ipairs(content) do
    element:draw(body)
  end
end

---@param text NuiText|string
---@param highlight? string
function Block:append(text, highlight)
  if type(text) == "string" then
    text = Text(text, highlight)
  elseif highlight then
    text:set(text:content(), highlight)
  end

  table.insert(self._.content, text)
end

---@param element NuiElement
function Block:append_child(element)
  table.insert(self._.content, element)
end

---@param class string
---@param style NuiBlockStyle
function Block:init(class, style) --
  Block.super.init(self)

  -- self._.style = style:merge(class)
  self._.content = {}
end

---@alias NuiBlock.constructor fun(style?: NuiBlockStyle): NuiLine
---@type NuiBlock|NuiBlock.constructor
local NuiBlock = Block

return NuiBlock