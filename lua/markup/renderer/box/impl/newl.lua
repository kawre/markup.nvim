local Impl = require("markup.renderer.box.impl")

---@class markup.box.newl : markup.box.impl
local M = Impl("RenderNewl", { "block" })

---@param box markup.box
function M.layout(box)
	box.width, box.content_width = 0, 0
	box.height, box.content_height = 1, 1
end

return M
