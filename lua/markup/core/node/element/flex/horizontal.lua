local markup = require("markup.core")

---@class markup.Flex.Horizontal : markup.Flex
local HorizontalFlex = markup.Flex:extend("markup.flex.horizontal") ---@diagnostic disable-line: undefined-field

function HorizontalFlex:init(...)
	self:extend_default_props({
		vertical = false,
	})
	HorizontalFlex.super.init(self, ...)
end

---@type markup.Flex.constructor
return HorizontalFlex
