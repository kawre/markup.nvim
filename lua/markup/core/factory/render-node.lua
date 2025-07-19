---@alias markup.Render.LayoutType "flex" | "block" | "inline" | "text"

local M = {}

local strategies = {
	["flex"] = require("markup.core.render.node.layout.flex"),
	["block"] = require("markup.core.render.node.layout.block"),
	["root"] = require("markup.core.render.node.layout.block"),
	["inline"] = require("markup.core.render.node.layout.inline"),
	["text"] = require("markup.core.render.node.layout.text"),
}

---@param node markup.Node
---@return markup.Render.Node
function M.create(node)
	local RenderNode = require("markup.core.render.node")
	-- local layout_type = type(node.props) == "table" and node.props.layout or "text"
	local layout_type = node.type == "text" and "text" or node.tag_name
	local layout_strategy = strategies[layout_type]

	if not layout_strategy then
		error("Unknown layout type: " .. tostring(layout_type))
	end

	return RenderNode:new(node, layout_strategy)
end

---@param renderer markup.Renderer
function M.create_root(renderer)
	local root = M.create(renderer.root.current.state_node)
	root.x = 0
	root.y = 0
	root.available_width = vim.api.nvim_win_get_width(renderer.id)
	root.available_height = vim.api.nvim_win_get_height(renderer.id)
	return root
end

return M
