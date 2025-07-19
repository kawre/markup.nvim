local log = require("markup.logger") ---@diagnostic disable-line: unused-local

---@class markup.Render.Layout.Flex : markup.Render.Layout
local FlexLayout = {}
FlexLayout.__name = "RenderFlex"
FlexLayout.__type = { flex = true, block = true }

---@param box markup.Render.Node
function FlexLayout.layout(box)
	-- if box.props.vertical then
	-- 	FlexLayout.layout_vertical(box)
	-- else
	FlexLayout.layout_horizontal(box)
	-- end
	FlexLayout.justify(box)
end

function FlexLayout.layout_horizontal(box)
	local parent = box.parent
	local props = box.props

	box.available_width = box.parent.available_width

	local max_width, max_height = 0, 0
	local len = #box.children

	for i, child in ipairs(box.children) do
		child:layout()

		child.available_height = child.height
		child.available_width = child.width

		box.x = box.x + child.width + (i ~= len and props.spacing or 0)
		max_height = math.max(max_height, child.height)
	end

	box.width = box.x
	box.height = max_height

	if props.justify == "center" then
		box.ox = math.floor((box.available_width - box.width) / 2)
	elseif props.justify == "end" then
		box.ox = box.available_width - box.width
	end
end

function FlexLayout.layout_vertical(box) end

function FlexLayout.justify(box)
	local props = box.props

	if props.justify == "center" then
		box.ox = math.floor((box.available_width - box.width) / 2)
	elseif props.justify == "end" then
		box.ox = box.available_width - box.width
	end
end

return FlexLayout
