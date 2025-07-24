local Layout = require("markup.renderer.box.layout")

---@class markup.Render.Layout.Flex : markup.Render.Layout
local FlexLayout = Layout.new("RenderFlex", { "flex", "block" })

---@param box markup.box
---@param constraints markup.box.constraints
function FlexLayout.layout(box, constraints)
	constraints = FlexLayout.compute_initial_size(box, constraints)

	if box.props.vertical then
		FlexLayout.layout_vertical(box, constraints)
	else
		FlexLayout.layout_horizontal(box, constraints)
	end
	FlexLayout.compute_final_size(box, constraints)

	FlexLayout.justify(box)
	FlexLayout.align(box)
end

---@param box markup.box
---@param constraints markup.box.constraints
function FlexLayout.layout_horizontal(box, constraints)
	local props = box.props
	local len = box:children_len()
	-- local gw = w and math.ceil(w / len)
	local max_width, max_height = 0, 0

	for i, child in box:iter_children() do
		child:layout({})
		local child_mbox = child:get_box_size("margin")

		box.x = box.x + child_mbox.width + (i ~= len and props.spacing or 0)
		max_width = math.max(max_width, box.x)
		max_height = math.max(max_height, child_mbox.height)
	end

	box.width = max_width
	box.height = max_height
end

---@param box markup.box
---@param constraints markup.box.constraints
function FlexLayout.layout_vertical(box, constraints)
	local props = box.props

	local max_width = 0
	local len = box:children_len()

	for i, child in box:iter_children() do
		child:layout({})
		local child_mbox = child:get_box_size("margin")

		box.y = box.y + child_mbox.height + (i ~= len and props.spacing or 0)
		max_width = math.max(max_width, child_mbox.width)
	end

	box.width = max_width
	box.height = box.y
end

---@param box markup.box
---@param constraints markup.box.constraints
function FlexLayout.compute_initial_size(box, constraints)
	local props = box.props
	local width, height = props.width, props.height

	if width == "fit" then
		width = nil
	elseif width == "auto" or width == "full" then
		width = constraints.width
	else ---@cast width number
		width = Layout.resolve_size(width, constraints.width)
	end

	if height == "fit" then
		height = nil
	elseif height == "auto" or height == "full" then
		height = constraints.height
	else ---@cast height number
		height = Layout.resolve_size(height, constraints.height)
	end

	return box:clamp_content_size({
		width = width,
		height = height,
	})
end

---@param box markup.box
---@param constraints markup.box.constraints
function FlexLayout.compute_final_size(box, constraints)
	box:set_content_box_size_raw({
		width = math.max(box.width, constraints.width or 0),
		height = math.max(box.height, constraints.height or 0),
	})
end

---@param box markup.box
function FlexLayout.justify(box)
	local props = box.props
	local cbox = box:get_box_size("content")

	if props.justify == "center" then
		local x = math.ceil((cbox.width - box.width) / 2)
		local len = box:children_len()
		for i, child in box:iter_children() do
			child.ox = x
			local child_mbox = child:get_box_size("margin")
			x = x + child_mbox.width + (i ~= len and props.spacing or 0)
		end
	elseif props.justify == "end" then
		local x = cbox.width - box.width
		local len = box:children_len()
		for i, child in box:iter_children() do
			child.ox = x
			local child_mbox = child:get_box_size("margin")
			x = x + child_mbox.width + (i ~= len and props.spacing or 0)
		end
	elseif props.justify == "between" then
		local children = box:children()
		local n = #children
		local last = children[n]

		if n > 1 then
			local total_children_width = 0
			for _, child in ipairs(children) do
				total_children_width = total_children_width + child.width
			end

			local space = math.floor((cbox.width - total_children_width) / (n - 1))
			local current_x = 0
			for _, child in ipairs(children) do
				child.ox = current_x
				current_x = current_x + child.width + space
			end

			last.ox = cbox.width - last.width
		else
			children[1].ox = 0
		end
	end
end

---@param box markup.box
function FlexLayout.align(box)
	local props = box.props
	local cbox = box:get_box_size("content")

	if props.align == "center" then
		local y = 0
		local len = box:children_len()
		for i, child in box:iter_children() do
			local child_mbox = child:get_box_size("margin")
			child.oy = y
			child.ox = math.ceil((cbox.width - child_mbox.width) / 2)
			y = y + child_mbox.height + (i ~= len and props.spacing or 0)
		end
	end
end

return FlexLayout
