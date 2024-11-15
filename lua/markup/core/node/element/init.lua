local markup = require("markup")
local u = require("markup.utils") ---@diagnostic disable-line: unused-local
local log = require("markup.logger") ---@diagnostic disable-line: unused-local

---@class markup.Element.props : markup.Node.props
---@field row integer
---@field lines markup.Renderer.Line[]
---@field style markup.Element.style
---@field children markup.Node[]
---@field display markup.Element.display
---@field padding markup.Element.padding
---@field margin markup.Element.margin
---@field align markup.Box.align
---@field spacing markup.Box.spacing
---@field vertical boolean
---@field reverse boolean
---@field final {row_start: integer, row_end: integer, col_start: integer, col_end: integer}

---@class markup.Element : markup.Node
---@field protected _ markup.Element.props
---@field protected super markup.Node
---@field display markup.Element.display
---@field padding markup.Element.padding
---@field margin markup.Element.margin
---@field align markup.Box.align
---@field spacing markup.Box.spacing
---@field vertical boolean
---@field reverse boolean
---@field child_nodes markup.Node[]
---@field children markup.Element[]
---@field first_child markup.Node
---@field first_element_child markup.Element
---@field last_child markup.Node
---@field last_element_child markup.Element
---@field prev_element_sibling markup.Element
---@field next_element_sibling markup.Element
local Element = markup.Node:extend("markup.element") ---@diagnostic disable-line: undefined-field

---------------------------------
---- Constructor
---------------------------------

Element.static._default_props = {
	type = "element",
	row = 0,
	lines = {},
	children = {},
	style = {},
	display = "inline",
	padding = 0,
	margin = 0,
	align = "start",
	spacing = 0,
	vertical = true,
	reverse = false,
	size = {
		width = false,
		height = false,
	},
	final = {},
}

---@param props any
function Element:_extend_default_props(props)
	local defaults = self._default_props or {}
	self._default_props = vim.tbl_deep_extend("force", props, defaults)
end

---@param props markup.Element.constructor.props
---@param style? markup.Element.style
function Element:init(props, style)
	props = self:_normalize_props(props, style)
	Element.super.init(self, props)
	self._default_props = nil
end

---------------------------------
---- Methods (Private)
---------------------------------

---@protected
---@param n? integer
---@return markup.Element
function Element:_newl(n)
	self:_inc_row(n or 1)
	self:_fill_lines()
	return self
end

---@protected
---@param row_at? integer (0-indexed)
---@return markup.Renderer.Line
function Element:_line(row_at)
	row_at = row_at or self:_row()
	self:_fill_lines(row_at)
	return self._.lines[row_at]
end

---@protected
---@param row integer (0-indexed)
function Element:_set_row(row)
	self._.row = row
	return self._.row
end

---@protected
---@return integer (0-indexed)
function Element:_row()
	return self._.row
end

---@protected
---@param row_at? integer (0-indexed)
function Element:_fill_lines(row_at)
	local lines = self._.lines
	for i = #lines, row_at or self:_row() do
		if not lines[i] then
			lines[i] = markup.RendererLine()
		end
	end
end

---@protected
---@param n integer
function Element:_inc_row(n)
	return self:_set_row(self:_row() + n)
end

---@protected
---@param content string|markup.Text|markup.Renderer.Line
---@param row_at? integer (0-indexed)
---@return markup.Element
function Element:_append(content, row_at)
	self:_line(row_at):append(content)
	return self
end

---@protected
---@param content string|markup.Text|markup.Renderer.Line
---@param row_at? integer (0-indexed)
---@return markup.Element
function Element:_prepend(content, row_at)
	self:_line(row_at):prepend(content)
	return self
end

---@protected
---@param element markup.Element
function Element:_inherit_style(element)
	if not element then
		return self._.style
	else
		return vim.tbl_deep_extend("force", element.style, self._.style)
	end
end

---@protected
---@param parent markup.Element
function Element:_inherit_display(parent)
	if parent and parent:is_box() then
		return parent.vertical and "block" or "inline-block"
	else
		return self._.display
	end
end

---@param child markup.Node
function Element:_index_of(child)
	return u.index_of(self.child_nodes, child)
end

---@param child markup.Element
function Element:_index_of_element(child)
	return u.index_of(self.children, child)
