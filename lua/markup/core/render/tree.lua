local markup = require("markup.core")

local log = require("markup.logger") ---@diagnostic disable-line: unused-local
local NodeType = require("markup.core.node.enum").Type

---@class markup.Render.Tree : markup.Render.Object
local RenderTree = markup.Object("markup.render.tree")

---@class markup.Render.Tree.static
RenderTree.static = RenderTree.static

---@param node markup.Node
---@return markup.Render.Object
function RenderTree.static.attach(node)
	local renderer = RenderTree.static.factory(node)

	for _, child in ipairs(node.child_nodes) do
		local renderer_child = RenderTree.static.attach(child)
		if renderer_child then
			table.insert(renderer.children, renderer_child)
		end
	end

	return renderer
end

---@param root markup.Renderer.Root
---@return markup.Render.View
function RenderTree.static.build(root)
	local view = markup.Render.View()

	local object = RenderTree.static.attach(root.current.state_node)
	table.insert(view.children, object)
	view.node = root.current.state_node

	return view
end

---@param node markup.Node
function RenderTree.static.factory(node)
	local object = markup.Switch(node.type, {
		[NodeType.TEXT] = function()
			---@cast node markup.Text

			return markup.Render.Text(node)
		end,

		[NodeType.ELEMENT] = function()
			---@cast node markup.Element

			assert(node.class, "Element node must have a class")
			local element = markup.Switch(node.class, {
				[markup.Inline] = markup.Render.Inline,
				[markup.Block] = markup.Render.Block,
				[markup.Flex] = markup.Render.Flex,
				-- [markup.List] = markup.Render.List,

				-- Default to inline
				["default"] = markup.Render.Inline,
			})

			return element(node)
		end,
	})

	return object()
end

return RenderTree
