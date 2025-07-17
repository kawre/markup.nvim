local log = require("markup.logger") ---@diagnostic disable-line: unused-local

---@class markup.Render.Layout.Text: markup.Render.Layout
local TextLayout = {}
TextLayout.__name = "RenderText"
TextLayout.__type = { inline = true }

---@param box markup.Render.Node
function TextLayout.layout(box)
	local str = tostring(box.node.text_content)

	box.height = 1
	box.width = vim.api.nvim_strwidth(str)
	-- box.parent.cx = box.parent.cx + box.width
	-- box.cx = box.cx + box.width

	table.insert(_MTEMP, box)
end

return TextLayout
