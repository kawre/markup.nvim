local RenderNodeFactory = require("markup.core.factory.render-box")
local assertor = require("markup.assertor")
local BoxProps = require("markup.core.render.props")
local log = require("markup.logger") ---@diagnostic disable-line: unused-local
local u = require("markup.utils") ---@diagnostic disable-line: unused-local

---@class markup.Render.Box
---@field layout_strategy markup.Render.Layout
---@field children markup.Render.Box[]
---@field node markup.Node
---@field parent markup.Render.Box
---@field dirty boolean
---@field buf table
---@field x integer
---@field y integer
---@field ox integer offset x
---@field oy integer offset y
---@field width integer
---@field height integer
---@field content_width integer
---@field content_height integer
---@field available_width integer
---@field available_height integer
---@field props markup.Render.props
---@field extmarks table
local RenderBox = {}
RenderBox.__index = RenderBox

---@param node markup.Node
---@param layout_strategy markup.Render.Layout
function RenderBox:new(node, layout_strategy)
	self = setmetatable({}, RenderBox)

	self.layout_strategy = layout_strategy
	self.children = {}
	self.node = node
	node.render_box = self
	self.dirty = true
	self.buf = {}
	self.props = BoxProps:new(self)
	self.extmarks = {}
	self.__id = u.gen_id()

	return self
end

function RenderBox:build()
	for _, child in ipairs(self.node.child_nodes) do
		local new_render_node = self:attach(child)
		new_render_node:build()
	end
	-- self.dirty = false
end

function RenderBox:reflow()
	for _, child in ipairs(self.children) do
		child:reflow()
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

---@param child markup.Node
function RenderBox:attach(child)
	local render_node = RenderNodeFactory.create(child)

	table.insert(self.children, render_node)
	render_node.parent = self

	return render_node
end

function RenderBox:iter_children()
	local children = self.children
	local reverse = self.props.reverse
	local i = reverse and #children + 1 or 0

	return function()
		i = i + (reverse and -1 or 1)
		if i < 1 or i > #children then
			return nil
		end
		return i, children[i]
	end
end

---@param style markup.Render.Style
function RenderBox:layout(_style)
	assert(self.layout_strategy, "Layout strategy is not set")

	if self.dirty == false then
		return
	end

	-- offset
	self.ox = self.parent.x
	self.oy = self.parent.y

	self.x = 0
	self.y = 0
	self.layout_strategy.layout(self)
	self.x = nil
	self.y = nil

	assertor.bug(self.width, "Width must be resolved by layout strategy.")
	assertor.bug(self.height, "Height must be resolved by layout strategy.")
	assertor.bug(self.content_width, "Content width must be resolved by layout strategy.")
	assertor.bug(self.content_height, "Content height must be resolved by layout strategy.")

	self.dirty = false
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
function RenderBox:normalize_size(size, ref)
	if size > 0 then
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
		self.content_width = width
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
			self.content_height = height
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
end

---@param renderer markup.Renderer
---@param x integer
---@param y integer
function RenderBox:paint(renderer, x, y)
	local bufnr = renderer.bufnr
	local ns = renderer.ns
	local props = self.props

	if self:is("text") then
		-- only leaf nodes can output text on the screen
		local word = tostring(self.node.text_content)
		vim.api.nvim_buf_set_text(bufnr, y, x, y, x + #word, { word })
	else
		-- everything else can only output style
		local pbox = self:padding_box_size()
		local pox = x + props.margin_left
		local poy = y + props.margin_top

		for line = 0, pbox.height - 1 do
			vim.api.nvim_buf_set_extmark(bufnr, ns, poy + line, pox, {
				end_col = pox + pbox.width,
				-- hl_mode = "blend",
				hl_eol = true,
				hl_group = props.style.bg,
				hl_mode = "combine",
			})
		end
	end
end

return RenderBox
