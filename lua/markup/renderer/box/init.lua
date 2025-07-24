local BoxProps = require("markup.renderer.box.props")

---@class markup.box
---@field layout_strategy markup.Render.Layout
---@field node markup.node
---@field parent markup.box
---@field dirty boolean
---@field buf table
---@field x integer
---@field y integer
---@field ox integer offset x
---@field oy integer offset y
---@field wx integer final window x
---@field wy integer final window y
---@field width integer
---@field height integer
---@field content_width integer
---@field content_height integer
---@field available_width integer
---@field available_height integer
---@field props markup.Render.props
---@field extmarks table
local RenderBox = Markup.object()

---@param node markup.node
---@param layout_strategy markup.Render.Layout
function RenderBox:new(node, layout_strategy)
	self.layout_strategy = layout_strategy
	self.node = node
	node.box = self
	self.dirty = true
	self.buf = {}
	self.props = BoxProps:new(self)
	self.extmarks = {}
	self.__id = Markup.util.gen_id()
end

function RenderBox:build()
	for _, child in ipairs(self.node.child_nodes) do
		local new_render_node = self:attach(child)
		new_render_node:build()
	end
	self:flag_as_dirty()
end

function RenderBox:reflow()
	if not self.dirty then
		return
	end

	for _, child in ipairs(self.node.child_nodes) do
		if not child.box then
			self:attach(child)
			child.box:build()
		else
			child.box:reflow()
		end
	end
end

function RenderBox:flag_as_dirty()
	if self.dirty then
		return
	end

	self.dirty = true
	if self.parent then
		self.parent:flag_as_dirty()
	end
end

---@param child markup.node
function RenderBox:attach(child)
	local child_box = Markup.factory.box(child)
	child_box.parent = self
	return child_box
end

function RenderBox:iter_children()
	local children = self.node.child_nodes
	local i, n = 0, #children
	local reverse = self.props.reverse

	return function()
		i = i + 1
		if i > n then
			return nil
		end
		return i, children[reverse and (n + 1 - i) or i].box
	end
end

function RenderBox:layout()
	assert(self.layout_strategy, "Layout strategy is not set")

	if self.dirty == false then
		return
	end

	local old_cwidth = self.content_width
	local old_cheight = self.content_height
	self.content_width = nil
	self.content_height = nil

	self.width = nil
	self.height = nil

	self.wx = nil
	self.wy = nil

	-- offset
	self.ox = self.parent.x
	self.oy = self.parent.y

	self.x = 0
	self.y = 0
	self.layout_strategy.layout(self)
	self.x = nil
	self.y = nil

	Markup.assert.bug(self.width, "Width must be resolved by layout strategy.")
	Markup.assert.bug(self.height, "Height must be resolved by layout strategy.")
	Markup.assert.bug(self.content_width, "Content width must be resolved by layout strategy.")
	Markup.assert.bug(self.content_height, "Content height must be resolved by layout strategy.")

	-- self.dirty = false
	if old_cwidth ~= self.content_width or old_cheight ~= self.content_height then
		self.parent:flag_as_dirty()
	end
end

function RenderBox:add_child(node)
	if not node or type(node) ~= "table" or not node.render or not node.layout then
		error("Invalid child node")
	end
	if not self.children then
		self.children = {}
	end
	table.insert(self.children, node)
	return self
end

function RenderBox:remove_child(node)
	if not self.children then
		return self
	end
	for i, child in ipairs(self.children) do
		if child == node then
			table.remove(self.children, i)
			return self
		end
	end
	error("Child node not found")
end

function RenderBox:name()
	return self.layout_strategy.__name
end

---@param layout_type markup.Render.LayoutType
function RenderBox:is(layout_type)
	return self.layout_strategy.__type[layout_type]
end

-- function RenderNode:set_constraints(width, height)
-- 	if width then
-- 		self.width = width
-- 	end
-- 	if height then
-- 		self.height = height
-- 	end
-- end

function RenderBox:margin_box_size()
	local props = self.props
	local pbox = self:padding_box_size()

	return {
		width = pbox.width and pbox.width + (props.margin_left + props.margin_right),
		height = pbox.height and pbox.height + (props.margin_top + props.margin_bottom),
	}
end

function RenderBox:padding_box_size()
	local props = self.props
	local cbox = self:content_box_size()

	return {
		width = cbox.width and cbox.width + (props.padding_left + props.padding_right),
		height = cbox.height and cbox.height + (props.padding_top + props.padding_bottom),
	}
end

---@param size integer
---@param ref integer
---@return integer
function RenderBox:inherit_size(size, ref)
	if not size then
		return ref
	end
	if not ref then
		return size
	end

	if size and size > 0 then
		return size < 1 and math.ceil(ref * size) or size
	else
		return ref
	end
