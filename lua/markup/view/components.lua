--- Small elements built from the primitives.

---@class markup.view.components
local M = {}

local PARTS = { "▏", "▎", "▍", "▌", "▋", "▊", "▉" }

--- The text of a bar, with eighths of a cell of precision.
---@param value number from 0 to 1
---@param width integer
---@return string
function M.bar(value, width)
	local eighths = math.floor(math.max(math.min(value, 1), 0) * width * 8 + 0.5)
	local full = math.floor(eighths / 8)
	return ("█"):rep(full) .. (PARTS[eighths % 8] or "")
end

---@class markup.view.progress
---@field value number|fun(): number from 0 to 1
---@field width integer
---@field style? string color of the bar
---@field track? string background behind it

--- A bar that shows fractions of a cell, so it can move smoothly.
---@param props markup.view.progress
function M.progress(props)
	local m = require("markup")
	local value = props.value

	return m.inline({
		style = props.track,
		width = props.width,
		m.inline(function()
			local current = type(value) == "function" and value() or value
			return M.bar(current, props.width)
		end, props.style),
	})
end

return M
