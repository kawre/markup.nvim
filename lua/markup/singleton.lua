---@class markup.singleton

return function()
	local M = setmetatable({}, {
		__call = function(t, ...)
			return t.call(...)
		end,
	})
	return M
end