end

---@param width? integer
---@param height? integer
function RenderBox:set_content_box_size(width, height)
	local props = self.props

	if width then
		if props.sizing == "inner" then
			width = width
				- (props.padding_left + props.padding_right)
				- (props.margin_left + props.margin_right)
		end
		self.content_width = math.max(self.width or 0, width)
	end

	if height then
		if self:is("inline") then
			self.content_height = 1
		else
			if props.sizing == "inner" then
				height = height
					- (props.padding_top + props.padding_bottom)
					- (props.margin_top + props.margin_bottom)
			end
			self.content_height = math.max(self.height or 0, height)
		end
	end
end

function RenderBox:content_box_size()
	return {
		width = self.content_width,
		height = self.content_height,
	}
end

function RenderBox:destroy()
	local index
	for i, child in ipairs(self.parent.children) do
		if child == self then
			index = i
			break
		end
	end
	table.remove(self.parent.children, index)
	self = nil
end

-- ---@param renderer markup.renderer
-- ---@param x integer
-- ---@param y integer
-- function RenderBox:paint(renderer, x, y)
-- 	local ns = renderer.ns
-- 	local props = self.props
--
-- 	if self:is("text") then
-- 		-- only leaf nodes (text) can output text on the screen
-- 		local word = tostring(self.node.text_content)
-- 		-- vim.api.nvim_buf_set_text(0, y, x, y, x + self.width, { word })
-- 		if not renderer.lines[y] then
-- 			renderer.lines[y] = {}
-- 		end
-- 		-- renderer.lines[y][x] = { str = word, len = self.width }
-- 		table.insert(renderer.lines[y], { word = word, width = self.width, x = x })
-- 	else
-- 		-- everything else only outputs style
-- 		local pbox = self:padding_box_size()
-- 		local pox = x + props.margin_left
-- 		local poy = y + props.margin_top
--
-- 		Markup.util.set_hl({
-- 			[self.__id] = self.props.style,
-- 		}, { managed = true, prefix = "MarkupDynamic" })
--
-- 		for line = 0, pbox.height - 1 do
-- 			table.insert(renderer.extmarks, {
-- 				line = poy + line,
-- 				col = pox,
-- 				end_col = pox + pbox.width,
-- 				hl_group = "MarkupDynamic" .. self.__id,
-- 			})
-- 			-- local extmark_id = vim.api.nvim_buf_set_extmark(0, ns, poy + line, pox, {
-- 			-- 	end_col = pox + pbox.width,
-- 			-- 	hl_eol = true,
-- 			-- 	hl_group = "MarkupDynamic" .. self.__id,
-- 			-- 	hl_mode = "combine",
-- 			-- })
-- 			-- table.insert(self.extmarks, extmark_id)
-- 		end
-- 	end
-- end

---@param renderer markup.renderer
---@param x integer
---@param y integer
function RenderBox:paint(renderer, x, y)
	local ns = renderer.ns
	local props = self.props

	if self:is("text") then
		-- only leaf nodes (text) can output text on the screen
		local word = tostring(self.node.text_content)
		-- vim.api.nvim_buf_set_text(0, y, x, y, x + self.width, { word })
		vim.api.nvim_buf_set_extmark(0, ns, y, x, {
			virt_text = { { word } },
			virt_text_pos = "overlay",
			hl_mode = "combine",
		})
	else
		-- everything else only outputs style
		local pbox = self:padding_box_size()
		local pox = x + props.margin_left
		local poy = y + props.margin_top

		Markup.util.set_hl({
			[self.__id] = self.props.style,
		}, { managed = true, prefix = "MarkupDynamic", force = true })

		for line = 0, pbox.height - 1 do
			local extmark_id = vim.api.nvim_buf_set_extmark(0, ns, poy + line, pox, {
				end_col = pox + pbox.width,
				hl_eol = true,
				hl_group = "MarkupDynamic" .. self.__id,
				hl_mode = "combine",
			})
			table.insert(self.extmarks, extmark_id)
		end
	end
end

