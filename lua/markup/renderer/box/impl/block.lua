local Impl = require("markup.renderer.box.impl")

---@class markup.box.block : markup.box.impl
local M = Impl("RenderBlock", { "block" })

---@param box markup.box
---@param input markup.box.layout.Input
function M.layout(box, input)
	local output = M.compute_output(box, input)

	local props = box.computed
	local max_x, max_y = 0, 0
	local prev_mheight, prev_is_block = 0, false

	for i, child in box:iter_children() do
		if i ~= 1 and (prev_is_block or child:is("block")) then
			box.y = box.y + prev_mheight + props.spacing
			box.x = 0
		end

		child:layout(output)
		local child_mbox = child:get_box_size("margin")
		box.x = box.x + child_mbox.width

		max_x = math.max(box.x, max_x)
		max_y = math.max(box.y, max_y)

		prev_is_block = child:is("block")
		prev_mheight = child_mbox.height
	end

	box.width = max_x
	box.height = box.y + prev_mheight

	M.compute_final_size(box, input, output)
end

---@param box markup.box
---@param input markup.box.layout.Input
---@return markup.box.layout.Input
function M.compute_output(box, input)
	local computed = box.computed

	local width = box:resolve_size(computed.width, input.available_width)
	-- local height = box:resolve_size(computed.height, input.available_height, input.min_height)

	return {
		available_width = box:clamp_size(width, "width"),
	}
end

---@param box markup.box
---@param input markup.box.layout.Input
---@param output markup.box.layout.Input
function M.compute_final_size(box, input, output)
	local computed = box.computed

	local width = math.max(box.width, output.available_width)
	local height = math.max(box.height, box:resolve_size(computed.height, 0))
	height = math.max(height, input.min_height or 0)

	-- box:set_content_box_size({ width = width, height = height })
	box:set_content_box_width(width)
	box:set_content_box_height(height, true)
end

return M
