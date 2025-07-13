local log = require("markup.logger") ---@diagnostic disable-line: unused-local

---@class markup.Render.Layout.Text: markup.Render.Layout
local TextLayout = {}
TextLayout.__name = "RenderText"
TextLayout.__type = { inline = true }

local ns = vim.api.nvim_create_namespace("markup_render_text")

---@param box markup.Render.Node
function TextLayout.layout(box)
	local str = tostring(box.node.props)

	box.height = 1
	box.width = vim.api.nvim_strwidth(str)
end

return TextLayout
