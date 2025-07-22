---@class markup.singleton

return function()
	local M = setmetatable({}, {
		__call = function(t, ...)
			assert(t.new, "Singleton must have a 'new' method")
			return t.new(...)
		end,
	})
	return M
end
