local markup = require("markup")

---@alias markup.Box.align "start"|"center"|"end"

---@class markup.Box.props : markup.Element.props
---@field align markup.Box.align
---@field spacing integer

---@class markup.Box : markup.Element
---@field _ markup.Box.props
-- local Box = Element:extend("MarkupBox")
local Box = markup.Object("MarkupBox")

---@param props markup.Box.constructor.props
function Box:init(props)
	self._ = vim.tbl_deep_extend("force", {
		align = "start",
		children = {},
	}, props)

	-- Box.super.init(self, props)
end

function Box:content()
	local children = {}
	local block = markup.Block()

	-- for _, elem in ipairs(self._.children) do
	-- 	if markup.Object.is_instance(elem, markup.Block) then
	-- 		table.insert(lines, vim.deepcopy(block))
	-- 		block._.children = {}
	-- 	end
	-- 	block:append(elem)
	-- end

	return self._.children
end

---@param window markup.Window
function Box:draw(window)
	local content = self:content()

	for _, obj in ipairs(content) do
		obj:draw(window)
	end
end

---@class markup.Box.constructor.props
---@field children markup.Element[]
---@field color? string
---@field align? markup.Box.align

---@alias markup.Box.constructor fun(props: markup.Element | markup.Box.constructor.props): markup.Box

---@type markup.Box.constructor
local MarkupBox = Box

return MarkupBox
