---@class markup.object
---@overload fun(): table
local M = setmetatable({}, {
	__call = function(t, name)
		return t.constructor(name)
	end,
})

---@private
function M.new() end

---@private
function M.constructor(name)
	local O = setmetatable({}, {
		__call = function(t, ...)
			local self = setmetatable({}, t)
			assert(t.new, "Object must have a 'new' method")
			t.new(self, ...)
			return self
		end,
		__name = name or "markup.object",
	})
	O.__index = O

	return O
end

return M
