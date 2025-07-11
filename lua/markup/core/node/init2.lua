---@class markup.Node
local Node = {}
Node.__index = Node

---@param type markup.Node.type
---@param props? markup.Node.constructor.props
function Node:new(type, props)
	local instance = setmetatable({}, self)
	instance.child_nodes = {}
	instance.parent = nil

	instance.type = "node" -- Default type, can be overridden
	return instance
end

return Node
