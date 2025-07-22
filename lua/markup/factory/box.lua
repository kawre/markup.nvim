---@alias markup.Render.LayoutType "flex" | "block" | "inline" | "text"

---@class markup.factory.box: markup.singleton
---@overload fun(node: markup.node): markup.box
local M = Markup.singleton()

local strategies = {
	["flex"] = require("markup.renderer.box.layout.flex"),
	["hflex"] = require("markup.renderer.box.layout.flex"),
	["vflex"] = require("markup.renderer.box.layout.flex"),
	["block"] = require("markup.renderer.box.layout.block"),
	["root"] = require("markup.renderer.box.layout.block"),
	["inline"] = require("markup.renderer.box.layout.inline"),
	["text"] = require("markup.renderer.box.layout.text"),
}

---@param node markup.node
---@return markup.box
function M.new(node)
	local RenderNode = require("markup.renderer.box")
	local layout_type = node.type == "text" and "text" or node.tag_name
	local layout_strategy = strategies[layout_type]

	if not layout_strategy then
		error("Unknown layout type: " .. tostring(layout_type))
	end

	return RenderNode(node, layout_strategy)
end

---@param renderer markup.renderer
function M.root(renderer)
	local root = M.new(renderer.rootf.state_node)

	local id = renderer.win.win
	local width = id and vim.api.nvim_win_get_width(id)
	local height = id and vim.api.nvim_win_get_height(id)

	---@diagnostic disable-next-line: missing-fields
	root.parent = { -- mock parent
		x = 0,
		y = 0,
		width = width,
		height = height,
		flag_as_dirty = function() end,
	}

	root.parent.content_box_size = function()
		return { width = root.parent.width, height = root.parent.height }
	end

	return root
end

return M
