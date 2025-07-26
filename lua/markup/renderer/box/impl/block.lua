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
	box.height = math.max(box.y + prev_mheight, max_y)

	M.compute_final_size(box, output)
end

---@param box markup.box
---@param output markup.box.layout.Input
function M.compute_final_size(box, output)
	local computed = box.computed

	local width = box:resolve_size(computed.width, output.available_width)
	local height = box:resolve_size(computed.height, output.available_height)

	box:set_content_box_size({ width = width, height = height })
end

---@param box markup.box
---@return markup.box.layout.Input
function M.compute_output(box, contraints)
	local computed = box.computed

	local width = box:resolve_size(computed.width, contraints.available_width)
	local height = box:resolve_size(computed.height, contraints.available_height)

	-- we skip the relative numbers to handle them in `compute_final_size`
	return {
		available_width = width,
		available_height = height,
	}
end

return M
