local log = require("markup.logger") ---@diagnostic disable-line: unused-local
local Layout = require("markup.core.render.node.layout")

---@class markup.Render.Layout.Block : markup.Render.Layout
local BlockLayout = Layout.new("RenderBlock", { "block" })

---@param box markup.Render.Node
function BlockLayout.layout(box)
	local parent = box.parent
	local props = box.props

	if props.width > 0 then
		if props.width < 1 then
			box.available_width = math.ceil(parent.available_width * props.width)
		else
			box.available_width = props.width
		end
	else
		box.available_width = parent.available_width
	end

	local max_x, max_y = 0, 0
	local prev ---@type markup.Render.Node

	for _, child in box:iter_children() do
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
