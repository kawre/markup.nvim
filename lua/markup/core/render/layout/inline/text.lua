local log = require("markup.logger") ---@diagnostic disable-line: unused-local
local RenderInline = require("markup.core.render.layout.inline")

---@class markup.Render.Text : markup.Render.Inline
---@field node markup.Text
---@field protected super markup.Render.Inline
local RenderText = RenderInline:extend("RenderText")

function RenderText:layout(style)
	self.need_layout = false
	self.node.props.style = style
	self.builder:line():append(self.node)
end

return RenderText
