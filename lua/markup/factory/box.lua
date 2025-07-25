---@alias markup.Render.LayoutType "flex" | "block" | "inline" | "text"

---@class markup.factory.box: markup.singleton
---@overload fun(node: markup.node): markup.box
local M = Markup.singleton()

local impls = {
	["flex"] = require("markup.renderer.box.impl.flex"),
	["hflex"] = require("markup.renderer.box.impl.flex"),
	["vflex"] = require("markup.renderer.box.impl.flex"),
	["block"] = require("markup.renderer.box.impl.block"),
	["button"] = require("markup.renderer.box.impl.block"),
	["root"] = require("markup.renderer.box.impl.block"),
	["inline"] = require("markup.renderer.box.impl.inline"),
	["text"] = require("markup.renderer.box.impl.text"),
}

---@param node markup.node
---@return markup.box
function M.call(node)
	local RenderNode = require("markup.renderer.box")
	local layout_type = node.type == "text" and "text" or node.tag_name
	local layout_strategy = impls[layout_type]

	if not layout_strategy then
		error("Unknown layout type: " .. tostring(layout_type))
	end

	return RenderNode(node, layout_strategy)
end

---@param renderer markup.renderer
function M.root(renderer)
	local root = M.call(renderer.rootf.state_node)
	return root
end

return M
