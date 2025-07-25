local BoxProps = require("markup.renderer.box.props")

---@class markup.box.constraints
---@field width? number
---@field height? number
---@field min_width? number
---@field min_height? number
---@field max_width? number
---@field max_height? number
---@field available_width? number
---@field available_height? number

---@class markup.box
---@field impl markup.box.impl
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
---@field min_content_width integer
---@field min_content_height integer
---@field max_content_width integer
---@field max_content_height integer
---@field fit_content_width integer
---@field fit_content_height integer
---@field intrinsic_width integer
---@field intrinsic_height integer
---@field props markup.box.props
---@field extmarks table
local M = Markup.object()

---@param node markup.node
---@param impl? markup.box.impl can be set later
function M:new(node, impl)
	self.impl = impl
	self.node = node
	node.box = self
	self.dirty = true
	self.buf = {}
	self.props = BoxProps(self)
	self.extmarks = {}
	self.__id = Markup.util.gen_id()
end

function M:build()
	for _, child in ipairs(self.node.child_nodes) do
		local new_render_node = self:attach(child)
		new_render_node:build()
	end
	self:flag_as_dirty()
end

function M:reflow()
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

function M:flag_as_dirty()
	if self.dirty then
		return
	end

	self.dirty = true
	if self.parent then
		self.parent:flag_as_dirty()
	end
end

---@param child markup.node
function M:attach(child)
	local child_box = Markup.factory.box(child)
	child_box.parent = self
	return child_box
end

function M:iter_children()
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

---@param constraints markup.box.constraints
function M:layout(constraints)
	assert(self.impl, "Layout strategy is not set")

	if self.dirty == false then
		return
	end

	-- local old_cwidth = self.content_width
	-- local old_cheight = self.content_height
	self.content_width = nil
	self.content_height = nil

	self.width = nil
	self.height = nil

	self.wx = nil
	self.wy = nil

	-- offset
	local parent = self.parent
	self.ox = parent and parent.x or 0
	self.oy = parent and parent.y or 0

	self.x = 0
	self.y = 0
	self.impl.layout(self, constraints)
	self.x = nil
	self.y = nil

	Markup.assert.bug(self.width, "Width must be resolved by layout strategy.")
	Markup.assert.bug(self.height, "Height must be resolved by layout strategy.")
	Markup.assert.bug(self.content_width, "Content width must be resolved by layout strategy.")
	Markup.assert.bug(self.content_height, "Content height must be resolved by layout strategy.")

	-- self.dirty = false
	-- if old_cwidth ~= self.content_width or old_cheight ~= self.content_height then
	-- 	self.parent:flag_as_dirty()
	-- end
end

function M:add_child(node)
	if not node or type(node) ~= "table" or not node.render or not node.layout then
		error("Invalid child node")
	end
	if not self.children then
		self.children = {}
	end
	table.insert(self.children, node)
	return self
end

function M:remove_child(node)
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

function M:name()
	return self.impl.__name
end

---@param layout_type markup.Render.LayoutType
function M:is(layout_type)
	return self.impl.__type[layout_type]
end

---@alias markup.box.kind "content" | "padding" | "margin"

---@param kind? markup.box.kind
function M:get_box_size(kind)
	local props = self.props
	if not kind then
		return { width = self.width, height = self.height }
	elseif kind == "content" then
		return { width = self.content_width, height = self.content_height }
	elseif kind == "padding" then
		local c = self:get_box_size("content")
		return {
			width = c.width + props.padding_left + props.padding_right,
			height = c.height + props.padding_top + props.padding_bottom,
		}
	elseif kind == "margin" then
		local p = self:get_box_size("padding")
		return {
			width = p.width + props.margin_left + props.margin_right,
			height = p.height + props.margin_top + props.margin_bottom,
		}
	end
end

---@param size { width?: integer, height?: integer }
function M:set_content_box_size(size)
	local out = self:clamp_content_size(size)
	self:set_content_box_size_raw(out)
end

---@param size { width?: integer, height?: integer }
function M:set_content_box_size_raw(size)
	self.content_width = size.width
	self.content_height = size.height
end

---@param size { width?: integer, height?: integer }
---@return { width?: integer, height?: integer }
function M:clamp_content_size(size)
	local props = self.props
	local out = {}

	if size.width then
		local width = size.width
		if props.sizing == "inner" then
			width = width
				- (props.padding_left + props.padding_right)
				- (props.margin_left + props.margin_right)
		end
		out.width = math.max(self.width or 0, width)
	end

	if size.height then
		local height = size.height
		if self:is("inline") then
			out.height = 1
		else
			if props.sizing == "inner" then
				height = height
					- (props.padding_top + props.padding_bottom)
					- (props.margin_top + props.margin_bottom)
			end
			out.height = math.max(self.height or 0, height)
		end
	end

	return out
end

function M:destroy()
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
function M:paint(renderer, x, y)
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
		local pbox = self:get_box_size("padding")
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

function M:debug_paint_margin(renderer, x, y)
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

function M:debug_paint_padding(renderer, x, y)
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

---@param kind markup.box.kind
function M:get_box_range(kind)
	local props = self.props

	if not self.wx or not self.wy then
		return
	end

	-- if not kind then
	-- 	return {
	-- 		top = self.wy,
	-- 		bottom = self.wy + self.height - 1,
	-- 		left = self.wx,
	-- 		right = self.wx + self.width - 1,
	-- 	}
	if kind == "margin" then
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
			bottom = math.max(0, bottom - 1),
			left = left,
			right = right,
		}
	elseif kind == "padding" then
		local top = self.wy + props.margin_top
		local bottom = props.padding_top + top + self.content_height + props.padding_bottom
		local left = self.wx + props.margin_left
		local right = left + props.padding_left + self.content_width + props.padding_right

		return {
			top = top,
			bottom = math.max(0, bottom - 1),
			left = left,
			right = right,
		}
	elseif kind == "content" then
		local top = self.wy + props.margin_top + props.padding_top
		local bottom = top + self.content_height
		local left = self.wx + props.margin_left + props.padding_left
		local right = left + self.content_width

		return {
			top = top,
			bottom = bottom,
			left = left,
			right = right,
		}
	end
end

function M:children()
	return vim.tbl_map(function(n)
		return n.box
	end, self.node.child_nodes)
end

function M:children_len()
	return #self.node.child_nodes
end

---(0,0) indexed
---@param x any
---@param y any
---@param range any
---@return boolean
function M:in_range(x, y, range)
	if not range then
		range = self:get_box_range("padding")
	end

	return x >= range.left and x <= range.right and y >= range.top and y <= range.bottom
end

function M:distance_to(x, y)
	if not self.wx or not self.wy then
		return math.huge
	end

	local range = self:get_box_range("margin")
	assert(range, "Box range is not defined.")
	local dx = math.max(range.left - x, 0, x - range.right)
	local dy = math.max(range.top - y, 0, y - range.bottom)

	return math.sqrt(dx * dx + dy * dy)
end

---@alias markup.size {width: integer, height: integer}

---@return markup.size
function M:compute_intrinsic_size()
	return self.impl.compute_intrinsic_size(self)
end

---@param size number
---@param ref number
function M:resolve_size(size, ref)
	if size < 1 then
		return math.floor(ref * size)
	else
		return math.floor(size)
	end
end

return M
