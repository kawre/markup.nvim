local LayoutStrategy = require("markup.core.render.node.layout")

---@class markup.Render.Layout.Flex : markup.Render.Layout
local FlexLayout = {}
FlexLayout.__index = FlexLayout
setmetatable(FlexLayout, { __index = LayoutStrategy })

function FlexLayout:layout(node)
	-- flex layout logic
end

return FlexLayout
