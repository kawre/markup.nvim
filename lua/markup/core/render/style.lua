local BasicObject = require("markup.core.object.basic")

---@class markup.Render.Style
local Style = BasicObject()

function Style:init(style, parent_style)
	self._style = style
	self._parent_style = parent_style
end

function Style:align()
	return self._style.align or "left"
end

function Style:width()
	return self._style.align or "left"
end

return Style
