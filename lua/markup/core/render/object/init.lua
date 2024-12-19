local markup = require("markup.core")

local log = require("markup.logger") ---@diagnostic disable-line: unused-local

---@class markup.Render.Object : markup.Object
---@field children markup.Render.Object[]
---@field node markup.Node
---@field builder markup.Renderer.Builder
---@field need_layout boolean
local RenderObject = markup.Object("RenderObject")

function RenderObject:init(node)
	self.node = node
	self.builder = markup.RendererBuilder()
	self.children = {}
	self.need_layout = true

	self:attach(node)
end

---@class markup.Render.Object.static : markup.Object.static
RenderObject.static = RenderObject.static

---@param node markup.Node
function RenderObject:attach(node)
	self.children = {}

	for _, child in ipairs(node.child_nodes) do
		local renderer = markup.Render.Tree.static.factory(child)
		table.insert(self.children, renderer)
	end

	self:layout()
end

function RenderObject:layout()
	error("Method not implemented")
end

---@param renderer markup.Renderer
function RenderObject:paint(renderer)
	local lines = self:computed_lines()

	local lines_str = vim.tbl_map(function(line)
		return line:content()
	end, vim.tbl_values(lines))
	renderer:buf_set_lines(0, -1, false, lines_str)

	-- Paint each line
	for row, line in pairs(lines) do
		line:paint(renderer, row)
	end
end

function RenderObject:computed_lines()
	return self.builder.lines
end

function RenderObject:print()
	local lines = {}

	---@param object markup.Render.Object
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

---@alias markup.Render.Object.constructor
---| fun(node: markup.Node): markup.Render.Object
---| { static: markup.Render.Object.static }
---| markup.Render.Object.static

---@type markup.Render.Object.constructor
return RenderObject
