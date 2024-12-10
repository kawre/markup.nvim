local markup = require("markup.core")

---@class markup.Node.props

---@class markup.Node : markup.Object
---@field protected props markup.Node.props
---@field type markup.Node.type
---@field child_nodes markup.Node[]
local Node = markup.Object("markup.node")

---@class markup.Node.static : markup.Object.static
Node.static = Node.static

---@param type markup.Node.type
---@param props? markup.Node.constructor.props
function Node:init(type, props)
	assert(self.class.super, "Node is an abstract class")

	self.child_nodes = {}
	self.props = props or {} ---@diagnostic disable-line: assign-type-mismatch
	self.type = type
end

function Node:clone()
	return vim.deepcopy(self)
end

function Node:has_child_nodes()
	return #self.child_nodes > 0
end

function Node:is_type(type)
	return self.type == type
end

function Node:append_child(child)
	table.insert(self.child_nodes, child)
end

function Node:remove_child(child)
	for i, node in ipairs(self.child_nodes) do
		if node == child then
			table.remove(self.child_nodes, i)
			break
		end
	end
end

function Node:replace_child(old, new)
	for i, node in ipairs(self.child_nodes) do
		if node == old then
			self.child_nodes[i] = new
			break
		end
	end
end

---@class markup.Node.constructor.props

---@alias markup.Node.constructor
---| fun(type: markup.Node.type, props?: markup.Node.constructor.props): markup.Node
---| { static: markup.Node.static }
---| markup.Node.static

---@type markup.Node.constructor
return Node
