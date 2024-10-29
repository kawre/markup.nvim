local markup = require("markup")

---@class markup.Block.props : markup.Element.props
---@field children markup.Block
---@field color string
---@field max_width_chars? integer

---@class markup.Block : markup.Element
---@field _ markup.Block.props
local Block = markup.Element:extend("MarkupBlock")

---@param renderer markup.Renderer
function Block:draw(renderer)
	local row, col = renderer._.row, renderer._.col

	if row ~= 0 or col ~= 0 then
		renderer:endl()
	end
	Block.super.draw(self, renderer)
	renderer:endl()
end

-- function Block:init(props)
-- 	self._ = vim.tbl_deep_extend("force", {
-- 		children = {},
-- 		color = "Normal",
-- 		max_width_chars = nil,
-- 	}, props)
-- end

---@class markup.Block.constructor.props

---@alias markup.Block.constructor fun(props?: markup.Block.constructor.props): markup.Block

---@type markup.Block.constructor
local MarkupBlock = Block

return MarkupBlock
