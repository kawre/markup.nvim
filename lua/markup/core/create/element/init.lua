local log = require("markup.logger") ---@diagnostic disable-line: unused-local
local markup = require("markup.core")

local function normalize_type(_type)
	if not type or type(_type) == "string" then
		_type = markup[_type or "inline"]
	end

	return _type
end

local function normalize_props(props, style)
	if not props then
		return {}
	end

	if type(props) == "string" or type(props) == "number" then
		return { children = props }
	end

	if not props.children then
		local res = { children = {} }

		for key, value in pairs(props) do
			if type(key) == "number" then
				table.insert(res.children, value)
			else
				res[key] = value
			end
		end

		if res.children then
			if #res.children == 0 then
				res.children = nil
			elseif #res.children == 1 then
				res.children = res.children[1]
			end
		end

		return res
	else
		return props
	end
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

---@alias markup.create_element
---| fun(type: markup.Fiber.type, props?: markup.create_element.props, style?: table): markup.xElement

---@alias markup.create_element_from_text
---| fun(props?: markup.create_element.props, style?: markup.Element.style.props): markup.xElement

---@alias markup.create_element_from_element
---| fun(props?: markup.create_element.props, style?: markup.Element.style.props): markup.xElement

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
