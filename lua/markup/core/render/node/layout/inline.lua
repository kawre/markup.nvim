local log = require("markup.logger")

---@class markup.Render.Layout.Inline: markup.Render.Layout
local InlineLayout = {}
InlineLayout.__name = "RenderInline"
InlineLayout.__type = { inline = true }

---@param box markup.Render.Node
function InlineLayout.layout(box)
	local props = box.props

	box.height = 1
	for _, child in ipairs(box.children) do
		assert(child:is("inline"), "Inline layout can only be used for inline nodes")
		child:layout()
		box.x = box.x + child.width + props.spacing
	end

	box.width = box.x - box.mx + props.margin_right + props.padding_right
end

return InlineLayout
