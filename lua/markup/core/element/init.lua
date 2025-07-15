---@class markup.Element
---@field type string
---@field props markup.Node.props
---@field ref? any
---@field key? any
---@field _owner? any
local Element = {}
Element.__index = Element

function Element:new(type, props)
	local instance = setmetatable({
		type = type,
		props = props,
		ref = nil,
		key = nil,
	}, self)

	return instance
end

return Element
