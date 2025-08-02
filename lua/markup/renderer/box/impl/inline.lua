local Impl = require("markup.renderer.box.impl")
local RenderBlock = require("markup.renderer.box.impl.block")
local RenderInblock = require("markup.renderer.box.impl.inblock")

---@class markup.box.inline : markup.box.impl
local M = Impl("RenderInline", { "inline" })

---@param box markup.box
---@param input markup.box.layout.Input
function M.layout(box, input)
	local props = box.props
	local output = M.compute_output(box, input)
	local max_y = 0

	local len = box:children_len()
	for i, child in box:iter_children() do
		if child:is("block") then
			child:layout(output, RenderInblock)
		else
			child:layout(output)
		end
		local mbox = child:get_box_size("margin")

		local taken = mbox.width + (i ~= len and props.spacing or 0)
		box.x = box.x + taken
		max_y = math.max(max_y, mbox.height)
		output.available_width = output.available_width - taken
	end

	box.width = box.x
	box.height = max_y

	box:set_content_box_width(box.width, true)
	box:set_content_box_height(box.height, true)
	-- RenderBlock.compute_final_size(box, input, output)
end

---@param box markup.box
---@param input markup.box.layout.Input
function M.compute_output(box, input)
	local width = box:resolve_size(box.computed.width, input.available_width)
	return { available_width = box:clamp_size(width, "width") }
end

return M
