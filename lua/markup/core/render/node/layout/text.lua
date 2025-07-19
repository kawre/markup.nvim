local log = require("markup.logger") ---@diagnostic disable-line: unused-local

---@class markup.Render.Layout.Text : markup.Render.Layout
local TextLayout = {}
TextLayout.__name = "RenderText"
TextLayout.__type = { inline = true, text = true }

---@param box markup.Render.Node
function TextLayout.layout(box)
	local str = tostring(box.node.text_content)
	assert(str ~= "", "text nodes should not be empty")

	box.width = vim.api.nvim_strwidth(str)
	box.height = 1
end

return TextLayout