function RenderBox:debug_paint_margin(renderer, x, y)
	assert(Markup.config.debug, "Debug mode is not enabled.")
	local props = self.props
	local ns = renderer.debug_ns

	local hl = "CurSearch"

	local mlxs = x
	local mrxs = mlxs
		+ props.margin_left
		+ props.padding_left
		+ self.content_width
		+ props.padding_right

	local mtys = y
	local mtye = mtys + props.margin_top
	local mbys = mtye + props.padding_top + self.content_height + props.padding_bottom
	local mbye = mbys + props.margin_bottom

	for line = mtys, mtye - 1 do
		vim.api.nvim_buf_set_extmark(0, ns, line, mlxs, {
			end_col = mrxs + props.margin_right,
			hl_eol = true,
			hl_group = hl,
			hl_mode = "combine",
		})
	end
	for line = mbys, mbye - 1 do
		vim.api.nvim_buf_set_extmark(0, ns, line, mlxs, {
			end_col = mrxs + props.margin_right,
			hl_eol = true,
			hl_group = hl,
			hl_mode = "combine",
		})
	end
	for line = mtye, mbys - 1 do
		vim.api.nvim_buf_set_extmark(0, ns, line, mlxs, {
			end_col = mlxs + props.margin_left,
			hl_eol = true,
			hl_group = hl,
			hl_mode = "combine",
		})
		vim.api.nvim_buf_set_extmark(0, ns, line, mrxs, {
			end_col = mrxs + props.margin_right,
			hl_eol = true,
			hl_group = hl,
			hl_mode = "combine",
		})
	end
end

function RenderBox:debug_paint_padding(renderer, x, y)
	assert(Markup.config.debug, "Debug mode is not enabled.")
	local props = self.props
	local ns = renderer.debug_ns

	local hl = "Search"

	local plxs = x + props.margin_left
	local prxs = plxs + props.padding_left + self.content_width

	local ptys = y + props.margin_top
	local ptye = ptys + props.padding_top
	local pbys = ptye + self.content_height
	local pbye = pbys + props.padding_bottom

	for line = ptys, ptye - 1 do
		vim.api.nvim_buf_set_extmark(0, ns, line, plxs, {
			end_col = prxs + props.padding_right,
			hl_eol = true,
			hl_group = hl,
			hl_mode = "combine",
		})
	end
	for line = pbys, pbye - 1 do
		vim.api.nvim_buf_set_extmark(0, ns, line, plxs, {
			end_col = prxs + props.padding_right,
			hl_eol = true,
			hl_group = hl,
			hl_mode = "combine",
		})
	end
	for line = ptye, pbys - 1 do
		vim.api.nvim_buf_set_extmark(0, ns, line, plxs, {
			end_col = plxs + props.padding_left,
			hl_eol = true,
			hl_group = hl,
			hl_mode = "combine",
		})
		vim.api.nvim_buf_set_extmark(0, ns, line, prxs, {
			end_col = prxs + props.padding_right,
			hl_eol = true,
			hl_group = hl,
			hl_mode = "combine",
		})
	end
end

function RenderBox:margin_box_range()
	local props = self.props

	if not self.wx or not self.wy then
		return
	end

	local top = self.wy
	local bottom = top
		+ props.margin_top
		+ props.padding_top
		+ self.content_height
		+ props.padding_bottom
		+ props.margin_bottom
	local left = self.wx
	local right = left
		+ props.margin_left
		+ props.padding_left
		+ self.content_width
		+ props.padding_right
		+ props.margin_right

	return {
		top = top,
		bottom = bottom,
		right = right,
		left = left,
	}
end

function RenderBox:padding_box_range()
	local props = self.props

	if not self.wx or not self.wy then
		return
	end

	local top = self.wy + props.margin_top
	local bottom = props.padding_top + top + self.content_height + props.padding_bottom
	local left = self.wx + props.margin_left
	local right = left + props.padding_left + self.content_width + props.padding_right

	return {
		top = top,
		bottom = bottom,
		right = right,
		left = left,
	}
end

function RenderBox:content_box_range()
	local props = self.props

	local top = self.wy + props.margin_top + props.padding_top
	local bottom = top + self.content_height
	local left = self.wx + props.margin_left + props.padding_left
	local right = left + self.content_width

	return {
		top = top,
		bottom = bottom,
		right = right,
		left = left,
	}
end

-- function RenderBox:box_range()
-- 	local props = self.props
--
-- 	local top = self.wy + props.margin_top + props.padding_top
-- 	local bottom = top + self.content_height
-- 	local left = self.wx + props.margin_left + props.padding_left
-- 	local right = left + self.content_width
--
-- 	return {
-- 		top = top,
-- 		bottom = bottom,
-- 		right = right,
-- 		left = left,
-- 	}
-- end

function RenderBox:children()
	return vim.tbl_map(function(n)
		return n.box
	end, self.node.child_nodes)
end

function RenderBox:children_len()
	return #self.node.child_nodes
end

function RenderBox:in_range(x, y, range)
	if not range then
		range = self:padding_box_range()
	end

	return x >= range.left and x < range.right and y >= range.top and y < range.bottom
end

return RenderBox
