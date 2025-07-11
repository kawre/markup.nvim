local markup = require("markup.core")
local default_styles = require("markup.core.factory.element.default")

local log = require("markup.logger") ---@diagnostic disable-line: unused-local

---@class markup.xElement
---@field type string
---@field props? markup.xElement.props
---@field ref? any
---@field key? any
---@field _style? markup.Element.style.props
---@field _owner? any

---@alias markup.xElement.props
---| markup.Element.constructor.props
---| { children?: any }

---@alias markup.create_element.props
---| markup.xElement.props
---| string
---| number

---@alias markup.create_element
---| fun(type: markup.Fiber.type, props?: markup.create_element.props, style?: markup.Element.style.props): markup.xElement

---@alias markup.create_element_from
---| fun(props?: markup.create_element.props, style?: markup.Element.style.props): markup.xElement

---@alias markup.create_element_from_text
---| markup.create_element_from

---@alias markup.create_element_from_element
---| markup.create_element_from

local M = {}

---@type markup.create_element
function M.create(type, props, style)
	return {
		type = type,
		props = props, -- not normalized yet
		_style = style, -- store as temporary variable to later merge with props.style
		ref = nil,
		key = nil,
	}
end

function M.create_component(Component)
	return function(...)
		return M.create(Component, ...)
	end
end

function M.create_fragment(...)
	return M.create("fragment", ...)
end

return M
