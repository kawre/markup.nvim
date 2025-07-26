local Impl = require("markup.renderer.box.impl")
local RenderBlock = require("markup.renderer.box.impl.block")

---@class markup.box.flex : markup.box.impl
local M = Impl("RenderFlex", { "flex", "block" })

-- ---@param box markup.box
-- ---@param constraints markup.box.layout.Input
-- function M.layout(box, constraints)
-- 	-- constraints = box:compute_available_size(constraints)
--
-- 	if box.props.vertical then
-- 		M.layout_vertical(box, constraints)
-- 	else
-- 		M.layout_horizontal(box, constraints)
-- 	end
--
-- 	-- M.justify(box)
-- 	-- M.align(box)
--
-- 	M.compute_final_size(box, constraints)
-- end

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

		local logical_width = is_vertical and bsize[i].height or bsize[i].width
		local logical_height = is_vertical and bsize[i].width or bsize[i].height

		-- determine content width
		content_size = content_size + logical_width + (i ~= len and props.spacing or 0)
		-- determine content height
		cross_size = math.max(cross_size, logical_height)
	end

	Markup.log(size)

	local main_size = is_vertical and size.available_height or size.available_width
	local free_space = main_size - content_size

	if props.justify == "center" then
		local x = math.ceil(free_space / 2)
		for i, child in ipairs(children) do
			child.ox = x
			x = x + bsize[i].width + (i ~= len and props.spacing or 0)
		end
	elseif props.justify == "start" then
		local x = 0
		for i, child in ipairs(children) do
			child.ox = x
			x = x + bsize[i].width + (i ~= len and props.spacing or 0)
		end
	elseif props.justify == "end" then
		local x = free_space
		for i, child in ipairs(children) do
			child.ox = x
			x = x + bsize[1].width + (i ~= len and props.spacing or 0)
		end
	elseif props.justify == "between" then
		local n = #children
		local last = children[n]

		if n > 1 then
			local space = math.floor(free_space / (n - 1))
			local current_x = 0
			for _, child in ipairs(children) do
				child.ox = current_x
				current_x = current_x + child.width + space
			end

			last.ox = main_size - last.width
		else
			children[1].ox = 0
		end
	end

	if props.align == "stretch" then
		for _, b in ipairs(bsize) do
			b.height = is_vertical and b.height or cross_size
		end
	elseif props.align == "center" then
		-- local y = 0
		-- for i, child in ipairs(children) do
		-- 	local child_mbox = child:get_box_size("margin")
		-- 	child.oy = y
		-- 	child.ox = math.ceil((cbox.width - child_mbox.width) / 2)
		-- 	y = y + child_mbox.height + (i ~= len and props.spacing or 0)
		-- end
	end

	for i, child in ipairs(children) do
		if child.width ~= bsize[i].width or child.height ~= bsize[i].height then
			-- layout the child if the size has changed
			bsize[i].resume = true
			child:layout(bsize[i])
		end
	end

	box.width = main_size
	box.height = cross_size

	RenderBlock.compute_final_size(box, size)
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
