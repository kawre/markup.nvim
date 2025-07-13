local log = require("markup.logger") ---@diagnostic disable-line: unused-local

local M = {}
local Element = {}

local function normalize_props(props, style)
	if not props then
		return {}
	elseif type(props) ~= "table" or getmetatable(props) then
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
	elseif type(props.children) == "table" and not getmetatable(props.children) then
		props.children = vim.tbl_filter(function(child)
			return not (child == nil or child == false)
		end, props.children)
	end

	if type(props.children) == "table" and #props.children == 1 then
		props.children = props.children[1]
	end

	return props
end

---@class markup.Element
---@field type string
---@field props markup.Element.props
---@field ref? any
---@field key? any
---@field _owner? any

---@class markup.Element.props.normalized
---@field children? markup.Element.constructor.props
---@field style markup.Element.style
---@field display markup.Element.display
---@field padding markup.Element.padding
---@field margin markup.Element.margin
---@field align markup.Box.align
---@field spacing markup.Box.spacing
---@field vertical boolean
---@field horizontal boolean
---@field reverse boolean
---@field on_submit? fun()
---@field on_key? table<string, fun()>

---@class markup.Element.props
---@field children? markup.Element.constructor.props
---@field style? markup.Element.constructor.props.style
---@field display? markup.Element.display
---@field padding? markup.Element.padding
---@field margin? markup.Element.margin
---@field align? markup.Box.align
---@field spacing? markup.Box.spacing
---@field vertical? boolean
---@field horizontal? boolean
---@field reverse? boolean
---@field on_submit? fun()
---@field on_key? table<string, fun()>

---@alias markup.factory.Element.constructor.props.children
---| string
---| number
---| table

---@alias markup.factory.Element.constructor.props
---| markup.factory.Element.constructor.props.children
---| { children?: markup.factory.Element.constructor.props.children }
---| markup.Element.props

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
	return setmetatable({
		type = type,
		props = normalize_props(props, style),
		ref = nil,
		key = nil,
	}, Element)
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
