---@class markup.hooks
---@field context markup.hooks.context
---@field variable markup.hooks.variable
---@field effect markup.hooks.effect
---@field store markup.hooks.store
---@field use markup.hooks.use
---@field window markup.hooks.window
local M = setmetatable({}, {
	__index = function(t, k)
		t[k] = require("markup.reconciler.hooks." .. k)
		return rawget(t, k)
	end,
})

return M
