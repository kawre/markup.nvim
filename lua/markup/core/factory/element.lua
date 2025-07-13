local log = require("markup.logger") ---@diagnostic disable-line: unused-local
local Element = require("markup.core.element")

local M = {}

local function normalize_props(props, style)
	if not props then
		return {}
	elseif type(props) ~= "table" or Element.is_instance(props) then
		return { children = props }
	end

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
	elseif type(props.children) == "table" and not Element.is_instance(props.children) then
		props.children = vim.tbl_filter(function(child)
			return not (child == nil or child == false)
		end, props.children)
	end

	if type(props.children) == "table" and #props.children == 1 then
		props.children = props.children[1]
	end

	return props
end

---@alias markup.factory.Element.constructor.props.children
---| string
---| number
---| table

---@alias markup.factory.Element.constructor.props
---| markup.factory.Element.constructor.props.children
---| { children?: markup.factory.Element.constructor.props.children }
---| markup.Node.props

---@alias markup.factory.Element.Fragment.constructor.props
---| markup.factory.Element.constructor.props.children
---| { children?: markup.factory.Element.constructor.props.children }

---@alias markup.factory.Element.constructor.style
---| string
---| vim.api.keyset.highlight

---@alias markup.factory.Element.Fragment.constructor
---| fun(props?: markup.factory.Element.Fragment.constructor.props): markup.Element

---@alias markup.factory.Element.constructor
---| fun(props?: markup.factory.Element.constructor.props, style?: markup.factory.Element.constructor.style): markup.Element

---@alias markup.factory.Element.constructor.raw
---| fun(type: any, props?: markup.factory.Element.constructor.props, style?: markup.factory.Element.constructor.style): markup.Element

---@type markup.factory.Element.constructor.raw
function M.create(type, props, style)
	return Element:new(type, normalize_props(props, style))
end

---@param Component fun()
function M.create_component(Component)
	return function(...)
		return M.create(Component, ...)
	end
end

---@param Class table
function M.create_class(Class)
	return function(...)
		return M.create(Class, ...)
	end
end

function M.create_fragment(...)
	return M.create("fragment", ...)
end

return M
