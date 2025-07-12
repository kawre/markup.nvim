local LayoutStrategy = require("markup.core.render.node.layout")

---@class markup.Render.Layout.Inline: markup.Render.Layout
local InlineLayout = {}
InlineLayout.__name = "RenderInline"

function InlineLayout.layout(node)
	-- flex layout logic
end

return InlineLayout
