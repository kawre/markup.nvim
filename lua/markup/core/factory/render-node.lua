local RenderNode = require("markup.core.render.node")

---@alias markup.Render.LayoutType "flex" | "block" | "inline" | "none"

---@param node markup.Node
---@param layout_type markup.Render.LayoutType
---@return markup.Render.Node
local function create_render_node(node, layout_type)
	local layout_strategy

	if layout_type == "flex" then
		layout_strategy = require("markup.core.render.node.layout.flex")
	elseif layout_type == "block" then
		layout_strategy = require("markup.core.render.node.layout.block")
	elseif layout_type == "inline" then
		layout_strategy = require("markup.core.render.node.layout.inline")
	else
		error("Unknown layout type: " .. tostring(layout_type))
	end

	return RenderNode:new(node, layout_strategy)
end

return create_render_node
