---@class markup.object
---@field private new function
return function(name)
	local M = setmetatable({}, {
		__call = function(t, ...)
			local self = setmetatable({}, t)
			assert(t.new, "Object must have a 'new' method")
			t.new(self, ...)
			return self
		end,
		__name = name or "markup.object",
	})
	M.__index = M
	return M
end
