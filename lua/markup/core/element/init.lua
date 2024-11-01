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
	self:before_draw(renderer)

	local row_start, col_start = renderer:get_pos()
	self:draw(renderer)
	local row_end = renderer:get_pos()

	local lengths, max_len = {}, 0
	for row = row_start, row_end do
		lengths[row] = renderer:get_col(row) - col_start
		max_len = math.max(max_len, lengths[row])
	end

	local start = { row = row_start, col = col_start }
	local endd = { row = row_end, col = max_len }
	local box = { width = max_len, height = endd.row - start.row }

	renderer:set_state(self, {
		start = start,
		endd = endd,
		lengths = lengths,
		box = box,
		parent = parent,
	})

	self:after_draw(renderer)
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
	log.debug({
		class_name = self.class.name,
		type = self._.type,
	})
	if self._.type == "block" and renderer:get_col() ~= 0 then
		renderer:endl()
	end
end

---@param renderer markup.Renderer
function Element:after_draw(renderer)
	log.debug({
		class_name = self.class.name,
		type = self._.type,
	})
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
