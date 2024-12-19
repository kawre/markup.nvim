local markup = require("markup.core")

local log = require("markup.logger") ---@diagnostic disable-line: unused-local
local NODE = require("markup.core.node.enum")

---@class markup.Render.Tree : markup.Render.Layout
local RenderTree = markup.Object("markup.render.tree")

---@class markup.Render.Tree.static
RenderTree.static = RenderTree.static

---@param root markup.Renderer.Root
function RenderTree:init(root)
	self.view = markup.Render.View(root.current.state_node)
end

local function renderer(display, node)
	return require("markup.core.render.layout." .. display)(node)
end

---@param node markup.Node
function RenderTree.static.factory(node)
	if node.type == NODE.Type.TEXT then
		return renderer("text", node)
	end

	local display = node.props.display or "inline"
	if display == NODE.Display.NONE then
		return nil
	else
		return renderer(display, node)
	end
end

return RenderTree
