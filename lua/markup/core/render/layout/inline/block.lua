local RenderBlock = require("markup.core.render.layout.block")
local log = require("markup.logger") ---@diagnostic disable-line: unused-local

---@class markup.Render.Inline.Block : markup.Render.Block
local RenderInlineBlock = RenderBlock:extend("RenderInlineBlock")

function RenderInlineBlock:occupy_full_width()
	-- do nothing
end

return RenderInlineBlock
