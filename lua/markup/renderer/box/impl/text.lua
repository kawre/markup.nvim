local Impl = require("markup.renderer.box.impl")

---@class markup.box.text : markup.box.impl
local TextLayout = Impl("RenderText", { "inline", "text" })

---@param box markup.box
function TextLayout.layout(box)
	local str = tostring(box.node.text_content)
	assert(str ~= "", "text nodes should not be empty")

	box.width = vim.api.nvim_strwidth(str)
	box.height = 1
	box.intrinsic_width = box.width
	box.intrinsic_height = box.height
	box.min_content_width = box.height
	box.min_content_height = box.width
	box.max_content_width = box.height
	box.max_content_height = box.width

	box:set_content_box_size({
		width = box.width,
		height = box.height,
	})
end

---@param box markup.box
---@return markup.box.constraints
function TextLayout.compute_intrinsic_size(box)
	local str = tostring(box.node.text_content)
	assert(str ~= "", "text nodes should not be empty")

	return {
		width = vim.api.nvim_strwidth(str),
		height = 1,
	}
end

return TextLayout
