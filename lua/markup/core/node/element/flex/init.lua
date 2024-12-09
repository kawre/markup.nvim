local markup = require("markup.core")

---@class markup.Flex : markup.Block
---@field protected super markup.Block
local Flex = markup.Block:extend("markup.flex")

function Flex:init(...)
	self:extend_default_props({
		display = "flex",
	})
	Flex.super.init(self, ...)
end

---@alias markup.Flex.constructor
---| markup.Block.constructor

---@type markup.Flex.constructor
return Flex
