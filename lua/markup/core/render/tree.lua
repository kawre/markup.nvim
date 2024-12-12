local markup = require("markup.core")

local log = require("markup.logger") ---@diagnostic disable-line: unused-local
local NodeType = require("markup.core.node.enum").Type

---@class markup.Render.Tree : markup.Render.Object
local RenderTree = markup.Object("markup.render.tree")

---@class markup.Render.Tree.static
RenderTree.static = RenderTree.static

---@param root markup.Renderer.Root
---@return markup.Render.View
function RenderTree.static.build(root)
	return markup.Render.View(root.current.state_node)
end

---@param node markup.Node
function RenderTree.static.factory(node)
	if node.props.display == "none" then
		return nil
	end

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
