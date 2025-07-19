local log = require("markup.logger")

---@class markup.Render.Layout.Block : markup.Render.Layout
local BlockLayout = {}
BlockLayout.__name = "RenderBlock"
BlockLayout.__type = { block = true }

---@param box markup.Render.Node
function BlockLayout.layout(box)
	local parent = box.parent
	local props = box.props

	box.available_width = parent.available_width

	local max_x, max_y = 0, 0
	local prev ---@type markup.Render.Node

	for _, child in ipairs(box.children) do
		if prev and (child:is("block") or prev:is("block")) then
			box.y = box.y + prev.height + props.spacing
			box.x = 0
		end

		child:layout()
		box.x = box.x + child.width

		max_x = math.max(box.x, max_x)
		max_y = math.max(box.y, max_y)
		prev = child
	end

	box.height = math.max(box.y + prev.height, max_y)
	box.width = max_x
end

return BlockLayout
