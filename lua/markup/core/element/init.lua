local markup = require("markup")
local log = require("markup.logger")

---@class markup.Element.props
---@field children markup.Element[]
---@field color string
---@field max_width_chars integer
---@field extmark any

---@class markup.Element : markup.Object
---@field _ markup.Element.props
local Element = markup.Object("MarkupElement")

---@param props markup.Element.constructor.props
function Element:init(props)
	if type(props) == "string" then
		props = { children = { markup.Text(props) } }
	end

	self._ = vim.tbl_deep_extend("force", {
		children = {},
		color = "Normal",
		max_width_chars = nil,
	}, props or {})
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
	local row_end, col_end = renderer:get_pos()

	local start = { row = row_start, col = col_start }
	local endd = { row = row_end, col = col_end }
	local box = { width = endd.col - start.col, height = endd.row - start.row }
	local lengths = {}
	for row = start.row, endd.row do
		lengths[row] = renderer:get_col(row) - start.col
	end

	renderer:set_state(self, {
		start = start,
		endd = endd,
		lengths = lengths,
		box = box,
		parent = parent,
	})

	self:after_draw(renderer)
	-- vim.wait(100)
end

---@param renderer markup.Renderer
function Element:draw(renderer)
	local content = self:content()
	for _, element in ipairs(content) do
		element:render(renderer)
	end
end

---@param renderer markup.Renderer
function Element:before_draw(renderer) end

---@param renderer markup.Renderer
function Element:after_draw(renderer) end

---@class markup.Element.constructor.props
---@field children markup.Element[]
---@field color? string
---@field max_width_chars? integer

---@alias markup.Element.constructor fun(props: string | markup.Element.constructor.props): markup.Element

---@type markup.Element.constructor
local MarkupElement = Element

return MarkupElement
