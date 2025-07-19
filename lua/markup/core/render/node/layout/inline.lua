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
	box:set_content_box_size(box.width, 1)
end

---@param box markup.Render.Node
function InlineLayout.apply_size_constraints(box) ---@diagnostic disable-line: unused-local
	local width = box.props.width
	local parent_cbox = box.parent:content_box_size()

	local new_width = 0
	if width > 0 then
		if width < 1 then
			new_width = math.ceil(parent_cbox.width * width)
		else
			new_width = width
		end
	else
		new_width = parent_cbox.width
	end

	box:set_content_box_size(new_width, parent_cbox.height)
end

return InlineLayout
