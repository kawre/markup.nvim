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

-- ---@param node markup.Node
-- function RenderLayout:attach(node)
-- 	self.children = {}
--
-- 	for _, child in ipairs(node.child_nodes) do
-- 		local layout = RenderTree.static.factory(child)
--
-- 		if layout then
-- 			table.insert(self.children, layout)
-- 			layout:attach(child)
-- 			layout.parent = self
-- 		end
-- 	end
--
-- 	-- self:layout()
-- end

function RenderLayout:children_iter()
	local i = 0
	local n = #self.node.child_nodes

	return function()
		i = i + 1
		if i <= n then
			local layout = RenderTree.static.factory(self.node.child_nodes[i])
			while i <= n and not layout do
				i = i + 1
				layout = RenderTree.static.factory(self.node.child_nodes[i])
			end
			return layout
		end
	end
end

---@alias markup.Render.Layout.constrains
---| { width: number, height: number }

---@param constrains markup.Render.Layout.constrains
function RenderLayout:aggregate(constrains)
	error("Method not implemented")
end

---@param constrains markup.Render.Layout.constrains
function RenderLayout:layout(constrains)
	for _, child in ipairs(self.node.child_nodes) do
		local renderer = RenderTree.static.factory(child)
		if renderer then
			table.insert(self.children, renderer)
			renderer:layout(constrains)
			renderer.parent = self
		end
	end

	self:aggregate(constrains)
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

function RenderLayout:available_height()
	-- return self.builder:available_size()
end

function RenderLayout:available_width()
	-- return self.builder:available_size()
	-- local parent = self.node.parent
end

function RenderLayout:available_size()
	return {
		width = self:available_width(),
		height = self:available_height(),
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

---@alias markup.Render.Layout.constructor
---| fun(node: markup.Node): markup.Render.Layout
---| { static: markup.Render.Layout.static }
---| markup.Render.Layout.static

---@type markup.Render.Layout.constructor
return RenderLayout
