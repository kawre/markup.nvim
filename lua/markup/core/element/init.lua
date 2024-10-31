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
		block = Text(block, highlight)
	end

	table.insert(self._.children, block)
end

---@param renderer markup.Renderer
---@param parent? markup.Element
function Element:draw(renderer, parent)
	local content = self:content()

	for _, obj in ipairs(content) do
		obj:draw(renderer, self)
	end
end

function Element.find_parent(parent, class)
	if not parent then
		return false
	end

	if markup.Object.is_instance(parent, class) then
		return true
	else
		return Element.find_parent(parent.parent, class)
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
