local markup = require("markup")

local HorizontalFlex = markup.Flex:extend("markup.flex.horizontal") ---@diagnostic disable-line: undefined-field

function HorizontalFlex:init(...)
	self:_extend_default_props({
		vertical = false,
	})
	HorizontalFlex.super.init(self, ...)
end

return HorizontalFlex
