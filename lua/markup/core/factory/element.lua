local markup = require("markup.core")

local log = require("markup.logger") ---@diagnostic disable-line: unused-local

---@class markup.Element
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

local function normalize_props(props, style)
	if not props then
		return nil
	end

	if type(props) ~= "table" then
		return { children = props }
	end
	-- props.style = normalize_style(props.style, style)

	if not props.children then
		local new_props = {}

		for key, value in pairs(props) do
			if type(key) == "number" then
				if value then
					if not new_props.children then
						new_props.children = {}
					end
					table.insert(new_props.children, value)
				end
			else
				new_props[key] = value
			end
		end

		props = new_props
	elseif type(props.children) == "table" then
		props.children = vim.tbl_filter(function(child)
			return not (child == nil or child == false)
		end, props.children)
	end

	if type(props.children) == "table" and #props.children == 1 then
		props.children = props.children[1]
	end

	return props
end

local M = {}

---@type markup.create_element
function M.create(_type, props, style)
	return {
		type = _type,
		props = normalize_props(props), -- not normalized yet
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
