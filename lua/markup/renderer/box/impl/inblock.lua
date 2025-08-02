local Impl = require("markup.renderer.box.impl")
local RenderBlock = require("markup.renderer.box.impl.block")

---@class markup.box.inblock : markup.box.impl
local M = Impl("RenderInblock", { "block", "inline" })

---@param box markup.box
---@param input markup.box.layout.Input
function M.layout(box, input)
	input.available_width = 0
	RenderBlock.layout(box, input)
end

return M
