local markup = require("markup.core")

local log = require("markup.logger") ---@diagnostic disable-line: unused-local

---@class markup.Node.props

---@class markup.Node : markup.Object
---@field props markup.Element.props
---@field type markup.Node.type
---@field child_nodes markup.Node[]
---@field parent? markup.Node
---@field frame? markup.Renderer
local Node = markup.Object("markup.node")

---@class markup.Node.static : markup.Object.static
Node.static = Node.static

---@param type markup.Node.type
---@param props? markup.Node.constructor.props
function Node:init(type, props)
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

---@param props markup.Element.props
function Node:set_props(props)
	self.props = vim.tbl_extend("force", self.props, props)
end

function Node:is_text()
	return false
end

function Node:is_element()
	return false
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

function Node:print()
	local lines = {}

	---@param node markup.Node
	local function print_node_tree(node, depth)
		if not node then
			return
		end

		local indent = ("\t"):rep(depth or 0)

		local line
		if node.type == "text" then
			line = indent .. ("󰚞 `%s`"):format(node)
		else
			line = indent .. ("󰅩 [%s]"):format(node)
		end
		table.insert(lines, line)

		for _, child in ipairs(node.child_nodes) do
			print_node_tree(child, (depth or 0) + 1)
		end
	end

	print_node_tree(self, 0)
	log.debug(table.concat(lines, "\n"))
end

---@class markup.Node.constructor.props

---@alias markup.Node.constructor
---| fun(type: markup.Node.type, props?: markup.Node.constructor.props): markup.Node
---| { static: markup.Node.static }
---| markup.Node.static

---@type markup.Node.constructor
return Node
