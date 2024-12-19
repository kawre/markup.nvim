local markup = require("markup.core")

---@class markup.Render.View : markup.Render.Block
---@field protected super markup.Render.Block
local RenderView = markup.Render.Block:extend("RenderView")

return RenderView
