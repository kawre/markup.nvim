local markup = require("markup")
local utils = require("markup.utils")
local log = require("markup.logger")

---@class markup.Element.props
---@field children markup.Element[]
---@field max_width_chars integer
---@field extmark any
---@field type "block"|"inline"
---@field style vim.api.keyset.highlight

---@class markup.Element : markup.Object
---@field _ markup.Element.props
local Element = markup.Object("MarkupElement")

---@param props markup.Element.constructor.props
function Element:init(props)
	self._ = self:normalize_props(props, {
		children = {},
		style = {},
		max_width_chars = nil,
		type = "inline",
	})
end

---@param props table
---@param defaults table
---@return markup.Element.props
function Element:normalize_props(props, defaults)
	local result = {}

	if type(props) == "string" then
		result.children = { markup.Text(props) }
	elseif getmetatable(props) then
		result.children = { props }
	else
		result = props
	end

	return vim.tbl_deep_extend("force", defaults or {}, result)
end

function Element:with_type(type, fn)
	local old_type = self._.type
	self._.type = type
	fn()
	-- self._.type = old_type
end

---@return markup.Element[]
function Element:content()
	return vim.tbl_filter(function(child)
		return #child:content() ~= 0
	end, self._.children)
end

---@param content string | markup.Text | markup.Element
---@param highlight? string
---
---@return markup.Element
function Element:append(content, highlight)
	local block = content

	if type(block) == "string" then
		block = markup.Text(block, highlight)
	end

	table.insert(self._.children, block)
end

function Element:inherit_style(parent)
	if parent then
		return vim.tbl_deep_extend("force", parent._.style, self._.style)
	else
		return vim.deepcopy(self._.style)
	end
end

---@param renderer markup.Renderer
---@param parent? markup.Element
function Element:render(renderer, parent)
	renderer:set_state(self, {
		style = self:inherit_style(parent),
		rendered_children = {},
		parent = parent,
	})

	self:before_draw(renderer)

	local row_initial, col_initial = renderer:get_pos()
	renderer:set_state(self, {
		initial = { row = row_initial, col = col_initial },
	})

	local row_start, col_start, row_end = renderer:draw_range(self)

	local lengths, max_len = {}, 0
	for row = row_start, row_end do
		local col_curr = renderer:get_col(row)
		lengths[row] = col_curr - col_start + 1
		max_len = math.max(max_len, lengths[row])
	end

	renderer:set_state(self, {
		row_start = row_start,
		row_end = row_end,
		col_start = col_start,
		col_end = max_len,
		lengths = lengths,
		box = { width = max_len, height = row_end - row_start },
	})

	self:after_draw(renderer)

	local row_final, col_final = renderer:get_pos()
	renderer:set_state(self, {
		final = { row = row_final, col = col_final },
	})

	renderer:append_rendered_child(parent, self)
end

---@param renderer markup.Renderer
function Element:draw(renderer)
	local content = self:content()
	for _, element in ipairs(content) do
		element:render(renderer, self)
	end
end

---@param renderer markup.Renderer
function Element:before_draw(renderer)
	local prev = renderer:get_prev(self)

	if prev and (prev:get_type() == "block" or self:get_type() == "block") then
		renderer:endl()
	end

	local parent_state = renderer:get_parent_state(self)
	if parent_state then
		local col = renderer:get_col()
		if parent_state.initial.col > col then
			renderer:pad(parent_state.initial.col - col)
		end
	end
end

---@param renderer markup.Renderer
function Element:after_draw(renderer) end

function Element:get_type()
	return self._.type
end

---@class markup.Element.constructor.props
---@field children markup.Element[]
---@field color? string
---@field max_width_chars? integer
---@field type? "block"|"inline"

---@alias markup.Element.constructor fun(props: string | markup.Element.constructor.props): markup.Element

---@type markup.Element.constructor
local MarkupElement = Element

return MarkupElement
