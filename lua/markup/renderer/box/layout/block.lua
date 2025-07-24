local Layout = require("markup.renderer.box.layout")

---@class markup.Render.Layout.Block : markup.Render.Layout
local M = Layout.new("RenderBlock", { "block" })

---@param box markup.box
---@param constraints markup.box.constraints
function M.layout(box, constraints)
	constraints = M.compute_initial_width(box, constraints)

	local props = box.props
	local max_x, max_y = 0, 0
	local prev_mheight, prev_is_block = 0, false

	for i, child in box:iter_children() do
		if i ~= 1 and (prev_is_block or child:is("block")) then
			box.y = box.y + prev_mheight + props.spacing
			box.x = 0
		end

		child:layout(constraints)
		local child_mbox = child:get_box_size("margin")
		box.x = box.x + child_mbox.width

		max_x = math.max(box.x, max_x)
		max_y = math.max(box.y, max_y)

		prev_is_block = child:is("block")
		prev_mheight = child_mbox.height
	end

	box.height = math.max(box.y + prev_mheight, max_y)
	box.width = max_x

	M.compute_final_size(box, constraints)
end

---@param box markup.box
---@param constraints markup.box.constraints
function M.compute_initial_width(box, constraints)
	local width = box.props.width

	-- box:set_content_box_size(width)
	if width == "auto" or width == "full" then
		width = constraints.width
	elseif width == "fit" then
		-- delegate to `compute_final_size`
		width = nil
	else ---@cast width number
		width = Layout.resolve_size(width, constraints.width)
	end

	local height = box.props.height
	if height == "auto" or height == "fit" then
		-- delegate to `compute_final_size`
		height = nil
	elseif height == "full" then
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
function M.compute_final_size(box, constraints)
	box:set_content_box_size({
		width = math.max(box.width, constraints.width or 0),
		height = math.max(box.height, constraints.height or 0),
	})
end

return M
