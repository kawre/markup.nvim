local RenderInline = require("markup.core.render.layout.inline")

---@class markup.Render.Text : markup.Render.Inline
---@field node markup.Text
---@field protected super markup.Render.Inline
local RenderText = RenderInline:extend("RenderText")

function RenderText:computed_lines()
	return { self.node.content }
end

function RenderText:layout()
	self.need_layout = false
	-- self.builder:append(self.node.content)
	self.builder:append(self.node.content)
end

return RenderText
