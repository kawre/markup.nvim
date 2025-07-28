local Impl = require("markup.renderer.box.impl")
local RenderBlock = require("markup.renderer.box.impl.block")

---@class markup.box.inline : markup.box.impl
local M = Impl("RenderInline", { "inline" })

---@param box markup.box
---@param input markup.box.layout.Input
function M.layout(box, input)
	local props = box.props
	local output = M.compute_output(box, input)

	local len = box:children_len()
	for i, child in box:iter_children() do
		assert(child:is("inline"), "Inline layout can only be used for inline nodes")

		child:layout(output)
		local mbox = child:get_box_size("margin")

		box.x = box.x + mbox.width + (i ~= len and props.spacing or 0)
	end

	box.width = box.x
	box.height = 1

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
