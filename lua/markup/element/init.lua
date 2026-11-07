local _type = type

---@alias markup.element.typeof
---| "function"
---| "class"
---| "fragment"
---| "element"
---| "root"
---| "context"

---@class markup.element
---@field type string basically a tag name or a function/class
---@field typeof markup.element.typeof more specific type of the element
---@field props markup.node.props
---@field ref? any
---@field key? any
---@field _owner? any
local M = {}
M.__index = M
M.__type = "markup.element"

---@return markup.element.typeof
local function typeof_from_type(type)
	if _type(type) == "function" then
		return "function"
	elseif _type(type) == "table" then
		return type.typeof or "fragment"
	elseif _type(type) == "string" then
		if type == "fragment" then
			return "fragment"
		elseif type == "root" then
			return "root"
		elseif type == "context" then
			return "context"
		elseif type == "consumer" then
			return "context"
		else
			return "element"
		end
	end

	error("Invalid type: " .. tostring(type))
end

function M.new(type, props)
	local self = setmetatable({}, M)

	self.type = type
	self.typeof = typeof_from_type(type)
	self.props = props
	self.ref = nil

	if props and props.key then
		self.key = props.key
	end

	return self
end

return M
