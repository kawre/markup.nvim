local Impl = require("markup.renderer.box.impl")
local RenderBlock = require("markup.renderer.box.impl.block")

---@class markup.box.flex : markup.box.impl
local M = Impl("RenderFlex", { "flex", "block" })

---@param box markup.box
---@param constraints markup.box.constraints
function M.layout(box, constraints)
	constraints = M.compute_initial_size(box, constraints)

	if box.props.vertical then
		M.layout_vertical(box, constraints)
	else
		M.layout_horizontal(box, constraints)
	end
	M.compute_final_size(box, constraints)

	M.justify(box)
	M.align(box)
end

---@param box markup.box
---@param constraints markup.box.constraints
function M.layout_horizontal(box, constraints)
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
function M.layout_vertical(box, constraints)
	local props = box.props

	local max_width = 0
	local len = box:children_len()

	local isize = {} ---@type table<markup.box, markup.size>
	for i, child in box:iter_children() do
		isize[i] = child:compute_intrinsic_size()
	end

	for i, child in box:iter_children() do
		child:layout({
			width = constraints.width,
		})
		local child_mbox = child:get_box_size("margin")

		box.y = box.y + child_mbox.height + (i ~= len and props.spacing or 0)
		max_width = math.max(max_width, child_mbox.width)
	end

	Markup.log(isize)

	box.width = max_width
	box.height = box.y
end

---@param box markup.box
---@param constraints markup.box.constraints
function M.compute_initial_size(box, constraints)
	return RenderBlock.compute_initial_size(box, constraints)
end

---@param box markup.box
---@param constraints markup.box.constraints
function M.compute_final_size(box, constraints)
	box:set_content_box_size_raw({
		width = math.max(box.width, constraints.width or 0),
		height = math.max(box.height, constraints.height or 0),
	})
end

---@param box markup.box
function M.justify(box)
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
function M.align(box)
	local props = box.props
	local cbox = box:get_box_size("content")

	if props.align == "center" then
		local y = 0
		local len = box:children_len()
		for i, child in box:iter_children() do
			child:set_content_box_size({
				width = child.width,
				height = child.height,
			})

			local child_mbox = child:get_box_size("margin")
			child.oy = y
			child.ox = math.ceil((cbox.width - child_mbox.width) / 2)
			y = y + child_mbox.height + (i ~= len and props.spacing or 0)
		end
	end
end

---@param box markup.box
---@return markup.box.constraints
function M.compute_intrinsic_size(box)
	-- Reuse the block layout's min intrinsic size computation
	return RenderBlock.compute_intrinsic_size(box)
end

return M
