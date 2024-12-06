local log = require("markup.logger") ---@diagnostic disable-line: unused-local
local markup = require("markup.core")

---@class markup.Element2
---@field type string
---@field props table
---@field ref any
---@field key any
---@field owner any

local function normalize_type(_type)
	if type(_type) == "string" then
		return markup[_type:lower()]
	end

	return _type
end

local function normalize_props(props)
	if not props then
		return {}
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

---@param type string
---@param props { children?: (number|string|table)[] }
---
---@return markup.Element2
return function(type, props)
	type = normalize_type(type)
	props = normalize_props(props)

	return {
		type = type,
		props = props,
		ref = nil,
		key = nil,
	}
end
