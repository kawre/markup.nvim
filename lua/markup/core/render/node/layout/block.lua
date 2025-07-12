local LayoutStrategy = require("markup.core.render.node.layout")
local log = require("markup.logger")

---@class markup.Render.Layout.Block : markup.Render.Layout
local BlockLayout = {}
BlockLayout.__name = "RenderBlock"

---@param node markup.Render.Node
function BlockLayout.layout(node)
	local props = node.props

	-- local contentX = node.x or 0
	-- local contentY = node.y or 0
	--
	-- local padding_top = props.padding.top or 0
	-- local padding_bottom = props.padding.bottom or 0
	-- local padding_left = props.padding.left or 0
	-- local padding_right = props.padding.right or 0
	--
	-- local contentWidth = (node.width or 100) - padding_left - padding_right
	--
	-- local cursorY = contentY + padding_top
	--
	-- for _, child in ipairs(node.children) do
	-- 	local margin_top = child.margin_top or 0
	-- 	local margin_bottom = child.margin_bottom or 0
	--
	-- 	-- Horizontal position
	-- 	child.x = contentX + padding_left + (child.margin_left or 0)
	--
	-- 	-- Vertical position
	-- 	cursorY = cursorY + margin_top
	-- 	child.y = cursorY
	--
	-- 	-- Width: fill content width by default
	-- 	child.width = child.width
	-- 		or (contentWidth - (child.margin_left or 0) - (child.margin_right or 0))
	--
	-- 	-- Height: should come from content or be fixed
	-- 	child.height = child.height or 20
	--
	-- 	cursorY = cursorY + child.height + margin_bottom
	--
	-- 	-- Recurse if child has children
	-- 	if child.layout_strategy then
	-- 		child:layout()
	-- 	end
	-- end
	--
	-- node.height = cursorY + padding_bottom - contentY
end

return BlockLayout
