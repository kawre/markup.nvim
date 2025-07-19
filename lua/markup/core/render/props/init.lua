local defaults = require("markup.core.render.props.defaults")
local log = require("markup.logger") ---@diagnostic disable-line: unused-local

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
---@field justify string
---@field align string
---@field vertical string
---@field sizing string
---@field reverse boolean
local BoxProps = {}
BoxProps.__index = BoxProps

---@param box markup.Render.Box
function BoxProps:new(box)
	return setmetatable({}, {
		__index = function(_, key)
			local props = box.node.props

			local tag = box.node.tag_name
			local tag_defaults = defaults[tag]
			local prop = props[key]

			if prop ~= nil then
				return prop
			elseif tag_defaults and tag_defaults[key] ~= nil then
				return tag_defaults[key]
			elseif defaults.default[key] ~= nil then
				return defaults.default[key]
			else
				error(string.format("Property `%s` not found for tag `%s`", key, tag))
			end
		end,
	})
end

return BoxProps
