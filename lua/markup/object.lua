---@alias markup.object
---| fun(type?: string): {}

---@type markup.object
return function(type)
	local M = setmetatable({}, {
		__call = function(t, ...)
			local self = setmetatable({}, t)
			assert(t.new, "Object must have a 'new' method")
			t.new(self, ...)
			return self
		end,
		__type = ("markup.%s"):format(type or "object"),
	})
	M.__index = M
	return M
end
