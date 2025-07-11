---@class markup.Render.Layout
local LayoutStrategy = {}
LayoutStrategy.__index = LayoutStrategy

---@param node markup.Render.Node
function LayoutStrategy:layout(node) ---@diagnostic disable-line: unused-local
	error("LayoutStrategy:layout() must be implemented by subclasses")
end

return LayoutStrategy
