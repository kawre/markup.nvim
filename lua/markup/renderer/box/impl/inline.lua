local Impl = require("markup.renderer.box.impl")

---@class markup.box.inline : markup.box.impl
local M = Impl("RenderInline", { "inline" })

---@param box markup.box
---@param constraints markup.box.constraints
function M.layout(box, constraints)
	local props = box.props
	box.height = 1

	local len = box:children_len()
	for i, child in box:iter_children() do
		assert(child:is("inline"), "Inline layout can only be used for inline nodes")

		child:layout({})
		local mbox = child:get_box_size("margin")

		box.x = box.x + mbox.width + (i ~= len and props.spacing or 0)
	end

	box.width = box.x
	box:set_content_box_size({
		width = box.width,
		height = box.height,
	})

	return {}
end

---@param box markup.box
---@return markup.box.constraints
function M.compute_intrinsic_size(box)
	local width = 0

	for _, child in box:iter_children() do
		local isize = child:compute_intrinsic_size()
		width = width + isize.width
	end

	return {
		width = width,
		height = 1,
	}
end

return M
