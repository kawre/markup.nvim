---@class markup.Render.Node
---@field layout_strategy markup.Render.Layout
---@field children markup.Render.Node[]
---@field node markup.Node
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

function RenderNode:layout()
	self.layout_strategy:layout(self)
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

return RenderNode
