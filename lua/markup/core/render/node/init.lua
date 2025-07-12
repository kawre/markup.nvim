local RenderNodeFactory = require("markup.core.factory.render-node")
local log = require("markup.logger")

---@class markup.Render.Node
---@field layout_strategy markup.Render.Layout
---@field children markup.Render.Node[]
---@field node markup.Node
---@field parent markup.Render.Node|nil
local RenderNode = {}
RenderNode.__index = RenderNode

---@param node markup.Node
---@param layout_strategy markup.Render.Layout
function RenderNode:new(node, layout_strategy)
	local instance = setmetatable({}, self)
	instance.layout_strategy = layout_strategy
	instance.children = {}
	instance.node = node
	return instance
end

function RenderNode:render()
	error("RenderNode:render() must be implemented by subclasses")
end

function RenderNode:build()
	for _, child in ipairs(self.node.child_nodes) do
		local new_render_node = self:attach(child)
		new_render_node:build()
	end
end

---@param child markup.Node
function RenderNode:attach(child)
	local render_node = RenderNodeFactory.create(child)

	table.insert(self.children, render_node)
	render_node.parent = self

	return render_node
end

function RenderNode:layout()
	self.layout_strategy.layout(self)
end

function RenderNode:add_child(node)
	if not node or type(node) ~= "table" or not node.render or not node.layout then
		error("Invalid child node")
	end
	if not self.children then
		self.children = {}
	end
	table.insert(self.children, node)
	return self
end

function RenderNode:remove_child(node)
	if not self.children then
		return self
	end
	for i, child in ipairs(self.children) do
		if child == node then
			table.remove(self.children, i)
			return self
		end
	end
	error("Child node not found")
end

function RenderNode:name()
	return self.layout_strategy.__name
end

return RenderNode
