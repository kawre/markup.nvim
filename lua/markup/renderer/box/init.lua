local BoxProps = require("markup.renderer.box.props")

-- -@class markup.box.layout.Input
-- -@field preferred_width number? if set, the layout will try to fit the box into this width
-- -@field preferred_height number? if set, the layout will try to fit the box into this height
-- -@field resume boolean? if true, the layout will not reset the box's position

---@class markup.box.layout.Input
---@field available_width number
---@field min_width integer? Minimum width required (optional)
---@field min_height integer? Minimum height required (optional)
---@field resume boolean? If true, don't reset box position

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
---@field props markup.node.props
---@field computed markup.box.props
---@field extmarks table
---@field text_content string? only for text nodes
---@field line? markup.renderer.line
local M = Markup.object()

---@param node markup.node
---@param impl? markup.box.impl can be set later
function M:new(node, impl)
	self.impl = impl
	self.node = node
	node.box = self
	self.dirty = true
	self.buf = {}
	self.props = self.node.props
	self.computed = BoxProps(self)
	self.extmarks = {}
	self.__id = Markup.util.gen_id()
end

function M:build()
	for _, child in ipairs(self.node.child_nodes) do
		local new_render_node = self:attach(child)
		new_render_node:build()
	end
end

---@param input markup.box.layout.Input
function M:reflow(input)
	for _, child in ipairs(self.node.child_nodes) do
		if not child.box then
			self:attach(child)
			child.box:build()
		end

		child.box:reflow(input)
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
	local reverse = self.computed.reverse

	return function()
		i = i + 1
		if i > n then
			return nil
		end
		return i, children[reverse and (n + 1 - i) or i].box
	end
end

function M:reset_layout()
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
end

---@param input markup.box.layout.Input
function M:layout(input)
	assert(self.impl, "Layout strategy is not set")

	if not input.resume and not self.dirty then
		return
	end

	-- local old_mbox = self:get_box_size("margin")
	if not input.resume then
		self:reset_layout()
	end

	self.x = 0
	self.y = 0
	self.impl.layout(self, input)
	self.x = nil
	self.y = nil

	Markup.assert.bug(self.width, "Width must be resolved by layout strategy.")
	Markup.assert.bug(self.height, "Height must be resolved by layout strategy.")
	Markup.assert.bug(self.content_width, "Content width must be resolved by layout strategy.")
	Markup.assert.bug(self.content_height, "Content height must be resolved by layout strategy.")

	-- local mbox = self:get_box_size("margin")
	-- if self.parent and (old_mbox.width ~= mbox.width or old_mbox.height ~= mbox.height) then
	-- 	self.parent.dirty = true
	-- end

	self.dirty = false
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
	local computed = self.computed

	if not kind then
		return { width = self.width, height = self.height }
	end

	if kind == "content" then
		return { width = self.content_width, height = self.content_height }
	elseif kind == "padding" then
		local c = self:get_box_size("content")

		if not c or not c.width or not c.height then
			return {}
		end

		return {
			width = c.width + computed.padding_left + computed.padding_right,
			height = c.height + computed.padding_top + computed.padding_bottom,
		}
	elseif kind == "margin" then
		local p = self:get_box_size("padding")

		if not p or not p.width or not p.height then
			return {}
		end

		return {
			width = p.width + computed.margin_left + computed.margin_right,
			height = p.height + computed.margin_top + computed.margin_bottom,
		}
	end
end

---@param size integer
---@param axis "width"|"height"
function M:clamp_size(size, axis)
	local computed = self.computed
	if computed.sizing ~= "inner" then
		return size
	end
	if axis == "width" then
		return size
			- (computed.padding_left + computed.padding_right)
			- (computed.margin_left + computed.margin_right)
	else
		return size
			- (computed.padding_top + computed.padding_bottom)
			- (computed.margin_top + computed.margin_bottom)
	end
end

---@param width integer
---@param clamp? boolean
function M:set_content_box_width(width, clamp)
	if clamp then
		width = self:clamp_size(width, "width")
	end
	self.content_width = math.max(self.width or 1, width)
end

---@param height integer
---@param clamp? boolean
function M:set_content_box_height(height, clamp)
	if self:is("inline") then
		height = 1
	elseif clamp then
		height = self:clamp_size(height, "height")
	end
	self.content_height = math.max(self.height or 1, height)
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

---(0,0) indexed
---@param renderer markup.renderer
---@param x integer
---@param y integer
function M:paint(renderer, x, y)
	local ns = renderer.ns
	local props = self.computed

	-- for _, extmark_id in ipairs(self.extmarks) do
	-- 	vim.api.nvim_buf_del_extmark(0, ns, extmark_id)
	-- end
	-- self.extmarks = {}

	if self:is("text") then
		-- only leaf nodes (text) can output text on the screen
		-- local word = tostring(self.node.text_content)
		renderer.lines[y + 1]:insert(self)
	else
		-- everything else only outputs style
		local pbox = self:get_box_size("padding")
		local pox = x + props.margin_left
		local poy = y + props.margin_top

		-- Markup.util.set_hl({
		-- 	[self.__id] = self.computed.style,
		-- }, { managed = true, prefix = "MarkupDynamic", force = true })

		for line = 0, pbox.height - 1 do
			renderer.lines[poy + line + 1]:highlight(pox, pox + pbox.width, self.props.style)
			-- local extmark_id = vim.api.nvim_buf_set_extmark(0, ns, poy + line, pox, {
			-- 	end_col = pox + pbox.width,
			-- 	hl_eol = true,
			-- 	hl_group = self.props.style,
			-- 	hl_mode = "combine",
			-- })
			-- table.insert(self.extmarks, extmark_id)
		end
	end

	-- self.need_paint = false
end

function M:debug_paint_margin(renderer, x, y)
	assert(Markup.config.debug, "Debug mode is not enabled.")
	local props = self.computed
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
	local props = self.computed
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
	local props = self.computed

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

---@return markup.box[]
function M:children()
	local res = {}
	for _, child in self:iter_children() do
		table.insert(res, child)
	end
	return res
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
	self:layout({ available_width = 0 })
	return self:get_box_size("margin")
end

---@param contraints markup.box.layout.Input
function M:compute_available_size(contraints)
	local props = self.computed
	local width = props.width
	local height = props.height

	if width == "auto" or width == "full" then
		width = contraints.available_width
	elseif width == "fit" then
		width = nil
	else ---@cast width number
		width = self:resolve_size(width, contraints.available_width)
	end

	if height == "auto" or height == "fit" then
		height = nil
	elseif height == "full" then
		height = contraints.available_height
	else ---@cast height number
		height = self:resolve_size(height, contraints.available_height)
	end

	return { available_width = width, available_height = height }
end

---@param size markup.box.props.unit
---@param ref number
---@param fallback? number
---@return number
function M:resolve_size(size, ref, fallback)
	if size == "auto" then
		return fallback or ref
	elseif size == "fit" then
		return 0
	elseif size == "full" then
		return ref
	end
	---@cast size number
	if size > 0 and size < 1 then
		return math.ceil(ref * size)
	else
		return size
	end
end

return M
