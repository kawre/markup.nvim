local defaults = require("markup.core.render.props.defaults")

---@class markup.Render.props
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
local BoxProps = {}
BoxProps.__index = BoxProps

---@param box markup.Render.Node
function BoxProps:new(box)
	return setmetatable({}, {
		__index = function(_, key)
			local props = box.node.props
			local tag = box.node.tag_name

			return props[key]
				or (defaults[tag] and defaults[tag][key])
				or defaults.default[key]
				or error(string.format("Property '%s' not found for tag '%s'", key, tag))
		end,
	})
end

return BoxProps
