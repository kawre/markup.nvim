---@alias markup.Render.LayoutType "flex" | "block" | "inline" | "text"

---@class markup.factory.box
local M = setmetatable({}, {
	__call = function(t, ...)
		return t.new(...)
	end,
})

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
---@return markup.Render.Box
function M.new(node)
	local RenderNode = require("markup.renderer.box")
	-- local layout_type = type(node.props) == "table" and node.props.layout or "text"
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

	-- local width = vim.api.nvim_win_get_width(renderer.win.win)
	-- local height = vim.api.nvim_win_get_height(renderer.win.win)

	---@diagnostic disable-next-line: missing-fields
	root.parent = { -- mock parent
		x = 0,
		y = 0,
		flag_as_dirty = function() end,
	}

	root.parent.content_box_size = function()
		return { width = root.parent.width, height = root.parent.height }
	end

	return root
end

return M
