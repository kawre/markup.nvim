local markup = require("markup")
local utils = require("markup.utils")
local log = require("markup.logger")

---@class markup.Element.props
---@field children markup.Element[]
---@field color string
---@field max_width_chars integer
---@field extmark any
---@field type "block"|"inline"

---@class markup.Element : markup.Object
---@field _ markup.Element.props
local Element = markup.Object("MarkupElement")

---@param props markup.Element.constructor.props
function Element:init(props)
	self._ = self:normalize_props(props, {
		children = {},
		color = "Normal",
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
	self._.type = old_type
end

---@return markup.Element[]
function Element:content()
	return self._.children
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

---@param renderer markup.Renderer
---@param parent? markup.Element
function Element:render(renderer, parent)
	local row_initial, col_initial = renderer:get_pos()
	renderer:set_state(self, {
		initial = { row = row_initial, col = col_initial },
		parent = parent,
	})

	self:before_draw(renderer)

	local row_start, col_start = renderer:get_pos()
	self:draw(renderer)
	local row_end = renderer:get_pos()

	local lengths, max_len = {}, 0
	for row = row_start, row_end do
		local col = renderer:get_col(row)
		if col < col_start then
			renderer:pad(col_start, row)
		end

		lengths[row] = col - col_start
		max_len = math.max(max_len, lengths[row])
	end

	renderer:set_state(self, {
		row_start = row_start,
		row_end = row_end,
		col_start = col_start,
		cole_end = max_len,
		lengths = lengths,
		box = { width = max_len, height = row_end - row_start },
	})

	self:after_draw(renderer)

	local row_final, col_final = renderer:get_pos()
	renderer:set_state(self, {
		final = { row = row_final, col = col_final },
	})
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
	local state = renderer:get_state(self)

	local col = renderer:get_col()
	if self._.type == "block" and col ~= state.initial.col then
		renderer:endl()
	end
end

---@param renderer markup.Renderer
function Element:after_draw(renderer)
	if self._.type == "block" then
		renderer:endl()
	end
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
