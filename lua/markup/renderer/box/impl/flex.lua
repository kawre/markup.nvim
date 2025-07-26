local Impl = require("markup.renderer.box.impl")
local RenderBlock = require("markup.renderer.box.impl.block")

---@class markup.box.flex : markup.box.impl
local M = Impl("RenderFlex", { "flex", "block" })

---@param box markup.box
---@param input markup.box.layout.Input
function M.layout(box, input)
	local props = box.computed
	local children = box:children()
	local len = #children
	local content_size, cross_size = 0, 0
	local is_vertical = props.vertical

	local size = RenderBlock.compute_output(box, input)

	-- base size for each flex item
	local bsize = {}

	for i, child in ipairs(children) do
		if child.computed.basis ~= "auto" then
			bsize[i] = { width = child.computed.basis, height = 0 }
		elseif child.computed.width ~= "auto" then
			bsize[i] = { width = child.computed.width, height = 0 }
		else
			bsize[i] = child:compute_intrinsic_size()
		end

		-- convert to logical size
		if is_vertical then
			bsize[i].width, bsize[i].height = bsize[i].height, bsize[i].width
		end

		-- determine content width
		content_size = content_size + bsize[i].width + (i ~= len and props.spacing or 0)
		-- determine content height
		cross_size = math.max(cross_size, bsize[i].height)
	end

	local xd = box:resolve_size(props.height, cross_size)
	local main_axis_avail = is_vertical and xd or size.available_width
	local main_size = math.max(main_axis_avail, content_size)
	local main_free_space = main_size - content_size
	local main_axis = is_vertical and "oy" or "ox"

	if props.justify == "center" then
		local x = math.floor(main_free_space / 2)
		for i, child in ipairs(children) do
			child[main_axis] = x
			x = x + bsize[i].width + (i ~= len and props.spacing or 0)
		end
	elseif props.justify == "start" then
		local x = 0
		for i, child in ipairs(children) do
			child[main_axis] = x
			x = x + bsize[i].width + (i ~= len and props.spacing or 0)
		end
	elseif props.justify == "end" then
		local x = main_free_space
		for i, child in ipairs(children) do
			child[main_axis] = x
			x = x + bsize[1].width + (i ~= len and props.spacing or 0)
		end
	elseif props.justify == "between" then
		local n = #children
		local last = children[n]

		if n > 1 then
			local space = math.floor(main_free_space / (n - 1))
			local current_x = 0
			for _, child in ipairs(children) do
				child[main_axis] = current_x
				current_x = current_x + child.width + space
			end

			last.ox = main_size - last.width
		else
			children[1][main_axis] = 0
		end
	end

	local cross_axis_avail = math.max(not is_vertical and xd or size.available_width, cross_size)
	local cross_axis = is_vertical and "ox" or "oy"

	if props.align == "stretch" then
		for i, child in ipairs(children) do
			child[cross_axis] = 0
			bsize[i].height = cross_axis_avail
		end
	elseif props.align == "center" then
		for i, child in ipairs(children) do
			child[cross_axis] = math.floor((cross_axis_avail - bsize[i].height) / 2)
		end
	elseif props.align == "start" then
		for _, child in ipairs(children) do
			child[cross_axis] = 0
		end
	elseif props.align == "end" then
		for i, child in ipairs(children) do
			child[cross_axis] = cross_axis_avail - bsize[i].height
		end
	end

	for i, child in ipairs(children) do
		local physical_width = is_vertical and bsize[i].height or bsize[i].width
		local physical_height = is_vertical and bsize[i].width or bsize[i].height

		if child.width ~= physical_width or child.height ~= physical_height then
			-- layout the child if the size has changed
			child:layout({
				available_width = physical_width,
				min_height = physical_height,
				resume = true,
			})
		end
	end

	box.width = is_vertical and cross_size or main_size
	box.height = is_vertical and main_size or cross_size

	RenderBlock.compute_final_size(box, input, size)
end

-- ---@param box markup.box
-- ---@param constraints markup.box.layout.Input
-- function M.layout_vertical(box, constraints)
-- 	local props = box.props
--
-- 	local max_width = 0
-- 	local len = box:children_len()
--
-- 	local isize = {} ---@type table<markup.box, markup.size>
-- 	for i, child in box:iter_children() do
-- 		isize[i] = child:compute_intrinsic_size()
-- 	end
--
-- 	for i, child in box:iter_children() do
-- 		child:layout({
-- 			width = constraints.width,
-- 		})
-- 		local child_mbox = child:get_box_size("margin")
--
-- 		box.y = box.y + child_mbox.height + (i ~= len and props.spacing or 0)
-- 		max_width = math.max(max_width, child_mbox.width)
-- 	end
--
-- 	Markup.log(isize)
--
-- 	box.width = max_width
-- 	box.height = box.y
-- end

return M
