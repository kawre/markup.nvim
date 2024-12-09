local markup = require("markup.core")

---@class markup.Render.Inline : markup.Render.Flow
local RenderInline = markup.Render.Flow:extend("markup.render.inline")

return RenderInline
