local log = require("markup.logger") ---@diagnostic disable-line: unused-local
local Layout = require("markup.core.render.box.layout")

---@class markup.Render.Layout.Block : markup.Render.Layout
local BlockLayout = Layout.new("RenderBlock", { "block" })

---@param box markup.Render.Box
function BlockLayout.layout(box)
	local parent = box.parent
	local props = box.props
	local parent_cbox = box.parent:content_box_size()

	BlockLayout.compute_initial_width(box, parent_cbox)

	local max_x, max_y = 0, 0
	local prev ---@type markup.Render.Box

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

	BlockLayout.compute_final_size(box, parent_cbox)
end

---@param box markup.Render.Box
---@param parent_cbox markup.Element.size
function BlockLayout.compute_initial_width(box, parent_cbox)
	local width = box.props.width
	local new_width = box:normalize_size(width, parent_cbox.width)
	box:set_content_box_size(new_width)
end

---@param box markup.Render.Box
---@param parent_cbox markup.Element.size
function BlockLayout.compute_final_size(box, parent_cbox)
	local height = box.props.height
	box:set_content_box_size(math.max(box.width, box.content_width), math.max(box.height, height))
end

return BlockLayout
