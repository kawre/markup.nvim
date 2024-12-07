local log = require("markup.logger") ---@diagnostic disable-line: unused-local
local markup = require("markup.core")

---@class markup.Element.Table
---@field type string
---@field props table
---@field ref any
---@field key any
---@field owner any

local function normalize_type(_type)
	local Node = require("markup.core.enum").Node
	if type(_type) == "string" and Node[_type] then
		return require(Node[_type])
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

---@alias markup.create_element.props { children?: (number|string|table)[] }
---@alias markup.create_element
---| fun(type: markup.Fiber.type, props?: markup.create_element.props, style?: table): markup.Element.Table

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
