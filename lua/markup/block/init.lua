local Element = require("markup.element")

---@class markup.Block.props : markup.Element.props
---@field children markup.Block
---@field color string
---@field max_width_chars? integer

---@class markup.Block : markup.Element
---@field _ markup.Block.props
local Block = Element:extend("MarkupBlock")

---@param window markup.Window
function Block:draw(window)
	local bufnr, row = window._.bufnr, window._.row
	if vim.api.nvim_buf_get_lines(bufnr, row, -1, false)[1] ~= "" then
		window:endl()
	end
	Block.super.draw(self, window)
	window:endl()
end

-- function Block:init(props)
-- 	self._ = vim.tbl_deep_extend("force", {
-- 		children = {},
-- 		color = "Normal",
-- 		max_width_chars = nil,
-- 	}, props)
-- end

---@class markup.Block.constructor.props
---@field xd integer

---@alias markup.Block.constructor fun(props: markup.Block.constructor.props): markup.Block

---@type markup.Block.constructor
local MarkupBlock = Block

return MarkupBlock
