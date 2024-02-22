local Object = require("nui.object")
local Style = require("nui.element.style")

---@type table<string, NuiElement>
Elements = {}

---@class NuiElement.data
---@field style? NuiStyle
---@field id? string
---@field class? string|string[]
---@field content NuiElement[]

---@class NuiElement : NuiObject
---@field _ NuiElement.data
local Element = Object("NuiElement")

function Element:get_style()
  if not self._.style then
    return
  end
  return self._.style:get()
end

function Element:content()
  return self._.content
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
