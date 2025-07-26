local Impl = require("markup.renderer.box.impl")

---@class markup.box.text : markup.box.impl
local M = Impl("RenderText", { "inline", "text" })

---@param box markup.box
function M.layout(box)
	local str = tostring(box.node.text_content)
	assert(str ~= "", "text nodes should not be empty")

	box.width = vim.api.nvim_strwidth(str)
	box.height = 1

	box:set_content_box_width(box.width, true)
	box:set_content_box_height(box.height, true)
end

return M
