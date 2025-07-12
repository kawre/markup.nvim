local log = require("markup.logger")

---@class markup.Render.Layout.Block : markup.Render.Layout
local BlockLayout = {}
BlockLayout.__name = "RenderBlock"
BlockLayout.__type = { block = true }

---@param box markup.Render.Node
function BlockLayout.layout(box)
	local parent = box.parent
	box.width = parent.width

	for _, child in ipairs(box.children) do
		child:layout()
		box.cy = box.cy + child.height
	end

	box.height = box.cy - box.y
end

return BlockLayout
