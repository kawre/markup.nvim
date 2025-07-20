local log = require("markup.logger") ---@diagnostic disable-line: unused-local
local Layout = require("markup.core.render.box.layout")

---@class markup.Render.Layout.Block : markup.Render.Layout
local BlockLayout = Layout.new("RenderBlock", { "block" })

---@param box markup.Render.Box
function BlockLayout.layout(box)
	local props = box.props

	BlockLayout.compute_initial_width(box)

	local max_x, max_y = 0, 0
	local prev_mheight, prev_is_block = 0, false

	for i, child in box:iter_children() do
		if i ~= 1 and (prev_is_block or child:is("block")) then
			box.y = box.y + prev_mheight + props.spacing
			box.x = 0
		end

		child:layout()
		local child_mbox = child:margin_box_size()
		box.x = box.x + child_mbox.width

		max_x = math.max(box.x, max_x)
		max_y = math.max(box.y, max_y)

		prev_is_block = child:is("block")
		prev_mheight = child_mbox.height
	end

	box.height = math.max(box.y + prev_mheight, max_y)
	box.width = max_x

	BlockLayout.compute_final_size(box)
end

---@param box markup.Render.Box
function BlockLayout.compute_initial_width(box)
	if box.parent then
		local width = box.props.width
		local parent_cbox = box.parent:content_box_size()
		width = box:inherit_size(width, parent_cbox.width)
		box:set_content_box_size(width)
	end
end

---@param box markup.Render.Box
function BlockLayout.compute_final_size(box)
	local height = box.props.height
	box:set_content_box_size(
		math.max(box.width, box.content_width or 0),
		math.max(box.height, height)
	)
end

return BlockLayout
