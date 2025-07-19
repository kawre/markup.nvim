local RenderNodeFactory = require("markup.core.factory.render-node")
-- local BoxStyle = require("markup.core.render.style")
local assertor = require("markup.assertor")
local BoxProps = require("markup.core.render.props")
local log = require("markup.logger") ---@diagnostic disable-line: unused-local
local u = require("markup.utils") ---@diagnostic disable-line: unused-local

---@class markup.Render.Node
---@field layout_strategy markup.Render.Layout
---@field children markup.Render.Node[]
---@field node markup.Node
---@field parent markup.Render.Node
---@field dirty boolean
---@field buf table
---@field x integer
---@field y integer
---@field ox integer offset x
---@field oy integer offset y
---@field width integer
---@field height integer
---@field content_width integer
---@field content_height integer
---@field available_width integer
---@field available_height integer
---@field props markup.Render.props
---@field extmarks table
local RenderNode = {}
RenderNode.__index = RenderNode

---@param node markup.Node
---@param layout_strategy markup.Render.Layout
function RenderNode:new(node, layout_strategy)
	self = setmetatable({}, RenderNode)

	self.layout_strategy = layout_strategy
	self.children = {}
	self.node = node
	node.render_box = self
	self.dirty = true
	self.buf = {}
	self.props = BoxProps:new(self)
	self.extmarks = {}
	self.__id = u.gen_id()

	return self
end

function RenderNode:build()
	for _, child in ipairs(self.node.child_nodes) do
		local new_render_node = self:attach(child)
		new_render_node:build()
	end
	-- self.dirty = false
end

function RenderNode:reflow()
	for _, child in ipairs(self.children) do
		child:reflow()
	end
end

function RenderNode:flag_as_dirty()
	if self.dirty then
		return
	end

	self.dirty = true
	if self.parent then
		self.parent:flag_as_dirty()
	end
end

---@param child markup.Node
function RenderNode:attach(child)
	local render_node = RenderNodeFactory.create(child)

	table.insert(self.children, render_node)
	render_node.parent = self

	return render_node
end

function RenderNode:iter_children()
	local children = self.children
	local reverse = self.props.reverse
	local sign = reverse and -1 or 1
	local i = reverse and #children + 1 or 0

	return function()
		i = i + (1 * sign)

		if i < 1 or i > #children then
			return nil
		end

		return i, children[i]
	end
end

---@param style markup.Render.Style
function RenderNode:layout(_style)
	assert(self.layout_strategy, "Layout strategy is not set")

	if self.dirty == false then
		return
	end

	-- offset
	self.ox = self.parent.x
	self.oy = self.parent.y

	self.x = 0
	self.y = 0

	self.layout_strategy.layout(self)

	self.x = nil
	self.y = nil

	assertor.bug(self.width, "Width must be resolved by layout strategy.")
	assertor.bug(self.height, "Height must be resolved by layout strategy.")

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

-- function RenderNode:set_constraints(width, height)
-- 	if width then
-- 		self.width = width
-- 	end
-- 	if height then
-- 		self.height = height
-- 	end
-- end

function RenderNode:margin_box_size()
	local props = self.props
	local pbox = self:padding_box_size()

	return {
		width = pbox.width and pbox.width + (props.margin_left + props.margin_right),
		height = pbox.height and pbox.height + (props.margin_top + props.margin_bottom),
	}
end

function RenderNode:padding_box_size()
	local props = self.props
	local cbox = self:content_box_size()

	return {
		width = cbox.width and cbox.width + (props.padding_left + props.padding_right),
		height = cbox.height and cbox.height + (props.padding_top + props.padding_bottom),
	}
end

---@param width? integer
---@param height? integer
function RenderNode:set_content_box_size(width, height)
	local props = self.props
	if width then
		self.content_width = width
			- (props.padding_left + props.padding_right)
			- (props.margin_left + props.margin_right)
	end
	if height then
		if self:is("inline") then
			self.content_height = 1
		else
			self.content_height = height
				- (props.padding_top + props.padding_bottom)
				- (props.margin_top + props.margin_bottom)
		end
	end
end

function RenderNode:content_box_size()
	return {
		width = self.content_width,
		height = self.content_height,
	}
end

function RenderNode:destroy()
	local index
	for i, child in ipairs(self.parent.children) do
		if child == self then
			index = i
			break
		end
	end
	table.remove(self.parent.children, index)
end

-- function RenderNode:paint()
--
-- end

return RenderNode
