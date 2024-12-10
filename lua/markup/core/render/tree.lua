local markup = require("markup.core")

---@class markup.Render.Tree : markup.Render.Object
local RenderTree = markup.Object("markup.render.tree")

---@class markup.Render.Tree.static
RenderTree.static = RenderTree.static

---@param node markup.Node
---@return markup.Render.Object
function RenderTree.static.attach(node)
	local renderer = markup.Render.Object()

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
	view.children = object.children

	return view
end

return RenderTree
