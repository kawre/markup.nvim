local log = require("markup.logger")

---@class markup.Render.Layout.Inline: markup.Render.Layout
local InlineLayout = {}
InlineLayout.__name = "RenderInline"
InlineLayout.__type = { inline = true }

---@param box markup.Render.Node
function InlineLayout.layout(box)
	box.height = 1

	for _, child in ipairs(box.children) do
		assert(child:is("inline"), "Inline layout can only be used for inline nodes")
		child:layout()
	end

	box.width = box.cx - box.x
end

return InlineLayout
