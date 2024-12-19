local markup = require("markup.core")

local log = require("markup.logger") ---@diagnostic disable-line: unused-local
local NodeType = require("markup.core.node.enum").Type

---@class markup.Render.Tree : markup.Render.Object
local RenderTree = markup.Object("markup.render.tree")

---@class markup.Render.Tree.static
RenderTree.static = RenderTree.static

---@param root markup.Renderer.Root
function RenderTree:init(root)
	self.view = markup.Render.View(root.current.state_node)
end

---@param node markup.Node
function RenderTree.static.factory(node)
	if node.props.display == "none" then
		return nil
	end

	if node.type == NodeType.TEXT then
		return markup.Render.Text(node)
	else -- Element Node
		---@cast node markup.Element
		return RenderTree.static.element_factory(node)
	end
end

---@param element markup.Element
function RenderTree.static.element_factory(element)
	if element.class == markup.Inline then
		return markup.Render.Inline(element)
	elseif element.class == markup.Block then
		return markup.Render.Block(element)
	elseif element.class == markup.Flex then
		return markup.Render.Flex(element)
	else
		return markup.Render.Inline(element)
	end
end

return RenderTree
