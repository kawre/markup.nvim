local log = require("markup.logger")

---@class markup.Render.Layout.Block : markup.Render.Layout
local BlockLayout = {}
BlockLayout.__name = "RenderBlock"
BlockLayout.__type = { block = true }

---@param box markup.Render.Node
function BlockLayout.layout(box)
	local parent = box.parent
	box.width = parent.width
	local style = box.node.props

	local prev
	for _, child in ipairs(box.children) do
		if prev and (child:is("block") or prev:is("block")) then
			box.y = box.y + prev.height + (style.spacing or 0)
			box.x = box.cx
		end

		child:layout()
		box.x = box.x + child.width
		prev = child
	end

	if prev then
		box.y = box.y + prev.height
	end

	box.height = box.y - box.my + (style.margin_bottom or 0) + (style.padding_bottom or 0)
end

return BlockLayout
