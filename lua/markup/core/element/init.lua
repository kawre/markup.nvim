local _type = type

---@alias markup.Element.typeof
---| "function"
---| "class"
---| "fragment"
---| "element"
---| "root"

---@class markup.Element
---@field type string basically a tag name or a function/class
---@field typeof markup.Element.typeof more specific type of the element
---@field props markup.Node.props
---@field ref? any
---@field key? any
---@field _owner? any
local Element = {}
Element.__index = Element

---@return markup.Element.typeof
local function typeof_from_type(type)
	if _type(type) == "function" then
		return "function"
	elseif _type(type) == "string" then
		if type == "fragment" then
			return "fragment"
		elseif type == "root" then
			return "root"
		else
			return "element"
		end
	elseif _type(type) == "table" and getmetatable(type) then
		return "class"
	end

	error("Invalid type: " .. tostring(type))
end

function Element:new(type, props)
	self = setmetatable({}, Element)

	self.type = type
	self.typeof = typeof_from_type(type)
	self.props = props
	self.ref = nil

	if props.key then
		self.key = props.key
		props.key = nil
	end

	return self
end

return Element