end

function Element:_insert_line(row, content)
	local line = markup.RendererLine()

	if content then
		line:append(content)
	end

	if not row then
		table.insert(self._.lines, line)
	else
		table.insert(self._.lines, row, line)
	end
end

function Element:_non_zero_spacing()
	return self.margin.top > 0
		or self.margin.right > 0
		or self.margin.bottom > 0
		or self.margin.left > 0
		or self.padding.top > 0
		or self.padding.right > 0
		or self.padding.bottom > 0
		or self.padding.left > 0
end

function Element:_apply_spacing()
	if not self:_non_zero_spacing() then
		return
	end

	local lines = self:computed_lines()
	local width = self:width()
	local mar, pad = self.margin, self.padding

	-- Apply vertical spacing
	if self:is_block_kind() then
		for _ = 1, self.padding.top do
			self:_insert_line(0, markup.Pad(width, self))
		end
		for _ = 1, self.margin.top do
			self:_insert_line(0, markup.Pad(width, self.parent))
		end
		for _ = 1, self.padding.bottom do
			self:_insert_line(nil, markup.Pad(width, self))
		end
		for _ = 1, self.margin.bottom do
			self:_insert_line(nil, markup.Pad(width, self.parent))
		end
	end

	-- Apply horizontal spacing
	for row, line in pairs(lines) do
		if row < mar.bottom or row > #lines - mar.top then
			line:prepend(markup.Pad(mar.left + pad.left, self.parent))
			line:append(markup.Pad(mar.right + pad.right, self.parent))
		else
			line:prepend(markup.Pad(pad.left, self))
			line:prepend(markup.Pad(mar.left, self.parent))
			line:append(markup.Pad(pad.right, self))
			line:append(markup.Pad(mar.right, self.parent))
		end
	end
end

---@protected
---@param renderer markup.Renderer
---@param parent markup.Element
function Element:_set_state(renderer, parent)
	Element.super._set_state(self, renderer, parent)

	self._.row = 0
	self._.lines = {}
	self.display = self._.display
	self.computed_display = self:_inherit_display(parent)
	self.style = self:_inherit_style(parent)
	self.child_nodes = u.shallow_copy(self._.children)
	self:_sync_children()

	self.margin = Element.static._normalize_spacing(self._.margin)
	self.padding = Element.static._normalize_spacing(self._.padding)

	self.align = self._.align
	self.spacing = self._.spacing
	self.vertical = self._.vertical
	self.reverse = self._.reverse
end

