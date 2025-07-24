local Layout = require("markup.renderer.box.layout")

---@class markup.Render.Layout.Inline : markup.Render.Layout
local InlineLayout = Layout.new("RenderInline", { "inline" })

---@param box markup.box
function InlineLayout.layout(box)
	local props = box.props
	box.height = 1

	local len = box:children_len()
	for i, child in box:iter_children() do
		assert(child:is("inline"), "Inline layout can only be used for inline nodes")

		child:layout({})
		local mbox = child:get_box_size("margin")

		box.x = box.x + mbox.width + (i ~= len and props.spacing or 0)
	end

	box.width = box.x
	box:set_content_box_size({
		width = box.width,
		height = box.height,
	})
end

return InlineLayout
