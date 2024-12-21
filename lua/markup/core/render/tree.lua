local markup = require("markup.core")

local log = require("markup.logger") ---@diagnostic disable-line: unused-local
local NODE = require("markup.core.node.enum")

---@class markup.Render.Tree : markup.Render.Layout
local RenderTree = markup.Object("markup.render.tree")

---@class markup.Render.Tree.static
RenderTree.static = RenderTree.static

---@param root markup.Renderer.Root
function RenderTree:init(root)
	self.view = markup.Render.View(root)
end

local display_map = {
	[NODE.Display.BLOCK] = "block",
	[NODE.Display.INLINE] = "inline",
	[NODE.Display.INLINE_BLOCK] = "inline.block",
	[NODE.Display.FLEX] = "flex",
	[NODE.Display.NONE] = "none",
	["text"] = "inline.text",
}

local function renderer(display, ...)
	local path = display_map[display]
	assert(path, "Unknown display type: " .. display)

	if display == NODE.Display.NONE then
		return nil
	end

	return require("markup.core.render.layout." .. path)(...)
end

---@param node markup.Node
---@param parent markup.Render.Layout
---@return markup.Render.Layout?
function RenderTree.static.factory(node, parent)
	if node.type == NODE.Type.TEXT then
		return renderer("text", node)
	end

	return renderer(node.props.display, node)
end

return RenderTree
