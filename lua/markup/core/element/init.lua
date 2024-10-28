local markup = require("markup")

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
		block = Text(block, highlight)
	end

	table.insert(self._.children, block)
end

---@param window markup.Window
function Element:draw(window)
	local content = self:content()

	for _, obj in ipairs(content) do
		obj:draw(window)
	end
end

---@class markup.Element.constructor.props
---@field children markup.Element[]
---@field color? string
---@field max_width_chars? integer

---@alias markup.Element.constructor fun(props: string | markup.Element.constructor.props): markup.Element

---@type markup.Element.constructor
local MarkupElement = Element

return MarkupElement
