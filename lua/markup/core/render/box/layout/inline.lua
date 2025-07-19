local log = require("markup.logger")
local Layout = require("markup.core.render.box.layout")

---@class markup.Render.Layout.Inline : markup.Render.Layout
local InlineLayout = Layout.new("RenderInline", { "inline" })

---@param box markup.Render.Box
function InlineLayout.layout(box)
	local props = box.props
	box.height = 1

	local len = #box.children
	for i, child in box:iter_children() do
		assert(child:is("inline"), "Inline layout can only be used for inline nodes")

		child:layout()
		local mbox = child:margin_box_size()

		box.x = box.x + mbox.width + (i ~= len and props.spacing or 0)
	end

	box.width = box.x
	box:set_content_box_size(box.width, box.height)
end

return InlineLayout
