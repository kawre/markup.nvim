local markup = require("markup")
local log = require("markup.logger")

---@class markup.Block.props : markup.Element.props
---@field children markup.Block
---@field color string
---@field max_width_chars? integer

---@class markup.Block : markup.Element
---@field _ markup.Block.props
local Block = markup.Element:extend("MarkupBlock")

-- function Block:before_draw(renderer)
-- 	if renderer:get_col() ~= 0 then
-- 		renderer:endl()
-- 	end
-- end
--
-- function Block:after_draw(renderer)
-- 	renderer:endl()
-- end

---@class markup.Block.constructor.props : markup.Element.constructor.props

---@alias markup.Block.constructor fun(props?: markup.Block.constructor.props): markup.Block

---@type markup.Block.constructor
local MarkupBlock = Block

return MarkupBlock
