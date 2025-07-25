local Impl = require("markup.renderer.box.impl")

---@class markup.box.block : markup.box.impl
local M = Impl("RenderBlock", { "block" })

---@param box markup.box
---@param input markup.box.constraints
---@return markup.box.constraints output
function M.layout(box, input)
	input = M.compute_initial_size(box, input)

	local props = box.props
	local max_x, max_y = 0, 0
	local prev_mheight, prev_is_block = 0, false

	for i, child in box:iter_children() do
		if i ~= 1 and (prev_is_block or child:is("block")) then
			box.y = box.y + prev_mheight + props.spacing
			box.x = 0
		end

		child:layout(input)
		local child_mbox = child:get_box_size("margin")
		box.x = box.x + child_mbox.width

		max_x = math.max(box.x, max_x)
		max_y = math.max(box.y, max_y)

		prev_is_block = child:is("block")
		prev_mheight = child_mbox.height
	end

	box.width = max_x
	box.height = math.max(box.y + prev_mheight, max_y)

	return M.compute_final_size(box, input)
end

---@param box markup.box
---@param constraints markup.box.constraints
---@return markup.box.constraints
function M.compute_initial_size(box, constraints)
	local width = box.props.width

	if width == "auto" or width == "full" then
		width = constraints.width
	elseif width == "fit" then
		-- delegate to `compute_final_size`
		width = nil
	else ---@cast width number
		width = box:resolve_size(width, constraints.width)
	end

	local height = box.props.height
	if height == "auto" or height == "fit" then
		-- delegate to `compute_final_size`
		height = nil
	elseif height == "full" then
		height = constraints.height
	else ---@cast height number
		height = box:resolve_size(height, constraints.height)
	end

	local size = box:clamp_content_size({
		width = width,
		height = height,
	})

	return size
end

---@param box markup.box
---@param constraints markup.box.constraints
---@return markup.box.constraints
function M.compute_final_size(box, constraints)
	local width = box.props.width
	if width == "auto" or width == "full" then
		width = constraints.width
	elseif width == "fit" then
		-- delegate to `compute_final_size`
		width = nil
	else ---@cast width number
		width = box:resolve_size(width, constraints.width)
	end

	local height = box.props.height
	if height == "auto" or height == "fit" then
		-- delegate to `compute_final_size`
		height = nil
	elseif height == "full" then
		height = constraints.height
	else ---@cast height number
		height = box:resolve_size(height, constraints.height)
	end

	box:set_content_box_size_raw({
		width = math.max(box.width, constraints.width or 0),
		height = math.max(box.height, constraints.height or 0),
	})
end

---@param box markup.box
---@return markup.box.constraints
function M.compute_intrinsic_size(box)
	local width, height = 0, 0
	local iwidth, iheight = 0, 0

	local prev_iheight, prev_is_block = 0, false

	for i, child in box:iter_children() do
		if i ~= 1 and (prev_is_block or child:is("block")) then
			width = 0
			height = height + prev_iheight
			iheight = math.max(iheight, height) + box.props.spacing
		end
		local isize = child:compute_intrinsic_size()
		width = width + isize.width
		iwidth = math.max(iwidth, width)
		prev_iheight = isize.height
		prev_is_block = child:is("block")
	end

	if prev_is_block then
		iheight = math.max(iheight, height + prev_iheight)
	end

	return {
		width = iwidth,
		height = iheight,
	}
end

return M
