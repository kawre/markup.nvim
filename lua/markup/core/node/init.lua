local markup = require("markup.core")

---@class markup.Node
---@field type markup.Node.type
---@field child_nodes markup.Node[]
local Node = markup.Object("markup.node")

---@param type markup.Node.type
function Node:init(type)
	assert(self.class.super, "Node is an abstract class")

	self.type = type
	self.child_nodes = {}
end

function Node:clone()
	return vim.deepcopy(self)
end

function Node:has_child_nodes()
	return #self.child_nodes > 0
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

return Node
