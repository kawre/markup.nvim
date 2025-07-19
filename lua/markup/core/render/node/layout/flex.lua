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

---@param box markup.Render.Node
function FlexLayout.layout_horizontal(box)
	local parent = box.parent
	local props = box.props

	box.available_width = box.parent.available_width

	local max_width, max_height = 0, 0
	local len = #box.children

	for i, child in box:iter_children() do
		child:layout()

		child.available_height = child.height
		child.available_width = child.width

		box.x = box.x + child.width + (i ~= len and props.spacing or 0)
		max_height = math.max(max_height, child.height)
	end

	box.width = box.x
	box.height = max_height
end

---@param box markup.Render.Node
function FlexLayout.layout_vertical(box) end

---@param box markup.Render.Node
function FlexLayout.justify(box)
	local props = box.props

	if props.justify == "center" then
		box.ox = math.floor((box.available_width - box.width) / 2)
	elseif props.justify == "end" then
		box.ox = box.available_width - box.width
	elseif props.justify == "between" then
		local n = #box.children
		local last = box.children[n]

		if n > 1 then
			local total_children_width = 0
			for _, child in box:iter_children() do
				total_children_width = total_children_width + child.width
			end

			local space = math.floor((box.available_width - total_children_width) / (n - 1))
			local current_x = 0
			for _, child in box:iter_children() do
				child.ox = current_x
				current_x = current_x + child.width + space
			end

			last.ox = box.available_width - last.width
		else
			box.children[1].ox = 0
		end
	end
end

return FlexLayout
