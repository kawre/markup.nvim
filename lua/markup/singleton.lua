---@class markup.singleton

return function()
	local M = setmetatable({}, {
		__call = function(t, ...)
			assert(t.call, "To use singleton, you must first set the call function.")
			return t.call(...)
		end,
	})
	return M
end
