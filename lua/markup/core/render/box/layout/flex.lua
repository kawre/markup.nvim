local log = require("markup.logger") ---@diagnostic disable-line: unused-local
local Layout = require("markup.core.render.box.layout")

---@class markup.Render.Layout.Flex : markup.Render.Layout
local FlexLayout = Layout.new("RenderFlex", { "flex", "block" })

---@param box markup.Render.Box
function FlexLayout.layout(box)
	local w, h = FlexLayout.compute_initial_size(box)
	if box.props.vertical then
		FlexLayout.layout_vertical(box, w, h)
	else
		FlexLayout.layout_horizontal(box, w, h)
	end
	FlexLayout.compute_final_size(box, w, h)

	FlexLayout.justify(box)
	FlexLayout.align(box)
end

---@param box markup.Render.Box
function FlexLayout.layout_horizontal(box, w, h)
	local props = box.props
	local gw = w and math.ceil(w / #box.children)

	local max_width, max_height = 0, 0
	local len = #box.children

	for i, child in box:iter_children() do
		child:layout()
		local child_mbox = child:margin_box_size()

		box.x = box.x + child_mbox.width + (i ~= len and props.spacing or 0)
		max_width = math.max(max_width, box.x)
		max_height = math.max(max_height, child_mbox.height)
	end

	box.width = max_width
	box.height = max_height
end

---@param box markup.Render.Box
function FlexLayout.layout_vertical(box, w, h)
	local props = box.props

	local max_width = 0
	local len = #box.children

	for i, child in box:iter_children() do
		child:layout()
		local child_mbox = child:margin_box_size()

		box.y = box.y + child_mbox.height + (i ~= len and props.spacing or 0)
		max_width = math.max(max_width, child_mbox.width)
	end

	box.width = max_width
	box.height = box.y
end

---@param box markup.Render.Box
function FlexLayout.compute_initial_size(box)
	local props = box.props
	local width, height = props.width, props.height
	local parent_cbox = box.parent and box.parent:content_box_size()

	if parent_cbox and not vim.tbl_isempty(parent_cbox) then
		width = box:inherit_size(width, parent_cbox.width)
		height = box:inherit_size(height, parent_cbox.height)
	else
		-- relative numbers [0,1) will not working when we don't know the parent size
		width = width >= 1 and width or nil
		height = height >= 1 and height or nil
	end

	return width, height
end

---@param box markup.Render.Box
function FlexLayout.compute_final_size(box, w, h)
	local vertical = box.props.vertical

	local width, height
	if vertical then
		width = w and math.max(w, box.width) or box.width
		height = h and math.max(h, box.height) or box.height
	else
		width = w and math.max(w, box.width) or box.width
		height = h and math.min(h, box.height) or box.height
	end

	box:set_content_box_size(width, height)
end

---@param box markup.Render.Box
function FlexLayout.justify(box)
	local props = box.props
	local cbox = box:content_box_size()

	if props.justify == "center" then
		local x = math.ceil((cbox.width - box.width) / 2)
		local len = #box.children
		for i, child in box:iter_children() do
			child.ox = x
			local child_mbox = child:margin_box_size()
			x = x + child_mbox.width + (i ~= len and props.spacing or 0)
		end
	elseif props.justify == "end" then
		local x = cbox.width - box.width
		local len = #box.children
		for i, child in box:iter_children() do
			child.ox = x
			local child_mbox = child:margin_box_size()
			x = x + child_mbox.width + (i ~= len and props.spacing or 0)
		end
	elseif props.justify == "between" then
		local n = #box.children
		local last = box.children[n]

		if n > 1 then
			local total_children_width = 0
			for _, child in box:iter_children() do
				total_children_width = total_children_width + child.width
			end

			local space = math.floor((cbox.width - total_children_width) / (n - 1))
			local current_x = 0
			for _, child in box:iter_children() do
				child.ox = current_x
				current_x = current_x + child.width + space
			end

			last.ox = cbox.width - last.width
		else
			box.children[1].ox = 0
		end
	end
end

---@param box markup.Render.Box
function FlexLayout.align(box)
	local props = box.props
	local cbox = box:content_box_size()

	if props.align == "center" then
		local y = 0
		local len = #box.children
		for i, child in box:iter_children() do
			local child_mbox = child:margin_box_size()
			child.oy = y
			child.ox = math.ceil((cbox.width - child_mbox.width) / 2)
			y = y + child_mbox.height + (i ~= len and props.spacing or 0)
		end
	end
end

return FlexLayout
