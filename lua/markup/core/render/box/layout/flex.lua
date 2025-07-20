local log = require("markup.logger") ---@diagnostic disable-line: unused-local
local Layout = require("markup.core.render.box.layout")

---@class markup.Render.Layout.Flex : markup.Render.Layout
local FlexLayout = Layout.new("RenderFlex", { "flex", "block" })

---@param box markup.Render.Box
function FlexLayout.layout(box)
	local parent_cbox = box.parent:content_box_size()
	-- FlexLayout.compute_initial_width(box, parent_cbox)

	if box.props.vertical then
		FlexLayout.layout_vertical(box)
	else
		FlexLayout.layout_horizontal(box)
	end

	FlexLayout.compute_final_size(box, parent_cbox)
	FlexLayout.justify(box)
	FlexLayout.align(box)
end

---@param box markup.Render.Box
function FlexLayout.layout_horizontal(box)
	local props = box.props

	local max_width, max_height = 0, 0
	local len = #box.children

	for i, child in box:iter_children() do
		child:layout()

		box.x = box.x + child.width + (i ~= len and props.spacing or 0)
		max_width = math.max(max_width, box.x)
		max_height = math.max(max_height, child.height)
	end

	box.width = max_width
	box.height = max_height
end

---@param box markup.Render.Box
function FlexLayout.layout_vertical(box)
	local props = box.props

	local max_width, max_height = 0, 0
	local len = #box.children

	for i, child in box:iter_children() do
		child:layout()

		box.y = box.y + child.height + (i ~= len and props.spacing or 0)
		max_width = math.max(max_width, box.x)
		max_height = math.max(max_height, child.height)
	end

	box.width = max_width
	box.height = max_height
end

---@param box markup.Render.Box
---@param parent_cbox markup.Element.size
function FlexLayout.compute_initial_width(box, parent_cbox)
	-- log.info(parent_cbox)
	-- local new_width = box:normalize_size(width, parent_cbox.width)
	-- box:set_content_box_size(new_width)
end

---@param box markup.Render.Box
---@param parent_cbox markup.Element.size
function FlexLayout.compute_final_size(box, parent_cbox)
	local height = box.props.height
	local width = box.props.width
	local new_width = box:normalize_size(width, parent_cbox.width)
	box:set_content_box_size(math.max(box.width, new_width or 0), math.max(box.height, height or 0))
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
