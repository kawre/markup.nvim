local NODE = require("markup.core.node.enum")
local Object = require("markup.core.object")
local RenderTree = require("markup.core.render.tree")
local RenderBuilder = require("markup.core.render.builder")

local log = require("markup.logger") ---@diagnostic disable-line: unused-local

---@class markup.Render.Layout : markup.Object
---@field children markup.Render.Layout[]
---@field node markup.Node
---@field builder markup.Render.Builder
---@field need_layout boolean
local RenderLayout = Object("RenderLayout")

function RenderLayout:init(node)
	self.node = node
	self.builder = RenderBuilder()
	self.children = {}
	self.need_layout = true

	self:attach(node)
end

---@class markup.Render.Layout.static : markup.Object.static
RenderLayout.static = RenderLayout.static

---@param node markup.Node
function RenderLayout:attach(node)
	self.children = {}

	for _, child in ipairs(node.child_nodes) do
		local renderer = RenderTree.static.factory(child)
		table.insert(self.children, renderer)
	end

	self:layout()
end

function RenderLayout:layout()
	error("Method not implemented")
end

function RenderLayout:pre_layout_size()
	local max_width, max_height = 0, 0
	local max = math.max

	for _, child in ipairs(self.children) do
		max_height = max(max_height, child:box_size().height)
		max_width = max(max_width, child:box_size().width)
	end

	return {
		width = max_width,
		height = max_height,
	}
end

-- the total size of the node
function RenderLayout:box_size()
	return {
		width = self.builder:width(),
		height = self.builder:height(),
	}
end

-- the size of the visible area (excluding margin)
function RenderLayout:offset_size()
	local box = self:box_size()

	return {
		width = box.width - self.node.props.margin.left - self.node.props.margin.right,
		height = box.height - self.node.props.margin.top - self.node.props.margin.bottom,
	}
end

-- the size of the content (excluding padding, border, and margin)
function RenderLayout:content_size()
	local offset = self:offset_size()

	return {
		width = offset.width - self.node.props.padding.left - self.node.props.padding.right,
		height = offset.height - self.node.props.padding.top - self.node.props.padding.bottom,
	}
end

function RenderLayout:computed_lines()
	return self.builder.lines, self.builder.len
end

function RenderLayout:is_block_flow()
	return false
end

function RenderLayout:is_block()
	local display = self.node.props.display
	return display == NODE.Display.BLOCK or display == NODE.Display.FLEX
end

function RenderLayout:is_inline_flow()
	return false
end

function RenderLayout:is_inline()
	local display = self.node.props.display
	return display == NODE.Display.INLINE
end

---@param renderer markup.Renderer
function RenderLayout:paint(renderer)
	local lines = self:computed_lines()

	local lines_str = vim.tbl_map(tostring, vim.tbl_values(lines))
	renderer.buf:set_lines(0, -1, false, lines_str)

	-- Paint each line
	for row, line in pairs(lines) do
		line:paint(renderer, row)
	end
end

function RenderLayout:print()
	local lines = {}

	---@param object markup.Render.Layout
	local function print_tree(object, depth)
		if not object then
			return
		end

		local indent = ("\t"):rep(depth or 0)

		local line = (indent .. ("Object: %s"):format(object.class.name))
		table.insert(lines, line)

		for _, child in ipairs(object.children) do
			print_tree(child, (depth or 0) + 1)
		end
	end

	print_tree(self, 0)
	log.info(table.concat(lines, "\n"))
end

---@alias markup.Render.Layout.constructor
---| fun(node: markup.Node): markup.Render.Layout
---| { static: markup.Render.Layout.static }
---| markup.Render.Layout.static

---@type markup.Render.Layout.constructor
return RenderLayout
