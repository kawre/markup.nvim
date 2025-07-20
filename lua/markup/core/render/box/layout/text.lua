local log = require("markup.logger") ---@diagnostic disable-line: unused-local
local Layout = require("markup.core.render.box.layout")

---@class markup.Render.Layout.Text : markup.Render.Layout
local TextLayout = Layout.new("RenderText", { "inline", "text" })

---@param box markup.Render.Box
function TextLayout.layout(box)
	local str = tostring(box.node.text_content)
	assert(str ~= "", "text nodes should not be empty")

	-- box.width = vim.api.nvim_strwidth(str)
	box.width = vim.fn.strlen(str)
	box.height = 1

	box:set_content_box_size(box.width, box.height)
end

return TextLayout
