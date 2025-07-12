local RenderNodeFactory = require("markup.core.factory.render-node")
local BoxStyle = require("markup.core.render.style")
local log = require("markup.logger")

---@class markup.Render.Layout
---@field layout fun(box: markup.Render.Node)
---@field __name string
---@field __type table<markup.Render.LayoutType, boolean>

---@class markup.Render.Node
---@field layout_strategy markup.Render.Layout
---@field children markup.Render.Node[]
---@field node markup.Node
---@field parent markup.Render.Node
---@field dirty boolean
---@field buf table
---@field x integer
---@field y integer
---@field cx? integer
---@field cy? integer
---@field width integer
---@field height integer
---@field style any
local RenderNode = {}
RenderNode.__index = RenderNode

---@param node markup.Node
---@param layout_strategy markup.Render.Layout
function RenderNode:new(node, layout_strategy)
	local instance = setmetatable({}, self)
	instance.layout_strategy = layout_strategy
	instance.children = {}
	instance.node = node
	instance.dirty = true
	instance.buf = {}
	instance.style = BoxStyle:new(instance)
	return instance
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

---@param parent? markup.Render.Node
function RenderNode:layout()
	assert(self.layout_strategy, "Layout strategy is not set")

	if self.dirty == false then
		return
	end

	self.x = self.parent.cx
	self.y = self.parent.cy

	self.cx = self.x
	self.cy = self.y
	self.layout_strategy.layout(self)
	self.cx = nil
	self.cy = nil

	self.dirty = false
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

---@param layout_type markup.Render.LayoutType
function RenderNode:is(layout_type)
	return self.layout_strategy.__type[layout_type]
end

return RenderNode
