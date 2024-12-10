local markup = require("markup.core")

---@class markup.Render.Box : markup.Render.Object
---@field protected super markup.Render.Object
local RenderBox = markup.Render.Object:extend("markup.render.box")

function RenderBox:width()
	-- return self.width_
end

function RenderBox:height()
	-- return self.height_
end

return RenderBox
