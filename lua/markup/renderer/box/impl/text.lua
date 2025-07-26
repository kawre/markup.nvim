local Impl = require("markup.renderer.box.impl")

---@class markup.box.text : markup.box.impl
local M = Impl("RenderText", { "inline", "text" })

---@param box markup.box
function M.layout(box)
	local str = tostring(box.node.text_content)
	assert(str ~= "", "text nodes should not be empty")

	box.width = vim.api.nvim_strwidth(str)
	box.height = 1

	box:set_content_box_size({
		width = box.width,
		height = box.height,
	})
end

return M
