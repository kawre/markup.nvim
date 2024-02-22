local Object = require("nui.object")
local Style = require("nui.element.style")
local Text = require("nui.text")
local Inline = require("nui.element.inline")

---@type table<string, NuiElement>
local Elements = {}

---@class NuiElement.data
---@field style? NuiStyle
---@field id? string
---@field class? string|string[]
---@field content NuiElement[]

---@class NuiElement : NuiObject
---@field _ NuiElement.data
local Element = Object("NuiElement")

---@return NuiStyle.data
function Element:style()
  if not self._.style then
    return {}
  end

  return self._.style:get()
end

---@return string[]
function Element:class()
  if not self._.class then
    return {}
  end

  if type(self._.class) == "string" then
    return { self._.class }
  else
    return self._.class
  end
end

---@return string
function Element:id()
  return self._.id
end

---@param shallow? boolean
---
---@return NuiElement[]
function Element:children(shallow)
  if shallow then
    local children = {}
    for _, child in ipairs(self._.content) do
      table.insert(children, child)
    end
    return children
  else
    return self._.content
  end
end

---@return NuiElement[]
function Element:content()
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

      element = Inline(texts)
    end

    table.insert(content, element)
    i = i + 1
  end

  return content
end

---@param element string|NuiText|NuiElement
function Element:append(element)
  if type(element) == "string" then
    element = Text(element)
  end

  -- if element:is_instance_of(Text) then
  --   element:set(element:content(), highlight)
  -- end

  table.insert(self:children(), element)
end

---@param body NuiBody
---@param parent NuiElement
function Element:draw(body, parent)
  local content = self:children()
  for _, element in ipairs(content) do
    element:draw(body, self)
  end
end

---@param attributes NuiElement.attributes
function Element:init(attributes, elements)
  local attr = attributes or {}

  if attr.id then
    if Elements[attr.id] then
      error("Element with id " .. attr.id .. " already exists")
    end
    Elements[attr.id] = self
  end

  if attr.style and not Object.is_subclass(attr.style, Style) then
    attr.style = Style(attr.style)
  end

  self._ = {
    style = attr.style,
    id = attr.id,
    class = attr.class,
    content = elements or {},
  }
end

---@class NuiElement.attributes
---@field id? string
---@field style? NuiStyle|table
---@field class? string|string[]

---@alias NuiElement.constructor fun(attributes?: NuiElement.attributes, elements?: NuiElement[]): NuiElement
---@type NuiElement|NuiElement.constructor
local NuiElement = Element

function Element.static:get_by_id(id)
  return Elements[id]
end

return NuiElement
