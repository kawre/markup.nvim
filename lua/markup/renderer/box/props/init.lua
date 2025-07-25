local defaults = require("markup.renderer.box.props.defaults")

---@alias markup.box.props.size "auto" | "fit" | "full" | number

---@class markup.box.props
---@field margin_top integer
---@field margin_right integer
---@field margin_bottom integer
---@field margin_left integer
---@field padding_top integer
---@field padding_right integer
---@field padding_bottom integer
---@field padding_left integer
---@field width markup.box.props.size
---@field height markup.box.props.size
---@field min_width markup.box.props.size
---@field min_height markup.box.props.size
---@field max_width? markup.box.props.size
---@field max_height? markup.box.props.size
---@field spacing integer
---@field justify string
---@field align string
---@field vertical boolean
---@field sizing string
---@field reverse boolean
---@field style markup.Element.style

local M = Markup.singleton()

---@param box markup.box
function M.call(box)
	return setmetatable({}, {
		__index = function(_, key)
			local function resolve()
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
			end

			-- local resolved = resolve()
			-- return M[key] and M[key](resolved, box) or resolved
			return resolve()
		end,
	})
end

function M:get_width()
	return 0
end

function M.get_intrinsic_size()
	return 0
end

return M
