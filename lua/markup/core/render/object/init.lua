local markup = require("markup.core")

local log = require("markup.logger") ---@diagnostic disable-line: unused-local

---@class markup.Render.Object : markup.Object
---@field children markup.Render.Object[]
---@field node markup.Node
---@field builder markup.Renderer.Builder
local RenderObject = markup.Object("markup.render.object")

function RenderObject:init(node)
	self.node = node
	self.builder = markup.RendererBuilder()
	self.children = {}
end

---@class markup.Render.Object.static : markup.Object.static
RenderObject.static = RenderObject.static

function RenderObject:first_child() end

function RenderObject:last_child() end

function RenderObject:prev_sibling() end

function RenderObject:next_sibling() end

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

		local line = (indent .. ("Object: %s (%s)"):format(object.node, object.node.type))
		table.insert(lines, line)

		for _, child in ipairs(object.children) do
			print_tree(child, (depth or 0) + 1)
		end
	end

	print_tree(self, 0)
	log.info(table.concat(lines, "\n"))
end

return RenderObject
