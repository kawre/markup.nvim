---@alias markup.Render.LayoutType "flex" | "block" | "inline" | "none"

local M = {}

---@param node markup.Node
---@return markup.Render.Node
function M.create(node)
	local RenderNode = require("markup.core.render.node")
	local layout_type = type(node.props) == "table" and node.props.layout or "block"
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

return M
