local markup = require("markup.core")

local log = require("markup.logger") ---@diagnostic disable-line: unused-local

local function normalize_type(_type)
	if not _type or type(_type) == "string" then
		_type = markup[_type or "inline"]
	end

	return _type
end

---@param style markup.Element.style.props
local function normalize_style(props_style, style)
	if not style then
		return props_style
	end

	if type(style) == "string" then
		return { link = style }
	elseif props_style then
		return vim.tbl_extend("force", props_style, style)
	else
		return style
	end
end

---@param props? markup.create_element.props
---@param style? markup.Element.style.props
local function normalize_props(props, style)
	if not props then
		return nil
	end

	if type(props) ~= "table" then
		return { children = props, style = normalize_style(nil, style) }
	end
	props.style = normalize_style(props.style, style)

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

---@class markup.xElement
---@field type string
---@field props? markup.xElement.props
---@field ref? any
---@field key? any
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

---@type markup.create_element
local function create_element(type, props, style)
	type = normalize_type(type)
	props = normalize_props(props, style)

	return {
		type = type,
		props = props,
		ref = nil,
		key = nil,
	}
end

return create_element
