local markup = require("markup.core")

---@class markup.Render.Text : markup.Render.Inline
---@field node markup.Text
---@field protected super markup.Render.Inline
local RenderText = markup.Render.Inline:extend("RenderText")

function RenderText:layout()
	self.need_layout = false
	-- self.builder:append(self.node.content)
	self.builder:append(self.node.content)
end

return RenderText