function Element:_sync_children()
	self.children = vim.tbl_filter(function(child)
		return child:is_element()
	end, self.child_nodes)

	self.last_child = self.child_nodes[#self.child_nodes]
	self.first_child = self.child_nodes[1]
	self.first_element_child = self.children[1]
	self.last_element_child = self.children[#self.children]

	if self.parent then
		local element_index = self.parent:_index_of_element(self)
		if element_index then
			self.prev_element_sibling = self.parent.children[element_index - 1]
			self.next_element_sibling = self.parent.children[element_index + 1]
		end
	end
end

function Element:_update_final_position(row, col_start, col_end)
	self._.final = {
		row_start = math.min(self._.final.row_start or row, row),
		row_end = math.max(self._.final.row_end or row, row),
		col_start = math.min(self._.final.col_start or col_start, col_start),
		col_end = math.max(self._.final.col_end or col_end, col_end),
	}
end

function Element.static._normalize_style(style)
	if type(style) == "string" then
		return { link = style }
	else
		return style
	end
end

---@param props any
function Element:_normalize_props(props, style)
	local result = {}

	if type(props) == "string" then
		result.children = { markup.Text(props) }
	elseif getmetatable(props) then
		result.children = { props }
	else
		result = props
		if not result.children then
			result = { children = result }
		end
		result.children = Element.static._normalize_content(result.children)
	end

	local defaults =
		vim.tbl_deep_extend("keep", self._default_props or {}, Element.static._default_props)

	if style then
		style = Element.static._normalize_style(style)
		defaults.style = vim.tbl_deep_extend("keep", style, defaults.style)
	end

	return vim.tbl_deep_extend("keep", result, defaults)
end

function Element.static._normalize_content(content)
	if type(content) == "string" then
		return { markup.Text(content) }
	elseif getmetatable(content) then
		return { content }
	end

	for i, child in ipairs(content) do
		if type(child) == "string" then
			content[i] = markup.Text(child)
		end
	end

	return content
end

function Element.static._normalize_spacing(spacing)
	local t = spacing

	if type(t) == "number" then
		return { top = t, right = t, bottom = t, left = t }
	elseif vim.islist(t) then
		if #t == 1 then
			return { top = t[1], right = t[1], bottom = t[1], left = t[1] }
		elseif #t == 2 then
			return { top = t[1], right = t[2], bottom = t[1], left = t[2] }
		elseif #t == 3 then
			return { top = t[1], right = t[2], bottom = t[3], left = t[2] }
		elseif #t == 4 then
			return { top = t[1], right = t[2], bottom = t[3], left = t[4] }
		end
	else
		return { top = t.top or 0, right = t.right or 0, bottom = t.bottom or 0, left = t.left or 0 }
	end
end

---------------------------------
---- Methods
---------------------------------

---@param child markup.Node
function Element:append_child(child)
	table.insert(self.child_nodes, child)
	return child
end

---@param other_node markup.Node
function Element:contains(other_node)
	return u.index_of(self.child_nodes, other_node) ~= nil
end

-- ---@param child markup.Node
-- ---@param reference markup.Node
-- function Element:insert_before(child, reference)
--     local index = u.index_of(self.child_nodes, node)
--     assert(index, "node not found")
--     table.insert(self.child_nodes, index, node)
--     return node
-- end

---@param child markup.Node
function Element:remove_child(child)
	local index = u.index_of(self.child_nodes, child)
	assert(index, "child not found")
	return table.remove(self.child_nodes, index)
end

function Element:replace_child(new_child, old_child)
	local index = u.index_of(self.child_nodes, old_child)
	assert(index, "child not found")
	self.child_nodes[index] = new_child
	return old_child
end

function Element:render()
	for _, child in ipairs(self.child_nodes) do
		child:render_node(self.owner, self)
	end
end

local display_map = {
	["block"] = "Block",
	["inline"] = "Inline",
	["inline-block"] = "Inline",
	["flex"] = "Flex",
	["grid"] = "Grid",
}

function Element:after_render()
	markup[display_map[self.display]].display_handler(self)
end

function Element:display_handler()
	error("[Element:display_handler] Method not implemented")
end

---@return integer
function Element:width()
	if self._.size.width then
		return self._.size.width
	end

	local max_len = 0
	for _, line in pairs(self._.lines) do
		max_len = math.max(max_len, line:width())
	end
	return max_len
end

---@return integer
function Element:height()
	if self._.size.height then
		return self._.size.height
	end

	local h = 0
	for _ in pairs(self._.lines) do
		h = h + 1
	end
	return h
end

---@return integer, integer
function Element:size()
	return self:width(), self:height()
end

---@return integer, integer
function Element:box_size()
	if self:is_br() and not self:is_box_item() then
		return self.owner:win_get_width(), self.owner:win_get_height()
	else
		return self:size()
	end
end

function Element:max_size()
	local children = self.children

	local max_width, max_height = 0, 0
	for _, child in ipairs(children) do
		max_height = math.max(max_height, child:height())
		max_width = math.max(max_width, child:width())
	end

	return max_width, max_height
end

function Element:computed_style()
	return self.style
end

function Element:computed_lines()
	return self._.lines
end

---------------------------------
---- Initializer
---------------------------------

---@class markup.Element.constructor.props : markup.Node.constructor.props
---@field children? markup.Element.content element children
---@field style? markup.Element.style element style
---@field display? markup.Element.display element display
---@field margin? markup.Element.margin element margin
---@field padding? markup.Element.padding element padding
---@field align? markup.Box.align box align
---@field spacing? markup.Box.spacing box spacing
---@field vertical? boolean box vertical
---@field reverse? boolean box reverse

---@alias markup.Element.style.props string|markup.Element.style

---@alias markup.Element.constructor fun(props?: markup.Element.content|markup.Window.constructor.props, style?: markup.Element.style.props): markup.Element

---@type markup.Element.constructor
local MarkupElement = Element ---@diagnostic disable-line: assign-type-mismatch

return MarkupElement
