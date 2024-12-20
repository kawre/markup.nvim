local markup = require("markup.core")

---@class markup.Flex.Horizontal : markup.Flex
---@field protected super markup.Flex
local HFlex = markup.Flex:extend("markup.flex.horizontal")

function HFlex:init(...)
	self:extend_default_props({
		horizontal = true,
	})
	HFlex.super.init(self, ...)
end

---@alias markup.Flex.Horizontal.constructor
---| markup.Flex.constructor

---@type markup.Flex.Horizontal.constructor
return HFlex
