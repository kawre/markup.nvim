---@class markup.hooks
---@field window markup.hooks.window
---@field context markup.hooks.context
---@field variable markup.hooks.variable
---@field effect markup.hooks.effect
---@field use markup.hooks.use
local M = setmetatable({}, {
	__index = function(t, k)
		t[k] = require("markup.hooks." .. k)
		return rawget(t, k)
	end,
})

return M
