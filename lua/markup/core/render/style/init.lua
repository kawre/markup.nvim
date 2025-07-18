local defaults = require("markup.core.render.style.defaults")

---@class markup.Render.Style
---@field margin_top integer
---@field margin_right integer
---@field margin_bottom integer
---@field margin_left integer
---@field padding_top integer
---@field padding_right integer
---@field padding_bottom integer
---@field padding_left integer
---@field width integer
---@field height integer
---@field spacing integer
---@field style integer
local BoxStyle = {}
BoxStyle.__index = BoxStyle

---@param box markup.Render.Node
function BoxStyle:new(box)
	return setmetatable({}, {
		__index = function(_, key)
			return defaults[box.node.tag_name][key]
		end,
	})
end

return BoxStyle
