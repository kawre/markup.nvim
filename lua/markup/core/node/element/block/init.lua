local markup = require("markup.core")

---@class markup.Block : markup.Element
---@field protected super markup.Element
local Block = markup.Element:extend("markup.block")

function Block:init(...)
	self:extend_default_props({
		display = "block",
	})
	Block.super.init(self, ...)
end

---@alias markup.Block.constructor
---| markup.Element.constructor

---@type markup.Block.constructor
return Block
