local Impl = require("markup.renderer.box.impl")

---@class markup.box.text : markup.box.impl
local M = Impl("RenderText", { "inline", "text" })

---@param box markup.box
function M.layout(box)
	local content = tostring(box.node.text_content)
	-- assert(content ~= "", "text nodes should not be empty")

	box.height = 1
	box.length = #content -- byte length
	box.width = vim.fn.strcharlen(content)
	box.text_content = content

	box:set_content_box_width(box.width, true)
	box:set_content_box_height(box.height, true)

	return { vim.split(content, "%s+") }
end

return M
