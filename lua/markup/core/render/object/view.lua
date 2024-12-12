local markup = require("markup.core")

---@class markup.Render.View : markup.Render.Inline
---@field protected super markup.Render.Inline
local RenderView = markup.Render.Inline:extend("RenderView")

return RenderView
