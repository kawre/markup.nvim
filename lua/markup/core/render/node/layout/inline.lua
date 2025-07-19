local log = require("markup.logger")
local Layout = require("markup.core.render.node.layout")

---@class markup.Render.Layout.Inline : markup.Render.Layout
local InlineLayout = Layout.new("RenderInline", { "inline" })

---@param box markup.Render.Node
function InlineLayout.layout(box)
	local props = box.props
	box.height = 1

	local len = #box.children
	for i, child in box:iter_children() do
		assert(child:is("inline"), "Inline layout can only be used for inline nodes")

		child:layout()

		box.x = box.x + child.width + (i ~= len and props.spacing or 0)
	end

	box.width = box.x
end

return InlineLayout
