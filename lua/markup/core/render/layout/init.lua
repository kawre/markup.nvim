local NODE = require("markup.core.node.enum")
local Object = require("markup.core.object")
local RenderTree = require("markup.core.render.tree")
local RenderBuilder = require("markup.core.render.builder")

local log = require("markup.logger") ---@diagnostic disable-line: unused-local

---@class markup.Render.Layout : markup.Object
---@field children markup.Render.Layout[]
---@field node markup.Node
---@field builder markup.Render.Builder
---@field parent markup.Render.Layout
---@field need_layout boolean
local RenderLayout = Object("RenderLayout")

---@param node markup.Node
function RenderLayout:init(node)
	self.node = node
	self.builder = RenderBuilder()
	self.children = {}
	self.need_layout = true
end

---@class markup.Render.Layout.static : markup.Object.static
RenderLayout.static = RenderLayout.static

---@alias markup.Render.Layout.constrains
---| { width: number, height: number }

---@param constrains markup.Render.Layout.constrains
function RenderLayout:calc_constrains(constrains)
	local parent = self.parent

	if not parent then
		return constrains
	end

	local style = self.node.props
	local size = style.size

	local width = constrains.width
	local height = constrains.height

	if size then
		if size.width then
			width = size.width < 1 and math.ceil(width * size.width) or size.width
		end
		if size.height then
			height = size.height < 1 and math.ceil(height * size.height) or size.height
		end
	end

	return {
		width = width,
		height = height,
	}
end

---@param constrains markup.Render.Layout.constrains
function RenderLayout:aggregate(constrains) ---@diagnostic disable-line: unused-local
	error("Method not implemented")
end

---@param child markup.Node
function RenderLayout:attach(child)
	local renderer = RenderTree.static.factory(child, self)

	table.insert(self.children, renderer)
	renderer.parent = self

	return renderer
end

---@param constrains markup.Render.Layout.constrains
function RenderLayout:layout(constrains)
	local new_constrains = self:calc_constrains(constrains)

	for _, child in ipairs(self.node.child_nodes) do
		local renderer = self:attach(child)
		if renderer then
			renderer:layout(new_constrains)
		end
	end

	if not vim.tbl_isempty(self.children) then
		self:aggregate(new_constrains)
	end
end

function RenderLayout:reflow()
	error("Method not implemented")
end

-- total size of the layout children
function RenderLayout:content_size()
	local max_width, max_height = 0, 0
	local max = math.max

	-- TODO optimize this with memoization
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

function RenderLayout:computed_lines()
	return self.builder.lines, self.builder.len
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
	log.debug(table.concat(lines, "\n"))
end

function RenderLayout:is_block_flow()
	return false
end

function RenderLayout:is_block()
	return false
end

function RenderLayout:is_inline_flow()
	return false
end

function RenderLayout:is_inline()
	return false
end

function RenderLayout:is_flex()
	return false
end

function RenderLayout:is_grid()
	return false
end

---@alias markup.Render.Layout.constructor
---| fun(node: markup.Node): markup.Render.Layout
---| { static: markup.Render.Layout.static }
---| markup.Render.Layout.static

---@type markup.Render.Layout.constructor
return RenderLayout
