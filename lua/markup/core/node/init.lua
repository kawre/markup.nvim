local log = require("markup.logger") ---@diagnostic disable-line: unused-local

---@class markup.Node
---@field tag_name string
local Node = {}
Node.__index = Node

---@alias markup.Node.type "element" | "text"

---@param type markup.Node.type
---@param name? string
---@param props? markup.Node.constructor.props
function Node:new(_type, name, props)
	local instance = setmetatable({}, self)
	instance.child_nodes = {}
	if props and type(props) == "table" and type(props.children) == "string" then
		instance.child_nodes = { Node:new("text", nil, props.children) }
	end
	instance.parent = nil
	instance.type = _type
	instance.tag_name = name
	instance.props = props
	return instance
end

function Node:clone()
	return vim.deepcopy(self)
end

function Node:has_child_nodes()
	return #self.child_nodes > 0
end

function Node:append_child(child)
	child.parent = self
	table.insert(self.child_nodes, child)
end

function Node:prepend_child(child)
	child.parent = self
	table.insert(self.child_nodes, 1, child)
end

function Node:remove_child(child)
	for i, node in ipairs(self.child_nodes) do
		if node == child then
			child.parent = nil
			table.remove(self.child_nodes, i)
			break
		end
	end
end

function Node:replace_child(old, new)
	for i, node in ipairs(self.child_nodes) do
		if node == old then
			old.parent = nil
			new.parent = self
			self.child_nodes[i] = new
			break
		end
	end
end

---@param _type markup.Node.type
function Node:is(_type)
	return self.type == _type
end

return Node
