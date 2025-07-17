local log = require("markup.logger")

---@class markup.Render.Layout.Block : markup.Render.Layout
local BlockLayout = {}
BlockLayout.__name = "RenderBlock"
BlockLayout.__type = { block = true }

---@param box markup.Render.Node
function BlockLayout.layout(box)
	local parent = box.parent
	box.width = parent.width

	local prev
	for _, child in ipairs(box.children) do
		if child:is("block") or (prev and prev:is("block")) then
			box.cy = box.cy + 1
			box.cx = box.x
		end

		child:layout()
		box.cx = box.cx + child.width
		prev = child
	end

	box.height = box.cy - box.y
end

return BlockLayout
